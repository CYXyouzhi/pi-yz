/// 终端按键编码工具。
///
/// 手机软键盘发不出 Esc / Ctrl / Tab / 方向键，必须由 App 合成转义序列。
/// 这里集中处理三类编码，避免散落在 UI 代码里出错：
///
/// 1. **普通字符** —— 原样发送
/// 2. **特殊键**（方向键 / PageUp / Home…）—— CSI 序列，带修饰符参数
/// 3. **修饰键组合** —— 传统控制字符（Ctrl+A → 0x01）优先，
///    需要区分 Shift/Ctrl 的少数键用 CSI-u（Kitty 键盘协议）
///
/// 修饰符位掩码遵循 xterm 规范：`1 + shift*1 + alt*2 + ctrl*4`，
/// 即无修饰为 1、Shift 为 2、Alt 为 3、Ctrl 为 5、Ctrl+Shift 为 6。
class KeyEncoder {
  KeyEncoder._();

  // ---- 基础按键 ----
  static const String esc = '\x1b';
  static const String tab = '\t';
  static const String shiftTab = '\x1b[Z';
  static const String enter = '\r';
  static const String backspace = '\x7f';
  static const String delete = '\x1b[3~';
  static const String insert = '\x1b[2~';

  /// 计算 CSI 修饰符参数。
  static int _mod({bool shift = false, bool alt = false, bool ctrl = false}) =>
      1 + (shift ? 1 : 0) + (alt ? 2 : 0) + (ctrl ? 4 : 0);

  // ---- 光标键 ----
  // 无修饰用短形式（\x1b[A），有修饰用带参形式（\x1b[1;5A）
  static String up({bool shift = false, bool alt = false, bool ctrl = false}) =>
      _cursor('A', shift: shift, alt: alt, ctrl: ctrl);
  static String down({bool shift = false, bool alt = false, bool ctrl = false}) =>
      _cursor('B', shift: shift, alt: alt, ctrl: ctrl);
  static String right({bool shift = false, bool alt = false, bool ctrl = false}) =>
      _cursor('C', shift: shift, alt: alt, ctrl: ctrl);
  static String left({bool shift = false, bool alt = false, bool ctrl = false}) =>
      _cursor('D', shift: shift, alt: alt, ctrl: ctrl);

  static String _cursor(String finalByte,
      {bool shift = false, bool alt = false, bool ctrl = false}) {
    final m = _mod(shift: shift, alt: alt, ctrl: ctrl);
    return m == 1 ? '\x1b[$finalByte' : '\x1b[1;$m$finalByte';
  }

  static String home({bool shift = false, bool alt = false, bool ctrl = false}) {
    final m = _mod(shift: shift, alt: alt, ctrl: ctrl);
    return m == 1 ? '\x1b[H' : '\x1b[1;${m}H';
  }

  static String end({bool shift = false, bool alt = false, bool ctrl = false}) {
    final m = _mod(shift: shift, alt: alt, ctrl: ctrl);
    return m == 1 ? '\x1b[F' : '\x1b[1;${m}F';
  }

  /// PageUp / PageDown —— pi 在 fullscreen 模式下用它们翻 transcript 整页。
  static String pageUp({bool shift = false, bool alt = false, bool ctrl = false}) =>
      _tilde(5, shift: shift, alt: alt, ctrl: ctrl);

  static String pageDown({bool shift = false, bool alt = false, bool ctrl = false}) =>
      _tilde(6, shift: shift, alt: alt, ctrl: ctrl);

  static String _tilde(int code,
      {bool shift = false, bool alt = false, bool ctrl = false}) {
    final m = _mod(shift: shift, alt: alt, ctrl: ctrl);
    return m == 1 ? '\x1b[$code~' : '\x1b[$code;$m~';
  }

  // ---- 功能键 ----
  static String f(int n, {bool shift = false, bool alt = false, bool ctrl = false}) {
    final m = _mod(shift: shift, alt: alt, ctrl: ctrl);
    // F1-F4 用 SS3（\x1bOP），F5 起用 CSI
    if (n >= 1 && n <= 4) {
      const bytes = ['P', 'Q', 'R', 'S'];
      return m == 1 ? '\x1bO${bytes[n - 1]}' : '\x1b[1;$m${bytes[n - 1]}';
    }
    const codes = [15, 17, 18, 19, 20, 21, 23, 24];
    final code = codes[n - 5];
    return m == 1 ? '\x1b[$code~' : '\x1b[$code;$m~';
  }

  // ---- 修饰键组合 ----

  /// Ctrl + 字母的传统控制字符编码：Ctrl+A → 0x01 … Ctrl+Z → 0x1A。
  ///
  /// 这是最兼容的做法，所有终端和 TUI 都认。
  static String? ctrlLetter(String letter) {
    if (letter.length != 1) return null;
    final c = letter.toLowerCase().codeUnitAt(0);
    if (c < 0x61 || c > 0x7a) return null;
    return String.fromCharCode(c - 0x60);
  }

  /// CSI-u（Kitty 键盘协议）编码：`CSI unicode-key-code ; modifiers u`。
  ///
  /// 用于必须区分修饰键的场景 —— 最典型的是 `Shift+Enter`（插入换行，
  /// 区别于 `Enter` 的提交）。pi 会优先按 Kitty 协议解析这类序列。
  static String csiU(int codePoint,
      {bool shift = false, bool alt = false, bool ctrl = false}) {
    final m = _mod(shift: shift, alt: alt, ctrl: ctrl);
    return '\x1b[$codePoint;${m}u';
  }

  /// Shift+Enter —— 在 pi 编辑器里插入换行（而不是提交）。
  /// 先尝试 CSI-u；若远端不认，退回传统 `\x1b\r`（alt+enter 风格）。
  static String shiftEnter() => csiU(13, shift: true);

  /// Alt+Enter —— pi 在 Windows/WSL 上把 follow-up 的默认键设为 Ctrl+Q，
  /// 这里保留标准 alt+enter 编码备用。
  static String altEnter() => csiU(13, alt: true);

  /// 把可打印字符包装成 Ctrl 组合（用于虚拟键栏上直接点的字母）。
  static String withModifiers(String ch,
      {bool shift = false, bool alt = false, bool ctrl = false}) {
    if (ctrl && !alt && !shift) {
      final c = ctrlLetter(ch);
      if (c != null) return c;
    }
    // 其余情况走 CSI-u，让远端自己判断
    if (ctrl || alt || shift) {
      return csiU(ch.codeUnitAt(0), shift: shift, alt: alt, ctrl: ctrl);
    }
    return ch;
  }

  /// 把一个字符的十六进制 dump 出来，便于在日志里排查编码问题。
  static String hexDump(String data) =>
      data.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join(' ');
}
