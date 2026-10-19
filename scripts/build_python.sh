#!/bin/bash
# 从源码编译 Python 3.14.8（x86_64，部署目标 10.14.6），产出 build/python/Python.framework。
# 为什么不用 python.org 的 universal2 安装包：其 x86_64 slice 的最低系统版本不受控，
# 无法保证能在 10.14.6 运行；源码编译可以显式指定 MACOSX_DEPLOYMENT_TARGET。
set -euo pipefail
PY_VER="${PY_VER:-3.14.8}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/python"
if [ -d "$OUT/Python.framework" ]; then
    echo "已存在 $OUT/Python.framework，跳过构建"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
echo "== 下载 Python-$PY_VER 源码 =="
curl -fsSL -o Python.tgz "https://www.python.org/ftp/python/$PY_VER/Python-$PY_VER.tgz"
tar xf Python.tgz
cd "Python-$PY_VER"

echo "== configure (MACOSX_DEPLOYMENT_TARGET=10.14.6) =="
./configure \
    --prefix="$WORK/install" \
    --enable-framework="$OUT/Python.framework" \
    MACOSX_DEPLOYMENT_TARGET=10.14.6 \
    --with-ensurepip=no \
    --disable-test-modules \
    >configure.log 2>&1 || { tail -40 configure.log; exit 1; }

# 禁用 _sqlite3：macOS SDK 的 sqlite3.h 把 sqlite3_create_window_function 标为 10.15+，
# 10.14.6 部署目标下 CPython 的 -Werror=unguarded-availability 会直接编译失败。
# 不降级该警告（那等于发布一个在老系统上加载不了、或调用不存在符号的 .so），
# 而是把模块从构建清单摘掉——模拟器用不到 sqlite。
for f in Modules/Setup.stdlib.in Modules/Setup.stdlib; do
    if [ -f "$f" ]; then
        sed -i '' 's/^\(@MODULE__SQLITE3_TRUE@\)/#\1/' "$f" 2>/dev/null || true
        sed -i '' 's/^\(_sqlite3[[:space:]]\)/#\1/' "$f" 2>/dev/null || true
    fi
done
echo "-- 模块清单状态 --"
ls -1 Modules/Setup* 2>/dev/null || true
if [ -f Modules/Setup.stdlib ]; then
    grep -n "_sqlite3" Modules/Setup.stdlib || echo "Setup.stdlib 中已无 _sqlite3 条目"
fi

echo "== make -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4) =="
make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" >make.log 2>&1 || { tail -40 make.log; exit 1; }
make install >install.log 2>&1 || { tail -40 install.log; exit 1; }

# 框架位置在不同版本间有差异，统一找出来放到 OUT
mkdir -p "$OUT"
FW="$(find "$WORK" -maxdepth 5 -type d -name "Python.framework" | head -1 || true)"
if [ -z "$FW" ]; then
    echo "构建后未找到 Python.framework" >&2
    exit 1
fi
rm -rf "$OUT/Python.framework"
cp -R "$FW" "$OUT/Python.framework"
echo "== 完成: $OUT/Python.framework =="
