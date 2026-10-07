# 从 config_page.dart 抽一个折叠分组为无状态组件。
#
# 用法：python tool/extract_config_section.py <i18n_key> <ClassName> <out_relpath>
#   例：python tool/extract_config_section.py ui.11eead2c33 ThinkingSection \
#         lib/ui/server/config/thinking_section.dart
#
# 已知缺陷（跑完必须人工核对，别直接信）：
#   · 调用点的实参名会写成 `foo: foo`，但页面里往往是 `foo: _foo`；
#   · 只认得 State 字段，不认得调用点的局部变量（如 `chat`）；
#   · icon 靠正则猜，猜不到时默认 circle。
#
# 只处理「单个分组、无嵌套」的情况 —— 复杂的（如设置页的「外观」，内含三个子分组）
# 脚本化会出错，见 docs/refactor-status.md 的踩坑⑤。
#
# 参数从代码里自动推导：扫出正文用到了哪些 State 字段，把它们做成构造参数
# （下划线去掉），再用同名实参替换正文里的引用。
import pathlib
import re
import sys

KEY, CLS, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
PAGE = pathlib.Path('lib/ui/server/config_page.dart')
lines = PAGE.read_text(encoding='utf-8').split('\n')

# ---- 1) 边界：本分组的 _section 到下一个分组的 _section ----
start = next(i for i, l in enumerate(lines) if f"I18n.t('{KEY}'" in l and '_section(' in l)
nxt = [i for i in range(start + 1, len(lines)) if '_section(' in lines[i] and 'I18n.t(' in lines[i]]
end = nxt[0] if nxt else next(i for i, l in enumerate(lines) if re.match(r'^  (?:Widget|Future|void|bool|String) ', l))
body = lines[start:end]
while body and body[-1].strip() == '':
    body.pop()
print(f'  边界：行 {start+1} ~ {end-1}（{len(body)} 行）')

# ---- 2) 缩进：children 的 18 空格 → 组件的 8 空格（减 10）----
text = '\n'.join(l[10:] if l.startswith(' ' * 10) else l for l in body)

# ---- 3) State 字段 → 构造参数 ----
FIELDS = ['_credentials', '_loading', '_mcp', '_models', '_packageUpdateError',
          '_packages', '_packagesBusy', '_thinkingLevels', '_updates', '_store']
used = [f for f in FIELDS if re.search(r'\b' + f + r'\b', text)]
params = [f[1:] for f in used]
print(f'  用到字段：{", ".join(used) if used else "（无）"}')

for f in used:
    text = re.sub(r'\b' + f + r'\b', f[1:], text)

# ---- 4) 开合判断与标题 ----
text = re.sub(r'_expanded\.contains\(\s*I18n\.t\([^)]*\),?\s*\)', 'open', text)
text = re.sub(r"_section\(t, I18n\.t\('" + re.escape(KEY) + r"'\)[^\n]*\)",
              "ConfigSection(\n        title: I18n.t('" + KEY + "'),\n        icon: icon,\n"
              "        open: open,\n        onToggle: onToggle,\n      )", text)

icon = re.search(r"_section\(t, I18n\.t\('" + re.escape(KEY) + r"'\), icon: IconId\.(\w+)",
                 '\n'.join(body))
icon = icon.group(1) if icon else 'circle'

# ---- 5) 生成组件文件 ----
ctor_params = ''.join(f'    required this.{p},\n' for p in params)
fields = ''.join(f'  final {p};\n' for p in params)
header = f'''// AI 配置页的「{KEY}」分组（由 tool/extract_config_section.py 机械搬运后人工校对）。
//
// 约定同 config/widgets.dart：组件不持有状态，用到的数据都由页面传进来。

import 'package:flutter/material.dart';

import '../../../server/i18n.dart';
import '../../../server/server_store.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../neu_icons.dart';
import '../../neu_toast.dart';
import 'rows.dart';
import 'widgets.dart';

class {CLS} extends StatelessWidget {{
  const {CLS}({{
    super.key,
{ctor_params}    required this.open,
    required this.onToggle,
  }});

{fields}  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {{
    final t = context.neu;
    const icon = IconId.{icon};

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
pathlib.Path(OUT).write_text(header + text + '\n' + footer, encoding='utf-8')
print(f'  ✓ 写入 {OUT}')

# ---- 6) 替换页面里的调用点 ----
args = ''.join(f'                {p}: {p},\n' for p in params)
call = (f"              {CLS}(\n{args}"
        f"                open: _expanded.contains(I18n.t('{KEY}')),\n"
        f"                onToggle: () => setState(() {{\n"
        f"                  const k = '{KEY}';\n"
        f"                  _expanded.contains(k) ? _expanded.remove(k) : _expanded.add(k);\n"
        f"                }}),\n"
        f"              ),")
del lines[start:end]
lines[start:start] = call.split('\n')
t2 = '\n'.join(lines)
if f'config/{pathlib.Path(OUT).name}' not in t2:
    t2 = t2.replace("import 'config/rows.dart';",
                    f"import 'config/{pathlib.Path(OUT).name}';\nimport 'config/rows.dart';", 1)
PAGE.write_text(t2, encoding='utf-8')
print(f'  ✓ 页面已替换，现 {len(t2.splitlines())} 行')
