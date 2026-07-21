#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }

# ---- core tool + config ----
install -Dm755 aegix-backup /usr/local/sbin/aegix-backup
install -Dm755 cron/aegix-backup.daily /etc/cron.daily/aegix-backup
[ -e /etc/aegix-backup.conf ] || install -Dm600 aegix-backup.conf.example /etc/aegix-backup.conf
mkdir -p /var/log/aegix-backup

# ---- read values needed for auto-mount from the live config ----
CONF=/etc/aegix-backup.conf
# shellcheck disable=SC1090
. "$CONF"

# ---- runit scan dir (where enabled services are supervised) ----
SVDIR=/run/runit/service
for d in /run/runit/service /var/service /service /etc/service; do
  [ -d "$d" ] && { SVDIR="$d"; break; }
done

# ---- local restic disk: runit boot service to unlock+mount the always-present internal LUKS SSD ----
# Installed whenever LOCAL_LUKS_UUID is configured (crypttab is not processed on Aegix/runit).
if [ -n "${LOCAL_LUKS_UUID:-}" ]; then
  install -Dm755 sv/aegix-restic-mount/run /etc/runit/sv/aegix-restic-mount/run
  rm -f /etc/runit/sv/aegix-restic-mount/down       # NO down file -> runsvdir starts it once at boot
  ln -sfn /etc/runit/sv/aegix-restic-mount "$SVDIR/aegix-restic-mount"
  echo "Local restic disk boot-mount installed -> unlocks $LOCAL_MAPPER, mounts ${LOCAL_MNT:-/mnt/aegix-restic}"
  echo "  (requires: cryptsetup luksFormat/luksAddKey with $LOCAL_KEYFILE)"
fi

# ---- interactive auto-mount: runit one-shot + udev rule + udev->runit wrapper ----
if [ "${AUTOMOUNT_ENABLE:-0}" = 1 ]; then
  # service definition (Artix/runit convention: defs in /etc/runit/sv, enable by symlink into SVDIR)
  # (1) hotplug one-shot: stays down at boot; only udev's `sv once` starts it on plug/unplug.
  install -Dm755 sv/aegix-automount/run /etc/runit/sv/aegix-automount/run
  : > /etc/runit/sv/aegix-automount/down            # stays down at boot; only `sv once` starts it
  ln -sfn /etc/runit/sv/aegix-automount "$SVDIR/aegix-automount"

  # (2) boot one-shot: NO `down` file, so runsvdir runs it once at boot to catch a drive that was
  # already plugged in (udev coldplug fires before supervision is up, so the hotplug rule misses it).
  install -Dm755 sv/aegix-automount-boot/run /etc/runit/sv/aegix-automount-boot/run
  rm -f /etc/runit/sv/aegix-automount-boot/down
  ln -sfn /etc/runit/sv/aegix-automount-boot "$SVDIR/aegix-automount-boot"

  # udev -> runit bridge (bake in the discovered scan dir)
  install -d /usr/local/lib/aegix-backup
  sed "s#__SVDIR__#$SVDIR#g" lib/automount-udev.in > /usr/local/lib/aegix-backup/automount-udev
  chmod 755 /usr/local/lib/aegix-backup/automount-udev

  # udev rule (bake in the drive's LUKS UUID from config)
  sed "s#__EXT_LUKS_UUID__#$EXT_LUKS_UUID#g" udev/99-aegix-automount.rules.in \
    > /etc/udev/rules.d/99-aegix-automount.rules
  udevadm control --reload-rules && udevadm trigger --subsystem-match=block 2>/dev/null || true
  echo "Auto-mount installed: plug the drive in -> read-only mount at ${AUTOMOUNT_MNT:-/mnt/aegixbackup}"
  echo "  (requires the keyfile keyslot: cryptsetup luksAddKey ... $EXT_KEYFILE)"
fi

echo
echo "Installed. Edit $CONF if needed, then run: aegix-backup preflight"
echo "Ensure anacron is enabled (Aegix/runit): sv up anacron  (or your distro's anacron service)"
