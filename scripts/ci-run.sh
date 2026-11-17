#!/usr/bin/env bash
# ============================================================================
# CI 门禁薄壳：跑一次 headless 任务，把 --json 流落盘；出现
# tool_result.status=error 或 dsh 自身非 0 退出时 exit 1。
# ----------------------------------------------------------------------------
# 用法：
#   ./scripts/ci-run.sh -w <WORKFLOW_ID> "prompt..."     # 固定 agent 走 PLAN_ARGS
#   ./scripts/ci-run.sh -a <AGENT_ID> -w <WF> "prompt"   # 或显式指定
#
# 原理：plan-boot 已经固化了 --json，输出是逐行 JSON；dsh 当前"工具失败仍
# exit 0"，所以必须用 jq 扫一遍 error 事件才能可靠判失败。
# ============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="${CI_JSON_OUT:-$(mktemp -t dsh-ci.XXXXXX.jsonl)}"
echo "[ci-run] json stream -> $OUT" >&2

set +e
./scripts/up.sh ci "$@" 2>&1 | tee "$OUT"
status=${PIPESTATUS[0]}
set -e

if [ "$status" -ne 0 ]; then
  echo "[ci-run] dsh 退出码 $status" >&2
  exit "$status"
fi

errors="$(jq -r 'select(.type=="tool_result" and .status=="error") | .result // "tool error"' "$OUT" 2>/dev/null || true)"
if [ -n "$errors" ]; then
  echo "[ci-run] 检测到工具失败：" >&2
  printf '%s\n' "$errors" >&2
  exit 1
fi

echo "[ci-run] OK" >&2
