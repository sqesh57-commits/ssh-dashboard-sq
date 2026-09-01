# SSH Dashboard

Адаптивный системный dashboard для интерактивных SSH-сессий на Debian.

После подключения по SSH отображает основные параметры сервера в виде компактных информационных блоков.

## Возможности

* 🖥️ System

  * hostname
  * Debian version
  * kernel
  * architecture
  * uptime

* 💻 CPU

  * модель CPU
  * количество ядер
  * загрузка
  * Load Average
  * температура

* 💾 Memory

  * RAM
  * Swap
  * процент использования

* 💿 Disks

  * файловые системы
  * размер
  * занятое пространство
  * процент использования

* 🌐 Network

  * основной интерфейс
  * LAN IP
  * WAN IP
  * доступность Internet
  * latency
  * RX/TX

* 🐳 Docker

  * количество контейнеров
  * состояние контейнеров
  * uptime/status

* 👤 Users

  * вошедшие пользователи
  * SSH-сессии
  * текущий пользователь

* 🔌 Ports

  * listening TCP/UDP ports
  * связанные процессы

* 🛡️ System & Security

  * failed systemd units
  * Fail2Ban
  * неудачные SSH-аутентификации
  * доступные обновления
  * необходимость reboot

## Интерфейс

На широком терминале используется двухколоночная компоновка:

```text
┌────────────── 💻 CPU ──────────────┐  ┌─────────── 💾 MEMORY ────────────┐
│ Cores: 8                           │  │ RAM: 3.1 GB / 15.6 GB            │
│ Temp: 🟢 39°C                      │  │ 🟢 20% ▓▓░░░░░░░░                │
│ Usage: 🟢 7% ░░░░░░░░░░           │  │ Swap: 0 B / 2 GB                 │
│ Load: 0.14 0.12 0.08               │  │ Available: 12.5 GB               │
└────────────────────────────────────┘  └───────────────────────────────────┘

┌────────────── 💾 DISKS ────────────┐  ┌─────────── 🌐 NETWORK ───────────┐
│ 📍 System /                        │  │ Interface: eth0                   │
│ 8.2G/40G 🟢 22% ▓▓░░░░░░░░        │  │ LAN: 192.168.1.131               │
│ 📦 /mnt/data                       │  │ WAN: xxx.xxx.xxx.xxx             │
│ 92G/234G 🟢 42% ▓▓▓▓░░░░░░        │  │ Internet: ✅ 23 ms                │
└────────────────────────────────────┘  └───────────────────────────────────┘
```

На узком терминале блоки автоматически переключаются в одноколоночный режим.

## Требования

Поддерживаются:

* Debian 12
* Debian 13
* x86_64
* ARM
* ARM64
* Raspberry Pi

Базовые зависимости:

* Bash
* curl
* iproute2
* procps
* util-linux
* coreutils
* grep
* gawk
* sed
* bc

Дополнительные возможности:

* `lm-sensors` — получение температуры;
* `smartmontools` — работа с SMART;
* `docker` — мониторинг контейнеров;
* `fail2ban` — отображение состояния Fail2Ban.

Отсутствие необязательных компонентов не препятствует запуску dashboard.

## Установка

Клонировать репозиторий:

```bash
git clone <repository-url>
cd ssh-dashboard
```

Запустить установщик:

```bash
sudo bash install-ssh-dashboard.sh
```

После установки:

```text
/usr/local/bin/ssh-dashboard
/etc/profile.d/ssh-dashboard.sh
```

## Проверка

Запустить dashboard вручную:

```bash
/usr/local/bin/ssh-dashboard
```

После установки также можно открыть новую SSH-сессию:

```bash
ssh user@server
```

Dashboard должен отображаться автоматически.

## Docker

Для отображения Docker-контейнеров пользователь должен иметь доступ к Docker daemon.

Например:

```bash
sudo usermod -aG docker "$USER"
```

После изменения группы необходимо выполнить новый вход в систему.

Проверить:

```bash
docker ps
```

Dashboard не использует `sudo docker`, поэтому отсутствие доступа к Docker не блокирует SSH-вход.

## Цветовые статусы

Используется следующая индикация:

```text
🟢 Normal
🟡 Warning
🔴 Critical
```

Пороговые значения:

| Метрика         |     🟢 |      🟡 |     🔴 |
| --------------- | -----: | ------: | -----: |
| CPU             |  < 60% |  60–84% |  ≥ 85% |
| RAM             |  < 70% |  70–89% |  ≥ 90% |
| Disk            |  < 75% |  75–89% |  ≥ 90% |
| CPU temperature | < 65°C | 65–79°C | ≥ 80°C |

## Удаление

Удалить dashboard:

```bash
sudo rm -f /usr/local/bin/ssh-dashboard
sudo rm -f /etc/profile.d/ssh-dashboard.sh
```

Дополнительные пакеты, установленные вручную или installer'ом, автоматически не удаляются.

## License

MIT

````

### `CONTRIBUTING.md`

:::writing{variant="document" id="73194"}
# Contributing

## Назначение

Этот документ содержит инструкции для разработчиков и правила развития SSH Dashboard.

`README.md` предназначен для пользователей.

`CONTRIBUTING.md` предназначен для разработки, тестирования и сопровождения проекта.

## Архитектура

Проект должен сохранять разделение между установщиком и приложением:

```text
ssh-dashboard/
│
├── install-ssh-dashboard.sh
├── ssh-dashboard.sh
├── README.md
├── CONTRIBUTING.md
└── .gitignore
````

### `ssh-dashboard.sh`

Основной исходный код dashboard.

Отвечает за:

* сбор системной информации;
* форматирование данных;
* определение состояния метрик;
* построение информационных блоков;
* адаптацию интерфейса под ширину терминала.

### `install-ssh-dashboard.sh`

Installer.

Отвечает только за:

* проверку root;
* установку необходимых зависимостей;
* установку `ssh-dashboard.sh` в `/usr/local/bin/ssh-dashboard`;
* создание `/etc/profile.d/ssh-dashboard.sh`;
* установку прав доступа.

Основная логика dashboard не должна дублироваться внутри installer.

### `/etc/profile.d/ssh-dashboard.sh`

Минимальный launcher.

Он должен:

1. Проверять наличие интерактивного терминала.
2. Проверять SSH-сессию.
3. Запускать `/usr/local/bin/ssh-dashboard`.

Dashboard не должен запускаться для неинтерактивных SSH-команд:

```bash
ssh user@host "ls -la"
```

## Принципы разработки

### 1. Dashboard не должен изменять систему

Во время обычного запуска запрещены:

* изменение SSH configuration;
* изменение firewall;
* изменение systemd units;
* изменение Docker containers;
* изменение сетевой конфигурации;
* изменение пользователей;
* автоматическая установка пакетов.

Dashboard только собирает и отображает информацию.

### 2. Не использовать sudo внутри dashboard

Dashboard должен работать с правами обычного пользователя.

Если определённая информация недоступна без root, необходимо:

* корректно определить отсутствие доступа;
* показать `N/A` или соответствующий статус;
* не запрашивать пароль.

### 3. Отсутствие компонента не должно ломать dashboard

Например, если Docker отсутствует:

```text
🐳 DOCKER
Docker is not installed
```

Если недоступна температура:

```text
Temp: N/A
```

Если Fail2Ban не установлен:

```text
Fail2Ban: not installed
```

Dashboard должен продолжать работу.

### 4. Не выполнять долгие операции

SSH login не должен зависать из-за dashboard.

Для сетевых запросов необходимо использовать timeout.

Для потенциально медленных операций рекомендуется использовать cache.

Например:

```text
WAN IP
  ↓
cache
  ↓
не чаще одного запроса в 60 секунд
```

## Структура dashboard

Основные блоки:

```text
System
CPU
Memory
Disks
Network
Docker
Users
Ports
System & Security
```

Новые блоки следует добавлять как отдельные функции.

Например:

```bash
render_cpu()
render_memory()
render_disks()
render_network()
render_docker()
```

Это упрощает тестирование и дальнейшее изменение интерфейса.

## Адаптивность

Dashboard должен поддерживать как минимум два режима.

### Wide

Для терминалов:

```text
>= 90 columns
```

Используется двухколоночная компоновка.

### Narrow

Для терминалов:

```text
< 90 columns
```

Блоки выводятся последовательно.

Нельзя рассчитывать на фиксированную ширину терминала.

## Пороговые значения

Пороговые значения должны находиться в конфигурационной секции в начале `ssh-dashboard.sh`.

Например:

```bash
CPU_WARN=60
CPU_CRIT=85

RAM_WARN=70
RAM_CRIT=90

DISK_WARN=75
DISK_CRIT=90

TEMP_WARN=65
TEMP_CRIT=80
```

Не следует распределять такие значения по функциям.

## Тестирование

Перед коммитом необходимо проверить:

### Обычный SSH

```bash
ssh user@server
```

### Неинтерактивная команда

```bash
ssh user@server "uptime"
```

Dashboard не должен появляться.

### Узкий терминал

Проверить терминал шириной менее 90 колонок.

### Широкий терминал

Проверить двухколоночный режим.

### Без Docker

Dashboard должен корректно работать на сервере без Docker.

### Docker без доступа

Dashboard не должен завершаться с ошибкой.

### Без температуры

`Temp: N/A` является допустимым результатом.

### Без WAN

Отсутствие Internet не должно останавливать dashboard.

## Roadmap

### v0.1

* [x] CPU
* [x] RAM
* [x] Swap
* [x] Disk usage
* [x] LAN IP
* [x] WAN IP
* [x] Internet latency
* [x] Docker containers
* [x] Users
* [x] Listening ports
* [x] systemd failed units
* [x] Fail2Ban
* [x] SSH failures
* [x] Available updates
* [x] Reboot requirement
* [x] Adaptive layout

### v0.2

* [ ] Docker CPU usage
* [ ] Docker RAM usage
* [ ] Docker health status
* [ ] NVMe temperature
* [ ] HDD/NVMe SMART health
* [ ] Disk I/O
* [ ] Network throughput

### v0.3

* [ ] systemd service monitoring
* [ ] recent system errors
* [ ] TLS certificate expiration
* [ ] configurable ping targets
* [ ] configuration file
* [ ] enable/disable individual blocks

### Future

* [ ] compact mode
* [ ] multiple display themes
* [ ] JSON output
* [ ] machine-readable metrics
* [ ] optional persistent metrics collector

## Backward compatibility

Dashboard должен продолжать работать при отсутствии дополнительных компонентов.

Новые функции не должны превращать необязательные зависимости в обязательные без явной причины.

Изменение формата конфигурации должно сопровождаться обновлением документации.

## Release checklist

Перед созданием release необходимо проверить:

```text
[ ] Debian 12
[ ] Debian 13
[ ] x86_64
[ ] ARM64
[ ] интерактивный SSH
[ ] неинтерактивный SSH
[ ] narrow terminal
[ ] wide terminal
[ ] Docker installed
[ ] Docker unavailable
[ ] Fail2Ban installed
[ ] Fail2Ban unavailable
[ ] CPU temperature available
[ ] CPU temperature unavailable
[ ] Internet available
[ ] Internet unavailable
[ ] отсутствие mounted data disk
[ ] наличие нескольких дисков
[ ] отсутствие sudo у пользователя
```
