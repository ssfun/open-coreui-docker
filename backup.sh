#!/bin/bash

# 从 /etc/environment 读取环境变量（cron 环境需要）
if [ -f /etc/environment ]; then
    set -a
    source /etc/environment
    set +a
fi

# Cloudflare R2 / AWS S3 配置
export AWS_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}"
export AWS_DEFAULT_REGION="auto"
export AWS_ENDPOINT_URL="${R2_ENDPOINT_URL}"
export BUCKET_NAME="${R2_BUCKET_NAME}"

# Open CoreUI 数据路径
DATA_DIR="/app/data"
DB_FILE="${DATA_DIR}/data.sqlite3"
BACKUP_PREFIX="opencoreui_backup_"

# 检查必要配置
if [ -z "$R2_ACCESS_KEY_ID" ] || [ -z "$R2_SECRET_ACCESS_KEY" ] || [ -z "$R2_ENDPOINT_URL" ] || [ -z "$R2_BUCKET_NAME" ]; then
    echo "[Backup] Warning: R2/S3 environment variables are not set. Skipping backup/restore."
    exit 0
fi

restore_backup() {
    echo "[Restore] Checking for latest backup in S3/R2..."
    
    # 获取最新的备份文件名
    LATEST_BACKUP=$(aws s3 ls "s3://${BUCKET_NAME}/backups/${BACKUP_PREFIX}" 2>/dev/null | sort | tail -n 1 | awk '{print $4}')
    
    if [ -n "$LATEST_BACKUP" ]; then
        echo "[Restore] Found backup: ${LATEST_BACKUP}"
        echo "[Restore] Downloading..."
        aws s3 cp "s3://${BUCKET_NAME}/backups/${LATEST_BACKUP}" /tmp/backup.tar.gz
        
        if [ -f "/tmp/backup.tar.gz" ]; then
            echo "[Restore] Extracting to ${DATA_DIR}..."
            rm -rf "${DATA_DIR:?}"/*
            tar -xzf "/tmp/backup.tar.gz" -C "${DATA_DIR}"
            rm "/tmp/backup.tar.gz"
            echo "[Restore] Success!"
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

    echo "[Backup] Starting backup job: ${TIMESTAMP}"

    # 1. 准备临时目录（确保清空）
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"

    # 2. 先复制所有非数据库文件
    echo "[Backup] Copying static files..."
    cd "$DATA_DIR"
    for item in *; do
        if [ "$item" != "data.sqlite3" ] && [ "$item" != "data.sqlite3-wal" ] && [ "$item" != "data.sqlite3-shm" ]; then
            cp -r "$item" "$TEMP_DIR/" 2>/dev/null || true
        fi
    done

    # 3. 数据库热备份 (VACUUM INTO 生成无锁快照) - 只执行一次
    if [ -f "$DB_FILE" ]; then
        echo "[Backup] Snapshotting SQLite database..."
        sqlite3 "$DB_FILE" "VACUUM INTO '$TEMP_DIR/data.sqlite3'"
        if [ $? -ne 0 ]; then
            echo "[Backup] Error: Database snapshot failed!"
            rm -rf "$TEMP_DIR"
            exit 1
        fi
    fi

    # 4. 压缩
    echo "[Backup] Compressing..."
    cd "$TEMP_DIR" && tar -czf "/tmp/${BACKUP_FILENAME}" .

    # 5. 上传
    echo "[Backup] Uploading to S3/R2..."
    if aws s3 cp "/tmp/${BACKUP_FILENAME}" "s3://${BUCKET_NAME}/backups/${BACKUP_FILENAME}"; then
        echo "[Backup] Upload complete."
    else
        echo "[Backup] Error: Upload failed!"
        echo "[Backup] Debug - Endpoint: $AWS_ENDPOINT_URL"
        echo "[Backup] Debug - Bucket: $BUCKET_NAME"
        echo "[Backup] Debug - Key ID length: ${#AWS_ACCESS_KEY_ID}"
        rm "/tmp/${BACKUP_FILENAME}"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    # 6. 清理本地缓存
    rm "/tmp/${BACKUP_FILENAME}"
    rm -rf "$TEMP_DIR"

    # 7. 轮转：删除 7 天前的备份
    echo "[Backup] Rotating old backups..."
    OLD_DATE=$(date -d "7 days ago" +%Y%m%d 2>/dev/null || date -v-7d +%Y%m%d)
    
    aws s3 ls "s3://${BUCKET_NAME}/backups/${BACKUP_PREFIX}" 2>/dev/null | while read -r line; do
        file_name=$(echo "$line" | awk '{print $4}')
        file_date=$(echo "$file_name" | grep -oE "[0-9]{8}" | head -1)
        if [ -n "$file_date" ] && [ "$file_date" -lt "$OLD_DATE" ]; then
            echo "[Backup] Deleting old backup: $file_name"
            aws s3 rm "s3://${BUCKET_NAME}/backups/$file_name"
        fi
    done
    
    echo "[Backup] All done!"
}

case "$1" in
    "restore")
        restore_backup
        ;;
    "backup")
        create_backup
        ;;
    "test")
        echo "[Test] Testing S3/R2 connection..."
        echo "[Test] Endpoint: $AWS_ENDPOINT_URL"
        echo "[Test] Bucket: $BUCKET_NAME"
        echo "[Test] Key ID: ${AWS_ACCESS_KEY_ID:0:5}..."
        aws s3 ls "s3://${BUCKET_NAME}/" --max-items 1
        ;;
    *)
        echo "Usage: $0 {backup|restore|test}"
        exit 1
        ;;
esac
