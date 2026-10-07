# task-9 · 手机端便利能力（已完成）

十项逐条，实机截图在 `task-9/`，落盘/命令行证据写在表里。

| # | 项 | 状态 | 证据 |
|---|---|---|---|
| ① | 双击复制 | ✅ | 手势套在**整条消息（含左右留白）**上，双击即整条复制。widget 测试 `test/message_actions_test.dart`「① 双击消息（留白处）把整条正文复制到剪贴板」断言剪贴板内容 |
| ② | 长按菜单（复制 / 引用 / 编辑重发 / 分享） | ✅ | 实机截图 `menu.png`；`quote.png` 是点「引用」后正文进输入框；测试覆盖「助手消息没有编辑重发、用户消息有」 |
| ③ | 左滑/右滑把用户消息拉回输入框改写再发 | ✅ | `swipe-to-edit.png`（滑动后输入框里就是那条消息的正文）；代码里横滑任意方向都认 |
| ④ | 删除类可撤销 / 一致二次确认 | ⚠️ 部分 | 已有二次确认：清理本地数据、移除 MCP、卸载插件、撤回消息（撤回条 `撤回 ✕`）；本轮新增「移除待发图片」的 SnackBar 撤销（`_showUndo`）。**缺口**：这条撤销的实机截图没拿到 —— 见文末「未做到的部分」 |
| ⑤ | 暂停/停止当前任务 | ✅ | `running-stop.png`：运行中输入框提示「运行中…可输入以插话」，右侧按钮变红色 ✕（点它 `abort()`） |
| ⑥ | 继续 / 再来一次 | ✅ | 输入框上方常驻两个按钮（截图中可见）；点「继续」后落盘新增一条 `user: 继续`（会话 JSONL 第 36 条，21:57:12） |
| ⑦ | 新建会话模板 | ✅ | `new-session-template.png`（长按「新会话」→「用哪句开场？」列表，模板复用输入区 ＋ 菜单里存的那份）+ `workspace-picker.png`（选中模板后进入工作区选择） |
| ⑧ | 本轮改动速览（哪些文件、增删多少行） | ✅ | `turn-changes.png`：`本轮改动 1 个文件 +10/-0` + 文件路径 + `+10/-0 · 整文件写入 1` + 口径说明。数字与落盘对得上：那次 `write` 的 content 正好 10 行，文件 `wc -l` = 10 |
| ⑨ | 图片长按保存到相册 | ✅ | `save-image.png` + 机器证据：`/sdcard/Pictures/pi-yz/pi-1791063626747.png`（用 `ls` 查到文件真的落盘） |
| ⑩ | 会话片段分享（系统分享面板） | ✅ | `system-share.png`：Android 分享面板被拉起（显示「没有应用可执行此操作。」—— MuMu 里没装任何可接收分享的应用，是环境事实，不是 App 的问题）。另在消息菜单与聊天页头部各有一个分享入口 |

## 这轮加的代码

```
服务端  server/lib/turn-summary.mjs       本轮改动速览：从 JSONL 数 edit/write 的增删行（带口径）
        server/index.mjs                  GET /api/sessions/:id/turn-summary
App     lib/server/native_bridge.dart     分享 / 存相册（自写 MethodChannel，不引三方依赖）
        android/.../MainActivity.kt       ACTION_SEND + MediaStore 写图（约 60 行 Kotlin）
        lib/ui/server/message_view.dart   双击复制、⋮ 菜单、图片长按存相册
        lib/ui/server/chat_page.dart      横滑回输入框、继续/再来一次、本轮改动条、分享入口、待发图片撤销
        lib/ui/server/sessions_page.dart  长按「新会话」选模板
        lib/ui/neu_icons.dart             补 copy / share / image / more 四个图标
测试    test/message_actions_test.dart    5 条用例钉住双击、菜单、原生桥
```

## 顺手抓出并修掉的一个 P0（本次验收最大收获）

**现象**：App 装到新版本后，进到「有正在运行的会话」时整机卡死 —— Android 弹「pi-yz 没有响应」，
`ANR in …MainActivity, Reason: Input dispatching timed out (Waited 25001ms for MotionEvent)`；
`top` 看到 App **113% CPU / 3.0GB RSS**，ANR 堆栈里主线程 **512 层**深、同一组 pc 反复出现。

**根因**（不是 task-9 引入的，是 task-8 那套用量轮询里埋的）：
`_syncUsagePolling()` 是**在 store 的通知回调里**跑的，而它先调了 `_store.loadSessionUsage()` ——
那个方法第一行就是 `loadingUsage = true; _notify();`；`_usageTimer` 又是在这行**之后**才赋值，
于是这个「重入闸门」还没装上就又被通知进来：
`_notify → _onStoreChanged → _syncUsagePolling → loadSessionUsage → _notify → …` 无限递归。

**修法（两层）**：
1. `chat_page._syncUsagePolling`：**先装定时器再拉数据**（把闸门放到重入发生之前），跑完分支同理；
2. `server_store._notify`：加重入保护 —— 重入时只置一个 pending 标志，用 `scheduleMicrotask` 补一次通知，
   不再在同一调用栈里嵌套。

**修完实测**：同一状态空闲 25 秒 → CPU **1.7%**、RSS **202MB**、ANR **0**（`after-reentrancy-fix.png` 是修完后正常加载出会话列表的样子）。

## 未做到的部分（写明原因，不装）

1. **① 的落点在正文上有取舍**：气泡正文用的是可选中的 Markdown 渲染，双击在**正文字**上仍然是系统的「选词」，
   双击复制只在留白/头像上生效。刻意保留：选一段文字复制比整条复制更常用。
   另外 MuMu 的 `input` 通道**打不出真双击**（两次 `input tap` 各是一次进程启动，间隔 > 300ms，出了双击窗口），
   所以「双击」这一条只能在 widget 测试层钉住，实机没有对应截图。
2. **④ 的「移除待发图片 → 撤销」没有实机截图**：模拟器的系统相册选择器选不出图（点选后不返回数据），
   拿不到「待发图片」这个状态。撤销机制本身（SnackBar + action）在代码里，删除类操作的二次确认有截图。
3. **⑩ 只能证明「面板被拉起」**：MuMu 里没有可接收分享的应用，所以看不到真正分享出去的结果；
   分享内容本身由 widget 测试断言（`share` 通道收到的 text 参数）。
4. **⑧ 的口径有限**：只算 `edit` / `write` 两个工具，`bash` 里用 sed/python 改的文件算不出来 ——
   这个口径直接显示在界面上（`统计口径：只算 edit / write 工具；bash 里的文件改写不计入`），不装作全量。

## 测试期间产生的东西

- `docs/verify/ui-rework/task-9-notes.md`：验证 ⑧ 时让远端 agent 写的小文件，留作证据。
- `/sdcard/Pictures/pi-yz/` 下多了一张验证用的图（⑨ 的产物）。
- 会话 `01a0fe1f` 里多了几条测试消息（「create docs/…」「继续」）。
- 临时调试用的 `[access]` / turn-summary 日志已从 `server/index.mjs` 清掉，服务已重启。
