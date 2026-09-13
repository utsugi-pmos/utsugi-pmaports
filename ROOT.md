# What this asks root for, and why

Building your own image needs your password a few times. A script you cloned
five minutes ago asking for one is a fair reason to stop, so here is each use,
in plain terms, with what it would do and what happens if you refuse.

You can check everything here yourself. Ours is `grep -n sudo scripts/*` — it is
short. The rest belongs to
[pmbootstrap](https://gitlab.postmarketos.org/postmarketOS/pmbootstrap), which is
postmarketOS's own tool and whose source is public.

**Flashing a ready-made image asks for none of this.** It is `fastboot` and
nothing else. What it cannot give you is an encrypted disk, because the
encryption key has to be made on your machine.

---

## First, what a "work directory" is

Everything happens inside one folder:

```
~/.local/var/pmbootstrap-utsugi/
```

It belongs to you. Inside it, `config_abuild/` is one small directory holding
the key that signs packages you build. pmbootstrap later hands that directory to
the build environment as `/home/pmos/.abuild`.

When you are finished, `rm -rf` on that folder removes every trace. Nothing is
installed on your system, nothing is written to `/etc`, and nothing outside that
folder is touched.

---

## 1. The signing key — and usually no root at all

**What it is.** Packages are signed so that a phone can tell they came from
whoever built them. `setup-workdir` makes you a key of your own the first time
you run it; the private half lives in `~/.abuild/` and never leaves your
machine.

**The problem.** Your key is mode `600` — only you can read it. But the thing
that signs is not you: builds run inside the chroot as a user called `pmos`,
which is uid **12345**. It cannot read your key, and the build then fails at its
very last step, after everything has already compiled, with

```
failed to sign ... Permission denied
```

**What is done about it.** One uid is granted read access to one file:

```sh
setfacl -m u:12345:r config_abuild/<your key>
```

That is an ACL, and **you can set one on your own file without root**. The
result:

```
user::rw-       you
user:12345:r--  the build user, read only
group::---
other::---      everybody else, nothing
```

The key is not made world-readable, and no ownership changes hands.

**When root is needed anyway.** ACLs need filesystem support. ext4, btrfs and
xfs have it on by default; something exotic, or a filesystem mounted `noacl`,
does not. Then the fallback is

```sh
sudo chown 12345:12345 config_abuild/<your key>
```

and root is required for one reason: **giving a file away is privileged, while
granting read access to it is not.** The script says which of the two it did.

**If you refuse:** nothing happens behind your back. The exact command is
printed, and you can run it in your own terminal after reading it:

```
  This filesystem has no ACLs, so one command has to run as root.
  It gives your signing key to the uid that builds inside the chroot.
  Nothing else here needs root.

      sudo chown 12345:12345 ~/.local/var/pmbootstrap-utsugi/config_abuild/<key> ...

  Run it in another terminal, then press enter.
```

Run `setup-workdir` again afterwards and it sees the key is already handed over
and leaves it alone. Refuse entirely and the work directory is still built --
only that one step is missing, and the build would fail when it tries to sign.

---

## Watching every root command as it happens

`sudo` prompts tell you something is about to happen and not what. This does:

```sh
UTSUGI_SHOW_ROOT=1 scripts/build-your-own-image --encrypted
```

Every privileged command pmbootstrap runs is printed before it runs &mdash;
mounts, chroots, `losetup`, `mkfs`, all of it. A build produces a few hundred
lines of that, so `UTSUGI_ROOT_LOG=/tmp/root.log` writes them to a file instead,
timestamped, which is easier to read afterwards than a build's worth of
scrollback.

It is not a promise about what the tool does. It is a transcript of what it
did.

---

## 2. The build environment — `chroot`, `mount`, `mknod`

**What it is.** A complete little Linux in a directory, so the build cannot see
or damage your system, and so the result does not depend on what you happen to
have installed.

**Why it needs root.** Three operations, all privileged on every Linux since
Unix:

- **`chroot`** — entering the directory as if it were `/`. Unprivileged users
  cannot, for an old and good reason: otherwise anyone could fake a `/etc/passwd`.
- **`mount`** — a working `/proc`, `/sys` and `/dev` have to appear inside it.
- **`mknod`** — creating device nodes. Inventing devices is not something an
  ordinary user is allowed to do.

**If you refuse:** nothing builds at all. This is pmbootstrap's normal way of
working, on every device it supports.

---

## 3. Treating a file as a disk — `losetup`, `parted`, `partprobe`

**What it is.** The image is a file that has to end up looking like a disk, with
a partition table the phone can read.

**Why it needs root.** A *loop device* is the kernel presenting a file as a
block device, and attaching one goes through the kernel. Writing a partition
table and asking the kernel to re-read it likewise.

**If you refuse:** the packages are all there and there is no image to flash.

---

## 4. The encryption itself — `cryptsetup`, `mkfs`, `dd`

**What it is.** `cryptsetup luksFormat` creates the encrypted container, a
filesystem is made inside it, and the boot image is written.

**Why it needs root.** They operate on the block device from step 3.

**This step is the reason this whole route exists.** The master key of a LUKS
volume is generated when the volume is formatted — here, on your machine, by
you. Changing the passphrase later replaces the slot that protects that key and
not the key itself, so an encrypted image handed out ready-made would give
whoever built it the master key of every phone flashed from it. Yours has to be
born where you are.

**If you refuse:** build the unencrypted image, or download it.

---

## The short version

| | |
|---|---|
| `setup-workdir` | usually **no root**: one ACL granting one uid read access to one file. Root only where ACLs are unavailable |
| the build | `chroot`, `mount`, `mknod` — pmbootstrap's build environment |
| the image | `losetup`, `parted`, `partprobe` — a file made to look like a disk |
| the encryption | `cryptsetup`, `mkfs`, `dd` — your LUKS container, your key |

Nothing installs anything on your system. Nothing is written outside
`~/.local/var/pmbootstrap-utsugi`. `rm -rf` on that folder undoes all of it.
