#!/usr/bin/env bash
# 首次部署/更新: 拉最新仓库 -> 起容器 (镜像由 GitHub Actions 推送/加载, 本机不构建不拉取)
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== git pull =="
git pull --ff-only

echo "== docker compose up -d =="
sudo docker compose up -d
sleep 3
sudo docker compose ps

echo "== 等待 dsh 打印登录 URL =="
for i in $(seq 1 45); do
  URL=$(sudo docker compose logs dsh 2>/dev/null | grep -o 'dsh web: .*' | tail -1 || true)
  [ -n "$URL" ] && { echo ""; echo ">>> $URL"; echo ">>> 只在可信设备打开"; exit 0; }
  sleep 2
done
echo "未捕获到 URL, 查看: sudo docker compose logs --tail=100 dsh"
