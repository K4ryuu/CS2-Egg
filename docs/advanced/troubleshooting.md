# Troubleshooting

Common issues and their solutions.

## Installation Issues

### Server Won't Start After Installation

**Symptoms**: Server stops immediately after starting, or shows error in console.

**Solutions**:

1. Check if you have enough disk space (40GB+ recommended)
2. Verify Docker image pulled successfully
3. Check console for SteamCMD errors
4. Ensure ports are not already in use

### SteamCMD Download Fails

**Error**: `Failed to download SteamCMD` or `Connection timeout`

**Solutions**:

1. Check your node's internet connection
2. Verify firewall isn't blocking Steam CDN
3. Check if Steam servers are up: https://steamstat.us/
4. Try restarting the server

### Exit Code 8 - Connection Error

**Error**: `SteamCMD failed with exit code 8`

**Solutions**:

1. Check network connectivity to Steam servers
2. Verify DNS is working properly
3. Check available disk space (need 30-40GB free)
4. Disable VPN/proxy if using one
5. Wait a few minutes and try again (temporary Steam issue)

## Auto-Restart Issues

### Auto-Restart Not Working

**Problem**: Server doesn't restart when CS2 updates.

**Checklist**:

- [ ] `ENABLE_AUTO_RESTART` is set to `1` in Pterodactyl startup
- [ ] `/egg/configs/auto-restart.json` exists with `"enabled": true`
- [ ] `pterodactyl_api_token` is set (48 chars, starts with `ptlc_` or `plcn_`)
- [ ] `pterodactyl_url` is correct (e.g., `https://panel.domain.com`)
- [ ] API token has proper permissions
- [ ] `check_interval` is set (60-3600 seconds)

**Check logs**:

```bash
# In server console, look for:
[INFO] Auto-restart enabled
[INFO] Stored initial buildid: XXXXXX
[SUCCESS] Version check cron job added
```

**Check config file via FTP**:

- Navigate to `/egg/configs/auto-restart.json`
- Verify all fields are properly set

### API Token Invalid

**Error**: `Failed to restart server: HTTP 403` or `HTTP 401`

**Solutions**:

1. Generate new API token:
   - Go to Account → API Credentials
   - Create Client API Key
   - Give it a descriptive name
   - Copy the token immediately (shown only once)
2. Verify token format: `ptlc_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX` (48 chars)
3. Update `/egg/configs/auto-restart.json` via FTP:
   ```json
   "pterodactyl_api_token": "ptlc_your_new_token_here"
   ```
4. Ensure token hasn't expired
5. Check token has permission to control servers

### Steam API Issues

**Error**: `Failed to check version` or API timeouts

**Solutions**:

1. Verify Steam API is accessible:
   ```bash
   curl -sf "https://api.steamcmd.net/v1/info/730"
   ```
2. Check timeout in logs (system has 10-30s built-in timeout)
3. System falls back gracefully on API failures
4. Increase `check_interval` to reduce frequency

### False Update Detections

**Problem**: Server restarts even when no update available.

**Solutions**:

1. Increase `check_interval` in `/egg/configs/auto-restart.json` to 600+ seconds
2. Check if Steam API is having issues: `https://api.steamcmd.net/v1/info/730`
3. Verify buildid is stable across checks
4. Check logs for buildid changes

## Auto-Updater Issues

### MetaMod Won't Update

**Problem**: MetaMod stays on old version.

**Solutions**:

1. Check `ADDON_SELECTION` is set to `metamod`, `metamod_css`, or `metamod_swiftly`
2. Verify internet connectivity
3. Check AlliedMods website is accessible
4. Manually check `/game/csgo/addons/metamod/` exists
5. Review console logs for download errors

### CounterStrikeSharp Won't Update

**Problem**: CSS doesn't update or install.

**Solutions**:

1. Set `ADDON_SELECTION` to `metamod_css`
2. Ensure MetaMod is installed first (it's a dependency)
3. Check GitHub API isn't rate-limited
4. Verify `/game/csgo/addons/counterstrikesharp/` directory
5. Check console for download/extraction errors

### Swiftly Won't Install

**Problem**: Swiftly plugin not working.

**Solutions**:

1. Set `ADDON_SELECTION` to `metamod_swiftly`
2. Verify MetaMod is installed
3. Check Swiftly GitHub releases are accessible
4. Look for errors in console during startup

## Console Filter Issues

### Filter Not Working

**Problem**: Messages still appear that should be filtered.

**Solutions**:

1. Verify `ENABLE_CONSOLE_FILTER` is set to `1` in Pterodactyl startup
2. Check `/egg/configs/console-filter.json` exists and `"enabled": true`
3. Verify filter patterns are correct (supports regex)
4. Check console for filter loading messages
5. Edit patterns via FTP in `/egg/configs/console-filter.json`

### Too Many Messages Filtered

**Problem**: Important messages are being hidden.

**Solutions**:

1. Edit `/egg/configs/console-filter.json` via FTP
2. Review your `filter_patterns` array
3. Use more specific patterns
4. Remove overly broad patterns
5. Test changes by restarting server

### Filter Configuration Not Loading

**Problem**: Changes to filter config not applied.

**Solutions**:

1. Verify JSON syntax is valid (use JSONLint.com)
2. Check file permissions on `/egg/configs/console-filter.json`
3. Restart server after making changes
4. Check logs for JSON parsing errors

## Cleanup Issues

### Files Not Being Cleaned

**Problem**: Old files accumulating.

**Solutions**:

1. Verify `ENABLE_CLEANUP` is set to `1`
2. Check `/egg/configs/cleanup.json` exists with `"enabled": true`
3. Verify cleanup patterns match your files
4. Check cleanup intervals are appropriate
5. Look for cleanup messages in logs

### Important Files Deleted

**Problem**: Cleaner removed files you wanted to keep.

**Solutions**:

1. Edit `/egg/configs/cleanup.json` via FTP
2. Adjust `max_age_days` values to be more conservative
3. Modify `file_patterns` to be more specific
4. Disable cleanup: Set `"enabled": false` in config
5. Restore from backups

## Logging Issues

### Logs Not Being Created

**Problem**: No log files in `/egg/logs/`.

**Solutions**:

1. Verify `ENABLE_LOGGING` is set to `1`
2. Check `/egg/configs/logging.json` has `"enabled": true`
3. Verify `/egg/logs/` directory exists and is writable
4. Check for error messages during startup
5. Logs are created on first write (may be delayed)

### Log Rotation Not Working

**Problem**: Single log file growing too large.

**Solutions**:

1. Check `/egg/configs/logging.json` rotation settings:
   ```json
   "rotation": {
     "max_size_mb": 100,
     "max_files": 30,
     "max_days": 7
   }
   ```
2. Verify rotation logic runs (check startup logs)
3. Ensure rotation limits are reasonable
4. Check disk space availability

### Too Many/Few Log Files

**Problem**: Unexpected number of log files retained.

**Solutions**:

1. Edit `/egg/configs/logging.json` via FTP
2. Adjust `max_files` (number of files) and `max_days` (age in days)
3. Rotation deletes files when: size>max OR count>max OR age>max
4. Set stricter limits if too many files
5. Restart to apply new settings

## Performance Issues

### High CPU Usage

**Possible causes**:

- Too frequent version checks (increase `check_interval` in auto-restart config)
- Server running on slow hardware
- Many players online
- Resource-intensive plugins

**Solutions**:

1. Increase auto-restart check interval to 600+ seconds
2. Disable unnecessary features (filter, logging if not needed)
3. Upgrade server resources
4. Optimize plugins

### High Memory Usage

**Solutions**:

1. Increase allocated RAM in Pterodactyl
2. Check for memory leaks in plugins
3. Monitor with `docker stats`
4. Review log file sizes (old logs consuming memory)

## Docker Issues

### Container Keeps Restarting

**Symptoms**: Server starts, then stops, then starts again repeatedly.

**Solutions**:

1. Check Docker logs: `docker logs <container_id>`
2. Verify no port conflicts
3. Check for errors in entrypoint script
4. Ensure all required environment variables are set

### Permission Denied Errors

**Error**: Various permission denied messages.

**Solutions**:

1. Verify container user has proper permissions
2. Check Pterodactyl node configuration
3. Ensure Docker is configured correctly
4. Check `/egg/` directory permissions
5. Verify SELinux/AppArmor isn't blocking

## Network Issues

### Can't Connect to Server

**Problem**: Server shows as online but can't connect.

**Checklist**:

- [ ] Port 27015 (UDP) is allocated and open
- [ ] Firewall allows UDP traffic
- [ ] Server has valid GSLT token
- [ ] Server is actually running (check console)
- [ ] Correct IP:port combination

### Server Not Appearing in Browser

**Solutions**:

1. Set valid `STEAM_ACC` (GSLT token)
2. Generate token: https://steamcommunity.com/dev/managegameservers
3. Ensure server is public (not LAN only)
4. Check Steam account is in good standing

## Logging Issues

### No Console Output

**Problem**: Console shows nothing or minimal output.

**Solutions**:

1. Check if output is being filtered too aggressively
2. Disable filter temporarily: `ENABLE_FILTER=0`
3. Check `LOG_LEVEL` setting
4. Verify Docker logs are working

### Logs Too Verbose

**Problem**: Too many debug messages.

**Solutions**:

1. Change `LOG_LEVEL` from `DEBUG` to `INFO` or `WARNING`
2. Disable `LOG_FILE_ENABLED` if not needed
3. Adjust filter to hide debug messages

## Getting More Help

### Before Asking for Help

1. ✅ Check this troubleshooting guide
2. ✅ Search existing GitHub issues
3. ✅ Check console logs for errors
4. ✅ Verify your configuration
5. ✅ Test with default settings

### When Reporting Issues

Include:

- [ ] Egg version (dev/beta/main)
- [ ] Docker image tag
- [ ] Full error message from console
- [ ] Relevant environment variables (hide sensitive data!)
- [ ] Steps to reproduce
- [ ] Server specifications

### Where to Get Help

- [GitHub Issues](https://github.com/K4ryuu/CS2-Egg/issues) - Bug reports and feature requests
- [GitHub Discussions](https://github.com/K4ryuu/CS2-Egg/discussions) - Questions and community help

## Common Error Messages

### "Segmentation fault"

Usually a CS2 server crash, not related to the egg. Check CS2 server logs and plugins.

### "Connection to Steam servers successful"

This is GOOD! It means server started successfully.

### "Failed to load plugin"

Check plugin compatibility with current CS2 version and installed dependencies.

### "Rate limit exceeded"

GitHub/Steam API rate limit. Increase check intervals or wait before retrying.

## Emergency Recovery

### Server Completely Broken

1. Stop the server
2. Backup current files
3. Set `SRCDS_VALIDATE=1` to force validation
4. Restart server (will re-download game files)
5. Restore custom configs after validation

### Start from Scratch

1. Stop server
2. Backup important files (configs, databases)
3. Delete server files
4. Reinstall from Pterodactyl panel
5. Restore backed up files

## Still Having Issues?

[Create a GitHub Issue](https://github.com/K4ryuu/CS2-Egg/issues/new/choose) with all relevant information.
