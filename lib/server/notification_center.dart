// 通知中心：跑完 / 需要确认 / 出错提醒，卡住提醒，免打扰，通知栏快速回复。
//
// 为什么放在 store 边上而不是界面里：这些提醒的意义就是「你没看界面的时候」——
// 挂在聊天页上，切到别的 tab 就不工作了。
//
// 判定口径（全部可复现，不猜）：
//   · 「跑完」= store.chat.isRunning 由 true 变 false，且没有待确认请求、最后一条不是错误
//   · 「需要确认」= store.uiRequests 非空（pi 在等人选）
//   · 「出错」= 最后一条消息 isError
//   · 「卡住」= 运行中且距上次「有新输出」超过阈值（新输出 = 消息条数或最后一条长度变了）
//     同一次停顿只提醒一次，出现新输出后重新武装。

import 'dart:async';
import 'i18n.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'server_store.dart';

enum NotifyKind { done, needInput, error, stalled }

class NotificationCenter with ChangeNotifier {
  NotificationCenter._();

  static final NotificationCenter instance = NotificationCenter._();

  static const _channel = MethodChannel('pi_mobile/native');

  // ==================== 设置（落盘） ====================

  bool enabled = true;
  bool notifyOnDone = true;
  bool notifyOnError = true;
  bool notifyOnNeedInput = true;

  /// 「卡住」判定的阈值（秒）—— 默认 120 秒，界面上能看到并改
  int stallSeconds = 120;

  /// 长任务看护模式：只在需要人（确认 / 出错）时提醒，跑完不吵
  bool watchOnly = false;

  /// 免打扰时段（按小时算，可跨零点，例如 23 → 8）
  bool dndEnabled = false;
  int dndStartHour = 23;
  int dndEndHour = 8;

  /// 通知栏快速回复（不进 App 就能回一句）
  bool quickReply = true;

  bool loaded = false;

  static const _kEnabled = 'notif_enabled';
  static const _kStall = 'notif_stall_seconds';
  static const _kWatch = 'notif_watch_only';
  static const _kDndOn = 'notif_dnd_on';
  static const _kDndStart = 'notif_dnd_start';
  static const _kDndEnd = 'notif_dnd_end';
  static const _kQuickReply = 'notif_quick_reply';

  Future<void> load() async {
    if (loaded) return;
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool(_kEnabled) ?? true;
    stallSeconds = prefs.getInt(_kStall) ?? 120;
    watchOnly = prefs.getBool(_kWatch) ?? false;
    dndEnabled = prefs.getBool(_kDndOn) ?? false;
    dndStartHour = prefs.getInt(_kDndStart) ?? 23;
    dndEndHour = prefs.getInt(_kDndEnd) ?? 8;
    quickReply = prefs.getBool(_kQuickReply) ?? true;
    loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, enabled);
    await prefs.setInt(_kStall, stallSeconds);
    await prefs.setBool(_kWatch, watchOnly);
    await prefs.setBool(_kDndOn, dndEnabled);
    await prefs.setInt(_kDndStart, dndStartHour);
    await prefs.setInt(_kDndEnd, dndEndHour);
    await prefs.setBool(_kQuickReply, quickReply);
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    notifyListeners();
    await _save();
    if (value) await requestPermission();
  }

  Future<void> setStallSeconds(int value) async {
    stallSeconds = value;
    notifyListeners();
    await _save();
  }

  Future<void> setWatchOnly(bool value) async {
    watchOnly = value;
    notifyListeners();
    await _save();
  }

  Future<void> setDnd({bool? on, int? startHour, int? endHour}) async {
    if (on != null) dndEnabled = on;
    if (startHour != null) dndStartHour = startHour;
    if (endHour != null) dndEndHour = endHour;
    notifyListeners();
    await _save();
  }

  Future<void> setQuickReply(bool value) async {
    quickReply = value;
    notifyListeners();
    await _save();
  }

  // ==================== 运行期状态 ====================

  ServerStore? _store;
  Timer? _tick;

  bool _wasRunning = false;
  int _lastMessageCount = 0;

  /// 诊断计数：卡住检查定时器真的在跑吗（timer 被系统掐掉时这两个数会停住）
  int debugTickCount = 0;
  int debugStoreChangedCount = 0;
  int _lastTextLength = 0;
  DateTime _lastOutputAt = DateTime.now();
  bool _stallNotified = false;

  /// 诊断用：被免打扰/看护模式压掉的提醒（设置页与验收记录里能看到，不静默丢）
  final List<String> suppressed = [];

  /// 最近一次通知的内容（自检用，也是「点一下能不能直达」的凭据）
  String? lastNotifiedTitle;

  bool get inDndWindow => dndEnabled && inHours(DateTime.now().hour, dndStartHour, dndEndHour);

  /// 免打扰时段判定（纯函数，可单测）：支持跨零点，例如 23 → 8 表示 23、0…7 点。
  @visibleForTesting
  static bool inHours(int hour, int startHour, int endHour) {
    if (startHour == endHour) return false;
    return startHour < endHour
        ? hour >= startHour && hour < endHour
        : hour >= startHour || hour < endHour;
  }

  /// 「卡住」判定（纯函数，可单测）：运行中 + 距上次输出超过阈值 + 这次停顿还没提醒过。
  /// 单独抽出来是为了能确定性地验证「到点提醒」与「同一停顿只提醒一次」。
  @visibleForTesting
  static bool shouldNotifyStall({
    required bool running,
    required DateTime lastOutputAt,
    required int stallSeconds,
    required bool alreadyNotified,
    required DateTime now,
  }) {
    if (!running || alreadyNotified) return false;
    return now.difference(lastOutputAt).inSeconds >= stallSeconds;
  }

  /// 抑制原因（纯函数，可单测）：返回 null 表示该发。
  @visibleForTesting
  static String? suppressReason({
    required bool enabled,
    required bool inDnd,
    required bool watchOnly,
    required bool notifyOnDone,
    required bool notifyOnError,
    required bool notifyOnNeedInput,
    required NotifyKind kind,
    int dndStartHour = 23,
    int dndEndHour = 8,
  }) {
    if (!enabled) return I18n.t('ui.8f4c857389');
    if (inDnd) return I18n.tp('ui.18d7b3c71a', {'a': dndStartHour, 'b': dndEndHour});
    if (watchOnly && kind == NotifyKind.done) return I18n.t('ui.7c54beebb8');
    switch (kind) {
      case NotifyKind.done:
        if (!notifyOnDone) return I18n.t('ui.094736ccd5');
      case NotifyKind.error:
        if (!notifyOnError) return I18n.t('ui.5492807fab');
      case NotifyKind.needInput:
        if (!notifyOnNeedInput) return I18n.t('ui.1b5996f581');
      case NotifyKind.stalled:
        break;
    }
    return null;
  }

  void attach(ServerStore store) {
    if (identical(_store, store)) return;
    _store?.removeListener(_onStoreChanged);
    _store = store;
    store.addListener(_onStoreChanged);
    _wasRunning = store.chat.isRunning;
    _lastMessageCount = store.chat.messages.length;
    _lastTextLength = _currentTextLength();

    _channel.setMethodCallHandler(_onNativeCall);
    _tick ??= Timer.periodic(const Duration(seconds: 5), (_) => _checkStall());
  }

  /// 解绑：把监听与定时器都收回。
  ///
  /// 为什么必须有：定时器不取消的话会一直挂着 —— 单测里直接报
  /// 「A Timer is still pending even after the widget tree was disposed」，
  /// 真机上则是 App 壳重建一次就多一个定时器（task-11 实测踩到）。
  void detach() {
    _store?.removeListener(_onStoreChanged);
    _store = null;
    _tick?.cancel();
    _tick = null;
    _channel.setMethodCallHandler(null);
  }

  /// 从通知进来时的界面动作（把界面切到会话页）。
  ///
  /// 为什么要这个回调：切哪个 tab 是界面的事，通知中心不该知道。
  /// 而单靠 store 的变更通知不够 —— App 壳里那个「看到会话就跳一次」的标志
  /// 是一次性的（启动时用掉了），App 已在前台时点通知就跳不过去（实测踩到）。
  VoidCallback? onOpenSessionRequested;

  /// 原生侧的回调：通知栏快速回复的内容、通知点击带来的会话 id
  Future<void> _onNativeCall(MethodCall call) async {
    final store = _store;
    if (store == null) return;
    switch (call.method) {
      case 'onQuickReply':
        final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
        final text = (args['text'] as String? ?? '').trim();
        final sessionId = args['sessionId'] as String? ?? '';
        if (text.isEmpty) return;
        debugPrint('[notif] quick reply from notification: $text (session ${sessionId.isEmpty ? 'current' : sessionId})');
        if (sessionId.isNotEmpty && sessionId != store.currentSessionId) {
          await store.openSession(sessionId);
        }
        onOpenSessionRequested?.call();
        await store.sendPrompt(
          text,
          streamingBehavior: store.chat.isRunning ? 'steer' : null,
        );
      case 'onOpenSession':
        final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
        final sessionId = args['sessionId'] as String? ?? '';
        if (sessionId.isNotEmpty) await store.openSession(sessionId);
        onOpenSessionRequested?.call();
    }
  }

  /// 回前台时取一次「通知点进来的会话」—— 冷启动那条路走这里
  Future<void> handleResume() async {
    final store = _store;
    if (store == null) return;
    if (!await hasPermission()) return;
    try {
      final sessionId = await _channel.invokeMethod<String>('consumeLaunchSession');
      if (sessionId != null && sessionId.isNotEmpty) {
        debugPrint('[notif] notification tap → session $sessionId');
        await store.openSession(sessionId);
        onOpenSessionRequested?.call();
      }
    } on PlatformException {
      // 老版本没有这个方法，忽略
    } on MissingPluginException {
      // 非 Android 环境（测试）忽略
    }
  }

  int _currentTextLength() {
    final messages = _store?.chat.messages ?? const [];
    if (messages.isEmpty) return 0;
    return messages.last.text.length + messages.last.thinking.length;
  }

  void _onStoreChanged() {
    debugStoreChangedCount++;
    final store = _store;
    if (store == null) return;
    final running = store.chat.isRunning;
    final count = store.chat.messages.length;
    final textLength = _currentTextLength();

    // 有新输出（新消息或最后一条在变长）→ 刷新「最后输出时间」，并重新武装卡住提醒
    if (running && (count != _lastMessageCount || textLength != _lastTextLength)) {
      _lastOutputAt = DateTime.now();
      _stallNotified = false;
    }
    _lastMessageCount = count;
    _lastTextLength = textLength;

    if (running && !_wasRunning) {
      _lastOutputAt = DateTime.now();
      _stallNotified = false;
    }
    if (!running && _wasRunning) {
      _onRunFinished(store);
    }
    _wasRunning = running;
  }

  void _onRunFinished(ServerStore store) {
    if (store.uiRequests.isNotEmpty) {
      _notify(
        kind: NotifyKind.needInput,
        title: I18n.tp('ui.ade9834361', {'label': _sessionLabel(store)}),
        body: store.uiRequests.first.title ?? I18n.t('ui.1e91c9aeb8'),
        sessionId: store.currentSessionId,
      );
      return;
    }
    final messages = store.chat.messages;
    final last = messages.isEmpty ? null : messages.last;
    if (last != null && last.isError) {
      _notify(
        kind: NotifyKind.error,
        title: I18n.tp('ui.94cbe1dd74', {'label': _sessionLabel(store)}),
        body: _summarize(last.text.isEmpty ? (store.lastError ?? I18n.t('ui.d99d6fe16a')) : last.text),
        sessionId: store.currentSessionId,
      );
      return;
    }
    _notify(
      kind: NotifyKind.done,
      title: I18n.tp('ui.c36902b0dc', {'label': _sessionLabel(store)}),
      body: _summarize(last?.text ?? I18n.t('ui.5a9e6a6a16')),
      sessionId: store.currentSessionId,
    );
  }

  String _sessionLabel(ServerStore store) {
    final name = store.chat.sessionName;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    final cwd = store.chat.cwd;
    if (cwd.isNotEmpty) {
      final parts = cwd.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).toList();
      if (parts.isNotEmpty) return parts.last;
    }
    return 'pi agent';
  }

  /// 一句话摘要：通知栏地方小，去掉换行、截断
  String _summarize(String text) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.isEmpty) return I18n.t('ui.5a9e6a6a16');
    return flat.length <= 80 ? flat : '${flat.substring(0, 80)}…';
  }

  /// 停顿时长的人话（纯函数，可单测）：
  /// 不足 1 分钟时说秒 —— 说「已经 0 分钟没输出」没有信息量（实测踩到过）。
  @visibleForTesting
  static String humanIdle(int seconds) {
    if (seconds < 60) return I18n.tp('ui.c2d9323e9e', {'n': seconds});
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return rest == 0
          ? I18n.tp('ui.47aeb4ecf8', {'n': minutes})
          : I18n.tp('ui.2607898580', {'n': minutes, 'm': rest});
  }

  void _checkStall() {
    debugTickCount++;
    final store = _store;
    if (store == null || !store.chat.isRunning) return;
    if (_stallNotified) return;
    final now = DateTime.now();
    if (!shouldNotifyStall(
      running: store.chat.isRunning,
      lastOutputAt: _lastOutputAt,
      stallSeconds: stallSeconds,
      alreadyNotified: _stallNotified,
      now: now,
    )) {
      return;
    }
    final idleSeconds = now.difference(_lastOutputAt).inSeconds;
    final idleLabel = humanIdle(idleSeconds);
    _stallNotified = true;
    _notify(
      kind: NotifyKind.stalled,
      title: I18n.tp('ui.a75650db91', {'label': _sessionLabel(store)}),
      body: I18n.tp('ui.53e037d7cc',
          {'idle': idleLabel, 'n': stallSeconds}),
      sessionId: store.currentSessionId,
    );
  }

  /// 发通知（受开关、看护模式、免打扰约束）
  Future<void> _notify({
    required NotifyKind kind,
    required String title,
    required String body,
    String? sessionId,
  }) async {
    final reason = _suppressReason(kind);
    if (reason != null) {
      // 不静默丢：记下来，设置页能看到「刚被压掉了 N 条」
      suppressed.insert(0, I18n.tp('ui.43d3089cba', {'title': title, 'reason': reason}));
      while (suppressed.length > 10) {
        suppressed.removeLast();
      }
      notifyListeners();
      debugPrint('[notif] suppressed one: $title（$reason）');
      return;
    }
    lastNotifiedTitle = title;
    notifyListeners();
    try {
      await _channel.invokeMethod<bool>('notify', {
        'id': 1001,
        'title': title,
        'body': body,
        'sessionId': sessionId ?? '',
        'replyable': quickReply,
      });
    } on MissingPluginException {
      // 非 Android（测试）忽略
    } on PlatformException catch (error) {
      debugPrint('[notif] send failed: ${error.message}');
    }
  }

  String? _suppressReason(NotifyKind kind) => suppressReason(
        enabled: enabled,
        inDnd: inDndWindow,
        watchOnly: watchOnly,
        notifyOnDone: notifyOnDone,
        notifyOnError: notifyOnError,
        notifyOnNeedInput: notifyOnNeedInput,
        kind: kind,
        dndStartHour: dndStartHour,
        dndEndHour: dndEndHour,
      );

  /// 测试通知：绕开免打扰与看护模式 —— 用户点「发一条测试通知」
  /// 就是想确认这条路通不通，被时段压掉反而看不出问题。
  Future<bool> sendTest() async {
    try {
      final ok = await _channel.invokeMethod<bool>('notify', {
        'id': 1002,
        'title': I18n.t('ui.05be0025af'),
        'body': I18n.t('ui.062e18cf92'),
        'sessionId': _store?.currentSessionId ?? '',
        'replyable': quickReply,
      });
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 自检快照（设置页显示，也是验收时可读的证据）：
  /// 把「挂上了没 / 当前算不算在跑 / 距上次输出多久 / 这次停顿提醒过没 / 压掉几条」摊开。
  String get selfCheck {
    final store = _store;
    final idle = DateTime.now().difference(_lastOutputAt).inSeconds;
    return 'attached=${store != null}'
        ' · tick=$debugTickCount'
        ' · storeChanged=$debugStoreChangedCount'
        ' · threshold=${stallSeconds}s'
        ' · lastNotified=${lastNotifiedTitle ?? '(never sent)'}'
        ' · running=${store?.chat.isRunning ?? false}'
        ' · wasRunning=$_wasRunning'
        ' · idle for ${idle}s'
        ' · alreadyNotified=$_stallNotified'
        ' · suppressed ${suppressed.length}';
  }

  Future<bool> hasPermission() async {
    try {
      return await _channel.invokeMethod<bool>('permission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod<bool>('requestPermission');
    } on MissingPluginException {
      // 忽略
    } on PlatformException {
      // 忽略
    }
  }

  Future<void> cancelAll() async {
    try {
      await _channel.invokeMethod<bool>('cancel');
    } on MissingPluginException {
      // 忽略
    } on PlatformException {
      // 忽略
    }
  }
}
