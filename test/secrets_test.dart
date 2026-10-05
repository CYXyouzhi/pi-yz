// 脱敏规则的确定性验证（task-16 合同③④）。
//
// 为什么值得单测：这类函数写错了不会报错，只会**静默泄漏** ——
// 诊断页看起来正常，token 已经在里面了。

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile/server/diagnose.dart';

void main() {
  group('诊断报告里的 token 必须是脱敏的', () {
    test('空值', () {
      expect(maskToken(''), '(空)');
    });

    test('短 token 一律全遮（露头露尾等于全给）', () {
      expect(maskToken('abc'), '***');
      expect(maskToken('abcdef'), '******');
    });

    test('长 token 只留头尾，中间用星号填满', () {
      final masked = maskToken('abcdefghijklmn');
      expect(masked, 'ab**********mn');
      expect(masked.length, 'abcdefghijklmn'.length);
    });

    test('原串本身不出现在脱敏结果里', () {
      const token = 'sk-live-abcdefghijklmnopqrstuvwxyz';
      expect(maskToken(token).contains(token), isFalse);
      expect(maskToken(token).contains('sk-live'), isFalse,
          reason: '前缀超过 2 个字符就不该露出来');
    });
  });
}
