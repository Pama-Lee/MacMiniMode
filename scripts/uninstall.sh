#!/bin/bash
# 卸载 Mac mini 模式并恢复正常睡眠。用法：sudo ./uninstall.sh
# Uninstalls Mac mini Mode and restores normal sleep. Usage: sudo ./uninstall.sh
set -uo pipefail

if [ "$(id -u)" != "0" ]; then
    echo "请用 sudo 运行 / Run with sudo: sudo $0" >&2
    exit 1
fi

CONSOLE_UID=$(stat -f %u /dev/console)

if [ "$CONSOLE_UID" != "0" ]; then
    launchctl bootout "gui/$CONSOLE_UID/com.macminimode.menubar" 2>/dev/null
fi
launchctl bootout system/com.macminimode.daemon 2>/dev/null

rm -f /Library/LaunchAgents/com.macminimode.menubar.plist \
      /Library/LaunchDaemons/com.macminimode.daemon.plist \
      /Library/PrivilegedHelperTools/macmini-moded \
      /var/db/macmini-mode \
      /var/log/macmini-mode.log /var/log/macmini-mode.log.1
# 只删我们自己建的那个软链接。
[ -L /usr/local/bin/macminimode ] && rm -f /usr/local/bin/macminimode
rm -rf /Applications/MacMiniMode.app
pkgutil --forget com.macminimode.pkg >/dev/null 2>&1

pmset -a disablesleep 0

echo "已卸载，睡眠设置已恢复 / Uninstalled, sleep settings restored:"
pmset -g | grep SleepDisabled
