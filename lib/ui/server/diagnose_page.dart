// 连接诊断页：把「连不上」摊开成一条条能动手的原因。
//
// 与连接页的分工：连接页负责「配」和「连」，这一页只负责「出了什么事」。
// 之所以独立成页：诊断结果长，塞在连接页里会把配置表单挤出屏幕。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../server/diagnose.dart';
import '../../server/i18n.dart';
import '../../server/native_bridge.dart';
import '../../theme/design_tokens.dart';
import '../../theme/neu.dart';
import '../neu_icons.dart';
import '../neu_toast.dart';

class DiagnosePage extends StatefulWidget {
  const DiagnosePage({
    super.key,
    required this.host,
    required this.port,
    required this.token,
    this.defaultCwd,
  });

  final String host;
  final int port;
  final String token;
  final String? defaultCwd;

  @override
  State<DiagnosePage> createState() => _DiagnosePageState();
}

class _DiagnosePageState extends State<DiagnosePage> {
  DiagReport? _report;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _running = true);
    final report = await runDiagnosis(
      host: widget.host,
      port: widget.port,
      token: widget.token,
      defaultCwd: widget.defaultCwd,
    );
    if (!mounted) return;
    setState(() {
      _report = report;
      _running = false;
    });
  }

  Future<void> _copy() async {
    final report = _report;
    if (report == null) return;
    await Clipboard.setData(ClipboardData(text: report.toText()));
    if (!mounted) return;
    NeuToast.show(
      context,
      message: I18n.t('ui.c92c4d1779'),
      icon: IconId.check,
    );
  }

  Future<void> _share() async {
    final report = _report;
    if (report == null) return;
    final ok = await NativeBridge.shareText(
      text: report.toText(),
      subject: I18n.t('ui.65b148d3ae'),
    );
    if (!mounted) return;
    if (!ok) {
      // 分享面板拉不起来时退回剪贴板，不把用户卡在这里
      await Clipboard.setData(ClipboardData(text: report.toText()));
      if (!mounted) return;
      NeuToast.show(
        context,
        message: I18n.t('ui.0f584a2971'),
        icon: IconId.info,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final report = _report;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            NeuSpace.n18,
            NeuSpace.n8,
            NeuSpace.n18,
            28,
          ),
          children: [
            Row(
              children: [
                NeuPressable(
                  onTap: () => Navigator.of(context).maybePop(),
                  radius: 12,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: NeuSpace.n12,
                      vertical: NeuSpace.n12,
                    ),
                    child: NeuIcon(IconId.chevronLeft, size: 16),
                  ),
                ),
                SizedBox(width: NeuSpace.n10),
                Text(
                  I18n.t('ui.de15ce00dd'),
                  style: TextStyle(
                    fontSize: NeuFonts.pageTitle,
                    fontWeight: FontWeight.w700,
                    color: t.onBg,
                  ),
                ),
                const Spacer(),
                if (_running) NeuIcon(IconId.spinner, size: 16, color: t.muted),
              ],
            ),
            SizedBox(height: NeuSpace.n6),
            Text(
              I18n.t('ui.ec238afeae'),
              style: TextStyle(fontSize: NeuFonts.sub, color: t.onBgDim),
            ),
            const SizedBox(height: NeuSpace.n16),

            // 当前连接参数：诊断结果离开现场就没意义，先把参数钉在上面
            NeuRaised(
              radius: NeuRadii.lg,
              padding: const EdgeInsets.all(NeuSpace.n14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      NeuIcon(IconId.server, size: 15, color: t.accentInk),
                      SizedBox(width: NeuSpace.n8),
                      Text(
                        I18n.t('ui.a1395a5eec'),
                        style: TextStyle(
                          fontSize: NeuFonts.bodyMid,
                          fontWeight: FontWeight.w700,
                          color: t.fg,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: NeuSpace.n10),
                  _kv(
                    t,
                    I18n.t('ui.7650487a87'),
                    '${widget.host}:${widget.port}',
                  ),
                  _kv(t, 'token', maskToken(widget.token)),
                  _kv(
                    t,
                    I18n.t('ui.96dba48253'),
                    widget.defaultCwd?.isNotEmpty == true
                        ? widget.defaultCwd!
                        : I18n.t('ui.cb8fd1da6d'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: NeuSpace.n14),

            if (report != null) ...[
              NeuRaised(
                radius: NeuRadii.lg,
                padding: const EdgeInsets.all(NeuSpace.n14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        NeuIcon(
                          report.allOk ? IconId.check : IconId.warn,
                          size: 16,
                          color: report.allOk ? t.success : t.danger,
                        ),
                        const SizedBox(width: NeuSpace.n8),
                        Expanded(
                          child: Text(
                            report.headline,
                            style: TextStyle(
                              fontSize: NeuFonts.bodyMid,
                              fontWeight: FontWeight.w700,
                              color: report.allOk ? t.success : t.danger,
                            ),
                          ),
                        ),
                        Text(
                          '${report.elapsed.inMilliseconds} ms',
                          style: TextStyle(
                            fontSize: NeuFonts.label,
                            color: t.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: NeuSpace.n12),
                    for (final step in report.steps) _step(t, step),
                  ],
                ),
              ),
              const SizedBox(height: NeuSpace.n14),
            ],

            Row(
              children: [
                Expanded(
                  child: NeuPressable(
                    onTap: _running ? null : _run,
                    radius: NeuRadii.md,
                    padding: const EdgeInsets.symmetric(
                      horizontal: NeuSpace.n13,
                      vertical: NeuSpace.n13,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        NeuIcon(IconId.sync, size: 15, color: t.muted),
                        SizedBox(width: NeuSpace.n7),
                        Text(
                          _running
                              ? I18n.t('ui.6d2374cab5')
                              : I18n.t('ui.eb7b58bbb4'),
                          style: TextStyle(
                            fontSize: NeuFonts.bodyTight,
                            color: t.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: NeuSpace.n10),
                Expanded(
                  child: NeuPressable(
                    onTap: report == null ? null : _copy,
                    radius: NeuRadii.md,
                    padding: const EdgeInsets.symmetric(
                      horizontal: NeuSpace.n13,
                      vertical: NeuSpace.n13,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        NeuIcon(IconId.copy, size: 15, color: t.accentInk),
                        SizedBox(width: NeuSpace.n7),
                        Text(
                          I18n.t('ui.cde0ad3061'),
                          style: TextStyle(
                            fontSize: NeuFonts.bodyTight,
                            color: t.accentInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: NeuSpace.n10),
            NeuPressable(
              onTap: report == null ? null : _share,
              radius: NeuRadii.md,
              padding: const EdgeInsets.symmetric(
                horizontal: NeuSpace.n13,
                vertical: NeuSpace.n13,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  NeuIcon(IconId.share, size: 15, color: t.muted),
                  SizedBox(width: NeuSpace.n7),
                  Text(
                    I18n.t('ui.bfa525d4c6'),
                    style: TextStyle(
                      fontSize: NeuFonts.bodyTight,
                      color: t.muted,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: NeuSpace.n14),
            Text(
              I18n.t('ui.cca1ded1d1'),
              style: TextStyle(fontSize: NeuFonts.label, color: t.onBgDim),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(NeuTokens t, String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: NeuSpace.n6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              key,
              style: TextStyle(fontSize: NeuFonts.small, color: t.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: NeuFonts.sub,
                color: t.fg,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(NeuTokens t, DiagStep step) {
    return Padding(
      padding: const EdgeInsets.only(bottom: NeuSpace.n10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: NeuSpace.n2),
            child: NeuIcon(
              step.ok ? IconId.check : IconId.warn,
              size: 14,
              color: step.ok ? t.success : t.danger,
            ),
          ),
          const SizedBox(width: NeuSpace.n8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${step.title}：${step.detail}',
                  style: TextStyle(
                    fontSize: NeuFonts.sub,
                    color: t.fg,
                    height: 1.5,
                  ),
                ),
                if (step.hint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: NeuSpace.n3),
                    child: Text(
                      '→ ${step.hint}',
                      style: TextStyle(
                        fontSize: NeuFonts.label,
                        color: t.accentInk,
                        height: 1.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
