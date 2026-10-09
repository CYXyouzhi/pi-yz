// AI 配置页（`config_page.dart`）的共用件。
//
// 与设置页的做法一致：状态留在 `_ConfigPageState`，
// 组件只收 open / onToggle 与渲染所需的数据；这样分组才能各自抽出去。

import 'package:flutter/material.dart';

import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../neu_icons.dart';
import '../../neu_section.dart';

/// 可折叠分组的标题。
///
/// 比设置页那版多一个 [stateKey]：配置页有几处标题是动态的（比如带数量），
/// 而展开状态要用一个稳定的键去记 —— 否则标题一变，展开状态就丢了。
class ConfigSection extends StatelessWidget {
  const ConfigSection({
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

/// 一行「标签 + 一排可选项」。
///
/// [labels] 用于把内部值映射成给人看的文本（例如把 `system` 显示成「跟随系统」）；
/// 没给映射就直接显示原值。
class ChoiceRow extends StatelessWidget {
  const ChoiceRow(
    this.label,
    this.values,
    this.current,
    this.onPick, {
    super.key,
    this.labels = const {},
  });

  final String label;
  final List<String> values;
  final String current;
  final ValueChanged<String> onPick;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Row(
      children: [
        SizedBox(
          width: 62,
          child: Text(
            label,
            style: TextStyle(fontSize: NeuFonts.sub, color: t.muted),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            children: [
              for (final value in values)
                NeuPressable(
                  onTap: () => onPick(value),
                  flat: current != value,
                  alwaysInset: current == value,
                  radius: NeuRadii.sm,
                  padding: const EdgeInsets.symmetric(
                    horizontal: NeuSpace.n12,
                    vertical: NeuSpace.n7,
                  ),
                  child: Text(
                    labels[value] ?? value,
                    style: TextStyle(
                      fontSize: NeuFonts.small,
                      color: current == value ? t.accentInk : t.muted,
                      fontWeight: current == value
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 对话框里的单行输入壳子（MCP 添加 / 凭据添加 / 安装包来源都用它）。
///
/// 从 config_page 提上来的原因：抽 MCP 分组时它被页面和组件同时需要，
/// 留在页面里会让组件反过来依赖页面。
Widget dialogField(
  NeuTokens t,
  TextEditingController controller,
  String hint,
) => NeuInset(
  radius: NeuRadii.sm,
  padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12),
  child: TextField(
    controller: controller,
    style: TextStyle(fontSize: NeuFonts.bodyMid, color: t.fg),
    decoration: InputDecoration(
      isDense: true,
      border: InputBorder.none,
      hintText: hint,
      hintStyle: TextStyle(fontSize: NeuFonts.bodySmall, color: t.muted),
      contentPadding: const EdgeInsets.symmetric(vertical: NeuSpace.n12),
    ),
  ),
);
