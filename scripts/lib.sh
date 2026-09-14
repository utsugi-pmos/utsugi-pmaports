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
REPO_URL="${REPO_URL:-https://utsugi-pmos.github.io/utsugi-pmaports}"
GH_REMOTE="${GH_REMOTE:-git@github.com:utsugi-pmos/utsugi-pmaports.git}"

# owner/repo, the form the gh CLI wants for --repo. In CI, $GITHUB_REPOSITORY is
# already exactly that; otherwise derive it from the remote. The derivation must
# handle BOTH git@host:owner/repo.git AND https://host/owner/repo.git -- the old
# 's|.*:||' only stripped to the last colon, so the https remote CI uses turned
# into //host/owner/repo and gh answered 422, failing every packages run.
GH_REPO="${GITHUB_REPOSITORY:-$(printf '%s' "$GH_REMOTE" | \
	sed -E 's#^[a-z]+://[^/]+/##; s#^[^/]*:##; s#\.git$##')}"

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
	# --checksum, and it is not paranoia: rsync decides by size and mtime, and a
	# pkgrel going from 1 to 2 changes neither the size nor, within the same
	# second, the timestamp. Bumps were silently not reaching the checkout, so a
	# rebuild kept producing the previous version.
	rsync -a --delete --checksum --exclude '.git' "$REPO/main" "$REPO/device" "$APORTS/utsugi/"
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
# for the password through SUDO_ASKPASS.
setup_sudo() {
	# ALWAYS route pmbootstrap's privileged calls through the wrapper.
	#
	# It used to be wired up only when sudo was not already cached, which meant
	# UTSUGI_SHOW_ROOT and UTSUGI_NO_SUDO -- the two things that let somebody
	# watch or withhold what runs as root -- did nothing in the ordinary case,
	# where sudo IS cached. The wrapper is a pass-through unless one of those is
	# set, so there is no cost to always using it.
	PMB_SUDO="$REPO/scripts/sudo-wrap"
	export PMB_SUDO

	[ -n "${UTSUGI_NO_SUDO:-}" ] && { grey "  root commands will be printed for you to run (UTSUGI_NO_SUDO)"; return 0; }
	sudo -n true 2>/dev/null && return 0

	# A password file, if there is one. UTSUGI_CREDENTIALS points at it; the
	# default lives beside this repository and is gitignored. There used to be a
	# second path hardcoded here into one particular person's home directory,
	# which is no business of a public repository.
	for f in "${UTSUGI_CREDENTIALS:-}" "$REPO/.local/credentials"; do
		[ -n "$f" ] || continue
		if [ -f "$f" ] && grep -q '^PMB_PW=' "$f"; then
			SUDO_ASKPASS="$REPO/scripts/askpass"
			export SUDO_ASKPASS
			grey "  sudo through SUDO_ASKPASS (pmbootstrap has no tty)"
			return 0
		fi
	done
	grey "  note: sudo is not cached. pmbootstrap will ask for it, or run with"
	grey "  UTSUGI_NO_SUDO=1 to be given each command to run yourself."
}

# The platform to run containers on: the host's own, computed rather than
# assumed. Not for portability -- docker caches an image by TAG, so pulling
# alpine:edge for another architecture (a container test of the phone's own
# aarch64, say) silently replaces what "alpine:edge" means on this machine, and
# the next run dies with "exec /bin/sh: no such file or directory" and no hint.
# That happened on 2026-09-13 and left the install page pointing at an image the
# latest release did not have. A fixed "linux/amd64" would have been worse: CI
# builds images on an arm64 runner, and that call would have been emulated.
DOCKER_PLATFORM="linux/$(docker version -f '{{.Server.Arch}}' 2>/dev/null || uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
export DOCKER_PLATFORM
