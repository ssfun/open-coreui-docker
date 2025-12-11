# Stage 1: Downloader (下载器依然可以用 Alpine，省流量)
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

# Stage 2: Runtime (必须使用 Debian Slim 以兼容 glibc)
FROM debian:stable-slim

WORKDIR /app

# 设置时区
ENV TZ=Asia/Shanghai

# 安装运行时依赖
# ca-certificates: HTTPS
# sqlite3: 数据库备份
# curl: 下载
# cron: 定时任务
# awscli: S3/R2 上传
# tzdata: 时区数据
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    sqlite3 \
    curl \
    cron \
    awscli \
    tzdata \
    && \
    # 配置时区
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    # 清理缓存减小体积
    rm -rf /var/lib/apt/lists/*

# 复制文件
COPY --from=downloader /downloads/open-coreui /app/open-coreui
COPY backup.sh /app/backup.sh
COPY entrypoint.sh /app/entrypoint.sh

# 权限与目录
RUN chmod +x /app/backup.sh /app/entrypoint.sh && \
    mkdir -p /app/data \
    && chmod -R 777 /app/data

# 环境变量
ENV HOST=0.0.0.0 \
    PORT=8168 \
    CONFIG_DIR=/app/data \
    ENABLE_RANDOM_PORT=false \
    ENV=production

EXPOSE 8168
VOLUME ["/app/data"]

ENTRYPOINT ["/app/entrypoint.sh"]
