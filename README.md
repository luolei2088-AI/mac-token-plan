# mac-token-plan

macOS 桌面常驻小组件，在桌面上直接显示订阅的各模型额度消耗。类似系统日历小组件，贴在桌面上随时可见，不用打开浏览器查控制台。

## 最新安装包

[下载 v1.3.0 安装包](https://github.com/luolei2088-AI/mac-token-plan/releases/download/v1.3.0/mac-token-plan-v1.3.0.zip)（macOS 14+，支持 Apple Silicon 和 Intel）。解压后将 `mac-token-plan.app` 拖入「应用程序」并启动。

v1.3.0 新增百炼 Token Plan 中国站个人版用量查询，以及百炼 / Codex CLI 的安装、登录和连接检测。安装包采用本地 ad-hoc 签名，未经过 Apple 公证。

## 效果预览

![mac-token-plan 桌面小组件](https://zgkc-storage.oss-cn-beijing.aliyuncs.com/mcp-test/11.png)

## 支持平台

- **MiniMax 月度订阅**：5小时 / 7天额度（general 模型）
- **智谱 GLM Coding Plan**：小时窗口（如 5 小时）/ 7天 / 总额度
- **火山方舟 Agent Plan**：5小时 / 7天 / 月度总额度
- **OpenAI Codex 订阅**：按额度来源分组显示 —— 账户主额度在上，其下各模型独立额度池（如 GPT-5.3-Codex-Spark）的 5小时 / 7天窗口聚拢展示，自动读取 codex CLI 登录态，开箱即用
- **DeepSeek 开放平台**：充值余额（金额显示，无进度条）
- **百炼 Token Plan（中国站个人版）**：通过百炼 CLI 查询已用百分比与重置时间；按实际返回显示 5小时 / 7天窗口。

## 功能

- 桌面常驻透明卡片，可拖动、可调整大小、位置自动记忆
- **平台显示顺序可拖动排序**：设置面板按住平台行拖动调整顺序，卡片和菜单栏即时跟随，重启后保持
- **百炼 Token Plan 用量查询**：支持中国站个人版，显示实际返回的额度窗口、已用百分比和重置倒计时
- **CLI 一键安装与登录**：百炼、Codex 支持本地检测、应用内安装、浏览器授权、连接检查、取消和失败重试；已有 CLI 可直接复用
- **接入方式分组**：设置中将「API 密钥」和「CLI 接入」分开，CLI 显示版本、路径和连接状态，Codex 备用 Token 放在高级配置中
- 菜单栏（macOS 顶部状态栏）滚动显示额度（开关控制，默认关闭），每 5 秒切换一个平台，点 status item 弹出「立即刷新 / 打开设置 / 退出」菜单
- **使用量统计**：右键卡片 -> 统计，打开独立统计窗口，支持 1天（按小时）、7天（按天）、30天（按天）查看各渠道使用趋势
- 统计支持全部渠道或单渠道筛选，也可按 5小时、7天、总额度等额度窗口筛选；统一按已用百分比展示
- 统计数据在本地保留 90 天，基于成功刷新结果进行采样；首次采样建立基线，刷新失败或应用未运行期间保留数据空档
- 进度条颜色随已用占比渐变（绿 → 橙 → 红）
- 重置倒计时实时显示（5小时显示「X:YY分钟后重置」，7天显示「X天Y小时后重置」）
- 同一平台多个额度池分组标注来源：如 Codex 区分「账户」主额度与各模型独立额度（「Spark」等），同模型 5小时/7天聚拢显示，右列百分比对齐
- 刷新失败保留旧数据并标红，不闪空
- 定时刷新（默认 5 分钟，可配 1/5/15/30 分钟）
- 设置面板：平台开关与拖动排序、维度勾选、刷新间隔、窗口层级、主题、透明度、圆角、锁定位置、开机自启、菜单栏显示开关
- API 密钥存 `.env`，CLI 登录凭证由对应 CLI 管理，均不进代码、不进 git

## 环境要求

- macOS 14+（Sonoma）
- Swift 6 / Xcode Command Line Tools（`xcode-select --install`）

## 快速开始

```bash
git clone https://github.com/luolei2088-AI/mac-token-plan.git
cd mac-token-plan
cp .env.example .env
# 使用 API 密钥的平台：编辑 .env 填入对应 key
# 百炼 / Codex：启动后在「设置 → CLI 接入」中安装并登录
swift run
```

## 配置凭证

设置分为「API 密钥」与「CLI 接入」。百炼和 Codex 推荐通过 CLI 登录，其他平台继续配置 API 密钥。

### CLI 接入：百炼与 Codex

右键卡片 → 设置 → CLI 接入：

1. 应用自动检测已有 `bl` / `codex`；也可展开「CLI 路径」选择可执行文件。
2. 未安装时点击「安装」。应用下载官方 macOS 独立二进制、验证 SHA256 并检查可执行版本，无需 Node.js、Homebrew 或管理员权限。
3. 点击「登录 / 重新登录」，在打开的浏览器中完成账号授权。百炼使用中国站 Console 登录；Codex 使用 ChatGPT 订阅登录。
4. 授权结束后自动检查订阅连接；在「平台」打开对应开关即可显示额度。百炼默认关闭。

下载的 CLI 存在 `~/Library/Application Support/mac-token-plan/cli/`，不修改系统 PATH。已有系统 CLI 优先复用，自定义路径优先级最高；安装与登录支持取消，失败后可重试。

Codex 查询优先使用本应用创建的登录凭证，其次读取已有本地 CLI 凭证，最后使用高级配置里的备用 Access Token。本应用发起的 Codex 登录在 `~/Library/Application Support/mac-token-plan/auth/codex/` 保存文件凭证，不覆盖原有 Codex 配置。该目录包含敏感认证信息，不要分享或提交到 Git。现有系统钥匙串登录无法直接读取时，可点击登录为本应用建立连接。

百炼个人版通过以下只读命令查询，额度按 Credits 已用比例展示，不估算 Token 数或套餐总额：

```bash
bl usage token-plan --console-region cn-beijing --console-site domestic --output json
```

安装成功只表示 CLI 可运行；「已连接」表示订阅查询成功。若登录取消、会话过期、无个人版订阅或网络异常，设置会显示提示。Codex API Key 登录不能查询 ChatGPT 订阅额度。查询失败时卡片保留上次额度并标红。

### API 密钥

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
- **Codex**：可以留空 —— 优先复用本应用或已有本地 CLI 的 ChatGPT 登录凭证；未登录时可在「CLI 接入」点击登录，也可在高级配置中填写备用 Access Token
- **DeepSeek key**：DeepSeek 开放平台 API Key

使用 API 密钥的平台，开关打开且有凭证才会拉取数据；CLI 平台开启后会显示连接结果或配置提示。

也可以在应用内配置：右键卡片 -> 设置 -> 「API 密钥」，保存后写回 `.env`。

Codex 备用 Token 已移至「CLI 接入 → Codex 高级配置」，使用独立保存按钮。

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
- **使用量统计**：右键卡片 -> 统计，进入独立统计窗口。选择时间范围、渠道和额度窗口后，可查看小时或每日使用量柱状图。
- **统计口径**：图表展示采样期间的已用百分比增量，不把 5 小时和 7 天窗口相加，避免同一次使用被重复计算。统计精度取决于刷新间隔。
- **菜单栏**：设置 -> 菜单栏 -> 打开「在菜单栏中显示」，会在 macOS 顶部状态栏出现滚动额度（每 5 秒切换一个平台），点击弹出菜单
- **平台排序**：设置 -> 平台，按住行拖动调整显示顺序，桌面卡片和菜单栏即时跟随
- **接入百炼**：设置 → CLI 接入 → 百炼 Token Plan，检测或安装 CLI，点击登录完成浏览器授权，再在平台列表启用百炼
- **设置**：配置平台、凭证、维度、刷新间隔、窗口层级、主题、菜单栏显示开关等

## 技术栈

验证命令：`swift test`（额度解析、安装清单校验、子进程超时与取消）；`swift build -c release`。测试不会安装 CLI 或触发账号登录。

Swift 6 + SwiftUI + AppKit（NSPanel），Swift Package Manager。窗口壳用 AppKit，卡片内容用 SwiftUI。

## License

[MIT](LICENSE)
