# --- 第一阶段：构建环境 (Builder) ---
FROM node:20-bookworm-slim AS builder

# 原生 ARM 环境下，直接安装编译链进行极速原生编译，绝不卡死或崩溃
RUN apt-get update && apt-get install -y --no-install-recommends \
    g++ make python3 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY package*.json ./

# 安装完整依赖并强制针对当前架构进行本地硬核编译（直接跑在 GitHub 的 ARM 刀片服务器上）
RUN npm ci && npm rebuild better-sqlite3 --build-from-source

# --- 第二阶段：生产运行时环境 (Runtime) ---
FROM node:20-bookworm-slim

# 显式禁止 Playwright 自动下载近 1GB 的无用官方浏览器内核
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
ENV DISPLAY=:99

# 安装运行时必需的图形依赖库及排查工具 x11-utils
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb xauth x11-utils libgtk-3-0 libnss3 libx11-xcb1 libasound2 libdbus-glib-1-2 libgbm1 fonts-liberation unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 从第一阶段克隆出纯净、针对原生 ARM64 编译好的 node_modules，杜绝体积脂肪
COPY --from=builder /app/node_modules ./node_modules
COPY . .

# 建立符合官方行为的缓存及配置目录，并统一变更文件属主为内置的 node 用户
RUN mkdir -p /home/nodeuser/.cache/camoufox /home/nodeuser/.camoufox/profiles \
    && chown -R node:node /home/nodeuser /app

# 注入特制浏览器内核二进制（通过 Buildkit 外部挂载安全读取）
ARG ARCH=aarch64
ARG CAMOUFOX_VERSION=1.0.0

RUN --mount=type=bind,source=dist,target=/dist \
    [ -f "/dist/camoufox-${ARCH}.zip" ] || { echo "ERROR: Camoufox zip package missing in dist/ !"; exit 1; } \
    && unzip -q "/dist/camoufox-${ARCH}.zip" -d /home/nodeuser/.cache/camoufox \
    # 注入假通行证，绕过 API 启动时严格的版本文件前置校验
    && echo "{\"version\":\"${CAMOUFOX_VERSION}\",\"release\":\"${CAMOUFOX_VERSION}\"}" > /home/nodeuser/.cache/camoufox/version.json \
    # 狸猫换太子补丁：拦截并清洗 Node20+ 环境下恶性的 [object Promise] 环境变量污染
    && mv /home/nodeuser/.cache/camoufox/camoufox-bin /home/nodeuser/.cache/camoufox/camoufox-bin-real \
    && printf '#!/bin/sh\nexport DISPLAY=${DISPLAY:-:99}\nexec /home/nodeuser/.cache/camoufox/camoufox-bin-real "$@"\n' > /home/nodeuser/.cache/camoufox/camoufox-bin \
    && chmod +x /home/nodeuser/.cache/camoufox/camoufox-bin \
    && chown -R node:node /home/nodeuser/.cache/camoufox

# 导入高可靠性进程启动管理器
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 9377

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
