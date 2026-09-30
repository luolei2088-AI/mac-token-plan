# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目

mac-token-plan：macOS 桌面常驻小组件，在桌面上直接显示订阅的各模型额度消耗。当前接入 minimax 月度订阅 + 智谱 GLM Coding Plan + 火山方舟 Agent Plan 月度订阅 + OpenAI Codex 订阅（5h/7d）+ DeepSeek 开放平台余额。形态为桌面常驻透明卡片窗口（NSPanel + SwiftUI）+ 可选的 macOS 菜单栏（NSStatusItem）滚动显示。非菜单栏独占、非 WidgetKit。

## 构建与运行

- 版本安装包仅上传 GitHub Releases，不提交到代码仓库；README 下载链接指向 Release 附件。
- README.md 仅介绍软件功能，保留通用下载和更新记录入口，不记录版本更新或开发构建细节。版本更新统一写入根目录 CHANGELOG.md，按新到旧排列，包含版本号、发布日期（北京时间）及新增/改进/修复内容；历史内容以 Release 和 Git 记录为依据。

- `swift run` - 编译并启动（调试模式，读项目根 `.env`）
- `swift build -c release` - release 构建
- `make app` - 打包 `.build/mac-token-plan.app`（release + 组装 bundle + ad-hoc 签名）
- `open .build/mac-token-plan.app` - 启动打包后的 .app

注意：`SMAppService` 开机自启仅在 .app bundle 运行时生效，`swift run` 下 register 会失败。`swift test` 运行 XCTest；无 lint。

## 项目发布与技能目录约定

- 发布本项目时读取 `.agents/skills/mac-token-plan-release/SKILL.md`，适用于 Codex 及遵循本文件的 Claude Code；技能不安装到用户全局目录。
- `.agents/skills/<技能名>/SKILL.md` 存流程说明，技能内 `scripts/` 只存可复用脚本；构建、压缩包、校验文件和验证截图全部放已忽略的 `.build/`，不提交产物或凭证。
- 发布包需同时包含 `arm64`、`x86_64`，沿用 macOS 14+；使用技能中的 `scripts/build_release.py` 构建及验证，不用仅面向本机架构的 `make app` 作为正式发布包。
- `Resources/Info.plist` 的 `CFBundleShortVersionString` 使用发布版本号，`CFBundleVersion` 每次正式发布递增；Git 标签为 `v<版本号>`。
- 更新记录写入 `CHANGELOG.md`，README 同步当前功能说明；GitHub Release 使用对应版本更新内容并附安装包、SHA-256 校验文件及签名状态。
- 用户明确要求完整发布或提交、推送、上传 Release 时，按当次授权完成对应步骤，不重复确认；仅要求准备或构建时，不自动推送或公开发布。其余红线继续适用。

## 架构与数据流

分层，数据/业务/UI 解耦。数据流：

`QuotaProvider.fetchQuota()` → `QuotaStore.fetchAll()`（withTaskGroup 并发 + 失败保留旧 buckets 标红 + 按 `AppSettings.providerOrder` 排序）→ `[ProviderQuota]` → `WidgetCard` 渲染。

- **Providers/** - `QuotaProvider` 协议（id/displayName/fetchQuota）。**新增平台 = 新增一个 Provider，不改 Store/UI**，平台间零耦合。
  - `MinimaxProvider`：GET `minimaxi.com/v1/token_plan/remains`，Bearer。只取 `modelName == "general"`，用 `remaining_percent` 反推 used/limit（返回无 total 字段）。无总额度维度，只有 5h/7d。
  - `ZhipuGLMProvider`：GET `open.bigmodel.cn/api/monitor/usage/quota/limit`，Authorization: raw token（不带 Bearer 前缀，按内版接口）。响应 `data.limits[]`，按 `type` 区分桶：`TIME_LIMIT → "5小时"`、`TOKENS_LIMIT → "总额度"`；**2026-08 起智谱改版全部返回 `CREDIT_LIMIT`**，用 `unit` 区分窗口：`unit=3` → 小时窗口（`number`=小时数，如 5 → "5小时"）、`unit=6` → "7天"（多条自动 `·N` 区分）。`percentage` 直接当已用占比 0-100。
  - `VolcEngineProvider`：GET `open.volcengineapi.com/?Action=GetAFPUsage&Version=2024-01-01`，**火山引擎 V4 签名**（AK/SK，serviceCode=ark，region=cn-north-1）。ark Bearer key 不能查 Agent Plan 额度，必须 AK/SK 签名。返回 5h/7d/月度总额度/今日（今日已隐藏）。
  - `CodexProvider`：GET `chatgpt.com/backend-api/wham/usage`（注意是 `wham/usage`，不是 `/usage`——后者返回前端 HTML），Bearer access token。响应结构（2026-09 实测）：顶层 `rate_limit.primary_window` 为账户主额度（prolite 当前只回 7 天 604800s，`secondary_window` 为 null）；**5 小时窗口已挪到 `additional_rate_limits[]`**——按模型独立计额的额度池（如 GPT-5.3-Codex-Spark / `codex_bengalfox`），每个自带 `primary_window`（5h，18000s）+ `secondary_window`（7d）。解析时把顶层 + additional 的所有窗口摊平，**按来源分组排序**：账户主额度（`source="账户"`）在最上，其下同一模型额度池的窗口聚拢、组内按 `limit_window_seconds` 升序（5h→7d），模型组之间按接口返回顺序。每条桶带 `source` 标注额度来源：顶层窗口 `source="账户"`，模型额度池 `source=limit_name` 末段短名（"GPT-5.3-Codex-Spark" → "Spark"）。卡片显示 `source·label`（如 "账户·7天"、"Spark·5小时"、"Spark·7天"），label 仍为纯维度名。窗口字段 `used_percent` / `limit_window_seconds` / `reset_at`（unix 秒），全 Optional 宽容解析。请求禁用本地缓存（`reloadIgnoringLocalCacheData`）。401/403 重读凭证重试一次。**凭证由 `CodexCredential` 提供**：优先读 `~/.codex/auth.json` 的 `tokens.access_token`（codex CLI 已登录 ChatGPT 订阅的场景，开箱即用），缺失时回退 `.env` 的 `CODEX_ACCESS_TOKEN`。每次 fetch 重新读文件，codex CLI 一旦刷新 token 下次拉取就拿到新值。注意 chatgpt.com 在国内需代理，`URLSession.shared` 自动走系统代理。
  - `DeepSeekProvider`：GET `api.deepseek.com/user/balance`，Bearer。**充值余额制**，与订阅额度不同：返回字符串金额（`total_balance`）+ 币种，无 used/limit/百分比/重置时间。走**金额桶**（`QuotaBucket.balanceAmount` 非 nil）：UI 显示金额文本、无进度条，>0 主文本色（浅色主题为黑）、≤0 红。`balance_infos[]` 每条一个桶，CNY 的 label 为「余额」，其他币种「余额(USD)」。
- **Store/QuotaStore** - `@MainActor ObservableObject`，init 注入 `AppSettings`。定时刷新（默认 5 分钟，可配）、错误降级、按 `settings.providerOrder` 排序（设置面板拖动配置，UserDefaults 持久化，默认 minimax → 智谱 GLM → 火山引擎 → Codex → DeepSeek），并订阅 `$providerOrder` 拖动后即时重排，卡片/菜单栏立即跟随。
- **Window/DesktopPanel** - NSPanel 子类。无边框透明圆角卡片，固定 200×243，`isMovableByWindowBackground` 可拖动。**窗口层级高于菜单栏**（`mainMenuWindow + 1`，可拖到物理顶部，代价是覆盖菜单栏）。`constrainFrameRect` 重写用 `screen.frame` 允许贴物理左/右/下边缘。frame 持久化到 UserDefaults。
- **Window/MenuBarController** - `NSStatusItem` 控制器（设置开关控制，默认关闭）。订阅 `QuotaStore.objectWillChange` 自动重建段文本，5 秒 `Timer` 切换，循环。点击 status item 弹出 `NSMenu`（立即刷新 / 打开设置 / 退出），菜单回调通过 `MenuActions` 闭包注入，避免反向依赖 AppDelegate。NSStatusBar 由系统独占，与 NSPanel 窗口层级无冲突。
- **Views/** - SwiftUI（NSHostingView）。`WidgetCard`（卡片+右键菜单+刷新按钮）、`QuotaRow`（百分比桶：胶囊进度条+状态色+倒计时；金额桶：金额文本，无进度条）、`SettingsView`（配置面板，Combine 绑定即时生效；「平台」Section 数据驱动，`onDrag/onDrop` + DropDelegate 拖动排序，开关经 `PlatformMeta.toggle` keyPath 合成 Binding）。
- **App/AppMain** - AppKit 入口（NSApplication，accessory 策略不显 Dock）。AppDelegate 管窗口+store+settings+menuBarController。
- **Security/** - `EnvConfig`（读写 .env）、`CodexCredential`（优先 `~/.codex/auth.json` / 回退 .env `CODEX_ACCESS_TOKEN`，供 CodexProvider 用）、`LaunchAtLoginHelper`（SMAppService）、`KeychainHelper`（历史方案，保留未用）。
- **Models/** - `QuotaBucket`（label 纯窗口维度名 "5小时"/"7天" + source 额度来源标注（Codex 用，"账户"/模型短名 "Spark"），UI 用 `displayLabel` 拼 `source·label`；used/limit/percentOnly/resetTime + 金额桶字段 balanceAmount/currency，id 纳入 source 保证同维度多窗口不冲突，自定义 init 带默认值）、`ProviderQuota`、`AppSettings`（含 `PlatformMeta` 平台元数据 + `allPlatforms` / `providerOrder`，provider_order 归一化：未知 id 丢弃、缺失 id 按默认顺序追加）。**label 必须保持纯维度名**：`AppSettings.shouldShow(label)` 按 "5小时"/"7天"/"总额度" 精确匹配控制维度开关，`QuotaRow` 倒计时靠 `label=="7天"` 判断格式——来源信息一律走 `source`，不得塞进 label。

## 凭证

存项目根 `.env`（已加 .gitignore）：
```
MINIMAX_API_KEY=...
ZHIPU_GLM_API_KEY=...
VOLC_AK=...
VOLC_SK=...
CODEX_ACCESS_TOKEN=...
DEEPSEEK_API_KEY=...
```
`EnvConfig` 按顺序查找 `.env`：当前工作目录（`swift run` 在项目根）、`~/.config/mac-token-plan/.env`（.app 推荐）、.app bundle 同目录。设置面板「API 凭证」可改（写回 .env）。`split("=", maxSplits:1)` 正确处理火山 SK 的 base64 `==` 尾缀。

## 关键约定

### CLI 接入约定

- 设置区分 API 密钥与 CLI 接入；百炼 Token Plan 暂时下线，平台迁移至千问后暂未提供 Token 用量获取接口，不提供开启或 CLI 接入。
- CLI 管理代码放 Security，平台解析放 Providers，设置卡片放 Views。Tests 使用 XCTest，新增目录内只存测试源文件，不存真实凭证。
- `bailian_token_plan` 保留在平台列表作为暂时下线提示，不构建 Provider；旧版启用状态会被强制关闭。
- 优先复用用户指定或系统 CLI；下载仅在用户点击安装后执行，使用官方二进制和 SHA256，存 `~/Library/Application Support/mac-token-plan/cli/<工具>/<版本>`，不改 PATH、不安装全局依赖。
- 登录仅在用户点击后执行。Codex 新登录使用应用专属配置目录和文件存储，已有本地凭证及手动 Token 保持兼容；不记录认证原始输出。
- Codex 凭证优先级：应用目录 `auth/codex/auth.json` → 原有本地 CLI `auth.json` → `.env` 备用 Token。CLI 程序安装路径和自定义路径存 UserDefaults，凭证仍由各 CLI 管理。
- 子进程使用 Process 参数数组，异步排空输出，提供超时与取消；安装/登录/用量状态分别显示。查询失败保留旧桶。
- `swift test` 验证解析、安装资源与进程生命周期；真实登录由用户完成，不在自动测试中执行。

- 额度维度不写死：`QuotaBucket` 带 label，平台返回几种展示几种。两种形态：**百分比桶**（进度条+状态色）和**金额桶**（`balanceAmount` 非 nil，纯金额文本无进度条，余额 ≤0 标红）。
- 进度条状态色按**已用占比**：≥95% 红、70-95% 橙、<70% 绿（低饱和 HSB）。
- 倒计时：5h 行 `H:MM分钟后重置`（小时为 0 则 `MM分钟后重置`），7d 行 `X天Y小时后重置`。`Timer.publish(every:1)` 每秒驱动 `now` 实时递减，独立于接口刷新；接口刷新拿到新 resetTime 后倒计时自动重置。
- UI 文案中文，代码/标识符英文。
- 刷新失败保留旧数据并标红，不闪空。
- 菜单栏段文本格式：`Minimax 5h:10% 7d:20%`（金额桶为 `DeepSeek 余额:¥110.00`），过滤受 `AppSettings.shouldShow(label)` 控制的维度；首次加载前显示 `加载中…`；失败 provider 显示 `Provider: 获取失败`。

## 自主边界（红线，必须先问）

删除文件、改密钥/凭证/.env、git push、公开发布 - 必须先确认。
