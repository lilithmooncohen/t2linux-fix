#!/bin/bash

# T2 MacBook Suspend Fix Installer
# Automatically detects WiFi PCI bus ID and configures s2idle suspend
# Use at your own risk!
# André Eikmeyer, Reken, Germany - 02/02/2026

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== T2 MacBook Suspend Fix Installer ===${NC}\n"

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
    echo -e "${RED}Error: Do not run this script as root. It will use sudo when needed.${NC}"
    exit 1
fi

# Detect WiFi PCI bus ID
echo -e "${YELLOW}${NC} Detecting Broadcom WiFi card..."
WIFI_PCI=$(lspci -nn | grep -i "broadcom.*bcm43" | grep -oP '^\S+')

if [ -z "$WIFI_PCI" ]; then
    echo -e "${RED}Error: Could not find Broadcom WiFi card. This script is for T2 MacBooks only.${NC}"
    exit 1
fi

WIFI_PCI_FULL="0000:${WIFI_PCI}"
echo -e "${GREEN}Found WiFi at PCI bus: ${WIFI_PCI_FULL}${NC}\n"

# Confirm with user
read -p "Continue with installation? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

# Remove prior systemd fixes
echo -e "\n${YELLOW}${NC} Removing prior systemd fixes (if any)..."
sudo systemctl disable suspend-fix-t2.service 2>/dev/null || true
sudo systemctl daemon-reload
sudo rm -f /etc/systemd/system/suspend-fix-t2.service
echo -e "${GREEN}Done${NC}"

# Create systemd service that calls a script to reload the KBD backlight on boot and on resume
echo -e "\n${YELLOW}${NC} Creating KBD reload service..."
sudo tee /etc/systemd/system/fix-kbd-backlight.service > /dev/null << EOF

[Unit]
Description=Fix Apple BCE Keyboard Backlight
After=multi-user.target suspend.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/fix-kbd-backlight.sh
RemainAfterExit=yes

[Install]
WantedBy=graphical.target suspend.target

EOF
echo -e "${GREEN}Done${NC}"

# Create script that reloads the keyboard backlight when systemd calls it
echo -e "\n${YELLOW}${NC} Creating keyboard backlight script..."
sudo tee /usr/local/bin/fix-kbd-backlight.sh > /dev/null << 'EOF'
#!/bin/sh
# Keyboard-backlight-check and apple-bce reload on boot

sleep 4

KBD_PATH="/sys/class/leds/:white:kbd_backlight/brightness"

if [ -f "$KBD_PATH" ]; then
    echo 1000 > "$KBD_PATH"
else
    # Driver reset if path is missing
    rmmod -f apple-bce
    sleep 2
    modprobe apple-bce
    sleep 2
    if [ -f "$KBD_PATH" ]; then
        echo 1000 > "$KBD_PATH"
    fi
fi
EOF
sudo chmod +x /usr/local/bin/fix-kbd-backlight.sh
echo -e "${GREEN}Done${NC}"

# Create WiFi unload service
echo -e "\n${YELLOW}${NC} Creating WiFi unload service..."
sudo tee /etc/systemd/system/suspend-wifi-unload.service > /dev/null << EOF
[Unit]
Description=Aggressive WiFi Unload
Before=sleep.target
StopWhenUnneeded=yes

[Service]
Type=oneshot
# 1. Deactivate WiFi interface
ExecStartPre=-/usr/sbin/nmcli radio wifi off
# 2. Unload drivers (wcc first!)
ExecStart=/usr/sbin/modprobe -r brcmfmac_wcc
ExecStart=/usr/sbin/modprobe -r brcmfmac
# 3. Hard unbind of PCI-ID
ExecStart=-/bin/sh -c 'echo "${WIFI_PCI_FULL}" > /sys/bus/pci/drivers/brcmfmac/unbind'
# 4. Apple BCE removal
ExecStart=/usr/sbin/rmmod -f apple-bce

[Install]
WantedBy=sleep.target
EOF
echo -e "${GREEN}Done${NC}"

# Create service that reloads WiFi on login screen after resume
echo -e "\n${YELLOW}${NC} Creating WiFi reload service..."
sudo tee /etc/systemd/system/resume-wifi-reload.service > /dev/null << EOF
[Unit]
Description=WiFi and BCE Reload
After=suspend.target

[Service]
Type=oneshot
# 1. Load BCE first
ExecStart=/usr/sbin/modprobe apple-bce
# 2. Force PCI-Bind
ExecStart=-/bin/sh -c 'echo "${WIFI_PCI_FULL}" > /sys/bus/pci/drivers/brcmfmac/bind'
# 3. Load driver
ExecStart=/usr/sbin/modprobe brcmfmac
# 4. Activate WiFi again
ExecStartPost=-/usr/sbin/nmcli radio wifi on

[Install]
WantedBy=suspend.target
EOF
echo -e "${GREEN}Done${NC}"

# Activate services
echo -e "\n${YELLOW}${NC} Activating services..."
sudo systemctl daemon-reload
sudo systemctl enable suspend-wifi-unload.service
sudo systemctl enable resume-wifi-reload.service
sudo systemctl enable fix-kbd-backlight.service 
sudo systemctl start suspend-wifi-unload.service
sudo systemctl start resume-wifi-reload.service
sudo systemctl start fix-kbd-backlight.service 
echo -e "${GREEN}Done${NC}"

# Make sure we use deep sleep
echo -e "\n${YELLOW}${NC} Configuring deep suspend mode..."
sudo grubby --update-kernel=ALL --args="mem_sleep_default=deep"
echo -e "${GREEN}Done${NC}"

# The following will remove/disable services that mess with suspend

# Disable thermald
echo -e "\n${YELLOW}${NC} Disabling thermald..."
if systemctl is-enabled thermald &>/dev/null; then
    echo "  - Disabling thermald..."
    sudo systemctl disable --now thermald
    echo -e "${GREEN}Done${NC}"
fi

# Set ASPM to default
echo -e "\n${YELLOW}${NC} Setting ASPM to default..."
if sudo grubby --info=ALL | grep -q "pcie_aspm=off"; then
    echo "  - Changing pcie_aspm from off to default..."
    sudo grubby --update-kernel=ALL --remove-args="pcie_aspm=off" --args="pcie_aspm=default"
    echo -e "${GREEN}Done${NC}"
fi

# Remove override.conf
echo -e "\n${YELLOW}${NC} Removing override.conf..."
if [ -f /etc/systemd/system/systemd-suspend.service.d/override.conf ]; then
    echo "  - Removing systemd-suspend override.conf..."
    sudo rm /etc/systemd/system/systemd-suspend.service.d/override.conf
    sudo systemctl daemon-reload
    echo -e "${GREEN}Done${NC}"
fi

# Summary
echo -e "\n${GREEN}=== Installation Complete ===${NC}\n"
echo "WiFi PCI Bus ID: ${WIFI_PCI_FULL}"
echo -e "\n${YELLOW}IMPORTANT: You must reboot for changes to take effect!${NC}"
read -p "Reboot now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo reboot
fi
