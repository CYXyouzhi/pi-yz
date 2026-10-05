import 'package:flutter/foundation.dart';

/// 底部导航栏的可见性开关（全局单例）。
///
/// **为什么需要它**：手机竖屏最稀缺的就是竖向空间。底部导航常驻约 70 逻辑高，
/// 而用户读消息、翻列表时并不需要它 —— 收起后消息区从 70% 提到 87%。
///
/// **为什么要改掉早先的接法**（2026-10 用户反馈后重做）：
/// 早先是「输入区塞一个 ⌄ 按钮手动切换 + 滚动时自动收起」，实测两个问题：
///
///   1. **操作顺序反直觉**。想切 Tab 得先低头在输入工具栏里找到那个 ⌄
///      —— 它跟底部导航毫无视觉关联 —— 点一下，再点 Tab。用户原话：「不太好用」。
///   2. **语义撞车**。它紧挨着 ⌘ 键、又在软键盘上方，看起来像「收起键盘」。
///
/// 现在的接法是**屏底常驻细把手**（见 main.dart 的 `_NavDock` / `_NavHandle`）：
/// 手指始终停在屏幕最底部，上滑或点一下就能唤出导航栏 —— 和手机原生底部手势
/// 是同一个操作顺序，不用先找按钮。
///
/// **为什么单独一个文件**（而不是放 main.dart）：放 main.dart 时，
/// chat_page 通过 `import '../../main.dart'` 拿到的实例与 AppShell 监听的不是同一个
/// —— 实测日志显示 `hidden == true` 写入成功、但 `ValueListenableBuilder` 不重建
/// （而把 main.dart 里的初始值直接改成 true 却生效）。抽成独立库保证同一实例。
class NavBarVisibility {
  NavBarVisibility._();

  /// true = 导航栏收起。
  ///
  /// 初值 true = 会话页默认收起（全屏），因为目标是「空闲态消息区 ≥ 87%」。
  /// **只有会话页**会因此隐藏 —— AppShell 里的判定让开始页 / 设置页永远显示
  /// 导航栏（否则用户切不回来）。
  static final ValueNotifier<bool> hidden = ValueNotifier<bool>(true);

  /// 唤出导航栏。触发点：屏底把手上滑，或点击把手。
  static void show() => hidden.value = false;

  /// 收起导航栏。触发点：选中任意 Tab 后、或把手下滑。
  static void hide() => hidden.value = true;

  /// 点击把手（同一个目标上的两种手势：上滑唤出、点一下切回）。
  static void toggle() => hidden.value = !hidden.value;
}

/// 屏底把手的 Key（`main.dart` 的 `_NavHandle` 挂上，widget 测试靠它找到）。
///
/// **为什么给一个私有 widget 暴露 Key**：会话页导航栏默认收起，测试要点底部
/// Tab 就得先把它唤出来。直接改 `NavBarVisibility.hidden` 也能让用例通过，
/// 但那样等于把「把手到底能不能唤出导航栏」这条真实路径排除在测试之外 ——
/// 而这正是本轮改动最需要被守住的东西。
const Key navBarHandleKey = ValueKey<String>('nav-bar-handle');
