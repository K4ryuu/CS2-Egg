# Automatic Cleanup

Rule-based disk cleanup for demo files, logs, backups, and crash dumps. Every cleanup rule is declarative — you edit a JSON config, not code.

## Enable

Set `CLEANUP_ENABLED=1` in your Pterodactyl/Pelican egg startup variables. Cleanup runs as part of the normal update/install flow.

## Config location

```
/home/container/egg/configs/cleanup.json
```

The file is auto-generated on first boot with sensible defaults. Edit via the panel file manager, SFTP, or `nano`. Save and restart the server to apply.

## Default rules

Out of the box, six rules cover the common disk hogs:

| Rule | What | Default age |
|------|------|-------------|
| `backup_rounds` | CS2 match backup `backup_round*.txt` | 24 h |
| `demos` | SourceTV `.dem` recordings | 168 h (7 days) |
| `css_logs` | CounterStrikeSharp `logs/*.txt` | 72 h (3 days) |
| `swiftly_logs` | SwiftlyS2 `logs/*.log` | 72 h (3 days) |
| `accelerator_dumps` | AcceleratorCS2 `*.dmp` + `*.dmp.txt` | 168 h (7 days) |
| `core_dumps` | Linux core files (`core`, `core.NNNN`) | 0 h (every run) |

## Rule schema

Each entry in `rules` has:

```json
{
  "name": "demos",
  "description": "SourceTV demo recordings",
  "directories": ["./game/csgo"],
  "patterns": ["*.dem"],
  "hours": 168,
  "recursive": true,
  "enabled": true
}
```

| Field | Type | Meaning |
|-------|------|---------|
| `name` | string | Stat category shown in log output. Keep it short. |
| `description` | string | Free-text comment, ignored by the engine. |
| `directories` | string[] | Paths to search. Relative paths resolve from `/home/container` (the container working dir). Absolute paths are fine too. |
| `patterns` | string[] | Filename globs. Matched against the **basename**, not the full path. `*.dem`, `core`, `core.[0-9]*`, `backup_round*.txt` all work. |
| `hours` | number | Files whose modification time is older than this many hours get deleted. `0` = delete every match regardless of age. |
| `recursive` | bool | `true` = descend into subdirectories. `false` = only the directory's top level (`-maxdepth 1`). |
| `enabled` | bool | `false` = skip this rule (without deleting the entry). |

## Common customizations

### Keep demos longer

```json
{
  "name": "demos",
  "directories": ["./game/csgo"],
  "patterns": ["*.dem"],
  "hours": 720,
  "recursive": true,
  "enabled": true
}
```
720 h = 30 days.

### Never clean demos (preserve all recordings)

```json
{
  "name": "demos",
  "directories": ["./game/csgo"],
  "patterns": ["*.dem"],
  "hours": 168,
  "recursive": true,
  "enabled": false
}
```
`enabled: false` disables the rule without removing it — easy to flip back later.

### Clean a custom plugin's logs

```json
{
  "name": "my_plugin_logs",
  "description": "Purge MyPlugin logs older than 2 days",
  "directories": ["./game/csgo/addons/myplugin/logs"],
  "patterns": ["*.log"],
  "hours": 48,
  "recursive": false,
  "enabled": true
}
```

### Sweep screenshots / maps / temp files

```json
{
  "name": "temp_maps",
  "directories": ["./game/csgo/maps/workshop"],
  "patterns": ["*.tmp", "*.cache"],
  "hours": 1,
  "recursive": true,
  "enabled": true
}
```

### Multiple directories in one rule

```json
{
  "name": "core_dumps",
  "directories": ["./game/bin/linuxsteamrt64", "/home/container"],
  "patterns": ["core", "core.[0-9]*"],
  "hours": 0,
  "recursive": false,
  "enabled": true
}
```
The default `core_dumps` rule already demonstrates this.

## How it runs

1. Cleanup executes as part of the entrypoint update flow when `CLEANUP_ENABLED=1`.
2. For each **enabled** rule, the engine builds a `find` command:
   - `find <directories> [-maxdepth 1] -type f \( -name <p1> -o -name <p2> ... \) [-mmin +<hours*60>]`
3. Matching files are deleted, total bytes freed and per-rule counts tracked.
4. Single summary line logged at the end:
   ```
   KitsuneLab |  OK   | Cleaned up 17 file(s), freed 1.23 GB in 2s
   KitsuneLab | DEBUG |   demos: 14 file(s)
   KitsuneLab | DEBUG |   core_dumps: 3 file(s)
   ```
5. If nothing was deleted, no log appears — cleanup stays silent.

## Caveats

- **Globs are basename-only.** `"patterns": ["*.dem"]` matches `backup.dem` anywhere under the directory, not `demos/backup.dem` literally. Use `directories` to scope where to search.
- **Symlinks are NOT followed** (find default). If you have symlinked cleanup targets, reference the real path.
- **Paths are evaluated at cleanup time.** Relative paths resolve from the container's working dir (`/home/container`), not from where cleanup.sh lives.
- **Regex is NOT supported.** Only shell globs (`*`, `?`, `[...]`). If you need complex matching, split into multiple patterns or rules.
- **Config version must match.** When the egg bumps `CONFIG_VERSION` and the schema changes, your `cleanup.json` is archived and a fresh default is written. Document custom rules outside the file or re-port them after an upgrade.

## Debugging

Cleanup quiet but files aren't going away? Check:

1. **Is `CLEANUP_ENABLED=1`?** Pterodactyl startup variable.
2. **Does the rule's `enabled` say `true`?**
3. **Does `hours` match reality?** `hours: 168` means file must be older than 7 days. Fresh files stay.
4. **Does the directory exist?** Non-existent directories are silently skipped. Check paths.
5. **Raise log level to `DEBUG`** in `logging.json` to see per-rule counts even when zero matches.

## Related

- Config schema details → [configuration/configuration-files.md](../configuration/configuration-files.md)
- Error codes that cleanup can emit → [advanced/error-codes.md](../advanced/error-codes.md)
