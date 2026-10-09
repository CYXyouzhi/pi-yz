// 用量明细页：本会话逐轮 + 今天/本月看板 + 上下文占用 + 额度预警。
//
// 数字全部来自服务端对**落盘 JSONL** 的统计（见 server/lib/usage.mjs），
// 页面上每一处口径都写出来，免得「这数字哪来的」说不清。

import 'package:flutter/material.dart';

import '../collapsible_text.dart';

import '../../server/server_store.dart';
import '../../server/i18n.dart';
import '../../server/server_types.dart';
import '../../theme/design_tokens.dart';
import '../../theme/neu.dart';
import '../neu_icons.dart';

class UsagePage extends StatefulWidget {
  const UsagePage({
    super.key,
    required this.store,
    this.contextPercent,
    this.contextTokens,
    this.contextWindow,
    this.autoCompactEnabled = true,
  });

  final ServerStore store;
  final double? contextPercent;
  final int? contextTokens;
  final int? contextWindow;
  final bool autoCompactEnabled;

  @override
  State<UsagePage> createState() => _UsagePageState();
}

class _UsagePageState extends State<UsagePage> {
  @override
  void initState() {
    super.initState();
    widget.store.loadSessionUsage();
    widget.store.loadUsageSummary();
  }

  String _tokens(int? value) {
    if (value == null) return '—';
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(2)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
    return '$value';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.store,
          builder: (context, _) {
            final usage = widget.store.sessionUsage;
            final summary = widget.store.usageSummary;
            final totals = usage?.totals;

            return ListView(
              padding: const EdgeInsets.fromLTRB(
                NeuSpace.n18,
                NeuSpace.n8,
                NeuSpace.n18,
                40,
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
                    SizedBox(width: NeuSpace.n8),
                    Expanded(
                      child: Text(
                        I18n.t('ui.53750dd580'),
                        style: TextStyle(
                          fontSize: NeuFonts.pageTitle,
                          fontWeight: FontWeight.w700,
                          color: t.onBg,
                        ),
                      ),
                    ),
                    NeuPressable(
                      onTap: () {
                        widget.store.loadSessionUsage();
                        widget.store.loadUsageSummary();
                      },
                      radius: 12,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: NeuSpace.n12,
                          vertical: NeuSpace.n12,
                        ),
                        child: NeuIcon(IconId.sync, size: 16),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: NeuSpace.n6),
                Text(
                  widget.store.loadingUsage
                      ? I18n.t('common.loading')
                      : I18n.t('ui.1aeddef693'),
                  style: TextStyle(fontSize: NeuFonts.label, color: t.muted),
                ),

                // ---------- 上下文占用 ----------
                if (widget.contextPercent != null) ...[
                  _section(t, I18n.t('ui.8539b2ecd4')),
                  NeuRaised(
                    radius: NeuRadii.md,
                    padding: const EdgeInsets.all(NeuSpace.n14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${widget.contextPercent!.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: _contextColor(t, widget.contextPercent!),
                              ),
                            ),
                            SizedBox(width: NeuSpace.n8),
                            Expanded(
                              child: Text(
                                // ignore: prefer_interpolation_to_compose_strings
                                '${_tokens(widget.contextTokens)} / ${_tokens(widget.contextWindow)}'
                                '${I18n.t('ui.2abac8cdd2')}',
                                style: TextStyle(
                                  fontSize: NeuFonts.label,
                                  color: t.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: NeuSpace.n10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (widget.contextPercent! / 100).clamp(
                              0.0,
                              1.0,
                            ),
                            minHeight: 6,
                            backgroundColor: t.border,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _contextColor(t, widget.contextPercent!),
                            ),
                          ),
                        ),
                        SizedBox(height: NeuSpace.n8),
                        Text(
                          widget.autoCompactEnabled
                              ? I18n.t('ui.beec95ef4a')
                              : I18n.t('ui.f7cf767827'),
                          style: TextStyle(
                            fontSize: NeuFonts.badge,
                            color: t.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // ---------- 本会话 ----------
                _section(t, I18n.t('ui.4f1a748dda')),
                NeuRaised(
                  radius: NeuRadii.md,
                  padding: EdgeInsets.all(NeuSpace.n14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row(
                        t,
                        I18n.t('ui.12bec730c7'),
                        totals == null ? '—' : '${totals.turns}',
                      ),
                      _row(
                        t,
                        I18n.t('ui.84dc1d5db5'),
                        totals == null
                            ? '—'
                            : _tokens(
                                totals.input +
                                    totals.output +
                                    totals.cacheRead +
                                    totals.cacheWrite,
                              ),
                        sub: I18n.t('ui.578b86ba8e'),
                      ),
                      _row(t, I18n.t('common.input'), _tokens(totals?.input)),
                      _row(t, I18n.t('ui.8ba7c3a7be'), _tokens(totals?.output)),
                      _row(
                        t,
                        I18n.t('ui.0ae4a745b0'),
                        _tokens(totals?.cacheRead),
                      ),
                      _row(
                        t,
                        I18n.t('ui.8e784e8cd7'),
                        _tokens(totals?.cacheWrite),
                      ),
                      _row(
                        t,
                        I18n.t('ui.21d68b2de0'),
                        _tokens(totals?.reasoning),
                      ),
                      _row(
                        t,
                        I18n.t('ui.7e237e9459'),
                        totals == null
                            ? '—'
                            : '\$${totals.cost.toStringAsFixed(4)}',
                        sub: I18n.t('ui.0f7aa5c1a7'),
                      ),
                      _row(
                        t,
                        I18n.t('ui.759391f11c'),
                        totals?.cacheHitRate == null
                            ? '—'
                            : '${totals!.cacheHitRate}%',
                        sub: I18n.t('ui.17c8715557'),
                      ),
                      _row(
                        t,
                        I18n.t('ui.2afd083385'),
                        totals?.tokensPerSec == null
                            ? '—'
                            : '${totals!.tokensPerSec} tokens/s',
                        sub: I18n.t('ui.3bc67904e3'),
                      ),
                    ],
                  ),
                ),

                // ---------- 今天 / 本月 ----------
                _section(t, I18n.t('ui.020b61cdae')),
                NeuRaised(
                  radius: NeuRadii.md,
                  padding: EdgeInsets.all(NeuSpace.n14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row(
                        t,
                        I18n.t('ui.800dfdd902'),
                        summary == null
                            ? '—'
                            : '${_tokens(summary.todayTokens)} · \$${summary.todayCost.toStringAsFixed(3)}',
                      ),
                      _row(
                        t,
                        I18n.t('ui.0ec94a3708'),
                        summary == null
                            ? '—'
                            : '${_tokens(summary.monthTokens)} · \$${summary.monthCost.toStringAsFixed(3)}',
                      ),
                      if (summary != null)
                        _row(
                          t,
                          I18n.t('ui.eb0d6764ea'),
                          I18n.tp('ui.6bc638f6a6', {
                            'n': summary.scannedSessions,
                          }),
                        ),
                      const SizedBox(height: NeuSpace.n6),
                      for (final item in [...?summary?.byProvider])
                        _row(
                          t,
                          item.provider,
                          '${_tokens(item.tokens)} · \$${item.cost.toStringAsFixed(3)}',
                          sub: I18n.tp('ui.aa1d2675e2', {'n': item.turns}),
                        ),
                    ],
                  ),
                ),

                // ---------- 按天趋势（task-16 合同①） ----------
                _section(t, I18n.t('ui.d75cd7604d')),
                if (summary == null || summary.byDay.isEmpty)
                  NeuRaised(
                    radius: NeuRadii.md,
                    padding: const EdgeInsets.all(NeuSpace.n14),
                    child: Text(
                      I18n.t('ui.de8eecad10'),
                      style: TextStyle(fontSize: NeuFonts.sub, color: t.muted),
                    ),
                  )
                else
                  NeuRaised(
                    radius: NeuRadii.md,
                    padding: const EdgeInsets.all(NeuSpace.n14),
                    child: Builder(
                      builder: (context) {
                        final days = summary.byDay.take(10).toList();
                        var maxTok = 1;
                        for (final d in days) {
                          if (d.tokens > maxTok) maxTok = d.tokens;
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final d in days)
                              _dayRow(t, d.day, d.tokens, d.cost, maxTok),
                            SizedBox(height: NeuSpace.n10),
                            CollapsibleText(
                              // ignore: prefer_interpolation_to_compose_strings
                              text:
                                  '${I18n.t('ui.fcbd3cc5d4')}'
                                  '${I18n.t('ui.5a6fa04a24')}',
                              style: TextStyle(
                                fontSize: NeuFonts.badge,
                                height: 1.5,
                                color: t.muted,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                // ---------- 按工作区（task-16 合同①） ----------
                _section(t, I18n.t('ui.3c56ed3536')),
                if (summary == null || summary.byWorkspace.isEmpty)
                  NeuRaised(
                    radius: NeuRadii.md,
                    padding: const EdgeInsets.all(NeuSpace.n14),
                    child: Text(
                      I18n.t('ui.7af44bc1f0'),
                      style: TextStyle(fontSize: NeuFonts.sub, color: t.muted),
                    ),
                  )
                else
                  NeuRaised(
                    radius: NeuRadii.md,
                    padding: const EdgeInsets.all(NeuSpace.n14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final w in summary.byWorkspace.take(12))
                          _row(
                            t,
                            _workspaceName(w.cwd),
                            '${_tokens(w.tokens)} · \$${w.cost.toStringAsFixed(4)}',
                            sub: I18n.tp('ui.e505495394', {
                              'n': w.sessions,
                              't': w.turns,
                              'cwd': w.cwd,
                            }),
                          ),
                      ],
                    ),
                  ),

                // ---------- 额度预警 ----------
                _section(t, I18n.t('ui.b6d1510faf')),
                NeuRaised(
                  radius: NeuRadii.md,
                  padding: const EdgeInsets.all(NeuSpace.n14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          NeuIcon(
                            _quotaLevel(summary) == 0
                                ? IconId.check
                                : IconId.warn,
                            size: 15,
                            color: _quotaLevel(summary) == 0
                                ? t.success
                                : (_quotaLevel(summary) == 1
                                      ? t.warn
                                      : t.danger),
                          ),
                          const SizedBox(width: NeuSpace.n8),
                          Expanded(
                            child: Text(
                              _quotaText(summary),
                              style: TextStyle(
                                fontSize: NeuFonts.sub,
                                color: t.fg,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: NeuSpace.n6),
                      // 5 段拼接的口径说明：默认收一行、点开看全文
                      CollapsibleText(
                        text:
                            '${I18n.t('ui.dbfff2a1f7')}'
                            '${I18n.t('ui.2cdecccb2e')}'
                            '${I18n.t('ui.0fdf6249a8')}'
                            '${I18n.t('ui.791693d17c')}'
                            '${I18n.t('ui.48fae69896')}',
                        style: TextStyle(
                          fontSize: NeuFonts.badge,
                          height: 1.5,
                          color: t.muted,
                        ),
                      ),
                    ],
                  ),
                ),

                // ---------- 逐轮明细 ----------
                _section(t, I18n.t('ui.6eedee5f84')),
                if (usage == null || usage.turns.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: NeuSpace.n12),
                    child: Text(
                      I18n.t('ui.ec884726be'),
                      style: TextStyle(
                        fontSize: NeuFonts.small,
                        color: t.muted,
                      ),
                    ),
                  )
                else
                  for (final turn in usage.turns.reversed) _turnCard(t, turn),
              ],
            );
          },
        ),
      ),
    );
  }

  Color _contextColor(NeuTokens t, double percent) {
    if (percent >= 85) return t.danger;
    if (percent >= 70) return t.warn;
    return t.accentInk;
  }

  int _quotaLevel(UsageSummary? summary) {
    if (summary == null) return 0;
    if (summary.todayCost >= 10) return 2;
    if (summary.todayCost >= 5) return 1;
    return 0;
  }

  String _quotaText(UsageSummary? summary) {
    if (summary == null) return I18n.t('ui.20b7049647');
    final level = _quotaLevel(summary);
    final today = '\$${summary.todayCost.toStringAsFixed(3)}';
    return switch (level) {
      0 => I18n.tp('ui.d32325742b', {'today': today}),
      1 => I18n.tp('ui.1c4dd927c8', {'today': today}),
      _ => I18n.tp('ui.5283a21d5b', {'today': today}),
    };
  }

  Widget _section(NeuTokens t, String title) => Padding(
    padding: const EdgeInsets.only(top: NeuSpace.n18, bottom: NeuSpace.n8),
    child: Text(
      title,
      style: TextStyle(
        fontSize: NeuFonts.sectionTitle,
        fontWeight: FontWeight.w700,
        color: t.onBg,
      ),
    ),
  );

  /// 一天一行：日期 + 横条 + 数字。横条只表示相对大小，不标刻度。
  Widget _dayRow(
    NeuTokens t,
    String day,
    int tokens,
    double cost,
    int maxTokens,
  ) {
    final ratio = maxTokens <= 0 ? 0.0 : (tokens / maxTokens).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NeuSpace.n5),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              day.isEmpty ? '—' : day.substring(day.length >= 10 ? 5 : 0),
              style: TextStyle(fontSize: NeuFonts.label, color: t.muted),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Container(
                height: 8,
                color: t.well,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: ratio,
                  child: Container(color: t.accent),
                ),
              ),
            ),
          ),
          const SizedBox(width: NeuSpace.n10),
          SizedBox(
            width: 96,
            child: Text(
              '${_tokens(tokens)} · \$${cost.toStringAsFixed(3)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: NeuFonts.badge,
                color: t.fg,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 工作区只取路径最后一段（路径本身放在 sub 里，太长会挤掉数字）
  static String _workspaceName(String cwd) {
    final parts = cwd
        .replaceAll('\\', '/')
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? I18n.t('ui.b21364a469') : parts.last;
  }

  Widget _row(NeuTokens t, String label, String value, {String? sub}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NeuSpace.n4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(fontSize: NeuFonts.sub, color: t.muted),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: NeuFonts.bodySmall,
                    color: t.fg,
                    fontFamily: 'monospace',
                  ),
                ),
                if (sub != null)
                  Text(
                    sub,
                    style: TextStyle(fontSize: NeuFonts.micro, color: t.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _turnCard(NeuTokens t, UsageTurn turn) {
    final at = turn.at == null ? '—' : turn.at!.substring(11, 19);
    return NeuRaised(
      radius: NeuRadii.sm,
      padding: const EdgeInsets.all(NeuSpace.n12),
      margin: const EdgeInsets.only(bottom: NeuSpace.n8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '#${turn.index}',
                style: TextStyle(
                  fontSize: NeuFonts.sub,
                  fontWeight: FontWeight.w700,
                  color: t.accentInk,
                ),
              ),
              const SizedBox(width: NeuSpace.n8),
              Expanded(
                child: Text(
                  '${turn.model ?? '—'} · ${turn.provider ?? '—'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: NeuFonts.small, color: t.fg),
                ),
              ),
              Text(
                at,
                style: TextStyle(fontSize: NeuFonts.badge, color: t.muted),
              ),
            ],
          ),
          SizedBox(height: NeuSpace.n6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _chip(t, I18n.t('common.input'), _tokens(turn.input)),
              _chip(t, I18n.t('ui.8ba7c3a7be'), _tokens(turn.output)),
              _chip(t, I18n.t('ui.0ae4a745b0'), _tokens(turn.cacheRead)),
              _chip(t, I18n.t('ui.8e784e8cd7'), _tokens(turn.cacheWrite)),
              _chip(t, I18n.t('ui.21d68b2de0'), _tokens(turn.reasoning)),
              _chip(
                t,
                I18n.t('ui.39f1374d36'),
                turn.durationMs == null
                    ? '—'
                    : '${(turn.durationMs! / 1000).toStringAsFixed(1)}s',
              ),
              _chip(
                t,
                I18n.t('ui.03f38597a6'),
                turn.tokensPerSec == null ? '—' : '${turn.tokensPerSec}t/s',
              ),
              _chip(
                t,
                I18n.t('ui.6787355b9b'),
                turn.cacheHitRate == null ? '—' : '${turn.cacheHitRate}%',
              ),
              _chip(
                t,
                I18n.t('ui.7e237e9459'),
                turn.cost == null ? '—' : '\$${turn.cost!.toStringAsFixed(5)}',
              ),
              if (turn.stopReason != null && turn.stopReason != 'stop')
                _chip(t, I18n.t('ui.12f1d7ef38'), turn.stopReason!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(NeuTokens t, String label, String value) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '$label ',
        style: TextStyle(fontSize: NeuFonts.badge, color: t.muted),
      ),
      Text(
        value,
        style: TextStyle(
          fontSize: NeuFonts.label,
          color: t.fg,
          fontFamily: 'monospace',
        ),
      ),
    ],
  );
}
