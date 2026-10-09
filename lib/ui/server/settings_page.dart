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
import '../neu_section.dart';
import '../../theme/design_tokens.dart';
import '../../theme/neu.dart';
import '../neu_icons.dart';
import '../neu_toast.dart';
import 'config_page.dart';
import 'settings/about_section.dart';
import 'settings/app_section.dart';
import 'settings/conn_section.dart';
import 'settings/workspace_section.dart';
import 'settings/widgets.dart';

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
  /// **展开**了的分组标题。
  ///
  /// 注意这是反过来的语义：早前存的是"收起来的"，初始为空 = 全部展开 ——
  /// 于是用户每次进来都要手动把七八块一个个收掉，页面自然显得乱。
  /// 用户的原话是「类似设置里的通知也应该默认收起来点击再展开，这样比较美观」。
  /// 现在存"展开的"，初始为空 = 全部收起，想看哪块点哪块。
  final Set<String> _expanded = {};

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
        padding: EdgeInsets.fromLTRB(
          NeuSpace.n18,
          NeuSpace.n14,
          NeuSpace.n18,
          104,
        ),
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

          ConnSection(
            store: store,
            open: _isOpen('settings.conn'),
            onToggle: () => _toggle('settings.conn'),
            onOpenConn: onOpenConn,
          ),
          SizedBox(height: NeuSpace.n20),
          WorkspaceSection(
            store: store,
            open: _isOpen('settings.workspace'),
            onToggle: () => _toggle('settings.workspace'),
          ),
          SizedBox(height: NeuSpace.n20),
          // 「AI 配置」原先藏在「工作区」分组里，而模型、思考等级、技能命令、
          // MCP 服务器跟工作区没有任何关系。更麻烦的是 ConfigPage 全 App 只有
          // 这一个入口 —— 想改模型必须猜到「去工作区下面找 AI 配置」，猜不到就
          // 以为没这个功能。
          // 提到顶层独立成行后：一次点击直达（原先要先展开分组），也没有
          // 「分组标题 + 展开后又一行同样标题」的重复感。
          NeuRaised(
            radius: NeuRadii.lg,
            padding: const EdgeInsets.symmetric(
              horizontal: NeuSpace.n14,
              vertical: NeuSpace.n4,
            ),
            child: NeuPressable(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ConfigPage(store: store),
                  ),
                );
              },
              flat: true,
              padding: const EdgeInsets.symmetric(
                horizontal: NeuSpace.n12,
                vertical: NeuSpace.n12,
              ),
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
                          style: TextStyle(
                            fontSize: NeuFonts.bodyTight,
                            color: t.fg,
                          ),
                        ),
                        SizedBox(height: NeuSpace.n2),
                        Text(
                          I18n.t('ui.0874b95e15'),
                          // 与 NeuSection 里的摘要一致：单行 + 省略号。
                          // 不加的话在 360dp 窄屏下这句会换行，卡片比旁边几个分组高出一截
                          // （这是先靠 golden 基线看出来的 —— 断言式用例抓不到「没溢出但换了行」）。
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
          ),
          SizedBox(height: NeuSpace.n20),
          _section(
            t,
            I18n.t('settings.appearance', context: context),
            icon: IconId.image,
          ),
          if (_expanded.contains(
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
            _section(
              t,
              I18n.t('ui.066ae8d7d6'),
              icon: IconId.power,
              summary: AppPrefs.instance.keepAlive
                  ? I18n.t('ui.97f76f1a29')
                  : I18n.t('ui.d58a55bcee'),
            ),
            if (_expanded.contains(I18n.t('ui.066ae8d7d6'))) ...[
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
                    _section(t, I18n.t('ui.5660bcd256'), icon: IconId.bubble),
                    if (_expanded.contains(I18n.t('ui.5660bcd256'))) ...[
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
                      t,
                      I18n.t('settings.language', context: context),
                      icon: IconId.cmd,
                      summary: lang == 'zh'
                          ? '中文'
                          : (lang == 'en' ? 'English' : I18n.t('theme.system')),
                    ),
                    if (_expanded.contains(
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
          SizedBox(height: NeuSpace.n20),
          AppSection(
            store: store,
            open: _isOpen('settings.app'),
            onToggle: () => _toggle('settings.app'),
            // 这三个动作要动配置与缓存，留在页面侧；组件只负责触发
            onPickWorkspace: () => _pickDefaultWorkspace(context, t),
            onPickModel: () => _pickDefaultModel(context, t),
            onClearData: () => _clearLocalData(context),
          ),
          SizedBox(height: NeuSpace.n20),
          AboutSection(
            store: store,
            open: _isOpen('settings.about'),
            onToggle: () => _toggle('settings.about'),
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

  /// 发一条测试通知：用户自己能确认「通知这条路是通的」
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
          padding: EdgeInsets.fromLTRB(
            NeuSpace.n18,
            NeuSpace.n14,
            NeuSpace.n18,
            NeuSpace.n24,
          ),
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
                          style: TextStyle(
                            fontSize: NeuFonts.sub,
                            color: st.fg,
                          ),
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
                        style: TextStyle(
                          fontSize: NeuFonts.sub,
                          color: st.muted,
                        ),
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
      message: picked.isEmpty
          ? I18n.t('ui.add6e7b352')
          : I18n.tp('ui.9b86661544', {'picked': picked}),
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
          padding: const EdgeInsets.fromLTRB(
            NeuSpace.n18,
            NeuSpace.n14,
            NeuSpace.n18,
            NeuSpace.n24,
          ),
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
                    padding: const EdgeInsets.only(
                      top: NeuSpace.n8,
                      bottom: NeuSpace.n4,
                    ),
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: NeuFonts.label,
                        color: st.muted,
                      ),
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
                                  style: TextStyle(
                                    fontSize: NeuFonts.bodySmall,
                                    color: st.fg,
                                  ),
                                ),
                                Text(
                                  I18n.tp('ui.b7077d029c', {
                                    'provider': model.provider,
                                    'window': model.contextWindow ?? '?',
                                  }),
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
  /// 折叠分组的薄包装：状态在本页（`_expanded`），视觉与交互复用 [NeuSection]。
  ///
  /// 这里保留一层包装而不是让 8 处调用各自组装 NeuSection —— 那些调用点
  /// 关心的只是「标题 + 图标 + 摘要」，不该每次都写一遍 open/onToggle。
  /// 分组是否展开（`_expanded` 存的是「展开了」的标题）。
  ///
  /// 配合 [_toggle] 给抽出去的分组组件用：它们自己不持有状态，
  /// 只收「我展开了吗」和「点了要干什么」（约定见 docs/refactor-status.md）。
  bool _isOpen(String key) => _expanded.contains(key);

  void _toggle(String key) => setState(() {
    if (_expanded.contains(key)) {
      _expanded.remove(key);
    } else {
      _expanded.add(key);
    }
  });

  /// 保留这层薄包装：8 个分组的调用点都写 `_section(t, I18n.t(...), ...)`，
  /// 让它继续读 `_expanded` 并调 setState，就不用改那 8 处。
  /// 真正的壳已经搬到 `settings/widgets.dart`，分组抽出去时直接用那个。
  Widget _section(
    NeuTokens t,
    String title, {
    IconId icon = IconId.circle,
    String? summary,
  }) {
    final open = _expanded.contains(title);
    return SettingsSection(
      title: title,
      icon: icon,
      summary: summary,
      open: open,
      onToggle: () => setState(() {
        if (open) {
          _expanded.remove(title);
        } else {
          _expanded.add(title);
        }
      }),
    );
  }
}
