# 把 State 里的一个渲染方法搬成无状态组件。
#
# 用法：python tool/extract_render_method.py <page_file> <method> <ClassName> <out_file> \
#         <ctor_sig> <fields_src> <rename:old=new,...>
#
# 为什么单独写这个：前面失败四次，根因都是**同一件事** ——
# 我按「去掉 body 的第一行」来剥签名，可 sessions_page 里的方法签名是**多行**的：
#
#     Widget _buildGroup(
#       NeuTokens t,
#       String cwd,
#       ...
#     ) {
#
# 于是参数列表残留进了组件，编译器报一堆 expected_class_member / already defined。
# 现在改成按「签名结束的那个 ) {」定位，跟签名占几行无关。
#
# 另一个必修的点：箭头函数（`Widget f(...) => ...;`）没有函数体花括号，
# 要单独处理。
import pathlib
import re
import sys

PAGE, METHOD, CLS, OUT, CTOR, FIELDS, RENAMES = sys.argv[1:8]
RENAMES = [tuple(r.split('=')) for r in RENAMES.split(',') if r]

p = pathlib.Path(PAGE)
t = p.read_text(encoding='utf-8')
lines = t.split('\n')

BOUND = re.compile(
    r'^  (?:///|@override|Widget |Future<|void |String |bool |int |static |IconId |List<|Map<|\w+Function)')

# 1) 定位方法
i = next(k for k, l in enumerate(lines) if re.match(r'^  (?:Widget|Future|void|String|bool|int) ' + METHOD + r'\(', l))
j = next((k for k in range(i + 1, len(lines)) if BOUND.match(lines[k])), len(lines))
k = j - 1
while k > i and lines[k].strip() == '':
    k -= 1
assert lines[k].strip() in ('}', ');'), f'{METHOD} 边界校验失败：{lines[k]!r}'
body = '\n'.join(lines[i:j])
print(f'  取出 {METHOD}：行 {i+1} ~ {j}（{j-i} 行）')

# 2) 剥签名 —— 按签名结束的 `) {` / `) async {` / `=>` 定位，不按行数
m = re.search(r'\)\s*(?:async\s*)?\{', body)
arrow = False
if not m:
    m = re.search(r'\)\s*(?:async\s*)?=>', body)
    arrow = True
assert m, f'{METHOD} 找不到签名结束'
inner = body[m.end():]
if not arrow:
    # 去掉函数体最外层的收尾 }
    inner = inner.rstrip()
    assert inner.endswith('}'), inner[-40:]
    inner = inner[:-1]
    # 再去掉它前面那个多余的花括号残留（若有）
else:
    inner = inner.rstrip()
    if inner.endswith(';'):
        inner = inner[:-1]

# 3) 改引用
for a, b in RENAMES:
    inner = re.sub(r'\b' + re.escape(a) + r'\b', b, inner)

# 4) 缩进对齐到组件 build 里（原在 State 里是 2 空格起 → build 内 4 空格起）
inner = '\n'.join(('  ' + l) if l.strip() else l for l in inner.strip('\n').split('\n'))

w = pathlib.Path(OUT)
existing = w.read_text(encoding='utf-8') if w.exists() else ''
header = '' if existing else 'import "package:flutter/material.dart";\n'
w.write_text(existing + f'''
/// {METHOD} 的组件化版本。
class {CLS} extends StatelessWidget {{
  const {CLS}({CTOR});

{FIELDS}

  @override
  Widget build(BuildContext context) {{
    final t = context.neu;
    return{inner}
  }}
}}
''', encoding='utf-8')
print(f'  ✓ 写入 {OUT}')

# 5) 从页面删掉
del lines[i:j]
while i < len(lines) and lines[i].strip() == '':
    del lines[i]
p.write_text('\n'.join(lines), encoding='utf-8')
print(f'  ✓ {PAGE} 现 {len(lines)} 行（调用点仍需人工替换）')
