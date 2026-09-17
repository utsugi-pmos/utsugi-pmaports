#!/bin/sh
#
# Run from this directory:
#
#     docker run --rm -v "$PWD":/t alpine:edge sh /t/tests/rename-user.sh
#
# (rename-user sits in /t, next to tests/). Last run 2026-09-17: 40 ok, 0 failed.
# Exercises rename-user in a throwaway Alpine: success, every refusal, an
# interrupted run and a failing home move. Each case must exit 0 and leave a
# working account.
set -u
apk add -q shadow procps >/dev/null 2>&1 || apk add -q shadow >/dev/null
R=/t/rename-user
REQ=/var/lib/utsugi-surya/rename-user
pass=0; fail=0
ok() { echo "  ok: $*"; pass=$((pass+1)); }
bad() { echo "  FAIL: $*"; fail=$((fail+1)); }
check() { if eval "$1"; then ok "$2"; else bad "$2"; fi; }

reset() {
	for u in $(awk -F: '$3==10000{print $1}' /etc/passwd); do userdel -r "$u" 2>/dev/null; done
	for g in $(awk -F: '$3==10000{print $1}' /etc/group); do groupdel "$g" 2>/dev/null; done
	rm -rf /home/* /var/lib/utsugi-surya /var/lib/systemd/linger
	groupadd -g 10000 user; useradd -u 10000 -g 10000 -G wheel,audio -m -d /home/user -s /bin/ash user
	mkdir -p /home/user/.config /home/user/.cache /home/user/.local/share
	printf 'Image=/home/user/Pictures/a.jpg\nOther=/home/username\n' > /home/user/.config/plasmarc
	printf 'x=/home/user/Pictures\n' > /home/user/.cache/c
	printf '\000sqlite /home/user/x' > /home/user/.local/share/db.sqlite
	chown -R user:user /home/user; chmod 600 /home/user/.config/plasmarc
	echo 'user:100000:65536' > /etc/subuid
	mkdir -p /var/lib/systemd/linger && touch /var/lib/systemd/linger/user
	mkdir -p /var/lib/utsugi-surya
}
unchanged() { [ "$(getent passwd 10000 | cut -d: -f1,6)" = "user:/home/user" ] && [ -d /home/user/.config ]; }

echo "== 1 normal rename"
reset; echo "10000 clara" > $REQ; sh $R >/dev/null; rc=$?
check '[ $rc = 0 ]' "exit 0"
check '[ "$(getent passwd 10000 | cut -d: -f1,6)" = "clara:/home/clara" ]' "passwd renamed, home path"
check '[ "$(getent group 10000 | cut -d: -f1)" = clara ]' "group renamed"
check 'id -nG clara | grep -qw wheel' "still in wheel"
check '[ -d /home/clara/.config ] && [ ! -e /home/user ]' "home moved"
check 'grep -qx "Image=/home/clara/Pictures/a.jpg" /home/clara/.config/plasmarc' "text path rewritten"
check 'grep -qx "Other=/home/username" /home/clara/.config/plasmarc' "longer name left alone"
check 'grep -q "/home/user/Pictures" /home/clara/.cache/c' "cache left alone"
check 'grep -q "/home/user/x" /home/clara/.local/share/db.sqlite' "binary left alone"
check '[ "$(stat -c "%U %a" /home/clara/.config/plasmarc)" = "clara 600" ]' "owner and mode kept"
check '[ -e /var/lib/systemd/linger/clara ] && grep -q "^clara:" /etc/subuid' "linger and subuid"
check '[ ! -e $REQ ] && [ ! -e $REQ.failed ]' "request consumed"

echo "== 1b running it again with the same request"
echo "10000 clara" > $REQ; sh $R >/dev/null; rc=$?
check '[ $rc = 0 ] && [ ! -e $REQ ]' "no-op, exit 0, request consumed"

for case in exists-user exists-group exists-home invalid process empty nouid; do
	echo "== refusal: $case"
	reset
	case $case in
		exists-user) useradd -M taken; echo "10000 taken" > $REQ ;;
		exists-group) groupadd taken2; echo "10000 taken2" > $REQ ;;
		exists-home) mkdir /home/clara; echo "10000 clara" > $REQ ;;
		invalid) echo "10000 Bad/Name" > $REQ ;;
		process) su user -s /bin/sh -c 'sleep 30' & sleep 1; echo "10000 clara" > $REQ ;;
		empty) : > $REQ ;;
		nouid) echo "12345 clara" > $REQ ;;
	esac
	sh $R >/dev/null; rc=$?
	check '[ $rc = 0 ]' "exit 0"
	check unchanged "account untouched"
	check '[ ! -e $REQ ]' "request consumed (no retry loop)"
	[ $case = process ] && kill %1 2>/dev/null; wait 2>/dev/null
	[ $case = exists-user ] && userdel taken; [ $case = exists-group ] && groupdel taken2
done

echo "== interrupted after the rename, before the home move"
reset; usermod -l clara user; echo "10000 clara" > $REQ; sh $R >/dev/null; rc=$?
check '[ $rc = 0 ] && [ ! -e $REQ ]' "exit 0, request consumed"
check '[ "$(getent passwd 10000 | cut -d: -f1,6)" = "clara:/home/user" ] && [ -d /home/user/.config ]' "account usable with its old home"

echo "== home move fails: name is put back"
reset; mkdir -p /fakebin
cat > /fakebin/usermod <<'SH'
#!/bin/sh
case " $* " in *" -m "*) echo "usermod: simulated move failure" >&2; exit 12 ;; esac
exec /usr/sbin/usermod "$@"
SH
chmod +x /fakebin/usermod
echo "10000 clara" > $REQ; PATH=/fakebin:$PATH sh $R >/dev/null 2>&1; rc=$?
check '[ $rc = 0 ]' "exit 0"
check unchanged "name and group put back"
check '[ "$(getent group 10000 | cut -d: -f1)" = user ]' "group put back"
check '[ ! -e $REQ ]' "request consumed"

echo "RESULT: $pass ok, $fail failed"
