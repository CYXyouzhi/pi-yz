// ignore_for_file: avoid_print
//
// 诊断用探针：把「正文/错误文字/toast 文字」实际拿到的 TextStyle 打出来，
// 用来定位那条多出来的下划线到底从哪来。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/theme/design_tokens.dart';
import 'package:pi_yz/theme/neu.dart';
import 'package:pi_yz/theme/neu_theme.dart';

void main() {
  testWidgets('探测各处的有效 TextStyle', (tester) async {
    final tokens = NeuTokens.light;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildNeuTheme(tokens, brightness: Brightness.light),
        home: NeuCanvas(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Column(
              children: [
                // 1) 裸 Text：继承 DefaultTextStyle
                const Text('plain'),
                // 2) 带显式 style 的 Text（与 toast / 错误文字同构）
                Text(
                  'styled',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.15,
                    color: tokens.toastFg,
                  ),
                ),
                // 3) 等宽字（预览页里也用等宽字）
                Text('mono', style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    void probe(String labelText) {
      final el = tester.element(find.text(labelText));
      final dflt = DefaultTextStyle.of(el).style;
      final rich = el.widget as Text;
      print('[$labelText] DefaultTextStyle.decoration=${dflt.decoration} '
          'color=${dflt.decorationColor} | 自身 style.decoration=${rich.style?.decoration}');
    }

    probe('plain');
    probe('styled');
    probe('mono');

    // 主题里 bodyMedium 的 decoration
    final theme = Theme.of(tester.element(find.text('plain')));
    print('theme.textTheme.bodyMedium.decoration=${theme.textTheme.bodyMedium?.decoration}');
    print('neu extension present=${theme.extension<NeuTheme>() != null}');
  });
}
