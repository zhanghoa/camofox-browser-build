#!/bin/sh
set -e

# 1. 采用 root 权限后台静默启动 Xvfb，规避普通用户无法创建 /tmp/.X11-unix 的权限漏洞
Xvfb :99 -screen 0 1280x1024x24 -nolisten tcp >/dev/null 2>&1 &
XVFB_PID=$!

# 2. 工业级阻塞轮询：通过 xdpyinfo 确保显示服务 100% 准备就绪
echo "Starting Xvfb virtual display server and checking health..."
for i in $(seq 1 20); do
  if xdpyinfo -display :99 >/dev/null 2>&1; then
    echo "✔ Xvfb virtual display is up and running successfully."
    break
  fi
  sleep 0.5
done

# 3. 兜底断言：若超时仍未就绪则强制熔断，防止产生静默僵尸进程
if ! xdpyinfo -display :99 >/dev/null 2>&1; then
  echo "❌ CRITICAL: Xvfb failed to start within timeout. Aborting."
  kill $XVFB_PID 2>/dev/null || true
  exit 1
fi

# 4. 降权生产：平滑降权至非 root 的 node 用户安全运行 Node.js 爬虫主程序
exec su - node -c "cd /app && npm start"
