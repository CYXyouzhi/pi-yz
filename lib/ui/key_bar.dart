import 'package:flutter/material.dart';

import '../server/i18n.dart';

import '../services/key_encoder.dart';
import '../theme/design_tokens.dart';
import '../theme/neu.dart';
import 'neu_icons.dart';

/// 修饰键状态（粘滞逻辑）。
///
/// 手机上没有「按住不放」这种操作，所以修饰键必须做成**点一下锁定、
/// 下一次按键用掉后自动解除**。这也是设计稿里 `Ctrl` / `Alt` 键帽会「亮」的原因：
/// 用户需要看见自己刚锁定了什么。
class ModifierState {
  const ModifierState({
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
  });

  final bool ctrl;
  final bool alt;
  final bool shift;

  bool get any => ctrl || alt || shift;

  ModifierState toggleCtrl() =>
      ModifierState(ctrl: !ctrl, alt: alt, shift: shift);
  ModifierState toggleAlt() =>
      ModifierState(ctrl: ctrl, alt: !alt, shift: shift);
  ModifierState toggleShift() =>
      ModifierState(ctrl: ctrl, alt: alt, shift: !shift);
  ModifierState cleared() => const ModifierState();
}

/// 快捷键栏（设计稿 `.keybar`，两态）。
///
/// 设计稿对这两态的定义值得保留：
/// - **折叠** = 一行四键，常驻在输入条下。它是**流内元素**，占布局位而不是覆盖层，
///   所以永远不会盖住正在读的内容。
/// - **展开** = 完整面板（标题行 + 网格），底部导航同时收起让位 ——
///   一行只塞得下四个键，十二个键放不进去，这正是面板存在的理由。
/// - 「完成」是**显式出口**，Esc 与 ⌘ 是第二、第三条出口。
///
/// 材质上它走凹槽（与上方输入条同属一块「输入区」），键帽反过来隆起，
/// 读成一排托盘里的键。
class NeuKeyBar extends StatelessWidget {
  const NeuKeyBar({
    super.key,
    required this.visible,
    required this.expanded,
    required this.onExpandedChanged,
    required this.onVisibleChanged,
    required this.modifiers,
    required this.onModifiersChanged,
    required this.onKey,
    this.onCommands,
    this.onEnter,
    this.showModifiers = true,
  });

  /// 整条是否显示（折叠态按 Esc / 点「收起」后整条收起）
  final bool visible;

  /// 是否展开为完整面板
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;
  final ValueChanged<bool> onVisibleChanged;

  final ModifierState modifiers;
  final ValueChanged<ModifierState> onModifiersChanged;

  /// 发送一段已经编码好的字节序列。
  final ValueChanged<String> onKey;

  /// 额外的「命令」键：调出斜杠命令面板（聊天通道里用得上）。
  /// 为空则不显示这个键。
  final VoidCallback? onCommands;

  /// 额外的「Enter」键：手机软键盘的回车默认是换行，
  /// 需要发送时得有个明确的键。传了它就把展开面板里的「⇤ 反向」换成「⏎ 发送」
  /// （聊天通道里 shift-tab 和 Tab 语义重合，占着位置不如换成回车）。
  final VoidCallback? onEnter;

  /// 是否显示 Ctrl/Alt/⇧ 修饰键行。
  /// 聊天通道是 pi（agent）而不是终端，修饰键组合基本无意义，所以那里传 false，
  /// 免得界面上摆一排按了没反应的键。
  final bool showModifiers;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    return AnimatedSize(
      duration: context.neuDur(NeuMotion.panel),
      curve: NeuMotion.out,
      alignment: Alignment.bottomCenter,
      child: !visible
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: EdgeInsets.fromLTRB(
                NeuSpace.n18,
                0,
                NeuSpace.n18,
                NeuSpace.n9 + bottom,
              ),
              child: NeuInset(
                radius: NeuRadii.md,
                padding: EdgeInsets.symmetric(
                  horizontal: NeuSpace.n4,
                  vertical: expanded ? NeuSpace.n6 : 0,
                ),
                child: AnimatedSize(
                  duration: context.neuDur(NeuMotion.panel),
                  curve: NeuMotion.out,
                  alignment: Alignment.bottomCenter,
                  child: expanded ? _FullPanel(this) : _MiniRow(this),
                ),
              ),
            ),
    );
  }

  /// 编码一个「直发键」（不叠加修饰键）。Esc / Tab 这类键的语义不随修饰键改变。
  void _emit(String data) => onKey(data);

  /// 编码一个「受修饰键影响」的键，并在用完后解除粘滞。
  void _emitWithModifiers(
    String Function({bool shift, bool alt, bool ctrl}) build,
  ) {
    onKey(
      build(shift: modifiers.shift, alt: modifiers.alt, ctrl: modifiers.ctrl),
    );
    if (modifiers.any) onModifiersChanged(modifiers.cleared());
  }

  /// 点修饰键：切换锁定状态。
  void _toggleMod(ModifierState Function() toggle) {
    onModifiersChanged(toggle());
  }
}

/// 折叠态：一行四键，常驻。
class _MiniRow extends StatelessWidget {
  const _MiniRow(this.bar);

  final NeuKeyBar bar;

  @override
  Widget build(BuildContext context) {
    // 宽度**按内容分配**，不是等分：Esc / Tab 是 3 个字符，其余是 1 个
    // 字符或图标。等分时 Esc/Tab 的键帽会超出格子 —— 实测各溢出 4.8
    // 逻辑像素（Flutter 的 OVERFLOWED 警告，debug 下以黄黑条纹显示在界面上）。
    // 4/4/3/3/3/3 让这两格从 55.7 变 66.8 逻辑宽，键帽需要约 42.5，留 6 逻辑余量。
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: _KeyCap(
            kbd: 'Esc',
            label: I18n.t('ui.def9e98b60'),
            onTap: () {
              bar.onExpandedChanged(false);
              bar.onVisibleChanged(false);
            },
          ),
        ),
        Expanded(
          flex: 4,
          child: _KeyCap(
            kbd: 'Tab',
            label: I18n.t('ui.4cb4f622a9'),
            onTap: () => bar._emit(KeyEncoder.tab),
          ),
        ),
        Expanded(
          flex: 3,
          child: _KeyCap(
            kbd: '↑',
            label: I18n.t('ui.1facbf7790'),
            onTap: () => bar._emitWithModifiers(KeyEncoder.up),
          ),
        ),
        Expanded(
          flex: 3,
          child: _KeyCap(
            kbd: '↓',
            label: I18n.t('ui.3c81db078c'),
            onTap: () => bar._emitWithModifiers(KeyEncoder.down),
          ),
        ),
        Expanded(
          flex: 3,
          child: _KeyCap(
            kbd: '▤',
            label: I18n.t('ui.a8b0c20416'),
            onTap: () => bar.onExpandedChanged(true),
          ),
        ),
        if (bar.onCommands != null)
          Expanded(
            flex: 3,
            child: _KeyCap(
              kbd: '/',
              label: I18n.t('common.command'),
              onTap: bar.onCommands!,
            ),
          ),
      ],
    );
  }
}

/// 展开态：标题行（含修饰键）+ 四列三行网格。
class _FullPanel extends StatelessWidget {
  const _FullPanel(this.bar);

  final NeuKeyBar bar;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 标题行：修饰键放在这里，它们不参与网格（语义不同）──
        SizedBox(
          height: 36,
          child: Row(
            children: [
              SizedBox(width: NeuSpace.n6),
              Text(
                I18n.t('ui.f7d2996639'),
                style: TextStyle(
                  fontSize: NeuFonts.bodySmall,
                  fontWeight: FontWeight.w700,
                  color: t.fg,
                ),
              ),
              SizedBox(width: NeuSpace.n8),
              Expanded(
                child: Text(
                  bar.showModifiers
                      ? I18n.t('ui.ca760bfec8')
                      : I18n.t('ui.5ed98f5447'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: NeuFonts.badge, color: t.muted),
                ),
              ),
              if (bar.showModifiers) ...[
                _ModKey(
                  label: 'Ctrl',
                  active: bar.modifiers.ctrl,
                  onTap: () => bar._toggleMod(bar.modifiers.toggleCtrl),
                ),
                _ModKey(
                  label: 'Alt',
                  active: bar.modifiers.alt,
                  onTap: () => bar._toggleMod(bar.modifiers.toggleAlt),
                ),
                _ModKey(
                  label: '⇧',
                  active: bar.modifiers.shift,
                  onTap: () => bar._toggleMod(bar.modifiers.toggleShift),
                ),
              ],
              SizedBox(width: NeuSpace.n6),
              if (bar.onCommands != null)
                _KeyCap(
                  kbd: '/',
                  label: I18n.t('common.command'),
                  compact: true,
                  onTap: bar.onCommands!,
                ),
              SizedBox(width: NeuSpace.n4),
              _KeyCap(
                kbd: I18n.t('common.done'),
                label: '',
                compact: true,
                onTap: () => bar.onExpandedChanged(false),
              ),
            ],
          ),
        ),
        SizedBox(height: NeuSpace.n5),

        // ── 四列三行：12 个终端键 ──
        Row(
          children: [
            Expanded(
              child: _KeyCap(
                kbd: 'Esc',
                label: I18n.t('ui.c3992269b4'),
                onTap: () => bar._emit(KeyEncoder.esc),
              ),
            ),
            Expanded(
              child: _KeyCap(
                kbd: 'Tab',
                label: I18n.t('ui.4cb4f622a9'),
                onTap: () => bar._emit(KeyEncoder.tab),
              ),
            ),
            Expanded(
              child: bar.onEnter != null
                  ? _KeyCap(
                      kbd: '⏎',
                      label: I18n.t('ui.1535fcfa4c'),
                      onTap: bar.onEnter!,
                    )
                  : _KeyCap(
                      kbd: '⇤',
                      label: I18n.t('ui.123adf145e'),
                      onTap: () => bar._emit(KeyEncoder.shiftTab),
                    ),
            ),
            Expanded(
              child: _KeyCap(
                kbd: '^C',
                label: I18n.t('ui.d8d7ca77e9'),
                onTap: () => bar._emit(KeyEncoder.ctrlLetter('c')!),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _KeyCap(
                kbd: '↑',
                label: I18n.t('ui.af767b7e4a'),
                onTap: () => bar._emitWithModifiers(KeyEncoder.up),
              ),
            ),
            Expanded(
              child: _KeyCap(
                kbd: '↓',
                label: I18n.t('ui.3850a186c3'),
                onTap: () => bar._emitWithModifiers(KeyEncoder.down),
              ),
            ),
            Expanded(
              child: _KeyCap(
                kbd: '←',
                label: I18n.t('ui.d2aff14178'),
                onTap: () => bar._emitWithModifiers(KeyEncoder.left),
              ),
            ),
            Expanded(
              child: _KeyCap(
                kbd: '→',
                label: I18n.t('ui.4d9c32c23d'),
                onTap: () => bar._emitWithModifiers(KeyEncoder.right),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _KeyCap(
                kbd: 'PgUp',
                label: I18n.t('ui.6c7b1c13e5'),
                onTap: () => bar._emitWithModifiers(KeyEncoder.pageUp),
              ),
            ),
            Expanded(
              child: _KeyCap(
                kbd: 'PgDn',
                label: I18n.t('ui.821d4333ad'),
                onTap: () => bar._emitWithModifiers(KeyEncoder.pageDown),
              ),
            ),
            Expanded(
              child: _KeyCap(
                kbd: 'Home',
                label: I18n.t('ui.f422e88af6'),
                onTap: () => bar._emitWithModifiers(KeyEncoder.home),
              ),
            ),
            Expanded(
              child: _KeyCap(
                kbd: 'End',
                label: I18n.t('ui.e8567f144b'),
                onTap: () => bar._emitWithModifiers(KeyEncoder.end),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 修饰键键帽：锁定后变成实心强调块（`--accent` + `--on-accent`）。
class _ModKey extends StatelessWidget {
  const _ModKey({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n3),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: NeuMotion.micro,
          curve: NeuMotion.out,
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12),
          decoration: BoxDecoration(
            color: active ? t.accent : null,
            gradient: active ? null : NeuDecorations.raisedGradient(t),
            borderRadius: BorderRadius.circular(NeuRadii.xs),
            boxShadow: active
                ? null
                : [
                    BoxShadow(
                      color: t.nmLo,
                      offset: const Offset(2, 2),
                      blurRadius: 4,
                    ),
                    BoxShadow(
                      color: t.nmHi,
                      offset: const Offset(-2, -2),
                      blurRadius: 4,
                    ),
                  ],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: NeuFonts.badge,
                fontWeight: FontWeight.w700,
                color: active ? t.onAccent : t.accentInk,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 键帽：凹槽里的一颗隆起。标签用等宽字（`kbd`），说明用正文字。
///
/// 设计稿的尺寸取舍：键帽阴影收到 1.5px/4px —— 标准档的 3px/7px 是按 40px 的整卡
/// 定的，套在 22px 键帽上会糊成一圈灰晕，键读成洞。
class _KeyCap extends StatefulWidget {
  const _KeyCap({
    required this.kbd,
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  final String kbd;
  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  State<_KeyCap> createState() => _KeyCapState();
}

class _KeyCapState extends State<_KeyCap> {
  /// 按下高亮 —— 设计稿特别说明这一栏的另一半作用就在这里：
  /// 用户需要看见「我刚按的那个键到底生效了没有」。
  bool _hit = false;

  Future<void> _fire() async {
    setState(() => _hit = true);
    widget.onTap();
    await Future<void>.delayed(NeuMotion.struct);
    if (mounted) setState(() => _hit = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _fire,
      child: Padding(
        // 触控目标：折叠态 30 + 5×2 = 40dp（原来 2.5×2，只有 35dp）
        padding: const EdgeInsets.all(NeuSpace.n5),
        child: AnimatedContainer(
          duration: NeuMotion.micro,
          curve: NeuMotion.out,
          height: widget.compact ? 30 : 44,
          padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n4),
          decoration: BoxDecoration(
            color: _hit ? t.accent.withValues(alpha: 0.10) : null,
            borderRadius: BorderRadius.circular(NeuRadii.chip),
          ),
          child: LayoutBuilder(
            builder: (context, box) {
              // 这个 Row 可能在**宽度无界**的约束下被布局，也可能在紧约束里。
              //
              // · 展开面板的标题行：`/` 和「完成」是外层的**非 flex 子项**，
              //   而 Flutter 给非 flex 子项的主轴约束就是无界的
              //   （`RenderFlex._constraintsForNonFlexChild` 水平方向只写
              //   maxHeight，maxWidth 缺省即 infinity）。此时带 flex 的子项会
              //   直接断言失败（“children have non-zero flex but incoming width
              //   constraints are unbounded”），布局中断，整块面板只剩标题
              //   —— 用户看到的就是那张空白卡片。
              // · `Expanded` 里（折叠态那一排、展开面板的键位网格）：宽度是紧的，
              //   标号必须能收缩，否则溢出（实测溢出 6.1 逻辑像素）。
              //
              // 两种场景都要留住，所以按约束是否有界二选一。
              final bounded = box.maxWidth.isFinite;
              return Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 外面再包一层 FittedBox 兜底：键帽宽度由文字决定，若某台设备
                  // 的 monospace 度量比这里更宽，也只是把该键帽等比缩小（scaleDown），
                  // 不会再出现溢出警告。不超宽时它完全不改变尺寸。
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: // kbd：键帽本体（在凹槽里隆起）
                    AnimatedContainer(
                      duration: NeuMotion.micro,
                      curve: NeuMotion.out,
                      constraints: const BoxConstraints(minWidth: 22),
                      height: 22,
                      padding: const EdgeInsets.symmetric(
                        horizontal: NeuSpace.n6,
                      ),
                      decoration: BoxDecoration(
                        color: _hit ? t.accent : null,
                        gradient: _hit
                            ? null
                            : NeuDecorations.raisedGradient(t),
                        borderRadius: BorderRadius.circular(7),
                        boxShadow: _hit
                            ? null
                            : [
                                BoxShadow(
                                  color: t.nmLo,
                                  offset: const Offset(1.5, 1.5),
                                  blurRadius: 4,
                                ),
                                BoxShadow(
                                  color: t.nmHi,
                                  offset: const Offset(-1.5, -1.5),
                                  blurRadius: 4,
                                ),
                              ],
                      ),
                      child: Center(
                        child: Text(
                          widget.kbd,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: NeuFonts.micro,
                            height: 1,
                            fontWeight: FontWeight.w600,
                            color: _hit ? t.onAccent : t.fg,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.label.isNotEmpty) ...[
                    const SizedBox(width: NeuSpace.n5),
                    Flexible(
                      // flex 0 = 当非 flex 子项用，避开「无界 + flex」的断言。
                      flex: bounded ? 1 : 0,
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: NeuFonts.badge,
                          fontWeight: FontWeight.w600,
                          color: _hit ? t.accentInk : t.muted,
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 「滚动到最新」悬浮按钮（设计稿 `.scroll-down`）。
///
/// 位置由三段实高反推：快捷键栏高 + 输入条高 + 间隙。设计稿强调过
/// 这个按钮的落点与 `--kb-h` 耦合 —— 快捷键栏展开时按钮必须跟着上移，
/// 否则会压在键帽上。这里用 [bottomOffset] 由调用方按实际高度算出来。
class NeuScrollButton extends StatelessWidget {
  const NeuScrollButton({
    super.key,
    required this.visible,
    required this.onTap,
    this.bottomOffset = 0,
  });

  final bool visible;
  final VoidCallback onTap;
  final double bottomOffset;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return AnimatedPositioned(
      duration: NeuMotion.panel,
      curve: NeuMotion.spring,
      right: 20,
      bottom: bottomOffset,
      child: AnimatedOpacity(
        duration: NeuMotion.micro,
        curve: NeuMotion.out,
        opacity: visible ? 1 : 0,
        child: IgnorePointer(
          ignoring: !visible,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: NeuDecorations.raisedGradient(t),
                boxShadow: NeuShadows.raise(t),
              ),
              child: Center(
                child: NeuIcon(IconId.download, size: 18, color: t.fg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
