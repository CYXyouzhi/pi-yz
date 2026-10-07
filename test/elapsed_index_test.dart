// ElapsedIndex 的缓存语义测试。
//
// 为什么这些断言值得写：这段逻辑原来是「每帧遍历全部消息」，改成带缓存之后，
// **行为必须逐字不变**（旧的耗时数字一个都不能变），同时**缓存必须真的命中**
// —— 后者光看 UI 完全看不出来，只能靠计数器和 identical 断言。

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/server/chat_models.dart';
import 'package:pi_yz/server/chat_reducer.dart';
import 'package:pi_yz/server/elapsed_index.dart';

/// 造一条消息。`at` 为 null 表示没有时间戳（服务端事件里很常见）。
ChatMessage msg(int index, {int? at}) => ChatMessage(
      key: 'k$index',
      role: index.isEven ? 'user' : 'assistant',
      text: '第 $index 条',
      timestamp: at,
    );

/// 造一个带 n 条消息、每条相隔 step 毫秒的会话，起点 base。
ChatReducer chatWith(int n, {int base = 1700000000000, int step = 1000}) {
  final chat = ChatReducer();
  for (var i = 0; i < n; i += 1) {
    chat.messages.add(msg(i, at: base + i * step));
  }
  return chat;
}

void main() {
  test('空会话：返回空表，重复调用是同一个实例', () {
    final idx = ElapsedIndex();
    final chat = ChatReducer();

    final a = idx.of(chat);
    final b = idx.of(chat);

    expect(a, isEmpty);
    expect(identical(a, b), isTrue, reason: '同一个空列表应命中缓存');
    expect(idx.hits, 1);
    expect(idx.misses, 1, reason: '第一次必须真的算一次');
  });

  test('数值与旧实现一致：每条记录距上一条有时间戳的消息的间隔', () {
    final idx = ElapsedIndex();
    final chat = chatWith(3, step: 1000); // 三条，各相隔 1s

    final map = idx.of(chat);

    // 第一条没有「上一条」，所以不入表
    expect(map.length, 2);
    expect(map['k1'], const Duration(seconds: 1));
    expect(map['k2'], const Duration(seconds: 1));
    expect(map.containsKey('k0'), isFalse, reason: '第一条不该有耗时');
  });

  test('同一份消息重复取用时返回同一个 Map 实例，且不再重算', () {
    final idx = ElapsedIndex();
    final chat = chatWith(500);

    final a = idx.of(chat);
    final b = idx.of(chat);
    final c = idx.of(chat);

    expect(identical(a, b), isTrue);
    expect(identical(a, c), isTrue);
    expect(idx.misses, 1, reason: '500 条消息只该遍历一次');
    expect(idx.hits, 2);
    expect(idx.lastScanned, 500);
  });

  test('追加消息后缓存失效、返回新实例，且新增那条的数值正确', () {
    final idx = ElapsedIndex();
    final chat = chatWith(3, step: 1000);

    final before = idx.of(chat);
    expect(idx.misses, 1);

    // 追加第 4 条，距第 3 条 5 秒（偏离常规 step，好确认算的是真值）
    chat.messages.add(msg(3, at: 1700000000000 + 2 * 1000 + 5000));

    final after = idx.of(chat);

    expect(identical(before, after), isFalse, reason: '消息变了必须重算');
    expect(idx.misses, 2);
    expect(before.containsKey('k3'), isFalse);
    expect(after['k3'], const Duration(seconds: 5));
    // 老条目的值不受影响
    expect(after['k1'], const Duration(seconds: 1));
  });

  test('「加载更早」在前面插入历史：长度变了，缓存要失效', () {
    final idx = ElapsedIndex();
    final chat = chatWith(3, step: 1000);

    final before = idx.of(chat);

    // 在前面插入更早的一条（时间戳更小），模拟 historyHasMore 拉取
    chat.messages.insert(0, msg(9, at: 1700000000000 - 3000));

    final after = idx.of(chat);

    expect(identical(before, after), isFalse);
    expect(idx.misses, 2);
    // 新插入的那条成为第一条 → 不入表；原本的 k0 现在有了「上一条」
    expect(after.containsKey('k9'), isFalse);
    expect(after['k0'], const Duration(seconds: 3));
  });

  test('长度与首尾都相同的重排：只要末条时间戳变了也要失效', () {
    final idx = ElapsedIndex();
    final chat = chatWith(4, step: 1000);

    idx.of(chat);

    // 改写末条的时间戳（长度、firstKey、lastKey 都不变）
    chat.messages.last.timestamp = 1700000000000 + 3 * 1000 + 7777;

    idx.of(chat);

    expect(idx.misses, 2, reason: '末条时间戳是缓存键的一部分');
  });

  test('没有时间戳的消息：不产生间隔，也不重置基准', () {
    final idx = ElapsedIndex();
    final chat = ChatReducer();
    chat.messages.add(msg(0, at: 1000));
    chat.messages.add(msg(1, at: null)); // 无时间戳
    chat.messages.add(msg(2, at: 4000));

    final map = idx.of(chat);

    expect(map.containsKey('k1'), isFalse, reason: '没有时间就谈不上耗时');
    // k2 的前一条「有时间戳的」是 k0(1000)，所以是 3000 而不是 4000-? 或 0
    expect(map['k2'], const Duration(milliseconds: 3000));
  });

  test('时间戳倒退或相等：不记录（负数/零耗时没有意义）', () {
    final idx = ElapsedIndex();
    final chat = ChatReducer();
    chat.messages.add(msg(0, at: 5000));
    chat.messages.add(msg(1, at: 5000)); // 相等
    chat.messages.add(msg(2, at: 3000)); // 倒退
    chat.messages.add(msg(3, at: 6000)); // 相对 k2(3000) 是 3000

    final map = idx.of(chat);

    expect(map.containsKey('k1'), isFalse, reason: '相等不算耗时');
    expect(map.containsKey('k2'), isFalse, reason: '倒退不算耗时');
    expect(map['k3'], const Duration(milliseconds: 3000));
  });

  test('流式输出（只改 text，不动时间戳）不会让缓存失效', () {
    final idx = ElapsedIndex();
    final chat = chatWith(3, step: 1000);

    final before = idx.of(chat);

    // 模拟流式：末条文本变长，timestamp 不变
    chat.messages.last.text = '很长的流式输出……';
    chat.messages.last.streaming = true;

    final after = idx.of(chat);

    expect(identical(before, after), isTrue,
        reason: '索引只看 key 与 timestamp，text 变化不该触发重算');
    expect(idx.misses, 1);
  });

  test('reset() 之后会重新计算', () {
    final idx = ElapsedIndex();
    final chat = chatWith(3);

    idx.of(chat);
    expect(idx.misses, 1);

    idx.reset();
    idx.of(chat);

    expect(idx.misses, 2);
  });

  test('每帧调用一次的场景：1000 条消息、100 帧只算一次', () {
    // 这是这次改动要解决的实际问题 —— 用数字把它固定下来。
    final idx = ElapsedIndex();
    final chat = chatWith(1000);

    for (var frame = 0; frame < 100; frame += 1) {
      idx.of(chat);
    }

    expect(idx.misses, 1, reason: '100 帧里只该真正遍历 1 次');
    expect(idx.hits, 99);
    expect(idx.lastScanned, 1000);
    // 旧实现是 100 × 1000 = 100000 次循环；现在是 1000 次。
  });
}
