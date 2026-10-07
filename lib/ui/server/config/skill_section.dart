// AI 配置页的「ui.a9cec18e05」分组（由 tool/extract_config_section.py 机械搬运后人工校对）。
//
// 约定同 config/widgets.dart：组件不持有状态，用到的数据都由页面传进来。

import 'package:flutter/material.dart';

import '../../../server/chat_models.dart';
import '../../../server/i18n.dart';
import '../../../server/server_store.dart';
import '../../../server/server_types.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../collapsible_text.dart';
import '../../neu_icons.dart';
import 'rows.dart';
import 'widgets.dart';

class SkillSection extends StatelessWidget {
  const SkillSection({
    super.key,
    required this.packageUpdateError,
    required this.packages,
    required this.packagesBusy,
    required this.updates,
    required this.store,
    required this.open,
    required this.onToggle,
    required this.isOpen,
    required this.onOpenGroup,
    required this.onViewSkill,
    required this.isSectionOpen,
    required this.onToggleSection,
    required this.onRemovePackage,
    required this.onInstallPackage,
    required this.onUpdatePackages,
  });

  final String? packageUpdateError;
  final List<PiPackageInfo> packages;
  final bool packagesBusy;
  final List<PackageUpdateInfo> updates;
  final ServerStore store;
  final bool open;
  final VoidCallback onToggle;

  /// 子组（技能/扩展/内置）自己的开合，以及「点开看 SKILL.md」——
  /// 后者的实现要读服务端，按约定留在页面侧。
  final bool Function(String) isOpen;
  final void Function(String) onOpenGroup;
  final void Function(SlashCommand) onViewSkill;

  /// 插件子分组自己的开合，以及装/卸/更新 —— 后三个要动服务端与磁盘，
  /// 按约定留在页面侧。
  final bool Function(String) isSectionOpen;
  final void Function(String) onToggleSection;
  final void Function(PiPackageInfo) onRemovePackage;
  final Future<void> Function() onInstallPackage;
  final Future<void> Function() onUpdatePackages;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    const icon = IconId.cmd;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
      ConfigSection(
        title: I18n.t('ui.a9cec18e05'),
        icon: icon,
        open: open,
        onToggle: onToggle,
      ),
      if (open) ...[
      NeuRaised(
        radius: NeuRadii.md,
        level: NeuLevel.small,
        padding: EdgeInsets.all(NeuSpace.n6),
        child: Column(
          children: [
            CommandGroup(isOpen: isOpen, onOpen: onOpenGroup, title: I18n.t('ui.699143b15a'),
              items: store.commandsBySource('skill'),
              // 技能点开就能看 SKILL.md 全文 —— pi-web 里技能也是可查看的
              onTapItem: onViewSkill,
              tapHint: I18n.t('ui.9822a4f972'),
            ),
            CommandGroup(isOpen: isOpen, onOpen: onOpenGroup, title: I18n.t('ui.aecb607774'),
              items: store.commandsBySource('extension'),
              // 扩展命令必须由会话启动时注册，没会话就取不到 ——
              // 这里说清楚原因，别让人以为一个扩展都没装
              emptyHint: store.extensionCommandsAvailable ? I18n.t('ui.d81bb206a8') : I18n.t('ui.4d4a4242b1'),
            ),
            CommandGroup(isOpen: isOpen, onOpen: onOpenGroup, title: I18n.t('ui.f96de32b76'), items: store.commandsBySource('builtin')),
          ],
        ),
      ),
      ],

      // 插件组同样默认收起（10 个插件展开就是一屏）
      ConfigSection(
        title: I18n.tp('ui.9d3c5fe8d6', {
          'count': packages.isEmpty ? '' : '（${packages.length}）',
        }),
        icon: IconId.serverPlus,
        // 标题带计数，展开状态挂在不随计数变的键上
        open: isSectionOpen('plugins'),
        onToggle: () => onToggleSection('plugins'),
      ),
      if (isSectionOpen('plugins')) ...[
      NeuRaised(
        radius: NeuRadii.md,
        level: NeuLevel.small,
        padding: const EdgeInsets.all(NeuSpace.n6),
        child: Column(
          children: [
            if (packages.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: NeuSpace.n10),
                child: Text(I18n.t('ui.606276afd3'), style: TextStyle(fontSize: NeuFonts.sub, color: t.muted)),
              )
            else
              for (var i = 0; i < packages.length; i++) ...[
                if (i > 0) Container(height: 1, color: t.border),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n10, vertical: NeuSpace.n8),
                  child: Row(
                    children: [
                      NeuIcon(IconId.download, size: 15, color: t.accentInk),
                      const SizedBox(width: NeuSpace.n10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              packages[i].source.replaceFirst('npm:', ''),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.fg),
                            ),
                            CollapsibleText(
                              text: packages[i].installedPath ??
                                  I18n.tp('ui.dfe094795b', {'scope': packages[i].scope}),
                              // 安装路径是关键信息（截断等于没给），
                              // 但它常占 2–3 行 —— 默认收一行、点开看全。
                              style: TextStyle(fontSize: NeuFonts.micro, color: t.muted),
                            ),
                            // 中文注释：这个包在电脑端被汉化了多少处
                            // （数据来自 ~/.pi/agent/hanhua-auto.json，不是我们另编的）
                            if (packages[i].zhCount > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: NeuSpace.n2),
                                child: Text(
                                  I18n.tp('ui.ebd66f8a1f', {'n': packages[i].zhCount}),
                                  style: TextStyle(fontSize: NeuFonts.micro, color: t.accentInk),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (updates.any((u) => u.source == packages[i].source))
                        Text(I18n.t('ui.b48cca48ed'), style: TextStyle(fontSize: NeuFonts.tiny, color: t.warn)),
                      NeuPressable(
                        onTap: packagesBusy ? null : () => onRemovePackage(packages[i]),
                        radius: 10,
                        padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
                        child: NeuIcon(IconId.trash, size: 14, color: t.danger),
                      ),
                    ],
                  ),
                ),
              ],
            Container(height: 1, color: t.border),
            Row(
              children: [
                Expanded(
                  child: NeuPressable(
                    onTap: packagesBusy ? null : onInstallPackage,
                    flat: true,
                    padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        NeuIcon(IconId.plus, size: 15, color: t.accentInk),
                        SizedBox(width: NeuSpace.n8),
                        Text(I18n.t('ui.49c24aafc0'),
                            style: TextStyle(fontSize: NeuFonts.bodyMid, color: t.accentInk)),
                      ],
                    ),
                  ),
                ),
                Container(width: 1, height: 22, color: t.border),
                Expanded(
                  child: NeuPressable(
                    onTap: packagesBusy ? null : onUpdatePackages,
                    flat: true,
                    padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        NeuIcon(IconId.sync, size: 15, color: t.accentInk),
                        SizedBox(width: NeuSpace.n8),
                        Text(
                          packagesBusy
                              ? I18n.t('ui.cf978c0252')
                              : (updates.isEmpty ? I18n.t('ui.7f28d733a5') : I18n.tp('ui.800e3b5963', {'n': updates.length})),
                          style: TextStyle(fontSize: NeuFonts.bodyMid, color: t.accentInk),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (packageUpdateError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: NeuSpace.n8),
                child: Text(I18n.tp('ui.bc346bf8af', {'e': packageUpdateError}),
                    style: TextStyle(fontSize: NeuFonts.micro, color: t.muted)),
              ),
          ],
        ),
      ),
      ],

      // 分组内容默认收起：AI 配置页分组多、每组都长，全展开看不出层次

      ],
    );
  }
}
