// 消息渲染。
//
// 视觉规则取自设计稿 pi-remote-app.html：
//   · agent 气泡 = 隆起软块（surface 渐变 + nm-raise）
//   · user  气泡 = accent 实心（凸凹对比 + 颜色双重区分「我」和「它」）
//   · 工具卡片 = 凹槽 + 等宽字，读作「一次机器执行」而不是「一次发言」
//   · 气泡圆角各留一角缺口：user 右下 8px、agent 左下 8px（对话指向感）

import 'dart:convert';
import '../collapsible_text.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../server/chat_models.dart';
import '../../server/i18n.dart';
import '../../server/native_bridge.dart';
import '../../server/app_prefs.dart';
import '../../server/server_types.dart';
import '../../theme/design_tokens.dart';
import '../../theme/neu.dart';
import '../neu_icons.dart';
import '../neu_toast.dart';
import 'markdown_view.dart';

/// 错误消息超过这个长度就默认折叠（单位：字符）。
///
/// 160 的来历：pi 的报错里，不带堆栈的短错误通常一行内说完（几十字符）；
/// 一旦超过 160，基本就是带堆栈或整段 JSON —— 那才是真正需要折叠的对象。
///
/// **这个值必须与传给 CollapsibleText 的 `expandableIfLongerThan` 是同一个**：
/// 若外面用 160 判断、里面传别的值，就会出现「折叠了但点不开」或
/// 「能点开却没折叠」这类只在长错误上复现的怪状态。
const int kErrorCollapseThreshold = 160;

/// `820ms` / `3.4s` / `2m10s` —— 耗时数字，短到能挂在气泡旁边
String humanElapsed(Duration d) {
  final ms = d.inMilliseconds;
  if (ms < 1000) return '${ms}ms';
  final seconds = ms / 1000;
  if (seconds < 10) return '${seconds.toStringAsFixed(1)}s';
  if (seconds < 60) return '${seconds.round()}s';
  final m = ms ~/ 60000;
  final s = (ms % 60000) ~/ 1000;
  return s == 0 ? '${m}m' : '${m}m${s}s';
}

class MessageTile extends StatelessWidget {
  const MessageTile({
    super.key,
    required this.message,
    this.toolRun,
    this.runOf,
    this.onTapTool,
    this.onQuote,
    this.onEditResend,
    this.elapsed,
  });

  final ChatMessage message;

  /// 这条消息与本轮前一条消息之间的间隔 —— 「这一轮花了多久」的直观数字
  final Duration? elapsed;

  /// 对应的工具运行状态（toolResult 消息用）
  final ToolRun? toolRun;

  /// 按 toolCallId 查工具运行状态（assistant 消息里的 toolCall 用）
  final ToolRun? Function(String id)? runOf;
  final VoidCallback? onTapTool;

  /// 长按菜单里的「引用」：把这段文字带引用标记塞回输入框
  final ValueChanged<String>? onQuote;

  /// 长按菜单里的「编辑重发」：把这条用户消息拉回输入框改写再发
  final ValueChanged<String>? onEditResend;

  @override
  Widget build(BuildContext context) {
    if (message.isToolResult) {
      final tile = _ToolTile(message: message, run: toolRun, onTap: onTapTool);
      // 工具结果是真正「花时间的那一步」，耗时挂在这里比挂在文字气泡上有用得多。
      // 不再动 _ToolTile 内部：外面包一层就够了，改内部反而容易碰坏它的展开逻辑。
      if (elapsed == null || elapsed!.inMilliseconds < 200) return tile;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          tile,
          Padding(
            padding: const EdgeInsets.only(top: NeuSpace.n2, right: NeuSpace.n4),
            child: Text(
              humanElapsed(elapsed!),
              style: TextStyle(
                fontSize: NeuFonts.micro,
                color: context.neu.muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      );
    }
    return _BubbleTile(
      message: message,
      runOf: runOf,
      onQuote: onQuote,
      onEditResend: onEditResend,
      elapsed: elapsed,
    );
  }
}

/// 头像：30×30 圆角 10，user 用凹槽、agent 用隆起
class _Avatar extends StatelessWidget {
  const _Avatar({required this.isUser});

  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NeuRadii.xs),
        gradient: isUser
            ? NeuDecorations.wellGradient(t)
            : NeuDecorations.raisedGradient(t),
        boxShadow: isUser ? NeuShadows.insetSm(t) : NeuShadows.raiseSm(t),
      ),
      alignment: Alignment.center,
      child: Text(
        isUser ? I18n.t('ui.7bbc73646a') : 'p',
        style: TextStyle(
          fontSize: NeuFonts.small,
          fontWeight: FontWeight.w700,
          color: isUser ? t.fg : t.accentInk,
        ),
      ),
    );
  }
}

class _BubbleTile extends StatelessWidget {
  const _BubbleTile({
    required this.message,
    this.runOf,
    this.onQuote,
    this.onEditResend,
    this.elapsed,
  });

  final ChatMessage message;
  final Duration? elapsed;
  final ToolRun? Function(String id)? runOf;
  final ValueChanged<String>? onQuote;
  final ValueChanged<String>? onEditResend;

  /// 双击复制：手机上取一段文字最自然的动作（保留原来的即时手感）
  Future<void> _copy(BuildContext context) async {
    final text = message.text.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    NeuToast.show(context, message: I18n.t('common.copied'), icon: IconId.check);
  }

  /// 长按菜单：复制 / 引用 / 编辑重发 / 分享
  ///
  /// 为什么不再让长按直接复制：能做的事情变多了，一个手势塞不下，
  /// 但把「复制」放在第一行，肌肉记忆还是两步之内。
  Future<void> _showActions(BuildContext context) async {
    final t = context.neu;
    final text = message.text.trim();
    final isUser = message.isUser;
    final hasImages = message.blocks.whereType<PiImage>().isNotEmpty;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        margin: EdgeInsets.fromLTRB(NeuSpace.n14, 0, NeuSpace.n14, NeuSpace.n14 + MediaQuery.paddingOf(sheetContext).bottom),
        padding: const EdgeInsets.symmetric(vertical: NeuSpace.n8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NeuRadii.lg),
          gradient: NeuDecorations.raisedGradient(t),
          boxShadow: NeuShadows.raise(t),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasImages)
              _sheetRow(sheetContext, t, IconId.image, I18n.t('ui.a2e9a7991a'), 'save-image'),
            if (text.isNotEmpty) ...[
              _sheetRow(sheetContext, t, IconId.copy, I18n.t('ui.79d3abe929'), 'copy'),
              _sheetRow(sheetContext, t, IconId.bubble, I18n.t('ui.0f875dd0dc'), 'quote'),
              if (isUser)
                _sheetRow(sheetContext, t, IconId.pen, I18n.t('ui.7c79620b1a'), 'edit'),
              _sheetRow(sheetContext, t, IconId.share, I18n.t('ui.96c2ee76cd'), 'share'),
            ],
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;

    switch (action) {
      case 'copy':
        await _copy(context);
      case 'quote':
        onQuote?.call(text);
        NeuToast.show(context, message: I18n.t('ui.c881be90ec'), icon: IconId.bubble);
      case 'edit':
        onEditResend?.call(text);
        NeuToast.show(context, message: I18n.t('ui.0ed6fd21dd'), icon: IconId.pen);
      case 'share':
        final ok = await NativeBridge.shareText(text: text);
        if (!context.mounted) return;
        NeuToast.show(
          context,
          message: ok ? I18n.t('ui.06a3c99161') : I18n.t('ui.56ed8b49c3'),
          icon: ok ? IconId.share : IconId.warn,
        );
      case 'save-image':
        await _saveFirstImage(context);
    }
  }

  Widget _sheetRow(
    BuildContext context,
    NeuTokens t,
    IconId icon,
    String label,
    String value,
  ) {
    return NeuPressable(
      onTap: () => Navigator.of(context).pop(value),
      flat: true,
      radius: NeuRadii.sm,
      padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n16, vertical: NeuSpace.n13),
      margin: const EdgeInsets.symmetric(horizontal: NeuSpace.n6, vertical: NeuSpace.n1),
      child: Row(
        children: [
          NeuIcon(icon, size: 16, color: t.muted),
          const SizedBox(width: NeuSpace.n12),
          Text(label, style: TextStyle(fontSize: NeuFonts.body, color: t.fg)),
        ],
      ),
    );
  }

  Future<void> _saveFirstImage(BuildContext context) async {
    final image = message.blocks.whereType<PiImage>().firstOrNull;
    if (image == null) return;
    Uint8List bytes;
    try {
      bytes = base64Decode(image.data);
    } catch (_) {
      if (context.mounted) {
        NeuToast.show(context, message: I18n.t('ui.db2728b716'), icon: IconId.warn);
      }
      return;
    }
    final ext = image.mimeType.contains('jpeg') ? 'jpg' : 'png';
    final ok = await NativeBridge.saveImage(
      bytes,
      name: 'pi-${DateTime.now().millisecondsSinceEpoch}.$ext',
    );
    if (!context.mounted) return;
    NeuToast.show(
      context,
      message: ok ? I18n.t('ui.3586246ba6') : I18n.t('ui.e383057c96'),
      icon: ok ? IconId.check : IconId.warn,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final isUser = message.isUser;
    final hasThinking = message.thinking.trim().isNotEmpty;
    final images = message.blocks.whereType<PiImage>().toList();
    // 摘要类消息（分支摘要 / 自动压缩）：自定义角色，界面上要标清楚是什么，
    // 否则和模型回复混在一起，看不出这段文字是自动生成的
    final summaryLabel = switch (message.role) {
      'branchSummary' => I18n.t('ui.f8dc3f9a56'),
      'compactionSummary' => I18n.t('ui.b900e1a8a8'),
      _ => null,
    };

    // 手势套在 Padding **外面**：气泡左右那两条留白也算这条消息的可点区。
    // 双击复制（①）本来就该有大的落点 —— 只包住气泡的话，
    // 落点只剩头像和几像素的缝，手机上根本点不准。
    return GestureDetector(
      // opaque：留白是透明的，不加这个，点在留白上不算命中
      behavior: HitTestBehavior.opaque,
      // 双击复制（①）：气泡**正文**上的双击仍然归系统的「选词」，
      // 留白与头像上双击则是整条复制。这是刻意取舍：
      // 选一段文字复制比整条复制更常用，不能为了双击把它让掉。
      onDoubleTap: () => _copy(context),
      // 长按仍然给系统文本选择（选一段复制是刚需），
      // 我们自己的菜单走每条消息右侧那个 ⋮ —— 长按会被选择工具条抢走手势，
      // 这一点是实测出来的，不是猜的。
      onLongPress: () => _showActions(context),
      child: Padding(
      padding: EdgeInsets.only(
        left: isUser ? 46 : 0,
        right: isUser ? 0 : 46,
        top: NeuSpace.n5,
        bottom: NeuSpace.n5,
      ),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const _Avatar(isUser: false),
            const SizedBox(width: NeuSpace.n8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // 图片排在最前：发截图时用户先看的是图
                if (images.isNotEmpty) _MessageImages(images: images),
                if (summaryLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(left: NeuSpace.n4, bottom: NeuSpace.n4),
                    child: Row(
                      children: [
                        NeuIcon(IconId.info, size: 13, color: t.accentInk),
                        const SizedBox(width: NeuSpace.n6),
                        Text(
                          summaryLabel,
                          style: TextStyle(
                            fontSize: NeuFonts.label,
                            fontWeight: FontWeight.w700,
                            color: t.accentInk,
                          ),
                        ),
                        SizedBox(width: NeuSpace.n8),
                        Text(
                          I18n.t('ui.cc2177391a'),
                          style: TextStyle(fontSize: NeuFonts.micro, color: t.muted),
                        ),
                      ],
                    ),
                  ),
                if (hasThinking && !isUser) ...[
                  _ThinkingBlock(text: message.thinking),
                  const SizedBox(height: NeuSpace.n6),
                ],
                if (message.toolCalls.isNotEmpty && !isUser)
                  // 只显示「还没有结果」的调用：有结果时工具结果那条消息
                  // （_ToolTile）自己带「完成/失败」标签，再显示一遍 chip 就是
                  // 同一个工具占两行 —— 这是用户反馈「工具不折叠」的直接原因。
                  ...message.toolCalls
                      .where((call) {
                        final run = runOf?.call(call.id);
                        return run == null || run.status == ToolStatus.running;
                      })
                      .map(
                        (call) => Padding(
                          padding: const EdgeInsets.only(bottom: NeuSpace.n6),
                          child: _ToolCallChip(
                            call: call,
                            run: runOf?.call(call.id),
                          ),
                        ),
                      ),
                if (message.text.isNotEmpty || message.streaming)
                  // 长错误默认折叠：pi 的报错常带整段堆栈（几十行），
                  // 全展开会把消息区挤没；截断又等于没给（用户要拿去搜），
                  // 所以默认一行、点开看全文。正常回复不走这条路。
                  message.isError && message.text.length > kErrorCollapseThreshold
                      ? CollapsibleText(
                          text: message.text,
                          expandableIfLongerThan: kErrorCollapseThreshold,
                          style: TextStyle(
                            fontSize: NeuFonts.bodyMid,
                            color: t.danger,
                            height: 1.5,
                          ),
                        )
                      : _Bubble(message: message),
                if (message.isError)
                  Padding(
                    padding: EdgeInsets.only(top: NeuSpace.n4),
                    child: Text(
                      I18n.t('ui.ad8e01fe71'),
                      style: TextStyle(fontSize: NeuFonts.label, color: t.danger),
                    ),
                  ),
                // 本轮耗时（task-21 合同①）：跟「出错」同一行的位置，
                // 只给 assistant —— 用户消息的间隔是人在打字，没有参考价值
                if (!isUser && elapsed != null && elapsed!.inMilliseconds >= 200)
                  Padding(
                    padding: const EdgeInsets.only(top: NeuSpace.n3),
                    child: Text(
                      humanElapsed(elapsed!),
                      style: TextStyle(
                        fontSize: NeuFonts.micro,
                        color: t.muted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: NeuSpace.n8),
            const _Avatar(isUser: true),
          ],
          // 两条消息之间的空隙放 ⋮：不压住正文，也不用长按（长按留给选文字）
          _MoreButton(onTap: () => _showActions(context)),
        ],
      ),
      ),
    );
  }
}

/// 消息上的「⋮」：复制 / 引用 / 编辑重发 / 分享 / 存图的入口。
///
/// 为什么不做成长按：气泡里的正文是可选中的（Markdown 用 SelectableText），
/// 长按手势会被系统的选择工具条吃掉 —— 实测长按弹出来的是 Copy/Share/Select all。
class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n2),
        child: NeuIcon(IconId.more, size: 15, color: t.muted.withValues(alpha: 0.75)),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final isUser = message.isUser;

    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(NeuRadii.md),
          topRight: const Radius.circular(NeuRadii.md),
          bottomLeft: Radius.circular(isUser ? NeuRadii.md : 8),
          bottomRight: Radius.circular(isUser ? 8 : NeuRadii.md),
        ),
        gradient: isUser
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(t.accent, Colors.white, 0.12)!,
                  t.accent,
                  Color.lerp(t.accent, Colors.black, 0.14)!,
                ],
                stops: const [0.0, 0.54, 1.0],
              )
            : NeuDecorations.raisedGradient(t),
        boxShadow: isUser
            ? [
                BoxShadow(color: t.nmLo, offset: const Offset(4, 4), blurRadius: 11),
                BoxShadow(color: t.nmHi, offset: const Offset(-4, -4), blurRadius: 11),
              ]
            : NeuShadows.raise(t),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: NeuSpace.n12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.text.isNotEmpty)
            // 用户消息保持纯文本（它就在 accent 实心气泡里，走 markdown
            // 反而会把普通文字里的符号当成语法）；模型回答走 Markdown。
            isUser
                ? SelectableText(
                    message.text,
                    style: TextStyle(
                      fontSize: NeuFonts.body,
                      height: AppPrefs.instance.lineHeight + 0.25,
                      color: t.onAccent,
                    ),
                  )
                : NeuMarkdown(data: message.text),
          if (message.streaming && message.text.isEmpty)
            const _TypingDots(),
        ],
      ),
    );
  }
}

/// 消息里的图片。
///
/// user 可以发截图，assistant 也可能带图；图片内容是 base64。
/// 解码失败（比如格式不对）就整块跳过，不让一条坏图拖垮整个列表。
class _MessageImages extends StatelessWidget {
  const _MessageImages({required this.images});

  final List<PiImage> images;

  /// 长按图片直接存相册：图片本来就该有「存下来」这个动作
  Future<void> _saveToGallery(BuildContext context, PiImage image) async {
    Uint8List bytes;
    try {
      bytes = base64Decode(image.data);
    } catch (_) {
      NeuToast.show(context, message: I18n.t('ui.db2728b716'), icon: IconId.warn);
      return;
    }
    final ext = image.mimeType.contains('jpeg') ? 'jpg' : 'png';
    final ok = await NativeBridge.saveImage(
      bytes,
      name: 'pi-${DateTime.now().millisecondsSinceEpoch}.$ext',
    );
    if (!context.mounted) return;
    NeuToast.show(
      context,
      message: ok ? I18n.t('ui.3586246ba6') : I18n.t('ui.e383057c96'),
      icon: ok ? IconId.check : IconId.warn,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Padding(
      padding: const EdgeInsets.only(bottom: NeuSpace.n6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final image in images)
            Padding(
              padding: const EdgeInsets.only(bottom: NeuSpace.n4),
              child: GestureDetector(
                onLongPress: () => _saveToGallery(context, image),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(NeuRadii.sm),
                  child: _decode(image, t),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _decode(PiImage image, NeuTokens t) {
    try {
      final bytes = base64Decode(image.data);
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240, maxHeight: 320),
        child: Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => _broken(t),
        ),
      );
    } catch (_) {
      return _broken(t);
    }
  }

  Widget _broken(NeuTokens t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n10, vertical: NeuSpace.n8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NeuRadii.sm),
          color: t.well,
        ),
        child: Text(I18n.t('ui.e2cf8c9f6c'), style: TextStyle(fontSize: NeuFonts.label, color: t.muted)),
      );
}

/// 流式等待的三点动画
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return SizedBox(
      height: 18,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final phase = (_controller.value * 3 - index * 0.18) % 1.0;
            final lift = phase < 0.3 ? (0.3 - phase) / 0.3 : 0.0;
            return Padding(
              padding: const EdgeInsets.only(right: NeuSpace.n3),
              child: Transform.translate(
                offset: Offset(0, -3.5 * lift),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: t.muted.withValues(alpha: 0.3 + 0.7 * lift),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// 思考块：折叠的凹槽，等宽字
class _ThinkingBlock extends StatefulWidget {
  const _ThinkingBlock({required this.text});

  final String text;

  @override
  State<_ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<_ThinkingBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final preview = widget.text.trim();
    final shown = _expanded
        ? preview
        : (preview.length > 90 ? '${preview.substring(0, 90)}…' : preview);

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NeuRadii.sm),
          gradient: NeuDecorations.wellGradient(t),
          boxShadow: NeuShadows.insetSm(t),
        ),
        padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                NeuIcon(IconId.info, size: 14, color: t.muted),
                SizedBox(width: NeuSpace.n6),
                Text(
                  I18n.t('ui.21d68b2de0'),
                  style: TextStyle(fontSize: NeuFonts.label, color: t.muted, letterSpacing: 0.5),
                ),
                const Spacer(),
                NeuIcon(
                  _expanded ? IconId.chevronDown : IconId.chevronRight,
                  size: 14,
                  color: t.muted,
                ),
              ],
            ),
            const SizedBox(height: NeuSpace.n6),
            Text(
              shown,
              style: TextStyle(
                fontSize: NeuFonts.sub,
                height: 1.65,
                color: t.muted,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 工具调用（来自 assistant 消息的 toolCall）
class _ToolCallChip extends StatelessWidget {
  const _ToolCallChip({required this.call, this.run});

  final PiToolCall call;

  /// 有运行状态时显示「运行中 / 完成 / 失败」
  final ToolRun? run;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final isRunning = run?.status == ToolStatus.running;
    final isError = run?.status == ToolStatus.error;
    return _ToolShell(
      icon: isRunning ? IconId.spinner : IconId.terminal,
      title: call.name,
      subtitle: call.summary.isEmpty ? (run?.output.split('\n').first ?? '') : call.summary,
      tag: isRunning ? I18n.t('common.running') : (isError ? I18n.t('common.failed') : I18n.t('ui.97d29d8430')),
      accentInk: isError ? t.danger : t.accentInk,
    );
  }
}

/// 工具结果（toolResult 消息）
class _ToolTile extends StatefulWidget {
  const _ToolTile({required this.message, this.run, this.onTap});

  final ChatMessage message;
  final ToolRun? run;
  final VoidCallback? onTap;

  @override
  State<_ToolTile> createState() => _ToolTileState();
}

class _ToolTileState extends State<_ToolTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final run = widget.run;
    final output = widget.message.text.isNotEmpty
        ? widget.message.text
        : (run?.output ?? '');
    final isRunning = run?.status == ToolStatus.running;
    final isError = widget.message.isError || run?.status == ToolStatus.error;

    final tag = isRunning
        ? I18n.t('common.running')
        : isError
            ? I18n.t('common.failed')
            : I18n.t('common.done');

    return Padding(
      padding: const EdgeInsets.only(left: 38, top: NeuSpace.n4, bottom: NeuSpace.n4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: output.isEmpty
                ? widget.onTap
                : () => setState(() => _expanded = !_expanded),
            child: _ToolShell(
              // 工具结果也是「工具调用」的一部分：默认同样收成单行细条，
              // 要看输出点右边的箭头展开（task-21 合同①）
              compact: true,
              icon: isRunning ? IconId.spinner : IconId.terminal,
              title: widget.message.toolName ?? run?.name ?? I18n.t('ui.20dce2c6fa'),
              subtitle: _firstLine(output),
              tag: tag,
              accentInk: isError ? t.danger : t.accentInk,
              trailing: output.isEmpty
                  ? null
                  : NeuIcon(
                      _expanded ? IconId.chevronDown : IconId.chevronRight,
                      size: 14,
                      color: t.muted,
                    ),
            ),
          ),
          if (_expanded && output.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: NeuSpace.n6),
              constraints: const BoxConstraints(maxHeight: 280),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(NeuRadii.sm),
                gradient: NeuDecorations.wellGradient(t),
                boxShadow: NeuShadows.insetSm(t),
              ),
              padding: const EdgeInsets.all(NeuSpace.n10),
              child: SingleChildScrollView(
                child: SelectableText(
                  output,
                  style: TextStyle(
                    fontSize: NeuFonts.label,
                    height: 1.5,
                    fontFamily: 'monospace',
                    color: t.fg,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _firstLine(String text) {
    if (text.isEmpty) return '';
    final line = text.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    return line.length > 80 ? '${line.substring(0, 80)}…' : line;
  }
}

/// 工具卡片的共用外观：凹槽 + 圆角图标底板 + 等宽标题 + 右侧标签
class _ToolShell extends StatelessWidget {
  const _ToolShell({
    required this.icon,
    required this.title,
    required this.tag,
    required this.accentInk,
    this.subtitle = '',
    this.trailing,
    this.compact = true,
  });

  final IconId icon;
  final String title;
  final String tag;
  final Color accentInk;
  final String subtitle;
  final Widget? trailing;

  /// 单行细条（默认）。工具结果那种要看输出的地方传 false。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.82,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NeuRadii.sm),
        gradient: NeuDecorations.wellGradient(t),
        boxShadow: NeuShadows.insetSm(t),
      ),
      // task-21 合同①：工具调用默认是**单行细条**，不是大块卡片。
      // 一屏里工具调用往往比正文还多，每条占三行会让对话主干被冲散；
      // 摘要（subtitle）改为只在用户主动点开时看得到（列在展开区里）。
      padding: EdgeInsets.fromLTRB(NeuSpace.n7, compact ? NeuSpace.n4 : NeuSpace.n9, NeuSpace.n9, compact ? NeuSpace.n4 : NeuSpace.n9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 18 : 26,
            height: compact ? 18 : 26,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(compact ? 6 : 9),
              gradient: NeuDecorations.raisedGradient(t),
              boxShadow: NeuShadows.raiseSm(t),
            ),
            alignment: Alignment.center,
            child: NeuIcon(icon, size: compact ? 11 : 14, color: accentInk),
          ),
          SizedBox(width: compact ? 7 : 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 11.5 : 12.5,
                    fontFamily: 'monospace',
                    color: accentInk,
                  ),
                ),
                if (!compact && subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: NeuFonts.badge, color: t.muted),
                  ),
              ],
            ),
          ),
          SizedBox(width: compact ? 6 : 8),
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: compact ? NeuSpace.n5 : NeuSpace.n7, vertical: compact ? NeuSpace.n2 : NeuSpace.n3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(compact ? 5 : 6),
              border: Border.all(color: t.muted.withValues(alpha: 0.3)),
            ),
            child: Text(
              tag,
              style: TextStyle(
                  fontSize: compact ? 9.5 : 10,
                  color: t.muted,
                  letterSpacing: 0.6),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: NeuSpace.n6),
            trailing!,
          ],
        ],
      ),
    );
  }
}
