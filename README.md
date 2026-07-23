# aegix-backup

Config-driven, encrypted, **tested-restore** disaster recovery for [Aegix Linux](https://aegixlinux.org)
(and any Artix/Arch system running runit). One shell script, no daemons, no systemd.

The design goal is not elegant backups. It is a **boring, certain restore**:

> A backup you haven't booted is a hypothesis, not a backup.

## What it does

Three legs, each covering a failure the others don't:

| Leg | Medium | Survives |
|---|---|---|
| **Bootable clone(s)** — full system, independently bootable | internal second disk and/or external drive (LUKS + btrfs) | dead primary drive (boot the internal clone from the firmware menu in minutes); lost/stolen/destroyed machine (boot the external clone on other hardware) |
| **Pictures offsite** — restic → Hugging Face mirror | always-present internal LUKS disk → HF dataset repo | everything local at once; only ciphertext ever leaves the machine |
| **Notes → git remote** | your notes repo → GitHub/other | everything local, with history |

Everything runs unattended from one nightly `cron.daily` entry (anacron catches up missed days).
A clone target that isn't plugged in is skipped, not an error.

## Why you might want it

- **Clones are made bootable on every run**: fstab/crypttab/GRUB are repointed at the target's own
  UUIDs, GRUB is installed for **both** BIOS and UEFI, and a **fallback initramfs** (all modules,
  not just this machine's) is built so the clone boots on *unfamiliar replacement hardware*.
- **Recovery-mode aware**: booted from a clone, the tool still works — it snapshots whatever system
  is actually running, and refuses to clone a running system onto itself.
- **runit/udev native**: boot one-shots and a udev hotplug rule, no systemd units, no crypttab
  assumptions (Artix/runit doesn't process it).
- **Plug-in browse**: the external drive auto-mounts **read-only** when plugged in; internal clones
  are inspectable on demand via `clone-browse`/`clone-unbrowse`.
- **Honest failure handling**: rsync 23/24 and restic exit 3 are warnings (logged), everything else
  fails loudly to your desktop via notify-send. Several of this tool's design decisions exist
  because a "successful" backup was silently broken — see `RECOVERY.md` and the code comments.
- **Offsite guard files**: the HF mirror regenerates `README.md`/`AGENTS.md` inside the repo every
  sync, telling humans *and AI agents* sharing the account not to delete/prune the backup.

## Install

```sh
git clone https://github.com/timbeach/aegix-backup
cd aegix-backup
sudo ./install.sh
sudoedit /etc/aegix-backup.conf     # replace every <PLACEHOLDER>
sudo aegix-backup preflight
```

You will also need, per clone target: a partitioned disk (legacy firmware: MBR with a ~1 GB
boot-flagged FAT32 + LUKS2→btrfs `@`/`@home`; UEFI-only firmware such as Framework laptops: GPT
with a 1 MB BIOS-boot partition + ~1 GB ESP + LUKS2 — the tool detects the table type and installs
the right GRUB paths), a keyfile keyslot (for unattended runs) and a passphrase keyslot (to unlock
at boot). `RECOVERY.md` §3 walks through provisioning a fresh target.

The notes and pictures/offsite legs are **optional** — leave `NOTES_REPO` / the restic block
unset for a clone-only install (e.g. a one-drive-slot laptop with an external clone target).

Then arm the nightly (already installed by `install.sh` as `/etc/cron.daily/aegix-backup`) by
making sure cronie + anacron run. Test everything first:

```sh
sudo aegix-backup --dry-run daily    # show the whole nightly without doing it
sudo aegix-backup clone-daily        # first real clone
sudo aegix-backup clone-browse internal   # look inside it, read-only
```

**Then boot your clone once, on purpose, while your system still works.** That is the test that
matters; everything else is supporting machinery.

## Commands

```
preflight                     check prerequisites and config sanity
clone-daily | clone-weekly    clone to every configured target (weekly = fewer excludes)
clone-bootfix [target]        re-apply bootability only (no rsync)
clone-browse <t> | clone-unbrowse <t>   read-only look inside a clone
videos                        add-only top-up of Videos to the external
pictures                      restic backup -> prune -> HF mirror (with guard files)
notes-push                    commit+push the notes repo (plaintext-vault guard)
ext-snapshot                  btrfs snapshots on the external, with retention
daily | now                   the scheduled nightly set
automount-up|down|sync        used by the udev/runit hotplug plumbing
local-up                      unlock+mount the internal restic disk (boot service)
--dry-run <cmd>               show what would happen
```

## Hard-won lessons baked in

The code comments document each of these where they're enforced — they were all found the hard way:

- rsync exclude patterns anchor at the **transfer root**, not `/` — `/home/user/X` silently
  matches nothing when the transfer root is the `@home` subvolume.
- `--exclude=/tmp` also means rsync never *creates* `/tmp` — a fresh clone had no `/tmp`,
  `/proc`, `/sys`, `/dev`, `/run`, and was a broken system. Skeleton dirs are recreated every run.
- Excluding a gocryptfs mountpoint directory (instead of its contents with `/**`) leaves a
  recovered system with ciphertext and **no mountpoint to open it on**.
- `lsblk -no pkname | head -1` hands you a **partition** or an **empty string** depending on
  device type and mapper state — resolve disks with `lsblk -rnso NAME | tail -1`.
- The default initramfs (`autodetect`) contains **zero** storage drivers for other machines.
  A travel clone needs the fallback image.
- NVMe device names swap between reboots. Identify disks by UUID/model/serial, never `nvmeXn1`.
- A backup tool must not swallow "success with warnings" as failure (restic exit 3 aborted the
  offsite upload for weeks) — nor report failure as success (rsync exit codes were being eaten).

## Recovery

Read **`RECOVERY.md`** now, not during the disaster. Keep a copy somewhere that isn't the machine
being recovered.

## License

MIT
