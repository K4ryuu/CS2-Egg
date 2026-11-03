#!/bin/bash
# Self-contained check for the shared updater helpers (docker/utils).
# No network or container needed: curl and the version file are stubbed, so the
# decision logic is driven directly. Run: bash this file.
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMMON="$ROOT/docker/utils/updater_common.sh"
FAILS=0

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    GREEN=$'\e[32m'; RED=$'\e[31m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
else
    GREEN=""; RED=""; BOLD=""; RESET=""
fi

echo ""
echo "${BOLD}Shared updater helpers${RESET}"
echo ""

report() {
    if [ "$2" = "0" ]; then
        echo "${GREEN}PASS${RESET}  $1"
    else
        echo "${RED}FAIL${RESET}  $1"
        FAILS=$((FAILS + 1))
    fi
}

# Loads the helpers with logging silenced and a throwaway version file.
# $VERSIONS holds "Addon=1.2.3" lines the way the real versions.txt does.
setup() {
    log_message() { :; }
    VERSION_FILE="$1"
    source "$COMMON"
    VERSION_FILE="$1"
}

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP  shared updater helpers (jq not installed)"
    echo ""
    exit 0
fi

# --- needs_update ------------------------------------------------------------

(
    set +e
    tmp=$(mktemp -d)
    printf 'CSS=1.0.0\n' > "$tmp/versions.txt"
    setup "$tmp/versions.txt"

    needs_update "CSS" "CSS" "1.0.1" || exit 1        # newer, install
    needs_update "CSS" "CSS" "1.0.0" && exit 1        # same, skip
    needs_update "CSS" "CSS" "0.9.9" && exit 1        # older, no downgrade
    needs_update "CSS" "CSS" "" && exit 1             # unresolved version, skip
    needs_update "New" "New" "1.0.0" || exit 1        # not installed yet, install
    rm -rf "$tmp"
    exit 0
)
report "needs_update installs forward, refuses same and older" "$?"

# 1.0.10 must beat 1.0.9: a lexical compare would call it a downgrade and every
# updater would stop dead at .9 forever
(
    set +e
    tmp=$(mktemp -d)
    printf 'CSS=1.0.9\n' > "$tmp/versions.txt"
    setup "$tmp/versions.txt"

    needs_update "CSS" "CSS" "1.0.10" || exit 1
    rm -rf "$tmp"
    exit 0
)
report "needs_update compares versions numerically, not lexically" "$?"

# --- fetch_release -----------------------------------------------------------

(
    set +e
    tmp=$(mktemp -d)
    setup "$tmp/versions.txt"

    # a release carrying the asset the updater asked for
    curl() { printf '{"tag_name":"v2.1.0","prerelease":false,"assets":[{"name":"pack-linux.zip","browser_download_url":"https://example.invalid/pack-linux.zip"}]}\n%s' "200"; }
    out=$(fetch_release "Test" "owner/repo" "linux\.zip$") || exit 1
    [ "$(echo "$out" | jq -r '.version')" = "v2.1.0" ] || exit 1
    [ "$(echo "$out" | jq -r '.asset_url')" = "https://example.invalid/pack-linux.zip" ] || exit 1

    # asset pattern matching nothing: still valid JSON, empty url for the caller
    out=$(fetch_release "Test" "owner/repo" "nothing-matches$") || exit 1
    [ -z "$(echo "$out" | jq -r '.asset_url')" ] || exit 1

    rm -rf "$tmp"
    exit 0
)
report "fetch_release parses the release and the requested asset" "$?"

# A prerelease feed can interleave the stable MetaMod 1.12 line with the CS2
# 2.x line. A release pattern must select the newest matching non-draft release
# by timestamp before the asset is selected, independent of API array order.
(
    set +e
    tmp=$(mktemp -d)
    setup "$tmp/versions.txt"

    mixed='[
      {"tag_name":"1.12.0.1229","draft":false,"published_at":"2026-11-01T16:41:47Z","created_at":"2026-11-01T16:37:24Z","assets":[{"name":"mmsource-1.12.0-git1229-linux.tar.gz","browser_download_url":"https://example.invalid/1.12"}]},
      {"tag_name":"2.0.0.1482","draft":false,"published_at":"2026-10-18T19:35:57Z","created_at":"2026-10-18T19:30:18Z","assets":[{"name":"mmsource-2.0.0-git1482-linux.tar.gz","browser_download_url":"https://example.invalid/1482"}]},
      {"tag_name":"2.0.0.1483","draft":false,"published_at":"2026-10-18T20:27:32Z","created_at":"2026-10-18T20:21:35Z","assets":[{"name":"mmsource-2.0.0-git1483-linux.tar.gz","browser_download_url":"https://example.invalid/1483"}]},
      {"tag_name":"2.0.0.9999","draft":true,"published_at":"2026-12-01T00:00:00Z","created_at":"2026-12-01T00:00:00Z","assets":[{"name":"mmsource-2.0.0-git9999-linux.tar.gz","browser_download_url":"https://example.invalid/draft"}]}
    ]'
    curl() { echo "$*" > "$tmp/requested"; printf '%s\n%s' "$mixed" "200"; }

    out=$(PRERELEASE=1 fetch_release "MetaMod" "owner/repo" \
        '^mmsource-2\.[0-9]+\.[0-9]+-git[0-9]+-linux\.tar\.gz$' '^2\.') || exit 1
    [ "$(echo "$out" | jq -r '.version')" = "2.0.0.1483" ] || exit 1
    [ "$(echo "$out" | jq -r '.asset_url')" = "https://example.invalid/1483" ] || exit 1
    # the feed must be asked for 100 releases, not the default 30
    grep -q "/releases?per_page=100" "$tmp/requested" || exit 1

    # Reordering the feed cannot change a timestamp-selected result.
    mixed=$(echo "$mixed" | jq 'reverse')
    out=$(PRERELEASE=1 fetch_release "MetaMod" "owner/repo" \
        '^mmsource-2\.[0-9]+\.[0-9]+-git[0-9]+-linux\.tar\.gz$' '^2\.') || exit 1
    [ "$(echo "$out" | jq -r '.version')" = "2.0.0.1483" ] || exit 1

    # published_at can be null; created_at is the required fallback.
    mixed='[
      {"tag_name":"2.0.0.1483","draft":false,"published_at":null,"created_at":"2026-10-18T20:21:35Z","assets":[]},
      {"tag_name":"2.0.0.1484","draft":false,"published_at":null,"created_at":"2026-10-19T20:21:35Z","assets":[]}
    ]'
    out=$(PRERELEASE=1 github_release_json "owner/repo" '^2\.') || exit 1
    [ "$(echo "$out" | jq -r '.tag_name')" = "2.0.0.1484" ] || exit 1

    rm -rf "$tmp"
    exit 0
)
report "release pattern selects the newest non-draft match by timestamp" "$?"

# A missing release family must not fall back to another tag, and a matching
# release without the requested asset must stay empty for the caller to reject.
(
    set +e
    tmp=$(mktemp -d)
    setup "$tmp/versions.txt"

    response_json='[{"tag_name":"1.12.0.1229","draft":false,"published_at":"2026-11-01T16:41:47Z","assets":[{"name":"mmsource-1.12.0-git1229-linux.tar.gz","browser_download_url":"https://example.invalid/1.12"}]}]'
    curl() { printf '%s\n%s' "$response_json" "200"; }
    PRERELEASE=1 fetch_release "MetaMod" "owner/repo" 'linux\.tar\.gz$' '^2\.' >/dev/null 2>&1 && exit 1

    response_json='[{"tag_name":"2.0.0.1483","draft":false,"published_at":"2026-10-18T20:27:32Z","assets":[{"name":"mmsource-2.0.0-git1483-windows.zip","browser_download_url":"https://example.invalid/windows"}]}]'
    out=$(PRERELEASE=1 fetch_release "MetaMod" "owner/repo" \
        '^mmsource-2\.[0-9]+\.[0-9]+-git[0-9]+-linux\.tar\.gz$' '^2\.') || exit 1
    [ -z "$(echo "$out" | jq -r '.asset_url')" ] || exit 1

    rm -rf "$tmp"
    exit 0
)
report "release filtering fails closed without a 2.x release or Linux asset" "$?"

# With no release pattern, preserve the existing array-element-zero behaviour.
(
    set +e
    tmp=$(mktemp -d)
    setup "$tmp/versions.txt"

    response_json='[
      {"tag_name":"1.12.0.1229","draft":false,"assets":[{"name":"first-linux.tar.gz","browser_download_url":"https://example.invalid/first"}]},
      {"tag_name":"2.0.0.1483","draft":false,"assets":[{"name":"second-linux.tar.gz","browser_download_url":"https://example.invalid/second"}]}
    ]'
    curl() { printf '%s\n%s' "$response_json" "200"; }
    out=$(PRERELEASE=1 fetch_release "Default" "owner/repo" 'linux\.tar\.gz$') || exit 1
    [ "$(echo "$out" | jq -r '.version')" = "1.12.0.1229" ] || exit 1

    rm -rf "$tmp"
    exit 0
)
report "fetch_release without a release pattern keeps existing behaviour" "$?"

(
    set +e
    tmp=$(mktemp -d)
    setup "$tmp/versions.txt"

    # Bodies here are perfectly parseable on purpose: the status code alone has
    # to reject them. A malformed body would fail further down anyway and the
    # test would pass with the status checks ripped out.
    good='{"tag_name":"v1.0.0","prerelease":false,"assets":[{"name":"a-linux.zip","browser_download_url":"https://example.invalid/a"}]}'

    curl() { printf '%s\n%s' "$good" "403"; }   # rate limited
    fetch_release "Test" "owner/repo" ".*" >/dev/null 2>&1 && exit 1

    curl() { printf '%s\n%s' "$good" "429"; }   # rate limited, secondary
    fetch_release "Test" "owner/repo" ".*" >/dev/null 2>&1 && exit 1

    curl() { printf '%s\n%s' "$good" "504"; }   # upstream error
    fetch_release "Test" "owner/repo" ".*" >/dev/null 2>&1 && exit 1

    # same body, 200: proves the rejections above came from the status code
    curl() { printf '%s\n%s' "$good" "200"; }
    fetch_release "Test" "owner/repo" ".*" >/dev/null 2>&1 || exit 1

    rm -rf "$tmp"
    exit 0
)
report "fetch_release fails on a rate limit or an HTTP error" "$?"

# --- github_release_json -----------------------------------------------------

# the prerelease endpoint answers with an array, /latest with a single object;
# ModSharp reads assets straight off this, so both shapes must come back usable
(
    set +e
    tmp=$(mktemp -d)
    setup "$tmp/versions.txt"

    curl() { printf '[{"tag_name":"v3.0.0","assets":[{"name":"a-linux.zip"},{"name":"a-linux-extensions.zip"}]}]\n%s' "200"; }
    out=$(PRERELEASE=1 github_release_json "owner/repo") || exit 1
    [ "$(echo "$out" | jq -r '.tag_name')" = "v3.0.0" ] || exit 1
    [ "$(echo "$out" | jq -r '.assets | length')" = "2" ] || exit 1

    curl() { printf '{"tag_name":"v3.0.1","assets":[]}\n%s' "200"; }
    out=$(github_release_json "owner/repo") || exit 1
    [ "$(echo "$out" | jq -r '.tag_name')" = "v3.0.1" ] || exit 1

    rm -rf "$tmp"
    exit 0
)
report "github_release_json handles both the array and object shapes" "$?"

echo ""
if [ "$FAILS" -eq 0 ]; then
    echo "${GREEN}All updater helper cases passed${RESET}"
    echo ""
    exit 0
fi
echo "${RED}${FAILS} case(s) failed${RESET}"
echo ""
exit 1
