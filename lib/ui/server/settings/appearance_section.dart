import 'package:flutter/material.dart';

import '../../../server/app_prefs.dart';
import '../../../server/i18n.dart';
import '../../../server/native_bridge.dart';
import '../../../server/notification_center.dart';
import '../../../server/session_cache.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../collapsible_text.dart';
import '../../neu_icons.dart';
import '../../neu_toast.dart';
import 'widgets.dart';

/// 外观分组：主题档 / 后台保活 / 通知 / 语言。
///
/// 从 `settings_page.dart` 搬出来的一块（那文件里它独自占了 422 行）。
/// 约定与其他分组一致：**状态留在父级 State**，这里只收
///   · 我展开了吗（`isOpen`）· 点了要干什么（`onToggle`）· 主题档那一对
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.isOpen,
    required this.onToggle,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final bool Function(String key) isOpen;
  final void Function(String key) onToggle;

  /// 与父级那个薄包装同名同形 —— 搬过来的调用点因此一行都不用改。
  Widget _section(
    String title, {
    IconId icon = IconId.circle,
    String? summary,
  }) => SettingsSection(
    title: title,
    open: isOpen(title),
    onToggle: () => onToggle(title),
    icon: icon,
    summary: summary,
  );

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(
          I18n.t('settings.appearance', context: context),
          icon: IconId.image,
        ),
        if (isOpen(I18n.t('settings.appearance', context: context))) ...[
          NeuRaised(
            radius: NeuRadii.lg,
            padding: const EdgeInsets.all(NeuSpace.n6),
            child: Row(
              children: [
                for (final option in const [
                  (ThemeMode.system, 'theme.system'),
                  (ThemeMode.light, 'theme.light'),
                  (ThemeMode.dark, 'theme.dark'),
                ])
                  Expanded(
                    child: NeuPressable(
                      onTap: () => onThemeModeChanged(option.$1),
                      flat: themeMode != option.$1,
                      alwaysInset: themeMode == option.$1,
                      radius: NeuRadii.sm,
                      padding: EdgeInsets.symmetric(vertical: NeuSpace.n11),
                      child: Center(
                        child: Text(
                          option.$2.startsWith('theme.')
                              ? I18n.t(option.$2, context: context)
                              : option.$2,
                          style: TextStyle(
                            fontSize: NeuFonts.bodySmall,
                            color: themeMode == option.$1
                                ? t.accentInk
                                : t.muted,
                            fontWeight: themeMode == option.$1
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          SizedBox(height: NeuSpace.n20),

          // ==================== 后台保活（补 task-10 的已知不足） ====================
          _section(
            I18n.t('ui.066ae8d7d6'),
            icon: IconId.power,
            summary: AppPrefs.instance.keepAlive
                ? I18n.t('ui.97f76f1a29')
                : I18n.t('ui.d58a55bcee'),
          ),
          if (isOpen(I18n.t('ui.066ae8d7d6'))) ...[
            NeuRaised(
              radius: NeuRadii.lg,
              padding: const EdgeInsets.fromLTRB(
                NeuSpace.n14,
                NeuSpace.n12,
                NeuSpace.n14,
                NeuSpace.n12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NotifToggle(
                    I18n.t('ui.97f76f1a29'),
                    AppPrefs.instance.keepAlive,
                    (value) async {
                      await AppPrefs.instance.setKeepAlive(value);
                      if (value) {
                        final ok = await NativeBridge.startKeepAlive();
                        // 这里的 context 是 builder 的，判断也用它的 mounted
                        if (!context.mounted) return;
                        NeuToast.show(
                          context,
                          message: ok
                              ? I18n.t('ui.79e99333c9')
                              : I18n.t('ui.c6f2208df0'),
                          icon: ok ? IconId.check : IconId.warn,
                        );
                      } else {
                        await NativeBridge.stopKeepAlive();
                        if (!context.mounted) return;
                        NeuToast.show(
                          context,
                          message: I18n.t('ui.cbfd37e24c'),
                          icon: IconId.check,
                        );
                      }
                    },
                  ),
                  SizedBox(height: NeuSpace.n6),
                  // 保活说明有 4–5 行，典型「想懂了有用、不想看时占地方」：
                  // 默认收成一行，点开看全文（手机竖屏的竖向空间最贵）。
                  CollapsibleText(
                    text:
                        '${I18n.t('ui.27109fea19')}'
                        '${I18n.tp('ui.c97d59e36c', {'n': SessionCache.maxSessions})}'
                        '${I18n.t('ui.74d486f798')}'
                        '${I18n.t('ui.3df36a0007')}',
                    style: TextStyle(
                      fontSize: NeuFonts.label,
                      height: 1.5,
                      color: t.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ==================== 通知（task-11） ====================
          ListenableBuilder(
            listenable: NotificationCenter.instance,
            builder: (context, _) {
              final notif = NotificationCenter.instance;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _section(I18n.t('ui.5660bcd256'), icon: IconId.bubble),
                  if (isOpen(I18n.t('ui.5660bcd256'))) ...[
                    NeuRaised(
                      radius: NeuRadii.lg,
                      padding: EdgeInsets.fromLTRB(
                        NeuSpace.n14,
                        NeuSpace.n12,
                        NeuSpace.n14,
                        NeuSpace.n12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          NotifToggle(
                            I18n.t('ui.0a2ef2dec1'),
                            notif.notifyOnDone,
                            (v) async {
                              notif.notifyOnDone = v;
                              await notif.setEnabled(notif.enabled);
                            },
                          ),
                          NotifToggle(
                            I18n.t('ui.dd24107d75'),
                            notif.notifyOnError,
                            (v) async {
                              notif.notifyOnError = v;
                              await notif.setEnabled(notif.enabled);
                            },
                          ),
                          NotifToggle(
                            I18n.t('ui.a7b4addcc2'),
                            notif.notifyOnNeedInput,
                            (v) async {
                              notif.notifyOnNeedInput = v;
                              await notif.setEnabled(notif.enabled);
                            },
                          ),
                          NotifToggle(
                            I18n.t('ui.4f1313e28c'),
                            notif.watchOnly,
                            notif.setWatchOnly,
                          ),
                          NotifToggle(
                            I18n.t('ui.a8b60db178'),
                            notif.quickReply,
                            notif.setQuickReply,
                          ),
                          SizedBox(height: NeuSpace.n6),
                          PrefLabel(I18n.t('ui.b33eaa597b')),
                          PrefChips(
                            [
                              (I18n.t('ui.f4ae4ba20c'), 60),
                              (I18n.t('ui.265b0f8cf7'), 120),
                              (I18n.t('ui.ec13baff37'), 300),
                              (I18n.t('ui.0e19f86e8d'), 600),
                            ],
                            current: notif.stallSeconds.toDouble(),
                            onPick: (v) => notif.setStallSeconds(v.round()),
                          ),
                          SizedBox(height: NeuSpace.n10),
                          PrefLabel(I18n.t('ui.be63fac285')),
                          Row(
                            children: [
                              Expanded(
                                child: PrefChips(
                                  [
                                    (I18n.t('ui.6224248126'), 0),
                                    ('23→8', 1),
                                    ('22→7', 2),
                                    ('0→7', 3),
                                  ],
                                  current: !notif.dndEnabled
                                      ? 0
                                      : notif.dndStartHour == 22
                                      ? 2
                                      : notif.dndStartHour == 0
                                      ? 3
                                      : 1,
                                  onPick: (v) {
                                    switch (v.round()) {
                                      case 0:
                                        notif.setDnd(on: false);
                                      case 1:
                                        notif.setDnd(
                                          on: true,
                                          startHour: 23,
                                          endHour: 8,
                                        );
                                      case 2:
                                        notif.setDnd(
                                          on: true,
                                          startHour: 22,
                                          endHour: 7,
                                        );
                                      default:
                                        notif.setDnd(
                                          on: true,
                                          startHour: 0,
                                          endHour: 7,
                                        );
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: NeuSpace.n10),
                          // 权限与「被压掉的提醒」都要看得见：不然用户只会觉得「没提醒」
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  notif.enabled
                                      ? I18n.tp('ui.ded70fe6ab', {
                                          'dnd': notif.inDndWindow
                                              ? I18n.t('ui.13b31d4b3e')
                                              : '',
                                        })
                                      : I18n.t('ui.b0a2bb16fb'),
                                  style: TextStyle(
                                    fontSize: NeuFonts.small,
                                    color: t.muted,
                                  ),
                                ),
                              ),
                              NeuPressable(
                                onTap: () => notif.setEnabled(!notif.enabled),
                                radius: NeuRadii.sm,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: NeuSpace.n12,
                                  vertical: NeuSpace.n8,
                                ),
                                child: Text(
                                  notif.enabled
                                      ? I18n.t('ui.3ee093d39a')
                                      : I18n.t('ui.e9e41b7e7f'),
                                  style: TextStyle(
                                    fontSize: NeuFonts.sub,
                                    color: t.accentInk,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (notif.suppressed.isNotEmpty) ...[
                            SizedBox(height: NeuSpace.n8),
                            Text(
                              I18n.tp('ui.ac2a29973b', {
                                'n': notif.suppressed.length,
                              }),
                              style: TextStyle(
                                fontSize: NeuFonts.label,
                                color: t.muted,
                              ),
                            ),
                            for (final item in notif.suppressed.take(3))
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: NeuSpace.n2,
                                ),
                                child: Text(
                                  '· $item',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: NeuFonts.badge,
                                    color: t.muted,
                                  ),
                                ),
                              ),
                          ],
                          SizedBox(height: NeuSpace.n6),
                          Text(
                            I18n.tp('ui.226628b2da', {
                              'check': notif.selfCheck,
                            }),
                            style: TextStyle(
                              fontSize: NeuFonts.micro,
                              color: t.muted,
                            ),
                          ),
                          const SizedBox(height: NeuSpace.n8),
                          Row(
                            children: [
                              Expanded(
                                child: NeuPressable(
                                  onTap: () => _testNotification(context, t),
                                  radius: NeuRadii.sm,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: NeuSpace.n10,
                                  ),
                                  child: Center(
                                    child: Text(
                                      I18n.t('ui.8454029f34'),
                                      style: TextStyle(
                                        fontSize: NeuFonts.sub,
                                        color: t.accentInk,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: NeuSpace.n8),
                              Expanded(
                                child: NeuPressable(
                                  onTap: () => _pickStuckSeconds(context, t),
                                  radius: NeuRadii.sm,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: NeuSpace.n10,
                                  ),
                                  child: Center(
                                    child: Text(
                                      I18n.t('ui.6c237fca7f'),
                                      style: TextStyle(
                                        fontSize: NeuFonts.sub,
                                        color: t.muted,
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
                  ],
                ],
              );
            },
          ),

          const SizedBox(height: NeuSpace.n20),
          const SizedBox(height: NeuSpace.n20),
          ListenableBuilder(
            listenable: AppPrefs.instance,
            builder: (context, _) {
              final lang = AppPrefs.instance.lang;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _section(
                    I18n.t('settings.language', context: context),
                    icon: IconId.cmd,
                    summary: lang == 'zh'
                        ? '中文'
                        : (lang == 'en' ? 'English' : I18n.t('theme.system')),
                  ),
                  if (isOpen(
                    I18n.t('settings.language', context: context),
                  )) ...[
                    NeuRaised(
                      radius: NeuRadii.lg,
                      padding: const EdgeInsets.all(NeuSpace.n6),
                      child: Row(
                        children: [
                          for (final option in const [
                            ('zh', 'lang.zh'),
                            ('en', 'lang.en'),
                            ('system', 'lang.system'),
                          ])
                            Expanded(
                              child: NeuPressable(
                                onTap: () =>
                                    AppPrefs.instance.setLang(option.$1),
                                flat: lang != option.$1,
                                alwaysInset: lang == option.$1,
                                radius: NeuRadii.sm,
                                padding: const EdgeInsets.symmetric(
                                  vertical: NeuSpace.n11,
                                ),
                                child: Center(
                                  child: Text(
                                    I18n.t(option.$2, context: context),
                                    style: TextStyle(
                                      fontSize: NeuFonts.bodySmall,
                                      color: lang == option.$1
                                          ? t.accentInk
                                          : t.muted,
                                      fontWeight: lang == option.$1
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  Future<void> _pickStuckSeconds(BuildContext context, NeuTokens t) async {
    final controller = TextEditingController(
      text: '${NotificationCenter.instance.stallSeconds}',
    );
    // 用 try/finally 包住：下面有「用户取消」与「值不合法」两条提前 return 的路径，
    // 只靠函数末尾清理会漏掉它们。同项目的 config_page / files_page 也是这个写法。
    try {
      final value = await showDialog<int>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: t.bg,
          title: Text(
            I18n.t('ui.af3e668e71'),
            style: TextStyle(color: t.fg, fontSize: NeuFonts.heading),
          ),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: TextStyle(color: t.fg),
            decoration: InputDecoration(hintText: I18n.t('ui.ef78e4268a')),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                I18n.t('common.cancel'),
                style: TextStyle(color: t.muted),
              ),
            ),
            TextButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text.trim());
                Navigator.of(dialogContext).pop(parsed);
              },
              child: Text(
                I18n.t('common.save'),
                style: TextStyle(color: t.accentInk),
              ),
            ),
          ],
        ),
      );
      if (value == null || value < 10) return;
      await NotificationCenter.instance.setStallSeconds(value);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _testNotification(BuildContext context, NeuTokens t) async {
    final notif = NotificationCenter.instance;
    final granted = await notif.hasPermission();
    if (!granted) {
      await notif.requestPermission();
      if (!context.mounted) return;
      NeuToast.show(
        context,
        message: I18n.t('ui.87ad4d4da6'),
        icon: IconId.info,
      );
      return;
    }
    final ok = await notif.sendTest();
    if (!context.mounted) return;
    NeuToast.show(
      context,
      message: ok ? I18n.t('ui.a3549f9b28') : I18n.t('ui.5e0e5bf05d'),
      icon: ok ? IconId.check : IconId.warn,
    );
  }
}
