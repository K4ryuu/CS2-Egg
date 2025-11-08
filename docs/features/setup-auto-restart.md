---
description: >-
  Quick setup guide for the Auto-Restart feature with API-based version checking
  and JSON configuration files.
icon: "1"
---

# Setup Auto Restart

## Overview

Auto-Restart now uses:

- **API-based version checking** (`api.steamcmd.net`) - Fast, non-blocking
- **FTP-editable JSON configs** - User-friendly configuration
- **Simplified egg variables** - Only enable flags needed

## Admin Setup (Nest Level)

1. Navigate to **Admin** → **Nests** → Your Nest → **Eggs**
2. Select the **KitsuneLab CS2 Egg**
3. Go to **Variables** tab
4. Configure default settings:

### Required Variable

**Enable Auto-Restart** (`ENABLE_AUTO_RESTART`)

- Default: `0` (disabled)
- Set to `1` to enable by default for all new servers
- Users can override via `/egg/configs/auto-restart.json`

{% hint style="danger" %}
**DO NOT set default API tokens or sensitive values!** Users configure these via FTP-accessible JSON files in `/egg/configs/`.
{% endhint %}

## Admin Setup (Server Level)

1. Navigate to **Admin** → **Servers** → Select Server
2. Go to **Startup** tab
3. Set **Enable Auto-Restart** to `1`
4. Restart server to generate config file

## User Setup (Client Side)

### Step 1: Enable Feature

1. Go to your server in the **Dashboard**
2. Navigate to **Startup** tab
3. Set **Enable Auto-Restart** to `1`
4. Restart server

### Step 2: Configure via FTP

1. Connect via FTP/SFTP to your server
2. Navigate to `/egg/configs/`
3. Open `auto-restart.json`
4. Configure settings:

```json
{
  "enabled": true,
  "check_interval": 300,
  "countdown_seconds": 300,
  "pterodactyl_url": "https://panel.your-domain.com",
  "pterodactyl_api_token": "",
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
4. Give it a name (e.g., "CS2 Auto-Restart")
5. **Copy the token immediately** (shown only once!)
6. Token format: `ptlc_` followed by 43 characters

### Step 4: Add API Token

1. Via FTP, edit `/egg/configs/auto-restart.json`
2. Update these fields:
   ```json
   "pterodactyl_url": "https://your-panel.com",
   "pterodactyl_api_token": "ptlc_your_token_here"
   ```
3. Save the file

### Step 5: Restart & Verify

1. Restart your server
2. Check console for:
   ```
   [INFO] Auto-restart enabled
   [INFO] Stored initial buildid: 1234567
   [SUCCESS] Version check cron job added
   ```

## Tips and Tricks

### Configuration Best Practices

- **Check Interval:** Set to 300-600 seconds (5-10 minutes) to avoid unnecessary API calls
- **Countdown Time:** Use 300+ seconds (5+ minutes) to give players adequate warning
- **VPK Sync Users:** Set countdown to 5+ minutes to allow centralized server to update first
- **Discord Webhooks:** Optional but helpful for monitoring multiple servers
- **API Token Security:** Never share or commit to version control

### Hosting Multiple Servers

- Configure nest-level defaults for consistent settings across all servers
- Each user still needs their own API token (configured via FTP)
- Use webhooks to monitor all servers from one Discord channel

### Plugin Data Safety

- Some plugins save inefficiently (only on player disconnect)
- Consider using `mp_timelimit` or similar to trigger saves
- Test restart behavior with your specific plugins

### Version Checking

- Uses Steam API (`api.steamcmd.net`) - Fast and reliable
- Non-blocking (doesn't interfere with running server)
- Automatically detects beta branches via `SRCDS_BETAID`
- Falls back gracefully if API is unreachable

### Troubleshooting

**No restart happening:**

- Check `/egg/configs/auto-restart.json` has valid API token
- Verify `pterodactyl_url` is correct (no trailing slash)
- Test API token with: `curl -H "Authorization: Bearer TOKEN" https://panel.com/api/client`

**Frequent false restarts:**

- Increase `check_interval` to 600+ seconds
- Verify Steam API is stable: `curl -sf https://api.steamcmd.net/v1/info/730`

**Webhook not working:**

- Verify webhook URL is valid
- Test with: `curl -X POST "WEBHOOK_URL" -H "Content-Type: application/json" -d '{"content":"test"}'`

## Related Documentation

- [Auto-Restart Feature Guide](./auto-restart.md) - Detailed documentation
- [Configuration Files](../configuration/configuration-files.md) - JSON configuration reference
- [Auto-Updaters](./auto-updaters.md) - Plugin auto-update system
