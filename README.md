# tinycore-tools

Lightweight Tiny Core Linux build and customisation tools for **iPXE booting, hardware discovery and basic diagnostics**.

TinyCore Tools builds two versions of the same RAM-resident diagnostic environment:

* **x86** — maximum compatibility with older 32-bit/legacy BIOS hardware
* **amd64 / CorePure64** — modern x86-64 systems, including UEFI iPXE booting

The same project overlay supplies the banner, prompt and diagnostic tools to both builds.

## Current Status

The environment is working on real hardware and currently provides:

* x86 and amd64 iPXE payloads from one build
* x86 and amd64 bootable ISO output
* Dynamic console-width banner and UI formatting
* Compact `tc:` shell prompt
* `help`, `sysinfo`, `pciinfo`, `meminfo` and `netspeed` commands
* System manufacturer/model/serial and BIOS/board information from SMBIOS/DMI where available
* DIMM capacity, type, speed and physical slot reporting with `meminfo slots`
* LAN throughput testing using `iperf3` with a simplified `netspeed` wrapper
* Intelligent `sysinfo` paging on classic low-resolution consoles
* PCI hardware reporting with readable vendor/device IDs
* Categorised PCI views and paged full PCI output
* `nano` text editor
* `pciutils` / `lspci`
* `dmidecode`
* `iperf3`
* Architecture-specific Tiny Core extension dependency resolution and local extension caching
* One-command Git refresh and rebuild workflow

The emphasis remains **small, simple, reproducible and useful on old hardware** without sacrificing modern UEFI support.

## Quick Start

```bash
git clone https://github.com/theretrobristolian/tinycore-tools.git
cd tinycore-tools
bash build.sh
```

To force-sync tracked files from GitHub and immediately rebuild:

```bash
bash build.sh --refresh
```

`--refresh` intentionally discards local changes to tracked repository files while preserving the downloaded Tiny Core base files and extension cache.

## Tiny Core Extensions

`build.sh` includes:

```text
nano
pciutils
iperf3
dmidecode
```

Dependencies are resolved recursively from the matching Tiny Core architecture repository and cached under `cache/`. Subsequent builds reuse cached `.tcz` files rather than downloading them again.

## Commands

### `sysinfo`

Structured system summary including manufacturer, model, serial, BIOS, motherboard, CPU, architecture, memory, kernel and active network information.

### `pciinfo`

Compact PCI inventory. The default view concentrates on network and storage hardware.

```bash
pciinfo
pciinfo network
pciinfo storage
pciinfo display
pciinfo usb
pciinfo audio
pciinfo all
```

### `meminfo`

Shows a concise physical-memory summary sourced from SMBIOS/DMI:

```bash
meminfo
```

Typical fields include installed memory, physical slot count, used/free slots, memory type and configured speed.

For the Speccy-style DIMM view:

```bash
meminfo slots
```

This reports each firmware-described memory slot and, where supplied by the machine, DIMM size, type, speed, configured speed, manufacturer, part number and serial number. Empty slots are identified separately. Firmware quality varies, so some systems may omit individual fields.

### `netspeed`

Friendly wrapper around `iperf3` for testing actual LAN throughput.

Start an iperf3 endpoint on another TinyCore Tools machine or normal computer:

```bash
iperf3 -s
```

Then from the machine being tested:

```bash
netspeed 10.1.2.50
```

The default performs a five-second upload test followed by a five-second reverse/download test and displays the active interface and local IP.

Individual directions can also be tested:

```bash
netspeed 10.1.2.50 upload
netspeed 10.1.2.50 download
```

TinyCore Tools itself can be the server:

```bash
netspeed server
```

Raw `iperf3` remains available for advanced testing.

## iPXE Boot

Copy the contents of `output/ipxe/` to your web server, preserving the `x86` and `amd64` directories.

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
kernel ${base-url}livecd/tiny-core/amd64/vmlinuz64 quiet || goto failed
initrd ${base-url}livecd/tiny-core/amd64/corepure64.gz    || goto failed
boot                                                        || goto failed
```

The x86 build keeps the pristine Tiny Core `core.gz` and loads the tools as a separate initramfs. The amd64/CorePure64 build uses the proven merged-initramfs UEFI path.

## ISO Boot

The build produces:

```text
output/iso/tinycore-tools-x86.iso
output/iso/tinycore-tools-amd64.iso
```

Use the x86 image for maximum old-hardware compatibility and the amd64/CorePure64 image for modern 64-bit systems.

## Useful Commands

```bash
help
sysinfo
meminfo
meminfo slots
pciinfo
pciinfo network
pciinfo storage
netspeed 10.1.2.50
netspeed server
iperf3 -s
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

The intention is not to turn Tiny Core into a full rescue distribution. Features should remain focused on **small, useful diagnostic and recovery tasks while keeping RAM and download requirements as low as practical**.

## Tiny Core Linux

Tiny Core Linux is a separate project. The base images and selected extensions are downloaded from the Tiny Core Linux project during the build.

---

Created by **The Retro Bristolian**  
https://github.com/theretrobristolian/tinycore-tools
