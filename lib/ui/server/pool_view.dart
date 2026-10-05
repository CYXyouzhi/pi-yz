// 多会话总览与磁盘占用（task-15）。
//
// 两件事放一个文件是因为它们回答的是同一个问题的两面：
//   · RunningSessionsCard —— 内存里活着的那几个会话在干什么（哪个在跑、跑到哪、花了多少）
//   · StoragePage         —— 磁盘上那些会话占了多少、能清哪几条
//
// 数据都来自服务端（/api/pool 与 /api/sessions/disk），App 不自己记账。

import 'dart:async';

import 'package:flutter/material.dart';

import '../../server/server_store.dart';
import '../../server/i18n.dart';
import '../../server/server_types.dart';
import '../../theme/design_tokens.dart';
import '../../theme/neu.dart';
import '../neu_icons.dart';
import '../neu_toast.dart';

/// 开始页顶部的「正在运行」卡片：点某一行直接切过去。
class RunningSessionsCard extends StatelessWidget {
  const RunningSessionsCard({
    super.key,
    required this.sessions,
    required this.onOpen,
    required this.onRefresh,
  });

  final List<PoolSession> sessions;

  /// 点某条会话 → 打开它（并切到会话页）
  final void Function(PoolSession) onOpen;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final running = sessions.where((s) => s.running).length;

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(NeuRadii.md),
        border: Border.all(color: t.border),
      ),
      padding: const EdgeInsets.fromLTRB(NeuSpace.n14, NeuSpace.n12, NeuSpace.n14, NeuSpace.n8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: running > 0 ? t.success : t.muted,
                ),
              ),
              SizedBox(width: NeuSpace.n8),
              Text(
                running > 0 ? I18n.tp('ui.e3e9b48350', {'n': running}) : I18n.t('ui.35eb0b8e30'),
                style: TextStyle(
                    fontSize: NeuFonts.bodySmall, fontWeight: FontWeight.w700, color: t.fg),
              ),
              SizedBox(width: NeuSpace.n8),
              Expanded(
                child: Text(
                  I18n.tp('ui.f39b24369b', {'n': sessions.length}),
                  style: TextStyle(fontSize: NeuFonts.small, color: t.muted),
                ),
              ),
              NeuPressable(
                onTap: onRefresh,
                radius: NeuRadii.sm,
                padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
                child: NeuIcon(IconId.sync, size: 15, color: t.muted),
              ),
            ],
          ),
          const SizedBox(height: NeuSpace.n4),
          for (final s in sessions) _row(context, t, s),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, NeuTokens t, PoolSession s) {
    final parts = <String>[];
    if (s.running) {
      parts.add(I18n.tp('ui.a33efe1f34', {'time': _short(s.runningMs)}));
    } else if (s.idleMs > 0) {
      parts.add(I18n.tp('ui.6bf9e327f2', {'time': _short(s.idleMs)}));
    }
    if (s.outputTokens > 0) parts.add('${s.outputTokens} tok');
    if (s.cost > 0) parts.add('\$${s.cost.toStringAsFixed(4)}');

    return NeuPressable(
      onTap: () => onOpen(s),
      radius: NeuRadii.sm,
      padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n14, vertical: NeuSpace.n14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: NeuSpace.n1),
            child: NeuIcon(
              s.running ? IconId.spinner : IconId.circle,
              size: 13,
              color: s.running ? t.accentInk : t.muted,
            ),
          ),
          const SizedBox(width: NeuSpace.n8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      s.workspaceName,
                      style: TextStyle(
                          fontSize: NeuFonts.label, color: t.muted, fontFamily: 'monospace'),
                    ),
                    if (s.lastAction.isNotEmpty) ...[
                      const SizedBox(width: NeuSpace.n6),
                      Expanded(
                        child: Text(
                          s.lastAction,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: NeuFonts.label,
                              color: t.accentInk,
                              fontFamily: 'monospace'),
                        ),
                      ),
                    ] else
                      const Spacer(),
                  ],
                ),
                const SizedBox(height: NeuSpace.n2),
                Text(
                  s.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: NeuFonts.sub, color: t.fg),
                ),
                if (parts.isNotEmpty) ...[
                  const SizedBox(height: NeuSpace.n2),
                  Text(parts.join(' · '),
                      style: TextStyle(fontSize: NeuFonts.badge, color: t.muted)),
                ],
              ],
            ),
          ),
          NeuIcon(IconId.chevronRight, size: 14, color: t.muted),
        ],
      ),
    );
  }

  static String _short(int ms) {
    if (ms <= 0) return I18n.t('ui.c73936bbd7');
    final total = ms ~/ 1000;
    if (total < 60) return I18n.tp('ui.c2d9323e9e', {'n': total});
    final m = total ~/ 60;
    if (m < 60) return I18n.tp('ui.021016e15c', {'m': m});
    return I18n.tp('ui.f405d8974a', {'h': m ~/ 60, 'm': m % 60});
  }
}

/// 磁盘占用页：按工作区看占用，逐条清理。
class StoragePage extends StatefulWidget {
  const StoragePage({super.key, required this.store});

  final ServerStore store;

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  /// 展开了哪几个工作区（默认只展开占用最大的那个）
  final Set<String> _expanded = {};

  ServerStore get _store => widget.store;

  /// 「谁正在跑」会变：页面活着时轮询一次 / 3 秒，否则标出来的状态是过期的
  Timer? _poolTimer;

  @override
  void initState() {
    super.initState();
    _store.loadDisk();
    _store.loadPool();
    _poolTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _store.loadPool(),
    );
  }

  @override
  void dispose() {
    _poolTimer?.cancel();
    super.dispose();
  }

  /// 正在跑的会话 id 集合（服务端拦得住，但界面先标出来更好 ——
  /// 用户不该点进去才知道删不了）
  Set<String> get _runningIds =>
      _store.pool.where((p) => p.running).map((p) => p.id).toSet();

  Future<void> _delete(DiskSession s, DiskGroup g) async {
    if (_runningIds.contains(s.id)) {
      NeuToast.show(context,
          message: I18n.t('ui.2d951376b5'), icon: IconId.warn);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.neu.surface,
        title: Text(I18n.t('ui.643e2ff2b9'), style: TextStyle(color: ctx.neu.fg, fontSize: NeuFonts.sectionTitle)),
        content: Text(
          '${I18n.tp('ui.cd0d2003f0', {
            'title': s.title,
            'size': humanBytes(s.bytes),
            'n': s.messages,
          })}'
          '${I18n.tp('ui.86b3ddbe40', {
            'ws': g.workspaceName,
            'size': humanBytes(s.bytes),
          })}',
          style: TextStyle(color: ctx.neu.muted, fontSize: NeuFonts.bodyMid, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(I18n.t('common.cancel'), style: TextStyle(color: ctx.neu.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(I18n.t('common.delete'), style: TextStyle(color: ctx.neu.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final done = await _store.deleteSession(s.id);
    if (!mounted) return;
    if (done) {
      NeuToast.show(context, message: I18n.tp('ui.5fa4f9c0f7', {'size': humanBytes(s.bytes)}),
          icon: IconId.check);
      // 归档标记顺手清掉（这条 id 不会再出现）
      // 故意不等：刷新磁盘缓存失败不影响本次操作；显式标 unawaited 表明是刻意而非漏写
      unawaited(_store.loadDisk());
    } else {
      // 服务端拒绝的情况（正在跑）会走这里，原因已在 store.lastError 里
      NeuToast.show(context,
          message: I18n.tp('ui.dd5666e6e0',
              {'e': _store.lastError ?? I18n.t('ui.31bbcc36d8')}),
          icon: IconId.warn);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        title: Text(I18n.t('ui.b9d0f24c4c'),
            style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            onPressed: _store.loadDisk,
            icon: NeuIcon(IconId.sync, size: 18, color: t.muted),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          final disk = _store.disk;
          if (_store.loadingDisk && disk == null) {
            return Center(
                child: NeuIcon(IconId.spinner, size: 22, color: t.muted));
          }
          if (disk == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  _store.diskError ?? I18n.t('ui.2af86cefa9'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.muted, fontSize: NeuFonts.bodyMid, height: 1.6),
                ),
              ),
            );
          }
          if (disk.groups.isEmpty) {
            return Center(
              child: Text(I18n.t('ui.ea2e75976e'),
                  style: TextStyle(color: t.muted, fontSize: NeuFonts.bodyMid)),
            );
          }

          if (_expanded.isEmpty) _expanded.add(disk.groups.first.cwd);

          return ListView(
            padding: const EdgeInsets.fromLTRB(NeuSpace.n16, NeuSpace.n12, NeuSpace.n16, 30),
            children: [
              // 总量 + 口径
              Container(
                padding: const EdgeInsets.all(NeuSpace.n14),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(NeuRadii.md),
                  border: Border.all(color: t.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(humanBytes(disk.totalBytes),
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w700, color: t.fg)),
                    SizedBox(height: NeuSpace.n4),
                    Text(
                        I18n.tp('ui.95409b9ef3', {'n': disk.totalSessions, 'g': disk.groups.length}),
                        style: TextStyle(fontSize: NeuFonts.small, color: t.muted)),
                    if (disk.basis.isNotEmpty) ...[
                      SizedBox(height: NeuSpace.n8),
                      Text(I18n.tp('ui.2a624cf5e8', {'basis': disk.basis}),
                          style: TextStyle(fontSize: NeuFonts.badge, color: t.muted, height: 1.5)),
                    ],
                  ],
                ),
              ),
              SizedBox(height: NeuSpace.n16),
              Text(I18n.t('ui.3c56ed3536'),
                  style: TextStyle(
                      fontSize: NeuFonts.bodyLg, fontWeight: FontWeight.w700, color: t.onBg)),
              const SizedBox(height: NeuSpace.n10),
              for (final g in disk.groups) _group(t, g),
            ],
          );
        },
      ),
    );
  }

  Widget _group(NeuTokens t, DiskGroup g) {
    final open = _expanded.contains(g.cwd);
    return Padding(
      padding: const EdgeInsets.only(bottom: NeuSpace.n10),
      child: Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(NeuRadii.md),
          border: Border.all(color: t.border),
        ),
        child: Column(
          children: [
            NeuPressable(
              onTap: () => setState(() {
                if (open) {
                  _expanded.remove(g.cwd);
                } else {
                  _expanded.add(g.cwd);
                }
              }),
              radius: NeuRadii.md,
              padding: const EdgeInsets.fromLTRB(NeuSpace.n14, NeuSpace.n12, NeuSpace.n14, NeuSpace.n12),
              child: Row(
                children: [
                  NeuIcon(IconId.folder, size: 16, color: t.accentInk),
                  const SizedBox(width: NeuSpace.n10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.workspaceName,
                            style: TextStyle(
                                fontSize: NeuFonts.bodyTight,
                                fontWeight: FontWeight.w600,
                                color: t.fg)),
                        SizedBox(height: NeuSpace.n2),
                        Text(I18n.tp('ui.dda1a3b608', {'n': g.count, 'size': humanBytes(g.bytes)}),
                            style: TextStyle(fontSize: NeuFonts.label, color: t.muted)),
                      ],
                    ),
                  ),
                  Text(humanBytes(g.bytes),
                      style: TextStyle(
                          fontSize: NeuFonts.small, fontWeight: FontWeight.w600, color: t.fg)),
                  const SizedBox(width: NeuSpace.n6),
                  NeuIcon(open ? IconId.chevronDown : IconId.chevronRight,
                      size: 14, color: t.muted),
                ],
              ),
            ),
            if (open) ...[
              Divider(height: 1, color: t.border),
              for (final s in g.sessions) _sessionRow(t, s, g),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sessionRow(NeuTokens t, DiskSession s, DiskGroup g) {
    final running = _runningIds.contains(s.id);
    final when = s.modifiedAt;
    final whenText = when == null
        ? ''
        : '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(NeuSpace.n14, NeuSpace.n10, NeuSpace.n10, NeuSpace.n10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (running) ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle, color: t.success),
                      ),
                      const SizedBox(width: NeuSpace.n6),
                    ],
                    Expanded(
                      child: Text(s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: NeuFonts.sub, color: t.fg)),
                    ),
                  ],
                ),
                SizedBox(height: NeuSpace.n2),
                Text(
                  [
                    if (running) I18n.t('ui.c9e2c3a6fd'),
                    humanBytes(s.bytes),
                    I18n.tp('ui.ce4502a521', {'n': s.messages}),
                    if (whenText.isNotEmpty) whenText,
                  ].join(' · '),
                  style: TextStyle(
                      fontSize: NeuFonts.badge,
                      color: running ? t.success : t.muted),
                ),
              ],
            ),
          ),
          NeuPressable(
            onTap: () => _delete(s, g),
            radius: NeuRadii.sm,
            padding: EdgeInsets.symmetric(horizontal: NeuSpace.n10, vertical: NeuSpace.n6),
            child: Text(I18n.t('common.delete'),
                style: TextStyle(fontSize: NeuFonts.small, color: t.danger)),
          ),
        ],
      ),
    );
  }
}
