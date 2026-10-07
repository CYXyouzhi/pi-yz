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
import '../../../server/i18n.dart';

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

/// 小标题（带上方留白，用来分隔同一分组里的几段设置）。
class PrefLabel extends StatelessWidget {
  const PrefLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Padding(
      padding: const EdgeInsets.only(top: NeuSpace.n12, bottom: NeuSpace.n6),
      child: Text(text, style: TextStyle(fontSize: NeuFonts.small, color: t.muted)),
    );
  }
}

/// 一行开关（状态直接写在右侧的按钮上，不靠颜色猜）。
///
/// 刻意不用 Switch：设计稿是「凹/凸」材质那一套，与全局的 NeuPressable 一致。
class NotifToggle extends StatelessWidget {
  const NotifToggle(this.label, this.value, this.onChanged, {super.key});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NeuSpace.n3),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: NeuFonts.bodyMid, color: t.fg)),
          ),
          NeuPressable(
            onTap: () => onChanged(!value),
            radius: NeuRadii.sm,
            flat: !value,
            alwaysInset: value,
            padding: EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n7),
            child: Text(
              value ? I18n.t('ui.8493205602') : I18n.t('ui.d58a55bcee'),
              style: TextStyle(
                fontSize: NeuFonts.sub,
                color: value ? t.accentInk : t.muted,
                fontWeight: value ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一行 chip 选择器（选中的那个凹进去）。
class PrefChips extends StatelessWidget {
  const PrefChips(
    this.options, {
    super.key,
    required this.current,
    required this.onPick,
  });

  /// (显示文本, 取值)。用记录类型而不是两个平行 List —— 平行列表迟早会错位。
  final List<(String, double)> options;
  final double current;
  final ValueChanged<double> onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return NeuRaised(
      radius: NeuRadii.sm,
      padding: const EdgeInsets.all(NeuSpace.n4),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: NeuPressable(
                onTap: () => onPick(option.$2),
                flat: (current - option.$2).abs() > 0.001,
                alwaysInset: (current - option.$2).abs() <= 0.001,
                radius: NeuRadii.sm,
                padding: const EdgeInsets.symmetric(vertical: NeuSpace.n9),
                child: Center(
                  child: Text(
                    option.$1,
                    style: TextStyle(
                      fontSize: NeuFonts.sub,
                      color: (current - option.$2).abs() <= 0.001 ? t.accentInk : t.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 一行「当前值 + 一个动作按钮」。
class PrefRow extends StatelessWidget {
  const PrefRow(
    this.value, {
    super.key,
    required this.actionLabel,
    required this.onAction,
  });

  final String value;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return NeuRaised(
      radius: NeuRadii.sm,
      padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n10, vertical: NeuSpace.n6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              // 值可能很长（例如聚合后的模型列表），硬切等于把信息藏起来
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: NeuFonts.small, color: t.fg),
            ),
          ),
          NeuPressable(
            onTap: onAction,
            radius: 8,
            flat: true,
            padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n10, vertical: NeuSpace.n5),
            child: Text(
              actionLabel,
              style: TextStyle(fontSize: NeuFonts.sub, color: t.accentInk),
            ),
          ),
        ],
      ),
    );
  }
}
