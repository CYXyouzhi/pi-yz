// 系统能力桥：调用 Android 原生（分享面板、存到相册）。
//
// 为什么不引第三方插件：这两个能力（ACTION_SEND、MediaStore 写图）总共不到 60 行 Kotlin，
// 自己写一个 MethodChannel 就够，省掉 share_plus / image_gallery_saver 这类依赖，
// 也少一层「插件版本与 Flutter 版本打架」的风险。
//
// 失败一律返回 false / null，由调用方给中文提示 —— 不做静默失败。

import 'package:flutter/services.dart';
import 'i18n.dart';

class NativeBridge {
  NativeBridge._();

  static const MethodChannel _channel = MethodChannel('pi_mobile/native');

  /// 系统分享面板（会话片段）
  static Future<bool> shareText({
    required String text,
    String subject = '', // 默认参数必须是常量，空的进函数再翻
  }) async {
    if (text.trim().isEmpty) return false;
    final subjectText =
        subject.isEmpty ? I18n.t('ui.61a53db098') : subject;
    try {
      final ok = await _channel.invokeMethod<bool>('share', {
        'text': text,
        'subject': subjectText,
      });
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 存到系统相册（Pictures/pi-mobile）
  // ==================== 后台保活（task-10 遗留项补齐） ====================

  /// 起常驻服务：退到后台后连接与定时器继续活着。
  ///
  /// 为什么必须走原生：Flutter 层拿不到前台服务，而「不被系统冻结」只能靠它。
  /// 服务本身会挂一条 IMPORTANCE_MIN 的常驻通知 —— 保活要让人看得见，
  /// 这是 Android 的规矩，也是我们愿意遵守的部分（不做偷偷保活）。
  static Future<bool> startKeepAlive() async {
    try {
      final ok = await _channel.invokeMethod<bool>('keepAliveStart');
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> stopKeepAlive() async {
    try {
      final ok = await _channel.invokeMethod<bool>('keepAliveStop');
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 服务当前是否在跑（进设置页时用它同步开关状态，避免显示与实际不符）
  static Future<bool> keepAliveRunning() async {
    try {
      final running = await _channel.invokeMethod<bool>('keepAliveStatus');
      return running ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> saveImage(Uint8List bytes, {String? name}) async {
    if (bytes.isEmpty) return false;
    try {
      final saved = await _channel.invokeMethod<String>('saveImage', {
        'bytes': bytes,
        'name': name ?? 'pi-${DateTime.now().millisecondsSinceEpoch}.png',
      });
      return (saved ?? '').isNotEmpty;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
