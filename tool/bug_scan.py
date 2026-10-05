# -*- coding: utf-8 -*-
"""常见 bug 模式扫描（只给候选，需人工核实，不当作结论）。"""
import sys

# Windows 控制台默认编码是 GBK，而本脚本的输出里有 ✓ ✗ ⚠ ↔ 这类不在
# GBK 字符集内的符号 —— 直接 print 不是显示乱码，而是整个脚本抛
# UnicodeEncodeError 退出（用户直接跑就会崩）。统一把标准输出重设为 UTF-8，
# 并用 errors="replace" 兜底：万一终端仍不支持，也只是把个别字符显示成 ?，
# 不会中断脚本。
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

import glob
import re
from pathlib import Path

BS = chr(92)

# ---------- A 类：单行模式 ----------
LINE_PATTERNS = [
    ('空 catch（吞异常）', re.compile(r'catch\s*\([^)]*\)\s*\{\s*\}')),
    ('catch 块内只有注释', re.compile(r'catch\s*\([^)]*\)\s*\{\s*//')),
    ('first/last/single 直接取（集合空会抛）', re.compile(r'\.(first|last|single)\b(?!\s*\()')),
    ('非空断言 ! 紧跟 ?.', re.compile(r'\?\.[\w]+\s*!')),
    ('substring 调用（需边界检查）', re.compile(r'\.substring\(')),
    ('double 除法 /（可能该用 ~/）', re.compile(r'[\w\)\]]\s*/\s*[\w\(]')),
    ('setState 在 await 之后', re.compile(r'await\s')),
    ('Future 未 await（fire and forget）', re.compile(r'^\s*(?!return|await|final|var|//)\w+\(\);\s*$')),
    ('TODO/FIXME/XXX/HACK', re.compile(r'(TODO|FIXME|XXX|HACK)')),
    ('硬编码 0.0.0.0/端口/IP', re.compile(r'\b(0\.0\.0\.0|127\.0\.0\.1)\b')),
    ('print（应走日志）', re.compile(r'(?<![\w.])print\(')),
    ('as 强转（可能崩）', re.compile(r'\bas\s+[A-Z]\w+')),
]

# ---------- B 类：文件级配对 ----------
PAIRS = [
    ('Timer 创建但无 cancel()', r'Timer(\.periodic)?\s*\(', r'\.cancel\(\)'),
    ('StreamSubscription 监听但无 cancel()', r'\.listen\s*\(', r'\.cancel\(\)'),
    ('TextEditingController 创建但无 dispose()', r'TextEditingController\s*\(', r'dispose\(\)'),
    ('AnimationController 创建但无 dispose()', r'AnimationController\s*\(', r'dispose\(\)'),
    ('ScrollController 创建但无 dispose()', r'ScrollController\s*\(', r'dispose\(\)'),
    ('addListener 但无 removeListener', r'\.addListener\s*\(', r'\.removeListener\s*\('),
]


def main():
    files = [f for f in glob.glob('lib/**/*.dart', recursive=True)]
    print('=' * 74)
    print('A 类：单行模式（候选，需人工核实）')
    print('=' * 74)
    for name, pat in LINE_PATTERNS:
        hits = []
        for f in files:
            for i, line in enumerate(Path(f).read_text(encoding='utf-8').split('\n'), 1):
                s = line.strip()
                if s.startswith('//'):
                    continue
                if pat.search(line):
                    hits.append((f.replace(BS, '/'), i, s[:74]))
        if not hits:
            continue
        print(f'\n### {name}：{len(hits)} 处')
        for f, i, s in hits[:6]:
            print(f'   {f}:{i}  {s}')
        if len(hits) > 6:
            print(f'   …另有 {len(hits) - 6} 处')

    print()
    print('=' * 74)
    print('B 类：文件级配对（创建了但没释放 / 没取消）')
    print('=' * 74)
    for name, create_pat, cleanup_pat in PAIRS:
        cp, xp = re.compile(create_pat), re.compile(cleanup_pat)
        bad = []
        for f in files:
            t = Path(f).read_text(encoding='utf-8')
            if cp.search(t) and not xp.search(t):
                bad.append(f.replace(BS, '/'))
        if bad:
            print(f'\n### {name}：{len(bad)} 个文件')
            for f in bad[:8]:
                print(f'   {f}')


if __name__ == '__main__':
    main()
