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

## Prerequisites

✅ **KitsuneLab CS2 Egg installed in Nests**
✅ **Pterodactyl Panel with [PR #4034](https://github.com/pterodactyl/panel/pull/4034) applied** (adds mount support)
✅ **Root access to node** (for cron setup and permissions)
✅ **Sufficient storage** for one complete CS2 installation

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

Create a cron job that updates CS2 files every 1-2 minutes to the centralized location (on the server machine, not inside containers).

**Why frequent checks?** SteamCMD only downloads when updates exist, otherwise it's just a quick version check.

**Example cron job request:** If you need a reference script, [request it via GitHub Issues](https://github.com/K4ryuu/CS2-Egg/issues).

**Basic concept:**

```bash
# Cron runs every 1-2 minutes
# Updates /srv/cs2-shared when CS2 updates
# Uses steamcmd +login anonymous +app_update 730 +quit
```

**Set permissions after initial download:**

```bash
chown -R pterodactyl:pterodactyl /srv/cs2-shared
chmod -R 755 /srv/cs2-shared
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
- [Request Cron Script Example](https://github.com/K4ryuu/CS2-Egg/issues)
