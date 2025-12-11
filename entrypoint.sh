#!/bin/bash
set -e

echo "=========================================="
echo "Open-CoreUI with R2 Backup"
echo "Started at: $(date)"
echo "=========================================="

# 配置 rclone
configure_rclone() {
    echo "[INFO] Configuring rclone..."
    mkdir -p /root/.config/rclone
    cat > /root/.config/rclone/rclone.conf << EOF
[r2]
type = s3
provider = Cloudflare
access_key_id = ${R2_ACCESS_KEY_ID}
secret_access_key = ${R2_SECRET_ACCESS_KEY}
endpoint = https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com
acl = private
no_check_bucket = true
EOF
}

# 配置 cron
configure_cron() {
    echo "[INFO] Configuring cron..."
    cat > /etc/cron.d/backup << EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
R2_ACCOUNT_ID=${R2_ACCOUNT_ID}
R2_ACCESS_KEY_ID=${R2_ACCESS_KEY_ID}
R2_SECRET_ACCESS_KEY=${R2_SECRET_ACCESS_KEY}
R2_BUCKET_NAME=${R2_BUCKET_NAME}
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}

# 每天凌晨2点和下午2点备份
0 2 * * * root /app/backup.sh >> /var/log/backup.log 2>&1
0 14 * * * root /app/backup.sh >> /var/log/backup.log 2>&1
EOF
    chmod 644 /etc/cron.d/backup
    touch /var/log/backup.log
}

# 检查 R2 配置
check_r2_config() {
    [ -n "$R2_ACCOUNT_ID" ] && [ -n "$R2_ACCESS_KEY_ID" ] && \
    [ -n "$R2_SECRET_ACCESS_KEY" ] && [ -n "$R2_BUCKET_NAME" ]
}

# 主流程
if check_r2_config; then
    configure_rclone
    configure_cron
    
    # 启动前恢复（应用未启动，安全）
    echo "[INFO] Checking for backup to restore..."
    /app/restore.sh || echo "[WARN] No backup restored"
    
    # 启动 cron 后台运行
    echo "[INFO] Starting cron..."
    cron
else
    echo "[WARN] R2 not configured, backup disabled"
fi

# 启动主应用（前台）
echo "[INFO] Starting Open-CoreUI..."
exec /app/open-coreui
