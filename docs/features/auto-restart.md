# Auto-Restart Feature

Automatically restart your CS2 server when game updates are detected.

## Overview

The Auto-Restart feature monitors CS2 for updates using the Steam API (`api.steamcmd.net`). When a new version is detected, it:

1. Sends countdown warnings to players (configurable via JSON)
2. Optionally sends notifications via Discord webhook
3. Gracefully restarts the server
4. Updates to the latest CS2 version

**Key Features:**

- Fast API-based version checking (no SteamCMD conflicts)
- Fully configurable via FTP-editable JSON files
- Supports beta branches
- Discord webhook integration
- Customizable countdown commands

> **⚠️ Better Alternative Available**
>
> If you use **[VPK Sync](vpk-sync.md)** with the centralized update script, you get **superior update management**:
> - ✅ **Single download** for all servers (saves bandwidth and time)
> - ✅ **Coordinated restarts** - all servers restart together after one download completes
> - ✅ **Centralized control** - manage updates from one location
> - ✅ **Faster updates** - no duplicate downloads across servers
>
> The egg-based auto-restart works per-server (each server downloads and restarts independently). For multiple servers, the centralized script is **significantly more efficient**.

## Prerequisites

Before setting up Auto-Restart:

- ✅ Pterodactyl Panel with API access
- ✅ Admin access to configure egg variables
- ✅ Client API token (users generate their own)
- ✅ Server using this egg

## Configuration Files

Auto-restart is configured through `/home/container/egg/configs/auto-restart.json`:

```json
{
  "enabled": true,
  "check_interval": 300,
  "countdown_seconds": 300,
  "pterodactyl_url": "https://panel.example.com",
  "pterodactyl_api_token": "your-client-api-token-here",
  "discord_webhook_url": "",
  "countdown_commands": {
    "300": "say Server updating in 5 minutes!",
    "60": "say Server updating in 1 minute!",
    "30": "say Server updating in 30 seconds!",
    "10": "say Server updating in 10 seconds!",
    "3": "say Server updating in 3 seconds!",
    "2": "say Server updating in 2 seconds!",
    "1": "say Server updating in 1 second!"
  }
}
```

### Configuration Options

| Field                   | Type    | Description                              | Default          |
| ----------------------- | ------- | ---------------------------------------- | ---------------- |
| `enabled`               | boolean | Enable/disable auto-restart              | `false`          |
| `check_interval`        | number  | Seconds between version checks (60-3600) | `300`            |
| `countdown_seconds`     | number  | Warning time before restart              | `300`            |
| `pterodactyl_url`       | string  | Panel URL (no trailing slash)            | `""`             |
| `pterodactyl_api_token` | string  | Your client API token                    | `""`             |
| `discord_webhook_url`   | string  | Optional Discord webhook                 | `""`             |
| `countdown_commands`    | object  | Commands at specific times               | Default warnings |

## Admin Setup (Nest Level)

Configure default egg variables for all new servers:

1. Navigate to **Admin** → **Nests** → Your Nest → **Eggs**
2. Select **KitsuneLab CS2 Egg**
3. Go to **Variables** tab
4. Configure these variables:

### Required Variables

**Enable Auto-Restart** (`ENABLE_AUTO_RESTART`)

- Default: `0` (disabled)
- Set to `1` to enable by default
- Users can override via JSON config

### Important Security Note

⚠️ **DO NOT set default values for sensitive data:**

- API tokens are user-specific
- Can be extracted from Docker environment
- Users configure these in `/egg/configs/auto-restart.json` via FTP

## User Setup

Users configure auto-restart via FTP-editable JSON files.

### Step 1: Enable Auto-Restart

**Via Pterodactyl Startup:**

1. Go to **Startup** tab
2. Set **Enable Auto-Restart** to `1`
3. Restart server to generate config file

### Step 2: Configure via FTP

1. Connect via FTP/SFTP to your server
2. Navigate to `/egg/configs/`
3. Edit `auto-restart.json`
4. Update configuration:

```json
{
  "enabled": true,
  "check_interval": 300,
  "countdown_seconds": 300,
  "pterodactyl_url": "https://your-panel.com",
  "pterodactyl_api_token": "ptlc_YOUR_API_TOKEN_HERE",
  "discord_webhook_url": "",
  "countdown_commands": {
    "300": "say Server updating in 5 minutes!",
    "60": "say Server updating in 1 minute!",
    "30": "say Server updating in 30 seconds!",
    "10": "say Server updating in 10 seconds!"
  }
}
```

5. Save the file

### Step 3: Generate API Token

1. Click your profile picture (top right)
2. Select **API Credentials** or visit: `https://panel.your-domain.com/account/api`
3. Click **Create Client API Key**
4. Give it a descriptive name (e.g., "CS2 Server Auto-Restart")
5. Copy the token **immediately** (shown only once!)
6. Token format: `ptlc_` or `plcn_` followed by 43 characters

### Step 4: Add API Token to Config

1. Via FTP, edit `/egg/configs/auto-restart.json`
2. Replace `"pterodactyl_api_token": ""` with your token:
   ```json
   "pterodactyl_api_token": "ptlc_your_actual_token_here"
   ```
3. Update `pterodactyl_url` to your panel URL (no trailing slash)
4. Save the file

### Step 5: Restart Server

1. Restart your server to apply changes
2. Check console for confirmation:

```
[INFO] Auto-restart enabled
[INFO] Stored initial buildid: 1234567
```

## How It Works

### Detection Method

The system uses **Steam API** (`api.steamcmd.net`) for version checking:

1. Queries Steam API for latest BuildID
2. Compares with stored local BuildID
3. Supports beta branches via `SRCDS_BETAID`
4. Non-blocking (doesn't interfere with running server)

**Advantages over SteamCMD:**

- Fast (API response in <1s)
- No file conflicts with running server
- No temporary directories needed
- Reliable version detection

### Update Cycle

```
[Check Interval] → [Detect Update] → [Countdown] → [Restart] → [Update]
     ↓                                                              ↓
  (5 minutes)                                                   (Auto)
                                                                    ↓
                                                            [Server Back Online]
```

### Timing Example

With default settings (300 second check interval, 300 second countdown):

1. **00:00** - API check detects update
2. **00:00** - Webhook notification sent (if configured)
3. **00:00** - Countdown starts, commands execute
4. **05:00** - Server restarts automatically
5. **05:00** - CS2 updates to latest version
6. **~10:00** - Server back online with new version

## Verification

### Check if Enabled

Look for these console messages on startup:

✅ **Success messages:**

```
[INFO] Auto-restart enabled
[INFO] Stored initial buildid: 1234567
[SUCCESS] Version check cron job added
```

❌ **Configuration errors:**

```
[WARNING] Auto-restart enabled but API token not set
[ERROR] Invalid Pterodactyl URL format
[ERROR] Failed to restart server: HTTP 403
```

### Monitor Version Checks

Version checks run silently in background. To see activity:

1. Enable debug logging via `/egg/configs/logging.json`:
   ```json
   {
     "enabled": true,
     "log_level": "DEBUG"
   }
   ```
2. Check `/egg/logs/YYYY-MM-DD.log` for:
   ```
   [DEBUG] Checking for updates (BuildID: 1234567)
   [INFO] No update available
   ```

### Test Configuration

Verify your setup:

**Test API Token:**

```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  https://panel.your-domain.com/api/client
```

Should return your account info (not 401/403).

**Test Steam API:**

```bash
curl -sf "https://api.steamcmd.net/v1/info/730"
```

Should return JSON with CS2 build information.

## Troubleshooting

### Not Detecting Updates

**Check configuration:**

- ✅ `enabled: true` in `/egg/configs/auto-restart.json`
- ✅ API token is valid (48 chars starting with `ptlc_` or `plcn_`)
- ✅ Panel URL is correct (no trailing slash)
- ✅ Check interval between 60-3600 seconds
- ✅ Server has internet connectivity

**Verify API access:**

```bash
curl -sf "https://api.steamcmd.net/v1/info/730" | jq '.data."730".depots.branches.public.buildid'
```

### Server Not Restarting

**Common issues:**

- Invalid API token (expired, wrong format)
- Incorrect panel URL
- Token lacks restart permissions
- Rate limiting (try longer check interval)

**Check logs for errors:**

```
[ERROR] Failed to restart: HTTP 401  # Invalid token
[ERROR] Failed to restart: HTTP 403  # No permission
[ERROR] Failed to parse API response
```

### Webhook Notifications Not Working

- Verify webhook URL is correct
- Check webhook hasn't been deleted in Discord
- Test manually:
  ```bash
  curl -X POST "YOUR_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d '{"content":"Test message"}'
  ```

### API Timeouts

If Steam API is slow/unreliable:

1. System has built-in timeout (10-30s)
2. Falls back gracefully on failure
3. Logs errors for debugging
4. Won't restart unless update confirmed

## Advanced Configuration

### Custom Check Intervals

Adjust based on your needs:

```json
{
  "check_interval": 600, // 10 minutes (recommended)
  "check_interval": 1800, // 30 minutes (low-priority)
  "check_interval": 300 // 5 minutes (high-priority)
}
```

### Custom Countdown Messages

Create sophisticated countdown sequences:

```json
{
  "countdown_commands": {
    "600": "say ⚠️ Update detected! Server restarts in 10 minutes.",
    "480": "say 🔄 Update in 8 minutes...",
    "360": "say 🔄 Update in 6 minutes...",
    "240": "say ⏰ Update in 4 minutes!",
    "180": "say ⏰ Update in 3 minutes!",
    "120": "say ⚠️ Update in 2 minutes! Save your progress.",
    "60": "say ⚠️ Update in 1 MINUTE!",
    "30": "say 🔴 Update in 30 SECONDS!",
    "10": "say 🔴 10 SECONDS!",
    "5": "say 🔴 5...",
    "4": "say 🔴 4...",
    "3": "say 🔴 3...",
    "2": "say 🔴 2...",
    "1": "say 🔴 1... Restarting!"
  }
}
```

### Longer Countdown for Busy Servers

```json
{
  "countdown_seconds": 900, // 15 minutes
  "countdown_commands": {
    "900": "say Server update in 15 minutes!",
    "600": "say Server update in 10 minutes!",
    "300": "say Server update in 5 minutes!",
    "60": "say Server update in 1 minute!",
    "30": "say Server update in 30 seconds!",
    "10": "say Server update in 10 seconds!"
  }
}
```

### Beta Branch Tracking

Auto-restart automatically detects beta branches:

1. Set `SRCDS_BETAID` to your branch (e.g., `experimental`)
2. System queries correct branch buildid
3. Restarts only when beta branch updates

## Best Practices

1. **Reasonable check intervals** - 300-600 seconds
2. **Test API token** before enabling
3. **Configure countdown warnings** - Give players time to save
4. **Use webhooks** - Monitor multiple servers easily
5. **Monitor first updates** - Ensure working correctly
6. **Keep API tokens secure** - Never share or commit
7. **Regular backups** - Automation doesn't replace backups

## Security Considerations

### API Token Security

- ✅ Each user creates their own token
- ✅ Stored in FTP-accessible config file
- ✅ Can be revoked anytime via panel
- ❌ Never share tokens publicly
- ❌ Don't commit to version control
- ❌ Admins: Don't set default tokens

### File Permissions

Config files in `/egg/configs/` are:

- Readable/writable by container user (FTP access)
- Not exposed via web server
- Backed up with server data

## FAQ

**Q: How often should I check for updates?**
A: 5-10 minutes (300-600 seconds). CS2 updates are infrequent.

**Q: Can I disable countdown messages?**
A: Yes, set `countdown_commands` to `{}` (empty object).

**Q: What happens if server is full during restart?**
A: Restart happens anyway. Configure appropriate countdown time.

**Q: Can I prevent restarts during peak hours?**
A: Not built-in, but you can temporarily set `enabled: false` in config.

**Q: Does this work with beta branches?**
A: Yes, automatically detects branch from `SRCDS_BETAID`.

**Q: Will this reinstall plugins?**
A: No, only updates CS2. Plugins update based on `ADDON_SELECTION`.

**Q: What if Steam API is down?**
A: System times out gracefully, logs error, skips that check cycle.

## Related Documentation

- [Configuration Files](../configuration/configuration-files.md)
- [Auto-Updaters](./auto-updaters.md)
- [Environment Variables](../configuration/environment-variables.md)

## Support

Need help?

- [Report Issue](https://github.com/K4ryuu/CS2-Egg/issues)
- [View Troubleshooting Guide](../advanced/troubleshooting.md)
