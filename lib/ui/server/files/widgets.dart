// 工作区文件页（`files_page.dart`）的共用件。
//
// 约定同其它页面（见 docs/refactor-status.md）：组件不持有状态，
// 需要的数据与动作都由页面传进来。

import 'package:flutter/material.dart';

import '../../../server/i18n.dart';
import '../../../server/server_types.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../neu_icons.dart';

/// 底部面板顶部的小把手（就是个视觉提示，不可点）。
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: t.muted.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(NeuRadii.hairline),
        ),
      ),
    );
  }
}

/// 页面内的小节标题（文件列表、Git、Worktrees 各自一段）。
class FilesSectionTitle extends StatelessWidget {
  const FilesSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Padding(
      padding: const EdgeInsets.only(top: NeuSpace.n14, bottom: NeuSpace.n8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: NeuFonts.sectionTitle,
          fontWeight: FontWeight.w700,
          color: t.onBg,
        ),
      ),
    );
  }
}

/// 一行 git 改动（点一下看 diff）。
class GitRow extends StatelessWidget {
  const GitRow(this.change, this.onShowDiff, {super.key});

  final GitChange change;
  final void Function(String path) onShowDiff;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    // 未跟踪用强调色、删除用危险色、其余当成功色 —— 一眼能分出性质
    final statusColor = change.status == '??'
        ? t.accentInk
        : change.status.contains('D')
        ? t.danger
        : t.success;

    return NeuPressable(
      flat: true,
      onTap: () => onShowDiff(change.path),
      padding: const EdgeInsets.symmetric(
        horizontal: NeuSpace.n10,
        vertical: NeuSpace.n10,
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            alignment: Alignment.centerLeft,
            child: Text(
              change.status.isEmpty ? 'M' : change.status,
              style: TextStyle(
                fontSize: NeuFonts.badge,
                fontFamily: 'monospace',
                color: statusColor,
              ),
            ),
          ),
          const SizedBox(width: NeuSpace.n6),
          Expanded(
            child: Text(
              change.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: NeuFonts.sub, color: t.fg),
            ),
          ),
          NeuIcon(IconId.chevronRight, size: 13, color: t.muted),
        ],
      ),
    );
  }
}

/// 一个 worktree：主工作树不能删；其它可以删、可以「用它开会话」
class WorktreeRow extends StatelessWidget {
  const WorktreeRow(
    this.wt, {
    super.key,
    required this.onOpenSession,
    required this.onRemove,
  });

  final WorktreeInfo wt;
  final void Function(String dir) onOpenSession;
  final void Function(WorktreeInfo wt) onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final short =
        wt.path
            .replaceAll('\\', '/')
            .split('/')
            .where((s) => s.isNotEmpty)
            .lastOrNull ??
        wt.path;
    final branch =
        wt.branch ?? (wt.detached ? '(detached)' : I18n.t('ui.a3645c3f66'));
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NeuSpace.n10,
        vertical: NeuSpace.n8,
      ),
      child: Row(
        children: [
          NeuIcon(
            IconId.folder,
            size: 15,
            color: wt.isMain ? t.accentInk : t.muted,
          ),
          const SizedBox(width: NeuSpace.n10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        short,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: NeuFonts.bodySmall,
                          color: t.fg,
                        ),
                      ),
                    ),
                    if (wt.isMain) ...[
                      SizedBox(width: NeuSpace.n6),
                      Text(
                        I18n.t('ui.36e8fd3177'),
                        style: TextStyle(
                          fontSize: NeuFonts.tiny,
                          color: t.accentInk,
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  '$branch · ${wt.path}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: NeuFonts.micro, color: t.muted),
                ),
              ],
            ),
          ),
          NeuPressable(
            onTap: () => onOpenSession(wt.path),
            radius: 10,
            padding: EdgeInsets.symmetric(
              horizontal: NeuSpace.n13,
              vertical: NeuSpace.n13,
            ),
            child: Text(
              I18n.t('ui.c33f0e7bb9'),
              style: TextStyle(fontSize: NeuFonts.badge, color: t.accentInk),
            ),
          ),
          if (!wt.isMain)
            NeuPressable(
              onTap: () => onRemove(wt),
              radius: 10,
              padding: const EdgeInsets.symmetric(
                horizontal: NeuSpace.n13,
                vertical: NeuSpace.n13,
              ),
              child: NeuIcon(IconId.trash, size: 14, color: t.danger),
            ),
        ],
      ),
    );
  }
}

/// 面包屑：把路径切成可点的一段段，最后一段是不可点的当前目录
class Breadcrumb extends StatelessWidget {
  const Breadcrumb(this.path, {super.key, required this.onOpenDir});

  final String path;
  final void Function(String target) onOpenDir;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final parts = path
        .replaceAll('\\', '/')
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return const SizedBox.shrink();

    final segments = <(String, String)>[];
    var acc = '';
    for (var i = 0; i < parts.length; i++) {
      acc = i == 0 ? parts[i] : '$acc/${parts[i]}';
      segments.add((parts[i], acc));
    }

    return SizedBox(
      height: 22,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: segments.length,
        itemBuilder: (context, i) {
          final seg = segments[i];
          final last = i == segments.length - 1;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n1),
                  child: Text(
                    '/',
                    style: TextStyle(fontSize: NeuFonts.label, color: t.muted),
                  ),
                ),
              NeuPressable(
                // 当前目录不可点（点了没意义）
                onTap: last ? null : () => onOpenDir(seg.$2),
                radius: 6,
                padding: const EdgeInsets.symmetric(
                  horizontal: NeuSpace.n4,
                  vertical: NeuSpace.n2,
                ),
                child: Text(
                  seg.$1,
                  style: TextStyle(
                    fontSize: NeuFonts.label,
                    color: last ? t.fg : t.accentInk,
                    fontWeight: last ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

String readableSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

IconId iconForEntry(FileEntry entry) {
  if (entry.isDir) return IconId.folder;
  final n = entry.name.toLowerCase();
  if (n.endsWith('.md') || n.endsWith('.txt') || n.endsWith('.rst')) {
    return IconId.pen;
  }
  if (n.endsWith('.png') ||
      n.endsWith('.jpg') ||
      n.endsWith('.jpeg') ||
      n.endsWith('.webp') ||
      n.endsWith('.gif') ||
      n.endsWith('.svg')) {
    return IconId.image;
  }
  if (n.endsWith('.dart') ||
      n.endsWith('.js') ||
      n.endsWith('.mjs') ||
      n.endsWith('.ts') ||
      n.endsWith('.py') ||
      n.endsWith('.kt') ||
      n.endsWith('.swift') ||
      n.endsWith('.json') ||
      n.endsWith('.yaml') ||
      n.endsWith('.yml') ||
      n.endsWith('.sh')) {
    return IconId.cmd;
  }
  return IconId.bubble;
}

/// 文件/目录列表里的一行（点一下进目录或预览）。
class FileRow extends StatelessWidget {
  const FileRow(this.entry, {super.key, required this.onEnter});

  final FileEntry entry;
  final void Function(FileEntry entry) onEnter;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return NeuPressable(
      flat: true,
      onTap: () => onEnter(entry),
      // 行高从 10 提到 13：手指点的目标高过 44dp 才不会误触下一行
      padding: const EdgeInsets.symmetric(
        horizontal: NeuSpace.n10,
        vertical: NeuSpace.n13,
      ),
      child: Row(
        children: [
          NeuIcon(
            iconForEntry(entry),
            size: 16,
            color: entry.isDir ? t.accentInk : t.muted,
          ),
          const SizedBox(width: NeuSpace.n10),
          Expanded(
            child: Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: NeuFonts.bodyMid, color: t.fg),
            ),
          ),
          if (!entry.isDir)
            Text(
              readableSize(entry.size),
              style: TextStyle(fontSize: NeuFonts.micro, color: t.muted),
            ),
          const SizedBox(width: NeuSpace.n6),
          NeuIcon(IconId.chevronRight, size: 13, color: t.muted),
        ],
      ),
    );
  }
}
