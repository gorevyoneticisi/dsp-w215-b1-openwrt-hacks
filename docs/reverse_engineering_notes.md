# DSP‑W215 Reverse Engineering Notes

This document collects raw findings, hypotheses, and low‑level observations discovered while reversing the stock firmware of the DSP‑W215 smart plug / power meter.

It is intentionally practical and messy: these are notes from real experiments, binwalk results, strings output, UART captures, and live probing.

---

## Firmware Under Test

File:
```
DSP-W215B2_FW224B01.bin
```

Extraction (binwalk):
```
binwalk -e DSP-W215B2_FW224B01.bin
```

Relevant output:
```
_DSP-W215B2_FW224B01.bin.extracted/
 ├── E0048.squashfs
 ├── squashfs-root/
 └── squashfs-root-0/
```

Primary rootfs used:
```
_DSP-W215B2_FW224B01.bin.extracted/squashfs-root
```

---

## Interesting Binaries

Two binaries are responsible for power meter communication:

```
squashfs-root/mnt/power_meter_uart
squashfs-root/usr/bin/prolific_center
```

File info:
```
ELF 32-bit MSB executable, MIPS, MIPS32 rel2, dynamically linked, uClibc
```

Meaning:
- Big‑endian MIPS
- o32 ABI
- Soft‑float
- Uses /lib/ld-uClibc.so.0

---

## UART Device

Hardcoded inside binary:
```
/dev/ttyS0
```

Therefore power meter IC is connected internally via SoC UART.

---

## Extracted Command Strings

Using:
```
strings -a squashfs-root/mnt/power_meter_uart
```

Unique commands found:

```
:01M      $01M
:01R00    $01R00
:01I00    $01I00
:01V00    $01V00
:01W00    $01W00
:01E00    $01E00
:01P00    $01P00
:01Y1     $01Y1
:01Y0     $01Y0
:01S001   $01S00 1
:01S000   $01S00 0
:01O01    $01O01
```

Observed pattern:

```
:01XXXX<CR>   -> transmit
$01XXXX ...   -> response
```

---

## Human‑Readable Printf Templates

Found inside binary:

```
Firmware Version:       %s
RMS of the Current:     %s A
RMS of the Voltage:      %s V
Instant Active Power:   %s W
Energy:         %s KWh
Power Factor:   %s
Set Relay ON Success.
Set Relay OFF Success.
Set IO High Success.
Set IO Low Success.
IO Status:      %s
Command response error!
```

This strongly confirms meaning of many commands.

---

## Live UART Sniffing (OpenWrt)

Basic dump:

```
cat /dev/ttyS0 | hexdump -C
```

or

```
cat /dev/ttyS0 | tr '\r' '\n'
```

---

## Working Filters

Voltage:
```
cat /dev/ttyS0 | tr '\r' '\n' | egrep '^\$01V00'
```

Power:
```
cat /dev/ttyS0 | tr '\r' '\n' | egrep '^\$01W00'
```

Current:
```
cat /dev/ttyS0 | tr '\r' '\n' | egrep '^\$01I00'
```

Power Factor:
```
cat /dev/ttyS0 | tr '\r' '\n' | egrep '^\$01P00'
```

---

## Verified Example Output

```
$01V00 218747      -> ~218.7 V
$01W00 000686      -> ~6.86 W
$01P00 +998        -> power factor ~0.998
```

7.5W LED lamp measured ≈ 6.9‑7.0W → matches real world.

---

## Command Injection Tests

Flush RX buffer and send:

```
dd if=/dev/ttyS0 of=/dev/null bs=512 count=1 2>/dev/null
printf ":01V00\r" > /dev/ttyS0
sleep 1
dd if=/dev/ttyS0 bs=512 count=1 2>/dev/null | tr '\r' '\n'
```

Same method works for:

```
:01W00
:01I00
:01P00
```

---

## Relay Control

ON:
```
printf ":01S001\r" > /dev/ttyS0
```

OFF:
```
printf ":01S000\r" > /dev/ttyS0
```

Responses:
```
$01S00 1
$01S00 0
```

---

## IO Control

```
printf ":01O01\r" > /dev/ttyS0
```

Returns IO status string.

Likely GPIO line tied to relay transistor.

---

## Protocol Characteristics

- ASCII based
- Carriage return terminated
- No checksum
- No framing bytes
- Master/slave style

Looks very similar to simple industrial meter ASCII protocols.

---

## Why QEMU Execution Failed

All extracted binaries:

```
ELF 32-bit MSB (big endian)
```

Most PC QEMU user emulation defaults to little‑endian MIPS.

Even with qemu-mips (BE), uClibc loader + ABI mismatch causes:

```
Exec format error
```

Conclusion: easier to reverse using strings + static analysis than emulating.

---

## Architecture Summary

```
AR9331/QCA9533 SoC
 └── UART -> Power meter IC
            └── ASCII command protocol
```

---

## Hypothesis About Temperature Sensor

Some datasheets claim DSP‑W215 contains temperature sensing.

However:
- No TMP/TEMP strings found in power_meter_uart
- No obvious command for temperature

Possibilities:
1) Temp handled by another MCU
2) Temp available via GPIO ADC not implemented
3) Marketing error

---

## Useful Reverse Engineering Commands

```
strings -a file
xxd file | grep 3031
readelf -h file
readelf -s file
radare2 -A file
```

---

## Future Work

- Dump raw UART traffic while official firmware app polls
- Identify baudrate & UART config
- Write minimal C or shell reader
- Create OpenWrt service
- Build MQTT bridge

---

## TL;DR

DSP‑W215 exposes a clean ASCII UART power meter protocol internally.

Once OpenWrt is installed, no vendor cloud is needed.

This device can become a fully local smart plug.

---

Documented by: TaskManager

