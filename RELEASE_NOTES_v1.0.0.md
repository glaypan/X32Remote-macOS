# X32 Remote · macOS 桌面版 v1.0.0

X32 虚拟调音台模拟器第一次有了原生 macOS 外壳：**双击启动，窗口就是控制台**——不用装 Python、不用开终端、不用先 `python x32_simulator.py` 再开浏览器。

## 下载

`X32Remote-macOS-unsigned.zip` → 解压得到 `X32Remote.app` → 拖进「应用程序」。

## 系统要求

- macOS **10.14.6**（Mojave）或更新
- **Intel（x86_64）** 处理器；Apple Silicon 需 Rosetta 2

## 首次启动（未签名）

本版未签名、未公证，首次双击会被 Gatekeeper 拦下，属预期行为：

- 右键点 `X32Remote.app` → 「打开」→ 再点「打开」；或
- 终端执行一次：`xattr -dr com.apple.quarantine /Applications/X32Remote.app`

## 里面装了什么

| 组件 | 说明 |
|---|---|
| AppKit 外壳 | 原生窗口与菜单，Swift 编译，目标 `x86_64-apple-macos10.14.6`（无 SwiftUI/async——它们需要 10.15+） |
| 内置 Python 3.14.8 | CI 从源码编译，显式 `MACOSX_DEPLOYMENT_TARGET=10.14.6`；不用 python.org 的 universal2 安装包，因其 x86_64 slice 的最低系统版本不受控 |
| x32_simulator.py | 构建时从 X32Remote-Protocol 的 `spec-v1.5` 拉取，保持唯一事实来源 |
| 网页控制台 | 模拟器自带的完整控制台，由 WKWebView 承载 |

## 功能

与命令行版完全一致：全部通道/母线/推子/静音、FX 机架、场景调用、演出卡片时间线引擎；可纯本地模拟，也可在设置页桥接到局域网内的真台 X32/M32。

桌面版额外提供：

- 原生菜单（关于 / 在浏览器中打开 / 打开配置文件夹 / 显示日志 / 重新加载）
- 窗口标题显示局域网地址，手机端照着输即可
- 配置与日志落在 `~/Library/Application Support/X32Remote/`（`user_config.json`、`simulator.log`）
- 模拟器异常退出时，把日志尾部直接显示在窗口里，并可从菜单一键重启

## 每次 CI 都验证的四关

1. **标准库导入冒烟**：模拟器实际用到的全部模块能 import
2. **重定位断言**：`sys.executable` 与 `sys.prefix` 必须位于 `.app` 内（防止悄悄跑到了系统 Python）
3. **部署目标 + 架构断言**：逐个 Mach-O 用 `otool` 查 `minos`、用 `lipo` 查架构——本次 **64 个 Python 侧二进制 + 1 个主程序**，全部 `minos ≤ 10.14.6` 且含 `x86_64`
4. **端到端**：模拟器无头启动 → `/api/state` 返回 27 个键 → 控制台 HTML 含预期标题

## 已知限制

- **未签名、未公证**：免提示分发需要 Apple 开发者账号（$99/年）签名 + 公证
- **仅 Intel**：Apple Silicon 走 Rosetta 2；arm64 原生版待后续
- **体积约 94MB**（Python 运行时占大部分）
- 网页服务监听 `0.0.0.0` 且无鉴权（与命令行版一致的设计），请在可信网络使用
- 构建依赖 GitHub 的 `macos-15-intel` runner，**2027 年 8 月**停止提供 x86_64 macOS runner，届时需迁 arm64 或自建 runner

## 校验和

见附件 `SHA256SUMS.txt`。
