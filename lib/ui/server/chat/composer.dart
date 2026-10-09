import 'package:flutter/material.dart';

import '../../../server/chat_models.dart';
import '../../../server/i18n.dart';
import '../../../server/server_store.dart';
import '../../../server/server_types.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../neu_icons.dart';

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
