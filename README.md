# Open CoreUI Docker

这是 [Open CoreUI](https://github.com/xxnuo/open-coreui) 的非官方 Docker 封装版本。

本项目旨在提供一个**轻量级**、**自动化**的容器部署方案。它利用 Docker 的多阶段构建，自动从官方 GitHub Releases 获取最新版本的二进制文件，并运行在精简的 Debian Slim 环境中。

## ✨ 特性

  * **⚡️ 自动追新**：构建时自动调用 GitHub API 获取最新发布的 Release 版本，无需手动指定版本号。
  * **🐧 极致兼容**：基于 `debian:stable-slim` 构建，完美兼容官方提供的 glibc 二进制文件（避免 Alpine musl 的兼容性问题）。
  * **🏗 多架构支持**：自动识别并支持 `x86_64 (amd64)` 和 `aarch64 (arm64)` 架构。
  * **💾 数据持久化**：预设 `/app/data` 卷，确保数据库和配置不丢失。
  * **🛡 开箱即用**：预装 `ca-certificates`，确保 HTTPS API（如 OpenAI）调用畅通无阻。

## 🚀 快速开始

### 方法一：Docker CLI

直接运行容器，将数据目录挂载到本地：

```bash
docker run -d \
  --name open-coreui \
  --restart unless-stopped \
  -p 8168:8168 \
  -v $(pwd)/data:/app/data \
  -e WEBUI_SECRET_KEY="your-secret-key-here" \
  open-coreui:latest
```

访问地址：`http://localhost:8168`

### 方法二：Docker Compose (推荐)

创建 `docker-compose.yml` 文件：

```yaml
version: '3.8'

services:
  open-coreui:
    build: .
    image: open-coreui:latest
    container_name: open-coreui
    restart: unless-stopped
    ports:
      - "8168:8168"
    volumes:
      - ./data:/app/data
    environment:
      # 基础配置
      - HOST=0.0.0.0
      - WEBUI_SECRET_KEY=your-generated-secret-key
      
      # OpenAI 配置 (可选)
      # - OPENAI_API_KEY=sk-xxxx
      # - OPENAI_API_BASE_URL=https://api.openai.com/v1
```

启动服务：

```bash
docker-compose up -d
```

## 🛠 构建镜像

由于 Dockerfile 包含自动获取最新版本的逻辑，您可以使用以下命令构建镜像。

### 标准构建

```bash
docker build -t open-coreui:latest .
```

### 强制更新构建

Docker 默认会缓存构建层。如果官方发布了新版本，而您想强制 Docker 重新拉取最新二进制文件，请使用构建参数破坏缓存：

```bash
# 在 Dockerfile 中加入 ARG CACHEBUST=1 后生效，或者简单地使用 --no-cache
docker build --no-cache -t open-coreui:latest .
```

## ⚙️ 环境变量配置

容器支持官方文档中的所有环境变量，以下是常用配置：

| 变量名 | 默认值 | 说明 |
| :--- | :--- | :--- |
| `WEBUI_SECRET_KEY` | (自动生成) | WebUI 会话管理的密钥，建议固定设置 |
| `OPENAI_API_KEY` | - | OpenAI API 密钥 |
| `OPENAI_API_BASE_URL` | `https://api.openai.com/v1` | OpenAI API 接口地址 |
| `ENABLE_SIGNUP` | `true` | 是否允许新用户注册 |
| `ENABLE_LOGIN_FORM` | `true` | 是否显示登录表单 |
| `GLOBAL_LOG_LEVEL` | `INFO` | 日志等级 (DEBUG, INFO, WARN, ERROR) |
| `DATABASE_URL` | `sqlite://...` | 默认指向 `/app/data/data.sqlite3`，无需修改 |

更多高级配置（如 LDAP, Redis, TTS 等）请参考官方 [CLI 文档](https://www.google.com/search?q=https://github.com/xxnuo/open-coreui/blob/main/CLI.md)。

## 📂 目录结构

容器内的关键路径映射：

  * `/app/data`: 存放 SQLite 数据库 (`data.sqlite3`)、上传的文件 (`uploads/`) 和缓存。请务必挂载此目录以持久化数据。

## 🔗 致谢

  * 核心程序：[xxnuo/open-coreui](https://github.com/xxnuo/open-coreui)
  * 灵感来源：[open-webui](https://github.com/open-webui/open-webui)

-----

> **免责声明**: 本项目仅为 Open CoreUI 提供 Docker 封装，与原项目开发团队无直接关联。使用时请遵循原项目的开源协议。
