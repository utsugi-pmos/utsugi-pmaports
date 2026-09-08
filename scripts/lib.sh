# shellcheck shell=sh
# Shared paths and helpers. Sourced by every script in this directory.
#
# The golden rule of this repository: THIS TREE IS AUTHORITATIVE. pmbootstrap
# needs the aports to sit inside a pmaports checkout, so every script copies this
# tree into a throwaway checkout right before building (see overlay below). What
# lands there is disposable; what is committed here is the truth. The old
# workflow had it the other way around and the distribution lived in a directory
# that "pmbootstrap zap" deletes.

REPO="${REPO:-$(cd "$(dirname "$0")/.." && pwd)}"

# pmbootstrap itself, and a work directory SEPARATE from the user's own. Two
# reasons: the packages published here must all be signed with the repository
# key (the personal work dir signs with pmbootstrap's throwaway pmos@local one),
# and a release build must never depend on whatever state the daily work dir is
# in.
PMB="${PMB:-$HOME/src/pmbootstrap/pmbootstrap.py}"
WORK="${WORK:-$HOME/.local/var/pmbootstrap-utsugi}"
APORTS="${APORTS:-$WORK/pmaports}"
PMB_CFG="${PMB_CFG:-$REPO/.local/pmbootstrap-release.cfg}"

ARCH="${ARCH:-aarch64}"
# The channel directory. postmarketOS edge publishes under "main" (it is the
# pmaports branch name, see channels.cfg), NOT "master": pmbootstrap builds the
# mirror URL as <mirror>/<branch_pmaports>/<arch>/APKINDEX.tar.gz.
CHANNEL_DIR="main"
PKGS="$WORK/packages/edge/$ARCH"

# The URL every phone will carry in /etc/apk/repositories. It is a domain we
# control on purpose: GitHub redirects repository URLs after an account rename
# but NOT github.io pages, and this URL cannot change without breaking every
# installed phone.
REPO_URL="${REPO_URL:-https://pmaports.cidwel.com}"
GH_REMOTE="${GH_REMOTE:-git@github.com:jjolmo/utsugi-pmaports.git}"

red()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green(){ printf '\033[32m%s\033[0m\n' "$*"; }
grey() { printf '\033[90m%s\033[0m\n' "$*"; }
title(){ printf '\n\033[1m== %s\033[0m\n' "$*"; }
die()  { red "$*"; exit 1; }

pmb() { python3 "$PMB" -c "$PMB_CFG" -w "$WORK" -p "$APORTS" -y "$@"; }

# The name of the signing key. Frozen once the first package is signed: apk v2
# stores the signer's file name inside every package and looks for exactly that
# name in /etc/apk/keys.
keyname() {
	set -- "$REPO"/keys/*.rsa.pub
	[ -f "$1" ] || die "no key in $REPO/keys (run scripts/setup-workdir)"
	basename "$1" .pub
}

# Every aport in this repository, by package directory name.
all_aports() {
	find "$REPO/main" "$REPO/device" -mindepth 1 -maxdepth 3 -name APKBUILD \
		-printf '%h\n' 2>/dev/null | while read -r d; do basename "$d"; done | sort
}

aport_dir() {
	find "$REPO/main" "$REPO/device" -mindepth 1 -maxdepth 3 -type d -name "$1" \
		2>/dev/null | head -1
}

# Package directories touched between a git ref and the working tree. Walks up
# from each changed file to the directory that owns an APKBUILD, the same way
# pmaports' own CI decides what to rebuild.
changed_aports() {
	base="${1:-origin/main}"
	git -C "$REPO" diff --name-only "$base" -- main device 2>/dev/null | while read -r f; do
		d="$(dirname "$f")"
		while [ "$d" != "." ] && [ ! -f "$REPO/$d/APKBUILD" ]; do d="$(dirname "$d")"; done
		[ "$d" != "." ] && basename "$d"
	done | sort -u
}

# Copy this tree into the disposable pmaports checkout. Everything lands under
# one directory: every package name here is distinct from upstream's, so no
# upstream aport is ever overwritten and the checkout stays clean.
overlay() {
	[ -d "$APORTS" ] || die "no pmaports checkout at $APORTS (run scripts/setup-workdir)"
	mkdir -p "$APORTS/utsugi"
	rsync -a --delete --exclude '.git' "$REPO/main" "$REPO/device" "$APORTS/utsugi/"
}

# Read variables out of an APKBUILD without running its build. abuild helpers are
# stubbed out because sourcing is the only way to expand things like
# pkgver=9999$_pkgver; a plain grep gets those wrong.
apkbuild_get() { # <pkg> <variable>...
	d="$(aport_dir "$1")"
	[ -n "$d" ] || { red "unknown aport: $1"; return 1; }
	shift
	( cd "$d" && env -i bash -c '
		CARCH=aarch64; CBUILD=aarch64; CHOST=aarch64
		for f in amove default_doc default_openrc default_systemd default_udev \
		         default_dbg default_lang default_dev default_pyc default_py3 msg \
		         abuild-meson meson cmake make install strip scanelf; do
			eval "$f() { :; }"
		done
		# shellcheck disable=SC1091
		. ./APKBUILD || exit 1
		for v in "$@"; do eval "printf %s\\\\n \"\$$v\""; done
	' _ "$@" )
}

apkbuild_version() {
	set -- "$(apkbuild_get "$1" pkgver pkgrel)"
	printf '%s-r%s\n' "$(echo "$1" | sed -n 1p)" "$(echo "$1" | sed -n 2p)"
}

# pmbootstrap needs sudo and runs without a terminal, so sudo must be able to ask
# for the password through SUDO_ASKPASS. Only wired up when a password is
# actually available; otherwise the normal interactive sudo is left alone.
setup_sudo() {
	sudo -n true 2>/dev/null && return 0
	for f in "$REPO/.local/credentials" "$HOME/projects/vayu-postmarketos/surya/audio/credenciales.local"; do
		if [ -f "$f" ] && grep -q '^PMB_PW=' "$f"; then
			SUDO_ASKPASS="$REPO/scripts/askpass"
			PMB_SUDO="$REPO/scripts/sudo-wrap"
			export SUDO_ASKPASS PMB_SUDO
			grey "  sudo through SUDO_ASKPASS (pmbootstrap has no tty)"
			return 0
		fi
	done
	grey "  note: no cached sudo and no PMB_PW; pmbootstrap may block asking for it"
}
