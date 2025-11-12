# Auto-Updaters

Automatically update MetaMod, CounterStrikeSharp, SwiftlyS2, and ModSharp on server startup with independent control per framework.

## Overview

The egg includes automatic updaters for popular CS2 server plugins with **multi-framework support** → enable multiple frameworks simultaneously:

- **MetaMod:Source** → Core plugin framework (required for CSS)
- **CounterStrikeSharp (CSS)** → C# plugin framework (.NET 8)
- **SwiftlyS2** → Standalone C# framework v2 (no MetaMod required)
- **ModSharp** → Standalone C# platform with .NET 9 runtime

Updates happen automatically on server startup, keeping your plugins current without manual intervention.

**Version Tracking:** All addon versions are stored in `/home/container/egg/versions.txt`

## Configuration

### Multi-Framework Selection

Each framework has an independent boolean toggle in the Pterodactyl panel:

| Variable             | Description                                      | Auto-Updates |
| -------------------- | ------------------------------------------------ | ------------ |
| `INSTALL_METAMOD`    | MetaMod:Source (required for CSS)                | ✅           |
| `INSTALL_CSS`        | CounterStrikeSharp (auto-enables MetaMod)        | ✅           |
| `INSTALL_SWIFTLY`    | SwiftlyS2 standalone (no MetaMod required)       | ✅           |
| `INSTALL_MODSHARP`   | ModSharp standalone with .NET 9                  | ✅           |

**Multi-Framework Examples:**
- MetaMod + CSS + ModSharp → All three enabled simultaneously
- SwiftlyS2 + ModSharp → Both standalone frameworks together
- CSS only → MetaMod auto-enabled as dependency

### Setting Up

**Via Pterodactyl Panel:**

1. Go to **Startup** tab
2. Toggle checkboxes for desired frameworks:
   - ☑ MetaMod:Source
   - ☑ CounterStrikeSharp
   - ☐ SwiftlyS2
   - ☑ ModSharp
3. Save and restart server

**Via Environment Variables:**

```bash
INSTALL_METAMOD=1
INSTALL_CSS=1
INSTALL_SWIFTLY=0
INSTALL_MODSHARP=1
```

### Dependency Handling

The egg automatically handles dependencies:

```
CSS enabled + MetaMod disabled
       ↓
[WARNING] CounterStrikeSharp requires MetaMod:Source, auto-enabling...
       ↓
Both MetaMod and CSS installed
```

### Load Order Management

**MetaMod always loads first** after Game_LowViolence (critical for proper initialization):

```
Game_LowViolence    csgo_lv
            Game    csgo/addons/metamod        ← Always first
            Game    csgo/addons/counterstrikesharp
            Game    csgo/addons/swiftlys2
            Game    sharp                       ← ModSharp

            Game    csgo
```

## MetaMod:Source

### What It Does

- Downloads latest stable MetaMod from MetaMod downloads
- Extracts to `game/csgo/addons/metamod/`
- Configures `gameinfo.gi` automatically (always first position)
- Stores version in `/home/container/egg/versions.txt`

### How It Works

1. Checks current installed version
2. Fetches latest version from metamodsource.net
3. Compares versions (format: `2.x-devXXXX`)
4. Downloads and extracts if newer version available
5. Updates `gameinfo.gi` to load MetaMod first

### Console Output

```
[KitsuneLab] > Checking MetaMod updates...
[KitsuneLab] > Update available for MetaMod: 2.x-dev1245 (current: 2.x-dev1234)
[KitsuneLab] > MetaMod updated to 2.x-dev1245
```

## CounterStrikeSharp

### What It Does

- Downloads latest CSS from GitHub releases
- Extracts to `game/csgo/addons/counterstrikesharp/`
- Installs with-runtime version (includes .NET runtime)
- Auto-enables MetaMod if not already enabled
- Stores version in `/home/container/egg/versions.txt`

### Prerequisites

- **MetaMod required** → Automatically enabled when CSS is toggled on

### How It Works

1. Checks if MetaMod enabled (auto-enables with warning if not)
2. Checks current CSS version
3. Fetches latest release from roflmuffin/CounterStrikeSharp
4. Downloads with-runtime Linux build
5. Extracts and updates version tracking

### Console Output

```
[KitsuneLab] > [WARNING] CounterStrikeSharp requires MetaMod:Source, auto-enabling...
[KitsuneLab] > Checking CSS updates...
[KitsuneLab] > CSS is up-to-date (v1.0.0)
```

### Plugin Compatibility

CSS updates may break plugins. Consider:

- Test updates on development server first
- Check plugin compatibility before updating
- Monitor CSS changelog for breaking changes
- Backup before enabling auto-updates

## SwiftlyS2

### What It Does

- Downloads latest SwiftlyS2 from GitHub releases
- Extracts to `game/csgo/addons/swiftlys2/`
- Installs with-runtime Linux version
- Configures `gameinfo.gi` automatically
- **Standalone** → No MetaMod dependency
- Stores version in `/home/container/egg/versions.txt`

### Prerequisites

- **None** → Completely standalone framework

### How It Works

1. Checks current SwiftlyS2 version
2. Fetches latest from swiftly-solution/swiftlys2
3. Downloads with-runtimes-linux.zip
4. Extracts swiftlys2 directory
5. Updates `gameinfo.gi` to load SwiftlyS2
6. Removes old metamod VDF file if present (legacy cleanup)

### Console Output

```
[KitsuneLab] > Checking SwiftlyS2 updates...
[KitsuneLab] > Update available for SwiftlyS2: v0.2.38 (current: v0.2.37)
[KitsuneLab] > SwiftlyS2 updated to v0.2.38
```

### Multi-Framework Compatibility

SwiftlyS2 can coexist with:
- ✅ ModSharp (both standalone)
- ✅ MetaMod + CSS (different frameworks)
- ✅ All frameworks simultaneously

## ModSharp

### What It Does

- Downloads latest ModSharp from GitHub releases
- Installs .NET 9 runtime automatically
- Extracts to `game/sharp/`
- Configures `gameinfo.gi` automatically
- **Standalone** → No MetaMod dependency
- Stores versions in `/home/container/egg/versions.txt`

### Prerequisites

- **None** → Completely standalone with bundled .NET 9

### How It Works

1. Checks and installs .NET 9.0.0 runtime if needed
2. Checks current ModSharp version
3. Fetches latest from Kxnrl/modsharp-public
4. Downloads core + extensions assets
5. Extracts preserving existing configs (`core.json` not overwritten)
6. Updates `gameinfo.gi` to load ModSharp

### Console Output

```
[KitsuneLab] > Installing .NET 9.0.0 runtime...
[KitsuneLab] > .NET 9.0.0 runtime installed successfully
[KitsuneLab] > Checking ModSharp updates...
[KitsuneLab] > Update available for ModSharp: git70 (current: git69)
[KitsuneLab] > ModSharp updated to git70
```

### Configuration

ModSharp configs are in `game/sharp/configs/core.json`. First install creates default config, updates preserve your settings.

### Multi-Framework Compatibility

ModSharp can coexist with:
- ✅ SwiftlyS2 (both standalone)
- ✅ MetaMod + CSS (different frameworks)
- ✅ All frameworks simultaneously

## Version Tracking

### Version File

Versions are stored in `/home/container/egg/versions.txt`:

```
Metamod=2.x-dev1245
CSS=v1.1.0
Swiftly=v0.2.38
ModSharp=git70
DotNet=9.0.0
```

### Location

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

- **On server startup** → Every time container starts
- **Not during runtime** → Server must restart to update
- **After game updates** → Auto-restart triggers update

### Forcing Updates

To force update:

1. Delete version file: `rm /home/container/egg/versions.txt` (via FTP or console)
2. Restart server
3. Will re-download latest versions

### Preventing Updates

To disable updates for specific framework:

1. Toggle off the framework checkbox in Pterodactyl panel
2. Or set environment variable to `0`: `INSTALL_CSS=0`
3. Framework won't be updated or installed

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
gameinfo.gi Load Order Verified
       ↓
Server Online with Latest Everything
```

Perfect for hands-off server management!

## Troubleshooting

### MetaMod Not Installing

**Check:**

- metamodsource.net accessible
- Sufficient disk space
- Write permissions on `game/csgo/addons/`

**Solution:**

```bash
# Check manually
curl -I https://www.metamodsource.net/downloads.php?branch=dev
```

### CSS Not Installing

**Check:**

- MetaMod auto-enabled (check for [WARNING] message)
- GitHub API not rate-limited
- Downloaded correct platform (Linux)
- Sufficient disk space

**Common error:**

```
[ERROR] No suitable asset found for roflmuffin/CounterStrikeSharp
```

**Solution:** GitHub API rate limit → wait 1 hour or check network access

### SwiftlyS2 Not Installing

**Check:**

- GitHub releases accessible
- Correct asset downloaded (with-runtimes-linux.zip)
- No file permission issues

**Note:** SwiftlyS2 is standalone, doesn't require MetaMod

### ModSharp Not Installing

**Check:**

- .NET runtime installation succeeded
- GitHub releases accessible
- Both core and extensions assets downloading
- Sufficient disk space for .NET 9 runtime

**Common issue:** .NET runtime download failure → check Microsoft CDN access

### Version Not Updating

**Problem:** Same version reinstalls every startup

**Cause:** Version file not being written/read correctly

**Solution:**

1. Check `/home/container/egg/versions.txt` exists and is readable
2. Verify write permissions on `/home/container/egg/`
3. Check for errors in console during update
4. Delete version file and restart to regenerate

### Load Order Issues

**Problem:** Plugins not loading correctly

**Cause:** Incorrect gameinfo.gi load order

**Solution:** MetaMod must be first addon after LowViolence. The egg handles this automatically via `ensure_metamod_first()` function.

**Verify load order:**

```bash
cat game/csgo/gameinfo.gi | grep -A 10 "Game_LowViolence"
```

Should show:
```
Game_LowViolence    csgo_lv
            Game    csgo/addons/metamod        ← MetaMod FIRST
            Game    csgo/addons/counterstrikesharp
            ...other addons...

            Game    csgo
```

### Rate Limiting

**Error:** `API rate limit exceeded` or `403 Forbidden`

**Cause:** Too many requests to GitHub API

**Solution:**

- Wait 1 hour for rate limit reset
- Less frequent restarts during development
- Check GitHub status: https://www.githubstatus.com/

## Migration from Old System

### Deprecated ADDON_SELECTION Variable

If you're using the old `ADDON_SELECTION` dropdown:

**Warning Message:**
```
[KitsuneLab] > [WARNING] ⚠️  DEPRECATION WARNING ⚠️
[KitsuneLab] > [WARNING] The ADDON_SELECTION variable is deprecated and will be removed in the next update!
[KitsuneLab] > [WARNING] Please update your Pterodactyl egg to use the new multi-framework support:
[KitsuneLab] > [WARNING]   → INSTALL_METAMOD (boolean)
[KitsuneLab] > [WARNING]   → INSTALL_CSS (boolean)
[KitsuneLab] > [WARNING]   → INSTALL_SWIFTLY (boolean)
[KitsuneLab] > [WARNING]   → INSTALL_MODSHARP (boolean)
```

**Migration Steps:**

1. Download latest egg JSON from GitHub
2. Re-import egg in Pterodactyl panel
3. Configure new boolean variables to match your current setup:
   - Old: `ADDON_SELECTION="Metamod + CounterStrikeSharp"`
   - New: `INSTALL_METAMOD=1` + `INSTALL_CSS=1`
4. Restart server
5. Verify frameworks load correctly

**Backwards Compatibility:**

The old `ADDON_SELECTION` variable still works temporarily:

| Old Value                          | New Equivalent                      |
| ---------------------------------- | ----------------------------------- |
| `Metamod Only`                     | `INSTALL_METAMOD=1`                 |
| `Metamod + CounterStrikeSharp`     | `INSTALL_METAMOD=1` + `INSTALL_CSS=1` |
| `SwiftlyS2`                        | `INSTALL_SWIFTLY=1`                 |
| `ModSharp`                         | `INSTALL_MODSHARP=1`                |

This compatibility will be removed in the next major update!

## Best Practices

1. **Test updates** on dev server before production
2. **Backup plugins** before enabling auto-updates
3. **Monitor changelogs** for breaking changes
4. **Use multi-framework wisely** → Test compatibility between frameworks
5. **Keep MetaMod updated** → Required by CSS
6. **Check plugin compatibility** after updates
7. **Use stable releases** in production
8. **Enable only needed frameworks** → Reduces startup time

## FAQ

**Q: Can I use CSS and SwiftlyS2 together?**
A: Yes! They are different frameworks and can coexist. Test compatibility first.

**Q: Can I use CSS and ModSharp together?**
A: Yes! ModSharp is standalone and doesn't conflict with CSS.

**Q: Will updates break my plugins?**
A: Possibly. Major updates can have breaking changes. Test on dev server first.

**Q: Can I rollback an update?**
A: Yes, manually install older version and toggle off auto-updates for that framework.

**Q: How do I update only MetaMod, not CSS?**
A: Toggle off CSS checkbox, keep MetaMod enabled.

**Q: Are beta versions supported?**
A: No, only stable releases from official repos.

**Q: What if GitHub is down?**
A: Updates will fail, but server will start anyway. Updates will work on next restart.

**Q: Can I auto-update custom plugins?**
A: Not built-in. You'll need to modify update scripts or manage them manually.

**Q: Where are versions stored?**
A: In `/home/container/egg/versions.txt` (accessible via FTP)

**Q: Does SwiftlyS2 require MetaMod?**
A: No! SwiftlyS2 v2 is standalone and doesn't require MetaMod.

**Q: Can I enable all 4 frameworks simultaneously?**
A: Technically yes, but test thoroughly. MetaMod + CSS + SwiftlyS2 + ModSharp is a lot of overhead.

## Related Documentation

- [Auto-Restart](auto-restart.md) → Automatic server restarts
- [Configuration Files](../configuration/configuration-files.md) → All configuration options
- [Building from Source](../advanced/building.md) → Customize update logic

## Support

Having update issues?

- [Report Issue](https://github.com/K4ryuu/CS2-Egg/issues)
- [Troubleshooting Guide](../advanced/troubleshooting.md)
