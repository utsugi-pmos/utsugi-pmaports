#!/bin/sh
# A shell over the USB cable while the initramfs runs -- above all while an
# encrypted phone waits at the passphrase screen, where nothing else can be seen.
#
# Only when /boot/utsugi/debug-shell exists: the boot partition is root-only on
# a running phone, so turning it on takes root. It listens on the USB network
# alone (172.16.42.1:2323, the address postmarketOS gives the phone there):
#
#     telnet 172.16.42.1 2323
#
# The stock pmos.debug-shell stops the boot; this one does not.
. /init_functions.sh

bootp=$(blkid -L pmOS_boot 2>/dev/null)
[ -n "$bootp" ] || exit 0
mkdir -p /tmp/utsugi-dbg-boot
mount -o ro "$bootp" /tmp/utsugi-dbg-boot 2>/dev/null || exit 0
on=0
[ -e /tmp/utsugi-dbg-boot/utsugi/debug-shell ] && on=1
umount /tmp/utsugi-dbg-boot 2>/dev/null
[ "$on" = 1 ] || exit 0
command -v busybox-extras >/dev/null || exit 0

# The USB network comes up before the hooks; give the address a moment anyway.
i=0
until ip addr show 2>/dev/null | grep -q 172.16.42.1; do
	i=$((i + 1)); [ "$i" -ge 20 ] && break; sleep 0.5
done
setsid busybox-extras telnetd -p 2323 -b 172.16.42.1 -l /bin/sh </dev/null >/dev/null 2>&1 &
echo "utsugi-debug: telnetd on 172.16.42.1:2323" > /dev/kmsg
exit 0
