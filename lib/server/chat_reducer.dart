// 事件归约器：把 pi 的 SSE 事件流变成可渲染的消息列表。
//
// 关键约束（实测得来）：
//   · message_update 事件只带 delta，不带完整消息 —— 服务端已经剔除了 partial
//   · 所以必须靠 message_start 建消息、靠 message_end 拿权威内容
//   · 事件有序，因此"最近一条消息"就是当前流式目标，不需要额外关联字段

import 'chat_models.dart';
import 'i18n.dart';
import 'server_types.dart';

class ChatReducer {
  final List<ChatMessage> messages = [];
  final Map<String, ToolRun> tools = {};

  /// 一次运行是否在进行中
  bool isRunning = false;

  /// 本轮开始时间（毫秒）。agent_start 时打点，agent_settled 时归零。
  /// 实时活动条靠它算「已运行多久」。
  int? runStartedAt;

  /// 上一轮跑了多久（毫秒）。结束态显示「上轮用时 x」用。
  int lastRunMs = 0;

  /// 是否有消息正在流式生成
  bool isStreaming = false;

  String? sessionName;
  ModelInfo? model;
  String thinkingLevel = 'medium';
  String cwd = '';
  int contextMessages = 0;

  /// 自动压缩开关（来自快照，会话信息面板要显示）
  bool autoCompactionEnabled = true;

  /// 历史分页：会话总条数、是否还有更早的、已加载的最早一条在全集里的下标
  int historyTotal = 0;
  bool historyHasMore = false;
  int historyStart = 0;

  /// 临时状态提示（压缩中、自动重试中…）
  String? notice;

  /// 排队中的消息条数
  int queuedSteering = 0;
  int queuedFollowUp = 0;

  ChatMessage? _last;
  int _seq = 0;

  String _nextKey() => 'm${_seq++}';

  void reset() {
    messages.clear();
    tools.clear();
    _last = null;
    isRunning = false;
    isStreaming = false;
    notice = null;
    queuedSteering = 0;
    queuedFollowUp = 0;
    historyTotal = 0;
    historyHasMore = false;
    historyStart = 0;
  }

  ToolRun? toolRunOf(String? toolCallId) =>
      toolCallId == null ? null : tools[toolCallId];

  /// 用快照重建整个列表（连接建立时、重连后）
  void applySnapshot(SessionSnapshot snapshot) {
    reset();
    cwd = snapshot.cwd;
    model = snapshot.model;
    thinkingLevel = snapshot.thinkingLevel;
    sessionName = snapshot.sessionName;
    autoCompactionEnabled = snapshot.autoCompactionEnabled;
    isRunning = snapshot.isStreaming;
    // 打开会话时已经在跑（手机刚连上）：打一个点，否则活动条永远显示 0 秒
    if (isRunning) runStartedAt ??= DateTime.now().millisecondsSinceEpoch;

    for (final message in snapshot.messages) {
      // 系统消息（整个 prompt + 工具 schema）不渲染
      if (message.role == 'system') continue;
      messages.add(ChatMessage.fromPiMessage(message, key: _nextKey()));
    }
    contextMessages = messages.length;
    historyTotal = snapshot.historyTotal == 0 ? messages.length : snapshot.historyTotal;
    historyHasMore = snapshot.historyHasMore;
    historyStart = historyTotal - messages.length;
    _last = messages.isEmpty ? null : messages.last;
  }

  /// 重连后的快照合并。
  ///
  /// 与 [applySnapshot] 的区别：保留已经翻页加载的早期历史。
  /// 直接用快照重建的话，用户翻上去看的历史会被冲掉（只剩最近几十条），
  /// 表现就是「重新载入后历史不见了」。
  void mergeSnapshot(SessionSnapshot snapshot) {
    final incoming = snapshot.messages.where((m) => m.role != 'system').toList();

    // 已结束的工具记录要清掉：重连后 toolCallId 不一定复用，留着会一直累积（内存），
    // 界面上也残留上一轮的工具卡片。运行中的保留，否则正在跑的工具会凭空消失。
    tools.removeWhere((_, run) => run.status != ToolStatus.running);

    model = snapshot.model;
    thinkingLevel = snapshot.thinkingLevel;
    sessionName = snapshot.sessionName;
    autoCompactionEnabled = snapshot.autoCompactionEnabled;
    isRunning = snapshot.isStreaming;
    if (isRunning) runStartedAt ??= DateTime.now().millisecondsSinceEpoch;
    historyTotal = snapshot.historyTotal == 0 ? incoming.length : snapshot.historyTotal;
    historyHasMore = snapshot.historyHasMore;

    // 本地比快照多出来的部分就是用户翻页加载过的，留着
    final keepCount = messages.length - incoming.length;
    if (keepCount > 0) {
      messages.removeRange(messages.length - incoming.length, messages.length);
    } else {
      messages.clear();
      historyStart = historyTotal - incoming.length;
    }
    for (final message in incoming) {
      messages.add(ChatMessage.fromPiMessage(message, key: _nextKey()));
    }
    contextMessages = messages.length;
    _last = messages.isEmpty ? null : messages.last;
  }

  /// 把更早的一页消息插到列表前面（往上翻历史）
  void prependHistory(List<PiMessage> older, int start, bool hasMore) {
    final items = <ChatMessage>[];
    for (final message in older) {
      if (message.role == 'system') continue;
      items.add(ChatMessage.fromPiMessage(message, key: _nextKey()));
    }
    messages.insertAll(0, items);
    historyStart = start;
    historyHasMore = hasMore;
  }

  /// 应用一条增量事件。返回 true 表示界面需要刷新。
  bool applyEvent(ServerEvent event) {
    switch (event.type) {
      // 模型被换掉（无人值守的额度兜底插件就是这么切到备用 provider 的）。
      // 不在界面上说一句的话，用户第二天醒来只会看到「模型显示不对」——
      // 而这条切换正是他最需要知道的事（task-20 合同④）。
      case 'model_change':
        {
          final provider = event.data['provider'] as String? ?? '';
          final modelId = event.data['modelId'] as String? ?? '';
          if (provider.isNotEmpty || modelId.isNotEmpty) {
            notice = I18n.tp('ui.cd8057fce0',
                {'p': provider, 'm': modelId});
          }
          return true;
        }

      case 'agent_start':
        isRunning = true;
        runStartedAt = DateTime.now().millisecondsSinceEpoch;
        notice = null;
        return true;

      case 'agent_settled':
        isRunning = false;
        isStreaming = false;
        notice = null;
        _last = null;
        if (runStartedAt != null) {
          lastRunMs = DateTime.now().millisecondsSinceEpoch - runStartedAt!;
          runStartedAt = null;
        }
        return true;

      case 'agent_end':
        // 服务端已压缩成 {type, willRetry}
        if (event.data['willRetry'] == true) notice = I18n.t('ui.4cc14a6c13');
        return true;

      case 'message_start':
        return _onMessageStart(event.data);

      case 'message_update':
        return _onMessageUpdate(event.data);

      case 'message_end':
        return _onMessageEnd(event.data);

      case 'tool_execution_start':
        return _onToolStart(event.data);

      case 'tool_execution_update':
        return _onToolUpdate(event.data);

      case 'tool_execution_end':
        return _onToolEnd(event.data);

      case 'queue_update':
        queuedSteering = (event.data['steering'] as List?)?.length ?? 0;
        queuedFollowUp = (event.data['followUp'] as List?)?.length ?? 0;
        return true;

      case 'session_info_changed':
        sessionName = event.data['name'] as String?;
        return true;

      case 'thinking_level_changed':
        thinkingLevel = event.data['level'] as String? ?? thinkingLevel;
        return true;

      case 'compaction_start':
        notice = I18n.t('ui.c296785412');
        return true;

      case 'compaction_end':
        notice = event.data['errorMessage'] != null
            ? I18n.tp('ui.7cec835f67',
                {'e': event.data['errorMessage']})
            : null;
        return true;

      case 'auto_retry_start':
        notice = I18n.tp('ui.cdad85d6a7', {
          'a': event.data['attempt'],
          'b': event.data['maxAttempts'],
        });
        return true;

      case 'auto_retry_end':
        notice = event.data['success'] == true ? null : I18n.t('ui.41b5785945');
        return true;

      case 'session_shutdown':
        isRunning = false;
        isStreaming = false;
        runStartedAt = null;
        notice = I18n.t('ui.0fbd2577cd');
        return true;

      default:
        return false;
    }
  }

  bool _onMessageStart(Map<String, dynamic> data) {
    final raw = data['message'];
    if (raw is! Map) return false;
    final message = PiMessage.fromJson(raw.cast<String, dynamic>());
    if (message.role == 'system') return false;

    final chat = ChatMessage.fromPiMessage(message, key: _nextKey());
    // 增量事件里的消息常常**不带 timestamp**（pi 是落盘那一步才补上），
    // 而「本轮耗时」是按相邻消息的时间差算的 —— 没有它界面上永远算不出来
    // （task-21 实测：消息间隔 25 秒也不显示）。先用本机时间兜底，
    // message_end / 快照拿到权威时间时会被 absorb 覆盖。
    chat.timestamp ??= DateTime.now().millisecondsSinceEpoch;
    // 助手消息接下来会走 message_update 增量；其他角色只有 start/end
    chat.streaming = message.isAssistant;
    messages.add(chat);
    _last = chat;
    if (message.isAssistant) isStreaming = true;
    return true;
  }

  bool _onMessageUpdate(Map<String, dynamic> data) {
    final target = _last;
    if (target == null || !target.isAssistant) return false;

    final inner = data['assistantMessageEvent'];
    if (inner is! Map) return false;
    final update = inner.cast<String, dynamic>();
    final type = update['type'] as String?;

    switch (type) {
      case 'text_start':
      case 'text_end':
        return false;
      case 'text_delta':
        target.text += update['delta'] as String? ?? '';
        return true;
      case 'thinking_start':
      case 'thinking_end':
        return false;
      case 'thinking_delta':
        target.thinking += update['delta'] as String? ?? '';
        return true;
      case 'toolcall_start':
        // 服务端在 start 时补了 id 与 toolName；参数要等 message_end 才有
        target.toolCalls.add(PiToolCall(
          id: update['id'] as String? ?? '',
          name: update['toolName'] as String? ?? '',
          arguments: const {},
        ));
        return true;
      case 'toolcall_delta':
        // 参数 JSON 的片段，流式期间不解析；message_end 会给完整参数
        return false;
      case 'toolcall_end':
        final call = update['toolCall'];
        if (call is Map && target.toolCalls.isNotEmpty) {
          target.toolCalls[target.toolCalls.length - 1] =
              PiToolCall.fromMap(call.cast<String, dynamic>());
          return true;
        }
        return false;
      default:
        return false;
    }
  }

  bool _onMessageEnd(Map<String, dynamic> data) {
    final raw = data['message'];
    if (raw is! Map) return false;
    final message = PiMessage.fromJson(raw.cast<String, dynamic>());
    if (message.role == 'system') return false;

    final target = _last;
    if (target != null && target.role == message.role) {
      target.absorb(message);
      if (message.isAssistant) isStreaming = false;
      contextMessages = messages.length;
      return true;
    }

    // 没有对应的 start（例如事件丢失）时补一条，保证内容不丢
    messages.add(ChatMessage.fromPiMessage(message, key: _nextKey()));
    _last = messages.last;
    contextMessages = messages.length;
    return true;
  }

  bool _onToolStart(Map<String, dynamic> data) {
    final id = data['toolCallId'] as String?;
    if (id == null) return false;
    final run = tools[id] ?? ToolRun(
      id: id,
      name: data['toolName'] as String? ?? I18n.t('ui.20dce2c6fa'),
    );
    run.status = ToolStatus.running;
    tools[id] = run;
    return true;
  }

  bool _onToolUpdate(Map<String, dynamic> data) {
    final id = data['toolCallId'] as String?;
    if (id == null) return false;
    final run = tools[id];
    if (run == null) return false;

    final text = _extractText(data['partialResult']);
    if (text.isNotEmpty) run.replaceOutput(text);
    return text.isNotEmpty;
  }

  bool _onToolEnd(Map<String, dynamic> data) {
    final id = data['toolCallId'] as String?;
    if (id == null) return false;
    final run = tools[id];
    if (run == null) return false;
    run.status = data['isError'] == true ? ToolStatus.error : ToolStatus.done;
    return true;
  }

  /// 从工具的部分结果里取出可显示文本
  static String _extractText(dynamic partialResult) {
    if (partialResult is String) return partialResult;
    if (partialResult is! Map) return '';
    final content = partialResult['content'];
    if (content is List) {
      final buffer = StringBuffer();
      for (final item in content) {
        if (item is Map && item['type'] == 'text') {
          buffer.write(item['text'] as String? ?? '');
        }
      }
      return buffer.toString();
    }
    final text = partialResult['text'];
    return text is String ? text : '';
  }
}
