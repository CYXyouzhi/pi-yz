// 日志页：把 DebugLog 里的东西读出来。
//
// 为什么需要一个页面（而不是只在控制台打日志）：
// 手机上出问题时，用户能自己去「设置 → 日志」看一眼，
// 把关键几行复制发出来，比「能不能连个调试器」现实得多。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/debug_log.dart';
import '../../theme/design_tokens.dart';
import '../../theme/neu.dart';
import '../neu_icons.dart';
import '../neu_toast.dart';
import '../../server/i18n.dart';

class LogPage extends StatefulWidget {
  const LogPage({super.key});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  final _scroll = ScrollController();
  List<LogEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _entries = DebugLog.instance.entries;
    DebugLog.instance.stream.listen((list) {
      if (!mounted) return;
      setState(() => _entries = List.unmodifiable(list));
      // 跟着最新一条走（看日志时最关心的就是刚才发生了什么）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Color _levelColor(NeuTokens t, LogLevel level) => switch (level) {
        LogLevel.error => t.danger,
        LogLevel.warn => t.warn,
        LogLevel.info => t.accentInk,
        LogLevel.debug => t.muted,
      };

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n8, NeuSpace.n12, NeuSpace.n8),
              child: Row(
                children: [
                  NeuPressable(
                    onTap: () => Navigator.of(context).maybePop(),
                    radius: 12,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n12),
                      child: NeuIcon(IconId.chevronLeft, size: 16),
                    ),
                  ),
                  SizedBox(width: NeuSpace.n8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(I18n.t('ui.456d29ef8b'),
                            style: TextStyle(
                              fontSize: NeuFonts.pageTitle,
                              fontWeight: FontWeight.w700,
                              color: t.onBg,
                            )),
                        Text(I18n.tp('ui.29889d892e', {'n': _entries.length}),
                            style: TextStyle(fontSize: NeuFonts.label, color: t.muted)),
                      ],
                    ),
                  ),
                  NeuPressable(
                    onTap: () async {
                      final text = _entries
                          .map((e) =>
                              '${e.time.toIso8601String()} [${e.level.name}] ${e.tag}: ${e.message}')
                          .join('\n');
                      await Clipboard.setData(ClipboardData(text: text));
                      if (context.mounted) {
                        NeuToast.show(context,
                            message: I18n.tp('ui.a2e6d79651', {'n': _entries.length}),
                            icon: IconId.check);
                      }
                    },
                    radius: 12,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n12),
                      child: NeuIcon(IconId.pen, size: 16),
                    ),
                  ),
                  NeuPressable(
                    onTap: () {
                      DebugLog.instance.clear();
                      setState(() => _entries = const []);
                    },
                    radius: 12,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n12),
                      child: NeuIcon(IconId.trash, size: 16),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _entries.isEmpty
                  ? Center(
                      child: Text(I18n.t('ui.761a77f1f9'),
                          style: TextStyle(fontSize: NeuFonts.sub, color: t.muted)),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(NeuSpace.n14, NeuSpace.n4, NeuSpace.n14, 30),
                      itemCount: _entries.length,
                      itemBuilder: (context, index) {
                        final entry = _entries[index];
                        final time = entry.time
                            .toIso8601String()
                            .substring(11, 19);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: NeuSpace.n6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(time,
                                  style: TextStyle(
                                      fontSize: NeuFonts.badge,
                                      fontFamily: 'monospace',
                                      color: t.muted)),
                              const SizedBox(width: NeuSpace.n8),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: '${entry.tag} ',
                                        style: TextStyle(
                                          fontSize: NeuFonts.label,
                                          fontFamily: 'monospace',
                                          color: _levelColor(t, entry.level),
                                        ),
                                      ),
                                      TextSpan(
                                        text: entry.message,
                                        style: TextStyle(
                                          fontSize: NeuFonts.label,
                                          fontFamily: 'monospace',
                                          color: t.fg,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
