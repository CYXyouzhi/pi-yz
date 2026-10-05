// 会话列表页（Tab「开始」）。
//
// 结构照设计稿的 page-home：连接状态卡 → 新会话 → 历史会话（按工作区分组）。
//
// 用「轻量行描述 + ListView.builder」而不是「先造一堆 Widget 再塞进 Column」：
// 实测历史会话有 244 条，全量构建 Widget 会卡；改成扁平行列表后按需构建。
// 展开状态放在 store 里，切 Tab 重建页面时不丢。

import 'dart:async';

import 'package:flutter/material.dart';

import '../../server/i18n.dart';
import '../../server/server_store.dart';
import '../../server/template_store.dart';
import '../../server/server_types.dart';
import '../../theme/design_tokens.dart';
import '../../theme/neu.dart';
import '../neu_icons.dart';
import '../neu_toast.dart';
import 'pool_view.dart';

/// 列表里的一行（轻量描述，不持有 Widget）
sealed class _Row {
  const _Row();
}

class _ConnRow extends _Row {
  const _ConnRow();
}

class _NewSessionRow extends _Row {
  const _NewSessionRow();
}

class _SearchRow extends _Row {
  const _SearchRow();
}

class _SectionRow extends _Row {
  const _SectionRow(this.title);
  final String title;
}

class _GroupRow extends _Row {
  const _GroupRow(this.cwd, this.name, this.sessions, this.expanded);
  final String cwd;
  final String name;
  final List<ServerSession> sessions;
  final bool expanded;
}

class _EmptyRow extends _Row {
  const _EmptyRow();
}

/// 「正在运行」总览（task-15 合同①②）
class _PoolRow extends _Row {
  const _PoolRow();
}

/// 已归档入口（合同③）
class _ArchiveRow extends _Row {
  const _ArchiveRow(this.count);
  final int count;
}

class _NoMatchRow extends _Row {
  const _NoMatchRow();
}

class ServerSessionsPage extends StatefulWidget {
  const ServerSessionsPage({
    super.key,
    required this.store,
    this.onOpenSession,
    this.onOpenConn,
    this.onOpenChat,
  });

  final ServerStore store;
  final void Function(ServerSession session)? onOpenSession;
  final VoidCallback? onOpenConn;
  final VoidCallback? onOpenChat;

  @override
  State<ServerSessionsPage> createState() => _ServerSessionsPageState();
}

class _ServerSessionsPageState extends State<ServerSessionsPage> {
  /// 新建会话进行中，防止连点造出一堆空会话
  bool _creating = false;

  /// 离线缓存里的会话（contract①：断网也要能点进会话读正文）
  List<ServerSession> _offline = const [];
  bool _offlineRequested = false;

  /// 会话搜索词（本地过滤，244 条已在内存，不需要服务端接口）
  String _query = '';
  final TextEditingController _searchController = TextEditingController();

  ServerStore get _store => widget.store;

  /// 活跃会话总览要「谁在跑」是活的，而池状态没有事件流 —— 3 秒轮一次。
  /// 只在列表页活着时轮，离开就停（省电、也省服务端）。
  Timer? _poolTimer;

  @override
  void initState() {
    super.initState();
    _store.loadPool();
    _poolTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _store.loadPool(),
    );
  }

  @override
  void dispose() {
    _poolTimer?.cancel();
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
  }

  // ==================== 行列表 ====================

  List<_Row> _buildRows() {
    // 有在线数据就用在线数据；没有就拿本地缓存顶上（并在顶部说明这是缓存）。
    // 在线数据用 visibleSessions：已归档的默认不出现（合同③）。
    final online = _store.sessions.isNotEmpty;
    final source = online ? _store.visibleSessions : _offline;
    final rows = <_Row>[
      const _ConnRow(),
      const _NewSessionRow(),
      if (_store.pool.isNotEmpty) const _PoolRow(),
      if (!online && source.isNotEmpty)
        _SectionRow(I18n.tp('ui.af6b674a02', {'n': source.length})),
    ];

    // 「未保存的新建会话」不再单独占一行（用户点名去掉）：
    // 它只是新建过程中的极短中间态，单独弄个分组既占地方，
    // 又让人以为有东西没存下来（而实际上后端已经建好了）。
    if (source.isEmpty) {
      rows.add(const _EmptyRow());
      final archived = _store.archivedSessions.length;
      if (archived > 0) rows.add(_ArchiveRow(archived));
      return rows;
    }

    rows.add(const _SearchRow());

    final query = _query.trim().toLowerCase();
    final searching = query.isNotEmpty;

    // 按工作区分组，会话多的排前面
    final groups = <String, List<ServerSession>>{};
    for (final session in source) {
      if (searching && !_matches(session, query)) continue;
      groups.putIfAbsent(session.cwd, () => []).add(session);
    }

    if (groups.isEmpty) {
      rows.add(const _NoMatchRow());
      return rows;
    }

    rows.add(_SectionRow(I18n.t('ui.9ea3f6a5de')));

    final entries = groups.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    for (final entry in entries) {
      // 搜索时强制展开：否则命中结果藏在收起的分组里，等于搜不到
      final expanded = searching || _store.expandedWorkspaces.contains(entry.key);
      rows.add(_GroupRow(
        entry.key,
        entry.value.first.workspaceName,
        entry.value,
        expanded,
      ));
    }

    // 已归档的会话不占默认列表，但得有个地方能把它们捞回来（合同③）
    final archived = _store.archivedSessions.length;
    if (archived > 0) rows.add(_ArchiveRow(archived));

    return rows;
  }

  /// 搜索匹配：会话名 / 首条消息 / 路径 任一命中
  static bool _matches(ServerSession session, String query) {
    final name = (session.name ?? '').toLowerCase();
    final preview = session.preview.toLowerCase();
    final cwd = session.cwd.toLowerCase();
    return name.contains(query) || preview.contains(query) || cwd.contains(query);
  }

  // ==================== 操作 ====================

  Future<void> _createSession({String? firstMessage}) async {
    if (_creating) return;
    if (!_store.isConnected) {
      widget.onOpenConn?.call();
      return;
    }

    // 当前会话已经是空的（上一次点「新会话」留下的）就直接切过去。
    // 不加这一步的话，连点会造出一堆空会话（实测点 10 次就真的建了 10 条）。
    // 带模板时不走这条捷径：模板是要发出去的，切到旧空会话会让人以为模板没生效。
    if (firstMessage == null &&
        _store.currentSessionId != null &&
        _store.chat.messages.isEmpty &&
        !_store.chat.isRunning) {
      widget.onOpenChat?.call();
      return;
    }

    final cwd = await _pickWorkspace();
    if (cwd == null) return;
    // 选择器是异步关闭的，其间页面可能已被销毁（切 Tab / 返回）
    if (!mounted) return;

    setState(() => _creating = true);
    final id = await _store.createSession(cwd);
    if (!mounted) return;
    setState(() => _creating = false);

    if (id == null) {
      NeuToast.show(context,
          message: _store.lastError ?? I18n.t('ui.96a6a6ca0f'), icon: IconId.warn);
      return;
    }
    // 模板开场白：建完会话立刻发出去，省掉「再打一遍」
    if (firstMessage != null) {
      final sent = await _store.sendPrompt(firstMessage);
      if (!mounted) return;
      if (!sent) {
        NeuToast.show(context,
            message: _store.lastError ?? I18n.t('ui.370bc4a6b1'), icon: IconId.warn);
      }
    }
    NeuToast.show(context, message: I18n.t('ui.b244d633d4'), icon: IconId.check);
    widget.onOpenChat?.call();
  }

  /// 手动输入一个工作区路径。
  ///
  /// 回填当前默认值作为起点：用户多半是在它附近改一层目录，
  /// 从空框开始打字要重敲整条路径。
  Future<String?> _askWorkspacePath(BuildContext context, String? hint) async {
    final controller = TextEditingController(text: hint ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final t = dialogContext.neu;
        return AlertDialog(
          backgroundColor: t.bg,
          title: Text(I18n.t('conn.manualWorkspace'),
              style: TextStyle(fontSize: NeuFonts.sectionTitle, color: t.fg)),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: I18n.t('conn.manualWorkspaceHint'),
              hintStyle: TextStyle(fontSize: NeuFonts.bodySmall, color: t.muted),
            ),
            style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.fg),
            onSubmitted: (v) => Navigator.of(dialogContext).pop(v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(I18n.t('common.cancel')), 
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(I18n.t('common.ok')),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (result == null || result.isEmpty) return null;
    return result;
  }

  /// 选工作区。
  ///
  /// 候选 = 连接配置里的默认工作区 + 所有历史会话用过的 cwd。
  /// 只有一个候选时直接用，不弹窗。
  Future<String?> _pickWorkspace() async {
    final configured = _store.target?.defaultCwd?.trim();
    final workspaces = <String>{};
    if (configured != null && configured.isNotEmpty) workspaces.add(configured);
    // 工作区候选也可以来自离线缓存：断网时新建会话选目录仍然要有东西可选
    final known = _store.sessions.isNotEmpty ? _store.sessions : _offline;
    for (final session in known) {
      if (session.cwd.trim().isNotEmpty) workspaces.add(session.cwd);
    }
    final list = workspaces.toList();

    if (list.isEmpty) {
      NeuToast.show(context, message: I18n.t('ui.0ef428fefc'), icon: IconId.warn);
      widget.onOpenConn?.call();
      return null;
    }
    if (list.length == 1) return list.first;
    if (!mounted) return null;

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final t = sheetContext.neu;
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.6,
          ),
          decoration: BoxDecoration(
            color: t.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(NeuRadii.lg)),
          ),
          padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n10, NeuSpace.n18, NeuSpace.n24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 把手：手机上提示「这是一个可下拉关闭的面板」
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.muted.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(NeuRadii.hairline),
                  ),
                ),
              ),
              SizedBox(height: NeuSpace.n14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      I18n.t('ui.7e0ab49ec4'),
                      style: TextStyle(
                        fontSize: NeuFonts.sectionTitle,
                        fontWeight: FontWeight.w700,
                        color: t.onBg,
                      ),
                    ),
                  ),
                  NeuPressable(
                    onTap: () => Navigator.of(sheetContext).pop(),
                    radius: 12,
                    padding: EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n7),
                    child: Text(I18n.t('common.cancel'), style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.muted)),
                  ),
                ],
              ),
              SizedBox(height: NeuSpace.n2),
              Text(I18n.t('ui.435ccbf9b2'), style: TextStyle(fontSize: NeuFonts.small, color: t.muted)),
              const SizedBox(height: NeuSpace.n14),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: list.length + 1,
                  itemBuilder: (_, index) {
                    // 第 0 项：手动输入路径。
                    // 为什么必须有它：候选只来自「配置里的默认工作区 + 历史上用过的 cwd」，
                    // 于是**没用过的目录永远进不来** —— 想在一个从没开过会话的目录下
                    // 新建会话，界面上无路可走（用户原话：「应该可以自定义工作区的，
                    // 现在只能使用历史工作区」）。
                    if (index == 0) {
                      return NeuPressable(
                        onTap: () async {
                          final typed = await _askWorkspacePath(sheetContext, configured);
                          if (typed == null || !sheetContext.mounted) return;
                          Navigator.of(sheetContext).pop(typed);
                        },
                        flat: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
                        margin: const EdgeInsets.only(bottom: NeuSpace.n6),
                        child: Row(
                          children: [
                            NeuIcon(IconId.pen, size: 15, color: t.accentInk),
                            const SizedBox(width: NeuSpace.n10),
                            Expanded(
                              child: Text(I18n.t('conn.manualWorkspace'),
                                  style: TextStyle(fontSize: NeuFonts.bodyMid, color: t.accentInk)),
                            ),
                            NeuIcon(IconId.chevronRight, size: 13, color: t.muted),
                          ],
                        ),
                      );
                    }
                    final path = list[index - 1];
                    final isDefault = path == configured;
                    return NeuPressable(
                      onTap: () => Navigator.of(sheetContext).pop(path),
                      flat: true,
                      padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
                      margin: const EdgeInsets.only(bottom: NeuSpace.n6),
                      child: Row(
                        children: [
                          NeuIcon(IconId.folder, size: 15, color: t.accentInk),
                          const SizedBox(width: NeuSpace.n10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  path.replaceAll('\\', '/').split('/').last,
                                  style: TextStyle(fontSize: NeuFonts.bodyMid, color: t.fg),
                                ),
                                Text(
                                  path,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: NeuFonts.badge, color: t.muted),
                                ),
                              ],
                            ),
                          ),
                          if (isDefault)
                            Text(I18n.t('ui.18c63459a2'), style: TextStyle(fontSize: NeuFonts.micro, color: t.accentInk)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 删除会话（显式按钮与长按都走这里）
  Future<void> _deleteSession(ServerSession session) async {
    final t = context.neu;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: t.bg,
        title: Text(I18n.t('ui.78fb22f373'), style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle)),
        content: Text(
          I18n.tp('ui.4751d5948e', {'title': session.displayTitle, 'n': session.messageCount}),
          style: TextStyle(color: t.muted, fontSize: NeuFonts.bodyMid, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(I18n.t('common.cancel'), style: TextStyle(color: t.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(I18n.t('common.delete'), style: TextStyle(color: t.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await _store.deleteSession(session.id);
    if (ok && mounted) {
      NeuToast.show(context, message: I18n.t('ui.5cc232620c'), icon: IconId.trash);
    }
  }

  // ==================== 构建 ====================

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    // 只监听列表专用信号：流式时 store 每秒 notify 几十次，
    // 列表跟着重建的话 244 条会明显卡顿
    return ValueListenableBuilder<int>(
      valueListenable: _store.sessionsRevision,
      builder: (context, value, child) {
        if (_store.sessions.isNotEmpty) {
          // 回到在线：允许下次断网时重新从缓存读（缓存是会更新的）
          _offlineRequested = false;
        } else {
          _ensureOfflineLoaded();
        }
        final rows = _buildRows();
        return RefreshIndicator(
          // 手机上「下拉刷新」是本能动作；列表只有 30s 缓存，下拉就走强制重扫
          onRefresh: () => _store.loadSessions(refresh: true),
          color: t.accentInk,
          backgroundColor: t.surface,
          child: ListView.builder(
            // 切 Tab 回来时保留滚动位置
            key: const PageStorageKey<String>('server-sessions'),
            // 底部留出 tab 栏的高度，否则最后一组会被 tab 栏切掉
            padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n10, NeuSpace.n18, 104),
            // 内容不满一屏时也要能下拉
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: rows.length,
            itemBuilder: (context, index) => _buildRow(t, rows[index]),
          ),
        );
      },
    );
  }

  /// 已归档入口：默认列表不放它们，但得留一条能把它们捞回来的路。
  Widget _buildArchiveEntry(NeuTokens t, int count) {
    return NeuPressable(
      onTap: () => _showArchiveSheet(),
      radius: NeuRadii.md,
      padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n14, vertical: NeuSpace.n14),
      child: Row(
        children: [
          NeuIcon(IconId.folder, size: 16, color: t.muted),
          SizedBox(width: NeuSpace.n10),
          Expanded(
            child: Text(I18n.tp('ui.5a04ac36ad', {'n': count}),
                style: TextStyle(fontSize: NeuFonts.bodyMid, color: t.fg)),
          ),
          Text(I18n.t('ui.56fddae514'), style: TextStyle(fontSize: NeuFonts.small, color: t.muted)),
          const SizedBox(width: NeuSpace.n6),
          NeuIcon(IconId.chevronRight, size: 14, color: t.muted),
        ],
      ),
    );
  }

  Future<void> _showArchiveSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Container(
          decoration: BoxDecoration(
            color: sheetContext.neu.bg,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(NeuRadii.lg)),
          ),
          padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n10, NeuSpace.n18, NeuSpace.n24),
          child: ListenableBuilder(
            listenable: _store,
            builder: (context, _) {
              final st = sheetContext.neu;
              final list = _store.archivedSessions;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: st.muted.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(NeuRadii.hairline),
                      ),
                    ),
                  ),
                  SizedBox(height: NeuSpace.n16),
                  Text(I18n.tp('ui.c748caed3a', {'n': list.length}),
                      style: TextStyle(
                          fontSize: NeuFonts.heading,
                          fontWeight: FontWeight.w700,
                          color: st.fg)),
                  SizedBox(height: NeuSpace.n6),
                  Text(I18n.t('ui.67a8909b85'),
                      style: TextStyle(fontSize: NeuFonts.small, color: st.muted, height: 1.5)),
                  const SizedBox(height: NeuSpace.n12),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: NeuSpace.n20),
                      child: Center(
                        child: Text(I18n.t('ui.065d1a7742'),
                            style: TextStyle(fontSize: NeuFonts.bodySmall, color: st.muted)),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight:
                            MediaQuery.of(sheetContext).size.height * 0.45,
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final session in list)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: NeuSpace.n6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(session.displayTitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: NeuFonts.bodySmall, color: st.fg)),
                                        SizedBox(height: NeuSpace.n2),
                                        Text(
                                            I18n.tp('ui.8d6dd7475a', {'ws': session.workspaceName, 'n': session.messageCount}),
                                            style: TextStyle(
                                                fontSize: NeuFonts.badge, color: st.muted)),
                                      ],
                                    ),
                                  ),
                                  NeuPressable(
                                    onTap: () => _store.unarchiveSession(session.id),
                                    radius: NeuRadii.sm,
                                    padding: EdgeInsets.symmetric(
                                        horizontal: NeuSpace.n10, vertical: NeuSpace.n6),
                                    child: Text(I18n.t('ui.8d8324a89f'),
                                        style: TextStyle(
                                            fontSize: NeuFonts.small, color: st.accentInk)),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildRow(NeuTokens t, _Row row) => switch (row) {
        _ConnRow() => _buildConnCard(t),
        _PoolRow() => Padding(
            padding: const EdgeInsets.only(top: NeuSpace.n14),
            child: RunningSessionsCard(
              sessions: _store.pool,
              // 点一下直接切过去：并行跑着的时候，「跳到我关心的那条」是最高频动作
              onOpen: (p) async {
                await _store.openSession(p.id);
                widget.onOpenChat?.call();
              },
              onRefresh: _store.loadPool,
              onClose: (p) => _store.closeLiveSession(p.id),
            ),
          ),
        _ArchiveRow(:final count) => Padding(
            padding: const EdgeInsets.only(top: NeuSpace.n20),
            child: _buildArchiveEntry(t, count),
          ),
        _NewSessionRow() => Padding(
            padding: const EdgeInsets.only(top: NeuSpace.n14),
            child: _buildNewSession(t),
          ),
        _SectionRow(:final title) => Padding(
            padding: const EdgeInsets.only(top: NeuSpace.n20, bottom: NeuSpace.n10),
            child: Text(
              title,
              style: TextStyle(
                fontSize: NeuFonts.sectionTitle,
                fontWeight: FontWeight.w700,
                color: t.onBg,
              ),
            ),
          ),
        _SearchRow() => Padding(
            padding: const EdgeInsets.only(top: NeuSpace.n14),
            child: _buildSearch(t),
          ),
        _NoMatchRow() => Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                NeuIcon(IconId.warn, size: 22, color: t.muted),
                SizedBox(height: NeuSpace.n10),
                Text(
                  I18n.tp('ui.a425983efe', {'query': _query}),
                  style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.onBgDim),
                ),
              ],
            ),
          ),
        _GroupRow(:final cwd, :final name, :final sessions, :final expanded) =>
          _buildGroup(t, cwd, name, sessions, expanded),
        _EmptyRow() => _buildEmptyState(t),
      };

  /// 搜索框。244 条会话全在内存，本地过滤就够，不必加服务端接口。
  Widget _buildSearch(NeuTokens t) {
    return NeuInset(
      radius: NeuRadii.sm,
      padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12),
      child: Row(
        children: [
          NeuIcon(IconId.bubble, size: 14, color: t.muted),
          const SizedBox(width: NeuSpace.n8),
          Expanded(
            child: TextField(
              controller: _searchController,
              style: TextStyle(fontSize: NeuFonts.bodyMid, color: t.fg),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: I18n.t('ui.c9651ff139'),
                hintStyle: TextStyle(fontSize: NeuFonts.bodySmall, color: t.muted),
                contentPadding: const EdgeInsets.symmetric(vertical: NeuSpace.n12),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          if (_query.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                setState(() => _query = '');
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(NeuSpace.n6),
                child: NeuIcon(IconId.close, size: 14, color: t.muted),
              ),
            ),
        ],
      ),
    );
  }

  /// 会话操作菜单：重命名 / 删除。
  ///
  /// 之前直接把垃圾桶画在每一行上，一屏十几个删除键，视觉噪点很大；
  /// 手机上更习惯的做法是收进一个「更多」菜单。
  Future<void> _showSessionActions(ServerSession session) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      // 不打开这个开关，弹层最高只有半屏，小屏手机上内容会被切掉
      isScrollControlled: true,
      builder: (sheetContext) {
        final sheetTokens = sheetContext.neu;
        final isArchived = _store.isArchived(session.id);
        return Container(
          decoration: BoxDecoration(
            color: sheetTokens.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(NeuRadii.lg)),
          ),
          padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n10, NeuSpace.n18, NeuSpace.n24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: sheetTokens.muted.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(NeuRadii.hairline),
                  ),
                ),
              ),
              const SizedBox(height: NeuSpace.n14),
              Text(
                session.displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: NeuFonts.sectionTitle,
                  fontWeight: FontWeight.w700,
                  color: sheetTokens.onBg,
                ),
              ),
              SizedBox(height: NeuSpace.n2),
              Text(
                I18n.tp('ui.40f8db2889', {'n': session.messageCount, 'cwd': session.cwd}),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: NeuFonts.label, color: sheetTokens.muted),
              ),
              const SizedBox(height: NeuSpace.n14),
              NeuPressable(
                onTap: () => Navigator.of(sheetContext).pop('rename'),
                flat: true,
                padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n12),
                margin: const EdgeInsets.only(bottom: NeuSpace.n6),
                child: Row(
                  children: [
                    NeuIcon(IconId.pen, size: 16, color: sheetTokens.accentInk),
                    SizedBox(width: NeuSpace.n10),
                    Text(I18n.t('ui.c8ce4b36cb'), style: TextStyle(fontSize: NeuFonts.bodyTight, color: sheetTokens.fg)),
                  ],
                ),
              ),
              NeuPressable(
                onTap: () => Navigator.of(sheetContext).pop('clone'),
                flat: true,
                padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n12),
                margin: const EdgeInsets.only(bottom: NeuSpace.n6),
                child: Row(
                  children: [
                    NeuIcon(IconId.download, size: 16, color: sheetTokens.accentInk),
                    SizedBox(width: NeuSpace.n10),
                    Text(I18n.t('ui.5f6e171c5b'), style: TextStyle(fontSize: NeuFonts.bodyTight, color: sheetTokens.fg)),
                  ],
                ),
              ),
              NeuPressable(
                onTap: () => Navigator.of(sheetContext)
                    .pop(isArchived ? 'unarchive' : 'archive'),
                flat: true,
                padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n12),
                margin: const EdgeInsets.only(bottom: NeuSpace.n6),
                child: Row(
                  children: [
                    NeuIcon(IconId.folder, size: 16, color: sheetTokens.accentInk),
                    SizedBox(width: NeuSpace.n10),
                    Expanded(
                      child: Text(
                        isArchived ? I18n.t('ui.bc83e0c0c2') : I18n.t('ui.dac78a7368'),
                        style: TextStyle(fontSize: NeuFonts.bodyTight, color: sheetTokens.fg),
                      ),
                    ),
                  ],
                ),
              ),
              NeuPressable(
                onTap: () => Navigator.of(sheetContext).pop('delete'),
                flat: true,
                padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n12),
                child: Row(
                  children: [
                    NeuIcon(IconId.trash, size: 16, color: sheetTokens.danger),
                    SizedBox(width: NeuSpace.n10),
                    Text(I18n.t('common.delete'), style: TextStyle(fontSize: NeuFonts.bodyTight, color: sheetTokens.danger)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    if (action == 'rename') {
      await _renameSession(session);
    } else if (action == 'clone') {
      final newId = await _store.cloneSession(sessionId: session.id);
      if (!mounted) return;
      if (newId != null) {
        NeuToast.show(context, message: I18n.t('ui.d228d6f331'), icon: IconId.check);
        widget.onOpenChat?.call();
      }
    } else if (action == 'archive') {
      await _store.archiveSession(session.id);
      if (!mounted) return;
      // 说清楚「归档 ≠ 删除」：用户最怕的是「我的会话是不是没了」
      NeuToast.show(context,
          message: I18n.t('ui.0708eadaa1'),
          icon: IconId.check);
    } else if (action == 'unarchive') {
      await _store.unarchiveSession(session.id);
      if (!mounted) return;
      NeuToast.show(context, message: I18n.t('ui.e8b121d05d'), icon: IconId.check);
    } else if (action == 'delete') {
      await _deleteSession(session);
    }
  }

  Future<void> _renameSession(ServerSession session) async {
    final t = context.neu;
    final controller = TextEditingController(text: session.name ?? '');
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: t.bg,
          title: Text(I18n.t('ui.3e654d807c'), style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle)),
          content: NeuInset(
            radius: NeuRadii.sm,
            padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12),
            child: TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(fontSize: NeuFonts.bodyTight, color: t.fg),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: I18n.t('ui.fd081a3eac'),
                hintStyle: TextStyle(fontSize: NeuFonts.bodySmall, color: t.muted),
                contentPadding: const EdgeInsets.symmetric(vertical: NeuSpace.n12),
              ),
              onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(I18n.t('common.cancel'), style: TextStyle(color: t.muted)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: Text(I18n.t('common.save'), style: TextStyle(color: t.accentInk)),
            ),
          ],
        ),
      );
      if (name == null || !mounted) return;
      final ok = await _store.renameSession(session.id, name);
      if (ok && mounted) {
        NeuToast.show(context, message: I18n.t('ui.560e8629e3'), icon: IconId.check);
      }
    } finally {
      controller.dispose();
    }
  }

  Widget _buildConnCard(NeuTokens t) {
    final target = _store.target;
    final connected = _store.isConnected;
    return NeuRaised(
      radius: NeuRadii.lg,
      level: NeuLevel.standard,
      padding: const EdgeInsets.all(NeuSpace.n16),
      child: Column(
        children: [
          NeuPressable(
            onTap: widget.onOpenConn,
            flat: true,
            padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n11, vertical: NeuSpace.n11),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(NeuRadii.chip),
                    gradient: NeuDecorations.raisedGradient(t),
                    boxShadow: NeuShadows.raiseSm(t),
                  ),
                  alignment: Alignment.center,
                  child: NeuIcon(IconId.server, size: 18, color: t.accentInk),
                ),
                SizedBox(width: NeuSpace.n12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        I18n.t('settings.conn'),
                        style: TextStyle(
                          fontSize: NeuFonts.bodyLg,
                          fontWeight: FontWeight.w700,
                          color: t.fg,
                        ),
                      ),
                      Text(
                        target == null
                            ? I18n.t('ui.47840e3fb4')
                            : '${target.label}${connected ? I18n.t('ui.836349be8d') : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: NeuFonts.sub, color: t.muted),
                      ),
                    ],
                  ),
                ),
                NeuIcon(IconId.chevronRight, size: 16, color: t.muted),
              ],
            ),
          ),
          const SizedBox(height: NeuSpace.n10),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: connected
                      ? t.success
                      : (_store.state == ServerConnectionState.connecting
                          ? t.warn
                          : t.muted),
                ),
              ),
              SizedBox(width: NeuSpace.n7),
              Expanded(
                child: Text(
                  switch (_store.state) {
                    ServerConnectionState.connected =>
                      I18n.tp('ui.33716d0005', {'v': _store.health?.piVersion ?? '', 'n': _store.sessions.length}),
                    ServerConnectionState.connecting => I18n.t('common.connecting'),
                    ServerConnectionState.error => _store.errorMessage ?? I18n.t('common.connFailed'),
                    ServerConnectionState.disconnected => I18n.t('common.disconnected'),
                  },
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: NeuFonts.sub, color: t.muted),
                ),
              ),
              // 这里原本还有个「手动刷新会话」的圆按钮，已去掉：
              // 会话列表在下拉刷新、进页、重连时都会自己刷新，
              // 再放一个按钮只是重复，而且占着连接卡右下角（用户点名它是多余的）。
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNewSession(NeuTokens t) {
    return NeuPressable(
      onTap: _createSession,
      // 长按 = 带模板新建（空会话还是点一下，老习惯不变）
      onLongPress: _creating ? null : _showTemplateSheet,
      radius: NeuRadii.md,
      level: NeuLevel.standard,
      padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n14, vertical: NeuSpace.n12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_creating)
            NeuIcon(IconId.spinner, size: 16, color: t.muted)
          else
            NeuIcon(IconId.plus, size: 16, color: t.accentInk),
          SizedBox(width: NeuSpace.n8),
          Text(
            _creating ? I18n.t('ui.d156b373ad') : I18n.t('ui.42ddad2439'),
            style: TextStyle(
              fontSize: NeuFonts.body,
              color: _creating ? t.muted : t.accentInk,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 长按「新会话」：选一个常用语模板当开场白，或者就开个空会话。
  ///
  /// 模板直接复用输入区 ＋ 菜单里存的那份（TemplateStore），
  /// 不另建一套「会话模板」，免得同一个概念在 App 里有两份数据。
  Future<void> _showTemplateSheet() async {
    final t = context.neu;
    final templates = await TemplateStore.instance.load();
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        margin: EdgeInsets.fromLTRB(
            NeuSpace.n14, 0, NeuSpace.n14, NeuSpace.n14 + MediaQuery.paddingOf(sheetContext).bottom),
        padding: const EdgeInsets.symmetric(vertical: NeuSpace.n10),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.6,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NeuRadii.lg),
          gradient: NeuDecorations.raisedGradient(t),
          boxShadow: NeuShadows.raise(t),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n4, NeuSpace.n18, NeuSpace.n8),
              child: Text(I18n.t('ui.08d9b34843'),
                  style: TextStyle(
                      fontSize: NeuFonts.bodyLg, fontWeight: FontWeight.w700, color: t.fg)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  _templateRow(sheetContext, t, I18n.t('ui.7870802a43'), ''),
                  for (final item in templates)
                    _templateRow(sheetContext, t, item, item),
                  if (templates.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n10, NeuSpace.n18, NeuSpace.n6),
                      child: Text(
                        I18n.t('ui.b47293f027'),
                        style: TextStyle(fontSize: NeuFonts.label, color: t.muted),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || picked == null) return;
    await _createSession(firstMessage: picked.isEmpty ? null : picked);
  }

  Widget _templateRow(
      BuildContext sheetContext, NeuTokens t, String label, String value) {
    return NeuPressable(
      onTap: () => Navigator.of(sheetContext).pop(value),
      flat: true,
      radius: NeuRadii.sm,
      padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n18, vertical: NeuSpace.n13),
      margin: const EdgeInsets.symmetric(horizontal: NeuSpace.n6, vertical: NeuSpace.n1),
      child: Row(
        children: [
          NeuIcon(value.isEmpty ? IconId.bubble : IconId.pen,
              size: 15, color: t.muted),
          const SizedBox(width: NeuSpace.n10),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: NeuFonts.bodyTight, color: t.fg),
            ),
          ),
        ],
      ),
    );
  }

  /// 新建但未落盘的会话：pi 要等第一条消息才写文件，
  /// 这里先给它一个位置，否则用户会以为「新建没生效」。
  /// 一个工作区一张卡：分组头 + （展开时）它自己的会话行。
  Widget _buildGroup(
    NeuTokens t,
    String cwd,
    String name,
    List<ServerSession> sessions,
    bool expanded,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: NeuSpace.n8),
      child: NeuRaised(
        radius: NeuRadii.md,
        level: NeuLevel.small,
        padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n6),
        child: Column(
          children: [
            NeuPressable(
              flat: true,
              onTap: () => setState(() {
                if (expanded) {
                  _store.expandedWorkspaces.remove(cwd);
                } else {
                  _store.expandedWorkspaces.add(cwd);
                }
              }),
              padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
              child: Row(
                children: [
                  NeuIcon(IconId.folder, size: 15, color: t.accentInk),
                  const SizedBox(width: NeuSpace.n8),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: NeuFonts.bodyMid,
                        color: t.fg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text('${sessions.length}', style: TextStyle(fontSize: NeuFonts.label, color: t.muted)),
                  const SizedBox(width: NeuSpace.n6),
                  NeuIcon(
                    expanded ? IconId.chevronDown : IconId.chevronRight,
                    size: 14,
                    color: t.muted,
                  ),
                ],
              ),
            ),
            if (expanded)
              for (var i = 0; i < sessions.length; i++) ...[
                // 发丝分隔线：inset-grouped 靠它把多条会话读成同一组
                Container(height: 1, color: t.border),
                _buildSessionRow(t, sessions[i]),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildSessionRow(NeuTokens t, ServerSession session) {
    // 「哪个在跑」直接标在行上（task-21 合同④）：并行跑几条时，
    // 用户第一眼要能看出哪一条在动，而不是只能看顶部的总览卡片。
    final running =
        _store.pool.any((p) => p.id == session.id && p.running);
    return GestureDetector(
      // 长按也进操作菜单（重命名/删除），与右侧图标同一入口
      onLongPress: () => _showSessionActions(session),
      child: NeuPressable(
        flat: true,
        onTap: () {
          widget.onOpenSession?.call(session);
          widget.onOpenChat?.call();
        },
        padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
        child: Row(
          children: [
            NeuIcon(
              running ? IconId.spinner : IconId.bubble,
              size: 14,
              color: running ? t.success : t.muted,
            ),
            const SizedBox(width: NeuSpace.n9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: NeuFonts.bodyMid, color: t.fg),
                  ),
                  SizedBox(height: NeuSpace.n2),
                  Text(
                    running
                        ? I18n.tp('ui.604c021ba2', {'n': session.messageCount, 'time': _relativeTime(session.modifiedAt)})
                        : I18n.tp('ui.d05a6b72d1', {'n': session.messageCount, 'time': _relativeTime(session.modifiedAt)}),
                    style: TextStyle(
                        fontSize: NeuFonts.badge, color: running ? t.success : t.muted),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _showSessionActions(session),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(NeuSpace.n6),
                child: NeuIcon(IconId.pen, size: 14, color: t.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(NeuTokens t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          NeuIcon(IconId.bubble, size: 26, color: t.muted),
          SizedBox(height: NeuSpace.n10),
          Text(
            _store.isConnected
                ? (_store.loadingSessions
                    ? I18n.t('ui.fb4ca1cf1b')
                    : I18n.t('start.noSession', context: context))
                : I18n.t('start.connectFirst', context: context),
            style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.onBgDim),
          ),
          if (_store.sessionsError != null) ...[
            const SizedBox(height: NeuSpace.n8),
            Text(
              _store.sessionsError!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: NeuFonts.small, color: t.danger),
            ),
            const SizedBox(height: NeuSpace.n10),
            // 失败要给一条能走的路：先补连接，再重新拉列表
            NeuPressable(
              onTap: () async {
                await _store.ensureConnected();
                await _store.loadSessions(refresh: true);
              },
              radius: NeuRadii.sm,
              padding: EdgeInsets.symmetric(horizontal: NeuSpace.n16, vertical: NeuSpace.n9),
              child: Text(I18n.t('common.retry'), style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.accentInk)),
            ),
          ],
        ],
      ),
    );
  }

  static String _relativeTime(DateTime? time) {
    if (time == null) return I18n.t('ui.9418d7cb5e');
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return I18n.t('ui.4181f7fe2a');
    if (diff.inMinutes < 60) return I18n.tp('ui.1f75ab9c48', {'count': diff.inMinutes});
    if (diff.inHours < 24) return I18n.tp('ui.16362ceb20', {'n': diff.inHours});
    if (diff.inDays < 30) return I18n.tp('ui.0dd2ae3aa0', {'n': diff.inDays});
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-'
        '${time.day.toString().padLeft(2, '0')}';
  }
}
