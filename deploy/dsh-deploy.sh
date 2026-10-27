#!/bin/bash
# 服务器端部署脚本 —— 由 CNB 流水线通过「受限 SSH key」触发。
#
# 安装位置: ~/bin/dsh-deploy.sh (chmod 755)
# 对应 authorized_keys 的写法:
#   restrict,command="/home/ubuntu/bin/dsh-deploy.sh" ssh-ed25519 AAAA... cnb-deploy
#
# 因为带 command= 强制项, 这把 key 只能跑本脚本: 拿不到 shell, 不能转发端口,
# 也不能执行任何其他命令 (客户端发来的命令会被忽略, 只本脚本被执行)。
set -euo pipefail

cd "$HOME/harness-deploy"

echo "[deploy] git pull (origin = CNB)"
git pull --ff-only

echo "[deploy] docker login docker.cnb.cool"
sudo -n docker login docker.cnb.cool -u cnb --password-stdin < "$HOME/.cnb-token" >/dev/null

echo "[deploy] compose pull"
sudo -n docker compose pull

echo "[deploy] compose up -d"
sudo -n docker compose up -d

echo "[deploy] ps"
sudo -n docker compose ps
