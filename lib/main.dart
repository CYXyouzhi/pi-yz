import 'dart:async';
import 'ui/nav_bar_visibility.dart';
import 'dart:ui' show FrameTiming;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import 'server/app_prefs.dart';
import 'server/i18n.dart';
import 'server/server_profile.dart';
import 'server/notification_center.dart';
import 'server/server_store.dart';
import 'services/debug_log.dart';
import 'theme/design_tokens.dart';
import 'theme/neu.dart';
import 'theme/neu_theme.dart';
import 'ui/neu_icons.dart';
import 'ui/server/chat_page.dart';
import 'ui/server/conn_page.dart';
import 'ui/server/sessions_page.dart';
import 'ui/server/settings_page.dart';

/// pi 远程 —— 把电脑上 pi 的完整 TUI 搬到手机。
///
/// 架构：本 App 只做「显示器 + 键盘」，pi 始终跑在你的电脑上，
/// 通过标准 SSH 连接。因此 pi 的任何功能（斜杠命令、扩展 UI、
/// 分支树、主题）都自动完整可用，App 侧无需逐个适配。
///
/// 界面按 `pi-remote-app.html` 的新拟态设计稿重做：
/// 材质与画布同色，形体只由「左上白光 / 右下暗影」一对软阴影建立。
void main() {
  // 框架级异常也收进调试日志：崩溃不必连调试器，打开日志面板就能看。
  FlutterError.onError = (FlutterErrorDetails details) {
    DebugLog.instance.error('flutter', details.exceptionAsString());
    final stack = details.stack?.toString().split('\n').take(5).join(' | ');
    if (stack != null) {
      DebugLog.instance.debug('flutter', stack);
    }
    FlutterError.presentError(details);
  };

  runApp(const PiMobileApp());
}

class PiMobileApp extends StatefulWidget {
  const PiMobileApp({super.key});

  @override
  State<PiMobileApp> createState() => _PiMobileAppState();
}

class _PiMobileAppState extends State<PiMobileApp> {
  ThemeMode _mode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    // App 自身偏好（字号 / 行距 / 回车发送 / 主题）：启动读一次
    AppPrefs.instance.load();
    AppPrefs.instance.addListener(_onPrefs);
  }

  void _onPrefs() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppPrefs.instance.removeListener(_onPrefs);
    super.dispose();
  }

  /// 启动遮罩是否已退场（详见 [_SplashOverlay] 的说明）
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: I18n.t('ui.appshort'),
      debugShowCheckedModeBanner: false,
      themeMode: AppPrefs.instance.loaded ? AppPrefs.instance.themeMode : _mode,
      theme: buildNeuTheme(NeuTokens.light, brightness: Brightness.light),
      darkTheme: buildNeuTheme(NeuTokens.dark, brightness: Brightness.dark),
      // 画布（渐变底 + 固定光源层）包住整个 App。
      // 光源是固定的：光一移动，所有阴影的方向就全错了。
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        // 字号：整棵树的文字一起缩放，改完立刻生效
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(AppPrefs.instance.fontScale),
          ),
          child: NeuCanvas(
          brightness: isDark ? Brightness.dark : Brightness.light,
          child: Stack(
            children: [
              ?child,
              if (!_splashDone)
                _SplashOverlay(
                  onDone: () => setState(() => _splashDone = true),
                ),
            ],
            ),
          ),
        );
      },
      home: AppShell(
        themeMode: AppPrefs.instance.loaded ? AppPrefs.instance.themeMode : _mode,
        onThemeModeChanged: (m) {
          setState(() => _mode = m);
          AppPrefs.instance.setThemeMode(m);
        },
      ),
    );
  }
}

/// 应用外壳：底部 Tab 栏 + 页面切换。
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _tab = 0;


  /// 服务端连接与当前会话（新的 HTTP 路线）
  final ServerStore _serverStore = ServerStore();

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    super.initState();
    _serverStore.addListener(_maybeJumpToChat);
    // 通知中心：跑完/卡住/需要确认的提醒，以及通知栏快速回复（task-11）
    // 从通知/快速回复进来时把界面切到会话页 —— 一次性标志不够用：
    // App 已在前台停在别的 tab 时，标志早就用掉了，点了通知会「哪也没去」。
    NotificationCenter.instance.onOpenSessionRequested = () {
      if (mounted) setState(() => _tab = 1);
    };
    NotificationCenter.instance.load().then((_) => NotificationCenter.instance.attach(_serverStore));
    _restoreConnection();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serverStore.removeListener(_maybeJumpToChat);
    // 通知中心解绑：不取消它那只 5 秒定时器的话，App 壳重建一次就多挂一个
    NotificationCenter.instance.detach();
    _serverStore.dispose();
    super.dispose();
  }

  /// 只在「启动后自动恢复了上次会话」这一种情况下自动切到会话页。
  ///
  /// 为什么值得做：退到后台被系统杀了进程、重开时用户是想接着聊，
  /// 停在连接卡上还得自己点一下「会话」才能看到刚才的进度。
  /// 只跳一次（_jumped），免得用户自己切走以后又被拽回来。
  bool _jumped = false;
  void _maybeJumpToChat() {
    if (_jumped) return;
    if (_serverStore.currentSessionId == null) return;
    _jumped = true;
    if (mounted) setState(() => _tab = 1);
  }

  /// 启动时自动连接上次使用的服务端
  Future<void> _restoreConnection() async {
    final profiles = await ServerProfileStore.loadAll();
    if (profiles.isEmpty) return;
    final activeId = await ServerProfileStore.loadActiveId();
    ServerProfile? active;
    for (final profile in profiles) {
      if (profile.id == activeId) active = profile;
    }
    active ??= profiles.first;
    await _serverStore.connect(ServerTarget(
      host: active.host,
      port: active.port,
      token: active.token,
      defaultCwd: active.defaultCwd,
      secure: active.secure,
      fallbackHost: active.fallbackHost,
      fallbackPort: active.fallbackPort,
      fallbackSecure: active.fallbackSecure,
    ));
  }

  void _openConnScreen() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ServerConnPage(
        store: _serverStore,
        onConnected: () {
          if (mounted) setState(() => _tab = 1);
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 由 NeuCanvas 提供画布，Scaffold 必须透明
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: context.neuDur(NeuMotion.page),
                switchInCurve: NeuMotion.out,
                switchOutCurve: NeuMotion.out,
                // 位移只属于「进入」这一个动作；离开只剩淡出，位置不动。
                transitionBuilder: (child, animation) => _buildPageTransition(
                  child: child,
                  animation: animation,
                  incoming: child.key == ValueKey<int>(_tab),
                  motionScale: context.neuMotion(1.0),
                ),
                // 默认的 layoutBuilder 是 Stack + 居中对齐，而 Stack 给子项的是**松约束**，
                // 于是 SingleChildScrollView 会缩到内容高度再被居中 —— 页面就飘在屏幕中间了。
                // 这里改成顶部对齐（并让两个页都撑满），页面才从顶上开始排。
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.topCenter,
                  children: [...previousChildren, ?currentChild],
                ),
                // 三个 Tab 用 IndexedStack 常驻：切走再回来时页面状态还在
                // （输入草稿、滚动位置、展开的目录、命令面板）。
                // 以前是 AnimatedSwitcher + 每个 Tab 一个 key：切走就把页面销毁，
                // 草稿跟着没了（用户报过「切个 tab 回来字没了」）。
                // 代价：Tab 之间没有转场动画 —— 手机端 Tab 切换本来也不需要，
                // 动效统一放到 UI 阶段再定。
                child: IndexedStack(index: _tab, children: _pages()),
              ),
            ),
            // 底部停靠区。会话页 = 常驻细把手 + 可收展的导航栏；
            // 开始 / 设置页 = 导航栏常驻（否则用户切不回来）。
            _NavDock(
              tab: _tab,
              alwaysShowBar: _tab != 1,
              onChanged: (i) {
                // 切到会话页时按「默认收起」复位：hidden 是全局的，用户可能在
                // 别的页面把导航栏上滑唤出过，不复位的话「会话页默认全屏」
                // 只在冷启动那一次成立（实测）。
                if (i == 1) NavBarVisibility.hide();
                setState(() => _tab = i);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 前后台切换：退后台记时间，回前台补连接 + 补消息 + 告诉用户离开了多久。
  ///
  /// Android 的现实（写清楚，别装作没有）：
  ///   · 普通 App 退到后台会被「冻结」（Doze/App Standby），网络与定时器可能被掐；
  ///   · 想让长任务在后台真的继续跑，必须有**前台服务**（通知栏常驻）——
  ///     那需要一个原生插件，放在任务⑪（通知）里做；
  ///   · 所以这一版保证的是：**回来不用手动重连、消息自动补齐、说话算数**。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final store = _serverStore;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        store.markPaused();
      case AppLifecycleState.resumed:
        store.resumeSync();
        // 点通知进来的那次冷启动：把会话 id 取走并直达
        NotificationCenter.instance.handleResume();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// 页面切换：进入的那一页淡入 + 轻微上移；离开的只淡出（位置不动）。
  ///
  /// 为什么位移只给「进入」：两边都给位移会让两页朝相反方向擦肩而过，
  /// 视觉上像翻卡片而不是切页面；只动进入的那一页，读起来是「新页面浮上来」。
  ///
  /// 注：这个方法是清理 SSH/RPC 遗留代码时被误删后重建的 —— 它原本夹在
  /// 一层不再使用的会话列表 widget 后面，删那段时被一起带走，靠
  /// `flutter analyze` 的 "The method '_buildPageTransition' isn't defined" 抓出来。
  Widget _buildPageTransition({
    required Widget child,
    required Animation<double> animation,
    required bool incoming,
    required double motionScale,
  }) {
    if (!incoming) return FadeTransition(opacity: animation, child: child);
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, 0.012 * motionScale),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  List<Widget> _pages() => [
        ServerSessionsPage(
          store: _serverStore,
          onOpenSession: (session) {
            _serverStore.openSession(session.id);
            setState(() => _tab = 1);
          },
          onOpenConn: _openConnScreen,
          onOpenChat: () => setState(() => _tab = 1),
        ),
        ServerChatPage(
          store: _serverStore,
          onOpenSessions: () => setState(() => _tab = 0),
        ),
        ServerSettingsPage(
          store: _serverStore,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
          onOpenConn: _openConnScreen,
        ),
      ];
}
/// 底部停靠区：常驻细把手 + 可收展的导航栏。
///
/// 布局自上而下是「页面 → [导航栏] → 把手」。把手永远贴屏底，因为上滑手势的
/// 起点必须在屏幕最底边 —— 那才是手指的自然落点；把手放到导航栏上面，
/// 展开时它会被推到屏幕中部，手势就还得先找位置。
///
/// **为什么收起时保留把手而不是留 0 高度**：契约要求「可发现的恢复方式，不止手势」。
/// 一条看得见的把手既是手势提示，本身也是可点目标（`onTap` 直接切换）。
class _NavDock extends StatelessWidget {
  const _NavDock({
    required this.tab,
    required this.onChanged,
    required this.alwaysShowBar,
  });

  final int tab;
  final ValueChanged<int> onChanged;

  /// true = 导航栏不参与收展，常驻显示（开始页 / 设置页）。
  final bool alwaysShowBar;

  /// 把手的布局高度。视觉上只有中间一条 4dp 细线，其余是留白 ——
  /// 留白不是浪费：指腹约 45–50dp 宽、按下去还会盖住周围，只有细线本身
  /// 可点的话命中率很低。24dp 是「不额外吃消息区」与「按得到」的折中。
  static const double handleHeight = 24;

  /// 上滑多少逻辑像素算一次「唤出」。12dp 的取值理由：手指按下时的自然抖动
  /// 约 3–8dp，取 12 能滤掉误触；同时又短于任何一次刻意的上滑动作。
  static const double swipeThreshold = 12;

  @override
  Widget build(BuildContext context) {
    // 系统手势条高度：Android 手势导航约 24dp，虚拟三键则为 0。
    // 取较大值意味着把手画在「本来就不能放内容」的那块系统区域里，
    // 于 87% 这个数字里并没有真的扣掉 24dp。
    final inset = MediaQuery.of(context).padding.bottom;
    final handleH = inset > handleHeight ? inset : handleHeight;

    return ListenableBuilder(
      listenable: NavBarVisibility.hidden,
      builder: (context, _) {
        final open = alwaysShowBar || !NavBarVisibility.hidden.value;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 导航栏从底部「长出来」：AnimatedSize 动画的是高度，页面被平滑
            // 推上去而不是跳变（早先用 AnimatedSwitcher 整块换 widget，高度
            // 瞬间变化 → 消息区闪一下）。
            AnimatedSize(
              duration: NeuMotion.struct,
              curve: NeuMotion.spring,
              alignment: Alignment.bottomCenter,
              child: open
                  ? _NeuTabBar(
                      index: tab,
                      onChanged: onChanged,
                      // 会话页展开时把手已经占了底部安全区，这里不能再加一次，
                      // 否则导航栏会离屏底多出 24dp 的空隙。
                      bottomInset: alwaysShowBar ? inset : 0,
                    )
                  : const SizedBox(width: double.infinity),
            ),
            // 把手只在会话页出现（其它页面导航栏常驻，用不着唤出）。
            // 外面再包一层 AnimatedSize：切页时把手的出现/消失也是滑入滑出，
            // 不然页面高度会瞬变 24dp。
            AnimatedSize(
              duration: NeuMotion.struct,
              curve: NeuMotion.spring,
              alignment: Alignment.topCenter,
              child: alwaysShowBar
                  ? const SizedBox(width: double.infinity)
                  : _NavHandle(
                      height: handleH,
                      open: open,
                      onTap: NavBarVisibility.toggle,
                      onSwipeUp: NavBarVisibility.show,
                      onSwipeDown: NavBarVisibility.hide,
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// 屏幕底部的常驻细把手：点一下切换导航栏，上滑唤出、下滑收起。
///
/// 三种方式并存是故意的：上滑最快、符合手机肌肉记忆；点击不需要任何手势知识，
/// 是「用户不知道能划」时的兜底。
class _NavHandle extends StatefulWidget {
  const _NavHandle({
    required this.height,
    required this.open,
    required this.onTap,
    required this.onSwipeUp,
    required this.onSwipeDown,
  });

  /// 布局高度（含留白），由 `_NavDock` 按底部安全区算好传给这里。
  final double height;

  /// 导航栏当前是否展开 —— 只影响把手颜色与宽度（展开时加深、缩短，
  /// 提示「现在可以往下滑收回去」）。
  final bool open;

  final VoidCallback onTap;
  final VoidCallback onSwipeUp;
  final VoidCallback onSwipeDown;

  /// 那条细线的宽度与粗细
  static const double gripWidth = 40;
  static const double gripThickness = 4;

  @override
  State<_NavHandle> createState() => _NavHandleState();
}

class _NavHandleState extends State<_NavHandle> {
  /// 本次手势累计的纵向位移（负 = 上滑）。
  ///
  /// 按**累计距离**而不是末帧速度判断方向：慢速拖动（意图明确、但手指不快）
  /// 末帧速度接近 0，只看速度会漏掉。
  double _dragDy = 0;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return GestureDetector(
      key: navBarHandleKey,
      // opaque：让整块 24dp 都是命中区，而不是只有中间那条 4dp 的线
      behavior: HitTestBehavior.opaque,
      // 位移从**按下点**算起。默认的 DragStartBehavior.start 会把启动手势所需的
      // 18dp touch slop 从 delta 里减掉 —— 用户明明划了 30dp，上报的只有 12dp，
      // 刚好卡在阈值边缘。真实意图应该看手指总共移动了多少。
      dragStartBehavior: DragStartBehavior.down,
      onTap: widget.onTap,
      onVerticalDragStart: (_) => _dragDy = 0,
      onVerticalDragUpdate: (d) => _dragDy += d.delta.dy,
      onVerticalDragEnd: (_) {
        if (_dragDy <= -_NavDock.swipeThreshold) {
          widget.onSwipeUp();
        } else if (_dragDy >= _NavDock.swipeThreshold) {
          widget.onSwipeDown();
        }
        _dragDy = 0;
      },
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Center(
          child: AnimatedContainer(
            duration: NeuMotion.micro,
            width: widget.open ? 32 : _NavHandle.gripWidth,
            height: _NavHandle.gripThickness,
            decoration: BoxDecoration(
              // 展开时加深：既是状态提示，也在暗示「这块现在能下滑关闭」。
              // 两个值都留在 0.55 以下 —— 把手是「存在感低但找得到」的东西，
              // 不该抢消息内容的注意力。
              color: t.muted.withValues(alpha: widget.open ? 0.55 : 0.35),
              borderRadius: BorderRadius.circular(_NavHandle.gripThickness / 2),
            ),
          ),
        ),
      ),
    );
  }
}

class _NeuTabBar extends StatelessWidget {
  const _NeuTabBar({
    required this.index,
    required this.onChanged,
    this.bottomInset = 0,
  });

  final int index;
  final ValueChanged<int> onChanged;

  /// 底部安全区高度（系统手势条）。
  ///
  /// 由调用方传入、而不是在这里读 MediaQuery：会话页展开导航栏时，把手已经
  /// 吃掉了那块底部空间（见 `_NavDock`），这里再加一次会重复留白。
  final double bottomInset;

  /// Tab 文案走语言包：切语言时整条栏一起变
  List<(IconId, String)> _tabs(BuildContext context) => [
        (IconId.home, I18n.t('tab.start', context: context)),
        (IconId.bubble, I18n.t('tab.chat', context: context)),
        (IconId.gear, I18n.t('tab.settings', context: context)),
      ];

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final tabs = _tabs(context);
    return NeuRaised(
      radius: NeuRadii.lg,
      level: NeuLevel.large,
      // 底部外边距 11 -> 6：导航栏常驻，竖向每一像素都是从消息区里扣的
      margin: EdgeInsets.fromLTRB(NeuSpace.n18, 0, NeuSpace.n18, NeuSpace.n6 + bottomInset),
      padding: const EdgeInsets.all(NeuSpace.n6),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            // 设计稿 .tabbar 有 gap:5px
            if (i > 0) const SizedBox(width: NeuSpace.n5),
            Expanded(
              child: NeuPressable(
                radius: NeuRadii.md,
                // 撑满那一格：设计稿的 .tab { min-height:50px }
                // 垂直 10 -> 8：Tab 高 50 -> 46，仍 >= 40dp 触控底线
                padding: const EdgeInsets.symmetric(vertical: NeuSpace.n8),
                // 未选中必须 flat：设计稿里 .tab 背景透明，
                // 只有 .tab.active 才有内凹。都给材质的话三块都凸着，
                // 反而看不出当前在哪一项，也不像「填满」
                flat: i != index,
                alwaysInset: i == index,
                onTap: () => onChanged(i),
                child: SizedBox(
                  // 必须显式撑满：NeuPressable 内部用 Stack 居中（松约束），
                  // 不包一层的话内凹块会缩到图标宽度，而不是占满这一格
                  width: double.infinity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      NeuIcon(
                        tabs[i].$1,
                        size: 22,
                        color: i == index ? t.accentInk : t.muted,
                      ),
                      const SizedBox(height: NeuSpace.n3),
                      Text(
                        tabs[i].$2,
                        style: TextStyle(
                          fontSize: NeuFonts.badge,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                          color: i == index ? t.accentInk : t.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 启动遮罩（App 内这一层）。
///
/// Android 12+ 的启动画面由系统的 SplashScreen API 接管，只显示「薄荷底 + 图标」——
/// 提供的完整遮罩图（渐变底 + 徽章 + "Pi Agent"）在 12+ 上永远不会露脸。
/// 所以这里再叠同一张图：首帧后停一拍、淡出，把画面交给 App。
///
/// 能和 Android 11 及以下的**原生**遮罩无缝衔接，是因为两者用同一张图、
/// 同样按 BoxFit.fill 拉伸：交接时位置完全对齐，看不出接缝。
class _SplashOverlay extends StatefulWidget {
  const _SplashOverlay({required this.onDone});

  final VoidCallback onDone;

  @override
  State<_SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<_SplashOverlay>
    with TickerProviderStateMixin {
  // 在 initState 里显式创建，不用 late 惰性初始化 ——
  // 否则若某次没走到 build，dispose 里访问它反而会现场建一个 ticker。
  late final AnimationController _c;

  /// 遮罩图的淡入进度（0 → 1）。
  /// 系统启动画面是「纯色底 + 图标」，而遮罩图自带渐变底，直接硬切会看到
  /// 背景忽然一暗。先把同色纯色打底、再让图片淡入，背景的变化就从「跳变」
  /// 变成了「浮现」，也不影响用哪张图。
  late final AnimationController _fadeIn;

  /// 是否已经开始退场（防止帧回调与兜底定时器重复触发）
  bool _exiting = false;
  Timer? _fallback;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      // 退场比进场慢：进来要快（别让人等），出去要缓（别闪一下）
      duration: const Duration(milliseconds: 420),
      value: 1,
    );
    _fadeIn = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..forward();
    // 关键：等「首帧真的画到屏幕上」才开始倒计时。
    // 在软件渲染或慢设备上，首帧的**构建**与**呈现**之间可能差好几秒；
    // 若从构建就开始计时，遮罩会在系统启动画面还没让开时就退完 ——
    // 结果就是「遮罩明明写了，却从来没被看见」。
    WidgetsBinding.instance.addTimingsCallback(_onFirstFrameTiming);
    // 兜底：万一帧时序回调不来，也不能把遮罩永远糊在屏幕上
    _fallback = Timer(const Duration(seconds: 6), _startExit);
  }

  /// 帧时序回调是否已经摘掉。
  /// 摘过再摘会触发 Flutter 的断言（debug 下实测报错），所以要记住。
  bool _timingsDetached = false;

  void _onFirstFrameTiming(List<FrameTiming> timings) {
    if (_exiting) return;
    if (!_timingsDetached) {
      _timingsDetached = true;
      WidgetsBinding.instance.removeTimingsCallback(_onFirstFrameTiming);
    }
    _fallback?.cancel();
    // 停一拍再退：刚出首帧就消失会像闪了一下，反而显得脏
    _fallback = Timer(const Duration(milliseconds: 700), _startExit);
  }

  void _startExit() {
    if (_exiting || !mounted) return;
    _exiting = true;
    _fallback?.cancel();
    _c.reverse().then((_) {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    if (!_timingsDetached) {
      _timingsDetached = true;
      WidgetsBinding.instance.removeTimingsCallback(_onFirstFrameTiming);
    }
    _fallback?.cancel();
    _c.dispose();
    _fadeIn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _c,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 与 Android 的 @color/splash_background 同色：
            // 从系统启动画面切过来时，这一屏背景是连续不动的。
            const ColoredBox(color: Color(0xFFE1FBF4)),
            // 还是原来那张 assets/splash.png，只是改成淡入。
            // fit 用 cover 而不是 fill：fill 会在 20:9 这类长屏上把等比的原图
            // 横向压窄，星球会被拉成竖椭圆。
            FadeTransition(
              opacity: CurvedAnimation(parent: _fadeIn, curve: Curves.easeOut),
              child: Image.asset('assets/splash.png', fit: BoxFit.cover),
            ),
          ],
        ),
      );
}
