# Error Codes

> **Can't find your error here, or the fix didn't work?**
> Open a [bug report](https://github.com/K4ryuu/CS2-Egg/issues/new/choose) — include the `KL-XXX-NN` code, the full log output, your egg version, and Docker image tag.

Every fatal error in the KitsuneLab egg emits a stable code. Look it up here to see what it means, how to diagnose it, and how to fix it.

## Index

- [KL-DMN — Daemon / VPK Sync](#kl-dmn--daemon--vpk-sync)
- [KL-STM — SteamCMD](#kl-stm--steamcmd)
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

---

### KL-DMN-02 — Daemon bind-mount timeout

**Symptom**: `[KL-DMN-02] Daemon mount wait timed out after Xs`

**Meaning**: Daemon marker is fresh (daemon is alive), but `/tmp/cs2-shared` never got bind-mounted into the container. The VPK symlinks will point to an empty mount → CS2 will fail to load game files.

**Diagnose (on host)**:
```bash
uname -r                 # must be 5.2+ for open_tree/move_mount syscalls
python3 --version        # daemon uses python3 to invoke the syscalls
sudo journalctl -u cs2-vpk-daemon -n 100 --no-pager | grep nsenter
```

**Fix**:
1. Ensure kernel ≥ 5.2 (Ubuntu 20.04+). Older kernels cannot bind-mount into an already-running container namespace — upgrade the host or switch `VPK_PUSH_METHOD` to `hardlink` / `copy` in the daemon config.
2. Ensure `python3` is installed on the host: `apt-get install -y python3`
3. Restart the daemon: `sudo systemctl restart cs2-vpk-daemon`

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

### KL-STM-01 — SteamCMD exit code 8

**Symptom**: `[KL-STM-01] SteamCMD connection error (exit code 8)`

**Meaning**: SteamCMD failed with exit 8. The name "connection error" is misleading — in practice this is almost always **disk space / filesystem** failure that cascades into a login/state failure.

**Most common cause — not enough disk space.**

**Diagnose**:
1. `df -h /home/container` — CS2 needs ~60 GB free (3 GB with VPK-sync daemon).
2. Look at the SteamCMD output ABOVE the code line for `state is 0x...`:
   - `state is 0x202` → disk or filesystem issue → see [KL-STM-03](#kl-stm-03--state-0x202-disk-space--filesystem)
   - `Please use force_install_dir before logon!` → egg arg order bug
3. Only if disk is fine: check Steam status at [steamstat.us](https://steamstat.us/) and try `curl -sI https://steamcdn-a.akamaihd.net/`.

**Fix**:
1. Free disk space on the host's panel volume directory.
2. Ensure quota isn't capped (Pterodactyl/Pelican server disk limit).
3. Retry — transient CDN issues self-resolve.
4. If persistent: collect the full SteamCMD output, [open a bug report](https://github.com/K4ryuu/CS2-Egg/issues/new/choose) with the `state is 0x...` code.

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
   - If the issue relates to the centralized VPK daemon, ask your node admin for `systemctl status cs2-vpk-daemon` output
