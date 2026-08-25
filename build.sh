#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

TINYCORE_VERSION="17.1"
TINYCORE_BRANCH="17.x"
BASE_URL="http://tinycorelinux.net/${TINYCORE_BRANCH}/x86/release"
TCZ_BASE_URL="http://tinycorelinux.net/${TINYCORE_BRANCH}/x86/tcz"
ISO_NAME="Core-${TINYCORE_VERSION}.iso"

# Tiny Core extensions baked into tools.gz.
# Dependencies are resolved automatically from each .tcz.dep file.
TINYCORE_EXTENSIONS=(
    nano
    pciutils
)

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIGINAL_DIR="${SCRIPT_ROOT}/original"
PATCHED_DIR="${SCRIPT_ROOT}/patched"
OVERLAY_DIR="${SCRIPT_ROOT}/overlay"
SCRATCH_DIR="${SCRIPT_ROOT}/tc-scratch"
OVERLAY_BUILD_DIR="${SCRATCH_DIR}/overlay-build"
EXTENSION_DIR="${SCRATCH_DIR}/extensions"

ISO_PATH="${SCRATCH_DIR}/${ISO_NAME}"
ISO_MOUNT="${SCRATCH_DIR}/iso"
ORIGINAL_KERNEL="${ORIGINAL_DIR}/vmlinuz"
ORIGINAL_INITRD="${ORIGINAL_DIR}/core.gz"
PATCHED_KERNEL="${PATCHED_DIR}/vmlinuz"
PATCHED_INITRD="${PATCHED_DIR}/core.gz"
PATCHED_TOOLS="${PATCHED_DIR}/tools.gz"
REFRESH=false

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

log() { echo; echo "==> $1"; }

cleanup_mount() {
    if mountpoint -q "${ISO_MOUNT}" 2>/dev/null; then
        sudo umount "${ISO_MOUNT}"
    fi
}
trap cleanup_mount EXIT

usage() {
    cat <<EOF
Usage:
  bash build.sh
  bash build.sh --refresh

Options:
  --refresh   Force-sync tracked repository files to origin/main, then build.
              Generated/cache folders are preserved.
  -h, --help  Show this help.
EOF
}

# Download an extension and recursively discover its dependencies.
# The extension list is accumulated in the global TCZ_QUEUE array.
queue_extension() {
    local extension="$1"
    local existing

    extension="${extension%.tcz}"
    [[ -n "${extension}" ]] || return 0

    for existing in "${TCZ_QUEUE[@]:-}"; do
        [[ "${existing}" == "${extension}" ]] && return 0
    done

    TCZ_QUEUE+=("${extension}")

    local dep_file="${EXTENSION_DIR}/${extension}.tcz.dep"

    if wget -q -O "${dep_file}" "${TCZ_BASE_URL}/${extension}.tcz.dep"; then
        while IFS= read -r dependency || [[ -n "${dependency}" ]]; do
            dependency="${dependency//$'\r'/}"
            [[ -n "${dependency}" ]] || continue
            queue_extension "${dependency}"
        done < "${dep_file}"
    else
        rm -f "${dep_file}"
    fi
}

# -----------------------------------------------------------------------------
# Arguments / refresh
# -----------------------------------------------------------------------------

while (( $# > 0 )); do
    case "$1" in
        --refresh) REFRESH=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: Unknown option: $1"; echo; usage; exit 1 ;;
    esac
    shift
done

if [[ "${REFRESH}" == true ]]; then
    log "Refreshing repository from origin/main"
    command -v git >/dev/null 2>&1 || { echo "ERROR: git is required for --refresh."; exit 1; }
    git -C "${SCRIPT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: Not a Git working tree."; exit 1; }
    echo "Local tracked changes will be discarded."
    echo "Generated/cache directories are preserved."
    echo
    git -C "${SCRIPT_ROOT}" fetch origin main
    git -C "${SCRIPT_ROOT}" reset --hard origin/main
    exec bash "${SCRIPT_ROOT}/build.sh"
fi

# -----------------------------------------------------------------------------
# Prerequisites
# -----------------------------------------------------------------------------

REQUIRED_COMMANDS=(wget cpio gzip find mount mountpoint unsquashfs)
MISSING_COMMANDS=()

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    command -v "${cmd}" >/dev/null 2>&1 || MISSING_COMMANDS+=("${cmd}")
done

if (( ${#MISSING_COMMANDS[@]} > 0 )); then
    log "Missing build prerequisites"
    printf '  - %s\n' "${MISSING_COMMANDS[@]}"
    echo

    if command -v apt-get >/dev/null 2>&1; then
        read -r -p "Install/update the required packages now? [Y/n]: " ANSWER
        ANSWER="${ANSWER:-Y}"
        [[ "${ANSWER}" =~ ^[Yy]$ ]] || exit 1
        sudo apt-get update
        sudo apt-get install -y wget cpio gzip findutils util-linux squashfs-tools
    elif command -v dnf >/dev/null 2>&1; then
        read -r -p "Install the required packages now? [Y/n]: " ANSWER
        ANSWER="${ANSWER:-Y}"
        [[ "${ANSWER}" =~ ^[Yy]$ ]] || exit 1
        sudo dnf install -y wget cpio gzip findutils util-linux squashfs-tools
    elif command -v yum >/dev/null 2>&1; then
        read -r -p "Install the required packages now? [Y/n]: " ANSWER
        ANSWER="${ANSWER:-Y}"
        [[ "${ANSWER}" =~ ^[Yy]$ ]] || exit 1
        sudo yum install -y wget cpio gzip findutils util-linux squashfs-tools
    else
        echo "ERROR: No supported package manager detected."
        exit 1
    fi
fi

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    command -v "${cmd}" >/dev/null 2>&1 || { echo "ERROR: Required command '${cmd}' is unavailable."; exit 1; }
done

log "Prerequisite check passed"

# -----------------------------------------------------------------------------
# Original Tiny Core files
# -----------------------------------------------------------------------------

mkdir -p "${ORIGINAL_DIR}" "${PATCHED_DIR}" "${OVERLAY_DIR}" "${SCRATCH_DIR}"

if [[ -f "${ORIGINAL_KERNEL}" && -f "${ORIGINAL_INITRD}" ]]; then
    log "Original Tiny Core files already exist"
    echo "Using:"
    echo "  ${ORIGINAL_KERNEL}"
    echo "  ${ORIGINAL_INITRD}"
else
    log "Original Tiny Core files not found"
    rm -rf "${SCRATCH_DIR}"
    mkdir -p "${SCRATCH_DIR}" "${ISO_MOUNT}"

    log "Downloading Tiny Core Linux ${TINYCORE_VERSION}"
    wget -O "${ISO_PATH}" "${BASE_URL}/${ISO_NAME}"

    log "Mounting ISO"
    sudo mount -o loop,ro "${ISO_PATH}" "${ISO_MOUNT}"

    log "Locating vmlinuz and core.gz"
    KERNEL_SOURCE="$(find "${ISO_MOUNT}" -type f -name vmlinuz | head -n 1)"
    INITRD_SOURCE="$(find "${ISO_MOUNT}" -type f -name core.gz | head -n 1)"
    [[ -n "${KERNEL_SOURCE}" ]] || { echo "ERROR: Could not locate vmlinuz"; exit 1; }
    [[ -n "${INITRD_SOURCE}" ]] || { echo "ERROR: Could not locate core.gz"; exit 1; }

    log "Saving original Tiny Core files"
    cp "${KERNEL_SOURCE}" "${ORIGINAL_KERNEL}"
    cp "${INITRD_SOURCE}" "${ORIGINAL_INITRD}"
    cleanup_mount
    rm -f "${ISO_PATH}"
fi

# -----------------------------------------------------------------------------
# Workspace / base overlay
# -----------------------------------------------------------------------------

log "Preparing scratch workspace"
rm -rf "${SCRATCH_DIR}"
mkdir -p "${SCRATCH_DIR}" "${OVERLAY_BUILD_DIR}" "${EXTENSION_DIR}"

log "Clearing previous patched build"
rm -rf "${PATCHED_DIR}"
mkdir -p "${PATCHED_DIR}"

log "Copying original Tiny Core boot files"
cp "${ORIGINAL_KERNEL}" "${PATCHED_KERNEL}"
cp "${ORIGINAL_INITRD}" "${PATCHED_INITRD}"

log "Preparing project overlay"
if [[ -n "$(find "${OVERLAY_DIR}" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
    cp -a "${OVERLAY_DIR}/." "${OVERLAY_BUILD_DIR}/"
fi

# -----------------------------------------------------------------------------
# Tiny Core extensions
# -----------------------------------------------------------------------------

if (( ${#TINYCORE_EXTENSIONS[@]} > 0 )); then
    log "Resolving Tiny Core extensions"

    TCZ_QUEUE=()
    for extension in "${TINYCORE_EXTENSIONS[@]}"; do
        queue_extension "${extension}"
    done

    echo "Extensions to include:"
    printf '  - %s\n' "${TCZ_QUEUE[@]}"

    log "Downloading and extracting Tiny Core extensions"

    for extension in "${TCZ_QUEUE[@]}"; do
        TCZ_FILE="${EXTENSION_DIR}/${extension}.tcz"
        EXTRACT_DIR="${EXTENSION_DIR}/${extension}"

        echo "  ${extension}.tcz"
        wget -q -O "${TCZ_FILE}" "${TCZ_BASE_URL}/${extension}.tcz"
        mkdir -p "${EXTRACT_DIR}"
        unsquashfs -f -d "${EXTRACT_DIR}" "${TCZ_FILE}" >/dev/null
        cp -a "${EXTRACT_DIR}/." "${OVERLAY_BUILD_DIR}/"
    done
fi

# -----------------------------------------------------------------------------
# Permissions
# -----------------------------------------------------------------------------

log "Preparing file permissions"

if [[ -d "${OVERLAY_BUILD_DIR}/usr/local/bin" ]]; then
    find "${OVERLAY_BUILD_DIR}/usr/local/bin" -type f -exec chmod 0755 {} +
fi

if [[ -f "${OVERLAY_BUILD_DIR}/home/tc/.profile" ]]; then
    chmod 0644 "${OVERLAY_BUILD_DIR}/home/tc/.profile"
fi

# -----------------------------------------------------------------------------
# Build tools.gz
# -----------------------------------------------------------------------------

log "Building tools overlay"

if [[ -n "$(find "${OVERLAY_BUILD_DIR}" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
    cd "${OVERLAY_BUILD_DIR}"
    find . -print0 | cpio --null -ov --format=newc | gzip -9 > "${PATCHED_TOOLS}"
else
    cd "${SCRATCH_DIR}"
    printf '' | cpio -o --format=newc | gzip -9 > "${PATCHED_TOOLS}"
fi

cat > "${SCRATCH_DIR}/README.txt" <<EOF
Tiny Core temporary build workspace.

This directory is deleted and recreated every time build.sh runs.

original/ contains the untouched Tiny Core kernel and core.gz.
patched/ contains the final vmlinuz, core.gz and tools.gz.
overlay/ contains project customisations.
tc-scratch/ contains temporary build data and downloaded extensions.

Configured Tiny Core extensions are resolved with their dependencies,
downloaded, extracted and merged into tools.gz during each build.
EOF

# -----------------------------------------------------------------------------
# Finished
# -----------------------------------------------------------------------------

log "Build complete"
echo
echo "Original:"
ls -lh "${ORIGINAL_DIR}"
echo
echo "Patched:"
ls -lh "${PATCHED_DIR}"
echo
echo "iPXE files ready:"
echo "  ${PATCHED_KERNEL}"
echo "  ${PATCHED_INITRD}"
echo "  ${PATCHED_TOOLS}"
echo
echo "Bundled extensions:"
printf '  %s\n' "${TINYCORE_EXTENSIONS[@]}"
echo
echo "Example iPXE:"
echo "  kernel <url>/vmlinuz quiet loglevel=3"
echo "  initrd <url>/core.gz"
echo "  initrd <url>/tools.gz"
echo "  boot"
echo
echo "To sync from GitHub and rebuild:"
echo "  bash build.sh --refresh"
