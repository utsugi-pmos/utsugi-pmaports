# Flashing the POCO X3 NFC (surya)

## The one rule

**The `boot` partition holds U-Boot, not the kernel.** Writing a kernel there
leaves the phone unable to boot at all.

```
fastboot flash boot   u-boot-...img      <- ONLY to install or repair U-Boot
fastboot flash userdata <image>.img      <- the system image goes here
```

`pmbootstrap flasher flash_rootfs` writes to `userdata` and is correct.
`pmbootstrap flasher flash_kernel` writes over U-Boot and is never part of an
upgrade: kernels arrive as apk packages and land in `/boot` inside the system
image.

## First install

1. **U-Boot, matched to the panel.** Get it wrong and the screen stays black.
   Releases: <https://github.com/sm7150-mainline/u-boot/releases>

   ```sh
   fastboot erase dtbo
   fastboot flash boot u-boot-sm7150-xiaomi-surya-tianma.img   # or -huaxing
   ```

2. **The image**, from this repository's releases:

   ```sh
   sha256sum -c SHA256SUMS
   xz -d utsugi-surya-<tag>.img.xz
   fastboot flash userdata utsugi-surya-<tag>.img
   fastboot reboot
   ```

The image already carries the repository line and the signing key, so
`apk upgrade` tracks updates from the first boot.

## After the first boot

The image cannot contain anything that needs a network or a user session:

- Flatpak applications (they need Flathub).
- Web application launchers.
- Personal choices: ad-blocking DNS, Telegram scaling, which browser.

Those come from `surya-setup` in the `vayu-postmarketos` repository.

## Upgrading the kernel, and why it is a separate step

```sh
sudo apk upgrade          # may bring a new kernel
sudo reboot               # deliberately not chained to the line above
```

Chaining the reboot to the install catches the package halfway through writing
its modules. And a kernel that does not boot is not a failed install: the
watchdog fires 20 s after PID 1 and reboots, forever, with no screen to fix it
from.

**Before rebooting into a kernel you have not booted before**, arm the way back
in. During a reboot loop there is a window of roughly 20 seconds of ssh over the
USB gadget, which is not something you hit by hand:

```sh
systemd-run --user --unit=rescue ~/projects/vayu-postmarketos/surya/boot/rescue-over-usb
journalctl --user -u rescue -f
```

`uname -r` reports **pkgrel + 1**, not the pkgrel: a kernel that says `#249` is
`r248`.
