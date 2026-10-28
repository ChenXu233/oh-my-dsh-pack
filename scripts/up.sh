#!/usr/bin/env bash
# ============================================================================
# 选一个安装方案起服务(或跑一次性任务)
# ----------------------------------------------------------------------------
#   ./scripts/up.sh                # 默认 full
#   ./scripts/up.sh mini
#   ./scripts/up.sh harness
#   ./scripts/up.sh coder "把测试修好"   # headless 方案: 一次性任务
#
# 作用: 读 plans/<方案>/plan.env, 决定用哪个镜像 tag, 再交给 docker compose。
# 镜像名可用 DSH_IMAGE 覆盖(想钉版本时用)。
# ============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

PLAN="${1:-full}"
shift || true

if [ ! -d "plans/$PLAN" ]; then
  echo "未知方案: $PLAN"
  echo "可用方案: $(ls plans | tr '\n' ' ')"
  exit 1
fi

# shellcheck disable=SC1090
. "plans/$PLAN/plan.env"

case "${PLAN_TIER:-slim}" in
  capable) DEFAULT_TAG=latest ;;
  slim)    DEFAULT_TAG=slim ;;
  *)
    echo "plans/$PLAN/plan.env 的 PLAN_TIER 非法: ${PLAN_TIER}"
    exit 1
    ;;
esac

export DSH_PLAN="$PLAN"
export DSH_IMAGE="${DSH_IMAGE:-docker.cnb.cool/chenxu233/oh-my-dsh-pack:$DEFAULT_TAG}"

echo "[plan] $PLAN — ${PLAN_TITLE:-}"
echo "[plan] image: $DSH_IMAGE"

if [ "${PLAN_ENTRY:-web}" = "headless" ]; then
  exec docker compose run --rm dsh "$@"
fi

exec docker compose up -d "$@"
