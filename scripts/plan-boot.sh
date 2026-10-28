#!/bin/sh
# ============================================================================
# 按"方案"启动: 读 plans/<plan>/plan.env + plugins.txt, 装插件, 再 exec dsh
# ----------------------------------------------------------------------------
# 方案的差异只有三件事:
#   1. 用哪个 dsh profile (web / headless)
#   2. 预装哪些插件    (plugins.txt, 没有就跳过)
#   3. 用什么方式启动  (常驻 web 服务 / 一次性 headless)
#
# 环境变量:
#   DSH_PLAN        方案名, 默认 full
#   DSH_PLANS_DIR   方案目录, 默认 /opt/plans
#   DSH_PUBLIC_URL  web 入口对外地址(可选)
#   DSH_TRUSTED_HOST 额外信任的 authority(可选)
#   DSH_BIND_HOST   绑定地址, 默认取容器第一个 IP
# ============================================================================
set -e

PLAN="${DSH_PLAN:-full}"
PLANS_DIR="${DSH_PLANS_DIR:-/opt/plans}"
DIR="$PLANS_DIR/$PLAN"

if [ ! -d "$DIR" ]; then
  echo "[plan] 未知方案: $PLAN"
  echo "[plan] 可用方案: $(ls "$PLANS_DIR" 2>/dev/null | tr '\n' ' ')"
  exit 1
fi

# shellcheck disable=SC1090
. "$DIR/plan.env"
PROFILE="${PLAN_PROFILE:-web}"
ENTRY="${PLAN_ENTRY:-web}"

echo "[plan] >>> plan=$PLAN profile=$PROFILE entry=$ENTRY  ${PLAN_TITLE:-}"

# 可选: 先清空该 profile 再按当前方案重建(会丢会话历史)
#   DSH_PLAN_RESET=1 docker compose run --rm dsh
if [ "${DSH_PLAN_RESET:-0}" = "1" ]; then
  RESET_DIR="${DSH_HOME:-/data/dsh-home}/profiles/$PROFILE"
  echo "[plan] RESET: 清空 $RESET_DIR"
  rm -rf "$RESET_DIR"
  # RESET_ONLY=1 只清不启动, 用于"换方案前先把 profile 推平"
  if [ "${DSH_PLAN_RESET_ONLY:-0}" = "1" ]; then
    echo "[plan] RESET_ONLY: 已清空, 退出"
    exit 0
  fi
fi

# --- 1. 先把 profile 材料化 -------------------------------------------------
# shipped profile(web / headless)第一次被引用时才落地成 $DSH_HOME/profiles/<name>。
# 不先跑这一步, 下面的 plugin add 会因为目录不存在而失败(旧版 bootstrap 就栽在这)。
dsh --profile "$PROFILE" --dump-config >/dev/null 2>&1 || \
  echo "[plan] WARN: profile $PROFILE 初始化失败, 继续尝试启动"

# --- 2. 按方案装插件 --------------------------------------------------------
# 每次都重装 30 个包会让重启变慢, 所以装成功后在 profile 里留一个清单指纹;
# 清单没变就跳过, 变了或上次有失败才重装。
PROFILE_DIR="${DSH_HOME:-/data/dsh-home}/profiles/$PROFILE"
STAMP="$PROFILE_DIR/.plan-$PLAN.stamp"
PLUGIN_HASH=""
if [ -f "$DIR/plugins.txt" ]; then
  PLUGIN_HASH="$(sha256sum "$DIR/plugins.txt" | awk '{print $1}')"
  # 只有 profile 目录确实存在时才可能命中指纹; 目录没落地就老老实实装
  if [ -d "$PROFILE_DIR" ] && [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$PLUGIN_HASH" ]; then
    echo "[plan] 插件清单未变, 跳过预装"
    PLUGIN_HASH=""
  fi
fi

if [ -f "$DIR/plugins.txt" ] && [ -n "$PLUGIN_HASH" ]; then
  INSTALL_FAILED=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue ;;
    esac
    # 去掉行尾注释(前置必须有空白, 否则 github:...#sha 会被截断)
    spec=$(printf '%s' "$line" | sed 's/[[:space:]]#.*$//' | sed 's/[[:space:]]*$//')
    [ -n "$spec" ] || continue
    echo "[plan] install $spec"
    dsh plugin --profile "$PROFILE" add "$spec" || {
      INSTALL_FAILED=1
      echo "[plan] WARN: $spec 安装失败(继续启动)"
    }
  done < "$DIR/plugins.txt"

  # 有失败就不留指纹, 下次启动重试
  if [ "$INSTALL_FAILED" -eq 0 ]; then
    printf '%s\n' "$PLUGIN_HASH" > "$STAMP" 2>/dev/null || true
  fi
fi

# --- 3. 启动 ----------------------------------------------------------------
case "$ENTRY" in
  web)
    BIND="${DSH_BIND_HOST:-}"
    if [ -z "$BIND" ]; then
      # 容器里必须绑容器 IP 而不是 127.0.0.1, 否则 docker-proxy 转发不可达
      BIND="$(hostname -i 2>/dev/null | awk '{print $1}')"
      [ -n "$BIND" ] || BIND=127.0.0.1
    fi
    EXTRA=""
    [ -n "${DSH_PUBLIC_URL:-}" ] && EXTRA="$EXTRA --public-url $DSH_PUBLIC_URL"
    [ -n "${DSH_TRUSTED_HOST:-}" ] && EXTRA="$EXTRA --trusted-host $DSH_TRUSTED_HOST"
    echo "[plan] boot web profile on $BIND"
    # shellcheck disable=SC2086
    exec dsh --profile "$PROFILE" --no-open --host "$BIND" $EXTRA "$@"
    ;;
  headless)
    echo "[plan] boot headless profile"
    exec dsh --profile "$PROFILE" "$@"
    ;;
  *)
    echo "[plan] 未知 PLAN_ENTRY: $ENTRY"
    exit 1
    ;;
esac