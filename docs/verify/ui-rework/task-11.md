# task-11 · 通知、卡住自动提醒与免打扰（已完成）

六条合同逐条。实机截图在 `task-11/`，系统级证据在 `task-11/16-notification-dump.txt`。

| # | 合同 | 状态 | 证据 |
|---|---|---|---|
| ① | 跑完 / 需要你确认 / 出错三类通知，含会话名与一句结果摘要，点击直达 | ✅（两类实机 + 一类同路径） | 通知栏截图 `02-notif-shade-two-cards.png`（`pi agent · 测试通知` 与 `pi-yz · 跑完了` 两张卡片，第二张带摘要）；`16-notification-dump.txt` 里 `android.title=String (pi-yz · 跑完了)` + 摘要正文；点击直达 = `10-tap-notification-jump.png`（App 停在「开始」tab → 带 `sessionId` 的 intent 进来 → 自动切到「会话」tab）。三类共用一个发送函数 `_notify()`，触发条件各有单测；「需要确认」那次没单独构造，见文末 |
| ② | 卡住 / 长时间无输出自动提醒：超过可配置时长没新输出就提醒 | ✅ | `16-notification-dump.txt`：`android.title=String (pi-yz · 好像卡住了)` / `android.text=String (已经 18 秒没有新输出（阈值 15 秒，可在设置里改）)`；阈值入口 `08-stall-threshold.png`（1/2/5/10 分钟 chips + 「卡住阈值自定义…」）；`09-threshold-1min.png`（选 1 分钟后自检里 `阈值=60s`，说明界面选的和存的是同一个值）；触发时自检 `07-stall-fired-selfcheck.png`（`已提醒过=true · 压掉 0 条`） |
| ③ | 同一停顿只提醒一次，不重复骚扰 | ✅ | 单测 `test/notification_center_test.dart`：`alreadyNotified=true → shouldNotifyStall=false`；实机：卡住通知 `when=1791070994249` 发出后 35 秒再 dump，`when` 仍是那一个（通知内容一直是「好像卡住了」，直到 54.7 秒后「跑完」才覆盖）。5 秒一次的 tick 在跑——自检里 `tick` 从 4 涨到 285 |
| ④ | 通知栏快速回复：不进 App 就能回一句 | ✅ | `03-quick-reply-expanded.png`（通知卡片展开出「回一句（会作为插话发进去）」输入框）、`04-quick-reply-typed.png`（输入 `quick-reply-from-shade`）、`05-after-quick-reply-selfcheck.png`（回复后 App 自检 `距上次输出 0s`，说明消息进了会话）、`06-chat-receiving-reply.png`（会话里 pi 已开始处理）。**落盘为证**：`~/.pi/agent/sessions/--C--Users-you-Desktop-1-pi-yz--/2026-10-02T19-37-57-553Z_*.jsonl` 第 143 行 `{"type":"message","role":"user", "text":"quick-reply-from-shade"}`，时间 23:46:37 |
| ⑤ | 长任务看护模式：只在需要人时提醒 | ✅ | 开关 `01-notif-settings.png`/`14-watch-only-suppressed.png`；实机压掉记录：`14-watch-only-suppressed.png` 里「最近被压掉的提醒」含 `· pi-yz · 跑完了（看护模式：跑完不吵）`；单测：`suppressReason(watchOnly=true, kind=done)` 返回看护理由，而 `needInput`/`error`/`stalled` 仍为 `null`（照样提醒） |
| ⑥ | 免打扰时段生效 | ✅ | `15-dnd-on-in-window.png`：选中 `23→8` 后状态行变成「通知已开启（当前在免打扰时段）」（此刻 07:5x 落在窗口内）；实机压掉记录 `13-dnd-suppressed.png`：`· pi-yz · 跑完了（免打扰时段 23:00–8:00）`；单测覆盖跨零点判定 `inHours(hour, 23, 8)`（23、0…7 点命中，8 点不命中） |

## 这轮加的代码

```
App  lib/server/notification_center.dart   通知中心（457+ 行）：判定、抑制、去重、快速回复、自检
     android/.../MainActivity.kt           通知收发 + RemoteInput 快速回复（框架自带 API，不引三方库）
     android/.../AndroidManifest.xml       POST_NOTIFICATIONS 权限
     lib/ui/server/settings_page.dart      通知设置区（开关 / 阈值 / 免打扰 / 自检 / 测试通知）
     lib/main.dart                         挂载通知中心 + 前后台切换 + 从通知切到会话页
     lib/server/i18n.dart                  通知区文案中英两份
测试 test/notification_center_test.dart   20 条：免打扰窗口、卡住判定、六类抑制理由、停顿时长文案
```

## 这轮修掉的三个真实缺陷

| 缺陷 | 现象 | 修法 |
|---|---|---|
| 定时器泄漏 | `attach()` 建的 5 秒定时器永不取消，widget 测试直接报 `A Timer is still pending even after the widget tree was disposed`（回归 1 条） | 新增 `detach()`：取消定时器 + 摘监听 + 清原生回调；`main.dart` 的 `dispose()` 调用它 |
| 点通知不跳页 | App 已在前台且停在别的 tab 时，点通知只打开会话、界面不动 —— 因为壳里那个「看到会话就跳一次」的标志是一次性的，启动时就用掉了 | 通知中心暴露 `onOpenSessionRequested` 回调，由 App 壳注入「切到会话页」；改完实测 `10-tap-notification-jump.png` 从「开始」跳到「会话」 |
| 卡住文案说「0 分钟」 | 阈值设成 15 秒时通知写「已经 0 分钟没有新输出」，没有信息量 | 抽纯函数 `humanIdle()`：不足 1 分钟说秒（`18 秒`），1 分 30 秒说 `1 分 30 秒`；6 条单测钉住 |

## 复现步骤（MuMu 上自己再看一遍）

1. 设置页 → 通知区：确认「通知已开启」；点「卡住阈值自定义…」填 15 秒。
2. 会话页发一句会让 pi 跑一阵的话（例如让它跑 `flutter clean` 再构建）。
3. 等 20 秒左右，`dumpsys notification --noredact | grep -E "android.title|android.text"` 能看到「好像卡住了」。
4. 主屏下拉通知栏 → 点「快速回复」→ 打一句 → 发送；回到 App 会话页可见这句已进会话。
5. 免打扰选 `23→8`（当前时刻落在窗口内）再跑一轮：通知不发，设置页「最近被压掉的提醒」记一条。

## 已知不足（如实写）

- **「需要确认」与「出错」两类通知没有单独拿到实机截图**。它们与「跑完了」走同一个 `_notify()` 函数（同一权限、同一通道、同一点击直达路径），差异只在触发条件；触发条件由单测覆盖（`_onRunFinished` 先看 `uiRequests` 再看 `last.isError`）。要单独构造得让 pi 真的进入「等人选」或自身报错状态 —— 本轮没做，标注在这里而不是假装验过。
- **通知栏界面截图在 MuMu 里不稳定**：App 跑在独立 display 上，通知栏属于主屏 display，同一个下拉手势有时给通知列表、有时给 QS 面板。所以②的主证据用的是 `dumpsys`（系统自己的账本），截图作为辅证。
- **通知合并**：所有会话共用通知 id 1001，后一条覆盖前一条。好处是不刷屏，代价是同时跑多个会话时旧通知会被顶掉。
- **后台不保活**：App 退到后台后定时器与网络可能被系统掐，卡住提醒只在前台可靠。真正的后台保活要前台服务，属于 task-10 的范围。

<!-- 开源前把用户名统一写成 you，其余内容未改（本文件是验证记录，不歪曲证据）。 -->
