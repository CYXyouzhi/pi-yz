// 实时活动视图：一眼看清 agent 正在干什么。
//
// 两个形态（task-14 的合同③①）：
//   · ActivityBar   —— 停靠在会话页顶部的细状态条：正在干什么 / 跑了多久 / 多快
//   · ActivitySheet —— 点状态条后弹出的时间线浮层：每一步工具调用、命令、思考、回复
//
// 数据全来自 buildActivity()（纯函数，单测钉死），这里只管画。

import 'dart:async';

import 'package:flutter/material.dart';

import '../../server/activity_feed.dart';
import '../../server/i18n.dart';
import '../../server/server_store.dart';
import '../../theme/design_tokens.dart';
import '../../theme/neu.dart';
import '../neu_icons.dart';

IconId _iconOf(ActivityItem it) {
  switch (it.kind) {
    case ActivityKind.user:
      return IconId.bubble;
    case ActivityKind.thinking:
      return IconId.info;
    case ActivityKind.reply:
      return IconId.bubble;
    case ActivityKind.wait:
      return IconId.warn;
    case ActivityKind.tool:
      final n = it.title.toLowerCase();
      if (n.contains('bash') || n.contains('shell') || n.contains('exec')) {
        return IconId.terminal;
      }
      if (n.contains('read') || n.contains('write') || n.contains('edit')) {
        return IconId.pen;
      }
      if (n.contains('grep') || n.contains('find') || n.contains('glob')) {
        return IconId.cmd;
      }
      if (n.contains('fetch') || n.contains('web') || n.contains('http')) {
        return IconId.download;
      }
      return IconId.cmd;
  }
}

String _labelOf(ActivityItem it) => it.title;

/// 停靠在会话页顶部的状态条。
///
/// 自带秒表（StatefulWidget + 自己的 1 秒 Timer）而不是让会话页每秒 setState：
/// 实测过前一种写法 —— 会话页每秒重建一次，[[运行中点状态条经常点不开]]，
/// 因为按下与抬起之间那一帧重建把手势丢了。只重建这一条就不会丢。
class ActivityBar extends StatefulWidget {
  const ActivityBar({
    super.key,
    required this.snap,
    required this.onTap,
    this.sessionName = '',
    this.runStartedAt,
    this.compact = false,
  });

  final ActivitySnapshot snap;
  final VoidCallback onTap;

  /// 合同③要求状态条上有会话名（多会话并行时得知道这是哪一个）
  final String sessionName;

  /// 本轮开始时间（毫秒）。有它才能自己走秒。
  final int? runStartedAt;

  /// 细条模式：空闲且没有待确认时用。
  ///
  /// 会话页竖向空间最贵（顶部标题 + 活动条 + 底部输入 + 导航栏），
  /// 空闲态没必要占和运行态一样的高度 —— 收成细条既保住「进活动视图」的入口，
  /// 又给消息列表让出一行。运行中 / 有待确认时仍用完整高度（那才是要看的信息）。
  final bool compact;

  @override
  State<ActivityBar> createState() => _ActivityBarState();
}

class _ActivityBarState extends State<ActivityBar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant ActivityBar old) {
    super.didUpdateWidget(old);
    _syncTicker();
  }

  void _syncTicker() {
    if (widget.snap.running) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (_ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final snap = widget.snap;
    final running = snap.running;
    final waiting = snap.waitingCount > 0;
    final dot = waiting ? t.warn : (running ? t.success : t.muted);

    // 自己算时长（父层给的 elapsedMs 是它构建那一刻的数，不会走）
    final start = widget.runStartedAt;
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = running && start != null && now > start ? now - start : 0;
    final speed = elapsed >= 1000 && snap.outputTokens > 0
        ? snap.outputTokens / (elapsed / 1000)
        : 0.0;

    // 一句话：在等用户回话 / 正在跑什么 / 空闲但上一轮有内容 / 完全没活动
    String head;
    if (waiting) {
      head = I18n.t('ui.493b7bc5ff');
    } else if (running) {
      head = I18n.t('ui.680ba4ce16');
    } else if (snap.empty) {
      head = I18n.t('ui.1d1a0f3be8');
    } else {
      head = I18n.t('ui.87bb5bbcc3');
    }

    final action = snap.current;
    final detail = waiting
        ? (action?.detail ?? I18n.t('ui.0b30277c77'))
        : running && action != null
            ? (action.kind == ActivityKind.tool
                ? '${action.title}${action.detail.isEmpty ? '' : ' ${action.detail}'}'
                : action.detail)
            : (snap.empty
                ? I18n.t('ui.409a5d5fb9')
                : (snap.toolCount == 0
                    ? I18n.t('ui.e2bbbd3cee')
                    : I18n.tp('ui.20f9b96cf2', {
                        'n': snap.toolCount,
                        'files': snap.fileCount > 0
                            ? I18n.tp('ui.30f2b16887', {'n': snap.fileCount})
                            : '',
                      })));

    final meta = <String>[];
    if (running && elapsed > 0) meta.add(humanDuration(elapsed));
    if (running && speed > 0) meta.add('${speed.toStringAsFixed(0)} tok/s');

    return NeuPressable(
      onTap: widget.onTap,
      radius: NeuRadii.sm,
      padding: EdgeInsets.symmetric(
        horizontal: NeuSpace.n12,
        vertical: widget.compact ? NeuSpace.n4 : NeuSpace.n8,
      ),
      child: Row(
        children: [
          // 状态点：跑着的是脉冲感的实心点，空闲是空心点
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (running || waiting) ? dot : Colors.transparent,
              border: Border.all(color: dot, width: 1.5),
            ),
          ),
          const SizedBox(width: NeuSpace.n8),
          if (widget.sessionName.trim().isNotEmpty) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 92),
              child: Text(
                widget.sessionName.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: NeuFonts.small, fontWeight: FontWeight.w600, color: t.muted),
              ),
            ),
            const SizedBox(width: NeuSpace.n6),
          ],
          Text(head,
              style: TextStyle(
                  fontSize: NeuFonts.small,
                  fontWeight: FontWeight.w600,
                  color: waiting ? t.warn : (running ? t.success : t.muted))),
          const SizedBox(width: NeuSpace.n8),
          Expanded(
            child: Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: NeuFonts.small,
                  fontFamily: 'monospace',
                  color: (running || waiting) ? t.fg : t.muted),
            ),
          ),
          // 细条模式不显示耗时/速度：那是「运行中」才关心的信息，
          // 空闲时留在这一行只会让状态条更挤
          if (meta.isNotEmpty && !widget.compact) ...[
            const SizedBox(width: NeuSpace.n8),
            Text(meta.join(' · '),
                style: TextStyle(
                    fontSize: NeuFonts.label,
                    color: t.muted,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
          const SizedBox(width: NeuSpace.n4),
          NeuIcon(IconId.chevronRight, size: 14, color: t.muted),
        ],
      ),
    );
  }
}

/// 弹出实时活动浮层。返回时不影响别的状态。
Future<void> showActivitySheet(BuildContext context, ServerStore store) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ActivitySheet(store: store),
  );
}

class _ActivitySheet extends StatefulWidget {
  const _ActivitySheet({required this.store});

  final ServerStore store;

  @override
  State<_ActivitySheet> createState() => _ActivitySheetState();
}

class _ActivitySheetState extends State<_ActivitySheet> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // 运行中每秒重画一次：否则「已运行 1:23」会一直停在打开那一刻
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final pending = widget.store.uiRequests
        .where((r) => r.needsResponse)
        .map((r) => r.title ?? r.message ?? r.method)
        .toList();
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return ListenableBuilder(
          listenable: widget.store,
          builder: (context, _) {
            final snap = buildActivity(
              widget.store.chat,
              runStartedAt: widget.store.chat.runStartedAt,
              pending: pending,
            );
            return Container(
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(NeuRadii.lg)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: NeuSpace.n10),
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: t.border,
                      borderRadius: BorderRadius.circular(NeuRadii.hairline),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n14, NeuSpace.n12, NeuSpace.n6),
                    child: Row(
                      children: [
                        NeuIcon(IconId.spinner,
                            size: 16,
                            color: snap.running ? t.success : t.muted),
                        SizedBox(width: NeuSpace.n8),
                        Text(I18n.t('ui.f3460980a4'),
                            style: TextStyle(
                                fontSize: NeuFonts.heading,
                                fontWeight: FontWeight.w700,
                                color: t.fg)),
                        const SizedBox(width: NeuSpace.n8),
                        Expanded(
                          child: Text(
                            widget.store.chat.sessionName ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: NeuFonts.small, color: t.muted),
                          ),
                        ),
                        NeuPressable(
                          onTap: () => Navigator.of(context).maybePop(),
                          radius: NeuRadii.sm,
                          padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n11, vertical: NeuSpace.n11),
                          child: NeuIcon(IconId.close, size: 18, color: t.muted),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(NeuSpace.n18, 0, NeuSpace.n18, NeuSpace.n10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _summaryLine(snap),
                        style: TextStyle(fontSize: NeuFonts.small, color: t.muted),
                      ),
                    ),
                  ),
                  Divider(height: 1, color: t.border),
                  Expanded(
                    child: snap.empty
                        ? _emptyState(t)
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(vertical: NeuSpace.n8),
                            itemCount: snap.items.length,
                            separatorBuilder: (_, _) => Divider(
                                height: 1,
                                indent: 18,
                                endIndent: 18,
                                color: t.border.withValues(alpha: 0.5)),
                            itemBuilder: (context, i) {
                              final it = snap.items[snap.items.length - 1 - i];
                              return _row(t, it);
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _summaryLine(ActivitySnapshot snap) {
    if (snap.empty && snap.waitingCount == 0) {
      return I18n.t('ui.a87c5ece96');
    }
    final parts = <String>[];
    if (snap.waitingCount > 0) {
      parts.add(I18n.tp('ui.a67d3f95b7', {'n': snap.waitingCount}));
    }
    parts.add(snap.running || snap.waitingCount > 0 ? I18n.t('common.running') : I18n.t('ui.c91492851a'));
    parts.add(I18n.tp('ui.2286308de1', {'n': snap.toolCount}));
    if (snap.fileCount > 0) parts.add(I18n.tp('ui.f547f2d5e4', {'n': snap.fileCount}));
    if (snap.outputTokens > 0) parts.add(I18n.tp('ui.1395da23fa', {'n': snap.outputTokens}));
    if (snap.running && snap.elapsedMs > 0) {
      parts.add(I18n.tp('ui.a33efe1f34', {'time': humanDuration(snap.elapsedMs)}));
    } else if (!snap.running && snap.lastRunMs > 0) {
      parts.add(I18n.tp('ui.19c1bd1b68', {'time': humanDuration(snap.lastRunMs)}));
    }
    final speed = snap.tokensPerSecond;
    if (snap.running && speed > 0) {
      parts.add('${speed.toStringAsFixed(0)} tok/s');
    }
    return parts.join(' · ');
  }

  Widget _emptyState(NeuTokens t) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NeuIcon(IconId.circle, size: 28, color: t.muted),
          SizedBox(height: NeuSpace.n10),
          Text(I18n.t('ui.1d1a0f3be8'), style: TextStyle(fontSize: NeuFonts.bodyTight, color: t.fg)),
          SizedBox(height: NeuSpace.n6),
          Text(I18n.t('ui.998a18b488'),
              style: TextStyle(fontSize: NeuFonts.small, color: t.muted)),
        ],
      ),
    );
  }

  Widget _row(NeuTokens t, ActivityItem it) {
    final Color c = it.failed
        ? t.danger
        : (it.kind == ActivityKind.wait
            ? t.warn
            : (it.running
                ? t.accentInk
                : (it.kind == ActivityKind.tool ? t.fg : t.muted)));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n18, vertical: NeuSpace.n9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              clockOf(it.at),
              style: TextStyle(
                fontSize: NeuFonts.badge,
                color: t.muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: NeuSpace.n1),
            child: NeuIcon(
              it.running ? IconId.spinner : _iconOf(it),
              size: 14,
              color: c,
            ),
          ),
          const SizedBox(width: NeuSpace.n10),
          SizedBox(
            width: 74,
            child: Text(
              _labelOf(it),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: NeuFonts.small,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                color: c,
              ),
            ),
          ),
          const SizedBox(width: NeuSpace.n6),
          Expanded(
            child: Text(
              it.detail.isEmpty ? '—' : it.detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: NeuFonts.small,
                fontFamily: 'monospace',
                color: t.fg.withValues(alpha: 0.9),
              ),
            ),
          ),
          SizedBox(width: NeuSpace.n8),
          if (it.failed)
            NeuIcon(IconId.warn, size: 14, color: t.danger)
          else if (it.kind == ActivityKind.wait)
            Text(I18n.t('ui.3b5b97cab5'), style: TextStyle(fontSize: NeuFonts.badge, color: t.warn))
          else if (it.running)
            Text(I18n.t('ui.fb852fc6cc'), style: TextStyle(fontSize: NeuFonts.badge, color: t.accentInk))
          else if (it.kind == ActivityKind.tool)
            NeuIcon(IconId.check, size: 14, color: t.muted),
        ],
      ),
    );
  }
}
