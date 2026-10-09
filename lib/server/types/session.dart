// session 领域的数据模型
//
// 由 server_types.dart 拆分而来（原文件保留为 barrel，
// 所以调用方 import 路径不用改）。

import 'dart:convert';

import '../i18n.dart';
import 'messages.dart';

/// 服务端上的一条会话（列表页用）
class ServerSession {
  const ServerSession({
    required this.id,
    required this.cwd,
    required this.preview,
    required this.messageCount,
    this.name,
    this.created,
    this.modified,
    this.parentId,
  });

  final String id;
  final String cwd;
  final String preview;
  final int messageCount;
  final String? name;
  final String? created;
  final String? modified;
  final String? parentId;

  /// 列表里显示的名字：优先会话名，否则用首条消息预览
  String get displayTitle {
    final named = name?.trim();
    if (named != null && named.isNotEmpty) return named;
    final p = preview.trim();
    return p.isEmpty ? I18n.t('ui.87bb8d621e') : p;
  }

  /// 工作区显示名：只取路径最后一段
  String get workspaceName {
    final parts = cwd
        .replaceAll('\\', '/')
        .split('/')
        .where((s) => s.isNotEmpty);
    return parts.isEmpty ? cwd : parts.last;
  }

  DateTime? get modifiedAt =>
      modified == null ? null : DateTime.tryParse(modified!)?.toLocal();

  /// 改名后的本地副本（不等服务端列表刷新）
  ServerSession withName(String? newName) => ServerSession(
    id: id,
    cwd: cwd,
    preview: preview,
    messageCount: messageCount,
    name: newName,
    created: created,
    modified: modified,
    parentId: parentId,
  );

  factory ServerSession.fromJson(Map<String, dynamic> json) => ServerSession(
    id: json['id'] as String,
    cwd: json['cwd'] as String? ?? '',
    preview: json['preview'] as String? ?? '',
    messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
    name: json['name'] as String?,
    created: json['created'] as String?,
    modified: json['modified'] as String?,
    parentId: json['parentId'] as String?,
  );
}

/// 模型信息

/// 模型信息
class ModelInfo {
  const ModelInfo({
    required this.provider,
    required this.id,
    required this.name,
    this.contextWindow,
    this.reasoning = false,
  });

  final String provider;
  final String id;
  final String name;
  final int? contextWindow;
  final bool reasoning;

  String get key => '$provider/$id';

  factory ModelInfo.fromJson(Map<String, dynamic> json) => ModelInfo(
    provider: json['provider'] as String? ?? '',
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? json['id'] as String? ?? '',
    contextWindow: (json['contextWindow'] as num?)?.toInt(),
    reasoning: json['reasoning'] as bool? ?? false,
  );
}

/// token 用量

/// SSE 首帧：会话当前状态
class SessionSnapshot {
  const SessionSnapshot({
    required this.sessionId,
    required this.cwd,
    required this.messages,
    required this.thinkingLevel,
    required this.isStreaming,
    this.model,
    this.sessionName,
    this.autoCompactionEnabled = true,
    this.historyTotal = 0,
    this.historyHasMore = false,
  });

  final String sessionId;
  final String cwd;
  final List<PiMessage> messages;
  final String thinkingLevel;
  final bool isStreaming;
  final ModelInfo? model;
  final String? sessionName;
  final bool autoCompactionEnabled;

  /// 会话共有多少条上下文消息（快照只带了最近的）
  final int historyTotal;

  /// 是否还有更早的消息可以翻页加载
  final bool historyHasMore;

  factory SessionSnapshot.fromJson(Map<String, dynamic> json) {
    final rawModel = json['model'];
    return SessionSnapshot(
      sessionId: json['sessionId'] as String? ?? '',
      cwd: json['cwd'] as String? ?? '',
      messages: PiMessage.listFromJson(json['messages']),
      thinkingLevel: json['thinkingLevel'] as String? ?? 'medium',
      isStreaming: json['isStreaming'] as bool? ?? false,
      model: rawModel is Map
          ? ModelInfo.fromJson(rawModel.cast<String, dynamic>())
          : null,
      sessionName: json['sessionName'] as String?,
      autoCompactionEnabled: json['autoCompactionEnabled'] as bool? ?? true,
      historyTotal: (json['historyTotal'] as num?)?.toInt() ?? 0,
      historyHasMore: json['historyHasMore'] as bool? ?? false,
    );
  }
}

/// 一条 SSE 事件

/// 一条 SSE 事件
class ServerEvent {
  const ServerEvent(this.name, this.data);

  /// message | snapshot | status
  final String name;
  final Map<String, dynamic> data;

  /// 事件类型（data.type），snapshot/status 帧没有
  String? get type => data['type'] as String?;

  @override
  String toString() => 'ServerEvent($name, ${data['type'] ?? data})';
}

/// 命令响应

/// 命令响应
class CommandResponse {
  const CommandResponse({
    required this.command,
    required this.success,
    this.id,
    this.error,
    this.data,
  });

  final String command;
  final bool success;
  final String? id;
  final String? error;
  final Map<String, dynamic>? data;

  /// 内置命令的返回内容（服务端在 data.builtin 里给出）
  Map<String, dynamic>? get builtin {
    final b = data?['builtin'];
    return b is Map ? b.cast<String, dynamic>() : null;
  }

  factory CommandResponse.fromJson(Map<String, dynamic> json) =>
      CommandResponse(
        command: json['command'] as String? ?? '',
        success: json['success'] as bool? ?? false,
        id: json['id'] as String?,
        error: json['error'] as String?,
        data: (json['data'] as Map?)?.cast<String, dynamic>(),
      );

  @override
  String toString() => jsonEncode({
    'command': command,
    'success': success,
    if (error != null) 'error': error,
  });
}

/// 文件条目（目录列表里的一项）
