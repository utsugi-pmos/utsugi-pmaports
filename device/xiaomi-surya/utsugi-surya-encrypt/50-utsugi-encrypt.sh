#!/bin/sh
# Encrypt the root filesystem in place, on the phone, at boot.
#
# Runs from the initramfs as /hooks-extra/50-utsugi-encrypt.sh: after
# mount_subpartitions has found the root partition and BEFORE anything unlocks
# or mounts it. That is the only moment a root filesystem can be encrypted --
# it cannot be done while it is mounted, and once init_2nd continues it will be.
#
# WHY HERE AND NOT ON A PC
# ------------------------
# The LUKS master key is generated when the container is formatted. Doing that
# on a PC means the person who built the image holds the key of every phone
# flashed from it, so an encrypted image cannot be handed out. Doing it here
# means the key is born on the phone that will use it, the image downloaded is
# an ordinary unencrypted one, and nobody's PC needs Linux, pmbootstrap or root.
#
# HOW IT IS ASKED FOR
# -------------------
# The first-boot assistant writes the chosen passphrase to
# /var/lib/utsugi-surya/encrypt-request (root, 0600) and reboots. This hook
# mounts the root read-only, takes that file, and does the work. The file is
# removed afterwards from inside the now-encrypted filesystem, so it never sits
# on an unencrypted disk past this boot.
#
# WHAT IT DOES, IN ORDER
# ----------------------
#   1. refuse politely if the battery is low and the charger is out: an
#      interrupted encryption is resumable, but why start one that way
#   2. e2fsck, because resize2fs refuses a filesystem it has not checked
#   3. shrink the filesystem by 32 MiB to make room for the LUKS2 header
#      (cryptsetup's own documented figure)
#   4. cryptsetup reencrypt --encrypt: the data is encrypted in place
#   5. open it as /dev/mapper/root, so init_2nd's unlock step finds it already
#      open and does not ask for the passphrase again this boot
#   6. delete the request and write /etc/crypttab, from inside
#
# From the next boot on, the stock initramfs sees TYPE=crypto_LUKS, calls
# fde-unlock, and unl0kr draws the keyboard on this panel. Nothing here has to
# be remembered by anyone.
#
# IF IT IS INTERRUPTED
# --------------------
# LUKS2 online reencryption keeps its own journal. If the phone dies halfway,
# the partition is already LUKS with a "reencrypt in progress" flag; the next
# boot lands in the crypto_LUKS branch below, asks for the passphrase, and
# resumes. The watchdog is no danger during this: the kernel keeps it fed
# until userspace opens it (CONFIG_WATCHDOG_HANDLE_BOOT_ENABLED), and nothing
# in the initramfs does.
#
# Plain POSIX sh: the initramfs shell is busybox.

. /init_functions.sh

REQUEST=var/lib/utsugi-surya/encrypt-request
MNT=/tmp/utsugi-encrypt-root
PW=/tmp/utsugi-encrypt-passphrase

say() { echo "utsugi-encrypt: $*"; splash_set_message "$1"; }

cleanup() {
	umount "$MNT" 2>/dev/null
	rm -f "$PW"
}

find_root_partition ROOT
[ -n "$ROOT" ] || exit 0

TYPE="$(get_partition_type "$ROOT")"

case "$TYPE" in
crypto_LUKS)
	# Already encrypted. Make sure the header carries the UUID the cmdline
	# expects -- repairs a phone encrypted by the version that did not set it,
	# which otherwise never gets past "Waiting for root partition". Reads the
	# wanted UUID from the cmdline, since the ext4 UUID is no longer visible.
	want="$(cat /proc/cmdline | tr ' ' '\n' | sed -n 's/^pmos.\?root_uuid=//p' | head -1)"
	have="$(blkid -o value -s UUID "$ROOT" 2>/dev/null)"
	if [ -n "$want" ] && [ "$want" != "$have" ]; then
		cryptsetup luksUUID "$ROOT" --uuid "$want" --batch-mode 2>/dev/null &&
			echo "utsugi-encrypt: set LUKS UUID to $want (cmdline)"
	fi
	# The only other thing to do is finish an interrupted encryption.
	if cryptsetup luksDump "$ROOT" 2>/dev/null | grep -q "online-reencrypt"; then
		say "Finishing the encryption that was interrupted.\nEnter the passphrase you chose."
		splash_hide
		until unl0kr | cryptsetup reencrypt --resume-only --batch-mode --key-file - "$ROOT"; do
			echo "utsugi-encrypt: resume failed, asking again"
		done
		say "Encryption complete."
	fi
	exit 0
	;;
ext4)
	;;
*)
	# Not something this knows how to encrypt. Leave it alone.
	exit 0
	;;
esac

# Is there a request? Look inside the filesystem, read-only, and get out.
mkdir -p "$MNT"
modprobe ext4 2>/dev/null
mount -o ro "$ROOT" "$MNT" 2>/dev/null || exit 0
if [ -f "$MNT/$REQUEST" ]; then
	umask 077
	cat "$MNT/$REQUEST" > "$PW"
fi
umount "$MNT"

# The UUID the kernel cmdline was built with (pmos_root_uuid=), which is this
# ext4 filesystem's UUID. After encryption the partition is crypto_LUKS with a
# random UUID, and the stock find_partition looks for the OLD one and refuses
# to fall back -- so the next boot cannot find its own root and stops at
# "Waiting for root partition". Captured here while it is still ext4, and put
# back on the LUKS header below. This is the difference between a phone that
# boots after encryption and one that does not; found the hard way on
# 2026-09-14, on a phone that encrypted fine and then could not boot.
OLD_UUID="$(blkid -o value -s UUID "$ROOT" 2>/dev/null)"
[ -s "$PW" ] || { rm -f "$PW"; exit 0; }

# Power. Encrypting a few gigabytes on a phone takes a while, and a phone that
# dies halfway through is recoverable (see above) but it is not a good start.
cap="$(cat /sys/class/power_supply/qcom_qg/capacity 2>/dev/null || echo 100)"
online="$(cat /sys/class/power_supply/pm8150b-charger/online 2>/dev/null || echo 0)"
if [ "$online" != 1 ] && [ "${cap:-100}" -lt 40 ]; then
	say "Not encrypting yet: battery at ${cap}% and no charger.\nPlug it in and restart, and it will start."
	sleep 6
	cleanup
	exit 0
fi

modprobe dm-crypt 2>/dev/null
modprobe dm-mod 2>/dev/null

# THE ENCRYPTION SECTOR SIZE MUST MATCH THE DISK, OR THE PHONE IS UNUSABLE.
#
# cryptsetup defaults to 512-byte encryption sectors even on a 4096-byte disk.
# This phone's UFS is 4096 native, and a 512-sector dm-crypt on it turns every
# 4096 write into read-decrypt-modify-encrypt of eight sectors -- read-modify-
# write amplification. Unencrypted the desktop loads at load ~3; through a
# 512-sector dm-crypt the same startup I/O saturated all four cores and the
# session never came up. Measured on 2026-09-14: encrypted, the phone unlocked
# and mounted but never reached the desktop; unencrypted it was fine.
#
# So pass the disk's own sector size. blockdev --getss reports the logical
# sector; fall back through sysfs; last resort 512, which is always valid.
SECSZ="$(blockdev --getss "$ROOT" 2>/dev/null)"
if [ -z "$SECSZ" ]; then
	# a loop partition has no queue/ of its own; the parent loop device does
	q="/sys/class/block/$name/queue/logical_block_size"
	[ -r "$q" ] || q="/sys/class/block/$name/../queue/logical_block_size"
	SECSZ="$(cat "$q" 2>/dev/null)"
fi
case "$SECSZ" in 512|1024|2048|4096) ;; *) SECSZ=512 ;; esac

say "Encrypting this phone.\nDo not turn it off. This takes a while."

# 2. Check first: resize2fs refuses to touch a filesystem that has not been.
e2fsck -fy "$ROOT" >/dev/null 2>&1
rc=$?
if [ "$rc" -ge 4 ]; then
	say "Cannot encrypt: the filesystem check failed (code $rc).\nStarting normally."
	sleep 6; cleanup; exit 0
fi

# 3. Shrink by 32 MiB. The device size comes from sysfs in 512-byte sectors
#    whatever the disk's logical sector size is, which matters on this phone
#    (UFS, 4096). resize2fs takes K without ambiguity.
name="$(basename "$ROOT")"
sectors="$(cat "/sys/class/block/$name/size" 2>/dev/null)"
if [ -z "$sectors" ]; then
	# A device-mapper path: resolve the dm-N name
	dm="$(readlink -f "$ROOT")"; name="$(basename "$dm")"
	sectors="$(cat "/sys/class/block/$name/size" 2>/dev/null)"
fi
if [ -z "$sectors" ]; then
	say "Cannot encrypt: could not read the device size.\nStarting normally."
	sleep 6; cleanup; exit 0
fi
newk=$(( sectors / 2 - 32768 ))
if ! resize2fs "$ROOT" "${newk}K" >/dev/null 2>&1; then
	say "Cannot encrypt: making room for the header failed.\nStarting normally."
	sleep 6; cleanup; exit 0
fi

# 4. The encryption itself, with a percentage that does not come from
#    cryptsetup. Measured on 2026-09-14: with no terminal attached, cryptsetup
#    prints NO progress at all -- not with --progress-frequency, and with
#    --progress-json only a single line when it is already done. The first
#    real run sat on "Encrypting this phone" for ten minutes and looked hung.
#
#    What does move is the block device's own I/O counters in sysfs:
#    reencrypt reads every sector once and writes it once, so sectors read (or
#    written) over the device size is the fraction done. The counters are in
#    512-byte units whatever the disk's logical sector size, and so is the
#    size, so the ratio needs no unit juggling. The journal adds a little on
#    top, hence the clamp at 99 until it really finishes.
#
#    busybox sh has no PIPESTATUS, so the exit code is taken from wait.
PROG=/tmp/utsugi-encrypt-progress
: > "$PROG"
stat_file="/sys/class/block/$name/stat"
r0="$(awk '{print $3}' "$stat_file" 2>/dev/null || echo 0)"
w0="$(awk '{print $7}' "$stat_file" 2>/dev/null || echo 0)"
cryptsetup reencrypt --encrypt --reduce-device-size 32M --batch-mode \
	--sector-size "$SECSZ" --key-file "$PW" "$ROOT" > "$PROG" 2>&1 &
pid=$!
last=-1
while kill -0 "$pid" 2>/dev/null; do
	if [ -r "$stat_file" ]; then
		r="$(awk '{print $3}' "$stat_file")"; w="$(awk '{print $7}' "$stat_file")"
		done_r=$((r - r0)); done_w=$((w - w0))
		[ "$done_w" -gt "$done_r" ] && done_r=$done_w
		pct=$(( done_r * 100 / sectors ))
		[ "$pct" -gt 99 ] && pct=99
		if [ "$pct" != "$last" ]; then
			splash_set_message "Encrypting this phone: ${pct}%\nDo not turn it off."
			last=$pct
		fi
	fi
	sleep 3
done
wait "$pid"
rc=$?
if [ "$rc" -ne 0 ]; then
	say "Encryption failed (cryptsetup: $rc).\nThe phone will start; try again from Settings."
	echo "utsugi-encrypt: cryptsetup output:"; cat "$PROG"
	sleep 8; cleanup; exit 0
fi

# 4b. Give the LUKS header the filesystem's old UUID, so the stock initramfs
#     finds it by the pmos_root_uuid= on the cmdline. Without this the phone
#     encrypts and then cannot find its root.
if [ -n "$OLD_UUID" ]; then
	cryptsetup luksUUID "$ROOT" --uuid "$OLD_UUID" --batch-mode 2>/dev/null ||
		echo "utsugi-encrypt: warning: could not set the LUKS UUID to $OLD_UUID"
fi

# 5. Open it, the same way fde-unlock does, so the unlock step sees it open.
cryptsetup --perf-no_read_workqueue --perf-no_write_workqueue \
	open "$ROOT" root --key-file "$PW" || {
	say "Encrypted, but could not open it now.\nRestart and enter the passphrase."
	sleep 6; cleanup; reboot -f
}

# 6. From inside: forget the request, record the volume. resize2fs is left to
#    init_2nd, which grows the filesystem to fill the container on this boot.
mount /dev/mapper/root "$MNT" && {
	rm -f "$MNT/$REQUEST"
	uuid="$(cryptsetup luksUUID "$ROOT")"
	if ! grep -qs "^root " "$MNT/etc/crypttab"; then
		printf 'root UUID=%s none luks\n' "$uuid" >> "$MNT/etc/crypttab"
	fi
	: > "$MNT/var/lib/utsugi-surya/encrypted-on-first-boot"
	umount "$MNT"
}
rm -f "$PW" "$PROG"
say "Encrypted. Starting up."
exit 0
