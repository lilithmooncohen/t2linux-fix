# T2Linux MacBook Suspend Fix

This script configures your system to properly suspend and resume by managing the Broadcom WiFi driver and Apple BCE keyboard backlight driver. 
It automatically detects your WiFi PCI bus ID and creates systemd services to handle driver unloading before suspend and reloading after resume.
Keyboard backlight not working on boot is also taken care of.

Developed on MacBook Air A2179 with Fedora 43 (should work on Debian and Ubuntu as well)

## Important Notes

Close the lid to suspend! Don't use the power button or suspend from the menu!
The system needs a bit more time to resume than you're used to from MacOS because it needs to re-initialize all bits and pieces we turned off to be able to make it sleep. But you can try shortening delays if your system is faster or making them longer if your system is slower.
Typically you will notice a screen still black when opening the lid for a few seconds. Also the keyboard may be re-initialized while you typing your password. I recommend to just be patient and wait a few seconds or play with the "sleep" figures to make delays shorter. 

## Installation

1. Download the script:
```bash
wget https://raw.githubusercontent.com/deqrocks/T2Linux-Suspend-Fix/refs/heads/main/t2-suspend-fix.sh
chmod +x t2-suspend-fix.sh
```

2. Run the script:
```bash
./t2-suspend-fix.sh
```

3. Reboot when prompted.

## How It Works

The script performs the following actions:

1. Detects the Broadcom WiFi card PCI bus ID
2. Configures the system to use deep sleep mode
3. Creates three systemd services
4. Disables conflicting services (thermald)
5. Adjusts ASPM settings if needed

## Created Files

### Systemd Services

**`/etc/systemd/system/suspend-wifi-unload.service`**  
Runs before suspend to aggressively unload WiFi and BCE drivers:
- Deactivates WiFi interface via NetworkManager
- Unloads brcmfmac_wcc and brcmfmac modules
- Unbinds the WiFi PCI device
- Removes the apple-bce module

**`/etc/systemd/system/resume-wifi-reload.service`**  
Runs after resume to restore WiFi and BCE:
- Loads apple-bce module
- Rebinds the WiFi PCI device
- Loads brcmfmac module
- Reactivates WiFi interface

**`/etc/systemd/system/fix-kbd-backlight.service`**  
Runs on boot and after resume to restore keyboard backlight:
- Waits 4 seconds for system stabilization
- Checks if keyboard backlight path exists
- Reloads apple-bce driver if needed
- Sets keyboard backlight brightness

### Helper Script

**`/usr/local/bin/fix-kbd-backlight.sh`**  
Shell script called by the keyboard backlight service to handle driver reload logic.

## System Changes

The script also modifies the following system settings:

- Sets `mem_sleep_default=deep` kernel parameter via grubby
- Disables thermald service if present
- Changes `pcie_aspm=off` to `pcie_aspm=default` if set
- Removes systemd-suspend override.conf if present

## Uninstallation

To remove the suspend fix:

```bash
sudo systemctl disable suspend-wifi-unload.service
sudo systemctl disable resume-wifi-reload.service
sudo systemctl disable fix-kbd-backlight.service
sudo rm /etc/systemd/system/suspend-wifi-unload.service
sudo rm /etc/systemd/system/resume-wifi-reload.service
sudo rm /etc/systemd/system/fix-kbd-backlight.service
sudo rm /usr/local/bin/fix-kbd-backlight.sh
sudo systemctl daemon-reload
```

## Contributing

Yes please!

## License

Use at your own risk.
