#!/bin/bash
set -e

# 设置默认环境变量
export HOST=${HOST:-0.0.0.0}
export PORT=${PORT:-8168}

echo "--- Open CoreUI Docker Launcher (Alpine) ---"
echo "Current Time: $(date)"

# 1. 写入 Crontab (Alpine 方式)
echo "Setting up cron job..."
# 导出环境变量供 cron 使用
printenv | grep -E "R2_|TZ" > /etc/environment

# 写入 root 用户的 crontab
# Alpine 的 crond 默认读取 /var/spool/cron/crontabs/
mkdir -p /var/spool/cron/crontabs
echo "0 2,14 * * * /bin/bash /app/backup.sh backup >> /var/log/backup.log 2>&1" > /var/spool/cron/crontabs/root

# 2. 启动时尝试恢复
/bin/bash /app/backup.sh restore

# 3. 启动 Crond (后台运行)
# -b: background, -l 8: log level (warning only)
crond -b -l 8

# 4. 启动主程序
echo "Starting Open CoreUI..."
exec /app/open-coreui
