#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
TINYCORE_BRANCH="17.x"

# Use the current release aliases so the x86 and x86_64 builds remain aligned
# within the selected Tiny Core major branch.
X86_ISO_URL="http://tinycorelinux.net/${TINYCORE_BRANCH}/x86/release/Core-current.iso"
AMD64_ISO_URL="http://tinycorelinux.net/${TINYCORE_BRANCH}/x86_64/release/CorePure64-current.iso"

TINYCORE_EXTENSIONS=(
    nano
    pciutils
)

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIGINAL_DIR="${SCRIPT_ROOT}/original"
OUTPUT_DIR="${SCRIPT_ROOT}/output"
IPXE_DIR="${OUTPUT_DIR}/ipxe"
ISO_OUTPUT_DIR="${OUTPUT_DIR}/iso"
OVERLAY_DIR="${SCRIPT_ROOT}/overlay"
SCRATCH_DIR="${SCRIPT_ROOT}/tc-scratch"
REFRESH=false
CURRENT_MOUNT=""

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

log() {
    echo
    echo "==> $1"
}

cleanup_mount() {
    if [[ -n "${CURRENT_MOUNT}" ]] && mountpoint -q "${CURRENT_MOUNT}" 2>/dev/null; then
        sudo umount "${CURRENT_MOUNT}"
    fi
    CURRENT_MOUNT=""
}

cleanup_workspace() {
    cleanup_mount

    if [[ -e "${SCRATCH_DIR}" ]]; then
        chmod -R u+w "${SCRATCH_DIR}" 2>/dev/null || sudo chmod -R u+w "${SCRATCH_DIR}"
        rm -rf "${SCRATCH_DIR}"
    fi

    rm -rf "${OUTPUT_DIR}"
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

queue_extension() {
    local extension="$1"
    local existing dep_file dependency

    extension="${extension%.tcz}"
    [[ -n "${extension}" ]] || return 0

    for existing in "${TCZ_QUEUE[@]:-}"; do
        [[ "${existing}" == "${extension}" ]] && return 0
    done

    TCZ_QUEUE+=("${extension}")
    dep_file="${ACTIVE_EXTENSION_DIR}/${extension}.tcz.dep"

    if wget -q -O "${dep_file}" "${ACTIVE_TCZ_URL}/${extension}.tcz.dep"; then
        while IFS= read -r dependency || [[ -n "${dependency}" ]]; do
            dependency="${dependency//$'\r'/}"
            [[ -n "${dependency}" ]] && queue_extension "${dependency}"
        done < "${dep_file}"
    else
        rm -f "${dep_file}"
    fi
}

prepare_original() {
    local arch="$1"
    local iso_url="$2"
    local kernel_name="$3"
    local initrd_name="$4"

    local arch_original="${ORIGINAL_DIR}/${arch}"
    local iso_path="${arch_original}/base.iso"
    local kernel_path="${arch_original}/${kernel_name}"
    local initrd_path="${arch_original}/${initrd_name}"
    local mount_dir="${SCRATCH_DIR}/prepare-${arch}-mount"
    local kernel_source initrd_source

    mkdir -p "${arch_original}"

    if [[ ! -f "${iso_path}" ]]; then
        log "Downloading Tiny Core base ISO (${arch})"
        wget -O "${iso_path}" "${iso_url}"
    fi

    if [[ -f "${kernel_path}" && -f "${initrd_path}" ]]; then
        log "Original Tiny Core files already exist (${arch})"
        return
    fi

    log "Extracting original Tiny Core boot files (${arch})"

    mkdir -p "${mount_dir}"
    CURRENT_MOUNT="${mount_dir}"
    sudo mount -o loop,ro "${iso_path}" "${mount_dir}"

    kernel_source="$(find "${mount_dir}" -type f -name "${kernel_name}" | head -n1)"
    initrd_source="$(find "${mount_dir}" -type f -name "${initrd_name}" | head -n1)"

    [[ -n "${kernel_source}" ]] || { echo "ERROR: Could not locate ${kernel_name} in ${arch} ISO."; exit 1; }
    [[ -n "${initrd_source}" ]] || { echo "ERROR: Could not locate ${initrd_name} in ${arch} ISO."; exit 1; }

    cp "${kernel_source}" "${kernel_path}"
    cp "${initrd_source}" "${initrd_path}"

    cleanup_mount
}

build_arch() {
    local arch="$1"
    local repo_arch="$2"
    local kernel_name="$3"
    local initrd_name="$4"
    local tools_name="$5"
    local iso_name="$6"

    local arch_original="${ORIGINAL_DIR}/${arch}"
    local source_iso="${arch_original}/base.iso"
    local source_kernel="${arch_original}/${kernel_name}"
    local source_initrd="${arch_original}/${initrd_name}"

    local arch_scratch="${SCRATCH_DIR}/${arch}"
    local overlay_build="${arch_scratch}/overlay-build"
    local extension_dir="${arch_scratch}/extensions"
    local iso_mount="${arch_scratch}/iso-mount"
    local iso_tree="${arch_scratch}/iso-tree"

    local arch_ipxe="${IPXE_DIR}/${arch}"
    local output_iso="${ISO_OUTPUT_DIR}/${iso_name}"
    local output_kernel="${arch_ipxe}/${kernel_name}"
    local output_initrd="${arch_ipxe}/${initrd_name}"
    local output_tools="${arch_ipxe}/${tools_name}"

    local extension tcz_file extract_dir iso_kernel iso_initrd

    log "Building TinyCore Tools (${arch})"

    mkdir -p "${overlay_build}" "${extension_dir}" "${arch_ipxe}" "${ISO_OUTPUT_DIR}"

    cp -a "${OVERLAY_DIR}/." "${overlay_build}/"

    ACTIVE_TCZ_URL="http://tinycorelinux.net/${TINYCORE_BRANCH}/${repo_arch}/tcz"
    ACTIVE_EXTENSION_DIR="${extension_dir}"
    TCZ_QUEUE=()

    log "Resolving Tiny Core extensions (${arch})"

    for extension in "${TINYCORE_EXTENSIONS[@]}"; do
        queue_extension "${extension}"
    done

    echo "Extensions to include (${arch}):"
    printf '  - %s\n' "${TCZ_QUEUE[@]}"

    log "Downloading and extracting Tiny Core extensions (${arch})"

    for extension in "${TCZ_QUEUE[@]}"; do
        tcz_file="${extension_dir}/${extension}.tcz"
        extract_dir="${extension_dir}/${extension}"

        echo "  ${extension}.tcz"
        wget -q -O "${tcz_file}" "${ACTIVE_TCZ_URL}/${extension}.tcz"
        mkdir -p "${extract_dir}"
        unsquashfs -f -d "${extract_dir}" "${tcz_file}" >/dev/null
        cp -a "${extract_dir}/." "${overlay_build}/"
    done

    log "Preparing file permissions (${arch})"

    if [[ -d "${overlay_build}/usr/local/bin" ]]; then
        find "${overlay_build}/usr/local/bin" -type f -exec chmod 0755 {} +
    fi

    if [[ -f "${overlay_build}/home/tc/.profile" ]]; then
        chmod 0644 "${overlay_build}/home/tc/.profile"
    fi

    log "Building tools overlay (${arch})"

    cp "${source_kernel}" "${output_kernel}"
    cp "${source_initrd}" "${output_initrd}"

    (
        cd "${overlay_build}"
        find . -print0 | cpio --null -ov --format=newc | gzip -9 > "${output_tools}"
    )

    log "Building bootable ISO (${arch})"

    mkdir -p "${iso_mount}" "${iso_tree}"
    CURRENT_MOUNT="${iso_mount}"
    sudo mount -o loop,ro "${source_iso}" "${iso_mount}"
    cp -a "${iso_mount}/." "${iso_tree}/"
    cleanup_mount

    chmod -R u+w "${iso_tree}"

    iso_kernel="$(find "${iso_tree}" -type f -name "${kernel_name}" | head -n1)"
    iso_initrd="$(find "${iso_tree}" -type f -name "${initrd_name}" | head -n1)"

    [[ -n "${iso_kernel}" ]] || { echo "ERROR: Could not locate ${kernel_name} in ${arch} ISO tree."; exit 1; }
    [[ -n "${iso_initrd}" ]] || { echo "ERROR: Could not locate ${initrd_name} in ${arch} ISO tree."; exit 1; }

    cp "${output_kernel}" "${iso_kernel}"
    cat "${output_initrd}" "${output_tools}" > "${iso_initrd}"

    # Tiny Core's documented remastering layout uses ISOLINUX. Build through
    # xorriso's mkisofs-compatible mode instead of replaying the source ISO's
    # boot catalogue after modifying the tree. Keep xorriso output visible so
    # any future ISO error is immediately obvious rather than silently exiting.
    if [[ ! -f "${iso_tree}/boot/isolinux/isolinux.bin" ]]; then
        echo "ERROR: ${arch} ISO does not contain boot/isolinux/isolinux.bin"
        exit 1
    fi

    rm -f "${iso_tree}/boot/isolinux/boot.cat"

    xorriso -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -volid "TC_TOOLS_${arch^^}" \
        -eltorito-boot boot/isolinux/isolinux.bin \
        -eltorito-catalog boot/isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -output "${output_iso}" \
        "${iso_tree}"
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

    echo "Local tracked changes will be discarded; generated/cache directories are preserved."

    git -C "${SCRIPT_ROOT}" fetch origin main
    git -C "${SCRIPT_ROOT}" reset --hard origin/main
    exec bash "${SCRIPT_ROOT}/build.sh"
fi

# -----------------------------------------------------------------------------
# Prerequisites
# -----------------------------------------------------------------------------

REQUIRED_COMMANDS=(wget cpio gzip find mount mountpoint unsquashfs xorriso)
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
        sudo apt-get install -y wget cpio gzip findutils util-linux squashfs-tools xorriso
    elif command -v dnf >/dev/null 2>&1; then
        read -r -p "Install the required packages now? [Y/n]: " ANSWER
        ANSWER="${ANSWER:-Y}"
        [[ "${ANSWER}" =~ ^[Yy]$ ]] || exit 1
        sudo dnf install -y wget cpio gzip findutils util-linux squashfs-tools xorriso
    elif command -v yum >/dev/null 2>&1; then
        read -r -p "Install the required packages now? [Y/n]: " ANSWER
        ANSWER="${ANSWER:-Y}"
        [[ "${ANSWER}" =~ ^[Yy]$ ]] || exit 1
        sudo yum install -y wget cpio gzip findutils util-linux squashfs-tools xorriso
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
# Build
# -----------------------------------------------------------------------------

mkdir -p "${ORIGINAL_DIR}" "${OVERLAY_DIR}"

cleanup_workspace
mkdir -p "${SCRATCH_DIR}" "${OUTPUT_DIR}" "${IPXE_DIR}" "${ISO_OUTPUT_DIR}"

prepare_original "x86" "${X86_ISO_URL}" "vmlinuz" "core.gz"
prepare_original "amd64" "${AMD64_ISO_URL}" "vmlinuz64" "corepure64.gz"

build_arch "x86"   "x86"    "vmlinuz"   "core.gz"       "tools.gz"   "tinycore-tools-x86.iso"
build_arch "amd64" "x86_64" "vmlinuz64" "corepure64.gz" "tools64.gz" "tinycore-tools-amd64.iso"

# -----------------------------------------------------------------------------
# Finished
# -----------------------------------------------------------------------------

log "Build complete"

echo
echo "Output:"
find "${OUTPUT_DIR}" -maxdepth 3 -type f -printf '  %P  (%k KB)\n' | sort

echo
echo "Architecture-aware iPXE example:"
cat <<'EOF'

  :tiny-core
  echo Booting TinyCore Tools...

  iseq ${buildarch} x86_64 && goto tiny-core-amd64 ||
  iseq ${buildarch} x86    && goto tiny-core-x86   ||
  iseq ${buildarch} i386   && goto tiny-core-x86   ||
  goto failed

  :tiny-core-x86
  kernel ${base-url}livecd/tiny-core/x86/vmlinuz quiet loglevel=3 || goto failed
  initrd ${base-url}livecd/tiny-core/x86/core.gz                    || goto failed
  initrd ${base-url}livecd/tiny-core/x86/tools.gz                   || goto failed
  boot                                                               || goto failed

  :tiny-core-amd64
  kernel ${base-url}livecd/tiny-core/amd64/vmlinuz64 initrd=corepure64.gz initrd=tools64.gz quiet loglevel=3 || goto failed
  initrd ${base-url}livecd/tiny-core/amd64/corepure64.gz corepure64.gz || goto failed
  initrd ${base-url}livecd/tiny-core/amd64/tools64.gz tools64.gz       || goto failed
  boot                                                                  || goto failed
EOF

echo
echo "To sync from GitHub and rebuild:"
echo "  bash build.sh --refresh"
