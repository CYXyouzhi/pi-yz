import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile/ui/server/chat_page.dart';

/// 渲染证据（**不是实机截图**）：把「无键盘 / 有键盘」两种 MediaQuery 下的
/// 命令面板高度渲染成图，直观看出键盘占位把面板压矮了。
/// 生成：flutter test --update-goldens test/slash_panel_golden_test.dart
void main() {
  testWidgets('命令面板：键盘占位前后（渲染证据）', (tester) async {
    const noKb = MediaQueryData(size: Size(400, 800));
    const withKb = MediaQueryData(
      size: Size(400, 800),
      viewInsets: EdgeInsets.only(bottom: 400),
    );

    Future<void> render(MediaQueryData mq) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: mq,
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: _Panel(height: slashPanelMaxHeight(mq)),
              ),
            ),
          ),
        ),
      );
    }

    await render(noKb);
    await expectLater(
      find.byType(_Panel),
      matchesGoldenFile('goldens/slash_panel_no_keyboard.png'),
    );

    await render(withKb);
    await expectLater(
      find.byType(_Panel),
      matchesGoldenFile('goldens/slash_panel_with_keyboard.png'),
    );
  });
}

class _Panel extends StatelessWidget {
  const _Panel({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        width: 360,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF23303A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF4A5B66)),
        ),
        child: Center(
          child: Text(
            'slash panel height = ${height.toStringAsFixed(0)}dp',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      );
}
