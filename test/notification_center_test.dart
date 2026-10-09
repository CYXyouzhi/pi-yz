// 通知判定的确定性验证（task-11 的 ②③⑤⑥）。
//
// 为什么在这一层钉：实机上要造出「运行中且 15 秒没有任何输出」很难 ——
// 真跑一个长命令时工具输出会一直流，反而不算卡住（这是对的）；
// 而把服务端杀掉又会被判成「跑完了」。所以用纯函数把判定逻辑测干净，
// 实机部分只负责证明「通知这条路通」与「设置项真的在界面上」。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/server/notification_center.dart';
import 'package:pi_yz/server/server_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    test(
      '90 秒 → 1 分 30 秒',
      () => expect(NotificationCenter.humanIdle(90), '1 分 30 秒'),
    );
    test(
      '600 秒 → 10 分钟',
      () => expect(NotificationCenter.humanIdle(600), '10 分钟'),
    );
    test('0 秒也不崩', () => expect(NotificationCenter.humanIdle(0), '0 秒'));
  });

  // 设置项必须「改了存住」：用户下次进来看到的还是自己上次选的那样。
  //
  // 这是**单例 + SharedPreferences**，所以每个用例都得把内存字段与 `loaded`
  // 标志一起重置 —— 否则上个用例的改动会串到下个用例（串了会得到假绿）。
  group('⑨ 设置持久化：改了必须存住（重进 App 还在）', () {
    final center = NotificationCenter.instance;

    setUp(() {
      center.enabled = true;
      center.stallSeconds = 120;
      center.watchOnly = false;
      center.dndEnabled = false;
      center.dndStartHour = 23;
      center.dndEndHour = 8;
      center.quickReply = true;
      center.loaded = false;
    });

    test('全新安装（prefs 空）：默认开通知、阈值 120 秒、带快速回复', () async {
      SharedPreferences.setMockInitialValues({});
      await center.load();

      expect(center.enabled, isTrue);
      expect(center.stallSeconds, 120);
      expect(center.watchOnly, isFalse);
      expect(center.dndEnabled, isFalse);
      expect(center.dndStartHour, 23);
      expect(center.dndEndHour, 8);
      expect(center.quickReply, isTrue);
      expect(center.loaded, isTrue);
    });

    test('load：存过的值覆盖默认值（7 个字段全都要读回）', () async {
      SharedPreferences.setMockInitialValues({
        'notif_enabled': false,
        'notif_stall_seconds': 300,
        'notif_watch_only': true,
        'notif_dnd_on': true,
        'notif_dnd_start': 22,
        'notif_dnd_end': 7,
        'notif_quick_reply': false,
      });
      await center.load();

      expect(center.enabled, isFalse);
      expect(center.stallSeconds, 300);
      expect(center.watchOnly, isTrue);
      expect(center.dndEnabled, isTrue);
      expect(center.dndStartHour, 22);
      expect(center.dndEndHour, 7);
      expect(center.quickReply, isFalse);
    });

    test('setter 真的写进 prefs —— 只改内存的话重启就丢', () async {
      SharedPreferences.setMockInitialValues({});
      await center.load();

      await center.setStallSeconds(45);
      await center.setWatchOnly(true);
      await center.setQuickReply(false);
      await center.setDnd(on: true, startHour: 21, endHour: 6);
      await center.setEnabled(false);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('notif_stall_seconds'), 45);
      expect(prefs.getBool('notif_watch_only'), isTrue);
      expect(prefs.getBool('notif_quick_reply'), isFalse);
      expect(prefs.getBool('notif_dnd_on'), isTrue);
      expect(prefs.getInt('notif_dnd_start'), 21);
      expect(prefs.getInt('notif_dnd_end'), 6);
      expect(prefs.getBool('notif_enabled'), isFalse);
    });

    test('setDnd 是部分更新：只传 startHour 时其余字段不动', () async {
      SharedPreferences.setMockInitialValues({});
      await center.load();

      await center.setDnd(startHour: 21);

      expect(center.dndStartHour, 21);
      expect(center.dndEndHour, 8, reason: '没传的字段不能被顺手改成别的值');
      expect(center.dndEnabled, isFalse);
    });

    test('load 幂等：第二次调用不会把用户刚改的值拉回旧值', () async {
      SharedPreferences.setMockInitialValues({});
      await center.load();
      await center.setStallSeconds(45);

      await center.load(); // loaded == true，应当直接返回

      expect(center.stallSeconds, 45);
    });

    test('setter 会通知监听者（界面得跟着变）', () async {
      SharedPreferences.setMockInitialValues({});
      await center.load();

      var notified = 0;
      void listener() => notified += 1;
      center.addListener(listener);
      await center.setStallSeconds(45);
      center.removeListener(listener);

      expect(notified, greaterThan(0));
    });
  });

  // 「接线」部分：attach / detach / 原生通道。
  //
  // 判定逻辑（该不该提醒、文案）在上面的 group 里是纯函数，已经测干净了；
  // 这里管「有没有真的把定时器和监听接上去、又有没有真的收回」——
  // 定时器没收掉是踩过的坑：单测报 pending timer，真机上壳重建一次多一个。
  group('⑩ 接线：attach / detach / 原生通道', () {
    final center = NotificationCenter.instance;
    const channel = MethodChannel('pi_yz/native');
    late List<MethodCall> native;

    /// 用例可改的返回值
    bool permitted = true;
    String? launchSessionId;

    setUp(() {
      native = <MethodCall>[];
      permitted = true;
      launchSessionId = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            native.add(call);
            return switch (call.method) {
              'permission' => permitted,
              'consumeLaunchSession' => launchSessionId,
              _ => null,
            };
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      center.detach(); // 保证定时器被收掉，否则 flutter_test 会报 pending timer
      center.onOpenSessionRequested = null;
    });

    test('attach 会起「每 5 秒查一次卡住」的定时器；detach 必须把它收掉', () async {
      final store = ServerStore();
      center.attach(store);

      final before = center.debugTickCount;
      await Future<void>.delayed(const Duration(milliseconds: 5600));
      expect(
        center.debugTickCount,
        greaterThan(before),
        reason: 'attach 之后定时器应当每 5 秒跑一次',
      );

      center.detach();
      final afterDetach = center.debugTickCount;
      await Future<void>.delayed(const Duration(milliseconds: 5600));
      expect(
        center.debugTickCount,
        afterDetach,
        reason: 'detach 没取消定时器的话会一直挂着 —— 真机上壳重建一次就多一个',
      );

      store.dispose();
    });

    test('handleResume：没有通知权限时什么都不做（不去问原生要会话）', () async {
      final store = ServerStore();
      center.attach(store);
      permitted = false;

      await center.handleResume();

      expect(
        native.map((c) => c.method),
        isNot(contains('consumeLaunchSession')),
        reason: '没权限就别去问原生要会话 id',
      );
      store.dispose();
    });

    test('handleResume：原生给了会话 id → 打开它并请求界面跳过去', () async {
      final store = ServerStore();
      var opened = 0;
      center.attach(store);
      center.onOpenSessionRequested = () => opened += 1;
      launchSessionId = 's-99';

      await center.handleResume();

      expect(native.map((c) => c.method), contains('consumeLaunchSession'));
      expect(opened, 1, reason: '不请求跳转的话，用户点了通知还停在原页面');
      store.dispose();
    });

    test('handleResume：原生没给出会话 id 时不动界面', () async {
      final store = ServerStore();
      var opened = 0;
      center.attach(store);
      center.onOpenSessionRequested = () => opened += 1;
      launchSessionId = null;

      await center.handleResume();

      expect(opened, 0);
      store.dispose();
    });

    test('handleResume：原生调用抛异常时不崩（老版本没这个接口）', () async {
      final store = ServerStore();
      center.attach(store);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'permission') return true;
            throw PlatformException(code: 'unavailable');
          });

      await expectLater(center.handleResume(), completes);
      store.dispose();
    });
  });
}
