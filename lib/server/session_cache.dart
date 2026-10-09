// 离线缓存：断网时还能读最近几条会话的正文。
//
// 上限（写死在常量里，设置页会把它们显示出来 —— 缓存必须是有边界的，
// 否则只会越长越大，最后变成「删不掉又不敢删」的东西）：
//   · 最多缓存 5 条会话（按最近打开时间淘汰）
//   · 每条会话最多 150 条消息（从最新的往前留）
//   · 每条会话正文合计最多 200 KB
//   · 单条消息正文最多 8 KB
//   · 图片进不了缓存（base64 太占地方，且离线看图的收益远小于读文字）
//
// 为什么用 SharedPreferences 而不是文件：条数少、总量有上限，
// 读写都是一次性小 JSON；用文件反而要自己处理目录、原子写、清理。

import 'dart:convert';

import 'i18n.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'chat_models.dart';

/// 缓存里的一条消息（精简版：只留离线读得动的部分）
class CachedMessage {
  const CachedMessage({
    required this.role,
    required this.text,
    this.thinking = '',
    this.toolName,
    this.timestamp,
    this.isError = false,
  });

  final String role;
  final String text;
  final String thinking;
  final String? toolName;
  final int? timestamp;
  final bool isError;

  Map<String, dynamic> toJson() => {
    'role': role,
    'text': text,
    if (thinking.isNotEmpty) 'thinking': thinking,
    if (toolName != null) 'tool': toolName,
    if (timestamp != null) 'ts': timestamp,
    if (isError) 'err': true,
  };

  factory CachedMessage.fromJson(Map<String, dynamic> json) => CachedMessage(
    role: json['role'] as String? ?? 'assistant',
    text: json['text'] as String? ?? '',
    thinking: json['thinking'] as String? ?? '',
    toolName: json['tool'] as String?,
    timestamp: (json['ts'] as num?)?.toInt(),
    isError: json['err'] == true,
  );
}

/// 一条会话的离线快照
class CachedSession {
  const CachedSession({
    required this.sessionId,
    required this.name,
    required this.cwd,
    required this.messages,
    required this.savedAt,
    required this.droppedCount,
  });

  final String sessionId;
  final String name;
  final String cwd;
  final List<CachedMessage> messages;
  final DateTime savedAt;

  /// 因为上限被丢掉的老消息条数（界面上要说清楚，不能让人以为消息丢了）
  final int droppedCount;
}

/// 设置页要展示的一条缓存记录
class CacheEntry {
  const CacheEntry({
    required this.sessionId,
    required this.name,
    required this.cwd,
    required this.lastText,
    required this.savedAt,
    required this.messageCount,
    required this.bytes,
    required this.droppedCount,
  });

  final String sessionId;
  final String name;

  /// 工作目录与最后一条正文：离线时列表要显示得跟在线一样
  final String cwd;
  final String lastText;

  final DateTime savedAt;
  final int messageCount;
  final int bytes;
  final int droppedCount;

  String get sizeLabel => bytes < 1024
      ? '$bytes B'
      : bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
}

class SessionCache {
  SessionCache._();

  /// 最多缓存几条会话（合同①要求「明确缓存上限」，这几个数字就是上限）
  static const int maxSessions = 5;
  static const int maxMessages = 150;
  static const int maxCharsPerSession = 200 * 1024;
  static const int maxCharsPerMessage = 8 * 1024;

  static const String _indexKey = 'pi_offline_index_v1';

  static String _key(String sessionId) => 'pi_offline_session_$sessionId';

  /// 存一条会话。**不抛异常**：缓存失败不该影响已经拿到的数据。
  static Future<void> save({
    required String sessionId,
    required String name,
    required String cwd,
    required List<ChatMessage> messages,
    DateTime? now,
  }) async {
    if (sessionId.isEmpty) return;
    try {
      final at = now ?? DateTime.now();
      final picked = <CachedMessage>[];
      var chars = 0;
      var dropped = 0;

      // 从最新往前取：离线最需要看的是「最后发生了什么」
      for (var i = messages.length - 1; i >= 0; i -= 1) {
        if (picked.length >= maxMessages) {
          dropped = i + 1;
          break;
        }
        final message = messages[i];
        final text = _clip(message.text, maxCharsPerMessage);
        final thinking = _clip(message.thinking, maxCharsPerMessage ~/ 2);
        if (text.isEmpty && thinking.isEmpty && message.toolCalls.isEmpty) {
          continue;
        }
        if (chars + text.length + thinking.length > maxCharsPerSession) {
          dropped = i + 1;
          break;
        }
        chars += text.length + thinking.length;
        picked.add(
          CachedMessage(
            role: message.role,
            text: text,
            thinking: thinking,
            toolName:
                message.toolName ??
                (message.toolCalls.isEmpty
                    ? null
                    : message.toolCalls.first.name),
            timestamp: message.timestamp,
            isError: message.isError,
          ),
        );
      }

      // 上面是从最新往前收集的，存之前倒回来，保持时间顺序
      final ordered = picked.reversed.toList();
      final payload = jsonEncode({
        'id': sessionId,
        'name': name,
        'cwd': cwd,
        'at': at.toIso8601String(),
        'dropped': dropped,
        'msgs': ordered.map((m) => m.toJson()).toList(),
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(sessionId), payload);

      // 索引维持 LRU：最近存的排前面，超出的直接删掉
      final index = prefs.getStringList(_indexKey) ?? <String>[];
      index.remove(sessionId);
      index.insert(0, sessionId);
      while (index.length > maxSessions) {
        final evicted = index.removeLast();
        await prefs.remove(_key(evicted));
      }
      await prefs.setStringList(_indexKey, index);
    } catch (_) {
      // 缓存是「有更好、没有也能用」的东西，失败就静默放过
    }
  }

  static Future<CachedSession?> load(String sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(sessionId));
      if (raw == null || raw.isEmpty) return null;
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final messages = (json['msgs'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => CachedMessage.fromJson(item.cast<String, dynamic>()))
          .toList();
      if (messages.isEmpty) return null;
      return CachedSession(
        sessionId: json['id'] as String? ?? sessionId,
        name: json['name'] as String? ?? '',
        cwd: json['cwd'] as String? ?? '',
        messages: messages,
        savedAt:
            DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
        droppedCount: (json['dropped'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// 设置页用：列出全部缓存（含占用大小）
  static Future<List<CacheEntry>> entries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getStringList(_indexKey) ?? <String>[];
      final out = <CacheEntry>[];
      for (final id in index) {
        final raw = prefs.getString(_key(id));
        if (raw == null || raw.isEmpty) continue;
        final json = jsonDecode(raw);
        if (json is! Map) continue;
        final messages = (json['msgs'] as List? ?? const []);
        // 先 is Map 判断再读，不要直接 as Map：末尾元素可能是任何类型
        // （缓存写坏、或旧版本格式不同），而断言失败会抛 TypeError，
        // 那会打断整个会话列表的恢复。同文件 227 行对 json 也是这么做的。
        final lastRaw = messages.isEmpty ? null : messages.last;
        final last = lastRaw is Map
            ? CachedMessage.fromJson(lastRaw.cast<String, dynamic>())
            : null;
        out.add(
          CacheEntry(
            sessionId: id,
            name: json['name'] as String? ?? '',
            cwd: json['cwd'] as String? ?? '',
            lastText: last?.text ?? '',
            savedAt:
                DateTime.tryParse(json['at'] as String? ?? '') ??
                DateTime.now(),
            messageCount: messages.length,
            // 用 UTF-8 字节数而不是字符串长度：中文一个字 3 字节，长度会低估
            bytes: utf8.encode(raw).length,
            droppedCount: (json['dropped'] as num?)?.toInt() ?? 0,
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static Future<int> totalBytes() async {
    final all = await entries();
    return all.fold<int>(0, (sum, item) => sum + item.bytes);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getStringList(_indexKey) ?? <String>[];
    for (final id in index) {
      await prefs.remove(_key(id));
    }
    await prefs.remove(_indexKey);
  }

  static Future<void> removeOne(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(sessionId));
    final index = prefs.getStringList(_indexKey) ?? <String>[];
    index.remove(sessionId);
    await prefs.setStringList(_indexKey, index);
  }

  static String _clip(String text, int max) => text.length <= max
      ? text
      : '${text.substring(0, max)}…${I18n.t('ui.offcut')}';
}
