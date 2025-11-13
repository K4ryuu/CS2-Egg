# VPK Sync Feature

Dramatically reduce storage and bandwidth by centralizing CS2 game files.

## Overview

VPK Sync allows multiple CS2 servers to share game files from a single centralized location instead of each server storing its own complete copy.

**Storage Savings:**

- Without sync: ~55GB per server
- With sync: ~3GB per server (configs + workshop only)
- **Savings per server: ~52GB** (real data)
- **10 servers**: 550GB → 82GB (85% reduction)

**How It Works:**

1. Automated cron job keeps centralized CS2 installation updated
2. Pterodactyl mounts this directory into containers (read-only)
3. Sync script symlinks .vpk files (~52GB) and syncs other files
4. Each server uses shared files, maintains separate configs

**Update Management Advantage:**

The centralized update script can automatically restart **all servers together** after downloading the update once, which is far more efficient than per-server updates.

- - **Single download** vs multiple duplicate downloads
- - **Coordinated restarts** vs staggered individual restarts
- - **Bandwidth savings** vs redundant traffic
- - **Faster updates** vs waiting for each server

## Prerequisites

- - **KitsuneLab CS2 Egg installed in Nests**
- - **Pterodactyl Panel with [PR #4034](https://github.com/pterodactyl/panel/pull/4034) applied** (adds mount support)
- - **Root access to node** (for cron setup and permissions)
- - **Sufficient storage** for one complete CS2 installation

## Setup Guide

### Step 1: Install Egg in Nests

Before proceeding, ensure the KitsuneLab CS2 Egg is imported into your Pterodactyl Nests.

### Step 2: Apply Pterodactyl Panel Modification

Apply [PR #4034](https://github.com/pterodactyl/panel/pull/4034) to enable directory mounting:

```bash
cd /var/www/pterodactyl
cp -r app app.backup  # Backup first!

# Apply PR #4034 changes
# See: https://github.com/pterodactyl/panel/pull/4034/files

# Run database migrations (new values for mount support)
php artisan migrate --force

# Clear cache
php artisan config:clear
php artisan cache:clear
```

### Step 3: Setup Automated Updates (Cron Job)

We provide an automated update script that handles everything: version checking, downloading, permissions, and optionally restarting servers.

**Script Features:**

- - **Input validation** - Validates all configuration paths and URLs for security
- - **Lock file mechanism** - Prevents concurrent execution (safe for cron)
- - **Live progress** - Real-time output during SteamCMD operations
- - **SteamCMD native checks** - Automatic disk space and version validation
- - **Graceful degradation** - Continues even if optional features fail

**Prerequisites for the update script:**

- **Required for auto-restart:** `docker` must be installed if you enable automatic server restarts (`AUTO_RESTART_SERVERS=true`)
  - Docker is typically already installed on Pterodactyl nodes
- **Auto-installed:** SteamCMD will be installed via package manager if not present
  - Requires Ubuntu/Debian with multiverse repository enabled
  - Script automatically handles i386 architecture and dependencies

#### Download and Configure

Download the script:

```bash
cd /root
curl -O https://raw.githubusercontent.com/K4ryuu/CS2-Egg/refs/heads/dev/misc/update-cs2-centralized.sh
chmod +x update-cs2-centralized.sh
```

Edit configuration at the top of the script:

```bash
nano update-cs2-centralized.sh
```

**Configuration section (at the top of the file):**

```bash
# ============================================================================
# CONFIGURATION - Edit these values for your setup
# ============================================================================

# Required: Path where centralized CS2 files are stored
CS2_DIR="/srv/cs2-shared"

# Optional: Docker image for server detection (for automatic server restart)
# Servers using this image (any tag/branch) will be automatically restarted after update
# Example: "sples1/k4ryuu-cs2" matches :latest, :dev, :staging, etc.
SERVER_IMAGE="sples1/k4ryuu-cs2"

# Optional: Enable automatic server restart (true/false)
AUTO_RESTART_SERVERS="false"

# Optional: Validate game files integrity during update (true/false)
# Set to "false" for faster updates (recommended for cron)
# Set to "true" to verify all files (useful for troubleshooting)
VALIDATE_INSTALL="false"

# Optional: Enable automatic script self-update (true/false)
# Script checks GitHub for updates and auto-replaces itself
# Keeps last 3 versions as backup, validates before applying
AUTO_UPDATE_SCRIPT="true"

# Optional: Interval between update checks in seconds (default: 600 = 10 minutes)
# Script will only check for updates if this interval has elapsed
UPDATE_CHECK_INTERVAL="600"
```

**Script Self-Update** (enabled by default):

- Script automatically checks GitHub for updates every 10 minutes (configurable via `UPDATE_CHECK_INTERVAL`)
- Downloads, validates syntax, creates backup, and atomically replaces itself
- **Preserves your configuration** - all config values (paths, settings) are automatically transferred to new version
- Keeps last 3 versions in `.script-backups/` directory for rollback
- Post-update health check automatically rolls back if new version fails
- Set `AUTO_UPDATE_SCRIPT="false"` to disable if you maintain local modifications

**For automatic server restarts**, set `AUTO_RESTART_SERVERS="true"`:

- Script uses Docker to detect and restart containers matching the specified `SERVER_IMAGE` (all tags/branches)
- Example: `SERVER_IMAGE="sples1/k4ryuu-cs2"` restarts containers using `:latest`, `:dev`, `:staging`, etc.
- No API credentials needed - uses native Docker commands
- Requires Docker installed (already present on Pterodactyl nodes)

#### Test the Script

Run manually to verify configuration:

```bash
./update-cs2-centralized.sh
```

**Expected output (no update available):**

```
──────────────────────────────────────────────────────
 KitsuneLab CS2 Centralized Update
──────────────────────────────────────────────────────

==> Pre-flight Checks

[DONE]  Configuration validated successfully
[DONE]  Acquired update lock
[DONE]  Dependencies satisfied
[INFO]  CS2 Directory: /srv/cs2-shared

==> SteamCMD Setup

[DONE]  SteamCMD already installed

==> CS2 Update

Checking for updates and downloading
[DONE]  CS2 is already up to date (version: 20778640)
[INFO]  Installing Steam client libraries...
[INFO]  Setting permissions...
[INFO]  CS2 directory size: 56G

==> Summary

[DONE]  CS2 update completed successfully
[INFO]  Version: 20778640
[INFO]  Location: /srv/cs2-shared
[INFO]  Servers will sync new files on next restart
```

**Expected output (update available):**

```
==> CS2 Update

Checking for updates and downloading
 Update state (0x5) downloading, progress: 45.67 (24821478192 / 54352914432)
 Update state (0x5) downloading, progress: 67.23 (36537648512 / 54352914432)
 Update state (0x5) downloading, progress: 89.41 (48592374192 / 54352914432)
[DONE]  CS2 updated successfully: 20778640 → 20778900
[INFO]  Installing Steam client libraries...
[INFO]  Setting permissions...
[INFO]  CS2 directory size: 56G

==> Detecting and Restarting Servers

[INFO]  Found 12 container(s) using image: sples1/k4ryuu-cs2*
[INFO]  Restarting container: ptero-a1b2c3d4...
[DONE]  Container ptero-a1b2c3d4 restarted successfully
[INFO]  Restarting container: ptero-e5f6g7h8...
[DONE]  Container ptero-e5f6g7h8 restarted successfully
[...10 more containers...]
[DONE]  All containers restarted successfully (12/12)

==> Summary

[DONE]  CS2 update completed successfully
[INFO]  Version: 20778900
[INFO]  Location: /srv/cs2-shared
[INFO]  Servers will sync new files on next restart
```

**Note:** During download/update operations, you'll see real-time progress with the last 3 lines of SteamCMD output. These lines update dynamically and clear when the operation completes.

#### Setup Cron Job

> **Recommended:** Run the script manually once before adding to cron to verify configuration and watch the initial CS2 installation (~60GB download). Once successful, the cron job will handle everything automatically in the background.

Add to crontab to run every 1-2 minutes:

```bash
crontab -e
```

**Without logging** (script output goes nowhere):

```bash
# CS2 Centralized Update - Runs every 2 minutes
*/2 * * * * /root/update-cs2-centralized.sh >/dev/null 2>&1
```

**With logging** (save output to file for monitoring):

```bash
# CS2 Centralized Update - Runs every 2 minutes (with logging)
*/2 * * * * /root/update-cs2-centralized.sh >> /var/log/cs2-update.log 2>&1
```

**Why frequent checks?** SteamCMD only downloads when updates exist. If no update, it's just a quick API check (~1 second).

**Alternative intervals:**

```bash
# Every 1 minute (aggressive) - with logging
* * * * * /root/update-cs2-centralized.sh >> /var/log/cs2-update.log 2>&1

# Every 5 minutes (conservative) - with logging
*/5 * * * * /root/update-cs2-centralized.sh >> /var/log/cs2-update.log 2>&1

# Every 2 minutes - without logging
*/2 * * * * /root/update-cs2-centralized.sh >/dev/null 2>&1
```

#### Monitor Updates

Check the log file (if you configured cron with output redirect):

```bash
# Real-time monitoring
tail -f /var/log/cs2-update.log

# Last 50 lines
tail -n 50 /var/log/cs2-update.log

# Check for successful updates
grep "DONE.*updated successfully" /var/log/cs2-update.log
```

### Step 4: Configure Pterodactyl System

Edit `/etc/pterodactyl/config.yml` and add mount path to allowed list:

```yaml
allowed_mounts:
  - /srv/cs2-shared
```

Restart Wings:

```bash
systemctl restart wings
```

### Step 5: Create Mount in Admin Panel

Navigate to: **Admin Panel** → **Mounts** → **Create New**

**Configuration:**

- **Name**: CS2 Shared Files
- **Source**: `/srv/cs2-shared` (external path on node)
- **Target**: `/tmp/cs2_ds` (internal path in container)
- **Read Only**: - **ON** (prevents servers from modifying shared files)
- **Auto Mount**: - **ON** (mounts automatically for assigned servers)

Save the mount.

### Step 6: Configure Egg-Level Environment Variable

**This is critical** - setting at egg level ensures ALL new servers inherit the configuration.

Navigate to: **Admin Panel** → **Nests** → **Your Nest** → **Eggs** → **KitsuneLab CS2**

Go to **Variables** tab and find **VPK Sync**:

- **Default Value**: `/tmp/cs2_ds` (the internal mount target from Step 5)
- **User Editable**: You can leave this on if you want per-server control
- **User Viewable**: No

Save changes.

**Assign mount to egg:**

- Go to **Mounts** tab in the same egg settings
- Enable the "CS2 Shared Files" mount
- Save

Now **all new servers** will automatically use VPK sync!

### Step 7: Deploy or Resize Servers

**For new servers:** Create as normal - VPK sync activates automatically on first start.

**For existing servers:** Resize to trigger sync:

1. Stop server
2. Change allocation or trigger reinstall
3. Start server - sync will run and reduce storage

Console output on successful sync:

```
[RUNNING] Syncing VPK files...
[SUCCESS] VPK sync complete — linked 28 file(s), total VPK size ~52 GB
```

## Maintenance

### Updates

**Automatic:** Cron job handles everything. When CS2 updates:

1. Cron detects update and downloads to `/srv/cs2-shared`
2. Servers sync new files on next restart
3. No manual intervention needed

**Manual trigger** (if needed, on the server node):

```bash
# On node, as root
/root/update-cs2-centralized.sh
```

## Troubleshooting

> **Auto-Fixed Issues**
>
> The update script automatically handles most common problems:
>
> - - **SteamCMD missing** - Auto-downloads and installs if not found
> - - **Permission errors** - Automatically runs `chown` and `chmod` after every update
> - - **Steam libraries** - Copies SDK files automatically
> - - **Directory creation** - Creates required directories if missing
>
> If you encounter issues, the script likely fixed them automatically on the next run.

### Sync Location Not Found

**Error:** `Sync location not found: /tmp/cs2_ds`

**Cause:** Mount not configured or not assigned to egg.

**Fix:**

1. Verify mount exists: **Admin** → **Mounts**
2. Check mount is assigned to egg: **Eggs** → **Mounts** tab
3. Verify `/srv/cs2-shared` exists on node
4. Restart server

### Permission Denied

**Error:** `Failed to sync base files`

**Note:** The update script automatically fixes permissions after every update (`chown pterodactyl:pterodactyl` + `chmod 755`).

**Manual fix (if needed immediately):**

```bash
chown -R pterodactyl:pterodactyl /srv/cs2-shared
chmod -R 755 /srv/cs2-shared
```

### Cron Job Not Running

**Check status:**

```bash
# Check cron service
systemctl status cron

# Verify crontab entry
crontab -l

# Test manual run
/root/update-cs2-centralized.sh
```

**Add as root cron:**

```bash
sudo crontab -e
```

## Configuration Reference

### File Hierarchy

```
Node (Physical Server):
├── /srv/cs2-shared (~55GB)       ← Cron updates this
└── /etc/pterodactyl/config.yml   ← allowed_mounts

Pterodactyl Admin Panel:
├── Mounts: /srv/cs2-shared → /tmp/cs2_ds
└── Egg Variables: SYNC_LOCATION = /tmp/cs2_ds

Container (Inside Server):
├── /tmp/cs2_ds (mounted, read-only)     ← Shared files (~55GB)
└── /home/container/game/csgo/*.vpk      ← Symlinks (~52GB saved)
```

### Mount Settings Summary

| Setting    | Value             | Why                                   |
| ---------- | ----------------- | ------------------------------------- |
| Source     | `/srv/cs2-shared` | External path on node                 |
| Target     | `/tmp/cs2_ds`     | Internal path in container            |
| Read Only  | - ON             | Prevents modification of shared files |
| Auto Mount | - ON             | Automatically mounts for servers      |

### Storage Calculation

| Servers | Without Sync | With Sync | Savings      |
| ------- | ------------ | --------- | ------------ |
| 1       | 55GB         | 55GB      | 0GB (0%)     |
| 5       | 275GB        | 70GB      | 205GB (75%)  |
| 10      | 550GB        | 85GB      | 465GB (85%)  |
| 20      | 1.1TB        | 115GB     | 1025GB (86%) |
| 50      | 2.75TB       | 205GB     | 2.6TB (87%)  |

_Real data: ~55GB per server without sync, ~3GB per server with sync, ~52GB VPK files saved_

## FAQ

**Q: Can servers modify shared files?**
A: No if mounted read-only (recommended). Modifications are server-specific.

**Q: What if the cron job fails?**
A: Servers continue using existing files. Update manually if needed.

**Q: How often should cron run?**
A: Every 1-2 minutes is safe - SteamCMD only downloads when updates exist.

## Related Documentation

- [Installation Guide](../getting-started/installation.md)
- [Configuration Files](../configuration/configuration-files.md)
- [Building from Source](../advanced/building.md)

## Support

Need help with VPK sync?

- [Report Issue](https://github.com/K4ryuu/CS2-Egg/issues)
- [View Update Script](https://github.com/K4ryuu/CS2-Egg/blob/main/misc/update-cs2-centralized.sh)
