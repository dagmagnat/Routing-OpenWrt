# Domain routing OpenWrt 24/25

> За основу взято отсюда: [itdoginfo/domain-routing-openwrt](https://github.com/itdoginfo/domain-routing-openwrt).
>
> Эта версия — не оригинальный проект, а переработанная maintenance-версия под OpenWrt 24.10/25.12 с исправлениями хранения списков, обновления, fw4/nftables и ручного управления доменами/IP.

Главное изменение: доменные и IP-списки больше не живут только в `/tmp`. Генерация перенесена в постоянную директорию `/etc/domain-routing`, а в `/tmp` пишется только временная проверка. Если GitHub или внешний список временно недоступны, последняя валидная конфигурация dnsmasq не затирается.

## Что изменено относительно оригинала

- Списки и состояние перенесены из `/tmp` в persistent `/etc/domain-routing`.
- Генерируемый dnsmasq-файл теперь `/etc/dnsmasq.d/90-domain-routing.conf`.
- Добавлены ручные списки: `/etc/domain-routing/domains/*.lst` и `/etc/domain-routing/ips/*.lst`.
- Добавлены таймауты, lock и fallback на последнюю валидную remote-конфигурацию.
- Обновлена логика под OpenWrt 24.10/25.12, fw4/nftables и dnsmasq `nftset`.
- Добавлена совместимость с `apk` в OpenWrt 25.12 и сохранена совместимость с `opkg` в 24.10/23.05.
- Обновлена поддержка туннелей: WireGuard, AmneziaWG, OpenVPN/tun0, Sing-box/tun0, tun2socks/tun0.

## Что делает проект

- Маршрутизирует выбранные домены через отдельную таблицу `vpn` по fwmark `0x1`.
- Использует `dnsmasq-full` + `nftset` + `fw4/nftables` для OpenWrt 24/25.
- Поддерживает локальные ручные списки доменов и IPv4/CIDR.
- Может дополнительно подтягивать удалённый dnsmasq/nftset-список.
- Поддерживает WireGuard, AmneziaWG, OpenVPN/tun0, Sing-box/tun0 и tun2socks/tun0.
- Для IP-списков использует persistent `loadfile`: `/etc/domain-routing/generated/vpn_ip.lst`.



## Быстрая установка одной командой

Эта команда скачивает bootstrap-скрипт именно из вашего репозитория `dagmagnat/Routing-OpenWrt`, обновляет зависимости роутера, скачивает проект и запускает установщик:

```sh
cd /tmp && (wget -O install.sh https://raw.githubusercontent.com/dagmagnat/Routing-OpenWrt/main/install.sh || curl -fsSL -o install.sh https://raw.githubusercontent.com/dagmagnat/Routing-OpenWrt/main/install.sh) && sh install.sh
```

В этой команде нет скачивания старого оригинального проекта. Оригинальный репозиторий указан только как атрибуция в начале README и в `NOTICE.md`.

## Установка с GitHub dagmagnat

Когда вы выложите проект в свой GitHub, установка должна идти уже из вашего репозитория, а ссылка на оригинальный проект остаётся только как атрибуция “за основу взято отсюда”.

Рекомендуемый вариант через `git`:

```sh
cd /tmp
if command -v apk >/dev/null 2>&1; then
  apk update
  apk add git curl ca-bundle jq
else
  opkg update
  opkg install git git-http curl ca-bundle jq
fi
rm -rf Routing-OpenWrt
git clone --depth=1 https://github.com/dagmagnat/Routing-OpenWrt.git
cd Routing-OpenWrt
sh getdomains-install.sh
```

Вариант без `git`, если места мало:

```sh
cd /tmp
if command -v apk >/dev/null 2>&1; then
  apk update
  apk add curl ca-bundle tar gzip jq
else
  opkg update
  opkg install curl ca-bundle tar gzip jq
fi
rm -rf Routing-OpenWrt-main
curl -L https://github.com/dagmagnat/Routing-OpenWrt/archive/refs/heads/main.tar.gz | tar -xz
cd Routing-OpenWrt-main
sh getdomains-install.sh
```

Если имя репозитория будет другим, замените `Routing-OpenWrt` в командах на фактическое имя.

## Установка shell-скриптом

Скопируйте проект на роутер или скачайте только скрипт, затем выполните:

```sh
sh getdomains-install.sh
```

Скрипт интерактивный. Он спросит:

1. Какой источник доменов использовать: только локальные списки, список Russia inside/outside, Ukraine или свой raw URL.
2. Какой туннель использовать: WireGuard, AmneziaWG, OpenVPN/tun0, Sing-box/tun0, tun2socks/tun0 или пропустить настройку туннеля.

После установки:

```sh
/etc/init.d/getdomains start
/etc/init.d/getdomains status
```


## AmneziaWG: вставка готового конфига

При выборе `AmneziaWG/awg0` установщик теперь предлагает два режима:

1. Вставить весь готовый конфиг `[Interface]` + `[Peer]` сразу в терминал. Это рекомендуемый режим.
2. Ввести поля вручную.

Режим вставки полного конфига поддерживает параметры AmneziaWG 1.x/2.x:

```ini
Jc = ...
Jmin = ...
Jmax = ...
S1 = ...
S2 = ...
S3 = ...
S4 = ...
H1 = ...
H2 = ...
H3 = ...
H4 = ...
I1 = <b ...>
I2 = <b ...>
I3 = <b ...>
I4 = <b ...>
I5 = <b ...>
```

После вставки конфига нужно написать отдельной строкой:

```text
END
```

и нажать Enter.


## Sing-box: вставка ссылки, подписки или JSON

При выборе пункта `Sing-box/tun0` установщик теперь предлагает отдельный выбор:

1. Вставить одну клиентскую ссылку сразу в терминал: `vless://`, `vmess://`, `trojan://` или `ss://`.
2. Вставить URL подписки из 3X-UI или другой панели.
3. Указать локальный файл на роутере: текст со ссылкой, subscription-файл, полный `config.json` sing-box или один outbound JSON.
4. Оставить уже существующий `/etc/sing-box/config.json`.
5. Создать только шаблон.

Основной сценарий для 3X-UI:

```sh
sh getdomains-install.sh
# выбрать Sing-box/tun0
# выбрать пункт 1
# вставить vless://... или другую клиентскую ссылку из панели
```

Конвертер установлен сюда:

```sh
/etc/domain-routing/singbox-convert.sh
```

Его можно запускать отдельно:

```sh
/etc/domain-routing/singbox-convert.sh --link 'vless://...'
/etc/domain-routing/singbox-convert.sh --url 'https://panel.example/sub/...'
/etc/domain-routing/singbox-convert.sh --input /tmp/proxy.txt
/etc/domain-routing/singbox-convert.sh --json /tmp/config.json
```

Результат всегда пишется сюда:

```sh
/etc/sing-box/config.json
```

Старый рабочий конфиг не затирается вслепую: перед заменой создаётся backup, а новый файл проверяется через `sing-box check`, если команда доступна.

Поддерживаемые входные форматы:

- `vless://`, включая VLESS Reality из 3X-UI;
- `vmess://` base64 JSON;
- `trojan://`;
- `ss://` Shadowsocks SIP002;
- plain subscription со строками ссылок;
- base64 subscription;
- полный sing-box `config.json`;
- одиночный sing-box outbound JSON.

## Где менять домены вручную

Все пользовательские домены лежат здесь:

```sh
/etc/domain-routing/domains/
```

Формат простой: один домен на строку.

Пример:

```txt
youtube.com
googlevideo.com
ytimg.com
instagram.com
cdninstagram.com
```

Можно создать отдельные файлы по сервисам:

```sh
vi /etc/domain-routing/domains/10-youtube.lst
vi /etc/domain-routing/domains/20-instagram.lst
vi /etc/domain-routing/domains/30-custom.lst
```

После изменения:

```sh
/etc/init.d/getdomains start
/etc/init.d/dnsmasq restart
```

Обычно достаточно первой команды: она сама перегенерирует файл `/etc/dnsmasq.d/90-domain-routing.conf` и перезапустит dnsmasq, если были изменения.

## Где менять IP вручную

Все пользовательские IPv4/CIDR списки лежат здесь:

```sh
/etc/domain-routing/ips/
```

Например:

```sh
vi /etc/domain-routing/ips/10-telegram.lst
vi /etc/domain-routing/ips/20-whatsapp.lst
```

Формат:

```txt
149.154.160.0/20
91.108.4.0/22
1.2.3.4
```

После изменения:

```sh
/etc/init.d/getdomains start
```

Скрипт соберёт единый файл:

```sh
/etc/domain-routing/generated/vpn_ip.lst
```

и перезапустит firewall, чтобы fw4 загрузил set `vpn_ip`.

## Удалённый обновляемый список

Основной конфиг:

```sh
vi /etc/domain-routing/config
```

Для своего GitHub raw-файла с доменными правилами:

```sh
USE_REMOTE_DOMAINS="1"
REMOTE_DOMAINS_URL="https://raw.githubusercontent.com/USER/REPO/main/domains-nftset.lst"
```

Удалённый доменный файл должен быть в формате dnsmasq/nftset, например:

```txt
nftset=/youtube.com/4#inet#fw4#vpn_domains
nftset=/googlevideo.com/4#inet#fw4#vpn_domains
```

Для удалённых IP-списков:

```sh
REMOTE_IP_URLS="https://raw.githubusercontent.com/USER/REPO/main/telegram.lst https://raw.githubusercontent.com/USER/REPO/main/whatsapp.lst"
```

IP-файлы должны содержать IPv4 или CIDR, по одному на строку.

## Автообновление

Installer добавляет cron:

```cron
17 */8 * * * /etc/init.d/getdomains start >/tmp/getdomains.log 2>&1
```

Это обновляет списки каждые 8 часов. При недоступности удалённого списка старая валидная конфигурация остаётся на месте.


## Повторный запуск после прерывания

Если установка была прервана после скачивания архива, проект обычно находится здесь:

```sh
cd /tmp/Routing-OpenWrt-main
sh getdomains-install.sh
```

Начиная с v6 установщик также создаёт короткую ссылку:

```sh
cd /tmp/Routing-OpenWrt
sh getdomains-install.sh
```

Если AmneziaWG уже установлен, повторный запуск пропустит установку AWG-пакетов и сразу перейдёт к настройке интерфейса `awg0`.

## Проверка

```sh
sh getdomains-check.sh
```

Дополнительно:

```sh
/etc/init.d/getdomains status
nft list set inet fw4 vpn_domains
nft list set inet fw4 vpn_ip
ip rule show
ip route show table vpn
```

## Удаление

Без удаления ваших ручных списков:

```sh
sh getdomains-uninstall.sh
```

С полным удалением `/etc/domain-routing`:

```sh
sh getdomains-uninstall.sh --purge
```

Туннельные интерфейсы и firewall zones намеренно не удаляются, чтобы не сломать существующую VPN-настройку.

## Ansible роль

Роль сохранена, но обновлена под persistent storage:

- dnsmasq `confdir` теперь `/etc/dnsmasq.d`, а не `/tmp/dnsmasq.d`.
- IP loadfile теперь `/etc/domain-routing/generated/*.lst`, а не `/tmp/lst/*.lst`.
- `templates/openwrt-getdomains.j2` больше не зацикливается бесконечно на недоступном GitHub.
- `templates/openwrt-30-vpnroute.j2` использует `ip route replace`, а не `ip route add`, чтобы не падать на повторном запуске.

## Важное по DNS

Маршрутизация по доменам работает только если клиенты используют DNS роутера. Если устройство использует Private DNS/DoH напрямую, dnsmasq не увидит запрос и не добавит IP в `vpn_domains`.



## Версия v9: что изменено для OpenWrt 24/25

Главная проблема доменной маршрутизации на OpenWrt 24/25 обычно не в AmneziaWG/WireGuard, а в DNS и IPv6:

- dnsmasq `nftset` наполняет nft-set только тогда, когда клиент резолвит домен через роутер;
- если телефон/браузер использует Private DNS / DoH, роутер может не увидеть домен;
- если клиент получает IPv6, трафик может уйти по IPv6 мимо IPv4-правил;
- на роутерах 16 MB flash нельзя ставить лишние пакеты вроде `git`, `jq`, `curl` без необходимости.

Поэтому установщик v9 добавляет режим надёжности:

1. перехват обычного DNS TCP/UDP 53 с LAN на локальный dnsmasq;
2. опциональное отключение RA/DHCPv6/NDP на LAN для IPv4-only VPN-конфигов;
3. облегчённый bootstrap без обязательной установки `jq` и `curl`;
4. проверку наличия DNS redirect и IPv6-режима в `getdomains-check.sh`.

После установки на телефоне/ПК желательно переподключить Wi-Fi и отключить Private DNS / Secure DNS / DoH в браузере, если доменная маршрутизация не срабатывает.
