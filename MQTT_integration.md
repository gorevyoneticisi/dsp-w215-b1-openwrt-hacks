# MQTT Integration (DSP-W215 B1 → Homelab)

This document explains how I integrated MQTT publishing into the power monitoring script and how to receive and view the data on a homelab server.

Nothing here modifies the power parsing logic.
MQTT is only used as an output channel.

---

## Overview

Flow:

DSP-W215 (OpenWrt)  
→ mosquitto_pub (client)  
→ Mosquitto Broker (CasaOS / Docker)  
→ MQTTX Web / mosquitto_sub / Home Assistant / Node-RED

The plug publishes JSON like:

```
{"voltage":221.37,"current":0.052,"power":11.51}
```

Topic example:

```
home/smartplug/status
```
## References
  
- Mosquitto MQTT Docker configuration for CasaOS: `https://github.com/hqnicolas/eclipse-mosquitto`

---




---

## Part 1 — Installing mosquitto_pub on the Smart Plug (OpenWrt)

Snapshot builds and tiny flash devices often have broken or unusable opkg feeds. Instead of fighting opkg, I used **manual package extraction**.

### 1. Allow mips_24kc architecture

```
echo "arch mips_24kc 100" >> /etc/opkg.conf
```

### 2. Download required packages

```
cd /tmp

wget http://downloads.openwrt.org/releases/21.02.0/packages/mips_24kc/packages/cJSON_1.7.15-3_mips_24kc.ipk
wget http://downloads.openwrt.org/releases/21.02.0/packages/mips_24kc/packages/libcares_1.17.2-1_mips_24kc.ipk
wget http://downloads.openwrt.org/releases/21.02.0/packages/mips_24kc/packages/libmosquitto-nossl_2.0.11-1_mips_24kc.ipk
wget http://downloads.openwrt.org/releases/21.02.0/packages/mips_24kc/packages/mosquitto-client-nossl_2.0.11-1_mips_24kc.ipk
```

### 3. Manual extraction (bypasses opkg)

```
tar -xzf libmosquitto-nossl_2.0.11-1_mips_24kc.ipk
tar -xzf data.tar.gz -C /
rm control.tar.gz data.tar.gz debian-binary


tar -xzf mosquitto-client-nossl_2.0.11-1_mips_24kc.ipk
tar -xzf data.tar.gz -C /
rm control.tar.gz data.tar.gz debian-binary


tar -xzf cJSON_1.7.15-3_mips_24kc.ipk
tar -xzf data.tar.gz -C /
rm control.tar.gz data.tar.gz debian-binary


tar -xzf libcares_1.17.2-1_mips_24kc.ipk
tar -xzf data.tar.gz -C /
rm control.tar.gz data.tar.gz debian-binary
```

### 4. Fix missing librt (musl systems)

```
ln -s /lib/libc.so /lib/librt.so.1
ln -s /lib/libc.so /usr/lib/librt.so.1
```

### 5. Verify

```
mosquitto_pub --help
```

If help text prints → success.

---

## Part 2 — Install Mosquitto Broker on Homelab (CasaOS)

I run Mosquitto inside Docker.

### 1. Create folders

```
sudo mkdir -p /DATA/AppData/eclipse-mosquitto/mosquitto/config
sudo mkdir -p /DATA/AppData/eclipse-mosquitto/mosquitto/data
sudo mkdir -p /DATA/AppData/eclipse-mosquitto/mosquitto/log
sudo chmod -R 777 /DATA/AppData/eclipse-mosquitto
```

### 2. Create config file

File:

```
/DATA/AppData/eclipse-mosquitto/mosquitto/config/mosquitto.conf
```

Content:

```
# This allows local connections
listener 1883
allow_anonymous true

listener 9001
protocol websockets

password_file /mosquitto/config/pwfile

persistence true
persistence_location /mosquitto/data

log_type all
```

> This config supports both raw MQTT (1883) and WebSockets (9001).

### 3. Start Mosquitto (terminal method)

This avoids CasaOS GUI bugs.

```
docker run -d \
  --name mosquitto-final \
  --restart always \
  -p 1883:1883 \
  -p 9001:9001 \
  -v /DATA/AppData/eclipse-mosquitto/mosquitto/config:/mosquitto/config \
  -v /DATA/AppData/eclipse-mosquitto/mosquitto/data:/mosquitto/data \
  -v /DATA/AppData/eclipse-mosquitto/mosquitto/log:/mosquitto/log \
  eclipse-mosquitto:latest
```

### 4. Verify broker

```
docker logs mosquitto-final
```

You should see:

```
mosquitto version X running
Opening ipv4 listen socket on port 1883.
Opening ipv4 listen socket on port 9001.
```

---

## CasaOS Mosquitto Volume Fix (Important)

CasaOS sometimes breaks Mosquitto permissions and volume mapping.

Follow this repo if you hit weird issues:

```
https://github.com/hqnicolas/eclipse-mosquitto/tree/main
```

---

## Part 3 — Test Broker from Any PC

Terminal 1:

```
mosquitto_sub -h HOMELAB_IP -t "test/topic" -v
```

Terminal 2:

```
mosquitto_pub -h HOMELAB_IP -t "test/topic" -m "IT WORKS"
```

Expected output:

```
test/topic IT WORKS
```

---

## Part 4 — MQTTX Web (Browser GUI)

Run MQTTX Web:

```
docker run -d \
  --name mqttx-web \
  -p 8081:80 \
  emqx/mqttx-web:latest
```

Open browser:

```
http://HOMELAB_IP:8081
```

### MQTTX Connection Settings

- Name: CasaOS
- Protocol: ws://
- Host: HOMELAB_IP
- Port: 9001
- Path: /mqtt
- Username: (empty)
- Password: (empty)
- SSL: Off

Connect.

Subscribe:

```
#
```

You will now see all topics.

---

## Part 5 — Smart Plug Publishing

Your script publishes JSON:

```
{"voltage":X,"current":Y,"power":Z}
```

Topic example:

```
home/smartplug/status
```

You should now see live messages in MQTTX Web.

---

## Notes

- No authentication (local network only)
- Very low CPU usage
- Works on 8MB flash devices
- mosquitto-client-nossl is used to save space

---

If something breaks, check:

- `mosquitto_pub --help` on the plug
- `docker logs mosquitto-final` on homelab
- Firewall ports 1883 / 9001

---


