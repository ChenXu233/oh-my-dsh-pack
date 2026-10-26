#!/bin/sh
# ============================================================================
# 个人开发环境专用: 把挂载进来的插件源码 link 进 web profile
# ----------------------------------------------------------------------------
# 这个目录只有在用 docker-compose.dev.yml 启动时才会被挂到容器的 /opt/dev,
# 标准部署 (只用 docker-compose.yml) 根本不会执行到这里。
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

MESH_DIR="${DSH_MESH_DIR:-/opt/mesh}"
PROFILE="${DSH_MESH_PROFILE:-web}"

# 1) 没挂源码, 或者源码还没 build -> 跳过(普通部署的正常情况)
if [ ! -f "$MESH_DIR/package.json" ] || [ ! -f "$MESH_DIR/lib/index.js" ]; then
  echo "[dev] skip: $MESH_DIR 里没有构建好的插件(源码未挂载, 或还没 build)"
  echo "[dev] hint: 若你之前装过 link 又不再用这条链路, 用 'dsh plugin --profile $PROFILE remove dsh-workspace-mesh' 清掉悬空依赖"
  exit 0
fi

# 2) dsh plugin 靠 PATH 上的 pnpm 干活
if ! command -v pnpm >/dev/null 2>&1; then
  echo "[dev] WARN: pnpm 不在 PATH, 无法执行 link 安装"
  echo "[dev] WARN: dsh plugin 需要 pnpm; 在 Dockerfile 里加 'npm install -g pnpm' 并重建镜像"
  exit 0
fi

# 3) 装成 link 依赖。
#    装完 DSH 会识别出它声明了 dsh.bundle(自带 cordis.patch.yml),
#    写进 profile 的 dsh.profile.bundles, 并按其 patch 组合出 'id: mesh' 那一行,
#    插件随之挂载, agent 里就能用到 mesh_* 工具。
echo "[dev] linking $MESH_DIR into profile '$PROFILE'"
if dsh plugin --profile "$PROFILE" add "link:$MESH_DIR"; then
  echo "[dev] linked: $MESH_DIR"
else
  echo "[dev] WARN: link 安装失败, 继续启动(该插件本轮不可用)"
fi
