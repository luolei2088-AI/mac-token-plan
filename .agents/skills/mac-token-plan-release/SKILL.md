---
name: mac-token-plan-release
description: 仅在 mac-token-plan 项目中使用；发布新版本时同步版本号、CHANGELOG 和 README，检查测试，构建 Apple Silicon 与 Intel 通用安装包，提交推送并上传 GitHub Releases。适用于“发布下个补丁版本”“发布 1.x.x”或完整版本发布请求。
---

# mac-token-plan 标准发布

## 范围与约定

- 从仓库根目录执行，先读根目录 `CLAUDE.md` / `AGENTS.md`。确认 `origin` 与 `gh repo view` 对应 `luolei2088-AI/mac-token-plan`；若项目或目标仓库不符，停止发布并说明。
- 技能仅存于本仓库 `.agents/skills/mac-token-plan-release/`，不复制到全局目录。`scripts/` 放打包脚本，所有产物、日志、截图和 Release 正文放 `.build/`。
- 完整发布请求包含当次提交、推送和公开 Release 的授权；“仅构建/准备”不包含这些远端操作，完成本地工作后再提出具体确认。未涉及的删除、凭证、CI/CD、数据库、系统配置等红线仍按项目规则执行。
- 不改写历史，不覆盖已有正式 Release、标签或附件，不用 `--clobber`。失败先查询远端状态，再决定续传缺失附件；已有标签指向不符、分支分歧、权限不足或同一步重试一次仍失败时，报告具体阻塞，不盲目重复发布。

## 1. 确认版本与发布内容

1. 检查 `git status --short`、已暂存与未暂存差异、当前分支、`git remote -v`、近期提交，以及 `gh release list`。
2. 读取当前 `Resources/Info.plist`、`CHANGELOG.md`、`README.md`，对照最近正式 Release 的标签、说明和附件。
3. 用户指定版本时采用指定值；“下个补丁版本”采用当前版本第三段加一。其他升级幅度不明确时询问，不擅自作主版本或次版本升级。
4. 确认版本高于最近正式版，目标标签尚未使用。检查远端 `main` 与本地关系，发布到已审阅的分支，默认 `main`。
5. 仅包含本次发布相关变更。不要覆盖已有本地修改，也不要把凭证、用户配置、临时文件、安装包或构建目录纳入提交。

## 2. 版本与文档

- `CFBundleShortVersionString` 改为目标版本；`CFBundleVersion` 在当前整数上加一。
- `CHANGELOG.md` 顶部增加该版本的新增、改进、修复及必要的使用限制，日期为 `Asia/Shanghai` 当日；链接采用 `releases/tag/v<版本>`。
- README 更新当前软件功能、用法与通用下载入口，不写版本流水账或开发构建步骤；保留首次打开的签名说明。
- Release 正文以本次 CHANGELOG 为依据，再补充真实验证结果、macOS 14+、双架构、安装方式和包 SHA-256。当前只有 ad-hoc 签名，不能声称经过 Apple Developer ID 签名或公证。

## 3. 测试与打包

执行（把示例版本换为目标版本）：

```bash
python3 .agents/skills/mac-token-plan-release/scripts/build_release.py --version 1.3.1
```

脚本仅使用 Python 标准库、Swift 和 macOS 自带构建工具，执行测试、两种架构的 Release 构建、通用二进制合并、签名、ZIP 压缩、解压复验及 SHA-256 生成。输出 JSON 给出包、校验文件和产物目录。仅打包已跟踪的图标和 plist，不执行会删除图标文件的 `build-icon.sh`。

- UI 变更还需检查相关界面。统计页可设置 `USAGE_SNAPSHOT_DIR` 为 `.build/` 下已创建的目录后运行上述脚本，检查测试生成的截图；模拟数据截图不得冒充真实账号数据。
- 检查 `git diff --check`、产物路径、双架构、版本号和签名结果。构建后若修改代码、资源或版本号，重新构建；不要上传旧包。
- 打包不会替换或重启正在运行的本地应用；用户要求本地更新时，先正常退出应用，再换入已验证的包并验证新进程。

## 4. 提交、标签与推送

1. 列出本次明确的文件路径执行 `git add`，不用无差别的 `git add .`。
2. 审阅 `git diff --cached --stat`、`git diff --cached --name-status` 和实际内容，确认产物、凭证与其他任务文件未进入提交。
3. 创建普通提交，例如 `release: v1.3.1 statistics and spending improvements`，不 amend。
4. 记录完整提交 SHA；为该提交创建注释标签 `v<版本>`。再次确认远端同名标签不存在。
5. 已有本次发布授权时，推送审阅分支及该标签，优先使用原子推送：`git push --atomic origin main v<版本>`；不推送其他标签或分支。若缺少推送授权，先展示具体提交、分支、标签与验证结果再确认。
6. 用 `git ls-remote` 核对远端分支与标签解引用后的提交 SHA，保证等于已验证提交。

## 5. GitHub Release

- 在本次产物目录写入 `release-notes.md`，用 `--notes-file` 提交正文，保持真实换行。
- 先用 `gh release create v<版本> <zip路径> <sha256路径> --repo luolei2088-AI/mac-token-plan --verify-tag --draft --title '<版本与主题>' --notes-file <正文路径>` 创建草稿并上传附件。
- 查询草稿附件列表，下载到新的 `.build/` 子目录，校验 SHA-256 与本地包一致；不得覆盖本地已有文件。
- 已有公开发布授权时，执行 `gh release edit v<版本> --repo luolei2088-AI/mac-token-plan --draft=false --latest`；否则把完整可审阅的草稿链接、正文和附件摘要交给用户确认后发布。
- 验证 Release 为非草稿、非预发布，Latest 指向新版本；附件名、大小和摘要符合预期，远端标签仍指向本次提交。
- 最终返回版本、提交短 SHA、Release 下载链接、验证结果；报告残留未提交文件。后续可直接说“使用 mac-token-plan-release 发布下个补丁版本”。
