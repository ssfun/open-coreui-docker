#!/bin/bash
set -e

export HOST=${HOST:-0.0.0.0}
export PORT=${PORT:-8168}

echo "--- Open CoreUI Docker Launcher ---"

# 1. 写入环境变量供 cron 使用（更安全的方式）
echo "Setting up cron job..."

# 使用更安全的方式写入环境变量，处理特殊字符
{
    echo "R2_ACCESS_KEY_ID='${R2_ACCESS_KEY_ID}'"
    echo "R2_SECRET_ACCESS_KEY='${R2_SECRET_ACCESS_KEY}'"
    echo "R2_ENDPOINT_URL='${R2_ENDPOINT_URL}'"
    echo "R2_BUCKET_NAME='${R2_BUCKET_NAME}'"
} > /etc/environment

# 设置 cron job
echo "0 2,14 * * * /bin/bash /app/backup.sh backup >> /var/log/backup.log 2>&1" > /etc/cron.d/backup-job
chmod 0644 /etc/cron.d/backup-job
crontab /etc/cron.d/backup-job

# 2. 启动时尝试恢复
/bin/bash /app/backup.sh restore

# 3. 启动 Cron 服务
cron

# 4. 启动主程序
echo "Starting Open CoreUI..."
exec /app/open-coreui
