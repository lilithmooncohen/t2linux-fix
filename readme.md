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

- The system needs more time to resume than you're used to from MacOS. The script takes between 1.5 to 3 seconds to run through. The longest waiting times is userland initializing after the script.
- Some systems don't work with the script yet. It's unclear if this is related to the specific hardware or distro.
- There is an uninstall option when running the script. So if it doesn't work for your, just reboot and run it again. It will restore your previous settings and files.
- Not that using powertop --auto-tune or any related script enabling/forcing ASPM will block "optimized" PCI devices from transitioning to D3 power state. Or in other words: If you want to enjoy working suspend, remove such scripts.


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
4. Backups, Disables or removes conflicting services (thermald/override.conf)
5. Adjusts ASPM settings to off if needed

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
- Backups and removes systemd-suspend override.conf if present

## Uninstallation

To remove the suspend fix run the script again and choose the uninstall option.

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
