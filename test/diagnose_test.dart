// 连接诊断的判定逻辑测试（合同⑤：连不上时要给具体原因，不能只说「连接失败」）。
//
// 为什么这些必须单测：真机上要复现「端口不通」「DNS 解析失败」得去改路由器/拔网线，
// 是不可控的现场；而判定逻辑本身是纯函数，能被确定性地钉住。

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile/server/diagnose.dart';

void main() {
  group('explainFailure：把异常翻译成能动手的原因', () {
    test('超时 → 提示检查同网段 / 防火墙', () {
      final result = explainFailure(TimeoutException('x'));
      expect(result.kind, FailureKind.timeout);
      expect(result.reason, contains('超时'));
      expect(result.hint, contains('防火墙'));
    });

    test('连接被拒 → 直接说「没人监听」', () {
      final error = SocketException(
        'Connection refused',
        osError: const OSError('Connection refused', 10061),
      );
      final result = explainFailure(error);
      expect(result.kind, FailureKind.portClosed);
      expect(result.hint, contains('服务端可能没启动'));
    });

    test('Android 上的拒绝码 111 也认', () {
      final error = SocketException(
        'Connection refused',
        osError: const OSError('Connection refused', 111),
      );
      expect(explainFailure(error).kind, FailureKind.portClosed);
    });

    test('域名解析失败 → 提醒可能打错名字', () {
      final error = SocketException(
        'Failed host lookup: my-pc',
        osError: const OSError('No address associated with hostname', 7),
      );
      final result = explainFailure(error);
      expect(result.kind, FailureKind.dns);
      expect(result.hint, contains('IP'));
    });

    test('Windows 的 11001（没有这台主机）也算 DNS 问题', () {
      final error = SocketException(
        'No such host is known',
        osError: const OSError('No such host is known', 11001),
      );
      expect(explainFailure(error).kind, FailureKind.dns);
    });

    test('完全陌生的错误也要有一句人话 + 下一步', () {
      final result = explainFailure(StateError('boom'));
      expect(result.kind, FailureKind.unknown);
      expect(result.reason, contains('boom'));
      expect(result.hint, isNotEmpty);
    });
  });

  group('maskToken：导出给别人看时不能泄露 token', () {
    test('正常长度保留首尾各两位', () {
      expect(maskToken('pimobile2026'), 'pi********26');
    });

    test('很短的一律打满星号（几个字符就打几个星，不固定 4 个）', () {
      // task-16 改过：原来长度 ≤4 一律给 '****'，会让「3 位的 token」
      // 看起来像 4 位；按真实长度打星既不泄露内容也不谎报长度
      expect(maskToken('abc'), '***');
      expect(maskToken('abcd'), '****');
      expect(maskToken(''), '(空)');
    });
  });

  group('DiagReport：报告文本与结论', () {
    DiagReport build(List<DiagStep> steps) => DiagReport(
          host: '10.1.1.195',
          port: 30142,
          token: 'pimobile2026',
          defaultCwd: 'C:/work',
          steps: steps,
          startedAt: DateTime(2026, 10, 4, 8, 30),
          elapsed: const Duration(milliseconds: 120),
        );

    test('全部通过时结论就是「全部通过」', () {
      final report = build([
        DiagStep(title: '地址解析', ok: true, detail: 'ok'),
        DiagStep(title: '端口可达性', ok: true, detail: 'ok'),
      ]);
      expect(report.allOk, isTrue);
      expect(report.headline, '全部通过');
    });

    test('有失败时结论点名第一个失败的项', () {
      final report = build([
        DiagStep(title: '地址解析', ok: true, detail: 'ok'),
        DiagStep(title: '端口可达性', ok: false, detail: '连接被拒绝', hint: '先启动服务端'),
      ]);
      expect(report.allOk, isFalse);
      expect(report.headline, '端口可达性 有问题');
    });

    test('导出文本里 token 是掩码的，且带上每项的下一步', () {
      final report = build([
        DiagStep(title: '鉴权', ok: false, detail: 'token 不正确', hint: '重新配对'),
      ]);
      final text = report.toText();
      expect(text, contains('pi********26'));
      expect(text, isNot(contains('pimobile2026')));
      expect(text, contains('[失败] 鉴权：token 不正确'));
      expect(text, contains('下一步：重新配对'));
      expect(text, contains('默认工作区：C:/work'));
    });
  });
}
