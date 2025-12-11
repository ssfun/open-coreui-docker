#!/bin/bash
set -e

# 设置默认环境变量
export HOST=${HOST:-0.0.0.0}
export PORT=${PORT:-8168}

echo "--- Open CoreUI Docker Launcher (Debian) ---"
echo "Current Time: $(date)"

# 1. 写入 Crontab
echo "Setting up cron job..."
# 导出环境变量 (R2配置 + 时区) 到 /etc/environment，这样 Cron 才能读到
printenv | grep -E "R2_|TZ" > /etc/environment

# 写入 Cron 任务文件
# 每天 02:00 和 14:00 执行备份
echo "0 2,14 * * * root /bin/bash /app/backup.sh backup >> /var/log/backup.log 2>&1" > /etc/cron.d/backup-job
# 设置权限 (必须)
chmod 0644 /etc/cron.d/backup-job

# 2. 启动时尝试恢复
/bin/bash /app/backup.sh restore

# 3. 启动 Cron 服务
# Debian 下 cron 需要在后台运行，但作为 docker 服务我们通常让它 fork
service cron start

# 4. 启动主程序
echo "Starting Open CoreUI..."
exec /app/open-coreui
