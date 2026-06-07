# --- 第一阶段：构建环境 (Builder) ---
FROM --platform=linux/arm64 node:20-bookworm-slim AS builder

WORKDIR /app
COPY package*.json ./

# 强行告诉 NPM 我们是在为 arm64 构建，直接去网络上拉取官方预编译好的 better-sqlite3 二进制包
# 这样就不需要本地安装 g++ 和 make，彻底跳过 QEMU 模拟编译，避开崩溃点
RUN npm env | grep -i arch; npm ci --omit=dev

# --- 第二阶段：生产运行时环境 (Runtime) ---
FROM --platform=linux/arm64 node:20-bookworm-slim

ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
ENV DISPLAY=:99

RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb xauth x11-utils libgtk-3-0 libnss3 libx11-xcb1 libasound2 libdbus-glib-1-2 libgbm1 fonts-liberation unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY . .

RUN mkdir -p /home/nodeuser/.cache/camoufox /home/nodeuser/.camoufox/profiles \
    && chown -R node:node /home/nodeuser /app

ARG ARCH=aarch64
ARG CAMOUFOX_VERSION=1.0.0

RUN --mount=type=bind,source=dist,target=/dist \
    [ -f "/dist/camoufox-${ARCH}.zip" ] || { echo "ERROR: Camoufox zip package missing in dist/ !"; exit 1; } \
    && unzip -q "/dist/camoufox-${ARCH}.zip" -d /home/nodeuser/.cache/camoufox \
    && echo "{\"version\":\"${CAMOUFOX_VERSION}\",\"release\":\"${CAMOUFOX_VERSION}\"}" > /home/nodeuser/.cache/camoufox/version.json \
    && mv /home/nodeuser/.cache/camoufox/camoufox-bin /home/nodeuser/.cache/camoufox/camoufox-bin-real \
    && printf '#!/bin/sh\nexport DISPLAY=${DISPLAY:-:99}\nexec /home/nodeuser/.cache/camoufox/camoufox-bin-real "$@"\n' > /home/nodeuser/.cache/camoufox/camoufox-bin \
    && chmod +x /home/nodeuser/.cache/camoufox/camoufox-bin \
    && chown -R node:node /home/nodeuser/.cache/camoufox

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 9377
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
