// 设置页的共用件：折叠分组标题、信息行。
//
// 为什么单独拿出来：设置页里有 8 个分组、每个都要「标题 + 展开/收起」这套壳，
// 而壳的实现（NeuSection + _expanded 集合的读写）原先写在 State 类里，
// 于是任何一个分组想抽成独立组件都会被它卡住 —— 抽出去之后分组才能各自独立。
//
// 这两个组件都是**无状态**的：展开与否由调用方传 `open`，点击由调用方收 `onToggle`。
// 状态仍然集中在设置页的 State 里（一个 Set<String>），只是渲染解耦了。

import 'package:flutter/material.dart';

import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../neu_icons.dart';
import '../../neu_section.dart';

/// 设置页的一个可折叠分组标题。
///
/// 与 [NeuSection] 的区别：[NeuSection] 是纯展示（只管长什么样），
/// 这里多带了一层「设置页的语义」—— 不过其实也只是转发。
/// 保留这层是为了让 8 个调用点的签名统一，将来要加东西（比如左侧留白差异）
/// 只改这一处。
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.open,
    required this.onToggle,
    this.icon = IconId.circle,
    this.summary,
  });

  final String title;
  final bool open;
  final VoidCallback onToggle;
  final IconId icon;

  /// 收起时显示的一行状态摘要（例如「未连接」「3 个工作区」）。
  final String? summary;

  @override
  Widget build(BuildContext context) {
    return NeuSection(
      title: title,
      icon: icon,
      summary: summary,
      open: open,
      onToggle: onToggle,
    );
  }
}

/// 「标签 —— 值」一行，值用等宽字体（版本号、路径、计数这类对齐才好读）。
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NeuSpace.n4),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.muted)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: NeuFonts.bodySmall,
              color: t.fg,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
