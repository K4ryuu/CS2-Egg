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
  <a align="center">CS2 Pterodactyl Egg with custom scripts such as CSS auto-updater, MetaMod auto-updater, junk cleaner with colored logging.</a>

  <p align="center">
    <br />
    <a href="https://github.com/K4ryuu/CS2-Egg/blob/dev/pterodactyl/kitsunelab-cs2-egg.json">Download</a>
    ·
    <a href="https://github.com/K4ryuu/CS2-Egg/issues/new?assignees=KitsuneLab-Development&labels=bug&projects=&template=bug_report.md&title=%5BBUG%5D">Report Bug</a>
    ·
    <a href="https://github.com/K4ryuu/CS2-Egg/issues/new?assignees=KitsuneLab-Development&labels=enhancement&projects=&template=feature_request.md&title=%5BREQ%5D">Request Feature</a>
  </p>
</div>

## Features

- Console Filter (block unwanted messages from appearing in console)
- CounterStrikeSharp Auto-Updater
- MetaMod Auto-Updater
- Junk Cleaner (Round backups 24hour, logs 3days, css logs 3days, accelerator logs 7days, demo files 7days)
- Colored logs from the main scripts
- Save version and update only if necessary
- Premade variables to support custom parameters safely by user

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## How to install

- Download egg(s) by clicking on the Download button above.
- Import into your Pterodactyl nest of choice. You can do this by navigating to the Admin section of your Pterodactyl panel, "Nests" under "Service Management", and clicking "Import Egg".

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## How to migrate to this egg

- Open the server's admin section which you want to migrate.
- Navigate to "Startup" tab.
- Go to "Service Configuration" secton and check the "Skip Egg Install Script" to prevent it from reinstalling the server.
- Change the egg to use "KitsuneLab CS2 Egg @ K4ryuu"
- In "Docker Image Configuration" it should be sples1/k4ryuu-cs2 selected and below that "sples1/k4ryuu-cs2"
- If you want to use the parameters and you changed manually the startup command, you should copy paste the one from my egg and modify it again.
- Save modifications.

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
