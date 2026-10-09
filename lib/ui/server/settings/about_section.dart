// 设置页的「关于」分组。
//
// 抽出来的理由与做法见 docs/refactor-status.md：状态留在父级 State，
// 组件只收 open（我展开了吗）与 onToggle（点了要干什么），自己不持有任何字段。

import 'package:flutter/material.dart';

import '../../../server/i18n.dart';
import '../../../server/server_store.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../collapsible_text.dart';
import '../../neu_icons.dart';
import 'widgets.dart';

class AboutSection extends StatelessWidget {
  const AboutSection({
    super.key,
    required this.store,
    required this.open,
    required this.onToggle,
  });

  final ServerStore store;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final key = I18n.t('settings.about', context: context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSection(
          title: key,
          icon: IconId.info,
          // 收起时能看到 pi 版本，省得为了看版本号把这块展开
          summary: store.health?.piVersion == null
              ? null
              : 'pi ${store.health!.piVersion}',
          open: open,
          onToggle: onToggle,
        ),
        if (open) ...[
          NeuRaised(
            radius: NeuRadii.lg,
            padding: const EdgeInsets.all(NeuSpace.n16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoRow(label: 'App', value: 'pi-yz · pi-yz'),
                InfoRow(
                  label: I18n.t('ui.1de0cfbc46'),
                  value: store.health?.piVersion ?? '—',
                ),
                InfoRow(
                  label: I18n.t('ui.b08caf56ca'),
                  value: '${store.health?.activeSessions ?? 0}',
                ),
                InfoRow(
                  label: I18n.t('ui.f98077685a'),
                  value: '${store.sessions.length}',
                ),
                SizedBox(height: NeuSpace.n6),
                CollapsibleText(
                  // ignore: prefer_interpolation_to_compose_strings
                  text:
                      '${I18n.t('ui.d2bf098e02')}'
                      '${I18n.t('ui.fccbc56d80')}',
                  style: TextStyle(
                    fontSize: NeuFonts.label,
                    height: 1.7,
                    color: t.onBgDim,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
