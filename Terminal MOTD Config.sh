#!/bin/bash
# =========================================================================
# TERMINAL STATUS MESSAGE OF THE DAY (MOTD) CONFIG
# Настраивает автоматический вывод военного статуса системы при запуске терминала.
# =========================================================================

if [ "$EUID" -ne 0 ]; then
    echo "🚨 Скрипт должен быть запущен от имени root или с помощью sudo."
    exit 1
fi

BASHRC_FILE="/etc/bash.bashrc"
echo "====================================================="
echo "💥 Configuring automatic security status display..."

# 1. Define the function that will display the message
MOTD_FUNCTION='
# --- [Section: Critical Monitoring and Alerts] ---
# This function is executed every time an interactive terminal starts.
display_paranoia_motd() {
    # Bash Color Codes: 1;31m - Bright Red, 1;33m - Yellow, 1;36m - Cyan, 1;32m - Green

    # System Header
    echo -e "\n\033[1;31m------------------------------------------------------------\033[0m"
    echo -e "\033[1;33m>>> [PROJECT M.O.R.I.S. (Military Operations Response & Integrity System)] <<<\033[0m"
    echo -e "\033[1;31m------------------------------------------------------------\033[0m"

    # Status of Key Systems
    echo -e "   \033[1;36m[C.I.D.S. Active]:\033[0m Cooperative Intrusion Detection System (Suricata) - \033[1;32mONLINE\033[0m"
    echo -e "   \033[1;36m[UFW Kill Switch]:\033[0m Core Network Protection - \033[1;32mOK\033[0m"
    echo -e "   \033[1;36m[Net Noise]:\033[0m Counter-Intelligence Noise Generation (Trafgen/Python) - \033[1;32mDEPLOYED (Check PID)\033[0m"

    # Dynamic AIDE Status (Paranoia Trap)
    ALARM_FILE="/var/log/system_monitoring/ALERT_SYSTEM_INTEGRITY_VIOLATION.log"
    if [ -f "$ALARM_FILE" ]; then
        AIDE_STATUS=$(head -n 1 "$ALARM_FILE")
        if grep -q "КРИТИЧЕСКАЯ ТРЕВОГА" "$ALARM_FILE"; then
            echo -e "   \033[1;36m[AIDE Status]:\033[0m \033[1;31m$AIDE_STATUS\033[0m"
        else
            echo -e "   \033[1;36m[AIDE Status]:\033[0m All System Integrity Checks - \033[1;32mNOMINAL\033[0m"
        fi
    else
        echo -e "   \033[1;36m[AIDE Status]:\033[0m Initializing... - \033[1;33mSTANDBY\033[0m"
    fi

    # SuperRoot Status
    if grep -q "|/bin/false" /proc/sys/kernel/core_pattern 2>/dev/null; then
        echo -e "   \033[1;36m[SuperRoot Mode]:\033[0m Core Kernel Integrity - \033[1;31mACTIVE (Super-Paranoia)\033[0m"
    else
        echo -e "   \033[1;36m[SuperRoot Mode]:\033[0m Core Kernel Integrity - \033[1;32mDEACTIVATED (Normal/Maintenance)\033[0m"
    fi

    # Display Current User
    if [ "$USER" == "super_admin" ]; then
        echo -e "\n\033[1;31m🔑 КРИТИЧЕСКИЙ УРОВЕНЬ: Вы вошли как SUPER_ADMIN.\033[0m"
    elif [ "$USER" == "secure_user" ]; then
        echo -e "\n\033[1;33m🔒 УРОВЕНЬ SECURE: Вы вошли как SECURE_USER.\033[0m"
    elif [ "$USER" == "normal_user" ]; then
        echo -e "\n\033[1;32m🟢 УРОВЕНЬ GUEST: Вы вошли как NORMAL_USER (Анечка).\033[0m"
    fi

    echo -e "\033[1;31m------------------------------------------------------------\033[0m\n"
}
'

# 2. Append the function and call to /etc/bash.bashrc
# Удаляем старую версию (если есть)
sed -i '/^# --- \[Section: Critical Monitoring and Alerts\] ---/,/^}/d' "$BASHRC_FILE"
sed -i '/display_paranoia_motd/d' "$BASHRC_FILE"

# Добавляем новую функцию
echo -e "$MOTD_FUNCTION" >> "$BASHRC_FILE"
echo 'display_paranoia_motd' >> "$BASHRC_FILE"
echo "✅ Функция MOTD добавлена в $BASHRC_FILE."

echo "====================================================="
echo "✅ MOTD настроен. Проверьте, открыв новый терминал."
