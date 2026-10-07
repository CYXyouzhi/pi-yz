# 把 State 里的一个渲染方法搬成无状态组件。
#
#   python tool/extract_render_method.py <page> <METHOD> <ClassName> <out> <ctor> <fields> <renames>
#
# renames 形如 "old=new,old2=new2"。
#
# ── 这个脚本踩过的三个坑（都写在这里，免得重蹈）────────────────────────
# 1) 页面文件是 **CRLF**。所有按 `\n` 写的锚点/替换都会静默失配 ——
#    前面「替换没生效」几乎全是这个原因，代价是五轮返工。
#    所以这里读入就统一成 LF。
# 2) 方法签名可能是**多行**的（`Widget f(\n  A a,\n) {`）。
#    早先按「去掉第 1 行」剥签名会留下参数列表，报一堆 expected_class_member。
#    现在按签名结束的 `) {` 或 `) =>` 定位，与占几行无关。
# 3) 方法体自己就有 `return`，不要在外面再包一个。
#
# 另外：**字段要一次性给全**。曾经先生成再去 str.replace 加字段，
# 而同一文件里两个 class 的构造签名文本相同，于是命中了错的那个。
import pathlib
import re
import sys

PAGE, METHOD, CLS, OUT, CTOR, FIELDS, RENAMES = sys.argv[1:8]
RENAMES = [tuple(r.split('=')) for r in RENAMES.split(',') if r]

p = pathlib.Path(PAGE)
t = p.read_text(encoding='utf-8').replace('\r\n', '\n')   # 坑 1
lines = t.split('\n')

BOUND = re.compile(
    r'^  (?:///|@override|Widget |Future<|void |String |bool |int |static |IconId |List<|Map<|\w+Function)')

i = next(k for k, l in enumerate(lines)
         if re.match(r'^  (?:Widget|Future|void|String|bool|int) ' + METHOD + r'\(', l))
j = next((k for k in range(i + 1, len(lines)) if BOUND.match(lines[k])), len(lines))
k = j - 1
while k > i and lines[k].strip() == '':
    k -= 1
assert lines[k].strip() in ('}', ');'), f'{METHOD} 边界校验失败：{lines[k]!r}'
body = '\n'.join(lines[i:j])
print(f'  取出 {METHOD}：行 {i+1} ~ {j}（{j-i} 行）')

# 坑 2：按签名结束处定位，不按行数
m = re.search(r'\)\s*(?:async\s*)?\{', body)
arrow = False
if m:
    inner = body[m.end():].rstrip()
    assert inner.endswith('}'), inner[-40:]
    inner = inner[:-1]
else:
    m = re.search(r'\)\s*(?:async\s*)?=>', body)
    assert m, f'{METHOD} 找不到签名结束'
    arrow = True
    inner = body[m.end():].rstrip()
    if inner.endswith(';'):
        inner = inner[:-1]

for a, b in RENAMES:                                     # 坑 1（同样的理由用 re 而非 str.replace）
    inner = re.sub(r'\b' + re.escape(a) + r'\b', b, inner)

inner = '\n'.join(('  ' + l) if l.strip() else l for l in inner.strip('\n').split('\n'))

w = pathlib.Path(OUT)
existing = w.read_text(encoding='utf-8').replace('\r\n', '\n') if w.exists() else \
    """import 'package:flutter/material.dart';

"""
w.write_text(existing + f'''
/// {METHOD} 的组件化版本。
class {CLS} extends StatelessWidget {{
  const {CLS}({CTOR});

{FIELDS}

  @override
  Widget build(BuildContext context) {{
    final t = context.neu;
    {inner.strip()}
  }}
}}
''', encoding='utf-8')
print(f'  ✓ 写入 {OUT}（调用点仍需人工替换）')

del lines[i:j]
while i < len(lines) and lines[i].strip() == '':
    del lines[i]
p.write_text('\n'.join(lines), encoding='utf-8')
print(f'  ✓ {PAGE} 现 {len(lines)} 行')
