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
PROJECT_LINK="$WORK_DIR/$REPO_NAME"

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
            log 'Обновляю индексы apk'
            apk update || die 'apk update завершился с ошибкой'
            log 'Устанавливаю базовые зависимости'
            apk add ca-bundle tar gzip || die 'Не удалось установить базовые зависимости через apk'
            ;;
        opkg)
            log 'Обновляю индексы opkg'
            opkg update || die 'opkg update завершился с ошибкой'
            log 'Устанавливаю базовые зависимости'
            opkg install ca-bundle tar gzip || die 'Не удалось установить базовые зависимости через opkg'
            ;;
        *)
            die 'Не найден ни apk, ни opkg. Этот установщик предназначен для OpenWrt.'
            ;;
    esac
}

run_local_or_downloaded_installer() {
    if [ -f ./getdomains-install.sh ]; then
        log 'Запускаю локальный getdomains-install.sh'
        sh ./getdomains-install.sh
        return $?
    fi

    mkdir -p "$WORK_DIR" || die "Не удалось создать $WORK_DIR"
    cd "$WORK_DIR" || die "Не удалось перейти в $WORK_DIR"
    rm -rf "$PROJECT_DIR" "$PROJECT_LINK" "/tmp/$REPO_NAME-main" "/tmp/$REPO_NAME-$REPO_BRANCH" "$WORK_DIR/$REPO_NAME.tar.gz"

    log "Скачиваю $REPO_OWNER/$REPO_NAME с GitHub"
    fetch_url "$ARCHIVE_URL" "$WORK_DIR/$REPO_NAME.tar.gz" || die "Не удалось скачать $ARCHIVE_URL"

    log 'Распаковываю архив проекта'
    tar -xzf "$WORK_DIR/$REPO_NAME.tar.gz" || die 'Не удалось распаковать архив проекта'

    [ -d "$PROJECT_DIR" ] || PROJECT_DIR="$(find "$WORK_DIR" -maxdepth 1 -type d -name "$REPO_NAME-*" | head -n 1)"
    [ -n "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/getdomains-install.sh" ] || die 'В скачанном проекте не найден getdomains-install.sh'

    if [ "$PROJECT_DIR" != "$PROJECT_LINK" ]; then
        ln -s "$PROJECT_DIR" "$PROJECT_LINK" 2>/dev/null || true
    fi

    cd "$PROJECT_DIR" || die "Не удалось перейти в $PROJECT_DIR"
    log 'Запускаю getdomains-install.sh'
    log "Если установку прервали, повторно зайдите так: cd $PROJECT_DIR && sh getdomains-install.sh"
    [ -e "$PROJECT_LINK" ] && log "Короткий путь также доступен: cd $PROJECT_LINK"
    sh ./getdomains-install.sh
}

main() {
    [ -r /etc/os-release ] || die '/etc/os-release не найден. Этот скрипт предназначен для OpenWrt.'
    pkg_update_and_deps
    run_local_or_downloaded_installer
}

main "$@"
