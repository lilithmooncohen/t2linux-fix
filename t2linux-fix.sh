#!/bin/bash

# T2 MacBook Suspend Fix Installer
# Use at your own risk!
# André Eikmeyer, Reken, Germany - 2026-02-05

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
VERSION="1.4.0"

T2LINUX_CONF_DIR="/etc/t2linux"
THERMALD_STATE_FILE="${T2LINUX_CONF_DIR}/thermald_enabled"
GRUB_BACKUP="${T2LINUX_CONF_DIR}/grub.bak"
OVERRIDE_BACKUP="${T2LINUX_CONF_DIR}/override.conf.bak"
GRUBBY_STATE_FILE="${T2LINUX_CONF_DIR}/grubby_state"
WAKEUP_BACKUP="${T2LINUX_CONF_DIR}/acpi_wakeup.bak"

ensure_libnotify() {
    if command -v notify-send >/dev/null 2>&1; then
        echo -e "${GREEN}libnotify already installed (notify-send found)${NC}"
        return 0
    fi
    echo -e "${YELLOW}Installing libnotify (notify-send not found)...${NC}"
    if command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y libnotify
    elif command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y libnotify-bin
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -Sy --noconfirm libnotify
    else
        echo -e "${YELLOW}Warning: No supported package manager found. Please install libnotify manually.${NC}"
        return 1
    fi
}

capture_acpi_wakeup_state() {
    sudo mkdir -p "$T2LINUX_CONF_DIR"
    sudo sh -c "cat /proc/acpi/wakeup > '$WAKEUP_BACKUP'"
}

enable_all_s3_wakeup() {
    while read -r dev sstate status _; do
        [ "$dev" = "Device" ] && continue
        [ "$sstate" != "S3" ] && continue
        if [ "$status" = "*disabled" ]; then
            sudo sh -c "echo $dev > /proc/acpi/wakeup"
        fi
    done < /proc/acpi/wakeup
}

restore_acpi_wakeup_state() {
    [ -f "$WAKEUP_BACKUP" ] || return 0
    while read -r dev _ desired_status _; do
        [ "$dev" = "Device" ] && continue
        current_status=$(awk -v d="$dev" '$1==d {print $3}' /proc/acpi/wakeup)
        [ -z "$current_status" ] && continue
        if [ "$current_status" != "$desired_status" ]; then
            sudo sh -c "echo $dev > /proc/acpi/wakeup"
        fi
    done < "$WAKEUP_BACKUP"
}

echo -e "${GREEN}=== T2 MacBook Suspend Fix Installer v${VERSION} ===${NC}\n"

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

MODE="install"
echo -e "${YELLOW}Select action:${NC}"
echo "1) Install"
echo "2) Uninstall"
read -p "Choose [1-2]: " -n 1 -r
echo
if [[ $REPLY =~ ^[2]$ ]]; then
    MODE="uninstall"
elif [[ $REPLY =~ ^[1]$ ]]; then
    MODE="install"
else
    echo -e "${RED}Invalid selection.${NC}"
    exit 1
fi

if [ "$MODE" = "uninstall" ]; then
    echo -e "${YELLOW}⚙${NC} Uninstalling and restoring backups..."

    # Disable and remove (previous) fixes
    echo "  - Disabling services..."
    # Disable services from services/ directory
    for service_file in services/*.service; do
        if [ -f "$service_file" ]; then
            service_name=$(basename "$service_file")
            sudo systemctl disable "$service_name" 2>/dev/null || true
        fi
    done
    # Detect and disable any t2linux-*.service from systemd
    for service in $(systemctl list-unit-files 't2linux-*.service' --no-legend 2>/dev/null | awk '{print $1}'); do
        sudo systemctl disable "$service" 2>/dev/null || true
    done
    # Also disable old services from previous versions
    sudo systemctl disable suspend-fix-t2.service 2>/dev/null || true
    sudo systemctl disable suspend-wifi-unload.service 2>/dev/null || true
    sudo systemctl disable resume-wifi-reload.service 2>/dev/null || true
    sudo systemctl disable fix-kbd-backlight.service 2>/dev/null || true
    sudo systemctl disable suspend-amdgpu-unbind.service 2>/dev/null || true
    sudo systemctl disable resume-amdgpu-bind.service 2>/dev/null || true
    echo "  - Services disabled."

    echo "  - Removing unit files and scripts..."
    sudo rm -f /etc/systemd/system/t2linux-*.service
    sudo rm -f /usr/local/bin/t2linux-*.sh
    echo "  - Removing old unit files and scripts from previous versions..."
    sudo rm -f /etc/systemd/system/suspend-fix-t2.service
    sudo rm -f /etc/systemd/system/suspend-wifi-unload.service
    sudo rm -f /etc/systemd/system/resume-wifi-reload.service
    sudo rm -f /etc/systemd/system/fix-kbd-backlight.service
    sudo rm -f /etc/systemd/system/suspend-amdgpu-unbind.service
    sudo rm -f /etc/systemd/system/resume-amdgpu-bind.service
    sudo rm -f /usr/local/bin/t2-wait-apple-bce.sh
    sudo rm -f /usr/local/bin/t2-wait-brcmfmac.sh
    sudo rm -f /usr/local/bin/fix-kbd-backlight.sh
    sudo rm -f /usr/lib/systemd/system-sleep/t2-resync
    sudo rm -f /usr/lib/systemd/system-sleep/90-t2-hibernate-test-brcmfmac.sh
    echo "  - Unit files and scripts removed."

    # Restore override.conf if backed up
    if [ -f "$OVERRIDE_BACKUP" ]; then
        echo "  - Restoring override.conf..."
        sudo mkdir -p /etc/systemd/system/systemd-suspend.service.d
        sudo cp "$OVERRIDE_BACKUP" /etc/systemd/system/systemd-suspend.service.d/override.conf
        echo "  - override.conf restored."
    else
        echo "  - No override.conf backup found. Skipping restore."
    fi

    GRUB_RESTORED=false

    # Restore GRUB config if backed up
    if [ -f "$GRUB_BACKUP" ]; then
        echo "  - Restoring /etc/default/grub..."
        sudo cp "$GRUB_BACKUP" /etc/default/grub
        GRUB_RESTORED=true
        echo "  - GRUB config restored."
    else
        echo "  - No GRUB backup found. Skipping /etc/default/grub restore."
    fi

    # Restore grubby changes if recorded
    if command -v grubby &> /dev/null && [ -f "$GRUBBY_STATE_FILE" ]; then
        if grep -q "^mem_sleep_added=1" "$GRUBBY_STATE_FILE"; then
            sudo grubby --update-kernel=ALL --remove-args="mem_sleep_default=deep"
        fi
        if grep -q "^pcie_aspm_was_off=1" "$GRUBBY_STATE_FILE"; then
            sudo grubby --update-kernel=ALL --remove-args="pcie_aspm=default" --args="pcie_aspm=off"
        fi
        echo "  - grubby changes restored."
    else
        echo "  - No grubby state found. Skipping grubby restore."
    fi

    # Restore thermald if it was enabled
    if [ -f "$THERMALD_STATE_FILE" ]; then
        if grep -q "^enabled=1" "$THERMALD_STATE_FILE"; then
            echo "  - Re-enabling thermald..."
            sudo systemctl enable --now thermald || true
            echo "  - thermald re-enabled."
        else
            echo "  - thermald was not enabled before. Skipping."
        fi
    else
        echo "  - No thermald state file found. Skipping."
    fi

    # Restore ACPI wake sources
    if [ -f "$WAKEUP_BACKUP" ]; then
        echo "  - Restoring ACPI wake sources..."
        restore_acpi_wakeup_state
        echo "  - ACPI wake sources restored."
    else
        echo "  - No ACPI wake backup found. Skipping."
    fi

    # Update GRUB if possible after restore
    if [ "$GRUB_RESTORED" = true ]; then
        echo "  - Updating GRUB..."
        if command -v update-grub &> /dev/null; then
            sudo update-grub
        elif command -v grub-mkconfig &> /dev/null; then
            if [ -f /boot/grub/grub.cfg ]; then
                sudo grub-mkconfig -o /boot/grub/grub.cfg
            fi
        fi
        echo "  - GRUB update complete."
    fi

    echo "  - Reloading systemd..."
    sudo systemctl daemon-reload
    echo -e "${GREEN}Uninstall complete.${NC}"
    exit 0
fi

# Determine which bootloader configuration method to use
USE_GRUBBY=false
USE_GRUB_MKCONFIG=false
USE_GRUB_MKCONFIG_ARCH=false
USE_REFIND=false

if command -v grubby &> /dev/null; then
    USE_GRUBBY=true
    echo -e "${GREEN}Detected Fedora/RHEL-based system (using grubby)${NC}"
elif [[ "$DISTRO_ID" == "ubuntu" ]] || [[ "$DISTRO_ID" == "debian" ]] || [[ "$DISTRO_ID_LIKE" == *"debian"* ]] || [[ "$DISTRO_ID_LIKE" == *"ubuntu"* ]]; then
    USE_GRUB_MKCONFIG=true
    echo -e "${GREEN}Detected Debian/Ubuntu-based system (using GRUB)${NC}"
elif [[ "$DISTRO_ID" == "arch" ]] || [[ "$DISTRO_ID_LIKE" == *"arch"* ]]; then
    USE_GRUB_MKCONFIG_ARCH=true
    echo -e "${GREEN}Detected Arch-based system (using grub-mkconfig)${NC}"
else
    echo -e "${YELLOW}Warning: Unknown distribution. Will attempt GRUB configuration.${NC}"
    USE_GRUB_MKCONFIG=true
fi

if [ -d /boot/efi/EFI/refind ] || [ -f /boot/efi/EFI/refind/refind.conf ] || [ -f /boot/refind_linux.conf ]; then
    USE_REFIND=true
    echo -e "${YELLOW}Warning: rEFInd detected. Kernel parameters in GRUB may not be used.${NC}"
fi

# Confirm with user
read -p "Continue with installation? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

# Ensure libnotify is available for desktop notifications
ensure_libnotify || true

# Remove prior systemd fixes
echo -e "\n${YELLOW}⚙${NC} Removing prior systemd fixes (if any)..."
echo "  - Disabling old services..."
# Detect and disable any t2linux-*.service from systemd
for service in $(systemctl list-unit-files 't2linux-*.service' --no-legend 2>/dev/null | awk '{print $1}'); do
    sudo systemctl disable "$service" 2>/dev/null || true
done
# Also disable old services from previous versions
sudo systemctl disable suspend-fix-t2.service 2>/dev/null || true
sudo systemctl disable suspend-wifi-unload.service 2>/dev/null || true
sudo systemctl disable resume-wifi-reload.service 2>/dev/null || true
sudo systemctl disable fix-kbd-backlight.service 2>/dev/null || true
echo "  - Old services disabled."

echo "  - Removing old unit files..."
sudo rm -f /etc/systemd/system/suspend-wifi-unload.service
sudo rm -f /etc/systemd/system/resume-wifi-reload.service
sudo rm -f /etc/systemd/system/fix-kbd-backlight.service
sudo rm -f /etc/systemd/system/suspend-fix-t2.service
sudo rm -f /usr/lib/systemd/system-sleep/t2-resync
sudo rm -f /usr/lib/systemd/system-sleep/90-t2-hibernate-test-brcmfmac.sh
echo "  - Old unit files removed."

# Enable all S3 wake sources (backup current state first)
echo -e "\n${YELLOW}⚙${NC} Enabling all S3 wake sources..."
capture_acpi_wakeup_state
enable_all_s3_wakeup
sudo systemctl daemon-reload
echo -e "${GREEN}Done${NC}"

# Create scripts
echo -e "\n${YELLOW}⚙${NC} Creating keyboard backlight script..."
sudo cp scripts/t2linux-*.sh /usr/local/bin/
echo -e "${GREEN}Done${NC}"

# Create systemd services
echo -e "\n${YELLOW}⚙${NC} Creating services..."
sudo cp services/t2linux-*.service /etc/systemd/system/
echo -e "${GREEN}Done${NC}"

# Activate services
echo -e "\n${YELLOW}⚙${NC} Activating services..."
sudo systemctl daemon-reload
# Detect and enable any t2linux-*.service from systemd
for service in $(systemctl list-unit-files 't2linux-*.service' --no-legend 2>/dev/null | awk '{print $1}'); do
    sudo systemctl enable "$service" 2>/dev/null || true
done
echo -e "${GREEN}Done${NC}"

# Configure deep suspend mode based on distribution
echo -e "\n${YELLOW}⚙${NC} Configuring deep suspend mode..."

if [ "$USE_GRUBBY" = true ]; then
    # Fedora/RHEL using grubby
    if sudo grubby --info=ALL | grep -q "mem_sleep_default=deep"; then
        echo -e "${GREEN}mem_sleep_default=deep already configured${NC}"
    else
        sudo mkdir -p "$T2LINUX_CONF_DIR"
        sudo grubby --update-kernel=ALL --args="mem_sleep_default=deep"
        echo "mem_sleep_added=1" | sudo tee -a "$GRUBBY_STATE_FILE" > /dev/null
        echo -e "${GREEN}Done (using grubby)${NC}"
    fi
elif [ "$USE_GRUB_MKCONFIG" = true ] || [ "$USE_GRUB_MKCONFIG_ARCH" = true ]; then
    # Debian/Ubuntu/Arch using GRUB
    GRUB_CONFIG="/etc/default/grub"

    if [ -f "$GRUB_CONFIG" ]; then
        # Backup GRUB config once
        if [ ! -f "$GRUB_BACKUP" ]; then
            sudo mkdir -p "$T2LINUX_CONF_DIR"
            sudo cp "$GRUB_CONFIG" "$GRUB_BACKUP"
            echo "  - Backed up GRUB config to $GRUB_BACKUP"
        fi
        # Check if mem_sleep_default is already set
        if grep -q "mem_sleep_default=deep" "$GRUB_CONFIG"; then
            echo -e "${GREEN}mem_sleep_default=deep already configured${NC}"
        else
            # Add or update GRUB_CMDLINE_LINUX_DEFAULT or GRUB_CMDLINE_LINUX
            if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" "$GRUB_CONFIG"; then
                sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 mem_sleep_default=deep"/' "$GRUB_CONFIG"
            elif grep -q "^GRUB_CMDLINE_LINUX=" "$GRUB_CONFIG"; then
                sudo sed -i 's/^GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 mem_sleep_default=deep"/' "$GRUB_CONFIG"
            else
                echo 'GRUB_CMDLINE_LINUX_DEFAULT="mem_sleep_default=deep"' | sudo tee -a "$GRUB_CONFIG" > /dev/null
            fi

            # Update GRUB
            if command -v update-grub &> /dev/null; then
                sudo update-grub
                echo -e "${GREEN}Done (using update-grub)${NC}"
            elif command -v grub-mkconfig &> /dev/null; then
                if [ -f /boot/grub/grub.cfg ]; then
                    sudo grub-mkconfig -o /boot/grub/grub.cfg
                    echo -e "${GREEN}Done (using grub-mkconfig)${NC}"
                else
                    echo -e "${YELLOW}Warning: /boot/grub/grub.cfg not found. Please run grub-mkconfig manually.${NC}"
                fi
            else
                echo -e "${YELLOW}Warning: No GRUB update tool found. Please update your bootloader manually.${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}Warning: GRUB config not found, skipping kernel parameters${NC}"
    fi
fi

# rEFInd note
if [ "$USE_REFIND" = true ]; then
    echo -e "\n${YELLOW}⚠ rEFInd detected:${NC}"
    echo "If you boot via rEFInd, kernel parameters from GRUB may be ignored."
    echo "Please add mem_sleep_default=deep to your rEFInd kernel options."
    echo "Common locations:"
    echo "  - /boot/refind_linux.conf"
    echo "  - /boot/efi/EFI/refind/refind.conf"
    echo ""
fi

# Disable thermald if present
echo -e "\n${YELLOW}⚙${NC} Checking for thermald..."
if systemctl is-enabled thermald &>/dev/null; then
    echo "  - Disabling thermald..."
    sudo mkdir -p "$T2LINUX_CONF_DIR"
    echo "enabled=1" | sudo tee "$THERMALD_STATE_FILE" > /dev/null
    sudo systemctl disable --now thermald
    echo -e "${GREEN}Done${NC}"
else
    sudo mkdir -p "$T2LINUX_CONF_DIR"
    echo "enabled=0" | sudo tee "$THERMALD_STATE_FILE" > /dev/null
    echo -e "${GREEN}thermald not found or not enabled${NC}"
fi

# Set ASPM to off
echo -e "\n${YELLOW}⚙${NC} Setting ASPM to off..."

if [ "$USE_GRUBBY" = true ]; then
    if sudo grubby --info=ALL | grep -q "pcie_aspm=off"; then
        echo -e "${GREEN}pcie_aspm already off${NC}"
    else
        echo "  - Setting pcie_aspm=off (removing other values)..."
        sudo mkdir -p "$T2LINUX_CONF_DIR"
        sudo grubby --update-kernel=ALL --remove-args="pcie_aspm=default pcie_aspm=force" --args="pcie_aspm=off"
        echo "pcie_aspm_was_off=0" | sudo tee -a "$GRUBBY_STATE_FILE" > /dev/null
        echo -e "${GREEN}Done${NC}"
    fi
elif [ "$USE_GRUB_MKCONFIG" = true ] || [ "$USE_GRUB_MKCONFIG_ARCH" = true ]; then
    GRUB_CONFIG="/etc/default/grub"
    if [ -f "$GRUB_CONFIG" ]; then
        # Backup GRUB config once (if not already)
        if [ ! -f "$GRUB_BACKUP" ]; then
            sudo mkdir -p "$T2LINUX_CONF_DIR"
            sudo cp "$GRUB_CONFIG" "$GRUB_BACKUP"
            echo "  - Backed up GRUB config to $GRUB_BACKUP"
        fi
        if grep -q "pcie_aspm=off" "$GRUB_CONFIG"; then
            echo -e "${GREEN}pcie_aspm already off${NC}"
        else
            echo "  - Forcing pcie_aspm=off (removing other values)..."
            sudo sed -i 's/pcie_aspm=default/pcie_aspm=off/g' "$GRUB_CONFIG"
            sudo sed -i 's/pcie_aspm=force/pcie_aspm=off/g' "$GRUB_CONFIG"
            if ! grep -q "pcie_aspm=off" "$GRUB_CONFIG"; then
                if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" "$GRUB_CONFIG"; then
                    sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 pcie_aspm=off"/' "$GRUB_CONFIG"
                elif grep -q "^GRUB_CMDLINE_LINUX=" "$GRUB_CONFIG"; then
                    sudo sed -i 's/^GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 pcie_aspm=off"/' "$GRUB_CONFIG"
                else
                    echo 'GRUB_CMDLINE_LINUX_DEFAULT="pcie_aspm=off"' | sudo tee -a "$GRUB_CONFIG" > /dev/null
                fi
            fi
            if command -v update-grub &> /dev/null; then
                sudo update-grub
                echo -e "${GREEN}Done (using update-grub)${NC}"
            elif command -v grub-mkconfig &> /dev/null; then
                if [ -f /boot/grub/grub.cfg ]; then
                    sudo grub-mkconfig -o /boot/grub/grub.cfg
                    echo -e "${GREEN}Done (using grub-mkconfig)${NC}"
                else
                    echo -e "${YELLOW}Warning: /boot/grub/grub.cfg not found. Please run grub-mkconfig manually.${NC}"
                fi
            else
                echo -e "${YELLOW}Warning: No GRUB update tool found. Please update your bootloader manually.${NC}"
            fi
        fi
    fi
fi

# rEFInd note
if [ "$USE_REFIND" = true ]; then
    echo -e "\n${YELLOW}⚠ rEFInd detected:${NC}"
    echo "If you boot via rEFInd, kernel parameters from GRUB may be ignored."
    echo "Please add pcie_aspm=off to your rEFInd kernel options."
    echo "Common locations:"
    echo "  - /boot/refind_linux.conf"
    echo "  - /boot/efi/EFI/refind/refind.conf"
    echo ""
fi

# Remove override.conf
echo -e "\n${YELLOW}⚙${NC} Checking for override.conf..."
if [ -f /etc/systemd/system/systemd-suspend.service.d/override.conf ]; then
    echo "  - Removing systemd-suspend override.conf..."
    # Backup override.conf once
    if [ ! -f "$OVERRIDE_BACKUP" ]; then
        sudo mkdir -p "$T2LINUX_CONF_DIR"
        sudo cp /etc/systemd/system/systemd-suspend.service.d/override.conf "$OVERRIDE_BACKUP"
        echo "  - Backed up override.conf to $OVERRIDE_BACKUP"
    fi
    sudo rm /etc/systemd/system/systemd-suspend.service.d/override.conf
    sudo systemctl daemon-reload
    echo -e "${GREEN}Done${NC}"
else
    echo -e "${GREEN}No override.conf found${NC}"
fi

# Summary
echo -e "\n${GREEN}=== Installation Complete ===${NC}\n"
echo ""
echo -e "${YELLOW}IMPORTANT NOTES:${NC}"
echo "Reminder: Suspend/Resume takes longer than on MacOS. This is normal behavior and not a malfunction"
echo ""
read -p "Reboot now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo reboot
fi
