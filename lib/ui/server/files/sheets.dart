// 工作区文件页的两个底部面板（预览、git diff）。
//
// 它们返回 Future<void> 而不是 Widget —— 走的是 showModalBottomSheet，
// 所以抽成顶层函数而非组件；状态与数据都由调用方传进来。

import 'package:flutter/material.dart';

import '../../../server/i18n.dart';
import '../../../server/server_store.dart';
import '../../../server/server_types.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import 'widgets.dart';

Future<void> showFilePreview(
  BuildContext context,
  String filePath, {
  required ServerStore store,
  required String cwd,
  required GitStatusInfo? git,
}) async {
  final file = await store.readFile(filePath);
  if (!context.mounted) return;
  if (file == null) return;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      final t = sheetContext.neu;
      final tail = filePath.replaceAll('\\', '/').split('/').last;
      return Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
        ),
        decoration: BoxDecoration(
          color: t.bg,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(NeuRadii.lg),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          NeuSpace.n18,
          NeuSpace.n10,
          NeuSpace.n18,
          NeuSpace.n20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: t.muted.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(NeuRadii.hairline),
                ),
              ),
            ),
            const SizedBox(height: NeuSpace.n12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    tail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: NeuFonts.sectionTitle,
                      fontWeight: FontWeight.w700,
                      color: t.onBg,
                    ),
                  ),
                ),
                if (git?.isRepo == true)
                  NeuPressable(
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      showDiffSheet(context, filePath, store: store, cwd: cwd);
                    },
                    radius: 12,
                    padding: const EdgeInsets.symmetric(
                      horizontal: NeuSpace.n12,
                      vertical: NeuSpace.n7,
                    ),
                    child: Text(
                      I18n.t('ui.30570a7afa'),
                      style: TextStyle(
                        fontSize: NeuFonts.sub,
                        color: t.accentInk,
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: NeuSpace.n2),
            Text(
              '${readableSize(file.size)}${file.truncated ? I18n.t('ui.70a59fefaa') : ''}',
              style: TextStyle(fontSize: NeuFonts.label, color: t.muted),
            ),
            const SizedBox(height: NeuSpace.n12),
            Flexible(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: NeuDecorations.wellGradient(t),
                  borderRadius: BorderRadius.circular(NeuRadii.sm),
                  boxShadow: NeuShadows.insetSm(t),
                ),
                padding: const EdgeInsets.all(NeuSpace.n10),
                child: SingleChildScrollView(
                  child: SelectableText(
                    file.text,
                    style: TextStyle(
                      fontSize: NeuFonts.label,
                      height: 1.55,
                      fontFamily: 'monospace',
                      color: t.fg,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> showDiffSheet(
  BuildContext context,
  String? filePath, {
  required ServerStore store,
  required String cwd,
}) async {
  final diff = await store.gitDiff(cwd, path: filePath);
  if (!context.mounted || diff == null) return;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      final t = sheetContext.neu;
      final lines = diff.diff.split('\n');
      return Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
        ),
        decoration: BoxDecoration(
          color: t.bg,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(NeuRadii.lg),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          NeuSpace.n18,
          NeuSpace.n10,
          NeuSpace.n18,
          NeuSpace.n20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: t.muted.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(NeuRadii.hairline),
                ),
              ),
            ),
            SizedBox(height: NeuSpace.n12),
            Text(
              filePath == null
                  ? I18n.t('ui.d597968aea')
                  : filePath.replaceAll('\\', '/').split('/').last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: NeuFonts.sectionTitle,
                fontWeight: FontWeight.w700,
                color: t.onBg,
              ),
            ),
            SizedBox(height: NeuSpace.n10),
            Flexible(
              child: diff.empty
                  ? Text(
                      I18n.t('ui.87afad55b5'),
                      style: TextStyle(
                        fontSize: NeuFonts.bodySmall,
                        color: t.muted,
                      ),
                    )
                  : Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: NeuDecorations.wellGradient(t),
                        borderRadius: BorderRadius.circular(NeuRadii.sm),
                        boxShadow: NeuShadows.insetSm(t),
                      ),
                      padding: const EdgeInsets.all(NeuSpace.n10),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final line in lines)
                              Text(
                                line.isEmpty ? ' ' : line,
                                style: TextStyle(
                                  fontSize: NeuFonts.badge,
                                  height: 1.5,
                                  fontFamily: 'monospace',
                                  color: line.startsWith('+')
                                      ? t.success
                                      : line.startsWith('-')
                                      ? t.danger
                                      : line.startsWith('@@')
                                      ? t.accentInk
                                      : t.fg,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      );
    },
  );
}
