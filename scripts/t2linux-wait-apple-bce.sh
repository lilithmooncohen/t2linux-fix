#!/bin/bash

set -e

# Configuration
readonly TIMEOUT_SECONDS=30
readonly POLL_INTERVAL=0.5
readonly BCE_DRIVER_PATH="/sys/bus/pci/drivers/apple-bce"
readonly LOG_TAG="t2linux-suspend-fix"

# Check if apple-bce driver has bound to a device
check_apple_bce() {
    # Check if driver path exists and has at least one device binding
    [ -d "${BCE_DRIVER_PATH}" ] || return 1
    compgen -G "${BCE_DRIVER_PATH}/*:*" >/dev/null 2>&1
}

# Send desktop notification to active user session
send_notification() {
    local message=$1

    command -v notify-send >/dev/null 2>&1 || return 1
    command -v loginctl >/dev/null 2>&1 || return 1

    # Find active graphical session
    local session_info
    session_info=$(loginctl list-sessions --no-legend 2>/dev/null | grep -E '^\s*\S+\s+\S+\s+\S+' | head -n1) || return 1

    [ -z "$session_info" ] && return 1

    local uid
    uid=$(echo "$session_info" | awk '{print $3}')

    [ -z "$uid" ] && return 1
    [ ! -S "/run/user/$uid/bus" ] && return 1

    XDG_RUNTIME_DIR="/run/user/$uid" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    sudo -u "#$uid" notify-send "Suspend Fix" "$message" 2>/dev/null || true

    return 0
}

# Main polling loop
main() {
    local iterations=$((TIMEOUT_SECONDS * 2))  # Poll twice per second
    local count=0

    while [ $count -lt $iterations ]; do
        check_apple_bce && exit 0
        sleep "$POLL_INTERVAL"
        ((count++))
    done

    # Timeout reached - log and notify
    local error_msg="apple-bce did not start within ${TIMEOUT_SECONDS}s - resume aborted"

    logger -t "$LOG_TAG" "$error_msg" 2>/dev/null || echo "$error_msg" >&2
    send_notification "$error_msg"

    exit 1
}

main
