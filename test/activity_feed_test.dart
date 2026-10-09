// 实时活动视图的数据层验证（task-14 的 ①②③④）。
//
// 为什么在这一层钉：界面上「正在跑什么 / 跑了多久 / 多少 tok/s」全是算出来的，
// 靠肉眼看截图只能证明「某一次对」，钉住纯函数才能保证每次都对。
// 实机部分只负责证明：状态条真的停在会话页顶上、新事件真的会自己冒出来。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/server/activity_feed.dart';
import 'package:pi_yz/server/i18n.dart';
import 'package:pi_yz/server/chat_models.dart';
import 'package:pi_yz/server/chat_reducer.dart';
import 'package:pi_yz/server/server_types.dart';

ChatMessage msg(
  String key,
  String role, {
  String text = '',
  String thinking = '',
  int? at,
  List<PiToolCall>? calls,
  PiUsage? usage,
}) {
  return ChatMessage(
    key: key,
    role: role,
    text: text,
    thinking: thinking,
    timestamp: at,
    toolCalls: calls,
    usage: usage,
  );
}

void main() {
  // 钉住中文：I18n.t 在无 context 时跟随系统 locale，而全量跑时
  // widget_test 会把 locale 改成 zh/en，导致这里的文案断言随测试顺序变化。
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  binding.platformDispatcher.localeTestValue = const Locale('zh');
  binding.platformDispatcher.localesTestValue = const [Locale('zh')];
  group('① 工具摘要：按参数名挑，未知工具退回首个子串', () {
    test('bash 取 command', () {
      expect(toolSummary('bash', {'command': 'flutter test'}), 'flutter test');
    });

    test('read 取 path', () {
      expect(toolSummary('read', {'path': 'lib/main.dart'}), 'lib/main.dart');
    });

    test('grep 取 pattern', () {
      expect(
        toolSummary('ffgrep', {'pattern': 'cacheShownAt'}),
        'cacheShownAt',
      );
    });

    test('参数名不认识时取第一个非空字符串', () {
      expect(toolSummary('weird', {'foo': 'bar', 'n': 1}), 'bar');
    });

    test('没有字符串参数 → 空串（界面显示为 —）', () {
      expect(toolSummary('weird', {'n': 1}), '');
      expect(toolSummary('weird', const {}), '');
    });

    test('ask_user_question 的结构化参数挑出人话（不是显示 —）', () {
      expect(
        toolSummary('ask_user_question', {
          'questions': [
            {'header': '水果偏好', 'question': '你最喜欢的水果？'},
          ],
        }),
        '水果偏好',
      );
      expect(
        toolSummary('pick', {
          'options': ['苹果', '香蕉'],
        }),
        '苹果',
      );
    });

    test('多行命令折成一行并截断', () {
      final s = toolSummary('bash', {
        'command': 'echo a\necho b\n${'x' * 200}',
      });
      expect(s.contains('\n'), isFalse);
      expect(s.endsWith('…'), isTrue);
      expect(s.length, lessThanOrEqualTo(91));
    });
  });

  group('① 时间线：每条消息摊成该有的条目', () {
    test('用户 / 思考 / 工具 / 回复各出一条', () {
      final chat = ChatReducer();
      final call = PiToolCall(
        id: 't1',
        name: 'bash',
        arguments: {'command': 'ls'},
      );
      chat.messages.addAll([
        msg('m1', 'user', text: '跑一下测试', at: 1000),
        msg('m2', 'assistant', thinking: '先看看目录', at: 1100, calls: [call]),
        msg('m3', 'assistant', text: '跑完了，全绿', at: 1200),
      ]);

      final snap = buildActivity(chat, now: 2000);
      expect(snap.items.map((e) => e.kind).toList(), [
        ActivityKind.user,
        ActivityKind.thinking,
        ActivityKind.tool,
        ActivityKind.reply,
      ]);
      expect(snap.items[2].title, 'bash');
      expect(snap.items[2].detail, 'ls');
    });

    test('纯工具轮的空文本不出「回复」条目', () {
      final chat = ChatReducer();
      chat.messages.add(msg('m1', 'assistant', text: '   ', at: 1000));
      expect(buildActivity(chat, now: 1500).items, isEmpty);
    });

    test('空会话 → 空时间线', () {
      final snap = buildActivity(ChatReducer(), now: 1000);
      expect(snap.empty, isTrue);
      expect(snap.current, isNull);
      expect(snap.toolCount, 0);
    });
  });

  group('①③ 当前动作与工具计数', () {
    test('正在跑的工具优先当「当前动作」', () {
      final chat = ChatReducer();
      final c1 = PiToolCall(id: 't1', name: 'read', arguments: {'path': 'a'});
      final c2 = PiToolCall(
        id: 't2',
        name: 'bash',
        arguments: {'command': 'sleep 30'},
      );
      chat.messages.addAll([
        msg('m1', 'assistant', thinking: '想想', at: 1000, calls: [c1]),
        msg('m2', 'assistant', at: 1100, calls: [c2]),
      ]);
      final done = ToolRun(id: 't1', name: 'read')..status = ToolStatus.done;
      chat.tools['t1'] = done;
      chat.tools['t2'] = ToolRun(id: 't2', name: 'bash'); // 默认 running

      final snap = buildActivity(chat, now: 2000);
      expect(snap.current!.title, 'bash');
      expect(snap.current!.running, isTrue);
      expect(snap.toolCount, 2);
    });

    test('全跑完 → 当前动作退回最后一条思考/回复', () {
      final chat = ChatReducer();
      final c1 = PiToolCall(
        id: 't1',
        name: 'bash',
        arguments: {'command': 'ls'},
      );
      chat.messages.add(msg('m1', 'assistant', at: 1000, calls: [c1]));
      chat.tools['t1'] = ToolRun(id: 't1', name: 'bash')
        ..status = ToolStatus.done;

      final snap = buildActivity(chat, now: 2000);
      expect(snap.current, isNull);
      expect(snap.items.single.failed, isFalse);
      expect(snap.items.single.running, isFalse);
    });

    test('工具出错会标出来', () {
      final chat = ChatReducer();
      final c1 = PiToolCall(
        id: 't1',
        name: 'bash',
        arguments: {'command': 'boom'},
      );
      chat.messages.add(msg('m1', 'assistant', at: 1000, calls: [c1]));
      chat.tools['t1'] = ToolRun(id: 't1', name: 'bash')
        ..status = ToolStatus.error;

      final snap = buildActivity(chat, now: 2000);
      expect(snap.items.single.failed, isTrue);
    });

    test('文件数按路径去重', () {
      final chat = ChatReducer();
      chat.messages.add(
        msg(
          'm1',
          'assistant',
          at: 1000,
          calls: [
            PiToolCall(id: 't1', name: 'read', arguments: {'path': 'a.dart'}),
            PiToolCall(id: 't2', name: 'edit', arguments: {'path': 'a.dart'}),
            PiToolCall(id: 't3', name: 'write', arguments: {'path': 'b.dart'}),
          ],
        ),
      );
      expect(buildActivity(chat, now: 2000).fileCount, 2);
    });
  });

  group('③ 运行时长与 token 速度', () {
    test('运行中：从本轮开始算到现在', () {
      final chat = ChatReducer()..isRunning = true;
      chat.messages.add(msg('m1', 'user', text: 'hi', at: 1000));
      final snap = buildActivity(chat, now: 61000, runStartedAt: 1000);
      expect(snap.elapsedMs, 60000);
      expect(humanDuration(snap.elapsedMs), '1:00');
    });

    test('没在跑 → 时长为 0（不编数字）', () {
      final chat = ChatReducer();
      chat.messages.add(msg('m1', 'user', text: 'hi', at: 1000));
      expect(buildActivity(chat, now: 61000).elapsedMs, 0);
    });

    test('不给 runStartedAt 就退回最后一条用户消息的时间', () {
      final chat = ChatReducer()..isRunning = true;
      chat.messages.addAll([
        msg('m1', 'user', text: '第一句', at: 1000),
        msg('m2', 'user', text: '第二句', at: 5000),
      ]);
      expect(buildActivity(chat, now: 15000).elapsedMs, 10000);
    });

    test('token 速度 = 本轮输出 / 秒数；不足 1 秒或没 token 时给 0', () {
      final chat = ChatReducer()..isRunning = true;
      chat.messages.add(
        msg('m1', 'assistant', at: 1000, usage: const PiUsage(output: 600)),
      );
      final snap = buildActivity(chat, now: 11000, runStartedAt: 1000);
      expect(snap.outputTokens, 600);
      expect(snap.tokensPerSecond, closeTo(60, 0.01));

      final fast = buildActivity(chat, now: 1500, runStartedAt: 1000);
      expect(fast.tokensPerSecond, 0);

      final noTok = buildActivity(ChatReducer(), now: 5000, runStartedAt: 1000);
      expect(noTok.tokensPerSecond, 0);
    });

    test('结束态：lastRunMs 带上，供界面写「用时 x」', () {
      final chat = ChatReducer()..lastRunMs = 83000;
      chat.messages.add(msg('m1', 'user', text: 'hi', at: 1000));
      final snap = buildActivity(chat, now: 99999);
      expect(snap.running, isFalse);
      expect(snap.lastRunMs, 83000);
      expect(humanDuration(snap.lastRunMs), '1:23');
    });
  });

  group('③ 计数只算本轮（历史别冒充“刚跑完”）', () {
    test('老会话空闲时不会把历史工具调用算成“本轮”', () {
      final chat = ChatReducer();
      // 上一轮：两次工具调用
      chat.messages.addAll([
        msg('m1', 'user', text: '第一轮', at: 1000),
        msg(
          'm2',
          'assistant',
          at: 1100,
          calls: [
            PiToolCall(id: 'a1', name: 'bash', arguments: {'command': 'ls'}),
            PiToolCall(id: 'a2', name: 'read', arguments: {'path': 'x.dart'}),
          ],
        ),
        // 本轮：只发了一句话，没有任何工具调用
        msg('m3', 'user', text: '谢谢', at: 5000),
        msg('m4', 'assistant', text: '不客气', at: 5100),
      ]);
      final snap = buildActivity(chat, now: 9000);
      expect(snap.toolCount, 0);
      expect(snap.fileCount, 0);
      // 但时间线里历史还在（用户往上滚能看到）
      expect(snap.items.where((e) => e.kind == ActivityKind.tool).length, 2);
    });

    test('本轮有工具调用时照常计数', () {
      final chat = ChatReducer();
      chat.messages.addAll([
        msg('m1', 'user', text: '第一轮', at: 1000),
        msg(
          'm2',
          'assistant',
          at: 1100,
          calls: [
            PiToolCall(id: 'a1', name: 'bash', arguments: {'command': 'ls'}),
          ],
        ),
        msg('m3', 'user', text: '再来', at: 5000),
        msg(
          'm4',
          'assistant',
          at: 5100,
          calls: [
            PiToolCall(id: 'b1', name: 'bash', arguments: {'command': 'pwd'}),
            PiToolCall(id: 'b2', name: 'write', arguments: {'path': 'y.dart'}),
          ],
        ),
      ]);
      final snap = buildActivity(chat, now: 9000);
      expect(snap.toolCount, 2);
      expect(snap.fileCount, 1);
    });
  });

  group('① 等待确认也进时间线', () {
    test('有等确认时：排在最上、状态条按它显示、计入 waitingCount', () {
      final chat = ChatReducer()..isRunning = true;
      chat.messages.add(msg('m1', 'user', text: 'hi', at: 1000));
      final snap = buildActivity(
        chat,
        now: 2000,
        runStartedAt: 1000,
        pending: const ['要删掉 3 个文件，确认吗？'],
      );
      expect(snap.waitingCount, 1);
      expect(snap.items.last.kind, ActivityKind.wait);
      expect(snap.items.last.title, I18n.t('ui.493b7bc5ff'));
      expect(snap.items.last.detail, '要删掉 3 个文件，确认吗？');
      expect(snap.current!.kind, ActivityKind.wait);
    });

    test('没有等确认时 waitingCount 为 0', () {
      final chat = ChatReducer();
      chat.messages.add(msg('m1', 'user', text: 'hi', at: 1000));
      expect(buildActivity(chat, now: 2000).waitingCount, 0);
    });
  });

  group('时间线裁剪：只留最近 max 条', () {
    test('超长会话不把内存撑爆', () {
      final chat = ChatReducer();
      for (var i = 0; i < 50; i++) {
        chat.messages.add(msg('m$i', 'user', text: 'n$i', at: 1000 + i));
      }
      final snap = buildActivity(chat, now: 9999, max: 10);
      expect(snap.items.length, 10);
      // 留下的是最新的那批
      expect(snap.items.last.detail, 'n49');
      expect(snap.items.first.detail, 'n40');
    });
  });

  group('时间格式', () {
    test('humanDuration', () {
      expect(humanDuration(0), '0 秒');
      expect(humanDuration(-5), '0 秒');
      expect(humanDuration(45 * 1000), '45 秒');
      expect(humanDuration(83 * 1000), '1:23');
      expect(humanDuration(59 * 60 * 1000), '59:00');
      expect(humanDuration(3725 * 1000), '1:02:05');
    });

    test('clockOf：没有时间戳就不显示时刻', () {
      expect(clockOf(0), '');
      final ms = DateTime(2026, 10, 4, 9, 5, 3).millisecondsSinceEpoch;
      expect(clockOf(ms), '09:05:03');
    });
  });
}
