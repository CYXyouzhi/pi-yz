import 'chat_models.dart';
import 'i18n.dart';
import 'chat_reducer.dart';

/// 实时活动视图的数据层：把会话消息摊平成「一眼看清 agent 在干什么」的时间线。
///
/// 为什么单独一个文件、且全是纯函数：这块逻辑（当前动作、运行时长、token 速度、
/// 文件数）都是可算的确定值，抽出来就能用单测钉死，不用靠肉眼看界面猜。
enum ActivityKind { user, thinking, tool, reply, wait }

class ActivityItem {
  const ActivityItem({
    required this.at,
    required this.kind,
    required this.title,
    required this.detail,
    this.running = false,
    this.failed = false,
  });

  /// 毫秒时间戳；0 表示这条没有时间（界面就不显示时刻）
  final int at;
  final ActivityKind kind;

  /// 工具名 / 「思考」/「你」
  final String title;

  /// 命令、路径、命令原文的摘要
  final String detail;

  /// 还在跑（只有工具会）
  final bool running;

  /// 出错了（对应的 toolResult 标记了 error）
  final bool failed;
}

class ActivitySnapshot {
  const ActivitySnapshot({
    required this.items,
    required this.running,
    required this.current,
    required this.toolCount,
    required this.fileCount,
    required this.outputTokens,
    required this.elapsedMs,
    this.lastRunMs = 0,
    this.waitingCount = 0,
  });

  /// 旧 → 新
  final List<ActivityItem> items;
  final bool running;

  /// 「正在干的那件」：最后一个还在跑的工具；没有就退回最后一条思考/回复
  final ActivityItem? current;

  final int toolCount;
  final int fileCount;
  final int outputTokens;

  /// 本轮已运行毫秒；没在跑就是 0
  final int elapsedMs;

  /// 上一轮用了多久（结束态显示「上轮用时 x」）
  final int lastRunMs;

  /// 正在等用户确认的条数（>0 时状态条要抢眼）
  final int waitingCount;

  bool get empty => items.isEmpty;

  /// 输出速度（token/秒）。不足 1 秒或没 token 时不编数字，返回 0。
  double get tokensPerSecond {
    if (elapsedMs < 1000 || outputTokens <= 0) return 0;
    return outputTokens / (elapsedMs / 1000);
  }
}

/// 工具调用的「一句话摘要」。不同工具的参数名不一样，按常见顺序挑。
String toolSummary(String name, Map<String, dynamic> args) {
  const keys = [
    'command', // bash
    'path', // read / write / edit / fffind
    'file_path',
    'pattern', // grep / ffgrep
    'query',
    'url',
    'text',
    'prompt',
  ];
  String? raw;
  for (final k in keys) {
    final v = args[k];
    if (v is String && v.trim().isNotEmpty) {
      raw = v;
      break;
    }
  }
  // ask_user_question 这类工具的参数是结构化列表（questions: [{header, ...}]）：
  // 挑出里面的人话当摘要，否则时间线上只能显示一个「—」
  if (raw == null) {
    final list = args['questions'] ?? args['options'];
    if (list is List && list.isNotEmpty) {
      final first = list.first;
      if (first is Map) {
        final t = first['header'] ?? first['question'] ?? first['label'];
        if (t is String && t.trim().isNotEmpty) raw = t;
      } else if (first is String && first.trim().isNotEmpty) {
        raw = first;
      }
    }
  }
  if (raw == null) {
    for (final v in args.values) {
      if (v is String && v.trim().isNotEmpty) {
        raw = v;
        break;
      }
    }
  }
  if (raw == null) return '';
  return oneLine(raw, 90);
}

/// 折成单行并截断 —— 时间线上每格只有一行，不能让换行把布局撑开。
String oneLine(String s, int max) {
  final flat = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.length <= max) return flat;
  return '${flat.substring(0, max)}…';
}

/// 把一次运行摊成时间线。
///
/// [now] 用毫秒时间戳传入（默认取系统时间），方便单测固定时间。
ActivitySnapshot buildActivity(
  ChatReducer chat, {
  int? now,

  /// 本轮开始时间（毫秒）。界面手里有更准的（agent_start 那一刻），优先用它；
  /// 没传就退回「本轮最后一条用户消息」的时间。
  int? runStartedAt,

  /// 正在等用户回话的那些请求（界面拿 store.uiRequests 传进来）。
  /// 合同①要求时间线里能看到「等待确认」—— 它不是一个工具调用，
  /// 但正是用户最需要被叫醒的那一步。
  List<String> pending = const [],
  int max = 300,
}) {
  final items = <ActivityItem>[];
  var outputTokens = 0;
  final files = <String>{};
  var lastUserAt = 0;

  // 「本轮」= 最后一条用户消息之后的那一段。
  // 状态条上的「本轮 N 次工具调用」只算这一段，否则老会话空闲时会一直挂着
  // 历史里所有工具调用的计数（实测：一个 10 次调用的会话写「本轮 10 次工具调用」，
  // 读起来像刚跑完）。整个会话没有用户消息时（少见）就按全量算。
  var toolCountInRound = 0;
  var lastUserMsgIdx = -1;
  for (var i = 0; i < chat.messages.length; i++) {
    if (chat.messages[i].role == 'user') lastUserMsgIdx = i;
  }
  bool inRound(int i) => lastUserMsgIdx < 0 || i > lastUserMsgIdx;

  for (var i = 0; i < chat.messages.length; i++) {
    final m = chat.messages[i];
    final at = m.timestamp ?? 0;

    if (m.role == 'user') {
      if (at > 0) lastUserAt = at;
      final text = m.text.trim();
      if (text.isNotEmpty) {
        items.add(
          ActivityItem(
            at: at,
            kind: ActivityKind.user,
            title: I18n.t('ui.df1fd91011'),
            detail: oneLine(text, 90),
          ),
        );
      }
    }

    if (m.thinking.trim().isNotEmpty) {
      items.add(
        ActivityItem(
          at: at,
          kind: ActivityKind.thinking,
          title: I18n.t('ui.21d68b2de0'),
          detail: oneLine(m.thinking, 90),
        ),
      );
    }

    for (final call in m.toolCalls) {
      final run = chat.toolRunOf(call.id);
      final path = call.arguments['path'] ?? call.arguments['file_path'];
      if (inRound(i)) toolCountInRound++;
      if (path is String && path.trim().isNotEmpty && inRound(i)) {
        files.add(path);
      }
      items.add(
        ActivityItem(
          at: at,
          kind: ActivityKind.tool,
          title: call.name,
          detail: toolSummary(call.name, call.arguments),
          running: run != null && run.status == ToolStatus.running,
          failed: run != null && run.status == ToolStatus.error,
        ),
      );
    }

    // 助手正文：只算「有话说」的那条，纯工具轮的空文本不进时间线
    if (m.role == 'assistant' && m.text.trim().isNotEmpty) {
      items.add(
        ActivityItem(
          at: at,
          kind: ActivityKind.reply,
          title: I18n.t('ui.1edff073d4'),
          detail: oneLine(m.text, 90),
        ),
      );
    }

    final u = m.usage;
    if (u != null) outputTokens += u.output;
  }

  if (items.length > max) {
    items.removeRange(0, items.length - max);
  }

  // 等你确认：放在最上面（时间线是新的在上）—— 这是最该被看见的一条
  //
  // 顺手记下最后一条：下面的「当前动作」要用它。
  // 原先那里写的是 items.last，依赖「pending 的元素都被 append 到 items 末尾」
  // 这个隐式不变量 —— 谁把 add 改成 insert(0, …) 就会取错甚至越界。
  ActivityItem? lastPending;
  for (final p in pending) {
    final item = ActivityItem(
      at: 0,
      kind: ActivityKind.wait,
      title: I18n.t('ui.493b7bc5ff'),
      detail: oneLine(p, 90),
      running: true,
    );
    items.add(item);
    lastPending = item;
  }

  // 当前动作：最后一个还在跑的工具优先；有等确认的则直接说等确认
  ActivityItem? current = lastPending;
  for (final it in items.reversed) {
    if (it.kind == ActivityKind.tool && it.running) {
      current = it;
      break;
    }
  }
  if (current == null) {
    for (final it in items.reversed) {
      if (it.kind == ActivityKind.thinking || it.kind == ActivityKind.reply) {
        current = it;
        break;
      }
    }
  }

  final stamp = now ?? DateTime.now().millisecondsSinceEpoch;
  final running = chat.isRunning;
  // 运行时长：优先用界面给的「本轮开始时间」，没有就用本轮最后一条用户消息的时间
  final start = runStartedAt ?? lastUserAt;
  final elapsed = running && start > 0 && stamp > start ? stamp - start : 0;

  return ActivitySnapshot(
    items: items,
    running: running,
    current: current,
    toolCount: toolCountInRound,
    fileCount: files.length,
    outputTokens: outputTokens,
    elapsedMs: elapsed,
    lastRunMs: chat.lastRunMs,
    waitingCount: pending.length,
  );
}

/// `1:23` / `12 分 4 秒` —— 状态条窄，用短格式。
String humanDuration(int ms) {
  if (ms <= 0) return I18n.t('ui.c73936bbd7');
  final total = ms ~/ 1000;
  if (total < 60) return I18n.tp('ui.c2d9323e9e', {'n': total});
  final m = total ~/ 60;
  final s = total % 60;
  if (m < 60) return '$m:${s.toString().padLeft(2, '0')}';
  final h = m ~/ 60;
  return '$h:${(m % 60).toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// `10:42:07` —— 时间线左侧的时刻。
String clockOf(int ms) {
  if (ms <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}
