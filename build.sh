#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

TINYCORE_VERSION="17.1"
BASE_URL="http://tinycorelinux.net/17.x/x86/release"
ISO_NAME="Core-${TINYCORE_VERSION}.iso"

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ORIGINAL_DIR="${SCRIPT_ROOT}/original"
PATCHED_DIR="${SCRIPT_ROOT}/patched"
OVERLAY_DIR="${SCRIPT_ROOT}/overlay"
SCRATCH_DIR="${SCRIPT_ROOT}/tc-scratch"

ISO_PATH="${SCRATCH_DIR}/${ISO_NAME}"
ISO_MOUNT="${SCRATCH_DIR}/iso"
INITRD_ROOT="${SCRATCH_DIR}/initrd"

ORIGINAL_KERNEL="${ORIGINAL_DIR}/vmlinuz"
ORIGINAL_INITRD="${ORIGINAL_DIR}/core.gz"

PATCHED_KERNEL="${PATCHED_DIR}/vmlinuz"
PATCHED_INITRD="${PATCHED_DIR}/core.gz"


# -----------------------------------------------------------------------------
# Helper
# -----------------------------------------------------------------------------

log() {
    echo
    echo "==> $1"
}

cleanup_mount() {
    if mountpoint -q "${ISO_MOUNT}" 2>/dev/null; then
        sudo umount "${ISO_MOUNT}"
    fi
}

trap cleanup_mount EXIT


# -----------------------------------------------------------------------------
# Prepare directories
# -----------------------------------------------------------------------------

mkdir -p "${ORIGINAL_DIR}"
mkdir -p "${PATCHED_DIR}"
mkdir -p "${OVERLAY_DIR}"


# -----------------------------------------------------------------------------
# Check for original Tiny Core files
# -----------------------------------------------------------------------------

if [[ -f "${ORIGINAL_KERNEL}" && -f "${ORIGINAL_INITRD}" ]]; then

    log "Original Tiny Core files already exist"

    echo "Using:"
    echo "  ${ORIGINAL_KERNEL}"
    echo "  ${ORIGINAL_INITRD}"

else

    log "Original Tiny Core files not found"

    rm -rf "${SCRATCH_DIR}"

    mkdir -p "${SCRATCH_DIR}"
    mkdir -p "${ISO_MOUNT}"

    # -------------------------------------------------------------------------
    # Download ISO
    # -------------------------------------------------------------------------

    log "Downloading Tiny Core Linux ${TINYCORE_VERSION}"

    wget \
        -O "${ISO_PATH}" \
        "${BASE_URL}/${ISO_NAME}"

    # -------------------------------------------------------------------------
    # Mount ISO
    # -------------------------------------------------------------------------

    log "Mounting ISO"

    sudo mount \
        -o loop,ro \
        "${ISO_PATH}" \
        "${ISO_MOUNT}"

    # -------------------------------------------------------------------------
    # Locate files
    # -------------------------------------------------------------------------

    log "Locating vmlinuz and core.gz"

    KERNEL_SOURCE="$(find "${ISO_MOUNT}" -type f -name vmlinuz | head -n 1)"
    INITRD_SOURCE="$(find "${ISO_MOUNT}" -type f -name core.gz | head -n 1)"

    if [[ -z "${KERNEL_SOURCE}" ]]; then
        echo "ERROR: Could not locate vmlinuz"
        exit 1
    fi

    if [[ -z "${INITRD_SOURCE}" ]]; then
        echo "ERROR: Could not locate core.gz"
        exit 1
    fi

    # -------------------------------------------------------------------------
    # Save gold copies
    # -------------------------------------------------------------------------

    log "Saving original Tiny Core files"

    cp "${KERNEL_SOURCE}" "${ORIGINAL_KERNEL}"
    cp "${INITRD_SOURCE}" "${ORIGINAL_INITRD}"

    cleanup_mount

    # -------------------------------------------------------------------------
    # Delete ISO / scratch download data
    # -------------------------------------------------------------------------

    log "Removing downloaded ISO"

    rm -f "${ISO_PATH}"

fi


# -----------------------------------------------------------------------------
# Recreate scratch directory
# -----------------------------------------------------------------------------

log "Preparing scratch workspace"

rm -rf "${SCRATCH_DIR}"

mkdir -p "${SCRATCH_DIR}"
mkdir -p "${INITRD_ROOT}"


# -----------------------------------------------------------------------------
# Clear previous patched output
# -----------------------------------------------------------------------------

log "Clearing previous patched build"

rm -rf "${PATCHED_DIR}"
mkdir -p "${PATCHED_DIR}"


# -----------------------------------------------------------------------------
# Unpack gold initramfs
# -----------------------------------------------------------------------------

log "Unpacking original core.gz"

cd "${INITRD_ROOT}"

gzip -dc "${ORIGINAL_INITRD}" | cpio -idmu


# -----------------------------------------------------------------------------
# Apply overlay
# -----------------------------------------------------------------------------

log "Applying overlay"

if [[ -d "${OVERLAY_DIR}" ]]; then
    cp -a "${OVERLAY_DIR}/." "${INITRD_ROOT}/"
fi


# -----------------------------------------------------------------------------
# Rebuild patched initramfs
# -----------------------------------------------------------------------------

log "Building patched core.gz"

cd "${INITRD_ROOT}"

find . -print0 \
    | cpio --null -ov --format=newc \
    | gzip -9 > "${PATCHED_INITRD}"


# -----------------------------------------------------------------------------
# Copy kernel
# -----------------------------------------------------------------------------

log "Copying kernel"

cp "${ORIGINAL_KERNEL}" "${PATCHED_KERNEL}"


# -----------------------------------------------------------------------------
# Add scratch README
# -----------------------------------------------------------------------------

cat > "${SCRATCH_DIR}/README.txt" <<EOF
Tiny Core temporary build workspace.

This directory is deleted and recreated every time build.sh runs.

Do not place permanent files here.

Repository layout:

original/
    Gold untouched Tiny Core files.

patched/
    Final iPXE-ready build.
    This directory is overwritten on every build.

overlay/
    Files to inject into the Tiny Core filesystem.

tc-scratch/
    Temporary unpacked build workspace.
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