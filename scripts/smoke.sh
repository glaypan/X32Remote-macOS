#!/bin/bash
# 冒烟：验证 .app 内的 Python 真的能跑、部署目标不超 10.14.6、模拟器能无头启动。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/X32Remote.app"
PREFIX="$APP/Contents/Resources/python"
PYBIN="$PREFIX/bin/python3"
TMP="${RUNNER_TEMP:-/tmp}"
mkdir -p "$TMP"

if [ ! -x "$PYBIN" ]; then
    echo "找不到内置 Python: $PYBIN" >&2
    exit 1
fi
echo "== 冒烟对象: $PYBIN =="

echo "== 1. 标准库导入冒烟（模拟器实际用到的模块） =="
"$PYBIN" -c "import argparse, collections, json, math, os, socket, socketserver, struct, sys, threading, time, urllib.parse, http.server; print('imports ok')"

echo "== 2. 重定位：sys.executable 与 sys.prefix 都必须位于 .app 内 =="
"$PYBIN" -c "import sys; assert 'X32Remote.app' in sys.executable, 'sys.executable=' + sys.executable; assert 'X32Remote.app' in sys.prefix, 'sys.prefix=' + sys.prefix; print('relocation ok:', sys.prefix)"

echo "== 3. 部署目标断言（所有 Mach-O 的 minos ≤ 10.14.6） =="
"$PYBIN" "$ROOT/scripts/check_deployment.py" "$PREFIX" "10.14.6"

echo "== 4. 模拟器无头启动 + /api/state + 控制台 HTML =="
PORT=18080
"$PYBIN" "$APP/Contents/Resources/x32_simulator.py" \
    --web-port "$PORT" --config "$TMP/smoke_config.json" > "$TMP/sim_smoke.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT
ok=""
for _ in $(seq 1 60); do
    if curl -fsS "http://127.0.0.1:$PORT/api/state" -o "$TMP/state.json" 2>/dev/null; then ok=1; break; fi
    sleep 0.25
done
if [ -z "$ok" ]; then
    echo "模拟器 15 秒未就绪，日志：" >&2
    cat "$TMP/sim_smoke.log" >&2
    exit 1
fi
"$PYBIN" -c "import json,sys; d=json.load(open(sys.argv[1])); assert isinstance(d, dict) and d, 'state 不是非空 dict'; print('state keys:', len(d))" "$TMP/state.json"
curl -fsS "http://127.0.0.1:$PORT/" | grep -q "X32 模拟器" && echo "console html ok"
kill $PID 2>/dev/null || true
trap - EXIT

echo "== 冒烟全部通过 =="
