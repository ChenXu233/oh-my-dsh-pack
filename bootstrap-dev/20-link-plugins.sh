#!/bin/sh
# ============================================================================
# 个人开发环境专用: 把挂载进来的【每个插件子目录】link 进 web profile
# ----------------------------------------------------------------------------
# 目录约定: /opt/dev-plugins/<插件名>/  每个子目录是一个可加载的包
#           (有 package.json, 且 lib/index.js 已构建)
#
# 这个目录只有在用 docker-compose.dev.yml 启动时才会被挂载, 标准部署不会执行到这里。
#
# 与 bootstrap/10-plugins.sh 的分工:
#   bootstrap/10-plugins.sh  装"发布物"(npm 包), 改代码必须发版; 它在镜像里,
#                            所以每次改动都要重建镜像。
#   bootstrap-dev/20-...sh   装"源码"(link: 依赖), 指向宿主机挂进来的目录,
#                            改代码只需同步构建产物 + 重启容器, 不必发版。
#
# 幂等: 容器每次启动都会跑, 重复装同一个 link 没有副作用。
# ============================================================================
set -e

ROOT="${DSH_DEV_PLUGINS_DIR:-/opt/dev-plugins}"
PROFILE="${DSH_DEV_PROFILE:-web}"

if [ ! -d "$ROOT" ]; then
  echo "[dev] skip: 没有挂载 $ROOT (标准部署的正常情况)"
  exit 0
fi

if ! command -v pnpm >/dev/null 2>&1; then
  echo "[dev] WARN: pnpm 不在 PATH, 无法执行 link 安装 (dsh plugin 依赖 pnpm)"
  exit 0
fi

found=0
for dir in "$ROOT"/*/; do
  [ -d "$dir" ] || continue
  dir="${dir%/}"
  name="$(basename "$dir")"

  if [ ! -f "$dir/package.json" ]; then
    echo "[dev] skip $name: 缺 package.json"
    continue
  fi
  if [ ! -f "$dir/lib/index.js" ]; then
    echo "[dev] skip $name: 缺 lib/index.js (先在该插件仓库里 pnpm build)"
    continue
  fi

  found=$((found + 1))
  echo "[dev] linking $name <- $dir"
  if dsh plugin --profile "$PROFILE" add "link:$dir"; then
    echo "[dev] linked: $name"
  else
    echo "[dev] WARN: $name link 安装失败, 继续启动(该插件本轮不可用)"
  fi
done

if [ "$found" -eq 0 ]; then
  echo "[dev] 没有可链接的插件: 在 $ROOT 下为每个插件建一个子目录, 放入 package.json 与 lib/"
fi
