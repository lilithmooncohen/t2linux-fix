#!/bin/bash

# 1. Backlight off before suspend
/usr/local/bin/t2linux-disable-kbd-backlight.sh
# 2. Deactivate WiFi interface
/usr/bin/nmcli radio wifi off
# 3. Unload WiFi plugin and driver
#/usr/sbin/modprobe -r brcmfmac_wcc
#/usr/sbin/modprobe -r brcmfmac
# 4. Apple BCE removal
/usr/sbin/rmmod -f apple-bce
