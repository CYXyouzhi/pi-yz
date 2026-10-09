import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../server/chat_models.dart';
import '../../../server/chat_reducer.dart';
import '../../../server/elapsed_index.dart';
import '../../../server/i18n.dart';
import '../../../server/server_store.dart';
import '../../../server/server_types.dart';
import '../../../server/template_store.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../neu_icons.dart';
import '../../neu_toast.dart';
import '../message_view.dart';
import '../export_page.dart';
import '../files_page.dart';
import '../usage_page.dart';
import 'bars.dart';
import 'loading.dart';
import 'message_detail.dart';

// 拆分后这里同时承担「对外接口」的角色：搬走的东西继续 export 出去，
// 于是 40 多个 import 'chat/widgets.dart' 的调用点一行都不用改。
// 注意 export 只影响「导入本文件的人」，本文件自己要用的符号仍要 import（所以上下都有）。
export 'bars.dart';
export 'header.dart';
export 'loading.dart';
export 'message_detail.dart';
export 'sheets.dart';

/// _buildFileRefs 的组件化版本。
class FileRefs extends StatelessWidget {
  const FileRefs({super.key, required this.refs, required this.onApply});

  final List<FileRef> refs;
  final void Function(FileRef ref) onApply;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      margin: const EdgeInsets.symmetric(horizontal: NeuSpace.n18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NeuRadii.md),
        gradient: NeuDecorations.wellGradient(t),
        boxShadow: NeuShadows.inset(t),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.all(NeuSpace.n6),
        itemCount: refs.length,
        itemBuilder: (context, index) {
          final ref = refs[index];
          return NeuPressable(
            onTap: () => onApply(ref),
            flat: true,
            padding: const EdgeInsets.symmetric(
              horizontal: NeuSpace.n13,
              vertical: NeuSpace.n13,
            ),
            child: Row(
              children: [
                NeuIcon(IconId.terminal, size: 14, color: t.accentInk),
                const SizedBox(width: NeuSpace.n8),
                Expanded(
                  child: Text(
                    ref.relative,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: NeuFonts.sub,
                      fontFamily: 'monospace',
                      color: t.fg,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// _buildSuggestions 的组件化版本。
class Suggestions extends StatelessWidget {
  const Suggestions({
    super.key,
    required this.commands,
    required this.onApply,
    required this.store,
  });

  final List<SlashCommand> commands;
  final void Function(SlashCommand cmd) onApply;
  final ServerStore store;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    // 面板高度跟屏幕走。以前写死 200：手机上只能看到 4 条，
    // 12 条命令得一直滑，看起来就像「显示不完全」。
    // 必须减掉键盘高度（viewInsets.bottom）：否则软键盘弹起来会盖住面板底部几条，
    // 用户会以为「命令就这些」。
    final maxHeight = slashPanelMaxHeight(MediaQuery.of(context));
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      margin: const EdgeInsets.symmetric(horizontal: NeuSpace.n18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NeuRadii.md),
        gradient: NeuDecorations.wellGradient(t),
        boxShadow: NeuShadows.inset(t),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (commands.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NeuSpace.n12,
                vertical: NeuSpace.n16,
              ),
              child: Row(
                children: [
                  NeuIcon(IconId.spinner, size: 14, color: t.muted),
                  SizedBox(width: NeuSpace.n8),
                  Expanded(
                    child: Text(
                      I18n.t('ui.8109beab3c'),
                      style: TextStyle(
                        fontSize: NeuFonts.small,
                        color: t.muted,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(NeuSpace.n6),
                itemCount: commands.length,
                itemBuilder: (context, index) {
                  final command = commands[index];
                  // 中文模式优先中文说明；没有就原文 + 标注（不假装翻过）
                  final description = I18n.describe(
                    command.description,
                    command.descriptionZh,
                    context: context,
                  );
                  return NeuPressable(
                    onTap: () => onApply(command),
                    flat: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: NeuSpace.n10,
                      vertical: NeuSpace.n8,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: NeuSpace.n2),
                          child: NeuIcon(
                            switch (command.source) {
                              'builtin' => IconId.cmd,
                              'skill' => IconId.spinner,
                              'prompt' => IconId.pen,
                              _ => IconId.terminal,
                            },
                            size: 15,
                            color: t.accentInk,
                          ),
                        ),
                        const SizedBox(width: NeuSpace.n8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 命令名长短不一（扩展命令可以是长路径），
                              // 所以给一行横向滚动：名字再长也能滑着读完，不截断
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: '/${command.name}',
                                        style: TextStyle(
                                          fontSize: NeuFonts.bodyMid,
                                          fontFamily: 'monospace',
                                          color: t.fg,
                                        ),
                                      ),
                                      if (command.argHint != null &&
                                          command.argHint!.isNotEmpty)
                                        TextSpan(
                                          text: '  ${command.argHint}',
                                          style: TextStyle(
                                            fontSize: NeuFonts.badge,
                                            color: t.muted,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              if (description.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: NeuSpace.n2,
                                  ),
                                  child: Text(
                                    description,
                                    // 说明不再截断：面板本身可以滚，读全比好看重要
                                    style: TextStyle(
                                      fontSize: NeuFonts.label,
                                      height: 1.45,
                                      color: t.muted,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          if (commands.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: NeuSpace.n6),
              child: Text(
                // 数字必须是真话：显示了多少 / 一共多少（筛选时两个数不一样）
                commands.length == store.commands.length
                    ? I18n.tp('ui.a977d99ebd', {'n': commands.length})
                    : I18n.tp('ui.6e9ce7a03e', {
                        'a': commands.length,
                        'b': store.commands.length,
                      }),
                style: TextStyle(fontSize: NeuFonts.micro, color: t.muted),
              ),
            ),
        ],
      ),
    );
  }
}

double slashPanelMaxHeight(MediaQueryData media) {
  final available = media.size.height - media.viewInsets.bottom;
  return (available * 0.45).clamp(160.0, 420.0);
}

/// _buildPendingImages 的组件化版本。
class PendingImages extends StatelessWidget {
  const PendingImages({
    super.key,
    required this.images,
    required this.onShowUndo,
    required this.onRemove,
    required this.onInsert,
  });

  final List<({String name, String base64, String mime})> images;
  final void Function(String message, VoidCallback onUndo) onShowUndo;
  final void Function(({String name, String base64, String mime}) image)
  onRemove;
  final void Function(
    int index,
    ({String name, String base64, String mime}) image,
  )
  onInsert;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NeuSpace.n18,
        NeuSpace.n4,
        NeuSpace.n18,
        0,
      ),
      child: Row(
        children: [
          for (final image in images)
            Padding(
              padding: const EdgeInsets.only(right: NeuSpace.n6),
              child: NeuPressable(
                // 点缩略图就是移除，但给一条可撤销的提示 ——
                // 手机上误触缩略图太容易了，直接没了会让人重新选一遍图
                onTap: () {
                  final index = images.indexOf(image);
                  onRemove(image);
                  onShowUndo(
                    I18n.tp('ui.8dc0a54c3c', {'name': image.name}),
                    () => onInsert(index.clamp(0, images.length), image),
                  );
                },
                radius: 8,
                flat: true,
                // 触控目标：图标 13 + 14×2 = 41dp（原来 vertical n5 只有 23dp）
                padding: const EdgeInsets.symmetric(
                  horizontal: NeuSpace.n8,
                  vertical: NeuSpace.n14,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NeuIcon(IconId.download, size: 13, color: t.accentInk),
                    const SizedBox(width: NeuSpace.n5),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        image.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: NeuFonts.label, color: t.fg),
                      ),
                    ),
                    const SizedBox(width: NeuSpace.n5),
                    NeuIcon(IconId.close, size: 12, color: t.muted),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 底部输入区：＋（素材/模板）、⌘（按键条）、输入框、发送 / 中止。
///
/// **控制器与焦点节点由页面持有**（页面负责 dispose），组件只把它们挂到
/// TextField 上、自己不持有状态 —— 这样切 Tab、重进页面时草稿与焦点都不会丢。
///
/// 运行中「发送」变成「中止」：同一个按钮位置，不额外占地方。
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.input,
    required this.inputFocus,
    required this.running,
    required this.keyBarVisible,
    required this.onSend,
    required this.onAbort,
    required this.onShowMenu,
    required this.onToggleKeyBar,
  });

  final TextEditingController input;
  final FocusNode inputFocus;

  /// agent 正在跑 —— 决定提示文案与按钮是「发送」还是「中止」。
  final bool running;

  /// ⌘ 键条是否已展开（决定图标是否高亮）。
  final bool keyBarVisible;

  final VoidCallback onSend;
  final VoidCallback onAbort;
  final VoidCallback onShowMenu;
  final VoidCallback onToggleKeyBar;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;

    return Container(
      // 上下各收一点：输入区常驻，竖向每一像素都是从消息区里扣的
      margin: EdgeInsets.fromLTRB(
        NeuSpace.n12,
        NeuSpace.n2,
        NeuSpace.n12,
        MediaQuery.paddingOf(context).bottom + NeuSpace.n4,
      ),
      padding: const EdgeInsets.all(NeuSpace.n2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NeuRadii.md),
        gradient: NeuDecorations.wellGradient(t),
        boxShadow: NeuShadows.inset(t),
      ),
      child: Row(
        children: [
          NeuPressable(
            // ＋：一个入口装两类东西 —— 素材（相册/文件/剪贴板）与常用语模板。
            // 聊天区拆两个按钮会很挤，手机上也难分。
            onTap: onShowMenu,
            radius: 12,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NeuSpace.n11,
                vertical: NeuSpace.n11,
              ),
              child: NeuIcon(IconId.plus, size: 18, color: t.muted),
            ),
          ),
          const SizedBox(width: NeuSpace.n2),
          NeuPressable(
            // ⌘ 的语义按用户预期来：调出手机软键盘打不出的那些键
            // （命令面板改成按键条里的「命令」键 + 手打 /）
            onTap: onToggleKeyBar,
            radius: 12,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NeuSpace.n11,
                vertical: NeuSpace.n11,
              ),
              child: NeuIcon(
                IconId.cmd,
                size: 18,
                color: keyBarVisible ? t.accentInk : t.muted,
              ),
            ),
          ),
          const SizedBox(width: NeuSpace.n6),
          Expanded(
            child: TextField(
              controller: input,
              focusNode: inputFocus,
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              style: TextStyle(fontSize: NeuFonts.body, color: t.fg),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: running
                    ? I18n.t('chat.inputHintRunning', context: context)
                    : I18n.t('chat.inputHint', context: context),
                hintStyle: TextStyle(
                  fontSize: NeuFonts.bodyTight,
                  color: t.muted,
                ),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: NeuSpace.n6),
          NeuPressable(
            onTap: running ? () => onAbort() : onSend,
            radius: 12,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NeuSpace.n11,
                vertical: NeuSpace.n11,
              ),
              child: NeuIcon(
                running ? IconId.close : IconId.send,
                size: 18,
                color: running ? t.danger : t.accentInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 模型切换器里的一行：模型名 + provider/窗口/推理标记，当前项打勾。
///
/// **收 `onTap` 而不是 `StateSetter`** —— 原实现把弹层的 `setState` 直接传进来、
/// 在组件里去改父级状态，那是把「谁负责状态」搅在一起了。现在组件只报告被点了，
/// 切模型、报错、弹 toast 都由弹层函数自己做。
class ModelOptionRow extends StatelessWidget {
  const ModelOptionRow({
    super.key,
    required this.model,
    required this.current,
    required this.onTap,
  });

  final ModelInfo model;

  /// 当前选中的模型 —— 用来判断这一行是不是「正在用的」。
  final ModelInfo? current;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final isCurrent =
        current != null &&
        current!.provider == model.provider &&
        current!.id == model.id;
    return NeuPressable(
      flat: !isCurrent,
      alwaysInset: isCurrent,
      radius: 10,
      padding: const EdgeInsets.symmetric(
        horizontal: NeuSpace.n12,
        vertical: NeuSpace.n9,
      ),
      margin: const EdgeInsets.only(bottom: NeuSpace.n6),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model.name,
                  style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.fg),
                ),
                Text(
                  I18n.tp('ui.b7077d029c', {
                        'provider': model.provider,
                        'window': model.contextWindow ?? '?',
                      }) +
                      (model.reasoning ? I18n.t('ui.af181ac8b2') : ''),
                  style: TextStyle(fontSize: NeuFonts.micro, color: t.muted),
                ),
              ],
            ),
          ),
          if (isCurrent) NeuIcon(IconId.check, size: 15, color: t.accentInk),
        ],
      ),
    );
  }
}

/// 模型 + 思考等级的浮动切换器（弹层）。
///
/// **为什么错误行不用 NeuToast**：底部弹层也在 overlay 里且盖在上面，
/// 弹层里弹出的 toast 会被自己挡住 —— 实测症状是「切模型失败但什么都看不到」。
/// 所以错误显示在弹层内部的一行里（`inSheetError`）。
///
/// 按 provider 分组：用户切换时要能一眼看出「这条是官方还是中转」。
/// 高度上限 80% 屏高，内容可滚。
Future<void> showModelSwitcherSheet(
  BuildContext context,
  ServerStore store,
) async {
  final models = await store.availableModels();
  final levels = await store.availableThinkingLevels();
  if (!context.mounted) return;

  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      final t = sheetContext.neu;
      // 弹层内部的错误行。
      // 为什么不用 NeuToast：底部弹层也在 overlay 里且盖在上面，
      // 弹层里弹出的 toast 会被自己挡住 —— 实测「切模型失败但什么都看不到」。
      String? inSheetError;
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final chat = store.chat;
          final current = chat.model;
          // 按 provider 分组，切换时能一眼看出「这条是官方还是中转」
          final byProvider = <String, List<ModelInfo>>{};
          for (final model in models) {
            byProvider.putIfAbsent(model.provider, () => []).add(model);
          }

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
            ),
            decoration: BoxDecoration(
              color: t.bg,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(NeuRadii.lg),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(
              NeuSpace.n18,
              NeuSpace.n12,
              NeuSpace.n18,
              NeuSpace.n24,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    I18n.t('ui.29f830c6dd'),
                    style: TextStyle(
                      fontSize: NeuFonts.sectionTitle,
                      fontWeight: FontWeight.w700,
                      color: t.onBg,
                    ),
                  ),
                  SizedBox(height: NeuSpace.n4),
                  Text(
                    current == null
                        ? I18n.t('ui.6e6f9563b7')
                        : I18n.tp('ui.9fa88d5d6f', {
                            'name': current.name,
                            'provider': current.provider,
                          }),
                    style: TextStyle(fontSize: NeuFonts.small, color: t.muted),
                  ),
                  if (inSheetError != null) ...[
                    const SizedBox(height: NeuSpace.n8),
                    Row(
                      children: [
                        NeuIcon(IconId.warn, size: 14, color: t.danger),
                        const SizedBox(width: NeuSpace.n6),
                        Expanded(
                          child: Text(
                            inSheetError!,
                            style: TextStyle(
                              fontSize: NeuFonts.small,
                              color: t.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: NeuSpace.n14),
                  Text(
                    I18n.t('ui.11eead2c33'),
                    style: TextStyle(
                      fontSize: NeuFonts.sub,
                      fontWeight: FontWeight.w700,
                      color: t.accentInk,
                    ),
                  ),
                  const SizedBox(height: NeuSpace.n8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final level in levels)
                        NeuPressable(
                          onTap: () async {
                            final ok = await store.setThinkingLevel(level);
                            if (!sheetContext.mounted) return;
                            setSheetState(() {
                              inSheetError = ok ? null : store.lastError;
                            });
                            if (ok) {
                              NeuToast.show(
                                sheetContext,
                                message: I18n.tp('ui.944e771000', {
                                  'level': level,
                                }),
                                icon: IconId.check,
                              );
                            }
                          },
                          flat: chat.thinkingLevel != level,
                          alwaysInset: chat.thinkingLevel == level,
                          radius: 8,
                          padding: const EdgeInsets.symmetric(
                            horizontal: NeuSpace.n12,
                            vertical: NeuSpace.n7,
                          ),
                          child: Text(
                            level,
                            style: TextStyle(
                              fontSize: NeuFonts.sub,
                              color: chat.thinkingLevel == level
                                  ? t.accentInk
                                  : t.fg,
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: NeuSpace.n16),
                  Text(
                    I18n.t('ui.41f1f2fb0e'),
                    style: TextStyle(
                      fontSize: NeuFonts.sub,
                      fontWeight: FontWeight.w700,
                      color: t.accentInk,
                    ),
                  ),
                  const SizedBox(height: NeuSpace.n8),
                  for (final entry in byProvider.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(
                        top: NeuSpace.n8,
                        bottom: NeuSpace.n4,
                      ),
                      child: Text(
                        entry.key,
                        style: TextStyle(
                          fontSize: NeuFonts.label,
                          color: t.muted,
                        ),
                      ),
                    ),
                    for (final model in entry.value)
                      ModelOptionRow(
                        model: model,
                        current: current,
                        onTap: () async {
                          final ok = await store.setModel(
                            model.provider,
                            model.id,
                          );
                          if (!sheetContext.mounted) return;
                          setSheetState(() {
                            inSheetError = ok
                                ? null
                                : (store.lastError ?? I18n.t('ui.2d5fbafe5d'));
                          });
                          if (ok) {
                            NeuToast.show(
                              sheetContext,
                              message: I18n.tp('ui.97523d250a', {
                                'name': model.name,
                                'provider': model.provider,
                              }),
                              icon: IconId.check,
                            );
                          }
                        },
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// 输入菜单里的一格：图标 + 文字。
///
/// 点一下**先收起弹层、再执行动作** —— 顺序不能反：动作会打开相册/文件选择器，
/// 弹层压在上面会挡住它。（组件用自己的 context pop，所以不必从外面传 sheetContext。）
class MenuTile extends StatelessWidget {
  const MenuTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconId icon;
  final String label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Expanded(
      child: NeuPressable(
        onTap: () async {
          Navigator.of(context).pop();
          await onTap();
        },
        radius: 10,
        padding: const EdgeInsets.symmetric(
          horizontal: NeuSpace.n12,
          vertical: NeuSpace.n11,
        ),
        child: Column(
          children: [
            NeuIcon(icon, size: 18, color: t.accentInk),
            const SizedBox(height: NeuSpace.n6),
            Text(
              label,
              style: TextStyle(fontSize: NeuFonts.label, color: t.fg),
            ),
          ],
        ),
      ),
    );
  }
}

/// 输入菜单（弹层）：素材（图片/文件/剪贴板）+ 常用语模板。
///
/// **一个入口装两类东西**：聊天区拆两个按钮会很挤，手机上也难分。
///
/// 模板增删直接读写 `TemplateStore` 单例，改完把新列表通过
/// `onTemplatesChanged` 回报给页面 —— 页面持有 `templates` 这份状态
/// （下次打开弹层要看到最新的），弹层自己不长期持有。
Future<void> showInputMenuSheet(
  BuildContext context, {
  required TextEditingController input,
  required List<String> templates,
  required ValueChanged<List<String>> onTemplatesChanged,
  required ValueChanged<String> onInsert,
  required Future<void> Function() onPickImage,
  required Future<void> Function() onPickFile,
  required Future<void> Function() onPaste,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      final t = sheetContext.neu;
      return StatefulBuilder(
        builder: (context, setSheetState) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
          ),
          decoration: BoxDecoration(
            color: t.bg,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(NeuRadii.lg),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            NeuSpace.n18,
            NeuSpace.n14,
            NeuSpace.n18,
            NeuSpace.n24,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  I18n.t('ui.54d363afee'),
                  style: TextStyle(
                    fontSize: NeuFonts.sub,
                    fontWeight: FontWeight.w700,
                    color: t.accentInk,
                  ),
                ),
                const SizedBox(height: NeuSpace.n8),
                Row(
                  children: [
                    MenuTile(
                      icon: IconId.download,
                      label: I18n.t('ui.824949be5b'),
                      onTap: onPickImage,
                    ),
                    SizedBox(width: NeuSpace.n8),
                    MenuTile(
                      icon: IconId.folder,
                      label: I18n.t('ui.2a0c4740f1'),
                      onTap: onPickFile,
                    ),
                    SizedBox(width: NeuSpace.n8),
                    MenuTile(
                      icon: IconId.pen,
                      label: I18n.t('ui.32249be96d'),
                      onTap: onPaste,
                    ),
                  ],
                ),
                SizedBox(height: NeuSpace.n6),
                Text(
                  I18n.t('ui.6b8e604809'),
                  style: TextStyle(fontSize: NeuFonts.badge, color: t.muted),
                ),
                SizedBox(height: NeuSpace.n16),
                Row(
                  children: [
                    Text(
                      I18n.t('ui.64dfcf277f'),
                      style: TextStyle(
                        fontSize: NeuFonts.sub,
                        fontWeight: FontWeight.w700,
                        color: t.accentInk,
                      ),
                    ),
                    SizedBox(width: NeuSpace.n8),
                    Text(
                      I18n.t('ui.14768ed565'),
                      style: TextStyle(
                        fontSize: NeuFonts.badge,
                        color: t.muted,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: NeuSpace.n8),
                if (templates.isEmpty)
                  Text(
                    I18n.t('ui.d0f489e127'),
                    style: TextStyle(fontSize: NeuFonts.small, color: t.muted),
                  )
                else
                  for (final item in templates)
                    NeuPressable(
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        onInsert(item);
                      },
                      radius: 10,
                      padding: const EdgeInsets.symmetric(
                        horizontal: NeuSpace.n12,
                        vertical: NeuSpace.n9,
                      ),
                      margin: const EdgeInsets.only(bottom: NeuSpace.n6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: NeuFonts.bodySmall,
                                color: t.fg,
                              ),
                            ),
                          ),
                          NeuPressable(
                            onTap: () async {
                              await TemplateStore.instance.remove(item);
                              final items = await TemplateStore.instance.load();
                              if (!sheetContext.mounted) return;
                              setSheetState(() {});
                              onTemplatesChanged(List.of(items));
                            },
                            radius: 8,
                            flat: true,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: NeuSpace.n14,
                                vertical: NeuSpace.n14,
                              ),
                              child: NeuIcon(
                                IconId.close,
                                size: 13,
                                color: t.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: NeuSpace.n8),
                NeuPressable(
                  onTap: () async {
                    final text = input.text.trim();
                    if (text.isEmpty) {
                      NeuToast.show(
                        sheetContext,
                        message: I18n.t('ui.37dba61d9d'),
                        icon: IconId.warn,
                      );
                      return;
                    }
                    await TemplateStore.instance.add(text);
                    final items = await TemplateStore.instance.load();
                    if (!sheetContext.mounted) return;
                    setSheetState(() {});
                    onTemplatesChanged(List.of(items));
                    NeuToast.show(
                      sheetContext,
                      message: I18n.t('ui.17ab7240c1'),
                      icon: IconId.check,
                    );
                  },
                  radius: NeuRadii.sm,
                  padding: const EdgeInsets.symmetric(vertical: NeuSpace.n11),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      NeuIcon(IconId.plus, size: 14, color: t.accentInk),
                      SizedBox(width: NeuSpace.n6),
                      Text(
                        I18n.t('ui.8551ea0b22'),
                        style: TextStyle(
                          fontSize: NeuFonts.bodySmall,
                          color: t.accentInk,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// 会话详情（弹层）：用量与花费、几个跳转入口、分支树。
///
/// 几处实测得来的约束：
///   · 取数**先接住异常再提示** —— 以前是裸 await，一旦抛错面板「点了没反应」，
///     这类静默失败比报错难查得多。
///   · 用量和分支树**一起拉**，别让面板分两次刷新。
///   · **整张面板可滚动** —— 以前只有分支树那一小块能滑，上面的「用量」一多
///     就把下面的按钮顶出屏幕，怎么滑都够不到（实测三指上推都不动）。
///   · 「重点模式」开关从标题栏下沉到这里：标题栏一行要塞下会话名 + 状态点 + 模型 + 按钮，
///     四个按钮里它最低频，却是把会话名挤到 0 宽的元凶之一。
Future<void> showSessionInfoSheet(
  BuildContext context,
  ServerStore store, {
  required bool focusMode,
  required VoidCallback onToggleFocusMode,
  required void Function(String id, String preview) onFork,
  required void Function(String id, String preview) onNavigate,
}) async {
  // 这里以前是裸 await：一旦取数抛出，面板会「点了没反应」——
  // 这类静默失败比报错难查得多，所以先接住再提示。
  Map<String, dynamic>? tree;
  SessionStats? stats;
  try {
    tree = await store.fetchTree();
    // 用量/花费/上下文占用：跟分支树一起拉，别让面板分两次刷新
    stats = await store.sessionStats();
  } catch (error) {
    if (!context.mounted) return;
    NeuToast.show(
      context,
      message: I18n.tp('ui.a6664f495a', {'error': error}),
      icon: IconId.warn,
    );
    return;
  }
  if (!context.mounted) return;
  final chat = store.chat;
  final nodes = tree?['tree'];
  final leafId = tree?['leafId'] as String?;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      final t = sheetContext.neu;
      return Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
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
          NeuSpace.n24,
        ),
        // 整张面板可滚动。
        // 以前只有分支树那一小块能滑，上面的「用量」一多就把下面按钮顶出屏幕，
        // 怎么滑都够不到（实测过：三指上推都不动）。
        child: SingleChildScrollView(
          child: Column(
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
              SizedBox(height: NeuSpace.n14),
              Text(
                I18n.t('ui.155e26ceeb'),
                style: TextStyle(
                  fontSize: NeuFonts.sectionTitle,
                  fontWeight: FontWeight.w700,
                  color: t.onBg,
                ),
              ),
              SizedBox(height: NeuSpace.n10),
              InfoLine(
                I18n.t('common.model'),
                chat.model == null
                    ? '—'
                    : '${chat.model!.name} (${chat.model!.provider})',
              ),
              InfoLine(I18n.t('ui.11eead2c33'), chat.thinkingLevel),
              InfoLine(
                I18n.t('ui.ff692f04ac'),
                I18n.tp('ui.7622b8adf0', {
                  'n': chat.messages.length,
                  'total': chat.historyTotal,
                }),
              ),
              InfoLine(I18n.t('settings.workspace'), chat.cwd),
              if (chat.sessionName != null)
                InfoLine(I18n.t('ui.20c94429e5'), chat.sessionName!),
              if (stats != null) ...[
                SizedBox(height: NeuSpace.n6),
                Text(
                  I18n.t('ui.743735721a'),
                  style: TextStyle(
                    fontSize: NeuFonts.small,
                    fontWeight: FontWeight.w700,
                    color: t.accentInk,
                  ),
                ),
                SizedBox(height: NeuSpace.n4),
                InfoLine(
                  I18n.t('ui.50f198f07f'),
                  stats.contextPercent != null
                      ? '${stats.contextPercent!.toStringAsFixed(1)}% · ${formatTokens(stats.contextTokens)} / ${formatTokens(stats.contextWindow)}'
                      : I18n.t('ui.4f23e4de2b'),
                ),
                InfoLine(
                  'tokens',
                  I18n.tp('ui.37e8f35792', {
                    'total': formatTokens(stats.totalTokens),
                    'input': formatTokens(stats.inputTokens),
                    'output': formatTokens(stats.outputTokens),
                    'cr': formatTokens(stats.cacheReadTokens),
                    'cw': formatTokens(stats.cacheWriteTokens),
                  }),
                ),
                if (stats.costTotal > 0)
                  InfoLine(
                    I18n.t('ui.f970d0272c'),
                    '\$${stats.costTotal.toStringAsFixed(4)}',
                  ),
                InfoLine(
                  I18n.t('ui.8fd578b58a'),
                  I18n.tp('ui.d8deeeee4c', {
                    'u': stats.userMessages,
                    'a': stats.assistantMessages,
                    'tc': stats.toolCalls,
                    'tr': stats.toolResults,
                  }),
                ),
                InfoLine(
                  I18n.t('ui.dc0f2e515f'),
                  chat.autoCompactionEnabled
                      ? I18n.t('ui.9db7a84fcd')
                      : I18n.t('ui.9c58505de3'),
                ),
                const SizedBox(height: NeuSpace.n4),
                // 「重点模式」从标题栏下沉到这里：标题栏一行要塞下
                // 会话名 + 状态点 + 模型 + 按钮，四个按钮里它最低频，
                // 却是把会话名挤到 0 宽的元凶之一（实测）。
                NeuPressable(
                  onTap: () {
                    onToggleFocusMode();
                    Navigator.of(sheetContext).pop();
                    NeuToast.show(
                      context,
                      message: !focusMode
                          ? I18n.t('ui.d03d895f04')
                          : I18n.t('ui.13261adf5f'),
                      icon: IconId.bubble,
                    );
                  },
                  radius: NeuRadii.sm,
                  flat: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: NeuSpace.n6,
                    vertical: NeuSpace.n10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          I18n.t('ui.d03d895f04'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: NeuFonts.small,
                            color: t.fg,
                          ),
                        ),
                      ),
                      Text(
                        focusMode
                            ? I18n.t('ui.9db7a84fcd')
                            : I18n.t('ui.9c58505de3'),
                        style: TextStyle(
                          fontSize: NeuFonts.label,
                          color: t.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: NeuSpace.n12),
              NeuPressable(
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SessionExportPage(store: store),
                    ),
                  );
                },
                radius: NeuRadii.sm,
                padding: const EdgeInsets.symmetric(
                  horizontal: NeuSpace.n13,
                  vertical: NeuSpace.n13,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    NeuIcon(IconId.download, size: 15, color: t.accentInk),
                    SizedBox(width: NeuSpace.n8),
                    Text(
                      I18n.t('ui.cb9bf0e70e'),
                      style: TextStyle(
                        fontSize: NeuFonts.bodyMid,
                        color: t.accentInk,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: NeuSpace.n8),
              NeuPressable(
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => UsagePage(
                        store: store,
                        contextPercent: stats?.contextPercent,
                        contextTokens: stats?.contextTokens,
                        contextWindow: stats?.contextWindow,
                        autoCompactEnabled: chat.autoCompactionEnabled,
                      ),
                    ),
                  );
                },
                radius: NeuRadii.sm,
                padding: const EdgeInsets.symmetric(vertical: NeuSpace.n11),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    NeuIcon(IconId.info, size: 15, color: t.accentInk),
                    SizedBox(width: NeuSpace.n8),
                    Text(
                      I18n.t('ui.f0d15d56eb'),
                      style: TextStyle(
                        fontSize: NeuFonts.bodyMid,
                        color: t.accentInk,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: NeuSpace.n8),
              NeuPressable(
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          WorkspaceFilesPage(store: store, cwd: chat.cwd),
                    ),
                  );
                },
                radius: NeuRadii.sm,
                padding: const EdgeInsets.symmetric(
                  horizontal: NeuSpace.n13,
                  vertical: NeuSpace.n13,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    NeuIcon(IconId.folder, size: 15, color: t.accentInk),
                    SizedBox(width: NeuSpace.n8),
                    Text(
                      I18n.t('ui.480b698883'),
                      style: TextStyle(
                        fontSize: NeuFonts.bodyMid,
                        color: t.accentInk,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: NeuSpace.n16),
              Text(
                I18n.t('ui.19b5e0a26e'),
                style: TextStyle(
                  fontSize: NeuFonts.sectionTitle,
                  fontWeight: FontWeight.w700,
                  color: t.onBg,
                ),
              ),
              SizedBox(height: NeuSpace.n6),
              Text(
                nodes == null
                    ? I18n.t('ui.dd55c97800')
                    : I18n.tp('ui.d7320b9231', {'n': countTree(nodes)}),
                style: TextStyle(fontSize: NeuFonts.label, color: t.muted),
              ),
              const SizedBox(height: NeuSpace.n10),
              if (nodes != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: treeRows(
                    t,
                    nodes,
                    0,
                    leafId,
                    onFork: onFork,
                    onNavigate: onNavigate,
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// 顶部细进度条：列表能滚的时候常驻，一眼看出读到哪儿了。
///
/// 以前没有进度条，只有一个时灵时不灵的回底按钮 —— 用户不知道自己在
/// 长会话的什么位置。用 ListenableBuilder 订阅滚动进度，避免整页重建。
class ScrollProgressBar extends StatelessWidget {
  const ScrollProgressBar({super.key, required this.progress});

  final ValueListenable<double> progress;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (context, value, _) => Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            // 至少 2% 宽，否则刚滚一点时几乎看不见，像是没反应
            widthFactor: value.clamp(0.02, 1.0),
            child: Container(
              height: 2.5,
              decoration: BoxDecoration(
                color: t.accentInk.withValues(alpha: 0.55),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(3),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 回底按钮：不在底部时浮在右下角（在底部时不显示，省掉一个没用的按钮）。
class ScrollToBottomButton extends StatelessWidget {
  const ScrollToBottomButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 12,
      child: NeuPressable(
        onTap: onTap,
        radius: 20,
        child: const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: NeuSpace.n11,
            vertical: NeuSpace.n10,
          ),
          child: NeuIcon(IconId.chevronDown, size: 18),
        ),
      ),
    );
  }
}

/// 消息区：加载 / 失败 / 空态 / 消息列表四态 + 顶部进度条 + 回底按钮。
///
/// 几个不能改的细节：
///   · **重点模式只过滤渲染**，不动 `chat.messages` —— 过滤掉数据会让
///     「加载更早」「本轮耗时」这些基于相邻消息的计算跟着变，模式一开关数字就跳。
///   · ListView 的每一项**必须给 key**（`message.key`）：否则复用 widget 时，
///     上一条消息的「思考展开 / 工具展开」状态会串到这一条上。
///   · 横滑用户消息 = 把这条拉回输入框改写再发（左右滑都认，手机上不用记方向）。
///     只对用户消息开放 —— 拉回自己的话才有意义。
///   · 会话没拉起来时不留空白，给出明确失败态（`_buildLoadFailed` 原本就是复用
///     ChatLoading，这里直接内联，少一层没有意义的间接）。
class ChatMessageArea extends StatelessWidget {
  const ChatMessageArea({
    super.key,
    required this.store,
    required this.chat,
    required this.focusMode,
    required this.atBottom,
    required this.scroll,
    required this.elapsed,
    required this.scrollProgress,
    required this.onQuote,
    required this.onEditResend,
    required this.onScrollToBottom,
  });

  final ServerStore store;
  final ChatReducer chat;

  /// 重点模式：只渲染「有意义」的消息（用户消息、有文本的回复）。
  final bool focusMode;

  /// 列表是否已到底 —— 决定回底按钮显不显示。
  final bool atBottom;

  final ScrollController scroll;

  /// 每条消息的耗时索引（`message.key` → 本轮耗时）。
  final ElapsedIndex elapsed;

  /// 滚动进度 0~1。
  final ValueListenable<double> scrollProgress;

  final ValueChanged<String> onQuote;
  final ValueChanged<String> onEditResend;
  final VoidCallback onScrollToBottom;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Stack(
        children: [
          if (store.loadingSession && chat.messages.isEmpty)
            ChatLoading(store: store)
          else if (store.lastError != null && chat.messages.isEmpty)
            // 会话没拉起来：说清楚 + 给一条重试的路
            ChatLoading(store: store)
          else if (chat.messages.isEmpty)
            ChatEmptyState(store: store)
          else
            Builder(
              builder: (context) {
                // 重点模式只过滤**渲染**，不动 chat.messages ——
                // 过滤掉数据会让「加载更早」「本轮耗时」这些基于相邻消息的
                // 计算跟着变，模式一开关数字就跳。
                final visible = focusMode
                    ? chat.messages
                          .where(
                            (m) =>
                                m.isUser ||
                                (!m.isToolResult &&
                                    m.toolCalls.isEmpty &&
                                    m.thinking.trim().isEmpty &&
                                    m.text.trim().isNotEmpty),
                          )
                          .toList()
                    : chat.messages;
                final elapsedMap = elapsed.of(chat);
                return ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(
                    NeuSpace.n14,
                    NeuSpace.n10,
                    NeuSpace.n14,
                    NeuSpace.n10,
                  ),
                  // 列表顶部多一格：还有更早的消息时放「加载更早」
                  itemCount: visible.length + (chat.historyHasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (chat.historyHasMore && index == 0) {
                      return LoadMoreRow(store: store, chat: chat);
                    }
                    final message =
                        visible[chat.historyHasMore ? index - 1 : index];
                    final tile = MessageTile(
                      // 必须给 key：否则 ListView 复用 widget 时，
                      // 上一条消息的「思考展开/工具展开」状态会串到这一条上
                      key: ValueKey<String>(message.key),
                      message: message,
                      elapsed: elapsedMap[message.key],
                      toolRun: chat.toolRunOf(message.toolCallId),
                      runOf: chat.toolRunOf,
                      onQuote: onQuote,
                      onEditResend: onEditResend,
                    );
                    // 横滑用户消息＝把这条拉回输入框改写再发（左滑右滑都认，
                    // 手机上不用记住方向是哪个）。只对用户消息开放：拉回自己的话才有意义。
                    if (!message.isUser || message.text.trim().isEmpty) {
                      return tile;
                    }
                    return GestureDetector(
                      onHorizontalDragEnd: (details) {
                        final velocity = details.primaryVelocity ?? 0;
                        if (velocity.abs() < 260) return;
                        onEditResend(message.text);
                      },
                      child: tile,
                    );
                  },
                );
              },
            ),
          // 顶部细进度条：列表能滚的时候常驻，一眼看出读到哪儿了。
          // 以前根本没有进度条，只有一个时灵时不灵的回底按钮。
          if (chat.messages.isNotEmpty)
            ScrollProgressBar(progress: scrollProgress),
          if (!atBottom) ScrollToBottomButton(onTap: onScrollToBottom),
        ],
      ),
    );
  }
}

/// 「从这条消息分叉出新会话」的确认框。
///
/// 与「切换分支」的区别要说清楚：切换是同一会话内换路径，
/// 这里是**另开一条会话**从该点往后走，原会话保持不动 —— 用户容易混。
Future<bool?> confirmForkDialog(
  BuildContext context, {
  required String entryId,
  required String preview,
}) {
  final t = context.neu;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: t.bg,
      title: Text(
        I18n.t('ui.a1c0a7962b'),
        style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle),
      ),
      content: Text(
        // ignore: prefer_interpolation_to_compose_strings
        '${I18n.tp('ui.124ba57d80', {'preview': preview.isEmpty ? entryId.substring(0, 8) : preview})}'
        '${I18n.t('ui.1263de37a0')}',
        style: TextStyle(
          color: t.muted,
          fontSize: NeuFonts.bodySmall,
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
            I18n.t('ui.bfc04cfda7'),
            style: TextStyle(color: t.accentInk),
          ),
        ),
      ],
    ),
  );
}

/// 「切到树里的另一个节点」的确认框。
///
/// 切换会改变模型上下文（后续对话接在另一条分支上），所以必须先确认；
/// 另给一个可选勾选「生成摘要」—— 把被舍弃的那条分支压缩成摘要带过去
/// （pi 的 editorText 行为之外的一条补偿路径，跑一次模型，耗时明显）。
///
/// 返回值：**null = 取消**；非 null = 确认，`summarize` 带勾选状态。
/// 用记录而不是 (bool, bool) 元组，是为了让调用点读起来知道每个布尔是什么。
Future<({bool summarize})?> confirmNavigateDialog(
  BuildContext context, {
  required String targetId,
  required String preview,
}) {
  final t = context.neu;
  var summarize = false;
  return showDialog<({bool summarize})>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        backgroundColor: t.bg,
        title: Text(
          I18n.t('ui.4956c9f6d6'),
          style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              // ignore: prefer_interpolation_to_compose_strings
              '${I18n.tp('ui.558ac73c08', {'preview': preview.isEmpty ? targetId.substring(0, 8) : preview})}'
              '${I18n.t('ui.68af09ffe6')}',
              style: TextStyle(
                color: t.muted,
                fontSize: NeuFonts.bodySmall,
                height: 1.6,
              ),
            ),
            const SizedBox(height: NeuSpace.n14),
            GestureDetector(
              onTap: () => setDialogState(() => summarize = !summarize),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Icon(
                    summarize ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 20,
                    color: summarize ? t.accentInk : t.muted,
                  ),
                  SizedBox(width: NeuSpace.n8),
                  Expanded(
                    child: Text(
                      I18n.t('ui.e949f0cedd'),
                      style: TextStyle(
                        color: summarize ? t.fg : t.muted,
                        fontSize: NeuFonts.sub,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: Text(
              I18n.t('common.cancel'),
              style: TextStyle(color: t.muted),
            ),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop((summarize: summarize)),
            child: Text(
              I18n.t('ui.bec7e4d621'),
              style: TextStyle(color: t.accentInk),
            ),
          ),
        ],
      ),
    ),
  );
}
