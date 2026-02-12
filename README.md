# T2Linux MacBook Suspend Fix

This script configures your system to properly suspend and resume by managing the Broadcom WiFi driver and Apple BCE keyboard backlight driver.
It creates scripts and systemd services to handle driver unloading before suspend and reloading after resume in correct sequence.
Keyboard backlight not working on boot is also taken care of.

### For now the script is as is

This is mostly configured for my specific usage but it may help others. Feel free to try the script. If it's working - yay! If not, use the uninstaller and call it a day until T2Linux devs come up with a better solution.


## Important Notes / Known Issues

- The system needs more time to resume than you're used to from MacOS. The script takes between 1.5 to 3 seconds to run through. The longest waiting times is userland re-initializing.
- Some systems don't work with the script. It's unclear if this is related to the specific hardware, firmware or distro.
- There is an uninstall option when running the script. If the script doesn't work for you, just reboot and run it again. It will restore your previous settings and files.
- Note that using powertop --auto-tune or any related script enabling/forcing ASPM will block "optimized" PCI devices from transitioning to D3 power state. Or in other words: If you want to enjoy working suspend, remove such scripts.
- The script uses deep sleep. Hibernate and hybrid sleep will also work, but require further manual steps like creating a swap partition.


## Installation

1. Clone this repo:
```bash
git clone https://github.com/lilithmooncohen/t2linux-fix && cd t2linux-fix
```

2. Make any changes relevant to you to the scripts (you may need to enable the brcmfmac_wcc and brcmfmac steps for instance in `scripts/t2linux-disable-all.sh`)

3. Run the installer:
```bash
./t2linux-fix.sh
```

4. Choose install or uninstall

5. Check the prompts and Reboot

## Changes on your system

The script performs the following actions:

1. Automatically configures the system to use deep sleep mode (will print needed changes if you use rEFInd)
2. Creates systemd services
3. Backups, disables or removes conflicting services (thermald/override.conf)
4. Sets ASPM to off if needed

### Systemd Services

**`/etc/systemd/system/t2linux-suspend-disable.service`**
Runs before suspend to aggressively unload WiFi and BCE drivers:
- Deactivates WiFi interface via NetworkManager
- Unloads brcmfmac_wcc and brcmfmac modules
- Removes the apple-bce module

**`/etc/systemd/system/t2linux-resume-enable.service`**
Runs after resume to restore WiFi and BCE:
- Loads apple-bce module
- Waits up to 30s for apple-bce to appear
- Loads brcmfmac_wcc and brcmfmac modules
- Reactivates WiFi interface
- After 5 seconds, checks if brcmfmac is bound; if not, reloads brcmfmac

**`/etc/systemd/system/t2linux-enable-kbd-backlight.service`**
Runs on boot and after resume to restore keyboard backlight:
- Checks if keyboard backlight path exists
- Reloads apple-bce driver if needed
- Sets keyboard backlight to previous brightness

### Helper Scripts

The installer creates the following helper scripts that can be run manually for troubleshooting:

**`/usr/local/bin/t2linux-disable-all.sh`**
Prepares system for suspend by:
- Disabling keyboard backlight and backing up brightness
- Turning off WiFi via NetworkManager
- Forcefully removing apple-bce driver

**`/usr/local/bin/t2linux-enable-all.sh`**
Restores drivers after resume by:
- Loading apple-bce driver
- Waiting for BCE initialization (up to 30s)
- Loading brcmfmac and brcmfmac_wcc WiFi drivers
- Restoring keyboard backlight brightness
- Activating WiFi via NetworkManager
- Checking WiFi binding after 5s and reloading if necessary

**`/usr/local/bin/t2linux-restart-all.sh`**
Performs a complete driver restart by running disable-all followed by enable-all. Useful for manual troubleshooting when drivers get into a bad state.

**`/usr/local/bin/t2linux-disable-kbd-backlight.sh`**
Backs up current keyboard backlight brightness to `/etc/t2linux/kbd_backlight_brightness` and sets brightness to 0 before suspend.

**`/usr/local/bin/t2linux-enable-kbd-backlight.sh`**
Restores keyboard backlight after resume by:
- Waiting for apple-bce driver to be available
- Restoring brightness from backup or setting to 1000 (default)
- Polling for up to 15s for brightness path
- Forcefully resetting apple-bce driver if brightness path remains unavailable

**`/usr/local/bin/t2linux-wait-apple-bce.sh`**
Polls for up to 30 seconds to verify apple-bce driver has bound to a PCI device. Logs error and sends desktop notification if timeout is reached.

### System Changes

The script also modifies the following system settings:

- Sets `mem_sleep_default=deep pcie_aspm=off` kernel parameter via grubby
  - Will need to set manually if not on grub (e.g. in `/boot/refind_linux.conf`
- Disables thermald service if present
- Backups and removes systemd-suspend override.conf if present


## Uninstallation

To remove the suspend fix run the script again and choose the uninstall option.

## Debugging

Execute BEFORE suspend:
```
./t2linux-fix-debug.sh
```

Then suspend and execute again AFTER suspend:
```
./t2linux-fix-debug.sh
```

The script will show you the output location of the log files like this:
```
=== Debug information collected ===
Log saved to: /tmp/t2linux-fix-debug-20260202-230441.log
```

Please post both log files when reporting issues.

## Contributing

Yes please!

## License

Use at your own risk.
