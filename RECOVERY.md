# Recovery runbook

Follow this top to bottom. It assumes nothing and is meant to be usable while tired and stressed.

**Print this, or keep it on your phone.** A runbook that only exists on the machine you just lost
is not a runbook.

---

## 0. Triage — which situation are you in?

| Situation | Go to |
|---|---|
| Machine boots, but the primary drive is failing/dead | **§1** — boot the internal clone |
| Machine is gone (lost, stolen, destroyed) | **§2** — boot the external clone elsewhere |
| You have a replacement drive and want to get back to normal | **§3** |
| You just need files, not a system | **§4** |

---

## 1. Primary drive died — boot the internal clone

The fastest path. There is **no restore step**: the clone *is* a complete system.

1. Power on, open the firmware boot menu (ThinkPad: **F12**).
2. Choose the clone's disk. **Identify it by MODEL, not by `nvme0`/`nvme1`** — Linux NVMe naming is
   not stable across reboots, and the firmware's numbering is its own thing.
3. Enter the LUKS passphrase at the initramfs prompt.
4. **Confirm you are on the clone, not the original:**
   ```sh
   findmnt -no SOURCE /      # expect the CLONE's mapper name, not the system's
   ```
   If you see the *system's* mapper, you booted the wrong entry — reboot and pick the other one.

You can now work indefinitely from the clone. Do §3 when convenient.

> ⚠️ While running from the clone, the nightly job will **skip** the disk you booted from (it
> refuses to clone a running system onto itself). Other targets still work normally.

---

## 2. Machine gone — boot the external clone on other hardware

1. Attach the external clone drive to any x86_64 machine.
2. In that machine's boot menu, select the external drive. Both **legacy/BIOS and UEFI** boot paths
   are installed, so pick whichever the firmware offers.
3. At the GRUB menu choose the **fallback** entry (under *Advanced options*). The default image is
   built with `autodetect` and contains drivers for the *original* machine only; the fallback
   contains every module and is what boots on unfamiliar hardware.
4. Enter the LUKS passphrase, then verify with `findmnt -no SOURCE /`.

> If the firmware will not offer the drive at all, that is a firmware/enclosure problem, not a
> problem with the clone. Fastest workaround: take the drive out of its enclosure and fit it
> **internally** in the replacement machine, then boot it directly.

---

## 3. Rebuild onto a replacement drive

Do this from a running system (your recovered clone is fine).

1. Fit the new drive. Identify it **by model/serial**, never by `/dev/nvmeXn1`.
2. Provision it to match a bootable layout: MBR, a ~1 GB FAT32 partition with the **boot flag**,
   then the rest as LUKS2 → btrfs with `@` and `@home` subvolumes.
3. Add a **keyfile** keyslot (for unattended backups) *and* a **passphrase** keyslot (you need this
   to unlock at boot; a keyfile-only volume cannot be unlocked at the initramfs prompt).
4. Add it to `CLONE_TARGETS` in the config with its own `TGT_<name>_*` UUIDs.
5. Run `aegix-backup preflight`, then `aegix-backup clone-daily`.
6. Verify it is bootable before trusting it:
   ```sh
   aegix-backup clone-browse <name>     # read-only look inside
   # then actually boot it once
   ```

**A backup you have not booted is a hypothesis, not a backup.**

---

## 4. Just need files back

```sh
aegix-backup clone-browse <target>     # read-only mount, safe
# ... copy what you need ...
aegix-backup clone-unbrowse <target>
```

### What is NOT in the clone

The clone is **system** recovery, not complete data recovery. By design it excludes:

| Excluded | Where it actually lives |
|---|---|
| `Pictures` | the restic repo → mirrored offsite |
| `Videos` | the external drive (`videos` subcommand) |
| caches, `node_modules`, package caches | regenerable, not backed up |

Restore Pictures from the offsite restic repo:
```sh
restic -r <repo> snapshots
restic -r <repo> restore latest --target /somewhere
```
You need the **restic password** and the **remote token**. If both are lost, the offsite copy is
unrecoverable ciphertext — keep them somewhere other than this machine.

---

## 5. Sanity checks worth knowing

```sh
findmnt -no SOURCE /                  # which system am I actually running?
lsblk -o NAME,MODEL,SERIAL,FSTYPE,LABEL,UUID   # identify disks by model/serial, never by name
aegix-backup preflight                # config + prerequisites sane?
tail -n 40 /var/log/aegix-backup/aegix-backup.log
```

**Never identify a disk by `/dev/nvme0n1` vs `/dev/nvme1n1`.** That numbering changes between
boots. Every destructive step here keys off UUID, model, or serial for exactly that reason.
