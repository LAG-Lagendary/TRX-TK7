#!/bin/bash
# Russian: Скрипт для генерации маскирующего сетевого трафика (шума) с помощью trafgen.
# English: Script to generate decoy network traffic (noise) using trafgen.

# --- Настройки ---
# !!! ВАЖНО: Измените на ваш ФИЗИЧЕСКИЙ сетевой интерфейс (например, wlan0, eth0).
# !!! КРИТИЧЕСКИ ВАЖНО: НИКОГДА НЕ ИСПОЛЬЗУЙТЕ VPN/TOR ИНТЕРФЕЙСЫ (tun0, wg0)!
IFACE="eth0"
PORT_RANGE="10000-60000" # Диапазон портов для имитации случайной активности
PID_FILE="/var/run/trafgen_noise.pid"
LOG_FILE="/var/log/trafgen_noise.log"
TRAFGEN_SCRIPT_PATH="/usr/local/bin/trafgen_noise_script.txf"

# Проверяем наличие trafgen
if ! command -v trafgen &> /dev/null
then
    echo "Ошибка: 'trafgen' не найден. Установите netsniff-ng: sudo apt install netsniff-ng"
    exit 1
fi

# Проверяем права root
if [ "$EUID" -ne 0 ]; then
    echo "Пожалуйста, запустите этот скрипт от имени root или с помощью sudo."
    exit 1
fi

# Создание файла шаблона трафика (Traffic Template File)
create_trafgen_template() {
cat <<EOF > "$TRAFGEN_SCRIPT_PATH"
# Trafgen Noise Template
# Имитация большого объема случайных UDP-пакетов (DNS/VoIP/Game-like traffic)

<frame>
    # Ethernet Header (Случайный MAC)
    0xcccccccccccc, rand:eth, 0x0800

    # IP Header (UDP, Случайный IP)
    rand:ip(udp), rand:ip, rand:ip

    # UDP Header (Случайный порт)
    rand:port:$PORT_RANGE, rand:port:$PORT_RANGE, rand:size(64, 512), checksum:udp

    # Payload (Случайные данные)
    fill:rand(64)
</frame>
EOF
}

start_noise() {
    if [ -f "$PID_FILE" ]; then
        echo "⚠️ Сетевой шум уже запущен (PID: $(cat $PID_FILE)). Сначала остановите его."
        exit 1
    fi
    echo "💥 Запуск генератора сетевого шума (trafgen) на $IFACE..."

    create_trafgen_template

    # Запуск trafgen в фоновом режиме
    # --dev: интерфейс, --cfs: script file, --silent: не выводить прогресс, --no-cpu-pin: не привязывать к CPU
    trafgen --dev "$IFACE" --cfs "$TRAFGEN_SCRIPT_PATH" --silent --no-cpu-pin > "$LOG_FILE" 2>&1 &

    echo $! > "$PID_FILE"
    echo "✅ Сетевой шум запущен в фоновом режиме (PID: $(cat $PID_FILE)). Проверьте Wireshark."
}

stop_noise() {
    if [ ! -f "$PID_FILE" ]; then
        echo "⚠️ Сетевой шум не запущен."
        exit 1
    fi
    PID=$(cat "$PID_FILE")
    echo "👋 Остановка генератора сетевого шума (PID: $PID)..."
    kill "$PID" 2>/dev/null
    rm -f "$PID_FILE"
    rm -f "$TRAFGEN_SCRIPT_PATH" # Удаление временного файла
    echo "✅ Генератор остановлен. Лог сохранен в $LOG_FILE."
}

status_noise() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null; then
            echo "🟢 Сетевой шум АКТИВЕН (PID: $PID) на интерфейсе $IFACE."
            echo "Для остановки: sudo $0 stop"
            exit 0
        else
            echo "🔴 Сетевой шум не активен (PID-файл найден, но процесс мертв)."
            rm -f "$PID_FILE"
        fi
    fi
    echo "🔴 Сетевой шум НЕ АКТИВЕН."
}

case "$1" in
    start)
        start_noise
        ;;
    stop)
        stop_noise
        ;;
    status)
        status_noise
        ;;
    *)
        echo "Использование: sudo $0 [start|stop|status]"
        exit 1
        ;;
esac
