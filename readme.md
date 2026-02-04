# T2Linux MacBook Suspend Fix

This script configures your system to properly suspend and resume by managing the Broadcom WiFi driver and Apple BCE keyboard backlight driver. 
It automatically detects your WiFi PCI bus ID and creates systemd services to handle driver unloading before suspend and reloading after resume.
Keyboard backlight not working on boot is also taken care of.

### We need Feedback to confirm it's working

Please open a GitHub issue even if it's working. So far I can only confirm it works on 
- Fedora 43 with MacBook Air and MacBook Pro 2020
- Arch Linux with MacBook Pro 2019
- Mint Cinnamon with MacBook Pro 2019

## Important Notes / Known Issues

- Close the lid to suspend! Don't use terminal, the power button or suspend from the menu! 
Although all methods should work the same, your mileage can vary. Using the lid seems to be the safest bet. On my 2020 Air all methods work.

- The system needs more time to resume than you're used to from MacOS because it needs to re-initialize all bits and pieces we turned off to be able to make it sleep. But you can try shortening delays if your system is faster or making them longer if your system is slower.
- Typically you will notice a screen and keyboard still black when opening the lid for some few seconds. Sometimes even longer. It depends on your specific hardware config and distro
- On faster machines, the keyboard may be re-initialized while you are typing your password. See below bullet point to work around that 
- I recommend to just be patient and wait a few seconds or play with the "sleep" figures in the systemd services in the suspend install script to make delays shorter. The script was made for broad compatibility. We don't want to leave Intel Core I3 machines behind
- The workaround isn't perfect and probably will never be. Though it works reliably, we know there is still some hardware/software blocking going on while waking up. Probably related to the apple-bce/VHCI/Audio patches. The T2 Linux team is still actively investigating the suspend issue and on the time of writing (February 2026), they had a major breakthrough. Keep in touch with the latest development on https://matrix.to/#/#space:t2linux.org

## Installation

1. Download the script:
```bash
wget https://raw.githubusercontent.com/deqrocks/T2Linux-Suspend-Fix/refs/heads/main/t2-suspend-fix.sh
```

2. Make it executable:
```bash
chmod +x t2-suspend-fix.sh
```

3. Run it:
```bash
./t2-suspend-fix.sh
```

4. Reboot when prompted.

## Changes on your system

The script performs the following actions:

1. Detects the Broadcom WiFi card PCI bus ID
2. Configures the system to use deep sleep mode
3. Creates three systemd services
4. Disables or removes conflicting services (thermald/override.conf)
5. Adjusts ASPM settings to default if needed

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

### System Changes

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

## Debugging

Download debug-suspend.sh

Make script executable:
```
chmod +x debug-suspend.sh
```

Execute BEFORE suspend:
```
./debug-suspend.sh
```

Then suspend and execute again AFTER suspend:
```
./debug-suspend.sh
```

The script will show you the output location of the log files like this:
```
=== Debug information collected ===
Log saved to: /tmp/t2-suspend-debug-20260202-230441.log
```

Please post both log files when reporting issues.

## Contributing

Yes please!

## License

Use at your own risk.
