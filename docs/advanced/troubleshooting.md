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

## Centralized Update Script Issues

### Script Not Running

**Problem**: Centralized update script (`misc/update-cs2-centralized.sh`) not running.

**Checklist**:

- [ ] Script has execute permissions: `chmod +x misc/update-cs2-centralized.sh`
- [ ] Docker daemon is running and accessible
- [ ] Script is configured in cron (if using auto-updates)
- [ ] VPK Sync paths are correct in script configuration

**Test manual run**:

```bash
cd /path/to/CS2-Egg
./misc/update-cs2-centralized.sh
```

**Check script logs**:

```bash
# Script outputs detailed logs during execution
# Look for errors in: SteamCMD, Docker commands, file permissions
```

### Lock File Conflicts

**Error**: `Another instance is running (lockfile exists)`

**Normal behavior**: Lock conflicts during cron execution are normal and prevent overlapping updates.

**Solutions**:

1. Wait for current update to complete (check `docker ps` for update activity)
2. Only remove lock if script is truly stuck (not running for 30+ minutes):
   ```bash
   rm /tmp/cs2-update.lock
   ```
3. Check for hung Docker operations: `docker ps -a`

### Docker Container Not Restarting

**Problem**: CS2 update completed but servers not restarting.

**Checklist**:

- [ ] `AUTO_RESTART_SERVERS="true"` in script configuration
- [ ] Docker image name matches running containers
- [ ] Docker daemon has permission to restart containers
- [ ] Containers are using VPK Sync image (docker.io/sples1/k4ryuu-cs2)

**Debug**:

```bash
# Check which containers would be restarted
docker ps --format "{{.Names}}\t{{.Image}}" | grep "sples1/k4ryuu-cs2"

# Manually restart a container
docker restart <container_name>
```

### SteamCMD Update Failures

**Error**: SteamCMD validation or update failures

**Solutions**:

1. Set `VALIDATE_INSTALL="false"` in script (faster, use for regular updates)
2. Enable validation only for troubleshooting: `VALIDATE_INSTALL="true"`
3. Check available disk space (need 60-70GB free)
4. Verify network connectivity to Steam CDN
5. Re-run script with validation enabled to repair installation

## Auto-Updater Issues

### MetaMod Won't Update

**Problem**: MetaMod stays on old version.

**Solutions**:

1. Check `INSTALL_METAMOD` is set to `1` in Pterodactyl Startup tab
2. Verify internet connectivity
3. Check metamodsource.net website is accessible
4. Manually check `/game/csgo/addons/metamod/` exists
5. Review console logs for download errors
6. Delete `/egg/versions.txt` and restart to force re-download

### CounterStrikeSharp Won't Update

**Problem**: CSS doesn't update or install.

**Solutions**:

1. Set `INSTALL_CSS` to `1` in Pterodactyl Startup tab
2. MetaMod automatically enabled (it's a dependency) - check for warning message
3. Check GitHub API isn't rate-limited
4. Verify `/game/csgo/addons/counterstrikesharp/` directory
5. Check console for download/extraction errors
6. Delete `/egg/versions.txt` and restart to force re-download

### SwiftlyS2 Won't Install

**Problem**: SwiftlyS2 not working.

**Solutions**:

1. Set `INSTALL_SWIFTLY` to `1` in Pterodactyl Startup tab
2. SwiftlyS2 v2 is standalone (no MetaMod required)
3. Check GitHub releases are accessible (swiftly-solution/swiftlys2)
4. Look for errors in console during startup
5. Verify `/game/csgo/addons/swiftlys2/` directory exists

### ModSharp Won't Install

**Problem**: ModSharp not working.

**Solutions**:

1. Set `INSTALL_MODSHARP` to `1` in Pterodactyl Startup tab
2. Check .NET 9 runtime installation succeeded (check logs)
3. Verify GitHub releases accessible (Kxnrl/modsharp-public)
4. Check `/game/sharp/` directory exists
5. Review console for download/extraction errors

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

- Server running on slow hardware
- Many players online
- Resource-intensive plugins

**Solutions**:

1. Disable unnecessary features (filter, logging if not needed)
2. Upgrade server resources
3. Optimize plugins

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

1. [✓] Check this troubleshooting guide
2. [✓] Search existing GitHub issues
3. [✓] Check console logs for errors
4. [✓] Verify your configuration
5. [✓] Test with default settings

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
