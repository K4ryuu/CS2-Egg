# 📚 KitsuneLab CS2 Egg Documentation# 📚 KitsuneLab CS2 Egg Documentation

Welcome to the official documentation for the KitsuneLab CS2 Pterodactyl Egg! This comprehensive guide will help you install, configure, and use all features.Welcome to the official documentation for the KitsuneLab CS2 Pterodactyl Egg! This comprehensive guide will help you install, configure, and use all features.

## 🚀 Quick Start## 🚀 Quick Start

New to this egg? Start here:New to this egg? Start here:

1. **[Quick Start Guide](getting-started/quickstart.md)** - Get your server running1. **[Installation Guide](getting-started/installation.md)** - Install the egg in Pterodactyl

2. **[Configuration](configuration/configuration-files.md)** - Configure features via JSON files 2. **[Quick Start](getting-started/quickstart.md)** - Get your server running

3. **[Updating Guide](getting-started/update.md)** - Keep everything up to date3. **[Updating Guide](getting-started/updating.md)** - Keep everything up to date

## 📖 Table of Contents## 📖 Table of Contents

### Getting Started### Getting Started

- [⚡ Quick Start](getting-started/quickstart.md) - Install and run your server- [📥 Installation](getting-started/installation.md) - How to install and apply the egg

- [🔄 Updating](getting-started/update.md) - Update the egg, Docker image, and addons- [⚡ Quick Start](getting-started/quickstart.md) - Get your server running quickly

- [🔄 Updating](getting-started/updating.md) - Update the egg, Docker image, and server

### Features

### Features

- [🔄 Auto-Restart](features/auto-restart.md) - Automatically restart when CS2 updates

- [💾 VPK Sync](features/vpk-sync.md) - Massive storage savings (3GB vs 30GB per server)- [🔄 Auto-Restart](features/auto-restart.md) - Automatically restart when CS2 updates

- [🧹 Junk Cleaner](features/junk-cleaner.md) - Automatic cleanup of old files- [🔧 Auto-Updaters](features/auto-updaters.md) - MetaMod, CounterStrikeSharp, and Swiftly

- [🚫 Console Filter](features/console-filter.md) - Block unwanted console messages- [� VPK Sync](features/vpk-sync.md) - Massive storage savings with centralized game files

- [🎨 Colored Logging](features/colored-logging.md) - Enhanced console output with daily rotation- [�🚫 Console Filter](features/console-filter.md) - Block unwanted console messages

- [🧹 Junk Cleaner](features/junk-cleaner.md) - Automatic cleanup of old files

### Configuration- [🎨 Colored Logging](features/colored-logging.md) - Enhanced console output

- [📝 Configuration Files](configuration/configuration-files.md) - JSON-based configuration in `/home/container/egg/configs/`### Configuration

- [🔧 Auto-Updaters](features/auto-updaters.md) - MetaMod, CounterStrikeSharp, and Swiftly

- [📝 Configuration Files](configuration/configuration-files.md) - JSON-based configuration system

## ✨ Key Features- [⚙️ Environment Variables](configuration/environment-variables.md) - All available configuration options

- [🚀 Startup Parameters](configuration/startup-parameters.md) - Customize server startup

This egg provides a comprehensive set of features for CS2 server management:

### Advanced

### 🔄 Auto-Restart

- **API-based version checking** - Uses `api.steamcmd.net` for fast, non-invasive updates- [🔨 Building from Source](advanced/building.md) - Build your own Docker image

- **Countdown system** - Configurable warnings before restart- [🔧 Troubleshooting](advanced/troubleshooting.md) - Common issues and solutions

- **Discord webhooks** - Optional notifications for update events- [🤝 Contributing](advanced/contributing.md) - How to contribute to this project

- **Beta branch support** - Works with public and beta CS2 branches

## ✨ Key Features

### 💾 VPK Sync

- **90% storage savings** - 3GB per server instead of 30GB+This egg includes many powerful features:

- **Symlink technology** - Game files stored once, linked to all servers

- **Config preservation** - Only syncs game files, preserves your configs- **🔄 Auto-Restart** - Detect CS2 updates and restart automatically

- **Automatic setup** - Just configure the sync location and go- **🔧 Auto-Updaters** - Keep MetaMod and plugins updated

- **💾 VPK Sync** - Massive storage savings with centralized files

### 🎨 Daily Log Rotation- **🧹 Junk Cleaner** - Remove old logs, demos, and backups

- **Organized logging** - One log file per day (`YYYY-MM-DD.log`)- **🎨 Colored Logs** - Beautiful, easy-to-read console output

- **Triple rotation limits** - Size, count, AND age based rotation- **🚫 Console Filter** - Hide unwanted messages

- **Configurable retention** - Set max size (MB), max files, and max days- **🔔 Webhooks** - Optional Discord notifications for updates

- **FTP accessible** - All logs in `/home/container/egg/logs/`- **⚙️ Flexible** - Works with Pterodactyl or standalone Docker

### 🧹 Junk Cleaner## 🎯 Common Tasks

- **Automatic cleanup** - Removes old files based on configurable intervals

- **Smart targeting** - Cleans backup logs, demos, CSS logs, and crash dumps### Install a New Server

- **Runs hourly** - Set-and-forget automation

- **Customizable** - Configure cleanup intervals per file type1. [Download the egg](https://github.com/K4ryuu/CS2-Egg/blob/main/pterodactyl/kitsunelab-cs2-egg.json)

2. Import into Pterodactyl

### 🚫 Console Filter3. Create a new server with the egg

- **Pattern matching** - Exact (@prefix) and contains matching4. Start and enjoy!

- **STEAM_ACC masking** - Automatically masks your GSLT token

- **Preview mode** - Test patterns before hiding messages[Full Installation Guide →](getting-started/installation.md)

- **FTP editable** - Modify patterns without server restart

### Enable Auto-Restart

### 🔧 Auto-Updaters

- **MetaMod** - Automatically updates to latest stable version1. Get a Pterodactyl API token

- **CounterStrikeSharp** - Keeps CSS with runtime updated2. Set environment variables

- **Swiftly** - Optional Swiftly plugin framework3. Enable the feature

- **Version tracking** - Stored in `/home/container/egg/versions.txt`4. Server restarts automatically on CS2 updates!

## 📁 Directory Structure[Auto-Restart Setup Guide →](features/auto-restart.md)

````### Build Custom Image

/home/container/

├── egg/                           # 🆕 Egg-specific files```bash

│   ├── configs/                   # JSON configuration files (FTP editable)git clone https://github.com/K4ryuu/CS2-Egg.git

│   │   ├── auto-restart.json     # Auto-restart, API credentials, countdowncd CS2-Egg

│   │   ├── webhook.json          # Discord webhook config./build.sh my-tag

│   │   ├── console-filter.json   # Console filter patternsdocker push your-registry/your-image:my-tag

│   │   ├── cleanup.json          # Cleanup intervals and paths```

│   │   └── logging.json          # Logging settings and rotation

│   ├── logs/                      # Daily rotating logs (if enabled)[Building Guide →](advanced/building.md)

│   │   ├── 2025-11-07.log

│   │   ├── 2025-11-06.log## 🔗 Quick Links

│   │   └── ...

│   └── versions.txt              # Addon version tracking- **[Download Egg (Stable)](https://github.com/K4ryuu/CS2-Egg/blob/main/pterodactyl/kitsunelab-cs2-egg.json)**

├── game/                          # CS2 game files- **[Download Egg (Beta)](https://github.com/K4ryuu/CS2-Egg/blob/beta/pterodactyl/kitsunelab-cs2-egg.json)**

│   └── csgo/- **[Download Egg (Dev)](https://github.com/K4ryuu/CS2-Egg/blob/dev/pterodactyl/kitsunelab-cs2-egg.json)**

│       ├── addons/               # MetaMod, CSS, Swiftly- **[Report Bug](https://github.com/K4ryuu/CS2-Egg/issues/new?assignees=KitsuneLab-Development&labels=bug&projects=&template=bug_report.md&title=%5BBUG%5D)**

│       └── cfg/                  # Server configs- **[Request Feature](https://github.com/K4ryuu/CS2-Egg/issues/new?assignees=KitsuneLab-Development&labels=enhancement&projects=&template=feature_request.md&title=%5BREQ%5D)**

├── steamcmd/                      # SteamCMD installation- **[View Changelog](../CHANGELOG)**

└── ...

```## 💡 Need Help?



## 🎯 Common TasksIf you need assistance:



### Install a New Server1. Check the [Troubleshooting Guide](advanced/troubleshooting.md)

2. Search existing [GitHub Issues](https://github.com/K4ryuu/CS2-Egg/issues)

1. Download the [egg JSON file](https://github.com/K4ryuu/CS2-Egg/blob/main/pterodactyl/kitsunelab-cs2-egg.json)3. Ask in [GitHub Discussions](https://github.com/K4ryuu/CS2-Egg/discussions)

2. Import into Pterodactyl Panel (Admin > Nests > Import Egg)4. Create a [new issue](https://github.com/K4ryuu/CS2-Egg/issues/new) if needed

3. Create a new server with the KitsuneLab CS2 egg

4. Start the server - it will auto-install and configure## 🤝 Contributing



[Full Quick Start Guide →](getting-started/quickstart.md)Want to help improve this project?



### Enable Auto-Restart- Report bugs and suggest features

- Improve documentation

1. Set `UPDATE_AUTO_RESTART=1` in Pterodactyl egg variables- Submit pull requests

2. Connect via FTP and edit `/egg/configs/auto-restart.json`- Share your experience

3. Add your Pterodactyl Panel URL and API token

4. Optionally add countdown messages and Discord webhook[Contributing Guide →](advanced/contributing.md)

5. Restart server - auto-restart is now active!

## 📝 License

[Auto-Restart Setup Guide →](features/auto-restart.md)

This project is licensed under the GPL-3.0 License - see the [LICENSE.md](../LICENSE.md) file for details.

### Configure Console Filter

## 🙏 Credits

1. Set `ENABLE_FILTER=1` in Pterodactyl egg variables

2. Edit `/egg/configs/console-filter.json` via FTP- **[1zc](https://github.com/1zc)** - Original [CS2-Pterodactyl](https://github.com/1zc/CS2-Pterodactyl) base image

3. Add patterns to filter:- **[Poggu](https://github.com/Poggicek)** - Console filter inspiration from [CleanerCS2](https://github.com/Source2ZE/CleanerCS2)

   - `"@exact match"` - Only hides exact text- All [contributors](https://github.com/K4ryuu/CS2-Egg/graphs/contributors) who help improve this project

   - `"contains this"` - Hides any line containing text

4. Restart server to apply filter---



[Console Filter Guide →](features/console-filter.md)<div align="center">

  <p>Made with ❤️ by <a href="https://github.com/K4ryuu">K4ryuu</a> @ <a href="https://kitsune-lab.com">KitsuneLab</a></p>

### Setup VPK Sync  <p>

    <a href="https://github.com/K4ryuu/CS2-Egg">⭐ Star on GitHub</a>

1. Create centralized CS2 installation on host machine  </p>

2. Configure Pterodactyl mount to expose directory</div>

3. Set `SYNC_LOCATION` variable in egg

4. Start server - VPK files are symlinked automatically# Welcome

5. Each server uses only ~3GB instead of 30GB+!

Welcome to the official documentation for Kitsune-Lab's CS2-Egg project.

[VPK Sync Guide →](features/vpk-sync.md)

The system includes various features designed to simplify server management. Automation tools ensure that your server and key add-ons are always up-to-date, clear unnecessary files, filter console outputs, and automatically restart the server when a new game version is detected—eliminating the need to manually track game updates.

## 🔗 Quick Links

The CS2-Egg project was initially created for use with the Pterodactyl platform, which is why it includes an importable egg file. However, the system's versatile design ensures compatibility with any Docker-based environment, provided that the appropriate environment variables are configured within the Docker setup. This flexibility allows users to leverage the system's features across various platforms, enhancing ease of management and functionality beyond its original scope.

- **[Download Egg (Stable)](https://github.com/K4ryuu/CS2-Egg/blob/main/pterodactyl/kitsunelab-cs2-egg.json)**

- **[Download Egg (Beta)](https://github.com/K4ryuu/CS2-Egg/blob/beta/pterodactyl/kitsunelab-cs2-egg.json)**## Features

- **[Download Egg (Dev)](https://github.com/K4ryuu/CS2-Egg/blob/dev/pterodactyl/kitsunelab-cs2-egg.json)**

- **[Report Bug](https://github.com/K4ryuu/CS2-Egg/issues/new?assignees=KitsuneLab-Development&labels=bug&projects=&template=bug_report.md&title=%5BBUG%5D)**- **Automated Restart Scheduling:** Automatically schedule a restart when a new game version is detected.

- **[Request Feature](https://github.com/K4ryuu/CS2-Egg/issues/new?assignees=KitsuneLab-Development&labels=enhancement&projects=&template=feature_request.md&title=%5BREQ%5D)**- **Restart Countdown Notifications:** Display information to players with timed commands during the restart countdown.

- **[View Changelog](../CHANGELOG)**- **Colored Logs:** Enhanced readability for main scripts with colored logs.

- **Junk Cleaner:**

## 💡 Need Help?  - Round backups: Retain for 24 hours

  - Logs: Retain for 3 days

If you need assistance:  - CSS logs: Retain for 3 days

  - Accelerator logs: Retain for 7 days

1. Check the relevant feature documentation  - Demo files: Retain for 7 days

2. Search existing [GitHub Issues](https://github.com/K4ryuu/CS2-Egg/issues)- **GameInfo Updater:** Automatically updates GameInfo file to maintain MetaMod reference.

3. Ask in [GitHub Discussions](https://github.com/K4ryuu/CS2-Egg/discussions)- **Auto-Updater:** Automatically updates CounterStrikeSharp and MetaMod to the latest versions on restart, when necessary.

4. Create a [new issue](https://github.com/K4ryuu/CS2-Egg/issues/new) if needed- **Console Filter:** Blocks your unwanted messages from appearing in the console.

- Premade variables to support custom parameters safely by user

## 🤝 Contributing

Want to help improve this project?

- Report bugs and suggest features
- Improve documentation
- Submit pull requests
- Share your experience

## 📝 License

This project is licensed under the GPL-3.0 License - see the [LICENSE.md](../LICENSE.md) file for details.

## 🙏 Credits

- **[1zc](https://github.com/1zc)** - Original [CS2-Pterodactyl](https://github.com/1zc/CS2-Pterodactyl) base image
- **[Poggu](https://github.com/Poggicek)** - Console filter inspiration from [CleanerCS2](https://github.com/Source2ZE/CleanerCS2)
- All [contributors](https://github.com/K4ryuu/CS2-Egg/graphs/contributors) who help improve this project

---

<div align="center">
  <p>Made with ❤️ by <a href="https://github.com/K4ryuu">K4ryuu</a> @ <a href="https://kitsune-lab.com">KitsuneLab</a></p>
  <p>
    <a href="https://github.com/K4ryuu/CS2-Egg">⭐ Star on GitHub</a>
  </p>
</div>
````
