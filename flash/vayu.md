# Flashing the POCO X3 Pro (vayu) -- experimental

**The modem does not work on this device.** It comes up and dies two to four
seconds after the radio is switched on, and the cause is pinned down to a
firmware assertion but not fixed. Everything here is for continuing that
investigation, not for daily use.

Unlike the surya, the vayu boots postmarketOS directly over fastboot, so the
kernel does go to the `boot` partition:

```sh
pmbootstrap flasher flash_kernel
pmbootstrap flasher flash_rootfs
fastboot reboot
```

## The IPA firmware is not in this repository

The modem's IPA firmware is proprietary and comes from the phone's own stock
`vendor` partition. It is not redistributable, so it is not packaged: extract it
from your own device.
