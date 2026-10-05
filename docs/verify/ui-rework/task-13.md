# task-13 · 离线与弱网（已完成）

四条合同逐条。实机截图在 `task-13/`。

| # | 合同 | 状态 | 证据 |
|---|---|---|---|
| ① | 断网后仍可读最近会话正文（明确缓存上限），有截图 | ✅ | 断网后进会话：`01-offline-chat-from-cache.png`（顶部提示条「离线 · 显示 10:47 的缓存（1 条）」+ 下面正文完整可读，含大量 bash/思考卡片）；另一会话 `03-offline-banner-count.png`（「离线 · 显示 08:49 的缓存（60 条）」）。**上限写死在界面里**：`04-settings-cache-limits.png` 写「已缓存 2 条会话 · 共 91.0 KB / 上限：最多 5 条会话、每条 150 条消息、正文合计 200 KB（图片不入缓存）」，并列出手上每条缓存的条数与体积（`01a0cb77 · 3 条 · 4.0 KB`、`01a0fe1f · 60 条 · 87.0 KB`） |
| ② | 缓存清理入口在设置里可手动清 | ✅ | `04-settings-cache-limits.png`：设置页「离线缓存」区，每条缓存右侧一个「清除」，下方一个「清空离线缓存」，再往下「本地数据与日志 → 清理本地数据」（走二次确认弹窗，文案「会清掉：未发送的草稿、常用语、本地缓存」）。每个动作都有 Toast 回执（`已清掉这条缓存` / `离线缓存已清空`） |
| ③ | 弱网下界面不卡死且操作有反馈 | ✅ | **不卡死**：服务端不在时连接卡不转圈，直接给具体原因 —— `02-offline-list-conn-refused.png` / `08-conn-refused-detail.png` 写「端口通到主机了，但没人监听（连接被拒绝）」，`09-settings-conn-failed.png` 写「连接失败」。**有反馈**：断网状态点顶栏「重试」，界面立即响应（提示条收起、拿到快照后正文更新，见 ⑤/⑥ 两张）。发消息路径的失败反馈在 task-3 已验（回填输入框 + Toast 写具体原因） |
| ④ | 恢复网络后自动补齐，不重复不丢消息（与 JSONL 对照） | ✅ | 用短会话 `01a0cb77`（powershell）做可数对照，逐行数据见 `10-jsonl-compare.txt`：断网前 JSONL 3 条 message 行 → 服务端恢复后 `curl` 往同一会话发一条 prompt → 变成 5 行（新增 `user: offline-resume-ok …` 与 `assistant: 主人，OK`）→ App 点「重试」。**补齐**：`05-after-retry-new-messages.png` 里新消息与回复都出现了。**不重复**：把会话从顶滚到底（`07-list-top-no-duplicate.png` 顶部是 `[GOAL CONFIRMATION focus=goal]` 开头，`06-list-bottom-new-messages.png` 底部是新消息），那条长消息全程只出现一次 —— 若走「缓存 + 快照」叠加，它要整段叠两遍 |

## 这轮加的代码

```
App  lib/server/session_cache.dart       离线缓存读写（5 会话 / 150 条 / 200 KB 上限，图片不入缓存）
     lib/server/server_store.dart        开会话先铺缓存、快照到达后落缓存、断连时保留缓存态
     lib/ui/server/chat_page.dart        会话页顶部的「离线 · 显示 HH:MM 的缓存（N 条）」提示条 + 重试
     lib/ui/server/sessions_page.dart    开始页「离线缓存」区（断网时也能点进去）
     lib/ui/server/settings_page.dart    设置页「离线缓存」区（逐条清除 / 清空 / 上限说明）
     lib/server/server_client.dart       连接层报错改成「人话 + 下一步」（端口拒绝 / 超时 / 401 分三类）
```

## 这轮修掉的两个真实缺陷

| 缺陷 | 现象 | 修法 |
|---|---|---|
| 重试把离线提示抹掉 | 断网时点「重试」，提示条消失了 —— 明明还是离线，界面却不再说明自己在看旧数据，用户会以为已经连上 | `openSession` 里删掉开头的 `cacheShownAt = null`，只在**服务端快照真的到达**时清（`_onEvent` 的 snapshot 分支）。这样重试失败提示条留着，成功才收 |
| 恢复后消息成对重复 | 离线看过一次缓存（key 是 `c0..cN`）再恢复网络，快照消息 key 是 `m0..mN`，两边对不上，`mergeSnapshot` 把同一段对话叠两遍 | 快照分支加条件：当前显示的是缓存（`cacheShownAt != null`）时**强制 `applySnapshot` 重建**，只有「消息本来就来自身份可信的服务端」时才走合并（保留已翻页历史） |

## 复现步骤（MuMu 上自己再看一遍）

1. 服务端跑着，App 打开一个短会话（几十条以内），等它渲染完 —— 这时缓存已落盘。
2. 电脑上 `taskkill` 掉服务端进程（或直接拔网），App 里 `am force-stop` 后重开：
   开始页会显示「离线缓存（N 条 · 断网也能读正文）」，连接卡写「端口通到主机了，但没人监听（连接被拒绝）」。
3. 点进缓存会话 → 顶部「离线 · 显示 HH:MM 的缓存（N 条）」，正文照读。
4. 重启服务端，另开一个终端往**同一会话**追加一条：
   `curl -X POST http://127.0.0.1:30142/api/sessions/<id>/command -H "Authorization: Bearer <token>" -H "Content-Type: application/json" -d '{"id":"c1","type":"prompt","message":"resume-test"}'`
5. 回 App 点「重试」：提示条收起，新消息出现；把会话从顶滚到底，确认老消息没有被叠第二遍。
6. 设置页 → 离线缓存区：点某条的「清除」→ Toast「已清掉这条缓存」；点「清空离线缓存」→ Toast「离线缓存已清空」。
