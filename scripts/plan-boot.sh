#!/bin/sh
# ============================================================================
# 按"方向"启动: 读 plans/<plan>/plan.env + plugins.txt, 装插件, 再 exec dsh
# ----------------------------------------------------------------------------
# 方向是数据: plans/ 由 compose 挂载到 /opt/plans（不在镜像里）。
# 方向的差异只有三件事:
#   1. 用哪个 dsh profile (web / headless)
#   2. 预装哪些插件    (plugins.txt, 没有就跳过)
#   3. 用什么方式启动  (常驻 web 服务 / 一次性 headless)
#
# 环境变量:
#   DSH_PLAN        方向名, 默认 full
#   DSH_PLANS_DIR   方向目录, 默认 /opt/plans（compose 挂载）
#   DSH_PUBLIC_URL  web 入口对外地址(可选)
#   DSH_TRUSTED_HOST 额外信任的 authority(可选)
#   DSH_BIND_HOST   绑定地址, 默认取容器第一个 IP
# ============================================================================
set -e

PLAN="${DSH_PLAN:-full}"
PLANS_DIR="${DSH_PLANS_DIR:-/opt/plans}"
DIR="$PLANS_DIR/$PLAN"

if [ ! -d "$PLANS_DIR" ]; then
  echo "[plan] 没有 $PLANS_DIR: compose 需要挂载 ./plans:/opt/plans:ro"
  exit 1
fi

if [ ! -d "$DIR" ]; then
  echo "[plan] 未知方向: $PLAN"
  echo "[plan] 可用方向: $(ls "$PLANS_DIR" 2>/dev/null | tr '\n' ' ')"
  exit 1
fi

# shellcheck disable=SC1090
. "$DIR/plan.env"
PROFILE="${PLAN_PROFILE:-web}"
ENTRY="${PLAN_ENTRY:-web}"

echo "[plan] >>> plan=$PLAN profile=$PROFILE entry=$ENTRY  ${PLAN_TITLE:-}"

# 可选: 先清空该 profile 再按当前方向重建(会丢会话历史)
#   DSH_PLAN_RESET=1 docker compose run --rm dsh
if [ "${DSH_PLAN_RESET:-0}" = "1" ]; then
  RESET_DIR="${DSH_HOME:-/data/dsh-home}/profiles/$PROFILE"
  echo "[plan] RESET: 清空 $RESET_DIR"
  rm -rf "$RESET_DIR"
  # RESET_ONLY=1 只清不启动, 用于"换方向前先把 profile 推平"
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

# --- 2. 按方向装插件 --------------------------------------------------------
# 只装"新增/变更"的 spec: profile 里记住上次成功应用的清单(.applied),
# 启动时和当前 plugins.txt 做 diff; 没变的行跳过, 变了才 add。
# 这样改一行清单只会装那一行, 不会把整份清单重装一遍。
PROFILE_DIR="${DSH_HOME:-/data/dsh-home}/profiles/$PROFILE"
STAMP="$PROFILE_DIR/.plan-$PLAN.stamp"
APPLIED="$PROFILE_DIR/.plan-$PLAN.applied"
CUR="$PROFILE_DIR/.plan-$PLAN.current"

# 归一化: 去注释/空行, 只留 spec (行尾注释的前置空白必须有, 否则 github:...#sha 会被截断)
normalize_plugins() {
  sed -e 's/[[:space:]]#.*$//' -e 's/[[:space:]]*$//' "$1" | \
    grep -v '^[[:space:]]*$' | grep -v '^[[:space:]]*#' || true
}

if [ -f "$DIR/plugins.txt" ] && [ -d "$PROFILE_DIR" ]; then
  normalize_plugins "$DIR/plugins.txt" > "$CUR"
  PLUGIN_HASH="$(sha256sum "$CUR" | awk '{print $1}')"

  # 清单和上次应用的一致 -> 跳过
  if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$PLUGIN_HASH" ] && [ -f "$APPLIED" ]; then
    echo "[plan] 插件清单未变, 跳过预装"
  else
    INSTALL_FAILED=0
    NEW_COUNT=0
    SKIP_COUNT=0
    while IFS= read -r spec || [ -n "$spec" ]; do
      [ -n "$spec" ] || continue
      # 上次已经应用过的 spec 直接跳过
      if [ -f "$APPLIED" ] && grep -Fxq "$spec" "$APPLIED"; then
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
      fi
      echo "[plan] install $spec"
      NEW_COUNT=$((NEW_COUNT + 1))
      dsh plugin --profile "$PROFILE" add "$spec" || {
        INSTALL_FAILED=1
        echo "[plan] WARN: $spec 安装失败(继续启动)"
      }
    done < "$CUR"

    # 只提示, 不自动 remove: 手装/网页装的包和 link 包不应该被清单误删
    if [ -f "$APPLIED" ]; then
      REMOVED="$(grep -Fxv -f "$CUR" "$APPLIED" 2>/dev/null || true)"
      if [ -n "$REMOVED" ]; then
        echo "[plan] 清单里删掉了(仍保留已装):"
        printf '%s\n' "$REMOVED" | sed 's/^/  - /'
      fi
    fi

    echo "[plan] 本次新增/变更 $NEW_COUNT 个, 跳过未变 $SKIP_COUNT 个"

    # 有失败就不留指纹, 下次启动只重试失败/新增的
    if [ "$INSTALL_FAILED" -eq 0 ]; then
      cp "$CUR" "$APPLIED" 2>/dev/null || true
      printf '%s\n' "$PLUGIN_HASH" > "$STAMP" 2>/dev/null || true
    fi
  fi
fi

# 插件没装上或 YAML 坏了都会让 dsh 起不来: 先验证再叠加
PATCH_ARGS=""
PLAN_PATCH="$DIR/patch.yml"
if [ -f "$PLAN_PATCH" ]; then
  PATCH_OK=1
  node --input-type=module - "$PLAN_PATCH" "$PROFILE_DIR" "$DIR/plugins.txt" <<'NODE' || PATCH_OK=0
import { existsSync, readFileSync } from 'node:fs';
const [patchFile, profile, listFile] = process.argv.slice(2);
const specName = (spec) => { const at = spec.lastIndexOf('@'); return at > 0 ? spec.slice(0, at) : spec; };
const specs = existsSync(listFile)
  ? readFileSync(listFile, 'utf8').split(/\r?\n/)
      .map((line) => line.replace(/\s+#.*$/, '').trim()).filter((line) => line && !line.startsWith('#'))
  : [];
const listed = new Set(specs.map(specName));
const deps = JSON.parse(readFileSync(profile + '/package.json', 'utf8')).dependencies ?? {};
const names = [...readFileSync(patchFile, 'utf8').matchAll(/^\s*name:\s*["']?([^"'\s#]+)/gm)].map((m) => m[1]);
const missing = names.filter((name) => listed.has(name) && deps[name] === undefined);
if (missing.length > 0) { console.error('missing: ' + missing.join(' ')); process.exit(1); }
NODE
  dsh --profile "$PROFILE" --dump-config --patch "$PLAN_PATCH" >/dev/null 2>&1 || PATCH_OK=0
  if [ "$PATCH_OK" = 1 ]; then
    PATCH_ARGS="--patch $PLAN_PATCH"
    echo "[plan] 叠加计划级 patch: $PLAN_PATCH"
  else
    echo "[plan] WARN: $PLAN_PATCH 校验失败, 跳过"
  fi
fi

# plans/<方向>/config/ 里的文件只在目标不存在时落进 $DSH_HOME
if [ -d "$DIR/config" ]; then
  for f in "$DIR"/config/*; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    target="${DSH_HOME:-/data/dsh-home}/$name"
    if [ -e "$target" ]; then
      echo "[plan] config $name 已存在, 跳过"
    else
      cp "$f" "$target" && echo "[plan] config $name 初始化"
    fi
  done
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
    exec dsh --profile "$PROFILE" $PATCH_ARGS --no-open --host "$BIND" $EXTRA "$@"
    ;;
  headless)
    echo "[plan] boot headless profile"
    # shellcheck disable=SC2086
    exec dsh --profile "$PROFILE" $PATCH_ARGS "$@"
    ;;
  *)
    echo "[plan] 未知 PLAN_ENTRY: $ENTRY"
    exit 1
    ;;
esac