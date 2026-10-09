// 设置页的「settings.workspace」分组（由 tool/extract_section.py 机械搬运，之后人工校对）。
//
// 抽出来的理由与做法见 docs/refactor-status.md：状态留在父级 State，
// 组件只收 open（我展开了吗）与 onToggle（点了要干什么），自己不持有任何字段。

import 'package:flutter/material.dart';

import '../../../server/i18n.dart';
import '../../../server/server_store.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../files_page.dart';
import '../../neu_icons.dart';
import '../../neu_toast.dart';
import '../pool_view.dart';
import 'widgets.dart';

class WorkspaceSection extends StatelessWidget {
  const WorkspaceSection({
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
    final key = I18n.t('settings.workspace', context: context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSection(
          title: key,
          icon: IconId.folder,
          summary: store.target?.defaultCwd ?? I18n.t('ui.e963f6371c'),
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
                  onTap: () {
                    final cwd = store.chat.cwd.isNotEmpty
                        ? store.chat.cwd
                        : (store.target?.defaultCwd ?? '');
                    if (cwd.isEmpty) {
                      NeuToast.show(
                        context,
                        message: I18n.t('ui.45afe85695'),
                        icon: IconId.warn,
                      );
                      return;
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            WorkspaceFilesPage(store: store, cwd: cwd),
                      ),
                    );
                  },
                  flat: true,
                  padding: const EdgeInsets.symmetric(vertical: NeuSpace.n6),
                  child: Row(
                    children: [
                      NeuIcon(IconId.folder, size: 17, color: t.accentInk),
                      SizedBox(width: NeuSpace.n12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              I18n.t('ui.5ba881d3c3'),
                              style: TextStyle(
                                fontSize: NeuFonts.bodyTight,
                                color: t.fg,
                              ),
                            ),
                            SizedBox(height: NeuSpace.n2),
                            Text(
                              I18n.t('ui.b66f0c9549'),
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
                // 存储占用：会话文件是本 App 在电脑上占地方的主角（实测一台机器 700+ MB），
                // 得让用户看得见、清得掉（task-15 合同④）
                NeuPressable(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => StoragePage(store: store),
                    ),
                  ),
                  flat: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: NeuSpace.n12,
                    vertical: NeuSpace.n12,
                  ),
                  child: Row(
                    children: [
                      NeuIcon(IconId.server, size: 17, color: t.accentInk),
                      SizedBox(width: NeuSpace.n12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              I18n.t('ui.b9d0f24c4c'),
                              style: TextStyle(
                                fontSize: NeuFonts.bodyTight,
                                color: t.fg,
                              ),
                            ),
                            SizedBox(height: NeuSpace.n2),
                            Text(
                              I18n.t('ui.c7abd045d8'),
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
              ],
            ),
          ),
        ],
      ],
    );
  }
}
