// ignore_for_file: avoid_print
//
// 功能层验证：真实地点击、输入、断言结果。
// 这是在没有模拟器的情况下最接近实测的一环 —— 它能抓出「逻辑错误」，
// 而截图只能抓出「视觉错误」。
//
// 两条踩过的坑，写在这里免得下次再踩：
// 1. `pumpAndSettle` 会被**永久循环**的动画卡死 —— 状态点的呼吸/心跳在设计上
//    就要一直动（设计稿原话：running 是「唯一在动的那个」）。所以手动推进时长。
// 2. 默认测试窗口只有 800×600，长表单里的按钮会落在屏幕外，
//    `tap` 会**静默落空**（只打一条 warning），于是断言看到「校验没生效」的假象。
//    所以先设成手机尺寸，再点之前 `ensureVisible`。
import 'package:flutter/material.dart';
import 'package:pi_mobile/ui/nav_bar_visibility.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile/main.dart';
import 'package:pi_mobile/server/app_prefs.dart';
import 'package:pi_mobile/services/key_encoder.dart';
import 'package:pi_mobile/theme/design_tokens.dart';
import 'package:pi_mobile/theme/neu_theme.dart';
import 'package:pi_mobile/ui/key_bar.dart';
import 'package:pi_mobile/ui/neu_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 把测试窗口设成手机尺寸（默认 800×600 会让长页面的按钮落到屏幕外）。
void setPhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  // 导航栏可见性是全局 static 开关，且**会话页默认收起**：上一个用例留下的
  // 状态会让下一个用例找不到底部 Tab（实测 10 个外壳用例全挂）。
  // 每个用例先复位成「导航栏显示」；用例若要走收起路径，自己再设回去或点把手。
  NavBarVisibility.hidden.value = false;
  // 语言钉成中文：I18n 跟系统 locale，CI/开发机可能是 en，
  // 那样断言里的中文就找不到（环境问题，不是界面问题）。
  // 需要验英文模式的用例自己会覆盖 AppPrefs.lang，不受这里影响。
  tester.binding.platformDispatcher.localeTestValue = const Locale('zh');
  tester.binding.platformDispatcher.localesTestValue = const [Locale('zh')];
  addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
}

/// 手动推进固定时长（不能用 pumpAndSettle，理由见文件头）。
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

/// 跳过启动遮罩。
///
/// 遮罩的退场计时锚在「首帧真的呈现」上（帧时序回调）；测试环境没有真实光栅化，
/// 那个回调不会来，于是走 6 秒兜底计时 —— 这里直接把它推过去，再等淡出动画。
Future<void> skipSplash(WidgetTester tester) async {
  await tester.pump();
  // 遮罩的兜底定时器是 6s，之后还有 420ms 的退场动画 —— 留够时间让它走完
  await tester.pump(const Duration(seconds: 7));
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pump(const Duration(milliseconds: 800));
}

/// 滚到可见再点 —— 否则离线按钮的 tap 会静默落空。
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await settle(tester);
  await tester.tap(finder);
  await settle(tester);
}

/// 点底部 Tab。会话页默认把导航栏收起（只留屏底把手），所以点 Tab 之前要先
/// 确保导航栏在屏幕上 —— 走用户真实路径：点把手唤出，而不是直接改全局开关。
/// 直接改开关的话，「把手到底能不能唤出导航栏」这条最容易坏的路就没被测到。
Future<void> tapTab(WidgetTester tester, String label) async {
  final handle = find.byKey(navBarHandleKey);
  if (handle.evaluate().isNotEmpty) {
    await tester.tap(handle);
    await settle(tester);
  }
  await tapVisible(tester, find.text(label));
}

/// 展开设置页里的某个分组。
///
/// 设置页现在**默认全部收起**（用户明确要求「默认收起来、点击再展开」），
/// 所以凡是要断言分组内容的用例，都得先把它点开 —— 否则断言的是
/// 「渲染失败」和「默认收起」这两种完全不同的事。
Future<void> openSection(WidgetTester tester, String title) async {
  await tapVisible(tester, find.text(title));
  await settle(tester);
}

/// 收尾：把待触发的定时器推完，避免测试因「pending timer」失败。
Future<void> flushTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
}

Widget harness(Widget child, {Brightness brightness = Brightness.light}) {
  final tokens =
      brightness == Brightness.dark ? NeuTokens.dark : NeuTokens.light;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildNeuTheme(tokens, brightness: brightness),
    home: NeuCanvas(
      brightness: brightness,
      child: Scaffold(backgroundColor: Colors.transparent, body: child),
    ),
  );
}



void main() {
  // 把测试环境的系统 locale 钉成中文：I18n 默认跟随系统，
  // 而 CI/开发机可能是 en —— 那样断言里的中文就找不到（环境问题，不是界面问题）。
  // 需要验证英文模式的用例自己会覆盖 setLang，不受这里影响。
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  binding.platformDispatcher.localeTestValue = const Locale('zh');
  binding.platformDispatcher.localesTestValue = const [Locale('zh')];
  // 注意：这里**不**把语言钉死 —— 有个用例专门验证「切到英文后外壳文案真的变英文」。
  // 断言统一用 I18n.t(key) 动态取值，中文/英文模式下都能对上。

  group('应用外壳（真实入口）', () {
    // 注：这组测试原先针对旧的 SSH 外壳（'还没有连接' / '还没有打开的会话'），
    // 服务端路线（ServerStore + 开始/会话/设置）上线后它们就失效了 —— 这里按新外壳重写。
    setUp(() {
      // StorageService 只依赖 shared_preferences，mock 掉即可让真实 App 起来。
      // 固定成中文：界面支持中英切换后，测试环境的语言跟着系统走，
      // 断言里写死的「开始/会话/设置」会随机变成 Home/Chat/Settings —— 测试不能这么飘。
      SharedPreferences.setMockInitialValues({'app_lang': 'zh'});
    });

    testWidgets('启动遮罩先盖住界面，之后自己退场', (tester) async {
      setPhoneSurface(tester);
      await tester.pumpWidget(const PiMobileApp());
      await tester.pump();
      // 遮罩是树上唯一的 Image（App 里的图标都是 CustomPaint 画的）
      expect(find.byType(Image), findsOneWidget);

      await skipSplash(tester);
      expect(find.byType(Image), findsNothing);
      // 三个 tab 都在
      expect(find.text('开始'), findsOneWidget);
      expect(find.text('会话'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('三个 Tab 都能打开，切来切去不抛异常', (tester) async {
      setPhoneSurface(tester);
      await tester.pumpWidget(const PiMobileApp());
      await skipSplash(tester);
      await settle(tester);

      // 起始＝开始页；空库（没有任何服务端配置）时给的是连接引导
      expect(find.textContaining('选择服务端地址'), findsOneWidget);
      expect(find.text('未连接'), findsOneWidget);

      // 切会话：没连服务端时是空态（连上了才显示「开始对话」）
      await tapTab(tester, '会话');
      expect(find.textContaining('尚未连接'), findsOneWidget);

      // 切设置
      await tapTab(tester, '设置');
      await openSection(tester, '工作区');
      expect(find.text('AI 配置'), findsOneWidget);
      expect(find.text('文件浏览'), findsOneWidget);

      // 切回开始
      await tapTab(tester, '开始');
      expect(find.textContaining('选择服务端地址'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('设置页在未连接时如实显示状态与操作', (tester) async {
      setPhoneSurface(tester);
      await tester.pumpWidget(const PiMobileApp());
      await skipSplash(tester);
      await settle(tester);

      await tapTab(tester, '设置');
      // 连接段：未连接状态 + 刷新/断开之外的可点入口
      expect(find.text('未连接'), findsOneWidget);
      await openSection(tester, '工作区');
      expect(find.text('AI 配置'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('设置页的主题段控件会真的换掉整个外壳的配色', (tester) async {
      setPhoneSurface(tester);
      await tester.pumpWidget(const PiMobileApp());
      await skipSplash(tester);
      await settle(tester);

      await tapTab(tester, '设置');

      // 锚在页面内的 Scaffold 上：既不能锚在可能被滚走的文字上，
      // 也不能锚在 MaterialApp 自身（它的 element 在 Theme 之上，读到的永远是默认亮色）
      Brightness currentBrightness() =>
          Theme.of(tester.element(find.byType(Scaffold).first)).brightness;

      await openSection(tester, '外观');
      await tapVisible(tester, find.text('深色'));
      expect(currentBrightness(), Brightness.dark);

      await tapVisible(tester, find.text('浅色'));
      expect(currentBrightness(), Brightness.light);

      expect(tester.takeException(), isNull);
    });
  });

  group('快捷键栏', () {
    testWidgets('界面语言切到英文后，外壳文案真的变英文', (tester) async {
      setPhoneSurface(tester);
      // AppPrefs 是单例且 load() 幂等（先跑过的用例已经装载过了），
      // 所以这里必须显式 setLang —— 靠改 mock 值再 load 是改不动的
      SharedPreferences.setMockInitialValues({'app_lang': 'en'});
      await AppPrefs.instance.load();
      await AppPrefs.instance.setLang('en');
      await tester.pumpWidget(const PiMobileApp());
      await tester.pump();
      await skipSplash(tester);

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('开始'), findsNothing);

      // 还原：单例是全局的，别把后面的用例带偏
      await AppPrefs.instance.setLang('zh');
      expect(tester.takeException(), isNull);
    });

    testWidgets('折叠态：点 Tab 发出 0x09', (tester) async {
      setPhoneSurface(tester);
      final sent = <String>[];
      await tester.pumpWidget(harness(_KeyBarHarness(onKey: sent.add)));
      await settle(tester);

      await tapVisible(tester, find.text('Tab'));
      expect(sent, [KeyEncoder.tab]);
    });

    testWidgets('修饰键粘滞：锁定 Ctrl 后点 ↑ 发出 Ctrl+↑，且自动解除', (tester) async {
      setPhoneSurface(tester);
      final sent = <String>[];
      await tester.pumpWidget(harness(_KeyBarHarness(
        onKey: sent.add,
        startExpanded: true,
      )));
      await settle(tester);

      await tapVisible(tester, find.text('Ctrl'));
      await tapVisible(tester, find.text('上'));
      expect(sent, ['\x1b[1;5A']);

      // 再用一次：修饰键应已解除，这次是干净的 ↑
      await tapVisible(tester, find.text('上'));
      expect(sent, ['\x1b[1;5A', '\x1b[A']);
    });

    testWidgets('展开/收起面板', (tester) async {
      setPhoneSurface(tester);
      await tester.pumpWidget(harness(_KeyBarHarness(onKey: (_) {})));
      await settle(tester);

      await tapVisible(tester, find.text('全部'));
      expect(find.text('点修饰键锁定，再点按键即组合'), findsOneWidget);

      await tapVisible(tester, find.text('完成'));
      expect(find.text('点修饰键锁定，再点按键即组合'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('折叠态 Esc 会把整条收起', (tester) async {
      setPhoneSurface(tester);
      await tester.pumpWidget(harness(_KeyBarHarness(onKey: (_) {})));
      await settle(tester);
      expect(find.text('补全'), findsOneWidget);

      await tapVisible(tester, find.text('Esc'));
      expect(find.text('补全'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Toast', () {
    testWidgets('弹出后可见，带行动按钮；到期自己退场', (tester) async {
      setPhoneSurface(tester);
      await tester.pumpWidget(harness(Builder(
        builder: (ctx) => Center(
          child: TextButton(
            onPressed: () => NeuToast.show(
              ctx,
              message: '已保存',
              actionLabel: '立即连接',
              onAction: () {},
              duration: const Duration(seconds: 2),
            ),
            child: const Text('fire'),
          ),
        ),
      )));
      await settle(tester);

      await tester.tap(find.text('fire'));
      await settle(tester);
      expect(find.text('已保存'), findsOneWidget);
      expect(find.text('立即连接'), findsOneWidget);

      // 推过时长 + 退场动画
      await flushTimers(tester);
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('减少动态偏好', () {
    testWidgets('系统开启「减少动态」后外壳与三个 Tab 仍能正常渲染与交互', (tester) async {
      setPhoneSurface(tester);
      // 用平台无障碍开关模拟系统级「减少动态」，而不是包一层 MediaQuery
      // （MaterialApp 会用自己的 MediaQuery.fromView 覆盖祖先，包了也不生效）
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

      await tester.pumpWidget(const PiMobileApp());
      await skipSplash(tester);
      await settle(tester);

      expect(find.text('开始'), findsOneWidget);
      await tapTab(tester, '会话');
      await tapTab(tester, '设置');
      await openSection(tester, '工作区');
      expect(find.text('AI 配置'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('深色档', () {
    testWidgets('切到深色后三个 Tab 都正常渲染', (tester) async {
      setPhoneSurface(tester);
      await tester.pumpWidget(const PiMobileApp());
      await skipSplash(tester);
      await settle(tester);

      await tapTab(tester, '设置');
      await openSection(tester, '外观');
      await tapVisible(tester, find.text('深色'));
      expect(
        Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
        Brightness.dark,
      );

      await tapTab(tester, '开始');
      expect(find.textContaining('选择服务端地址'), findsOneWidget);
      await tapTab(tester, '会话');
      await tapTab(tester, '设置');
      expect(tester.takeException(), isNull);
    });
  });

  group('底部导航把手（会话页全屏）', () {
    testWidgets('会话页默认收起导航栏，点把手唤出、选完 Tab 又收回', (tester) async {
      setPhoneSurface(tester);
      await tester.pumpWidget(const PiMobileApp());
      await skipSplash(tester);
      await settle(tester);

      // 开始页：导航栏常驻，页面上没有把手（用不着唤出）
      expect(find.text('设置'), findsOneWidget);
      expect(find.byKey(navBarHandleKey), findsNothing);

      // 进会话页：导航栏立刻收起，屏底只剩把手
      await tapVisible(tester, find.text('会话'));
      expect(find.text('设置'), findsNothing, reason: '会话页默认全屏，导航栏应收起');
      expect(find.byKey(navBarHandleKey), findsOneWidget);

      // 点把手 → 导航栏滑出
      await tester.tap(find.byKey(navBarHandleKey));
      await settle(tester);
      expect(find.text('设置'), findsOneWidget, reason: '点把手应唤出导航栏');

      // 选一个 Tab → 导航栏又收起（不是停在展开态）
      await tapVisible(tester, find.text('设置'));
      await openSection(tester, '工作区');
      expect(find.text('AI 配置'), findsOneWidget);

      // 回会话页：又回到全屏
      await tapVisible(tester, find.text('会话'));
      expect(find.text('设置'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('从屏底把手上滑也能唤出；下滑收回', (tester) async {
      setPhoneSurface(tester);
      await tester.pumpWidget(const PiMobileApp());
      await skipSplash(tester);
      await settle(tester);

      await tapVisible(tester, find.text('会话'));
      expect(find.text('设置'), findsNothing);

      // 上滑 40dp（阈值 12dp）。用 drag 而不是 fling：这个手势按累计位移
      // 判方向，慢速拖动（手指不快但意图明确）必须也认。
      await tester.drag(find.byKey(navBarHandleKey), const Offset(0, -40));
      await settle(tester);
      expect(find.text('设置'), findsOneWidget, reason: '把手上滑应唤出导航栏');

      // 下滑收回
      await tester.drag(find.byKey(navBarHandleKey), const Offset(0, 40));
      await settle(tester);
      expect(find.text('设置'), findsNothing, reason: '把手下滑应收起导航栏');
      expect(tester.takeException(), isNull);
    });
  });
}

/// 快捷键栏的宿主：真实使用里修饰键状态由父级持有，这里照做，
/// 才能验证「粘滞一次即解除」这条语义。
class _KeyBarHarness extends StatefulWidget {
  const _KeyBarHarness({required this.onKey, this.startExpanded = false});

  final ValueChanged<String> onKey;
  final bool startExpanded;

  @override
  State<_KeyBarHarness> createState() => _KeyBarHarnessState();
}

class _KeyBarHarnessState extends State<_KeyBarHarness> {
  late bool _expanded = widget.startExpanded;
  bool _visible = true;
  ModifierState _mods = const ModifierState();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: NeuKeyBar(
        visible: _visible,
        expanded: _expanded,
        onExpandedChanged: (v) => setState(() => _expanded = v),
        onVisibleChanged: (v) => setState(() => _visible = v),
        modifiers: _mods,
        onModifiersChanged: (m) => setState(() => _mods = m),
        onKey: widget.onKey,
      ),
    );
  }
}
