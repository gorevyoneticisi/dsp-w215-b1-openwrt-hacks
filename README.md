# D-Link DSP‑W215 B1 OpenWrt Hacks

Reverse engineering + practical control scripts for the **D‑Link DSP‑W215 B1 (EU / REV B1)** smart plug running OpenWrt.

> A complete, real‑world, step‑by‑step guide to flashing OpenWrt on the **D‑Link DSP‑W215 B1**, fixing connectivity issues, dealing with snapshot/opkg chaos, enabling serial communication with the **PL8331 power metering chip**, controlling the relay, and extracting real‑time voltage/current/power values.

This document is intentionally verbose and forensic. It exists so nobody else has to rediscover this through days of trial and error.

---

## ⚠️ Scope

This guide is written and tested on:

- Device: **D‑Link DSP‑W215 B1 (EU / REV B)**
- SoC: Qualcomm Atheros QCA9533 / QCA9531 family
- Flash: 8 MB
- RAM: 64 MB
- Power metering IC: **Prolific PL8331**

This repo focuses on:

- **Flashing OpenWrt via the built‑in recovery web UI** (no Ethernet port)
- **Fixing post‑flash connectivity issues** (sysupgrade step)
- **Relay (AC output) control** via GPIO
- **PL8331 UART power metering** on `/dev/ttyS0` (19200 baud)
- A **working, real‑world monitoring script** (your “Adaptive V” version)
- Reality of **snapshot-ish builds + broken opkg feeds** and the exact workaround you used

A1/A2 variants behave differently (GPIO naming, PL8331 enable behavior, serial console conflicts, etc.). Some notes about A1/A2 are included, but scripts in this repo target **B1**.

> ! **Mains voltage warning**: this device switches AC mains. Do not open the enclosure or probe the PCB while connected to mains. If you use TTL serial on the board, do it with the device safely isolated and/or powered from a safe low‑voltage setup.


---

## References (upstream / authoritative)

- OpenWrt Wiki hardware page: `https://openwrt.org/toh/d-link/dsp-w215`
  
- Original OpenWrt support commit for B1 (Sebastian Schaper / s‑2): `https://github.com/s-2/openwrt/commit/0c162e7e482ebc92c8c4f5661c62771555399fc8`

---


## Why this device is special

- No Ethernet port → Wi‑Fi must auto‑enable
- No official OpenWrt mainline support
- Extremely small flash → modern OpenWrt barely fits
- Serial port is shared between Linux console and PL8331
- Snapshot builds often have broken or missing opkg feeds

Despite this, the device is perfectly usable as:

- Smart relay
- Power meter
- Home Assistant / MQTT / SSH controlled plug

---

# PART 1 — Flashing OpenWrt (Recovery Method)

### Download firmware

Factory image:

```
http://sebastianschaper.net/openwrt/openwrt-ath79-tiny-dlink_dsp-w215-b1-squashfs-factory.bin
```

Sysupgrade image:

```
http://sebastianschaper.net/openwrt/openwrt-ath79-tiny-dlink_dsp-w215-b1-squashfs-sysupgrade.bin
```

---

### Enter Recovery Mode

1. Unplug plug from mains
2. Hold **RESET** button (side of device)
3. Plug into mains while holding RESET
4. Keep holding until LED flashes **red**

---

### Flash

1. Connect to Wi‑Fi AP broadcast by plug: `DSP-XXXX`
2. Open browser:

```
http://192.168.0.60
```

3. Upload `*-factory.bin`
4. Wait for flash + reboot

---

# PART 2 — Post‑Flash Connectivity Fix (CRITICAL)

After factory flash, networking may be unstable or broken.

Immediately perform a sysupgrade to the matching sysupgrade image:

```sh
cd /tmp
wget http://sebastianschaper.net/openwrt/openwrt-ath79-tiny-dlink_dsp-w215-b1-squashfs-sysupgrade.bin
```
```sh
sysupgrade -n openwrt-ath79-tiny-dlink_dsp-w215-b1-squashfs-sysupgrade.bin
```

`-n` wipes config and prevents corrupted defaults.

---

# PART 3 — Wi‑Fi Login Credentials (B1)

The device auto‑generates Wi‑Fi credentials on boot.

- SSID format:

  `DSP-XXYY`

- Password format:

  `<SSID><6-digit PIN printed on the label>`

Example:

- SSID: `DSP-A1B2`
- PIN: `123456`
- Password: `DSP-A1B2123456`

---

# PART 4 — Relay Control (B1)

The B1 variant exposes a GPIO directly controlling AC relay:

```
/sys/class/gpio/gpio:ac_output_enable/value
```

### Manual Control

```sh
# ON
echo 1 > /sys/class/gpio/gpio:ac_output_enable/value

# OFF
echo 0 > /sys/class/gpio/gpio:ac_output_enable/value
```

---

### Create Convenience Scripts

```sh
echo '#!/bin/sh' > /usr/bin/poweron
echo 'echo 1 > /sys/class/gpio/gpio:ac_output_enable/value' >> /usr/bin/poweron
chmod +x /usr/bin/poweron


echo '#!/bin/sh' > /usr/bin/poweroff
echo 'echo 0 > /sys/class/gpio/gpio:ac_output_enable/value' >> /usr/bin/poweroff
chmod +x /usr/bin/poweroff
```

Usage:

```
poweron
poweroff
```

---

# PART 5 — Serial Interface to PL8331 (Power Meter)

PL8331 is connected to:

```
/dev/ttyS0
```

Baud rate:

```
19200
```

---

# PART 6 — Snapshot / opkg Reality

This firmware behaves like a snapshot build.

Symptoms:

- `opkg update` fails
- Packages report "no valid architecture"
- Feeds often unusable

Solution: manual IPK installation + architecture override.

---

# PART 7 — Installing stty (Required)

BusyBox build does **NOT** include stty.

We must install coreutils + coreutils-stty manually.

### Download IPKs

```sh
cd /tmp
wget --no-check-certificate https://downloads.openwrt.org/releases/21.02.7/packages/mips_24kc/packages/coreutils_8.32-6_mips_24kc.ipk
wget --no-check-certificate https://downloads.openwrt.org/releases/21.02.7/packages/mips_24kc/packages/coreutils-stty_8.32-6_mips_24kc.ipk
```

---

### Fix Architecture Mismatch

Edit:

```sh
vi /etc/opkg.conf
```

Add at bottom:

```
arch mips_24kc 100
```

---

### Install

```sh
opkg install --force-depends coreutils_8.32-6_mips_24kc.ipk
opkg install --force-depends coreutils-stty_8.32-6_mips_24kc.ipk
```

Warnings about other packages having no valid architecture are expected.

---

### Locate stty

```sh
opkg files coreutils-stty
```

Output:

```
/usr/libexec/stty-coreutils
```

Create symlink:

```sh
ln -s /usr/libexec/stty-coreutils /usr/bin/stty
```

Verify:

```sh
stty --version
```

---

# PART 8 — First Contact with PL8331

```sh
stty -F /dev/ttyS0 19200 raw -echo

echo -e ":01M\r" > /dev/ttyS0
cat /dev/ttyS0
```

Expected spam example:

```
$01MPL05
```

This confirms UART + chip are alive.

---

# PART 9 — Raw Byte Inspection (Discovery Phase)

```sh
echo -e ":01M\n" > /dev/ttyS0
head -c 20 /dev/ttyS0 | hexdump -C
```

Observed samples:

```
50 0a 00 20 2d 30 31 32 0d 24 30 31 50
2b 38 35 37 0d 24 30 31 50
2b 39 31 31 0d 24 30 31 50
```

Observations:

- Frames contain ASCII text
- CR (0d) and LF (0a) separators
- Occasional 00 bytes
- Tags such as `$01P`, `$01I`, `$01V`

This explains why cleaning with printable‑only filtering is required.

---

# PART 10 — Working Monitoring Script (Adaptive Voltage)

```sh
#!/bin/sh

cleanup() {
    if [ ! -z "$PID" ]; then kill $PID 2>/dev/null; fi
    rm -f /tmp/raw.dump
    echo ""
    echo "Exiting."
    exit 0
}
trap cleanup INT TERM

stty -F /dev/ttyS0 19200 raw -echo -hupcl min 1 time 0

echo "=========================================="
echo "    SMART PLUG MONITOR (Adaptive V)       "
echo "=========================================="

while true; do
    rm -f /tmp/raw.dump

    cat /dev/ttyS0 > /tmp/raw.dump &
    PID=$!

    sleep 1

    printf ":01V\n" > /dev/ttyS0
    sleep 2

    printf ":01I\n" > /dev/ttyS0
    sleep 4

    kill $PID 2>/dev/null
    wait $PID 2>/dev/null

    CLEAN_DATA=$(cat /tmp/raw.dump | tr -cd '\40-\176')

    SAFE_DATA=$(echo "$CLEAN_DATA" | sed 's/\$01I/|/')

    RAW_V=$(echo "$SAFE_DATA" | cut -d'|' -f1 | tr -d -c 0-9 | awk '{l=length($0); if(l>6) print substr($0, l-5); else print $0}')
    RAW_I=$(echo "$SAFE_DATA" | cut -d'|' -f2 | tr -d -c 0-9 | head -c 6)

    echo "----------------------------------------"
    echo "RAW DATA: $CLEAN_DATA"

    if [ ${#RAW_V} -ge 5 ] && [ ${#RAW_I} -gt 0 ]; then
        VOLTS=$(awk "BEGIN {if($RAW_V > 99999) printf \"%.2f\", $RAW_V/1000; else printf \"%.2f\", $RAW_V/100}")
        AMPS=$(awk "BEGIN {printf \"%.3f\", $RAW_I/10000}")
        WATTS=$(awk "BEGIN {printf \"%.2f\", $VOLTS * $AMPS}")

        echo "VOLTAGE : $VOLTS V"
        echo "CURRENT : $AMPS A"
        echo "POWER   : $WATTS W"
    else
        echo "WARNING : Frame Skipped!"
    fi
done
```

---

# PART 11 — Example Output

```
RAW DATA:  221371$01I 000524
VOLTAGE : 221.37 V
CURRENT : 0.052 A
POWER   : 11.51 W
```

---

# PART 12 — Home Assistant Integration (SSH Command Line Switch)

```yaml
switch:
 - platform: command_line
   switches:
      dlink_powerplug:
        command_on: ssh root@192.168.X.X 'echo 1 > /sys/class/gpio/gpio:ac_output_enable/value'
        command_off: ssh root@192.168.X.X 'echo 0 > /sys/class/gpio/gpio:ac_output_enable/value'
```

Run once to store host key:

```sh
ssh root@192.168.X.X
```

---

# PART 13 — Credits

- Sebastian Schaper (s‑2) — Original OpenWrt support
- accwebs — A1/A2 resurrection and modern branches
- Community reverse‑engineering

---




