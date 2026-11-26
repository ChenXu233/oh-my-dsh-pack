#!/bin/sh
# ============================================================================
# 构建期: 把 plans/ 铺一份到镜像里当默认值, 让没有挂载的环境也能启动
# ----------------------------------------------------------------------------
# 为什么需要: 方向目录靠 compose 挂载(./plans:/opt/plans:ro), 而云原生开发
# 这类环境没有 compose、也挂不了宿主目录, /opt/plans 不存在 -> 入口脚本退出 1。
# 内嵌一份之后, 任何环境都能起来; 挂载了的话 plan-boot 优先用挂载的那份。
#
# 两个关键约束:
#   1. 必须复制, 不能 COPY 进镜像: .dockerignore 排了 plans/(compose 挂载是
#      唯一进容器的路), 构建上下文里根本没有这个目录。
#   2. 要 .git 才读得到: 镜像本身不带 git 目录, 构建上下文里的 .git 是 git clone
#      留下的。读不到就只记一行说明, 不失败(本地构建没有 .git 也能出镜像)。
#
# 用法(在仓库根目录执行, 已进 Dockerfile 的 base 阶段):
#   sh scripts/bake-plans.sh /opt/plans-default
# ============================================================================
set -e

DEST="${1:-/opt/plans-default}"

if [ -f plans/full/plan.env ] && [ -d plans ]; then
  mkdir -p "$DEST"
  cp -R plans/. "$DEST"/
  echo "[bake-plans] 从工作区复制 plans/ -> $DEST"
elif [ -d .git ]; then
  mkdir -p "$DEST"
  git archive HEAD plans | tar -x -C "$DEST" --strip-components=1
  echo "[bake-plans] 从 git 读出 plans/ -> $DEST"
else
  # 不是错误: 挂载方式照样能用, 只是失去了"没有 plans/ 也能启动"的兜底
  echo "[bake-plans] 跳过: 工作区和 .git 里都没有 plans/"
  exit 0
fi

[ -f "$DEST/full/plan.env" ] && echo "[bake-plans] 可用方向: $(ls "$DEST" | tr '\n' ' ')"
exit 0
