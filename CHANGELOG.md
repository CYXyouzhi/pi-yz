# 更新记录

本文件记录每个版本的改动。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

App 的版本号在 `pubspec.yaml`（`0.2.0+2` 里的 `+2` 是 Android versionCode），
电脑端服务端与 pi 插件的版本号在 `server/package.json`、`pi-plugin/package.json` —— **三处必须一致**。

---

## [0.2.0] — 未发布（等推送到 GitHub 后打 tag）

v0.1.0 之后累计 **89 个提交**，以「解耦 + 修 bug」为主，没有破坏性变更。

### 新增

- `pi-yz` 命令行入口：`start` / `stop` / `status` / `doctor` / `token` / `logs`
  （不依赖 pi 主进程也能把服务端拉起来）。pi 里的 `/mobile` 一并改名 `/yz`，
  两套入口共用 `pi-plugin/lib/ctl.mjs`，避免「命令行说在跑、pi 里说没跑」的分歧。

### 修复

- **启动不再自动跳「会话」tab**，默认停在「开始」页（恢复上次会话的逻辑保留）
- **日志页永远空**：连接 / 请求 / 事件流三处补上埋点
- **换会话后 Chat 标题栏消失**：换会话时重置滚动派生状态
- **Markdown 表格长单元格被裁掉**：列宽改成按比例分配
- **文件浏览左上角「<」只能退上一级**，不能退出页面
- **界面语言中英混排**：语言判定只认 `AppPrefs` / 平台 Locale
- 存储占用删除确认的文案主语
- 4 处「折叠头点了没反应」（`_expanded` 存的是翻译值，不是 i18n key）
- 新用户加不了连接 + 返回键滚走
- 「AI 配置」从「工作区」分组提到顶层（入口收敛）
- 代码审计发现的 4 处问题（含连接测试超时 30s/8s 不一致）
- `/mobile start` 静默失效（状态判断从 PID 换成端口探活）

### 重构（47 个提交，纯重构、不改行为）

大文件拆分走「抽成无状态组件」路线（不用 `part`），状态统一留在父级 State：

| 文件 | 拆前 | 现在 |
|---|---|---|
| `lib/ui/server/chat_page.dart` | 3374 | 1099 |
| `lib/ui/server/conn_page.dart` | 1300 | 556 |
| `lib/ui/server/settings_page.dart` | 1472 | 875 |
| `lib/ui/server/config_page.dart` | 1307 | 811 |
| `lib/ui/server/files_page.dart` | 1059 | 651 |
| `lib/ui/server/sessions_page.dart` | 1316 | 991 |
| `lib/server/server_types.dart` | 1268 | 拆成 `types/` 6 个领域文件（barrel 保留） |

`server_store.dart`（唯一状态源）**按约定不拆**。进度与约定见 `docs/refactor-status.md`。

### 工程

- 新增 CI（GitHub Actions）：Flutter（analyze + test）与 Node（服务端 + pi 插件测试）
- 新增 `.editorconfig` + 全仓 `dart format` 统一（88 个文件），并加 `.git-blame-ignore-revs`
- CI 增加格式检查与覆盖率测量（首次基线：行覆盖率 19.5%，暂不设阈值）

---

## [0.1.0] — 2026-10-05

首个公开版本：手机端 App + 电脑端服务端，局域网连接；会话列表 / 对话（流式与中断）/
文件浏览（含 Git 改动）/ 用量 / 导出 / 连接诊断等页面可用。
