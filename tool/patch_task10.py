import io

# ---------- 1) ServerStore：暂停/恢复同步 ----------
p = 'lib/server/server_store.dart'
s = io.open(p, encoding='utf-8').read()
if 'resumeSync' not in s:
    anchor = "  /// 「重试」用：没连上就先用记着的地址再连一次，已连上则直接返回。"
    add = '''  // ==================== 前后台切换 ====================

  /// 退到后台的时刻（回到前台时用它算「离开了多久」）
  DateTime? _pausedAt;

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
      return '没连上：${errorMessage ?? lastError ?? '原因未知'}';
    }

    await loadSessions(refresh: true);
    final after = messageCountOf(sessionId);
    final added = (before != null && after != null && after > before) ? after - before : 0;

    // 重新订阅，把离开期间的消息补回界面
    if (sessionId != null) await openSession(sessionId);

    final parts = <String>[];
    if (!wasConnected) parts.add('已自动重连');
    if (added > 0) parts.add('离开期间新增 $added 条');
    if (away != null && away.inSeconds >= 20) {
      parts.add(away.inMinutes >= 1 ? '离开了 ${away.inMinutes} 分钟' : '离开了 ${away.inSeconds} 秒');
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

'''
    assert anchor in s
    s = s.replace(anchor, add + anchor, 1)
    io.open(p, 'w', encoding='utf-8').write(s)
    print('server_store: 已加 resumeSync / markPaused')

# ---------- 2) main.dart：监听前后台 ----------
p = 'lib/main.dart'
s = io.open(p, encoding='utf-8').read()
if 'didChangeAppLifecycleState' not in s:
    old = """class _AppShellState extends State<AppShell> {"""
    new = """class _AppShellState extends State<AppShell> with WidgetsBindingObserver {"""
    assert old in s
    s = s.replace(old, new, 1)

    # 在 AppShell 的 initState 里注册观察者（先找到它的 initState）
    import re
    m = re.search(r"class _AppShellState extends State<AppShell> with WidgetsBindingObserver \{\n((?:.|\n)*?)  @override\n  void initState\(\) \{\n", s)
    assert m, '找不到 AppShell 的 initState'
    insert_at = m.end()
    s = s[:insert_at] + "    WidgetsBinding.instance.addObserver(this);\n" + s[insert_at:]

    # 找到 AppShell 的 dispose 并注销观察者
    m = re.search(r"(class _AppShellState extends State<AppShell> with WidgetsBindingObserver \{(?:.|\n)*?)\n  @override\n  void dispose\(\) \{\n", s)
    assert m, '找不到 AppShell 的 dispose'
    insert_at = m.end()
    s = s[:insert_at] + "    WidgetsBinding.instance.removeObserver(this);\n" + s[insert_at:]

    # 追加 didChangeAppLifecycleState（放在 _page() 之前）
    anchor = "  List<Widget> _pages() => ["
    assert anchor in s
    lifecycle = '''  /// 前后台切换：退后台记时间，回前台补连接 + 补消息 + 告诉用户离开了多久。
  ///
  /// Android 的现实（写清楚，别装作没有）：
  ///   · 普通 App 退到后台会被「冻结」（Doze/App Standby），网络与定时器可能被掐；
  ///   · 想让长任务在后台真的继续跑，必须有**前台服务**（通知栏常驻）——
  ///     那需要一个原生插件，放在任务⑪（通知）里做；
  ///   · 所以这一版保证的是：**回来不用手动重连、消息自动补齐、说话算数**。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final store = _serverStore;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        store.markPaused();
      case AppLifecycleState.resumed:
        store.resumeSync();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

'''
    s = s.replace(anchor, lifecycle + anchor, 1)
    io.open(p, 'w', encoding='utf-8').write(s)
    print('main.dart: 已加前后台监听')
