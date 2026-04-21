# Error Codes

> **Can't find your error here, or the fix didn't work?**
> Open a [bug report](https://github.com/K4ryuu/CS2-Egg/issues/new/choose) — include the `KL-XXX-NN` code, the full log output, your egg version, Docker image tag, and (if host-side) the daemon status.

Every fatal error in the KitsuneLab egg and the centralized update daemon emits a stable code. Look it up here to see what it means, how to diagnose it, and how to fix it.

## Index

- [KL-DMN — Daemon / VPK Sync](#kl-dmn--daemon--vpk-sync)
- [KL-STM — SteamCMD](#kl-stm--steamcmd)
- [KL-HOST — Host-side daemon installer](#kl-host--host-side-daemon-installer)
- [KL-SRV — Server runtime](#kl-srv--server-runtime)

---

## KL-DMN — Daemon / VPK Sync

### KL-DMN-01 — Daemon marker stale

**Symptom**: `[KL-DMN-01] Daemon marker stale (Xs > Ys)`

**Meaning**: The centralized VPK daemon stopped refreshing the heartbeat file (`/home/container/egg/.daemon-managed`). The daemon process almost certainly died on the host.

**Auto-recovery**: The egg removes the stale marker + broken VPK symlinks, then falls back to SteamCMD so the server still boots.

**Diagnose (on host)**:
```bash
sudo systemctl status cs2-vpk-daemon
sudo journalctl -u cs2-vpk-daemon -n 100 --no-pager
```

**Fix**:
1. Restart: `sudo systemctl restart cs2-vpk-daemon`
2. If service is missing, install it:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/K4ryuu/CS2-Egg/main/misc/install-cs2-update.sh -o /tmp/install-cs2-update.sh
   sudo bash /tmp/install-cs2-update.sh
   ```
3. Don't want the daemon anymore? Stop it (`sudo systemctl disable --now cs2-vpk-daemon`) and delete `.daemon-managed` from every server volume.

---

### KL-DMN-02 — Daemon bind-mount timeout

**Symptom**: `[KL-DMN-02] Daemon mount wait timed out after Xs`

**Meaning**: Daemon marker is fresh (daemon is alive), but `/tmp/cs2-shared` never got bind-mounted into the container. The VPK symlinks will point to an empty mount → CS2 will fail to load game files.

**Diagnose (on host)**:
```bash
sudo journalctl -u cs2-vpk-daemon -n 100 --no-pager | grep nsenter
python3 -c "import ctypes; print(ctypes.CDLL(None).syscall)"   # open_tree/move_mount syscalls need python3
```

**Fix**:
1. Ensure `python3` is installed on the host: `apt-get install -y python3`
2. Ensure kernel ≥ 5.2 (Ubuntu 20.04+): `uname -r`
3. Restart the daemon: `sudo systemctl restart cs2-vpk-daemon`
4. Increase budget if the host is under heavy load: set env `DAEMON_MOUNT_WAIT_SECS=60` on the server.

---

### KL-DMN-05 — Legacy SYNC_LOCATION directory not found

**Symptom**: `[KL-DMN-05] SYNC_LOCATION directory not found: <path>`

**Meaning**: The `SYNC_LOCATION` environment variable is set but points to a path that doesn't exist inside the container. Usually a misconfigured mount.

**Auto-recovery**: Egg skips VPK sync and proceeds to SteamCMD.

**Fix**:
1. If you're using the centralized daemon now, just **remove `SYNC_LOCATION`** from your server startup variables — the daemon marker supersedes it.
2. If you're still on the legacy setup: verify the Pterodactyl/Pelican **Mount** is active and maps host `/srv/cs2-shared` (or your path) into `SYNC_LOCATION` inside the container.

`SYNC_LOCATION` is deprecated and will be removed after **2026-10-01**. Migrate to the centralized daemon.

---

### KL-DMN-06 — Legacy base file sync failed

**Symptom**: `[KL-DMN-06] Failed to sync base files`

**Meaning**: `rsync` from `SYNC_LOCATION` into `/home/container` failed. Usually permission or disk-full.

**Diagnose**:
```bash
df -h /home/container
ls -la "$SYNC_LOCATION"
```

**Fix**:
1. Free disk space.
2. Check file ownership on the host — the Pterodactyl user must be able to read `SYNC_LOCATION`.
3. Migrate to the centralized daemon (same rationale as [KL-DMN-05](#kl-dmn-05--legacy-sync_location-directory-not-found)).

---

## KL-STM — SteamCMD

### KL-STM-01 — SteamCMD exit code 8 (connection error)

**Symptom**: `[KL-STM-01] SteamCMD connection error (exit code 8)`

**Meaning**: SteamCMD couldn't reach Steam servers or was rejected (TCP reset, DNS failure, or Steam is down).

**Diagnose**:
1. Check Steam server status: [steamstat.us](https://steamstat.us/)
2. From the host: `curl -sI https://steamcdn-a.akamaihd.net/` — should return `HTTP/2 200` or similar.
3. Check for VPN / proxy that might blackhole Steam CDN.

**Fix**:
1. Ensure ≥ 60-70 GB free disk (3 GB if daemon-synced). Run `df -h /home/container`.
2. Disable any VPN/proxy in the container's egress path.
3. Retry — if Steam itself is in outage, there's nothing the egg can do.

---

### KL-STM-02 — SteamCMD generic failure

**Symptom**: `[KL-STM-02] SteamCMD failed with exit code <N>`

**Meaning**: SteamCMD exited non-zero, but not with the well-known code 8. Common values: `7` (no subscription / appid access), `1` (generic), `42` (steamcmd bug).

**Fix**:
1. Check the SteamCMD output just above this line for the actual cause.
2. `SRCDS_APPID=730` for CS2. Verify it isn't overridden.
3. If you're using an account login (`SRCDS_LOGIN`), verify the credentials.

---

### KL-STM-03 — State 0x202 (disk space / filesystem)

**Symptom**: `[KL-STM-03] SteamCMD Error 0x202 - Disk space or filesystem issue`

**Meaning**: SteamCMD ran out of disk or hit a filesystem permission / readonly issue.

**Fix**:
1. `df -h /srv/cs2-shared` — CS2 needs **~60 GB** for a fresh install.
2. Check that the mount isn't read-only: `mount | grep cs2-shared`.
3. Clear incomplete downloads: `rm -rf /srv/cs2-shared/steamapps/downloading` then re-run.

---

### KL-STM-04 — State 0x??? (generic SteamCMD state)

**Symptom**: `[KL-STM-04] SteamCMD Error 0x<hex> detected`

**Meaning**: SteamCMD returned an unmapped state code. Refer to SteamCMD documentation; most codes indicate validation or network failures.

**Fix**: Check the SteamCMD output above the code for the real cause. Try a re-run with `VALIDATE_INSTALL="true"`.

---

### KL-STM-05 — SteamCMD download failed (container-side)

**Symptom**: `[KL-STM-05] Failed to download SteamCMD after N attempts`

**Meaning**: The egg couldn't fetch the SteamCMD installer from `steamcdn-a.akamaihd.net`. Usually network policy or DNS.

**Fix**:
1. Verify outbound HTTPS works inside the container: `curl -sI https://steamcdn-a.akamaihd.net/`
2. Check your node's firewall / egress rules.
3. Retry — transient CDN failures resolve quickly.

---

### KL-STM-06 — SteamCMD extract failed

**Symptom**: `[KL-STM-06] Failed to extract SteamCMD`

**Meaning**: The downloaded tarball was corrupted or `tar` failed.

**Fix**:
1. Remove the partial archive: `rm -rf /home/container/steamcmd`
2. Re-run — the egg will re-download on next boot.
3. If persistent: check for disk-full (`df -h`).

---

### KL-STM-07 — SteamCMD directory missing

**Symptom**: `[KL-STM-07] steamcmd directory does not exist`

**Meaning**: After extract, `/home/container/steamcmd` wasn't created. The archive was likely malformed or another process deleted it mid-install.

**Fix**: Force-reinstall — delete `/home/container/steamcmd` and restart. If it keeps failing, check for hostile cleanup scripts or antivirus interfering with container volumes.

---

## KL-HOST — Host-side daemon installer

### KL-HOST-01 — Not root

**Symptom**: `[KL-HOST-01] Requires root. Re-executing with sudo...` (or similar permission-denied)

**Fix**: Run the installer with `sudo`:
```bash
sudo bash install-cs2-update.sh
```

---

### KL-HOST-02 — Installer download failed

**Symptom**: `[KL-HOST-02] Download failed - check internet access`

**Meaning**: `curl` / `wget` couldn't reach `raw.githubusercontent.com` to fetch the update script.

**Fix**:
1. Verify outbound HTTPS to GitHub: `curl -sI https://raw.githubusercontent.com/`
2. Check proxy / corporate firewall.
3. If Cloudflare-blocked, try `curl -fsSL <URL>` with `--resolve` mapped to a specific IP, or install manually from a git clone.

---

### KL-HOST-03 — i386 architecture install failed

**Symptom**: `[KL-HOST-03] Failed to add i386 architecture`

**Meaning**: `dpkg --add-architecture i386` or the follow-up `apt-get update` failed. SteamCMD needs 32-bit libs to run.

**Fix**:
1. Manually: `sudo dpkg --add-architecture i386 && sudo apt-get update`
2. If APT fails: check `/etc/apt/sources.list` for bad entries. Fix them and retry.

---

### KL-HOST-04 — lib32gcc install failed

**Symptom**: `[KL-HOST-04] Failed to install 32-bit libraries (tried both lib32gcc-s1 and lib32gcc1)`

**Fix**:
1. Refresh APT: `sudo apt-get update`
2. Manually: `sudo apt-get install -y lib32gcc-s1 lib32stdc++6` (or `lib32gcc1` on older distros)
3. If repos are broken, fix them first.

---

### KL-HOST-05 — SteamCMD validation failed

**Symptom**: `[KL-HOST-05] SteamCMD extraction validation failed (steamcmd.sh not found)`

**Fix**: Delete `$STEAMCMD_DIR` and re-run the updater. If it keeps failing, download manually:
```bash
curl -sqL 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz' | tar -xz -C /root/steamcmd
```

---

### KL-HOST-06 — Wings API token missing

**Symptom**: `[KL-HOST-06] Wings API not available - cannot restart servers`

**Meaning**: The updater couldn't read a token from `/etc/pterodactyl/config.yml`. Either Wings isn't on this node or the config file is missing / unreadable.

**Fix**:
1. Confirm Wings is installed: `systemctl status wings`
2. Confirm the config exists: `ls -la /etc/pterodactyl/config.yml`
3. If Wings is on a different node, run the updater there — it must run on the same node as the servers it restarts.

---

### KL-HOST-07 — Wings restart failed

**Symptom**: `[KL-HOST-07] Failed to restart <container> via Wings API (HTTP <code>)`

**Common HTTP codes**:
- `401` — token invalid / expired
- `404` — server UUID doesn't exist in this Wings
- `500` — Wings internal error; check Wings logs

**Fix**:
1. Check Wings logs: `sudo journalctl -u wings -n 100 --no-pager`
2. Verify the container name matches a real Pterodactyl server UUID.
3. If token is stale, restart Wings: `sudo systemctl restart wings`

---

### KL-HOST-08 — nsenter bind-mount failed

**Symptom**: `[KL-HOST-08] nsenter[<container>]: mount failed: <error>`

**Meaning**: The daemon couldn't inject `/tmp/cs2-shared` into the container's mount namespace. Symlink-mode VPK push requires kernel ≥ 5.2 (`open_tree` / `move_mount` syscalls).

**Fix**:
1. Check kernel version: `uname -r` — must be 5.2+.
2. Install `python3` on the host: `apt-get install -y python3`
3. Fall back to `hardlink` or `copy` mode: edit `VPK_PUSH_METHOD` in `/usr/local/bin/update-cs2-centralized.sh`.

---

### KL-HOST-09 — VPK push rsync failed

**Symptom**: `[KL-HOST-09] rsync failed for <container>`

**Fix**:
1. Check disk space on the server's volume path.
2. Verify the volume path is writable by root: `ls -la /var/lib/pterodactyl/volumes/<uuid>/`
3. If one server is corrupted, delete the affected volume contents and let the daemon re-push.

---

### KL-HOST-10 — Self-update download failed

**Symptom**: `[KL-HOST-10] Failed to download update from GitHub`

**Meaning**: The updater couldn't fetch its own new version from GitHub.

**Fix**: Transient — next cron run will retry. If persistent, set `AUTO_UPDATE_SCRIPT="false"` in the script to pin the current version, then update manually.

---

### KL-HOST-11 — Self-update syntax check failed

**Symptom**: `[KL-HOST-11] Downloaded script has syntax errors`

**Meaning**: The newly downloaded script failed `bash -n`. Likely a partial download or mid-flight GitHub outage.

**Auto-recovery**: The old script continues running. Backup is retained in `.script-backups/`.

**Fix**: Wait for the next scheduled check, or trigger manually: `sudo bash /usr/local/bin/update-cs2-centralized.sh`

---

### KL-HOST-12 — Lock busy (concurrent run)

**Symptom**: `[KL-HOST-12] Another CS2 update instance is already running`

**Meaning**: The cron schedule fired while the previous run is still executing. Normal during long SteamCMD updates.

**Fix**: Wait. If truly stuck (> 30 min, no SteamCMD activity): `sudo rm /var/lock/cs2-update.lock` and re-run.

---

## KL-SRV — Server runtime

### KL-SRV-01 — Server crashed

**Symptom**: `[KL-SRV-01] Server crash detected` (follows `./game/cs2.sh: ... Aborted (core dumped)`)

**Meaning**: CS2 process died unexpectedly. Root cause is in the log lines **above** this error — stack traces, SIG reasons, or plugin error messages.

**Common causes**:

1. **Plugin issues** — recently installed/updated plugin incompatible with the current CS2 version. Disable plugins one at a time to isolate.
2. **Addon compatibility** — MetaMod / CounterStrikeSharp / SwiftlyS2 / ModSharp out of date. Update all via the egg's auto-updater (`Update on Start` = `true` in panel). Verify `gameinfo.gi` load order — MetaMod MUST load first.
3. **Outdated gamedata** — plugin gamedata (offsets, signatures) broken after a CS2 update. Check: https://gdc.eternar.dev

**Fix**:
1. Read the stack trace above the crash marker — it identifies the failing module.
2. Update all addons to latest.
3. If crash is reproducible with minimal plugin set, [open a bug report](https://github.com/K4ryuu/CS2-Egg/issues/new/choose) with the core dump info and full log.

---

## Still need help?

If the fix above didn't resolve your issue:

1. **Check [troubleshooting.md](troubleshooting.md)** and [debugging.md](debugging.md) for context.
2. **Open a [bug report](https://github.com/K4ryuu/CS2-Egg/issues/new/choose)**. Please include:
   - The `KL-XXX-NN` error code
   - Full log output (container console + `/home/container/egg/logs/*.log` if file logging is on)
   - Egg version (check `pterodactyl/kitsunelab-cs2-egg.json` → `meta.version`)
   - Docker image tag (`ghcr.io/k4ryuu/cs2-egg:latest` or `:dev`)
   - For host-side errors: `systemctl status cs2-vpk-daemon` output and recent `journalctl -u cs2-vpk-daemon` lines
