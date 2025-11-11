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

The centralized update script can automatically restart **all servers together** after downloading the update once. This is far superior to the [egg-based auto-restart](auto-restart.md), which makes each server download and restart independently.

- ✅ **Single download** vs multiple duplicate downloads
- ✅ **Coordinated restarts** vs staggered individual restarts
- ✅ **Bandwidth savings** vs redundant traffic
- ✅ **Faster updates** vs waiting for each server

## Prerequisites

- ✅ **KitsuneLab CS2 Egg installed in Nests**
- ✅ **Pterodactyl Panel with [PR #4034](https://github.com/pterodactyl/panel/pull/4034) applied** (adds mount support)
- ✅ **Root access to node** (for cron setup and permissions)
- ✅ **Sufficient storage** for one complete CS2 installation

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

# Clear cache
php artisan config:clear
php artisan cache:clear
```

### Step 3: Setup Automated Updates (Cron Job)

We provide an automated update script that handles everything: version checking, downloading, permissions, and optionally restarting servers.

#### Download and Configure

Download the script:

```bash
cd /root
curl -O https://raw.githubusercontent.com/K4ryuu/CS2-Egg/main/misc/update-cs2-centralized.sh
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

# Required: SteamCMD installation directory
STEAMCMD_DIR="/root/steamcmd"

# Optional: Pterodactyl Panel URL (for automatic server restart)
PTERODACTYL_API_URL=""

# Optional: Pterodactyl Application API Token
PTERODACTYL_API_TOKEN=""

# Optional: Docker image filter for server detection
SERVER_IMAGE="sples1/k4ryuu-cs2"

# Optional: Enable automatic server restart (true/false)
AUTO_RESTART_SERVERS="false"
```

**For automatic server restarts**, add Pterodactyl API credentials:

1. Admin Panel → Application API → Create New
2. Permissions needed: `servers.read`, `servers.power`
3. Copy token and URL to script:

```bash
PTERODACTYL_API_URL="https://panel.yourdomain.com"
PTERODACTYL_API_TOKEN="ptla_YOUR_API_TOKEN_HERE"
AUTO_RESTART_SERVERS="true"
```

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

✓ DONE  Dependencies satisfied
ℹ INFO  CS2 Directory: /srv/cs2-shared
ℹ INFO  SteamCMD Directory: /root/steamcmd

==> SteamCMD Setup

✓ DONE  SteamCMD already installed

==> Version Check

ℹ INFO  Checking CS2 updates (current: 14589)...
✓ DONE  CS2 is up to date (version: 14589)
```

**Expected output (update available):**

```
==> Version Check

ℹ INFO  Checking CS2 updates (current: 14589)...
⚠ WARN  Update available! Current: 14589 → Required: 14590

==> Updating CS2 to version 14590

Downloading CS2 update
 Update state (0x5) downloading, progress: 45.67 (24821478192 / 54352914432)
 Update state (0x5) downloading, progress: 67.23 (36537648512 / 54352914432)
 Update state (0x5) downloading, progress: 89.41 (48592374192 / 54352914432)
✓ DONE  Downloading CS2 update finished in 245s
ℹ INFO  Installing Steam client libraries...
ℹ INFO  Setting permissions...
✓ DONE  CS2 updated successfully to version 14590
ℹ INFO  CS2 directory size: 55G

==> Detecting Affected Servers

ℹ INFO  Fetching servers from Pterodactyl API...
✓ DONE  Found 12 server(s) using CS2 image

==> Restarting Servers

ℹ INFO  Preparing to restart 12 server(s)...
✓ DONE  All servers restarted successfully (12/12)
```

**Note:** During download/update operations, you'll see real-time progress with the last 3 lines of SteamCMD output. These lines automatically update as new output arrives, and clear when the operation completes.

#### Setup Cron Job

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
- **Read Only**: ✅ **ON** (prevents servers from modifying shared files)
- **Auto Mount**: ✅ **ON** (mounts automatically for assigned servers)

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
steamcmd +force_install_dir /srv/cs2-shared +login anonymous +app_update 730 +quit
```

## Troubleshooting

### Sync Location Not Found

**Error:** `Sync location not found: /tmp/cs2_ds`

**Fix:**

1. Verify mount exists: **Admin** → **Mounts**
2. Check mount is assigned to egg: **Eggs** → **Mounts** tab
3. Verify `/srv/cs2-shared` exists on node
4. Restart server

### Permission Denied

**Error:** `Failed to sync base files`

**Fix:**

```bash
chown -R pterodactyl:pterodactyl /srv/cs2-shared
chmod -R 755 /srv/cs2-shared
```

### Cron Job Not Running

**Fix:**

```bash
# Check cron service
systemctl status cron

# Verify crontab entry
crontab -l

# Test manual run
/path/to/your/update-script.sh
```

Also you can add the cron as root by running `sudo crontab -e`.

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
| Read Only  | ✅ ON             | Prevents modification of shared files |
| Auto Mount | ✅ ON             | Automatically mounts for servers      |

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
- [Auto-Restart Feature](auto-restart.md) - Automatically restart servers when CS2 updates
- [Configuration Files](../configuration/configuration-files.md)
- [Building from Source](../advanced/building.md)

## Support

Need help with VPK sync?

- [Report Issue](https://github.com/K4ryuu/CS2-Egg/issues)
- [View Update Script](https://github.com/K4ryuu/CS2-Egg/blob/main/misc/update-cs2-centralized.sh)
