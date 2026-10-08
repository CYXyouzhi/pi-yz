import 'package:flutter/material.dart';

import '../../../server/i18n.dart';
import '../../../server/server_store.dart';
import '../../../server/server_types.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../neu_icons.dart';

/// _buildEmptyState 的组件化版本。
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({super.key, required this.store});

  final ServerStore store;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            NeuIcon(IconId.bubble, size: 26, color: t.muted),
            SizedBox(height: NeuSpace.n10),
            Text(
              store.isConnected
                  ? (store.loadingSessions
                      ? I18n.t('ui.fb4ca1cf1b')
                      : I18n.t('start.noSession', context: context))
                  : I18n.t('start.connectFirst', context: context),
              style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.onBgDim),
            ),
            if (store.sessionsError != null) ...[
              const SizedBox(height: NeuSpace.n8),
              Text(
                store.sessionsError!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: NeuFonts.small, color: t.danger),
              ),
              const SizedBox(height: NeuSpace.n10),
              // 失败要给一条能走的路：先补连接，再重新拉列表
              NeuPressable(
                onTap: () async {
                  await store.ensureConnected();
                  await store.loadSessions(refresh: true);
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
}

/// _buildConnCard 的组件化版本。
class ConnCard extends StatelessWidget {
  const ConnCard({super.key, required this.store, required this.onOpenConn});

  final ServerStore store;
  final VoidCallback? onOpenConn;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final target = store.target;
      final connected = store.isConnected;
      return NeuRaised(
        radius: NeuRadii.lg,
        level: NeuLevel.standard,
        padding: const EdgeInsets.all(NeuSpace.n16),
        child: Column(
          children: [
            NeuPressable(
              onTap: onOpenConn,
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
                        : (store.state == ServerConnectionState.connecting
                            ? t.warn
                            : t.muted),
                  ),
                ),
                SizedBox(width: NeuSpace.n7),
                Expanded(
                  child: Text(
                    switch (store.state) {
                      ServerConnectionState.connected =>
                        I18n.tp('ui.33716d0005', {'v': store.health?.piVersion ?? '', 'n': store.sessions.length}),
                      ServerConnectionState.connecting => I18n.t('common.connecting'),
                      ServerConnectionState.error => store.errorMessage ?? I18n.t('common.connFailed'),
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
}

/// _buildArchiveEntry 的组件化版本。
class ArchiveEntryRow extends StatelessWidget {
  const ArchiveEntryRow({super.key, required this.count, required this.onOpen});

  final int count;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return NeuPressable(
        onTap: () => onOpen(),
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
}

/// _buildNewSession 的组件化版本。
class NewSessionRow extends StatelessWidget {
  const NewSessionRow({super.key, required this.creating, required this.onCreate, required this.onLongPress});

  final bool creating;
  final VoidCallback onCreate;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return NeuPressable(
        onTap: onCreate,
        // 长按 = 带模板新建（空会话还是点一下，老习惯不变）
        onLongPress: creating ? null : onLongPress,
        radius: NeuRadii.md,
        level: NeuLevel.standard,
        padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n14, vertical: NeuSpace.n12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (creating)
              NeuIcon(IconId.spinner, size: 16, color: t.muted)
            else
              NeuIcon(IconId.plus, size: 16, color: t.accentInk),
            SizedBox(width: NeuSpace.n8),
            Text(
              creating ? I18n.t('ui.d156b373ad') : I18n.t('ui.42ddad2439'),
              style: TextStyle(
                fontSize: NeuFonts.body,
                color: creating ? t.muted : t.accentInk,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
  }
}

/// _buildSearch 的组件化版本。
class SessionSearchBar extends StatelessWidget {
  const SessionSearchBar({super.key, required this.query, required this.controller, required this.onQueryChanged});

  final String query;
  final TextEditingController controller;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return NeuInset(
        radius: NeuRadii.sm,
        padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12),
        child: Row(
          children: [
            NeuIcon(IconId.bubble, size: 14, color: t.muted),
            const SizedBox(width: NeuSpace.n8),
            Expanded(
              child: TextField(
                controller: controller,
                style: TextStyle(fontSize: NeuFonts.bodyMid, color: t.fg),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: I18n.t('ui.c9651ff139'),
                  hintStyle: TextStyle(fontSize: NeuFonts.bodySmall, color: t.muted),
                  contentPadding: const EdgeInsets.symmetric(vertical: NeuSpace.n12),
                ),
                onChanged: onQueryChanged,
              ),
            ),
            if (query.isNotEmpty)
              GestureDetector(
                onTap: () {
                  controller.clear();
                  onQueryChanged('');
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
}

/// 把时间写成「3 分钟前」这类相对量。
///
/// 30 天以上就退回具体日期 —— 相对量再大就没有信息量了。
String relativeTime(DateTime? time) {
  if (time == null) return I18n.t('ui.9418d7cb5e');
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return I18n.t('ui.4181f7fe2a');
  if (diff.inMinutes < 60) return I18n.tp('ui.1f75ab9c48', {'count': diff.inMinutes});
  if (diff.inHours < 24) return I18n.tp('ui.16362ceb20', {'n': diff.inHours});
  if (diff.inDays < 30) return I18n.tp('ui.0dd2ae3aa0', {'n': diff.inDays});
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';
}

/// 会话行：一条会话（标题 + 相对时间 + 右侧「更多」）。
///
/// 长按和右侧铅笔是**同一个**操作菜单入口 —— 手机上长按是习惯动作，
/// 图标是给不知道可以长按的人看的。
class SessionRow extends StatelessWidget {
  const SessionRow({
    super.key,
    required this.session,
    required this.running,
    required this.onOpen,
    required this.onMore,
  });

  final ServerSession session;

  /// 这条会话是否正在跑。标在行上（task-21 合同④）：并行跑几条时，
  /// 用户第一眼要能看出哪一条在动，而不是只能看顶部的总览卡片。
  final bool running;

  final ValueChanged<ServerSession> onOpen;
  final ValueChanged<ServerSession> onMore;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return GestureDetector(
      onLongPress: () => onMore(session),
      child: NeuPressable(
        flat: true,
        onTap: () => onOpen(session),
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
                        ? I18n.tp('ui.604c021ba2', {
                            'n': session.messageCount,
                            'time': relativeTime(session.modifiedAt),
                          })
                        : I18n.tp('ui.d05a6b72d1', {
                            'n': session.messageCount,
                            'time': relativeTime(session.modifiedAt),
                          }),
                    style: TextStyle(fontSize: NeuFonts.badge, color: running ? t.success : t.muted),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => onMore(session),
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
}

/// 一个工作区分组（可折叠）：分组头 + 展开后的会话行。
///
/// 这个分组**不持有**展开状态 —— 展开与否存在 store 里（切 Tab 重建页面时不丢），
/// 组件只负责把它画出来、点击时回调给页面去改。
class SessionGroupCard extends StatelessWidget {
  const SessionGroupCard({
    super.key,
    required this.cwd,
    required this.name,
    required this.sessions,
    required this.expanded,
    required this.runningIds,
    required this.onToggle,
    required this.onOpenSession,
    required this.onOpenChat,
    required this.onMore,
  });

  final String cwd;
  final String name;
  final List<ServerSession> sessions;
  final bool expanded;

  /// 正在跑的会话 id。整组只查一次，不必每行都去 pool 里找。
  final Set<String> runningIds;

  final ValueChanged<String> onToggle;
  final ValueChanged<ServerSession> onOpenSession;
  final VoidCallback onOpenChat;
  final ValueChanged<ServerSession> onMore;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
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
              onTap: () => onToggle(cwd),
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
                  Text('${sessions.length}',
                      style: TextStyle(fontSize: NeuFonts.label, color: t.muted)),
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
                SessionRow(
                  session: sessions[i],
                  running: runningIds.contains(sessions[i].id),
                  onOpen: (s) {
                    onOpenSession(s);
                    onOpenChat();
                  },
                  onMore: onMore,
                ),
              ],
          ],
        ),
      ),
    );
  }
}
