#!/bin/bash

# 导入环境变量 (兼容 Docker 环境)
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
    LATEST_BACKUP=$(aws s3 ls "s3://${BUCKET_NAME}/backups/${BACKUP_PREFIX}" | sort | tail -n 1 | awk '{print $4}')
    
    if [ -n "$LATEST_BACKUP" ]; then
        echo "[Restore] Found backup: ${LATEST_BACKUP}"
        echo "[Restore] Downloading..."
        aws s3 cp "s3://${BUCKET_NAME}/backups/${LATEST_BACKUP}" /tmp/backup.tar.gz
        
        if [ -f "/tmp/backup.tar.gz" ]; then
            echo "[Restore] Extracting to ${DATA_DIR}..."
            # 清空现有数据（慎重，但恢复通常意味着覆盖）
            rm -rf "${DATA_DIR:?}"/*
            # 解压
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

    # 1. 准备临时目录
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"

    # 2. 数据库热备份 (VACUUM INTO 生成无锁快照)
    if [ -f "$DB_FILE" ]; then
        echo "[Backup] Snapshotting SQLite database..."
        sqlite3 "$DB_FILE" "VACUUM INTO '$TEMP_DIR/data.sqlite3'"
    fi

    # 3. 复制其他文件 (如 uploads 目录, 排除正在运行的数据库文件)
    echo "[Backup] Copying static files..."
    # 使用 rsync 或 cp 复制除了 data.sqlite3 以外的所有内容
    # 这里简单地复制整个目录，然后用刚才的热备份覆盖数据库文件，确保一致性
    cp -r "$DATA_DIR/." "$TEMP_DIR/"
    # 再次确保使用的是热备份的数据库文件
    if [ -f "$DB_FILE" ]; then
        sqlite3 "$DB_FILE" "VACUUM INTO '$TEMP_DIR/data.sqlite3'"
    fi

    # 4. 压缩
    echo "[Backup] Compressing..."
    cd "$TEMP_DIR" && tar -czf "/tmp/${BACKUP_FILENAME}" .
    
    # 5. 上传
    echo "[Backup] Uploading to S3/R2..."
    aws s3 cp "/tmp/${BACKUP_FILENAME}" "s3://${BUCKET_NAME}/backups/${BACKUP_FILENAME}"
    
    # 6. 清理本地缓存
    rm "/tmp/${BACKUP_FILENAME}"
    rm -rf "$TEMP_DIR"
    echo "[Backup] Upload complete."

    # 7. 轮转：删除 7 天前的备份
    echo "[Backup] Rotating old backups..."
    # 计算7天前的日期整数 (例如 20231001)
    OLD_DATE=$(date -d "7 days ago" +%Y%m%d)
    
    aws s3 ls "s3://${BUCKET_NAME}/backups/${BACKUP_PREFIX}" | while read -r line; do
        file_name=$(echo "$line" | awk '{print $4}')
        # 从文件名提取日期 (opencoreui_backup_20231001_120000.tar.gz -> 20231001)
        file_date=$(echo "$file_name" | grep -oE "[0-9]{8}" | head -1)
        
        if [ -n "$file_date" ] && [ "$file_date" -lt "$OLD_DATE" ]; then
            echo "[Backup] Deleting old backup: $file_name"
            aws s3 rm "s3://${BUCKET_NAME}/backups/$file_name"
        fi
    done
}

case "$1" in
    "restore")
        restore_backup
        ;;
    "backup")
        create_backup
        ;;
    *)
        echo "Usage: $0 {backup|restore}"
        exit 1
        ;;
esac
