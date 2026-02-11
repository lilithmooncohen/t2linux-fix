#!/bin/bash

set -e

T2LINUX_CONF_DIR="/etc/t2linux"
T2LINUX_KBD_BACKLIGHT_BRIGHTNESS_PATH="/sys/class/leds/:white:kbd_backlight/brightness"
T2LINUX_KBD_BACKLIGHT_BRIGHTNESS_BACKUP_PATH="${T2LINUX_CONF_DIR}/kbd_backlight_brightness"

# Function to set keyboard backlight brightness
set_brightness() {
    [ ! -f "${T2LINUX_KBD_BACKLIGHT_BRIGHTNESS_PATH}" ] && return 1

    if [ -f "${T2LINUX_KBD_BACKLIGHT_BRIGHTNESS_BACKUP_PATH}" ]; then
        cat "${T2LINUX_KBD_BACKLIGHT_BRIGHTNESS_BACKUP_PATH}" > "${T2LINUX_KBD_BACKLIGHT_BRIGHTNESS_PATH}" 2>/dev/null || true
    else
        echo 1000 > "${T2LINUX_KBD_BACKLIGHT_BRIGHTNESS_PATH}" 2>/dev/null
    fi
    return 0
}

# Function to poll for brightness path and set it
poll_and_set() {
    local max_iterations=$1
    local sleep_duration=$2

    for ((i=1; i<=max_iterations; i++)); do
        set_brightness && exit 0
        sleep "$sleep_duration"
    done
    return 1
}

# Wait for Apple BCE
/usr/local/bin/t2linux-wait-apple-bce.sh

# Try setting brightness immediately
set_brightness && exit 0

# Poll up to 15s before forcing a BCE reset
poll_and_set 15 1

# Additional apple-bce reset if path is still missing
rmmod -f apple-bce 2>/dev/null || true
modprobe apple-bce
/usr/local/bin/t2linux-wait-apple-bce.sh
poll_and_set 15 0.2
