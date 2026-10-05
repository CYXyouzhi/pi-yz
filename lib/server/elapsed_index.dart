import 'chat_models.dart';
import 'chat_reducer.dart';

/// 「这一轮花了多久」的索引：键是消息 key，值是它距**上一条有时间戳的消息**的间隔。
///
/// ## 为什么要单独抽出来并加缓存
///
/// 原来这段逻辑是 `ChatPageState._elapsedByKey`，在 `build()` 里**无条件**调用 ——
/// 也就是**每一帧都遍历全部消息**。会话上千条时，每一帧（包括流式输出期间每秒
/// 几十帧）都要跑一遍上千次循环加上千次 `Duration` 分配，这些全在主 isolate 上。
///
/// 而它的输入只有消息的 `(key, timestamp)` 序列，输出只由这两者决定：
/// 消息列表没变，结果就必然不变。所以完全没有必要重算。
///
/// ## 缓存键为什么长这样
///
/// `ChatReducer.messages` 是**可变列表**（append-only），`ChatMessage` 的字段也不是
/// final —— 所以不能用「对象身份」（`identical`）当键：同一个 `ChatReducer` 实例的
/// 消息会一直增长，用身份当键会导致**永远命中缓存、结果过期**。
///
/// 于是键取「能 O(1) 算出来、且内容一变就会变」的四项：
///
/// | 键成分 | 覆盖的变化 |
/// |---|---|
/// | `length` | 追加新消息、往前插入历史（「加载更早」） |
/// | `firstKey` | 头部被替换（例如历史重排、切换会话） |
/// | `lastKey` | 尾部换成了另一条消息 |
/// | `lastTimestamp` | 末条消息的时间戳被补上或改写 |
///
/// **已知的理论盲区**：中间某条消息的 `timestamp` 被改写、而首尾与长度都不变时，
/// 键不变、缓存不会失效。现实里不会发生 —— 消息时间戳来自服务端事件，一旦写入
/// 不再修改；而流式输出只改 `text`，不改 `timestamp`（且本索引根本不看 `text`）。
///
/// 键里**不能**放「所有时间戳之和」之类的东西：算它本身就是 O(n)，缓存就白做了。
///
/// ## 返回值的约定
///
/// 命中缓存时返回的是**同一个 Map 实例**（这正是「缓存命中」的可观测证据）。
/// 调用方**只读**，不要修改它。
class ElapsedIndex {
  int _len = -1;
  String? _firstKey;
  String? _lastKey;
  int? _lastTs;

  Map<String, Duration> _cached = const <String, Duration>{};

  /// 缓存命中次数。测试与诊断用 —— 「同一帧不重算」这条要靠它来断言，
  /// 光看 UI 是看不出来的。
  int hits = 0;

  /// 缓存未命中（真正重算）次数。
  int misses = 0;

  /// 上一次重算时遍历过的消息条数（诊断用：能算出省下了多少次遍历）。
  int lastScanned = 0;

  /// 取耗时索引。同样的消息列表重复调用时不会重算。
  Map<String, Duration> of(ChatReducer chat) {
    final msgs = chat.messages;
    final len = msgs.length;
    // 空列表时三项都是 null，等价于「长度为 0」这一个条件
    final firstKey = len == 0 ? null : msgs.first.key;
    final lastKey = len == 0 ? null : msgs.last.key;
    final lastTs = len == 0 ? null : msgs.last.timestamp;

    if (len == _len &&
        firstKey == _firstKey &&
        lastKey == _lastKey &&
        lastTs == _lastTs) {
      hits++;
      return _cached;
    }

    misses++;
    _len = len;
    _firstKey = firstKey;
    _lastKey = lastKey;
    _lastTs = lastTs;
    _cached = _build(msgs);
    return _cached;
  }

  /// 清空缓存（切会话、或怀疑数据被外部改写时用）。
  void reset() {
    _len = -1;
    _firstKey = null;
    _lastKey = null;
    _lastTs = null;
    _cached = const <String, Duration>{};
    lastScanned = 0;
  }

  /// 真正的计算。与旧实现逐字一致，保证行为不变：
  ///   · 时间戳为空的消息不产生间隔，也不重置基准；
  ///   · 时间戳**倒退或相等**时不记录（负数或零的「耗时」没有意义）。
  Map<String, Duration> _build(List<ChatMessage> msgs) {
    final out = <String, Duration>{};
    int? prev;
    for (final m in msgs) {
      final at = m.timestamp;
      if (at != null && prev != null && at > prev) {
        out[m.key] = Duration(milliseconds: at - prev);
      }
      if (at != null) prev = at;
    }
    lastScanned = msgs.length;
    return out;
  }
}
