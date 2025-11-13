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

emoji() { [[ -n "${NO_EMOJI:-}" ]] && echo "" || echo "$1"; }

log_info()    { echo -e "$(emoji 🔷) ${BOLD}${CYAN}INFO${RESET}  $*"; }
log_ok()      { echo -e "$(emoji ✅) ${BOLD}${GREEN}DONE${RESET}  $*"; }
log_warn()    { echo -e "$(emoji ⚠️) ${BOLD}${YELLOW}WARN${RESET}  $*"; }
log_error()   { echo -e "$(emoji ❌) ${BOLD}${RED}ERROR${RESET} $*"; }
section()     { echo -e "\n${BOLD}${MAGENTA}==>${RESET} ${BOLD}$*${RESET}\n"; }
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
    echo -e "    -P, --publish       Push the image to registry after successful build"
    echo -e "    -h, --help          Show this help and exit"
    echo -e ""
    echo -e "${BOLD}Examples:${RESET}"
    echo -e "    ./build.sh                    # build :dev"
    echo -e "    ./build.sh release            # build :release"
    echo -e "    ./build.sh -t 1.2.3 -P        # build :1.2.3 and push"
}

# ---------------------------------------------
# Parse arguments
# ---------------------------------------------
TAG="dev"
PUBLISH=false

POSITIONAL_TAG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage; exit 0 ;;
        -t|--tag)
            [[ $# -lt 2 ]] && { log_error "Missing value for $1"; exit 1; }
            TAG="$2"; shift 2 ;;
        -P|--publish)
            PUBLISH=true; shift ;;
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

IMAGE_NAME="sples1/k4ryuu-cs2"
FULL_IMAGE="${IMAGE_NAME}:${TAG}"

headline "KitsuneLab CS2 Docker Image Builder" "Image: ${BOLD}${FULL_IMAGE}${RESET}"

# ---------------------------------------------
# Pre-flight checks
# ---------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
    log_error "Docker is not installed or not in PATH"
    exit 1
fi

# ---------------------------------------------
# Build
# ---------------------------------------------
section "Building Docker image"
pushd "$(dirname "$0")/docker" >/dev/null

log_info "Dockerfile: ${BOLD}KitsuneLab-Dockerfile${RESET}"
log_info "Tag:        ${BOLD}${TAG}${RESET}"

# Check if image with this tag already exists (will become dangling after rebuild)
OLD_IMAGE_ID=$(docker images -q "${FULL_IMAGE}" 2>/dev/null || echo "")
if [[ -n "$OLD_IMAGE_ID" ]]; then
    log_info "Existing image found: ${OLD_IMAGE_ID:0:12}"
fi

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

run_with_spinner "Building image" docker build -f KitsuneLab-Dockerfile -t "${FULL_IMAGE}" .
if [[ -f "$BUILD_LAST_LOG" ]]; then
    size=$(docker image inspect "$FULL_IMAGE" -f '{{.Size}}' 2>/dev/null || echo 0)
    if [[ "$size" =~ ^[0-9]+$ ]] && [ "$size" -gt 0 ]; then
        human_size=$(awk -v s="$size" 'BEGIN{u[1]="B";u[2]="KB";u[3]="MB";u[4]="GB";u[5]="TB";i=1;while(s>1024&&i<5){s/=1024;i++}printf("%.2f %s",s,u[i])}')
        log_info "Image size: ${human_size}"
    fi
fi

# Clean up old image that was replaced
if [[ -n "$OLD_IMAGE_ID" ]]; then
    # Check if the old image became dangling (no tag anymore)
    if docker images -f "dangling=true" -q | grep -q "$OLD_IMAGE_ID"; then
        log_info "Cleaning up replaced image ${OLD_IMAGE_ID:0:12}..."
        docker rmi "$OLD_IMAGE_ID" >/dev/null 2>&1 || true
        log_ok "Removed old image"
    fi
fi

popd >/dev/null

# ---------------------------------------------
# Publish (optional)
# ---------------------------------------------
if [[ "$PUBLISH" == true ]]; then
    section "Publishing image"
    run_with_spinner "Pushing image" docker push "${FULL_IMAGE}"
else
    section "Next steps"
    echo -e "To push to Docker Hub, run:\n  ${BOLD}docker push ${FULL_IMAGE}${RESET}"
fi

exit 0
