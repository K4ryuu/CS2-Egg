# Updating

This guide covers how to update your egg, Docker image, and server.

## Updating the Egg

When a new version of the egg is released:

### For Administrators

1. Download the latest egg JSON from GitHub
2. Go to **Admin** → **Nests** → Your Nest → **Eggs**
3. Click on the KitsuneLab CS2 Egg
4. Either:
   - **Option A**: Click **Import Egg** and upload the new JSON (will update all variables)
   - **Option B**: Manually update changed variables in the **Variables** tab

### For Existing Servers

After updating the egg:

1. Go to each server using this egg
2. Navigate to **Startup** tab
3. Click **Reinstall** if needed (be careful, this may reset configurations)
4. Or simply restart the server to use the new egg configuration

## Updating the Docker Image

Docker images are automatically pulled when specified in the egg. To use a newer image:

### Manual Update

1. Stop your server
2. Go to **Startup** tab
3. Change the **Docker Image** dropdown or field to:
   - `docker.io/sples1/k4ryuu-cs2:latest` for the latest stable
   - `docker.io/sples1/k4ryuu-cs2:beta` for beta
   - `docker.io/sples1/k4ryuu-cs2:dev` for development
4. Start your server

The new image will be automatically pulled on startup.

### Image Tags

- `latest` - Stable release (recommended for production)
- `beta` - Beta testing release (new features, less stable)
- `dev` - Development release (bleeding edge, may have bugs)

## Auto-Updates

The egg includes several auto-update features:

### CS2 Server Updates

The server automatically updates on startup by default. To disable:

1. Go to **Startup** tab
2. Find **Disable Updates**
3. Set to `1` to disable automatic updates
4. Save changes

### MetaMod & Plugins Auto-Updates

Configure the **Server Add-ons** dropdown:

- `none` - No auto-updates (vanilla server)
- `metamod` - Auto-update MetaMod only
- `metamod_css` - Auto-update MetaMod + CounterStrikeSharp
- `metamod_swiftly` - Auto-update MetaMod + Swiftly

These update automatically on server startup when enabled.

## Update Notifications

### Auto-Restart on CS2 Updates

The egg can automatically restart your server when a new CS2 update is detected.

See the [Auto-Restart Guide](../features/auto-restart.md) for full setup instructions.

### Webhook Notifications

You can configure Discord webhooks to receive notifications about scheduled updates. The webhook feature sends formatted embeds with update information and countdown timers.

**Configuration:**

1. Create a webhook in your Discord server
2. Add the webhook URL to the **Auto Restart - Discord Webhook** variable
3. Server will send notifications when updates are detected

**Note:** This is an optional feature for monitoring purposes.

## Checking Versions

### Current CS2 Version

The server logs show the current BuildID on startup:

```
[INFO] Stored initial buildid: 1234567
```

### Installed Add-ons

Version information is stored in `/home/container/egg/versions.txt`:

```
Metamod=git1234
CSS=v1.0.0
Swiftly=v2.0.0
```

**Accessing versions:**

- Via FTP: Navigate to `/egg/versions.txt`
- Via console: `cat /home/container/egg/versions.txt`
- Via logs: Check startup logs for version info

## Rollback

If an update causes issues:

### Docker Image Rollback

1. Stop the server
2. Go to **Startup** tab
3. Change Docker Image to a previous tag (if you know it)
4. Start the server

### CS2 Server Rollback

Use SteamCMD's beta branch feature:

1. Add these environment variables (admin access required):
   - `SRCDS_BETAID` - Beta branch name
   - `SRCDS_BETAPASS` - Beta branch password (if required)
2. Restart the server

## Best Practices

1. **Always backup** before major updates
2. **Test updates** on a development server first
3. **Monitor the changelog** for breaking changes
4. **Keep the egg updated** to get new features and fixes
5. **Use stable images** for production servers
6. **Enable auto-restart** to minimize downtime during CS2 updates

## Changelog

View the full changelog: [CHANGELOG](../../CHANGELOG)

## Support

Having issues with updates?

- [Report a Bug](https://github.com/K4ryuu/CS2-Egg/issues/new?template=bug_report.md)
- [Check Troubleshooting](../advanced/troubleshooting.md)
