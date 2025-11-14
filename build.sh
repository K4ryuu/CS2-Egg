#!/bin/bash
# KitsuneLab CS2 Docker Image Builder

set -euo pipefail

# ---------------------------------------------
# Styling / Colors (auto-disabled for non-TTY)
# ---------------------------------------------
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    BOLD="\033[1m"; DIM="\033[2m"; UNDER="\033[4m"
    RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[34m"; MAGENTA="\033[35m"; CYAN="\033[36m"; GRAY="\033[90m"
    RESET="\033[0m"
else
    BOLD=""; DIM=""; UNDER=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""; GRAY=""; RESET=""
fi

log_info()    { echo -e "ℹ ${BOLD}${CYAN}INFO${RESET}  $*" >&2; }
log_ok()      { echo -e "✓ ${BOLD}${GREEN}DONE${RESET}  $*" >&2; }
log_warn()    { echo -e "⚠ ${BOLD}${YELLOW}WARN${RESET}  $*" >&2; }
log_error()   { echo -e "✗ ${BOLD}${RED}ERROR${RESET} $*" >&2; }
section()     { echo -e "\n${BOLD}${MAGENTA}==>${RESET} ${BOLD}$*${RESET}\n" >&2; }
headline()    {
    local title="$1"; shift || true
    echo -e "${BOLD}${BLUE}──────────────────────────────────────────────────────${RESET}"
    echo -e "${BOLD}${BLUE} ${title}${RESET}"
    echo -e "${BOLD}${BLUE}──────────────────────────────────────────────────────${RESET}"
    [[ $# -gt 0 ]] && echo -e "$*\n"
}

usage() {
    echo -e "${BOLD}KitsuneLab CS2 Docker Image Builder${RESET}"
    echo -e ""
    echo -e "${BOLD}Usage:${RESET}"
    echo -e "    ./build.sh [TAG] [options]"
    echo -e ""
    echo -e "${BOLD}Positional:${RESET}"
    echo -e "    TAG                 Docker tag to use (default: dev)"
    echo -e ""
    echo -e "${BOLD}Options:${RESET}"
    echo -e "    -t, --tag TAG       Explicitly set the tag (overrides positional)"
    echo -e "    -d, --dockerhub     Push the image to Docker Hub after successful build"
    echo -e "    -g, --ghcr          Push the image to GitHub Container Registry (ghcr.io)"
    echo -e "    -a, --all           Push the image to both Docker Hub and GHCR"
    echo -e "    -h, --help          Show this help and exit"
    echo -e ""
    echo -e "${BOLD}Examples:${RESET}"
    echo -e "    ./build.sh                    # build :dev"
    echo -e "    ./build.sh release            # build :release"
    echo -e "    ./build.sh -t 1.2.3 -d        # build :1.2.3 and push to Docker Hub"
    echo -e "    ./build.sh -t 1.2.3 -g        # build :1.2.3 and push to GHCR"
    echo -e "    ./build.sh -t 1.2.3 -a        # build :1.2.3 and push to both registries"
}

# ---------------------------------------------
# Parse arguments
# ---------------------------------------------
TAG="dev"
PUBLISH_DOCKERHUB=false
PUBLISH_GHCR=false

POSITIONAL_TAG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage; exit 0 ;;
        -t|--tag)
            [[ $# -lt 2 ]] && { log_error "Missing value for $1"; exit 1; }
            TAG="$2"; shift 2 ;;
        -d|--dockerhub)
            PUBLISH_DOCKERHUB=true; shift ;;
        -g|--ghcr)
            PUBLISH_GHCR=true; shift ;;
        -a|--all)
            PUBLISH_DOCKERHUB=true
            PUBLISH_GHCR=true
            shift ;;
        --)
            shift; break ;;
        -*)
            log_error "Unknown option: $1"; echo; usage; exit 1 ;;
        *)
            # First non-flag arg treated as positional TAG
            if [[ -z "$POSITIONAL_TAG" ]]; then
                POSITIONAL_TAG="$1"
            else
                log_warn "Ignoring extra positional argument: $1"
            fi
            shift ;;
    esac
done

if [[ -n "$POSITIONAL_TAG" ]]; then
    TAG="$POSITIONAL_TAG"
fi

# Docker Hub configuration
DOCKERHUB_IMAGE="sples1/k4ryuu-cs2"
DOCKERHUB_FULL="${DOCKERHUB_IMAGE}:${TAG}"

# GitHub Container Registry configuration
# Note: GHCR requires lowercase repository names
GITHUB_REPO="k4ryuu/cs2-egg"
GHCR_IMAGE="ghcr.io/${GITHUB_REPO}"
GHCR_FULL="${GHCR_IMAGE}:${TAG}"

# Primary build target (Docker Hub image)
FULL_IMAGE="${DOCKERHUB_FULL}"

headline "KitsuneLab CS2 Docker Image Builder" "Image: ${BOLD}${FULL_IMAGE}${RESET}"

# ---------------------------------------------
# Pre-flight checks
# ---------------------------------------------
section "Pre-flight checks"

if ! command -v docker >/dev/null 2>&1; then
    log_error "Docker is not installed or not in PATH"
    exit 1
fi
log_ok "Docker is available"

# Validate all shell scripts before building
log_info "Validating shell scripts..."
SCRIPT_DIR="$(dirname "$0")/docker"
VALIDATION_FAILED=false

# Find all .sh files in docker directory
while IFS= read -r script; do
    script_name="${script#$SCRIPT_DIR/}"

    # Check bash syntax
    if ! bash -n "$script" 2>/dev/null; then
        log_error "Syntax error in ${script_name}"
        bash -n "$script" 2>&1 | sed 's/^/  /' >&2
        VALIDATION_FAILED=true
        continue
    fi

    # Check if sourced files exist
    while IFS= read -r source_line; do
        # Extract path from 'source /path/to/file.sh' or '. /path/to/file.sh'
        source_path=$(echo "$source_line" | sed -E 's/^[[:space:]]*(source|\.)//;s/[[:space:]]+//' | tr -d '"' | tr -d "'")

        # Skip variables and non-absolute paths
        if [[ "$source_path" =~ ^/ ]]; then
            # Check if file will exist in Docker container
            # /utils/* maps to docker/utils/*
            # /scripts/* maps to docker/scripts/*
            local_path=""
            if [[ "$source_path" =~ ^/utils/ ]]; then
                local_path="$SCRIPT_DIR${source_path}"
            elif [[ "$source_path" =~ ^/scripts/ ]]; then
                local_path="$SCRIPT_DIR${source_path}"
            fi

            if [[ -n "$local_path" ]] && [[ ! -f "$local_path" ]]; then
                log_error "Missing source file in ${script_name}: ${source_path}"
                VALIDATION_FAILED=true
            fi
        fi
    done < <(grep -E '^\s*(source|\.)' "$script" 2>/dev/null || true)

done < <(find "$SCRIPT_DIR" -type f -name "*.sh")

if [[ "$VALIDATION_FAILED" == true ]]; then
    log_error "Shell script validation failed - fix errors before building"
    exit 1
fi

log_ok "All shell scripts validated successfully"

# ---------------------------------------------
# Build
# ---------------------------------------------
section "Building Docker image"
pushd "$(dirname "$0")/docker" >/dev/null

# Check if image with this tag already exists (will become dangling after rebuild)
OLD_IMAGE_ID=$(docker images -q "${FULL_IMAGE}" 2>/dev/null || echo "")

run_with_spinner() {
    local label="$1"; shift
    local cmd=("$@")
    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    local start_ts=$(date +%s)
    local log_file="/tmp/build.$$.$RANDOM.log"
    "${cmd[@]}" >"$log_file" 2>&1 &
    local pid=$!
    printf "${BOLD}${MAGENTA}%s${RESET}\n" "$label"
    while kill -0 $pid 2>/dev/null; do
        printf "\r${CYAN}%s${RESET} ${DIM}%s${RESET}" "${spin[$i]}" "$label"
        i=$(((i+1)%${#spin[@]}))
        sleep 0.12
    done
    wait $pid
    local ec=$?
    local end_ts=$(date +%s)
    local dur=$((end_ts-start_ts))
    printf "\r" # clear spinner line
    if [ $ec -eq 0 ]; then
        log_ok "${label} finished in ${dur}s"
    else
        log_error "${label} failed after ${dur}s (exit $ec)"
        echo "${BOLD}Last 40 lines:${RESET}" >&2
        tail -n 40 "$log_file" >&2 || true
        exit $ec
    fi
    BUILD_LAST_LOG="$log_file"
}

run_with_spinner "Building ${FULL_IMAGE}" docker build -f KitsuneLab-Dockerfile -t "${FULL_IMAGE}" .
if [[ -f "$BUILD_LAST_LOG" ]]; then
    size=$(docker image inspect "$FULL_IMAGE" -f '{{.Size}}' 2>/dev/null || echo 0)
    if [[ "$size" =~ ^[0-9]+$ ]] && [ "$size" -gt 0 ]; then
        human_size=$(awk -v s="$size" 'BEGIN{u[1]="B";u[2]="KB";u[3]="MB";u[4]="GB";u[5]="TB";i=1;while(s>1024&&i<5){s/=1024;i++}printf("%.2f %s",s,u[i])}')
        log_ok "Built ${BOLD}${FULL_IMAGE}${RESET} (${human_size})"
    fi
fi

# Clean up old image that was replaced (silently)
if [[ -n "$OLD_IMAGE_ID" ]]; then
    if docker images -f "dangling=true" -q | grep -q "$OLD_IMAGE_ID"; then
        docker rmi "$OLD_IMAGE_ID" >/dev/null 2>&1 || true
    fi
fi

popd >/dev/null

# ---------------------------------------------
# GHCR Login (if needed)
# ---------------------------------------------
ghcr_login() {
    log_info "Logging in to GitHub Container Registry..."

    # Check for GITHUB_TOKEN environment variable
    if [[ -n "${GITHUB_TOKEN:-}" ]] && [[ -n "${GITHUB_USER:-}" ]]; then
        log_info "Using GITHUB_TOKEN from environment"
        echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_USER" --password-stdin >/dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            log_ok "Logged in to ghcr.io"
            return 0
        else
            log_error "Failed to login with GITHUB_TOKEN"
            return 1
        fi
    fi

    # Interactive login fallback
    log_warn "GITHUB_TOKEN not found in environment"
    log_info "You need a GitHub Personal Access Token with 'packages:write' scope"
    log_info "Create one at: https://github.com/settings/tokens/new?scopes=write:packages"
    echo ""

    read -p "GitHub username: " gh_user
    read -sp "GitHub token: " gh_token
    echo ""

    echo "$gh_token" | docker login ghcr.io -u "$gh_user" --password-stdin >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        log_ok "Logged in to ghcr.io"
        return 0
    else
        log_error "Failed to login to ghcr.io"
        return 1
    fi
}

# ---------------------------------------------
# Publish (optional)
# ---------------------------------------------
if [[ "$PUBLISH_DOCKERHUB" == true ]] || [[ "$PUBLISH_GHCR" == true ]]; then
    section "Publishing image"

    # Tag for GHCR if needed (silently)
    if [[ "$PUBLISH_GHCR" == true ]]; then
        docker tag "${DOCKERHUB_FULL}" "${GHCR_FULL}"
    fi

    # Authenticate to GHCR if needed (before any pushing)
    GHCR_NEW_LOGIN=false
    if [[ "$PUBLISH_GHCR" == true ]]; then
        # Check if credentials are already saved in ~/.docker/config.json
        if [[ -f "${HOME}/.docker/config.json" ]] && grep -q "ghcr.io" "${HOME}/.docker/config.json" 2>/dev/null; then
            # Already logged in, no message needed
            true
        else
            if ! ghcr_login; then
                log_error "Cannot push to GHCR without authentication"
                exit 1
            fi
            GHCR_NEW_LOGIN=true
        fi
    fi

    # Push to Docker Hub
    if [[ "$PUBLISH_DOCKERHUB" == true ]]; then
        run_with_spinner "Pushing to Docker Hub" docker push "${DOCKERHUB_FULL}"
    fi

    # Push to GHCR
    if [[ "$PUBLISH_GHCR" == true ]]; then
        run_with_spinner "Pushing to GHCR" docker push "${GHCR_FULL}"
    fi

    # Show credential storage info only if new login happened
    if [[ "$GHCR_NEW_LOGIN" == true ]]; then
        log_info "Credentials saved to: ${HOME}/.docker/config.json"
    fi
else
    section "Next steps"
    echo -e "To push to Docker Hub, run:\n  ${BOLD}docker push ${DOCKERHUB_FULL}${RESET}"
    echo -e "\nTo push to GitHub Container Registry, run:\n  ${BOLD}docker push ${GHCR_FULL}${RESET}"
    echo -e "\n${DIM}Tip: Use -d for Docker Hub, -g for GHCR, or -a for both${RESET}"
fi

exit 0
