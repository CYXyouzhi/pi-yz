import 'package:flutter/material.dart';

import '../../../server/i18n.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../neu_icons.dart';

/// _cmdRow 的组件化版本。
class CmdRow extends StatelessWidget {
  const CmdRow({super.key, required this.command, required this.label, required this.onCopy});

  final String command;
  final String label;
  final void Function(String text, String label) onCopy;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return NeuPressable(
        onTap: () => onCopy(command, label),
        radius: NeuRadii.sm,
        padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                command,
                style: TextStyle(fontSize: NeuFonts.sub, color: t.accentInk),
              ),
            ),
            const SizedBox(width: NeuSpace.n8),
            NeuIcon(IconId.copy, size: 14, color: t.muted),
          ],
        ),
      );
  }
}

/// _tunnelOption 的组件化版本。
class TunnelOption extends StatelessWidget {
  const TunnelOption({super.key, required this.value, required this.current, required this.onPick});

  final String value;
  final String current;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final selected = current == value;
      final isCf = value == 'cloudflare';
      final label = I18n.t(isCf ? 'remote.optCloudflare' : 'remote.optSsh');
      final hint = I18n.t(isCf ? 'remote.optCloudflareHint' : 'remote.optSshHint');
      return NeuPressable(
        onTap: () => onPick(value),
        radius: NeuRadii.sm,
        // 选中 = 按进去（设计稿 .wsg-item.active 的那套语义）
        flat: !selected,
        alwaysInset: selected,
        padding:
            const EdgeInsets.symmetric(horizontal: NeuSpace.n10, vertical: NeuSpace.n10),
        child: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? t.accentInk : t.muted, width: 2),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration:
                            BoxDecoration(shape: BoxShape.circle, color: t.accentInk),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: NeuSpace.n8),
            // 名称不允许被压掉（它是选项的主信息），说明文字才让位
            Text(label,
                maxLines: 1,
                style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.fg)),
            const SizedBox(width: NeuSpace.n8),
            Expanded(
              child: Text(hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: NeuFonts.label, color: t.muted)),
            ),
          ],
        ),
      );
  }
}

/// _ownToolSection 的组件化版本。
class OwnToolSection extends StatelessWidget {
  const OwnToolSection({super.key, required this.ownRemote, required this.onSave});

  final TextEditingController? ownRemote;
  final Future<void> Function(String raw) onSave;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(I18n.t('remote.ownTitle'),
              style: TextStyle(
                  fontSize: NeuFonts.bodySmall,
                  fontWeight: FontWeight.w700,
                  color: t.fg)),
          const SizedBox(height: NeuSpace.n2),
          Text(I18n.t('remote.ownHint'),
              style: TextStyle(fontSize: NeuFonts.label, height: 1.5, color: t.muted)),
          const SizedBox(height: NeuSpace.n8),
          TextField(
            controller: ownRemote,
            style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.fg),
            decoration: InputDecoration(
              hintText: I18n.t('remote.ownPlaceholder'),
              hintStyle: TextStyle(fontSize: NeuFonts.label, color: t.muted),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(NeuRadii.sm)),
            ),
            onSubmitted: onSave,
          ),
          const SizedBox(height: NeuSpace.n8),
          NeuPressable(
            onTap: () => onSave(ownRemote?.text ?? ''),
            radius: NeuRadii.sm,
            padding: EdgeInsets.symmetric(vertical: NeuSpace.n10),
            child: Center(
              child: Text(I18n.t('remote.ownSave'),
                  style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.accentInk)),
            ),
          ),
        ],
      );
  }
}
