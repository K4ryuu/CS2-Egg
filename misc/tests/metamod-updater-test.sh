#!/bin/bash
# Self-contained MetaMod updater checks. No network or game server required:
# release, download/extract, copy, logging and version stamping are stubbed.
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
UPDATER="$ROOT/docker/scripts/updaters/metamod.sh"
FAILS=0

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    GREEN=$'\e[32m'; RED=$'\e[31m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
else
    GREEN=""; RED=""; BOLD=""; RESET=""
fi

echo ""
echo "${BOLD}MetaMod updater${RESET}"
echo ""

report() {
    if [ "$2" = "0" ]; then
        echo "${GREEN}PASS${RESET}  $1"
    else
        echo "${RED}FAIL${RESET}  $1"
        FAILS=$((FAILS + 1))
    fi
}

# Load only the updater function: its container-only absolute helper sources
# are replaced by the stubs each case defines below.
load_updater() {
    source() {
        case "$1" in
            /utils/logging.sh|/utils/updater_common.sh) return 0 ;;
            *) builtin source "$@" ;;
        esac
    }
    source "$UPDATER"
    unset -f source
}

setup_case() {
    local root="$1"
    TEMP_DIR="$root/temps"
    mkdir -p "$root/game/csgo/addons" "$TEMP_DIR"
    log_message() { :; }
    needs_update() { return 0; }
}

# Release discovery failure must stop before download, copy or stamping.
(
    set +e
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    cd "$tmp" || exit 1
    load_updater; setup_case "$tmp"
    called=""
    fetch_release() { return 1; }
    handle_download_and_extract() { called="download"; return 0; }
    cp() { called="copy"; return 0; }
    update_version_file() { called="stamp"; return 0; }
    update_metamod && exit 1
    [ -z "$called" ] || exit 1
)
report "discovery failure stops before download, copy and stamp" "$?"

# A selected release with no Linux asset must also fail before download.
(
    set +e
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    cd "$tmp" || exit 1
    load_updater; setup_case "$tmp"
    called=""
    fetch_release() { printf '%s\n' '{"version":"2.0.0.1483","asset_url":"","asset_name":""}'; }
    handle_download_and_extract() { called="download"; return 0; }
    update_metamod && exit 1
    [ -z "$called" ] || exit 1
)
report "missing Linux asset fails closed" "$?"

# The extracted archive must contain the official CS2 linuxsteamrt64 library.
(
    set +e
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    cd "$tmp" || exit 1
    load_updater; setup_case "$tmp"
    copied=0; stamped=0
    fetch_release() { printf '%s\n' '{"version":"2.0.0.1483","asset_url":"https://example.invalid/mm.tar.gz","asset_name":"mmsource-2.0.0-git1483-linux.tar.gz"}'; }
    handle_download_and_extract() { mkdir -p "$3/addons/metamod/bin/linuxsteamrt64"; }
    cp() { copied=1; return 0; }
    update_version_file() { stamped=1; return 0; }
    update_metamod && exit 1
    [ "$copied" = "0" ] && [ "$stamped" = "0" ] || exit 1
)
report "invalid extracted layout stops before copy and stamp" "$?"

# Copy failure must leave the version unstamped for a retry.
(
    set +e
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    cd "$tmp" || exit 1
    load_updater; setup_case "$tmp"
    stamped=0
    fetch_release() { printf '%s\n' '{"version":"2.0.0.1483","asset_url":"https://example.invalid/mm.tar.gz","asset_name":"mmsource-2.0.0-git1483-linux.tar.gz"}'; }
    handle_download_and_extract() {
        mkdir -p "$3/addons/metamod/bin/linuxsteamrt64"
        printf 'synthetic' > "$3/addons/metamod/bin/linuxsteamrt64/metamod.2.cs2.so"
    }
    cp() { return 1; }
    update_version_file() { stamped=1; return 0; }
    update_metamod && exit 1
    [ "$stamped" = "0" ] || exit 1
)
report "copy failure does not stamp a version" "$?"

# Stamp failure must be visible and cause a retry even after a successful copy.
(
    set +e
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    cd "$tmp" || exit 1
    load_updater; setup_case "$tmp"
    fetch_release() { printf '%s\n' '{"version":"2.0.0.1483","asset_url":"https://example.invalid/mm.tar.gz","asset_name":"mmsource-2.0.0-git1483-linux.tar.gz"}'; }
    handle_download_and_extract() {
        mkdir -p "$3/addons/metamod/bin/linuxsteamrt64"
        printf 'synthetic' > "$3/addons/metamod/bin/linuxsteamrt64/metamod.2.cs2.so"
    }
    update_version_file() { return 1; }
    update_metamod && exit 1
    [ -s "$tmp/game/csgo/addons/metamod/bin/linuxsteamrt64/metamod.2.cs2.so" ] || exit 1
)
report "version stamp failure is reported after a successful copy" "$?"

# Success verifies the strict helper arguments, copies the guarded layout, then
# stamps the extracted git version without changing the global PRERELEASE value.
(
    set +e
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    cd "$tmp" || exit 1
    load_updater; setup_case "$tmp"
    stamped=""; PRERELEASE=0
    fetch_release() {
        [ "${PRERELEASE:-}" = "1" ] || return 1
        [ "$3" = '^mmsource-2\.[0-9]+\.[0-9]+-git[0-9]+-linux\.tar\.gz$' ] || return 1
        [ "$4" = '^2\.' ] || return 1
        printf '%s\n' '{"version":"2.0.0.1483","asset_url":"https://example.invalid/mm.tar.gz","asset_name":"mmsource-2.0.0-git1483-linux.tar.gz"}'
    }
    handle_download_and_extract() {
        mkdir -p "$3/addons/metamod/bin/linuxsteamrt64"
        printf 'synthetic' > "$3/addons/metamod/bin/linuxsteamrt64/metamod.2.cs2.so"
    }
    update_version_file() {
        [ -s "$tmp/game/csgo/addons/metamod/bin/linuxsteamrt64/metamod.2.cs2.so" ] || return 1
        stamped="$1=$2"
    }
    update_metamod || exit 1
    [ "$stamped" = "Metamod=git1483" ] || exit 1
    [ "$PRERELEASE" = "0" ] || exit 1
)
report "valid CS2 layout copies before stamping without leaking PRERELEASE" "$?"

echo ""
if [ "$FAILS" -eq 0 ]; then
    echo "${GREEN}All MetaMod updater cases passed${RESET}"
    echo ""
    exit 0
fi
echo "${RED}${FAILS} case(s) failed${RESET}"
echo ""
exit 1
