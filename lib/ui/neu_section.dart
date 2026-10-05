import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/neu.dart';
import 'neu_icons.dart';

/// 可折叠分组标题 —— **全 App 共用这一套**。
///
/// ## 为什么要抽出来
///
/// 原先「可折叠」这个概念在三处各写各的：
///   · `settings_page.dart` 一套 `_collapsed`（存"收起来的"，初始为空 = 全部展开）
///   · `sessions_page.dart` 一套 `expandedWorkspaces`（存在 store 里，跨页面保留）
///   · `usage_page.dart` 干脆没有折叠
///
/// 三套的默认状态还不一样（一个默认全开、一个默认全收），用户看到的就是
/// 「有的地方点了会收、有的地方点了没反应」—— 他原话是「好多地方都有这样的问题」。
/// 抽成一个组件后，视觉与交互只有一种，默认状态由调用方传 `open` 决定（但都建议默认收起）。
///
/// ## 两种形态（这是"好看"的关键）
///
/// · **收起时**：一张缩略卡片 —— 图标 + 标题 + 一行摘要 + 右箭头。
///   早前收起后只剩「纯文字 + 右箭头」，没有任何容器，看起来像没做完；
///   用户的原话是「收起来一点都不美观太丑了」。摘要那行不是装饰：
///   它让收起时**仍然看得到这块的状态**（连没连上、几个工作区、什么主题），
///   否则收起就等于"把信息藏起来"，而不是"整理"。
///
/// · **展开时**：普通标题行（不带卡片底色）。否则标题一张卡片、内容又一张卡片，
///   两层叠着反而更碎。
class NeuSection extends StatelessWidget {
  const NeuSection({
    super.key,
    required this.title,
    required this.open,
    required this.onToggle,
    this.icon = IconId.circle,
    this.summary,
    this.trailing,
  });

  final String title;
  final bool open;
  final VoidCallback onToggle;
  final IconId icon;

  /// 收起时显示的一行状态摘要。展开后不再显示（内容自己会说话）。
  final String? summary;

  /// 标题行右侧的额外控件（例如「+ 新增」按钮）。
  /// 有它的时候整行不再可点 —— 免得点「新增」却把分组收起来了。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    // 取到局部变量：Dart 的类型提升对字段不生效（字段可能在检查后被改），
    // 所以 `summary != null && summary.isNotEmpty` 这种写法在字段上会报
    // unchecked_use_of_nullable_value。
    final summaryText = summary;

    final header = Row(
      children: [
        NeuIcon(icon, size: 17, color: open ? t.accentInk : t.muted),
        SizedBox(width: NeuSpace.n12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: NeuFonts.sectionTitle,
                  fontWeight: FontWeight.w700,
                  color: open ? t.accentInk : t.onBg,
                ),
              ),
              if (!open && summaryText != null && summaryText.isNotEmpty) ...[
                SizedBox(height: NeuSpace.n2),
                Text(
                  summaryText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: NeuFonts.badge, color: t.muted),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          SizedBox(width: NeuSpace.n8),
          trailing!,
        ] else
          NeuIcon(
            open ? IconId.chevronDown : IconId.chevronRight,
            size: 16,
            color: t.muted,
          ),
      ],
    );

    // trailing 存在时整行不可点（否则点「+ 新增」会连带切换折叠状态）；
    // 那种场景下折叠由 trailing 里的控件自己或外层负责。
    final body = trailing == null
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: header,
          )
        : header;

    return open
        ? Padding(
            padding: const EdgeInsets.only(bottom: NeuSpace.n8),
            child: body,
          )
        : Padding(
            padding: const EdgeInsets.only(bottom: NeuSpace.n10),
            child: NeuRaised(
              radius: NeuRadii.lg,
              padding: const EdgeInsets.symmetric(
                horizontal: NeuSpace.n14,
                vertical: NeuSpace.n12,
              ),
              child: body,
            ),
          );
  }
}
