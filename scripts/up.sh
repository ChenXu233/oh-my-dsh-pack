#!/usr/bin/env bash
# ============================================================================
# 选一个方向启动（或起开发实例）
# ----------------------------------------------------------------------------
#   ./scripts/up.sh                 # 默认 full
#   ./scripts/up.sh chat
#   ./scripts/up.sh harness
#   ./scripts/up.sh dev             # 开发实例（独立栈，不碰生产）
#   ./scripts/up.sh --build full    # 本地构建镜像再起
#
# 作用: 读 plans/<方向>/plan.env, 按 PLAN_ENV 选镜像 tag, 再交给 docker compose。
# 镜像名可用 DSH_IMAGE 覆盖（想钉版本时用）。
# ============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

BUILD_FLAG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --build) BUILD_FLAG="--build"; shift ;;
    *) break ;;
  esac
done

PLAN="${1:-full}"
shift || true

if [ ! -d "plans/$PLAN" ]; then
  echo "未知方向: $PLAN"
  echo "可用方向: $(ls plans | tr '\n' ' ')"
  exit 1
fi

# shellcheck disable=SC1090
. "plans/$PLAN/plan.env"

case "${PLAN_ENV:-capable}" in
  capable) IMAGE_TAG=latest; BUILD_TARGET=capable ;;
  base)    IMAGE_TAG=slim;   BUILD_TARGET=slim ;;
  *)
    echo "plans/$PLAN/plan.env 的 PLAN_ENV 非法: ${PLAN_ENV}"
    exit 1
    ;;
esac

IMAGE="${DSH_IMAGE:-docker.cnb.cool/chenxu233/oh-my-dsh-pack:$IMAGE_TAG}"

echo "[plan] $PLAN — ${PLAN_TITLE:-}"
echo "[plan] env: $PLAN_ENV -> $IMAGE"

# 开发实例: 独立 compose 栈（自己的项目名/卷/端口），不碰生产
if [ "$PLAN" = "dev" ]; then
  export DSH_PLAN="$PLAN"
  export DSH_DEV_IMAGE="${DSH_DEV_IMAGE:-$IMAGE}"
  exec docker compose -f docker-compose.dev.yml up -d $BUILD_FLAG "$@"
fi

# 方向写进 .env: 之后 deploy 的 `docker compose up -d` 会读它,
# 不会被打回默认 full / :latest
set_env() {
  key="$1"; val="$2"
  touch .env
  grep -v "^${key}=" .env > .env.tmp 2>/dev/null || true
  printf '%s=%s\n' "$key" "$val" >> .env.tmp
  mv .env.tmp .env
}
set_env DSH_PLAN "$PLAN"
set_env DSH_IMAGE "$IMAGE"
export DSH_PLAN="$PLAN"
export DSH_IMAGE="$IMAGE"
export DSH_TARGET="$BUILD_TARGET"

if [ "${PLAN_ENTRY:-web}" = "headless" ]; then
  exec docker compose run --rm dsh "$@"
fi

exec docker compose up -d $BUILD_FLAG "$@"
