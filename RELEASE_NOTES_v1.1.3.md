# X32 Remote macOS Commander v1.1.3

**重要修复：v1.1.0 / v1.1.1 / v1.1.2 的内置 Python 在"干净"的 Mac 上无法启动。**

## 事故说明（v1.1.2 及之前）

内置 Python 3.14.8 是在带 Homebrew 的构建机（GitHub macOS runner）上编译的，
自动探测把 Homebrew 的 keg-only 库链了进来，产物里写死了构建机私有绝对路径：

```
dyld: Library not loaded: /usr/local/opt/gettext/lib/libintl.8.dylib
  Referenced from: X32Remote.app/Contents/Resources/python/bin/python3
  Reason: image not found
```

中招的共 9 个 Mach-O：`python3` / `python3.14`（libintl）、`_dbm` / `_gdbm`（gdbm）、
`_decimal`（mpdecimal）、`_ssl` / `_hashlib`（openssl@3）、`_lzma`（xz）、`_zstd`（zstd）。
只要机器上没装这些 Homebrew 包，模拟器内核就起不来，App 弹「模拟器未能启动」。
旧版校验脚本只查架构和最低系统版本，查不到这类问题，所以漏过了。

**临时兜底（不必升级也能用）**：`brew install gettext` 只为第一个缺失库，
其余仍需 `brew install gdbm mpdecimal openssl@3 xz zstd` —— 建议直接升级本版。

## 本版改动

- 构建层根治：configure 层禁用 libintl / gdbm / ndbm / openssl / lzma / zstd 探测，
  `_decimal` 改链 CPython 自带静态 libmpdec，新增 pkg-config 过滤器与
  **外部依赖硬闸**（make install 后 + 组装 .app 后各扫一遍，任何指向
  `/usr/local/opt`、`/opt/homebrew` 的动态库直接让构建失败）
- 内核：spec-v1.9（与 v1.1.2 相同，无变化）
- 内置 Python 3.14.8 源码编译，离线校验 Mach-O 最高 minos = 10.14.6、全 x86_64、
  **外部私有动态库引用 = 0**
- 受影响模块（ssl / lzma / zstd / gdbm / dbm / decimal）本应用均不使用：
  内核只依赖纯标准库与 hashlib 内置 `_sha*`，功能不受影响

## 安装

解压后右键 → 打开（未签名、未公证，首次需在 系统设置 → 隐私与安全性 里点「仍要打开」）。
- 系统要求：macOS 10.14.6+ / Intel(x86_64)
