# Updating

This guide covers how to update your egg, Docker image, and server.

## Updating the Egg

When a new version of the egg is released:

### For Administrators

1. Download the latest egg JSON from GitHub
2. Go to **Admin** → **Nests** → Your Nest → **Eggs**
3. Click on the KitsuneLab CS2 Egg
4. Either:
   - **Option A**: Click **Import Egg** and upload the new JSON
     - **Warning**: This resets ALL variables to default values
     - You must reconfigure: VPK Sync path and else that are default values.
   - **Option B**: Manually update changed variables in the **Variables** tab
     - - Preserves your existing configuration
     - Only update variables mentioned in changelog

### Recommended Approach

**For production servers**, use **Option B** (manual update) to avoid reconfiguration:

1. Check the [CHANGELOG](../../CHANGELOG) for new/changed variables
2. Update only those specific variables in the **Variables** tab
3. Your existing configuration remains intact

**For new deployments** or **major version upgrades**, **Option A** (import) is acceptable:

1. Make note of your current variable values before importing
2. Import the new egg JSON
3. Reconfigure all custom variables (VPK Sync, tokens, etc.)

### For Existing Servers

After updating the egg:

1. Go to each server using this egg
2. Navigate to **Startup** tab
3. If variables were reset (Option A), reconfigure them now
4. Restart the server to apply changes

## Updating the Docker Image

Docker images are automatically pulled when specified in the egg. To use a newer image:

### Manual Update

1. Stop your server
2. Go to **Startup** tab
3. Change the **Docker Image** dropdown or field to:
   - `docker.io/sples1/k4ryuu-cs2:latest` for the latest stable
   - `docker.io/sples1/k4ryuu-cs2:beta` for beta
4. Start your server

The new image will be automatically pulled on startup.

### Image Tags

- `latest` - Stable release (recommended for production)
- `beta` - Beta testing release (new features, less stable)

## Auto-Updates

The egg includes several auto-update features:

### CS2 Server Updates

The server automatically updates on startup by default. To disable:

1. Go to **Startup** tab
2. Find **Disable Updates**
3. Set to `1` to disable automatic updates
4. Save changes

### Framework Auto-Updates

**Multi-Framework Support** - Enable any combination of frameworks with independent boolean toggles:

| Variable           | Framework          | Auto-Updates |
| ------------------ | ------------------ | ------------ |
| `INSTALL_METAMOD`  | MetaMod:Source     | -           |
| `INSTALL_CSS`      | CounterStrikeSharp | -           |
| `INSTALL_SWIFTLY`  | SwiftlyS2          | -           |
| `INSTALL_MODSHARP` | ModSharp           | -           |

**Configuration:**

1. Go to **Startup** tab
2. Toggle checkboxes for desired frameworks
3. Save and restart server
4. Enabled frameworks auto-update on every server startup

**Dependencies:**

- CounterStrikeSharp automatically enables MetaMod (required dependency)
- SwiftlyS2 and ModSharp are standalone (no MetaMod required)

See [Auto-Updaters Documentation](../features/auto-updaters.md) for full details.

## Update Notifications

### Auto-Restart on CS2 Updates

The egg can automatically restart your server when a new CS2 update is detected.

See the [VPK Sync & Centralized Updates Guide](../features/vpk-sync.md) for automatic updates and server restarts.

> ****TIP** Tip for Multiple Servers:** If you run multiple CS2 servers, use [VPK Sync](../features/vpk-sync.md) with the centralized update script instead. It downloads once and restarts all servers together, saving bandwidth and time compared to per-server auto-restart.

## Checking Versions

### Current CS2 Version

The server logs show the current BuildID on startup:

```
[INFO] Stored initial buildid: 1234567
```

### Installed Frameworks

Version information is stored in `/home/container/egg/versions.txt`:

```
Metamod=2.x-dev1245
CSS=v1.1.0
Swiftly=v0.2.38
ModSharp=git70
DotNet=9.0.0
```

**Accessing versions:**

- Via FTP: Navigate to `/egg/versions.txt`
- Via console: `cat /home/container/egg/versions.txt`
- Via logs: Check startup logs for version info

**Framework Updates:**

- Only enabled frameworks appear in versions.txt
- Versions update automatically on server restart while framework is enabled
- To force re-download: delete versions.txt and restart

## Rollback

If an update causes issues:

### Docker Image Rollback

1. Stop the server
2. Go to **Startup** tab
3. Change Docker Image to a previous tag (if you know it)
4. Start the server

### CS2 Server Rollback

CS2 server rollback is not currently supported by this egg. For version-specific deployments, consider using Docker image tags:

- `docker.io/sples1/k4ryuu-cs2:latest` - Latest stable
- `docker.io/sples1/k4ryuu-cs2:beta` - Beta

Manual rollback requires direct SteamCMD usage outside the egg's automated update system.

## Best Practices

1. **Use manual variable updates (Option B)** for production servers to preserve configuration
2. **Always backup** before major updates
3. **Test updates** on a development server first
4. **Monitor the changelog** for breaking changes
5. **Document your custom variables** before egg imports (VPK Sync, tokens, etc.)
6. **Keep the egg updated** to get new features and fixes
7. **Use stable images** for production servers
8. **Enable auto-restart** to minimize downtime during CS2 updates

## Changelog

View the full changelog: [CHANGELOG](../../CHANGELOG)

## Support

Having issues with updates?

- [Report a Bug](https://github.com/K4ryuu/CS2-Egg/issues/new?template=bug_report.md)
- [Check Troubleshooting](../advanced/troubleshooting.md)
