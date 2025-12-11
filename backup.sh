#!/bin/bash
set -e

DB_PATH="/app/data/data.sqlite3"
BACKUP_DIR="/app/backup"
BUCKET_NAME="${R2_BUCKET_NAME}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="data_${TIMESTAMP}.sqlite3"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILE}"

echo "=========================================="
echo "[BACKUP] $(date)"
echo "=========================================="

# 检查
[ ! -f "$DB_PATH" ] && echo "[BACKUP] No database found" && exit 0
[ -z "$BUCKET_NAME" ] && echo "[BACKUP] R2 not configured" && exit 1

mkdir -p "$BACKUP_DIR"

# 热备份
echo "[BACKUP] Creating backup..."
sqlite3 "$DB_PATH" "VACUUM INTO '${BACKUP_PATH}';"

[ ! -f "$BACKUP_PATH" ] && echo "[BACKUP] Failed" && exit 1

echo "[BACKUP] Created: $BACKUP_FILE ($(du -h "$BACKUP_PATH" | cut -f1))"

# 上传
echo "[BACKUP] Uploading to R2..."
if rclone copy "$BACKUP_PATH" "r2:${BUCKET_NAME}/backups/"; then
    echo "[BACKUP] Upload successful"
    rm -f "$BACKUP_PATH"
else
    echo "[BACKUP] Upload failed"
    rm -f "$BACKUP_PATH"
    exit 1
fi

# 清理旧备份
CUTOFF=$(date -d "-${RETENTION_DAYS} days" +"%Y%m%d" 2>/dev/null) || exit 0

rclone lsf "r2:${BUCKET_NAME}/backups/" 2>/dev/null | while read -r file; do
    FILE_DATE=$(echo "$file" | sed -n 's/data_\([0-9]\{8\}\)_.*/\1/p')
    if [ -n "$FILE_DATE" ] && [ "$FILE_DATE" -lt "$CUTOFF" ] 2>/dev/null; then
        echo "[BACKUP] Deleting old: $file"
        rclone delete "r2:${BUCKET_NAME}/backups/${file}"
    fi
done

echo "[BACKUP] Done"
