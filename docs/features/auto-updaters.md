# Auto-Updaters

Automatically update MetaMod, CounterStrikeSharp, and Swiftly on server startup.

## Overview

The egg includes automatic updaters for popular CS2 server plugins:

- **MetaMod:Source** - Core plugin framework
- **CounterStrikeSharp (CSS)** - C# plugin framework
- **Swiftly** - Alternative plugin framework

Updates happen automatically on server startup, keeping your plugins current without manual intervention.

**Version Tracking:** All addon versions are stored in `/home/container/egg/versions.txt`

## Configuration

### Server Add-ons Selection

The `ADDON_SELECTION` variable controls which plugins are auto-updated:

| Value             | What Gets Updated            |
| ----------------- | ---------------------------- |
| `none`            | Nothing (vanilla server)     |
| `metamod`         | MetaMod only                 |
| `metamod_css`     | MetaMod + CounterStrikeSharp |
| `metamod_swiftly` | MetaMod + Swiftly            |

### Setting Up

**Via Pterodactyl:**

1. Go to **Startup** tab
2. Find **Server Add-ons** dropdown
3. Select your preferred option
4. Save and restart server

**Via Environment Variable:**

```bash
ADDON_SELECTION=metamod_css
```

## MetaMod:Source

### What It Does

- Downloads latest stable MetaMod from AlliedMods/GitHub
- Extracts to `game/csgo/addons/metamod/`
- Configures `gameinfo.gi` automatically
- Stores version in `/home/container/egg/versions.txt`

### How It Works

1. Checks current installed version
2. Fetches latest version from AlliedMods/GitHub
3. Compares versions (format: `git1234`)
4. Downloads and extracts if newer version available
5. Updates `gameinfo.gi` to load MetaMod

### Console Output

```
[INFO] Checking MetaMod version...
[INFO] Current: git1234, Latest: git1245
[INFO] Updating MetaMod...
[SUCCESS] MetaMod updated successfully
```

### Manual Installation

If you prefer manual control:

1. Set `ADDON_SELECTION=none`
2. Install MetaMod manually
3. Server won't overwrite your installation

## CounterStrikeSharp

### What It Does

- Downloads latest CSS from GitHub releases
- Extracts to `game/csgo/addons/counterstrikesharp/`
- Installs with-runtime version (includes .NET runtime)
- Stores version in `/home/container/egg/versions.txt`

### Prerequisites

- **MetaMod must be installed** (CSS requires it)
- Set `ADDON_SELECTION=metamod_css`

### How It Works

1. Verifies MetaMod is installed
2. Checks current CSS version
3. Fetches latest release from roflmuffin/CounterStrikeSharp
4. Downloads with-runtime Linux build
5. Extracts and updates version tracking

### Console Output

```
[INFO] Checking CSS version...
[INFO] Current: v1.0.0, Latest: v1.1.0
[INFO] Downloading CSS...
[SUCCESS] CSS updated successfully
```

### Plugin Compatibility

CSS updates may break plugins. Consider:

- Test updates on development server first
- Check plugin compatibility before updating
- Monitor CSS changelog for breaking changes
- Backup before enabling auto-updates

## Swiftly

### What It Does

- Downloads latest Swiftly from GitHub releases
- Extracts to `game/csgo/addons/swiftly/`
- Installs Linux plugin version
- Stores version in `/home/container/egg/versions.txt`

### Prerequisites

- **MetaMod must be installed** (Swiftly requires it)
- Set `ADDON_SELECTION=metamod_swiftly`

### How It Works

1. Verifies MetaMod is installed
2. Checks current Swiftly version
3. Fetches latest from swiftly-solution/swiftly
4. Downloads Swiftly.Plugin.Linux.zip
5. Extracts and updates version tracking

### Console Output

```
[INFO] Checking Swiftly version...
[INFO] Current: v2.0.0, Latest: v2.1.0
[INFO] Downloading Swiftly...
[SUCCESS] Swiftly updated successfully
```

## Version Tracking

### Version File

Versions are stored in `/home/container/egg/versions.txt`:

```
Metamod=git1245
CSS=v1.1.0
Swiftly=v2.1.0
```

### Location

The version file is stored in the organized egg directory:

- **Path:** `/home/container/egg/versions.txt`
- **Accessible via FTP:** Yes
- **Backed up with server data:** Yes

### Smart Updates

The updater:

- ✅ Only downloads when new version available
- ✅ Compares versions before downloading
- ✅ Skips updates if already current
- ✅ Logs all version changes

This saves bandwidth and startup time.

## Update Schedule

### When Updates Happen

- **On server startup** - Every time container starts
- **Not during runtime** - Server must restart to update
- **After game updates** - Auto-restart triggers update

### Forcing Updates

To force update:

1. Delete version file: `rm /home/container/egg/versions.txt` (via FTP or console)
2. Restart server
3. Will re-download latest versions

### Preventing Updates

To keep current versions:

1. Set `ADDON_SELECTION=none`
2. Or manually manage addons
3. Version file won't be created/updated

## Combining with Auto-Restart

Auto-Restart + Auto-Updaters = Fully automated server:

```
CS2 Update Detected
       ↓
Server Restarts
       ↓
Game Files Update (SteamCMD)
       ↓
Plugins Update (Auto-Updaters)
       ↓
Server Online with Latest Everything
```

Perfect for hands-off server management!

## Troubleshooting

### MetaMod Not Installing

**Check:**

- AlliedMods website accessible
- GitHub API accessible
- Sufficient disk space
- Write permissions on `game/csgo/addons/`

**Solution:**

```bash
# Check manually
curl -s https://mms.alliedmods.net/mmsdrop/2.0/ | grep linux
```

### CSS Not Installing

**Check:**

- MetaMod installed first
- GitHub API not rate-limited
- Downloaded correct platform (Linux)
- Sufficient disk space

**Common error:**

```
[ERROR] MetaMod not found, CSS requires MetaMod
```

**Solution:** Change to `metamod_css` (not just `css`)

### Swiftly Not Installing

**Check:**

- MetaMod installed first
- GitHub releases accessible
- Correct asset downloaded
- No conflicts with CSS

**Note:** Don't use `metamod_css` and `metamod_swiftly` together - choose one plugin framework.

### Version Not Updating

**Problem:** Same version reinstalls every startup.

**Cause:** Version file not being written/read correctly.

**Solution:**

1. Check `/home/container/egg/versions.txt` exists and is readable
2. Verify write permissions on `/home/container/egg/`
3. Check for errors in console during update
4. Delete version file and restart to regenerate

### Rate Limiting

**Error:** `API rate limit exceeded` or `403 Forbidden`

**Cause:** Too many requests to GitHub API.

**Solution:**

- Wait 1 hour for rate limit reset
- Add GitHub token (advanced, requires modifying scripts)
- Less frequent restarts during development

## Manual Updates

### Updating MetaMod Manually

```bash
# Download
wget https://mms.alliedmods.net/mmsdrop/2.0/mmsource-latest-linux.tar.gz

# Extract
tar -xzf mmsource-latest-linux.tar.gz -C game/csgo/

# Update gameinfo
# (automatically done by egg on startup)
```

### Updating CSS Manually

```bash
# Download latest
wget https://github.com/roflmuffin/CounterStrikeSharp/releases/download/v1.x.x/counterstrikesharp-with-runtime-linux-xxx.zip

# Extract
unzip counterstrikesharp-with-runtime-linux-xxx.zip -d game/csgo/
```

### Updating Swiftly Manually

```bash
# Download latest
wget https://github.com/swiftly-solution/swiftly/releases/download/v2.x.x/Swiftly.Plugin.Linux.zip

# Extract
unzip Swiftly.Plugin.Linux.zip -d game/csgo/
```

## Best Practices

1. **Test updates** on dev server before production
2. **Backup plugins** before enabling auto-updates
3. **Monitor changelogs** for breaking changes
4. **Choose one framework** (CSS or Swiftly, not both)
5. **Keep MetaMod updated** - required by other plugins
6. **Check plugin compatibility** after updates
7. **Use stable releases** in production

## Advanced

### Disabling Specific Updates

Currently not supported, but you can:

1. Set `ADDON_SELECTION=none`
2. Manually install desired plugins
3. They won't be auto-updated

### Custom Update Logic

To modify update behavior:

1. Edit `docker/scripts/update.sh`
2. Modify `update_metamod`, `update_addon`, or `update_swiftly` functions
3. Rebuild Docker image
4. See [Building from Source](../advanced/building.md)

### Update Notifications

No built-in notifications for plugin updates, but you can:

- Monitor console logs
- Check `/home/container/egg/versions.txt` changes
- Add custom logging to update scripts
- Combine with logging feature for persistent logs

## FAQ

**Q: Can I use CSS and Swiftly together?**
A: Not recommended. Choose one plugin framework to avoid conflicts.

**Q: Will updates break my plugins?**
A: Possibly. Major updates can have breaking changes. Test on dev server first.

**Q: Can I rollback an update?**
A: Yes, manually install older version and set `ADDON_SELECTION=none` to prevent auto-update.

**Q: How do I update only MetaMod, not CSS?**
A: Set `ADDON_SELECTION=metamod`

**Q: Are beta versions supported?**
A: No, only stable releases from official repos.

**Q: What if GitHub is down?**
A: Updates will fail, but server will start anyway. Updates will work on next restart.

**Q: Can I auto-update custom plugins?**
A: Not built-in. You'll need to modify update scripts or manage them manually.

**Q: Where are versions stored?**
A: In `/home/container/egg/versions.txt` (accessible via FTP)

## Related Documentation

- [Auto-Restart](auto-restart.md) - Automatic server restarts
- [Environment Variables](../configuration/environment-variables.md) - All configuration options
- [Building from Source](../advanced/building.md) - Customize update logic

## Support

Having update issues?

- [Report Issue](https://github.com/K4ryuu/CS2-Egg/issues)
- [Troubleshooting Guide](../advanced/troubleshooting.md)
