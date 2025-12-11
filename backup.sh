#!/bin/bash

# 导入环境变量
export AWS_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}"
# R2 兼容性通常建议设置为 us-east-1，虽然它是自动的，但某些客户端需要明确的区域
export AWS_DEFAULT_REGION="us-east-1"
export BUCKET_NAME="${R2_BUCKET_NAME}"

# 关键修正：AWS CLI v1 不会自动读取 AWS_ENDPOINT_URL 环境变量，需构造参数
ENDPOINT_ARG=""
if [ -n "$R2_ENDPOINT_URL" ]; then
    ENDPOINT_ARG="--endpoint-url $R2_ENDPOINT_URL"
fi

DATA_DIR="/app/data"
DB_FILE="${DATA_DIR}/data.sqlite3"
BACKUP_PREFIX="opencoreui_backup_"

# 检查必要配置
if [ -z "$R2_ACCESS_KEY_ID" ] || [ -z "$R2_SECRET_ACCESS_KEY" ] || [ -z "$R2_ENDPOINT_URL" ] || [ -z "$R2_BUCKET_NAME" ]; then
    echo "[Backup] Warning: R2/S3 environment variables are not set. Skipping."
    exit 0
fi

restore_backup() {
    echo "[Restore] Checking for latest backup in S3/R2..."
    # 修正：显式添加 endpoint 参数
    LATEST_BACKUP=$(aws $ENDPOINT_ARG s3 ls "s3://${BUCKET_NAME}/backups/${BACKUP_PREFIX}" | sort | tail -n 1 | awk '{print $4}')
    
    if [ -n "$LATEST_BACKUP" ]; then
        echo "[Restore] Found: ${LATEST_BACKUP}. Downloading..."
        aws $ENDPOINT_ARG s3 cp "s3://${BUCKET_NAME}/backups/${LATEST_BACKUP}" /tmp/backup.tar.gz
        
        if [ -f "/tmp/backup.tar.gz" ]; then
            echo "[Restore] Extracting..."
            rm -rf "${DATA_DIR:?}"/*
            tar -xzf "/tmp/backup.tar.gz" -C "${DATA_DIR}"
            rm "/tmp/backup.tar.gz"
            echo "[Restore] Success!"
        else
            echo "[Restore] Download failed."
        fi
    else
        echo "[Restore] No remote backup found."
    fi
}

create_backup() {
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILENAME="${BACKUP_PREFIX}${TIMESTAMP}.tar.gz"
    TEMP_DIR="/tmp/backup_stage"

    echo "[Backup] Starting backup job: ${TIMESTAMP}"

    # 1. 准备目录
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"

    # 2. 修正逻辑：先复制静态文件，再处理数据库
    echo "[Backup] Copying files..."
    cp -r "$DATA_DIR/." "$TEMP_DIR/"

    # 3. 修正逻辑：删除复制过来的“脏”数据库文件，使用 VACUUM 生成干净的快照
    if [ -f "$DB_FILE" ]; then
        echo "[Backup] Snapshotting SQLite database..."
        # 必须先删除目标文件，否则 VACUUM INTO 会报错 "output file already exists"
        rm -f "$TEMP_DIR/data.sqlite3" 
        sqlite3 "$DB_FILE" "VACUUM INTO '$TEMP_DIR/data.sqlite3'"
    fi

    # 4. 压缩
    echo "[Backup] Compressing..."
    # 切换目录以避免压缩包包含绝对路径
    (cd "$TEMP_DIR" && tar -czf "/tmp/${BACKUP_FILENAME}" .)
    
    # 5. 上传 (修正：显式添加 endpoint)
    echo "[Backup] Uploading to S3/R2..."
    aws $ENDPOINT_ARG s3 cp "/tmp/${BACKUP_FILENAME}" "s3://${BUCKET_NAME}/backups/${BACKUP_FILENAME}"
    
    # 6. 清理本地
    rm "/tmp/${BACKUP_FILENAME}"
    rm -rf "$TEMP_DIR"
    
    if [ $? -eq 0 ]; then
        echo "[Backup] Upload complete."
    else
        echo "[Backup] Upload failed!"
        return 1
    fi

    # 7. 轮转旧备份
    echo "[Backup] Rotating old backups..."
    OLD_DATE=$(date -d "7 days ago" +%Y%m%d)
    
    aws $ENDPOINT_ARG s3 ls "s3://${BUCKET_NAME}/backups/${BACKUP_PREFIX}" | while read -r line; do
        file_name=$(echo "$line" | awk '{print $4}')
        file_date=$(echo "$file_name" | grep -oE "[0-9]{8}" | head -1)
        
        if [ -n "$file_date" ] && [ "$file_date" -lt "$OLD_DATE" ]; then
            echo "[Backup] Deleting old backup: $file_name"
            aws $ENDPOINT_ARG s3 rm "s3://${BUCKET_NAME}/backups/$file_name"
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
