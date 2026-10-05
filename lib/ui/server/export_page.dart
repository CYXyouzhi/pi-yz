// 会话导出页：预览 Markdown → 复制 / 存到手机 / 导出到服务端。
//
// 为什么手机端要单独做个「导出」页，而不是只给一个服务端路径：
//   pi 自带的 /export 是把 HTML 写到电脑上，手机用户看不到、也用不上。
//   手机端的导出要能：在 App 里预览、复制走、或者存进手机文件目录，
//   所以这里拉的是 Markdown 文本，HTML/JSONL 作为「落到电脑上」的附加选项。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../server/server_store.dart';
import '../../server/i18n.dart';
import '../../theme/design_tokens.dart';
import '../../theme/neu.dart';
import '../neu_icons.dart';
import '../neu_toast.dart';
import 'markdown_view.dart';

class SessionExportPage extends StatefulWidget {
  const SessionExportPage({super.key, required this.store});

  final ServerStore store;

  @override
  State<SessionExportPage> createState() => _SessionExportPageState();
}

class _SessionExportPageState extends State<SessionExportPage> {
  String _markdown = '';
  String _filename = 'session.md';
  String _title = '';
  bool _loading = true;
  String? _error;

  /// 服务端导出的两个路径（HTML / JSONL），导出成功后显示出来供复制
  Map<String, String>? _serverPaths;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.store.exportMarkdownText();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result == null) {
        _error = I18n.t('ui.67bda6669e');
        return;
      }
      _markdown = result.markdown;
      _filename = result.filename;
      _title = result.title;
    });
  }

  /// 存到手机应用目录（不需要额外权限），并给出路径
  Future<void> _saveToPhone() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final exportDir = Directory('${dir.path}/pi-exports');
      if (!await exportDir.exists()) await exportDir.create(recursive: true);
      final file = File('${exportDir.path}/$_filename');
      await file.writeAsString(_markdown, flush: true);
      if (!mounted) return;
      NeuToast.show(context, message: I18n.tp('ui.8af708690a', {'path': file.path}), icon: IconId.check);
    } catch (error) {
      if (!mounted) return;
      NeuToast.show(context, message: I18n.tp('ui.d7c8e237a5', {'error': error}), icon: IconId.warn);
    }
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _markdown));
    if (!mounted) return;
    NeuToast.show(context, message: I18n.t('ui.1b857f46f0'), icon: IconId.check);
  }

  Future<void> _exportToServer() async {
    final result = await widget.store.exportFilesToServer();
    if (!mounted) return;
    if (result == null) return;
    setState(() => _serverPaths = result);
    NeuToast.show(context, message: I18n.t('ui.2a5478aa2c'), icon: IconId.check);
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    NeuToast.show(context, message: I18n.tp('ui.eb2ee57cb4', {'label': label}), icon: IconId.check);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(t),
            Expanded(
              child: _loading
                  ? Center(
                      child: Text(I18n.t('ui.5f31a99e96'), style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.muted)),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(NeuSpace.n24),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.muted, height: 1.7),
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n4, NeuSpace.n18, 28),
                          child: NeuMarkdown(data: _markdown, fontSize: NeuFonts.bodyMid),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(NeuTokens t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(NeuSpace.n14, NeuSpace.n10, NeuSpace.n14, NeuSpace.n8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              NeuPressable(
                onTap: () => Navigator.of(context).pop(),
                radius: 12,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n12),
                  child: NeuIcon(IconId.chevronLeft, size: 16),
                ),
              ),
              SizedBox(width: NeuSpace.n10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      I18n.t('ui.cb9bf0e70e'),
                      style: TextStyle(
                        fontSize: NeuFonts.sectionTitle,
                        fontWeight: FontWeight.w700,
                        color: t.onBg,
                      ),
                    ),
                    if (_title.isNotEmpty)
                      Text(
                        _filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: NeuFonts.label, color: t.muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: NeuSpace.n10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(t, IconId.cmd, I18n.t('ui.290b624aca'), _loading ? null : _copyAll),
              _chip(t, IconId.download, I18n.t('ui.03fcdf562e'), _loading ? null : _saveToPhone),
              _chip(t, IconId.server, I18n.t('ui.50242e8bb9'), _loading ? null : _exportToServer),
            ],
          ),
          if (_serverPaths != null) ...[
            const SizedBox(height: NeuSpace.n10),
            for (final entry in _serverPaths!.entries)
              if (entry.value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: NeuSpace.n4),
                  child: NeuPressable(
                    onTap: () => _copy(entry.value,
                        I18n.tp('ui.9aa63cf775', {'key': entry.key.toUpperCase()})),
                    radius: NeuRadii.sm,
                    padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n14, vertical: NeuSpace.n14),
                    child: Row(
                      children: [
                        Text('${entry.key.toUpperCase()} ',
                            style: TextStyle(fontSize: NeuFonts.micro, color: t.accentInk)),
                        Expanded(
                          child: Text(
                            entry.value,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: NeuFonts.micro, color: t.muted, height: 1.4),
                          ),
                        ),
                        NeuIcon(IconId.cmd, size: 13, color: t.muted),
                      ],
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _chip(NeuTokens t, IconId icon, String label, VoidCallback? onTap) {
    return NeuPressable(
      onTap: onTap,
      radius: NeuRadii.sm,
      padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n14, vertical: NeuSpace.n14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          NeuIcon(icon, size: 13, color: onTap == null ? t.muted : t.accentInk),
          const SizedBox(width: NeuSpace.n6),
          Text(label,
              style: TextStyle(fontSize: NeuFonts.sub, color: onTap == null ? t.muted : t.fg)),
        ],
      ),
    );
  }
}
