import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

/// 日志级别。
enum LogLevel { debug, info, warn, error }

/// 单条日志记录。
class LogEntry {
  LogEntry(this.level, this.tag, this.message) : time = DateTime.now();

  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;

  /// 形如 `[16:05:31.482] INFO  ssh: connected`
  String get formatted {
    String p2(int v) => v.toString().padLeft(2, '0');
    final t = '${p2(time.hour)}:${p2(time.minute)}:${p2(time.second)}'
        '.${time.millisecond.toString().padLeft(3, '0')}';
    return '[$t] ${level.name.toUpperCase().padRight(5)} $tag: $message';
  }
}

/// 全局调试日志。
///
/// 设计要点：
/// - **环形缓冲**：只保留最近 [maxEntries] 条，长时间运行不会吃内存。
/// - **广播流**：调试面板可随时订阅，不影响其他订阅者。
/// - **字节统计**：记录收发量，用于判断链路是否卡死（只统计、不存储内容）。
///
/// 这是「开发者模式」的第一层：任何 SSH 生命周期事件都往这里写，
/// 出问题时打开面板即可看到全过程，不需要连调试器。
class DebugLog {
  DebugLog._();
  static final DebugLog instance = DebugLog._();

  /// 保留的最大日志条数。
  static const int maxEntries = 500;

  final Queue<LogEntry> _entries = Queue<LogEntry>();
  final StreamController<List<LogEntry>> _controller =
      StreamController<List<LogEntry>>.broadcast();

  // ---- 收发统计（调试面板展示）----
  int rxBytes = 0;
  int txBytes = 0;
  int rxChunks = 0;
  int txChunks = 0;

  // ---- 日志开关（调试面板可切换）----

  /// dartssh2 协议层细节（`_sendWindowAdjustIfNeeded` 之类）。
  /// 输出量极大，默认关闭，否则会把关键事件从 500 条缓冲里挤出去。
  bool verboseSsh = false;

  /// 输入字节日志。排查 IME 多空格、按键编码问题时打开，
  /// 能看到每个字符实际发出的十六进制。
  bool verboseInput = true;

  Stream<List<LogEntry>> get stream => _controller.stream;

  List<LogEntry> get entries => _entries.toList(growable: false);

  void log(LogLevel level, String tag, String message) {
    _entries.addLast(LogEntry(level, tag, message));
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
    if (!_controller.isClosed) {
      _controller.add(entries);
    }
    // 同时打到控制台：这样插着 USB 时用 `adb logcat` 就能抓取，
    // 不必让用户手动复制 App 内的日志面板。
    debugPrint('[${level.name.toUpperCase()}] $tag: $message');
  }

  void debug(String tag, String message) => log(LogLevel.debug, tag, message);
  void info(String tag, String message) => log(LogLevel.info, tag, message);
  void warn(String tag, String message) => log(LogLevel.warn, tag, message);
  void error(String tag, String message) => log(LogLevel.error, tag, message);

  /// 记录下行（pi → App）字节。
  void countRx(int bytes) {
    rxBytes += bytes;
    rxChunks++;
  }

  /// 记录上行（App → pi）字节。
  void countTx(int bytes) {
    txBytes += bytes;
    txChunks++;
  }

  /// 人类可读的统计摘要。
  String get statsSummary {
    String human(int b) {
      if (b < 1024) return '$b B';
      if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
      return '${(b / 1024 / 1024).toStringAsFixed(2)} MB';
    }

    return 'RX ${human(rxBytes)} / $rxChunks chunks    '
        'TX ${human(txBytes)} / $txChunks chunks';
  }

  void clear() {
    _entries.clear();
    rxBytes = txBytes = rxChunks = txChunks = 0;
    if (!_controller.isClosed) {
      _controller.add(const <LogEntry>[]);
    }
  }

  /// 导出全部日志文本（便于复制粘贴反馈问题）。
  String dump() => entries.map((e) => e.formatted).join('\n');
}
