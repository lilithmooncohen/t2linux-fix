#!/bin/bash


# 1. Load BCE first
/usr/sbin/modprobe apple-bce
# 2. Wait for BCE to initialize (up to 15s, then fail with message)
/usr/local/bin/t2linux-wait-apple-bce.sh
# 3. Load WiFi driver and plugin
/usr/sbin/modprobe brcmfmac
/usr/sbin/modprobe brcmfmac_wcc
# 4. Restore keyboard backlight on resume
/usr/local/bin/t2linux-enable-kbd-backlight.sh
# 5. Activate WiFi again
/usr/bin/nmcli radio wifi on
# 6. Final WiFi check (after 5s) and retry modprobe if needed
/bin/sh -c 'sleep 5; if ! ls /sys/bus/pci/drivers/brcmfmac/*:* >/dev/null 2>&1; then modprobe -r brcmfmac 2>/dev/null || true; modprobe brcmfmac 2>/dev/null || true; modprobe brcmfmac_wcc 2>/dev/null || true; fi'
