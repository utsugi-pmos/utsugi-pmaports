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
# encrypted phone, and nothing in there knows about the alarm or can play a
# sound: the DSP firmware and the audio stack are inside the encrypted root.
# The vibrator is not. So a small watcher stays behind in the initramfs and,
# at the alarm's time, vibrates until the phone is unlocked; once the real
# init is PID 1 the Clock app has taken over and the watcher quits. It is not
# a shell: init_2nd kills every 'sh' before switching root, so busybox runs
# under another name to survive that sweep. Harmless on an unencrypted phone:
# systemd is PID 1 long before the alarm is due.
arm_buzzer() {
	[ -n "$ALARM" ] && command -v beebzzr >/dev/null || return 0
	ring=$(( ALARM + 120 ))
	now=$(cat "$RTC" 2>/dev/null || echo 0)
	# Only an alarm this boot is actually for: not a stale one hours away.
	[ $(( ring - now )) -le 600 ] && [ $(( now - ring )) -le 600 ] || { log "alarm at rtc $ring is not this boot's"; return 0; }
	cp /bin/busybox /tmp/utsugi-alarm-buzz 2>/dev/null || return 0
	grep -qs . /sys/class/input/*/device/name && grep -qls aw8695 /sys/class/input/*/device/name \
		|| log "no vibrator found yet (aw8695); the buzzer will try anyway"
	setsid /tmp/utsugi-alarm-buzz sh -c '
		while [ "$(cat /sys/class/rtc/rtc0/since_epoch)" -lt "$1" ]; do
			[ "$(cat /proc/1/comm 2>/dev/null)" = init ] || exit 0
			sleep 2
		done
		n=0
		while [ "$(cat /proc/1/comm 2>/dev/null)" = init ] && [ "$n" -lt 150 ]; do
			beebzzr -d 700 -b 2 >/dev/null 2>&1
			sleep 2; n=$((n + 1))
		done' buzz "$ring" >/dev/null 2>&1 </dev/null &
	log "alarm buzzer armed for rtc $ring"
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
	plymouth update --status="charge-$cap" 2>/dev/null; log "status charge-$cap rc=$?"
	case "$st" in
		Charging) words="$cap %  charging" ;;
		Full)     words="$cap %  full" ;;
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
