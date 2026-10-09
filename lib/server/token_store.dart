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
