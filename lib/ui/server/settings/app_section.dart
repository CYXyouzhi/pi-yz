// 设置页的「settings.app」分组（由 tool/extract_section.py 机械搬运，之后人工校对）。
//
// 抽出来的理由与做法见 docs/refactor-status.md：状态留在父级 State，
// 组件只收 open（我展开了吗）与 onToggle（点了要干什么），自己不持有任何字段。

import 'package:flutter/material.dart';

import '../../../server/i18n.dart';
import '../../../server/app_prefs.dart';
import '../../../server/session_cache.dart';
import '../../../server/server_store.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../neu_icons.dart';
import '../log_page.dart';
import '../../collapsible_text.dart';
import '../../neu_toast.dart';
import 'widgets.dart';

class AppSection extends StatelessWidget {
  const AppSection({
    super.key,
    required this.store,
    required this.open,
    required this.onToggle,
    required this.onPickWorkspace,
    required this.onPickModel,
    required this.onClearData,
  });

  final ServerStore store;
  final bool open;
  final VoidCallback onToggle;

  /// 三个「打开选择器 / 清理」动作仍由页面实现（它们要动配置与缓存），
  /// 组件只负责在合适的位置触发 —— 符合「状态与副作用留在父级」的约定。
  final Future<void> Function() onPickWorkspace;
  final Future<void> Function() onPickModel;
  final Future<void> Function() onClearData;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final key = I18n.t('settings.app', context: context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSection(
          title: key,
          icon: IconId.gear,
          open: open,
          onToggle: onToggle,
        ),
        if (open) ...[
          ListenableBuilder(
            listenable: AppPrefs.instance,
            builder: (context, _) {
              final prefs = AppPrefs.instance;
              return NeuRaised(
                radius: NeuRadii.lg,
                padding: EdgeInsets.fromLTRB(NeuSpace.n14, NeuSpace.n10, NeuSpace.n14, NeuSpace.n14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PrefLabel(I18n.t('settings.fontSize', context: context),
                    ),
                    PrefChips([
                        (I18n.t('ui.391b8fa9c7'), 0.9),
                        (I18n.t('ui.544fac400d'), 1.0),
                        (I18n.t('ui.ab18e30c0d'), 1.15),
                        (I18n.t('ui.3386da5f56'), 1.3),
                      ],
                      current: prefs.fontScale,
                      onPick: prefs.setFontScale,
                    ),
                    PrefLabel(I18n.t('settings.lineHeight', context: context),
                    ),
                    PrefChips([(I18n.t('ui.03e59bb33c'), 1.3), (I18n.t('ui.544fac400d'), 1.45), (I18n.t('ui.43e534acf9'), 1.7)],
                      current: prefs.lineHeight,
                      onPick: prefs.setLineHeight,
                    ),
                    PrefLabel(I18n.t('settings.enter', context: context)),
                    PrefChips([(I18n.t('ui.2629bdbfad'), 0.0), (I18n.t('ui.63000cee55'), 1.0)],
                      current: prefs.sendWithEnter ? 1.0 : 0.0,
                      onPick: (v) => prefs.setSendWithEnter(v > 0.5),
                    ),
                    PrefLabel(I18n.t('settings.defaultWorkspace', context: context),
                    ),
                    PrefRow(prefs.defaultCwd.isEmpty ? I18n.t('ui.fe2d26a257') : prefs.defaultCwd,
                      actionLabel: I18n.t('common.select'),
                      onAction: () => onPickWorkspace(),
                    ),
                    PrefLabel(I18n.t('settings.defaultModel', context: context),
                    ),
                    PrefRow((store.defaultModelId == null ||
                              store.defaultModelProvider == null)
                          ? I18n.t('ui.56420c43ac')
                          : '${store.defaultModelId} · ${store.defaultModelProvider}',
                      actionLabel: I18n.t('common.select'),
                      onAction: () => onPickModel(),
                    ),
                    PrefLabel(I18n.t('ui.6e33906ae2')),
                    ValueListenableBuilder<int>(
                      valueListenable: cacheTick,
                      builder: (context, tick, _) => FutureBuilder<List<CacheEntry>>(
                        key: ValueKey<int>(tick),
                        future: SessionCache.entries(),
                        builder: (context, snapshot) {
                          final list = snapshot.data ?? const <CacheEntry>[];
                          final bytes = list.fold<int>(
                            0,
                            (sum, item) => sum + item.bytes,
                          );
                          final sizeLabel = bytes < 1024
                              ? '$bytes B'
                              : bytes < 1024 * 1024
                              ? '${(bytes / 1024).toStringAsFixed(1)} KB'
                              : '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                list.isEmpty
                                    ? I18n.t('ui.577d49c54f')
                                    : I18n.tp('ui.745a442139', {'n': list.length, 'size': sizeLabel}),
                                style: TextStyle(
                                  fontSize: NeuFonts.small,
                                  color: t.muted,
                                ),
                              ),
                              SizedBox(height: NeuSpace.n6),
                              CollapsibleText(
                                // 用插值而不是 +：三段的语言不同，拼接位置由每条译文自己决定
                                text: '${I18n.tp('ui.c97d59e36c', {'n': SessionCache.maxSessions})}'
                                    '${I18n.tp('ui.3c7de3c73a', {'n': SessionCache.maxMessages})}'
                                    '${I18n.t('ui.6b1e5ff3a1')} ${SessionCache.maxCharsPerSession ~/ 1024} KB'
                                    '${I18n.t('ui.2e2b64d0b1')}',
                                style: TextStyle(
                                  fontSize: NeuFonts.badge,
                                  height: 1.6,
                                  color: t.onBgDim,
                                ),
                              ),
                              for (final entry in list)
                                Padding(
                                  padding: const EdgeInsets.only(top: NeuSpace.n6),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${entry.name.isEmpty ? entry.sessionId.substring(0, 8) : entry.name}'
                                          '${I18n.tp('ui.96738eb2aa', {'n': entry.messageCount, 'size': entry.sizeLabel})}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: NeuFonts.label,
                                            color: t.muted,
                                          ),
                                        ),
                                      ),
                                      NeuPressable(
                                        onTap: () async {
                                          await SessionCache.removeOne(
                                            entry.sessionId,
                                          );
                                          cacheTick.value += 1;
                                          if (!context.mounted) return;
                                          NeuToast.show(
                                            context,
                                            message: I18n.t('ui.6d0d37ee23'),
                                            icon: IconId.check,
                                          );
                                        },
                                        radius: 8,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: NeuSpace.n8,
                                          vertical: NeuSpace.n4,
                                        ),
                                        child: Text(
                                          I18n.t('ui.4403fca0c0'),
                                          style: TextStyle(
                                            fontSize: NeuFonts.label,
                                            color: t.danger,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (list.isNotEmpty) ...[
                                const SizedBox(height: NeuSpace.n8),
                                NeuPressable(
                                  onTap: () async {
                                    await SessionCache.clear();
                                    cacheTick.value += 1;
                                    if (!context.mounted) return;
                                    NeuToast.show(
                                      context,
                                      message: I18n.t('ui.b2b3bb2703'),
                                      icon: IconId.check,
                                    );
                                  },
                                  radius: NeuRadii.sm,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: NeuSpace.n10,
                                  ),
                                  child: Center(
                                    child: Text(
                                      I18n.t('ui.3bc9ba2888'),
                                      style: TextStyle(
                                        fontSize: NeuFonts.sub,
                                        color: t.danger,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                    SizedBox(height: NeuSpace.n10),
                    PrefLabel(I18n.t('settings.localData', context: context),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: NeuPressable(
                            onTap: () => onClearData(),
                            radius: NeuRadii.sm,
                            padding: EdgeInsets.symmetric(vertical: NeuSpace.n10),
                            child: Center(
                              child: Text(
                                I18n.t('settings.clear', context: context),
                                style: TextStyle(
                                  fontSize: NeuFonts.sub,
                                  color: t.danger,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: NeuSpace.n8),
                        Expanded(
                          child: NeuPressable(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const LogPage(),
                              ),
                            ),
                            radius: NeuRadii.sm,
                            padding: EdgeInsets.symmetric(vertical: NeuSpace.n10),
                            child: Center(
                              child: Text(
                                I18n.t('settings.logs', context: context),
                                style: TextStyle(
                                  fontSize: NeuFonts.sub,
                                  color: t.accentInk,
                                ),
                              ),
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
        ],
      ],
    );
  }
}
