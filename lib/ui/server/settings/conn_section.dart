// 设置页的「连接」分组：当前连的是哪、刷新会话、断开。
//
// 抽出来的理由与做法见 docs/refactor-status.md：状态留在父级 State，
// 组件只收 open（我展开了吗）与 onToggle（点了要干什么），自己不持有任何字段。

import 'package:flutter/material.dart';

import '../../../server/i18n.dart';
import '../../../server/server_store.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../neu_icons.dart';
import 'widgets.dart';

class ConnSection extends StatelessWidget {
  const ConnSection({
    super.key,
    required this.store,
    required this.open,
    required this.onToggle,
    required this.onOpenConn,
  });

  final ServerStore store;
  final bool open;
  final VoidCallback onToggle;

  /// 打开连接页（由设置页提供，可能是 null —— 那时这一行仍可点，只是没反应）。
  final VoidCallback? onOpenConn;

  /// 连接状态的短标签，收起态要显示它。
  String _stateLabel() => switch (store.state) {
    ServerConnectionState.connected =>
      '${I18n.t('common.connected')} · ${store.activeEndpoint?.label ?? store.target?.label ?? ''}',
    ServerConnectionState.connecting => I18n.t('common.connecting'),
    ServerConnectionState.error =>
      store.errorMessage ?? I18n.t('common.connFailed'),
    ServerConnectionState.disconnected => I18n.t('common.disconnected'),
  };

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final key = I18n.t('settings.conn', context: context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSection(
          title: key,
          icon: IconId.server,
          summary: _stateLabel(),
          open: open,
          onToggle: onToggle,
        ),
        if (open) ...[
          NeuRaised(
            radius: NeuRadii.lg,
            padding: const EdgeInsets.all(NeuSpace.n16),
            child: Column(
              children: [
                NeuPressable(
                  onTap: onOpenConn,
                  flat: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: NeuSpace.n12,
                    vertical: NeuSpace.n12,
                  ),
                  child: Row(
                    children: [
                      NeuIcon(IconId.server, size: 17, color: t.accentInk),
                      const SizedBox(width: NeuSpace.n12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              // 显示**实际连上的**那个地址：配了备用地址且回落成功时，
                              // 这里会和主地址不同 —— 不显示的话，用户根本不知道
                              // 现在走的是局域网还是 VPN，排查问题只能靠猜。
                              store.activeEndpoint?.label ??
                                  store.target?.label ??
                                  I18n.t('ui.95af3b54e0'),
                              style: TextStyle(
                                fontSize: NeuFonts.bodyTight,
                                color: t.fg,
                              ),
                            ),
                            if (store.activeEndpoint?.isFallback == true) ...[
                              SizedBox(height: NeuSpace.n2),
                              Text(
                                I18n.t('conn.viaFallback'),
                                style: TextStyle(
                                  fontSize: NeuFonts.badge,
                                  color: t.muted,
                                ),
                              ),
                            ],
                            SizedBox(height: NeuSpace.n2),
                            Text(
                              switch (store.state) {
                                ServerConnectionState.connected => I18n.tp(
                                  'ui.b083df935e',
                                  {'v': store.health?.piVersion ?? ''},
                                ),
                                ServerConnectionState.connecting => I18n.t(
                                  'common.connecting',
                                ),
                                ServerConnectionState.error =>
                                  store.errorMessage ??
                                      I18n.t('common.connFailed'),
                                ServerConnectionState.disconnected => I18n.t(
                                  'common.disconnected',
                                ),
                              },
                              style: TextStyle(
                                fontSize: NeuFonts.label,
                                color: t.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      NeuIcon(IconId.chevronRight, size: 16, color: t.muted),
                    ],
                  ),
                ),
                if (store.isConnected) ...[
                  const SizedBox(height: NeuSpace.n10),
                  Row(
                    children: [
                      Expanded(
                        child: NeuPressable(
                          onTap: () => store.loadSessions(refresh: true),
                          radius: NeuRadii.sm,
                          padding: const EdgeInsets.symmetric(
                            horizontal: NeuSpace.n13,
                            vertical: NeuSpace.n13,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              NeuIcon(IconId.sync, size: 14, color: t.muted),
                              SizedBox(width: NeuSpace.n6),
                              Text(
                                I18n.t('ui.5e51feb8f3'),
                                style: TextStyle(
                                  fontSize: NeuFonts.bodySmall,
                                  color: t.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: NeuSpace.n10),
                      Expanded(
                        child: NeuPressable(
                          onTap: () => store.disconnect(),
                          radius: NeuRadii.sm,
                          padding: const EdgeInsets.symmetric(
                            horizontal: NeuSpace.n13,
                            vertical: NeuSpace.n13,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              NeuIcon(IconId.power, size: 14, color: t.danger),
                              SizedBox(width: NeuSpace.n6),
                              Text(
                                I18n.t('ui.9b55c5c9f8'),
                                style: TextStyle(
                                  fontSize: NeuFonts.bodySmall,
                                  color: t.danger,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
