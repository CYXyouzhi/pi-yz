import 'package:flutter/material.dart';

import '../../../server/activity_feed.dart';
import '../../../server/chat_models.dart';
import '../../../server/chat_reducer.dart';
import '../../../server/i18n.dart';
import '../../../server/server_store.dart';
import '../../../server/server_types.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../neu_icons.dart';
import '../activity_view.dart';
import 'sheets.dart';

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

/// _buildLiveSpeed 的组件化版本。
class LiveSpeed extends StatelessWidget {
  const LiveSpeed({super.key, required this.store, required this.runStartedAt});

  final ServerStore store;
  final DateTime? runStartedAt;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final totals = store.sessionUsage?.totals;
      final speed = totals?.tokensPerSec;
      final started = runStartedAt;
      final seconds = started == null
          ? null
          : DateTime.now().difference(started).inSeconds;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          NeuIcon(IconId.spinner, size: 11, color: t.accentInk),
          const SizedBox(width: NeuSpace.n4),
          Text(
            '${speed == null ? '—' : '$speed'} tok/s'
            '${seconds == null ? '' : ' · ${seconds}s'}',
            style: TextStyle(fontSize: NeuFonts.micro, color: t.accentInk),
          ),
        ],
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
        padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n4, NeuSpace.n18, 0),
        child: NeuPressable(
          onTap: onUndo,
          radius: 10,
          flat: true,
          padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
          child: Row(
            children: [
              NeuIcon(IconId.check, size: 14, color: t.accentInk),
              SizedBox(width: NeuSpace.n8),
              Expanded(
                child: Text(I18n.t('ui.93d159228b'), style: TextStyle(fontSize: NeuFonts.sub, color: t.fg)),
              ),
              Text(I18n.t('ui.2305051ed0'), style: TextStyle(fontSize: NeuFonts.sub, color: t.accentInk)),
              const SizedBox(width: NeuSpace.n4),
              NeuIcon(IconId.close, size: 13, color: t.accentInk),
            ],
          ),
        ),
      );
  }
}

/// _buildFileRefs 的组件化版本。
class FileRefs extends StatelessWidget {
  const FileRefs({super.key, required this.refs, required this.onApply});

  final List<FileRef> refs;
  final void Function(FileRef ref) onApply;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Container(
        constraints: const BoxConstraints(maxHeight: 200),
        margin: const EdgeInsets.symmetric(horizontal: NeuSpace.n18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NeuRadii.md),
          gradient: NeuDecorations.wellGradient(t),
          boxShadow: NeuShadows.inset(t),
        ),
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.all(NeuSpace.n6),
          itemCount: refs.length,
          itemBuilder: (context, index) {
            final ref = refs[index];
            return NeuPressable(
              onTap: () => onApply(ref),
              flat: true,
              padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
              child: Row(
                children: [
                  NeuIcon(IconId.terminal, size: 14, color: t.accentInk),
                  const SizedBox(width: NeuSpace.n8),
                  Expanded(
                    child: Text(
                      ref.relative,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: NeuFonts.sub,
                        fontFamily: 'monospace',
                        color: t.fg,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
  }
}

/// _buildSuggestions 的组件化版本。
class Suggestions extends StatelessWidget {
  const Suggestions({super.key, required this.commands, required this.onApply, required this.store});

  final List<SlashCommand> commands;
  final void Function(SlashCommand cmd) onApply;
  final ServerStore store;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    // 面板高度跟屏幕走。以前写死 200：手机上只能看到 4 条，
      // 12 条命令得一直滑，看起来就像「显示不完全」。
      // 必须减掉键盘高度（viewInsets.bottom）：否则软键盘弹起来会盖住面板底部几条，
      // 用户会以为「命令就这些」。
      final maxHeight = slashPanelMaxHeight(MediaQuery.of(context));
      return Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        margin: const EdgeInsets.symmetric(horizontal: NeuSpace.n18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NeuRadii.md),
          gradient: NeuDecorations.wellGradient(t),
          boxShadow: NeuShadows.inset(t),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (commands.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n16),
                child: Row(
                  children: [
                    NeuIcon(IconId.spinner, size: 14, color: t.muted),
                    SizedBox(width: NeuSpace.n8),
                    Expanded(
                      child: Text(
                        I18n.t('ui.8109beab3c'),
                        style: TextStyle(fontSize: NeuFonts.small, color: t.muted),
                      ),
                    ),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(NeuSpace.n6),
                  itemCount: commands.length,
                  itemBuilder: (context, index) {
                    final command = commands[index];
                    // 中文模式优先中文说明；没有就原文 + 标注（不假装翻过）
                    final description = I18n.describe(
                      command.description,
                      command.descriptionZh,
                      context: context,
                    );
                    return NeuPressable(
                      onTap: () => onApply(command),
                      flat: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: NeuSpace.n10,
                        vertical: NeuSpace.n8,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: NeuSpace.n2),
                            child: NeuIcon(
                              switch (command.source) {
                                'builtin' => IconId.cmd,
                                'skill' => IconId.spinner,
                                'prompt' => IconId.pen,
                                _ => IconId.terminal,
                              },
                              size: 15,
                              color: t.accentInk,
                            ),
                          ),
                          const SizedBox(width: NeuSpace.n8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 命令名长短不一（扩展命令可以是长路径），
                                // 所以给一行横向滚动：名字再长也能滑着读完，不截断
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '/${command.name}',
                                          style: TextStyle(
                                            fontSize: NeuFonts.bodyMid,
                                            fontFamily: 'monospace',
                                            color: t.fg,
                                          ),
                                        ),
                                        if (command.argHint != null &&
                                            command.argHint!.isNotEmpty)
                                          TextSpan(
                                            text: '  ${command.argHint}',
                                            style: TextStyle(
                                              fontSize: NeuFonts.badge,
                                              color: t.muted,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (description.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: NeuSpace.n2),
                                    child: Text(
                                      description,
                                      // 说明不再截断：面板本身可以滚，读全比好看重要
                                      style: TextStyle(
                                        fontSize: NeuFonts.label,
                                        height: 1.45,
                                        color: t.muted,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            if (commands.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: NeuSpace.n6),
                child: Text(
                  // 数字必须是真话：显示了多少 / 一共多少（筛选时两个数不一样）
                  commands.length == store.commands.length
                      ? I18n.tp('ui.a977d99ebd', {'n': commands.length})
                      : I18n.tp('ui.6e9ce7a03e', {'a': commands.length, 'b': store.commands.length}),
                  style: TextStyle(fontSize: NeuFonts.micro, color: t.muted),
                ),
              ),
          ],
        ),
      );
  }
}

double slashPanelMaxHeight(MediaQueryData media) {
  final available = media.size.height - media.viewInsets.bottom;
  return (available * 0.45).clamp(160.0, 420.0);
}

/// _footerAction 的组件化版本。
class FooterAction extends StatelessWidget {
  const FooterAction({super.key, required this.icon, required this.label, required this.onTap});

  final IconId icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return NeuPressable(
        onTap: onTap,
        flat: true,
        radius: NeuRadii.sm,
        padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n14, vertical: NeuSpace.n14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            NeuIcon(icon, size: 12, color: t.muted),
            const SizedBox(width: NeuSpace.n4),
            Text(label, style: TextStyle(fontSize: NeuFonts.badge, color: t.muted)),
          ],
        ),
      );
  }
}

/// _buildTurnFooter 的组件化版本。
class TurnFooter extends StatelessWidget {
  const TurnFooter({super.key, required this.store, required this.chat, required this.onContinue, required this.onRedo, required this.onSummary});

  final ServerStore store;
  final ChatReducer chat;
  final VoidCallback onContinue;
  final VoidCallback onRedo;
  final VoidCallback onSummary;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final summary = store.turnSummary;
      final hasChanges = summary != null && !summary.isEmpty;
      return Padding(
        padding: const EdgeInsets.fromLTRB(NeuSpace.n18, 0, NeuSpace.n18, NeuSpace.n4),
        child: Row(
          children: [
            if (hasChanges)
              Expanded(
                child: NeuPressable(
                  onTap: () => showTurnSummarySheet(context, summary),
                  flat: true,
                  radius: NeuRadii.sm,
                  padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n14, vertical: NeuSpace.n14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      NeuIcon(IconId.pen, size: 12, color: t.accentInk),
                      SizedBox(width: NeuSpace.n5),
                      Flexible(
                        child: Text(
                          I18n.tp('ui.9069e11411', {'files': summary.files.length, 'added': summary.added, 'removed': summary.removed}),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: NeuFonts.badge, color: t.accentInk),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            SizedBox(width: NeuSpace.n8),
            FooterAction(icon: IconId.send, label: I18n.t('ui.27ca568be2'), onTap: onContinue),
            SizedBox(width: NeuSpace.n6),
            FooterAction(
                icon: IconId.sync,
                label: I18n.t('ui.7f7c7dcf89'),
                onTap: () => onRedo()),
          ],
        ),
      );
  }
}

/// _buildPendingImages 的组件化版本。
class PendingImages extends StatelessWidget {
  const PendingImages({super.key, required this.images, required this.onShowUndo, required this.onRemove, required this.onInsert});

  final List<({String name, String base64, String mime})> images;
  final void Function(String message, VoidCallback onUndo) onShowUndo;
  final void Function(({String name, String base64, String mime}) image) onRemove;
  final void Function(int index, ({String name, String base64, String mime}) image) onInsert;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Padding(
        padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n4, NeuSpace.n18, 0),
        child: Row(
          children: [
            for (final image in images)
              Padding(
                padding: const EdgeInsets.only(right: NeuSpace.n6),
                child: NeuPressable(
                  // 点缩略图就是移除，但给一条可撤销的提示 ——
                  // 手机上误触缩略图太容易了，直接没了会让人重新选一遍图
                  onTap: () {
                    final index = images.indexOf(image);
                    onRemove(image);
                    onShowUndo(
                      I18n.tp('ui.8dc0a54c3c', {'name': image.name}),
                      () => onInsert(index.clamp(0, images.length), image),
                    );
                  },
                  radius: 8,
                  flat: true,
                  // 触控目标：图标 13 + 14×2 = 41dp（原来 vertical n5 只有 23dp）
                  padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n8, vertical: NeuSpace.n14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      NeuIcon(IconId.download, size: 13, color: t.accentInk),
                      const SizedBox(width: NeuSpace.n5),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 120),
                        child: Text(
                          image.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: NeuFonts.label, color: t.fg),
                        ),
                      ),
                      const SizedBox(width: NeuSpace.n5),
                      NeuIcon(IconId.close, size: 12, color: t.muted),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
  }
}
