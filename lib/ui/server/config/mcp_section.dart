import 'package:flutter/material.dart';

import '../../../server/i18n.dart';
import '../../../server/server_store.dart';
import '../../../server/server_types.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../neu_icons.dart';
import '../../neu_toast.dart';
import 'widgets.dart';

/// MCP 分组：列出已配置的 MCP 服务器，可增可删。
///
/// 从 `config_page.dart` 搬出来的一块（连同它的三个私有方法）。约定同其他分组：
/// **状态留在父级 State**，这里只收数据、折叠态与三个回调。
/// `dialogField` 是共享的输入框壳子，已提到 `config/widgets.dart`。
class McpSection extends StatelessWidget {
  const McpSection({
    super.key,
    required this.store,
    required this.servers,
    required this.isOpen,
    required this.onToggle,
    required this.onChanged,
  });

  final ServerStore store;

  /// 已配置的 MCP 服务器列表（父级持有）。
  final List<McpServerInfo> servers;
  final bool Function(String key) isOpen;
  final void Function(String key) onToggle;

  /// 增删成功之后通知父级重新拉取。
  final Future<void> Function() onChanged;

  /// 与父级 `_section` 同名的包装：搬过来的调用点因此不用改一列参数。
  Widget _section(
    String title, {
    IconId icon = IconId.circle,
    String? summary,
  }) => ConfigSection(
    title: title,
    icon: icon,
    summary: summary,
    open: isOpen(title),
    onToggle: () => onToggle(title),
  );

  /// MCP 条目的第二行：类型 · target · args
  /// （写成方法而不是嵌套的三元插值：嵌套同种引号在这种字符串里容易把解析器带沟里）
  String _mcpSubtitle(McpServerInfo info) {
    // 中文注释：不只是把 kind 翻一遍，还说明这类 MCP 是干什么的、参数在哪（合同要求“含义/参数/副作用”）
    final isLocal = info.kind == 'local' || info.kind == 'stdio';
    final parts = <String>[
      isLocal ? I18n.t('ui.91977f0940') : I18n.t('ui.1aef0e1818'),
    ];
    if (info.target.isNotEmpty) parts.add(info.target);
    if (info.args.isNotEmpty) parts.add(info.args);
    if (info.description.isNotEmpty) parts.add(info.description);
    if (!info.enabled) parts.add(I18n.t('ui.69b0f68457'));
    return parts.join('\n');
  }

  /// 添加（或覆盖）一个 MCP 服务器。
  /// 两种形态：本地 stdio（command + args）/ 远程 http（url）—— 对应 pi 的 mcp.json。
  Future<void> _addMcpServer(BuildContext context) async {
    final nameController = TextEditingController();
    final targetController = TextEditingController();
    final argsController = TextEditingController();
    final descController = TextEditingController();
    var scope = 'user';
    var kind = 'stdio';
    final t = context.neu;
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            backgroundColor: t.bg,
            title: Text(
              I18n.t('ui.3bd1c146b5'),
              style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  dialogField(t, nameController, I18n.t('ui.5a47c238fb')),
                  SizedBox(height: NeuSpace.n12),
                  ChoiceRow(
                    I18n.t('ui.4705b88497'),
                    ['user', 'project'],
                    scope,
                    (value) {
                      setDialogState(() => scope = value);
                    },
                    labels: {
                      'user': I18n.t('ui.7b79313922'),
                      'project': I18n.t('ui.98a5faeeaf'),
                    },
                  ),
                  SizedBox(height: NeuSpace.n12),
                  ChoiceRow(
                    I18n.t('ui.226b091218'),
                    ['stdio', 'http'],
                    kind,
                    (value) {
                      setDialogState(() => kind = value);
                    },
                    labels: {
                      'stdio': I18n.t('ui.904333d474'),
                      'http': I18n.t('ui.f40bb45c68'),
                    },
                  ),
                  SizedBox(height: NeuSpace.n12),
                  dialogField(
                    t,
                    targetController,
                    kind == 'stdio'
                        ? I18n.t('ui.c2cad6ac24')
                        : 'url（https://…/mcp）',
                  ),
                  if (kind == 'stdio') ...[
                    SizedBox(height: NeuSpace.n10),
                    dialogField(t, argsController, I18n.t('ui.f8d73b6d3b')),
                  ],
                  SizedBox(height: NeuSpace.n10),
                  dialogField(t, descController, I18n.t('ui.a9f32d22fd')),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(
                  I18n.t('common.cancel'),
                  style: TextStyle(color: t.muted),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(
                  I18n.t('common.save'),
                  style: TextStyle(color: t.accentInk),
                ),
              ),
            ],
          ),
        ),
      );
      if (ok != true || !context.mounted) return;

      final name = nameController.text.trim();
      if (name.isEmpty) {
        NeuToast.show(
          context,
          message: I18n.t('ui.e20009713c'),
          icon: IconId.warn,
        );
        return;
      }
      final target = targetController.text.trim();
      if (target.isEmpty) {
        NeuToast.show(
          context,
          message: kind == 'stdio'
              ? I18n.t('ui.079283b6b1')
              : I18n.t('ui.61d5eeff77'),
          icon: IconId.warn,
        );
        return;
      }
      final config = <String, dynamic>{
        if (kind == 'stdio') 'command': target else 'url': target,
        if (kind == 'stdio' && argsController.text.trim().isNotEmpty)
          'args': argsController.text.trim().split(RegExp(r'\s+')),
        if (descController.text.trim().isNotEmpty)
          'description': descController.text.trim(),
      };
      final saved = await store.saveMcpServer(
        name: name,
        scope: scope,
        config: config,
      );
      if (saved) await onChanged();
    } finally {
      nameController.dispose();
      targetController.dispose();
      argsController.dispose();
      descController.dispose();
    }
  }

  Future<void> _removeMcpServer(
    BuildContext context,
    McpServerInfo server,
  ) async {
    final t = context.neu;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: t.bg,
        title: Text(
          I18n.t('ui.269830c1e6'),
          style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle),
        ),
        content: Text(
          // ignore: prefer_interpolation_to_compose_strings
          '${I18n.tp('ui.af094ee50d', {'scope': server.scope == 'project' ? I18n.t('ui.98a5faeeaf') : I18n.t('ui.7b79313922'), 'name': server.name})}'
          '${I18n.t('ui.2e8c13741c')}',
          style: TextStyle(
            color: t.muted,
            fontSize: NeuFonts.bodyMid,
            height: 1.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              I18n.t('common.cancel'),
              style: TextStyle(color: t.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              I18n.t('common.delete'),
              style: TextStyle(color: t.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final removed = await store.removeMcpServer(
      server.name,
      scope: server.scope,
    );
    if (removed) await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(I18n.t('ui.d7911f414c'), icon: IconId.server),
        if (isOpen(I18n.t('ui.d7911f414c'))) ...[
          NeuRaised(
            radius: NeuRadii.md,
            level: NeuLevel.small,
            padding: const EdgeInsets.all(NeuSpace.n6),
            child: Column(
              children: [
                if (servers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: NeuSpace.n12),
                    child: Center(
                      child: Text(
                        I18n.t('ui.5ab2668c03'),
                        style: TextStyle(
                          fontSize: NeuFonts.small,
                          color: t.muted,
                        ),
                      ),
                    ),
                  )
                else
                  for (var i = 0; i < servers.length; i++) ...[
                    if (i > 0) Container(height: 1, color: t.border),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: NeuSpace.n10,
                        vertical: NeuSpace.n8,
                      ),
                      child: Row(
                        children: [
                          NeuIcon(
                            servers[i].kind == 'remote'
                                ? IconId.download
                                : IconId.server,
                            size: 15,
                            color: servers[i].enabled ? t.accentInk : t.muted,
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
                                        servers[i].name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: NeuFonts.bodySmall,
                                          color: servers[i].enabled
                                              ? t.fg
                                              : t.muted,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: NeuSpace.n6),
                                    Text(
                                      servers[i].scope == 'project'
                                          ? I18n.t('ui.98a5faeeaf')
                                          : I18n.t('ui.7b79313922'),
                                      style: TextStyle(
                                        fontSize: NeuFonts.tiny,
                                        color: t.muted,
                                      ),
                                    ),
                                    if (!servers[i].enabled) ...[
                                      SizedBox(width: NeuSpace.n6),
                                      Text(
                                        I18n.t('ui.69b0f68457'),
                                        style: TextStyle(
                                          fontSize: NeuFonts.tiny,
                                          color: t.warn,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Text(
                                  _mcpSubtitle(servers[i]),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: NeuFonts.badge,
                                    color: t.muted,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 启用/停用：pi 侧 enabled:false = 保留条目但不连接
                          NeuPressable(
                            onTap: () async {
                              final ok = await store.setMcpServerEnabled(
                                servers[i].name,
                                scope: servers[i].scope,
                                enabled: !servers[i].enabled,
                              );
                              if (ok) await onChanged();
                            },
                            radius: 10,
                            padding: EdgeInsets.all(NeuSpace.n6),
                            child: Text(
                              servers[i].enabled
                                  ? I18n.t('ui.5c56a88945')
                                  : I18n.t('ui.7854b52a88'),
                              style: TextStyle(
                                fontSize: NeuFonts.badge,
                                color: t.accentInk,
                              ),
                            ),
                          ),
                          NeuPressable(
                            onTap: () => _removeMcpServer(context, servers[i]),
                            radius: 10,
                            padding: const EdgeInsets.symmetric(
                              horizontal: NeuSpace.n13,
                              vertical: NeuSpace.n13,
                            ),
                            child: NeuIcon(
                              IconId.trash,
                              size: 14,
                              color: t.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                if (servers.isNotEmpty) Container(height: 1, color: t.border),
                NeuPressable(
                  onTap: () => _addMcpServer(context),
                  flat: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: NeuSpace.n13,
                    vertical: NeuSpace.n13,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      NeuIcon(IconId.plus, size: 15, color: t.accentInk),
                      SizedBox(width: NeuSpace.n8),
                      Text(
                        I18n.t('ui.3bd1c146b5'),
                        style: TextStyle(
                          fontSize: NeuFonts.bodyMid,
                          color: t.accentInk,
                        ),
                      ),
                    ],
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
