// AI 配置页的「模型」分组。
//
// 约定同 config/widgets.dart：不持有状态 —— chat / models / loading 都由页面传。
// 数据（models 与 loading）留在页面里是因为它们由页面发起的加载流程维护。

import 'package:flutter/material.dart';

import '../../../server/chat_reducer.dart';
import '../../../server/i18n.dart';
import '../../../server/server_store.dart';
import '../../../server/server_types.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../neu_icons.dart';
import 'rows.dart';
import 'widgets.dart';

class ModelSection extends StatelessWidget {
  const ModelSection({
    super.key,
    required this.chat,
    required this.models,
    required this.loading,
    required this.store,
    required this.open,
    required this.onToggle,
  });

  final ChatReducer chat;
  final List<ModelInfo> models;
  final bool loading;
  final ServerStore store;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConfigSection(
          title: I18n.t('common.model'),
          icon: IconId.gear,
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
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NeuSpace.n10,
                    vertical: NeuSpace.n8,
                  ),
                  child: Row(
                    children: [
                      NeuIcon(IconId.spinner, size: 14, color: t.accentInk),
                      SizedBox(width: NeuSpace.n8),
                      Expanded(
                        child: Text(
                          chat.model == null
                              ? I18n.t('ui.261ec4f0de')
                              : '${chat.model!.name} · ${chat.model!.provider}',
                          // 不再截成一行：手机窄屏上「DeepSeek V4.1 Flash · opencode-go」
                          // 会被截掉 provider，看不出用的是哪家
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: NeuFonts.bodySmall,
                            color: t.fg,
                          ),
                        ),
                      ),
                      Text(
                        I18n.t('ui.48ac479789'),
                        style: TextStyle(
                          fontSize: NeuFonts.micro,
                          color: t.accentInk,
                        ),
                      ),
                    ],
                  ),
                ),
                if (loading)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: NeuSpace.n12),
                    child: Text(
                      I18n.t('common.loading'),
                      style: TextStyle(
                        fontSize: NeuFonts.small,
                        color: t.muted,
                      ),
                    ),
                  )
                else if (models.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: NeuSpace.n12),
                    child: Text(
                      I18n.t('ui.039e58de36'),
                      style: TextStyle(
                        fontSize: NeuFonts.small,
                        color: t.muted,
                      ),
                    ),
                  )
                else ...[
                  for (final model in models.take(40)) ...[
                    Container(height: 1, color: t.border),
                    ModelRow(model: model, chat: chat, store: store),
                  ],
                  if (models.length > 40)
                    Padding(
                      padding: const EdgeInsets.only(top: NeuSpace.n8),
                      child: Text(
                        I18n.tp('ui.edb9ab9fc0', {'n': models.length}),
                        style: TextStyle(
                          fontSize: NeuFonts.badge,
                          color: t.muted,
                        ),
                      ),
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
