# X32 Remote · macOS 桌面版 v1.0.1

本版是**内核升级版**：外壳无变化，内置模拟器从协议仓 `spec-v1.5` 升至 **`spec-v1.7`**
（6512 行 → 8918 行）。v1.0.0 发布的模拟器落后主线 12 个提交——
v1.0.1 确保桌面版与命令行版、在线版跑的是同一份内核。

## 下载

`X32Remote-macOS-unsigned.zip` → 解压得到 `X32Remote.app` → 拖进「应用程序」。

## 系统要求

- macOS **10.14.6**（Mojave）或更新
- **Intel（x86_64）** 处理器；Apple Silicon 需 Rosetta 2

## 首次启动（未签名）

本版未签名、未公证，首次双击会被 Gatekeeper 拦下，属预期行为：

- 右键点 `X32Remote.app` → 「打开」→ 再点「打开」；或
- 终端执行一次：`xattr -dr com.apple.quarantine /Applications/X32Remote.app`

## 新内核带来了什么（spec-v1.5 → spec-v1.7）

| 主题 | 内容 |
|---|---|
| 假成功防线（B0 五项 P0） | NaN 穿透致界面卡死、卡片竞态、配置原子写、写风暴合并器——全部修复 |
| 模块化（B1–B5） | 单文件拆成 24 个模块，双形态分发（`x32sim/` 包 + 合成单文件），行为一致 |
| 流量治理 | `/api/state` 条件轮询（命中不变只回 ~30 字节）+ `/api/meters` 独立端点 + gzip 协商；实测 22.5 → 11.7 MB/h |
| 通道参数建模 | 登记表 16 → **75 项**，ch 行 40 → 58 字段：增益/反相/延时/低切/插入/噪声门/压缩/均衡(4 段全参)/发送(16 Bus)全部可遥控 |
| 侧链与取点 | 门/压缩的 hold、keysrc(0–64)、filter(on/type/f) 五段地址；发送取点按官方 5 档枚举、奇数 Bus 成对共享 |
| 订阅语义 | 新增 `/subscribe ,s<addr> [,i<rate>]`（首轮回当前值）；`/xremote` 保持真台语义（只推变化），`--xremote-snapshot` 可选开全量 |
| 数值保真 | `send_level` 按 161 档量化；推子 dB 曲线改为真台 4 段伪对数（旧式在 0.25 处偏 +20.5 dB） |

桌面版功能与命令行版完全一致，另提供原生菜单、窗口标题显示局域网地址、
配置与日志落在 `~/Library/Application Support/X32Remote/`、
模拟器异常退出时直接在窗口内显示日志尾部。

## 每次 CI 都验证的四关

1. **标准库导入冒烟**：模拟器实际用到的全部模块能 import
2. **重定位断言**：`sys.executable` 与 `sys.prefix` 必须位于 `.app` 内（防止悄悄跑到了系统 Python）
3. **部署目标 + 架构断言**：逐个 Mach-O 用 `otool` 查 `minos`、用 `lipo` 查架构，全部 `minos ≤ 10.14.6` 且含 `x86_64`
4. **端到端**：模拟器无头启动 → `/api/state` 返回正常 → 控制台 HTML 含预期标题

## 已知限制

- **未签名、未公证**：免提示分发需要 Apple 开发者账号（$99/年）签名 + 公证
- **仅 Intel**：Apple Silicon 走 Rosetta 2；arm64 原生版待后续
- **体积约 94MB**（Python 运行时占大部分）
- 网页服务监听 `0.0.0.0` 且无鉴权（与命令行版一致的设计），请在可信网络使用
- 构建依赖 GitHub 的 `macos-15-intel` runner，**2027 年 8月**停止提供 x86_64 macOS runner，届时需迁 arm64 或自建 runner

## 校验和

见附件 `SHA256SUMS.txt`（校验：`shasum -a 256 -c SHA256SUMS.txt`）。
