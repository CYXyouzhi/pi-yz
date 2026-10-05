// 服务端状态管理。
//
// 一个 store 管一件事：当前连接 + 当前会话的消息流。
// 页面只读 store，不自己发请求。

import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'chat_models.dart';
import 'i18n.dart';
import 'app_prefs.dart';
import 'chat_reducer.dart';
import 'session_cache.dart';
import 'native_bridge.dart';
import 'server_client.dart';
import 'server_types.dart';

enum ServerConnectionState { disconnected, connecting, connected, error }

/// 连接目标
class ServerTarget {
  const ServerTarget({
    required this.host,
    required this.port,
    required this.token,
    this.defaultCwd,
    this.secure = false,
    this.fallbackHost,
    this.fallbackPort,
    this.fallbackSecure = false,
  });

  final String host;
  final int port;
  final String token;

  /// 新建会话时默认使用的工作目录
  final String? defaultCwd;

  /// HTTPS（远程隧道）；局域网直连是 http
  final bool secure;

  /// 备用地址（可选）：主地址连不上时自动试它，见 [ServerStore.connect]。
  /// 典型配法 —— 主地址填家里局域网 IP，备用填 Tailscale 的 100.x.x.x。
  final String? fallbackHost;
  final int? fallbackPort;
  final bool fallbackSecure;

  String get label => secure ? 'https://$host:$port' : '$host:$port';

  /// 候选地址列表：主地址在前、备用在后。
  ///
  /// 主地址排第一是**故意的**：局域网延迟比走 VPN 低一个数量级，
  /// 所以「在家优先直连」是默认行为；出门时第一条自然连不上，
  /// 自动落到第二条 —— 用户不需要切任何东西。
  List<ServerEndpoint> get candidates => [
        ServerEndpoint(host, port, secure, isFallback: false),
        if ((fallbackHost ?? '').trim().isNotEmpty)
          ServerEndpoint(
            fallbackHost!.trim(),
            fallbackPort ?? port,
            fallbackSecure,
            isFallback: true,
          ),
      ];
}

/// 一个可尝试的地址（主地址或备用地址）。
class ServerEndpoint {
  const ServerEndpoint(this.host, this.port, this.secure, {required this.isFallback});

  final String host;
  final int port;
  final bool secure;

  /// true = 这是备用地址。回落成功时界面要如实标出来，否则用户
  /// 根本不知道现在走的是局域网还是 VPN，排查问题会很糊涂。
  final bool isFallback;

  /// 展示用。**与 `ServerProfile.endpoint` 用同一条规则**：HTTPS 且端口是 443 时
  /// 不带端口 —— 否则同一台服务器在连接页显示 `https://pi.example.com`、
  /// 在状态栏显示 `https://pi.example.com:443`，看起来像两个不同的地址。
  /// （这条不一致是单元测试抓出来的，不是看代码看出来的。）
  String get label {
    if (!secure) return '$host:$port';
    return port == 443 ? 'https://$host' : 'https://$host:$port';
  }
}

class ServerStore extends ChangeNotifier {
  ServerClient? _client;
  StreamSubscription<ServerEvent>? _events;
  Timer? _reconnectTimer;
  /// 载入超时兜底：不能因为一个请求没回来就一直显示「正在载入」
  Timer? _snapshotTimeout;
  int _reconnectAttempt = 0;
  bool _disposed = false;

  ServerConnectionState state = ServerConnectionState.disconnected;
  String? errorMessage;
  HealthInfo? health;
  ServerTarget? target;

  /// 当前**实际**连上的那个地址。配了备用地址且回落成功时，这里指向备用那条。
  /// 界面靠它显示「当前走的是哪条路」。
  ServerEndpoint? activeEndpoint;

  /// 探活超时。见 connect() 里的说明：必须足够短，回落才有意义。
  static const _probeTimeout = Duration(seconds: 5);

  List<ServerSession> sessions = const [];
  bool loadingSessions = false;
  String? sessionsError;

  // ==================== 多会话并行与磁盘占用（task-15） ====================

  /// 服务端池里还活着的会话：哪个在跑、跑到哪、花了多少
  List<PoolSession> pool = const [];

  /// 远程访问隧道状态（task-18）
  RemoteState remote = RemoteState.empty;
  bool remoteBusy = false;

  /// 磁盘占用（按工作区分组）；null = 还没拉过
  DiskUsage? disk;
  bool loadingDisk = false;
  String? diskError;

  /// 默认列表：把已归档的筛掉（合同③）
  List<ServerSession> get visibleSessions =>
      sessions.where((s) => !AppPrefs.instance.isArchived(s.id)).toList();

  /// 归档箱（列表底部的入口）
  List<ServerSession> get archivedSessions =>
      sessions.where((s) => AppPrefs.instance.isArchived(s.id)).toList();

  bool isArchived(String sessionId) => AppPrefs.instance.isArchived(sessionId);

  List<PoolSession> get runningPool =>
      pool.where((p) => p.running).toList();

  /// 归档一条会话：本地标记 + 立刻刷新列表（不然要点别的才看出来）
  Future<void> archiveSession(String sessionId) async {
    await AppPrefs.instance.archiveSession(sessionId);
    _notify();
  }

  Future<void> unarchiveSession(String sessionId) async {
    await AppPrefs.instance.unarchiveSession(sessionId);
    _notify();
  }

  /// 会话列表专用的版本号。
  ///
  /// store 是单一的 ChangeNotifier，流式时每个 delta 都会 notify ——
  /// 列表页（实测历史 244 条）跟着重建纯属浪费。
  /// 列表只关心「数据变了」，所以单独给它一个信号。
  final ValueNotifier<int> sessionsRevision = ValueNotifier<int>(0);

  void _bumpSessions() {
    if (_disposed) return;
    sessionsRevision.value++;
  }

  /// 最近一次操作失败的原因（界面用来提示）
  String? lastError;

  /// 新建但还没落盘的会话。
  ///
  /// pi 的会话存储是 append-only：没说过话就不产生文件，
  /// 所以刚建的会话不会出现在 /api/sessions 里。
  /// 界面需要把它显式排到列表顶部，否则用户会以为「新建没生效」。
  ServerSession? pendingSession;

  /// 已展开的工作区。放在 store 里而不是页面 State 里：
  /// 切 Tab 时页面会重建，State 里的展开状态会丢。
  final Set<String> expandedWorkspaces = {};

  String? currentSessionId;

  /// 当前会话的显示名（会话名，没有就用首条消息预览）。
  /// 实时活动条上要写它 —— 多会话并行时得知道这条状态属于谁。
  String get currentSessionTitle {
    final id = currentSessionId;
    if (id == null) return '';
    for (final s in sessions) {
      if (s.id == id) return s.displayTitle;
    }
    // 离线时 sessions 是空的：退回服务端给的会话名（快照里有）
    return chat.sessionName ?? '';
  }

  /// 正在建立事件流、等首帧快照（界面据此显示加载态）
  bool loadingSession = false;

  /// 正在加载更早的历史
  bool loadingHistory = false;

  final ChatReducer chat = ChatReducer();

  List<SlashCommand> commands = const [];

  /// 命令列表里是否包含「扩展命令」。
  /// 扩展命令只有会话启动时才会注册，所以没打开会话时它是缺的 ——
  /// 界面据此显示"需打开会话"，而不是让人误以为一个扩展都没装。
  bool extensionCommandsAvailable = false;
  final List<UiRequest> uiRequests = [];

  /// 扩展状态栏文本（key → 文本）
  final Map<String, String> extensionStatus = {};

  /// 轻提示回调，由界面层挂上
  void Function(String message, {String? type})? onToast;

  bool get isConnected => state == ServerConnectionState.connected;
  bool get isBusy => chat.isRunning;

  // ==================== 连接 ====================

  Future<void> connect(ServerTarget newTarget) async {
    // 先把本机偏好读完：lastSessionId 就存在里面，
    // 不等它读完就读，会拿到空字符串 —— 于是「恢复上次会话」永远不生效（实测踩到）
    await AppPrefs.instance.load();
    await disconnect(silent: true);
    target = newTarget;
    state = ServerConnectionState.connecting;
    errorMessage = null;
    activeEndpoint = null;
    _notify();

    // 逐个试候选地址：主地址连不上就**静默**试备用地址。
    //
    // 不在第一条失败时就报错 —— 那样「出门自动走 VPN」永远不会生效，
    // 用户还是会看到连接错误，只是这次他没法手动救。
    final failures = <String>[];
    ServerClient? client;
    HealthInfo? healthResult;
    ServerEndpoint? connectedVia;
    for (final endpoint in newTarget.candidates) {
      final candidate = ServerClient(
        host: endpoint.host,
        port: endpoint.port,
        token: newTarget.token,
        secure: endpoint.secure,
      );
      try {
        // 5 秒硬超时：这是「探活」不是「干活」。主地址不可达时（出门在外的
        // 常态）必须很快判定失败才能落到备用地址，否则用户得盯着「连接中…」
        // 等满默认的 30 秒 —— 回落就白做了。
        healthResult = await candidate.health(timeout: _probeTimeout);
        client = candidate;
        connectedVia = endpoint;
        break;
      } on ServerException catch (error) {
        await candidate.dispose();
        failures.add('${endpoint.label} — ${error.message}');
      } catch (error) {
        // 兜底：网络层还能抛出别的异常。特别是 TimeoutException ——
        // `_json` 只把 `openUrl` 阶段的超时翻译成了 ServerException，
        // 而 `request.close()` 和读 body 的 `.timeout()` 抛的是 Dart 内置的
        // TimeoutException。不接住它就会冒泡出 connect()，
        // 状态永远停在「连接中」—— 这是实测踩到的现象。
        await candidate.dispose();
        failures.add('${endpoint.label} — $error');
      }
    }

    if (client == null || connectedVia == null || healthResult == null) {
      state = ServerConnectionState.error;
      // 两条都失败时把原因都列出来。只说第一条会让人以为备用地址
      // 根本没被尝试过 —— 其实试了，只是也没通。
      errorMessage = failures.length > 1
          ? failures.map((f) => '· $f').join('\n')
          : (failures.isEmpty ? '没有可用的地址' : failures.first);
      _notify();
      return;
    }

    health = healthResult;
    activeEndpoint = connectedVia;
    _client = client;
    state = ServerConnectionState.connected;
    _reconnectAttempt = 0;
    _notify();
    _bumpSessions();

    // 连上就把后台保活也起来（用户可在设置里关）：
    // 用户点名要的正是「退到后台不断线」—— 只在回前台重连是不够的，
    // 睡着了的那几个小时里 SSE 和卡住定时器都得继续活着。
    if (AppPrefs.instance.keepAlive) {
      unawaited(NativeBridge.startKeepAlive());
    }

    await loadSessions(refresh: true);
    // 命令清单必须在这里先拉一次。
    //
    // 以前只在「打开会话」时才拉，于是没开会话时输入 / 什么命令都看不到 ——
    // 用户报的「命令也显示不完全」就是这个。
    // refreshCommandsIfNeeded 会先试 get_commands（能拿到扩展命令），
    // 拿不到就退回 configCommands（技能 / 模板 / 内置命令）。
    await refreshCommandsIfNeeded();

    // 恢复上次的会话（退到后台被系统杀了进程，重开时不该停在空页面）
    final last = AppPrefs.instance.lastSessionId;
    if (last.isNotEmpty && currentSessionId == null) {
      await openSession(last);
    }
  }

  Future<void> disconnect({bool silent = false}) async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _events?.cancel();
    _events = null;
    await _client?.dispose();
    _client = null;
    health = null;
    currentSessionId = null;
    chat.reset();
    loadingSession = false;
    pendingSession = null;
    uiRequests.clear();
    extensionStatus.clear();
    commands = const [];
    sessions = const [];
    if (!silent) {
      state = ServerConnectionState.disconnected;
      errorMessage = null;
      _notify();
    }
    _bumpSessions();
  }

  // ==================== 输入草稿 ====================
  // ==================== 前后台切换 ====================

  /// 退到后台的时刻（回到前台时用它算「离开了多久」）
  DateTime? _pausedAt;

  /// 离线时的会话列表：拿本地缓存拼出来。
  ///
  /// 为什么必须有：断网时 sessions 是空的，会话列表页会一片空白 ——
  /// 那样「离线可读」等于没做（用户连会话都点不进去）。
  Future<List<ServerSession>> loadOfflineSessions() async {
    final entries = await SessionCache.entries();
    return [
      for (final entry in entries)
        ServerSession(
          id: entry.sessionId,
          cwd: entry.cwd,
          preview: entry.lastText,
          messageCount: entry.messageCount,
          name: entry.name.isEmpty ? null : entry.name,
          modified: entry.savedAt.toIso8601String(),
        ),
    ];
  }

  // ==================== 离线缓存状态 ====================

  /// 界面此刻显示的是缓存吗：非 null 表示「是，缓存于这个时刻」。
  /// 服务端的快照一到就清空 —— 缓存只是垫底的，不能盖住真数据。
  DateTime? cacheShownAt;

  /// 缓存里有多少条消息、因为上限丢掉了多少条老消息（界面要如实说）
  int cacheShownCount = 0;
  int cacheDropped = 0;

  /// 读一次离线缓存铺到界面上。返回是否铺上了。
  Future<bool> _applyCache(String sessionId) async {
    final cached = await SessionCache.load(sessionId);
    if (cached == null || currentSessionId != sessionId) return false;
    chat.messages
      ..clear()
      ..addAll([
        for (var i = 0; i < cached.messages.length; i += 1)
          ChatMessage(
            key: 'c$i',
            role: cached.messages[i].role,
            text: cached.messages[i].text,
            thinking: cached.messages[i].thinking,
            toolName: cached.messages[i].toolName,
            timestamp: cached.messages[i].timestamp,
            isError: cached.messages[i].isError,
          ),
      ]);
    if (cached.name.isNotEmpty) chat.sessionName = cached.name;
    if (cached.cwd.isNotEmpty) chat.cwd = cached.cwd;
    cacheShownAt = cached.savedAt;
    cacheShownCount = cached.messages.length;
    cacheDropped = cached.droppedCount;
    return true;
  }

  void markPaused() {
    _pausedAt = DateTime.now();
    // 顺手记一下：后台期间是否在跑任务（回来要提示「后台跑了多久」）
  }

  /// 回到前台：补连接 + 补列表 + 重新订阅当前会话，并告诉用户「离开期间发生了什么」。
  ///
  /// 为什么要重开一次会话：快照是在订阅时给的，后台期间服务端推的事件我们收不到
  /// （Android 可能冻结进程/断流），所以回来必须重新订阅拿一次完整快照。
  /// 返回一句人话，界面拿它做提示。
  Future<String?> resumeSync() async {
    final pausedAt = _pausedAt;
    _pausedAt = null;
    final away = pausedAt == null ? null : DateTime.now().difference(pausedAt);
    final wasConnected = state == ServerConnectionState.connected;
    final sessionId = currentSessionId;

    int? messageCountOf(String? id) {
      if (id == null) return null;
      for (final session in sessions) {
        if (session.id == id) return session.messageCount;
      }
      return null;
    }

    final before = messageCountOf(sessionId);

    if (!wasConnected) await ensureConnected();
    if (state != ServerConnectionState.connected) {
      return '${I18n.t('ui.23ab4cb7b6')}${errorMessage ?? lastError ?? I18n.t('ui.8027d6f830')}';
    }

    await loadSessions(refresh: true);
    final after = messageCountOf(sessionId);
    final added = (before != null && after != null && after > before) ? after - before : 0;

    // 重新订阅，把离开期间的消息补回界面；
    // 若本来就没有当前会话（例如进程被杀后重开），就恢复上次那条
    final target = sessionId ??
        (AppPrefs.instance.lastSessionId.isEmpty ? null : AppPrefs.instance.lastSessionId);
    if (target != null) await openSession(target);

    final parts = <String>[];
    if (!wasConnected) parts.add(I18n.t('ui.0569d5987b'));
    if (added > 0) parts.add(I18n.tp('ui.bb45590174', {'n': added}));
    if (away != null && away.inSeconds >= 20) {
      parts.add(away.inMinutes >= 1 ? I18n.tp('ui.fe3338e328', {'n': away.inMinutes}) : I18n.tp('ui.ec9f506f82', {'n': away.inSeconds}));
    }
    if (parts.isEmpty) return null;

    final text = parts.join(' · ');
    chat.notice = text;
    _notify();
    // 提示自己消失，别一直挂在输入框上面
    Timer(const Duration(seconds: 8), () {
      if (chat.notice == text) {
        chat.notice = null;
        _notify();
      }
    });
    return text;
  }

  /// 「重试」用：没连上就先用记着的地址再连一次，已连上则直接返回。
  ///
  /// 没有这一步，断线时点「重试」只会再失败一次 —— 因为 store 根本没有客户端。
  Future<void> ensureConnected() async {
    if (state == ServerConnectionState.connected && _client != null) return;
    final t = target;
    if (t == null) return;
    await connect(t);
  }

  /// 输入草稿：按会话 id 存。
  ///
  /// 为什么放在 store 而不是页面 state：页面可能被重建（切 tab、切页、
  /// 系统回收），存在页面里就会丢。只放内存 —— 这是「正在打但还没发」的内容，
  /// 不需要落盘；断线时也不该带着一条旧草稿。
  final Map<String, String> _drafts = {};

  String draftFor(String? sessionId) => _drafts[sessionId ?? ''] ?? '';

  /// 清掉全部草稿，返回清掉几条（设置页「清理本地数据」用）
  int clearDrafts() {
    final count = _drafts.length;
    _drafts.clear();
    return count;
  }

  // ==================== 用量 ====================

  SessionUsage? sessionUsage;
  UsageSummary? usageSummary;
  bool loadingUsage = false;

  /// 拉当前会话的逐轮用量（会话信息面板与用量明细页用）
  Future<void> loadSessionUsage() async {
    final client = _client;
    final id = currentSessionId;
    if (client == null || id == null) return;
    loadingUsage = true;
    _notify();
    try {
      sessionUsage = await client.readSessionUsage(id);
    } on ServerException catch (error) {
      onToast?.call(I18n.tp('ui.d2a6633d48', {'e': error.message}), type: 'error');
    }
    loadingUsage = false;
    _notify();
  }

  /// 本轮改动速览（改了哪些文件、增删多少行）
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

  /// 拉跨会话用量（今天 / 本月 / 按 provider）
  Future<void> loadUsageSummary() async {
    final client = _client;
    if (client == null) return;
    try {
      usageSummary = await client.readUsageSummary();
      _notify();
    } on ServerException catch (error) {
      onToast?.call(I18n.tp('ui.c3f797f056', {'e': error.message}), type: 'error');
    }
  }

  // ==================== pi 侧默认模型（新会话用） ====================

  String? defaultModelProvider;
  String? defaultModelId;

  /// 读 pi 的默认模型（settings.json 里的 defaultProvider/defaultModel）
  Future<void> loadDefaultModel() async {
    final client = _client;
    if (client == null) return;
    try {
      final json = await client.readDefaultModel();
      defaultModelProvider = json['provider'] as String?;
      defaultModelId = json['modelId'] as String?;
      _notify();
    } on ServerException catch (error) {
      onToast?.call(I18n.tp('ui.8210d7f767', {'e': error.message}),
          type: 'error');
    }
  }

  /// 写 pi 的默认模型：只影响**新会话**，当前会话不受影响
  Future<bool> setDefaultModel(String provider, String modelId) async {
    final client = _client;
    if (client == null) {
      lastError = I18n.t('ui.859d589642');
      return false;
    }
    try {
      await client.writeDefaultModel(provider, modelId);
      defaultModelProvider = provider;
      defaultModelId = modelId;
      _notify();
      return true;
    } on ServerException catch (error) {
      lastError = error.message;
      return false;
    }
  }

  void saveDraft(String? sessionId, String text) {
    final key = sessionId ?? '';
    if (text.isEmpty) {
      _drafts.remove(key);
    } else {
      _drafts[key] = text;
    }
  }

  // ==================== 会话列表 ====================

  Future<void> loadSessions({bool refresh = false}) async {
    final client = _client;
    if (client == null) return;
    loadingSessions = true;
    sessionsError = null;
    _notify();
    try {
      sessions = await client.listSessions(refresh: refresh);
      // 待定会话一旦出现在服务端列表里，说明它已经落盘了
      final pending = pendingSession;
      if (pending != null && sessions.any((s) => s.id == pending.id)) {
        pendingSession = null;
      }
    } on ServerException catch (error) {
      sessionsError = error.message;
    } finally {
      loadingSessions = false;
      _notify();
      _bumpSessions();
    }
  }

  /// 打开一条会话：订阅事件流，等快照把消息灌进来
  Future<void> openSession(String sessionId) async {
    final client = _client;

    currentSessionId = sessionId;
    // 记住这条会话：进程被 Android 杀掉后重开，connect 完会自动回到这里
    await AppPrefs.instance.setLastSession(sessionId);
    chat.reset();
    uiRequests.clear();
    loadingSession = true;
    errorMessage = null;

    // 注意：这里**不清** cacheShownAt / cacheShownCount。
    // 清空只发生在「服务端快照真的到了」那一刻（见 _onEvent 的 snapshot 分支）。
    // 否则离线时点一次「重试」，提示条就会闪掉 —— 明明还是离线，界面却不再说。
    // 先把上次的离线缓存铺上（有的话）：
    // 网络慢的时候不用盯着空白页等快照，断网时也还能读上次的内容。
    await _applyCache(sessionId);
    _notify();

    // 连都没有：到此为止，界面留着缓存 + 「离线」提示
    if (client == null) {
      loadingSession = false;
      _notify();
      return;
    }

    // 兜底：15 秒还没等到快照就结束载入态，让界面能提示重试
    _snapshotTimeout?.cancel();
    _snapshotTimeout = Timer(const Duration(seconds: 15), () {
      if (_disposed || currentSessionId != sessionId || !loadingSession) return;
      loadingSession = false;
      errorMessage = I18n.t('ui.435b4754a0');
      _notify();
    });

    // 不 await cancel：旧连接的取消可能要等网络层，
    // 而新的订阅没必要排队等它
    unawaited(_events?.cancel());
    _events = client.events(sessionId).listen(
      _onEvent,
      onError: (Object error) => _onStreamError(error),
      onDone: _onStreamDone,
      cancelOnError: false,
    );
  }

  /// 新建会话并立即打开。成功返回会话 id，失败返回 null（原因在 lastError）。
  Future<String?> createSession(String cwd) async {
    final client = _client;
    if (client == null) {
      lastError = I18n.t('ui.1a5741451f');
      return null;
    }
    if (cwd.trim().isEmpty) {
      lastError = I18n.t('ui.37c4dd9994');
      return null;
    }
    try {
      final id = await client.createSession(cwd);
      lastError = null;
      final now = DateTime.now().toIso8601String();
      pendingSession = ServerSession(
        id: id,
        cwd: cwd,
        preview: '',
        messageCount: 0,
        created: now,
        modified: now,
      );
      await openSession(id);
      _bumpSessions();
      return id;
    } on ServerException catch (error) {
      lastError = error.message;
      onToast?.call(error.message, type: 'error');
      return null;
    }
  }

  /// 删除一条会话。删除后刷新列表；若删的是当前会话则清空对话区。
  /// 拉一次活跃会话总览。
  ///
  /// 为什么是轮询而不是 SSE：池状态（谁在跑、跑了多久）没有事件流，
  /// 服务端只在 /api/pool 上一次性给快照。总览页 3 秒轮一次足够，
  /// 而且拉失败就静默保留上一次的数 —— 它不是关键路径，不该弹错误。
  Future<void> loadPool() async {
    final client = _client;
    if (client == null) return;
    try {
      pool = await client.pool();
      _notify();
    } on ServerException {
      // 静默：总览失败不影响任何操作
    }
  }

  /// 拉一次远程访问状态（连接页进入时拉，不轮询 —— 隧道不会自己变来变去）
  Future<void> loadRemote() async {
    final client = _client;
    if (client == null) return;
    try {
      remote = await client.remoteState();
      _notify();
    } on ServerException {
      // 静默：老版本服务端没有这个接口，不该因此报错
    }
  }

  Future<bool> startRemote() async {
    final client = _client;
    if (client == null) return false;
    remoteBusy = true;
    _notify();
    try {
      remote = await client.startRemote();
      // 隧道要几秒才拿到地址：隔几秒再问一次，别让界面停在「正在建立」
      for (var i = 0; i < 8 && remote.status == 'starting'; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        remote = await client.remoteState();
        _notify();
      }
      return remote.running;
    } on ServerException catch (error) {
      remote = RemoteState(status: 'error', error: error.message);
      return false;
    } finally {
      remoteBusy = false;
      _notify();
    }
  }

  /// 一键断开（合同④）
  Future<void> stopRemote() async {
    final client = _client;
    if (client == null) return;
    remoteBusy = true;
    _notify();
    try {
      remote = await client.stopRemote();
    } on ServerException catch (error) {
      remote = RemoteState(status: 'error', error: error.message);
    } finally {
      remoteBusy = false;
      _notify();
    }
  }

  /// 拉一次磁盘占用（进占用页时才拉，一次要扫 200+ 个文件）
  Future<void> loadDisk() async {
    final client = _client;
    if (client == null) return;
    loadingDisk = true;
    diskError = null;
    _notify();
    try {
      disk = await client.diskUsage();
    } on ServerException catch (error) {
      diskError = error.message;
    } finally {
      loadingDisk = false;
      _notify();
    }
  }

  /// 关闭一条活跃会话（移出池、保留文件）。
  ///
  /// **先本地移除、再和服务器对齐**，而不是只靠 loadPool 刷新：
  ///   · 实测「关闭后等 loadPool 刷新」这一步在真机上不生效 ——
  ///     服务端已经关了（日志与 /api/pool 都证实），界面却仍显示那一条，
  ///     根因未查明（loadPool 有 _notify、页面也有 3 秒轮询）。
  ///   · 而从交互上讲，用户主动关掉的东西**本来就该立刻消失**，
  ///     不该依赖一次网络往返的结果 —— 那属于"乐观更新"，
  ///     哪怕后面发现服务端没关成功，下一轮轮询也会把它拉回来，不至于骗人。
  Future<bool> closeLiveSession(String sessionId) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.closeLiveSession(sessionId);
      pool = pool.where((p) => p.id != sessionId).toList();
      _notify();
      // 再和服务器对齐一次；这一步失败也不影响上面的即时反馈
      await loadPool();
      return true;
    } on ServerException catch (error) {
      lastError = error.message;
      return false;
    }
  }

  Future<bool> deleteSession(String sessionId) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.deleteSession(sessionId);
      if (currentSessionId == sessionId) {
        await _events?.cancel();
        _events = null;
        currentSessionId = null;
        chat.reset();
      }
      if (pendingSession?.id == sessionId) pendingSession = null;
      sessions = sessions.where((s) => s.id != sessionId).toList();
      _notify();
      _bumpSessions();
      // 后台重新扫一遍，保证与服务端一致
      unawaited(loadSessions(refresh: true));
      return true;
    } on ServerException catch (error) {
      lastError = error.message;
      onToast?.call(I18n.tp('ui.e5d81c0a03', {'e': error.message}), type: 'error');
      return false;
    }
  }

  // ==================== 事件流 ====================

  void _onEvent(ServerEvent event) {
    switch (event.name) {
      case 'snapshot':
        {
          final snapshot = SessionSnapshot.fromJson(event.data);
          // 合并 vs 重建：
          //   · 在线重连（消息来自服务端）→ 合并，否则已翻页加载的历史会被冲掉；
          //   · 当前显示的是**离线缓存**→ 必须重建。缓存的 key 是 c0..cN，
          //     快照的 key 是 m0..mN，两边对不上，合并只会把同一段对话叠两遍
          //     （实测踩到：断网看过一次缓存，恢复后消息成对出现）。
          final showingCache = cacheShownAt != null;
          if (currentSessionId == snapshot.sessionId &&
              chat.messages.isNotEmpty &&
              !showingCache) {
            chat.mergeSnapshot(snapshot);
          } else {
            chat.applySnapshot(snapshot);
          }
          loadingSession = false;
          errorMessage = null;
          // 真数据到了：缓存标记退场，界面不再自称「离线」
          cacheShownAt = null;
          cacheShownCount = 0;
          cacheDropped = 0;
          _snapshotTimeout?.cancel();
          _refreshCommands();
          // 落一份离线缓存（不 await：缓存失败不能拖慢界面）
          unawaited(SessionCache.save(
            sessionId: snapshot.sessionId,
            name: chat.sessionName ?? '',
            cwd: chat.cwd,
            messages: chat.messages,
          ));
        }
        break;

      case 'status':
        final phase = event.data['phase'] as String?;
        if (phase == 'error') {
          errorMessage = event.data['message'] as String? ?? I18n.t('ui.74c6f09b91');
        } else if (phase == 'shutdown') {
          chat.notice = I18n.t('ui.0fbd2577cd');
        }
        break;

      default:
        if (event.type == 'extension_ui_request') {
          _onUiRequest(event.data);
        } else if (chat.applyEvent(event)) {
          // 归约器认为界面需要刷新
        } else if (event.type == 'agent_settled') {
          // 一次运行结束，重新拉一遍会话列表（标题/时间会变）
          unawaited(loadSessions(refresh: true));
        }
        break;
    }
    _notify();
  }

  void _onUiRequest(Map<String, dynamic> data) {
    final request = UiRequest.fromJson(data);
    switch (request.method) {
      case 'notify':
        onToast?.call(
          request.message ?? '',
          type: request.notifyType == 'error'
              ? 'error'
              : request.notifyType == 'warning'
                  ? 'warning'
                  : null,
        );
        break;
      case 'setStatus':
        final key = data['statusKey'] as String? ?? '';
        final text = data['statusText'] as String?;
        if (text == null || text.isEmpty) {
          extensionStatus.remove(key);
        } else {
          extensionStatus[key] = text;
        }
        break;
      default:
        if (request.needsResponse) {
          uiRequests.add(request);
        }
        break;
    }
  }

  Future<void> respondUi(String requestId, Map<String, dynamic> response) async {
    final client = _client;
    final sessionId = currentSessionId;
    uiRequests.removeWhere((r) => r.id == requestId);
    _notify();
    if (client == null || sessionId == null) return;
    try {
      await client.respondToUi(sessionId, requestId, response);
    } on ServerException catch (error) {
      onToast?.call(I18n.tp('ui.44a5b4dcf1', {'e': error.message}), type: 'error');
    }
  }

  void _onStreamError(Object error) {
    if (_disposed) return;
    errorMessage = error is ServerException ? error.message : '$error';
    // 关键：出错时必须退出载入态，否则界面会一直卡在「正在载入会话」
    loadingSession = false;
    _snapshotTimeout?.cancel();
    _scheduleReconnect();
    _notify();
  }

  void _onStreamDone() {
    if (_disposed) return;
    // 流正常结束（服务端关闭）也要退出载入态
    loadingSession = false;
    _snapshotTimeout?.cancel();
    _scheduleReconnect();
  }

  /// 事件流断了就重连：重连后会重新收到快照，状态自动重建
  void _scheduleReconnect() {
    final sessionId = currentSessionId;
    if (sessionId == null || _client == null) return;
    if (_reconnectTimer?.isActive ?? false) return;

    _reconnectAttempt += 1;
    if (_reconnectAttempt > 10) {
      errorMessage = I18n.t('ui.fcaecec77a');
      _notify();
      return;
    }

    final delay = Duration(milliseconds: 800 * _reconnectAttempt.clamp(1, 6));
    _reconnectTimer = Timer(delay, () async {
      if (_disposed) return;
      final client = _client;
      if (client == null || currentSessionId != sessionId) return;
      // 必须等旧订阅真正取消完再建新连接，否则上一轮的事件可能串到新会话里
      await _events?.cancel();
      _events = client.events(sessionId).listen(
        _onEvent,
        onError: (Object error) => _onStreamError(error),
        onDone: _onStreamDone,
        cancelOnError: false,
      );
    });
  }

  // ==================== 命令 ====================

  Future<CommandResponse?> runCommand(Map<String, dynamic> command) async {
    final client = _client;
    final sessionId = currentSessionId;
    if (client == null || sessionId == null) return null;
    try {
      final response = await client.command(sessionId, command);
      if (!response.success && response.error != null) {
        onToast?.call(response.error!, type: 'error');
      }
      return response;
    } on ServerException catch (error) {
      onToast?.call(error.message, type: 'error');
      return null;
    }
  }

  /// 发一条消息。返回是否已被接受。
  Future<bool> sendPrompt(
    String text, {
    String? streamingBehavior,
    List<Map<String, dynamic>>? images,
  }) async {
    final trimmed = text.trim();
    // 只有图片没有文字也允许（拍照问一句是常见用法）
    if (trimmed.isEmpty && (images == null || images.isEmpty)) return false;

    // 空态直接发消息：先把会话开出来再发。
    //
    // 为什么必须补这一步：runCommand 在没有 currentSessionId 时直接返回 null，
    // 于是「开始对话」那个输入框（占位文字还在邀请你输入）根本发不出去 ——
    // 用户看到的就是「打完字点发送，什么也没发生」。
    if (currentSessionId == null) {
      // 没开会话时直接发消息：工作区优先用当前会话，其次连接配置里的默认，
      // 最后用 App 设置里的「默认工作区」（本机偏好，跟电脑端配置解耦）
      final cwd = _configCwd.isNotEmpty
          ? _configCwd
          : AppPrefs.instance.defaultCwd;
      if (cwd.isEmpty) {
        lastError = I18n.t('ui.166cc5d6de');
        onToast?.call(lastError!, type: 'error');
        return false;
      }
      final created = await createSession(cwd);
      if (created == null) return false;
    }

    // 乐观上屏：不等服务端回事件，用户立刻看到自己的消息
    final response = await runCommand({
      'id': 'p${DateTime.now().microsecondsSinceEpoch}',
      'type': 'prompt',
      'message': trimmed,
      // pi 侧的 prompt 支持 images：{type:'image', data:<base64>, mimeType:'image/png'}
      if (images != null && images.isNotEmpty) 'images': images,
      'streamingBehavior': ?streamingBehavior,
    });

    if (response == null) return false;

    // 内置命令被拦截：结果不是模型回答，交给界面层展示
    final builtin = response.builtin;
    if (builtin != null) {
      onBuiltinResult?.call(builtin);
      return true;
    }
    return response.success;
  }

  /// 往上翻历史：加载更早的一页
  Future<bool> loadMoreHistory({int limit = 40}) async {
    if (!chat.historyHasMore || chat.historyStart <= 0) return false;
    if (loadingHistory) return false;
    loadingHistory = true;
    _notify();
    try {
      final response = await runCommand({
        'id': 'gh${DateTime.now().microsecondsSinceEpoch}',
        'type': 'get_history',
        'before': chat.historyStart,
        'limit': limit,
      });
      final data = response?.data;
      if (response?.success != true || data == null) return false;
      chat.prependHistory(
        PiMessage.listFromJson(data['messages']),
        (data['start'] as num?)?.toInt() ?? 0,
        data['hasMore'] as bool? ?? false,
      );
      return true;
    } finally {
      loadingHistory = false;
      _notify();
    }
  }

  /// 重命名任意会话（服务端会在必要时临时打开它改名再释放）
  Future<bool> renameSession(String sessionId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      lastError = I18n.t('ui.f1c5acdc4a');
      return false;
    }
    final response = await runCommand({
      'id': 'rn${DateTime.now().microsecondsSinceEpoch}',
      'type': 'rename_session',
      'sessionId': sessionId,
      'name': trimmed,
    });
    if (response?.success != true) {
      lastError = response?.error ?? I18n.t('ui.37ba51a4c6');
      onToast?.call(lastError!, type: 'error');
      return false;
    }
    // 本地立即生效，不等列表重新扫描
    sessions = sessions
        .map((s) => s.id == sessionId ? s.withName(trimmed) : s)
        .toList();
    if (currentSessionId == sessionId) chat.sessionName = trimmed;
    _notify();
    _bumpSessions();
    unawaited(loadSessions(refresh: true));
    return true;
  }

  /// 复制会话为新分支（源会话不变）。成功后刷新列表并切到新会话。
  Future<String?> cloneSession({String? sessionId}) async {
    // runCommand 需要一条“当前会话”作为通道；没有的话先把源会话打开
    if (_client == null) return null;
    if (currentSessionId == null && sessionId != null) await openSession(sessionId);
    if (currentSessionId == null) {
      lastError = I18n.t('ui.e410196151');
      onToast?.call(lastError!, type: 'error');
      return null;
    }

    final response = await runCommand({
      'id': 'cl${DateTime.now().microsecondsSinceEpoch}',
      'type': 'clone_session',
      'sessionId': ?sessionId,
    });
    final newId = response?.data?['sessionId'] as String?;
    if (response?.success != true || newId == null) {
      lastError = response?.error ?? I18n.t('ui.cd2f6e9c3f');
      onToast?.call(lastError!, type: 'error');
      return null;
    }
    await loadSessions(refresh: true);
    await openSession(newId);
    return newId;
  }

  /// 取会话分支树（只读浏览用）
  Future<Map<String, dynamic>?> fetchTree() async {
    final response = await runCommand({
      'id': 'gt${DateTime.now().microsecondsSinceEpoch}',
      'type': 'get_tree',
    });
    return response?.success == true ? response!.data : null;
  }

  /// 从某条历史消息分出一条新会话。
  ///
  /// 服务端两步完成：复制完整历史 → 把新会话的叶子回退到该节点。
  /// 成功后刷新列表并切到新会话。
  Future<String?> forkFromMessage(String entryId) async {
    final response = await runCommand({
      'id': 'fk${DateTime.now().microsecondsSinceEpoch}',
      'type': 'fork_from_message',
      'entryId': entryId,
    });
    final newId = response?.data?['sessionId'] as String?;
    if (response?.success != true || newId == null) {
      lastError = response?.error ?? I18n.t('ui.fd86967e02');
      onToast?.call(lastError!, type: 'error');
      return null;
    }
    await loadSessions(refresh: true);
    await openSession(newId);
    return newId;
  }

  /// pi 在切分支/分叉时会回传 `editorText`（被切走的那条用户消息）。
  /// CLI 里它会被放回输入框；App 侧由界面消费这个值，用完置空。
  String? pendingEditorText;

  /// 会话内切换分支。
  ///
  /// navigateTree 会改掉模型上下文，所以成功后重新拉一次快照，
  /// 让消息列表跟着新分支重建。
  ///
  /// [summarize] = true 时同时把「被舍弃的那条分支」压缩成一段摘要带进新上下文
  /// （pi 的 navigateTree({summarize:true})，走的是模型，所以会明显慢一些）。
  Future<bool> navigateTree(String targetId, {bool summarize = false}) async {
    final response = await runCommand({
      'id': 'nt${DateTime.now().microsecondsSinceEpoch}',
      'type': 'navigate_tree',
      'targetId': targetId,
      'summarize': summarize,
    });
    if (response?.success != true) {
      lastError = response?.error ?? I18n.t('ui.5b9eb774d9');
      onToast?.call(lastError!, type: 'error');
      return false;
    }
    if (response!.data?['cancelled'] == true) return false;
    // 记住被切走的用户消息，界面会把它放回输入框（pi 的 editorText 语义）
    final editorText = response.data?['editorText'];
    pendingEditorText = editorText is String && editorText.trim().isNotEmpty ? editorText : null;
    final sessionId = currentSessionId;
    if (sessionId != null) await openSession(sessionId);
    return true;
  }

  // ==================== 文件与 Git ====================

  /// 取原始字节（图片 / PDF 预览）
  Future<RawFileData?> rawFile(String path) async {
    final client = _client;
    if (client == null) return null;
    try {
      return await client.rawFile(path);
    } on ServerException catch (error) {
      onToast?.call(I18n.tp('ui.c621e5e25b', {'e': error.message}), type: 'error');
      return null;
    }
  }

  /// 上一次上传成功的绝对路径（手机端选完文件后要把路径写回输入框，
  /// 告诉 pi “看这个文件”）
  String? lastUploadedPath;

  /// 上传一份字节到工作区（手机上选的文件）
  Future<bool> uploadFile({
    required String dir,
    required String name,
    required List<int> bytes,
    bool overwrite = false,
  }) async {
    final client = _client;
    if (client == null) return false;
    try {
      final result = await client.uploadFile(
        dir: dir,
        name: name,
        base64: base64Encode(bytes),
        overwrite: overwrite,
      );
      final size = result['size'];
      lastUploadedPath = result['path'] as String?;
      onToast?.call(I18n.tp('ui.78b07cb72a', {'n': name, 's': size ?? bytes.length}), type: 'success');
      return true;
    } on ServerException catch (error) {
      onToast?.call(I18n.tp('ui.384e5130bb', {'e': error.message}), type: 'error');
      return false;
    }
  }

  // ==================== git worktree ====================

  Future<List<WorktreeInfo>> worktrees(String cwd) async {
    final client = _client;
    if (client == null) return const [];
    try {
      final json = await client.listWorktrees(cwd);
      return (json['worktrees'] as List?)
              ?.whereType<Map>()
              .map((e) => WorktreeInfo.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          const [];
    } on ServerException catch (error) {
      onToast?.call(error.message, type: 'error');
      return const [];
    }
  }

  Future<bool> addWorktree({
    required String cwd,
    required String dir,
    String? branch,
  }) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.addWorktree(cwd: cwd, dir: dir, branch: branch);
      onToast?.call(I18n.t('ui.f8e34f3543'), type: 'success');
      return true;
    } on ServerException catch (error) {
      onToast?.call(I18n.tp('ui.106406ad4d', {'e': error.message}), type: 'error');
      return false;
    }
  }

  Future<bool> removeWorktree(String cwd, String dir, {bool force = false}) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.removeWorktree(cwd: cwd, dir: dir, force: force);
      onToast?.call(I18n.t('ui.3e6c4f97df'), type: 'success');
      return true;
    } on ServerException catch (error) {
      onToast?.call(I18n.tp('ui.e5d81c0a03', {'e': error.message}), type: 'error');
      return false;
    }
  }

  // ==================== pi 包（插件）====================

  /// 已装插件 + 可更新列表
  Future<(List<PiPackageInfo>, List<PackageUpdateInfo>, String?)> packages() async {
    final client = _client;
    if (client == null) return (const <PiPackageInfo>[], const <PackageUpdateInfo>[], null);
    try {
      final json = await client.listPackages(_configCwd);
      final list = (json['packages'] as List?)
              ?.whereType<Map>()
              .map((e) => PiPackageInfo.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          const <PiPackageInfo>[];
      final updates = (json['updates'] as List?)
              ?.whereType<Map>()
              .map((e) => PackageUpdateInfo.fromJson(e.cast<String, dynamic>()))
              .toList() ??
          const <PackageUpdateInfo>[];
      return (list, updates, json['updateError'] as String?);
    } on ServerException catch (error) {
      onToast?.call(error.message, type: 'error');
      return (const <PiPackageInfo>[], const <PackageUpdateInfo>[], null);
    }
  }

  /// 装 / 卸 / 更新插件。装和更新会联网，慢是正常的。
  Future<bool> runPackageAction({
    required String action,
    String? source,
    bool local = false,
  }) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.packageAction(action: action, source: source, local: local, cwd: _configCwd);
      onToast?.call(
        switch (action) {
          'install' => I18n.tp('ui.53ff7b7c01', {'s': source}),
          'remove' => I18n.tp('ui.9e1bfdc29d', {'s': source}),
          _ => I18n.t('ui.56a851859a'),
        },
        type: 'success',
      );
      return true;
    } on ServerException catch (error) {
      onToast?.call(I18n.tp('ui.274b2eafab', {'a': action, 'e': error.message}), type: 'error');
      return false;
    }
  }

  /// 列目录（path 为空时用服务端默认根）
  Future<DirListing?> listFiles({String? path}) async {
    final client = _client;
    if (client == null) return null;
    try {
      return await client.listFiles(path: path);
    } on ServerException catch (error) {
      onToast?.call(error.message, type: 'error');
      return null;
    }
  }

  Future<FileText?> readFile(String path) async {
    final client = _client;
    if (client == null) return null;
    try {
      return await client.readFile(path);
    } on ServerException catch (error) {
      onToast?.call(I18n.tp('ui.f55e153cb5', {'e': error.message}), type: 'error');
      return null;
    }
  }

  Future<GitStatusInfo?> gitStatus(String cwd) async {
    final client = _client;
    if (client == null) return null;
    try {
      return await client.gitStatus(cwd);
    } on ServerException catch (error) {
      onToast?.call(I18n.tp('ui.5e541876ac', {'e': error.message}), type: 'error');
      return null;
    }
  }

  Future<GitDiffInfo?> gitDiff(String cwd, {String? path}) async {
    final client = _client;
    if (client == null) return null;
    try {
      return await client.gitDiff(cwd, path: path);
    } on ServerException catch (error) {
      onToast?.call(I18n.tp('ui.151f0ad89b', {'e': error.message}), type: 'error');
      return null;
    }
  }

  /// @ 引用候选（用当前会话的工作区）
  Future<List<FileRef>> fileRefs(String query) async {
    final client = _client;
    final cwd = chat.cwd.isNotEmpty ? chat.cwd : (target?.defaultCwd ?? '');
    if (client == null || cwd.isEmpty) return const [];
    try {
      return await client.fileIndex(cwd, query);
    } on ServerException {
      return const [];
    }
  }

  // ==================== MCP 服务器 ====================

  /// 新增/覆盖一条 MCP 配置（写服务端的 mcp.json）
  Future<bool> saveMcpServer({
    required String name,
    required String scope,
    required Map<String, dynamic> config,
  }) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.upsertMcp(name: name, scope: scope, config: config, cwd: _configCwd);
      onToast?.call(I18n.tp('ui.68e0c6d05e', {'n': name}), type: 'success');
      return true;
    } on ServerException catch (error) {
      onToast?.call(error.message, type: 'error');
      return false;
    }
  }

  Future<bool> removeMcpServer(String name, {required String scope}) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.removeMcp(name, scope: scope, cwd: _configCwd);
      onToast?.call(I18n.tp('ui.24fa0cd945', {'n': name}), type: 'success');
      return true;
    } on ServerException catch (error) {
      onToast?.call(I18n.tp('ui.e5d81c0a03', {'e': error.message}), type: 'error');
      return false;
    }
  }

  Future<bool> setMcpServerEnabled(String name,
      {required String scope, required bool enabled}) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.setMcpEnabled(name, scope: scope, enabled: enabled, cwd: _configCwd);
      return true;
    } on ServerException catch (error) {
      onToast?.call(error.message, type: 'error');
      return false;
    }
  }

  // ==================== Provider 登录 ====================

  Future<List<ProviderInfo>> providers() async {
    final client = _client;
    if (client == null) return const [];
    try {
      return await client.listProviders();
    } on ServerException catch (error) {
      onToast?.call(error.message, type: 'error');
      return const [];
    }
  }

  /// 起登录；失败返回 null
  Future<String?> beginLogin(String provider, String type) async {
    final client = _client;
    if (client == null) return null;
    try {
      return await client.startLogin(provider, type);
    } on ServerException catch (error) {
      onToast?.call(I18n.tp('ui.6076ca52e7', {'e': error.message}), type: 'error');
      return null;
    }
  }

  Future<LoginStatus?> pollLogin(String taskId) async {
    final client = _client;
    if (client == null) return null;
    try {
      return await client.loginStatus(taskId);
    } on ServerException {
      return null;
    }
  }

  Future<bool> answerLogin(String taskId, String answer) async {
    final client = _client;
    if (client == null) return false;
    try {
      return await client.answerLogin(taskId, answer);
    } on ServerException catch (error) {
      onToast?.call(error.message, type: 'error');
      return false;
    }
  }

  Future<void> cancelLogin(String taskId) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.cancelLogin(taskId);
    } on ServerException {
      // 取消失败无所谓：任务最终会因为 abort 自己结束
    }
  }

  Future<bool> logoutProvider(String provider) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.logoutProvider(provider);
      onToast?.call(I18n.tp('ui.ae61e7d374', {'p': provider}), type: 'success');
      return true;
    } on ServerException catch (error) {
      onToast?.call(I18n.tp('ui.ffbd30b3e8', {'e': error.message}), type: 'error');
      return false;
    }
  }

  /// MCP 服务器列表（只读，读 ~/.pi/agent/mcp.json 与项目 .pi/mcp.json）
  Future<List<McpServerInfo>> mcpServers() async {
    final client = _client;
    final cwd = chat.cwd.isNotEmpty ? chat.cwd : (target?.defaultCwd ?? '');
    if (client == null) return const [];
    try {
      return await client.listMcp(cwd);
    } on ServerException {
      return const [];
    }
  }

  /// 按来源筛命令：builtin / extension / prompt / skill
  List<SlashCommand> commandsBySource(String source) =>
      commands.where((c) => c.source == source).toList();

  /// 命令列表还没有（或只有会话无关的那部分）时补一次。
  /// 配置页在没有打开任何会话时也调它。
  Future<void> refreshCommandsIfNeeded() async {
    if (commands.isNotEmpty && extensionCommandsAvailable) return;
    await _refreshCommands();
  }

  // ==================== Provider 凭据 ====================

  /// 已配置凭据清单（不含密钥本体）
  Future<List<CredentialInfo>> credentials() async {
    final client = _client;
    if (client == null) return const [];
    try {
      return await client.listCredentials();
    } on ServerException catch (error) {
      onToast?.call(error.message, type: 'error');
      return const [];
    }
  }

  /// 写入 API Key（会真实写进 pi 的凭据库）
  Future<bool> setApiKey(String provider, String apiKey) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.setApiKey(provider, apiKey);
      onToast?.call(I18n.tp('ui.a234cc694b', {'p': provider}), type: 'success');
      return true;
    } on ServerException catch (error) {
      onToast?.call(I18n.tp('ui.e1ecbe92e3', {'e': error.message}), type: 'error');
      return false;
    }
  }

  /// 删除某个 provider 的凭据
  Future<bool> removeApiKey(String provider) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.removeApiKey(provider);
      onToast?.call(I18n.tp('ui.8ec238cd15', {'p': provider}), type: 'success');
      return true;
    } on ServerException catch (error) {
      onToast?.call(I18n.tp('ui.e5d81c0a03', {'e': error.message}), type: 'error');
      return false;
    }
  }

  /// 会话统计（`get_session_stats`）：tokens / 花费 / 上下文占用
  Future<SessionStats?> sessionStats() async {
    final response = await runCommand({
      'id': 'st${DateTime.now().microsecondsSinceEpoch}',
      'type': 'get_session_stats',
    });
    final data = response?.data;
    if (response?.success != true || data == null) return null;
    return SessionStats.fromJson(data);
  }

  /// 会话导出：Markdown 文本（App 内预览）
  Future<ExportMarkdown?> exportMarkdownText() async {
    final client = _client;
    final sessionId = currentSessionId;
    if (client == null || sessionId == null) return null;
    try {
      return await client.exportMarkdown(sessionId);
    } on ServerException catch (error) {
      onToast?.call(error.message, type: 'error');
      return null;
    }
  }

  /// 会话导出：写到服务端磁盘（HTML + JSONL）
  Future<Map<String, String>?> exportFilesToServer() async {
    final client = _client;
    final sessionId = currentSessionId;
    if (client == null || sessionId == null) return null;
    try {
      return await client.exportToServer(sessionId);
    } on ServerException catch (error) {
      onToast?.call(I18n.tp('ui.eb0814d40c', {'e': error.message}), type: 'error');
      return null;
    }
  }

  /// 内置命令的返回结果回调（选择器、提示文本等）
  void Function(Map<String, dynamic> builtin)? onBuiltinResult;

  Future<void> abort() async {
    await runCommand({'id': 'a${DateTime.now().microsecondsSinceEpoch}', 'type': 'abort'});
  }

  Future<void> compact({String? instructions}) async {
    await runCommand({
      'id': 'c${DateTime.now().microsecondsSinceEpoch}',
      'type': 'compact',
      if (instructions != null && instructions.isNotEmpty) 'instructions': instructions,
    });
  }

  Future<bool> setModel(String provider, String modelId) async {
    final response = await runCommand({
      'id': 'sm${DateTime.now().microsecondsSinceEpoch}',
      'type': 'set_model',
      'provider': provider,
      'modelId': modelId,
    });
    // 服务端改完就回传新模型，本地同步一下 ——
    // 否则界面会一直显示旧模型（实测切成功了但界面不变）
    final data = response?.data;
    if (response?.success == true && data != null) {
      chat.model = ModelInfo.fromJson(data);
      _notify();
      return true;
    }
    // 失败要把原因说出来（常见：该 provider 没凭据、模型不存在），
    // 而不是「点了没反应」
    lastError = response == null
        ? I18n.t('ui.c0e94b1077')
        : (response.error ?? I18n.t('ui.929511ecf0'));
    return false;
  }

  Future<bool> setThinkingLevel(String level) async {
    final response = await runCommand({
      'id': 'st${DateTime.now().microsecondsSinceEpoch}',
      'type': 'set_thinking_level',
      'level': level,
    });
    if (response?.success == true) {
      chat.thinkingLevel = (response!.data?['level'] as String?) ?? level;
      _notify();
      return true;
    }
    lastError = response == null
        ? I18n.t('ui.4eb6435474')
        : (response.error ?? I18n.t('ui.0867017254'));
    return false;
  }

  Future<void> setSessionName(String name) async {
    final response = await runCommand({
      'id': 'sn${DateTime.now().microsecondsSinceEpoch}',
      'type': 'set_session_name',
      'name': name,
    });
    if (response?.success == true) {
      chat.sessionName = name;
      _notify();
    }
  }

  /// 会话无关的配置用 cwd（没打开会话时用默认工作区）
  String get _configCwd => chat.cwd.isNotEmpty ? chat.cwd : (target?.defaultCwd ?? '');

  Future<List<ModelInfo>> availableModels() async {
    final response = await runCommand({
      'id': 'am${DateTime.now().microsecondsSinceEpoch}',
      'type': 'get_available_models',
    });
    final list = response?.data?['models'];
    if (list is List && list.isNotEmpty) {
      return list
          .whereType<Map>()
          .map((item) => ModelInfo.fromJson(item.cast<String, dynamic>()))
          .toList();
    }
    // 没打开会话（runCommand 没有通道）时退到会话无关接口 —— 否则配置页是空的
    final client = _client;
    if (client == null) return const [];
    try {
      return await client.configModels(_configCwd);
    } on ServerException {
      return const [];
    }
  }

  Future<List<String>> availableThinkingLevels() async {
    final response = await runCommand({
      'id': 'atl${DateTime.now().microsecondsSinceEpoch}',
      'type': 'get_available_thinking_levels',
    });
    final list = response?.data?['levels'];
    if (list is List && list.isNotEmpty) return list.whereType<String>().toList();

    final client = _client;
    if (client == null) return const [];
    try {
      final (levels, _, _) = await client.configThinkingLevels(
        _configCwd,
        chat.model?.provider,
        chat.model?.id,
      );
      return levels;
    } on ServerException {
      return const [];
    }
  }

  Future<void> _refreshCommands() async {
    final response = await runCommand({
      'id': 'gc${DateTime.now().microsecondsSinceEpoch}',
      'type': 'get_commands',
    });
    final list = response?.data?['commands'];
    if (list is List && list.isNotEmpty) {
      commands = list
          .whereType<Map>()
          .map((item) => SlashCommand.fromJson(item.cast<String, dynamic>()))
          .toList();
      extensionCommandsAvailable = true;
      _notify();
      return;
    }

    // 没打开会话：退到会话无关接口（只能给出技能 / 模板 / 内置命令，
    // 扩展命令需要 ExtensionRunner，必须由会话启动时才注册）。
    final client = _client;
    if (client == null) return;
    try {
      commands = await client.configCommands(_configCwd);
      extensionCommandsAvailable = false;
      _notify();
    } on ServerException {
      // 保持原样，等下一次刷新
    }
  }

  /// 通知界面。
  ///
  /// 防重入：监听回调里如果再调一个「会立刻 _notify()」的 store 方法，
  /// 同步递归会一路把主线程堆栈吃光（实测 512 层栈 + 113% CPU + ANR）。
  /// 这里把重入的那次通知压成微任务补发 —— 语义上「状态变了要通知」仍然成立，
  /// 但不会在同一个调用栈里嵌套下去。
  bool _notifying = false;
  bool _notifyPending = false;

  void _notify() {
    if (_disposed) return;
    if (_notifying) {
      _notifyPending = true;
      return;
    }
    _notifying = true;
    try {
      notifyListeners();
    } finally {
      _notifying = false;
    }
    if (_notifyPending && !_disposed) {
      _notifyPending = false;
      scheduleMicrotask(_notify);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _snapshotTimeout?.cancel();
    unawaited(_events?.cancel());
    unawaited(_client?.dispose());
    sessionsRevision.dispose();
    super.dispose();
  }
}
