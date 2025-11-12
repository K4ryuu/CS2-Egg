# 📚 KitsuneLab CS2 Egg Documentation

Welcome to the official documentation for the KitsuneLab CS2 Pterodactyl Egg! This comprehensive guide will help you install, configure, and use all features.

## 🚀 Quick Start

New to this egg? Start here:

1. **[Installation Guide](getting-started/installation.md)** - Install the egg in Pterodactyl

2. **[Quick Start](getting-started/quickstart.md)** - Get your server running

3. **[Updating Guide](getting-started/update.md)** - Keep everything up to date

## 📖 Table of Contents

### Getting Started

- [📥 Installation](getting-started/installation.md) - How to install and apply the egg

- [⚡ Quick Start](getting-started/quickstart.md) - Get your server running quickly

- [🔄 Updating](getting-started/update.md) - Update the egg, Docker image, and server

### Features

- [🔄 Auto-Restart](features/auto-restart.md) - Automatically restart when CS2 updates

- [🔧 Auto-Updaters](features/auto-updaters.md) - MetaMod, CounterStrikeSharp, Swiftly, and ModSharp

- [💾 VPK Sync](features/vpk-sync.md) - Massive storage savings with centralized game files

### Configuration

- [📝 Configuration Files](configuration/configuration-files.md) - JSON-based configuration system

### Advanced

- [🔨 Building from Source](advanced/building.md) - Build your own Docker image

- [🔧 Troubleshooting](advanced/troubleshooting.md) - Common issues and solutions

## ✨ Key Features

This egg includes many powerful features:

- **🔄 Auto-Restart** - Detect CS2 updates and restart automatically

- **🔧 Auto-Updaters** - Keep MetaMod, CounterStrikeSharp, Swiftly, and ModSharp updated

- **💾 VPK Sync** - Save ~52GB per server with centralized files

- **🧹 Junk Cleaner** - Automatic cleanup configured via JSON

- **🎨 Colored Logs** - Enhanced console output with rotation

- **🚫 Console Filter** - Pattern-based message filtering

- **🔔 Webhooks** - Optional Discord notifications for events

- **⚙️ Flexible** - Works with Pterodactyl or standalone Docker

## 🎯 Common Tasks

### Install a New Server

1. [Download the egg](https://github.com/K4ryuu/CS2-Egg/blob/main/pterodactyl/kitsunelab-cs2-egg.json)

2. Import into Pterodactyl

3. Create a new server with the egg

4. Start and enjoy!

[Full Installation Guide →](getting-started/installation.md)

### Enable Auto-Restart

1. Get a Pterodactyl API token

2. Set environment variables

3. Enable the feature

4. Server restarts automatically on CS2 updates!

[Auto-Restart Setup Guide →](features/auto-restart.md)

### Build Custom Image

```bash
git clone https://github.com/K4ryuu/CS2-Egg.git
cd CS2-Egg
./build.sh my-tag
docker push your-registry/your-image:my-tag
```

[Building Guide →](advanced/building.md)

## 🔗 Quick Links

- **[Download Egg (Stable)](https://github.com/K4ryuu/CS2-Egg/blob/main/pterodactyl/kitsunelab-cs2-egg.json)**

- **[Download Egg (Beta)](https://github.com/K4ryuu/CS2-Egg/blob/beta/pterodactyl/kitsunelab-cs2-egg.json)**

- **[Download Egg (Dev)](https://github.com/K4ryuu/CS2-Egg/blob/dev/pterodactyl/kitsunelab-cs2-egg.json)**

- **[Report Bug](https://github.com/K4ryuu/CS2-Egg/issues/new?assignees=KitsuneLab-Development&labels=bug&projects=&template=bug_report.md&title=%5BBUG%5D)**

- **[Request Feature](https://github.com/K4ryuu/CS2-Egg/issues/new?assignees=KitsuneLab-Development&labels=enhancement&projects=&template=feature_request.md&title=%5BREQ%5D)**

- **[View Changelog](../CHANGELOG)**

## 💡 Need Help?

If you need assistance:

1. Check the [Troubleshooting Guide](advanced/troubleshooting.md)

2. Search existing [GitHub Issues](https://github.com/K4ryuu/CS2-Egg/issues)

3. Ask in [GitHub Discussions](https://github.com/K4ryuu/CS2-Egg/discussions)

4. Create a [new issue](https://github.com/K4ryuu/CS2-Egg/issues/new) if needed

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
