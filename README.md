<a name="readme-top"></a>

![GitHub Repo stars](https://img.shields.io/github/stars/K4ryuu/CS2-Egg?style=for-the-badge)
![GitHub issues](https://img.shields.io/github/issues/K4ryuu/CS2-Egg?style=for-the-badge)
![GitHub](https://img.shields.io/github/license/K4ryuu/CS2-Egg?style=for-the-badge)
![GitHub last commit (branch)](https://img.shields.io/github/last-commit/K4ryuu/CS2-Egg/dev?style=for-the-badge)

<!-- PROJECT LOGO -->
<br />
<div align="center">
  <h1 align="center">KitsuneLab©</h1>
  <h3 align="center">CS2 Egg</h3>
  <a align="center">CS2 Pterodactyl Egg with custom scripts such as CSS auto-updater, MetaMod auto-updater, junk cleaner, auto restart on update with colored logging.</a>

  <p align="center">
    <br />
    <a href="https://github.com/K4ryuu/CS2-Egg/blob/dev/pterodactyl/kitsunelab-cs2-egg.json">Download</a>
    ·
    <a href="https://github.com/K4ryuu/CS2-Egg/blob/beta/pterodactyl/kitsunelab-cs2-egg.json">Download Beta</a>
    ·
    <a href="https://github.com/K4ryuu/CS2-Egg/issues/new?assignees=KitsuneLab-Development&labels=bug&projects=&template=bug_report.md&title=%5BBUG%5D">Report Bug</a>
    ·
    <a href="https://github.com/K4ryuu/CS2-Egg/issues/new?assignees=KitsuneLab-Development&labels=enhancement&projects=&template=feature_request.md&title=%5BREQ%5D">Request Feature</a>
    ·
    <a href="docs/README.md">Documentation</a>
  </p>
</div>

## ✨ Features

- 🔄 **Auto-Restart** - Automatically restart when CS2 updates are detected
- 🔧 **Auto-Updaters** - MetaMod, CounterStrikeSharp, and Swiftly auto-updates
- 💾 **VPK Sync** - Massive storage & bandwidth savings (80% reduction!)
- 🧹 **Junk Cleaner** - Automatic cleanup (round backups, logs, demos)
- 🎨 **Colored Logging** - Enhanced console output with color-coded messages
- 🚫 **Console Filter** - Block unwanted console messages (inspired by [Poggu](https://github.com/Poggicek)'s [CleanerCS2](https://github.com/Source2ZE/CleanerCS2))
- 💾 **Version Tracking** - Smart updates only when necessary
- 🔔 **Discord Webhooks** - Get notified about scheduled restarts
- ⚙️ **Custom Parameters** - Safe user-configurable startup options

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## 📚 Documentation

Comprehensive documentation is available:

### 🚀 Quick Start

- **[Installation Guide](docs/getting-started/installation.md)** - Install and configure the egg
- **[Quick Start](docs/getting-started/quickstart.md)** - Get running quickly
- **[Updating](docs/getting-started/updating.md)** - Update guide

### ⚡ Features

- **[Auto-Restart](docs/features/auto-restart.md)** - Automatic CS2 update restarts
- **[Auto-Updaters](docs/features/auto-updaters.md)** - Plugin auto-updates
- **[VPK Sync](docs/features/vpk-sync.md)** - 80% storage savings
- **[Console Filter](docs/features/console-filter.md)** - Message filtering
- **[Junk Cleaner](docs/features/junk-cleaner.md)** - Automatic cleanup

### 🔧 Advanced

- **[Building from Source](docs/advanced/building.md)** - Build your own image
- **[Troubleshooting](docs/advanced/troubleshooting.md)** - Common issues

[**📖 View Full Documentation →**](docs/README.md)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## 🎯 Quick Build

Build your own Docker image:

```bash
# Clone and build
git clone https://github.com/K4ryuu/CS2-Egg.git
cd CS2-Egg
./build.sh dev

# Push to your registry
docker push sples1/k4ryuu-cs2:dev
```

See [Building from Source](docs/advanced/building.md) for details.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Credits

- [CS2 Pterodactyl from 1zc](https://github.com/1zc/CS2-Pterodactyl): The base of the image is maximally based on this image and if you don't want to use the custom scripts, you can use this image instead. Appreciate the work of [1zc](https://github.com/1zc) and give him a star.

## Roadmap

- [ ] No plans for now

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- LICENSE -->

## License

Distributed under the GPL-3.0 License. See `LICENSE.md` for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>
