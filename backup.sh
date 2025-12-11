#!/bin/bash

# --- 1. 环境配置 ---
CLEAN_ENDPOINT_URL="${R2_ENDPOINT_URL%/}"
export AWS_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}"
export AWS_DEFAULT_REGION="us-east-1"
export BUCKET_NAME="${R2_BUCKET_NAME}"

# 修复 SignatureDoesNotMatch: 强制 s3v4 和 path style
mkdir -p ~/.aws
aws configure set default.s3.signature_version s3v4
aws configure set default.s3.addressing_style path
aws configure set default.region us-east-1

ENDPOINT_ARG=""
if [ -n "$CLEAN_ENDPOINT_URL" ]; then
    ENDPOINT_ARG="--endpoint-url $CLEAN_ENDPOINT_URL"
fi

DATA_DIR="/app/data"
DB_FILE="${DATA_DIR}/data.sqlite3"
BACKUP_PREFIX="opencoreui_backup_"

if [ -z "$R2_ACCESS_KEY_ID" ] || [ -z "$R2_SECRET_ACCESS_KEY" ] || [ -z "$CLEAN_ENDPOINT_URL" ] || [ -z "$R2_BUCKET_NAME" ]; then
    echo "[Backup] Warning: R2 env vars missing. Skipping."
    exit 0
fi

# --- 2. 核心功能 ---

restore_backup() {
    echo "[Restore] Checking R2 for backups..."
    LATEST_BACKUP=$(aws $ENDPOINT_ARG s3 ls "s3://${BUCKET_NAME}/backups/${BACKUP_PREFIX}" | sort | tail -n 1 | awk '{print $4}')
    
    if [ -n "$LATEST_BACKUP" ]; then
        echo "[Restore] Found: ${LATEST_BACKUP}. Downloading..."
        if aws $ENDPOINT_ARG s3 cp "s3://${BUCKET_NAME}/backups/${LATEST_BACKUP}" /tmp/backup.tar.gz; then
            if [ -f "/tmp/backup.tar.gz" ]; then
                echo "[Restore] Extracting..."
                rm -rf "${DATA_DIR:?}"/*
                tar -xzf "/tmp/backup.tar.gz" -C "${DATA_DIR}"
                rm "/tmp/backup.tar.gz"
                echo "[Restore] Done!"
            fi
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
    LOCAL_BACKUP_PATH="/tmp/${BACKUP_FILENAME}"

    echo "[Backup] Starting job: ${TIMESTAMP}"
    rm -rf "$TEMP_DIR" "$LOCAL_BACKUP_PATH"
    mkdir -p "$TEMP_DIR"

    # 复制文件
    cp -r "$DATA_DIR/." "$TEMP_DIR/"

    # SQLite 热备份
    if [ -f "$DB_FILE" ]; then
        rm -f "$TEMP_DIR/data.sqlite3"
        if ! sqlite3 "$DB_FILE" "VACUUM INTO '$TEMP_DIR/data.sqlite3'"; then
            echo "[Backup] Error: Database backup failed."
            return 1
        fi
    fi

    # 压缩
    (cd "$TEMP_DIR" && tar -czf "$LOCAL_BACKUP_PATH" .)
    
    # 上传
    if aws $ENDPOINT_ARG s3 cp "$LOCAL_BACKUP_PATH" "s3://${BUCKET_NAME}/backups/${BACKUP_FILENAME}"; then
        echo "[Backup] Upload success."
        rm "$LOCAL_BACKUP_PATH"
        rm -rf "$TEMP_DIR"
    else
        echo "[Backup] Upload failed."
        return 1
    fi

    # 轮转清理
    echo "[Backup] Cleaning old backups..."
    OLD_DATE=$(date -d "7 days ago" +%Y%m%d)
    aws $ENDPOINT_ARG s3 ls "s3://${BUCKET_NAME}/backups/${BACKUP_PREFIX}" | while read -r line; do
        file_name=$(echo "$line" | awk '{print $4}')
        file_date=$(echo "$file_name" | grep -oE "[0-9]{8}" | head -1)
        if [ -n "$file_date" ] && [ "$file_date" -lt "$OLD_DATE" ]; then
            echo "[Backup] Deleting: $file_name"
            aws $ENDPOINT_ARG s3 rm "s3://${BUCKET_NAME}/backups/$file_name"
        fi
    done
}

case "$1" in
    "restore") restore_backup ;;
    "backup") create_backup ;;
    *) echo "Usage: $0 {backup|restore}"; exit 1 ;;
esac
