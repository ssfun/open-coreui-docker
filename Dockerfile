# Stage 1: Downloader (自动获取最新版)
FROM alpine:latest AS downloader

ARG TARGETARCH

RUN apk add --no-cache curl jq

WORKDIR /downloads

RUN echo "Checking latest version from GitHub..." && \
    LATEST_TAG=$(curl -s https://api.github.com/repos/xxnuo/open-coreui/releases/latest | jq -r .tag_name) && \
    VERSION=${LATEST_TAG#v} && \
    echo "Detected latest version: ${VERSION}" && \
    \
    if [ "$TARGETARCH" = "amd64" ]; then \
        FILENAME="open-coreui-${VERSION}-x86_64-unknown-linux-gnu"; \
    elif [ "$TARGETARCH" = "arm64" ]; then \
        FILENAME="open-coreui-${VERSION}-aarch64-unknown-linux-gnu"; \
    else \
        echo "Error: Unsupported architecture $TARGETARCH"; exit 1; \
    fi && \
    \
    DOWNLOAD_URL="https://github.com/xxnuo/open-coreui/releases/download/${LATEST_TAG}/${FILENAME}" && \
    echo "Downloading from: ${DOWNLOAD_URL}" && \
    \
    curl -L -f -o open-coreui "${DOWNLOAD_URL}" && \
    chmod +x open-coreui

# Stage 2: Runtime (运行时环境)
FROM debian:stable-slim

WORKDIR /app

# 安装依赖：ca-certificates, sqlite3, rclone, supercrond, tzdata
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        sqlite3 \
        curl \
        unzip \
        tzdata \
        supercronic && \
    # 安装 rclone
    curl -O https://downloads.rclone.org/rclone-current-linux-$(dpkg --print-architecture).zip && \
    unzip rclone-current-linux-*.zip && \
    cp rclone-*-linux-*/rclone /usr/local/bin/ && \
    chmod +x /usr/local/bin/rclone && \
    rm -rf rclone-* && \
    # 清理
    apt-get remove -y unzip && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

# 从下载阶段复制文件
COPY --from=downloader /downloads/open-coreui /app/open-coreui

# 复制脚本
COPY entrypoint.sh /app/entrypoint.sh
COPY backup.sh /app/backup.sh
COPY restore.sh /app/restore.sh

RUN chmod +x /app/*.sh

# 创建数据目录和备份目录
RUN mkdir -p /app/data /app/backup

# 创建 crontab 文件
RUN echo "0 2 * * * /app/backup.sh >> /var/log/backup.log 2>&1" > /app/crontab && \
    echo "0 14 * * * /app/backup.sh >> /var/log/backup.log 2>&1" >> /app/crontab

# 设置环境变量
ENV HOST=0.0.0.0
ENV PORT=8168
ENV CONFIG_DIR=/app/data
ENV ENABLE_RANDOM_PORT=false
ENV ENV=production
ENV TZ=Asia/Shanghai

# R2 配置环境变量 (需在运行时提供)
# ENV R2_ACCOUNT_ID=
# ENV R2_ACCESS_KEY_ID=
# ENV R2_SECRET_ACCESS_KEY=
# ENV R2_BUCKET_NAME=
# ENV R2_ENDPOINT=

# 备份保留天数
ENV BACKUP_RETENTION_DAYS=7

# 挂载卷
VOLUME ["/app/data"]

EXPOSE 8168

ENTRYPOINT ["/app/entrypoint.sh"]
