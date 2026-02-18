#!/bin/bash

set -e

T2LINUX_KBD_BACKLIGHT_BRIGHTNESS_PATH="/sys/class/leds/:white:kbd_backlight/brightness"

if [ -f "$T2LINUX_KBD_BACKLIGHT_BRIGHTNESS_PATH" ]; then
    set -e
    echo 0 > "${T2LINUX_KBD_BACKLIGHT_BRIGHTNESS_PATH}" 2>/dev/null || true
fi
