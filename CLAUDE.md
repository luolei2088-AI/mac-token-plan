# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目

mac-token-plan：macOS 桌面常驻小组件，在桌面上直接显示订阅的各模型额度消耗。当前接入 minimax 月度订阅 + 智谱 GLM Coding Plan + 火山方舟 Agent Plan 月度订阅。形态为桌面常驻透明卡片窗口（NSPanel + SwiftUI）+ 可选的 macOS 菜单栏（NSStatusItem）滚动显示。非菜单栏独占、非 WidgetKit。

## 构建与运行

- `swift run` - 编译并启动（调试模式，读项目根 `.env`）
- `swift build -c release` - release 构建
- `make app` - 打包 `.build/mac-token-plan.app`（release + 组装 bundle + ad-hoc 签名）
- `open .build/mac-token-plan.app` - 启动打包后的 .app

注意：`SMAppService` 开机自启仅在 .app bundle 运行时生效，`swift run` 下 register 会失败。无测试、无 lint。

## 架构与数据流

分层，数据/业务/UI 解耦。数据流：

`QuotaProvider.fetchQuota()` → `QuotaStore.fetchAll()`（withTaskGroup 并发 + 失败保留旧 buckets 标红 + 按 id 固定顺序排序）→ `[ProviderQuota]` → `WidgetCard` 渲染。

- **Providers/** - `QuotaProvider` 协议（id/displayName/fetchQuota）。**新增平台 = 新增一个 Provider，不改 Store/UI**，平台间零耦合。
  - `MinimaxProvider`：GET `minimaxi.com/v1/token_plan/remains`，Bearer。只取 `modelName == "general"`，用 `remaining_percent` 反推 used/limit（返回无 total 字段）。无总额度维度，只有 5h/7d。
  - `ZhipuGLMProvider`：GET `open.bigmodel.cn/api/monitor/usage/quota/limit`，Authorization: raw token（不带 Bearer 前缀，按内版接口）。响应 `data.limits[]`，按 `type` 区分桶：`TIME_LIMIT → "5小时"`、`TOKENS_LIMIT → "总额度"`（多条自动 `·N` 区分）。`percentage` 直接当已用占比 0-100。
  - `VolcEngineProvider`：GET `open.volcengineapi.com/?Action=GetAFPUsage&Version=2024-01-01`，**火山引擎 V4 签名**（AK/SK，serviceCode=ark，region=cn-north-1）。ark Bearer key 不能查 Agent Plan 额度，必须 AK/SK 签名。返回 5h/7d/月度总额度/今日（今日已隐藏）。
- **Store/QuotaStore** - `@MainActor ObservableObject`。定时刷新（默认 5 分钟，可配）、错误降级、固定顺序（minimax → 智谱 GLM → 火山引擎）。
- **Window/DesktopPanel** - NSPanel 子类。无边框透明圆角卡片，固定 200×243，`isMovableByWindowBackground` 可拖动。**窗口层级高于菜单栏**（`mainMenuWindow + 1`，可拖到物理顶部，代价是覆盖菜单栏）。`constrainFrameRect` 重写用 `screen.frame` 允许贴物理左/右/下边缘。frame 持久化到 UserDefaults。
- **Window/MenuBarController** - `NSStatusItem` 控制器（设置开关控制，默认关闭）。订阅 `QuotaStore.objectWillChange` 自动重建段文本，5 秒 `Timer` 切换，循环。点击 status item 弹出 `NSMenu`（立即刷新 / 打开设置 / 退出），菜单回调通过 `MenuActions` 闭包注入，避免反向依赖 AppDelegate。NSStatusBar 由系统独占，与 NSPanel 窗口层级无冲突。
- **Views/** - SwiftUI（NSHostingView）。`WidgetCard`（卡片+右键菜单+刷新按钮）、`QuotaRow`（胶囊进度条+状态色+倒计时）、`SettingsView`（配置面板，Combine 绑定即时生效）。
- **App/AppMain** - AppKit 入口（NSApplication，accessory 策略不显 Dock）。AppDelegate 管窗口+store+settings+menuBarController。
- **Security/** - `EnvConfig`（读写 .env）、`LaunchAtLoginHelper`（SMAppService）、`KeychainHelper`（历史方案，保留未用）。
- **Models/** - `QuotaBucket`（label/used/limit/percentOnly/resetTime，自定义 init 带默认值）、`ProviderQuota`、`AppSettings`。

## 凭证

存项目根 `.env`（已加 .gitignore）：
```
MINIMAX_API_KEY=...
ZHIPU_GLM_API_KEY=...
VOLC_AK=...
VOLC_SK=...
```
`EnvConfig` 按顺序查找 `.env`：当前工作目录（`swift run` 在项目根）、`~/.config/mac-token-plan/.env`（.app 推荐）、.app bundle 同目录。设置面板「API 凭证」可改（写回 .env）。`split("=", maxSplits:1)` 正确处理火山 SK 的 base64 `==` 尾缀。

## 关键约定

- 额度维度不写死：`QuotaBucket` 带 label，平台返回几种展示几种。
- 进度条状态色按**已用占比**：≥95% 红、70-95% 橙、<70% 绿（低饱和 HSB）。
- 倒计时：5h 行 `H:MM分钟后重置`（小时为 0 则 `MM分钟后重置`），7d 行 `X天Y小时后重置`。`Timer.publish(every:1)` 每秒驱动 `now` 实时递减，独立于接口刷新；接口刷新拿到新 resetTime 后倒计时自动重置。
- UI 文案中文，代码/标识符英文。
- 刷新失败保留旧数据并标红，不闪空。
- 菜单栏段文本格式：`Minimax 5h:10% 7d:20%`，过滤受 `AppSettings.shouldShow(label)` 控制的维度；首次加载前显示 `加载中…`；失败 provider 显示 `Provider: 获取失败`。

## 自主边界（红线，必须先问）

删除文件、改密钥/凭证/.env、git push、公开发布 - 必须先确认。
