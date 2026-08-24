# tinycore-tools

Lightweight Tiny Core Linux build and customisation tools for **iPXE booting, hardware discovery and basic diagnostics**.

The aim of this project is to provide a very small Linux environment that can be booted entirely into RAM using iPXE and used across a wide range of x86 hardware.

The project intentionally starts with the standard **32-bit Tiny Core Linux Core image** and applies a small custom overlay rather than requiring users to build a Linux distribution from scratch.

## Goals

`tinycore-tools` is intended to provide a simple RAM-based environment for tasks such as:

* Basic hardware identification
* CPU and memory information
* PCI device identification
* Network adapter and MAC address identification
* IP and network diagnostics
* Disk and partition identification
* Basic access to local filesystems
* File transfer and recovery tasks
* Gathering information useful when troubleshooting or building iPXE environments

The emphasis is on keeping the environment **small, simple and easy to reproduce**.

## Repository Structure

```text
tinycore-tools/
├── build.sh
├── README.md
├── .gitignore
│
├── overlay/
│   ├── etc/
│   │   └── motd
│   └── usr/local/bin/
│       └── help
│
├── examples/
│   └── tinycore.ipxe
│
├── original/
│   ├── vmlinuz
│   └── core.gz
│
├── patched/
│   ├── vmlinuz
│   └── core.gz
│
└── tc-scratch/
```

### `original/`

Contains the untouched Tiny Core Linux kernel and initramfs.

On the first run, `build.sh` downloads the configured Tiny Core ISO and extracts:

```text
vmlinuz
core.gz
```

These files are retained as the clean source for future builds.

Subsequent builds reuse these files and do not download the ISO again.

### `overlay/`

Contains files that will be added to or replace files within the Tiny Core initramfs.

For example:

```text
overlay/etc/motd
```

becomes:

```text
/etc/motd
```

inside the resulting Linux environment.

Custom scripts can similarly be placed under:

```text
overlay/usr/local/bin/
```

### `patched/`

Contains the finished iPXE-ready build:

```text
patched/vmlinuz
patched/core.gz
```

This directory is regenerated each time `build.sh` runs.

### `tc-scratch/`

Temporary workspace used while unpacking and rebuilding the Tiny Core initramfs.

This directory is disposable and should not contain permanent customisations.

## Requirements

The build script is intended to run on Linux or WSL.

Basic requirements include:

```text
bash
wget
gzip
cpio
mount
find
```

Mounting the Tiny Core ISO during the initial build may require `sudo`.

## Quick Start

Clone the repository:

```bash
git clone <repository-url>
cd tinycore-tools
```

Make the build script executable:

```bash
chmod +x build.sh
```

Run the build:

```bash
./build.sh
```

### First Run

The first run will:

1. Download the configured Tiny Core Linux ISO.
2. Mount the ISO.
3. Extract `vmlinuz` and `core.gz`.
4. Store the untouched files in `original/`.
5. Remove the downloaded ISO.
6. Unpack `original/core.gz`.
7. Apply the contents of `overlay/`.
8. Rebuild the initramfs.
9. Place the finished files in `patched/`.

### Subsequent Runs

If these files already exist:

```text
original/vmlinuz
original/core.gz
```

the download and extraction process is skipped.

The existing original files are reused and a new `patched/core.gz` is built from the current contents of `overlay/`.

This makes experimenting with changes quick while always starting from a known clean Tiny Core image.

## iPXE

Copy the contents of:

```text
patched/
```

to a directory accessible from your iPXE HTTP server.

A minimal iPXE configuration looks like:

```ipxe
:tiny-core
echo Booting Tiny Core Tools...
kernel ${base-url}livecd/tiny-core/boot/vmlinuz   || goto failed
initrd ${base-url}livecd/tiny-core/boot/core.gz   || goto failed
boot                                              || goto failed
```

Adjust the paths to match your environment.

## Initial Commands

The standard Tiny Core environment already provides enough functionality for some basic diagnostics.

Examples include:

```bash
uname -a
```

Display kernel and architecture information.

```bash
free -m
```

Display available memory.

```bash
cat /proc/cpuinfo
```

Display CPU information.

```bash
ifconfig
```

Display network interfaces, IP addresses and MAC addresses.

```bash
route -n
```

Display the routing table.

```bash
ping google.com
```

Test network connectivity and DNS resolution.

## Development Approach

Changes should generally be made under:

```text
overlay/
```

rather than directly modifying the generated filesystem under `tc-scratch/`.

The intended workflow is:

```text
original/core.gz
       │
       ▼
   unpack
       │
       ▼
 apply overlay/
       │
       ▼
    rebuild
       │
       ▼
patched/core.gz
```

This keeps the original Tiny Core image untouched and makes every customised build reproducible.

## Planned Functionality

Future additions may include:

* Friendly boot banner and help system
* Hardware summary command
* PCI device enumeration
* PCI vendor/device ID reporting
* Network adapter identification
* MAC and IP address summary
* Storage device identification
* FAT/FAT32/NTFS filesystem access
* Automatic detection of Windows partitions
* HTTP file download
* File upload to a deployment server
* NFS/SMB network access
* Additional network diagnostics
* Information useful for identifying NICs and preparing iPXE ROM builds

The intention is not to turn Tiny Core into a full rescue distribution. Features should remain focused on **small, useful diagnostic and recovery tasks while keeping RAM and download requirements as low as practical**.

## Tiny Core Linux

This project uses Tiny Core Linux as its base operating system.

Tiny Core Linux is a separate project and is not included in this repository. The required base image is downloaded from the Tiny Core Linux project during the initial build.

The Tiny Core version used by the build can be configured in `build.sh`.
