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

# Stage 2: Runtime
FROM debian:stable-slim

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        sqlite3 \
        curl \
        unzip \
        tzdata \
        cron && \
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

COPY --from=downloader /downloads/open-coreui /app/open-coreui

COPY entrypoint.sh /app/entrypoint.sh
COPY backup.sh /app/backup.sh
COPY restore.sh /app/restore.sh

RUN chmod +x /app/*.sh && \
    mkdir -p /app/data /app/backup && \
    chmod -R 777 /app

ENV HOST=0.0.0.0
ENV PORT=8168
ENV CONFIG_DIR=/app/data
ENV ENABLE_RANDOM_PORT=false
ENV ENV=production
ENV TZ=Asia/Shanghai
ENV BACKUP_RETENTION_DAYS=7
ENV RESTORE_MODE=smart

VOLUME ["/app/data"]
EXPOSE 8168

ENTRYPOINT ["/app/entrypoint.sh"]
