# X32 Remote · macOS 桌面版

X32 虚拟调音台模拟器的 macOS 桌面外壳：**原生 AppKit 窗口（WKWebView）加载内置模拟器的网页控制台**，模拟器由捆绑的 Python 3.14 框架运行——无需安装 Python、无需终端、无需浏览器。

| 项 | 值 |
|---|---|
| 目标平台 | macOS **10.14.6+**，**仅 Intel（x86_64）** |
| 分发形式 | 未签名 `.app`（首次需右键打开，见下文） |
| 模拟器源码 | 构建时从 [glaypan/X32Remote-Protocol](https://github.com/glaypan/X32Remote-Protocol) 按 tag `spec-v1.8` 拉取，保持唯一事实来源 |
| Python | CI 源码编译 3.14.8（`MACOSX_DEPLOYMENT_TARGET=10.14.6`），非 universal2 安装包 |

## 功能

与网页控制台完全一致（模拟器即权威实现）：全部通道/母线/推子/静音、FX 机架、场景调用、
演出卡片时间线引擎；支持本地纯模拟，也可在设置页桥接到局域网内的真实 X32/M32。
桌面版额外提供：原生窗口与菜单、局域网地址显示在窗口标题、配置与日志落在
`~/Library/Application Support/X32Remote/`、模拟器异常退出时弹出日志尾部。

## 安装（未签名）

1. 解压 zip，得到 `X32Remote.app`，拖入 `/Applications`
2. 首次启动：**右键 → 打开**（Gatekeeper 对未签名应用的正常提示）
3. 或在终端执行一次：`xattr -dr com.apple.quarantine /Applications/X32Remote.app`

## 从源码构建

本地（需要 Xcode 与命令行工具）：

```bash
bash scripts/build_python.sh   # 源码编译内置 Python 3.14.8（约 4–7 分钟）
bash scripts/build.sh          # 编译 Swift 外壳 + 组装 .app
bash scripts/smoke.sh          # 冒烟：重定位 / 部署目标 + x86_64 架构断言 / /api/state
```

CI：push 到 `main` 自动构建，`build-macos` 工作流产出
`X32Remote-macOS-unsigned.zip` artifact。打 `v*` tag 时同样触发。

## 目录结构

```
Sources/     main.swift / AppDelegate.swift（外壳）/ SimulatorProcess.swift（守护进程）
tools/       make_icon.swift（构建期代码绘制图标）
scripts/     build.sh / build_python.sh / smoke.sh / check_deployment.py
Info.plist   最低系统版本 10.14.6、禁突然终止（保证退出时收尸 Python 子进程）
.github/     build-macos.yml（macos-15-intel runner）
```

## 配置与日志

- 配置：`~/Library/Application Support/X32Remote/user_config.json`（与控制台设置页互通，含自定义端口）
- 日志：同目录 `simulator.log`（菜单「文件 → 显示模拟器日志」）

## 端口行为

- 网页端口优先级：设置页保存的端口 → 8080 → 8081–8099 中第一个空闲；实际端口显示在窗口标题
- OSC/UDP 端口：模拟器默认 10023；被占用时应用会提示（通常是另一个模拟器在运行）

## 已知限制

- **未签名、未公证**：Gatekeeper 提示属预期；需要免提示分发需 Apple 开发者账号（$99/年）签名+公证
- **仅 Intel x86_64**：Apple Silicon Mac 可通过 Rosetta 2 运行；arm64 原生版待后续
- Python 为源码编译产物（普通 prefix 构建，非 framework），`.app` 约 60–90MB
- `macos-15-intel` 是 GitHub 最后一个 x86_64 runner，**2027 年 8 月退役**，届时构建链需迁 arm64 或自建 runner
- 模拟器网页服务监听 `0.0.0.0` 且无鉴权（与命令行版一致的设计），请在可信网络使用

## 与其他仓的关系

| 仓 | 内容 |
|---|---|
| glaypan/X32Remote-Protocol | 共享协议规范 + Python 模拟器 + 工具（本 App 的模拟器来源） |
| glaypan/X32Remote | iOS 源码 + 全部 Release 产物 |
| glaypan/X32RemoteAndroid | Android 源码 |
| glaypan/X32Remote-macOS | 本仓 |
