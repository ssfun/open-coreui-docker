# Stage 1: Downloader (保持不变)
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

# Stage 2: Runtime (改为 Alpine)
FROM alpine:latest

WORKDIR /app

# 设置时区环境变量
ENV TZ=Asia/Shanghai

# 安装运行时依赖
# gcompat: 运行 glibc 二进制文件必须
# aws-cli: 用于 S3 备份
# sqlite: 用于数据库操作
# bash: 脚本需要
# tzdata: 时区支持
RUN apk add --no-cache \
    bash \
    ca-certificates \
    sqlite \
    curl \
    tzdata \
    aws-cli \
    gcompat \
    libstdc++ \
    && \
    # 配置时区
    cp /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 复制文件
COPY --from=downloader /downloads/open-coreui /app/open-coreui
COPY backup.sh /app/backup.sh
COPY entrypoint.sh /app/entrypoint.sh

RUN chmod +x /app/backup.sh /app/entrypoint.sh && \
    mkdir -p /app/data

# 环境变量
ENV HOST=0.0.0.0 \
    PORT=8168 \
    CONFIG_DIR=/app/data \
    ENABLE_RANDOM_PORT=false \
    ENV=production

EXPOSE 8168
VOLUME ["/app/data"]

ENTRYPOINT ["/app/entrypoint.sh"]
