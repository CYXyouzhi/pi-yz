// Provider 登录界面：选 provider →（API Key 向导 / OAuth）→ 轮询进度并回答提示。
//
// 为什么做成「轮询任务」而不是一条长连接：
//   登录是「服务端问一句、用户答一句」的长交互（OAuth 还要等浏览器回调），
//   手机上随时会切后台、锁屏，长连接断掉就前功尽弃。任务式的状态在服务端，
//   手机回来接着问就行。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../server/server_store.dart';
import '../../server/i18n.dart';
import '../../server/server_types.dart';
import '../../theme/design_tokens.dart';
import '../../theme/neu.dart';
import '../neu_icons.dart';
import '../neu_toast.dart';

/// 选一个 provider + 登录方式
class ProviderLoginSheet extends StatefulWidget {
  const ProviderLoginSheet({super.key, required this.store, this.onLoggedIn});

  final ServerStore store;
  final VoidCallback? onLoggedIn;

  @override
  State<ProviderLoginSheet> createState() => _ProviderLoginSheetState();
}

class _ProviderLoginSheetState extends State<ProviderLoginSheet> {
  List<ProviderInfo> _providers = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await widget.store.providers();
    if (!mounted) return;
    setState(() {
      _providers = list;
      _loading = false;
    });
  }

  Future<void> _start(ProviderInfo provider, AuthOption option) async {
    final taskId = await widget.store.beginLogin(provider.id, option.type);
    if (!mounted) return;
    if (taskId == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LoginProgressPage(
          store: widget.store,
          taskId: taskId,
          providerName: provider.name,
        ),
      ),
    );
    if (!mounted) return;
    await _load();
    widget.onLoggedIn?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    // 未配置的排在前面：登录页的主要用途是「补一个还没配的」
    final providers = [..._providers]
      ..sort((a, b) {
        if (a.configured != b.configured) return a.configured ? 1 : -1;
        return a.name.compareTo(b.name);
      });

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(NeuRadii.lg),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        NeuSpace.n16,
        NeuSpace.n10,
        NeuSpace.n16,
        NeuSpace.n18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: t.muted.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(NeuRadii.hairline),
              ),
            ),
          ),
          SizedBox(height: NeuSpace.n14),
          Text(
            I18n.t('ui.4be9b33847'),
            style: TextStyle(
              fontSize: NeuFonts.sectionTitle,
              fontWeight: FontWeight.w700,
              color: t.onBg,
            ),
          ),
          SizedBox(height: NeuSpace.n4),
          Text(
            I18n.t('ui.bdd04225f4'),
            style: TextStyle(
              fontSize: NeuFonts.label,
              color: t.muted,
              height: 1.6,
            ),
          ),
          SizedBox(height: NeuSpace.n12),
          Flexible(
            child: _loading
                ? Center(
                    child: Text(
                      I18n.t('ui.054235bdc7'),
                      style: TextStyle(
                        fontSize: NeuFonts.bodySmall,
                        color: t.muted,
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: providers.length,
                    separatorBuilder: (_, _) =>
                        Container(height: 1, color: t.border),
                    itemBuilder: (context, index) {
                      final provider = providers[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: NeuSpace.n8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  provider.name,
                                  style: TextStyle(
                                    fontSize: NeuFonts.bodyMid,
                                    color: t.fg,
                                  ),
                                ),
                                const SizedBox(width: NeuSpace.n6),
                                Text(
                                  provider.id,
                                  style: TextStyle(
                                    fontSize: NeuFonts.micro,
                                    color: t.muted,
                                  ),
                                ),
                                if (provider.configured) ...[
                                  SizedBox(width: NeuSpace.n6),
                                  Text(
                                    I18n.t('ui.da208e9c74'),
                                    style: TextStyle(
                                      fontSize: NeuFonts.tiny,
                                      color: t.success,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: NeuSpace.n6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final option in provider.auth)
                                  NeuPressable(
                                    onTap: option.interactive
                                        ? () => _start(provider, option)
                                        : null,
                                    radius: NeuRadii.sm,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: NeuSpace.n11,
                                      vertical: NeuSpace.n7,
                                    ),
                                    child: Text(
                                      option.interactive
                                          ? option.label
                                          : I18n.tp('ui.72a5d6bddc', {
                                              'label': option.label,
                                            }),
                                      style: TextStyle(
                                        fontSize: NeuFonts.label,
                                        color: option.interactive
                                            ? t.accentInk
                                            : t.muted,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 登录进行中：轮询状态、展示授权链接/设备码、回答提示
class LoginProgressPage extends StatefulWidget {
  const LoginProgressPage({
    super.key,
    required this.store,
    required this.taskId,
    required this.providerName,
  });

  final ServerStore store;
  final String taskId;
  final String providerName;

  @override
  State<LoginProgressPage> createState() => _LoginProgressPageState();
}

class _LoginProgressPageState extends State<LoginProgressPage> {
  Timer? _timer;
  LoginStatus? _status;
  final List<Map<String, dynamic>> _log = [];
  final TextEditingController _answer = TextEditingController();

  /// 已提交过的那条提示（按内容记，因为同一轮里可能连着来好几条提示；
  /// 只比 type 会误判：select 提交后紧接着的 manual_code 也会显示「已提交」）
  String? _answeredPrompt;
  bool _submitting = false;

  /// 刚提交的那条提示（用来在等待下一步时给个「已提交」的反馈）
  String? _submittedPrompt;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(milliseconds: 900), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _answer.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    final status = await widget.store.pollLogin(widget.taskId);
    if (!mounted || status == null) return;
    setState(() {
      _status = status;
      _log.addAll(status.events);
    });
    if (status.isFinished) {
      _timer?.cancel();
      if (status.state == 'done') {
        NeuToast.show(
          context,
          message: I18n.tp('ui.a236b08a33', {'name': widget.providerName}),
          icon: IconId.check,
        );
      } else if (status.state == 'error') {
        NeuToast.show(
          context,
          message: I18n.tp('ui.ba23cee4eb', {'error': status.error}),
          icon: IconId.warn,
        );
      }
    }
  }

  Future<void> _submit(String value) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    _submittedPrompt = _status?.prompt?.message;
    await widget.store.answerLogin(widget.taskId, value);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _answeredPrompt = _submittedPrompt;
      _answer.clear();
    });
  }

  Future<void> _cancel() async {
    await widget.store.cancelLogin(widget.taskId);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    NeuToast.show(
      context,
      message: I18n.tp('ui.eb2ee57cb4', {'label': label}),
      icon: IconId.check,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final status = _status;
    final prompt = status?.prompt;

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NeuSpace.n14,
                NeuSpace.n10,
                NeuSpace.n14,
                NeuSpace.n6,
              ),
              child: Row(
                children: [
                  NeuPressable(
                    onTap: _cancel,
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          I18n.tp('ui.c0fdf79953', {
                            'name': widget.providerName,
                          }),
                          style: TextStyle(
                            fontSize: NeuFonts.heading,
                            fontWeight: FontWeight.w700,
                            color: t.onBg,
                          ),
                        ),
                        Text(
                          switch (status?.state) {
                            'done' => I18n.t('ui.fad5222ca0'),
                            'error' => I18n.t('common.failed'),
                            'cancelled' => I18n.t('ui.2111ccbb19'),
                            'prompt' => I18n.t('ui.9b5fb84bb2'),
                            _ => I18n.t('ui.435a51e1a2'),
                          },
                          style: TextStyle(
                            fontSize: NeuFonts.label,
                            color: t.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!(status?.isFinished ?? false))
                    NeuPressable(
                      onTap: _cancel,
                      radius: NeuRadii.sm,
                      padding: EdgeInsets.symmetric(
                        horizontal: NeuSpace.n12,
                        vertical: NeuSpace.n8,
                      ),
                      child: Text(
                        I18n.t('common.cancel'),
                        style: TextStyle(
                          fontSize: NeuFonts.sub,
                          color: t.danger,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  NeuSpace.n16,
                  NeuSpace.n6,
                  NeuSpace.n16,
                  NeuSpace.n20,
                ),
                children: [
                  // ① 服务端推来的信息：授权链接 / 设备码 / 进度
                  for (final event in _log) _eventCard(t, event),

                  // ② 当前提示
                  if (prompt != null) _promptCard(t, prompt),

                  if (status?.state == 'done')
                    _note(t, I18n.t('ui.eeab2a93eb')),
                  if (status?.state == 'error')
                    _note(
                      t,
                      I18n.tp('ui.c6729a8150', {
                        'e': status?.error ?? I18n.t('ui.31bbcc36d8'),
                      }),
                      danger: true,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _note(NeuTokens t, String text, {bool danger = false}) => Padding(
    padding: const EdgeInsets.only(top: NeuSpace.n12),
    child: Text(
      text,
      style: TextStyle(
        fontSize: NeuFonts.sub,
        color: danger ? t.danger : t.muted,
        height: 1.7,
      ),
    ),
  );

  Widget _eventCard(NeuTokens t, Map<String, dynamic> event) {
    final type = event['type'] as String? ?? 'info';
    if (type == 'info') {
      return Padding(
        padding: const EdgeInsets.only(bottom: NeuSpace.n10),
        child: _note(t, event['message'] as String? ?? ''),
      );
    }
    if (type == 'progress') {
      return Padding(
        padding: const EdgeInsets.only(bottom: NeuSpace.n10),
        child: _note(t, event['message'] as String? ?? ''),
      );
    }
    if (type == 'auth_url') {
      final url = event['url'] as String? ?? '';
      return _linkCard(
        t,
        I18n.t('ui.fc9ce61bab'),
        url,
        event['instructions'] as String?,
      );
    }
    if (type == 'device_code') {
      final code = event['userCode'] as String? ?? '';
      return _linkCard(
        t,
        I18n.t('ui.a1dfc88cea'),
        event['verificationUri'] as String? ?? '',
        I18n.tp('ui.0403f8b312', {'code': code}),
        extra: code,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _linkCard(
    NeuTokens t,
    String title,
    String url,
    String? hint, {
    String? extra,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: NeuSpace.n12),
      child: NeuRaised(
        radius: NeuRadii.md,
        level: NeuLevel.small,
        padding: const EdgeInsets.all(NeuSpace.n12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: NeuFonts.sub,
                fontWeight: FontWeight.w700,
                color: t.accentInk,
              ),
            ),
            const SizedBox(height: NeuSpace.n6),
            SelectableText(
              url,
              style: TextStyle(
                fontSize: NeuFonts.label,
                color: t.fg,
                height: 1.5,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: NeuSpace.n6),
              Text(
                hint,
                style: TextStyle(
                  fontSize: NeuFonts.label,
                  color: t.muted,
                  height: 1.6,
                ),
              ),
            ],
            SizedBox(height: NeuSpace.n10),
            Row(
              children: [
                NeuPressable(
                  onTap: () => _copy(url, I18n.t('ui.bfe68d5844')),
                  radius: NeuRadii.sm,
                  padding: EdgeInsets.symmetric(
                    horizontal: NeuSpace.n12,
                    vertical: NeuSpace.n8,
                  ),
                  child: Text(
                    I18n.t('ui.879058ce06'),
                    style: TextStyle(
                      fontSize: NeuFonts.small,
                      color: t.accentInk,
                    ),
                  ),
                ),
                if (extra != null) ...[
                  SizedBox(width: NeuSpace.n8),
                  NeuPressable(
                    onTap: () => _copy(extra, I18n.t('ui.42861ce8c8')),
                    radius: NeuRadii.sm,
                    padding: const EdgeInsets.symmetric(
                      horizontal: NeuSpace.n12,
                      vertical: NeuSpace.n8,
                    ),
                    child: Text(
                      I18n.t('ui.f7959bcdd0'),
                      style: TextStyle(
                        fontSize: NeuFonts.small,
                        color: t.accentInk,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _promptCard(NeuTokens t, AuthPromptInfo prompt) {
    final isSelect = prompt.type == 'select';
    return NeuRaised(
      radius: NeuRadii.md,
      level: NeuLevel.small,
      padding: const EdgeInsets.all(NeuSpace.n12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            prompt.message,
            style: TextStyle(
              fontSize: NeuFonts.bodySmall,
              color: t.fg,
              height: 1.6,
            ),
          ),
          const SizedBox(height: NeuSpace.n10),
          if (isSelect)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in prompt.options)
                  NeuPressable(
                    onTap: _submitting ? null : () => _submit(option.id),
                    radius: NeuRadii.sm,
                    padding: const EdgeInsets.symmetric(
                      horizontal: NeuSpace.n12,
                      vertical: NeuSpace.n9,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.label,
                          style: TextStyle(fontSize: NeuFonts.sub, color: t.fg),
                        ),
                        if (option.description != null)
                          Text(
                            option.description!,
                            style: TextStyle(
                              fontSize: NeuFonts.micro,
                              color: t.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            )
          else ...[
            TextField(
              controller: _answer,
              obscureText: prompt.type == 'secret',
              style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.fg),
              decoration: InputDecoration(
                hintText:
                    prompt.placeholder ??
                    (prompt.type == 'secret'
                        ? I18n.t('ui.21587f0de2')
                        : I18n.t('common.input')),
                hintStyle: TextStyle(fontSize: NeuFonts.small, color: t.muted),
                isDense: true,
              ),
            ),
            const SizedBox(height: NeuSpace.n10),
            Row(
              children: [
                NeuPressable(
                  onTap: _submitting
                      ? null
                      : () => _submit(_answer.text.trim()),
                  radius: NeuRadii.sm,
                  padding: EdgeInsets.symmetric(
                    horizontal: NeuSpace.n14,
                    vertical: NeuSpace.n9,
                  ),
                  child: Text(
                    I18n.t('ui.939d5345ad'),
                    style: TextStyle(
                      fontSize: NeuFonts.sub,
                      color: t.accentInk,
                    ),
                  ),
                ),
                if (_answeredPrompt != null &&
                    _answeredPrompt == prompt.message) ...[
                  SizedBox(width: NeuSpace.n10),
                  Text(
                    I18n.t('ui.e2410daedf'),
                    style: TextStyle(fontSize: NeuFonts.label, color: t.muted),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
