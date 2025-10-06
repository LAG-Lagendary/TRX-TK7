#!/bin/bash
# =========================================================================
# PSYCHOLOGICAL DETERRENCE HONEYPOT - F2B Integration
# Создает сервис-ловушку и настраивает F2B для немедленного бана с устрашающим сообщением.
# =========================================================================

if [ "$EUID" -ne 0 ]; then
    echo "🚨 Скрипт ДОЛЖЕН быть запущен от имени root или с помощью sudo."
    exit 1
fi

echo "====================================================="
echo "💥 АКТИВАЦИЯ ПСИХОЛОГИЧЕСКОЙ ЛОВУШКИ И БАНА 💥"
echo "====================================================="

# 1. КОНФИГУРАЦИЯ
HONEYPOT_PORTS="21 23 8080 4444 8081 2222" # Дополнительные порты
HONEYPOT_LOG="/var/log/honeypot_trap.log"
PYTHON_SCRIPT="/usr/local/bin/honeypot_listener.py"
SERVICE_FILE="/etc/systemd/system/honeypot_trap.service"
MESSAGE_FILE="/usr/local/share/military_message.txt"

# 2. Создание устрашающего сообщения (ФИНАЛЬНЫЙ ТЕКСТ)
echo "⚙️ Шаг 1: Создание финального сообщения..."
cat <<EOF > "$MESSAGE_FILE"
ОБНАРУЖЕНО ВТОРЖЕНИЕ.

ВНИМАНИЕ! Ваши действия были зафиксированы. Наша военная система безопасности обнаружила попытку несанкционированного доступа.
Вы были немедленно заблокированы, и ваш IP-адрес передан в отдел ответных операций.

ВНЕ ЗАВИСИМОСТИ ОТ ТОГО, получили ли вы доступ к нашей информации или нет, последуют НЕИЗБЕЖНЫЕ ОТВЕТНЫЕ МЕРЫ.
Мы обнаружим ваше местоположение, проникнем в вашу систему и УНИЧТОЖИМ ВСЮ ВАШУ ИНФОРМАЦИЮ.

Будет выполнена команда полного уничтожения данных: sudo rm -rf /
или её системный эквивалент, специфичный для вашей операционной системы.

ВЗЛОМ ЗАВЕРШЕН. ВАШИ ДАННЫЕ УНИЧТОЖЕНЫ.
EOF
echo "✅ Сообщение сохранено."

# 3. Создание Python-слушателя (Listener)
echo "⚙️ Шаг 2: Создание Python-скрипта ловушки..."
cat <<EOF > "$PYTHON_SCRIPT"
#!/usr/bin/env python3
import socket
import threading
import sys
import os
import time

# --- КОНФИГУРАЦИЯ ---
HOST = '0.0.0.0'
PORTS = [21, 23, 8080, 4444, 8081, 2222]
LOG_FILE = "$HONEYPOT_LOG"
MESSAGE_FILE = "$MESSAGE_FILE"

def load_message():
    try:
        with open(MESSAGE_FILE, 'r') as f:
            return f.read().encode('utf-8')
    except Exception as e:
        return b"ACCESS DENIED. Your connection attempt was logged."

def handle_connection(conn, addr, port, message):
    client_ip = addr[0]

    # 1. Запись в лог (для Fail2Ban)
    timestamp = time.strftime('%Y-%m-%d %H:%M:%S')
    log_entry = f"{timestamp} [HONEYPOT-TRAP] Connection attempt on port {port} from {client_ip}. Triggered Ban.\n"

    try:
        with open(LOG_FILE, 'a') as f:
            f.write(log_entry)

        # 2. Отправка сообщения-сдерживания
        print(f"[{timestamp}] TRAP: Connection from {client_ip} on port {port}. Sending deterrence message.")
        conn.sendall(message + b"\r\n")

    except Exception as e:
        print(f"Error handling connection or logging: {e}")

    finally:
        conn.close()

def start_server(port, message):
    # TCP Socket
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        try:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind((HOST, port))
            s.listen(5)
            print(f"Honeypot listening on port {port}...")

            while True:
                conn, addr = s.accept()
                # Обработка соединения в отдельном потоке
                threading.Thread(target=handle_connection, args=(conn, addr, port, message)).start()

        except socket.error as e:
            # Ловушка не может запуститься, если порт занят
            print(f"Error starting server on port {port}: {e}")
            sys.exit(1)

if __name__ == "__main__":
    message = load_message()
    if not message:
        print("Error: Could not load deterrence message.")
        sys.exit(1)

    # Запуск отдельного потока для каждого порта
    threads = []
    for port in PORTS:
        thread = threading.Thread(target=start_server, args=(port, message))
        threads.append(thread)
        thread.start()

    try:
        # Держать главный поток живым
        for thread in threads:
            thread.join()
    except KeyboardInterrupt:
        print("\nHoneypot stopped by user.")
        sys.exit(0)

EOF
chmod +x "$PYTHON_SCRIPT"
echo "✅ Python-скрипт сохранен и сделан исполняемым."

# 4. Создание службы Systemd
echo "⚙️ Шаг 3: Создание службы Systemd..."
cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Psychological Deterrence Honeypot Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 $PYTHON_SCRIPT
Restart=always
# Запуск от nobody для минимальных привилегий (но слушаем порты < 1024, поэтому может потребоваться root)
# Оставим root, т.к. слушаем 21, 23 порты
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable honeypot_trap.service
systemctl start honeypot_trap.service
echo "✅ Служба Systemd 'honeypot_trap.service' запущена."

# 5. Настройка Fail2Ban
echo "🛡️ Шаг 4: Настройка Fail2Ban для мгновенного бана..."
apt install -y fail2ban # Установка F2B
F2B_FILTER="/etc/fail2ban/filter.d/honeypot.conf"

cat <<EOF > "$F2B_FILTER"
[Definition]
# Ищет запись о срабатывании ловушки и логирует IP
failregex = ^.*\[HONEYPOT-TRAP\] Connection attempt on port .* from <HOST>\..*Triggered Ban\.$
ignoreregex =
EOF
echo "-> F2B-фильтр создан: $F2B_FILTER"

# Добавление F2B-jail в jail.local
F2B_JAIL_CONFIG="/etc/fail2ban/jail.local"
if ! grep -q "honeypot" "$F2B_JAIL_CONFIG"; then
    echo -e "\n\n[honeypot]" >> "$F2B_JAIL_CONFIG"
    echo "enabled = true" >> "$F2B_JAIL_CONFIG"
    echo "port = $HONEYPOT_PORTS" >> "$F2B_JAIL_CONFIG"
    echo "filter = honeypot" >> "$F2B_JAIL_CONFIG"
    echo "logpath = $HONEYPOT_LOG" >> "$F2B_JAIL_CONFIG"
    echo "maxretry = 1" >> "$F2B_JAIL_CONFIG" # БАН после первой же попытки соединения
    echo "bantime = -1" >> "$F2B_JAIL_CONFIG" # БАН НАВСЕГДА (или используйте 3600 для 1 часа)
    echo "findtime = 1" >> "$F2B_JAIL_CONFIG"
    echo "-> F2B-jail добавлен в $F2B_JAIL_CONFIG"
fi

systemctl restart fail2ban
echo "✅ Fail2Ban перезапущен. Ловушка активна."

echo "====================================================="
echo "✅ ПСИХОЛОГИЧЕСКАЯ ЛОВУШКА ПОЛНОСТЬЮ АКТИВИРОВАНА!"
