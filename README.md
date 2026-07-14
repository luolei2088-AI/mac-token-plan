# mac-token-plan

macOS 桌面常驻小组件，在桌面上直接显示订阅的各模型额度消耗。类似系统日历小组件，贴在桌面上随时可见，不用打开浏览器查控制台。

## 效果预览

![mac-token-plan 桌面小组件](https://zgkc-storage.oss-cn-beijing.aliyuncs.com/mcp-test/11.png)

## 支持平台

- **MiniMax 月度订阅**：5小时 / 7天额度（general 模型）
- **火山方舟 Agent Plan**：5小时 / 7天 / 月度总额度

## 功能

- 桌面常驻透明卡片，可拖动、可调整大小、位置自动记忆
- 菜单栏（macOS 顶部状态栏）滚动显示额度（开关控制，默认关闭），每 5 秒切换一个平台，点 status item 弹出「立即刷新 / 打开设置 / 退出」菜单
- 进度条颜色随已用占比渐变（绿 → 橙 → 红）
- 重置倒计时实时显示（5小时显示「X:YY分钟后重置」，7天显示「X天Y小时后重置」）
- 定时刷新（默认 5 分钟，可配 1/5/15/30 分钟）
- 设置面板：平台开关、维度勾选、刷新间隔、窗口层级、主题、开机自启、菜单栏显示开关
- 凭证存 `.env`，不进代码、不进 git

## 环境要求

- macOS 14+（Sonoma）
- Swift 6 / Xcode Command Line Tools（`xcode-select --install`）

## 快速开始

```bash
git clone https://github.com/<your-github-username>/mac-token-plan.git
cd mac-token-plan
cp .env.example .env
# 编辑 .env 填入你的 API key
swift run
```

## 配置凭证

编辑项目根 `.env`（从 `.env.example` 复制）：

```
MINIMAX_API_KEY=...
VOLC_AK=...
VOLC_SK=...
```

- **minimax key**：minimax 开放平台 API Key
- **火山 AK/SK**：火山引擎控制台 -> 访问密钥。⚠️ 不是 `ark-` 开头的 Bearer key（那个只能调模型推理），查 Agent Plan 额度必须用 AK/SK 做 V4 签名

## 打包成 .app

```bash
make app
open .build/mac-token-plan.app
```

`.app` 读取 `.env` 的位置（按顺序查找）：
1. 当前工作目录 `.env`
2. `~/.config/mac-token-plan/.env`（推荐，.app 运行时用这个）
3. .app 同目录的 `.env`

**开机自启**：右键卡片 -> 设置 -> 通用 -> 打开「开机自启」（基于 SMAppService，仅 .app 运行时生效）。

## 使用

- **拖动**：按住卡片任意位置拖动
- **调整大小**：拖动卡片边缘
- **右键菜单**：刷新 / 设置 / 退出
- **菜单栏**：设置 -> 菜单栏 -> 打开「在菜单栏中显示」，会在 macOS 顶部状态栏出现滚动额度（每 5 秒切换一个平台），点击弹出菜单
- **设置**：配置平台、凭证、维度、刷新间隔、窗口层级、主题、菜单栏显示开关等

## 技术栈

Swift 6 + SwiftUI + AppKit（NSPanel），Swift Package Manager。窗口壳用 AppKit，卡片内容用 SwiftUI。

## License

[MIT](LICENSE)
