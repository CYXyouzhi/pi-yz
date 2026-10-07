// 通知判定的确定性验证（task-11 的 ②③⑤⑥）。
//
// 为什么在这一层钉：实机上要造出「运行中且 15 秒没有任何输出」很难 ——
// 真跑一个长命令时工具输出会一直流，反而不算卡住（这是对的）；
// 而把服务端杀掉又会被判成「跑完了」。所以用纯函数把判定逻辑测干净，
// 实机部分只负责证明「通知这条路通」与「设置项真的在界面上」。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/server/notification_center.dart';

void main() {
  // 钉住中文：I18n.t 无 context 时跟随系统 locale，全量跑时会被
  // widget_test 改成 en，导致文案断言随测试顺序变化。
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  binding.platformDispatcher.localeTestValue = const Locale('zh');
  binding.platformDispatcher.localesTestValue = const [Locale('zh')];
  group('② 卡住提醒：到点提醒、不到点不提醒', () {
    final start = DateTime(2026, 10, 4, 6, 0, 0);

    test('运行中、超过阈值 → 提醒', () {
      expect(
        NotificationCenter.shouldNotifyStall(
          running: true,
          lastOutputAt: start,
          stallSeconds: 120,
          alreadyNotified: false,
          now: start.add(const Duration(seconds: 120)),
        ),
        isTrue,
      );
    });

    test('没过阈值 → 不提醒', () {
      expect(
        NotificationCenter.shouldNotifyStall(
          running: true,
          lastOutputAt: start,
          stallSeconds: 120,
          alreadyNotified: false,
          now: start.add(const Duration(seconds: 119)),
        ),
        isFalse,
      );
    });

    test('没在跑 → 不提醒（跑完的提醒走另一条路）', () {
      expect(
        NotificationCenter.shouldNotifyStall(
          running: false,
          lastOutputAt: start,
          stallSeconds: 120,
          alreadyNotified: false,
          now: start.add(const Duration(hours: 1)),
        ),
        isFalse,
      );
    });
  });

  group('③ 同一停顿只提醒一次', () {
    final start = DateTime(2026, 10, 4, 6, 0, 0);

    test('提醒过一次之后，再等多久都不重复提醒', () {
      for (final extra in [0, 60, 600, 3600]) {
        expect(
          NotificationCenter.shouldNotifyStall(
            running: true,
            lastOutputAt: start,
            stallSeconds: 120,
            alreadyNotified: true, // 已经提醒过这一次停顿
            now: start.add(Duration(seconds: 120 + extra)),
          ),
          isFalse,
          reason: 'alreadyNotified=true 时不该再提醒（多等了 $extra 秒）',
        );
      }
    });

    test('出现新输出（重新武装）后，下一次停顿会再提醒', () {
      // 有输出 → 调用方把 lastOutputAt 刷新、alreadyNotified 复位
      final newOutputAt = start.add(const Duration(seconds: 300));
      expect(
        NotificationCenter.shouldNotifyStall(
          running: true,
          lastOutputAt: newOutputAt,
          stallSeconds: 120,
          alreadyNotified: false,
          now: newOutputAt.add(const Duration(seconds: 120)),
        ),
        isTrue,
      );
    });
  });

  group('⑥ 免打扰时段（含跨零点）', () {
    test('23 → 8：23 点、0 点、7 点算免打扰；8 点、12 点不算', () {
      expect(NotificationCenter.inHours(23, 23, 8), isTrue);
      expect(NotificationCenter.inHours(0, 23, 8), isTrue);
      expect(NotificationCenter.inHours(7, 23, 8), isTrue);
      expect(NotificationCenter.inHours(8, 23, 8), isFalse);
      expect(NotificationCenter.inHours(12, 23, 8), isFalse);
    });

    test('不跨零点的时段（22 → 23）只覆盖那一个小时', () {
      expect(NotificationCenter.inHours(22, 22, 23), isTrue);
      expect(NotificationCenter.inHours(23, 22, 23), isFalse);
      expect(NotificationCenter.inHours(21, 22, 23), isFalse);
    });

    test('起止相同 = 不启用', () {
      expect(NotificationCenter.inHours(23, 0, 0), isFalse);
    });

    test('免打扰期间压掉提醒，且给出具体原因', () {
      final reason = NotificationCenter.suppressReason(
        enabled: true,
        inDnd: true,
        watchOnly: false,
        notifyOnDone: true,
        notifyOnError: true,
        notifyOnNeedInput: true,
        kind: NotifyKind.done,
      );
      expect(reason, contains('免打扰时段'));
    });
  });

  group('⑤ 长任务看护模式：只在需要人时提醒', () {
    String? reason(NotifyKind kind, {bool watchOnly = true}) =>
        NotificationCenter.suppressReason(
          enabled: true,
          inDnd: false,
          watchOnly: watchOnly,
          notifyOnDone: true,
          notifyOnError: true,
          notifyOnNeedInput: true,
          kind: kind,
        );

    test('看护模式下：跑完不吵', () {
      expect(reason(NotifyKind.done), contains('看护模式'));
    });

    test('看护模式下：需要确认、出错仍然提醒', () {
      expect(reason(NotifyKind.needInput), isNull);
      expect(reason(NotifyKind.error), isNull);
    });

    test('看护模式下：卡住也提醒（那是异常，不是正常跑完）', () {
      expect(reason(NotifyKind.stalled), isNull);
    });

    test('关掉总开关 → 全都不发', () {
      final r = NotificationCenter.suppressReason(
        enabled: false,
        inDnd: false,
        watchOnly: false,
        notifyOnDone: true,
        notifyOnError: true,
        notifyOnNeedInput: true,
        kind: NotifyKind.error,
      );
      expect(r, contains('总开关'));
    });

    test('细项开关生效：关掉「跑完提醒」只影响跑完', () {
      String? r(NotifyKind kind) => NotificationCenter.suppressReason(
            enabled: true,
            inDnd: false,
            watchOnly: false,
            notifyOnDone: false,
            notifyOnError: true,
            notifyOnNeedInput: true,
            kind: kind,
          );
      expect(r(NotifyKind.done), contains('跑完提醒'));
      expect(r(NotifyKind.error), isNull);
    });
  });

  group('停顿时长文案 humanIdle（不足 1 分钟不许说「0 分钟」）', () {
    test('15 秒 → 说秒', () => expect(NotificationCenter.humanIdle(15), '15 秒'));
    test('59 秒 → 说秒', () => expect(NotificationCenter.humanIdle(59), '59 秒'));
    test('60 秒 → 1 分钟', () => expect(NotificationCenter.humanIdle(60), '1 分钟'));
    test('90 秒 → 1 分 30 秒', () => expect(NotificationCenter.humanIdle(90), '1 分 30 秒'));
    test('600 秒 → 10 分钟', () => expect(NotificationCenter.humanIdle(600), '10 分钟'));
    test('0 秒也不崩', () => expect(NotificationCenter.humanIdle(0), '0 秒'));
  });
}
