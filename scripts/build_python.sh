#!/bin/bash
# 从源码编译 Python 3.14.8（x86_64，部署目标 10.14.6），产出 build/python/（bin + lib，可重定位）。
#
# 为什么不用 python.org 的 universal2 安装包：其 x86_64 slice 的最低系统版本不受控，
# 无法保证能在 10.14.6 运行；源码编译可以显式指定 MACOSX_DEPLOYMENT_TARGET。
#
# 为什么不用 --enable-framework：framework 构建的 make install 会连带编译
# Mac/PythonLauncher.app（上古 Xcode 工程，新版工具链必失败），而本应用只是
# 子进程调用 Python，不嵌 C API —— 普通 prefix 构建即可，靠 CPython 的
# landmark 机制（bin/python3 + lib/python3.14/os.py）保持可重定位。
set -euo pipefail
PY_VER="${PY_VER:-3.14.8}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/python"
if [ -x "$OUT/python/bin/python3" ]; then
    echo "已存在 $OUT/python/bin/python3，跳过构建"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
echo "== 下载 Python-$PY_VER 源码 =="
curl -fsSL -o Python.tgz "https://www.python.org/ftp/python/$PY_VER/Python-$PY_VER.tgz"
tar xf Python.tgz
cd "Python-$PY_VER"

echo "== configure (MACOSX_DEPLOYMENT_TARGET=10.14.6, 关闭 _sqlite3) =="
# 为什么关 _sqlite3：macOS SDK 把 sqlite3_create_window_function 标为 10.15+，
# 而 CPython 的 _sqlite/connection.c 无条件调用它，且自带 -Werror=unguarded-availability，
# 10.14.6 部署目标下直接编译失败。不能降级该警告（那等于发布一个在老系统上
# 加载不了、或调用不存在符号的 .so），必须让这个模块根本不进构建。
#
# 必须在 configure 层关：Modules/Setup.stdlib 会在 make 时由 config.status
# 从 Setup.stdlib.in 重新生成，事后注释清单会被覆盖掉（踩过一次）。
# _sqlite3 的启用条件见 configure.ac 8313 行：have_sqlite3=yes && have_supported_sqlite3=yes。
# 两个开关同时给：检测层（ac_cv_header_sqlite3_h）+ 模块层（py_cv_module__sqlite3）。
./configure \
    --prefix="$OUT/python" \
    MACOSX_DEPLOYMENT_TARGET=10.14.6 \
    --with-ensurepip=no \
    --disable-test-modules \
    ac_cv_header_sqlite3_h=no \
    py_cv_module__sqlite3=n/a \
    >configure.log 2>&1 || { tail -40 configure.log; exit 1; }

# 断言：清单里 _sqlite3 必须已注释，否则编译必炸——早失败早报，别等 3 分钟后
if [ -f Modules/Setup.stdlib ]; then
    if grep -qE '^_sqlite3[[:space:]]' Modules/Setup.stdlib; then
        echo "错误：_sqlite3 仍处于启用状态，configure 开关未生效" >&2
        grep -n "_sqlite3" Modules/Setup.stdlib >&2
        exit 1
    fi
    grep -n "_sqlite3" Modules/Setup.stdlib || echo "Setup.stdlib 中已无 _sqlite3 条目"
fi

echo "== make -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4) =="
make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" >make.log 2>&1 || { tail -40 make.log; exit 1; }

echo "== make install =="
mkdir -p "$OUT"
rm -rf "$OUT/python"
make install >install.log 2>&1 || { tail -40 install.log; exit 1; }

if [ ! -x "$OUT/python/bin/python3" ]; then
    echo "安装后未找到 $OUT/python/bin/python3" >&2
    ls -R "$OUT" | head -30 >&2
    exit 1
fi
echo "== 完成: $OUT/python/bin/python3 =="
du -sh "$OUT/python"
