// 离线缓存的上限逻辑测试（合同①要求「明确缓存上限」，那上限就必须真的生效）。
//
// 用 SharedPreferences 的官方 mock：_setMockInitialValues 之后，
// 读写走内存，测的是真实的存取路径而不是我另写一套假实现。

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/server/chat_models.dart';
import 'package:pi_yz/server/session_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

ChatMessage msg(int index, {String text = ''}) => ChatMessage(
  key: 'k$index',
  role: index.isEven ? 'user' : 'assistant',
  text: text.isEmpty ? '第 $index 条消息' : text,
  timestamp: 1700000000000 + index,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('上限之外的老消息会被丢掉，并且如实记下丢了几条', () async {
    final messages = [for (var i = 0; i < 200; i += 1) msg(i)];
    await SessionCache.save(
      sessionId: 's1',
      name: '测试会话',
      cwd: 'C:/work',
      messages: messages,
    );

    final cached = await SessionCache.load('s1');
    expect(cached, isNotNull);
    expect(cached!.messages.length, SessionCache.maxMessages);
    expect(
      cached.droppedCount,
      200 - SessionCache.maxMessages,
      reason: '丢掉的条数要能报出来',
    );
    // 留下的必须是最新的那批：最后一条与原始最后一条一致
    expect(cached.messages.last.text, messages.last.text);
  });

  test('单条超长正文会被裁剪，不会把整条会话撑爆', () async {
    final huge = 'x' * (SessionCache.maxCharsPerMessage * 3);
    await SessionCache.save(
      sessionId: 's2',
      name: '',
      cwd: '',
      messages: [msg(0, text: huge)],
    );
    final cached = await SessionCache.load('s2');
    expect(
      cached!.messages.single.text.length,
      lessThanOrEqualTo(SessionCache.maxCharsPerMessage + 20),
    );
    expect(cached.messages.single.text, endsWith('（离线缓存截断）'));
  });

  test('超过会话条数上限时，最老的会话被淘汰', () async {
    for (var i = 0; i < SessionCache.maxSessions + 2; i += 1) {
      await SessionCache.save(
        sessionId: 's$i',
        name: '会话$i',
        cwd: '',
        messages: [msg(i)],
      );
    }
    final entries = await SessionCache.entries();
    expect(entries.length, SessionCache.maxSessions);
    // 最后存的 s6 在，s0/s1 已经被挤掉
    expect(entries.first.sessionId, 's${SessionCache.maxSessions + 1}');
    expect(await SessionCache.load('s0'), isNull);
  });

  test('同一会话重复保存只占一份，并且排到最前', () async {
    await SessionCache.save(
      sessionId: 'a',
      name: 'A',
      cwd: '',
      messages: [msg(1)],
    );
    await SessionCache.save(
      sessionId: 'b',
      name: 'B',
      cwd: '',
      messages: [msg(2)],
    );
    await SessionCache.save(
      sessionId: 'a',
      name: 'A2',
      cwd: '',
      messages: [msg(3), msg(4)],
    );

    final entries = await SessionCache.entries();
    expect(entries.length, 2);
    expect(entries.first.sessionId, 'a');
    expect(entries.first.messageCount, 2);
    expect((await SessionCache.load('a'))!.name, 'A2');
  });

  test('清空与单条清除都真的生效', () async {
    await SessionCache.save(
      sessionId: 'x',
      name: '',
      cwd: '',
      messages: [msg(1)],
    );
    await SessionCache.save(
      sessionId: 'y',
      name: '',
      cwd: '',
      messages: [msg(2)],
    );

    await SessionCache.removeOne('x');
    expect(await SessionCache.load('x'), isNull);
    expect(await SessionCache.load('y'), isNotNull);

    await SessionCache.clear();
    expect(await SessionCache.entries(), isEmpty);
    expect(await SessionCache.totalBytes(), 0);
  });

  test('占用按 UTF-8 字节算（中文不能按字符数低估）', () async {
    await SessionCache.save(
      sessionId: 'zh',
      name: '中文名字',
      cwd: '',
      messages: [msg(0, text: '这是一段中文正文，用来验证字节数')],
    );
    final entries = await SessionCache.entries();
    expect(entries.single.bytes, greaterThan(30));
  });

  test('没缓存过就返回 null，不抛异常', () async {
    expect(await SessionCache.load('不存在'), isNull);
    expect(await SessionCache.entries(), isEmpty);
  });
}
