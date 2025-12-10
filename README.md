# Open CoreUI (Docker + S3 Backup Edition)

这是一个基于 [Open CoreUI](https://github.com/xxnuo/open-coreui) 官方二进制文件构建的 Docker 镜像，额外增强了 **自动备份与还原** 功能。

它保留了原版轻量、高性能的特性，同时解决了容器化部署中数据安全的核心痛点。

## ✨ 特性

- **轻量级**：基于 Debian Slim 构建，无 Python/NodeJS 臃肿依赖。
- **多架构支持**：自动适配 `amd64` (x86_64) 和 `arm64` (aarch64)。
- **数据安全**：
  - 支持 **Cloudflare R2**、**AWS S3**、**MinIO** 等 S3 兼容存储。
  - **启动自动还原**：容器启动时自动从云端拉取最新备份。
  - **定时自动备份**：每天凌晨 02:00 和下午 14:00 自动打包数据并上传。
  - **SQLite 热备份**：使用 `VACUUM INTO` 技术，确保在数据库运行时也能生成完整无损的快照。
  - **自动轮转**：自动清理 7 天前的旧备份，节省存储空间。

## 🚀 快速开始

### 1. Docker CLI

最简单的运行方式（不带备份功能）：

```bash
docker run -d \
  --name open-coreui \
  -p 8168:8168 \
  -v $(pwd)/data:/app/data \
  open-coreui:latest
````

### 2\. 配置自动备份 (推荐 Cloudflare R2)

需提供 R2 或 S3 的访问凭证。

```bash
docker run -d \
  --name open-coreui \
  -p 8168:8168 \
  -v $(pwd)/data:/app/data \
  -e R2_ACCESS_KEY_ID="你的AccessKey" \
  -e R2_SECRET_ACCESS_KEY="你的SecretKey" \
  -e R2_ENDPOINT_URL="https://<ACCOUNT_ID>.r2.cloudflarestorage.com" \
  -e R2_BUCKET_NAME="你的存储桶名称" \
  open-coreui:latest
```

### 3\. Docker Compose (推荐)

创建 `docker-compose.yml`：

```yaml
version: '3.8'

services:
  open-coreui:
    image: open-coreui:latest  # 请替换为你构建的镜像名
    container_name: open-coreui
    restart: unless-stopped
    ports:
      - "8168:8168"
    volumes:
      - ./data:/app/data
    environment:
      # --- 核心配置 ---
      - HOST=0.0.0.0
      - PORT=8168
      - WEBUI_SECRET_KEY=generate-secure-key-here  # 建议手动设置一个固定密钥
      
      # --- 备份配置 (Cloudflare R2 示例) ---
      - R2_ACCESS_KEY_ID=xxxxxxxxxxxxxxxx
      - R2_SECRET_ACCESS_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
      # 注意：Endpoint URL 必须包含 https:// 且不要带 bucket 子路径
      - R2_ENDPOINT_URL=https://<ACCOUNT_ID>.r2.cloudflarestorage.com
      - R2_BUCKET_NAME=open-coreui-backup
      
      # --- 其他 Open CoreUI 环境变量 ---
      # - OPENAI_API_KEY=sk-xxxx
      # - OPENAI_API_BASE_URL=[https://api.openai.com/v1](https://api.openai.com/v1)
```

## 📂 备份策略说明

系统内置了 `backup.sh` 和 `entrypoint.sh` 脚本来管理生命周期：

1.  **启动时 (Restore)**：

      * 容器启动时，会自动检查 S3/R2 存储桶中是否有 `opencoreui_backup_` 开头的备份文件。
      * 如果找到，会自动下载最新的备份并解压覆盖 `/app/data` 目录。
      * *注意：如果本地数据卷中有数据，启动时的还原操作会覆盖本地数据，请确保这是你想要的行为（无状态设计）。*

2.  **运行时 (Backup)**：

      * 内置 Cron 任务固定在 **每天 02:00 和 14:00** 执行备份。
      * **备份内容**：包含 `data.sqlite3` 数据库（热备份）以及 `/app/data` 下的所有文件（如上传的图片、文档）。
      * **过期清理**：每次备份成功后，会自动检测并删除存储桶中 **7 天前** 的旧备份文件。

## 🛠️ 环境变量列表

| 变量名 | 描述 | 默认值 |
| :--- | :--- | :--- |
| `R2_ACCESS_KEY_ID` | S3/R2 Access Key | 空 (不启用备份) |
| `R2_SECRET_ACCESS_KEY` | S3/R2 Secret Key | 空 |
| `R2_ENDPOINT_URL` | S3 API 端点 (需带 https://) | 空 |
| `R2_BUCKET_NAME` | 存储桶名称 | 空 |
| `HOST` | 监听地址 | `0.0.0.0` |
| `PORT` | 监听端口 | `8168` |
| `WEBUI_SECRET_KEY` | JWT 签名密钥 | 随机生成 (建议固定) |

更多 Open CoreUI 原生环境变量（如 `OPENAI_API_KEY`, `ENABLE_signup` 等）请参考官方 [CLI 文档](https://www.google.com/search?q=CLI.md)。

## 📝 构建指南

如果你需要自己构建镜像：

```bash
# 构建镜像 (自动获取最新版)
docker build -t open-coreui:latest .

# 强制更新构建 (忽略缓存)
docker build --build-arg CACHEBUST=$(date +%s) -t open-coreui:latest .
```

## ⚠️ 注意事项

1.  **Endpoint 格式**：Cloudflare R2 的 `R2_ENDPOINT_URL` 应该是 `https://<account_id>.r2.cloudflarestorage.com`，**不要**在 URL 后面加 Bucket 名字，AWS CLI 库会自动处理。
2.  **权限**：提供的 S3 凭证必须拥有 `ListBucket`, `PutObject`, `GetObject`, `DeleteObject` 权限。
3.  **时区**：Docker 容器默认使用 UTC 时间，Cron 任务的 02:00 和 14:00 也是 UTC 时间。如需修改时区，可挂载 `/etc/localtime` 或设置 `TZ` 环境变量（需 Dockerfile 支持 tzdata）。
