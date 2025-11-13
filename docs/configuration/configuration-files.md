# Configuration Files

The KitsuneLab CS2 Egg uses JSON configuration files for easy, persistent customization.

## Location

All configuration files are stored in:
```
/home/container/egg/configs/
```

Files are automatically created on first startup with default values and detailed descriptions.

## Configuration System

### How It Works

1. **Enable features** via Pterodactyl egg variables (e.g., `ENABLE_FILTER=1`)
2. **Configure details** via JSON files (e.g., API tokens, intervals, patterns)
3. **Edit via FTP** - All configs are accessible through SFTP/FTP
4. **Restart to apply** - Changes take effect on server restart

### Benefits

- - **FTP Accessible** - Edit without panel access
- - **Well Documented** - Each file includes `_description` with examples
- - **Persistent** - Survives server restarts and updates
- - **Type Safe** - JSON structure prevents configuration errors
- - **Version Controlled** - Easy to backup and restore

## Configuration Files

### `console-filter.json`

**Purpose:** Filter unwanted console messages

**Enable:** Set `ENABLE_FILTER=1` in Pterodactyl egg

```json
{
  "preview_mode": false,
  "patterns": [
    "Certificate expires"
  ]
}
```

**Key Settings:**
- `preview_mode` - Show what would be filtered (testing)
- `patterns` - Array of patterns to filter
  - `"@exact text"` - Exact match only
  - `"contains this"` - Contains match (default)

**Example Patterns:**
```json
{
  "patterns": [
    "@Server is hibernating",
    "edicts used",
    "ConVarRef",
    "Fontconfig error"
  ]
}
```

**Note:** `STEAM_ACC` (GSLT token) is automatically masked regardless of settings.

---

### `cleanup.json`

**Purpose:** Automatic cleanup of old files

**Enable:** Set `CLEANUP_ENABLED=1` in Pterodactyl egg

```json
{
  "intervals": {
    "backup_rounds_hours": 24,
    "demos_hours": 168,
    "css_logs_hours": 72,
    "accelerator_dumps_hours": 168
  },
  "paths": {
    "game_directory": "./game/csgo",
    "accelerator_dumps": "./game/csgo/addons/AcceleratorCS2/dumps"
  }
}
```

**Key Settings:**
- `intervals` - Hours to keep files
  - `backup_rounds_hours` - Round backups (default: 24h)
  - `demos_hours` - Demo files (default: 168h = 7 days)
  - `css_logs_hours` - CounterStrikeSharp logs (default: 72h = 3 days)
  - `accelerator_dumps_hours` - Crash dumps (default: 168h = 7 days)

Cleanup runs every hour automatically.

---

### `logging.json`

**Purpose:** Configure console output and daily log rotation

**Note:** Always loaded, no environment variable needed

```json
{
  "logging": {
    "console_level": "INFO",
    "file_enabled": false,
    "file_level": "DEBUG",
    "max_size_mb": 100,
    "max_files": 30,
    "max_days": 7
  },
  "colors": {
    "enabled": true,
    "use_emoji": true
  }
}
```

**Key Settings:**
- `console_level` - Console verbosity: `DEBUG`, `INFO`, `WARNING`, `ERROR`
- `file_enabled` - Save logs to `/home/container/egg/logs/`
- `file_level` - File log verbosity (can be more detailed than console)
- `max_size_mb` - Max total log directory size (MB)
- `max_files` - Max number of log files to keep
- `max_days` - Max age of log files (days)
- `colors.enabled` - Colored console output
- `colors.use_emoji` - Emoji icons in logs

**Log Rotation:**
- One file per day: `YYYY-MM-DD.log`
- Automatically deleted when ANY limit is reached (size OR count OR age)
- Location: `/home/container/egg/logs/`

---

## Accessing Configuration Files

### Via FTP/SFTP

1. Connect to your server via FTP
2. Navigate to `/egg/configs/`
3. Edit JSON files with any text editor
4. Save and restart server

### Via Pterodactyl File Manager

1. Go to your server in Pterodactyl
2. Click **Files**
3. Navigate to `egg/configs/`
4. Click file to edit
5. Save and restart server

### Via Console

```bash
# View config
cat egg/configs/console-filter.json

# Edit with nano
nano egg/configs/console-filter.json
```

## First-Time Setup

On first startup:

1. `/home/container/egg/configs/` directory is created
2. All JSON files are created with defaults
3. Each file includes `_description` array with documentation
4. All features are disabled by default
5. Edit files to configure and enable features

## Configuration Workflow

### Step 1: Enable Feature

In Pterodactyl egg variables, set to `1`:
- `ENABLE_FILTER` - Console filter
- `CLEANUP_ENABLED` - Junk cleaner

**Note:** For automatic CS2 updates and server restarts, see the [VPK Sync & Centralized Updates](../features/vpk-sync.md) guide.

### Step 2: Configure Details

Edit corresponding JSON file in `/egg/configs/` via FTP:
- Add API tokens
- Set intervals and timings
- Configure patterns or commands
- Customize colors and usernames

### Step 3: Restart Server

Changes apply on next server start.

## Examples

### Enable Console Filter

1. Set `ENABLE_FILTER=1` in egg
2. Edit `egg/configs/console-filter.json`:

```json
{
  "preview_mode": false,
  "patterns": [
    "HostStateTransition",
    "edicts used",
    "@Server is hibernating"
  ]
}
```

3. Restart server

### Enable Daily Log Files

1. Edit `egg/configs/logging.json`:

```json
{
  "logging": {
    "console_level": "INFO",
    "file_enabled": true,
    "file_level": "DEBUG",
    "max_size_mb": 100,
    "max_files": 30,
    "max_days": 7
  }
}
```

2. Restart server
3. Logs appear in `/egg/logs/YYYY-MM-DD.log`

## Troubleshooting

### Config Not Loading

**Check:**
- File exists in `/home/container/egg/configs/`
- Valid JSON syntax (use jsonlint.com)
- Feature enabled via Pterodactyl egg variable
- Server restarted after changes

### Feature Not Working

**Check:**
- Enabled in Pterodactyl egg (`=1`)
- Required fields filled (API tokens, URLs)
- Console logs for errors
- Correct JSON syntax

### Reset to Defaults

Delete config file and restart server:

```bash
rm /home/container/egg/configs/console-filter.json
# Restart - default config recreated
```

Or delete all configs:

```bash
rm -rf /home/container/egg/configs/
# Restart - all defaults recreated
```

## Backup and Restore

### Backup

Via FTP:
1. Download entire `/egg/` directory
2. Includes all configs, logs, and versions

Via Console:
```bash
cd /home/container
tar -czf egg-backup.tar.gz egg/
# Download egg-backup.tar.gz via FTP
```

### Restore

Via FTP:
1. Upload backup
2. Extract to `/home/container/egg/`
3. Restart server

Via Console:
```bash
cd /home/container
tar -xzf egg-backup.tar.gz
# Restart server
```

## Related Documentation

- [VPK Sync & Centralized Updates](../features/vpk-sync.md)
- [Auto-Updaters](../features/auto-updaters.md)
- [VPK Sync](../features/vpk-sync.md)
- [Quick Start](../getting-started/quickstart.md)

## Support

Need help with configuration?

- [GitHub Issues](https://github.com/K4ryuu/CS2-Egg/issues)
- [GitHub Discussions](https://github.com/K4ryuu/CS2-Egg/discussions)
