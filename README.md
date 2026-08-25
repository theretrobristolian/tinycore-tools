# tinycore-tools

Lightweight Tiny Core Linux build and customisation tools for **iPXE booting, hardware discovery and basic diagnostics**.

The project provides a very small 32-bit Linux environment that boots entirely into RAM. A single build now produces both **iPXE boot files** and a **bootable ISO**, making the same diagnostic environment usable on systems with or without PXE capability.

## Current Status

The environment is working on real hardware and currently provides:

* iPXE and bootable ISO output from the same build
* Dynamic console-width banner and UI formatting
* Compact `tc:` shell prompt
* `help`, `sysinfo` and `pciinfo` commands
* System manufacturer/model/serial and BIOS/board information from SMBIOS/DMI where available
* Intelligent `sysinfo` paging on classic low-resolution consoles
* PCI hardware reporting with readable vendor/device IDs
* Categorised PCI views and paged full PCI output
* `nano` text editor
* `pciutils` / `lspci`
* Automatic Tiny Core extension dependency resolution
* One-command Git refresh and rebuild workflow

The emphasis remains **small, simple, reproducible and useful on old hardware**.

## Repository Structure

```text
tinycore-tools/
├── build.sh
├── README.md
├── .gitignore
├── overlay/
│   ├── home/tc/.profile
│   └── usr/local/
│       ├── bin/
│       │   ├── pciinfo
│       │   ├── sysinfo
│       │   └── tc-help
│       └── lib/
│           └── tc-ui.sh
├── original/             # cached upstream Tiny Core files
├── output/               # generated final artifacts
│   ├── ipxe/
│   │   ├── vmlinuz
│   │   ├── core.gz
│   │   └── tools.gz
│   └── iso/
│       └── tinycore-tools.iso
└── tc-scratch/           # temporary build workspace
```

`original/`, `output/` and `tc-scratch/` are generated locally and ignored by Git.

## Quick Start

```bash
git clone https://github.com/theretrobristolian/tinycore-tools.git
cd tinycore-tools
bash build.sh
```

The script checks its prerequisites and can offer to install missing packages on supported Linux distributions.

The first build downloads and caches the Tiny Core base ISO. Later builds reuse it.

To force-sync tracked files from GitHub and immediately rebuild:

```bash
bash build.sh --refresh
```

`--refresh` intentionally discards local changes to tracked repository files while preserving generated/cache directories.

## Build Output

Every successful build creates:

```text
output/ipxe/vmlinuz
output/ipxe/core.gz
output/ipxe/tools.gz
output/iso/tinycore-tools.iso
```

The iPXE output keeps the upstream `core.gz` untouched and loads the custom environment separately as `tools.gz`.

For the ISO, the same `tools.gz` is appended to the Tiny Core initramfs and packaged using the boot metadata from the upstream Tiny Core ISO. This keeps the CD/USB and network-booted environments functionally aligned.

The ISO can be burned to optical media or written to suitable bootable media using normal ISO imaging software.

## Tiny Core Extensions

`build.sh` currently bakes these Tiny Core extensions into `tools.gz`:

```bash
nano
pciutils
```

Dependencies are resolved recursively from `.tcz.dep`, downloaded, extracted and merged into the temporary overlay. Extensions increase RAM/download requirements, so additions should remain purposeful.

## Commands

### `help`

Displays project commands, included utilities, examples and project information.

### `sysinfo`

Displays a structured machine summary including, where the firmware exposes the information:

* System manufacturer
* Model
* Serial number
* BIOS vendor/version/date
* Motherboard manufacturer/model/version
* CPU
* Architecture
* Memory
* Kernel
* Active network interface
* MAC address
* IPv4 address
* Default gateway

Terminal dimensions are detected automatically. On taller terminals the report is shown in one view; on classic 25-line VGA consoles it is split into two screens with a **Press any key to continue** pause.

### `pciinfo`

The default report concentrates on network and storage controllers plus their PCI vendor/device IDs:

```bash
pciinfo
```

Additional views:

```bash
pciinfo network
pciinfo storage
pciinfo display
pciinfo usb
pciinfo audio
pciinfo all
```

Long device descriptions are formatted into short records for narrow legacy consoles. `pciinfo all` provides the complete paged PCI inventory.

## iPXE Boot

Copy `output/ipxe/` to your iPXE HTTP server:

```ipxe
:tiny-core
echo Booting TinyCore Tools...
kernel ${base-url}livecd/tiny-core/boot/vmlinuz quiet loglevel=3 || goto failed
initrd ${base-url}livecd/tiny-core/boot/core.gz                 || goto failed
initrd ${base-url}livecd/tiny-core/boot/tools.gz                || goto failed
boot                                                             || goto failed
```

## ISO Boot

The build also produces:

```text
output/iso/tinycore-tools.iso
```

This provides a route into TinyCore Tools on hardware that cannot PXE boot. It can then be used to run `sysinfo` and `pciinfo`, identify the NIC and investigate PXE/iPXE support.

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

## Development Direction

Potential additions include USB/floppy-oriented legacy boot images, assisted iPXE ROM identification/build workflows, storage/partition summaries, FAT/FAT32/NTFS access, Windows partition detection, HTTP file transfer and NFS/SMB network access.

A useful workflow is:

```text
Machine cannot PXE boot
        │
        ▼
Boot TinyCore Tools ISO
        │
        ▼
Run sysinfo / pciinfo
        │
        ▼
Identify wired NIC PCI ID
        │
        ▼
Investigate/build matching iPXE support
```

The intention is not to turn Tiny Core into a full rescue distribution. Features should remain focused on **small, useful diagnostic and recovery tasks while keeping RAM and download requirements as low as practical**.

## Tiny Core Linux

Tiny Core Linux is a separate project. The base image and selected extensions are downloaded from the Tiny Core Linux project during the build.

---

Created by **The Retro Bristolian**  
https://github.com/theretrobristolian/tinycore-tools
