#!/bin/bash
# 从源码编译 Python 3.14.8（x86_64，部署目标 10.14.6），产出 build/pyroot/（bin + lib，可重定位）。
#
# 为什么不用 python.org 的 universal2 安装包：其 x86_64 slice 的最低系统版本不受控，
# 无法保证能在 10.14.6 运行；源码编译可以显式指定 MACOSX_DEPLOYMENT_TARGET。
#
# 为什么不用 --enable-framework：framework 构建的 make install 会连带编译
# Mac/PythonLauncher.app（上古 Xcode 工程，新版工具链必失败），而本应用只是
# 子进程调用 Python，不嵌 C API —— 普通 prefix 构建即可，靠 CPython 的
# landmark 机制（bin/python3 + lib/python3.14/os.py）保持可重定位。
#
# ── v1.1.2 事故与修复（必读）───────────────────────────────────────────
# 旧脚本只给了 _sqlite3 两个开关，没管其它自动探测。CI runner（macos-15-intel）
# 的默认搜索路径 / pkg-config 能摸到 Homebrew 的 keg-only 库，CPython 的
# AC_CHECK_LIB([intl]...)、AC_CHECK_HEADERS([gdbm/ndbm.h]...)、
# PKG_CHECK_MODULES([liblzma/libzstd/libmpdec]) 一旦命中，就把
# /usr/local/opt/... 的**绝对 install name** 写进产物。用户机器上没有这些
# 文件 → `dyld: Library not loaded: /usr/local/opt/gettext/lib/libintl.8.dylib`
# → python3 根本起不来，App 弹"模拟器未能启动"。
# 实测中招 9 个 Mach-O：python3/python3.14（libintl）、_dbm/_gdbm（gdbm）、
# _decimal（mpdec）、_ssl/_hashlib（openssl@3）、_lzma（xz）、_zstd（zstd）。
# 这些模块本应用一个都用不到（内核只碰纯 stdlib + hashlib 内置 _sha*）。
#
# 对策三层，缺一不可：
#   1. configure 缓存变量开关：摁死 libintl / gdbm / ndbm / openssl / lzma / zstd
#      的探测，_decimal 改链内置静态 libmpdec（--with-system-libmpdec=no）；
#   2. pkg-config 过滤器：liblzma / libzstd 没有 --without 开关，configure 只认
#      pkg-config 的结果，让过滤器对这两个模块直接失败，退回的 fallback 再被
#      第 1 层的缓存变量摁死；
#   3. 构建后硬闸：make install 完扫描全部 Mach-O，任何指向系统库
#      （/usr/lib、/System）之外的动态库都让构建失败 —— 宁可 CI 红，不发坏包。
#      （缓存命中时也要过闸：actions/cache 里的旧 pyroot 可能是事故构建。）
set -euo pipefail
PY_VER="${PY_VER:-3.14.8}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/pyroot"

# 硬闸：内置 Python 的任何 Mach-O 都不得引用系统库之外的动态库。
# 用刚构建出来的 python3 自己跑（纯标准库脚本，顺便证明解释器能启动）。
gate() {
    echo "== 外部依赖硬闸：不得引用构建机私有动态库（/usr/local/opt、/opt/homebrew 等） =="
    "$OUT/bin/python3" "$ROOT/tools/list_dylib_deps.py" "$OUT"
}

if [ -x "$OUT/bin/python3" ]; then
    echo "已存在 $OUT/bin/python3，跳过构建（缓存命中也要过闸）"
    gate
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
echo "== 下载 Python-$PY_VER 源码 =="
curl -fsSL -o Python.tgz "https://www.python.org/ftp/python/$PY_VER/Python-$PY_VER.tgz"
tar xf Python.tgz
cd "Python-$PY_VER"

# pkg-config 过滤器：除 liblzma / libzstd 外全部原样透传。
# 这两个库在 runner 上只有 pkg-config 找得到（Homebrew keg-only），而 configure
# 没有 --without-lzma / --without-zstd 开关，PKG_CHECK_MODULES 一旦成功就直接
# 按绝对路径链接。让它们"找不到"，fallback 的头文件/符号检查再由 configure
# 行的 ac_cv_header_lzma_h=no 等缓存变量摁死。
cat > "$WORK/pkg-config-deny" <<'EOF'
#!/bin/bash
for arg in "$@"; do
  case "$arg" in
    liblzma*|libzstd*)
      echo "pkg-config-deny: $arg 是 keg-only 库，禁止进入可重定位构建" >&2
      exit 1
      ;;
  esac
done
exec pkg-config "$@"
EOF
chmod +x "$WORK/pkg-config-deny"

echo "== configure (MACOSX_DEPLOYMENT_TARGET=10.14.6, 关闭 _sqlite3, 切断 Homebrew 依赖) =="
# 为什么关 _sqlite3：macOS SDK 把 sqlite3_create_window_function 标为 10.15+，
# 而 CPython 的 _sqlite/connection.c 无条件调用它，且自带 -Werror=unguarded-availability，
# 10.14.6 部署目标下直接编译失败。不能降级该警告（那等于发布一个在老系统上
# 加载不了、或调用不存在符号的 .so），必须让这个模块根本不进构建。
#
# 必须在 configure 层关：Modules/Setup.stdlib 会在 make 时由 config.status
# 从 Setup.stdlib.in 重新生成，事后注释清单会被覆盖掉（踩过一次）。
# _sqlite3 的启用条件见 configure.ac 8313 行：have_sqlite3=yes && have_supported_sqlite3=yes。
# 两个开关同时给：检测层（ac_cv_header_sqlite3_h）+ 模块层（py_cv_module__sqlite3）。
#
# 其余新增开关（全部在 Python-3.14.8 生成的 configure 里逐个核对过变量名）：
#   ac_cv_header_libintl_h=no        **不能只禁 -lintl**：SDK 的 libintl.h 会把
#                                     setlocale/textdomain 等宏重命名成 libintl_*
#                                     符号（Apple 的 libintl.dylib 导出这套名字），
#                                     _localemodule.c 只要见到头文件就引用它们，
#                                     链接期必须提供 libintl。而 _locale.gettext /
#                                     textdomain 系列方法全库无人使用（locale.py 只用
#                                     _getdefaultlocale / getencoding，gettext.py 是
#                                     纯 Python 实现），禁掉头文件检测即可彻底不链
#                                     libintl，且不依赖"系统恰好有 /usr/lib/libintl"。
#   ac_cv_lib_intl_textdomain=no     双保险：WITH_LIBINTL 不定义，-lintl 不进 LIBS
#   ac_cv_header_gdbm_h=no            gdbm 头文件不存在 → _gdbm 不构建
#   ac_cv_header_ndbm_h=no            ndbm 头文件不存在 → _dbm 的 ndbm 分支不构建
#   ac_cv_header_gdbm_slash_ndbm_h=no / gdbm_dash_ndbm_h=no
#                                     **关键**：configure.ac 4623 行还有第二个
#                                     dbm_open 搜索，只由 gdbm/ndbm.h 或
#                                     gdbm-ndbm.h 守卫（ runner 上 Homebrew gdbm
#                                     提供前者），且它会 AS_UNSET 掉
#                                     ac_cv_search_dbm_open——只禁 ndbm_h 不够，
#                                     _dbm 照样链 libgdbm_compat（硬闸抓到过）
#   ac_cv_header_db_h=no              bdb 头文件判否，-ldb 链接尝试直接跳过
#   ac_cv_search_dbm_open=no          双保险：dbm_open 符号搜索直接判否
#   ac_cv_have_libdb=no               bdb 后端判否（macOS 本来也没有）
#   ac_cv_working_openssl_ssl=no      _ssl 门闩（configure.ac 8342 行）→ 不构建
#   ac_cv_working_openssl_hashlib=no  _hashlib 门闩 → 不构建；hashlib 仍有内置
#                                     _md5/_sha1/_sha2/_sha3/_blake2 兜底，功能不受影响
#   ac_cv_header_lzma_h=no            lzma fallback 判否（pkg-config 路由由过滤器切断）
#   ac_cv_header_zstd_h=no / zdict_h  zstd fallback 判否（同上）
#   ac_cv_search_ZDICT_finalizeDictionary=no  zstd 符号搜索判否，双保险
#   --with-system-libmpdec=no         强制用 CPython 自带的静态 libmpdec，不碰系统/Homebrew 的
PKG_CONFIG="$WORK/pkg-config-deny" ./configure \
    --prefix="$OUT" \
    MACOSX_DEPLOYMENT_TARGET=10.14.6 \
    --with-ensurepip=no \
    --disable-test-modules \
    --with-system-libmpdec=no \
    ac_cv_header_sqlite3_h=no \
    py_cv_module__sqlite3=n/a \
    ac_cv_header_libintl_h=no \
    ac_cv_lib_intl_textdomain=no \
    ac_cv_header_gdbm_h=no \
    ac_cv_header_ndbm_h=no \
    ac_cv_header_gdbm_slash_ndbm_h=no \
    ac_cv_header_gdbm_dash_ndbm_h=no \
    ac_cv_header_db_h=no \
    ac_cv_search_dbm_open=no \
    ac_cv_have_libdb=no \
    ac_cv_working_openssl_ssl=no \
    ac_cv_working_openssl_hashlib=no \
    ac_cv_header_lzma_h=no \
    ac_cv_header_zstd_h=no \
    ac_cv_header_zdict_h=no \
    ac_cv_search_ZDICT_finalizeDictionary=no \
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

# 早断言：pkg-config 过滤器真的在工作（liblzma / libzstd 必须被拒）
if "$WORK/pkg-config-deny" --exists liblzma 2>/dev/null; then
    echo "错误：pkg-config 过滤器没有拦住 liblzma" >&2
    exit 1
fi

echo "== make -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4) =="
make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" >make.log 2>&1 || { tail -40 make.log; exit 1; }

echo "== make install =="
rm -rf "$OUT"
make install >install.log 2>&1 || { tail -40 install.log; exit 1; }

if [ ! -x "$OUT/bin/python3" ]; then
    echo "安装后未找到 $OUT/bin/python3" >&2
    ls -R "$OUT" | head -30 >&2
    exit 1
fi

# 硬闸：外部依赖清零才允许进入组装（缓存命中路径在脚本开头同样过闸）
gate

echo "== 完成: $OUT/bin/python3 =="
du -sh "$OUT"
