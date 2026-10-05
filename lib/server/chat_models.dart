// 手机端的聊天数据模型。
//
// 与 pi 的原始消息不同：这里是为渲染准备的累积状态。
// 流式过程中文本/思考是逐步累积的，所以字段可变，由 store 负责通知刷新。

import 'server_types.dart';
import 'i18n.dart';

/// 工具运行状态
enum ToolStatus { running, done, error }

/// 一次工具执行。由 tool_execution_* 事件驱动，
/// 与 assistant 消息里的 toolCall 通过 toolCallId 对应。
class ToolRun {
  ToolRun({required this.id, required this.name, this.args = const {}});

  final String id;
  final String name;
  Map<String, dynamic> args;
  ToolStatus status = ToolStatus.running;

  /// 部分输出（bash 滚动输出等）。截断保存，避免一次 24MB 的命令撑爆内存。
  String output = '';

  static const int _maxOutputChars = 4000;

  void appendOutput(String chunk) {
    if (chunk.isEmpty) return;
    output += chunk;
    if (output.length > _maxOutputChars) {
      output = '${I18n.t('ui.trunc1')}\n${output.substring(output.length - _maxOutputChars)}';
    }
  }

  void replaceOutput(String text) {
    output = text.length > _maxOutputChars
        ? '${I18n.t('ui.trunc1')}\n${text.substring(text.length - _maxOutputChars)}'
        : text;
  }
}

/// 一条可渲染的消息
class ChatMessage {
  ChatMessage({
    required this.key,
    required this.role,
    this.text = '',
    this.thinking = '',
    this.toolName,
    this.toolCallId,
    this.isError = false,
    this.streaming = false,
    this.timestamp,
    this.usage,
    List<PiToolCall>? toolCalls,
    List<PiContent>? blocks,
  })  : toolCalls = toolCalls ?? [],
        blocks = blocks ?? [];

  /// 稳定标识，用于列表 key 与去重
  final String key;

  /// user | assistant | toolResult | system | custom | compactionSummary ...
  final String role;

  String text;
  String thinking;

  /// 原始内容块（含图片等，渲染时需要）
  List<PiContent> blocks;

  List<PiToolCall> toolCalls;

  /// toolResult 消息的工具名
  String? toolName;
  String? toolCallId;

  bool isError;

  /// 是否正在流式生成（显示光标/动画）
  bool streaming;

  int? timestamp;
  PiUsage? usage;

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
  bool get isToolResult => role == 'toolResult';

  bool get isEmpty => text.isEmpty && thinking.isEmpty && toolCalls.isEmpty && blocks.isEmpty;

  /// 从 pi 的权威消息构造
  factory ChatMessage.fromPiMessage(PiMessage message, {required String key}) {
    return ChatMessage(
      key: key,
      role: message.role,
      text: message.text,
      thinking: message.thinking,
      toolName: message.toolName,
      toolCallId: message.toolCallId,
      isError: message.isError,
      timestamp: message.timestamp,
      usage: message.usage,
      toolCalls: message.toolCalls,
      blocks: message.content,
    );
  }

  /// 用权威内容覆盖（message_end 时调用）
  void absorb(PiMessage message) {
    text = message.text;
    thinking = message.thinking;
    toolCalls = message.toolCalls;
    blocks = message.content;
    isError = message.isError;
    usage = message.usage ?? usage;
    timestamp = message.timestamp ?? timestamp;
    streaming = false;
  }
}

/// 扩展对话框请求（ctx.ui.*）
class UiRequest {
  const UiRequest({
    required this.id,
    required this.method,
    this.title,
    this.message,
    this.options = const [],
    this.placeholder,
    this.prefill,
    this.notifyType,
  });

  final String id;

  /// select | confirm | input | editor | notify | setStatus | setWidget | setTitle | set_editor_text
  final String method;
  final String? title;
  final String? message;
  final List<String> options;
  final String? placeholder;
  final String? prefill;
  final String? notifyType;

  bool get needsResponse =>
      method == 'select' || method == 'confirm' || method == 'input' || method == 'editor';

  factory UiRequest.fromJson(Map<String, dynamic> json) => UiRequest(
        id: json['id'] as String? ?? '',
        method: json['method'] as String? ?? '',
        title: json['title'] as String?,
        message: json['message'] as String?,
        options: (json['options'] as List?)?.whereType<String>().toList() ?? const [],
        placeholder: json['placeholder'] as String?,
        prefill: json['prefill'] as String?,
        notifyType: json['notifyType'] as String?,
      );
}

/// 可调用的命令（slash 补全的数据源）
class SlashCommand {
  const SlashCommand({
    required this.name,
    required this.source,
    this.description,
    this.descriptionZh,
    this.argHint,
    this.sourcePath,
  });

  final String name;

  /// builtin | extension | prompt | skill
  final String source;
  final String? description;

  /// 电脑端汉化表（~/.pi/agent/commands-cn.json）里对应的中文说明；
  /// 没有就是 null —— 界面会显示原文并标注「未翻译」，不假装翻过。
  final String? descriptionZh;
  final String? argHint;

  /// 技能类命令对应 SKILL.md 的路径（点开看内容要用）
  final String? sourcePath;

  factory SlashCommand.fromJson(Map<String, dynamic> json) => SlashCommand(
        name: json['name'] as String? ?? '',
        source: json['source'] as String? ?? 'extension',
        description: json['description'] as String?,
        descriptionZh: json['descriptionZh'] as String?,
        argHint: json['argHint'] as String?,
        sourcePath: json['sourcePath'] as String?,
      );
}


/// 本轮改动速览里的一个文件
class TurnFileChange {
  const TurnFileChange({
    required this.path,
    required this.added,
    required this.removed,
    required this.edits,
    required this.writes,
  });

  final String path;
  final int added;
  final int removed;
  final int edits;
  final int writes;

  factory TurnFileChange.fromJson(Map<String, dynamic> json) => TurnFileChange(
        path: json['path'] as String? ?? '',
        added: (json['added'] as num?)?.toInt() ?? 0,
        removed: (json['removed'] as num?)?.toInt() ?? 0,
        edits: (json['edits'] as num?)?.toInt() ?? 0,
        writes: (json['writes'] as num?)?.toInt() ?? 0,
      );
}

/// 本轮改动速览（服务端从落盘 JSONL 里数出来的，不是猜的）
class TurnSummary {
  const TurnSummary({
    required this.files,
    required this.added,
    required this.removed,
    required this.toolCalls,
    required this.basis,
  });

  final List<TurnFileChange> files;
  final int added;
  final int removed;
  final int toolCalls;

  /// 统计口径（服务端给的，直接显示，免得用户以为漏算了 bash 里改的文件）
  final String basis;

  static const empty = TurnSummary(
    files: [],
    added: 0,
    removed: 0,
    toolCalls: 0,
    basis: '',
  );

  bool get isEmpty => files.isEmpty;

  factory TurnSummary.fromJson(Map<String, dynamic> json) {
    final list = (json['files'] as List?)
            ?.whereType<Map>()
            .map((item) => TurnFileChange.fromJson(item.cast<String, dynamic>()))
            .toList() ??
        const <TurnFileChange>[];
    final totals = (json['totals'] as Map?)?.cast<String, dynamic>() ?? const {};
    return TurnSummary(
      files: list,
      added: (totals['added'] as num?)?.toInt() ?? 0,
      removed: (totals['removed'] as num?)?.toInt() ?? 0,
      toolCalls: (totals['toolCalls'] as num?)?.toInt() ?? 0,
      basis: json['basis'] as String? ?? '',
    );
  }
}
