import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../server/chat_reducer.dart';
import '../../../server/elapsed_index.dart';
import '../../../server/server_store.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../neu_icons.dart';
import '../message_view.dart';
import 'bars.dart';
import 'loading.dart';

// 拆分后这里同时承担「对外接口」的角色：搬走的东西继续 export 出去，
// 于是 40 多个 import 'chat/widgets.dart' 的调用点一行都不用改。
// 注意 export 只影响「导入本文件的人」，本文件自己要用的符号仍要 import（所以上下都有）。
export 'bars.dart';
export 'composer.dart';
export 'dialogs.dart';
export 'header.dart';
export 'loading.dart';
export 'message_detail.dart';
export 'sheets.dart';

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
