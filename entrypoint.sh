#!/bin/sh
set -e

# 内置 web profile 首次启动会从随附模板自动初始化, 无需手动 seed
for s in /opt/bootstrap/*.sh; do
  [ -e "$s" ] || continue
  echo "[bootstrap] >>> $(basename "$s")"
  sh "$s" || echo "[bootstrap] WARN: $(basename "$s") failed (continuing)"
done

exec dsh --profile web --no-open --host 127.0.0.1 --public-url https://harness.chenxu233.cn --trusted-host harness.chenxu233.cn "$@"
