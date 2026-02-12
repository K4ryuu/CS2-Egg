<a name="readme-top"></a>
 
![GitHub Repo stars](https://img.shields.io/github/stars/K4ryuu/CS2-Egg?style=for-the-badge)
![GitHub issues](https://img.shields.io/github/issues/K4ryuu/CS2-Egg?style=for-the-badge)
![GitHub](https://img.shields.io/github/license/K4ryuu/CS2-Egg?style=for-the-badge)
![Docker Pulls](https://img.shields.io/docker/pulls/sples1/k4ryuu-cs2?style=for-the-badge&logo=docker&logoColor=white)
![GHCR Pulls](https://img.shields.io/badge/GHCR_Pulls-Unlimited-2088FF?style=for-the-badge&logo=github&logoColor=white)
[![Discord](https://img.shields.io/badge/Discord-Join%20Server-5865F2?style=for-the-badge&logo=discord&logoColor=white)](https://dsc.gg/k4-fanbase)

<div align="center">
  <strong>⭐ Star this repo if you find it useful!</strong>
</div>

<!-- PROJECT LOGO -->
<br />
<div align="center">
  <h1 align="center">KitsuneLab©</h1>
  <h3 align="center">CS2 Egg</h3>
  <a align="center">Production-ready CS2 Pterodactyl Egg with automated updates, intelligent cleanup, auto-restart on game updates, and advanced configuration management.</a>

  <p align="center">
    <br />
    <a href="https://github.com/K4ryuu/CS2-Egg/blob/main/pterodactyl/kitsunelab-cs2-egg.json">Download</a>
    ·
    <a href="https://github.com/K4ryuu/CS2-Egg/issues/new?assignees=KitsuneLab-Development&labels=bug&projects=&template=bug_report.md&title=%5BBUG%5D">Report Bug</a>
    ·
    <a href="https://github.com/K4ryuu/CS2-Egg/issues/new?assignees=KitsuneLab-Development&labels=enhancement&projects=&template=feature_request.md&title=%5BREQ%5D">Request Feature</a>
    ·
    <a href="https://dsc.gg/k4-fanbase">Discord</a>
    ·
    <a href="docs/README.md">Documentation</a>
  </p>
</div>

### Support My Work

I create free, open-source projects for the community. If you'd like to support my work, consider becoming a sponsor!

#### 💖 GitHub Sponsors

Support this project through [GitHub Sponsors](https://github.com/sponsors/K4ryuu) with flexible options:

- **One-time** or **monthly** contributions
- **Custom amount** - choose what works for you
- **Multiple tiers available** - from basic benefits to priority support or private project access

Every contribution helps me dedicate more time to development, support, and creating new features. Thank you! 🙏

<p align="center">
  <a href="https://github.com/sponsors/K4ryuu">
    <img src="https://img.shields.io/badge/sponsor-30363D?style=for-the-badge&logo=GitHub-Sponsors&logoColor=#EA4AAA" alt="GitHub Sponsors" />
  </a>
</p>

⭐ **Or support me for free by starring this repository!**

## System Requirements

**Supported Operating Systems** (for VPK Sync & Centralized Updates)

| Operating System | Minimum Version | Supported Versions         | Status    |
| ---------------- | --------------- | -------------------------- | --------- |
| **Ubuntu**       | 18.04 (Bionic)  | 18.04, 20.04, 22.04, 24.04 | ✅ Tested |
| **Debian**       | 10 (Buster)     | 10, 11, 12, 13             | ✅ Tested |

The centralized update script automatically detects your OS version and installs appropriate dependencies.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Supported Modding Frameworks

**Multi-Framework Support** → Enable multiple frameworks simultaneously with independent boolean toggles. The egg automatically handles framework dependencies, load order, and gameinfo.gi configuration.

- **[MetaMod:Source](https://www.metamodsource.net/downloads.php?branch=dev)** → Core plugin framework (required for CSS)
- **[CounterStrikeSharp](https://github.com/roflmuffin/CounterStrikeSharp)** → C# plugin framework with .NET 8 runtime
- **[SwiftlyS2](https://github.com/swiftly-solution/swiftlys2)** → Standalone C# framework v2
- **[ModSharp](https://github.com/Kxnrl/modsharp-public)** → Standalone C# platform with .NET 9 runtime

Each framework can be enabled/disabled independently via Pterodactyl panel. Auto-updates on server restart while enabled.

## Features

### Automation & Updates

- **Auto-Updaters** → MetaMod, CounterStrikeSharp, SwiftlyS2, ModSharp automatically update on server restart
- **[Centralized Update Script](docs/features/vpk-sync.md)** → Auto-restart on CS2 updates with version tracking (misc/update-cs2-centralized.sh)

### Storage & Performance

- **[VPK Sync](docs/features/vpk-sync.md)** → 80% storage & bandwidth reduction via centralized file sharing
- **Junk Cleaner** → Automatic cleanup (backups, logs, demos)

### Management & Configuration

- **Console Filter** → Block unwanted messages (inspired by [Poggu](https://github.com/Poggicek)'s [CleanerCS2](https://github.com/Source2ZE/CleanerCS2))
- **JSON Configs** → FTP-editable configuration files
- **Colored Logging** → Enhanced console output
- **Custom Parameters** → Safe user-configurable startup options
- **Tokenless Servers** → Run servers without GSLT token requirement

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Documentation

Comprehensive documentation is available:

### Getting Started

- **[Installation Guide](docs/getting-started/installation.md)** → Install and configure the egg
- **[Quick Start](docs/getting-started/quickstart.md)** → Get running quickly
- **[Updating](docs/getting-started/updating.md)** → Update guide

### Features

- **[VPK Sync & Centralized Updates](docs/features/vpk-sync.md)** → 80% storage savings + auto-restart on CS2 updates
- **[Auto-Updaters](docs/features/auto-updaters.md)** → Plugin auto-updates (MetaMod, CSS, SwiftlyS2, ModSharp)
- **[Console Filter](docs/features/console-filter.md)** → Message filtering
- **[Junk Cleaner](docs/features/junk-cleaner.md)** → Automatic cleanup

### Advanced

- **[Building from Source](docs/advanced/building.md)** → Build your own image
- **[Troubleshooting](docs/advanced/troubleshooting.md)** → Common issues

**[View Full Documentation →](docs/README.md)**

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Quick Build

Build your own Docker image using the included build script:

```bash
# Build with custom tag
./build.sh latest

# Build and publish to Docker Hub
./build.sh latest --publish
```

**Note:** Edit `build.sh` to change the registry from `sples1/k4ryuu-cs2` to your own.

**[Full Building Guide →](docs/advanced/building.md)** - Customization, multi-arch builds, CI/CD integration

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Credits

- [CS2 Pterodactyl from 1zc](https://github.com/1zc/CS2-Pterodactyl): The base of the image is maximally based on this image and if you don't want to use the custom scripts, you can use this image instead. Appreciate the work of [1zc](https://github.com/1zc) and give him a star.

## Roadmap

- [ ] Improve bad SFTP client compatibility against stating symbolic links
- [ ] GDC optional connection to automatically detect unreliable gamedatas(?)
- [ ] Optimize and add more automated tests for update scripts

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- LICENSE -->

## License

Distributed under the GPL-3.0 License. See `LICENSE.md` for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>
