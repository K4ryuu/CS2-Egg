# Building from Source

This guide explains how to build your own Docker image from the source code.

## Prerequisites

- Docker installed on your system
- Git installed
- Basic command line knowledge

## Quick Build

The repository includes a `build.sh` script that simplifies the Docker image building process.

**Usage Examples:**

```bash
# Build with default 'dev' tag
./build.sh

# Build with custom tag
./build.sh latest

# Build and publish to Docker Hub
./build.sh latest --publish

# Build production version
./build.sh v1.0.0
```

**Customizing for Your Registry:**

Before building, edit the `build.sh` script to use your own Docker Hub username or private registry:

1. Open `build.sh` in a text editor
2. Find the `IMAGE_NAME` variable
3. Change `sples1/k4ryuu-cs2` to your registry (e.g., `yourusername/cs2-server`)
4. Save and run with your desired tag

**What the script does:**

1. Builds the Docker image from the Dockerfile
2. Tags it as `your-registry/image-name:TAG`
3. Optionally pushes to Docker Hub with `--publish` flag
4. Displays helpful next steps for testing

## Manual Build

If you prefer to build manually:

```bash
# Navigate to the docker directory
cd docker

# Build the image
docker build -f KitsuneLab-Dockerfile -t your-registry/your-image:tag .

# Example
docker build -f KitsuneLab-Dockerfile -t myrepo/cs2-server:latest .
```

## Build Arguments

Currently, the Dockerfile doesn't use build arguments, but you can modify it to add them.

## Pushing to Registry

### Docker Hub

```bash
# Login
docker login

# Push
docker push your-registry/your-image:tag
```

### Private Registry

```bash
# Login to your registry
docker login your-registry.com

# Tag for your registry
docker tag your-registry/your-image:tag your-registry.com/your-image:tag

# Push
docker push your-registry.com/your-image:tag
```

## Using Custom Image in Pterodactyl

After building and pushing your image:

**Recommendation:** Use Docker Hub with a **private repository** to protect your customizations.

### Configure the Egg

1. Go to **Admin** → **Nests** → Your Nest → **Eggs**
2. Edit the KitsuneLab CS2 Egg
3. In **Docker Images** section, add your custom image:
   ```json
   "My Custom Image": "your-registry/your-image:tag"
   ```
4. Save changes
5. In your server's **Startup** tab, select your custom image

### For Private Registries

If using a private Docker Hub repository or private registry, you must authenticate on **all Pterodactyl nodes**:

```bash
# SSH into each Pterodactyl node
ssh root@your-node.com

# Login to Docker Hub (or your private registry)
docker login

# Enter your credentials when prompted
```

**Important:** Pterodactyl nodes need registry access to pull private images. Without authentication, container creation will fail with "pull access denied" errors.

## Modifying the Image

### Adding Packages

Edit `docker/KitsuneLab-Dockerfile`:

```dockerfile
ENV         DEBIAN_FRONTEND=noninteractive
RUN         apt update && \
            apt install -y iproute2 jq unzip expect rsync cron curl gawk \
            your-new-package \
            another-package && \
            apt-get clean
```

### Adding Scripts

1. Create your script in `docker/scripts/` or `docker/utils/`
2. Ensure it's copied in the Dockerfile:

```dockerfile
COPY        ./scripts/* /scripts/
COPY        ./utils/* /utils/
```

3. Make it executable:

```dockerfile
RUN         chmod +x /scripts/*.sh && \
            chmod +x /utils/*.sh
```

### Modifying Entrypoint

Edit `docker/entrypoint.sh` to change startup behavior.

## Build Script Details

The `build.sh` script provides a streamlined building experience with multiple options:

**Usage:**
```bash
./build.sh [TAG] [options]
```

**Options:**
- `-t, --tag TAG` - Set the Docker tag (default: `dev`)
- `-P, --publish` - Automatically push to registry after build
- `-h, --help` - Show usage information

**Examples:**
```bash
./build.sh                    # Build with 'dev' tag
./build.sh release            # Build with 'release' tag
./build.sh -t 1.2.3 -P        # Build version 1.2.3 and push
```

### Script Output

The script provides a modern, colorful output with progress indicators:

```
──────────────────────────────────────────────────────
 KitsuneLab CS2 Docker Image Builder
──────────────────────────────────────────────────────
Image: sples1/k4ryuu-cs2:latest


==> Building Docker image

🔷 INFO  Dockerfile: KitsuneLab-Dockerfile
🔷 INFO  Tag:        latest
Building image
⠋ Building image
[✓] DONE  Building image finished in 45s
🔷 INFO  Image size: 1.23 GB


==> Next steps

To push to Docker Hub, run:
  docker push sples1/k4ryuu-cs2:latest
```

**Features:**
- Animated spinner during build
- Build time tracking
- Automatic image size calculation
- Color-coded status messages ([SUCCESS], [ERROR], [WARNING])
- Optional auto-publish with `--publish` flag

## Multi-Architecture Builds

To build for multiple architectures (AMD64, ARM64):

```bash
# Create a builder
docker buildx create --name cs2-builder --use

# Build for multiple platforms
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f docker/KitsuneLab-Dockerfile \
  -t your-registry/your-image:tag \
  --push \
  .
```

## CI/CD Integration

### GitHub Actions Example

Create `.github/workflows/build.yml`:

```yaml
name: Build Docker Image

on:
  push:
    branches: [main, dev, beta]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2

      - name: Login to DockerHub
        uses: docker/login-action@v2
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Build and push
        uses: docker/build-push-action@v4
        with:
          context: ./docker
          file: ./docker/KitsuneLab-Dockerfile
          push: true
          tags: |
            sples1/k4ryuu-cs2:${{ github.ref_name }}
            sples1/k4ryuu-cs2:latest
```

## Troubleshooting Build Issues

### Build Fails on apt install

```bash
# Clear Docker build cache
docker builder prune

# Rebuild without cache
docker build --no-cache -f docker/KitsuneLab-Dockerfile -t your-image:tag .
```

### Permission Denied Errors

```bash
# Ensure build script is executable
chmod +x build.sh

# Ensure scripts are accessible
chmod +x docker/scripts/*.sh
chmod +x docker/utils/*.sh
```

### Large Image Size

Optimize your Dockerfile:

- Combine RUN commands
- Remove unnecessary packages
- Use `.dockerignore` file
- Clean up after installations

## Best Practices

1. **Version your builds** - Use semantic versioning tags
2. **Test before pushing** - Always test locally first
3. **Use multi-stage builds** - If adding compilation steps
4. **Document changes** - Update CHANGELOG for custom builds
5. **Keep base image updated** - Regularly pull SteamRT updates
6. **Minimize layers** - Combine commands where possible

## Contributing Your Changes

If you've made improvements:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

See [Contributing Guide](contributing.md) for details.

## Support

Need help with building?

- [Report an Issue](https://github.com/K4ryuu/CS2-Egg/issues)
- Check existing build-related issues
