# GDB Debugging

Remote debugging for CS2 server crash analysis and plugin development.

## Quick Setup

### 1. Port Configuration

Add **additional port** in Pterodactyl:

- **Game**: `27015` (UDP)
- **Debug**: `27016` (TCP)

Set environment variable in **Startup** tab:

```
GDB_DEBUG_PORT=27016
```

### 2. Server Behavior

**⚠️ IMPORTANT**: When GDB is enabled, server **locks on startup** until debugger connects!

Console shows:

```
[INFO] Starting GDB debugger on port 27016 (PID: 12345)
[WARNING] The console may hang until you resume it through IDA Pro or GDB client
```

Server waits frozen - **this is normal**. Connect debugger to continue.

## Connecting with IDA Pro

1. **Debugger → Attach → Remote GDB debugger**
2. Enter server IP and port `27016`
3. Resume the process

Now you can:

- Set breakpoints (F2)
- Step through code (F7/F8)
- Inspect memory and variables

## Troubleshooting

**Server frozen on startup?**

- Normal behavior! Connect debugger and resume to continue.

**Can't connect?**

- Check port allocated in Pterodactyl
- Verify firewall allows TCP on debug port
- Check `/tmp/gdb.log` in container

**Can't stop the server with Stop button?**

- The `quit` command and graceful shutdown do not work while GDB is attached
- Use the **Kill** button in Pterodactyl to force stop the server
- This is a Docker limitation with gdbserver signal handling

**Performance issues?**

- Expected with debugging enabled
- Only use on dev/test servers

## Security Warning

**⚠️ NEVER enable on production servers!**

Debugging gives full process access:

- Only use on development/testing
- Firewall the debug port
- Disable after debugging session
