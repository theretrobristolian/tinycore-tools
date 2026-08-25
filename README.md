# tinycore-tools

Lightweight Tiny Core Linux build and customisation tools for **iPXE booting, hardware discovery and basic diagnostics**.

TinyCore Tools now builds two versions of the same RAM-resident diagnostic environment:

* **x86** — maximum compatibility with older 32-bit/legacy BIOS hardware
* **amd64 / CorePure64** — modern x86-64 systems, including UEFI iPXE booting

The same project overlay supplies the banner, prompt and diagnostic tools to both builds.

## Current Status

The environment is working on real hardware and currently provides:

* x86 and amd64 iPXE payloads from one build
* x86 and amd64 bootable ISO output
* Dynamic console-width banner and UI formatting
* Compact `tc:` shell prompt
* `help`, `sysinfo` and `pciinfo` commands
* System manufacturer/model/serial and BIOS/board information from SMBIOS/DMI where available
* Intelligent `sysinfo` paging on classic low-resolution consoles
* PCI hardware reporting with readable vendor/device IDs
* Categorised PCI views and paged full PCI output
* `nano` text editor
* `pciutils` / `lspci`
* Architecture-specific Tiny Core extension dependency resolution
* One-command Git refresh and rebuild workflow

The emphasis remains **small, simple, reproducible and useful on old hardware** without sacrificing modern UEFI support.

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
├── original/
│   ├── x86/              # cached upstream x86 ISO/kernel/initramfs
│   └── amd64/            # cached upstream CorePure64 files
├── output/
│   ├── ipxe/
│   │   ├── x86/
│   │   │   ├── vmlinuz
│   │   │   ├── core.gz
│   │   │   └── tools.gz
│   │   └── amd64/
│   │       ├── vmlinuz64
│   │       ├── corepure64.gz
│   │       └── tools64.gz
│   └── iso/
│       ├── tinycore-tools-x86.iso
│       └── tinycore-tools-amd64.iso
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

The first build downloads and caches both upstream Tiny Core base ISOs. Later builds reuse them.

To force-sync tracked files from GitHub and immediately rebuild:

```bash
bash build.sh --refresh
```

`--refresh` intentionally discards local changes to tracked repository files while preserving generated/cache directories.

## Build Output

Every successful build creates:

```text
output/
├── ipxe/
│   ├── x86/
│   │   ├── vmlinuz
│   │   ├── core.gz
│   │   └── tools.gz
│   └── amd64/
│       ├── vmlinuz64
│       ├── corepure64.gz
│       └── tools64.gz
└── iso/
    ├── tinycore-tools-x86.iso
    └── tinycore-tools-amd64.iso
```

The iPXE builds keep the upstream base initramfs separate and load the TinyCore Tools environment as a second initramfs archive.

The ISO builds append the matching tools overlay to the matching Tiny Core initramfs and reuse the boot metadata from that architecture's upstream ISO.

## Tiny Core Extensions

`build.sh` currently includes:

```bash
nano
pciutils
```

Dependencies are resolved recursively from the **matching Tiny Core architecture repository**, downloaded, extracted and merged into the temporary overlay. This is done independently for x86 and x86_64 so binary extensions are never mixed between architectures.

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

Copy the contents of `output/ipxe/` to your web server, preserving the `x86` and `amd64` directories.

TinyCore Tools can then use the same `${buildarch}` approach commonly used for architecture-aware WinPE/iPXE environments:

```ipxe
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
```

This keeps old x86/BIOS hardware on the lightweight 32-bit Tiny Core kernel while x86-64/UEFI systems receive CorePure64.

## ISO Boot

The build produces two ISO images:

```text
output/iso/tinycore-tools-x86.iso
output/iso/tinycore-tools-amd64.iso
```

Use the x86 image when maximum old-hardware compatibility is required. Use the amd64/CorePure64 image for modern 64-bit systems and UEFI-capable hardware.

These provide a route into TinyCore Tools on machines that cannot PXE boot and can be written to suitable USB/optical media using normal ISO imaging software.

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

Tiny Core Linux is a separate project. The base images and selected extensions are downloaded from the Tiny Core Linux project during the build.

---

Created by **The Retro Bristolian**  
https://github.com/theretrobristolian/tinycore-tools
