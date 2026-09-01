#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# SSH Dashboard Installer
# ============================================================

DASHBOARD_PATH="/usr/local/bin/ssh-dashboard"
PROFILE_PATH="/etc/profile.d/ssh-dashboard.sh"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Ошибка: installer необходимо запускать от root."
    echo
    echo "Использование:"
    echo "  sudo bash $0"
    exit 1
fi

echo "============================================================"
echo " SSH Dashboard Installer"
echo "============================================================"
echo

# ------------------------------------------------------------
# Install dependencies
# ------------------------------------------------------------

echo "[1/4] Установка зависимостей..."

export DEBIAN_FRONTEND=noninteractive

apt-get update -qq

apt-get install -y \
    curl \
    iproute2 \
    procps \
    util-linux \
    coreutils \
    grep \
    gawk \
    sed \
    >/dev/null

# Optional utilities.
# Dashboard продолжит работать без них.
apt-get install -y \
    lm-sensors \
    smartmontools \
    >/dev/null 2>&1 || true

echo "      OK"


# ------------------------------------------------------------
# Install dashboard
# ------------------------------------------------------------

echo "[2/4] Установка dashboard..."

cat > "${DASHBOARD_PATH}" <<'DASHBOARD'
#!/usr/bin/env bash

# ============================================================
# SSH Dashboard
# ============================================================
#
# Adaptive system information dashboard for Debian.
#
# Supports:
#   Debian 12 / 13
#   x86_64
#   ARM / ARM64
#   Raspberry Pi
#
# ============================================================


# ------------------------------------------------------------
# UTF-8 locale
# ------------------------------------------------------------

setup_locale() {

    local locale_name

    for locale_name in C.UTF-8 en_US.UTF-8; do
        if locale -a 2>/dev/null | grep -qi "^${locale_name}$"; then
            export LANG="${locale_name}"
            export LC_ALL="${locale_name}"
            return
        fi
    done

    # Debian commonly uses c.utf8.
    if locale -a 2>/dev/null | grep -qi '^c\.utf8$'; then
        export LANG="C.utf8"
        export LC_ALL="C.utf8"
    fi
}

setup_locale


# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

BAR_WIDTH=10

CPU_WARN=60
CPU_CRIT=85

RAM_WARN=70
RAM_CRIT=90

DISK_WARN=75
DISK_CRIT=90

TEMP_WARN=65
TEMP_CRIT=80

PING_HOST="1.1.1.1"

CURL_TIMEOUT=2
PING_TIMEOUT=1

MAX_DOCKER_ROWS=8
MAX_PORT_ROWS=10


# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------

if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then

    RESET=$'\033[0m'
    BOLD=$'\033[1m'
    DIM=$'\033[2m'

    RED=$'\033[31m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    CYAN=$'\033[36m'

else

    RESET=""
    BOLD=""
    DIM=""

    RED=""
    GREEN=""
    YELLOW=""
    CYAN=""

fi


# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

repeat_char() {

    local char="$1"
    local count="$2"

    local result=""

    (( count <= 0 )) && return

    for ((i = 0; i < count; i++)); do
        result+="${char}"
    done

    printf '%s' "${result}"
}


strip_ansi() {

    sed $'s/\033\\[[0-9;]*m//g'
}


visible_length() {

    local value="$1"

    printf '%s' "${value}" |
        strip_ansi |
        wc -L |
        tr -d ' '
}


truncate_text() {

    local text="$1"
    local max="$2"

    if (( ${#text} <= max )); then
        printf '%s' "${text}"
    elif (( max > 3 )); then
        printf '%s...' "${text:0:max-3}"
    else
        printf '%s' "${text:0:max}"
    fi
}


status_icon() {

    local value="$1"
    local warn="$2"
    local crit="$3"

    if (( value >= crit )); then
        printf '%s🔴%s' "${RED}" "${RESET}"
    elif (( value >= warn )); then
        printf '%s🟡%s' "${YELLOW}" "${RESET}"
    else
        printf '%s🟢%s' "${GREEN}" "${RESET}"
    fi
}


progress_bar() {

    local value="$1"
    local width="${2:-${BAR_WIDTH}}"

    (( value < 0 )) && value=0
    (( value > 100 )) && value=100

    local filled=$(( value * width / 100 ))
    local empty=$(( width - filled ))

    printf '%s%s' \
        "$(repeat_char '▓' "${filled}")" \
        "$(repeat_char '░' "${empty}")"
}


human_bytes() {

    local bytes="${1:-0}"

    awk -v b="${bytes}" '
    BEGIN {
        split("B KB MB GB TB PB", units, " ")

        i = 1

        while (b >= 1024 && i < 6) {
            b /= 1024
            i++
        }

        if (b >= 100 || i == 1)
            printf "%.0f %s", b, units[i]
        else if (b >= 10)
            printf "%.1f %s", b, units[i]
        else
            printf "%.2f %s", b, units[i]
    }'
}


format_seconds() {

    local seconds="${1:-0}"

    local weeks
    local days
    local hours
    local minutes

    weeks=$(( seconds / 604800 ))
    seconds=$(( seconds % 604800 ))

    days=$(( seconds / 86400 ))
    seconds=$(( seconds % 86400 ))

    hours=$(( seconds / 3600 ))
    seconds=$(( seconds % 3600 ))

    minutes=$(( seconds / 60 ))

    local result=""

    (( weeks > 0 )) && result+="${weeks} weeks, "
    (( days > 0 )) && result+="${days} days, "
    (( hours > 0 )) && result+="${hours} hours, "

    result+="${minutes} minutes"

    printf '%s' "${result}"
}


# ------------------------------------------------------------
# Box rendering
# ------------------------------------------------------------

make_box() {

    local width="$1"
    local title="$2"

    shift 2

    local inner=$(( width - 2 ))

    local title_text=" ${title} "
    local title_len

    title_len=$(visible_length "${title_text}")

    local remaining=$(( inner - title_len ))

    (( remaining < 0 )) && remaining=0

    printf '┌%s%s%s┐\n' \
        "$(repeat_char '─' $(( remaining / 2 )))" \
        "${title_text}" \
        "$(repeat_char '─' $(( remaining - remaining / 2 )))"

    local line

    for line in "$@"; do

        local len

        len=$(visible_length "${line}")

        if (( len > inner - 2 )); then
            line=$(truncate_text "${line}" $(( inner - 2 )))
            len=$(visible_length "${line}")
        fi

        local padding=$(( inner - 2 - len ))

        (( padding < 0 )) && padding=0

        printf '│ %s%*s │\n' \
            "${line}" \
            "${padding}" \
            ''

    done

    printf '└%s┘\n' \
        "$(repeat_char '─' "${inner}")"
}


combine_boxes() {

    local left="$1"
    local right="$2"
    local gap="${3:-2}"

    mapfile -t LEFT_LINES <<< "${left}"
    mapfile -t RIGHT_LINES <<< "${right}"

    local max=${#LEFT_LINES[@]}

    (( ${#RIGHT_LINES[@]} > max )) &&
        max=${#RIGHT_LINES[@]}

    local left_width=0
    local line
    local len

    for line in "${LEFT_LINES[@]}"; do

        len=$(visible_length "${line}")

        (( len > left_width )) &&
            left_width="${len}"

    done

    local i

    for ((i = 0; i < max; i++)); do

        local left_line="${LEFT_LINES[i]:-}"
        local right_line="${RIGHT_LINES[i]:-}"

        local left_len

        left_len=$(visible_length "${left_line}")

        printf '%s' "${left_line}"

        printf '%*s' \
            $(( left_width - left_len + gap )) \
            ''

        printf '%s\n' "${right_line}"

    done
}


# ------------------------------------------------------------
# System information
# ------------------------------------------------------------

HOSTNAME_SHORT=$(hostname -s 2>/dev/null || hostname)

OS_NAME="$(
    . /etc/os-release 2>/dev/null

    printf '%s' "${PRETTY_NAME:-Debian}"
)"

KERNEL=$(uname -r)
ARCH=$(uname -m)

UPTIME_SECONDS=$(
    awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0
)

UPTIME_TEXT=$(format_seconds "${UPTIME_SECONDS}")


# ------------------------------------------------------------
# CPU
# ------------------------------------------------------------

CPU_MODEL="$(
    awk -F: '
        /model name/ {
            gsub(/^[ \t]+/, "", $2)
            print $2
            exit
        }

        /^Model/ {
            gsub(/^[ \t]+/, "", $2)
            print $2
            exit
        }
    ' /proc/cpuinfo 2>/dev/null
)"

[[ -z "${CPU_MODEL}" ]] &&
    CPU_MODEL="${ARCH}"

CPU_CORES=$(nproc 2>/dev/null || echo "?")


read_cpu_stats() {

    awk '
        /^cpu / {

            idle=$5
            total=0

            for (i=2; i<=NF; i++)
                total += $i

            print total, idle

            exit
        }
    ' /proc/stat
}


read CPU_TOTAL_1 CPU_IDLE_1 < <(read_cpu_stats)

sleep 0.15

read CPU_TOTAL_2 CPU_IDLE_2 < <(read_cpu_stats)


CPU_DELTA=$(( CPU_TOTAL_2 - CPU_TOTAL_1 ))
CPU_IDLE_DELTA=$(( CPU_IDLE_2 - CPU_IDLE_1 ))


if (( CPU_DELTA > 0 )); then

    CPU_USAGE=$(
        awk \
            -v total="${CPU_DELTA}" \
            -v idle="${CPU_IDLE_DELTA}" \
            'BEGIN {
                printf "%.0f", 100 * (total - idle) / total
            }'
    )

else

    CPU_USAGE=0

fi


LOAD_AVG=$(
    awk '{printf "%s %s %s", $1, $2, $3}' /proc/loadavg
)


get_cpu_temp() {

    local temp

    # Standard Linux thermal zone.
    for file in /sys/class/thermal/thermal_zone*/temp; do

        [[ -r "${file}" ]] || continue

        temp=$(cat "${file}" 2>/dev/null || true)

        if [[ "${temp}" =~ ^[0-9]+$ ]] &&
           (( temp > 1000 && temp < 150000 )); then

            awk -v t="${temp}" \
                'BEGIN { printf "%.0f", t / 1000 }'

            return

        fi

    done


    # hwmon.
    for file in /sys/class/hwmon/hwmon*/temp*_input; do

        [[ -r "${file}" ]] || continue

        temp=$(cat "${file}" 2>/dev/null || true)

        if [[ "${temp}" =~ ^[0-9]+$ ]] &&
           (( temp > 1000 && temp < 150000 )); then

            awk -v t="${temp}" \
                'BEGIN { printf "%.0f", t / 1000 }'

            return

        fi

    done


    printf ''
}


CPU_TEMP=$(get_cpu_temp)


# ------------------------------------------------------------
# Memory
# ------------------------------------------------------------

MEM_TOTAL_KB=$(
    awk '/MemTotal:/ {print $2}' /proc/meminfo
)

MEM_AVAILABLE_KB=$(
    awk '/MemAvailable:/ {print $2}' /proc/meminfo
)

MEM_USED_KB=$(
    awk -v total="${MEM_TOTAL_KB}" \
        -v available="${MEM_AVAILABLE_KB}" \
        'BEGIN { print total - available }'
)


if (( MEM_TOTAL_KB > 0 )); then

    MEM_PERCENT=$(
        awk \
            -v used="${MEM_USED_KB}" \
            -v total="${MEM_TOTAL_KB}" \
            'BEGIN {
                printf "%.0f", used * 100 / total
            }'
    )

else

    MEM_PERCENT=0

fi


MEM_USED=$(human_bytes $(( MEM_USED_KB * 1024 )))
MEM_TOTAL=$(human_bytes $(( MEM_TOTAL_KB * 1024 )))

MEM_AVAILABLE=$(human_bytes $(( MEM_AVAILABLE_KB * 1024 )))


SWAP_TOTAL_KB=$(
    awk '/SwapTotal:/ {print $2}' /proc/meminfo
)

SWAP_FREE_KB=$(
    awk '/SwapFree:/ {print $2}' /proc/meminfo
)

SWAP_USED_KB=$(( SWAP_TOTAL_KB - SWAP_FREE_KB ))

SWAP_USED=$(human_bytes $(( SWAP_USED_KB * 1024 )))
SWAP_TOTAL=$(human_bytes $(( SWAP_TOTAL_KB * 1024 )))


# ------------------------------------------------------------
# Network
# ------------------------------------------------------------

DEFAULT_INTERFACE="$(
    ip route show default 2>/dev/null |
        awk 'NR==1 {print $5}'
)"

LAN_IP="N/A"


if [[ -n "${DEFAULT_INTERFACE}" ]]; then

    LAN_IP="$(
        ip -4 addr show dev "${DEFAULT_INTERFACE}" 2>/dev/null |
            awk '/inet / {
                print $2
                exit
            }' |
            cut -d/ -f1
    )"

    [[ -z "${LAN_IP}" ]] &&
        LAN_IP="N/A"

fi


# ------------------------------------------------------------
# WAN cache
# ------------------------------------------------------------

CACHE_DIR="/tmp/ssh-dashboard-${UID}"

mkdir -p "${CACHE_DIR}" 2>/dev/null || true

WAN_CACHE="${CACHE_DIR}/wan"

WAN_IP="N/A"


cache_valid() {

    local file="$1"
    local max_age="$2"

    [[ -f "${file}" ]] || return 1

    local now
    local mtime

    now=$(date +%s)

    mtime=$(
        stat -c %Y "${file}" 2>/dev/null || echo 0
    )

    (( now - mtime < max_age ))
}


if cache_valid "${WAN_CACHE}" 60; then

    WAN_IP=$(cat "${WAN_CACHE}" 2>/dev/null || echo "N/A")

else

    WAN_IP="$(
        curl \
            --silent \
            --max-time "${CURL_TIMEOUT}" \
            https://api.ipify.org \
            2>/dev/null || true
    )"

    [[ -z "${WAN_IP}" ]] &&
        WAN_IP="N/A"

    printf '%s' "${WAN_IP}" \
        > "${WAN_CACHE}" 2>/dev/null || true

fi


# ------------------------------------------------------------
# Internet latency
# ------------------------------------------------------------

PING_RESULT="$(
    ping \
        -c 1 \
        -W "${PING_TIMEOUT}" \
        "${PING_HOST}" \
        2>/dev/null || true
)"

PING_MS="$(
    printf '%s\n' "${PING_RESULT}" |
        awk -F'time=' '
            /time=/ {
                split($2,a," ")
                print a[1]
                exit
            }
        '
)"


if [[ -n "${PING_MS}" ]]; then
    INTERNET_STATUS="✅ Available (${PING_MS} ms)"
else
    INTERNET_STATUS="❌ Unavailable"
fi


# ------------------------------------------------------------
# Network traffic
# ------------------------------------------------------------

RX_BYTES=0
TX_BYTES=0


if [[ -n "${DEFAULT_INTERFACE}" ]]; then

    if [[ -r "/sys/class/net/${DEFAULT_INTERFACE}/statistics/rx_bytes" ]]; then
        RX_BYTES=$(cat \
            "/sys/class/net/${DEFAULT_INTERFACE}/statistics/rx_bytes")
    fi

    if [[ -r "/sys/class/net/${DEFAULT_INTERFACE}/statistics/tx_bytes" ]]; then
        TX_BYTES=$(cat \
            "/sys/class/net/${DEFAULT_INTERFACE}/statistics/tx_bytes")
    fi

fi


# ------------------------------------------------------------
# Docker
# ------------------------------------------------------------

DOCKER_AVAILABLE=0
DOCKER_RUNNING=0
DOCKER_TOTAL=0

DOCKER_LINES=()


if command -v docker >/dev/null 2>&1; then

    if docker info >/dev/null 2>&1; then

        DOCKER_AVAILABLE=1

        DOCKER_TOTAL=$(
            docker ps -a -q 2>/dev/null |
                wc -l |
                tr -d ' '
        )

        DOCKER_RUNNING=$(
            docker ps -q 2>/dev/null |
                wc -l |
                tr -d ' '
        )


        while IFS='|' read -r name state status; do

            [[ -z "${name}" ]] &&
                continue

            local_icon="🔴"

            case "${state}" in

                running)
                    local_icon="🟢"
                    ;;

                paused)
                    local_icon="🟡"
                    ;;

                restarting)
                    local_icon="🟡"
                    ;;

            esac

            DOCKER_LINES+=(
                "${local_icon} $(printf '%-18s' "${name}") ${status}"
            )

        done < <(
            docker ps -a \
                --format '{{.Names}}|{{.State}}|{{.Status}}' \
                2>/dev/null |
                head -n "${MAX_DOCKER_ROWS}"
        )

    fi

fi


# ------------------------------------------------------------
# Users
# ------------------------------------------------------------

LOGGED_USERS=$(
    who 2>/dev/null |
        awk '{print $1}' |
        sort -u |
        wc -l |
        tr -d ' '
)

SSH_SESSIONS=$(
    who 2>/dev/null |
        grep -cE '\([^)]+\)' ||
        true
)

USER_LIST="$(
    who 2>/dev/null |
        awk '{print $1}' |
        sort -u |
        paste -sd ', ' -
)"

[[ -z "${USER_LIST}" ]] &&
    USER_LIST="none"


# ------------------------------------------------------------
# Listening ports
# ------------------------------------------------------------

PORT_LINES=()


while IFS= read -r entry; do

    [[ -n "${entry}" ]] &&
        PORT_LINES+=("${entry}")

done < <(

    ss -H -lntup 2>/dev/null |
        awk '

        {
            proto=$1
            local_address=$5

            n=split(local_address, a, ":")
            port=a[n]

            process=""

            if (match($0, /users:\(\("[^"]+"/)) {

                p=substr($0,RSTART,RLENGTH)

                gsub(/users:\(\("/, "", p)
                gsub(/"/, "", p)

                process=p
            }


            key=proto "/" port


            if (!(key in seen)) {

                seen[key]=1

                if (process != "")
                    printf "%-9s %-6s %s\n",
                        proto, port, process
                else
                    printf "%-9s %-6s\n",
                        proto, port

            }

        }
        ' |
        sort -k2,2n |
        head -n "${MAX_PORT_ROWS}"

)


# ------------------------------------------------------------
# System health
# ------------------------------------------------------------

FAILED_UNITS=$(
    systemctl --failed --no-legend 2>/dev/null |
        grep -c . ||
        true
)


if command -v fail2ban-client >/dev/null 2>&1; then

    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        FAIL2BAN_STATUS="🟢 active"
    else
        FAIL2BAN_STATUS="🔴 inactive"
    fi

else

    FAIL2BAN_STATUS="not installed"

fi


# ------------------------------------------------------------
# Failed SSH attempts
# ------------------------------------------------------------

FAILED_SSH=0


if command -v journalctl >/dev/null 2>&1; then

    FAILED_SSH=$(
        journalctl \
            --since "24 hours ago" \
            -u ssh \
            -u sshd \
            --no-pager \
            2>/dev/null |
            grep -Eic \
                'Failed password|authentication failure|Invalid user' ||
            true
    )

fi


# ------------------------------------------------------------
# Updates
# ------------------------------------------------------------

UPDATES="?"


if command -v apt >/dev/null 2>&1; then

    UPDATES=$(
        apt list --upgradable 2>/dev/null |
            tail -n +2 |
            grep -c . ||
            true
    )

fi


# ------------------------------------------------------------
# Reboot
# ------------------------------------------------------------

if [[ -f /var/run/reboot-required ]]; then
    REBOOT_STATUS="⚠️ yes"
else
    REBOOT_STATUS="✅ no"
fi


# ------------------------------------------------------------
# Disks
# ------------------------------------------------------------

DISK_LINES=()


while read -r filesystem size used avail percent mountpoint; do

    [[ -z "${filesystem}" ]] &&
        continue


    case "${filesystem}" in

        tmpfs|devtmpfs|overlay|shm)
            continue
            ;;

    esac


    percent_num="${percent%\%}"

    [[ "${percent_num}" =~ ^[0-9]+$ ]] ||
        continue


    disk_icon=$(
        status_icon \
            "${percent_num}" \
            "${DISK_WARN}" \
            "${DISK_CRIT}"
    )


    disk_bar=$(
        progress_bar "${percent_num}"
    )


    label="${mountpoint}"


    case "${mountpoint}" in

        /)
            label="📍 System /"
            ;;

        /boot)
            label="Boot"
            ;;

        /boot/efi)
            label="EFI"
            ;;

        /home)
            label="Home"
            ;;

        /mnt/*|/media/*)
            label="📦 ${mountpoint}"
            ;;

    esac


    DISK_LINES+=("${label}")

    DISK_LINES+=(
        "${used}/${size} ${disk_icon} ${percent_num}% ${disk_bar}"
    )


done < <(

    df -hP \
        -x tmpfs \
        -x devtmpfs \
        -x squashfs \
        -x overlay \
        2>/dev/null |
        awk 'NR > 1 {
            print $1,$2,$3,$4,$5,$6
        }'

)


if (( ${#DISK_LINES[@]} == 0 )); then
    DISK_LINES=("No disks detected")
fi


# ------------------------------------------------------------
# Build blocks
# ------------------------------------------------------------

CPU_STATUS=$(
    status_icon \
        "${CPU_USAGE}" \
        "${CPU_WARN}" \
        "${CPU_CRIT}"
)

CPU_BAR=$(
    progress_bar "${CPU_USAGE}"
)


if [[ -n "${CPU_TEMP}" ]]; then

    TEMP_STATUS=$(
        status_icon \
            "${CPU_TEMP}" \
            "${TEMP_WARN}" \
            "${TEMP_CRIT}"
    )

    TEMP_LINE="Temp: ${TEMP_STATUS} ${CPU_TEMP}°C"

else

    TEMP_LINE="Temp: N/A"

fi


RAM_STATUS=$(
    status_icon \
        "${MEM_PERCENT}" \
        "${RAM_WARN}" \
        "${RAM_CRIT}"
)

RAM_BAR=$(
    progress_bar "${MEM_PERCENT}"
)


SYSTEM_BOX=$(
    make_box 88 \
        "🖥️  ${HOSTNAME_SHORT}" \
        "${OS_NAME}" \
        "Kernel: ${KERNEL} • ${ARCH}" \
        "Uptime: ${UPTIME_TEXT}"
)


CPU_BOX=$(
    make_box 42 \
        "💻 CPU" \
        "$(truncate_text "${CPU_MODEL}" 34)" \
        "Cores: ${CPU_CORES}" \
        "${TEMP_LINE}" \
        "Usage: ${CPU_STATUS} ${CPU_USAGE}% ${CPU_BAR}" \
        "Load: ${LOAD_AVG}"
)


MEMORY_BOX=$(
    make_box 42 \
        "💾 MEMORY" \
        "RAM: ${MEM_USED} / ${MEM_TOTAL}" \
        "${RAM_STATUS} ${MEM_PERCENT}% ${RAM_BAR}" \
        "Swap: ${SWAP_USED} / ${SWAP_TOTAL}" \
        "" \
        "Available: ${MEM_AVAILABLE}"
)


NETWORK_BOX=$(
    make_box 42 \
        "🌐 NETWORK" \
        "Interface: ${DEFAULT_INTERFACE:-N/A}" \
        "LAN: ${LAN_IP}" \
        "WAN: ${WAN_IP}" \
        "Internet: ${INTERNET_STATUS}" \
        "RX: $(human_bytes "${RX_BYTES}")  TX: $(human_bytes "${TX_BYTES}")"
)


DISKS_BOX=$(
    make_box 42 \
        "💾 DISKS" \
        "${DISK_LINES[@]}"
)


USER_BOX=$(
    make_box 42 \
        "👤 USERS" \
        "Logged users: ${LOGGED_USERS}" \
        "SSH sessions: ${SSH_SESSIONS}" \
        "Users: ${USER_LIST}" \
        "" \
        "Current: ${USER:-unknown}"
)


if (( ${#PORT_LINES[@]} == 0 )); then
    PORT_LINES=("No listening ports detected")
fi


PORT_BOX=$(
    make_box 42 \
        "🔌 LISTENING PORTS" \
        "${PORT_LINES[@]}"
)


if (( DOCKER_AVAILABLE )); then

    DOCKER_CONTENT=(
        "Containers: ${DOCKER_RUNNING} running / ${DOCKER_TOTAL} total"
        ""
    )

    if (( ${#DOCKER_LINES[@]} > 0 )); then
        DOCKER_CONTENT+=("${DOCKER_LINES[@]}")
    else
        DOCKER_CONTENT+=("No containers")
    fi

else

    if command -v docker >/dev/null 2>&1; then

        DOCKER_CONTENT=(
            "Docker installed"
            "Daemon unavailable or permission denied"
        )

    else

        DOCKER_CONTENT=(
            "Docker is not installed"
        )

    fi

fi


DOCKER_BOX=$(
    make_box 88 \
        "🐳 DOCKER" \
        "${DOCKER_CONTENT[@]}"
)


if (( FAILED_UNITS > 0 )); then
    SYSTEMD_STATUS="🔴 ${FAILED_UNITS} failed"
else
    SYSTEMD_STATUS="🟢 0 failed"
fi


SECURITY_BOX=$(
    make_box 88 \
        "🛡️ SYSTEM & SECURITY" \
        "systemd: ${SYSTEMD_STATUS}    Fail2Ban: ${FAIL2BAN_STATUS}" \
        "Failed SSH / 24h: ${FAILED_SSH}    Updates: ${UPDATES}" \
        "Reboot required: ${REBOOT_STATUS}"
)


# ------------------------------------------------------------
# Render
# ------------------------------------------------------------

TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)


# Clear previous terminal content.
clear 2>/dev/null || true


printf '%s\n' "${CYAN}${SYSTEM_BOX}${RESET}"
printf '\n'


if (( TERM_WIDTH >= 90 )); then

    combine_boxes "${CPU_BOX}" "${MEMORY_BOX}"

    printf '\n'

    combine_boxes "${DISKS_BOX}" "${NETWORK_BOX}"

    printf '\n'

    printf '%s\n' "${DOCKER_BOX}"

    printf '\n'

    combine_boxes "${USER_BOX}" "${PORT_BOX}"

    printf '\n'

else

    printf '%s\n\n' "${CPU_BOX}"
    printf '%s\n\n' "${MEMORY_BOX}"
    printf '%s\n\n' "${DISKS_BOX}"
    printf '%s\n\n' "${NETWORK_BOX}"
    printf '%s\n\n' "${DOCKER_BOX}"
    printf '%s\n\n' "${USER_BOX}"
    printf '%s\n\n' "${PORT_BOX}"

fi


printf '%s\n' "${SECURITY_BOX}"

printf '\n'

printf '%s🕐 %s%s\n' \
    "${DIM}" \
    "$(date '+%d.%m.%Y %H:%M:%S %Z')" \
    "${RESET}"

printf '\n'

DASHBOARD


chmod 755 "${DASHBOARD_PATH}"

echo "      OK"


# ------------------------------------------------------------
# SSH profile hook
# ------------------------------------------------------------

echo "[3/4] Настройка SSH login hook..."

cat > "${PROFILE_PATH}" <<'PROFILE'
#!/usr/bin/env bash

# SSH Dashboard
#
# Run only for interactive SSH sessions.

if [[ -n "${SSH_CONNECTION:-}" ]] &&
   [[ -t 1 ]] &&
   [[ "${TERM:-}" != "dumb" ]]; then

    if [[ -x /usr/local/bin/ssh-dashboard ]]; then
        /usr/local/bin/ssh-dashboard
    fi

fi
PROFILE


chmod 644 "${PROFILE_PATH}"

echo "      OK"


# ------------------------------------------------------------
# Installation summary
# ------------------------------------------------------------

echo "[4/4] Проверка..."

if [[ -x "${DASHBOARD_PATH}" ]] &&
   [[ -f "${PROFILE_PATH}" ]]; then

    echo "      OK"

else

    echo "      ERROR"
    exit 1

fi


echo
echo "============================================================"
echo " SSH Dashboard успешно установлен"
echo "============================================================"
echo
echo "Dashboard:"
echo "  ${DASHBOARD_PATH}"
echo
echo "SSH hook:"
echo "  ${PROFILE_PATH}"
echo
echo "Запустить вручную:"
echo
echo "  ${DASHBOARD_PATH}"
echo
echo "После следующего интерактивного SSH-входа dashboard"
echo "запустится автоматически."
echo
echo "============================================================"
