// 模型胶囊短名的边界用例。
//
// 用户的抱怨是「标题栏太杂乱」，具体现象是模型名被截成 `Dee…` ——
// 只剩三个字母，既认不出是哪个模型，看起来也像渲染坏了。
// 修法是剥掉名字里与型号重复的厂商词（宽度上限不能取消：旁边还有会话名、
// 状态点和三个按钮）。这个剥法最容易在边界上出错，所以单独测。
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile/server/server_types.dart';
import 'package:pi_mobile/ui/server/chat_page.dart';

ModelInfo _m(String provider, String id, String name) =>
    ModelInfo(provider: provider, id: id, name: name);

void main() {
  group('modelChipLabel：该剥的剥', () {
    test('DeepSeek V4.1 Flash → V4.1 Flash（用户当前用的这个）', () {
      expect(
        modelChipLabel(_m('deepseek', 'deepseek-flash', 'DeepSeek V4.1 Flash')),
        'V4.1 Flash',
      );
    });

    test('provider 与型号无关时也能剥（靠 id 判定，不靠 provider）', () {
      expect(
        modelChipLabel(_m('opencode-go', 'deepseek-v4.1-flash', 'DeepSeek V4.1 Flash')),
        'V4.1 Flash',
      );
    });

    test('大小写不同也算命中', () {
      expect(
        modelChipLabel(_m('x', 'DEEPSEEK-v4-pro', 'deepseek V4 Pro')),
        'V4 Pro',
      );
    });
  });

  group('modelChipLabel：不该剥的别动', () {
    test('剥完只剩一个词 → 不剥（否则 Qwen3.8 Flash 会变成 Flash，型号丢了）', () {
      expect(
        modelChipLabel(_m('opencode-go', 'qwen3.8-flash', 'Qwen3.8 Flash')),
        'Qwen3.8 Flash',
      );
    });

    test('厂商与型号粘连、名字里根本没有空格 → 不剥', () {
      expect(
        modelChipLabel(_m('opencode-go', 'minimax-m3', 'MiniMax-M3')),
        'MiniMax-M3',
      );
    });

    test('名字首段与 id 首段不一致 → 不剥', () {
      // 比如名字写了厂商简称、而 id 用的是另一个词：这时无从判断哪段可以省
      expect(
        modelChipLabel(_m('x', 'gpt-5-flash', 'OpenAI GPT-5 Flash')),
        'OpenAI GPT-5 Flash',
      );
    });

    test('名字为空 / 只有一段的极端情况不炸', () {
      expect(modelChipLabel(_m('x', 'y', '')), '');
      expect(modelChipLabel(_m('x', 'y', 'Solo')), 'Solo');
    });
  });

  test('model 为 null 时给出「选模型」占位文案', () {
    final label = modelChipLabel(null);
    expect(label, isNotEmpty);
  });
}
