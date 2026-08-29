#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
TINYCORE_BRANCH="17.x"

X86_ISO_URL="http://tinycorelinux.net/${TINYCORE_BRANCH}/x86/release/Core-current.iso"
AMD64_ISO_URL="http://tinycorelinux.net/${TINYCORE_BRANCH}/x86_64/release/CorePure64-current.iso"

TINYCORE_EXTENSIONS=(
    nano
    pciutils
    iperf3
    dmidecode
)

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIGINAL_DIR="${SCRIPT_ROOT}/original"
CACHE_DIR="${SCRIPT_ROOT}/cache"
OUTPUT_DIR="${SCRIPT_ROOT}/output"
IPXE_DIR="${OUTPUT_DIR}/ipxe"
ISO_OUTPUT_DIR="${OUTPUT_DIR}/iso"
OVERLAY_DIR="${SCRIPT_ROOT}/overlay"
SCRATCH_DIR="${SCRIPT_ROOT}/tc-scratch"
REFRESH=false
CURRENT_MOUNT=""

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
    local existing dep_file dependency cache_dep

    extension="${extension%.tcz}"
    [[ -n "${extension}" ]] || return 0

    for existing in "${TCZ_QUEUE[@]:-}"; do
        [[ "${existing}" == "${extension}" ]] && return 0
    done

    TCZ_QUEUE+=("${extension}")

    cache_dep="${ACTIVE_CACHE_DIR}/${extension}.tcz.dep"
    dep_file="${ACTIVE_EXTENSION_DIR}/${extension}.tcz.dep"

    if [[ -f "${cache_dep}" ]]; then
        cp "${cache_dep}" "${dep_file}"
    elif wget -q -O "${cache_dep}.tmp" "${ACTIVE_TCZ_URL}/${extension}.tcz.dep"; then
        mv "${cache_dep}.tmp" "${cache_dep}"
        cp "${cache_dep}" "${dep_file}"
    else
        rm -f "${cache_dep}.tmp"
        return 0
    fi

    while IFS= read -r dependency || [[ -n "${dependency}" ]]; do
        dependency="${dependency//$'\r'/}"
        [[ -n "${dependency}" ]] && queue_extension "${dependency}"
    done < "${dep_file}"
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

prepare_overlay_with_extensions() {
    local arch="$1"
    local repo_arch="$2"
    local overlay_build="$3"
    local extension_dir="$4"
    local extension tcz_file extract_dir cache_file

    mkdir -p "${overlay_build}" "${extension_dir}"
    cp -a "${OVERLAY_DIR}/." "${overlay_build}/"

    ACTIVE_TCZ_URL="http://tinycorelinux.net/${TINYCORE_BRANCH}/${repo_arch}/tcz"
    ACTIVE_EXTENSION_DIR="${extension_dir}"
    ACTIVE_CACHE_DIR="${CACHE_DIR}/${arch}/tcz"
    mkdir -p "${ACTIVE_CACHE_DIR}"
    TCZ_QUEUE=()

    log "Resolving Tiny Core extensions (${arch})"

    for extension in "${TINYCORE_EXTENSIONS[@]}"; do
        queue_extension "${extension}"
    done

    echo "Extensions to include (${arch}):"
    printf '  - %s\n' "${TCZ_QUEUE[@]}"

    log "Preparing Tiny Core extensions (${arch})"

    for extension in "${TCZ_QUEUE[@]}"; do
        cache_file="${ACTIVE_CACHE_DIR}/${extension}.tcz"
        tcz_file="${extension_dir}/${extension}.tcz"
        extract_dir="${extension_dir}/${extension}"

        if [[ -f "${cache_file}" ]]; then
            echo "  ${extension}.tcz (cached)"
        else
            echo "  ${extension}.tcz (downloading)"
            wget -q -O "${cache_file}.tmp" "${ACTIVE_TCZ_URL}/${extension}.tcz"
            mv "${cache_file}.tmp" "${cache_file}"
        fi

        cp "${cache_file}" "${tcz_file}"
        mkdir -p "${extract_dir}"
        unsquashfs -f -d "${extract_dir}" "${tcz_file}" >/dev/null
        cp -a "${extract_dir}/." "${overlay_build}/"
    done

    if [[ -d "${overlay_build}/usr/local/bin" ]]; then
        find "${overlay_build}/usr/local/bin" -type f -exec chmod 0755 {} +
    fi

    if [[ -f "${overlay_build}/home/tc/.profile" ]]; then
        chmod 0644 "${overlay_build}/home/tc/.profile"
    fi
}

build_iso_from_tree() {
    local arch="$1"
    local source_iso="$2"
    local kernel_name="$3"
    local initrd_name="$4"
    local replacement_kernel="$5"
    local replacement_initrd="$6"
    local output_iso="$7"
    local work_root="$8"

    local iso_mount="${work_root}/iso-mount"
    local iso_tree="${work_root}/iso-tree"
    local iso_kernel iso_initrd

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

    cp "${replacement_kernel}" "${iso_kernel}"
    cp "${replacement_initrd}" "${iso_initrd}"

    [[ -f "${iso_tree}/boot/isolinux/isolinux.bin" ]] || { echo "ERROR: ${arch} ISO does not contain boot/isolinux/isolinux.bin"; exit 1; }

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

build_x86() {
    local source_dir="${ORIGINAL_DIR}/x86"
    local work_root="${SCRATCH_DIR}/x86"
    local overlay_build="${work_root}/overlay-build"
    local extension_dir="${work_root}/extensions"
    local output_dir="${IPXE_DIR}/x86"
    local iso_initrd="${work_root}/iso-core.gz"

    log "Building TinyCore Tools (x86 - split initrd)"

    mkdir -p "${output_dir}"
    prepare_overlay_with_extensions "x86" "x86" "${overlay_build}" "${extension_dir}"

    cp "${source_dir}/vmlinuz" "${output_dir}/vmlinuz"
    cp "${source_dir}/core.gz" "${output_dir}/core.gz"

    log "Building tools overlay (x86)"
    (
        cd "${overlay_build}"
        find . -print0 | cpio --null -o --format=newc --quiet | gzip -9 > "${output_dir}/tools.gz"
    )

    cat "${output_dir}/core.gz" "${output_dir}/tools.gz" > "${iso_initrd}"

    build_iso_from_tree \
        "x86" "${source_dir}/base.iso" "vmlinuz" "core.gz" \
        "${output_dir}/vmlinuz" "${iso_initrd}" \
        "${ISO_OUTPUT_DIR}/tinycore-tools-x86.iso" "${work_root}"
}

build_amd64() {
    local source_dir="${ORIGINAL_DIR}/amd64"
    local work_root="${SCRATCH_DIR}/amd64"
    local initrd_root="${work_root}/initrd-root"
    local extension_dir="${work_root}/extensions"
    local overlay_build="${work_root}/overlay-build"
    local output_dir="${IPXE_DIR}/amd64"

    log "Building TinyCore Tools (amd64 - merged initrd)"

    mkdir -p "${initrd_root}" "${output_dir}"

    log "Unpacking base initramfs (amd64)"
    (
        cd "${initrd_root}"
        gzip -dc "${source_dir}/corepure64.gz" | cpio -idmu --quiet
    )

    prepare_overlay_with_extensions "amd64" "x86_64" "${overlay_build}" "${extension_dir}"

    log "Merging TinyCore Tools into CorePure64"
    cp -a "${overlay_build}/." "${initrd_root}/"

    cp "${source_dir}/vmlinuz64" "${output_dir}/vmlinuz64"

    log "Building merged initramfs (amd64)"
    (
        cd "${initrd_root}"
        find . -print0 | cpio --null -o --format=newc --quiet | gzip -9 > "${output_dir}/corepure64.gz"
    )

    build_iso_from_tree \
        "amd64" "${source_dir}/base.iso" "vmlinuz64" "corepure64.gz" \
        "${output_dir}/vmlinuz64" "${output_dir}/corepure64.gz" \
        "${ISO_OUTPUT_DIR}/tinycore-tools-amd64.iso" "${work_root}"
}

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

mkdir -p "${ORIGINAL_DIR}" "${CACHE_DIR}" "${OVERLAY_DIR}"
cleanup_workspace
mkdir -p "${SCRATCH_DIR}" "${OUTPUT_DIR}" "${IPXE_DIR}" "${ISO_OUTPUT_DIR}"

prepare_original "x86" "${X86_ISO_URL}" "vmlinuz" "core.gz"
prepare_original "amd64" "${AMD64_ISO_URL}" "vmlinuz64" "corepure64.gz"

build_x86
build_amd64

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
iseq ${buildarch} x86 && goto tiny-core-x86 ||
iseq ${buildarch} i386 && goto tiny-core-x86 ||
goto failed

:tiny-core-x86
kernel ${base-url}livecd/tiny-core/x86/vmlinuz quiet loglevel=3 || goto failed
initrd ${base-url}livecd/tiny-core/x86/core.gz || goto failed
initrd ${base-url}livecd/tiny-core/x86/tools.gz || goto failed
console
boot || goto failed

:tiny-core-amd64
kernel ${base-url}livecd/tiny-core/amd64/vmlinuz64 quiet loglevel=3 || goto failed
initrd ${base-url}livecd/tiny-core/amd64/corepure64.gz || goto failed
console
boot || goto failed
EOF

echo
echo "Boot design:"
echo "  x86   : pristine core.gz + separate tools.gz (known-good legacy BIOS path)"
echo "  amd64 : customised corepure64.gz with minimal proven UEFI/iPXE syntax"
echo
echo "Extension cache:"
echo "  ${CACHE_DIR}/x86/tcz"
echo "  ${CACHE_DIR}/amd64/tcz"
echo
echo "To sync from GitHub and rebuild:"
echo "  bash build.sh --refresh"
