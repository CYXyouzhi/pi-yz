// AI 配置页的「ui.11eead2c33」分组（由 tool/extract_config_section.py 机械搬运后人工校对）。
//
// 约定同 config/widgets.dart：组件不持有状态，用到的数据都由页面传进来。

import 'package:flutter/material.dart';

import '../../../server/i18n.dart';
import '../../../server/chat_reducer.dart';
import '../../../server/server_store.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../neu_icons.dart';
import '../../neu_toast.dart';
import 'widgets.dart';

class ThinkingSection extends StatelessWidget {
  const ThinkingSection({
    super.key,
    required this.thinkingLevels,
    required this.store,
    required this.chat,
    required this.open,
    required this.onToggle,
  });

  final List<String> thinkingLevels;
  final ServerStore store;
  final ChatReducer chat;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    const icon = IconId.spinner;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
      ConfigSection(
        title: I18n.t('ui.11eead2c33'),
        icon: icon,
        open: open,
        onToggle: onToggle,
      ),
      if (open) ...[
      NeuRaised(
        radius: NeuRadii.md,
        level: NeuLevel.small,
        padding: const EdgeInsets.all(NeuSpace.n6),
        child: thinkingLevels.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: NeuSpace.n12),
                child: Center(
                  child: Text('—', style: TextStyle(fontSize: NeuFonts.small, color: t.muted)),
                ),
              )
            : Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final level in thinkingLevels)
                    NeuPressable(
                      onTap: () {
                        // 改思考等级要经会话命令下发，没会话先说清楚，
                        // 不要点了没反应（以前就是静默失败）
                        if (store.currentSessionId == null) {
                          NeuToast.show(context,
                              message: I18n.t('ui.ce27b6f56c'),
                              icon: IconId.warn);
                          return;
                        }
                        store.setThinkingLevel(level);
                      },
                      flat: chat.thinkingLevel != level,
                      alwaysInset: chat.thinkingLevel == level,
                      radius: NeuRadii.sm,
                      padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n14, vertical: NeuSpace.n9),
                      child: Text(
                        level,
                        style: TextStyle(
                          fontSize: NeuFonts.sub,
                          color: chat.thinkingLevel == level ? t.accentInk : t.muted,
                          fontWeight: chat.thinkingLevel == level
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
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
