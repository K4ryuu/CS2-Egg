---
icon: hand-wave
cover: https://gitbookio.github.io/onboarding-template-images/header.png
coverY: 0
layout:
  cover:
    visible: true
    size: full
  title:
    visible: true
  description:
    visible: true
  tableOfContents:
    visible: true
  outline:
    visible: true
  pagination:
    visible: true
---

# Welcome

Welcome to the official documentation for Kitsune-Lab’s CS2-Egg project.

The system includes various features designed to simplify server management. Automation tools ensure that your server and key add-ons are always up-to-date, clear unnecessary files, filter console outputs, and automatically restart the server when a new game version is detected—eliminating the need to manually track game updates.

The CS2-Egg project was initially created for use with the Pterodactyl platform, which is why it includes an importable egg file. However, the system's versatile design ensures compatibility with any Docker-based environment, provided that the appropriate environment variables are configured within the Docker setup. This flexibility allows users to leverage the system's features across various platforms, enhancing ease of management and functionality beyond its original scope.

## Features

* **Automated Restart Scheduling:** Automatically schedule a restart when a new game version is detected.
* **Restart Countdown Notifications:** Display information to players with timed commands during the restart countdown.
* **Colored Logs:** Enhanced readability for main scripts with colored logs.
* **Junk Cleaner:**
  * Round backups: Retain for 24 hours
  * Logs: Retain for 3 days
  * CSS logs: Retain for 3 days
  * Accelerator logs: Retain for 7 days
  * Demo files: Retain for 7 days
* **GameInfo Updater:** Automatically updates GameInfo file to maintain MetaMod reference.
* **Auto-Updater:** Automatically updates CounterStrikeSharp and MetaMod to the latest versions on restart, when necessary.
* **Console Filter:** Blocks your unwanted messages from appearing in the console.
* Premade variables to support custom parameters safely by user
