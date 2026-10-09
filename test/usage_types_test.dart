// 用量与健康检查两类 DTO 的 fromJson 守卫。
//
// 为什么值得单独一组：这些 fromJson 是**手写的防御式解析**（服务端字段可能缺、
// 类型可能变），而它们出了问题的表现形式很隐蔽 —— 不会崩，而是数字变成 0、
// 或者直接抛异常让某个面板点不开。历史上真出过一次：
//
//   `tokens / contextUsage` 是对象、`cost` 是**数字**，当时一律 `as Map` 解析，
//   于是服务端返回 double 时强转抛异常 —— 表现是「会话信息」面板点了没反应。
//   （见 types/usage.dart 里 SessionStats.fromJson 的注释）
//
// 所以这里的用例大多是「字段缺失 / 类型不对时不许抛、不许悄悄变成错的值」。
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/server/types/usage.dart';

void main() {
  group('SessionStats.fromJson', () {
    test('真实响应形状：tokens / contextUsage 是对象，cost 是数字', () {
      final s = SessionStats.fromJson({
        'userMessages': 3,
        'assistantMessages': 4,
        'toolCalls': 1,
        'toolResults': 1,
        'totalMessages': 8,
        'tokens': {
          'input': 44800,
          'output': 725,
          'cacheRead': 512,
          'cacheWrite': 0,
          'total': 46037,
        },
        'cost': 0.0072,
        'contextUsage': {
          'tokens': 15700,
          'contextWindow': 1000000,
          'percent': 1.6,
        },
      });

      expect(s.userMessages, 3);
      expect(s.assistantMessages, 4);
      expect(s.toolCalls, 1);
      expect(s.totalMessages, 8);
      expect(s.inputTokens, 44800);
      expect(s.outputTokens, 725);
      expect(s.cacheReadTokens, 512);
      expect(s.totalTokens, 46037);
      expect(s.contextTokens, 15700);
      expect(s.contextWindow, 1000000);
      expect(s.contextPercent, 1.6);
    });

    test('回归点：cost 是纯 double 时不许抛（曾经被 as Map 强转炸掉）', () {
      // 这条对应「会话信息面板点了没反应」那个 bug：解析函数对着 num 做 as Map。
      expect(() => SessionStats.fromJson({'cost': 0.0072}), returnsNormally);
      expect(SessionStats.fromJson({'cost': 0.0072}).costTotal, 0.0072);
    });

    test('cost 是对象 {total: x} 时也读得出来（两种形状都兼容）', () {
      expect(
        SessionStats.fromJson({
          'cost': {'total': 1.25},
        }).costTotal,
        1.25,
      );
    });

    test('cost 类型完全不对：按 0 处理，不抛', () {
      expect(SessionStats.fromJson({'cost': 'n/a'}).costTotal, 0.0);
      expect(SessionStats.fromJson({}).costTotal, 0.0);
    });

    test('tokens 不是 Map（服务端改了形状）：全部按 0，不抛', () {
      final s = SessionStats.fromJson({'tokens': 'oops', 'userMessages': 2});
      expect(s.inputTokens, 0);
      expect(s.outputTokens, 0);
      expect(s.totalTokens, 0);
      expect(s.userMessages, 2);
    });

    test('contextUsage 缺失：三个上下文字段是 null（而不是 0）', () {
      final s = SessionStats.fromJson({'userMessages': 1});
      expect(s.contextTokens, isNull);
      expect(s.contextWindow, isNull);
      expect(s.contextPercent, isNull);
    });

    test('contextUsage 里字段类型不对：同样按 null 处理', () {
      final s = SessionStats.fromJson({
        'contextUsage': {'tokens': 'x', 'percent': 'y'},
      });
      expect(s.contextTokens, isNull);
      expect(s.contextPercent, isNull);
    });

    test('整数位收到小数（num 兼容）：截断而不是抛', () {
      expect(SessionStats.fromJson({'userMessages': 3.7}).userMessages, 3);
      expect(SessionStats.fromJson({'userMessages': 3.0}).userMessages, 3);
    });
  });

  group('HealthInfo.fromJson', () {
    test('正常响应', () {
      final h = HealthInfo.fromJson({
        'ok': true,
        'piVersion': '1.0.4',
        'activeSessions': 2,
      });
      expect(h.ok, isTrue);
      expect(h.piVersion, '1.0.4');
      expect(h.activeSessions, 2);
    });

    test('空 JSON：不抛，字段取默认', () {
      final h = HealthInfo.fromJson({});
      expect(h.ok, isFalse);
      expect(h.activeSessions, 0);
    });
  });

  group('UsageTurn.fromJson', () {
    test('正常一轮', () {
      final t = UsageTurn.fromJson({
        'index': 2,
        'at': '2026-10-09T05:44:00.000Z',
        'provider': 'opencode-go',
        'model': 'deepseek-v4.1-flash',
        'input': 14800,
        'output': 103,
        'totalTokens': 14903,
        'cost': 0.0023,
        'durationMs': 4200,
        'tokensPerSec': 24.5,
        'cacheHitRate': 1.1,
        'stopReason': 'end_turn',
      });
      expect(t.index, 2);
      expect(t.provider, 'opencode-go');
      expect(t.input, 14800);
      expect(t.cost, 0.0023);
      expect(t.tokensPerSec, 24.5);
      expect(t.stopReason, 'end_turn');
    });

    test('空 JSON：可选字段全是 null，不抛', () {
      final t = UsageTurn.fromJson({});
      expect(t.index, 0);
      expect(t.at, isNull);
      expect(t.cost, isNull);
      expect(t.durationMs, isNull);
    });
  });

  group('SessionUsage / UsageTotals', () {
    test('turns 数组逐条解析，totals 汇总', () {
      final u = SessionUsage.fromJson({
        'turns': [
          {'index': 1, 'input': 100, 'cost': 0.01},
          {'index': 2, 'input': 200, 'cost': 0.02},
        ],
        'totals': {
          'input': 300,
          'output': 50,
          'cacheRead': 10,
          'cacheWrite': 0,
          'reasoning': 7,
          'cost': 0.03,
          'turns': 2,
        },
      });
      expect(u.turns.length, 2);
      expect(u.turns[0].input, 100);
      expect(u.turns[1].input, 200);
      expect(u.totals.input, 300);
      expect(u.totals.reasoning, 7);
      expect(u.totals.turns, 2);
    });

    test('空 JSON：turns 为空表，totals 全 0', () {
      final u = SessionUsage.fromJson({});
      expect(u.turns, isEmpty);
      expect(u.totals.input, 0);
      expect(u.totals.cost, 0.0);
    });
  });

  group('UsageSummary.fromJson', () {
    test('today / month / 三个分组列表都解析到位', () {
      final s = UsageSummary.fromJson({
        'today': {'tokens': 1200, 'cost': 0.5},
        'month': {'tokens': 90000, 'cost': 12.5},
        'scannedSessions': 254,
        'byProvider': [
          {'provider': 'opencode-go', 'tokens': 1000, 'cost': 0.4, 'turns': 12},
        ],
        'byDay': [
          {'day': '2026-10-09', 'tokens': 1200, 'cost': 0.5},
        ],
        'byWorkspace': [
          {
            'cwd': 'C:/Users/YOUZHI/Desktop/1',
            'tokens': 800,
            'cost': 0.3,
            'turns': 9,
            'sessions': 3,
          },
        ],
      });
      expect(s.todayTokens, 1200);
      expect(s.todayCost, 0.5);
      expect(s.monthTokens, 90000);
      expect(s.scannedSessions, 254);
      expect(s.byProvider.single.provider, 'opencode-go');
      expect(s.byProvider.single.turns, 12);
      expect(s.byDay.single.day, '2026-10-09');
      expect(s.byWorkspace.single.cwd, 'C:/Users/YOUZHI/Desktop/1');
      expect(s.byWorkspace.single.sessions, 3);
    });

    test('空 JSON：全部取默认，分组列表为空', () {
      final s = UsageSummary.fromJson({});
      expect(s.todayTokens, 0);
      expect(s.monthCost, 0.0);
      expect(s.scannedSessions, 0);
      expect(s.byProvider, isEmpty);
      expect(s.byDay, isEmpty);
      expect(s.byWorkspace, isEmpty);
    });

    test('分组列表里混进非 Map 元素：跳过它们，不抛', () {
      final s = UsageSummary.fromJson({
        'byProvider': [
          'garbage',
          {'provider': 'kimi', 'tokens': 5},
        ],
      });
      expect(s.byProvider.length, 1);
      expect(s.byProvider.single.provider, 'kimi');
      expect(s.byProvider.single.cost, 0.0);
    });

    test('分组条目缺 provider 名：显示 unknown 而不是崩', () {
      final s = UsageSummary.fromJson({
        'byProvider': [
          {'tokens': 5},
        ],
      });
      expect(s.byProvider.single.provider, 'unknown');
    });
  });
}
