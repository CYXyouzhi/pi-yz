# task-13 设置页接线（设置页是 StatelessWidget，所以借一个 ValueNotifier 触发缓存区重读）：
#   1. 「本地数据与日志」区显示离线缓存占用与上限，并给单独清理入口（合同②）
#   2. 「清理本地数据」也要把离线缓存一起清掉（否则用户以为清干净了）

from pathlib import Path

p = Path('lib/ui/server/settings_page.dart')
s = p.read_text(encoding='utf-8')

# ---- import ----
old_imp = "import '../../server/notification_center.dart';"
assert s.count(old_imp) == 1, 'import 锚点'
s = s.replace(old_imp, old_imp + "\nimport '../../server/session_cache.dart';")

# ---- 重载信号 ----
old_top = "class ServerSettingsPage extends StatelessWidget {"
assert s.count(old_top) == 1, '类锚点'
s = s.replace(
    old_top,
    "/// 清空离线缓存后自增，让缓存区重读一次（设置页本身是无状态的）\n"
    "final ValueNotifier<int> cacheTick = ValueNotifier<int>(0);\n\n" + old_top,
)

# ---- UI ----
old_ui = "                    _prefLabel(t, I18n.t('settings.localData', context: context)),"
assert s.count(old_ui) == 1, '本地数据标签锚点'

new_ui = """                    _prefLabel(t, '离线缓存（断网时还能读的最近会话）'),
                    ValueListenableBuilder<int>(
                      valueListenable: cacheTick,
                      builder: (context, tick, _) => FutureBuilder<List<CacheEntry>>(
                        key: ValueKey<int>(tick),
                        future: SessionCache.entries(),
                        builder: (context, snapshot) {
                          final list = snapshot.data ?? const <CacheEntry>[];
                          final bytes = list.fold<int>(0, (sum, item) => sum + item.bytes);
                          final sizeLabel = bytes < 1024
                              ? '$bytes B'
                              : bytes < 1024 * 1024
                                  ? '${(bytes / 1024).toStringAsFixed(1)} KB'
                                  : '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                list.isEmpty
                                    ? '还没有缓存（打开过的会话会自动留一份）'
                                    : '已缓存 ${list.length} 条会话 · 共 $sizeLabel',
                                style: TextStyle(fontSize: 12, color: t.muted),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '上限：最多 ${SessionCache.maxSessions} 条会话、'
                                '每条 ${SessionCache.maxMessages} 条消息、'
                                '正文合计 ${SessionCache.maxCharsPerSession ~/ 1024} KB'
                                '（图片不入缓存）',
                                style: TextStyle(fontSize: 11, height: 1.6, color: t.onBgDim),
                              ),
                              for (final entry in list)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${entry.name.isEmpty ? entry.sessionId.substring(0, 8) : entry.name}'
                                          ' · ${entry.messageCount} 条 · ${entry.sizeLabel}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 11.5, color: t.muted),
                                        ),
                                      ),
                                      NeuPressable(
                                        onTap: () async {
                                          await SessionCache.removeOne(entry.sessionId);
                                          cacheTick.value += 1;
                                          if (!context.mounted) return;
                                          NeuToast.show(context,
                                              message: '已清掉这条缓存', icon: IconId.check);
                                        },
                                        radius: 8,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        child: Text('清除',
                                            style: TextStyle(fontSize: 11.5, color: t.danger)),
                                      ),
                                    ],
                                  ),
                                ),
                              if (list.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                NeuPressable(
                                  onTap: () async {
                                    await SessionCache.clear();
                                    cacheTick.value += 1;
                                    if (!context.mounted) return;
                                    NeuToast.show(context,
                                        message: '离线缓存已清空', icon: IconId.check);
                                  },
                                  radius: NeuRadii.sm,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  child: Center(
                                    child: Text('清空离线缓存',
                                        style: TextStyle(fontSize: 12.5, color: t.danger)),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
"""
s = s.replace(old_ui, new_ui + old_ui)

# ---- 清理本地数据时一并清缓存 ----
old_clear = """    final drafts = store.clearDrafts();
    final others = await AppPrefs.instance.clearLocalData();"""
new_clear = """    final drafts = store.clearDrafts();
    final others = await AppPrefs.instance.clearLocalData();
    // 离线缓存是独立存的一份，不清的话用户会以为「清理本地数据」清干净了
    await SessionCache.clear();
    cacheTick.value += 1;"""
assert s.count(old_clear) == 1, '清理锚点'
s = s.replace(old_clear, new_clear)

p.write_text(s, encoding='utf-8')
print('settings_page 已加离线缓存区（ValueNotifier 版）')
