// messages 领域的数据模型
//
// 由 server_types.dart 拆分而来（原文件保留为 barrel，
// 所以调用方 import 路径不用改）。

int? parseTimestamp(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toInt();
  final text = raw.toString();
  final asInt = int.tryParse(text);
  if (asInt != null) return asInt;
  return DateTime.tryParse(text)?.millisecondsSinceEpoch;
}

class PiText extends PiContent {
  const PiText(this.text);
  final String text;
}

class PiThinking extends PiContent {
  const PiThinking(this.thinking, {this.redacted = false});
  final String thinking;
  final bool redacted;
}

class PiToolCall extends PiContent {
  const PiToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  factory PiToolCall.fromMap(Map<String, dynamic> json) => PiToolCall(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    arguments: (json['arguments'] as Map?)?.cast<String, dynamic>() ?? const {},
  );

  /// 工具参数的简短摘要，用于工具卡片副标题
  String get summary {
    for (final key in const [
      'command',
      'path',
      'pattern',
      'query',
      'url',
      'prompt',
    ]) {
      final value = arguments[key];
      if (value is String && value.isNotEmpty) return value;
    }
    if (arguments.isEmpty) return '';
    final first = arguments.entries.first;
    return '${first.key}: ${first.value}';
  }
}

class PiImage extends PiContent {
  const PiImage({required this.data, required this.mimeType});
  final String data;
  final String mimeType;
}

/// 一条消息。role: user | assistant | toolResult | system | custom | ...

/// token 用量
class PiUsage {
  const PiUsage({
    this.input = 0,
    this.output = 0,
    this.cacheRead = 0,
    this.cacheWrite = 0,
    this.reasoning = 0,
    this.totalTokens = 0,
    this.costTotal = 0,
  });

  final int input;
  final int output;
  final int cacheRead;
  final int cacheWrite;
  final int reasoning;
  final int totalTokens;
  final double costTotal;

  factory PiUsage.fromJson(Map<String, dynamic> json) {
    final cost = json['cost'];
    return PiUsage(
      input: (json['input'] as num?)?.toInt() ?? 0,
      output: (json['output'] as num?)?.toInt() ?? 0,
      cacheRead: (json['cacheRead'] as num?)?.toInt() ?? 0,
      cacheWrite: (json['cacheWrite'] as num?)?.toInt() ?? 0,
      reasoning: (json['reasoning'] as num?)?.toInt() ?? 0,
      totalTokens: (json['totalTokens'] as num?)?.toInt() ?? 0,
      costTotal: cost is Map ? ((cost['total'] as num?)?.toDouble() ?? 0) : 0,
    );
  }
}

/// 消息内容块
sealed class PiContent {
  const PiContent();

  static PiContent? fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'text':
        return PiText(json['text'] as String? ?? '');
      case 'thinking':
        return PiThinking(
          json['thinking'] as String? ?? '',
          redacted: json['redacted'] as bool? ?? false,
        );
      case 'toolCall':
        return PiToolCall(
          id: json['id'] as String? ?? '',
          name: json['name'] as String? ?? '',
          arguments:
              (json['arguments'] as Map?)?.cast<String, dynamic>() ?? const {},
        );
      case 'image':
        return PiImage(
          data: json['data'] as String? ?? '',
          mimeType: json['mimeType'] as String? ?? 'image/png',
        );
      default:
        return null;
    }
  }
}

/// 一条消息。role: user | assistant | toolResult | system | custom | ...
class PiMessage {
  const PiMessage({
    required this.role,
    required this.content,
    this.toolName,
    this.toolCallId,
    this.isError = false,
    this.timestamp,
    this.usage,
    this.raw = const {},
  });

  final String role;
  final List<PiContent> content;
  final String? toolName;
  final String? toolCallId;
  final bool isError;
  final int? timestamp;
  final PiUsage? usage;
  final Map<String, dynamic> raw;

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
  bool get isToolResult => role == 'toolResult';

  /// 纯文本部分（不含思考与工具调用）
  String get text => content.whereType<PiText>().map((c) => c.text).join();

  /// 思考部分
  String get thinking =>
      content.whereType<PiThinking>().map((c) => c.thinking).join();

  List<PiToolCall> get toolCalls => content.whereType<PiToolCall>().toList();

  /// 唯一标识：服务端不保证每条消息有 id，用角色 + 时间戳 + 内容长度兜底
  String get dedupeKey {
    final id = raw['id'];
    if (id is String && id.isNotEmpty) return id;
    return '$role|${timestamp ?? 0}|${text.length}|${content.length}';
  }

  factory PiMessage.fromJson(Map<String, dynamic> json) {
    final rawContent = json['content'];
    final blocks = <PiContent>[];

    if (rawContent is String) {
      // user 消息的 content 可以是纯字符串
      if (rawContent.isNotEmpty) blocks.add(PiText(rawContent));
    } else if (rawContent is List) {
      for (final item in rawContent) {
        if (item is Map) {
          final parsed = PiContent.fromJson(item.cast<String, dynamic>());
          if (parsed != null) blocks.add(parsed);
        } else if (item is String) {
          blocks.add(PiText(item));
        }
      }
    }

    // 摘要类消息（分支摘要 branchSummary / 自动压缩 compactionSummary）：
    // pi 把正文放在 summary 字段而不是 content —— 不读它界面上就是个空气泡。
    final role = json['role'] as String? ?? 'unknown';
    if (blocks.isEmpty &&
        (role == 'branchSummary' || role == 'compactionSummary')) {
      final summary = json['summary'];
      if (summary is String && summary.isNotEmpty) blocks.add(PiText(summary));
    }

    final rawUsage = json['usage'];
    return PiMessage(
      role: role,
      content: blocks,
      toolName: json['toolName'] as String?,
      toolCallId: json['toolCallId'] as String?,
      isError: json['isError'] as bool? ?? false,
      timestamp: parseTimestamp(json['timestamp']),
      usage: rawUsage is Map
          ? PiUsage.fromJson(rawUsage.cast<String, dynamic>())
          : null,
      raw: json,
    );
  }

  static List<PiMessage> listFromJson(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => PiMessage.fromJson(item.cast<String, dynamic>()))
        .toList();
  }
}

/// SSE 首帧：会话当前状态
