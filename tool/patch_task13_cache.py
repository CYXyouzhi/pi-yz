# 把「离线缓存」接进 ServerStore：
#   1. 打开会话时先把上次的缓存铺上（网络慢/不通也能读到内容）
#   2. 快照到达后写缓存，并清掉「正在看缓存」的标记
#   3. 连接都没有时（真正离线）也要显示缓存，而不是空白页

from pathlib import Path

p = Path('lib/server/server_store.dart')
s = p.read_text(encoding='utf-8')

# ---- 1) import ----
old = "import 'chat_reducer.dart';"
new = "import 'chat_reducer.dart';\nimport 'session_cache.dart';"
assert s.count(old) == 1
s = s.replace(old, new)

# ---- 2) 状态字段：加在 _pausedAt 附近 ----
old = """  /// 退到后台的时刻（回到前台时用它算「离开了多久」）
  DateTime? _pausedAt;"""
new = """  /// 退到后台的时刻（回到前台时用它算「离开了多久」）
  DateTime? _pausedAt;

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
  }"""
assert s.count(old) == 1, s.count(old)
s = s.replace(old, new)

# ---- 3) openSession：先把缓存铺上 ----
old = """  Future<void> openSession(String sessionId) async {
    final client = _client;
    if (client == null) return;

    currentSessionId = sessionId;
    // 记住这条会话：进程被 Android 杀掉后重开，connect 完会自动回到这里
    AppPrefs.instance.setLastSession(sessionId);
    chat.reset();
    uiRequests.clear();
    loadingSession = true;
    errorMessage = null;
    _notify();"""
new = """  Future<void> openSession(String sessionId) async {
    final client = _client;

    currentSessionId = sessionId;
    // 记住这条会话：进程被 Android 杀掉后重开，connect 完会自动回到这里
    AppPrefs.instance.setLastSession(sessionId);
    chat.reset();
    uiRequests.clear();
    loadingSession = true;
    errorMessage = null;
    cacheShownAt = null;
    cacheShownCount = 0;
    cacheDropped = 0;

    // 先把上次的离线缓存铺上（有的话）：
    // 网络慢的时候不用盯着空白页等快照，断网时也还能读上次的内容。
    await _applyCache(sessionId);
    _notify();

    // 连都没有：到此为止，界面留着缓存 + 「离线」提示
    if (client == null) {
      loadingSession = false;
      _notify();
      return;
    }"""
assert s.count(old) == 1, s.count(old)
s = s.replace(old, new)

# ---- 4) 快照到达：清缓存标记 + 写缓存 ----
old = """          loadingSession = false;
          errorMessage = null;
          _snapshotTimeout?.cancel();
          _refreshCommands();
        }
        break;"""
new = """          loadingSession = false;
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
        break;"""
assert s.count(old) == 1, s.count(old)
s = s.replace(old, new)

p.write_text(s, encoding='utf-8')
print('server_store 已接上离线缓存')
