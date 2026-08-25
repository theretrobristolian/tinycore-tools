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
TINYCORE_EXTENSIONS=(nano pciutils)

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIGINAL_DIR="${SCRIPT_ROOT}/original"
OUTPUT_DIR="${SCRIPT_ROOT}/output"
IPXE_DIR="${OUTPUT_DIR}/ipxe"
ISO_OUTPUT_DIR="${OUTPUT_DIR}/iso"
OVERLAY_DIR="${SCRIPT_ROOT}/overlay"
SCRATCH_DIR="${SCRIPT_ROOT}/tc-scratch"
OVERLAY_BUILD_DIR="${SCRATCH_DIR}/overlay-build"
EXTENSION_DIR="${SCRATCH_DIR}/extensions"
ISO_TREE="${SCRATCH_DIR}/iso-tree"
ISO_MOUNT="${SCRATCH_DIR}/iso-mount"
ISO_PATH="${SCRATCH_DIR}/${ISO_NAME}"
ORIGINAL_ISO="${ORIGINAL_DIR}/${ISO_NAME}"
ORIGINAL_KERNEL="${ORIGINAL_DIR}/vmlinuz"
ORIGINAL_INITRD="${ORIGINAL_DIR}/core.gz"
IPXE_KERNEL="${IPXE_DIR}/vmlinuz"
IPXE_INITRD="${IPXE_DIR}/core.gz"
IPXE_TOOLS="${IPXE_DIR}/tools.gz"
OUTPUT_ISO="${ISO_OUTPUT_DIR}/tinycore-tools.iso"
REFRESH=false

log() { echo; echo "==> $1"; }
cleanup_mount() { if mountpoint -q "${ISO_MOUNT}" 2>/dev/null; then sudo umount "${ISO_MOUNT}"; fi; }
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
    local extension="$1" existing dep_file
    extension="${extension%.tcz}"
    [[ -n "$extension" ]] || return 0
    for existing in "${TCZ_QUEUE[@]:-}"; do [[ "$existing" == "$extension" ]] && return 0; done
    TCZ_QUEUE+=("$extension")
    dep_file="${EXTENSION_DIR}/${extension}.tcz.dep"
    if wget -q -O "$dep_file" "${TCZ_BASE_URL}/${extension}.tcz.dep"; then
        while IFS= read -r dependency || [[ -n "$dependency" ]]; do
            dependency="${dependency//$'\r'/}"
            [[ -n "$dependency" ]] && queue_extension "$dependency"
        done < "$dep_file"
    else rm -f "$dep_file"; fi
}

while (( $# > 0 )); do
    case "$1" in
        --refresh) REFRESH=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: Unknown option: $1"; echo; usage; exit 1 ;;
    esac
    shift
done

if [[ "$REFRESH" == true ]]; then
    log "Refreshing repository from origin/main"
    command -v git >/dev/null 2>&1 || { echo "ERROR: git is required for --refresh."; exit 1; }
    git -C "$SCRIPT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: Not a Git working tree."; exit 1; }
    echo "Local tracked changes will be discarded; generated/cache directories are preserved."
    git -C "$SCRIPT_ROOT" fetch origin main
    git -C "$SCRIPT_ROOT" reset --hard origin/main
    exec bash "$SCRIPT_ROOT/build.sh"
fi

# xorriso creates the final bootable ISO and unsquashfs expands Tiny Core extensions.
REQUIRED_COMMANDS=(wget cpio gzip find mount mountpoint unsquashfs xorriso)
MISSING_COMMANDS=()
for cmd in "${REQUIRED_COMMANDS[@]}"; do command -v "$cmd" >/dev/null 2>&1 || MISSING_COMMANDS+=("$cmd"); done

if (( ${#MISSING_COMMANDS[@]} > 0 )); then
    log "Missing build prerequisites"
    printf '  - %s\n' "${MISSING_COMMANDS[@]}"
    echo
    if command -v apt-get >/dev/null 2>&1; then
        read -r -p "Install/update the required packages now? [Y/n]: " ANSWER; ANSWER="${ANSWER:-Y}"
        [[ "$ANSWER" =~ ^[Yy]$ ]] || exit 1
        sudo apt-get update
        sudo apt-get install -y wget cpio gzip findutils util-linux squashfs-tools xorriso
    elif command -v dnf >/dev/null 2>&1; then
        read -r -p "Install the required packages now? [Y/n]: " ANSWER; ANSWER="${ANSWER:-Y}"
        [[ "$ANSWER" =~ ^[Yy]$ ]] || exit 1
        sudo dnf install -y wget cpio gzip findutils util-linux squashfs-tools xorriso
    elif command -v yum >/dev/null 2>&1; then
        read -r -p "Install the required packages now? [Y/n]: " ANSWER; ANSWER="${ANSWER:-Y}"
        [[ "$ANSWER" =~ ^[Yy]$ ]] || exit 1
        sudo yum install -y wget cpio gzip findutils util-linux squashfs-tools xorriso
    else echo "ERROR: No supported package manager detected."; exit 1; fi
fi
for cmd in "${REQUIRED_COMMANDS[@]}"; do command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: Required command '$cmd' is unavailable."; exit 1; }; done
log "Prerequisite check passed"

mkdir -p "$ORIGINAL_DIR" "$OUTPUT_DIR" "$OVERLAY_DIR" "$SCRATCH_DIR"

# Keep the original ISO as a cache as well as the extracted kernel/initramfs.
# It supplies Tiny Core's proven bootloader files when generating our ISO.
if [[ ! -f "$ORIGINAL_ISO" ]]; then
    log "Downloading Tiny Core Linux ${TINYCORE_VERSION} base ISO"
    wget -O "$ORIGINAL_ISO" "${BASE_URL}/${ISO_NAME}"
fi

if [[ ! -f "$ORIGINAL_KERNEL" || ! -f "$ORIGINAL_INITRD" ]]; then
    log "Extracting original Tiny Core boot files"
    rm -rf "$ISO_MOUNT"; mkdir -p "$ISO_MOUNT"
    sudo mount -o loop,ro "$ORIGINAL_ISO" "$ISO_MOUNT"
    KERNEL_SOURCE="$(find "$ISO_MOUNT" -type f -name vmlinuz | head -n1)"
    INITRD_SOURCE="$(find "$ISO_MOUNT" -type f -name core.gz | head -n1)"
    [[ -n "$KERNEL_SOURCE" && -n "$INITRD_SOURCE" ]] || { echo "ERROR: Could not locate Tiny Core boot files."; exit 1; }
    cp "$KERNEL_SOURCE" "$ORIGINAL_KERNEL"
    cp "$INITRD_SOURCE" "$ORIGINAL_INITRD"
    cleanup_mount
else
    log "Original Tiny Core files already exist"
fi

log "Preparing build workspace and output"
rm -rf "$SCRATCH_DIR" "$OUTPUT_DIR"
mkdir -p "$SCRATCH_DIR" "$OVERLAY_BUILD_DIR" "$EXTENSION_DIR" "$IPXE_DIR" "$ISO_OUTPUT_DIR"
cp "$ORIGINAL_KERNEL" "$IPXE_KERNEL"
cp "$ORIGINAL_INITRD" "$IPXE_INITRD"

log "Preparing project overlay"
if [[ -n "$(find "$OVERLAY_DIR" -mindepth 1 -print -quit 2>/dev/null)" ]]; then cp -a "$OVERLAY_DIR/." "$OVERLAY_BUILD_DIR/"; fi

if (( ${#TINYCORE_EXTENSIONS[@]} > 0 )); then
    log "Resolving Tiny Core extensions"
    TCZ_QUEUE=()
    for extension in "${TINYCORE_EXTENSIONS[@]}"; do queue_extension "$extension"; done
    echo "Extensions to include:"; printf '  - %s\n' "${TCZ_QUEUE[@]}"
    log "Downloading and extracting Tiny Core extensions"
    for extension in "${TCZ_QUEUE[@]}"; do
        TCZ_FILE="${EXTENSION_DIR}/${extension}.tcz"; EXTRACT_DIR="${EXTENSION_DIR}/${extension}"
        echo "  ${extension}.tcz"
        wget -q -O "$TCZ_FILE" "${TCZ_BASE_URL}/${extension}.tcz"
        mkdir -p "$EXTRACT_DIR"
        unsquashfs -f -d "$EXTRACT_DIR" "$TCZ_FILE" >/dev/null
        cp -a "$EXTRACT_DIR/." "$OVERLAY_BUILD_DIR/"
    done
fi

log "Preparing file permissions"
if [[ -d "$OVERLAY_BUILD_DIR/usr/local/bin" ]]; then find "$OVERLAY_BUILD_DIR/usr/local/bin" -type f -exec chmod 0755 {} +; fi
if [[ -f "$OVERLAY_BUILD_DIR/home/tc/.profile" ]]; then chmod 0644 "$OVERLAY_BUILD_DIR/home/tc/.profile"; fi

log "Building tools overlay"
cd "$OVERLAY_BUILD_DIR"
find . -print0 | cpio --null -ov --format=newc | gzip -9 > "$IPXE_TOOLS"

# Build an ISO by copying Tiny Core's own bootable ISO tree and replacing its
# boot payload. tools.gz is appended to core.gz because the CD bootloader loads
# a single initrd, while iPXE can load core.gz and tools.gz independently.
log "Building bootable TinyCore Tools ISO"
mkdir -p "$ISO_MOUNT" "$ISO_TREE"
sudo mount -o loop,ro "$ORIGINAL_ISO" "$ISO_MOUNT"
cp -a "$ISO_MOUNT/." "$ISO_TREE/"
cleanup_mount

ISO_KERNEL="$(find "$ISO_TREE" -type f -name vmlinuz | head -n1)"
ISO_INITRD="$(find "$ISO_TREE" -type f -name core.gz | head -n1)"
[[ -n "$ISO_KERNEL" && -n "$ISO_INITRD" ]] || { echo "ERROR: Could not locate boot payload in ISO tree."; exit 1; }
cp "$IPXE_KERNEL" "$ISO_KERNEL"
cat "$IPXE_INITRD" "$IPXE_TOOLS" > "$ISO_INITRD"

# Replay the boot metadata from the upstream Tiny Core ISO while using our
# modified filesystem tree. This avoids hard-coding isolinux paths/flags.
xorriso -indev "$ORIGINAL_ISO" -outdev "$OUTPUT_ISO" -map "$ISO_TREE" / -boot_image any replay >/dev/null 2>&1

log "Build complete"
echo
echo "Output:"
find "$OUTPUT_DIR" -maxdepth 2 -type f -printf '  %P  (%k KB)\n' | sort
echo
echo "iPXE files:"
echo "  $IPXE_DIR"
echo
echo "Bootable ISO:"
echo "  $OUTPUT_ISO"
echo
echo "Example iPXE:"
echo "  kernel <url>/vmlinuz quiet loglevel=3"
echo "  initrd <url>/core.gz"
echo "  initrd <url>/tools.gz"
echo "  boot"
echo
echo "To sync from GitHub and rebuild:"
echo "  bash build.sh --refresh"
