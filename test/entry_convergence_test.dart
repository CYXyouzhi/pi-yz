// 入口收敛的回归测试。
//
// 对应的清单：`docs/audit/entry-map-2026-10-08.md`
//
// ## 背景
//
// 「AI 配置」（模型、思考等级、技能命令、MCP 服务器）原先藏在设置页的
// **「工作区」分组**里，而它跟工作区没有任何关系。更麻烦的是 `ConfigPage`
// 全 App 只有这一个入口 —— 想改模型必须**猜到**「去工作区下面找 AI 配置」，
// 猜不到就以为没这个功能。
//
// 已提到设置页顶层、独立成行。这个文件把结果钉住，防止再次退回去。

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ui_harness.dart';

const String kAiConfig = 'AI 配置';
const String kAiConfigSummary = '模型、思考等级、技能命令、MCP 服务器';
const String kWorkspace = '工作区';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'app_lang': 'zh'});
  });

  testWidgets('「AI 配置」在设置页顶层，不用展开任何分组就能看到', (tester) async {
    setPhoneSurface(tester, width: 360);
    await tester.pumpWidget(const PiYzApp());
    await skipSplash(tester);
    await tapTab(tester, '设置');

    // 关键点一：默认（所有分组都收起）就该看见它。
    // 若它被塞回某个分组里，这里会失败 —— 那正是我们要防的退步。
    expect(
      find.text(kAiConfig),
      findsWidgets,
      reason: '「$kAiConfig」应该出现在设置页顶层（不展开任何分组就可见）',
    );
    expect(
      find.text(kAiConfigSummary),
      findsWidgets,
      reason: '顶层入口应该带上摘要「$kAiConfigSummary」，否则用户不知道它是什么',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('展开「工作区」后，「AI 配置」仍然只有顶层那一处', (tester) async {
    setPhoneSurface(tester, width: 360);
    await tester.pumpWidget(const PiYzApp());
    await skipSplash(tester);
    await tapTab(tester, '设置');

    // 前提：「工作区」分组确实存在（否则这条用例什么都没验证）
    expect(
      find.text(kWorkspace),
      findsWidgets,
      reason: '前提：设置页应该有「$kWorkspace」分组',
    );
    await tapVisible(tester, find.text(kWorkspace));
    expect(tester.takeException(), isNull);

    // 关键点二：展开后「AI 配置」**仍然只有一处**（就是顶层那个）。
    //
    // 为什么这么写而不是 findsNothing：顶层的入口本来就一直可见，
    // 用 findsNothing 会恒失败（第一版就踩了这个坑）。
    // 而「只数一处」恰好能抓住退步 —— 若它被塞回工作区分组，
    // 页面上就会出现两处（顶层 + 分组里）或位置不对。
    expect(
      find.text(kAiConfig),
      findsOneWidget,
      reason: '「$kAiConfig」应该只有顶层一处；展开「$kWorkspace」后变成多处，说明它又被塞回分组里了',
    );
    expect(
      find.text(kAiConfigSummary),
      findsOneWidget,
      reason: '「$kAiConfigSummary」应该只跟着顶层那一处出现',
    );

    // 反面对照：「文件浏览」跟工作区确实是相干的，应该留在该分组里 ——
    // 防止「收敛入口」时舞过头把它一起挪走。
    expect(find.text('文件浏览'), findsWidgets, reason: '「文件浏览」跟工作区相干，应该留在该分组里');
  });
}
