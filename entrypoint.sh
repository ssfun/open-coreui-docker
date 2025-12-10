#!/bin/bash
set -e

# 设置默认环境变量
export HOST=${HOST:-0.0.0.0}
export PORT=${PORT:-8168}

echo "--- Open CoreUI Docker Launcher ---"

# 1. 写入 Crontab (每天凌晨 2 点和下午 2 点备份)
# 注意：必须导出环境变量给 cron 执行的脚本，否则脚本读不到 R2 配置
echo "Setting up cron job..."
printenv | grep "R2_" > /etc/environment
echo "0 2,14 * * * /bin/bash /app/backup.sh backup >> /var/log/backup.log 2>&1" > /etc/cron.d/backup-job
chmod 0644 /etc/cron.d/backup-job
crontab /etc/cron.d/backup-job

# 2. 启动时尝试恢复
/bin/bash /app/backup.sh restore

# 3. 启动 Cron 服务 (Debian 方式)
cron

# 4. 启动主程序
echo "Starting Open CoreUI..."
exec /app/open-coreui
