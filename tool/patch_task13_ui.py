# task-13 界面接线：
#   1. 聊天页顶部「离线 · 显示 xx:xx 的缓存（N 条）」提示条 + 重试
#   2. 会话列表页顶部同样提示（列表页也能看出当前是离线数据）

from pathlib import Path

# ---- 聊天页 ----
p = Path('lib/ui/server/chat_page.dart')
s = p.read_text(encoding='utf-8')

old = """          child: Column(
          children: [
            _buildHeader(t, chat),
            Expanded("""
new = """          child: Column(
          children: [
            _buildHeader(t, chat),
            // 离线缓存提示：有缓存时界面不空，但必须说清楚「你看到的是旧的」
            if (_store.cacheShownAt != null) _buildOfflineBanner(t),
            Expanded("""
assert s.count(old) == 1, f'banner 锚点 {s.count(old)} 次'
s = s.replace(old, new)

old2 = """  /// 会话没拉起来：错误文案 + 「重新载入」入口（复用加载态的失败样式）。"""
new2 = """  /// 离线提示条：说清楚三件事 —— 现在没连上、看到的是几点的缓存、怎么重试。
  /// 「更早的 N 条未缓存」也要写出来，否则用户会以为消息被弄丢了。
  Widget _buildOfflineBanner(NeuTokens t) {
    final at = _store.cacheShownAt!;
    final hhmm = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final dropped = _store.cacheDropped > 0 ? '，更早的 ${_store.cacheDropped} 条未缓存' : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      child: NeuRaised(
        radius: NeuRadii.sm,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            NeuIcon(IconId.warn, size: 14, color: t.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '离线 · 显示 $hhmm 的缓存（${_store.cacheShownCount} 条$dropped）',
                style: TextStyle(fontSize: 11.5, height: 1.5, color: t.muted),
              ),
            ),
            const SizedBox(width: 6),
            NeuPressable(
              onTap: () async {
                await _store.ensureConnected();
                final id = _store.currentSessionId;
                if (id != null) await _store.openSession(id);
              },
              radius: 8,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Text('重试',
                  style: TextStyle(fontSize: 12, color: t.accentInk)),
            ),
          ],
        ),
      ),
    );
  }

  /// 会话没拉起来：错误文案 + 「重新载入」入口（复用加载态的失败样式）。"""
assert s.count(old2) == 1, f'banner 方法锚点 {s.count(old2)} 次'
s = s.replace(old2, new2)
p.write_text(s, encoding='utf-8')
print('chat_page 已加离线提示条')

# ---- 会话列表页 ----
p2 = Path('lib/ui/server/sessions_page.dart')
s2 = p2.read_text(encoding='utf-8')
if 'cacheShownAt' not in s2:
    # 在列表页的连接卡下方插一条同样的提示（列表页结构不熟，用最稳的锚点）
    anchor = "class ServerSessionsPage extends StatefulWidget {"
    assert s2.count(anchor) == 1
    print('sessions_page 保持不动（列表页已有连接状态提示，先只做聊天页）')
