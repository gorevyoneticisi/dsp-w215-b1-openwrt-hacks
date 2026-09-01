# Live B1 flash layout and GPIO (2026-09-01)

SSH dump from a D-Link DSP-W215 B1 running OpenWrt SNAPSHOT r19327+6 (kernel 5.10.109, ath79/tiny). Board string: `dlink,dsp-w215-b1`. SoC: QCA9533 ver 2 rev 0. Flash: MX25L6405D 8 MiB SPI NOR.

This is a live `/proc/mtd` plus binwalk of the dumped partitions. It is not a schematic.

## GPIO (sysfs)

`dmesg`: `gpio-export gpio-export: 1 gpio(s) exported`

From `/sys/kernel/debug/gpio` at dump time:

```
gpio-0   (gpio:ac_output_enable) out lo
gpio-3   (red:power)             out hi ACTIVE LOW
gpio-4   (green:power)           out lo ACTIVE LOW
gpio-11  (red:wps)               out hi ACTIVE LOW
gpio-12  (green:wps)             out hi ACTIVE LOW
```

GPIO 0 is the OpenWrt AC output control path (`echo 1/0 > /sys/class/gpio/gpio:ac_output_enable/value`). This dump does not continuity trace the pin to the relay coil.

GPIO 2, 13, and 17 are in the DTS (`key_ac_toggle`, reset, wps) but were not exported. `gpio-keys` failed:

```
gpio-keys keys: Button node 'key_ac_toggle' without keycode
gpio-keys: probe of keys failed with error -22
```

That failure takes down the whole keys node, so reset/WPS gpio-keys also did not bind.

Kernel console is `ttyS0` at 115200. PL8331 metering on the same UART is 19200 in this project. Those are different baud rates on one port.

No second PL8331 enable GPIO showed up in sysfs.

## MTD (live)

```
mtd0: 00010000 00010000 "u-boot"
mtd1: 00010000 00010000 "art"
mtd2: 00010000 00010000 "mp"
mtd3: 00010000 00010000 "config"
mtd4: 00010000 00010000 "log"
mtd5: 00260000 00010000 "recovery"
mtd6: 00550000 00010000 "firmware"
mtd7: 001a0000 00010000 "kernel"
mtd8: 003b0000 00010000 "rootfs"
mtd9: 000b0000 00010000 "rootfs_data"
```

dmesg matches the DTS cuts:

```
0x00000000-0x00010000 : "u-boot"
0x00010000-0x00020000 : "art"
0x00020000-0x00030000 : "mp"
0x00030000-0x00040000 : "config"
0x00040000-0x00050000 : "log"
0x00050000-0x002b0000 : "recovery"
0x002b0000-0x00800000 : "firmware"
```

Inside firmware, uimage-fw split:

```
0x00000000-0x001a0000 : "kernel"
0x001a0000-0x00550000 : "rootfs"
```

rootfs_data is the JFFS2 overlay at the end of rootfs (`0x4a0000` relative to firmware in dmesg).

Sizes in KiB:

| Region | Flash offset | Size |
|--------|--------------|------|
| recovery | 0x050000 | 2432 KiB (0x260000) |
| firmware | 0x2B0000 | 5440 KiB (0x550000) |
| OpenWrt kernel (mtd7) | 0x2B0000 | 1664 KiB (0x1a0000) |
| OpenWrt rootfs (mtd8) | 0x450000 | 3776 KiB (0x3b0000) |

## Recovery kernel / rootfs (mtd5)

File: `dumps/mtd5-recovery.bin` (2490368 bytes)

- uImage at 0x0, name `Linux Backup Mode Kernel Image`, data size 870808
- squashfs magic `hsqs` at **0xE0000**

That is:

- kernel 0x050000 to 0x130000 (896 KiB)
- rootfs 0x130000 to 0x2B0000 (1536 KiB)

The 870808 byte header size matches the 2014 backup image in s-2's old U-Boot log.

## OpenWrt kernel / rootfs (mtd6/mtd7/mtd8)

This image does **not** use a 896 KiB kernel slot. mtdsplit follows the uImage.

File: `dumps/mtd7-kernel.bin` (1703936 bytes = 0x1a0000)

- uImage at 0x0, name `MIPS OpenWrt Linux-5.10.109`, data size 1644485
- squashfs starts at 0x1a0000 in the firmware partition (start of mtd8)

Flash:

- kernel 0x2B0000 to 0x450000
- rootfs 0x450000 to 0x800000

OEM factory images (DAP wrapped, `mkdapimg2 0x000E0000`) still use a 896 KiB kernel slot. That is the stock update format, not this OpenWrt runtime split.

## What is not in this repo

Not published:

- `art` (radio calibration)
- `mp` (board/MAC data)
- `rootfs_data` / the tail of `firmware` (JFFS2 overlay: wireless, dropbear host keys, shadow)
- `full-flash.bin` (concatenated overlapping mtds, 14 MB, not an 8 MiB chip image)
- extracted squashfs trees
- live WiFi passwords and root password

Text configs in the original dump folder were placeholder redacted. The overlay partition still holds a `wireless` inode (JFFS2 LZMA), so those bins stay offline.

## SHA256

```
mtd5-recovery.bin  b58f14db186250aa7a8b0ab48ef28aaa2479545548cd0850b0b4d54e3ab1e4d5
mtd7-kernel.bin    c27c243b7b8b051ca5ce1665ea95ffc9082e667d69759945cecf84a8ca321f66
```
