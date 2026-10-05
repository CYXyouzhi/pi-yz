# 01 · 代码审查（task-1）：真 bug 与逻辑错误

本轮体检的代码层结果。**原则：先让编译器帮忙（语义分析），再人工核实**——
正则扫描信噪比太低（试过：287 处"除法"其实是 import、232 处 `as` 大多是安全的 JSON 解析），
所以改用「打开一批 bug 类 lint 规则 + 逐条人工判断」。

## 一、修掉的真问题

| # | 症状 | 根因 | 修法 | 严重度 |
|---|---|---|---|---|
| 1 | 重连后上一条会话的事件可能串到新会话 | `Timer` 回调里 `_events?.cancel()` 未 await 就立刻 `client.events(...).listen(...)`，旧订阅还没取消完 | 回调整体改 `async`，`await _events?.cancel()` | **中高** |
| 2 | 进程被 Android 杀掉后「上次会话」丢失 | `openSession` 里 `AppPrefs.instance.setLastSession(...)` 未 await（写 SharedPreferences 是异步的） | 补 `await` | **中** |
| 3 | 工具状态随会话累积（内存 + 界面残留上一轮工具卡片） | `mergeSnapshot` 只重建 `messages`，不清 `tools`；重连后 toolCallId 不一定复用 | `tools.removeWhere((_, r) => r.status != ToolStatus.running)`（运行中的保留，否则正在跑的工具会消失） | **中** |
| 4 | 类型安全被绕过 | `_modelRow(..., dynamic chat)` —— 参数写成 `dynamic`，内部 `chat.model` 等全成了 dynamic 调用（编译期不检查） | 改真实类型 `ChatReducer` | 中 |
| 5 | 类型推断失败 | `usage_page` 的 `?? const []` 是 `List<dynamic>` | 改 `[...?summary?.byProvider]`（由元素推断类型） | 低 |
| 6 | `Widget.dispose()` 里发起异步但无标记 | `_events?.cancel()` / `_client?.dispose()` 在非 async 的 `dispose()` 中 | 显式 `unawaited(...)`，表明是刻意而非漏写 | 低 |

门禁：每修完一批都跑 `flutter analyze`（保持 0 issue）与 `flutter test`（99 全过），未留下破损状态。

## 二、核实后确认「无问题」的地方（避免误改）

- **SSE 分帧**：客户端按 `

` 切帧，服务端 `server/lib/sse.mjs` 用 `data: ...

` 写出 —— **两端一致**；
  客户端用 `utf8.decoder` 作为**流式**转换器，多字节中文字符跨 chunk 不会被切坏（注释里记录了这一点）；
  坏帧 `catch (_) => return null` 丢弃但不断流 ✅
- **服务端 SSE 背压**：`res.writableLength > BACKLOG_LIMIT_BYTES` 就断开让客户端重连；
  可丢弃事件（`isDroppable`）在高水位时静默丢弃（后续 `*_end` 或下一条 update 会覆盖）；心跳、`cleanup()` 幂等 ✅
- **`chat_reducer` 状态机**：`message_start` 建消息、`message_update` 只吃 delta、`message_end` 用权威内容 `absorb`；
  事件丢失时 `_onMessageEnd` 会补一条保证内容不丢 ✅
- **主消息列表**：`ListView.builder` 无 `shrinkWrap`（懒加载），且**每一条都给了 `ValueKey`** ——
  注释说明「不给 key 会让上一条的展开状态串到这一条」，这个坑踩过并修好了 ✅
- **lib/ 死代码**：172 个顶层类/枚举/typedef/mixin **全部有引用**（0 个孤儿）；`flutter analyze` 0 issue
  意味着 `unused_element` / `unused_import` / `dead_code` 也全清 ✅

## 三、发现的性能隐患（已记录，未改）

`chat_page.dart` 每次 build 都会做两件 O(n) 的事（n = 消息条数）：

1. `_elapsedByKey(chat)`：**遍历全部消息**——注释说明「本轮耗时」是按相邻消息时间差算的。
2. `_focusMode` 打开时 `chat.messages.where(...).toList()`：**每次 build 重新过滤一遍**。

消息上千条时这两处会明显吃主线程。当前**未改**，原因是要动就得引入缓存/增量维护，
属于"改动面大于收益"且容易引入新 bug 的类型；先如实记录，留待有明确卡顿证据时再动。

## 四、一份真实 ANR 日志（重要证据）

仓库根目录的 `anr-tmp.txt`（694KB，未跟踪）是一份**真实 ANR**：

```
Subject: Input dispatching timed out (com.youzhi.pimobile.pi_mobile/.MainActivity
         is not responding. Waited 25001ms for MotionEvent).
RssKb: 3099308      <- 约 2.96 GB
RssAnonKb: 2974312  <- 匿名内存(堆) 约 2.84 GB
VmSwapKb: 0
"main" prio=5 tid=1 Native
  state=R schedstat=( 84136252782 603612520 42909 ) utm=7944 stm=469 core=1 HZ=100
```

**解读**：
- `state=R`（Running）而非 Blocked/Waiting → **主线程在跑而不是在等锁**；
- 栈全是 `base.apk (???)` → **release 版无符号的原生栈**（Flutter 引擎内部）；
- 匿名内存 2.84GB → **不是文件映射，是堆上真的堆了这么多东西**；
- 触发的输入是 `MotionEvent`（用户点了一下，等了 25 秒没响应）。

**已排除**：主消息列表不是元凶（`ListView.builder` 懒加载、无 `shrinkWrap`）。
**仍待定位**：只发生过 1 次，且是模拟器环境。已在第三节记录两处每帧 O(n) 的可疑点。
这份日志**建议保留**（作为后续定位的原始依据），不要删。
