#!/bin/bash
# 组装 X32Remote.app：编译 Swift 外壳（x86_64 / 10.14.6）+ 拷贝模拟器脚本 + Python 框架 + 图标。
# 前置：scripts/build_python.sh 已产出 build/python/Python.framework，
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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BUILD/X32Remote" "$APP/Contents/MacOS/X32Remote"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$SIM_SRC" "$APP/Contents/Resources/x32_simulator.py"

FW="$BUILD/python/Python.framework"
if [ ! -d "$FW" ]; then
    echo "缺少 $FW —— 先执行 scripts/build_python.sh" >&2
    exit 1
fi
cp -R "$FW" "$APP/Contents/Frameworks/"
find "$APP/Contents/Frameworks/Python.framework" -name "__pycache__" -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "$APP/Contents/Frameworks/Python.framework" -name "*.pyc" -delete 2>/dev/null || true

echo "== 生成图标 =="
swiftc -O -sdk "$SDK" -o "$BUILD/make_icon" "$ROOT/tools/make_icon.swift"
"$BUILD/make_icon" "$BUILD/AppIcon.iconset"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$BUILD/AppIcon.iconset"

echo "== 完成 =="
echo "$APP"
du -sh "$APP"
