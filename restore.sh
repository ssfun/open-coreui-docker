#!/bin/bash
set -e

DB_PATH="/app/data/data.sqlite3"
BACKUP_DIR="/app/backup"
BUCKET_NAME="${R2_BUCKET_NAME}"
RESTORE_MODE="${RESTORE_MODE:-smart}"

echo "=========================================="
echo "[RESTORE] $(date) | Mode: $RESTORE_MODE"
echo "=========================================="

[ -z "$BUCKET_NAME" ] && echo "[RESTORE] R2 not configured" && exit 1

mkdir -p "$BACKUP_DIR"

# 获取最新备份
LATEST=$(rclone lsf "r2:${BUCKET_NAME}/backups/" --files-only 2>/dev/null | \
         grep -E '^data_[0-9]{8}_[0-9]{6}\.sqlite3$' | sort -r | head -n1)

[ -z "$LATEST" ] && echo "[RESTORE] No backup found" && exit 0

REMOTE_TS=$(echo "$LATEST" | sed -n 's/data_\([0-9]\{8\}_[0-9]\{6\}\)\.sqlite3/\1/p')
echo "[RESTORE] Remote: $LATEST ($REMOTE_TS)"

# 检查本地
if [ -f "$DB_PATH" ]; then
    if sqlite3 "$DB_PATH" "PRAGMA integrity_check;" 2>/dev/null | grep -q "ok"; then
        LOCAL_TS=$(date -r "$DB_PATH" +"%Y%m%d_%H%M%S" 2>/dev/null)
        echo "[RESTORE] Local DB valid ($LOCAL_TS)"
        
        case "$RESTORE_MODE" in
            skip)
                echo "[RESTORE] Skipping (local exists)"
                exit 0
                ;;
            smart)
                if [ "$REMOTE_TS" \> "$LOCAL_TS" ]; then
                    echo "[RESTORE] Remote is newer, will restore"
                else
                    echo "[RESTORE] Local is current, skipping"
                    exit 0
                fi
                ;;
            force)
                echo "[RESTORE] Force mode, will restore"
                ;;
        esac
        
        # 备份本地
        echo "[RESTORE] Backing up local DB..."
        LOCAL_BK="/tmp/local_$(date +%Y%m%d_%H%M%S).sqlite3"
        cp "$DB_PATH" "$LOCAL_BK"
        rclone copy "$LOCAL_BK" "r2:${BUCKET_NAME}/local-backups/" 2>/dev/null || true
        rm -f "$LOCAL_BK"
    else
        echo "[RESTORE] Local DB corrupted, will restore"
    fi
fi

# 下载
echo "[RESTORE] Downloading..."
rclone copy "r2:${BUCKET_NAME}/backups/${LATEST}" "$BACKUP_DIR/" || exit 1

RESTORE_PATH="${BACKUP_DIR}/${LATEST}"

# 验证
if ! sqlite3 "$RESTORE_PATH" "PRAGMA integrity_check;" | grep -q "ok"; then
    echo "[RESTORE] Downloaded file corrupted"
    rm -f "$RESTORE_PATH"
    exit 1
fi

# 恢复
mkdir -p "$(dirname "$DB_PATH")"
rm -f "$DB_PATH" "${DB_PATH}-wal" "${DB_PATH}-shm"
mv "$RESTORE_PATH" "$DB_PATH"

echo "[RESTORE] ✓ Restored successfully"
