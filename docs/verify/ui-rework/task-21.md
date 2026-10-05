# task-21 · UI 统一①：按手机端习惯重做五大界面（已完成）

前提：task-1~20 的功能全部完成（20/23 完成时开工）。逐项前后对比截图在 `task-21/`。

| # | 合同 | 状态 | 证据 |
|---|---|---|---|
| ① | 会话消息区：工具调用**默认折叠为单行小条**（不是大块卡片）、模型与思考统一窄折叠条、「**重点模式**」一键只看对话主干、每条消息旁显示**本轮耗时**、运行中/失败/空态三态齐备 | ✅ | **单行小条**：`01-tools-compact-and-elapsed.png` —— `⬛ bash 调用` / `⬛ bash 完成 ›` 各占一行细条（改造前是两行大卡片：26px 图标 + 标题 + 副标题 + 标签）。思考块本来就是窄折叠条（`_ThinkingBlock`，默认收起）。**本轮耗时**：同一张图右侧 `13s`，挂在真正花时间的那一步（工具结果）上。**重点模式**：`02-focus-mode-off.png`（全部消息，可见两条 bash 工具条）↔ `03-focus-mode-on.png`（一键收起后只剩对话主干：`主人，p2` / `reply only: e1` / `主人，e1` / `Run bash sleep 4…` / `主人，TIMED`）。**三态**：运行中（状态条 + typing dots）、失败（工具条变 `失败` 红标 + 气泡下「出错」）、空态（`还没有活动` + `发一句话…`）都各有截图（见 task-13/14 与本目录） |
| ② | 输入区：键盘条与发送/换行布局合理、命令面板与模板入口不拥挤、附件入口清晰 | ✅（已有能力，本轮未动） | 这三样是前面任务做好的：**键盘条**（`lib/ui/key_bar.dart`，⌘ 按钮展开，专治手机上打不出的键，task-6）、**命令面板**（输入 `/` 弹补全，`_showSuggestions`，task-6）、**模板/常用语**（`template_store.dart` + 工具栏「⌘」旁入口）、**附件**（输入条最左侧 `+`，走 file_picker，task-9/20）。本轮只是按「不拥挤」复核了排布：`+`（附件）→ `⌘`（键盘条）→ 输入框 → 发送/换行，一条线上四个，没有新增元素，故没有改动 |
| ③ | 设置页：**折叠分组 + 可滚动**，pi 配置与 App 配置分区清晰，改字号后全界面真实生效 | ✅ | **折叠**：`04-settings-groups-expanded.png`（「连接」「工作区」都是展开态 + 右侧 `⌄`）↔ `05-settings-group-collapsed.png`（点了「工作区」标题后内容收起、箭头变 `›`，后面的「外观」直接顶上来）。实现是 `ServerSettingsPage` 改成 StatefulWidget + `_collapsed` 集合，标题行整行可点。**分区**：分组本身就是分区 —— 「连接 / 工作区（AI 配置、文件浏览、存储占用）/ 外观 / App 设置 / 通知 / 关于」，其中「工作区」里的项都是**电脑端 pi 的配置**、「App 设置」与「外观」是**手机端自己的**。**可滚动**：`ListView` + 底部 104px 让出 tab 栏。**字号生效**：`AppPrefs.fontScale` → `MediaQuery.textScaler`，改完整个 App 的文字一起变（task-7 做的，本轮未回归） |
| ④ | 开始页：连接卡**精简无多余按钮**，会话按工作区分组，每行显示最后一句/轮数/相对时间并能**看出哪个在跑**，空态/加载/错误态齐备 | ✅ | **连接卡精简**：开始页的连接卡现在只有「状态点 + 地址/已连接 + 会话数」一行（代码里留着注释说明「原本还有个手动刷新的圆按钮，已去掉」）；管理动作（刷新会话 / 断开）收进**设置页**的连接卡，那里是管理区。**分组**：按 cwd 分组、组内条数徽标（task-4 做的，一直保持）。**每行信息**：`${messageCount} 条 · ${相对时间}`（如「125 条 · 2026-09-02」）。**哪个在跑**：本轮新加 —— 会话行左侧图标在跑时变成转圈（`IconId.spinner`）且副标题变绿写「正在跑 · N 条 · 相对时间」，数据直接取 `/api/pool`（task-15 的总览同一份源）。**三态**：空（`_EmptyRow`）、加载（`loadingSessions` 骨架）、错误（`sessionsError` + 重试）都有 |
| ⑤ | 文件页：目录层级、面包屑、返回行为、预览入口一致 | ✅（task-5 交付，本轮复核） | `WorkspaceFilesPage` / `FilesPage`：从会话工作区进入（设置 → 文件浏览），有面包屑（可点任意一级跳回）、点目录下钻、系统返回键退回上一级（栈内行为与全 App 一致）、点文件进预览（文本走 `readFile`、图片走 `/api/file/raw`）。本轮复核未发现与本轮改动冲突的地方 |
| ⑥ | 同层级标题/正文/辅助文字在五个 tab 的字号与颜色一致，同一动作不再出现两种图标 | ✅（字号已 token 化） | **字号**：把五个页面里最高频的五个字面量收进 `NeuFonts`，**值不变、纯改名**，共替换 **285 处**：`12.5 → NeuFonts.sub`、`11.5 → NeuFonts.label`、`12 → NeuFonts.small`（新增）、`13 → NeuFonts.bodySmall`（新增）、`13.5 → NeuFonts.bodyMid`（新增）。改前这五个值散在各处（12.5 出现 67 次、11.5 出现 60 次…），想统一调一次得全局搜；改后调「辅助文字多大」只需动 `design_tokens.dart` 一处。**颜色**：本来就统一走 `NeuTokens`（`t.fg` / `t.muted` / `t.accentInk` / `t.danger`），没有裸 `Colors.xxx`（本轮的 grep 复核确认）。**图标唯一性**：同一动作统一成同一个 `IconId` —— 会话操作菜单（重命名/复制为分支/归档/删除）、消息操作菜单（复制/引用/编辑重发/分享）、头部（重点模式 `bubble` / 分享 `share` / 信息 `info` / 新建 `plus`）、工具条（`terminal` / `pen` / `cmd` / `download` 按工具类型，见 `activity_view.dart` 的 `_iconOf`） |

## 这轮改的代码

```
App  lib/ui/server/message_view.dart   _ToolShell 加 compact（单行细条：4px 内边距、18px 图标、无副标题）；
                                       humanElapsed() + 工具结果/气泡旁的「本轮耗时」
     lib/ui/server/chat_page.dart      「重点模式」开关（头部最左按钮）+ 列表过滤 + _elapsedByKey()
     lib/ui/server/settings_page.dart  StatelessWidget → StatefulWidget；_section 变可点击折叠标题；五组内容按 _collapsed 收起
     lib/ui/server/sessions_page.dart  会话行「哪个在跑」标记（读 /api/pool）
     lib/server/server_types.dart      新增 parseTimestamp()（iso 字符串 / 毫秒都认）
     lib/server/chat_reducer.dart      增量消息缺 timestamp 时用本机时间兜底
     lib/theme/design_tokens.dart      NeuFonts 补 small / bodySmall / bodyMid
     lib/ui/**（五个页面）             285 处硬编码字号 → NeuFonts token
```

## 这轮修掉的三个真缺陷

| 缺陷 | 现象 | 修法 |
|---|---|---|
| 时间戳只认数字 | `PiMessage.timestamp` 写成 `(json['timestamp'] as num?)?.toInt()`，而 pi 落盘的是 **ISO 字符串** —— 于是**所有消息的 timestamp 都是 null**，「本轮耗时」永远算不出来 | 抽 `parseTimestamp()`：数字当毫秒、字符串按 ISO 解析，两种都认 |
| 增量消息没有时间戳 | 就算修好解析也没用：`message_start` 增量事件里的消息**不带 timestamp**（pi 是落盘那一步才补）。实测消息间隔 25 秒仍不显示耗时 | `ChatMessage` 创建后用本机时间兜底，`message_end`/快照拿到权威时间时被 `absorb` 覆盖 |
| 重点模式点了没反应 | `onTap: () => setState(() { …; NeuToast.show(context, …); })` —— 在 setState 回调里触发界面更新是反模式，实测点击无响应（连点三次界面都不变） | 拆开：先 `setState` 再弹提示 |
