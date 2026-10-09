// 消息上的动作（task-9 的 ①②⑨）：双击复制、⋮ 菜单（复制/引用）、图片存相册。
//
// 为什么要写这层测试：MuMu 的 input 通道**打不出真双击** ——
// 每次 `input tap` 都是一次进程启动，两次之间隔 300ms 以上，早就出了双击窗口。
// 实机只能验证「菜单能弹出、能点到、能存到相册」，
// 「双击」这条只能在这一层钉住（widget 测试里 pump 50ms 再点，就是标准双击）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/server/i18n.dart';
import 'package:pi_yz/server/chat_models.dart';
import 'package:pi_yz/server/native_bridge.dart';
import 'package:pi_yz/server/server_types.dart';
import 'package:pi_yz/theme/design_tokens.dart';
import 'package:pi_yz/theme/neu_theme.dart';
import 'package:pi_yz/ui/server/message_view.dart';

/// 造一条带正文的消息
ChatMessage textMessage({required String text, bool isUser = false}) {
  return ChatMessage(
    key: 'k1',
    role: isUser ? 'user' : 'assistant',
    text: text,
    blocks: const [],
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );
}

/// 造一条带图片的消息（1×1 透明 PNG 的 base64）
ChatMessage imageMessage() {
  const tinyPng =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
  return ChatMessage(
    key: 'k2',
    role: 'user',
    text: '',
    blocks: [PiImage(data: tinyPng, mimeType: 'image/png')],
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );
}

Widget host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildNeuTheme(NeuTokens.light, brightness: Brightness.light),
  home: NeuCanvas(
    brightness: Brightness.light,
    child: Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(child: child),
    ),
  ),
);

void main() {
  // 剪贴板与原生桥都是平台通道：这里 mock 掉并记录调用
  late List<String> clipboard;
  late List<MethodCall> nativeCalls;

  setUp(() {
    clipboard = [];
    nativeCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('pi_yz/native'), (
          call,
        ) async {
          nativeCalls.add(call);
          return call.method == 'saveImage' ? 'content://saved' : true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('pi_yz/native'), null);
  });

  testWidgets('① 双击消息（留白处）把整条正文复制到剪贴板', (tester) async {
    await tester.pumpWidget(
      host(MessageTile(message: textMessage(text: '结论：都读到了'))),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final tile = find.byType(MessageTile);
    // 双击：两次点击之间只 pump 50ms，落在双击窗口内
    await tester.tapAt(tester.getTopRight(tile) - const Offset(4, -8));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(tester.getTopRight(tile) - const Offset(4, -8));
    await tester.pump(const Duration(milliseconds: 300));

    expect(clipboard, ['结论：都读到了']);
  });

  testWidgets('② ⋮ 菜单：复制 / 引用 / 分享都在，引用会把原文回调出去', (tester) async {
    String? quoted;
    await tester.pumpWidget(
      host(
        MessageTile(
          message: textMessage(text: '被引用的正文'),
          onQuote: (text) => quoted = text,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byType(GestureDetector).last); // 消息右侧那个 ⋮
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(find.text(I18n.t('ui.79d3abe929')), findsOneWidget);
    expect(find.text(I18n.t('ui.0f875dd0dc')), findsOneWidget);
    expect(find.text(I18n.t('ui.96c2ee76cd')), findsOneWidget);
    // 助手消息不该有「编辑重发」（那是用户消息才有的语义）
    expect(find.text(I18n.t('ui.7c79620b1a')), findsNothing);

    await tester.tap(find.text(I18n.t('ui.0f875dd0dc')));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(quoted, '被引用的正文');
  });

  testWidgets('② 用户消息的菜单里有「编辑重发」', (tester) async {
    String? resend;
    await tester.pumpWidget(
      host(
        MessageTile(
          message: textMessage(text: '我发的话', isUser: true),
          onEditResend: (text) => resend = text,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byType(GestureDetector).last);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.text(I18n.t('ui.7c79620b1a')), findsOneWidget);

    await tester.tap(find.text(I18n.t('ui.7c79620b1a')));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(resend, '我发的话');
  });

  // ⑨ 的「长按图片 → 存相册」这条链路在实机上有硬证据（相册里真的多了
  // Pictures/pi-yz/pi-*.png）。
  // 这里只把最底下那层桥钉住：widget 测试里 Image.memory 解不出尺寸，
  // 长按落不到它身上 —— 与其写个永远点不中的测试，不如测桥本身。
  test('⑨ 原生桥：存相册与分享都把参数交给平台通道', () async {
    final saved = await NativeBridge.saveImage(
      Uint8List.fromList(List<int>.filled(8, 7)),
      name: 'pi-test.png',
    );
    expect(saved, isTrue);
    final shareOk = await NativeBridge.shareText(text: '会话片段正文');
    expect(shareOk, isTrue);

    expect(nativeCalls.map((c) => c.method).toList(), ['saveImage', 'share']);
    final saveArgs = nativeCalls.first.arguments as Map;
    expect(saveArgs['name'], 'pi-test.png');
    expect((saveArgs['bytes'] as Uint8List).length, 8);
    final shareArgs = nativeCalls.last.arguments as Map;
    expect(shareArgs['text'], '会话片段正文');
  });

  test('⑨ 原生桥：空内容不发请求（不做假动作）', () async {
    expect(await NativeBridge.saveImage(Uint8List(0)), isFalse);
    expect(await NativeBridge.shareText(text: '   '), isFalse);
    expect(nativeCalls, isEmpty);
  });
}
