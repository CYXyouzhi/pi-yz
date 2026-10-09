import 'package:flutter/material.dart';

import '../../../server/chat_reducer.dart';
import '../../../server/i18n.dart';
import '../../../server/server_store.dart';
import '../../../server/server_types.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../neu_icons.dart';
import '../activity_view.dart';
import 'loading.dart';

/// 会话内的模型胶囊：显示当前模型名，点开切换器。
///
/// **只显示模型名** —— `模型 · provider` 太长，会把会话名挤到看不见
/// （provider 在点开的切换器里能看到）。
///
/// 宽度限制 96，且用 **FittedBox 缩字**而不是截断：截成 `DeepSe…`
/// 只剩三个字母，既认不出是哪个模型、又像渲染坏了。缩小时配合
/// `modelChipLabel` 剥掉冗余厂商词，通常几乎不缩。
///
/// 只收 `model` 字符串（不收整个 chat）—— 组件要什么就给什么，
/// 这样它的依赖一眼看得见，也不会因为 chat 多一个字段就重新编译。
class ModelChip extends StatelessWidget {
  const ModelChip({super.key, required this.model, required this.onTap});

  final ModelInfo? model;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    // 只显示模型名：`模型 · provider` 太长，会把会话名挤到看不见
    //（provider 在点开的切换器里能看到）
    final label = modelChipLabel(model);
    return ConstrainedBox(
      // 宽度：一行里还要放会话名 + 状态点 + 三个按钮，所以必须给上限。
      // 76 是更早的值 —— 实测它把「DeepSeek V4.1 Flash」截成 Dee…，用户的原话是
      // 「太杂乱了一点也不美观」：一个只剩三个字母的截断，既认不出是哪个模型，
      // 看起来也像渲染坏了。
      //
      // 96 配上面剥掉厂商词之后的型号（`V4.1 Flash`，10 个字符）刚好装得下，
      // 不用再抢会话名的空间。
      constraints: const BoxConstraints(maxWidth: 96),
      child: NeuPressable(
        onTap: onTap,
        radius: 8,
        flat: true,
        padding: const EdgeInsets.symmetric(
          horizontal: NeuSpace.n14,
          vertical: NeuSpace.n14,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              // 缩放而不是截断。用户的原话是「在这里显示缩小的不就好了」——
              // 截成 `DeepSe…` 只剩三个字母，既认不出是哪个模型、又像渲染坏了；
              // 缩到小一号至少把名字完整给出来。
              //
              // 配合 modelChipLabel 剥掉冗余厂商词，缩的幅度通常很小
              //（`V4.1 Flash` 在 96dp 里几乎不用缩）；即使遇到特别长的名字
              //（`DeepSeek V4 Flash Vision Exp`），也只是变小，不会丢字。
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: NeuFonts.badge,
                    color: t.accentInk,
                  ),
                ),
              ),
            ),
            const SizedBox(width: NeuSpace.n4),
            NeuIcon(IconId.chevronDown, size: 12, color: t.accentInk),
          ],
        ),
      ),
    );
  }
}

String modelChipLabel(ModelInfo? model) {
  if (model == null) return I18n.t('ui.aa50cded3a');
  final name = model.name.trim();
  final firstSpace = name.indexOf(' ');
  if (firstSpace <= 0) return name;
  final head = name.substring(0, firstSpace);
  final tail = name.substring(firstSpace + 1).trim();
  if (tail.isEmpty || !tail.contains(' ')) return name;
  final idHead = model.id.split(RegExp(r'[-_]')).first;
  if (head.toLowerCase() != idHead.toLowerCase()) return name;
  return tail;
}

/// 会话页头部：头像 + 会话名 + 状态点 + 模型胶囊 + 实时速度 + 三个按钮。
///
/// 几个设计约束（都来自实测）：
///   · 会话名可点 → 打开实时活动视图。活动条空闲时不再占行，
///     但入口不能跟着丢，所以挂在会话名上。
///   · **地址胶囊从这一行拿掉了** —— 一行要塞下「会话名 + 状态点 + 模型 + 三个按钮」，
///     谁都不够宽（实测会话名和地址互相挤）。连的是哪台机器，活动条和连接页都能看到。
///   · 「分享」放在头部而不是只藏在消息菜单里：手机上「把这段发出去」是高频动作，
///     值得一个一眼可见的入口。
class ChatHeader extends StatelessWidget {
  const ChatHeader({
    super.key,
    required this.store,
    required this.chat,
    required this.runStartedAt,
    required this.onShare,
    required this.onShowInfo,
    required this.onNewSession,
    required this.onShowModelSwitcher,
  });

  final ServerStore store;
  final ChatReducer chat;

  /// 本轮开始跑的时刻 —— 实时速度要用它算「跑了多久」。
  final DateTime? runStartedAt;

  final VoidCallback onShare;
  final VoidCallback onShowInfo;
  final VoidCallback onNewSession;

  /// 点模型胶囊 → 打开模型/思考等级切换器。
  final VoidCallback onShowModelSwitcher;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final connected = store.isConnected;
    return Padding(
      // 垂直 8 → 5：标题栏已并成一行，上下再多留就是白占竖向空间
      padding: const EdgeInsets.fromLTRB(
        NeuSpace.n18,
        NeuSpace.n5,
        NeuSpace.n12,
        NeuSpace.n5,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(NeuRadii.chip),
              gradient: NeuDecorations.raisedGradient(t),
              boxShadow: NeuShadows.raiseSm(t),
            ),
            alignment: Alignment.center,
            child: Text(
              'p',
              style: TextStyle(fontWeight: FontWeight.w700, color: t.accentInk),
            ),
          ),
          const SizedBox(width: NeuSpace.n10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // 会话名与地址都要能收缩：右侧还有分享/详情/新建三个按钮，
                    // 不收缩时长会话名会把地址挤到按钮底下（看起来像被遮住）。
                    Flexible(
                      // 会话名可点：打开实时活动视图。
                      // 活动条空闲时不再占行（见 build 里的条件），入口落在这里 ——
                      // 省空间不能把入口弄丢。
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => showActivitySheet(context, store),
                        child: Text(
                          // 会话名可能是空串（用户没命名）：只判 null 标题栏会空一块
                          // （实测被挤成「p ● 模型」），空串也要回落到默认名
                          (chat.sessionName ?? '').trim().isEmpty
                              ? 'pi agent'
                              : chat.sessionName!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: NeuFonts.bodyLg,
                            fontWeight: FontWeight.w700,
                            color: t.onBg,
                          ),
                        ),
                      ),
                    ),
                    // 地址胶囊从标题栏拿掉：一行里要塞下「会话名 + 地址 + 状态点 +
                    // 模型 + 四个按钮」，谁都不够宽（实测会话名和地址一起被挤成 0）。
                    // 连的是哪台机器，活动条和连接页都能看到，这里让位给会话名。
                    const SizedBox(width: NeuSpace.n6),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: connected ? t.success : t.muted,
                      ),
                    ),
                    const SizedBox(width: NeuSpace.n6),
                    // 会话内一键切模型/思考等级：不用离开会话，也不用记命令
                    ModelChip(model: chat.model, onTap: onShowModelSwitcher),
                    if (chat.isRunning) ...[
                      const SizedBox(width: NeuSpace.n6),
                      LiveSpeed(store: store, runStartedAt: runStartedAt),
                    ],
                  ],
                ),
              ],
            ),
          ),
          NeuPressable(
            // 分享这条回复（⑩）：走系统分享面板。
            // 放在头部而不是只藏在消息菜单里 —— 手机上「把这段发给同事」
            // 是高频动作，值得一个一眼可见的入口。
            onTap: onShare,
            radius: 14,
            child: const Padding(
              padding: EdgeInsets.all(NeuSpace.n11),
              child: NeuIcon(IconId.share, size: 18),
            ),
          ),
          const SizedBox(width: NeuSpace.n6),
          NeuPressable(
            onTap: onShowInfo,
            radius: 14,
            child: const Padding(
              padding: EdgeInsets.all(NeuSpace.n11),
              child: NeuIcon(IconId.info, size: 18),
            ),
          ),
          const SizedBox(width: NeuSpace.n6),
          NeuPressable(
            onTap: onNewSession,
            radius: 14,
            child: const Padding(
              padding: EdgeInsets.all(NeuSpace.n11),
              child: NeuIcon(IconId.plus, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
