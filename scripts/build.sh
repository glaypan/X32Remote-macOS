#!/bin/bash
# 组装 X32Remote.app：编译 Swift 外壳（x86_64 / 10.14.6）+ 拷贝模拟器脚本 + 内置 Python + 图标。
# 前置：scripts/build_python.sh 已产出 build/pyroot/（bin + lib），
#       build/x32_simulator.py 已就位（CI 从协议仓拉取；本地可手动拷贝）。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/X32Remote.app"
SIM_SRC="${SIM_SRC:-$BUILD/x32_simulator.py}"

SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$BUILD"

echo "== 编译 Swift 外壳 (x86_64-apple-macos10.14.6) =="
swiftc -target x86_64-apple-macos10.14.6 -swift-version 5 -O \
    -sdk "$SDK" \
    -o "$BUILD/X32Remote" \
    "$ROOT"/Sources/*.swift \
    -framework AppKit -framework WebKit -framework Foundation

echo "== 组装 .app =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/X32Remote" "$APP/Contents/MacOS/X32Remote"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$SIM_SRC" "$APP/Contents/Resources/x32_simulator.py"

PYROOT="$BUILD/pyroot"
if [ ! -x "$PYROOT/bin/python3" ]; then
    echo "缺少 $PYROOT/bin/python3 —— 先执行 scripts/build_python.sh" >&2
    exit 1
fi
cp -R "$PYROOT" "$APP/Contents/Resources/python"
find "$APP/Contents/Resources/python" -name "__pycache__" -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "$APP/Contents/Resources/python" -name "*.pyc" -delete 2>/dev/null || true

echo "== 生成图标 =="
swiftc -O -sdk "$SDK" -o "$BUILD/make_icon" "$ROOT/tools/make_icon.swift"
"$BUILD/make_icon" "$BUILD/AppIcon.iconset"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$BUILD/AppIcon.iconset"

echo "== 外部依赖硬闸：最终 .app 不得引用构建机私有动态库 =="
# v1.1.2 事故复盘：内置 Python 曾链 Homebrew keg-only 库（/usr/local/opt/...），
# 用户机上 dyld: Library not loaded，python3 起不来。构造脚本已在 pyroot 层拦过一次，
# 这里对组装后的 .app（含 Swift 外壳）再拦一次 —— 发布出去的东西必须自包含。
"$PYROOT/bin/python3" "$ROOT/tools/list_dylib_deps.py" "$APP"

echo "== 完成 =="
echo "$APP"
du -sh "$APP"
