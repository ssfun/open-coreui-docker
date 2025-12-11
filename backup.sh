#!/bin/bash

# --- 1. Rclone 动态配置 ---
# Rclone 支持通过环境变量直接定义配置，无需生成配置文件
# 定义一个名为 'r2' 的远程连接
export RCLONE_CONFIG_R2_TYPE="s3"
export RCLONE_CONFIG_R2_PROVIDER="Cloudflare"
export RCLONE_CONFIG_R2_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}"
export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}"
export RCLONE_CONFIG_R2_ENDPOINT="${R2_ENDPOINT_URL}"
export RCLONE_CONFIG_R2_ACL="private"

DATA_DIR="/app/data"
DB_FILE="${DATA_DIR}/data.sqlite3"
BACKUP_PREFIX="opencoreui_backup_"
REMOTE_PATH="r2:${R2_BUCKET_NAME}/backups"

# 检查配置
if [ -z "$R2_ACCESS_KEY_ID" ] || [ -z "$R2_ENDPOINT_URL" ] || [ -z "$R2_BUCKET_NAME" ]; then
    echo "[Backup] Error: R2 env vars missing. Skipping."
    exit 0
fi

# --- 2. 核心功能 ---

restore_backup() {
    echo "[Restore] Checking R2 for backups..."
    # 使用 lsf 获取最新文件 (按时间排序)
    LATEST_BACKUP=$(rclone lsf "$REMOTE_PATH/" --files-only --sort-by t | tail -n 1)
    
    if [ -n "$LATEST_BACKUP" ]; then
        echo "[Restore] Found: ${LATEST_BACKUP}. Downloading..."
        if rclone copy "$REMOTE_PATH/$LATEST_BACKUP" /tmp/; then
            echo "[Restore] Extracting..."
            # 双重保险：确保下载成功
            if [ -f "/tmp/$LATEST_BACKUP" ]; then
                # 清空当前数据 (注意：这会删除未备份的数据)
                rm -rf "${DATA_DIR:?}"/*
                tar -xzf "/tmp/$LATEST_BACKUP" -C "${DATA_DIR}"
                rm "/tmp/$LATEST_BACKUP"
                echo "[Restore] Done! Database restored."
            fi
        else
            echo "[Restore] Download failed."
        fi
    else
        echo "[Restore] No remote backup found. Starting fresh."
    fi
}

create_backup() {
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILENAME="${BACKUP_PREFIX}${TIMESTAMP}.tar.gz"
    TEMP_DIR="/tmp/backup_stage"
    LOCAL_BACKUP_PATH="/tmp/${BACKUP_FILENAME}"

    echo "[Backup] Starting job: ${TIMESTAMP}"
    rm -rf "$TEMP_DIR" "$LOCAL_BACKUP_PATH"
    mkdir -p "$TEMP_DIR"

    # A. 复制文件
    cp -r "$DATA_DIR/." "$TEMP_DIR/"

    # B. SQLite 热备份 (覆盖)
    if [ -f "$DB_FILE" ]; then
        rm -f "$TEMP_DIR/data.sqlite3"
        if ! sqlite3 "$DB_FILE" "VACUUM INTO '$TEMP_DIR/data.sqlite3'"; then
            echo "[Backup] Error: Database backup failed."
            return 1
        fi
    fi

    # C. 压缩
    (cd "$TEMP_DIR" && tar -czf "$LOCAL_BACKUP_PATH" .)
    
    # D. 上传 (Rclone copy)
    echo "[Backup] Uploading to $REMOTE_PATH..."
    if rclone copy "$LOCAL_BACKUP_PATH" "$REMOTE_PATH/"; then
        echo "[Backup] Upload success."
        rm "$LOCAL_BACKUP_PATH"
        rm -rf "$TEMP_DIR"
    else
        echo "[Backup] Upload failed."
        return 1
    fi

    # E. 轮转清理 (Rclone 的杀手级功能: 一行命令删除7天前文件)
    echo "[Backup] Cleaning old backups (>7 days)..."
    rclone delete "$REMOTE_PATH/" --min-age 7d --include "${BACKUP_PREFIX}*"
}

case "$1" in
    "restore") restore_backup ;;
    "backup") create_backup ;;
    *) echo "Usage: $0 {backup|restore}"; exit 1 ;;
esac
