# Stage 1: Downloader (自动获取最新版)
FROM alpine:latest AS downloader

# 定义构建参数，Docker 会自动传入目标架构 (amd64 或 arm64)
ARG TARGETARCH

# 安装必要的工具: curl 用于下载, jq 用于解析 GitHub API 返回的 JSON
RUN apk add --no-cache curl jq

WORKDIR /downloads

# 核心逻辑：
# 1. 请求 GitHub API 获取 latest release 的 JSON
# 2. 用 jq 提取 tag_name (通常是 v0.9.x)
# 3. 去掉 'v' 前缀以匹配二进制文件名规范
# 4. 根据架构拼接文件名并下载
RUN echo "Checking latest version from GitHub..." && \
    # 获取最新 Tag (例如 v0.9.6)
    LATEST_TAG=$(curl -s https://api.github.com/repos/xxnuo/open-coreui/releases/latest | jq -r .tag_name) && \
    # 去掉 tag 中的 'v' 前缀 (v0.9.6 -> 0.9.6)
    VERSION=${LATEST_TAG#v} && \
    echo "Detected latest version: ${VERSION}" && \
    \
    # 判断架构
    if [ "$TARGETARCH" = "amd64" ]; then \
        FILENAME="open-coreui-${VERSION}-x86_64-unknown-linux-gnu"; \
    elif [ "$TARGETARCH" = "arm64" ]; then \
        FILENAME="open-coreui-${VERSION}-aarch64-unknown-linux-gnu"; \
    else \
        echo "Error: Unsupported architecture $TARGETARCH"; exit 1; \
    fi && \
    \
    # 拼接下载 URL
    DOWNLOAD_URL="https://github.com/xxnuo/open-coreui/releases/download/${LATEST_TAG}/${FILENAME}" && \
    echo "Downloading from: ${DOWNLOAD_URL}" && \
    \
    # 下载并重命名
    curl -L -f -o open-coreui "${DOWNLOAD_URL}" && \
    chmod +x open-coreui

# Stage 2: Runtime (运行时环境)
# 依然使用 debian:stable-slim 以确保 glibc 兼容性
FROM debian:stable-slim

WORKDIR /app

# 安装基础证书依赖
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# 从下载阶段复制文件
COPY --from=downloader /downloads/open-coreui /app/open-coreui

# 创建数据目录
RUN mkdir -p /app/data && chmod -R 777 /app/data

# 设置环境变量
ENV HOST=0.0.0.0
ENV PORT=8168
ENV CONFIG_DIR=/app/data
ENV ENABLE_RANDOM_PORT=false
ENV ENV=production

# 挂载卷
VOLUME ["/app/data"]

EXPOSE 8168

CMD ["/app/open-coreui"]
