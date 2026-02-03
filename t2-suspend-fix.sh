#!/bin/bash

# T2 MacBook Suspend Fix Installer
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

# Detect distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID="$ID"
    DISTRO_ID_LIKE="$ID_LIKE"
else
    echo -e "${RED}Error: Cannot detect distribution.${NC}"
    exit 1
fi

# Determine which bootloader configuration method to use
USE_GRUBBY=false
USE_GRUB_MKCONFIG=false

if command -v grubby &> /dev/null; then
    USE_GRUBBY=true
    echo -e "${GREEN}Detected Fedora/RHEL-based system (using grubby)${NC}"
elif [[ "$DISTRO_ID" == "ubuntu" ]] || [[ "$DISTRO_ID" == "debian" ]] || [[ "$DISTRO_ID_LIKE" == *"debian"* ]] || [[ "$DISTRO_ID_LIKE" == *"ubuntu"* ]]; then
    USE_GRUB_MKCONFIG=true
    echo -e "${GREEN}Detected Debian/Ubuntu-based system (using GRUB)${NC}"
else
    echo -e "${YELLOW}Warning: Unknown distribution. Will attempt GRUB configuration.${NC}"
    USE_GRUB_MKCONFIG=true
fi

# Detect WiFi PCI bus ID
echo -e "\n${YELLOW}⚙${NC} Detecting Broadcom WiFi card..."
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
echo -e "\n${YELLOW}⚙${NC} Removing prior systemd fixes (if any)..."
sudo systemctl disable suspend-fix-t2.service 2>/dev/null || true
sudo systemctl daemon-reload
sudo rm -f /etc/systemd/system/suspend-fix-t2.service
echo -e "${GREEN}Done${NC}"

# Create systemd service that calls a script to reload the KBD backlight on boot and on resume
echo -e "\n${YELLOW}⚙${NC} Creating KBD reload service..."
sudo tee /etc/systemd/system/fix-kbd-backlight.service > /dev/null << 'EOF'
[Unit]
Description=Fix Apple BCE Keyboard Backlight
After=multi-user.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target

[Service]
Type=oneshot
ExecStart=/usr/bin/bash /usr/local/bin/fix-kbd-backlight.sh
User=root
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
EOF
echo -e "${GREEN}Done${NC}"

# Create script that reloads the keyboard backlight when systemd calls it
echo -e "\n${YELLOW}⚙${NC} Creating keyboard backlight script..."
sudo tee /usr/local/bin/fix-kbd-backlight.sh > /dev/null << 'EOF'
#!/bin/sh
# Keyboard backlight fix for apple-bce after resume

KBD_PATH="/sys/class/leds/:white:kbd_backlight/brightness"

if [ -f "$KBD_PATH" ]; then
    echo 1000 > "$KBD_PATH" 2>/dev/null || true
else
    # Driver reset if path is missing
    rmmod -f apple-bce 2>/dev/null || true
    sleep 2
    modprobe apple-bce
    sleep 2
    if [ -f "$KBD_PATH" ]; then
        echo 1000 > "$KBD_PATH" 2>/dev/null || true
    fi
fi
EOF
sudo chmod +x /usr/local/bin/fix-kbd-backlight.sh
echo -e "${GREEN}Done${NC}"

# Create WiFi unload service
echo -e "\n${YELLOW}⚙${NC} Creating WiFi unload service..."
sudo tee /etc/systemd/system/suspend-wifi-unload.service > /dev/null << EOF
[Unit]
Description=Aggressive WiFi Unload Before Suspend
Before=sleep.target
StopWhenUnneeded=yes

[Service]
Type=oneshot
# 1. Deactivate WiFi interface
ExecStart=-/usr/bin/nmcli radio wifi off
# 2. Unload drivers (wcc first!)
ExecStart=-/usr/sbin/modprobe -r brcmfmac_wcc
ExecStart=-/usr/sbin/modprobe -r brcmfmac
# 3. Hard unbind of PCI-ID
ExecStart=-/bin/sh -c 'echo "${WIFI_PCI_FULL}" > /sys/bus/pci/drivers/brcmfmac/unbind'
# 4. Apple BCE removal
ExecStart=-/usr/sbin/rmmod -f apple-bce
# 5. Remove PCI device completely from bus
ExecStart=-/bin/sh -c 'echo 1 > /sys/bus/pci/devices/${WIFI_PCI_FULL}/remove'

[Install]
WantedBy=sleep.target
EOF
echo -e "${GREEN}Done${NC}"

# Create service that reloads WiFi after resume
echo -e "\n${YELLOW}⚙${NC} Creating WiFi reload service..."
sudo tee /etc/systemd/system/resume-wifi-reload.service > /dev/null << EOF
[Unit]
Description=WiFi and BCE Reload After Resume
After=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target

[Service]
Type=oneshot
# 1. Rescan PCI bus to find device again
ExecStart=/bin/sh -c 'echo 1 > /sys/bus/pci/rescan'
# 2. Wait for device to appear
ExecStart=/bin/sleep 3
# 3. Load BCE first
ExecStart=/usr/sbin/modprobe apple-bce
# 4. Wait for BCE to initialize
ExecStart=/bin/sleep 1
# 5. Force PCI-Bind (may fail, that's ok)
ExecStart=-/bin/sh -c 'echo "${WIFI_PCI_FULL}" > /sys/bus/pci/drivers/brcmfmac/bind'
# 6. Load driver
ExecStart=/usr/sbin/modprobe brcmfmac
# 7. Wait for driver initialization
ExecStart=/bin/sleep 2
# 8. Activate WiFi again
ExecStartPost=-/usr/bin/nmcli radio wifi on
# 9. Activate keyboard backlight (needed for A2252)
ExecStart=-/bin/sh -c 'echo 1000 > /sys/class/leds/:white:kbd_backlight/brightness'

[Install]
WantedBy=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
EOF
echo -e "${GREEN}Done${NC}"

# Activate services
echo -e "\n${YELLOW}⚙${NC} Activating services..."
sudo systemctl daemon-reload
sudo systemctl enable suspend-wifi-unload.service
sudo systemctl enable resume-wifi-reload.service
sudo systemctl enable fix-kbd-backlight.service 
echo -e "${GREEN}Done${NC}"

# Configure deep suspend mode based on distribution
echo -e "\n${YELLOW}⚙${NC} Configuring deep suspend mode..."

if [ "$USE_GRUBBY" = true ]; then
    # Fedora/RHEL using grubby
    sudo grubby --update-kernel=ALL --args="mem_sleep_default=deep"
    echo -e "${GREEN}Done (using grubby)${NC}"
elif [ "$USE_GRUB_MKCONFIG" = true ]; then
    # Debian/Ubuntu using GRUB
    GRUB_CONFIG="/etc/default/grub"
    
    if [ -f "$GRUB_CONFIG" ]; then
        # Check if mem_sleep_default is already set
        if grep -q "mem_sleep_default=deep" "$GRUB_CONFIG"; then
            echo -e "${GREEN}mem_sleep_default=deep already configured${NC}"
        else
            # Add or update GRUB_CMDLINE_LINUX_DEFAULT
            if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" "$GRUB_CONFIG"; then
                # Append to existing line
                sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 mem_sleep_default=deep"/' "$GRUB_CONFIG"
            else
                # Add new line
                echo 'GRUB_CMDLINE_LINUX_DEFAULT="mem_sleep_default=deep"' | sudo tee -a "$GRUB_CONFIG" > /dev/null
            fi
            
            # Update GRUB
            sudo update-grub
            echo -e "${GREEN}Done (using GRUB)${NC}"
        fi
    else
        echo -e "${YELLOW}Warning: GRUB config not found, skipping kernel parameters${NC}"
    fi
fi

# Disable thermald if present
echo -e "\n${YELLOW}⚙${NC} Checking for thermald..."
if systemctl is-enabled thermald &>/dev/null; then
    echo "  - Disabling thermald..."
    sudo systemctl disable --now thermald
    echo -e "${GREEN}Done${NC}"
else
    echo -e "${GREEN}thermald not found or not enabled${NC}"
fi

# Set ASPM to default
echo -e "\n${YELLOW}⚙${NC} Setting ASPM to default..."

if [ "$USE_GRUBBY" = true ]; then
    if sudo grubby --info=ALL | grep -q "pcie_aspm=off"; then
        echo "  - Changing pcie_aspm from off to default..."
        sudo grubby --update-kernel=ALL --remove-args="pcie_aspm=off" --args="pcie_aspm=default"
        echo -e "${GREEN}Done${NC}"
    else
        echo -e "${GREEN}pcie_aspm already correct${NC}"
    fi
elif [ "$USE_GRUB_MKCONFIG" = true ]; then
    GRUB_CONFIG="/etc/default/grub"
    if [ -f "$GRUB_CONFIG" ]; then
        if grep -q "pcie_aspm=off" "$GRUB_CONFIG"; then
            echo "  - Removing pcie_aspm=off and adding pcie_aspm=default..."
            sudo sed -i 's/pcie_aspm=off/pcie_aspm=default/g' "$GRUB_CONFIG"
            sudo update-grub
            echo -e "${GREEN}Done${NC}"
        else
            echo -e "${GREEN}pcie_aspm already correct${NC}"
        fi
    fi
fi

# Remove override.conf
echo -e "\n${YELLOW}⚙${NC} Removing override.conf..."
if [ -f /etc/systemd/system/systemd-suspend.service.d/override.conf ]; then
    echo "  - Removing systemd-suspend override.conf..."
    sudo rm /etc/systemd/system/systemd-suspend.service.d/override.conf
    sudo systemctl daemon-reload
    echo -e "${GREEN}Done${NC}"
else
    echo -e "${GREEN}No override.conf found${NC}"
fi

# Summary
echo -e "\n${GREEN}=== Installation Complete ===${NC}\n"
echo "WiFi PCI Bus ID: ${WIFI_PCI_FULL}"
echo "Distribution: $DISTRO_ID"
echo ""
echo -e "${YELLOW}IMPORTANT NOTES:${NC}"
echo "1. You must reboot for changes to take effect"
echo "2. Suspend by closing the lid! After resume, wait 3-5 seconds for WiFi and keyboard backlight to come back"
echo "3. This is normal behavior and not a malfunction"
echo ""
read -p "Reboot now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo reboot
fi
