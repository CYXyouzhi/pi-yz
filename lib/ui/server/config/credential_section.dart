// AI 配置页的「ui.c4d89641a1」分组（由 tool/extract_config_section.py 机械搬运后人工校对）。
//
// 约定同 config/widgets.dart：组件不持有状态，用到的数据都由页面传进来。

import 'package:flutter/material.dart';

import '../../../server/i18n.dart';
import '../../../server/server_types.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../neu_icons.dart';
import 'widgets.dart';

class CredentialSection extends StatelessWidget {
  const CredentialSection({
    super.key,
    required this.credentials,
    required this.open,
    required this.onToggle,
    required this.onRemoveCredential,
    required this.onLoginProvider,
    required this.onAddCredential,
  });

  final List<CredentialInfo> credentials;
  final bool open;
  final VoidCallback onToggle;

  /// 增删凭据与登录 provider 都要动服务端，按约定留在页面侧，这里只触发。
  final Future<void> Function(String provider) onRemoveCredential;
  final Future<void> Function() onLoginProvider;
  final Future<void> Function() onAddCredential;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    const icon = IconId.lock;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
      ConfigSection(
        title: I18n.t('ui.c4d89641a1'),
        icon: icon,
        open: open,
        onToggle: onToggle,
      ),
      if (open) ...[
      NeuRaised(
        radius: NeuRadii.md,
        level: NeuLevel.small,
        padding: const EdgeInsets.all(NeuSpace.n6),
        child: Column(
          children: [
            if (credentials.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: NeuSpace.n12),
                child: Text(I18n.t('ui.3a61229d9e'),
                    style: TextStyle(fontSize: NeuFonts.small, color: t.muted)),
              )
            else
              for (var i = 0; i < credentials.length; i++) ...[
                if (i > 0) Container(height: 1, color: t.border),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n10, vertical: NeuSpace.n6),
                  child: Row(
                    children: [
                      NeuIcon(IconId.lock, size: 15, color: t.accentInk),
                      const SizedBox(width: NeuSpace.n10),
                      Expanded(
                        child: Text(
                          credentials[i].provider,
                          style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.fg),
                        ),
                      ),
                      Text(
                        credentials[i].type,
                        style: TextStyle(fontSize: NeuFonts.micro, color: t.muted),
                      ),
                      const SizedBox(width: NeuSpace.n8),
                      NeuPressable(
                        onTap: () => onRemoveCredential(credentials[i].provider),
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
                    onTap: onLoginProvider,
                    flat: true,
                    padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        NeuIcon(IconId.lock, size: 15, color: t.accentInk),
                        SizedBox(width: NeuSpace.n8),
                        Text(I18n.t('ui.4be9b33847'),
                            style: TextStyle(fontSize: NeuFonts.bodyMid, color: t.accentInk)),
                      ],
                    ),
                  ),
                ),
                Container(width: 1, height: 22, color: t.border),
                Expanded(
                  child: NeuPressable(
                    onTap: onAddCredential,
                    flat: true,
                    padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        NeuIcon(IconId.plus, size: 15, color: t.accentInk),
                        SizedBox(width: NeuSpace.n8),
                        Text(I18n.t('ui.8a31d0428f'),
                            style: TextStyle(fontSize: NeuFonts.bodyMid, color: t.accentInk)),
                      ],
                    ),
                  ),
                ),
              ],
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
