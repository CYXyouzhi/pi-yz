import 'package:flutter/material.dart';

import '../../../server/activity_feed.dart';
import '../../../server/chat_reducer.dart';
import '../../../server/i18n.dart';
import '../../../server/server_store.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../neu_icons.dart';
import '../activity_view.dart';

/// _buildActivityBar 的组件化版本。
class ChatActivityBar extends StatelessWidget {
  const ChatActivityBar({super.key, required this.store, required this.chat});

  final ServerStore store;
  final ChatReducer chat;

  @override
  Widget build(BuildContext context) {
    // 「等你确认」要进时间线：contract① 要求它能被看见
    final pending = store.uiRequests
        .where((r) => r.needsResponse)
        .map((r) => r.title ?? r.message ?? r.method)
        .toList();
    final snap = buildActivity(
      chat,
      runStartedAt: chat.runStartedAt,
      pending: pending,
    );
    // 没打开会话才隐藏；空会话照样显示 —— 「还没有活动」本身就是要说清楚的状态，
    // 而且它是进实时活动视图的唯一入口（合同④）。
    if (store.currentSessionId == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NeuSpace.n14,
        0,
        NeuSpace.n14,
        NeuSpace.n6,
      ),
      child: ActivityBar(
        snap: snap,
        sessionName: store.currentSessionTitle,
        runStartedAt: chat.runStartedAt,
        // 空闲且没有待确认时收成细条：会话页最贵的是竖向空间，
        // 空闲态没必要占和运行态一样的高度（入口仍在，点一下照样打开活动视图）
        compact: !chat.isRunning && pending.isEmpty,
        onTap: () => showActivitySheet(context, store),
      ),
    );
  }
}

/// _buildLoadMore 的组件化版本。
class LoadMoreRow extends StatelessWidget {
  const LoadMoreRow({super.key, required this.store, required this.chat});

  final ServerStore store;
  final ChatReducer chat;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final loading = store.loadingHistory;
    return Center(
      child: NeuPressable(
        onTap: loading ? null : () => store.loadMoreHistory(),
        radius: 14,
        padding: const EdgeInsets.symmetric(
          horizontal: NeuSpace.n14,
          vertical: NeuSpace.n14,
        ),
        margin: const EdgeInsets.only(bottom: NeuSpace.n10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            NeuIcon(
              loading ? IconId.spinner : IconId.chevronDown,
              size: 13,
              color: loading ? t.muted : t.accentInk,
            ),
            SizedBox(width: NeuSpace.n6),
            Text(
              loading
                  ? I18n.t('ui.fb4ca1cf1b')
                  : I18n.tp('ui.54507a5944', {
                      'shown': chat.messages.length,
                      'total': chat.historyTotal,
                    }),
              style: TextStyle(
                fontSize: NeuFonts.small,
                color: loading ? t.muted : t.accentInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// _buildOfflineBanner 的组件化版本。
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.store});

  final ServerStore store;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final at = store.cacheShownAt!;
    final hhmm =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final dropped = store.cacheDropped > 0
        ? I18n.tp('ui.acb19e42a6', {'n': store.cacheDropped})
        : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NeuSpace.n14,
        NeuSpace.n6,
        NeuSpace.n14,
        0,
      ),
      child: NeuRaised(
        radius: NeuRadii.sm,
        padding: const EdgeInsets.symmetric(
          horizontal: NeuSpace.n12,
          vertical: NeuSpace.n9,
        ),
        child: Row(
          children: [
            NeuIcon(IconId.warn, size: 14, color: t.danger),
            SizedBox(width: NeuSpace.n8),
            Expanded(
              child: Text(
                I18n.tp('ui.cb3f40c93e', {
                  'time': hhmm,
                  'n': store.cacheShownCount,
                  'dropped': dropped,
                }),
                style: TextStyle(
                  fontSize: NeuFonts.label,
                  height: 1.5,
                  color: t.muted,
                ),
              ),
            ),
            const SizedBox(width: NeuSpace.n6),
            NeuPressable(
              onTap: () async {
                await store.ensureConnected();
                final id = store.currentSessionId;
                if (id != null) await store.openSession(id);
              },
              radius: 8,
              padding: EdgeInsets.symmetric(
                horizontal: NeuSpace.n8,
                vertical: NeuSpace.n5,
              ),
              child: Text(
                I18n.t('common.retry'),
                style: TextStyle(fontSize: NeuFonts.small, color: t.accentInk),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// _buildUndoBar 的组件化版本。
class UndoBar extends StatelessWidget {
  const UndoBar({super.key, required this.onUndo});

  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NeuSpace.n18,
        NeuSpace.n4,
        NeuSpace.n18,
        0,
      ),
      child: NeuPressable(
        onTap: onUndo,
        radius: 10,
        flat: true,
        padding: const EdgeInsets.symmetric(
          horizontal: NeuSpace.n13,
          vertical: NeuSpace.n13,
        ),
        child: Row(
          children: [
            NeuIcon(IconId.check, size: 14, color: t.accentInk),
            SizedBox(width: NeuSpace.n8),
            Expanded(
              child: Text(
                I18n.t('ui.93d159228b'),
                style: TextStyle(fontSize: NeuFonts.sub, color: t.fg),
              ),
            ),
            Text(
              I18n.t('ui.2305051ed0'),
              style: TextStyle(fontSize: NeuFonts.sub, color: t.accentInk),
            ),
            const SizedBox(width: NeuSpace.n4),
            NeuIcon(IconId.close, size: 13, color: t.accentInk),
          ],
        ),
      ),
    );
  }
}

/// 一行进度提示（`chat.notice`）：转圈图标 + 文案。没有提示时不要插进来。
class ChatNoticeRow extends StatelessWidget {
  const ChatNoticeRow({super.key, required this.notice});

  final String notice;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NeuSpace.n18,
        vertical: NeuSpace.n4,
      ),
      child: Row(
        children: [
          NeuIcon(IconId.spinner, size: 13, color: t.muted),
          const SizedBox(width: NeuSpace.n6),
          Expanded(
            child: Text(
              notice,
              style: TextStyle(fontSize: NeuFonts.small, color: t.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// 排队中的消息提示：跑着的时候又发了话，会排进队列。
///
/// 必须**看得见 + 能撤** —— 用户发了话却看不出它有没有被接收，会重复发。
/// 右侧「清空」直接把队列丢掉。
class QueuedMessagesRow extends StatelessWidget {
  const QueuedMessagesRow({
    super.key,
    required this.steering,
    required this.followUp,
    required this.onClear,
  });

  /// steering（插话，中途改变方向）与 followUp（追加）的条数。
  final int steering;
  final int followUp;

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NeuSpace.n18,
        NeuSpace.n4,
        NeuSpace.n18,
        NeuSpace.n4,
      ),
      child: Row(
        children: [
          NeuIcon(IconId.info, size: 13, color: t.accentInk),
          SizedBox(width: NeuSpace.n6),
          Expanded(
            child: Text(
              I18n.tp('ui.ae9a52e8c8', {'a': steering, 'b': followUp}),
              style: TextStyle(fontSize: NeuFonts.small, color: t.muted),
            ),
          ),
          NeuPressable(
            onTap: onClear,
            radius: 10,
            padding: const EdgeInsets.symmetric(
              horizontal: NeuSpace.n10,
              vertical: NeuSpace.n6,
            ),
            child: Text(
              I18n.t('common.clear'),
              style: TextStyle(fontSize: NeuFonts.small, color: t.danger),
            ),
          ),
        ],
      ),
    );
  }
}
