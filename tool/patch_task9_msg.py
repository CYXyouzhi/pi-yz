import io

p = 'lib/ui/server/message_view.dart'
s = io.open(p, encoding='utf-8').read()

# ---------- 1) import ----------
if 'native_bridge.dart' not in s:
    s = s.replace("import '../../server/chat_models.dart';",
                  "import 'dart:typed_data';\n\nimport '../../server/chat_models.dart';\nimport '../../server/native_bridge.dart';", 1)
    if 'import \'dart:typed_data\';' not in s:
        s = s.replace("import 'dart:convert';", "import 'dart:convert';\nimport 'dart:typed_data';", 1)

# ---------- 2) MessageTile 增加两个回调 ----------
s = s.replace("""  const MessageTile({
    super.key,
    required this.message,
    this.toolRun,
    this.runOf,
    this.onTapTool,
  });""",
"""  const MessageTile({
    super.key,
    required this.message,
    this.toolRun,
    this.runOf,
    this.onTapTool,
    this.onQuote,
    this.onEditResend,
  });""", 1)
s = s.replace("""  final ToolRun? Function(String id)? runOf;
  final VoidCallback? onTapTool;""",
"""  final ToolRun? Function(String id)? runOf;
  final VoidCallback? onTapTool;

  /// 长按菜单里的「引用」：把这段文字带引用标记塞回输入框
  final ValueChanged<String>? onQuote;

  /// 长按菜单里的「编辑重发」：把这条用户消息拉回输入框改写再发
  final ValueChanged<String>? onEditResend;""", 1)
s = s.replace("""    return _BubbleTile(message: message, runOf: runOf);""",
"""    return _BubbleTile(
      message: message,
      runOf: runOf,
      onQuote: onQuote,
      onEditResend: onEditResend,
    );""", 1)

# ---------- 3) _BubbleTile：双击复制 + 长按菜单 ----------
s = s.replace("""class _BubbleTile extends StatelessWidget {
  const _BubbleTile({required this.message, this.runOf});

  final ChatMessage message;
  final ToolRun? Function(String id)? runOf;""",
"""class _BubbleTile extends StatelessWidget {
  const _BubbleTile({
    required this.message,
    this.runOf,
    this.onQuote,
    this.onEditResend,
  });

  final ChatMessage message;
  final ToolRun? Function(String id)? runOf;
  final ValueChanged<String>? onQuote;
  final ValueChanged<String>? onEditResend;""", 1)

s = s.replace("""  /// 长按复制：手机上取一段文字最自然的动作
  Future<void> _copy(BuildContext context) async {
    final text = message.text.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    NeuToast.show(context, message: '已复制', icon: IconId.check);
  }""",
"""  /// 双击复制：手机上取一段文字最自然的动作（保留原来的即时手感）
  Future<void> _copy(BuildContext context) async {
    final text = message.text.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    NeuToast.show(context, message: '已复制', icon: IconId.check);
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
        margin: EdgeInsets.fromLTRB(14, 0, 14, 14 + MediaQuery.paddingOf(sheetContext).bottom),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NeuRadii.lg),
          gradient: NeuDecorations.raisedGradient(t),
          boxShadow: NeuShadows.raise(t),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasImages)
              _sheetRow(sheetContext, t, IconId.image, '保存图片到相册', 'save-image'),
            if (text.isNotEmpty) ...[
              _sheetRow(sheetContext, t, IconId.copy, '复制', 'copy'),
              _sheetRow(sheetContext, t, IconId.quote, '引用（回输入框）', 'quote'),
              if (isUser)
                _sheetRow(sheetContext, t, IconId.edit, '编辑重发', 'edit'),
              _sheetRow(sheetContext, t, IconId.share, '分享这段', 'share'),
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
        NeuToast.show(context, message: '已引用到输入框', icon: IconId.quote);
      case 'edit':
        onEditResend?.call(text);
        NeuToast.show(context, message: '已拉回输入框，改完再发', icon: IconId.edit);
      case 'share':
        final ok = await NativeBridge.shareText(text: text);
        if (!context.mounted) return;
        NeuToast.show(
          context,
          message: ok ? '已打开分享面板' : '分享不可用（系统没接住）',
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Row(
        children: [
          NeuIcon(icon, size: 16, color: t.muted),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 14.5, color: t.fg)),
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
        NeuToast.show(context, message: '图片数据坏了，存不了', icon: IconId.warn);
      }
      return;
    }
    final ext = (image.mimeType ?? 'image/png').contains('jpeg') ? 'jpg' : 'png';
    final ok = await NativeBridge.saveImage(
      bytes,
      name: 'pi-${DateTime.now().millisecondsSinceEpoch}.$ext',
    );
    if (!context.mounted) return;
    NeuToast.show(
      context,
      message: ok ? '已存到相册（Pictures/pi-mobile）' : '保存失败：系统相册没接住',
      icon: ok ? IconId.check : IconId.warn,
    );
  }""", 1)

# 手势：双击复制 + 长按菜单
s = s.replace("""      child: GestureDetector(
        onLongPress: () => _copy(context),""",
"""      child: GestureDetector(
        // 双击复制、长按出菜单（复制在第一行）
        onDoubleTap: () => _copy(context),
        onLongPress: () => _showActions(context),""", 1)

# ---------- 4) 图片长按：保存到相册 ----------
s = s.replace("""class _MessageImages extends StatelessWidget {
  const _MessageImages({required this.images});

  final List<PiImage> images;""",
"""class _MessageImages extends StatelessWidget {
  const _MessageImages({required this.images});

  final List<PiImage> images;

  /// 长按图片直接存相册：图片本来就该有「存下来」这个动作
  Future<void> _saveToGallery(BuildContext context, PiImage image) async {
    Uint8List bytes;
    try {
      bytes = base64Decode(image.data);
    } catch (_) {
      NeuToast.show(context, message: '图片数据坏了，存不了', icon: IconId.warn);
      return;
    }
    final ext = (image.mimeType ?? 'image/png').contains('jpeg') ? 'jpg' : 'png';
    final ok = await NativeBridge.saveImage(
      bytes,
      name: 'pi-${DateTime.now().millisecondsSinceEpoch}.$ext',
    );
    if (!context.mounted) return;
    NeuToast.show(
      context,
      message: ok ? '已存到相册（Pictures/pi-mobile）' : '保存失败：系统相册没接住',
      icon: ok ? IconId.check : IconId.warn,
    );
  }""", 1)

s = s.replace("""              child: ClipRRect(
                borderRadius: BorderRadius.circular(NeuRadii.sm),
                child: _decode(image, t),
              ),""",
"""              child: GestureDetector(
                onLongPress: () => _saveToGallery(context, image),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(NeuRadii.sm),
                  child: _decode(image, t),
                ),
              ),""", 1)

io.open(p, 'w', encoding='utf-8').write(s)
print('message_view.dart 已改')
