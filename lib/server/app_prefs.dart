// App 自身的偏好设置（跟「pi 的配置」分开）。
//
// 为什么不塞进 ServerStore：那些是「这台电脑上的 pi 怎么配」，
// 这些是「我这台手机怎么显示、怎么输入」—— 换机器也该跟着手机走。
//
// 用 shared_preferences 存，改完立刻 notify，界面即时生效。

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPrefs extends ChangeNotifier {
  AppPrefs._();
  static final AppPrefs instance = AppPrefs._();

  static const _kFontScale = 'app_font_scale';
  static const _kLineHeight = 'app_line_height';
  static const _kSendWithEnter = 'app_send_with_enter';
  static const _kThemeMode = 'app_theme_mode';
  static const _kDefaultCwd = 'app_default_cwd';
  static const _kLastSession = 'app_last_session';
  static const _kLang = 'app_lang';
  static const _kArchived = 'app_archived_sessions';
  static const _kKeepAlive = 'app_keep_alive';

  double _fontScale = 1.0;
  double _lineHeight = 1.45;
  bool _sendWithEnter = false;
  ThemeMode _themeMode = ThemeMode.system;
  String _defaultCwd = '';
  String _lastSessionId = '';

  /// 'zh' | 'en' | 'system'
  String _lang = 'system';

  /// 已归档的会话 id（默认列表里不显示，但会话本身还在磁盘上）。
  /// 存本地：归档是「这台手机不想看到」的偏好，不是服务端的事实。
  Set<String> _archived = <String>{};

  /// 后台保活开关（默认开）：连上服务端就起常驻服务，退到后台不断线。
  /// 默认开是因为它解决的正是用户点名的问题（睡着了的那几个小时）；
  /// 代价是通知栏常驻一条 + 略费电，所以给一个明确的关掉入口。
  bool _keepAlive = true;

  bool _loaded = false;

  /// 只给测试用：把「已经读过」的标志打回原样，下次 [load] 会重新读存储。
  ///
  /// 为什么需要它：AppPrefs 是**内存单例**，而 `load()` 是幂等的（读一次就置
  /// `_loaded`）。`SharedPreferences.setMockInitialValues` 只重置存储、动不了这个
  /// 单例 —— 于是用例之间会串状态。实测到的那次：上个用例存下的 `lastSessionId`
  /// 会被 `ServerStore.connect()` 拿去做「恢复上次会话」，导致下个用例里
  /// 「还没有会话」这种前提根本造不出来（断言看到的是上一条用例的会话）。
  @visibleForTesting
  void debugForgetLoaded() => _loaded = false;

  double get fontScale => _fontScale;
  double get lineHeight => _lineHeight;
  bool get sendWithEnter => _sendWithEnter;
  ThemeMode get themeMode => _themeMode;
  String get defaultCwd => _defaultCwd;

  /// 上次打开的会话 id：进程被系统杀掉后重开也能回到那条会话
  String get lastSessionId => _lastSessionId;
  String get lang => _lang;
  Set<String> get archivedSessionIds => Set.unmodifiable(_archived);
  bool get loaded => _loaded;

  bool isArchived(String sessionId) => _archived.contains(sessionId);

  bool get keepAlive => _keepAlive;

  Future<void> load() async {
    // 幂等：connect() 也会调它，别把盘上的旧值盖掉内存里的新值
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _fontScale = prefs.getDouble(_kFontScale) ?? 1.0;
    _lineHeight = prefs.getDouble(_kLineHeight) ?? 1.45;
    _sendWithEnter = prefs.getBool(_kSendWithEnter) ?? false;
    _defaultCwd = prefs.getString(_kDefaultCwd) ?? '';
    _lastSessionId = prefs.getString(_kLastSession) ?? '';
    _lang = prefs.getString(_kLang) ?? 'system';
    _archived = (prefs.getStringList(_kArchived) ?? const []).toSet();
    _keepAlive = prefs.getBool(_kKeepAlive) ?? true;
    _themeMode = switch (prefs.getString(_kThemeMode)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    _loaded = true;
    notifyListeners();
  }

  Future<void> setFontScale(double value) async {
    _fontScale = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kFontScale, value);
  }

  Future<void> setLineHeight(double value) async {
    _lineHeight = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kLineHeight, value);
  }

  Future<void> setSendWithEnter(bool value) async {
    _sendWithEnter = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSendWithEnter, value);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }

  Future<void> setLang(String value) async {
    _lang = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLang, value);
  }

  Future<void> setLastSession(String sessionId) async {
    if (sessionId.isEmpty || _lastSessionId == sessionId) return;
    _lastSessionId = sessionId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastSession, sessionId);
  }

  Future<void> setDefaultCwd(String cwd) async {
    _defaultCwd = cwd;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDefaultCwd, cwd);
  }

  Future<void> setKeepAlive(bool value) async {
    if (_keepAlive == value) return;
    _keepAlive = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKeepAlive, value);
  }

  /// 归档一条会话（默认列表里不再出现）
  Future<void> archiveSession(String sessionId) async {
    if (sessionId.isEmpty || _archived.contains(sessionId)) return;
    _archived.add(sessionId);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kArchived, _archived.toList());
  }

  /// 取消归档
  Future<void> unarchiveSession(String sessionId) async {
    if (!_archived.remove(sessionId)) return;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kArchived, _archived.toList());
  }

  /// 清空归档标记（会话删掉时顺手调，免得键一直留着旧的 id）
  Future<void> forgetArchived(Iterable<String> ids) async {
    var changed = false;
    for (final id in ids) {
      if (_archived.remove(id)) changed = true;
    }
    if (!changed) return;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kArchived, _archived.toList());
  }

  /// 清掉 App 本地的「内容型」数据：常用语、离线缓存。
  /// 草稿在 ServerStore 里，由设置页一并清（两边都算一项）。
  /// 返回清掉了几项，界面拿它做回执。
  Future<int> clearLocalData() async {
    var cleared = 0;
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getString('chat_templates_v1') ?? '').isNotEmpty) {
      await prefs.remove('chat_templates_v1');
      cleared += 1;
    }
    if ((prefs.getString('offline_sessions_v1') ?? '').isNotEmpty) {
      await prefs.remove('offline_sessions_v1');
      cleared += 1;
    }
    if (_archived.isNotEmpty) {
      _archived = <String>{};
      await prefs.remove(_kArchived);
      cleared += 1;
    }
    notifyListeners();
    return cleared;
  }
}
