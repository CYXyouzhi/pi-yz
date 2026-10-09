// pool 领域的数据模型
//
// 由 server_types.dart 拆分而来（原文件保留为 barrel，
// 所以调用方 import 路径不用改）。

import '../i18n.dart';

// ==================== 多会话总览与磁盘占用（task-15） ====================

/// 池里活着的一条会话：多会话总览要回答「哪个在跑、跑到哪、花了多少」。
class PoolSession {
  const PoolSession({
    required this.id,
    required this.cwd,
    this.title = '',
    this.isStreaming = false,
    this.messageCount = 0,
    this.outputTokens = 0,
    this.cost = 0,
    this.lastAction = '',
    this.runningMs = 0,
    this.idleMs = 0,
  });

  final String id;
  final String cwd;

  /// 首条用户消息摘要（服务端现算）
  final String title;
  final bool isStreaming;
  final int messageCount;
  final int outputTokens;
  final double cost;

  /// 最近一次工具调用名（「跑到哪」）
  final String lastAction;

  /// 这个会话实例活了多久
  final int runningMs;

  /// 距上次活动多久
  final int idleMs;

  bool get running => isStreaming;

  String get workspaceName {
    final parts = cwd
        .replaceAll('\\', '/')
        .split('/')
        .where((s) => s.isNotEmpty);
    return parts.isEmpty ? cwd : parts.last;
  }

  String get displayTitle {
    final t = title.trim();
    return t.isEmpty ? I18n.t('ui.648679c656') : t;
  }

  factory PoolSession.fromJson(Map<String, dynamic> json) => PoolSession(
    id: json['id'] as String? ?? '',
    cwd: json['cwd'] as String? ?? '',
    title: json['title'] as String? ?? '',
    isStreaming: json['isStreaming'] == true,
    messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
    outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
    cost: (json['cost'] as num?)?.toDouble() ?? 0,
    lastAction: json['lastAction'] as String? ?? '',
    runningMs: (json['runningMs'] as num?)?.toInt() ?? 0,
    idleMs: (json['idleMs'] as num?)?.toInt() ?? 0,
  );
}

/// 磁盘上一条会话占了多少

/// 磁盘上一条会话占了多少
class DiskSession {
  const DiskSession({
    required this.id,
    required this.title,
    required this.bytes,
    required this.messages,
    this.modified,
  });

  final String id;
  final String title;
  final int bytes;
  final int messages;
  final String? modified;

  DateTime? get modifiedAt =>
      modified == null ? null : DateTime.tryParse(modified!)?.toLocal();

  factory DiskSession.fromJson(Map<String, dynamic> json) => DiskSession(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    bytes: (json['bytes'] as num?)?.toInt() ?? 0,
    messages: (json['messages'] as num?)?.toInt() ?? 0,
    modified: json['modified'] as String?,
  );
}

class DiskGroup {
  const DiskGroup({
    required this.cwd,
    required this.bytes,
    required this.count,
    required this.sessions,
  });

  final String cwd;
  final int bytes;
  final int count;
  final List<DiskSession> sessions;

  String get workspaceName {
    final parts = cwd
        .replaceAll('\\', '/')
        .split('/')
        .where((s) => s.isNotEmpty);
    return parts.isEmpty ? cwd : parts.last;
  }

  factory DiskGroup.fromJson(Map<String, dynamic> json) => DiskGroup(
    cwd: json['cwd'] as String? ?? '',
    bytes: (json['bytes'] as num?)?.toInt() ?? 0,
    count: (json['count'] as num?)?.toInt() ?? 0,
    sessions:
        (json['sessions'] as List?)
            ?.whereType<Map>()
            .map((e) => DiskSession.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [],
  );
}

class DiskUsage {
  const DiskUsage({
    required this.groups,
    required this.totalBytes,
    required this.totalSessions,
    this.basis = '',
  });

  final List<DiskGroup> groups;
  final int totalBytes;
  final int totalSessions;

  /// 统计口径（服务端给的，直接显示）
  final String basis;

  static const empty = DiskUsage(groups: [], totalBytes: 0, totalSessions: 0);

  factory DiskUsage.fromJson(Map<String, dynamic> json) => DiskUsage(
    groups:
        (json['groups'] as List?)
            ?.whereType<Map>()
            .map((e) => DiskGroup.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [],
    totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
    totalSessions: (json['totalSessions'] as num?)?.toInt() ?? 0,
    basis: json['basis'] as String? ?? '',
  );
}

/// 字节数说人话：1.2 MB / 486 MB / 1.4 GB
String humanBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(2)} GB';
}

/// 远程访问隧道状态（task-18）

/// 远程访问隧道状态（task-18）
class RemoteState {
  const RemoteState({
    this.status = 'idle',
    this.url = '',
    this.error = '',
    this.running = false,
    this.provider = '',
    this.threatModel = const [],
  });

  /// idle | starting | up | error
  final String status;
  final String url;
  final String error;
  final bool running;

  /// cloudflare | localhost.run
  final String provider;

  /// 威胁模型（服务端给的，直接展示给用户）
  final List<String> threatModel;

  static const empty = RemoteState();

  String get providerLabel => switch (provider) {
    'cloudflare' => I18n.t('ui.0b436778d8'),
    'localhost.run' => I18n.t('ui.2c028e4a7b'),
    _ => provider,
  };

  factory RemoteState.fromJson(Map<String, dynamic> json) => RemoteState(
    status: json['status'] as String? ?? 'idle',
    url: json['url'] as String? ?? '',
    error: json['error'] as String? ?? '',
    running: json['running'] == true,
    provider: json['provider'] as String? ?? '',
    threatModel:
        (json['threatModel'] as List?)?.whereType<String>().toList() ??
        const [],
  );
}

/// 时间戳解析：pi 落盘的 timestamp 是 **ISO 字符串**（`2026-10-04T05:03:26.123Z`），
/// 不是毫秒数。早前这里写成 `(json['timestamp'] as num?)?.toInt()`，
/// 于是所有消息的 timestamp 都是 null —— 界面上「本轮耗时」永远算不出来
/// （task-21 实测发现）。两种格式都认，数字当毫秒、字符串按 ISO 解析。
