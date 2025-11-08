# Installation Guide

This guide will walk you through installing and configuring the KitsuneLab CS2 Egg for Pterodactyl.

## Prerequisites

- A working Pterodactyl Panel installation
- Admin access to the panel
- Docker support on your nodes

## Installing the Egg

### Step 1: Download the Egg

Choose the version you want to install:

- **Stable (Recommended)**: [Download from main branch](https://raw.githubusercontent.com/K4ryuu/CS2-Egg/main/pterodactyl/kitsunelab-cs2-egg.json)
- **Beta**: [Download from beta branch](https://raw.githubusercontent.com/K4ryuu/CS2-Egg/beta/pterodactyl/kitsunelab-cs2-egg.json)
- **Development**: [Download from dev branch](https://raw.githubusercontent.com/K4ryuu/CS2-Egg/dev/pterodactyl/kitsunelab-cs2-egg.json)

### Step 2: Import the Egg

1. Log into your Pterodactyl Panel as an **administrator**
2. Navigate to **Admin** → **Nests** (under Service Management)
3. Select the nest where you want to add the egg (or create a new one)
4. Click **Import Egg**
5. Upload the downloaded JSON file
6. Click **Import**

## Applying to an Existing Server

If you have an existing CS2 server and want to switch to this egg:

### ⚠️ Important: Backup First!

Always backup your server files before changing eggs.

### Steps

1. Go to **Admin** → **Servers**
2. Select your server
3. Navigate to the **Startup** tab
4. Change the **Nest** to the one containing the KitsuneLab egg
5. Change the **Egg** to `KitsuneLab CS2 Egg @ K4ryuu`
6. **Check** the box for **Skip Egg Install Script** (important to preserve your files!)
7. Select the **Docker Image**:
   - `docker.io/sples1/k4ryuu-cs2:latest` (Stable)
   - `docker.io/sples1/k4ryuu-cs2:beta` (Beta)
   - `docker.io/sples1/k4ryuu-cs2:dev` (Development)
8. Click **Save Modifications**
9. Restart your server

## Creating a New Server

1. Navigate to **Admin** → **Servers**
2. Click **Create New**
3. Fill in the basic server details (name, owner, etc.)
4. Scroll down to **Nest Configuration**
5. Select the nest containing the KitsuneLab egg
6. Select `KitsuneLab CS2 Egg @ K4ryuu` as the egg
7. Choose your **Docker Image**:
   - `docker.io/sples1/k4ryuu-cs2:latest` (Recommended)
   - `docker.io/sples1/k4ryuu-cs2:beta`
   - `docker.io/sples1/k4ryuu-cs2:dev`
8. Configure allocation (ports)
9. Set resource limits (CPU, RAM, Disk)
10. Click **Create Server**

## First Startup

When you start your server for the first time:

1. The Docker container will download and install SteamCMD
2. CS2 server files will be downloaded (~30GB)
3. This process may take 10-30 minutes depending on your connection
4. You can watch the progress in the console

## Next Steps

- [Configure Environment Variables](../configuration/environment-variables.md)
- [Setup Auto-Restart Feature](../features/auto-restart.md)
- [Enable Auto-Updaters](../features/auto-updaters.md)
- [Configure Console Filter](../features/console-filter.md)

## Troubleshooting

If you encounter issues during installation:

- Check the [Troubleshooting Guide](../advanced/troubleshooting.md)
- Ensure your node has enough disk space (40GB+ recommended)
- Verify Docker is working properly on your node
- Check the console for error messages

## Support

Need help?

- [Report an Issue](https://github.com/K4ryuu/CS2-Egg/issues)
- [GitHub Discussions](https://github.com/K4ryuu/CS2-Egg/discussions)
