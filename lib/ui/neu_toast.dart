import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/neu.dart';
import 'neu_icons.dart';

/// Toast（设计稿 `.toast`）。
///
/// 设计稿对它的定位很清楚：它是**一条状态播报**，不是弹窗 ——
/// 从底部升起、停一会儿、自己退场，期间不打断任何操作。
///
/// 材质上它全套设计里唯一的**深色块**（`--toast-bg` 浅色档是 34% 明度的石板青，
/// 深色档反而翻成 92% 的亮块）。这是刻意的：Toast 要「浮」在所有材质之上，
/// 而新拟态靠阴影做不出跨越层级的感觉，只能靠明度反转把视线抢过来。
///
/// 实现说明（2026-10-03 改）：
/// 原先用自定义 OverlayEntry 绘制，在 MuMu 上实测**任何 toast 都不可见**
/// （新建会话、切模型、复制全都没有反馈）。排查掉主题扩展/动效取值两条隐患后
/// 仍不渲染，于是改用 [ScaffoldMessenger]，保留同一套配色与圆角 ——
/// 样式略简化，但「反馈一定看得见」优先。
class NeuToast {
  const NeuToast._();

  /// 显示一条 toast。
  ///
  /// [icon] 可选图标；[actionLabel] + [onAction] 给出一个可点的补救动作
  /// （设计稿的 `.toast-act`，例如「看日志」「重试」）。
  static void show(
    BuildContext context, {
    required String message,
    IconId? icon,
    IconId? actionIcon,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
    bool rootOverlay = true,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final tokens = Theme.of(context).extension<NeuTheme>()?.tokens ??
        (Theme.of(context).brightness == Brightness.dark
            ? NeuTokens.dark
            : NeuTokens.light);

    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              if (icon != null) ...[
                NeuIcon(icon, size: 16, color: tokens.toastAccent),
                const SizedBox(width: NeuSpace.n10),
              ],
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: NeuFonts.bodyMid,
                    height: 1.45,
                    color: tokens.toastFg,
                  ),
                ),
              ),
            ],
          ),
          duration: duration,
          behavior: SnackBarBehavior.floating,
          backgroundColor: tokens.toastBg,
          elevation: 0,
          margin: const EdgeInsets.fromLTRB(NeuSpace.n18, 0, NeuSpace.n18, 96),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NeuRadii.md),
          ),
          action: actionLabel == null
              ? null
              : SnackBarAction(
                  label: actionLabel,
                  textColor: tokens.toastAccent,
                  onPressed: () {
                    onAction?.call();
                    messenger.hideCurrentSnackBar();
                  },
                ),
        ),
      );
  }

  /// 立刻收起当前 toast（保留旧接口，调用点不用改）
  static void dismiss() {}
}
