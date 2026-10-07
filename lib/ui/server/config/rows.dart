// AI 配置页里成行出现的组件（模型行、命令组…）。
//
// 与 config/widgets.dart 同样的约定：不持有状态，需要什么就收什么。
// 这里多收一个 store —— 因为点一行模型要真的去切模型（有副作用），
// 副作用留在 store 里，组件只负责发起。

import 'package:flutter/material.dart';

import '../../../server/chat_models.dart';
import '../../../server/chat_reducer.dart';
import '../../../server/i18n.dart';
import '../../../server/server_store.dart';
import '../../../server/server_types.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../neu_icons.dart';
import '../../neu_toast.dart';

/// 一行模型：点一下就切过去（当前用的那个显示对勾，且不可点）。
class ModelRow extends StatelessWidget {
  const ModelRow({
    super.key,
    required this.model,
    required this.chat,
    required this.store,
  });

  final ModelInfo model;
  final ChatReducer chat;
  final ServerStore store;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final current = chat.model != null &&
        chat.model!.provider == model.provider &&
        chat.model!.id == model.id;

    return NeuPressable(
      flat: !current,
      alwaysInset: current,
      onTap: current
          ? null
          : () async {
              // 没有打开的会话就没法切模型 —— 服务端是往会话上设的
              if (store.currentSessionId == null) {
                NeuToast.show(context,
                    message: I18n.t('ui.b35af26ccf'), icon: IconId.warn);
                return;
              }
              await store.setModel(model.provider, model.id);
              if (!context.mounted) return;
              NeuToast.show(
                context,
                message: I18n.tp('ui.8480b01bc7', {'name': model.name}),
                icon: IconId.check,
              );
            },
      padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n10, vertical: NeuSpace.n10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model.name,
                  // 模型名很长（DeepSeek V4.1 Flash Vision Exp），一行装不下
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.fg),
                ),
                Text(
                  '${I18n.tp('ui.b7077d029c', {
                    'provider': model.provider,
                    'window': model.contextWindow ?? '?',
                  })}'
                  '${model.reasoning ? I18n.t('ui.af181ac8b2') : ''}',
                  style: TextStyle(fontSize: NeuFonts.micro, color: t.muted),
                ),
              ],
            ),
          ),
          if (current) NeuIcon(IconId.check, size: 15, color: t.accentInk),
        ],
      ),
    );
  }
}

/// 一行命令 / 技能。可点时整行可点（技能就是靠这个点开 SKILL.md）。
class CommandRow extends StatelessWidget {
  const CommandRow(this.item, this.onTap, {super.key});

  final SlashCommand item;
  final void Function(SlashCommand)? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          // 140 太窄：/skill:impeccable-design-polish-… 这类长命令名会被截
          width: 168,
          child: Text(
            '/${item.name}',
            maxLines: 2,
            // 原先靠把宽度从 140 加到 168 来避免截断 —— 名字再长一样会截，加省略号才治本
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: NeuFonts.label, fontFamily: 'monospace', color: t.fg),
          ),
        ),
        Expanded(
          child: Text(
            item.description ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: NeuFonts.badge, color: t.muted),
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(width: NeuSpace.n6),
          NeuIcon(IconId.chevronRight, size: 12, color: t.muted),
        ],
      ],
    );
    if (onTap == null) return row;
    return NeuPressable(
      onTap: () => onTap!(item),
      flat: true,
      radius: NeuRadii.sm,
      padding: const EdgeInsets.symmetric(vertical: NeuSpace.n2),
      child: row,
    );
  }
}

/// 命令/技能的一个子组（技能、扩展、内置三组）。
///
/// 子组自己也能折叠：三组各自几十条，全展开就是一屏垃圾
/// （用户原话：「技能与命令那里应该分类的一大堆在一起不美观」）。
/// 开合状态仍由页面持有，这里收 isOpen / onOpen 两个函数。
class CommandGroup extends StatelessWidget {
  const CommandGroup({
    super.key,
    required this.title,
    required this.items,
    required this.isOpen,
    required this.onOpen,
    this.emptyHint = '',
    this.onTapItem,
    this.tapHint,
  });

  final String title;
  final List<SlashCommand> items;
  final bool Function(String) isOpen;
  final void Function(String) onOpen;

  /// 为空时显示的提示。默认值必须是常量，所以不能在这里调 I18n ——
  /// 调用方传进来时再翻（空的就在下面兜底翻）。
  final String emptyHint;
  final void Function(SlashCommand item)? onTapItem;
  final String? tapHint;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final groupOpen = isOpen(title);

    if (items.isNotEmpty && !groupOpen) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n10, vertical: NeuSpace.n6),
        child: NeuPressable(
          flat: true,
          onTap: () => onOpen(title),
          padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n10, vertical: NeuSpace.n10),
          child: Row(
            children: [
              NeuIcon(IconId.chevronRight, size: 13, color: t.muted),
              SizedBox(width: NeuSpace.n6),
              Text('$title（${items.length}）',
                  style: TextStyle(fontSize: NeuFonts.sub, color: t.accentInk)),
            ],
          ),
        ),
      );
    }

    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n10, vertical: NeuSpace.n10),
        child: Row(
          children: [
            Text(title, style: TextStyle(fontSize: NeuFonts.sub, color: t.muted)),
            Spacer(),
            Text(emptyHint.isEmpty ? I18n.t('ui.b7612b71c0') : emptyHint,
                style: TextStyle(fontSize: NeuFonts.badge, color: t.muted)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n10, vertical: NeuSpace.n8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('$title（${items.length}）',
                  style: TextStyle(fontSize: NeuFonts.sub, color: t.accentInk)),
              if (tapHint != null) ...[
                const Spacer(),
                Text(tapHint!, style: TextStyle(fontSize: NeuFonts.tiny, color: t.muted)),
              ],
            ],
          ),
          const SizedBox(height: NeuSpace.n6),
          // 只列前 12 条：再多就不是「看一眼」而是「翻目录」了
          for (final item in items.take(12))
            Padding(
              padding: const EdgeInsets.only(bottom: NeuSpace.n3),
              child: CommandRow(item, onTapItem),
            ),
          if (items.length > 12)
            Text(I18n.tp('ui.9030449893', {'n': items.length - 12}),
                style: TextStyle(fontSize: NeuFonts.micro, color: t.muted)),
        ],
      ),
    );
  }
}
