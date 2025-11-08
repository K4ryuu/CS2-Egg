# VPK Sync Feature

Dramatically reduce storage and bandwidth usage by syncing CS2 game files from a centralized location.

## Overview

The VPK Sync feature allows multiple CS2 servers to share the same game files stored on the host machine, instead of each server having its own complete copy.

### Storage Savings

**Without VPK Sync:**

- Each server: ~30GB (game files + VPK files)
- 10 servers: ~300GB total storage

**With VPK Sync:**

- Centralized storage: ~30GB (one complete copy)
- Each server: ~3GB (configs + workshop content only)
- 10 servers: ~30GB + (10 × 3GB) = ~60GB total
- **Savings: ~240GB (80% reduction!)**

### Bandwidth Savings

- Game files downloaded **once** to centralized location
- Updates downloaded **once**, synced to all servers instantly
- No redundant downloads across multiple servers

## How It Works

1. **Centralized Storage**: Complete CS2 installation in a host directory
2. **VPK Symlinks**: Large .vpk files are symlinked (not copied) to each server
3. **File Sync**: Non-VPK files are synced using rsync
4. **Config Preservation**: Server-specific configs are preserved
5. **Auto-Update**: Update centralized location once, all servers benefit

### Technical Details

- Uses `rsync` for efficient file synchronization
- Creates symbolic links for `.vpk` files (25GB+ of data)
- Preserves existing configuration files
- Runs on every server startup before SteamCMD

## Prerequisites

### Required Pterodactyl Panel Modification

This feature requires a **specific panel modification** to allow host directory mounts.

**Panel PR:** https://github.com/pterodactyl/panel/pull/4034/files

This PR adds support for mounting host directories into containers, which is essential for VPK sync.

### Requirements

- ✅ Pterodactyl Panel with PR #4034 applied
- ✅ Node with sufficient storage for centralized CS2 installation
- ✅ Admin access to configure mounts
- ✅ CS2 game files in centralized location

## Setup Guide

### Step 1: Apply Pterodactyl Panel Patch

1. **Check if already applied:**

   ```bash
   # Check panel version or manually verify code
   grep -r "additional_mounts" /var/www/pterodactyl/app/
   ```

2. **Apply the patch:**

   ```bash
   cd /var/www/pterodactyl

   # Backup first!
   cp -r app app.backup

   # Apply PR #4034 changes manually or merge the PR
   # See: https://github.com/pterodactyl/panel/pull/4034/files
   ```

3. **Restart panel:**
   ```bash
   php artisan config:clear
   php artisan cache:clear
   ```

### Step 2: Create Centralized Storage

On your node, create a directory for centralized CS2 files:

```bash
# Create directory
mkdir -p /srv/cs2-shared

# Set permissions (important!)
chown -R pterodactyl:pterodactyl /srv/cs2-shared
chmod -R 755 /srv/cs2-shared
```

### Step 3: Download CS2 to Centralized Location

Install CS2 to the centralized directory:

```bash
# Install SteamCMD if not already installed
apt-get install steamcmd

# Download CS2
steamcmd +force_install_dir /srv/cs2-shared +login anonymous +app_update 730 +quit
```

This downloads the complete CS2 server (~30GB).

### Step 4: Configure Pterodactyl Mount

In Pterodactyl panel:

1. Go to **Admin** → **Nests** → Your Nest → **Mounts**
2. Create a new mount:

   - **Name**: CS2 Shared Files
   - **Source**: `/srv/cs2-shared`
   - **Target**: `/tmp/cs2_ds` (inside container)
   - **Read Only**: ✅ Yes (recommended for safety)
   - **User Mountable**: ❌ No

3. Save the mount

### Step 5: Enable Mount for Servers

**Option A: Enable for all servers (Egg level)**

1. Go to **Nests** → Your Nest → **Eggs** → KitsuneLab CS2 Egg
2. Go to **Mounts** tab
3. Enable the "CS2 Shared Files" mount

**Option B: Enable per server**

1. Go to specific server
2. Go to **Mounts** tab
3. Enable the "CS2 Shared Files" mount

### Step 6: Configure Sync Location Variable

Set the environment variable:

**For all new servers (Nest level):**

1. **Nests** → **Eggs** → KitsuneLab CS2 Egg → **Variables**
2. Find **VPK Sync - Location**
3. Set default value to: `/tmp/cs2_ds`
4. Save

**For existing server:**

1. Server → **Startup** tab
2. Find **VPK SYNC - LOCATION**
3. Set to: `/tmp/cs2_ds`
4. Save

### Step 7: Restart Server

Restart your CS2 server. You should see:

```
[RUNNING] Starting VPK sync from: /tmp/cs2_ds
[RUNNING] Syncing base files (excluding VPKs and configs)...
[SUCCESS] Base files synced successfully
[RUNNING] Creating VPK symlinks...
[SUCCESS] VPK symlinks created successfully
[SUCCESS] VPK sync completed! Server size reduced significantly.
```

## Maintenance

### Updating CS2

When CS2 updates, only update the centralized location:

```bash
# Update centralized CS2
steamcmd +force_install_dir /srv/cs2-shared +login anonymous +app_update 730 +quit

# Restart all servers
# Each server will sync the new files on startup
```

All servers will get the update on their next restart!

### Monitoring Storage

Check storage usage:

```bash
# Centralized storage
du -sh /srv/cs2-shared

# Individual server
du -sh /var/lib/pterodactyl/volumes/YOUR_SERVER_UUID

# Compare before/after VPK sync
```

### Verifying Symlinks

Check if VPK files are symlinked:

```bash
# Inside a server container
ls -lh /home/container/game/csgo/*.vpk

# Should show: pak01_000.vpk -> /tmp/cs2_ds/game/csgo/pak01_000.vpk
```

## Troubleshooting

### Sync Location Not Found

**Error:** `Sync location does not exist: /tmp/cs2_ds`

**Solutions:**

1. Verify mount is enabled for the server
2. Check mount source exists on node: `ls /srv/cs2-shared`
3. Verify mount target is `/tmp/cs2_ds` in mount configuration
4. Restart server after enabling mount

### Permission Denied Errors

**Error:** `Failed to sync base files` or `Permission denied`

**Solutions:**

```bash
# On node, fix permissions
chown -R pterodactyl:pterodactyl /srv/cs2-shared
chmod -R 755 /srv/cs2-shared

# Check container user has read access
```

### Symlinks Not Working

**Problem:** VPK files copied instead of symlinked

**Solutions:**

1. Ensure mount is configured (symlinks require mount)
2. Check `rsync` flags include `-L` for symlink handling
3. Verify source VPK files exist in `/srv/cs2-shared`

### Server Won't Start After Enabling

**Solutions:**

1. Check sync completed successfully in console
2. Verify centralized CS2 installation is complete
3. Try disabling sync temporarily: `SYNC_LOCATION=""`
4. Check container has network access (for fallback to SteamCMD)

### Updates Not Syncing

**Problem:** Server doesn't get updated files

**Solutions:**

1. Verify centralized location was updated
2. Check mount is read-only (forces sync, not write-back)
3. Restart server to trigger sync
4. Check rsync completed without errors

## Advanced Configuration

### Custom Sync Location

Use a different path:

```bash
# Different mount point
SYNC_LOCATION=/mnt/cs2-central

# Network share (if mounted)
SYNC_LOCATION=/mnt/nfs/cs2-shared
```

### Selective Sync

Modify `docker/scripts/sync.sh` to customize what's synced:

```bash
# Exclude additional paths
rsync -aKLz --exclude '*.vpk' \
             --exclude 'cfg/' \
             --exclude 'maps/' \
             "$src_dir/" "$dest_dir"
```

### Workshop Content Handling

Workshop content is NOT synced (server-specific):

- Each server maintains its own workshop content
- Located in `game/csgo/addons/` and workshop folders
- Not included in VPK sync

## Performance Impact

### Startup Time

- **First startup**: Slightly slower (rsync + symlink creation)
- **Subsequent startups**: Much faster (only changed files synced)
- **After updates**: Instant sync vs. 10-30 minute download

### Runtime Performance

- **No performance impact** - symlinks are transparent to the game
- **Same speed** as having files locally
- **Network storage**: May have minimal latency (use local storage recommended)

## Best Practices

1. **Use local storage** for centralized location (fastest)
2. **Mount as read-only** to prevent accidental modifications
3. **Update centralized location** during low-traffic hours
4. **Monitor disk space** on centralized location
5. **Regular backups** of centralized location
6. **Test updates** on one server before restarting all
7. **Document your setup** for other admins

## Architecture Examples

### Small Setup (1-5 servers)

```
Node 1:
├── /srv/cs2-shared (30GB) ← Centralized CS2
└── Servers (5 × 3GB = 15GB)
Total: ~45GB vs. 150GB without sync
```

### Medium Setup (10-20 servers)

```
Node 1:
├── /srv/cs2-shared (30GB)
└── Servers 1-10 (10 × 3GB = 30GB)

Node 2:
├── /srv/cs2-shared (30GB) ← Same version
└── Servers 11-20 (10 × 3GB = 30GB)

Total: ~120GB vs. 600GB without sync
```

### Large Setup (Many servers, NFS)

```
NFS Server:
└── /exports/cs2-shared (30GB) ← Single source of truth

Node 1, 2, 3... N:
├── /mnt/nfs/cs2-shared (NFS mount)
└── Multiple servers (3GB each)

Total: 30GB + (N servers × 3GB)
```

## Security Considerations

### Read-Only Mounts

- ✅ Prevents servers from modifying shared files
- ✅ Protects against malicious plugins
- ✅ Ensures consistency across servers

### File Permissions

```bash
# Centralized storage should be:
Owner: pterodactyl:pterodactyl
Permissions: 755 (rwxr-xr-x)

# Individual files:
644 (rw-r--r--)
```

### Network Mounts

If using NFS/network storage:

- Use secure mount options
- Restrict access to Pterodactyl nodes only
- Consider encryption for sensitive data

## FAQ

**Q: Does this work with Windows nodes?**
A: No, this requires Linux with rsync and symlink support.

**Q: Can I use this with Docker Compose?**
A: Yes! Mount the centralized directory as a volume and set `SYNC_LOCATION`.

**Q: What if centralized storage fails?**
A: Server will skip sync and download files normally via SteamCMD (fallback).

**Q: Can servers modify shared files?**
A: No if mounted read-only (recommended). Modifications are server-specific.

**Q: Does this sync workshop maps?**
A: No, workshop content is server-specific and not synced.

**Q: Can I sync between different CS2 versions?**
A: Not recommended. Use separate centralized locations for beta branches.

**Q: How do I disable sync for one server?**
A: Set `SYNC_LOCATION=""` for that server, or disable the mount.

**Q: Does this work with the auto-restart feature?**
A: Yes! Update centralized location, all servers sync on restart.

## Related Documentation

- [Installation Guide](../getting-started/installation.md)
- [Environment Variables](../configuration/environment-variables.md)
- [Building from Source](../advanced/building.md)
- [Troubleshooting](../advanced/troubleshooting.md)

## Support

Need help with VPK sync?

- [Report Issue](https://github.com/K4ryuu/CS2-Egg/issues)
- Include mount configuration and console logs
