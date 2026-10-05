// 设置页（新）：服务端连接管理 + 外观 + 关于。
//
// 旧设置页面向 SSH 主机列表，服务端路线下这些字段没有意义，
// 所以重做一个精简版；旧的 SettingsPage 保留在代码里但不再引用。

import 'package:flutter/material.dart';
import '../collapsible_text.dart';

import '../../server/app_prefs.dart';
import '../../server/i18n.dart';
import '../../server/native_bridge.dart';
import '../../server/notification_center.dart';
import '../../server/session_cache.dart';
import '../../server/server_store.dart';
import '../../server/server_types.dart';
import '../../theme/design_tokens.dart';
import '../../theme/neu.dart';
import '../neu_icons.dart';
import '../neu_toast.dart';
import 'config_page.dart';
import 'files_page.dart';
import 'log_page.dart';
import 'pool_view.dart';

/// 清空离线缓存后自增，让缓存区重读一次（设置页本身是无状态的）
final ValueNotifier<int> cacheTick = ValueNotifier<int>(0);

class ServerSettingsPage extends StatefulWidget {
  const ServerSettingsPage({
    super.key,
    required this.store,
    required this.themeMode,
    required this.onThemeModeChanged,
    this.onOpenConn,
  });

  final ServerStore store;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VoidCallback? onOpenConn;

  @override
  State<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends State<ServerSettingsPage> {
  /// 收起来的分组标题（task-21 合同③）。
  /// 设置页太长，一屏一屏翻很累；收起来后能一屏看到"有哪几块"。
  final Set<String> _collapsed = {};

  // 用 getter 代理，这样下面 build 里原有的 store/themeMode 引用一行都不用改
  ServerStore get store => widget.store;
  ThemeMode get themeMode => widget.themeMode;
  ValueChanged<ThemeMode> get onThemeModeChanged => widget.onThemeModeChanged;
  VoidCallback? get onOpenConn => widget.onOpenConn;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => ListView(
        // 底部留出 tab 栏高度，否则「关于」最后一行被遮住
        padding: EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n14, NeuSpace.n18, 104),
        children: [
          Text(
            I18n.t('tab.settings'),
            style: TextStyle(
              fontSize: NeuFonts.pageTitle,
              fontWeight: FontWeight.w700,
              color: t.onBg,
            ),
          ),
          SizedBox(height: NeuSpace.n16),

          _section(t, I18n.t('settings.conn', context: context)),
          if (!_collapsed.contains(
            I18n.t('settings.conn', context: context),
          )) ...[
            NeuRaised(
              radius: NeuRadii.lg,
              padding: const EdgeInsets.all(NeuSpace.n16),
              child: Column(
                children: [
                  NeuPressable(
                    onTap: onOpenConn,
                    flat: true,
                    padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n12),
                    child: Row(
                      children: [
                        NeuIcon(IconId.server, size: 17, color: t.accentInk),
                        const SizedBox(width: NeuSpace.n12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                store.target?.label ?? I18n.t('ui.95af3b54e0'),
                                style: TextStyle(fontSize: NeuFonts.bodyTight, color: t.fg),
                              ),
                              SizedBox(height: NeuSpace.n2),
                              Text(
                                switch (store.state) {
                                  ServerConnectionState.connected =>
                                    I18n.tp('ui.b083df935e', {'v': store.health?.piVersion ?? ''}),
                                  ServerConnectionState.connecting => I18n.t('common.connecting'),
                                  ServerConnectionState.error =>
                                    store.errorMessage ?? I18n.t('common.connFailed'),
                                  ServerConnectionState.disconnected => I18n.t('common.disconnected'),
                                },
                                style: TextStyle(
                                  fontSize: NeuFonts.label,
                                  color: t.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        NeuIcon(IconId.chevronRight, size: 16, color: t.muted),
                      ],
                    ),
                  ),
                  if (store.isConnected) ...[
                    const SizedBox(height: NeuSpace.n10),
                    Row(
                      children: [
                        Expanded(
                          child: NeuPressable(
                            onTap: () => store.loadSessions(refresh: true),
                            radius: NeuRadii.sm,
                            padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                NeuIcon(IconId.sync, size: 14, color: t.muted),
                                SizedBox(width: NeuSpace.n6),
                                Text(
                                  I18n.t('ui.5e51feb8f3'),
                                  style: TextStyle(
                                    fontSize: NeuFonts.bodySmall,
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
                            onTap: () => store.disconnect(),
                            radius: NeuRadii.sm,
                            padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                NeuIcon(
                                  IconId.power,
                                  size: 14,
                                  color: t.danger,
                                ),
                                SizedBox(width: NeuSpace.n6),
                                Text(
                                  I18n.t('ui.9b55c5c9f8'),
                                  style: TextStyle(
                                    fontSize: NeuFonts.bodySmall,
                                    color: t.danger,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
          SizedBox(height: NeuSpace.n20),
          _section(t, I18n.t('settings.workspace', context: context)),
          if (!_collapsed.contains(
            I18n.t('settings.workspace', context: context),
          )) ...[
            NeuRaised(
              radius: NeuRadii.lg,
              padding: const EdgeInsets.all(NeuSpace.n16),
              child: Column(
                children: [
                  NeuPressable(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ConfigPage(store: store),
                        ),
                      );
                    },
                    flat: true,
                    padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n12),
                    child: Row(
                      children: [
                        NeuIcon(IconId.spinner, size: 17, color: t.accentInk),
                        SizedBox(width: NeuSpace.n12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                I18n.t('ui.5258ce61e8'),
                                style: TextStyle(fontSize: NeuFonts.bodyTight, color: t.fg),
                              ),
                              SizedBox(height: NeuSpace.n2),
                              Text(
                                I18n.t('ui.0874b95e15'),
                                style: TextStyle(
                                  fontSize: NeuFonts.label,
                                  color: t.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        NeuIcon(IconId.chevronRight, size: 16, color: t.muted),
                      ],
                    ),
                  ),
                  Container(height: 1, color: t.border),
                  NeuPressable(
                    onTap: () {
                      final cwd = store.chat.cwd.isNotEmpty
                          ? store.chat.cwd
                          : (store.target?.defaultCwd ?? '');
                      if (cwd.isEmpty) {
                        NeuToast.show(
                          context,
                          message: I18n.t('ui.45afe85695'),
                          icon: IconId.warn,
                        );
                        return;
                      }
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              WorkspaceFilesPage(store: store, cwd: cwd),
                        ),
                      );
                    },
                    flat: true,
                    padding: const EdgeInsets.symmetric(vertical: NeuSpace.n6),
                    child: Row(
                      children: [
                        NeuIcon(IconId.folder, size: 17, color: t.accentInk),
                        SizedBox(width: NeuSpace.n12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                I18n.t('ui.5ba881d3c3'),
                                style: TextStyle(fontSize: NeuFonts.bodyTight, color: t.fg),
                              ),
                              SizedBox(height: NeuSpace.n2),
                              Text(
                                I18n.t('ui.b66f0c9549'),
                                style: TextStyle(
                                  fontSize: NeuFonts.label,
                                  color: t.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        NeuIcon(IconId.chevronRight, size: 16, color: t.muted),
                      ],
                    ),
                  ),
                  // 存储占用：会话文件是本 App 在电脑上占地方的主角（实测一台机器 700+ MB），
                  // 得让用户看得见、清得掉（task-15 合同④）
                  NeuPressable(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => StoragePage(store: store),
                      ),
                    ),
                    flat: true,
                    padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n12),
                    child: Row(
                      children: [
                        NeuIcon(IconId.server, size: 17, color: t.accentInk),
                        SizedBox(width: NeuSpace.n12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                I18n.t('ui.b9d0f24c4c'),
                                style: TextStyle(fontSize: NeuFonts.bodyTight, color: t.fg),
                              ),
                              SizedBox(height: NeuSpace.n2),
                              Text(
                                I18n.t('ui.c7abd045d8'),
                                style: TextStyle(
                                  fontSize: NeuFonts.label,
                                  color: t.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        NeuIcon(IconId.chevronRight, size: 16, color: t.muted),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: NeuSpace.n20),
          _section(t, I18n.t('settings.appearance', context: context)),
          if (!_collapsed.contains(
            I18n.t('settings.appearance', context: context),
          )) ...[
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
            _section(t, I18n.t('ui.066ae8d7d6')),
            if (!_collapsed.contains(I18n.t('ui.066ae8d7d6'))) ...[
              NeuRaised(
                radius: NeuRadii.lg,
                padding: const EdgeInsets.fromLTRB(NeuSpace.n14, NeuSpace.n12, NeuSpace.n14, NeuSpace.n12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _notifToggle(
                      t,
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
                          NeuToast.show(context,
                              message: I18n.t('ui.cbfd37e24c'),
                              icon: IconId.check);
                        }
                      },
                    ),
                    SizedBox(height: NeuSpace.n6),
                    // 保活说明有 4–5 行，典型「想懂了有用、不想看时占地方」：
                    // 默认收成一行，点开看全文（手机竖屏的竖向空间最贵）。
                    CollapsibleText(
                      text: '${I18n.t('ui.27109fea19')}'
                          '${I18n.tp('ui.c97d59e36c', {'n': SessionCache.maxSessions})}'
                          '${I18n.t('ui.74d486f798')}'
                          '${I18n.t('ui.3df36a0007')}',
                      style: TextStyle(
                          fontSize: NeuFonts.label, height: 1.5, color: t.muted),
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
                    _section(t, I18n.t('ui.5660bcd256')),
                    NeuRaised(
                      radius: NeuRadii.lg,
                      padding: EdgeInsets.fromLTRB(NeuSpace.n14, NeuSpace.n12, NeuSpace.n14, NeuSpace.n12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _notifToggle(t, I18n.t('ui.0a2ef2dec1'), notif.notifyOnDone, (
                            v,
                          ) async {
                            notif.notifyOnDone = v;
                            await notif.setEnabled(notif.enabled);
                          }),
                          _notifToggle(t, I18n.t('ui.dd24107d75'), notif.notifyOnError, (
                            v,
                          ) async {
                            notif.notifyOnError = v;
                            await notif.setEnabled(notif.enabled);
                          }),
                          _notifToggle(t, I18n.t('ui.a7b4addcc2'), notif.notifyOnNeedInput, (
                            v,
                          ) async {
                            notif.notifyOnNeedInput = v;
                            await notif.setEnabled(notif.enabled);
                          }),
                          _notifToggle(
                            t,
                            I18n.t('ui.4f1313e28c'),
                            notif.watchOnly,
                            notif.setWatchOnly,
                          ),
                          _notifToggle(
                            t,
                            I18n.t('ui.a8b60db178'),
                            notif.quickReply,
                            notif.setQuickReply,
                          ),
                          SizedBox(height: NeuSpace.n6),
                          _prefLabel(t, I18n.t('ui.b33eaa597b')),
                          _prefChips(
                            t,
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
                          _prefLabel(t, I18n.t('ui.be63fac285')),
                          Row(
                            children: [
                              Expanded(
                                child: _prefChips(
                                  t,
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
                        'dnd': notif.inDndWindow ? I18n.t('ui.13b31d4b3e') : '',
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
                                  notif.enabled ? I18n.t('ui.3ee093d39a') : I18n.t('ui.e9e41b7e7f'),
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
                              I18n.tp('ui.ac2a29973b', {'n': notif.suppressed.length}),
                              style: TextStyle(fontSize: NeuFonts.label, color: t.muted),
                            ),
                            for (final item in notif.suppressed.take(3))
                              Padding(
                                padding: const EdgeInsets.only(top: NeuSpace.n2),
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
                            I18n.tp('ui.226628b2da', {'check': notif.selfCheck}),
                            style: TextStyle(fontSize: NeuFonts.micro, color: t.muted),
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
                    _section(t, I18n.t('settings.language', context: context)),
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
                );
              },
            ),
          ],
          SizedBox(height: NeuSpace.n20),
          _section(t, I18n.t('settings.app', context: context)),
          if (!_collapsed.contains(
            I18n.t('settings.app', context: context),
          )) ...[
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
                      _prefLabel(
                        t,
                        I18n.t('settings.fontSize', context: context),
                      ),
                      _prefChips(
                        t,
                        [
                          (I18n.t('ui.391b8fa9c7'), 0.9),
                          (I18n.t('ui.544fac400d'), 1.0),
                          (I18n.t('ui.ab18e30c0d'), 1.15),
                          (I18n.t('ui.3386da5f56'), 1.3),
                        ],
                        current: prefs.fontScale,
                        onPick: prefs.setFontScale,
                      ),
                      _prefLabel(
                        t,
                        I18n.t('settings.lineHeight', context: context),
                      ),
                      _prefChips(
                        t,
                        [(I18n.t('ui.03e59bb33c'), 1.3), (I18n.t('ui.544fac400d'), 1.45), (I18n.t('ui.43e534acf9'), 1.7)],
                        current: prefs.lineHeight,
                        onPick: prefs.setLineHeight,
                      ),
                      _prefLabel(t, I18n.t('settings.enter', context: context)),
                      _prefChips(
                        t,
                        [(I18n.t('ui.2629bdbfad'), 0.0), (I18n.t('ui.63000cee55'), 1.0)],
                        current: prefs.sendWithEnter ? 1.0 : 0.0,
                        onPick: (v) => prefs.setSendWithEnter(v > 0.5),
                      ),
                      _prefLabel(
                        t,
                        I18n.t('settings.defaultWorkspace', context: context),
                      ),
                      _prefRow(
                        t,
                        prefs.defaultCwd.isEmpty ? I18n.t('ui.fe2d26a257') : prefs.defaultCwd,
                        actionLabel: I18n.t('common.select'),
                        onAction: () => _pickDefaultWorkspace(context, t),
                      ),
                      _prefLabel(
                        t,
                        I18n.t('settings.defaultModel', context: context),
                      ),
                      _prefRow(
                        t,
                        (store.defaultModelId == null ||
                                store.defaultModelProvider == null)
                            ? I18n.t('ui.56420c43ac')
                            : '${store.defaultModelId} · ${store.defaultModelProvider}',
                        actionLabel: I18n.t('common.select'),
                        onAction: () => _pickDefaultModel(context, t),
                      ),
                      _prefLabel(t, I18n.t('ui.6e33906ae2')),
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
                      _prefLabel(
                        t,
                        I18n.t('settings.localData', context: context),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: NeuPressable(
                              onTap: () => _clearLocalData(context),
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
          SizedBox(height: NeuSpace.n20),
          _section(t, I18n.t('settings.about', context: context)),
          if (!_collapsed.contains(
            I18n.t('settings.about', context: context),
          )) ...[
            NeuRaised(
              radius: NeuRadii.lg,
              padding: const EdgeInsets.all(NeuSpace.n16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow(t, 'App', 'pi-mobile · pi-yz'),
                  _infoRow(t, I18n.t('ui.1de0cfbc46'), store.health?.piVersion ?? '—'),
                  _infoRow(t, I18n.t('ui.b08caf56ca'), '${store.health?.activeSessions ?? 0}'),
                  _infoRow(t, I18n.t('ui.f98077685a'), '${store.sessions.length}'),
                  SizedBox(height: NeuSpace.n6),
                  CollapsibleText(
                    // ignore: prefer_interpolation_to_compose_strings
                    text: '${I18n.t('ui.d2bf098e02')}'
                        '${I18n.t('ui.fccbc56d80')}',
                    style: TextStyle(
                      fontSize: NeuFonts.label,
                      height: 1.7,
                      color: t.onBgDim,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _prefLabel(NeuTokens t, String text) => Padding(
    padding: const EdgeInsets.only(top: NeuSpace.n12, bottom: NeuSpace.n6),
    child: Text(text, style: TextStyle(fontSize: NeuFonts.small, color: t.muted)),
  );

  /// 一行 chip 选择器（选中的那个凹进去）
  /// 通知项的一行开关（开关状态直接写在右侧，不靠颜色猜）
  Widget _notifToggle(
    NeuTokens t,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NeuSpace.n3),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: NeuFonts.bodyMid, color: t.fg)),
          ),
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

  /// 卡住阈值自定义：直接输入秒数（同时验证「默认值界面可见」之外的灵活性）
  Future<void> _pickStuckSeconds(BuildContext context, NeuTokens t) async {
    final controller = TextEditingController(
      text: '${NotificationCenter.instance.stallSeconds}',
    );
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: t.bg,
        title: Text(I18n.t('ui.af3e668e71'), style: TextStyle(color: t.fg, fontSize: NeuFonts.heading)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: TextStyle(color: t.fg),
          decoration: InputDecoration(hintText: I18n.t('ui.ef78e4268a')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(I18n.t('common.cancel'), style: TextStyle(color: t.muted)),
          ),
          TextButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              Navigator.of(dialogContext).pop(parsed);
            },
            child: Text(I18n.t('common.save'), style: TextStyle(color: t.accentInk)),
          ),
        ],
      ),
    );
    if (value == null || value < 10) return;
    await NotificationCenter.instance.setStallSeconds(value);
  }

  /// 发一条测试通知：用户自己能确认「通知这条路是通的」
  Future<void> _testNotification(BuildContext context, NeuTokens t) async {
    final notif = NotificationCenter.instance;
    final granted = await notif.hasPermission();
    if (!granted) {
      await notif.requestPermission();
      if (!context.mounted) return;
      NeuToast.show(context, message: I18n.t('ui.87ad4d4da6'), icon: IconId.info);
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

  Widget _prefChips(
    NeuTokens t,
    List<(String, double)> options, {
    required double current,
    required ValueChanged<double> onPick,
  }) {
    return NeuRaised(
      radius: NeuRadii.sm,
      padding: const EdgeInsets.all(NeuSpace.n4),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: NeuPressable(
                onTap: () => onPick(option.$2),
                flat: (current - option.$2).abs() > 0.001,
                alwaysInset: (current - option.$2).abs() <= 0.001,
                radius: NeuRadii.sm,
                padding: const EdgeInsets.symmetric(vertical: NeuSpace.n9),
                child: Center(
                  child: Text(
                    option.$1,
                    style: TextStyle(
                      fontSize: NeuFonts.sub,
                      color: (current - option.$2).abs() <= 0.001
                          ? t.accentInk
                          : t.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 一行「当前值 + 一个动作按钮」
  Widget _prefRow(
    NeuTokens t,
    String value, {
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return NeuRaised(
      radius: NeuRadii.sm,
      padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n10, vertical: NeuSpace.n6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              style: TextStyle(fontSize: NeuFonts.small, color: t.fg),
            ),
          ),
          NeuPressable(
            onTap: onAction,
            radius: 8,
            flat: true,
            padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n10, vertical: NeuSpace.n5),
            child: Text(
              actionLabel,
              style: TextStyle(fontSize: NeuFonts.sub, color: t.accentInk),
            ),
          ),
        ],
      ),
    );
  }

  /// 选默认工作区：候选来自「会话用过的工作区」+ 连接配置里的默认值
  Future<void> _pickDefaultWorkspace(BuildContext context, NeuTokens t) async {
    final cwds = <String>{
      if ((store.target?.defaultCwd ?? '').isNotEmpty)
        store.target!.defaultCwd!,
      for (final session in store.sessions) session.cwd,
    }.toList()..sort();
    if (!context.mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final st = sheetContext.neu;
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
          ),
          decoration: BoxDecoration(
            color: st.bg,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(NeuRadii.lg),
            ),
          ),
          padding: EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n14, NeuSpace.n18, NeuSpace.n24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                I18n.t('ui.96dba48253'),
                style: TextStyle(
                  fontSize: NeuFonts.sectionTitle,
                  fontWeight: FontWeight.w700,
                  color: st.onBg,
                ),
              ),
              const SizedBox(height: NeuSpace.n8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final cwd in cwds)
                      NeuPressable(
                        onTap: () => Navigator.of(sheetContext).pop(cwd),
                        radius: 10,
                        padding: const EdgeInsets.symmetric(
                          horizontal: NeuSpace.n12,
                          vertical: NeuSpace.n10,
                        ),
                        margin: const EdgeInsets.only(bottom: NeuSpace.n6),
                        child: Text(
                          cwd,
                          style: TextStyle(fontSize: NeuFonts.sub, color: st.fg),
                        ),
                      ),
                    NeuPressable(
                      onTap: () => Navigator.of(sheetContext).pop(''),
                      radius: 10,
                      padding: const EdgeInsets.symmetric(
                        horizontal: NeuSpace.n12,
                        vertical: NeuSpace.n10,
                      ),
                      child: Text(
                        I18n.t('ui.f447ebec03'),
                        style: TextStyle(fontSize: NeuFonts.sub, color: st.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked == null) return;
    await AppPrefs.instance.setDefaultCwd(picked);
    if (!context.mounted) return;
    NeuToast.show(
      context,
      message: picked.isEmpty ? I18n.t('ui.add6e7b352') : I18n.tp('ui.9b86661544', {'picked': picked}),
      icon: IconId.check,
    );
  }

  /// 选「新会话默认模型」：写电脑端 pi 的 settings.json（只影响新会话）
  Future<void> _pickDefaultModel(BuildContext context, NeuTokens t) async {
    await store.loadDefaultModel();
    final models = await store.availableModels();
    if (!context.mounted) return;
    final byProvider = <String, List<ModelInfo>>{};
    for (final model in models) {
      byProvider.putIfAbsent(model.provider, () => []).add(model);
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final st = sheetContext.neu;
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
          ),
          decoration: BoxDecoration(
            color: st.bg,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(NeuRadii.lg),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n14, NeuSpace.n18, NeuSpace.n24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  I18n.t('ui.930618f742'),
                  style: TextStyle(
                    fontSize: NeuFonts.sectionTitle,
                    fontWeight: FontWeight.w700,
                    color: st.onBg,
                  ),
                ),
                SizedBox(height: NeuSpace.n4),
                Text(
                  I18n.tp('ui.03dd98a903', {
                    'name': store.defaultModelId ?? '—',
                    'provider': store.defaultModelProvider ?? '—',
                  }),
                  style: TextStyle(fontSize: NeuFonts.small, color: st.muted),
                ),
                const SizedBox(height: NeuSpace.n10),
                for (final entry in byProvider.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: NeuSpace.n8, bottom: NeuSpace.n4),
                    child: Text(
                      entry.key,
                      style: TextStyle(fontSize: NeuFonts.label, color: st.muted),
                    ),
                  ),
                  for (final model in entry.value)
                    NeuPressable(
                      onTap: () =>
                          Navigator.of(sheetContext)
                              .pop('${model.provider}/${model.id}'),
                      radius: 10,
                      padding: const EdgeInsets.symmetric(
                        horizontal: NeuSpace.n12,
                        vertical: NeuSpace.n9,
                      ),
                      margin: const EdgeInsets.only(bottom: NeuSpace.n6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  model.name,
                                  style: TextStyle(fontSize: NeuFonts.bodySmall, color: st.fg),
                                ),
                                Text(
                                  I18n.tp('ui.b7077d029c',
                    {'provider': model.provider, 'window': model.contextWindow ?? '?'}),
                                  style: TextStyle(
                                    fontSize: NeuFonts.micro,
                                    color: st.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (model.id == store.defaultModelId &&
                              model.provider == store.defaultModelProvider)
                            NeuIcon(
                              IconId.check,
                              size: 15,
                              color: st.accentInk,
                            ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
    if (picked == null) return;
    final parts = picked.split('/');
    if (parts.length != 2) return;
    final ok = await store.setDefaultModel(parts[0], parts[1]);
    if (!context.mounted) return;
    NeuToast.show(
      context,
      message: ok
          ? I18n.tp('ui.fd70d64c54', {'model': parts[1]})
          : (store.lastError ?? I18n.t('ui.fa76940a48')),
      icon: ok ? IconId.check : IconId.warn,
    );
  }

  Future<void> _clearLocalData(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(dialogContext).colorScheme.surface,
        title: Text(I18n.t('ui.1d3a567c5e')),
        content: Text(
          '${I18n.t('ui.d92cca389d0')}'
          '${I18n.t('ui.22f5ca6614')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(I18n.t('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(I18n.t('ui.e47bb1cd74')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final drafts = store.clearDrafts();
    final others = await AppPrefs.instance.clearLocalData();
    // 离线缓存是独立存的一份，不清的话用户会以为「清理本地数据」清干净了
    await SessionCache.clear();
    cacheTick.value += 1;
    if (!context.mounted) return;
    NeuToast.show(
      context,
      message: I18n.tp('ui.c1a9075e7b', {'drafts': drafts, 'others': others}),
      icon: IconId.check,
    );
  }

  /// 分组标题：点一下收起/展开这一组（task-21 合同③）
  Widget _section(NeuTokens t, String title) {
    final open = !_collapsed.contains(title);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        if (open) {
          _collapsed.add(title);
        } else {
          _collapsed.remove(title);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.only(bottom: NeuSpace.n8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: NeuFonts.sectionTitle,
                  fontWeight: FontWeight.w700,
                  color: t.onBg,
                ),
              ),
            ),
            NeuIcon(
              open ? IconId.chevronDown : IconId.chevronRight,
              size: 16,
              color: t.muted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(NeuTokens t, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: NeuSpace.n4),
    child: Row(
      children: [
        Text(label, style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.muted)),
        const Spacer(),
        Text(
          value,
          style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.fg, fontFamily: 'monospace'),
        ),
      ],
    ),
  );
}
