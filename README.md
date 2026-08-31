# mac-token-plan

macOS 桌面常驻小组件，在桌面上直接显示订阅的各模型额度消耗。类似系统日历小组件，贴在桌面上随时可见，不用打开浏览器查控制台。

## 效果预览

![mac-token-plan 桌面小组件](https://zgkc-storage.oss-cn-beijing.aliyuncs.com/mcp-test/11.png)

## 支持平台

- **MiniMax 月度订阅**：5小时 / 7天额度（general 模型）
- **智谱 GLM Coding Plan**：小时窗口（如 5 小时）/ 7天 / 总额度
- **火山方舟 Agent Plan**：5小时 / 7天 / 月度总额度
- **OpenAI Codex 订阅**：5小时 / 7天窗口（自动读取 codex CLI 登录态，开箱即用）
- **DeepSeek 开放平台**：充值余额（金额显示，无进度条）

## 功能

- 桌面常驻透明卡片，可拖动、可调整大小、位置自动记忆
- **平台显示顺序可拖动排序**：设置面板按住平台行拖动调整顺序，卡片和菜单栏即时跟随，重启后保持
- 菜单栏（macOS 顶部状态栏）滚动显示额度（开关控制，默认关闭），每 5 秒切换一个平台，点 status item 弹出「立即刷新 / 打开设置 / 退出」菜单
- 进度条颜色随已用占比渐变（绿 → 橙 → 红）
- 重置倒计时实时显示（5小时显示「X:YY分钟后重置」，7天显示「X天Y小时后重置」）
- 刷新失败保留旧数据并标红，不闪空
- 定时刷新（默认 5 分钟，可配 1/5/15/30 分钟）
- 设置面板：平台开关与拖动排序、维度勾选、刷新间隔、窗口层级、主题、透明度、圆角、锁定位置、开机自启、菜单栏显示开关
- 凭证存 `.env`，不进代码、不进 git

## 环境要求

- macOS 14+（Sonoma）
- Swift 6 / Xcode Command Line Tools（`xcode-select --install`）

## 快速开始

```bash
git clone https://github.com/luolei2088-AI/mac-token-plan.git
cd mac-token-plan
cp .env.example .env
# 编辑 .env 填入你的 API key
swift run
```

## 配置凭证

编辑项目根 `.env`（从 `.env.example` 复制，各项说明见文件内注释）：

```
MINIMAX_API_KEY=...
VOLC_AK=...
VOLC_SK=...
ZHIPU_GLM_API_KEY=...
CODEX_ACCESS_TOKEN=
DEEPSEEK_API_KEY=...
```

- **minimax key**：minimax 开放平台 API Key
- **火山 AK/SK**：火山引擎控制台 -> 访问密钥。⚠️ 不是 `ark-` 开头的 Bearer key（那个只能调模型推理），查 Agent Plan 额度必须用 AK/SK 做 V4 签名
- **智谱 GLM key**：open.bigmodel.cn 的 API Key
- **Codex**：可以留空 —— 默认自动读取本地 codex CLI 的登录态（`~/.codex/auth.json`），只要用 ChatGPT 订阅账号（Plus/Pro 等）`codex` 登录过就无需配置；未登录时才需要手动填 access token
- **DeepSeek key**：DeepSeek 开放平台 API Key

不填凭证的平台在设置面板保持关闭即可；开关打开且有凭证才会拉取数据。

也可以在应用内配置：右键卡片 -> 设置 -> 「API 凭证」，保存后写回 `.env`。

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
- **平台排序**：设置 -> 平台，按住行拖动调整显示顺序，桌面卡片和菜单栏即时跟随
- **设置**：配置平台、凭证、维度、刷新间隔、窗口层级、主题、菜单栏显示开关等

## 技术栈

Swift 6 + SwiftUI + AppKit（NSPanel），Swift Package Manager。窗口壳用 AppKit，卡片内容用 SwiftUI。

## License

[MIT](LICENSE)
