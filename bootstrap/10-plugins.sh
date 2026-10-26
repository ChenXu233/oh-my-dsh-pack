#!/bin/sh
# ===== 私人插件预安装清单 =====
# 每行一个包名 (npm 包名或 git url), # 开头为注释; 幂等, 失败不阻断
set -e
PROFILE_DIR="${DSH_HOME:-/data/dsh-home}/profiles/web"
[ -d "$PROFILE_DIR" ] || { echo "[plugins] profile dir missing, skip"; exit 0; }

PLUGINS="
# @deepseek-ai/dsh-example-plugin
"

for p in $PLUGINS; do
  case "$p" in ''|'#'*) continue ;; esac
  echo "[plugins] installing $p"
  dsh plugin --profile web add "$p" || echo "[plugins] WARN: $p install failed"
done
echo "[plugins] done"
