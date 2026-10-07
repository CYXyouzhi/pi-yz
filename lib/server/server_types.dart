// 与服务端通信的协议类型。
//
// 对应 pi-yz-server 的接口：
//   GET  /api/sessions                  会话列表
//   POST /api/sessions                  新建会话
//   GET  /api/sessions/:id/events       SSE 事件流
//   POST /api/sessions/:id/command      命令
//   POST /api/sessions/:id/ui-response  扩展对话框回应

import 'dart:convert';
import 'i18n.dart';

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
    final parts = cwd.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty);
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
          arguments: (json['arguments'] as Map?)?.cast<String, dynamic>() ?? const {},
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
  const PiToolCall({required this.id, required this.name, required this.arguments});
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
    for (final key in const ['command', 'path', 'pattern', 'query', 'url', 'prompt']) {
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
  String get thinking => content.whereType<PiThinking>().map((c) => c.thinking).join();

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
    if (blocks.isEmpty && (role == 'branchSummary' || role == 'compactionSummary')) {
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
      usage: rawUsage is Map ? PiUsage.fromJson(rawUsage.cast<String, dynamic>()) : null,
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
      model: rawModel is Map ? ModelInfo.fromJson(rawModel.cast<String, dynamic>()) : null,
      sessionName: json['sessionName'] as String?,
      autoCompactionEnabled: json['autoCompactionEnabled'] as bool? ?? true,
      historyTotal: (json['historyTotal'] as num?)?.toInt() ?? 0,
      historyHasMore: json['historyHasMore'] as bool? ?? false,
    );
  }
}

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

  factory CommandResponse.fromJson(Map<String, dynamic> json) => CommandResponse(
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
class FileEntry {
  const FileEntry({
    required this.name,
    required this.path,
    required this.isDir,
    this.size = 0,
  });

  final String name;
  final String path;
  final bool isDir;
  final int size;

  factory FileEntry.fromJson(Map<String, dynamic> json) => FileEntry(
        name: json['name'] as String? ?? '',
        path: json['path'] as String? ?? '',
        isDir: json['type'] == 'dir',
        size: (json['size'] as num?)?.toInt() ?? 0,
      );
}

/// 目录列表
class DirListing {
  const DirListing({required this.path, required this.entries, this.parent});

  final String path;
  final String? parent;
  final List<FileEntry> entries;

  factory DirListing.fromJson(Map<String, dynamic> json) => DirListing(
        path: json['path'] as String? ?? '',
        parent: json['parent'] as String?,
        entries: (json['entries'] as List?)
                ?.whereType<Map>()
                .map((e) => FileEntry.fromJson(e.cast<String, dynamic>()))
                .toList() ??
            const [],
      );
}

/// 文本文件内容
class FileText {
  const FileText({
    required this.path,
    required this.text,
    required this.size,
    required this.truncated,
  });

  final String path;
  final String text;
  final int size;
  final bool truncated;

  factory FileText.fromJson(Map<String, dynamic> json) => FileText(
        path: json['path'] as String? ?? '',
        text: json['text'] as String? ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
        truncated: json['truncated'] as bool? ?? false,
      );
}

/// git status 的一条变更
class GitChange {
  const GitChange({required this.status, required this.path});
  final String status;
  final String path;

  factory GitChange.fromJson(Map<String, dynamic> json) => GitChange(
        status: json['status'] as String? ?? '',
        path: json['path'] as String? ?? '',
      );
}

class GitStatusInfo {
  const GitStatusInfo({
    required this.cwd,
    required this.files,
    required this.isRepo,
    this.branch,
    this.error,
  });

  final String cwd;
  final List<GitChange> files;
  final bool isRepo;
  final String? branch;
  final String? error;

  factory GitStatusInfo.fromJson(Map<String, dynamic> json) => GitStatusInfo(
        cwd: json['cwd'] as String? ?? '',
        isRepo: json['isRepo'] as bool? ?? false,
        branch: json['branch'] as String?,
        error: json['error'] as String?,
        files: (json['files'] as List?)
                ?.whereType<Map>()
                .map((e) => GitChange.fromJson(e.cast<String, dynamic>()))
                .toList() ??
            const [],
      );
}

class GitDiffInfo {
  const GitDiffInfo({required this.diff, required this.empty, this.path});
  final String diff;
  final bool empty;
  final String? path;

  factory GitDiffInfo.fromJson(Map<String, dynamic> json) => GitDiffInfo(
        diff: json['diff'] as String? ?? '',
        empty: json['empty'] as bool? ?? true,
        path: json['path'] as String?,
      );
}

/// @ 引用候选
class FileRef {
  const FileRef({required this.name, required this.path, required this.relative});
  final String name;
  final String path;
  final String relative;

  factory FileRef.fromJson(Map<String, dynamic> json) => FileRef(
        name: json['name'] as String? ?? '',
        path: json['path'] as String? ?? '',
        relative: json['relative'] as String? ?? '',
      );
}

/// MCP 服务器（只读列举）
class McpServerInfo {
  const McpServerInfo({
    required this.name,
    required this.scope,
    required this.kind,
    required this.target,
    this.args = '',
    this.enabled = true,
    this.description = '',
  });

  final String name;
  final String scope; // user | project
  final String kind; // local | remote
  final String target;
  final String args;

  /// enabled:false 表示条目保留但不连接
  final bool enabled;
  final String description;

  factory McpServerInfo.fromJson(Map<String, dynamic> json) => McpServerInfo(
        name: json['name'] as String? ?? '',
        scope: json['scope'] as String? ?? 'user',
        kind: json['kind'] as String? ?? 'local',
        target: json['target'] as String? ?? '',
        args: json['args'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
        description: json['description'] as String? ?? '',
      );
}

/// Provider 凭据（只报哪个 provider 配了，不含密钥本体）
class CredentialInfo {
  const CredentialInfo({required this.provider, required this.type});
  final String provider;
  final String type;

  factory CredentialInfo.fromJson(Map<String, dynamic> json) => CredentialInfo(
        provider: json['provider'] as String? ?? '',
        type: json['type'] as String? ?? 'api_key',
      );
}


/// 一个已配置的 pi 包（插件）
class PiPackageInfo {
  const PiPackageInfo({
    required this.source,
    required this.scope,
    this.filtered = false,
    this.installedPath,
    this.zhCount = 0,
  });

  /// npm:xxx / git 地址 / 本地路径
  final String source;
  final String scope; // user | project
  final bool filtered;
  final String? installedPath;

  /// 电脑端汉化扩展在这个包里翻译了多少处文案（0 = 没汉化过）
  final int zhCount;

  factory PiPackageInfo.fromJson(Map<String, dynamic> json) => PiPackageInfo(
        source: json['source'] as String? ?? '',
        scope: json['scope'] as String? ?? 'user',
        filtered: json['filtered'] as bool? ?? false,
        installedPath: json['installedPath'] as String?,
        zhCount: (json['zhCount'] as num?)?.toInt() ?? 0,
      );
}

/// 可更新的包
class PackageUpdateInfo {
  const PackageUpdateInfo({required this.source, this.displayName = '', this.type = 'npm'});

  final String source;
  final String displayName;
  final String type;

  factory PackageUpdateInfo.fromJson(Map<String, dynamic> json) => PackageUpdateInfo(
        source: json['source'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        type: json['type'] as String? ?? 'npm',
      );
}

/// 原始文件（图片 / PDF 预览）
class RawFileData {
  const RawFileData({required this.bytes, required this.contentType, required this.kind});

  final List<int> bytes;
  final String contentType;

  /// image | pdf | audio | video | text | binary
  final String kind;

  int get size => bytes.length;
}

/// 一个 git worktree
class WorktreeInfo {
  const WorktreeInfo({
    required this.path,
    this.branch,
    this.head,
    this.detached = false,
    this.isMain = false,
  });

  final String path;
  final String? branch;
  final String? head;
  final bool detached;
  final bool isMain;

  factory WorktreeInfo.fromJson(Map<String, dynamic> json) => WorktreeInfo(
        path: json['path'] as String? ?? '',
        branch: json['branch'] as String?,
        head: json['head'] as String?,
        detached: json['detached'] as bool? ?? false,
        isMain: json['isMain'] as bool? ?? false,
      );
}

/// 会话导出（Markdown 文本），给 App 预览/复制/存手机用
class ExportMarkdown {
  const ExportMarkdown({
    required this.markdown,
    required this.filename,
    required this.title,
  });

  final String markdown;
  final String filename;
  final String title;
}

/// 会话统计（`get_session_stats`）
class SessionStats {
  const SessionStats({
    this.userMessages = 0,
    this.assistantMessages = 0,
    this.toolCalls = 0,
    this.toolResults = 0,
    this.totalMessages = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheWriteTokens = 0,
    this.totalTokens = 0,
    this.costTotal = 0,
    this.contextTokens,
    this.contextWindow,
    this.contextPercent,
  });

  final int userMessages;
  final int assistantMessages;
  final int toolCalls;
  final int toolResults;
  final int totalMessages;
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final int totalTokens;
  final double costTotal;

  /// 当前上下文占用（压缩后、还没跑过模型时可能是 null）
  final int? contextTokens;
  final int? contextWindow;
  final double? contextPercent;

  factory SessionStats.fromJson(Map<String, dynamic> json) {
    // 注意：服务端的 `cost` 是**数字**（总额），而消息级的 usage.cost 是对象；
    // tokens / contextUsage 是对象。所以不能一律 `as Map` —— 之前就是这么错的：
    // 一个 double 被强转成 Map 直接抛异常，害得「会话信息」面板点了没反应。
    final tokens = json['tokens'];
    final cost = json['cost'];
    final ctx = json['contextUsage'];
    final tokensMap = tokens is Map ? tokens : const {};
    final ctxMap = ctx is Map ? ctx : const {};
    final costTotal = cost is num
        ? cost.toDouble()
        : (cost is Map && cost['total'] is num ? (cost['total'] as num).toDouble() : 0.0);
    int intOf(dynamic value) => value is num ? value.toInt() : 0;
    return SessionStats(
      userMessages: intOf(json['userMessages']),
      assistantMessages: intOf(json['assistantMessages']),
      toolCalls: intOf(json['toolCalls']),
      toolResults: intOf(json['toolResults']),
      totalMessages: intOf(json['totalMessages']),
      inputTokens: intOf(tokensMap['input']),
      outputTokens: intOf(tokensMap['output']),
      cacheReadTokens: intOf(tokensMap['cacheRead']),
      cacheWriteTokens: intOf(tokensMap['cacheWrite']),
      totalTokens: intOf(tokensMap['total']),
      costTotal: costTotal,
      contextTokens: ctxMap['tokens'] is num ? (ctxMap['tokens'] as num).toInt() : null,
      contextWindow: ctxMap['contextWindow'] is num ? (ctxMap['contextWindow'] as num).toInt() : null,
      contextPercent: ctxMap['percent'] is num ? (ctxMap['percent'] as num).toDouble() : null,
    );
  }
}

/// 服务端健康状态
class HealthInfo {
  const HealthInfo({required this.ok, required this.piVersion, this.activeSessions = 0});

  final bool ok;
  final String piVersion;
  final int activeSessions;

  factory HealthInfo.fromJson(Map<String, dynamic> json) => HealthInfo(
        ok: json['ok'] as bool? ?? false,
        piVersion: json['piVersion'] as String? ?? '?',
        activeSessions: (json['activeSessions'] as num?)?.toInt() ?? 0,
      );
}

// ==================== Provider 登录（/api/providers, /api/login） ====================

/// provider 支持的一种登录方式
class AuthOption {
  const AuthOption({
    required this.type,
    required this.label,
    this.interactive = true,
    this.subscription = false,
  });

  /// api_key | oauth
  final String type;
  final String label;

  /// false = 只能靠环境变量/配置文件，界面上点不了
  final bool interactive;
  final bool subscription;

  factory AuthOption.fromJson(Map<String, dynamic> json) => AuthOption(
        type: json['type'] as String? ?? 'api_key',
        label: json['label'] as String? ?? 'API Key',
        interactive: json['interactive'] as bool? ?? true,
        subscription: json['subscription'] as bool? ?? false,
      );
}

class ProviderInfo {
  const ProviderInfo({
    required this.id,
    required this.name,
    this.configured = false,
    this.source,
    this.label,
    this.auth = const [],
  });

  final String id;
  final String name;
  final bool configured;
  final String? source;
  final String? label;
  final List<AuthOption> auth;

  factory ProviderInfo.fromJson(Map<String, dynamic> json) => ProviderInfo(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        configured: json['configured'] as bool? ?? false,
        source: json['source'] as String?,
        label: json['label'] as String?,
        auth: (json['auth'] as List?)
                ?.whereType<Map>()
                .map((e) => AuthOption.fromJson(e.cast<String, dynamic>()))
                .toList() ??
            const [],
      );
}

/// 登录流程里的一个提示（服务端问、用户答）
class AuthPromptInfo {
  const AuthPromptInfo({
    required this.type,
    required this.message,
    this.placeholder,
    this.options = const [],
  });

  /// text | secret | select | manual_code
  final String type;
  final String message;
  final String? placeholder;
  final List<({String id, String label, String? description})> options;

  factory AuthPromptInfo.fromJson(Map<String, dynamic> json) => AuthPromptInfo(
        type: json['type'] as String? ?? 'text',
        message: json['message'] as String? ?? '',
        placeholder: json['placeholder'] as String?,
        options: (json['options'] as List?)
                ?.whereType<Map>()
                .map((e) => (
                      id: e['id'] as String? ?? '',
                      label: e['label'] as String? ?? '',
                      description: e['description'] as String?,
                    ))
                .toList() ??
            const [],
      );
}

/// 登录流程的一次轮询结果
class LoginStatus {
  const LoginStatus({
    required this.id,
    required this.state,
    this.prompt,
    this.events = const [],
    this.error,
  });

  /// running | prompt | done | error | cancelled
  final String state;
  final String id;
  final AuthPromptInfo? prompt;

  /// 服务端推来的信息（授权链接、设备码、进度）
  final List<Map<String, dynamic>> events;
  final String? error;

  bool get isFinished => state == 'done' || state == 'error' || state == 'cancelled';

  factory LoginStatus.fromJson(Map<String, dynamic> json) => LoginStatus(
        id: json['id'] as String? ?? '',
        state: json['state'] as String? ?? 'running',
        prompt: json['prompt'] is Map
            ? AuthPromptInfo.fromJson((json['prompt'] as Map).cast<String, dynamic>())
            : null,
        events: (json['events'] as List?)
                ?.whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList() ??
            const [],
        error: json['error'] as String?,
      );
}


/// 一轮（一次模型调用）的用量明细。数字全部来自落盘 JSONL，缺的就是 null。
class UsageTurn {
  const UsageTurn({
    required this.index,
    this.at,
    this.provider,
    this.model,
    this.input,
    this.output,
    this.cacheRead,
    this.cacheWrite,
    this.reasoning,
    this.totalTokens,
    this.cost,
    this.durationMs,
    this.tokensPerSec,
    this.cacheHitRate,
    this.stopReason,
  });

  final int index;
  final String? at;
  final String? provider;
  final String? model;
  final int? input;
  final int? output;
  final int? cacheRead;
  final int? cacheWrite;
  final int? reasoning;
  final int? totalTokens;
  final double? cost;
  final int? durationMs;
  final double? tokensPerSec;
  final double? cacheHitRate;
  final String? stopReason;

  factory UsageTurn.fromJson(Map<String, dynamic> json) => UsageTurn(
        index: (json['index'] as num?)?.toInt() ?? 0,
        at: json['at'] as String?,
        provider: json['provider'] as String?,
        model: json['model'] as String?,
        input: (json['input'] as num?)?.toInt(),
        output: (json['output'] as num?)?.toInt(),
        cacheRead: (json['cacheRead'] as num?)?.toInt(),
        cacheWrite: (json['cacheWrite'] as num?)?.toInt(),
        reasoning: (json['reasoning'] as num?)?.toInt(),
        totalTokens: (json['totalTokens'] as num?)?.toInt(),
        cost: (json['cost'] as num?)?.toDouble(),
        durationMs: (json['durationMs'] as num?)?.toInt(),
        tokensPerSec: (json['tokensPerSec'] as num?)?.toDouble(),
        cacheHitRate: (json['cacheHitRate'] as num?)?.toDouble(),
        stopReason: json['stopReason'] as String?,
      );
}

/// 一条会话的用量（逐轮 + 汇总）
class SessionUsage {
  const SessionUsage({required this.turns, required this.totals});
  final List<UsageTurn> turns;
  final UsageTotals totals;

  factory SessionUsage.fromJson(Map<String, dynamic> json) => SessionUsage(
        turns: (json['turns'] as List?)
                ?.whereType<Map>()
                .map((e) => UsageTurn.fromJson(e.cast<String, dynamic>()))
                .toList() ??
            const [],
        totals: UsageTotals.fromJson(
            (json['totals'] as Map?)?.cast<String, dynamic>() ?? const {}),
      );
}

class UsageTotals {
  const UsageTotals({
    this.input = 0,
    this.output = 0,
    this.cacheRead = 0,
    this.cacheWrite = 0,
    this.reasoning = 0,
    this.cost = 0,
    this.turns = 0,
    this.cacheHitRate,
    this.tokensPerSec,
  });

  final int input;
  final int output;
  final int cacheRead;
  final int cacheWrite;
  final int reasoning;
  final double cost;
  final int turns;
  final double? cacheHitRate;
  final double? tokensPerSec;

  factory UsageTotals.fromJson(Map<String, dynamic> json) => UsageTotals(
        input: (json['input'] as num?)?.toInt() ?? 0,
        output: (json['output'] as num?)?.toInt() ?? 0,
        cacheRead: (json['cacheRead'] as num?)?.toInt() ?? 0,
        cacheWrite: (json['cacheWrite'] as num?)?.toInt() ?? 0,
        reasoning: (json['reasoning'] as num?)?.toInt() ?? 0,
        cost: (json['cost'] as num?)?.toDouble() ?? 0,
        turns: (json['turns'] as num?)?.toInt() ?? 0,
        cacheHitRate: (json['cacheHitRate'] as num?)?.toDouble(),
        tokensPerSec: (json['tokensPerSec'] as num?)?.toDouble(),
      );
}

/// 跨会话用量（今天 / 本月 / 按天 / 按 provider）
class UsageSummary {
  const UsageSummary({
    required this.todayTokens,
    required this.todayCost,
    required this.monthTokens,
    required this.monthCost,
    required this.scannedSessions,
    required this.byProvider,
    this.byDay = const [],
    this.byWorkspace = const [],
  });

  final int todayTokens;
  final double todayCost;
  final int monthTokens;
  final double monthCost;
  final int scannedSessions;
  final List<({String provider, int tokens, double cost, int turns})> byProvider;

  /// 按天（服务端从落盘 JSONL 的 assistant 条目里累加，日期取条目时间戳的 UTC 前缀）
  final List<({String day, int tokens, double cost})> byDay;

  /// 按工作区：同一台电脑上不同项目的花费能分开看
  final List<({String cwd, int tokens, double cost, int turns, int sessions})>
      byWorkspace;

  factory UsageSummary.fromJson(Map<String, dynamic> json) {
    final today = (json['today'] as Map?)?.cast<String, dynamic>() ?? const {};
    final month = (json['month'] as Map?)?.cast<String, dynamic>() ?? const {};
    final providers = (json['byProvider'] as List?) ?? const [];
    return UsageSummary(
      todayTokens: (today['tokens'] as num?)?.toInt() ?? 0,
      todayCost: (today['cost'] as num?)?.toDouble() ?? 0,
      monthTokens: (month['tokens'] as num?)?.toInt() ?? 0,
      monthCost: (month['cost'] as num?)?.toDouble() ?? 0,
      scannedSessions: (json['scannedSessions'] as num?)?.toInt() ?? 0,
      byProvider: [
        for (final item in providers.whereType<Map>())
          (
            provider: (item['provider'] as String?) ?? 'unknown',
            tokens: ((item['tokens'] as num?)?.toInt()) ?? 0,
            cost: ((item['cost'] as num?)?.toDouble()) ?? 0,
            turns: ((item['turns'] as num?)?.toInt()) ?? 0,
          ),
      ],
      byDay: [
        for (final item in ((json['byDay'] as List?) ?? const []).whereType<Map>())
          (
            day: (item['day'] as String?) ?? '',
            tokens: ((item['tokens'] as num?)?.toInt()) ?? 0,
            cost: ((item['cost'] as num?)?.toDouble()) ?? 0,
          ),
      ],
      byWorkspace: [
        for (final item
            in ((json['byWorkspace'] as List?) ?? const []).whereType<Map>())
          (
            cwd: (item['cwd'] as String?) ?? '',
            tokens: ((item['tokens'] as num?)?.toInt()) ?? 0,
            cost: ((item['cost'] as num?)?.toDouble()) ?? 0,
            turns: ((item['turns'] as num?)?.toInt()) ?? 0,
            sessions: ((item['sessions'] as num?)?.toInt()) ?? 0,
          ),
      ],
    );
  }
}

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
    final parts = cwd.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty);
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
    final parts = cwd.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty);
    return parts.isEmpty ? cwd : parts.last;
  }

  factory DiskGroup.fromJson(Map<String, dynamic> json) => DiskGroup(
        cwd: json['cwd'] as String? ?? '',
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
        count: (json['count'] as num?)?.toInt() ?? 0,
        sessions: (json['sessions'] as List?)
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
        groups: (json['groups'] as List?)
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
        threatModel: (json['threatModel'] as List?)
                ?.whereType<String>()
                .toList() ??
            const [],
      );
}

/// 时间戳解析：pi 落盘的 timestamp 是 **ISO 字符串**（`2026-10-04T05:03:26.123Z`），
/// 不是毫秒数。早前这里写成 `(json['timestamp'] as num?)?.toInt()`，
/// 于是所有消息的 timestamp 都是 null —— 界面上「本轮耗时」永远算不出来
/// （task-21 实测发现）。两种格式都认，数字当毫秒、字符串按 ISO 解析。
int? parseTimestamp(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toInt();
  final text = raw.toString();
  final asInt = int.tryParse(text);
  if (asInt != null) return asInt;
  return DateTime.tryParse(text)?.millisecondsSinceEpoch;
}
