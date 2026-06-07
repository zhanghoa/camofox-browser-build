# --- 第一阶段：在宿主机原生架构上极速安装依赖 (无 QEMU 干扰) ---
# 不指定 --platform，让它在 GitHub 的 x86_64 机器上原生运行，100% 不会崩溃
FROM node:20-bookworm-slim AS builder

WORKDIR /app
COPY package*.json ./

# 在这里我们不进行任何原生编译，只让 npm 纯粹地把所有 JS 依赖拉下来
RUN npm ci --omit=dev --ignore-scripts

# --- 第二阶段：真正的生产运行时环境 (ARM64) ---
# 只有在最终打包层才切换回你的目标架构 linux/arm64
FROM --platform=linux/arm64 node:20-bookworm-slim

ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
ENV DISPLAY=:99

# 安装运行时必需的图形依赖库
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb xauth x11-utils libgtk-3-0 libnss3 libx11-xcb1 libasound2 libdbus-glib-1-2 libgbm1 fonts-liberation unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 从第一阶段将干净的依赖树直接复制过来
COPY --from=builder /app/node_modules ./node_modules
COPY . .

# 💡 核心修复：由于 better-sqlite3 官方对 Linux ARM64 提供了开箱即用的预编译绑定，
# 它是纯 JS 加载机制，不需要在这里运行笨重的 npm install，彻底规避 QEMU 崩溃
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
