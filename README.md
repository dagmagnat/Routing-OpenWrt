# Domain routing для OpenWrt / ImmortalWrt / X-Wrt

> За основу взято отсюда: [itdoginfo/domain-routing-openwrt](https://github.com/itdoginfo/domain-routing-openwrt).
>
> Эта версия — не оригинальный проект, а переработанная maintenance-версия под OpenWrt‑подобные прошивки с fw4/nftables: OpenWrt, ImmortalWrt, X-Wrt и совместимые сборки.

Главное изменение: доменные и IP-списки больше не живут только в `/tmp`. Генерация перенесена в постоянную директорию `/etc/domain-routing`, а в `/tmp` пишется только временная проверка. Если GitHub или внешний список временно недоступны, последняя валидная конфигурация dnsmasq не затирается.

## Что изменено относительно оригинала

- Списки и состояние перенесены из `/tmp` в persistent `/etc/domain-routing`.
- Генерируемый dnsmasq-файл теперь `/etc/dnsmasq.d/90-domain-routing.conf`.
- Добавлены ручные списки: `/etc/domain-routing/domains/*.lst` и `/etc/domain-routing/ips/*.lst`.
- Добавлены таймауты, lock и fallback на последнюю валидную remote-конфигурацию.
- Обновлена логика под OpenWrt‑подобные прошивки с fw4/nftables и dnsmasq `nftset`: OpenWrt, ImmortalWrt, X-Wrt и совместимые сборки.
- Добавлена автоадаптация под `apk` и `opkg`: OpenWrt 25.12+ обычно использует `apk`, многие форки и ветки 23/24 используют `opkg`.
- Обновлена поддержка туннелей: WireGuard, AmneziaWG, OpenVPN/tun0, Sing-box/tun0, tun2socks/tun0.
- Интерактивный установщик стал безопаснее: в меню есть `0` для возврата и `q` для остановки, а ошибки импорта WG/AWG/Sing-box больше не обрывают весь мастер.

## Что делает проект

- Маршрутизирует выбранные домены через отдельную таблицу `vpn` по fwmark `0x1`.
- Использует `dnsmasq-full` + `nftset` + `fw4/nftables` для OpenWrt‑подобных сборок с firewall4.
- Поддерживает локальные ручные списки доменов и IPv4/CIDR.
- Может дополнительно подтягивать удалённый dnsmasq/nftset-список.
- Поддерживает WireGuard, AmneziaWG, OpenVPN/tun0, Sing-box/tun0 и tun2socks/tun0.
- Для IP-списков использует persistent `loadfile`: `/etc/domain-routing/generated/vpn_ip.lst`.


## Совместимость с OpenWrt‑подобными прошивками

Цель проекта — работать не только на официальном OpenWrt, но и на ImmortalWrt, X-Wrt и других сборках, если в них есть UCI, fw4/firewall4, nftables и `dnsmasq` с поддержкой `nftset`. Старый fw3/iptables-профиль этим установщиком не настраивается.

Установщик теперь делает так:

- определяет `apk` или `opkg` автоматически;
- не отсекает X-Wrt/ImmortalWrt только из-за другого имени прошивки;
- при ошибке TLS/сертификатов пробует `curl -k`, `wget --no-check-certificate`, `opkg ... --no-check-certificate`;
- пишет краткую диагностику причины: сертификаты, подписи репозитория, сеть/DNS, несовпадение kmod с ядром, нехватка места;
- если `dnsmasq-full` не установился, не ломает установку целиком, но предупреждает, что доменная маршрутизация заработает только после появления `nftset` support.

По умолчанию fallback без проверки сертификата включён, потому что на старых/кастомных сборках часто нет нормального CA bundle. Для строгого режима запускайте так:

```sh
STRICT_TLS=1 ALLOW_INSECURE_DOWNLOADS=0 sh install.sh
```



## Быстрая установка одной командой

Эта команда скачивает bootstrap-скрипт и обновляет зависимости роутера, скачивает проект и запускает установщик:

```sh
cd /tmp && (wget -O install.sh https://raw.githubusercontent.com/dagmagnat/Routing-OpenWrt/main/install.sh || curl -fsSL -o install.sh https://raw.githubusercontent.com/dagmagnat/Routing-OpenWrt/main/install.sh) && sh install.sh
```

Если на X-Wrt/старой сборке есть ошибка сертификатов при скачивании:

```sh
cd /tmp
wget --no-check-certificate -O install.sh https://raw.githubusercontent.com/dagmagnat/Routing-OpenWrt/main/install.sh
ALLOW_INSECURE_DOWNLOADS=1 sh install.sh
```

То же через `curl`:

```sh
cd /tmp
curl -k -fsSL -o install.sh https://raw.githubusercontent.com/dagmagnat/Routing-OpenWrt/main/install.sh
ALLOW_INSECURE_DOWNLOADS=1 sh install.sh
```

Оффлайн-вариант, если у роутера нет нормального доступа к GitHub: скачайте ZIP на компьютер, распакуйте и передайте папку на роутер через `scp`/WinSCP, затем:

```sh
cd /tmp/Routing-OpenWrt
sh getdomains-install.sh
```

В этой команде нет скачивания старого оригинального проекта. Оригинальный репозиторий указан только как атрибуция в начале README и в `NOTICE.md`.

## Установка с GitHub dagmagnat


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


## Установка shell-скриптом

Скопируйте проект на роутер или скачайте только скрипт, затем выполните:

```sh
sh getdomains-install.sh
```

Скрипт интерактивный. Он спросит:

1. Какой источник доменов использовать: только локальные списки, список Russia inside/outside, Ukraine или свой raw URL.
2. Режим надёжности: перехват DNS и IPv6/IPv4-only.
3. Какой туннель использовать: WireGuard, AmneziaWG, OpenVPN/tun0, Sing-box/tun0, tun2socks/tun0 или пропустить настройку туннеля.

В интерактивных меню можно ввести `0`, чтобы вернуться назад, или `q`, чтобы остановить установку без продолжения. Если ошибка возникает при вставке WG/AWG-конфига или Sing-box-ссылки, мастер не падает целиком, а возвращает вас к соответствующему выбору.

После установки:

```sh
/etc/init.d/getdomains start
/etc/init.d/getdomains status
```


## Если установка пакетов не проходит

Установщик сохраняет последние логи сюда:

```sh
/tmp/domain-routing-pkg-update.log
/tmp/domain-routing-pkg-install-ИМЯ_ПАКЕТА.log
```

Типовые причины:

- `certificate`, `SSL verify`, `self-signed`, `not trusted` — нет CA bundle, неправильная дата или TLS-проблема сборки. Скрипт попробует fallback; после установки лучше поставить `ca-bundle`/`ca-certificates` и синхронизировать время.
- `Signature check failed`, `UNTRUSTED`, `public key` — проблема ключей или feeds не соответствуют прошивке. Лучше обновить прошивку/sysupgrade или исправить репозитории.
- `kernel`, `kmod`, `cannot satisfy dependencies` — пакет ядра не совпадает с текущим kernel. Часто бывает на snapshot/форках после обновления feeds. Нужна та же версия сборки или sysupgrade.
- `No space left` — не хватает flash/overlay. Для маленьких роутеров лучше собрать firmware уже с нужными пакетами.
- `Could not resolve`, `Network unreachable`, `Failed to send request` — проблема WAN/DNS на самом роутере.

Не запускайте массовое `opkg upgrade`/`apk upgrade` на роутере ради этого проекта: на OpenWrt‑подобных системах это часто ломает kmod/ядро. Лучше ставить только нужные пакеты или обновлять firmware целиком через sysupgrade.


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

и нажать Enter. В новых версиях установщик также терпимо обработает `END # комментарий` или `END - комментарий`, но безопаснее писать просто `END` без лишнего текста.

Важно: bundled-списки из папки `domains/` репозитория автоматически копируются в `/etc/domain-routing/domains` и `/etc/domain-routing/ips` при первом запуске. После ручного изменения списков выполните:

```sh
/etc/init.d/getdomains restart
```

Для уже установленной старой версии можно применить быстрый ремонт из полного архива проекта:

```sh
cd /tmp/Routing-OpenWrt-main  # или в папку, куда распакован архив
sh repair-current-install.sh
```

Если вы подключены по SSH и не хотите перезапускать сеть автоматически:

```sh
NO_NETWORK_RESTART=1 sh repair-current-install.sh
```


## Если счётчики RX/TX или nft-set по нулям

Проверьте по шагам:

```sh
uci show network.awg0
uci show network | grep -A20 "amneziawg_awg0"
amneziawg show 2>/dev/null || wg show
ip address show awg0
ip route show table vpn
/etc/init.d/getdomains restart
sh getdomains-check.sh
```

Для AmneziaWG в `/etc/config/network` адрес и `AllowedIPs` должны быть именно list-полями, например:

```text
list addresses '10.28.8.6/32'
list allowed_ips '0.0.0.0/0'
```

Если видите `option addresses` или `option allowed_ips`, перезапустите обновлённый установщик или исправьте интерфейс через LuCI/консоль. Для конфигов AmneziaWG 2.0 с `I1-I5` убедитесь, что установлены AWG 2.0 пакеты и proto-скрипт поддерживает эти параметры; старые пакеты часто поддерживают только `S1/S2/Jc/Jmin/Jmax/H1-H4`.


### DNS из WG/AWG-конфигов

По умолчанию установщик **не импортирует** строку `DNS = ...` из WireGuard/AmneziaWG-конфига в UCI-интерфейс. Это сделано специально: доменная маршрутизация через `dnsmasq`/`nftset` работает стабильно только тогда, когда клиенты резолвят домены через роутер, а подмена DNS на DNS провайдера туннеля часто ломает наполнение nft-set.

Если DNS туннеля действительно нужен, включите это вручную после установки в `/etc/domain-routing/config`:

```sh
USE_TUNNEL_DNS="1"
```

После этого повторно примените настройку интерфейса или задайте DNS вручную через UCI. Обычный рекомендуемый режим — оставить `USE_TUNNEL_DNS="0"`.

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

Установщик также создаёт короткую ссылку:

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

Маршрутизация по доменам работает только если клиенты используют DNS роутера. Если устройство использует Private DNS/DoH напрямую, dnsmasq не увидит запрос и не добавит IP в `vpn_domains`. Поэтому установщик по умолчанию не переносит DNS из WG/AWG-конфига в интерфейс туннеля.



## Что изменено для OpenWrt 24/25?

Главная проблема доменной маршрутизации на OpenWrt 24/25 обычно не в AmneziaWG/WireGuard, а в DNS и IPv6:

- dnsmasq `nftset` наполняет nft-set только тогда, когда клиент резолвит домен через роутер;
- если телефон/браузер использует Private DNS / DoH, роутер может не увидеть домен;
- если клиент получает IPv6, трафик может уйти по IPv6 мимо IPv4-правил;
- на роутерах 16 MB flash нельзя ставить лишние пакеты вроде `git`, `jq`, `curl` без необходимости.

Поэтому установщик добавляет режим надёжности:

1. перехват обычного DNS TCP/UDP 53 с LAN на локальный dnsmasq;
2. опциональное отключение RA/DHCPv6/NDP на LAN для IPv4-only VPN-конфигов;
3. облегчённый bootstrap без обязательной установки `jq` и `curl`;
4. проверку наличия DNS redirect и IPv6-режима в `getdomains-check.sh`.

После установки на телефоне/ПК желательно переподключить Wi-Fi и отключить Private DNS / Secure DNS / DoH в браузере, если доменная маршрутизация не срабатывает.
