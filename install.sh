#!/bin/sh

# Bootstrap installer for dagmagnat/Routing-OpenWrt.
# It updates OpenWrt package indexes, installs minimal dependencies,
# downloads this repository from GitHub when needed, then starts getdomains-install.sh.

set -u

REPO_OWNER="${REPO_OWNER:-dagmagnat}"
REPO_NAME="${REPO_NAME:-Routing-OpenWrt}"
REPO_BRANCH="${REPO_BRANCH:-main}"
ARCHIVE_URL="${ARCHIVE_URL:-https://github.com/$REPO_OWNER/$REPO_NAME/archive/refs/heads/$REPO_BRANCH.tar.gz}"
# Default is permissive because many OpenWrt forks/old builds have missing or stale CA bundles.
# Set STRICT_TLS=1 or ALLOW_INSECURE_DOWNLOADS=0 to forbid --no-check-certificate / curl -k fallbacks.
ALLOW_INSECURE_DOWNLOADS="${ALLOW_INSECURE_DOWNLOADS:-1}"
STRICT_TLS="${STRICT_TLS:-0}"
WORK_DIR="${WORK_DIR:-/tmp}"
PROJECT_DIR="$WORK_DIR/$REPO_NAME-$REPO_BRANCH"
PROJECT_LINK="$WORK_DIR/$REPO_NAME"

log() { printf '\033[32;1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33;1m%s\033[0m\n' "$*"; }
err() { printf '\033[31;1m%s\033[0m\n' "$*" >&2; }
die() { err "$*"; exit 1; }

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

insecure_download_allowed() {
    [ "${STRICT_TLS:-0}" = '1' ] && return 1
    [ "${ALLOW_INSECURE_DOWNLOADS:-1}" = '1' ]
}

fetch_url() {
    url="$1"
    out="$2"
    rm -f "$out" 2>/dev/null || true

    if cmd_exists curl; then
        curl -4 -fsSL --connect-timeout 10 --max-time 80 --retry 2 -o "$out" "$url" && return 0
        if insecure_download_allowed; then
            warn "Обычное HTTPS-скачивание через curl не удалось. Пробую curl -k для прошивок без корректных CA-сертификатов."
            curl -4 -k -fsSL --connect-timeout 10 --max-time 80 --retry 2 -o "$out" "$url" && return 0
        fi
    fi

    if cmd_exists wget; then
        wget -4 -q -T 80 -O "$out" "$url" && return 0
        if insecure_download_allowed; then
            warn "Обычное HTTPS-скачивание через wget не удалось. Пробую --no-check-certificate."
            wget --no-check-certificate -4 -q -T 80 -O "$out" "$url" && return 0
        fi
    fi

    return 1
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

diagnose_pkg_log() {
    log_file="$1"
    [ -s "$log_file" ] || return 0
    if grep -Eiq 'certificate|SSL|TLS|not trusted|self-signed|verify' "$log_file"; then
        warn 'Похоже на проблему TLS/CA-сертификатов. Скрипт пробует insecure fallback; позже лучше установить ca-bundle/ca-certificates и проверить дату роутера.'
    fi
    if grep -Eiq 'Signature check failed|UNTRUSTED|BAD signature|public key|key' "$log_file"; then
        warn 'Похоже на проблему подписи/ключей репозитория. Часто это несовпадение прошивки и feeds или устаревший snapshot.'
    fi
    if grep -Eiq 'Failed to send request|Network unreachable|bad address|Could not resolve|Temporary failure|Connection timed out' "$log_file"; then
        warn 'Похоже на проблему сети/DNS до репозитория. Проверьте WAN, DNS и дату/время на роутере.'
    fi
    if grep -Eiq 'kernel|kmod|incompatible|cannot satisfy|unsatisfiable' "$log_file"; then
        warn 'Похоже на несовпадение kmod-пакетов с ядром. Для snapshot/форков обычно нужен свежий sysupgrade той же сборки.'
    fi
    if grep -Eiq 'No space left|not enough space|Cannot allocate' "$log_file"; then
        warn 'Похоже на нехватку места во flash/overlay. Удалите лишние пакеты или используйте сборку с нужными пакетами внутри firmware.'
    fi
}

pkg_update() {
    pm="$(pkg_manager)"
    log_file='/tmp/domain-routing-pkg-update.log'
    case "$pm" in
        apk)
            apk update >"$log_file" 2>&1 && return 0
            diagnose_pkg_log "$log_file"
            if insecure_download_allowed; then
                warn 'Повторяю apk update с --no-check-certificate/--allow-untrusted, если эти ключи поддерживаются сборкой.'
                apk update --no-check-certificate >>"$log_file" 2>&1 && return 0
                apk update --allow-untrusted >>"$log_file" 2>&1 && return 0
            fi
            cat "$log_file" >&2 2>/dev/null || true
            return 1
            ;;
        opkg)
            opkg update >"$log_file" 2>&1 && return 0
            diagnose_pkg_log "$log_file"
            if insecure_download_allowed; then
                warn 'Повторяю opkg update с --no-check-certificate.'
                opkg update --no-check-certificate >>"$log_file" 2>&1 && return 0
                opkg --no-check-certificate update >>"$log_file" 2>&1 && return 0
            fi
            cat "$log_file" >&2 2>/dev/null || true
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

pkg_install_one() {
    package="$1"
    pm="$(pkg_manager)"
    log_file="/tmp/domain-routing-pkg-install-$package.log"
    case "$pm" in
        apk)
            apk add "$package" >"$log_file" 2>&1 && return 0
            diagnose_pkg_log "$log_file"
            if insecure_download_allowed; then
                apk add --no-check-certificate "$package" >>"$log_file" 2>&1 && return 0
                apk add --allow-untrusted "$package" >>"$log_file" 2>&1 && return 0
            fi
            return 1
            ;;
        opkg)
            opkg install "$package" >"$log_file" 2>&1 && return 0
            diagnose_pkg_log "$log_file"
            if insecure_download_allowed; then
                opkg install --no-check-certificate "$package" >>"$log_file" 2>&1 && return 0
                opkg --no-check-certificate install "$package" >>"$log_file" 2>&1 && return 0
            fi
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

pkg_install_any() {
    for package in "$@"; do
        [ -n "$package" ] || continue
        if pkg_install_one "$package"; then
            log "Установлен пакет: $package"
            return 0
        fi
    done
    return 1
}

pkg_update_and_deps() {
    pm="$(pkg_manager)"
    [ "$pm" != 'none' ] || die 'Не найден ни apk, ни opkg. Этот установщик предназначен для OpenWrt/ImmortalWrt/X-Wrt-подобных прошивок.'

    log "Найден пакетный менеджер: $pm"
    pkg_update || warn 'Индексы пакетов не обновились. Продолжаю: локальная установка/скачивание проекта может всё равно сработать.'

    log 'Проверяю базовые зависимости'
    pkg_install_any ca-bundle ca-certificates || warn 'CA bundle не установлен автоматически. Скачивание будет пробовать fallback без проверки сертификата.'
    pkg_install_any tar || true
    pkg_install_any gzip || true
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

detect_openwrt_like() {
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        log "Прошивка: ${PRETTY_NAME:-${NAME:-OpenWrt-like}} ${VERSION_ID:-}"
        return 0
    fi
    if [ -r /etc/openwrt_release ]; then
        . /etc/openwrt_release
        log "Прошивка: ${DISTRIB_DESCRIPTION:-OpenWrt-like}"
        return 0
    fi
    warn 'Не найден /etc/os-release или /etc/openwrt_release. Продолжаю как на OpenWrt-like системе, если есть opkg/apk.'
    return 0
}

main() {
    detect_openwrt_like
    pkg_update_and_deps
    run_local_or_downloaded_installer
}

main "$@"
