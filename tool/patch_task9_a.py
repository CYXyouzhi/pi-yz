import io

# ---------- 1) 模型：TurnSummary ----------
p = 'lib/server/chat_models.dart'
s = io.open(p, encoding='utf-8').read()
if 'class TurnSummary' not in s:
    s += '''

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
'''
    io.open(p, 'w', encoding='utf-8').write(s)
    print('chat_models: TurnSummary')

# ---------- 2) 客户端 ----------
p = 'lib/server/server_client.dart'
s = io.open(p, encoding='utf-8').read()
if 'readTurnSummary' not in s:
    s = s.replace("""  /// 跨会话用量（今天 / 本月 / 按 provider）""",
"""  /// 本轮改动速览（改了哪些文件、增删多少行）
  ///
  /// 会话里一条 edit/write 都没有时会返回空表（不是错误）——
  /// 404 只有会话本身找不到才出现，那种情况返回 null 让界面不显示这一条。
  Future<TurnSummary?> readTurnSummary(String sessionId) async {
    try {
      final json = await _json('GET', '/api/sessions/$sessionId/turn-summary');
      return TurnSummary.fromJson(json);
    } on ServerException catch (error) {
      if (error.message.contains('未找到会话')) return null;
      rethrow;
    }
  }

  /// 跨会话用量（今天 / 本月 / 按 provider）""", 1)
    io.open(p, 'w', encoding='utf-8').write(s)
    print('server_client: readTurnSummary')

# ---------- 3) store ----------
p = 'lib/server/server_store.dart'
s = io.open(p, encoding='utf-8').read()
if 'loadTurnSummary' not in s:
    s = s.replace("""  /// 拉跨会话用量（今天 / 本月 / 按 provider）""",
"""  /// 本轮改动速览（改了哪些文件、增删多少行）
  TurnSummary? turnSummary;

  Future<void> loadTurnSummary() async {
    final client = _client;
    final id = currentSessionId;
    if (client == null || id == null) {
      turnSummary = null;
      return;
    }
    try {
      turnSummary = await client.readTurnSummary(id);
    } on ServerException {
      // 读不到就当没有（不能因为一条统计把会话页搞红）
      turnSummary = null;
    }
    _notify();
  }

  /// 拉跨会话用量（今天 / 本月 / 按 provider）""", 1)
    io.open(p, 'w', encoding='utf-8').write(s)
    print('server_store: loadTurnSummary')
