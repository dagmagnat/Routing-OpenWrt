#!/bin/sh

# Bootstrap installer for dagmagnat/Routing-OpenWrt.
# It updates OpenWrt package indexes, installs minimal dependencies,
# downloads this repository from GitHub when needed, then starts getdomains-install.sh.

set -u

REPO_OWNER="${REPO_OWNER:-dagmagnat}"
REPO_NAME="${REPO_NAME:-Routing-OpenWrt}"
REPO_BRANCH="${REPO_BRANCH:-main}"
ARCHIVE_URL="${ARCHIVE_URL:-https://github.com/$REPO_OWNER/$REPO_NAME/archive/refs/heads/$REPO_BRANCH.tar.gz}"
WORK_DIR="${WORK_DIR:-/tmp}"
PROJECT_DIR="$WORK_DIR/$REPO_NAME-$REPO_BRANCH"

log() { printf '\033[32;1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33;1m%s\033[0m\n' "$*"; }
err() { printf '\033[31;1m%s\033[0m\n' "$*" >&2; }
die() { err "$*"; exit 1; }

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

fetch_url() {
    url="$1"
    out="$2"
    if cmd_exists curl; then
        curl -4 -fsSL --connect-timeout 10 --max-time 80 --retry 2 -o "$out" "$url"
    elif cmd_exists wget; then
        wget -4 -q -T 80 -O "$out" "$url"
    else
        return 1
    fi
}

pkg_manager() {
    if cmd_exists apk; then
        printf 'apk'
    elif cmd_exists opkg; then
        printf 'opkg'
    else
        printf 'none'
    fi
}

pkg_update_and_deps() {
    pm="$(pkg_manager)"
    case "$pm" in
        apk)
            log 'Updating apk indexes'
            apk update || die 'apk update failed'
            log 'Installing bootstrap dependencies'
            apk add curl ca-bundle tar gzip jq || die 'Failed to install bootstrap dependencies via apk'
            ;;
        opkg)
            log 'Updating opkg indexes'
            opkg update || die 'opkg update failed'
            log 'Installing bootstrap dependencies'
            opkg install curl ca-bundle tar gzip jq || die 'Failed to install bootstrap dependencies via opkg'
            ;;
        *)
            die 'Neither apk nor opkg was found. This installer is intended for OpenWrt.'
            ;;
    esac
}

run_local_or_downloaded_installer() {
    if [ -f ./getdomains-install.sh ]; then
        log 'Running local getdomains-install.sh'
        sh ./getdomains-install.sh
        return $?
    fi

    mkdir -p "$WORK_DIR" || die "Cannot create $WORK_DIR"
    cd "$WORK_DIR" || die "Cannot enter $WORK_DIR"
    rm -rf "$PROJECT_DIR" "/tmp/$REPO_NAME-main" "/tmp/$REPO_NAME-$REPO_BRANCH" "$WORK_DIR/$REPO_NAME.tar.gz"

    log "Downloading $REPO_OWNER/$REPO_NAME from GitHub"
    fetch_url "$ARCHIVE_URL" "$WORK_DIR/$REPO_NAME.tar.gz" || die "Failed to download $ARCHIVE_URL"

    log 'Extracting project archive'
    tar -xzf "$WORK_DIR/$REPO_NAME.tar.gz" || die 'Failed to extract project archive'

    [ -d "$PROJECT_DIR" ] || PROJECT_DIR="$(find "$WORK_DIR" -maxdepth 1 -type d -name "$REPO_NAME-*" | head -n 1)"
    [ -n "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/getdomains-install.sh" ] || die 'getdomains-install.sh was not found in downloaded project'

    cd "$PROJECT_DIR" || die "Cannot enter $PROJECT_DIR"
    log 'Running getdomains-install.sh'
    sh ./getdomains-install.sh
}

main() {
    [ -r /etc/os-release ] || die '/etc/os-release not found. This script is intended for OpenWrt.'
    pkg_update_and_deps
    run_local_or_downloaded_installer
}

main "$@"
