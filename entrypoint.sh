#!/bin/bash
set -e

echo "=========================================="
echo "Open-CoreUI with R2 Backup"
echo "=========================================="

# 配置 rclone
configure_rclone() {
    echo "[INFO] Configuring rclone for Cloudflare R2..."
    
    mkdir -p ~/.config/rclone
    
    cat > ~/.config/rclone/rclone.conf << EOF
[r2]
type = s3
provider = Cloudflare
access_key_id = ${R2_ACCESS_KEY_ID}
secret_access_key = ${R2_SECRET_ACCESS_KEY}
endpoint = https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com
acl = private
EOF

    echo "[INFO] Rclone configured successfully"
}

# 检查必要的环境变量
check_r2_config() {
    if [ -z "$R2_ACCOUNT_ID" ] || [ -z "$R2_ACCESS_KEY_ID" ] || \
       [ -z "$R2_SECRET_ACCESS_KEY" ] || [ -z "$R2_BUCKET_NAME" ]; then
        echo "[WARN] R2 configuration incomplete, backup/restore disabled"
        return 1
    fi
    return 0
}

# 主流程
main() {
    # 创建日志文件
    touch /var/log/backup.log
    
    # 检查 R2 配置
    if check_r2_config; then
        # 配置 rclone
        configure_rclone
        
        # 启动时还原最新备份
        echo "[INFO] Attempting to restore latest backup..."
        /app/restore.sh || echo "[WARN] Restore failed or no backup found, starting fresh"
        
        # 启动 supercronic 定时任务（后台运行）
        echo "[INFO] Starting backup scheduler..."
        supercronic /app/crontab &
        CROND_PID=$!
        echo "[INFO] Backup scheduler started (PID: $CROND_PID)"
    else
        echo "[WARN] Skipping backup/restore functionality"
    fi
    
    # 启动主应用
    echo "[INFO] Starting Open-CoreUI..."
    exec /app/open-coreui
}

main "$@"
