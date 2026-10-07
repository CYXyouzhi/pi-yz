// usage 领域的数据模型
//
// 由 server_types.dart 拆分而来（原文件保留为 barrel，
// 所以调用方 import 路径不用改）。




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
