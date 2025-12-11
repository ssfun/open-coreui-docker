#!/bin/bash
set -e

# 配置
DB_PATH="/app/data/data.sqlite3"
BACKUP_DIR="/app/backup"
BUCKET_NAME="${R2_BUCKET_NAME}"

echo "=========================================="
echo "[RESTORE] Started at $(date)"
echo "=========================================="

# 检查 R2 配置
if [ -z "$R2_ACCOUNT_ID" ] || [ -z "$R2_ACCESS_KEY_ID" ] || \
   [ -z "$R2_SECRET_ACCESS_KEY" ] || [ -z "$BUCKET_NAME" ]; then
    echo "[RESTORE] R2 configuration incomplete, skipping restore"
    exit 1
fi

# 如果数据库已存在，跳过还原
if [ -f "$DB_PATH" ]; then
    echo "[RESTORE] Database already exists at $DB_PATH"
    echo "[RESTORE] Skipping restore to prevent data loss"
    echo "[RESTORE] To force restore, remove the existing database first"
    exit 0
fi

# 确保备份目录存在
mkdir -p "$BACKUP_DIR"

# 获取最新的备份文件
echo "[RESTORE] Fetching latest backup from R2..."

LATEST_BACKUP=$(rclone lsf "r2:${BUCKET_NAME}/backups/" --files-only 2>/dev/null | \
                grep -E '^data_[0-9]{8}_[0-9]{6}\.sqlite3$' | \
                sort -r | \
                head -n 1)

if [ -z "$LATEST_BACKUP" ]; then
    echo "[RESTORE] No backup found in R2"
    exit 1
fi

echo "[RESTORE] Found latest backup: $LATEST_BACKUP"

# 下载备份
RESTORE_PATH="${BACKUP_DIR}/${LATEST_BACKUP}"
echo "[RESTORE] Downloading backup..."

if ! rclone copy "r2:${BUCKET_NAME}/backups/${LATEST_BACKUP}" "$BACKUP_DIR/" --progress; then
    echo "[RESTORE] ERROR: Download failed"
    exit 1
fi

# 验证下载的文件
if [ ! -f "$RESTORE_PATH" ]; then
    echo "[RESTORE] ERROR: Downloaded file not found"
    exit 1
fi

# 验证 SQLite 文件完整性
echo "[RESTORE] Verifying database integrity..."
if ! sqlite3 "$RESTORE_PATH" "PRAGMA integrity_check;" | grep -q "ok"; then
    echo "[RESTORE] ERROR: Database integrity check failed"
    rm -f "$RESTORE_PATH"
    exit 1
fi

echo "[RESTORE] Database integrity verified"

# 确保数据目录存在
mkdir -p "$(dirname "$DB_PATH")"

# 复制到目标位置
echo "[RESTORE] Restoring database..."
cp "$RESTORE_PATH" "$DB_PATH"

# 清理下载的文件
rm -f "$RESTORE_PATH"

# 验证还原后的数据库
if sqlite3 "$DB_PATH" "PRAGMA integrity_check;" | grep -q "ok"; then
    echo "[RESTORE] Database restored successfully"
else
    echo "[RESTORE] WARNING: Restored database may be corrupted"
fi

echo "[RESTORE] Finished at $(date)"
echo "=========================================="
