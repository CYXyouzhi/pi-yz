# task-2：消息列表的每帧全量遍历（`_elapsedByKey`）

## 1. 问题

`lib/ui/server/chat_page.dart` 的 `build()` 里有一段**无条件**调用：

```dart
final elapsedMap = _elapsedByKey(chat);   // 旧代码，位于 build 内
...
Map<String, Duration> _elapsedByKey(ChatReducer chat) {
  final out = <String, Duration>{};
  int? prev;
  for (final m in chat.messages) {        // ← 遍历全部消息
    final at = m.timestamp;
    if (at != null && prev != null && at > prev) {
      out[m.key] = Duration(milliseconds: at - prev);
    }
    if (at != null) prev = at;
  }
  return out;
}
```

它做的事是「每条消息距上一条有时间戳的消息过了多久」（用来在气泡旁显示 `820ms` / `3.4s`）。

**问题在于它每次 `build()` 都重算**：

- `build()` 每帧都会跑 —— **包括流式输出期间**，那时每秒有几十帧；
- 会话上千条消息时，每帧就是**上千次循环 + 上千次 `Duration` 对象分配**；
- 全部发生在**主 isolate**（也就是 Android 的 UI 线程）上。

而且它的输入只有消息的 `(key, timestamp)` 序列 —— **列表没变，结果必然不变**，重算没有任何意义。

## 2. 改法：抽成带缓存的 `ElapsedIndex`

新建 `lib/server/elapsed_index.dart`，把逻辑从 `ChatPageState` 里搬出来（搬出来的另一个好处是**可单测**，原来的私有方法测不到）。

`ChatPageState` 只留一个字段 + 一次调用：

```dart
final _elapsed = ElapsedIndex();
...
final elapsedMap = _elapsed.of(chat);     // 命中缓存时直接返回上次的 Map
```

### 缓存键为什么是这四项

**不能用对象身份当键**：`ChatReducer.messages` 是**可变列表**（`final List<ChatMessage> messages = [];`，append-only），`ChatMessage` 的字段也不是 final。同一个 `ChatReducer` 实例的消息会一直增长 —— 用 `identical` 当键会导致**永远命中缓存、结果过期**。

于是键取「O(1) 能算出来、且内容一变就会变」的四项：

| 键成分 | 覆盖的变化 |
|---|---|
| `messages.length` | 追加新消息、往前插入历史（「加载更早」） |
| `first.key` | 头部被替换（历史重排、切换会话） |
| `last.key` | 尾部换成了另一条消息 |
| `last.timestamp` | 末条消息的时间戳被补上或改写 |

**已知的理论盲区**（写在代码注释里，没有藏）：中间某条消息的 `timestamp` 被改写、而首尾与长度都不变时，键不变、缓存不失效。现实里不会发生 —— 时间戳来自服务端事件、写入后不再修改；流式输出只改 `text`，而本索引根本不看 `text`（有专门的测试守住这一点）。

**键里不能放「所有时间戳之和」**：算它本身就是 O(n)，缓存就白做了。

## 3. 证据

### 3.1 缓存真的命中了（11 个单元测试）

`test/elapsed_index_test.dart`。关键的几条：

| 用例 | 断言 |
|---|---|
| 同一份消息重复取用 | 三次调用返回**同一 Map 实例**（`identical`），`misses == 1`、`hits == 2` |
| 追加消息后 | 返回**新实例**（`identical` 为 false），`misses == 2`，且新增那条的耗时为**偏离常规值的 5 秒**（确认算的是真值而不是碰巧） |
| 「加载更早」前插 | 长度变了 → 缓存失效；原首条现在有了「上一条」，值为真实的 3 秒 |
| 长度与首尾相同、仅末条时间戳变 | 仍要失效（证明 `last.timestamp` 确实是缓存键的一部分） |
| 流式输出（只改 `text`/`streaming`） | **仍是同一实例**、`misses` 不增 |
| 没有时间戳的消息 | 不产生间隔，**也不重置基准**（`k2` 相对 `k0` 是 3000ms，不是 0） |
| 时间戳倒退或相等 | 不记录（负数/零耗时没有意义） |
| **每帧调用一次的实际场景** | 1000 条消息 × 100 帧 → `misses == 1`、`hits == 99` |

最后一条是这次改动要解决的真实场景，用数字固定下来：

```
旧实现：100 帧 × 1000 条 = 100,000 次循环
新实现：                     1,000 次循环（+ 99 次 O(1) 键比较）
```

### 3.2 行为逐字不变

`_build()` 与原实现逐行一致，包括两处容易改错的边界：

- 时间戳为空的消息**既不产生间隔，也不重置基准**（所以它不打断「相邻两条有时间戳的消息」之间的计算）；
- `at > prev` 严格大于 —— **相等或倒退都不记录**。

这两条都有独立用例。

### 3.3 关于「实机计时」的取舍

**没有**做「改前 vs 改后」的实机帧耗时对比。原因：改动已经落地，要测改前版本得先回滚；而实机计时受设备负载、后台进程、模拟器转译影响，重复性差。

取而代之的是 §3.1 里的**确定性证据**：同一份输入、同样的调用次数，遍历次数从 100,000 降到 1,000 —— 这个数字不依赖设备，可复现，比一次噪声很大的实机计时更能说明问题。

全量门禁：`flutter analyze` 0 issue、`flutter test` **117 全过**（原 106 + 本次 11）。

## 4. 那这份 ANR 日志能对上吗

`docs/verify/health-check/evidence/anr-2026-10-04.txt`（9029 行）。

### 结论：**对不上**。这个修复不构成对那次 ANR 的解释。

四条理由，按证据强度排列：

**① 量级对不上。** ANR 的判据是 `Waited 25001ms for MotionEvent` —— 主线程 **25 秒**没能处理输入事件。而这个索引即使遍历上千条消息也是**微秒级**（单测里 100 帧才扫 1000 条）。要撑起 25 秒，需要的是**数量级完全不同**的原因。

**② 内存证据指向别处。** 日志头部的数字：

```
RssKb:      3,099,308   ← RSS 约 3.0 GB
RssAnonKb:  2,974,312   ← 其中匿名内存 2.97 GB
```

而同一份日志里的 Java 侧数据：

```
Heap: 42% free, 2743KB/4750KB          ← Java 堆总共才 4.75 MB
Total GC count: 3
Total GC time: 10.550ms                 ← GC 总共跑了 10.5 毫秒
Total blocking GC count: 0
```

**Java 堆只有 4.75MB、GC 总共 10.5ms，而匿名内存 2.97GB** —— 说明开销在**原生层**（Flutter engine / Skia / Dart heap），跟「Dart 层每帧多遍历一次列表」不是一回事。这正是**内存压力**的特征，不是算法复杂度的特征。

**③ 栈无法定位。** main 线程 `state=R`（在跑），栈是纯原生帧：

```
"main" prio=5 tid=1 Native
  | state=R schedstat=( 84136252782 603612520 42909 ) utm=7944 stm=469 core=1 HZ=100
  native: #00 pc 00b2d96d  .../base.apk (offset 2754000) (???) (BuildId: 10a8...)
  native: #01 pc 00b008cd  .../base.apk (offset 2754000) (???) (BuildId: 10a8...)
  ...（#02 一直到 #30 全是同一形式）
```

Flutter 的 Dart 代码在 Android 上就跑在 main 线程，所以**理论上**它能出现在这份栈里 —— 但所有帧的符号都是 `(???)`（native 库被 strip），**分不出是 Dart 还是 engine**。这一条不构成「不是 Dart 问题」的证明，只是说明**这份日志不足以定位**。

**④ 环境特殊。** `Build fingerprint: 'Redmi/manet/manet:15/...'` 配 `ABI: 'x86_64'` —— 这是 **MuMu 模拟器伪装的 Redmi 指纹**，不是真机。模拟器的内存统计与 x86 转译开销都会放大现象，不能直接当真实用户环境。

### 这个修复仍然值得做

ANR 对不上，**不代表这次改动没价值**：每帧遍历全部消息是**独立成立的真实浪费**（流式输出期间每秒几十次），改掉它有 §3.1 的独立证据。只是**不能**把它说成「ANR 已修复」——那样就是拿一个证据不足的因果链当作结论。

### 留给后续排查的新线索（本轮没解决）

- **RSS 2.97GB 匿名内存** 与 **Java 堆 4.75MB** 的巨大落差 —— 原生层内存问题，值得单独一轮查（候选方向：图片/纹理未释放、Dart heap 膨胀、模拟器转译开销）。这是目前最强的线索。
- main 线程 `utm=7944`（79.4 秒用户态 CPU）、`schedstat` 第三项 `42909`（等 CPU 次数）—— 说明主线程长期在忙，但**忙在哪个原生函数上不知道**，需要未 strip 符号的构建（`--native-debug-symbols`）才能定位。
- 该日志只捕获了**一次** ANR、且发生在模拟器上，代表性有限。

## 5. 改动文件

| 文件 | 改动 |
|---|---|
| `lib/server/elapsed_index.dart` | **新增**。`ElapsedIndex`：四项内容键 + `_build()`（逻辑与原实现逐行一致）+ `hits` / `misses` / `lastScanned` 诊断计数 |
| `lib/ui/server/chat_page.dart` | 删除私有方法 `_elapsedByKey`；新增 `final _elapsed = ElapsedIndex();`；`build()` 内改为 `_elapsed.of(chat)` |
| `test/elapsed_index_test.dart` | **新增**。11 个用例（缓存语义 7 + 数值一致性 4） |
