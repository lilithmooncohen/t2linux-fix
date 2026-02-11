#!/bin/bash

set -e

T2LINUX_CONF_DIR="/etc/t2linux"
T2LINUX_KBD_BACKLIGHT_BRIGHTNESS_PATH="/sys/class/leds/:white:kbd_backlight/brightness"
T2LINUX_KBD_BACKLIGHT_BRIGHTNESS_BACKUP_PATH="${T2LINUX_CONF_DIR}/kbd_backlight_brightness"

if [ -f "$T2LINUX_KBD_BACKLIGHT_BRIGHTNESS_PATH" ]; then
    set -e
    mkdir -p "${T2LINUX_CONF_DIR}"
    cat  "${T2LINUX_KBD_BACKLIGHT_BRIGHTNESS_PATH}" > "${T2LINUX_KBD_BACKLIGHT_BRIGHTNESS_BACKUP_PATH}" 2>/dev/null || true
    echo 0 > "${T2LINUX_KBD_BACKLIGHT_BRIGHTNESS_PATH}" 2>/dev/null || true
fi
