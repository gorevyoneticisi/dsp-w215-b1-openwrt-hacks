# DSP-W215 UART Protocol – Firmware-Backed Reverse Engineering

Author: gorevyoneticisi  
Device: DSP-W215 / DSP-W215B2 Power Meter Plug  
Focus: Internal UART protocol used by the power-meter MCU via `/dev/ttyS0`

---

## 1. Executive Summary

The DSP-W215 contains an internal power-meter microcontroller connected to the main SoC through UART (`/dev/ttyS0`).

By extracting and analyzing the stock firmware, the binary `power_meter_uart` was identified as the userland program responsible for communicating with the power meter.

Reverse engineering of this binary proves:

- Commands are **raw ASCII strings**
- Commands have **no CR (\r)**
- Commands have **no LF (\n)**
- Commands have **no CRLF**
- Firmware uses `strlen()` when writing commands

Therefore:

> Commands must be sent exactly as plain ASCII with no terminator.

Example:

```
printf ":01V00" > /dev/ttyS0
```

---

## 2. Firmware Extraction (Binwalk Research)

### 2.1 Dump Firmware

```
binwalk -e DSP-W215B2_FW224B01.bin
```

Results:

```
_DSP-W215B2_FW224B01.bin.extracted/
 ├── squashfs-root/
```

### 2.2 Locate Power Meter Binary

```
find squashfs-root -type f | grep power_meter
```

Output:

```
squashfs-root/mnt/power_meter_uart
```

### 2.3 Identify Binary

```
file squashfs-root/mnt/power_meter_uart
```

Output:

```
ELF 32-bit MSB executable, MIPS, MIPS32 rel2 version 1 (SYSV)
interpreter /lib/ld-uClibc.so.0
not stripped
```

---

## 3. ELF Inspection

### 3.1 Header

```
readelf -h power_meter_uart
```

Important fields:

```
Class: ELF32
Data:  Big Endian
Machine: MIPS R3000
Type: EXEC
```

### 3.2 Imported Functions

```
readelf -s power_meter_uart | grep UND
```

Notable imports:

```
strlen
write
read
sprintf
strncmp
strcat
strncat
memcpy
tcgetattr
tcsetattr
tcflush
```

Presence of `strlen` strongly indicates writes use exact string length.

---

## 4. Extracted Command Strings

```
strings -a power_meter_uart | grep -E '^:01|^\$01'
```

Output:

```
:01M
$01M

:01R00
$01R00

:01I00
$01I00

:01V00
$01V00

:01W00
$01W00

:01E00
$01E00

:01P00
$01P00

:01Y1
$01Y1

:01Y0
$01Y0

:01S001
$01S00 1

:01S000
$01S00 0

:01O01
$01O01
```

Each command appears twice:

- `:01XXX` → transmit
- `$01XXX` → expected response prefix

---

## 5. No CR/LF Evidence

### 5.1 Search for CRLF

```
grep -aobU $'\r\n' power_meter_uart
```

No results.

### 5.2 Search for standalone CR

```
grep -aobU $'\r' power_meter_uart
```

No results.

### 5.3 Search for standalone LF

```
grep -aobU $'\n' power_meter_uart
```

LF exists only inside user-facing print strings such as:

```
Command response error!\n
Reset Success.\n
```

Meaning LF is used only for console output, not for UART framing.

---

## 6. Proof via Hex Inspection

```
xxd -g 1 power_meter_uart | grep 3a 30 31
```

Example snippet:

```
3a 30 31 56 30 30   => :01V00
24 30 31 56 30 30   => $01V00
```

No trailing bytes follow these strings.

---

## 7. Runtime Verification on Device

Voltage:

```
printf ":01V00" > /dev/ttyS0
cat /dev/ttyS0 | tr '\r' '\n'

$01V00 218747
```

Power:

```
printf ":01W00" > /dev/ttyS0

$01W00 000686
```

Connected load ≈ 7.5W LED lamp → reading ≈ 6.8–7.0W (correct)

---

## 8. Command Table

| Command | Description |
|-------|------------|
| :01V00 | RMS Voltage |
| :01I00 | RMS Current |
| :01W00 | Instant Active Power |
| :01E00 | Energy (kWh) |
| :01P00 | Power Factor |
| :01M | Firmware version |
| :01R00 | Reset |
| :01Y1 | Relay ON |
| :01Y0 | Relay OFF |
| :01S001 | Set IO High |
| :01S000 | Set IO Low |
| :01O01 | IO Status |

---

## 9. Correct Usage Pattern

Always send raw command:

```
printf ":01V00" > /dev/ttyS0
```

❌ Do NOT use:

```
echo :01V00
printf ":01V00\n"
printf ":01V00\r"
printf ":01V00\r\n"
```

---

## 10. Root Cause of Common Failures

Most failures online occur because users append newline characters.  
Firmware does strict string comparison using `strncmp()`.

Even one extra byte breaks parsing.

---

## 11. Why This Works

Decompiled logic pattern:

```c
write(fd, cmd, strlen(cmd));
read(fd, buf, ...);
strncmp(buf, expected_prefix, ...);
```

No delimiter handling exists.

---

## 12. Credits

Reverse engineered by **gorevyoneticisi**  
Method: Firmware-backed static analysis + live UART verification

---

## 13. License

Documentation released under MIT License.

