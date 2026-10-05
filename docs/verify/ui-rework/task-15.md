# task-15 · 多会话并行与会话归档清理（已完成）

四条合同逐条。实机截图在 `task-15/`，服务端拒绝删除的原始响应在 `task-15/11-delete-running-refused.txt`。

| # | 合同 | 状态 | 证据 |
|---|---|---|---|
| ① | 多个会话可同时运行并有总览（哪个在跑、跑到哪、花了多少），有截图 | ✅ | 造了三条会话并存：用 `curl` 往两个会话各发一条长任务（`sleep 45` / `sleep 60`），再打开开始页。`01-pool-overview.png`：卡片头「**正在运行 2 个**  共 3 个会话活着」，三行分别是 `1 / Run bash sleep 10 three times… / 闲置 15 秒 · 471 tok · $0.0027`、`powershell / 你好 / **已跑 32 秒** · 375 tok · $0.0100`、`powershell / [GOAL CONFIRMATION focus=goal] / 已跑 32 秒 · 375 tok · $0.0100`。跑着的行是转圈图标，空闲的是空心圈；工作区名、会话名、当前工具、时长、token、花费都在一行里 |
| ② | 快速在运行中的会话间切换 | ✅ | `02-switch-to-session.png`：在总览里点「你好」那一行，**一次点击**同时完成「打开该会话 + 切到会话页」—— 截图里已经是会话页、状态条写 `● 你好 正在跑 主人，您选… 8 秒 · 47 tok/s`，正文正是那条会话（`ask_user_question` 卡片 + `主人，您选择的答案是：苹果。`） |
| ③ | 会话可归档且归档后不出现在默认列表 | ✅ | 完整闭环五张：`03-session-menu-archive.png`（会话菜单第 3 项「**归档（默认列表里收起）**」，位于「复制为分支」与「删除」之间）、`04-list-after-archive.png`（归档前后对比：分组计数 **51 → 50**，那条「你好 · 2 条 · 18 天前」从列表里消失）、`05-archive-entry.png`（列表底部「**已归档 1 条** · 点开管理」）、`06-archive-sheet.png`（归档箱，写着「已归档只影响这台手机的默认列表，会话文件还在电脑上」+「捞回来」）、`07-archive-restored.png`（捞回后「已归档（0）· 这里空了，都捞回来了」） |
| ④ | 按工作区看磁盘占用并可清理旧会话（删除有二次确认、不能误删在跑的） | ✅ | **看**：`10-settings-storage-entry.png`（设置 → 工作区 → 存储占用）、`08-storage-groups.png`（总计 `723 MB / 248 条会话 / 28 个工作区` + 口径一行「只算会话 JSONL 文件本身（含图片等附件），单位字节」；按工作区分组，`1` 组展开列出每条会话的占用/条数/日期，最大一条 329 MB · 7359 条）。**二次确认**：`09-delete-confirm.png`（「删除这条会话？」写清标题、`329 MB · 7359 条消息`、「文件会从电脑上删掉，无法恢复。1 会腾出 329 MB。」+ 取消/删除）。**不能误删在跑的**：`11-delete-running-refused.txt` —— 会话正在跑时 `DELETE /api/sessions/<id>` 返回 `HTTP 409` + `{"error":"这条会话正在运行，先停下再删","running":true}`；UI 侧先拦一道（正在跑的会话行标「正在运行」并直接给 toast，不发请求） |

## 这轮加的代码

```
服务端 server/lib/session-pool.mjs   listDetailed()：从会话消息里现算 title / messageCount /
                                     outputTokens / cost / lastAction / runningMs
      server/lib/sessions.mjs        diskUsage()：按工作区统计 JSONL 字节数（含图片附件）
      server/index.mjs               /api/pool 改返回带细节的列表；新增 /api/sessions/disk；
                                     DELETE /api/sessions/:id 对「正在跑」返回 409（除非 ?force=1）
App   lib/server/server_types.dart    PoolSession / DiskSession / DiskGroup / DiskUsage + humanBytes
      lib/server/server_client.dart   pool() / diskUsage()；deleteSession 支持 force
      lib/server/server_store.dart    pool / disk 状态 + loadPool() / loadDisk() + 归档代理 +
                                      visibleSessions（默认列表过滤归档）
      lib/server/app_prefs.dart       归档集合本地持久化（archiveSession / unarchiveSession）
      lib/ui/server/pool_view.dart    RunningSessionsCard（总览 + 一键切换）、StoragePage（占用与清理）
      lib/ui/server/sessions_page.dart 总览行 + 归档行 + 会话菜单「归档/取消归档」+ 3 秒轮询池状态
      lib/ui/server/settings_page.dart 「存储占用」入口
```

## 这轮踩到并修掉的三处

| 问题 | 现象 | 处理 |
|---|---|---|
| 路由顺序会让「磁盘占用」被当成会话 id | `/api/sessions/:id` 的正则会先匹配 `/api/sessions/disk`，于是 `disk` 被当成要删的会话 | 把 `/api/sessions/disk` 的分支放到该正则之前，并在注释里写明原因 |
| 会话页/存储页每秒重建导致手势丢 | 总览卡片点不动（按下与抬起之间被重建）—— 和 task-14 状态条同一类问题 | 总览用 3 秒轮询而不是每秒重建；秒表只留在需要走秒的小组件内部 |
| 存储页看不到「哪条正在跑」 | 用户要点删除才知道删不了 | 会话行上标绿点 + 「正在运行」，点删除时先给 toast，不发请求（服务端那道 409 仍在兜底） |

## 复现步骤（MuMu 上自己再看一遍）

1. 电脑上往两个不同会话各发一条长任务：
   `curl -X POST http://127.0.0.1:30142/api/sessions/<id>/command -H "Authorization: Bearer <token>" -H "Content-Type: application/json" -d '{"id":"c1","type":"prompt","message":"Run bash sleep 60 then reply DONE."}'`
2. 手机开始页 → 顶部「正在运行 N 个」卡片列出这些会话（哪条在跑、跑了多久、多少 token、多少钱）。
3. 点其中一行 → 直接跳到那条会话，状态条也是那条会话的。
4. 任意会话右侧铅笔 → 「归档（默认列表里收起）」→ 分组计数 −1；滚到列表底部点「已归档 N 条」→「捞回来」。
5. 设置 → 存储占用 → 展开一个工作区看每条会话占多少 → 点「删除」看确认弹窗（写清占用和不可恢复）。
6. 想删一条正在跑的：先发一条 `sleep 120` 的任务，再删它 —— 手机先给 toast，用 `curl` 直接删会拿到 409。
