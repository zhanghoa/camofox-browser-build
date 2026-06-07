#!/bin/sh
set -e

# 1. 以 root 启动 Xvfb
Xvfb :99 -screen 0 1280x1024x24 -nolisten tcp >/dev/null 2>&1 &
XVFB_PID=$!

# 2. 轮询等待 Xvfb 就绪
echo "Waiting for Xvfb..."
for i in $(seq 1 20); do
  if xdpyinfo -display :99 >/dev/null 2>&1; then
    echo "Xvfb is ready."
    break
  fi
  sleep 0.5
done

if ! xdpyinfo -display :99 >/dev/null 2>&1; then
  echo "Xvfb failed to start"
  kill $XVFB_PID
  exit 1
fi

# 3. 切换到普通用户运行 Node 服务
exec su - node -c "cd /app && npm start"
