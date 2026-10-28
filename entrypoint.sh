#!/bin/sh
set -e

# 容器内自带的初始化脚本(按序执行, 存在才跑; 插件清单已移到 plans/ 里)
for s in /opt/bootstrap/*.sh; do
  [ -e "$s" ] || continue
  echo "[bootstrap] >>> $(basename "$s")"
  sh "$s" || echo "[bootstrap] WARN: $(basename "$s") failed (continuing)"
done

# 个人开发环境 (可选): /opt/dev 由 docker-compose.dev.yml 挂载, 标准部署不存在
for s in /opt/dev/*.sh; do
  [ -e "$s" ] || continue
  echo "[dev] >>> $(basename "$s")"
  sh "$s" || echo "[dev] WARN: $(basename "$s") failed (continuing)"
done

exec /opt/scripts/plan-boot.sh "$@"
