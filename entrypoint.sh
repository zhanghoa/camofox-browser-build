#!/bin/sh
set -e

# 可选：调试模式 (docker run -e DEBUG=1 ...)
[ "${DEBUG:-0}" = "1" ] && set -x

# 1. 启动 Xvfb（主流分辨率 + 安全参数）
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp -ac +extension GLX +render -noreset >/dev/null 2>&1 &
XVFB_PID=$!

# 2. 轮询等待 Xvfb 就绪（超时 15s）
echo "Waiting for Xvfb..."
READY=0
for i in $(seq 1 30); do
  if xdpyinfo -display :99 >/dev/null 2>&1; then
    echo "Xvfb is ready on :99"
    READY=1
    break
  fi
  sleep 0.5
done

if [ "$READY" -ne 1 ]; then
  echo "ERROR: Xvfb failed to start within 15s" >&2
  kill "$XVFB_PID" 2>/dev/null || true
  exit 1
fi

# 3. 信号处理：容器停止时优雅关闭 Xvfb
cleanup() {
  echo "Shutting down Xvfb (PID=$XVFB_PID)..."
  kill "$XVFB_PID" 2>/dev/null || true
  wait "$XVFB_PID" 2>/dev/null || true
}
trap cleanup TERM INT

# 4. 以 node 用户执行传入命令（保留所有环境变量）
exec gosu node "$@"
