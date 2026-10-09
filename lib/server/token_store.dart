// token 的存放处 —— 与「连接配置」分开。
//
// 为什么必须拆开：token 是**唯一一个泄露就等于「别人能操作你的电脑」**的凭据
// （服务端拿到它就能跑命令、读文件）。而它之前跟地址、端口、备注名一起明文躺在
// SharedPreferences 的 `server_profiles_v1` 那个 JSON 里 —— 只要有人能读到 App
// 私有目录（root、`adb backup`、某些"手机清理"工具），token 就直接到手。
//
// 拆成两层之后：
//   · `server_profiles_v1`：只剩地址、端口、名字 —— 泄了也做不了事
//   · 这里：只放 token —— Android 上走 Keystore（密钥住在安全硬件里、导不出来）
//
// 接口是异步的：Keystore 调用要过原生通道。上层 `await` 一下就行，
// 好处是**换实现不用动任何调用方**（这也是这一层存在的理由）。
//
// 回落行为见 [PrefsTokenStore]：桌面与测试环境用它，**不提供硬件级保护** ——
// 这一点在 SECURITY.md 里如实写明，不假装安全。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// token 的读写口。
abstract class TokenStore {
  /// 这个实现是否真的走了系统级保护。
  ///
  /// 界面提示（设置页那行「token 存在哪」）与 SECURITY.md 都据此措辞，
  /// 所以它必须是**事实**，不能乐观返回 true。
  bool get isSecure;

  Future<String?> read(String id);

  /// 返回是否**确实写成功了**。
  ///
  /// 迁移逻辑靠这个返回值决定「能不能把明文抹掉」—— 写失败还继续抹，
  /// 就是把用户的 token 弄丢（他得重新配一遍连接）。所以这里不能说谎。
  Future<bool> write(String id, String token);

  Future<void> delete(String id);
}

/// 回落实现：桌面与测试环境用（没有 Keystore 可用）。
///
/// 刻意与 profile 的 JSON **分开存**：这样「连接配置泄露」不再等于
/// 「token 泄露」。但要说清楚它保护不了什么 —— 它仍然是明文，
/// 有读权限的人照样能拿到。
class PrefsTokenStore implements TokenStore {
  /// 独立键前缀：与 `server_profiles_v1` 互不干扰，也方便在真机上用 adb 核对
  static const keyPrefix = 'server_token_v1_';

  @override
  bool get isSecure => false;

  @override
  Future<String?> read(String id) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$keyPrefix$id');
  }

  @override
  Future<bool> write(String id, String token) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.setString('$keyPrefix$id', token);
  }

  @override
  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$keyPrefix$id');
  }
}

/// 与原生侧共用的通道（原生实现见 android/.../MainActivity.kt 的 secure* 分支）
const MethodChannel _channel = MethodChannel('pi_yz/native');

/// Android 上的安全实现：token 先经 Keystore 里的 AES 密钥加密，再落盘。
///
/// 密钥本体**不可导出**（住在系统里，部分设备还有硬件背书），所以即使拿到设备上
/// 的文件也解不开 —— 具体机制与四处理由见 android/.../SecureTokenStore.kt 的注释。
class KeystoreTokenStore implements TokenStore {
  @override
  bool get isSecure => true;

  @override
  Future<String?> read(String id) async {
    if (id.isEmpty) return null;
    try {
      return await _channel.invokeMethod<String>('secureGet', {'id': id});
    } on MissingPluginException {
      return null; // 原生没注册（测试/桌面跑法）
    } on PlatformException {
      // 解不开就当读不到：换机、清数据、Keystore 被系统重置都会这样。
      // 上层会请用户重新输入 token，而不是崩在启动路径上。
      return null;
    }
  }

  @override
  Future<bool> write(String id, String token) async {
    if (id.isEmpty || token.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('securePut', {
            'id': id,
            'token': token,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> delete(String id) async {
    if (id.isEmpty) return;
    try {
      await _channel.invokeMethod<bool>('secureRemove', {'id': id});
    } on MissingPluginException {
      // 没得删就算了
    } on PlatformException {
      // 同上
    }
  }
}

/// 挑一个当前环境**真能用**的实现。
///
/// 只有 Android 且 Keystore 可用时才走安全实现；其余情况（桌面、测试、
/// Android 5.x 这种没有 Keystore AES 的）回落到本地存储 ——
/// 并且这个事实会如实反映在 `isSecure` 上（界面提示与 SECURITY.md 靠它措辞）。
Future<TokenStore> resolveTokenStore() async {
  if (!Platform.isAndroid) return PrefsTokenStore();
  try {
    final ok = await _channel.invokeMethod<bool>('secureAvailable');
    if (ok == true) return KeystoreTokenStore();
  } on MissingPluginException {
    // 原生侧没注册（例如跑在 Dart 测试里）→ 回落
  } on PlatformException {
    // 同上
  }
  return PrefsTokenStore();
}
