#!/bin/bash

# --- КОНФИГУРАЦИЯ ---
BIN_DIR="/usr/local/bin"
SERVICE_NAME="warp-tunnel.service"
WARP_CONF="$BIN_DIR/wgcf-profile.conf"
TUNNEL_SCRIPT="$BIN_DIR/warp-tunnel.sh"
WATCHDOG_SCRIPT="$BIN_DIR/warp-watchdog.sh"
WGCF_BIN="$BIN_DIR/wgcf"

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   echo "Этот скрипт должен быть запущен от имени root (sudo)." 
   exit 1
fi

echo "--- Начинается деинсталляция WARP-Wrap ---"

# 1. Остановка и отключение сервиса
echo "Остановка сервиса $SERVICE_NAME..."
if systemctl is-active --quiet $SERVICE_NAME; then
    systemctl stop $SERVICE_NAME
fi
systemctl disable $SERVICE_NAME 2>/dev/null

# 2. Удаление файла сервиса
echo "Удаление файлов systemd..."
rm -f /etc/systemd/system/$SERVICE_NAME
systemctl daemon-reload

# 3. Удаление задачи из Cron
echo "Очистка планировщика cron..."
(crontab -l 2>/dev/null | grep -v "warp-watchdog.sh") | crontab -

# 4. Удаление исполняемых файлов и конфигов
echo "Удаление скриптов и конфигураций из $BIN_DIR..."
rm -f $TUNNEL_SCRIPT
rm -f $WATCHDOG_SCRIPT
rm -f $WARP_CONF
rm -f $WGCF_BIN
rm -f "$BIN_DIR/wgcf-account.toml" # Остаточные файлы аккаунта wgcf

# 5. Финальная проверка сетевых правил
echo "Очистка оставшихся правил маршрутизации..."
# Пытаемся удалить правила по приоритетам, если они зависли
while ip rule del priority 90 2>/dev/null; do :; done
while ip rule del priority 100 2>/dev/null; do :; done
ip route flush table 51820 2>/dev/null

echo "-------------------------------------------------------"
echo "ДЕИНСТАЛЛЯЦИЯ ЗАВЕРШЕНА"
echo "Все компоненты туннеля удалены."
echo "Установленные пакеты (wireguard, jq и т.д.) сохранены."
echo "-------------------------------------------------------"