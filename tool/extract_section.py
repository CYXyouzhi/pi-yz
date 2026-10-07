# 一次性工具：把 settings_page.dart 里的一个分组抽成独立组件文件。
# 用法：python tool/extract_section.py <section_key> <ClassName> <out_file>
#
# 只做机械搬运：提取 _section(...) 到分组末尾的代码，做三处替换，包上 class 外壳。
# 参数重排这类需要判断的地方仍由人改 —— 脚本只负责别打错 100 行代码。
import pathlib
import re
import sys

key, cls, out = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path('lib/ui/server/settings_page.dart')
lines = p.read_text(encoding='utf-8').split('\n')

# 分组起点：_section(t, I18n.t('<key>')
start = next(i for i, l in enumerate(lines) if f"I18n.t('{key}'" in l and '_section(' in l)
# 终点：下一个 SizedBox(height: NeuSpace.n20)（那是分组之间的分隔）
end = next(i for i in range(start + 1, len(lines)) if 'SizedBox(height: NeuSpace.n20)' in lines[i])
body = lines[start:end]
print(f'  提取 行 {start+1} ~ {end}（{len(body)} 行）')

text = '\n'.join(body)
# 1) 把 `_section(...)`（可能跨行）改成 SettingsSection(...)
text = re.sub(r"_section\(t,\s*I18n\.t\('" + re.escape(key) + r"'[^)]*\)",
              'SettingsSection(\n            title: key', text, count=1)
# 2) if (_expanded.contains(...)) ...[ → if (open) ...[
text = re.sub(r"if \(_expanded\.contains\([^)]*\)\) \.\.\.\[", 'if (open) ...[', text, count=1)
# 3) 缩进整体减 2（从 build 的 children 层 → 组件的 children 层）
text = '\n'.join(l[2:] if l.startswith('  ') else l for l in text.split('\n'))

header = f'''// 设置页的「{key}」分组（由 tool/extract_section.py 机械搬运，之后人工校对）。
//
// 抽出来的理由与做法见 docs/refactor-status.md：状态留在父级 State，
// 组件只收 open（我展开了吗）与 onToggle（点了要干什么），自己不持有任何字段。

import 'package:flutter/material.dart';

import '../../../server/i18n.dart';
import '../../../server/server_store.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../neu_icons.dart';
import '../../neu_toast.dart';
import 'widgets.dart';

class {cls} extends StatelessWidget {{
  const {cls}({{
    super.key,
    required this.store,
    required this.open,
    required this.onToggle,
  }});

  final ServerStore store;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {{
    final t = context.neu;
    final key = I18n.t('{key}', context: context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
'''
footer = '''
      ],
    );
  }
}
'''

pathlib.Path(out).write_text(header + text + footer, encoding='utf-8')
print(f'  ✓ 写入 {out}')

# 原文件：把该分组替换成一行组件调用
call = f"""          {cls}(
            store: store,
            open: _isOpen('{key}'),
            onToggle: () => _toggle('{key}'),
          ),"""
lines[start:end] = call.split('\n')
p.write_text('\n'.join(lines), encoding='utf-8')
print(f'  ✓ 原文件已替换，现 {len(lines)} 行')
