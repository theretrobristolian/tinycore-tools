# tinycore-tools

Lightweight Tiny Core Linux build and customisation tools for **iPXE booting, hardware discovery and basic diagnostics**.

The project provides a very small Linux environment that boots entirely into RAM using iPXE. It starts with the standard **32-bit Tiny Core Linux Core image** and adds a separate custom initramfs overlay, keeping the original Tiny Core files untouched.

## Goals

`tinycore-tools` is intended for tasks such as:

* Basic hardware identification
* CPU and memory information
* PCI device identification
* Network adapter, MAC and IP identification
* Network diagnostics
* Disk and partition identification
* Basic local filesystem access
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
│   ├── home/tc/
│   │   └── .profile
│   └── usr/local/bin/
│       └── sysinfo
│
├── original/             # generated/cache - ignored by Git
│   ├── vmlinuz
│   └── core.gz
│
├── patched/              # generated - ignored by Git
│   ├── vmlinuz
│   ├── core.gz
│   └── tools.gz
│
└── tc-scratch/           # temporary - ignored by Git
```

### `original/`

Contains untouched Tiny Core boot files. On the first build, `build.sh` downloads the configured Tiny Core ISO and extracts:

```text
vmlinuz
core.gz
```

These files are retained locally and reused on later builds, so the ISO does not need to be downloaded every time.

### `overlay/`

Contains the project's custom files. The directory structure mirrors where each file will appear inside the booted Tiny Core environment.

For example:

```text
overlay/etc/motd
```

becomes:

```text
/etc/motd
```

and commands placed in:

```text
overlay/usr/local/bin/
```

become commands available in the booted environment.

The build script copies the overlay into its temporary workspace before changing command permissions, so building does not modify the tracked files in your Git working tree.

### `patched/`

Contains the finished iPXE-ready files:

```text
patched/vmlinuz
patched/core.gz
patched/tools.gz
```

`vmlinuz` and `core.gz` remain the original Tiny Core files. `tools.gz` contains only the custom `tinycore-tools` overlay.

### `tc-scratch/`

Disposable temporary workspace used during the build.

## Requirements

The build script is intended to run on Linux or WSL. It checks for its required utilities and, on supported package managers, offers to install missing prerequisites.

The initial Tiny Core ISO extraction uses a loop mount and may require `sudo`.

## Quick Start

Clone the repository:

```bash
git clone https://github.com/theretrobristolian/tinycore-tools.git
cd tinycore-tools
```

Run the build through Bash:

```bash
bash build.sh
```

Using `bash build.sh` means the executable bit on the script is not required.

### First Build

The first build will:

1. Check/install required build utilities.
2. Download the configured Tiny Core Linux ISO.
3. Mount the ISO.
4. Extract `vmlinuz` and `core.gz` into `original/`.
5. Remove the downloaded ISO.
6. Copy the original boot files into `patched/`.
7. Package `overlay/` as `patched/tools.gz`.

The original `core.gz` is never unpacked or modified.

### Later Builds

Simply run:

```bash
bash build.sh
```

The cached files in `original/` are reused and only the custom overlay is rebuilt.

### Refresh From GitHub and Build

If the repository has been updated on GitHub and this local copy is only being used as a build machine, run:

```bash
bash build.sh --refresh
```

This will:

1. Fetch the latest `main` branch from GitHub.
2. Discard local changes to **tracked repository files**.
3. Preserve `original/`, `patched/` and `tc-scratch/`.
4. Restart the latest version of `build.sh`.
5. Build a fresh `tools.gz`.

This avoids the previous `git reset`, `git clean`, `git pull`, `chmod` sequence and, importantly, preserves the cached Tiny Core files in `original/`.

> `--refresh` intentionally discards local changes to tracked files. Use it on a build copy where GitHub is the source of truth.

## iPXE

Copy the contents of `patched/` to a directory available from your iPXE HTTP server.

A minimal entry is:

```ipxe
:tiny-core
echo Booting TinyCore Tools...
kernel ${base-url}livecd/tiny-core/boot/vmlinuz quiet loglevel=3 || goto failed
initrd ${base-url}livecd/tiny-core/boot/core.gz                 || goto failed
initrd ${base-url}livecd/tiny-core/boot/tools.gz                || goto failed
boot                                                             || goto failed
```

The base Tiny Core initramfs is loaded first, followed by the project overlay.

## Current Customisation

The current overlay provides:

* A `TinyCore Tools` login banner.
* A compact `tc:~$` shell prompt.
* `sysinfo` for concise CPU, architecture, memory, kernel and active network information.

Example:

```bash
sysinfo
```

The standard Tiny Core environment also provides commands such as:

```bash
uname -a
free -m
cat /proc/cpuinfo
ifconfig
route -n
ping google.com
```

## Development Approach

Permanent project changes belong under `overlay/`. Generated files under `original/`, `patched/` and `tc-scratch/` are deliberately excluded from Git.

The build model is:

```text
original/vmlinuz + original/core.gz
                 +
              overlay/
                 │
                 ▼
        patched/vmlinuz
        patched/core.gz
        patched/tools.gz
```

This keeps upstream Tiny Core pristine and makes the custom layer small and reproducible.

## Planned Functionality

Future additions may include:

* Help command
* PCI device enumeration and vendor/device IDs
* Network adapter identification
* Storage device identification
* FAT/FAT32/NTFS filesystem access
* Automatic detection of Windows partitions
* HTTP file download/upload
* NFS/SMB network access
* Additional network diagnostics
* Information useful for identifying NICs and preparing iPXE ROM builds

The intention is not to turn Tiny Core into a full rescue distribution. Features should remain focused on **small, useful diagnostic and recovery tasks while keeping RAM and download requirements as low as practical**.

## Tiny Core Linux

This project uses Tiny Core Linux as its base operating system. Tiny Core Linux is a separate project and is not included in this repository. The required base image is downloaded from the Tiny Core Linux project during the initial build.

The Tiny Core version used by the build can be configured in `build.sh`.
