import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/neu.dart';
import 'neu_icons.dart';

/// 默认折叠成一行、点开看全文的次要文本。
///
/// 为什么需要它：手机竖屏的竖向空间最稀缺，而「安装路径」「完整命令」这类
/// 次要信息常常占 2–3 行 —— 截断又等于没给（用户就是要看完整路径），
/// 所以做法是**默认一行、点一下展开**。
class CollapsibleText extends StatefulWidget {
  const CollapsibleText({
    super.key,
    required this.text,
    this.style,
    this.expandableIfLongerThan = 28,
  });

  final String text;
  final TextStyle? style;

  /// 超过这么多个字符才值得给展开箭头（短文本不折腾）。
  final int expandableIfLongerThan;

  @override
  State<CollapsibleText> createState() => _CollapsibleTextState();
}

class _CollapsibleTextState extends State<CollapsibleText> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final style = widget.style ??
        TextStyle(fontSize: NeuFonts.micro, color: t.muted);
    if (widget.text.length <= widget.expandableIfLongerThan) {
      return Text(widget.text, style: style);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _open = !_open),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              widget.text,
              maxLines: _open ? null : 1,
              overflow: _open ? null : TextOverflow.ellipsis,
              style: style,
            ),
          ),
          const SizedBox(width: NeuSpace.n4),
          NeuIcon(
            _open ? IconId.chevronDown : IconId.chevronRight,
            size: 12,
            color: t.muted,
          ),
        ],
      ),
    );
  }
}
