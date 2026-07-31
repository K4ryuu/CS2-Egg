# VPK Sync Feature

Dramatically reduce storage and bandwidth by centralizing CS2 game files across all servers on a node.

## Overview

VPK Sync allows multiple CS2 servers to share game files from a single centralized location instead of each server maintaining its own complete copy.

**How It Works:**

1. A cron job keeps one centralized CS2 installation updated via SteamCMD
2. After each update, the script pushes game files directly into each server's volume - no Pterodactyl/Pelican mounts or manual configuration required
3. VPK files are shared via symlinks (default), hardlinks, or full copies depending on your `VPK_PUSH_METHOD` setting
4. A daemon watches for new containers and pushes files instantly on first start

> **No Pterodactyl/Pelican Panel modifications required.** The script works directly with Docker and Wings - no PR patches, no mount setup, no egg variable configuration.

## Boot Handshake (status file)

On every container boot the egg and the daemon talk through a single one-way file: `egg/.daemon-status` inside the server volume. The daemon writes it, the egg only reads it - nothing is ever deleted, so no boot-ordering race is possible.

```
state=queued|updating|verifying|pushing|done|failed
ts=<unix epoch of last write>
queue_pos=<n>            # only while queued
```

| State       | Meaning                                        | Egg behavior                              |
| ----------- | ---------------------------------------------- | ----------------------------------------- |
| `queued`    | Waiting for a free push worker                 | Waits, shows queue position               |
| `updating`  | Central CS2 update is rewriting `CS2_DIR`      | Waits, shows "central update in progress" |
| `verifying` | Worker is checking the volume's files          | Waits                                     |
| `pushing`   | Worker (or cron) is copying/linking game files | Waits                                     |
| `done`      | Files verified/pushed for this boot            | Skips SteamCMD, starts the server         |
| `failed`    | Push failed                                    | Falls back to SteamCMD immediately        |

Two rules make this race-proof:

- **Freshness**: the daemon refreshes `ts` every 3 seconds on all waiting states. If `ts` goes stale (>20s, `DAEMON_STATUS_STALE_SECS`), the daemon is dead and the egg falls back to SteamCMD - same recovery behavior as before, just detected faster.
- **Boot acknowledgement**: `done`/`failed` only count if `ts` is newer than the container's boot. A restart during a CS2 update therefore never starts on files that are mid-replacement - the egg waits for the daemon to re-verify this specific boot (typically 1-3s).

While `steamcmd` rewrites the central `CS2_DIR`, the update run holds a global lock. Workers handling a server start during that window report `updating` and verify only after the update finishes, so a restart mid-update simply waits instead of receiving half-written files or falling back to a full download.

Old eggs (images without the status protocol) keep working: the daemon still maintains the legacy `.daemon-managed` marker and `.daemon-push-active` heartbeat until **2026-10-01**, when the legacy path is removed together with the deprecated `SYNC_LOCATION` sync.

## Startup Performance

With the centralized script and VPK sync, new server startup is near-instant:

| Step                                    | Time           |
| --------------------------------------- | -------------- |
| Daemon detects container start          | ~0s            |
| Daemon mounts CS2_DIR into container    | 1-3s           |
| Entrypoint detects VPKs, skips SteamCMD | ~0s            |
| CS2 server process starts               | ~2s            |
| **Total (new server, first boot)**      | **~5 seconds** |

This replaces what would otherwise be a 10-30 minute SteamCMD download on first boot.

## Storage Savings

| Servers | Without Sync | With Sync | Savings      |
| ------- | ------------ | --------- | ------------ |
| 1       | 55GB         | 55GB      | 0GB (0%)     |
| 5       | 275GB        | 70GB      | 205GB (75%)  |
| 10      | 550GB        | 85GB      | 465GB (85%)  |
| 20      | 1.1TB        | 115GB     | 1025GB (86%) |
| 50      | 2.75TB       | 205GB     | 2.6TB (87%)  |

## Prerequisites

- Root access to the node
- Docker (standard on Pterodactyl/Pelican nodes)
- `rsync` - `apt-get install -y rsync`
- ~56GB free storage for one complete CS2 installation
- For `hardlink` mode: `CS2_DIR` and panel volumes must be on the same filesystem

## Installation

Run the installer as root - it handles everything:

```bash
curl -fsSL https://raw.githubusercontent.com/K4ryuu/CS2-Egg/main/misc/install-cs2-update.sh -o /tmp/install-cs2-update.sh && sudo bash /tmp/install-cs2-update.sh
```

The installer will:

1. Walk you through configuration (paths, push method, restart behavior)
2. Download the update script to `/usr/local/bin/update-cs2-centralized.sh`
3. Install and start the VPK push daemon as a systemd service
4. Register a cron job that runs every minute (rate-limited by `UPDATE_CHECK_INTERVAL`)

After installation, edit the config section at the top of the script to adjust any settings:

```bash
nano /usr/local/bin/update-cs2-centralized.sh
```

## Push Methods

| Method     | Panel disk usage | Writable       | Requirements                                |
| ---------- | ---------------- | -------------- | ------------------------------------------- |
| `symlink`  | ~0 per server    | No (read-only) | None - CS2_DIR auto-mounted into containers |
| `hardlink` | ~53GB per server | No (read-only) | Same filesystem as CS2_DIR                  |
| `copy`     | ~52GB per server | Yes            | None                                        |
| `off`      | -                | -              | -                                           |

**Symlink** (default) - symlinks from each server's volume to CS2_DIR. Panel sees near-zero disk usage. CS2_DIR is automatically bind-mounted read-only into each container so symlinks resolve correctly inside.

**Hardlink** - no extra physical disk space, but panel disk quota counts the full VPK size (~53GB) per server. Requires CS2_DIR on the same filesystem as panel volumes.

**Copy** - each server gets its own independent copy. Useful if servers need write access to game files.

## Quick Reference

```bash
# Run update manually
# If cron is currently running you'll get a lock error - wait a moment and retry
/usr/local/bin/update-cs2-centralized.sh

# Test push and restart logic (skip SteamCMD download)
/usr/local/bin/update-cs2-centralized.sh --simulate

# Health check + safe auto-fixes (run this FIRST when anything misbehaves)
/usr/local/bin/update-cs2-centralized.sh --doctor

# Self-update the script right now (daemon restarts automatically)
/usr/local/bin/update-cs2-centralized.sh --update

# Run the boot-handshake protocol tests (downloads from GitHub, cleans up after)
/usr/local/bin/update-cs2-centralized.sh --test

# Daemon status
systemctl status cs2-vpk-daemon

# Daemon logs (live)
journalctl -u cs2-vpk-daemon -f

# Update logs
tail -f /var/log/cs2-update.log
```

## Maintenance

### Script Self-Update

Enabled by default. The script checks GitHub for newer versions, preserves your configuration, validates syntax, and atomically replaces itself. Keeps last 3 backups in `.script-backups/`. Disable with `AUTO_UPDATE_SCRIPT="false"`.

### Monitoring

```bash
tail -f /var/log/cs2-update.log
journalctl -u cs2-vpk-daemon --since "1 hour ago"
```

## Troubleshooting

**Always start with the doctor** - it checks the whole setup (script/service/cron paths, daemon state, dependencies, per-server status files, disk space, locks), fixes what it safely can, and prints the exact command for everything else:

```bash
sudo /usr/local/bin/update-cs2-centralized.sh --doctor
```

Its output is also the ideal thing to paste into a GitHub issue.

> The script automatically handles: SteamCMD installation, 32-bit library setup, permissions, Steam SDK libraries, and directory creation.

> **Doctor says reinstall?** Re-run the installer - it resets config to working defaults while offering your current values as starting points:
>
> ```bash
> curl -fsSL https://raw.githubusercontent.com/K4ryuu/CS2-Egg/main/misc/install-cs2-update.sh -o /tmp/install-cs2-update.sh && sudo bash /tmp/install-cs2-update.sh
> ```

### Cross-Filesystem Hardlink Error

**Error:** `Cross-filesystem hardlink not possible for ptero-xxxx`

`CS2_DIR` and panel volumes are on different partitions.

```bash
# Check filesystems
df -h /srv/cs2-shared
df -h /var/lib/pterodactyl/volumes
df -h /var/lib/pelican/volumes

# Option A: move CS2_DIR onto the same partition as volumes
# Option B: switch to copy mode - edit VPK_PUSH_METHOD="copy" in the script
```

### Cron Job Not Running

Scheduling lives in **`/etc/cron.d/cs2-update`** (runs every minute, rate-limited by `UPDATE_CHECK_INTERVAL`) - never add the script to root's crontab. `--doctor` recreates a missing cron file, rewrites a dead path in it, and removes duplicate crontab entries automatically. To test an update manually: `sudo /usr/local/bin/update-cs2-centralized.sh`

## FAQ

**Q: Do I need to modify Pterodactyl/Pelican Panel or apply any patches?**
No. The script works directly with Docker and Wings.

**Q: Do I need to configure anything on individual servers?**
No. Files are pushed directly into each server's volume from the host.

**Q: What if the cron job fails?**
Servers continue using existing files. The daemon still handles new containers. Run manually to trigger a push: `/usr/local/bin/update-cs2-centralized.sh --simulate`.

**Q: What's the difference between the cron job and the daemon?**
The cron job handles CS2 updates and pushes to all existing servers. The daemon handles new servers - it reacts instantly when a container starts so game files are present before the startup script runs.

**Q: Can I use VPK sync without the daemon?**
Yes. Without the daemon, new servers receive files on the next cron cycle (~2 minutes). For most setups this is fine since CS2 startup takes longer than that anyway.

**Q: How many servers does the daemon handle in parallel?**
File pushes run on a worker pool, 8 parallel workers by default. Symlink mounts are instant and unlimited. The installer asks for the pool size (`MAX_WORKERS`), or edit it later in `/usr/local/bin/update-cs2-centralized.sh` and restart the daemon.

**Q: How do I test a prerelease (dev) version?**
Run the installer with the branch override, and use the matching image tag on the server:

```bash
curl -fsSL https://raw.githubusercontent.com/K4ryuu/CS2-Egg/dev/misc/install-cs2-update.sh -o /tmp/install-cs2-update.sh && sudo CS2_EGG_BRANCH=dev bash /tmp/install-cs2-update.sh
```

Set the server's Docker image to `docker.io/sples1/k4ryuu-cs2:dev` in the panel (the dev image is only published to Docker Hub). The installed script's self-update tracks the same branch, so it won't overwrite itself with the stable version. To go back, rerun the installer without `CS2_EGG_BRANCH` and switch the image back to `:latest`.

If the testing branch is later deleted (merged into main), the script notices the 404 and switches its self-update back to `main` automatically - just remember to switch the Docker image back to `:latest` yourself.

## Support

- [Report Issue](https://github.com/K4ryuu/CS2-Egg/issues)
- [View Update Script](https://github.com/K4ryuu/CS2-Egg/blob/main/misc/update-cs2-centralized.sh)
- [View Installer](https://github.com/K4ryuu/CS2-Egg/blob/main/misc/install-cs2-update.sh)
