#!/bin/sh
# ============================================================================
# 个人开发环境专用: 把挂载进来的【每个插件子目录】link 进 web profile
# ----------------------------------------------------------------------------
# 目录约定: /opt/dev-plugins/<插件名>/
#   必须有 package.json, 且它声明的入口(exports["."] / main, 缺省 lib/index.js)
#   已经构建出来。不假定入口一定叫 lib/index.js —— 多入口包(靠 exports 子路径被
#   cordis.patch.yml 引用)也是合法的。
#
# 只适用于【零运行时依赖】的插件:
#   pnpm 的 link: 只建符号链接, **不会给被链接的目录装依赖**。实测: 被链接的包在
#   运行时 require 自己的 dependency 会直接 MODULE_NOT_FOUND。
#   所以有 dependencies 又没有自带 node_modules 的包会被跳过, 并打印打包安装的写法。
#
# 这个目录只有在用 docker-compose.dev.yml 启动时才会被挂载, 标准部署不会执行到这里。
#
# 与 plans/<方案>/plugins.txt 的分工:
#   plans/<方案>/plugins.txt 装"发布物"(npm 包), 改代码必须发版; 它在镜像里,
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

# 入口: 读 package.json 声明的那个, 而不是假定 lib/index.js
entry_of() {
  node -e '
    const fs = require("fs"), path = require("path");
    const dir = process.argv[1];
    let pkg = {};
    try { pkg = JSON.parse(fs.readFileSync(path.join(dir, "package.json"), "utf8")); } catch { process.exit(0); }
    const pick = (v) => (typeof v === "string" ? v : v && (v.default || v.import || v.node));
    let entry;
    if (pkg.exports) entry = typeof pkg.exports === "string" ? pkg.exports : pick(pkg.exports["."]);
    entry = entry || pkg.main || "lib/index.js";
    if (!fs.existsSync(path.resolve(dir, entry))) process.exit(0);
    process.stdout.write(entry);
  ' "$1"
}

# 运行时依赖个数
deps_of() {
  node -e '
    const p = require(process.argv[1] + "/package.json");
    process.stdout.write(String(Object.keys(p.dependencies || {}).length));
  ' "$1"
}

found=0
skipped=0
for dir in "$ROOT"/*/; do
  [ -d "$dir" ] || continue
  dir="${dir%/}"
  name="$(basename "$dir")"

  if [ ! -f "$dir/package.json" ]; then
    echo "[dev] skip $name: 缺 package.json"
    skipped=$((skipped + 1))
    continue
  fi

  entry="$(entry_of "$dir")"
  if [ -z "$entry" ]; then
    echo "[dev] skip $name: 入口文件不存在 (先在该插件仓库里构建)"
    skipped=$((skipped + 1))
    continue
  fi

  deps="$(deps_of "$dir")"
  if [ "$deps" -gt 0 ] && [ ! -d "$dir/node_modules" ]; then
    echo "[dev] skip $name: 有 $deps 个运行时依赖, 但目录里没有 node_modules"
    echo "        link: 不会给被链接的目录装依赖, 装上也会在加载时报 MODULE_NOT_FOUND。"
    echo "        改用打包安装(之后流程与 link 一样, 只是改代码要多 pack 一次):"
    echo "          pnpm pack                                # 在该插件仓库里"
    echo "          dsh plugin --profile $PROFILE add /abs/path/<包名>-<版本>.tgz"
    skipped=$((skipped + 1))
    continue
  fi

  found=$((found + 1))
  echo "[dev] linking $name <- $dir ($entry)"
  if dsh plugin --profile "$PROFILE" add "link:$dir"; then
    echo "[dev] linked: $name"
  else
    echo "[dev] WARN: $name link 安装失败, 继续启动(该插件本轮不可用)"
  fi
done

if [ "$found" -eq 0 ]; then
  echo "[dev] 没有可链接的插件 (跳过 $skipped 个): 在 $ROOT 下为每个插件建一个子目录,"
  echo "       放入 package.json 与构建产物; 有运行时依赖的包请走 pnpm pack + tgz 安装。"
fi
