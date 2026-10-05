// 「目标」配置子页面 —— 新增 / 编辑一条服务端连接。
//
// 为什么要独立成页，而不是留在连接页里内联展开：
//
//  1. **讲得清楚 token**。内联那块只有一行 input，用户完全不知道 token
//     从哪来（实测反馈就是「不知道怎么添加 token」）。独立页面有空间把
//     三个来源、以及「配对码怎么用」摆出来。
//  2. **主页面不再变长**。内联表单展开后连接页长了一大截，页面上同时存在
//     的阴影图层翻倍，滚动就掉帧（实测「手指滑、画面跟不上」）。抽出去以后
//     连接页的长度恒定。
//
// 字段与视觉沿用连接页那一套（同款 _field / _switchRow / NeuInset），
// 不引入第二套表单样式。
import 'package:flutter/material.dart';

import '../../server/i18n.dart';
import '../../server/server_client.dart';
import '../../server/server_profile.dart';
import '../../theme/design_tokens.dart';
import '../../theme/neu.dart';
import '../neu_icons.dart';
import '../neu_toast.dart';

class ConnEditPage extends StatefulWidget {
  const ConnEditPage({
    super.key,
    this.initial,
    this.draft,
    required this.defaultToken,
  });

  /// 传入 = 编辑这条（标题显示「编辑连接」，保存时沿用它的 id）。
  final ServerProfile? initial;

  /// 传入 = 新增，但把已知字段（比如扫描到的地址）先填上。
  /// 与 [initial] 的区别只在语义：它不影响标题，也不会让保存变成「覆盖」。
  final ServerProfile? draft;

  /// 新增时预填的 token（通常是当前已连那条的，用户已经配对过，不用再问）。
  final String defaultToken;

  @override
  State<ConnEditPage> createState() => _ConnEditPageState();
}

class _ConnEditPageState extends State<ConnEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _token;
  late final TextEditingController _cwd;
  late final TextEditingController _fallback;
  bool _secure = false;

  /// 「token 从哪来」的展开状态。默认收起，但标题就写着「不知道填什么？」，
  /// 正好是用户在困惑时找得到的那一行。
  bool _showTokenHelp = false;

  bool _testing = false;
  String? _testMessage;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    final p = widget.initial ?? widget.draft;
    _name = TextEditingController(text: p?.name ?? '');
    _host = TextEditingController(text: p?.host ?? '');
    _port = TextEditingController(text: (p?.port ?? 30142).toString());
    _token = TextEditingController(text: p?.token ?? widget.defaultToken);
    _cwd = TextEditingController(text: p?.defaultCwd ?? '');
    _fallback = TextEditingController(text: p?.fallbackHost ?? '');
    _secure = p?.secure ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _token.dispose();
    _cwd.dispose();
    _fallback.dispose();
    super.dispose();
  }

  /// 收集表单 → profile。校验不过返回 null（并弹提示）。
  ServerProfile? _collect() {
    final host = _host.text.trim();
    if (host.isEmpty) {
      NeuToast.show(context, message: I18n.t('connEdit.hostRequired'), icon: IconId.warn);
      return null;
    }
    final port = int.tryParse(_port.text.trim()) ?? 0;
    if (port <= 0 || port > 65535) {
      NeuToast.show(context, message: I18n.t('connEdit.portInvalid'), icon: IconId.warn);
      return null;
    }
    final token = _token.text.trim();
    if (token.isEmpty) {
      NeuToast.show(context, message: I18n.t('connEdit.tokenRequired'), icon: IconId.warn);
      return null;
    }
    return ServerProfile(
      id: widget.initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim().isEmpty ? host : _name.text.trim(),
      host: host,
      port: port,
      token: token,
      defaultCwd: _cwd.text.trim().isEmpty ? null : _cwd.text.trim(),
      secure: _secure,
      fallbackHost: _fallback.text.trim().isEmpty ? null : _fallback.text.trim(),
      fallbackPort: null,
      fallbackSecure: false,
    );
  }

  /// 试连一下，不保存。用的是和服务端同一套 client，所以结果和真连一致。
  Future<void> _test() async {
    final profile = _collect();
    if (profile == null) return;
    setState(() {
      _testing = true;
      _testMessage = null;
    });
    final client = ServerClient(
      host: profile.host,
      port: profile.port,
      token: profile.token,
      secure: profile.secure,
    );
    try {
      final health = await client.health();
      if (!mounted) return;
      setState(() {
        _testOk = health.ok;
        _testMessage = I18n.tp('connEdit.testOk', {'pi': health.piVersion});
      });
    } on ServerException catch (error) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMessage = error.message;
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _save() {
    final profile = _collect();
    if (profile == null) return;
    Navigator.of(context).pop(profile);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n8, NeuSpace.n18, 28),
          children: [
            _header(t),
            const SizedBox(height: NeuSpace.n14),
            NeuRaised(
              radius: NeuRadii.lg,
              padding: const EdgeInsets.all(NeuSpace.n16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _groupTitle(t, I18n.t('conn.groupBasic')),
                  _field(t, label: I18n.t('ui.4fcad1c9ba'), controller: _name,
                      hint: I18n.t('ui.ae50303667')),
                  _field(t, label: I18n.t('ui.aeb5271ede'), controller: _host,
                      hint: I18n.t('ui.358bf4b90b'), keyboard: TextInputType.url),
                  _field(t, label: I18n.t('ui.c76cfefe72'), controller: _port,
                      hint: '30142', keyboard: TextInputType.number),
                  _tokenField(t),
                  _field(t, label: I18n.t('ui.e963f6371c'), controller: _cwd,
                      hint: I18n.t('ui.487a7ad4fa')),
                  _switchRow(
                    t,
                    label: I18n.t('conn.useHttps'),
                    hint: I18n.t('conn.useHttpsHint'),
                    value: _secure,
                    onChanged: (v) => setState(() => _secure = v),
                  ),
                  _groupTitle(t, I18n.t('conn.groupRemote')),
                  _note(t, I18n.t('conn.remoteIntro')),
                  _field(
                    t,
                    label: I18n.t('conn.fallbackHost'),
                    controller: _fallback,
                    hint: I18n.t('conn.fallbackHint'),
                    keyboard: TextInputType.url,
                  ),
                  _securityNote(t),
                ],
              ),
            ),
            if (_testMessage != null) ...[
              const SizedBox(height: NeuSpace.n12),
              _testBanner(t),
            ],
            const SizedBox(height: NeuSpace.n16),
            Row(
              children: [
                Expanded(
                  child: NeuPressable(
                    onTap: _testing ? null : _test,
                    radius: NeuRadii.md,
                    padding: EdgeInsets.symmetric(vertical: NeuSpace.n12),
                    child: Center(
                      child: Text(
                        _testing ? I18n.t('connEdit.testing') : I18n.t('connEdit.test'),
                        style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.accentInk),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: NeuSpace.n10),
                Expanded(
                  child: NeuPressable(
                    onTap: _save,
                    radius: NeuRadii.md,
                    padding: EdgeInsets.symmetric(vertical: NeuSpace.n12),
                    child: Center(
                      child: Text(
                        I18n.t('connEdit.save'),
                        style: TextStyle(
                          fontSize: NeuFonts.bodySmall,
                          color: t.accentInk,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(NeuTokens t) {
    return Row(
      children: [
        NeuPressable(
          onTap: () => Navigator.of(context).maybePop(),
          radius: 12,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n12),
            child: NeuIcon(IconId.chevronLeft, size: 16),
          ),
        ),
        const SizedBox(width: NeuSpace.n10),
        Text(
          widget.initial == null ? I18n.t('connEdit.newTitle') : I18n.t('connEdit.editTitle'),
          style: TextStyle(
            fontSize: NeuFonts.sectionTitle,
            fontWeight: FontWeight.w700,
            color: t.fg,
          ),
        ),
      ],
    );
  }

  /// token 字段 + 「不知道填什么？」的引导。
  ///
  /// 这一段是这次改造的主要目的：用户第一次配对时的原话是
  /// 「不知道怎么添加 token」—— 之前它就是一个没有说明的输入框。
  Widget _tokenField(NeuTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(
          t,
          label: 'token',
          controller: _token,
          hint: I18n.t('ui.7ab030fd16'),
          obscure: false,
        ),
        GestureDetector(
          onTap: () => setState(() => _showTokenHelp = !_showTokenHelp),
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              NeuIcon(IconId.info, size: 13, color: t.muted),
              const SizedBox(width: NeuSpace.n6),
              Text(
                I18n.t('connEdit.tokenHelpTitle'),
                style: TextStyle(fontSize: NeuFonts.label, color: t.accentInk),
              ),
              const SizedBox(width: NeuSpace.n4),
              NeuIcon(
                _showTokenHelp ? IconId.chevronDown : IconId.chevronRight,
                size: 12,
                color: t.muted,
              ),
            ],
          ),
        ),
        if (_showTokenHelp) ...[
          const SizedBox(height: NeuSpace.n8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(NeuSpace.n12),
            decoration: BoxDecoration(
              color: t.muted.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(NeuRadii.sm),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in [
                  I18n.t('connEdit.tokenHelp1'),
                  I18n.t('connEdit.tokenHelp2'),
                  I18n.t('connEdit.tokenHelp3'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: NeuSpace.n5),
                    child: Text(
                      '· $line',
                      style: TextStyle(fontSize: NeuFonts.badge, height: 1.6, color: t.muted),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _testBanner(NeuTokens t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(NeuSpace.n12),
      decoration: BoxDecoration(
        color: (_testOk ? t.success : t.danger).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(NeuRadii.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NeuIcon(_testOk ? IconId.check : IconId.warn, size: 14,
              color: _testOk ? t.success : t.danger),
          const SizedBox(width: NeuSpace.n8),
          Expanded(
            child: Text(
              _testMessage ?? '',
              style: TextStyle(fontSize: NeuFonts.label, height: 1.5, color: t.fg),
            ),
          ),
        ],
      ),
    );
  }

  Widget _securityNote(NeuTokens t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(NeuSpace.n12),
      decoration: BoxDecoration(
        color: t.muted.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(NeuRadii.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            I18n.t('conn.securityTitle'),
            style: TextStyle(
              fontSize: NeuFonts.bodySmall,
              fontWeight: FontWeight.w600,
              color: t.muted,
            ),
          ),
          SizedBox(height: NeuSpace.n6),
          Text(
            I18n.t('conn.securityBody'),
            style: TextStyle(fontSize: NeuFonts.badge, height: 1.6, color: t.muted),
          ),
        ],
      ),
    );
  }

  // ---------- 下面这几个和连接页里那套保持一致，不另立样式 ----------

  Widget _groupTitle(NeuTokens t, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: NeuSpace.n6, bottom: NeuSpace.n10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 13,
            decoration: BoxDecoration(
              color: t.accentInk.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: NeuSpace.n7),
          Text(
            text,
            style: TextStyle(
              fontSize: NeuFonts.bodySmall,
              fontWeight: FontWeight.w700,
              color: t.fg,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _note(NeuTokens t, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: NeuSpace.n10),
      child: Text(
        text,
        style: TextStyle(fontSize: NeuFonts.badge, height: 1.6, color: t.muted),
      ),
    );
  }

  Widget _switchRow(
    NeuTokens t, {
    required String label,
    required String hint,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: NeuSpace.n12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: NeuFonts.bodyTight, color: t.fg)),
                SizedBox(height: NeuSpace.n2),
                Text(hint, style: TextStyle(fontSize: NeuFonts.badge, height: 1.5, color: t.muted)),
              ],
            ),
          ),
          SizedBox(width: NeuSpace.n10),
          NeuPressable(
            onTap: () => onChanged(!value),
            radius: NeuRadii.sm,
            flat: !value,
            alwaysInset: value,
            padding: EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n7),
            child: Text(
              value ? I18n.t('ui.8493205602') : I18n.t('ui.d58a55bcee'),
              style: TextStyle(
                fontSize: NeuFonts.sub,
                color: value ? t.accentInk : t.muted,
                fontWeight: value ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    NeuTokens t, {
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboard,
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: NeuSpace.n12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: NeuFonts.small, color: t.muted)),
          const SizedBox(height: NeuSpace.n6),
          NeuInset(
            radius: NeuRadii.sm,
            padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12),
            child: TextField(
              controller: controller,
              keyboardType: keyboard,
              obscureText: obscure,
              style: TextStyle(fontSize: NeuFonts.bodyTight, color: t.fg),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: TextStyle(fontSize: NeuFonts.bodySmall, color: t.muted),
                contentPadding: const EdgeInsets.symmetric(vertical: NeuSpace.n12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
