# tinycore-tools

Lightweight Tiny Core Linux build and customisation tools for **iPXE booting, hardware discovery and basic diagnostics**.

The project provides a very small Linux environment that boots entirely into RAM using iPXE. It starts with the standard **32-bit Tiny Core Linux Core image** and adds a separate custom initramfs overlay, keeping the original Tiny Core files untouched.

## v1 Status

The initial v1 environment is now working on real hardware.

Current features include:

* RAM-based Tiny Core Linux boot environment
* iPXE boot support
* Dynamic console-width banner and UI formatting
* Compact `tc:` shell prompt
* `help` command
* `sysinfo` hardware/network summary
* `pciinfo` PCI hardware reporting with readable PCI vendor/device IDs
* Categorised PCI views such as `pciinfo network` and `pciinfo storage`
* Paged full PCI output with `pciinfo all`
* `nano` text editor
* `pciutils` / `lspci`
* Automatic Tiny Core extension dependency resolution during build
* One-command Git refresh and rebuild workflow

The emphasis remains **small, simple, reproducible and useful on old hardware**.

## Repository Structure

```text
tinycore-tools/
├── build.sh
├── README.md
├── .gitignore
├── overlay/
│   ├── etc/motd
│   ├── home/tc/.profile
│   └── usr/local/
│       ├── bin/
│       │   ├── pciinfo
│       │   ├── sysinfo
│       │   └── tc-help
│       └── lib/
│           └── tc-ui.sh
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

`--refresh` intentionally discards local changes to tracked repository files while preserving generated/cache directories such as `original/`.

## Build Model

Files under `overlay/` mirror their destination inside Tiny Core. The build script works on a temporary copy, adds configured Tiny Core extensions, and produces:

```text
patched/vmlinuz
patched/core.gz
patched/tools.gz
```

The upstream `core.gz` remains untouched. Project files and bundled extensions live in `tools.gz`.

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

## Tiny Core Extensions

`build.sh` can bake standard Tiny Core `.tcz` extensions directly into `tools.gz`.

Configured extensions currently include:

```bash
nano
pciutils
```

The build recursively resolves `.tcz.dep` dependencies, downloads the required extensions, extracts them with `unsquashfs`, and merges them into the temporary overlay.

Extensions increase `tools.gz` and RAM usage, so additions should remain purposeful.

## Commands

### `help`

Displays the project command summary, included utilities, examples and project information.

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

The default report deliberately shows only the most immediately useful PCI hardware:

```bash
pciinfo
```

* Network controllers
* Storage controllers
* PCI vendor/device IDs

Additional views are available on demand:

```bash
pciinfo network
pciinfo storage
pciinfo display
pciinfo usb
pciinfo audio
pciinfo all
```

The output is formatted into short records so long hardware descriptions do not split awkwardly across narrow legacy consoles.

PCI IDs such as:

```text
1969:2060
8086:0083
```

can be used to identify the exact network hardware and are useful when investigating or building an iPXE option ROM for a specific NIC.

## iPXE Boot

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
pciinfo network
pciinfo storage
pciinfo all
lspci -nn
nano /tmp/notes.txt
ifconfig
route -n
ping google.com
uname -a
free -m
```

## Future Direction

Potential follow-on work includes:

* Build a bootable TinyCore Tools ISO for machines that cannot PXE boot
* USB/floppy boot images for legacy systems
* Assisted iPXE ROM identification/build workflow using detected PCI IDs
* Storage device and partition summaries
* FAT/FAT32/NTFS access
* Automatic Windows partition detection
* HTTP file transfer
* NFS/SMB network access
* Additional network/NIC diagnostics

A useful future workflow is therefore:

```text
Machine cannot PXE boot
        │
        ▼
Boot TinyCore Tools from CD/USB
        │
        ▼
Run pciinfo
        │
        ▼
Identify wired NIC PCI vendor/device ID
        │
        ▼
Build/test the matching iPXE ROM
        │
        ▼
Machine can PXE/iPXE boot directly
```

The intention is not to turn Tiny Core into a full rescue distribution. Features should remain focused on **small, useful diagnostic and recovery tasks while keeping RAM and download requirements as low as practical**.

## Tiny Core Linux

Tiny Core Linux is a separate project and is not included in this repository. The base image and selected extensions are downloaded from the Tiny Core Linux project during the build.

---

Created by **The Retro Bristolian**  
https://github.com/theretrobristolian/tinycore-tools
