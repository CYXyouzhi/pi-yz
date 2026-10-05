import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile/ui/server/chat_page.dart';

void main() {
  group('slashPanelMaxHeight：命令面板高度与键盘', () {
    test('没有键盘时按屏幕高度的 45%', () {
      const base = MediaQueryData(size: Size(400, 800));
      expect(slashPanelMaxHeight(base), 360);
    });

    test('键盘弹起后按「键盘之上剩余空间」算，面板相应变矮', () {
      const base = MediaQueryData(size: Size(400, 800));
      final withKb = base.copyWith(viewInsets: const EdgeInsets.only(bottom: 400));
      expect(slashPanelMaxHeight(withKb), 180);
      expect(slashPanelMaxHeight(withKb) < slashPanelMaxHeight(base), isTrue);
    });

    test('极端小空间时有下限保护，不会缩成 0', () {
      final tiny = MediaQueryData(
        size: const Size(400, 300),
        viewInsets: const EdgeInsets.only(bottom: 250),
      );
      expect(slashPanelMaxHeight(tiny), 160);
    });

    test('大屏时受上限约束（420px），避免占满整屏', () {
      expect(slashPanelMaxHeight(const MediaQueryData(size: Size(400, 1920))), 420);
    });
  });
}
