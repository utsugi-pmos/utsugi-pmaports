#!/bin/sh
# The charging screen, inside the initramfs: what the phone shows when it is
# plugged in while off. Runs from hooks-extra, before the root partition is
# waited for -- and so before unl0kr asks for the passphrase. That is the whole
# point: the version that lived in systemd could never run on an encrypted
# phone, because systemd only starts after the passphrase.
#
# Who decides: the PMIC. PON_REASON1 (0x8c0) says how the phone left the off
# state -- 0x10 the charger, 0x80 the button, 0x01 a reset. Measured on the
# surya on 2026-09-05 and read here through the regmap in debugfs.
#
# Three rules, the ones every phone follows:
#   - unplugged   -> powers off
#   - short press -> the screen comes on for a while
#   - long press  -> boots the phone (on to the passphrase, or the desktop)
# and a fourth of ours: the next clock alarm. arm-alarm-wakeup leaves it in the
# unencrypted boot partition at power-off; when its time comes the boot
# simply continues, the desktop comes up and the Clock app rings it.
#
# Drawing is plymouth's job: it already owns the screen here, and the
# utsugi-spin theme turns 'plymouth update --status=charge-<n>' into a battery.
# Words go through display-message. Nothing new to draw with, nothing to
# fight plymouth for the panel.
#
# Everything this reads may be missing on some other device: then it says so
# on the kernel log and lets the boot go on. It must never stop a boot.
. /init_functions.sh

log() { echo "utsugi-charge: $*" > /dev/kmsg 2>/dev/null; }

QG=/sys/class/power_supply/qcom_qg
CHG=/sys/class/power_supply/pm8150b-charger
RTC=/sys/class/rtc/rtc0/since_epoch
USB_CHG=16; DC_CHG=8; RTC_ALARM=4; KPDPWR=128; HARD_RESET=1
SCREEN_OFF=45   # s without a press before the screen goes dark
LONG_PRESS=2    # s of power to boot

command -v plymouth >/dev/null && command -v iskey >/dev/null || { log "no plymouth or iskey, normal boot"; exit 0; }

# The gauge and the charger are modules (40-utsugi-charge-mode.modules puts
# them in the initramfs); udev loads them, but not before this hook runs at
# boot second 5. Ask for them and give them up to twenty seconds to probe.
modprobe qcom_spmi_adc5 2>/dev/null; modprobe nvmem_qcom_spmi_sdam 2>/dev/null
modprobe qcom_qg 2>/dev/null; modprobe qcom_smbx 2>/dev/null
modprobe aw8695_haptics 2>/dev/null
mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug 2>/dev/null
i=0
until [ -r "$CHG/online" ] && [ -r "$QG/capacity" ] && [ -n "$(ls /sys/kernel/debug/regmap 2>/dev/null)" ]; do
	i=$((i + 1))
	[ "$i" -ge 80 ] && { log "no battery nodes after 20 s, normal boot"; exit 0; }
	sleep 0.25
done
[ "$i" -gt 0 ] && log "battery nodes appeared after $((i / 4)) s"
reason() {
	for d in /sys/kernel/debug/regmap/*; do
		[ "$(cat "$d/name" 2>/dev/null)" = pmic-spmi ] || continue
		v=$(grep -E '^0*8c0: ' "$d/registers" 2>/dev/null | awk '{print $2}')
		[ -n "$v" ] && { echo $((0x$v)); return 0; }
	done
	return 1
}
# The next alarm, as an RTC timestamp, left by arm-alarm-wakeup at power-off.
# The RTC is the only clock here: the system time is not set yet.
ALARM=; ALARM_TEXT=
bootp=$(blkid -L pmOS_boot 2>/dev/null)
if [ -n "$bootp" ]; then
	mkdir -p /tmp/utsugi-boot
	if mount -o ro "$bootp" /tmp/utsugi-boot 2>/dev/null; then
		[ -r /tmp/utsugi-boot/utsugi/next-alarm ] && read -r ALARM ALARM_TEXT < /tmp/utsugi-boot/utsugi/next-alarm
		umount /tmp/utsugi-boot 2>/dev/null
	fi
fi
# The file is rewritten at every power-off, but not by a reboot, a crash or a
# flat battery, so it can be old. An alarm already more than ten minutes past
# is not this boot's: without this, the charging screen would think its time
# had come and carry straight on booting. Seen on 2026-09-16 after the reboot
# into encryption.
if [ -n "$ALARM" ] && [ $(( $(cat "$RTC" 2>/dev/null || echo 0) - ALARM )) -gt 600 ]; then
	log "stale alarm at rtc $ALARM ($ALARM_TEXT), ignored"
	ALARM=; ALARM_TEXT=
fi
[ -n "$ALARM" ] && log "next alarm at rtc $ALARM ($ALARM_TEXT)"

# A boot that is going on for an alarm may stop at the passphrase of an
# encrypted phone, where nothing knows about the alarm. alarm-sound, which
# travels in the initramfs with the DSP firmware and the audio stack, rings it
# by the speaker and buzzes until the phone is unlocked; after that the Clock
# app has taken over. PID 1 is
# not called "init" while waiting: the initramfs execs /init_2nd.sh, so the
# test is "not systemd yet" -- testing for "init" made the watcher quit at once
# and nothing vibrated, measured on 2026-09-16. It is not
# a shell: init_2nd kills every 'sh' before switching root, so busybox runs
# under another name to survive that sweep. Harmless on an unencrypted phone:
# systemd is PID 1 long before the alarm is due.
# The passphrase screen can say what is ringing and how to stop it: unl0kr
# takes --message, and fde-unlock is what starts it, in a loop until the root
# opens. The initramfs's own files are writable at this point, so on an alarm
# boot fde-unlock is swapped for one that passes the message when
# /tmp/utsugi-unlock-message exists; alarm-sound writes that file and restarts
# unl0kr so it comes back with the text. (Not through a mkinitfs file list:
# with two sources for /usr/bin/fde-unlock, which one lands is a map order.)
#
# The copy is the original with --message added, so a future fde-unlock keeps
# its own options; if the edit does not take, nothing is swapped.
message_on_passphrase_screen() {
	F=/usr/bin/fde-unlock
	[ -f "$F" ] && [ ! -e "$F.orig" ] || return 0
	sed 's/unl0kr |/unl0kr --message "$UTSUGI_MESSAGE" |/' "$F" > "$F.message" 2>/dev/null
	grep -q -- '--message "$UTSUGI_MESSAGE"' "$F.message" 2>/dev/null || { rm -f "$F.message"; log "fde-unlock not recognised: no message on the passphrase screen"; return 0; }
	cp "$F" "$F.orig" && chmod 755 "$F.message" || return 0
	cat > "$F" <<'WRAPPER'
#!/bin/sh
# utsugi: the alarm's message on the passphrase screen, see 40-utsugi-charge-mode.sh
if [ -s /tmp/utsugi-unlock-message ]; then
	UTSUGI_MESSAGE="$(cat /tmp/utsugi-unlock-message)"
	export UTSUGI_MESSAGE
	exec sh /usr/bin/fde-unlock.message "$@"
fi
exec sh /usr/bin/fde-unlock.orig "$@"
WRAPPER
	chmod 755 "$F"
	log "fde-unlock can show the alarm message"
}

arm_buzzer() {
	[ -n "$ALARM" ] || return 0
	ring=$(( ALARM + 120 ))
	now=$(cat "$RTC" 2>/dev/null || echo 0)
	# Only an alarm this boot is actually for: not a stale one hours away.
	[ $(( ring - now )) -le 600 ] && [ $(( now - ring )) -le 600 ] || { log "alarm at rtc $ring is not this boot's"; return 0; }
	# Only an encrypted root stops at a passphrase. An unencrypted phone is at
	# its desktop long before the alarm, where the Clock app rings it; loading
	# the audio stack here too would race the real system's own.
	find_root_partition ROOT
	[ "$(get_partition_type "$ROOT")" = crypto_LUKS ] || { log "root not encrypted: the desktop rings the alarm"; return 0; }
	[ -x /usr/libexec/utsugi-surya/alarm-sound ] || { log "no alarm-sound in this initramfs"; return 0; }
	message_on_passphrase_screen
	setsid sh /usr/libexec/utsugi-surya/alarm-sound "$ring" "$ALARM_TEXT" </dev/null >/dev/null 2>&1 &
	log "alarm ringer armed for rtc $ring"
}

n=$(reason) || { log "cannot read PON_REASON1, normal boot"; exit 0; }
online=$(cat "$CHG/online" 2>/dev/null || echo 0)
# The RTC alarm turned the phone on while it was off: a Clock alarm is due.
[ $((n & RTC_ALARM)) -ne 0 ] && { log "PON_REASON1=$n: woken by the alarm"; arm_buzzer; }
if [ $((n & HARD_RESET)) -ne 0 ] || [ $((n & KPDPWR)) -ne 0 ] || \
   [ $((n & (USB_CHG | DC_CHG))) -eq 0 ] || [ "$online" != 1 ]; then
	log "PON_REASON1=$n charger=$online: normal boot"
	exit 0
fi
log "PON_REASON1=$n charger=$online: charge mode"


# The power key's event node. Polling "is it pressed now" (iskey) misses a
# quick tap between two polls -- measured on 2026-09-16, a short press did
# nothing -- so presses and releases are read as events, and iskey is only the
# fallback when no node is found.
KEY=
for d in /sys/class/input/event*; do
	[ "$(cat "$d/device/name" 2>/dev/null)" = pm8941_pwrkey ] && KEY=/dev/input/$(basename "$d")
done
[ -n "$KEY" ] && log "power key at $KEY" || log "power key node not found, polling with iskey"

BL=$(ls -d /sys/class/backlight/* 2>/dev/null | head -1)
MAXBL=$(cat "$BL/max_brightness" 2>/dev/null || echo 4095)
DIM=$(( MAXBL / 12 ))
brightness() { [ -n "$BL" ] && echo "$1" > "$BL/brightness" 2>/dev/null; true; }
rtc() { cat "$RTC" 2>/dev/null || echo 0; }

paint() {
	cap=$(cat "$QG/capacity" 2>/dev/null || echo 0)
	st=$(cat "$QG/status" 2>/dev/null)
	key="$cap/$st"
	[ "$key" = "$last" ] && return
	last="$key"
	# The gauge keeps saying "Charging" at 100 % while it tops off. For the
	# owner that is full: say so, and the theme draws it green.
	[ "$st" = Full ] && cap=100
	[ "$cap" -ge 100 ] 2>/dev/null && { cap=100; st=Full; }
	plymouth update --status="charge-$cap" 2>/dev/null; log "status charge-$cap rc=$?"
	case "$st" in
		Charging) words="$cap %  charging" ;;
		Full)     words="Fully charged" ;;
		*)        words="$cap %" ;;
	esac
	[ -n "$ALARM_TEXT" ] && words="$words\nAlarm $ALARM_TEXT"
	plymouth display-message --text="$(printf '%b' "$words")" 2>/dev/null
}

splash_show
last=
paint
brightness "$DIM"
woke=$(rtc); pressed=0; no_cable=0; why=

while :; do
	now=$(rtc)
	# Unplugged: off. Two readings in a row, a renegotiation of the port reads 0 once.
	if [ "$(cat "$CHG/online" 2>/dev/null || echo 0)" = 1 ]; then
		no_cable=0
	else
		no_cable=$(( no_cable + 1 ))
		if [ "$no_cable" -ge 2 ]; then
			log "unplugged: powering off"
			plymouth update --status=charge-off 2>/dev/null
			brightness 0
			poweroff -f
			exit 0
		fi
	fi
	# The clock alarm: on with the boot, the desktop rings it.
	if [ -n "$ALARM" ] && [ "$now" -ge "$ALARM" ]; then why="alarm $ALARM_TEXT"; break; fi
	# The button: any press lights the screen, a long one boots. With the
	# event node, waiting for an event is also the loop's clock: a press
	# returns at once, otherwise the read times out and the cable is checked.
	if [ -n "$KEY" ]; then
		ev=$( { timeout 1 dd if="$KEY" bs=24 count=1 2>/dev/null | hexdump -v -e '6/4 "%u " "\n"'; } 2>/dev/null )
		if [ -n "$ev" ]; then
			# struct input_event: two 64-bit time fields, then type+code in
			# one u32 and the value in the next.
			set -- $ev
			kind=$(( $5 & 65535 )); code=$(( $5 >> 16 )); value=$6
			if [ "$kind" -eq 1 ] && [ "$code" -eq 116 ]; then
				log "power key value=$value at rtc $now"
				if [ "$value" -eq 1 ]; then
					pressed=$now; woke=$now; brightness "$DIM"
				elif [ "$value" -eq 0 ]; then
					pressed=0
				fi
			fi
		fi
		# Still held: the time counts from the press.
		[ "$pressed" != 0 ] && [ $(( now - pressed )) -ge "$LONG_PRESS" ] && { why="long press"; break; }
	else
		if iskey KEY_POWER 2>/dev/null; then
			[ "$pressed" = 0 ] && pressed=$now
			woke=$now
			brightness "$DIM"
			[ $(( now - pressed )) -ge "$LONG_PRESS" ] && { why="long press"; break; }
		else
			pressed=0
		fi
		sleep 0.25
	fi
	[ $(( now - woke )) -ge "$SCREEN_OFF" ] && brightness 0
	paint
done

log "leaving charge mode: $why"
# An empty message is refused by the client; a space clears the text.
plymouth display-message --text=" " 2>/dev/null
plymouth update --status=charge-off 2>/dev/null
brightness $(( MAXBL / 2 ))
[ "${why%% *}" = alarm ] && arm_buzzer
exit 0
