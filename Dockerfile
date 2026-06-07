# --- 第一阶段：构建 ---
FROM node:20-bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    g++ make python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY package*.json ./
RUN npm ci && npm rebuild better-sqlite3 --build-from-source

# --- 第二阶段：运行时 ---
FROM node:20-bookworm-slim

# 安装运行时依赖、GUI库、字体及 gosu
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb xauth x11-utils \
    libgtk-3-0 libnss3 libx11-xcb1 libasound2 libdbus-glib-1-2 libgbm1 \
    fonts-liberation fonts-noto-cjk \
    gosu \
    && rm -rf /var/lib/apt/lists/* \
    && gosu nobody true

WORKDIR /app

# 复制构建产物与应用代码
COPY --from=builder /app/node_modules ./node_modules
COPY . .

# 创建 Camoufox 缓存目录（统一使用 node 用户）
RUN mkdir -p /home/node/.cache/camoufox /home/node/.camoufox/profiles \
    && chown -R node:node /home/node/.cache /home/node/.camoufox /app

# 注入浏览器二进制
ARG ARCH=aarch64
ARG CAMOUFOX_VERSION=1.0.0

COPY dist/camoufox-${ARCH}.zip /tmp/camoufox.zip
RUN unzip -q /tmp/camoufox.zip -d /home/node/.cache/camoufox \
    && echo "{\"version\":\"${CAMOUFOX_VERSION}\",\"release\":\"${CAMOUFOX_VERSION}\"}" > /home/node/.cache/camoufox/version.json \
    && mv /home/node/.cache/camoufox/camoufox-bin /home/node/.cache/camoufox/camoufox-bin-real \
    && printf '#!/bin/sh\nexport DISPLAY=${DISPLAY:-:99}\nexec /home/node/.cache/camoufox/camoufox-bin-real "$@"\n' > /home/node/.cache/camoufox/camoufox-bin \
    && chmod +x /home/node/.cache/camoufox/camoufox-bin \
    && chown -R node:node /home/node/.cache/camoufox \
    && rm /tmp/camoufox.zip

# 复制入口脚本
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV DISPLAY=:99
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
EXPOSE 9377

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD xdpyinfo -display :99 >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["npm", "start"]
