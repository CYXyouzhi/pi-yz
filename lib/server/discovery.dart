// 局域网发现与配对（手机端）。
//
// 解决的痛点是「不再手输 IP」：
//   1. App 往局域网广播一个探测包（UDP 30143）
//   2. 电脑端 pi-mobile-server 应答自己的地址/端口/版本
//   3. 选中设备后用「配对码」换 token（码由用户在电脑端显式开启窗口才有）
//
// 为什么用 dart:io 手写而不是拉 mDNS/扫码库：
//   · 不引依赖，Flutter 升级不会因为三方包停更把功能带走；
//   · 协议就一行 JSON，出错也只影响「发现」这一步，不影响已保存的连接。

import 'dart:async';
import 'i18n.dart';
import 'dart:convert';
import 'dart:io';

/// 一台被发现的电脑。
class DiscoveredServer {
  const DiscoveredServer({
    required this.name,
    required this.host,
    required this.port,
    required this.piVersion,
    required this.pairingOpen,
  });

  final String name;
  final String host;
  final int port;
  final String piVersion;

  /// 电脑端此刻是否开着配对窗口（开着才能用配对码换 token）
  final bool pairingOpen;

  String get endpoint => '$host:$port';

  static DiscoveredServer? tryParse(String raw, String from) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      if (json['app'] != 'pi-mobile-server') return null;
      return DiscoveredServer(
        name: (json['name'] as String?)?.trim().isNotEmpty == true
            ? json['name'] as String
            : from,
        host: from,
        port: (json['port'] as num?)?.toInt() ?? 30142,
        piVersion: json['piVersion'] as String? ?? '?',
        pairingOpen: json['pairingOpen'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// 配对结果：成功给出 token，失败给出人话原因。
class PairOutcome {
  const PairOutcome({required this.ok, required this.message, this.token});

  final bool ok;
  final String message;
  final String? token;
}

class LanDiscovery {
  /// 发现端口：与电脑端 discovery.mjs 里的一致。
  static const int discoveryPort = 30143;

  /// 扫描局域网。
  ///
  /// [window] 是收集应答的时间窗：太短会漏掉慢的机器，太长用户要干等。
  /// 3 秒是实测（本机 + 局域网单机）都够用的值。
  static Future<List<DiscoveredServer>> scan({
    Duration window = const Duration(seconds: 3),
    void Function(String note)? onNote,
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final found = <String, DiscoveredServer>{};
    socket.broadcastEnabled = true;

    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      final parsed = DiscoveredServer.tryParse(
        utf8.decode(datagram.data, allowMalformed: true),
        datagram.address.address,
      );
      if (parsed != null) found[parsed.endpoint] = parsed;
    });

    final targets = <InternetAddress>[
      // 全子网广播：绝大多数家庭/办公网都吃这一套
      InternetAddress('255.255.255.255'),
      // 再按本机地址推一个定向广播（有些路由器会挡 255.255.255.255）
      ...await _localBroadcasts(),
      // 回环：电脑和模拟器在同一台机器上时，这是唯一能通的一条路
      InternetAddress('127.0.0.1'),
    ];

    final payload = utf8.encode('PI_MOBILE_DISCOVER $discoveryPort');
    for (final target in targets) {
      try {
        socket.send(payload, target, discoveryPort);
      } catch (error) {
        onNote?.call(I18n.tp('ui.d30d228229', {'target': target, 'e': error}));
      }
    }

    await Future<void>.delayed(window);
    socket.close();
    return found.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  /// 由本机 IPv4 地址推出 /24 广播地址（a.b.c.255）。
  static Future<List<InternetAddress>> _localBroadcasts() async {
    final out = <InternetAddress>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final parts = address.address.split('.');
          if (parts.length == 4) {
            out.add(InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'));
          }
        }
      }
    } catch (_) {
      // 拿不到网卡信息就只靠 255.255.255.255
    }
    return out;
  }

  /// 用配对码换 token。
  ///
  /// 失败原因分得很细，因为这一页的失败几乎全是「窗口没开」或「码打错」，
  /// 含糊地说一句「配对失败」等于让用户去猜。
  static Future<PairOutcome> pair({
    required String host,
    required int port,
    required String code,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .postUrl(Uri.parse('http://$host:$port/api/pair'))
          .timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'code': code.trim()}));
      final response = await request.close().timeout(timeout);
      final text = await utf8.decoder.bind(response).join();

      if (response.statusCode == 200) {
        final json = jsonDecode(text);
        final token = (json is Map ? json['token'] as String? : null) ?? '';
        if (token.isEmpty) {
          return PairOutcome(ok: false, message: I18n.t('ui.06e2174d32'));
        }
        return PairOutcome(ok: true, message: I18n.t('ui.942ce60e9f'), token: token);
      }
      // 服务端把原因写在 error 里（例如「配对码不对」「配对窗口没开」）
      try {
        final json = jsonDecode(text);
        final message = json is Map ? json['error'] as String? : null;
        if (message != null && message.isNotEmpty) {
          return PairOutcome(ok: false, message: message);
        }
      } catch (_) {
        // 不是 JSON 就退回通用文案
      }
      return PairOutcome(
        ok: false,
        message: I18n.tp('ui.d5c5d56576', {'code': response.statusCode}),
      );
    } on TimeoutException {
      return PairOutcome(ok: false, message: I18n.t('ui.50fec36c81'));
    } on SocketException catch (error) {
      return PairOutcome(
        ok: false,
        message: I18n.tp('ui.53eb8845bf', {'host': host, 'port': port, 'e': error.osError?.message ?? error.message}),
      );
    } finally {
      client.close(force: true);
    }
  }
}
