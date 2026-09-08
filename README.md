# utsugi-pmaports

postmarketOS packages for phones I actually use: a signed apk repository, so a
clean postmarketOS install becomes a working phone with `apk add`, and stays
current with `apk upgrade`.

postmarketOS is Alpine-based, so this is **apk**, not apt.

| Device | Codename | Status |
|---|---|---|
| POCO X3 NFC | `xiaomi-surya` (generic port `qcom-sm7150`) | cameras, in-call voice, volume, sensors, GPS, real power-off |
| POCO X3 Pro | `xiaomi-vayu` | **experimental**, the modem does not work |

## Install it on a phone

```sh
KEY=<the key file name, see the repository index page>
sudo wget -qO /etc/apk/keys/$KEY https://utsugi-pmos.github.io/utsugi-pmaports/keys/$KEY
echo https://utsugi-pmos.github.io/utsugi-pmaports/main | sudo tee -a /etc/apk/repositories
sudo apk update
sudo apk add utsugi-surya-full
```

Two levels, pick one:

- **`utsugi-surya-base`** -- what makes the hardware work: the patched kernel,
  audio, sensors, GPS, power-off, charge mode, cameras.
- **`utsugi-surya-full`** -- base plus the applications and the Plasma Mobile
  fixes.

Personal preferences (which browser, ad-blocking DNS, Telegram scaling, web app
launchers) are deliberately **not** in either: they live in the interactive
`surya-setup` tool, because they are choices, not fixes.

> **The kernel comes with `base`, and a kernel that fails to boot on the surya
> costs a reboot loop:** the watchdog fires 20 s after PID 1. Reboot as a
> separate, deliberate step, with a way back in (see `flash/surya.md`).

## Why the package names have a `-utsugi` suffix

Most of what is here is a **fork of an upstream package**: the same files, with
patches upstream does not carry. Two packages installing the same files fight,
so each fork uses its own name and claims upstream's with a versioned
`provides` plus `replaces`:

```sh
_orig=hexagonrpcd
pkgname=$_orig-utsugi
provides="$_orig=$pkgver-r$pkgrel"
replaces="$_orig"
```

apk then refuses to have both installed, everything that depends on
`hexagonrpcd` is satisfied by ours, and an upstream release cannot silently
replace it, because nothing installed is called `hexagonrpcd` any more. This is
the pattern postmarketOS documents for forks; `provider_priority` is
deliberately not used with a versioned provides.

The trade-off: when upstream moves to a newer version, nothing tells the phone.
`scripts/check-upstream` is that alarm, and it is meant to be run before every
publish.

## Layout

| Path | What |
|---|---|
| `main/` | packages that work on any Plasma Mobile postmarketOS |
| `device/xiaomi-surya/` | kernel, ALSA profile, tweaks and metapackages for the surya |
| `device/xiaomi-vayu/` | the same for the vayu, experimental |
| `scripts/` | build, bump, publish, image, sideload, lint |
| `flash/` | how to flash each device, and how to get back in when it does not boot |
| `keys/` | the public half of the signing key |
| `upstream.lock` | the pmaports commit these packages are built against |

## Building it yourself

```sh
scripts/setup-workdir      # separate pmbootstrap work dir, pinned pmaports, signing key
scripts/build --all        # everything (the kernel takes minutes)
scripts/lint               # fork bookkeeping and version bumps
scripts/publish            # assemble and sign the repository
scripts/publish --push     # ...and put it on GitHub Pages
```

The tree here is authoritative. pmbootstrap needs the aports inside a pmaports
checkout, so every script copies this tree into a throwaway one first. The old
workflow kept the distribution *inside* that checkout, which `pmbootstrap zap`
deletes.

**Always bump before rebuilding.** pmbootstrap skips a build whose
`pkgver-pkgrel` already exists in any index it knows and reports success, so a
forgotten bump looks like a publish that changed nothing:

```sh
scripts/bump <pkg>         # pkgrel + 1 and refresh the checksums
```
