# --- 第一阶段：构建 ---
FROM node:20-bookworm-slim AS builder
RUN apt-get update && apt-get install -y --no-install-recommends \
    g++ make python3 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY package*.json ./
RUN npm ci && npm rebuild better-sqlite3 --build-from-source

# --- 第二阶段：运行时 ---
FROM node:20-bookworm-slim
# 安装必要运行时库及检查工具 x11-utils
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb xauth x11-utils libgtk-3-0 libnss3 libx11-xcb1 libasound2 libdbus-glib-1-2 libgbm1 fonts-liberation \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY . .

# 创建用户与目录
RUN mkdir -p /home/nodeuser/.cache/camoufox /home/nodeuser/.camoufox/profiles \
    && chown -R node:node /home/nodeuser /app

# 注入浏览器二进制 (构建时挂载)
ARG ARCH=aarch64
ARG CAMOUFOX_VERSION=1.0.0
RUN --mount=type=bind,source=dist,target=/dist \
    [ -f "/dist/camoufox-${ARCH}.zip" ] || { echo "Browser zip missing!"; exit 1; } \
    && unzip -q "/dist/camoufox-${ARCH}.zip" -d /home/nodeuser/.cache/camoufox \
    && echo "{\"version\":\"${CAMOUFOX_VERSION}\",\"release\":\"${CAMOUFOX_VERSION}\"}" > /home/nodeuser/.cache/camoufox/version.json \
    && mv /home/nodeuser/.cache/camoufox/camoufox-bin /home/nodeuser/.cache/camoufox/camoufox-bin-real \
    && printf '#!/bin/sh\nexport DISPLAY=${DISPLAY:-:99}\nexec /home/nodeuser/.cache/camoufox/camoufox-bin-real "$@"\n' > /home/nodeuser/.cache/camoufox/camoufox-bin \
    && chmod +x /home/nodeuser/.cache/camoufox/camoufox-bin \
    && chown -R node:node /home/nodeuser/.cache/camoufox

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV DISPLAY=:99
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
EXPOSE 9377

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
