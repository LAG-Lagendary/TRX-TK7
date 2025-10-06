#!/bin/bash

# =========================================================================
# ULTIMATE PARANOIA SYSTEM SETUP (MASTER SCRIPT)
# Единый скрипт для полной настройки системы: База, Логирование, AppArmor,
# SuperRoot, UFW Kill Switch, Suricata, и финальные исправления GRUB.
# =========================================================================

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo "🚨 Этот скрипт ДОЛЖЕН быть запущен от имени root или с помощью sudo."
    exit 1
fi

echo "================================================================="
echo "💥 НАЧАЛО ПОЛНОЙ УСТАНОВКИ ULTIMATE PARANOIA SYSTEM 💥"
echo "================================================================="

# -----------------------------------------------------------------
# --- БЛОК 1: ПОЛЬЗОВАТЕЛИ, УТИЛИТЫ, СИСТЕМА И ЯДРО (Sysctl)
# -----------------------------------------------------------------
echo "⚙️ Шаг 1: Настройка пользователей и установка базовых утилит..."

# 1. Настройка пользователей
adduser secure_user --disabled-password --gecos ""
usermod -aG sudo secure_user
adduser normal_user --disabled-password --gecos ""
adduser super_admin --disabled-password --gecos ""
usermod -aG sudo super_admin
echo "!!! Установите пароли для secure_user, normal_user и super_admin вручную после выполнения скрипта !!!"

# 2. Обновление и установка утилит
apt update && apt upgrade -y
# Основные утилиты
apt install -y htop net-tools iperf3 ethtool linux-cpupower util-linux ksystemstats sysstat ksysguard
# Инструменты анализа/мониторинга
apt install -y wireshark synaptic baobab
# Сетевые и системные
apt install -y vim tmux screen curl wget unzip python3 python3-pip iftop vnstat
# Безопасность
apt install -y openssh-server ufw aide apparmor apparmor-utils netfilter-persistent
# Дополнительные инструменты
apt install -y libreoffice fuse3

# 3. Установка netsniff-ng (для Masking Traffic Generator)
apt install -y netsniff-ng

# 4. Установка Suricata (IDS)
echo "🛡️ Установка Suricata (Система Обнаружения Вторжений)..."
apt install -y suricata
systemctl enable suricata
systemctl start suricata
echo "✅ Suricata установлена и запущена."

# 5. Настройка ядра (Sysctl)
echo "⚙️ Настройка параметров ядра (Sysctl) для агрессивной сетевой защиты..."
SYSCTL_CONF="/etc/sysctl.d/99-rocket.conf"
cat <<EOF > "$SYSCTL_CONF"
# --- Настройки для Производительности и Сетевой Агрессии ---
# net.ipv4.* - Увеличение сетевых лимитов и защиты
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.log_martians = 1

# net.core.* - Очереди и соединения
net.core.netdev_max_backlog = 4096
net.core.somaxconn = 4096

# fs.* - Увеличение лимитов системы
fs.file-max = 1048576
EOF
sysctl -p "$SYSCTL_CONF"


# -----------------------------------------------------------------
# --- БЛОК 2: UFW, RSYSLOG И LOGROTATE
# -----------------------------------------------------------------
echo "⚙️ Шаг 2: Настройка UFW Kill Switch, Логирования и Logrotate..."

# 1. Настройка UFW Kill Switch (Запрет всего, кроме VPN/TOR)
ufw default deny incoming
ufw default deny outgoing
ufw enable

# Настройка VPN/TOR исключений (ВАЖНО: Предполагается OpenVPN/Wireguard)
VPN_PORT="1194" # Стандартный порт OpenVPN. Если ваш VPN использует другой, измените!
TOR_PORTS="9001 9030" # Стандартные порты TOR-реле

# Разрешаем исходящий VPN-трафик
ufw allow out $VPN_PORT/udp comment 'Allow VPN connection port'
ufw allow out $VPN_PORT/tcp comment 'Allow VPN connection port'

# Разрешаем TOR-трафик
for PORT in $TOR_PORTS; do
    ufw allow out $PORT comment "Allow TOR traffic port $PORT"
done
echo "✅ UFW: Активирован Kill Switch. Разрешен только исходящий трафик для VPN ($VPN_PORT) и TOR ($TOR_PORTS)."

# 2. Настройка Rsyslog для централизованного логирования
echo "⚙️ Настройка Rsyslog для централизованного логирования..."
# Создаем файл конфигурации, который отправляет все логи в один файл
RSYSLOG_CONF="/etc/rsyslog.d/50-security-logs.conf"
cat <<EOF > "$RSYSLOG_CONF"
# Отправляем все критические сообщения в один файл
:msg, contains, "CRITICAL ALARM" -/var/log/security/critical_alerts.log
:msg, contains, "UFW" -/var/log/security/ufw_activity.log
:msg, contains, "AppArmor" -/var/log/security/apparmor_activity.log
& stop
# Все остальные сообщения
*.* /var/log/security/all_system_activity.log
EOF
mkdir -p /var/log/security
chmod 700 /var/log/security
systemctl restart rsyslog
echo "✅ Rsyslog настроен. Все логи идут в /var/log/security."

# 3. Настройка Logrotate
echo "⚙️ Настройка Logrotate..."
LOGROTATE_CONF="/etc/logrotate.d/security_logs"
cat <<EOF > "$LOGROTATE_CONF"
/var/log/security/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root adm
    sharedscripts
    postrotate
        systemctl reload rsyslog.service
    endscript
}
EOF
echo "✅ Logrotate настроен для еженедельной ротации логов безопасности."


# -----------------------------------------------------------------
# --- БЛОК 3: SUPERROOT (СУПЕРРУТ) И АВТОМАТИЧЕСКАЯ ИЗОЛЯЦИЯ APPAMOR
# -----------------------------------------------------------------
echo "🛡️ Шаг 3: Настройка 'СуперРута' и автоматическая изоляция утилит..."

# 1. Настройка скрипта super_k
SUPER_K_SCRIPT="/usr/local/sbin/super_k"
cat <<EOF > "$SUPER_K_SCRIPT"
#!/bin/bash
# super_k: Скрипт для управления защитой ядра (SuperRoot)

# Файлы-блокировки ядра
K_LOCK1="/proc/sys/kernel/core_pattern"
K_LOCK2="/proc/sys/kernel/kexec_load_disabled"
K_LOCK3="/proc/sys/kernel/perf_event_paranoid"

# Значения для активации (max paranoia)
LOCK_VAL1="|/bin/false"
LOCK_VAL2="1"
LOCK_VAL3="3"

# Значения для деактивации (для обслуживания)
UNLOCK_VAL1="core"
UNLOCK_VAL2="0"
UNLOCK_VAL3="0"

if [ "\$EUID" -ne 0 ]; then
    echo "🚨 Доступ только для root/sudo. Запуск от имени: \$USER"
    exit 1
fi

if [ "\$1" == "activate" ]; then
    echo "🔥 АКТИВАЦИЯ РЕЖИМА SUPERROOT: Блокировка ядра..."
    echo "\$LOCK_VAL1" > \$K_LOCK1
    echo "\$LOCK_VAL2" > \$K_LOCK2
    echo "\$LOCK_VAL3" > \$K_LOCK3
    /usr/sbin/aa-enforce /etc/apparmor.d/* # Включаем все AppArmor профили
    echo "✅ Ядро заблокировано. AppArmor в режиме enforce."
    echo "⚠️ ПРЕДУПРЕЖДЕНИЕ: Выход из системы ДОЛЖЕН сопровождаться 'super_k deactivate'."
elif [ "\$1" == "deactivate" ]; then
    echo "🔓 ДЕАКТИВАЦИЯ РЕЖИМА SUPERROOT: Разблокировка ядра..."
    echo "\$UNLOCK_VAL1" > \$K_LOCK1
    echo "\$UNLOCK_VAL2" > \$K_LOCK2
    echo "\$UNLOCK_VAL3" > \$K_LOCK3
    /usr/sbin/aa-complain /etc/apparmor.d/* # Переводим все AppArmor в режим complain
    echo "✅ Ядро разблокировано. AppArmor в режиме complain (для обслуживания)."
else
    echo "Использование: sudo super_k [activate|deactivate]"
fi
EOF
chmod +x "$SUPER_K_SCRIPT"
echo "✅ Скрипт super_k создан: $SUPER_K_SCRIPT"

# 2. Изоляция Wireshark (Разрешаем сеть, запрещаем домашний каталог)
echo "🛡️ Автоматическая изоляция Wireshark (только сеть, без файлов)..."
WIRESHARK_PROFILE="/etc/apparmor.d/usr.bin.wireshark"

# Создание профиля с нуля
cat <<EOF > "$WIRESHARK_PROFILE"
#include <tunables/global>

/usr/bin/wireshark {
  #include <abstractions/base>
  #include <abstractions/consoles>
  #include <abstractions/gnome>
  #include <abstractions/nameservice>
  #include <abstractions/X>

  # Разрешить доступ к сети (критически важно для Wireshark)
  network,

  # Запретить доступ к домашним каталогам пользователей (КРИТИЧЕСКАЯ ИЗОЛЯЦИЯ)
  # Эта строка блокирует доступ к /home/user, что не дает украсть файлы
  deny @{HOME}/** rwk,

  # Разрешить только чтение и выполнение самого Wireshark
  /usr/bin/wireshark mr,

  # Разрешить доступ к устройствам захвата (НЕОБХОДИМО)
  /dev/net/packet rw,
  /dev/net/tun rw,

  # Прочее, что нужно для запуска GUI
  /usr/lib/x86_64-linux-gnu/wireshark/** rmix,
  /usr/share/wireshark/** r,

  # Разрешить запись только во временные каталоги (для .pcap)
  /tmp/** rw,
}
EOF
/usr/sbin/aa-enforce /usr/bin/wireshark
echo "✅ AppArmor: Wireshark изолирован. Доступ к сети разрешен, доступ к домашним файлам запрещен."

# 3. Изоляция Remmina (Запрет сети, но разрешаем домашний каталог)
echo "🛡️ Автоматическая изоляция Remmina (только файлы, без сети)..."
REMMINA_PROFILE="/etc/apparmor.d/usr.bin.remmina"

cat <<EOF > "$REMMINA_PROFILE"
#include <tunables/global>

/usr/bin/remmina {
  #include <abstractions/base>
  #include <abstractions/nameservice>
  #include <abstractions/X>

  # Запретить любой сетевой доступ (КРИТИЧЕСКАЯ ИЗОЛЯЦИЯ)
  deny network,

  # Разрешить доступ к домашним каталогам (для сохранения профилей/конфигов)
  @{HOME}/** rwk,

  # Разрешить только чтение и выполнение самой Remmina
  /usr/bin/remmina mr,

  # Остальные разрешения Remmina
  /usr/lib/x86_64-linux-gnu/remmina/** rmix,
  /usr/share/remmina/** r,
}
EOF
/usr/sbin/aa-enforce /usr/bin/remmina
echo "✅ AppArmor: Remmina изолирована. Доступ к сети запрещен, доступ к домашним файлам разрешен."


# -----------------------------------------------------------------
# --- БЛОК 4: ФИНАЛЬНАЯ КОРРЕКЦИЯ GRUB (ДЛЯ ASCII Art и AppArmor)
# -----------------------------------------------------------------
echo "⚙️ Шаг 4: Финальная коррекция GRUB для AppArmor и ASCII Art..."
GRUB_CONFIG="/etc/default/grub"
GRUB_CMDLINE_CORE="apparmor=1 security=apparmor"

if [ -f "$GRUB_CONFIG" ]; then
    # 1. Добавляем/убеждаемся в наличии apparmor=1 security=apparmor
    # Удаляем старую строку, чтобы избежать дублирования
    sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/ s/apparmor=1//g" "$GRUB_CONFIG"
    sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/ s/security=apparmor//g" "$GRUB_CONFIG"

    # Добавляем нужные параметры
    if ! grep -q "$GRUB_CMDLINE_CORE" "$GRUB_CONFIG"; then
        # Ищем строку GRUB_CMDLINE_LINUX_DEFAULT="X" и вставляем $GRUB_CMDLINE_CORE перед закрывающей кавычкой
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 '$GRUB_CMDLINE_CORE'\"/' "$GRUB_CONFIG"
        echo "-> Добавлены параметры AppArmor в GRUB_CMDLINE_LINUX_DEFAULT."
    fi

    # 2. Убеждаемся, что 'quiet' и 'splash' удалены (Для ASCII Art и логов)
    sed -i 's/quiet//g' "$GRUB_CONFIG"
    sed -i 's/splash//g' "$GRUB_CONFIG"
    echo "-> Удалены 'quiet' и 'splash' для видимости логов и ASCII Art."

    # 3. Добавляем GRUB_TERMINAL=console (Для ASCII Art)
    if ! grep -q "GRUB_TERMINAL=console" "$GRUB_CONFIG"; then
        echo "GRUB_TERMINAL=console" >> "$GRUB_CONFIG"
        echo "-> Добавлен GRUB_TERMINAL=console для корректного отображения ASCII Art."
    fi

    # 4. Обновление GRUB
    update-grub
    echo "✅ GRUB обновлен."
fi

# -----------------------------------------------------------------
# --- ФИНАЛИЗАЦИЯ И ИНСТРУКЦИИ
# -----------------------------------------------------------------
echo "================================================================="
echo "✅ ОСНОВНАЯ УСТАНОВКА ЗАВЕРШЕНА. ТРЕБУЕТСЯ ПЕРЕЗАГРУЗКА."
echo "================================================================="
echo "!!! ДАЛЬНЕЙШИЕ ШАГИ !!!"
echo "1. Установите пароли для secure_user, normal_user и super_admin (sudo passwd <user>)."
echo "2. Запустите скрипты ловушек (AIDE, психологическая, TShark) и MOTD."
echo "3. Запустите скрипт установки инструментов разработки (по желанию)."
echo "4. Перезагрузите систему: sudo reboot"
