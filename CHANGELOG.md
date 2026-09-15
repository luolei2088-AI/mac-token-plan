# 更新记录

按版本由新到旧排列，日期采用北京时间。安装包见 [GitHub Releases](https://github.com/luolei2088-AI/mac-token-plan/releases)。

## [1.3.0](https://github.com/luolei2088-AI/mac-token-plan/releases/tag/v1.3.0) · 2026-09-15

### 新增

- 接入百炼 Token Plan 中国站个人版，通过百炼 CLI 查询额度，显示实际返回的 5小时 / 7天窗口、已用百分比和重置时间。
- 百炼、Codex 支持 CLI 检测、安装、浏览器登录和连接检查，可取消操作并在失败后重试。
- 支持复用已有 CLI、自定义可执行文件路径，以及安装到应用管理的用户目录。

### 改进

- 设置分为「API 密钥」与「CLI 接入」，分别展示 CLI 版本、路径和连接状态。
- Codex 备用 Access Token 移至高级配置；优先使用本应用登录，兼容已有本地 CLI 凭证和手动 Token。
- 安装包同时支持 Apple Silicon 和 Intel，提供下载校验；应用安装包统一通过 GitHub Releases 分发。

## [1.2.0](https://github.com/luolei2088-AI/mac-token-plan/releases/tag/v1.2.0) · 2026-09-12

### 新增

- 新增独立使用量统计窗口，可查看 1天、7天、30天的使用趋势。
- 支持全部渠道或单渠道筛选，以及按额度窗口筛选。
- 本地保留 90 天历史采样，以成功刷新的已用百分比增量统计使用量。

### 修复

- 7天窗口剩余时间不足一天时改为显示小时和分钟，不再显示「0天X小时」。

## [1.1.0](https://github.com/luolei2088-AI/mac-token-plan/releases/tag/v1.1.0) · 2026-09-07

### 新增与改进

- Codex 额度按来源分组，区分账户主额度与模型独立额度池，同模型的 5小时 / 7天窗口集中展示。
- 百分比与金额列固定宽度、右对齐。
- 用量文案由「已使用 X%」调整为「已用 X%」。

### 修复

- 适配 Codex 额度接口结构变化，恢复模型独立额度池中的 5小时窗口显示。
- 修复桌面卡片无法拖动的问题，保留四角缩放。

## [1.0.0](https://github.com/luolei2088-AI/mac-token-plan/releases/tag/v1.0.0) · 2026-08-31

### 首次发布

- 支持 MiniMax 月度订阅、智谱 GLM Coding Plan、火山方舟 Agent Plan、OpenAI Codex 订阅及 DeepSeek 余额查询。
- 提供可拖动、可调整大小的桌面透明卡片，支持位置记忆与锁定。
- 支持平台开关与拖动排序，可选菜单栏滚动显示额度。
- 提供用量进度条、状态颜色、实时重置倒计时和定时刷新；刷新失败保留旧数据并标红。
- 支持主题、透明度、圆角、窗口层级和开机自启设置。
