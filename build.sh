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

ORIGINAL_KERNEL="${ORIGINAL_DIR}/vmlinuz"
ORIGINAL_INITRD="${ORIGINAL_DIR}/core.gz"

PATCHED_KERNEL="${PATCHED_DIR}/vmlinuz"
PATCHED_INITRD="${PATCHED_DIR}/core.gz"
PATCHED_TOOLS="${PATCHED_DIR}/tools.gz"


# -----------------------------------------------------------------------------
# Helpers
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
# Prerequisite check
# -----------------------------------------------------------------------------

REQUIRED_COMMANDS=(
    wget
    cpio
    gzip
    find
    mount
    mountpoint
)

MISSING_COMMANDS=()

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        MISSING_COMMANDS+=("${cmd}")
    fi
done

if (( ${#MISSING_COMMANDS[@]} > 0 )); then

    log "Missing build prerequisites"

    echo "The following required commands are not installed:"
    echo

    for cmd in "${MISSING_COMMANDS[@]}"; do
        echo "  - ${cmd}"
    done

    echo

    if command -v apt-get >/dev/null 2>&1; then

        echo "This system appears to use APT."
        echo
        read -r -p "Install/update the required packages now? [Y/n]: " ANSWER
        ANSWER="${ANSWER:-Y}"

        if [[ "${ANSWER}" =~ ^[Yy]$ ]]; then

            sudo apt-get update

            sudo apt-get install -y \
                wget \
                cpio \
                gzip \
                findutils \
                util-linux

        else
            echo
            echo "Cannot continue without the required packages."
            exit 1
        fi

    elif command -v dnf >/dev/null 2>&1; then

        echo "This system appears to use DNF."
        echo
        read -r -p "Install the required packages now? [Y/n]: " ANSWER
        ANSWER="${ANSWER:-Y}"

        if [[ "${ANSWER}" =~ ^[Yy]$ ]]; then

            sudo dnf install -y \
                wget \
                cpio \
                gzip \
                findutils \
                util-linux

        else
            echo
            echo "Cannot continue without the required packages."
            exit 1
        fi

    elif command -v yum >/dev/null 2>&1; then

        echo "This system appears to use YUM."
        echo
        read -r -p "Install the required packages now? [Y/n]: " ANSWER
        ANSWER="${ANSWER:-Y}"

        if [[ "${ANSWER}" =~ ^[Yy]$ ]]; then

            sudo yum install -y \
                wget \
                cpio \
                gzip \
                findutils \
                util-linux

        else
            echo
            echo "Cannot continue without the required packages."
            exit 1
        fi

    else

        echo "ERROR: No supported package manager was detected."
        echo
        echo "Please install the following commands manually:"
        echo

        for cmd in "${MISSING_COMMANDS[@]}"; do
            echo "  - ${cmd}"
        done

        exit 1

    fi

fi


# -----------------------------------------------------------------------------
# Verify prerequisites after installation
# -----------------------------------------------------------------------------

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "ERROR: Required command '${cmd}' is still unavailable."
        exit 1
    fi
done

log "Prerequisite check passed"


# -----------------------------------------------------------------------------
# Prepare directories
# -----------------------------------------------------------------------------

mkdir -p "${ORIGINAL_DIR}"
mkdir -p "${PATCHED_DIR}"
mkdir -p "${OVERLAY_DIR}"
mkdir -p "${SCRATCH_DIR}"


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
    # Delete ISO
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


# -----------------------------------------------------------------------------
# Clear previous patched output
# -----------------------------------------------------------------------------

log "Clearing previous patched build"

rm -rf "${PATCHED_DIR}"
mkdir -p "${PATCHED_DIR}"


# -----------------------------------------------------------------------------
# Copy original Tiny Core files
# -----------------------------------------------------------------------------

log "Copying original Tiny Core boot files"

cp "${ORIGINAL_KERNEL}" "${PATCHED_KERNEL}"
cp "${ORIGINAL_INITRD}" "${PATCHED_INITRD}"


# -----------------------------------------------------------------------------
# Build custom tools initramfs
# -----------------------------------------------------------------------------

log "Building tools overlay"

if [[ -n "$(find "${OVERLAY_DIR}" -mindepth 1 -print -quit 2>/dev/null)" ]]; then

    cd "${OVERLAY_DIR}"

    find . -print0 \
        | cpio --null -ov --format=newc \
        | gzip -9 > "${PATCHED_TOOLS}"

else

    echo "WARNING: overlay directory is empty."
    echo "Creating an empty tools.gz."

    cd "${SCRATCH_DIR}"

    printf '' \
        | cpio -o --format=newc \
        | gzip -9 > "${PATCHED_TOOLS}"

fi


# -----------------------------------------------------------------------------
# Add scratch README
# -----------------------------------------------------------------------------

cat > "${SCRATCH_DIR}/README.txt" <<EOF
Tiny Core temporary build workspace.

This directory is deleted and recreated every time build.sh runs.

Do not place permanent files here.

Repository layout:

original/
    Gold untouched Tiny Core files:
        vmlinuz
        core.gz

patched/
    Final iPXE-ready build:
        vmlinuz
        core.gz
        tools.gz

overlay/
    Files to inject into Tiny Core at boot.

    The directory structure underneath overlay/ should match the
    desired Linux filesystem structure.

    Example:

        overlay/etc/motd

    becomes:

        /etc/motd

    inside Tiny Core.

tc-scratch/
    Temporary build workspace.

The original Tiny Core core.gz is never unpacked or modified.

tools.gz contains only the contents of overlay/.
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
echo "Example iPXE:"
echo
echo "  kernel <url>/vmlinuz"
echo "  initrd <url>/core.gz"
echo "  initrd <url>/tools.gz"
echo "  boot"