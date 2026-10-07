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
        padding: const EdgeInsets.fromLTRB(NeuSpace.n14, 0, NeuSpace.n14, NeuSpace.n6),
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
          padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n14, vertical: NeuSpace.n14),
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
                    : I18n.tp('ui.54507a5944', {'shown': chat.messages.length, 'total': chat.historyTotal}),
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
        padding: const EdgeInsets.fromLTRB(NeuSpace.n14, NeuSpace.n6, NeuSpace.n14, 0),
        child: NeuRaised(
          radius: NeuRadii.sm,
          padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n9),
          child: Row(
            children: [
              NeuIcon(IconId.warn, size: 14, color: t.danger),
              SizedBox(width: NeuSpace.n8),
              Expanded(
                child: Text(
                  I18n.tp('ui.cb3f40c93e', {'time': hhmm, 'n': store.cacheShownCount, 'dropped': dropped}),
                  style: TextStyle(fontSize: NeuFonts.label, height: 1.5, color: t.muted),
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
                padding: EdgeInsets.symmetric(horizontal: NeuSpace.n8, vertical: NeuSpace.n5),
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

/// _buildEmpty 的组件化版本。
class ChatEmptyState extends StatelessWidget {
  const ChatEmptyState({super.key, required this.store});

  final ServerStore store;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: NeuDecorations.raisedGradient(t),
                boxShadow: NeuShadows.raise(t),
              ),
              alignment: Alignment.center,
              child: NeuIcon(IconId.bubble, size: 24, color: t.accentInk),
            ),
            SizedBox(height: NeuSpace.n14),
            Text(
              store.isConnected ? I18n.t('ui.bd3d0854a0') : I18n.t('ui.16ae3ae443'),
              style: TextStyle(
                fontSize: NeuFonts.bodyLg,
                fontWeight: FontWeight.w700,
                color: t.onBg,
              ),
            ),
            SizedBox(height: NeuSpace.n6),
            Text(
              store.isConnected ? I18n.t('ui.8f4e9d8dbf') : I18n.t('ui.3a27243926'),
              style: TextStyle(fontSize: NeuFonts.sub, color: t.onBgDim),
            ),
          ],
        ),
      );
  }
}

/// _buildLoading 的组件化版本。
class ChatLoading extends StatelessWidget {
  const ChatLoading({super.key, required this.store});

  final ServerStore store;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final error = store.errorMessage;
      final failed = error != null && error.isNotEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NeuIcon(
                failed ? IconId.warn : IconId.spinner,
                size: 24,
                color: failed ? t.danger : t.accentInk,
              ),
              SizedBox(height: NeuSpace.n12),
              Text(
                failed ? error : I18n.t('ui.d8999cf874'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: NeuFonts.bodySmall,
                  height: 1.6,
                  color: failed ? t.danger : t.onBgDim,
                ),
              ),
              if (failed) ...[
                const SizedBox(height: NeuSpace.n14),
                NeuPressable(
                  onTap: () async {
                    // 先补连接：断线时 store 没客户端，直接重载只会再失败一次
                    await store.ensureConnected();
                    final id = store.currentSessionId;
                    if (id != null) await store.openSession(id);
                  },
                  radius: 14,
                  padding: const EdgeInsets.symmetric(
                    // 触控目标：14 + 13×2 = 40dp（原来 vertical n9 只有 32dp）
                    horizontal: NeuSpace.n18,
                    vertical: NeuSpace.n13,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      NeuIcon(IconId.sync, size: 14, color: t.accentInk),
                      SizedBox(width: NeuSpace.n6),
                      Text(
                        I18n.t('ui.421b536739'),
                        style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.accentInk),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
  }
}
