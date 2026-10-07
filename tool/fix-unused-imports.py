# 一次性清理工具：删掉 analyze 报出的所有 unused import。
# 用法：python tool/fix-unused-imports.py
import pathlib
import re
import subprocess
from collections import defaultdict

BACKSLASH = chr(92)

out = subprocess.run(
    ['flutter', 'analyze'],
    capture_output=True, text=True, encoding='utf-8', errors='replace',
    shell=True, timeout=900,
).stdout

targets = defaultdict(set)
for line in out.splitlines():
    if 'Unused import' not in line:
        continue
    m = re.search(r' - ([^ ]+):(\d+):\d+ - unused_import', line)
    if m:
        targets[m.group(1).replace(BACKSLASH, '/')].add(int(m.group(2)))

print(f'  涉及 {len(targets)} 个文件，共 {sum(len(v) for v in targets.values())} 行')
for f, nos in targets.items():
    p = pathlib.Path(f)
    lines = p.read_text(encoding='utf-8').split('\n')
    for n in sorted(nos, reverse=True):
        idx = n - 1
        if 'import' in lines[idx]:
            print(f'      删 {f}:{n}  {lines[idx].strip()}')
            del lines[idx]
    p.write_text('\n'.join(lines), encoding='utf-8')
print('  完成')
