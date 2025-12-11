# Stage 1: Downloader
FROM alpine:latest AS downloader
ARG TARGETARCH
RUN apk add --no-cache curl jq
WORKDIR /downloads
RUN echo "Fetching latest version..." && \
    LATEST_TAG=$(curl -s https://api.github.com/repos/xxnuo/open-coreui/releases/latest | jq -r .tag_name) && \
    VERSION=${LATEST_TAG#v} && \
    if [ "$TARGETARCH" = "amd64" ]; then FILENAME="open-coreui-${VERSION}-x86_64-unknown-linux-gnu"; \
    elif [ "$TARGETARCH" = "arm64" ]; then FILENAME="open-coreui-${VERSION}-aarch64-unknown-linux-gnu"; \
    else echo "Unsupported arch: $TARGETARCH"; exit 1; fi && \
    curl -L -f -o open-coreui "https://github.com/xxnuo/open-coreui/releases/download/${LATEST_TAG}/${FILENAME}" && \
    chmod +x open-coreui

# Stage 2: Runtime
FROM debian:stable-slim

WORKDIR /app

# 安装运行时依赖
# awscli: 用于 S3/R2 备份
# sqlite3: 用于数据库热备份
# cron: 用于定时任务
# ca-certificates: 用于 HTTPS
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    sqlite3 \
    curl \
    cron \
    awscli \
    && rm -rf /var/lib/apt/lists/*

# 复制文件
COPY --from=downloader /downloads/open-coreui /app/open-coreui
COPY backup.sh /app/backup.sh
COPY entrypoint.sh /app/entrypoint.sh

# 权限设置
RUN chmod +x /app/backup.sh /app/entrypoint.sh && \
    mkdir -p /app/data

# 环境变量
ENV HOST=0.0.0.0 \
    PORT=8168 \
    CONFIG_DIR=/app/data \
    ENABLE_RANDOM_PORT=false \
    ENV=production

# 暴露端口和挂载点
EXPOSE 8168
VOLUME ["/app/data"]

ENTRYPOINT ["/app/entrypoint.sh"]
