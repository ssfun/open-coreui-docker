#!/bin/bash
set -e

# 配置
DB_PATH="/app/data/data.sqlite3"
BACKUP_DIR="/app/backup"
BUCKET_NAME="${R2_BUCKET_NAME}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"

# 生成备份文件名（包含时间戳）
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILENAME="data_${TIMESTAMP}.sqlite3"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILENAME}"

echo "=========================================="
echo "[BACKUP] Started at $(date)"
echo "=========================================="

# 检查源数据库是否存在
if [ ! -f "$DB_PATH" ]; then
    echo "[BACKUP] Database not found at $DB_PATH, skipping backup"
    exit 0
fi

# 检查 R2 配置
if [ -z "$R2_ACCOUNT_ID" ] || [ -z "$R2_ACCESS_KEY_ID" ] || \
   [ -z "$R2_SECRET_ACCESS_KEY" ] || [ -z "$BUCKET_NAME" ]; then
    echo "[BACKUP] R2 configuration incomplete, skipping backup"
    exit 1
fi

# 确保备份目录存在
mkdir -p "$BACKUP_DIR"

# 使用 VACUUM INTO 进行热备份（不会锁定数据库）
echo "[BACKUP] Creating hot backup using VACUUM INTO..."
sqlite3 "$DB_PATH" "VACUUM INTO '${BACKUP_PATH}';"

if [ ! -f "$BACKUP_PATH" ]; then
    echo "[BACKUP] ERROR: Backup file was not created"
    exit 1
fi

BACKUP_SIZE=$(du -h "$BACKUP_PATH" | cut -f1)
echo "[BACKUP] Local backup created: $BACKUP_FILENAME ($BACKUP_SIZE)"

# 上传到 R2
echo "[BACKUP] Uploading to Cloudflare R2..."
if rclone copy "$BACKUP_PATH" "r2:${BUCKET_NAME}/backups/" --progress; then
    echo "[BACKUP] Upload successful"
else
    echo "[BACKUP] ERROR: Upload failed"
    rm -f "$BACKUP_PATH"
    exit 1
fi

# 删除本地备份文件
rm -f "$BACKUP_PATH"
echo "[BACKUP] Local backup file cleaned up"

# 清理 R2 上的旧备份
echo "[BACKUP] Cleaning up old backups (keeping last $RETENTION_DAYS days)..."

# 获取所有备份文件列表
CUTOFF_DATE=$(date -d "-${RETENTION_DAYS} days" +"%Y%m%d" 2>/dev/null || \
              date -v-${RETENTION_DAYS}d +"%Y%m%d" 2>/dev/null)

echo "[BACKUP] Cutoff date: $CUTOFF_DATE"

# 列出所有备份并删除过期的
rclone lsf "r2:${BUCKET_NAME}/backups/" 2>/dev/null | while read -r file; do
    # 提取文件名中的日期部分 (data_YYYYMMDD_HHMMSS.sqlite3 -> YYYYMMDD)
    FILE_DATE=$(echo "$file" | grep -oP 'data_\K[0-9]{8}' || echo "")
    
    if [ -n "$FILE_DATE" ] && [ "$FILE_DATE" -lt "$CUTOFF_DATE" ]; then
        echo "[BACKUP] Deleting old backup: $file"
        rclone delete "r2:${BUCKET_NAME}/backups/${file}"
    fi
done

echo "[BACKUP] Cleanup completed"
echo "[BACKUP] Finished at $(date)"
echo "=========================================="
