#!/bin/bash
# =========================================================================
# PARANOIA TRAP (AIDE) SETUP SCRIPT
# Инициализирует AIDE и настраивает CRON-задачу для постоянного мониторинга.
# !!! ВАЖНО: Мониторинговый скрипт ТОЛЬКО ОПОВЕЩАЕТ, НО НЕ ОБНОВЛЯЕТ БАЗУ !!!
# =========================================================================

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo "🚨 Скрипт 'Ловушка Паранои' ДОЛЖЕН быть запущен от имени root или с помощью sudo."
    exit 1
fi

LOG_DIR="/var/log/system_monitoring"
ALARM_FILE="$LOG_DIR/ALERT_SYSTEM_INTEGRITY_VIOLATION.log"
CRON_JOB_NAME="AIDE_INTEGRITY_CHECK"
AIDE_DB="/var/lib/aide/aide.db"
TEMP_REPORT="/tmp/aide_check_report.tmp"

echo "====================================================="
echo "💥 ACTIVATING PARANOIA TRAP (AIDE)"
echo "====================================================="

# 1. Create log directory
mkdir -p "$LOG_DIR"
chmod 700 "$LOG_DIR"
echo "⚙️ Log directory created: $LOG_DIR"

# 2. Initialize AIDE database
echo "🔐 Initializing AIDE database (this may take a few minutes)..."
/usr/bin/aide --init
if [ -f /var/lib/aide/aide.db.new ]; then
    mv /var/lib/aide/aide.db.new "$AIDE_DB"
    echo "✅ AIDE database created. System state is 'ideal'."
else
    echo "❌ Ошибка: Не удалось создать aide.db. Проверьте конфигурацию AIDE."
    exit 1
fi

# 3. Setup CRON job script (Corrected - NO AUTO-UPDATE!)
AIDE_RUN_SCRIPT="/usr/local/sbin/aide_monitor_script.sh"

cat <<EOF > "$AIDE_RUN_SCRIPT"
#!/bin/bash
# AIDE Integrity Check Monitor Script (Corrected)
AIDE_DB="$AIDE_DB"
TEMP_REPORT="$TEMP_REPORT"
LOG_FILE="$ALARM_FILE"

# Запуск проверки
/usr/bin/aide --check > \$TEMP_REPORT 2>&1

if [ -s \$TEMP_REPORT ]; then
    # Change detected!

    # 1. Create/Update the critical alarm log
    echo "!!! КРИТИЧЕСКАЯ ТРЕВОГА (AIDE) - НАРУШЕНИЕ ЦЕЛОСТНОСТИ ФАЙЛОВОЙ СИСТЕМЫ !!!" > \$LOG_FILE
    echo "Дата/Время: \$(date)" >> \$LOG_FILE
    echo "-------------------------------------------------------------" >> \$LOG_FILE
    echo "WARNING: RESPONSE MECHANISM ACTIVATED. DO NOT TOUCH." >> \$LOG_FILE
    echo "" >> \$LOG_FILE

    # 2. Add summary of changes
    grep 'Total number of entries added' \$TEMP_REPORT >> \$LOG_FILE
    grep 'Total number of entries removed' \$TEMP_REPORT >> \$LOG_FILE
    grep 'Total number of entries changed' \$TEMP_REPORT >> \$LOG_FILE

    # 3. Add pointer to the full report and move it
    echo "" >> \$LOG_FILE
    REPORT_PATH="/var/log/system_monitoring/aide_report_latest.log"
    echo "Full report saved to: \$REPORT_PATH" >> \$LOG_FILE
    mv \$TEMP_REPORT \$REPORT_PATH

    echo "❌ Change detected. Alarm file updated. AIDE database REMAINS UNCHANGED (Evidence preserved)."

    # Отправка сигнала (например, для MOTD или Rsyslog)
    logger -t CRITICAL_ALARM "AIDE Integrity Violation Detected. Full report at \$REPORT_PATH"

else
    # Status NOMINAL
    echo "🟢 \$(date): System NOMINAL. Integrity check passed." > \$LOG_FILE
    rm -f /var/log/system_monitoring/aide_report_latest.log 2>/dev/null
    rm -f \$TEMP_REPORT 2>/dev/null
fi
EOF

chmod +x "$AIDE_RUN_SCRIPT"
echo "✅ Monitoring script created: $AIDE_RUN_SCRIPT"

# 4. Add CRON job: run script every 5 minutes
CRON_ENTRY="*/5 * * * * $AIDE_RUN_SCRIPT"
(crontab -l 2>/dev/null | grep -v "$CRON_JOB_NAME" ; echo "$CRON_ENTRY # $CRON_JOB_NAME") | crontab -
echo "✅ CRON-задание добавлено (запуск каждые 5 минут)."

echo "====================================================="
echo "✅ ЛОВУШКА ПАРАНОИ АКТИВИРОВАНА. Проверка начнется через 5 минут."
