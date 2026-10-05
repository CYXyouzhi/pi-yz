# task-13 会话列表页接线：断网时用本地缓存会话列表，点进去仍能读正文。
#
# 为什么必须在列表页做：只做「聊天页显示缓存」是不够的 ——
# 断网后列表页一片空白，用户根本点不进任何会话，缓存等于没写。

from pathlib import Path

p = Path('lib/ui/server/sessions_page.dart')
s = p.read_text(encoding='utf-8')

# ---- 1) 状态 ----
old_state = """  /// 会话搜索词（本地过滤，244 条已在内存，不需要服务端接口）
  String _query = '';"""
new_state = """  /// 离线缓存里的会话（contract①：断网也要能点进会话读正文）
  List<ServerSession> _offline = const [];
  bool _offlineRequested = false;

  /// 会话搜索词（本地过滤，244 条已在内存，不需要服务端接口）
  String _query = '';"""
assert s.count(old_state) == 1, '状态锚点'
s = s.replace(old_state, new_state)

# ---- 2) 离线加载方法 ----
old_dispose = """  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }"""
new_dispose = """  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 列表为空时补一次离线缓存（失败不报错：没缓存就是没缓存）
  void _ensureOfflineLoaded() {
    if (_offlineRequested || _store.sessions.isNotEmpty) return;
    _offlineRequested = true;
    _store.loadOfflineSessions().then((list) {
      if (!mounted) return;
      setState(() => _offline = list);
    });
  }"""
assert s.count(old_dispose) == 1, 'dispose 锚点'
s = s.replace(old_dispose, new_dispose)

# ---- 3) 数据源切换到离线列表 ----
old_rows = """  List<_Row> _buildRows() {
    final rows = <_Row>[
      const _ConnRow(),
      const _NewSessionRow(),
    ];"""
new_rows = """  List<_Row> _buildRows() {
    // 有在线数据就用在线数据；没有就拿本地缓存顶上（并在顶部说明这是缓存）
    final source = _store.sessions.isNotEmpty ? _store.sessions : _offline;
    final rows = <_Row>[
      const _ConnRow(),
      const _NewSessionRow(),
      if (_store.sessions.isEmpty && source.isNotEmpty)
        _SectionRow('离线缓存（${source.length} 条 · 断网也能读正文）'),
    ];"""
assert s.count(old_rows) == 1, 'rows 锚点'
s = s.replace(old_rows, new_rows)

# 空判断与两处遍历都改成 source
old_empty = """    if (_store.sessions.isEmpty) {
      rows.add(const _EmptyRow());
      return rows;
    }"""
new_empty = """    if (source.isEmpty) {
      rows.add(const _EmptyRow());
      return rows;
    }"""
assert s.count(old_empty) == 1, '空判断锚点'
s = s.replace(old_empty, new_empty)

count_loop = s.count("for (final session in _store.sessions) {")
assert count_loop >= 1, '会话遍历锚点'
s = s.replace("for (final session in _store.sessions) {", "for (final session in source) {")

# ---- 4) build 里补一次离线加载，并在恢复在线后允许重读 ----
old_build = """      builder: (context, value, child) {
        final rows = _buildRows();"""
new_build = """      builder: (context, value, child) {
        if (_store.sessions.isNotEmpty) {
          // 回到在线：允许下次断网时重新从缓存读（缓存是会更新的）
          _offlineRequested = false;
        } else {
          _ensureOfflineLoaded();
        }
        final rows = _buildRows();"""
assert s.count(old_build) == 1, 'build 锚点'
s = s.replace(old_build, new_build)

p.write_text(s, encoding='utf-8')
print(f'sessions_page 已接上离线会话列表（遍历替换 {count_loop} 处）')
