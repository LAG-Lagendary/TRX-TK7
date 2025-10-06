#!/bin/bash
# =========================================================================
# WIRESHARK PURSUIT TRAP - Изоляция и Обнаружение Подозрительной Активности
# Настраивает AppArmor для защиты файлов и CRON для TShark-мониторинга.
# =========================================================================

if [ "$EUID" -ne 0 ]; then
    echo "🚨 Скрипт ДОЛЖЕН быть запущен от имени root или с помощью sudo."
    exit 1
fi

LOG_DIR="/var/log/system_monitoring"
TTRAP_SCRIPT="/usr/local/sbin/tshark_trap_monitor.sh"
TSHARK_FILTER="tcp.port==22 && tcp.len>1000" # Пример: Слишком большой пакет SSH (попытка эксплойта/загрузки)

echo "====================================================="
echo "💥 АКТИВАЦИЯ ЛОВУШКИ ПРЕСЛЕДОВАНИЯ WIRESHARK 💥"
echo "====================================================="

# 1. Проверка AppArmor (уже настроен в главном скрипте, но дублируем логику)
WIRESHARK_PROFILE="/etc/apparmor.d/usr.bin.wireshark"
if [ -f "$WIRESHARK_PROFILE" ]; then
    echo "🛡️ AppArmor-профиль Wireshark уже настроен (Сеть разрешена, Домашний каталог запрещен)."
else
    echo "⚠️ ПРЕДУПРЕЖДЕНИЕ: AppArmor-профиль Wireshark не найден. Запустите Ultimate Paranoia System Setup.sh!"
fi

# 2. Создание скрипта TShark-мониторинга
echo "⚙️ Создание скрипта TShark-мониторинга для CRON..."
mkdir -p "$LOG_DIR"
chmod 700 "$LOG_DIR"

cat <<EOF > "$TTRAP_SCRIPT"
#!/bin/bash
# TShark Trap Monitor: Захват трафика и поиск подозрительной активности.
LOG_FILE="$LOG_DIR/ALERT_WIRESHARK_ACTIVITY.log"
TSHARK_FILTER="$TSHARK_FILTER"
IFACE="eth0" # !!! Измените на ваш сетевой интерфейс (eth0, wlan0 и т.д.)

# 1. Захват трафика на 60 секунд (для снижения нагрузки)
/usr/bin/tshark -i \$IFACE -a duration:60 -w /tmp/tshark_temp.pcap 2>/dev/null

if [ -f /tmp/tshark_temp.pcap ]; then
    # 2. Фильтрация захваченного файла по подозрительным правилам
    ALERT_COUNT=\$(/usr/bin/tshark -r /tmp/tshark_temp.pcap -Y "\$TSHARK_FILTER" | wc -l)

    if [ \$ALERT_COUNT -gt 0 ]; then
        # Обнаружено подозрение - сохраняем улики
        echo "=====================================================" >> \$LOG_FILE
        echo "🚨 \$(date): TSHARK TRAP ACTIVATED! (\${ALERT_COUNT} suspicious packets captured)" >> \$LOG_FILE
        echo "Suspect IP Sources:" >> \$LOG_FILE
        # Выводит уникальные исходные IP-адреса, которые соответствовали фильтру
        /usr/bin/tshark -r /tmp/tshark_temp.pcap -Y "\$TSHARK_FILTER" -T fields -e ip.src | sort | uniq >> \$LOG_FILE

        EVIDENCE_FILE="$LOG_DIR/evidence_\$(date +%Y%m%d%H%M%S).pcap"
        echo "Capture file saved to: \$EVIDENCE_FILE" >> \$LOG_FILE
        mv /tmp/tshark_temp.pcap \$EVIDENCE_FILE

        logger -t CRITICAL_ALARM "TShark Trap Activated. Evidence saved to \$EVIDENCE_FILE"

    else
        rm -f /tmp/tshark_temp.pcap # Удаляем, если ничего не найдено
    fi
fi
EOF

chmod +x "$TTRAP_SCRIPT"
echo "✅ Мониторинговый скрипт TShark создан: $TTRAP_SCRIPT"

# 3. Настройка CRON для постоянного запуска ловушки (Каждый час)
CRON_JOB="0 * * * * $TTRAP_SCRIPT"
CRON_NAME="TSHARK_PURSUIT_TRAP"
(crontab -l 2>/dev/null | grep -v "$CRON_NAME" ; echo "$CRON_JOB # $CRON_NAME") | crontab -
echo "✅ CRON-задание добавлено (запуск каждый час)."

echo "====================================================="
echo "✅ ЛОВУШКА ПРЕСЛЕДОВАНИЯ АКТИВИРОВАНА."
