# tinycore-tools

Lightweight Tiny Core Linux build and customisation tools for **iPXE booting, hardware discovery and basic diagnostics**.

The project provides a very small Linux environment that boots entirely into RAM using iPXE. It starts with the standard **32-bit Tiny Core Linux Core image** and adds a separate custom initramfs overlay, keeping the original Tiny Core files untouched.

## Goals

`tinycore-tools` is intended for basic hardware identification, PCI/network discovery, network diagnostics, storage/file access and other lightweight tasks useful when troubleshooting or building iPXE environments.

The emphasis is on keeping the environment **small, simple and easy to reproduce**.

## Repository Structure

```text
tinycore-tools/
├── build.sh
├── README.md
├── .gitignore
├── overlay/
│   ├── etc/motd
│   ├── home/tc/.profile
│   └── usr/local/bin/
│       ├── help
│       ├── pciinfo
│       └── sysinfo
├── original/             # generated/cache - ignored by Git
├── patched/              # generated - ignored by Git
└── tc-scratch/           # temporary - ignored by Git
```

## Quick Start

```bash
git clone https://github.com/theretrobristolian/tinycore-tools.git
cd tinycore-tools
bash build.sh
```

The script checks for its own build prerequisites and can offer to install missing packages on supported Linux distributions.

The first build downloads the configured Tiny Core ISO and caches untouched `vmlinuz` and `core.gz` files under `original/`. Later builds reuse them.

To force-sync tracked files from GitHub and immediately rebuild:

```bash
bash build.sh --refresh
```

`--refresh` intentionally discards local changes to tracked repository files, while preserving generated/cache directories such as `original/`.

## Overlay Model

Files under `overlay/` mirror their destination inside Tiny Core. For example:

```text
overlay/etc/motd                 -> /etc/motd
overlay/usr/local/bin/sysinfo    -> /usr/local/bin/sysinfo
```

The build script works on a temporary copy, so setting command permissions does not dirty the Git working tree.

The finished files are:

```text
patched/vmlinuz
patched/core.gz
patched/tools.gz
```

The upstream `core.gz` remains untouched. Project files and bundled extensions live in `tools.gz`.

## Tiny Core Extensions

`build.sh` can bake standard Tiny Core `.tcz` extensions directly into `tools.gz`.

Configured extensions are listed near the top of the script:

```bash
TINYCORE_EXTENSIONS=(
    nano
    pciutils
)
```

For each configured extension the build automatically reads its `.tcz.dep` file, recursively resolves dependencies, downloads the required `.tcz` packages, extracts them with `unsquashfs`, and merges them into the temporary overlay.

This keeps the iPXE boot simple while allowing useful Tiny Core software to be added without committing binaries to this repository.

Current bundled extensions provide:

* `nano` - simple console text editor.
* `pciutils` - provides `lspci` and friendly PCI device reporting.

Extensions increase `tools.gz` and RAM usage, so additions should remain purposeful.

## Current Commands

### `help`

Displays the project commands, useful built-in commands and examples.

### `sysinfo`

Displays a concise summary of:

* CPU
* Architecture
* Memory
* Kernel
* Active network interface
* MAC address
* IPv4 address
* Default gateway

### `pciinfo`

Displays PCI hardware and PCI vendor/device IDs. When `pciutils` is available it uses:

```bash
lspci -nn
```

and separately highlights network devices. A `/sys/bus/pci` fallback remains in the script so raw IDs can still be reported without `lspci`.

## iPXE

Copy the contents of `patched/` to your iPXE HTTP server.

```ipxe
:tiny-core
echo Booting TinyCore Tools...
kernel ${base-url}livecd/tiny-core/boot/vmlinuz quiet loglevel=3 || goto failed
initrd ${base-url}livecd/tiny-core/boot/core.gz                 || goto failed
initrd ${base-url}livecd/tiny-core/boot/tools.gz                || goto failed
boot                                                             || goto failed
```

## Useful Commands

```bash
help
sysinfo
pciinfo
lspci -nn
nano /tmp/notes.txt
ifconfig
route -n
ping google.com
uname -a
free -m
```

## Development Approach

Permanent project changes belong under `overlay/`. Generated files under `original/`, `patched/` and `tc-scratch/` are excluded from Git.

The build model is:

```text
original/vmlinuz + original/core.gz
                 +
              overlay/
                 +
        configured .tcz extensions
                 │
                 ▼
        patched/vmlinuz
        patched/core.gz
        patched/tools.gz
```

This keeps upstream Tiny Core pristine and makes the custom layer reproducible.

## Planned Functionality

Future additions may include storage device identification, FAT/FAT32/NTFS access, automatic Windows partition detection, HTTP file transfer, NFS/SMB network access and further network/NIC diagnostics useful for preparing iPXE ROM builds.

The intention is not to turn Tiny Core into a full rescue distribution. Features should remain focused on **small, useful diagnostic and recovery tasks while keeping RAM and download requirements as low as practical**.

## Tiny Core Linux

Tiny Core Linux is a separate project and is not included in this repository. The base image and selected extensions are downloaded from the Tiny Core Linux project during the build.
