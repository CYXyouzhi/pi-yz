import 'package:flutter/material.dart';

import '../../../server/chat_reducer.dart';
import '../../../server/i18n.dart';
import '../../../server/server_store.dart';
import '../../../services/key_encoder.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../neu_icons.dart';
import 'sheets.dart';

/// _footerAction 的组件化版本。
class FooterAction extends StatelessWidget {
  const FooterAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

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
      padding: const EdgeInsets.symmetric(
        horizontal: NeuSpace.n14,
        vertical: NeuSpace.n14,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          NeuIcon(icon, size: 12, color: t.muted),
          const SizedBox(width: NeuSpace.n4),
          Text(
            label,
            style: TextStyle(fontSize: NeuFonts.badge, color: t.muted),
          ),
        ],
      ),
    );
  }
}

/// _buildTurnFooter 的组件化版本。
class TurnFooter extends StatelessWidget {
  const TurnFooter({
    super.key,
    required this.store,
    required this.chat,
    required this.onContinue,
    required this.onRedo,
    required this.onSummary,
  });

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
      padding: const EdgeInsets.fromLTRB(
        NeuSpace.n18,
        0,
        NeuSpace.n18,
        NeuSpace.n4,
      ),
      child: Row(
        children: [
          if (hasChanges)
            Expanded(
              child: NeuPressable(
                onTap: () => showTurnSummarySheet(context, summary),
                flat: true,
                radius: NeuRadii.sm,
                padding: const EdgeInsets.symmetric(
                  horizontal: NeuSpace.n14,
                  vertical: NeuSpace.n14,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NeuIcon(IconId.pen, size: 12, color: t.accentInk),
                    SizedBox(width: NeuSpace.n5),
                    Flexible(
                      child: Text(
                        I18n.tp('ui.9069e11411', {
                          'files': summary.files.length,
                          'added': summary.added,
                          'removed': summary.removed,
                        }),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: NeuFonts.badge,
                          color: t.accentInk,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SizedBox(width: NeuSpace.n8),
          FooterAction(
            icon: IconId.send,
            label: I18n.t('ui.27ca568be2'),
            onTap: onContinue,
          ),
          SizedBox(width: NeuSpace.n6),
          FooterAction(
            icon: IconId.sync,
            label: I18n.t('ui.7f7c7dcf89'),
            onTap: () => onRedo(),
          ),
        ],
      ),
    );
  }
}

/// _infoLine 的组件化版本。
class InfoLine extends StatelessWidget {
  const InfoLine(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NeuSpace.n3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              label,
              style: TextStyle(fontSize: NeuFonts.sub, color: t.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: NeuFonts.sub,
                color: t.fg,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

int countTree(List<dynamic> nodes) {
  var total = 0;
  for (final node in nodes) {
    if (node is! Map) continue;
    total += 1;
    final children = node['children'];
    if (children is List) total += countTree(children);
  }
  return total;
}

String formatTokens(int? value) {
  if (value == null) return '?';
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(2)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
  return '$value';
}

/// 把分支树压成带缩进的列表（深度优先）。
///
/// **递归函数**：子节点还要再调自己，所以 `t`、`leafId` 与两个回调一直往下传。
/// 不接 `BuildContext` —— `t` 由调用方给，递归时原样传下去就行。
/// 「从这条分叉」（`onFork`）与「跳回这条」（`onNavigate`）都走回调，函数本身不碰 store。
List<Widget> treeRows(
  NeuTokens t,
  List<dynamic> nodes,
  int depth,
  String? leafId, {
  required void Function(String id, String preview) onFork,
  required void Function(String id, String preview) onNavigate,
}) {
  final rows = <Widget>[];
  for (final node in nodes) {
    if (node is! Map) continue;
    final entry = (node['entry'] ?? node) as Map;
    final id = entry['id']?.toString();
    final message = entry['message'] as Map?;
    final role =
        message?['role']?.toString() ?? entry['type']?.toString() ?? '?';

    String preview = '';
    final content = message?['content'];
    if (content is String) {
      preview = content;
    } else if (content is List) {
      for (final block in content) {
        if (block is Map && block['type'] == 'text') {
          preview = block['text']?.toString() ?? '';
          break;
        }
      }
    }
    // 把所有空白（含换行）压成单个空格；用正则避免在源码里写转义换行
    preview = preview.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (preview.length > 42) preview = '${preview.substring(0, 42)}…';

    final isLeaf = id != null && id == leafId;
    final children = node['children'];
    final childCount = children is List ? children.length : 0;
    // 分叉点标出来：这里曾经有过另一条路
    final branchHint = childCount > 1
        ? I18n.tp('ui.5bbb1a9d41', {'n': childCount})
        : '';

    final rowContent = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (depth > 0)
          Padding(
            padding: const EdgeInsets.only(
              right: NeuSpace.n6,
              top: NeuSpace.n1,
            ),
            child: NeuIcon(IconId.chevronRight, size: 12, color: t.muted),
          ),
        Expanded(
          child: Text(
            '${isLeaf ? '● ' : ''}$role${preview.isEmpty ? '' : ' · $preview'}$branchHint',
            style: TextStyle(
              fontSize: NeuFonts.small,
              height: 1.5,
              color: isLeaf ? t.accentInk : t.fg,
              fontWeight: isLeaf ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        // 从这里分出一条新会话（复制历史 + 回退到该节点）
        if (id != null && !isLeaf)
          NeuPressable(
            onTap: () => onFork(id, preview),
            radius: 10,
            // 触控目标 13 + 14×2 = 41dp；原本 23dp（13+5×2），手指按不准
            padding: const EdgeInsets.all(NeuSpace.n14),
            child: NeuIcon(IconId.plus, size: 13, color: t.muted),
          ),
      ],
    );

    rows.add(
      Padding(
        padding: EdgeInsets.only(left: depth * 14.0),
        child: isLeaf || id == null
            // 当前节点不可点；其余节点点一下切过去
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: NeuSpace.n3),
                child: rowContent,
              )
            : NeuPressable(
                flat: true,
                onTap: () => onNavigate(id, preview),
                padding: const EdgeInsets.symmetric(
                  vertical: NeuSpace.n6,
                  horizontal: NeuSpace.n4,
                ),
                child: rowContent,
              ),
      ),
    );

    if (children is List && children.isNotEmpty) {
      rows.addAll(
        treeRows(
          t,
          children,
          depth + 1,
          leafId,
          onFork: onFork,
          onNavigate: onNavigate,
        ),
      );
    }
  }
  return rows;
}

String decodeKey(String seq) {
  if (seq == KeyEncoder.esc) return 'esc';
  if (seq == KeyEncoder.tab) return 'tab';
  if (seq == KeyEncoder.shiftTab) return 'shift-tab';
  if (seq == '\x1b[Z') return 'shift-tab';
  if (seq == '\x03' || seq == KeyEncoder.ctrlLetter('c')) return 'ctrl-c';
  if (seq == '\r' || seq == '\n') return 'enter';
  // CSI 序列：ESC [ 参数? 终结符 —— 参数可能带修饰键（如 1;5A = Ctrl+↑）
  final m = RegExp(r'^\x1b\[(?:(\d+)(?:;(\d+))?)?([A-Za-z~])$').firstMatch(seq);
  if (m == null) return '';
  final tail = m.group(3)!;
  return switch (tail) {
    'A' => 'up',
    'B' => 'down',
    'C' => 'right',
    'D' => 'left',
    'H' => 'home',
    'F' => 'end',
    'Z' => 'shift-tab',
    '~' => switch (m.group(1)) {
      '1' => 'home',
      '3' => 'delete',
      '4' => 'end',
      '5' => 'page-up',
      '6' => 'page-down',
      _ => '',
    },
    _ => '',
  };
}
