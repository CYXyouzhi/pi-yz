# -*- coding: utf-8 -*-
"""触控目标扫描：找出带图标的 NeuPressable 里触控尺寸不足 40dp 的。

口径（高度与宽度分开量，因为两者会各自不足）：
  高度 = 内部 NeuIcon 的 size + 2 × 垂直 padding
  宽度 = 内部 NeuIcon 的 size + 2 × 水平 padding
Material 的下限是 40dp（建议 48）。

用法：python tool/touch_targets.py   （期望：高度与宽度都不足 40dp 的为 0 个）
"""
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
NL = chr(10)


def num(s):
    m = re.match(r'NeuSpace\.n(\d+)', (s or '').strip())
    if m:
        return int(m.group(1))
    m = re.match(r'(\d+(?:\.\d+)?)', (s or '').strip())
    return float(m.group(1)) if m else None


def main():
    total = 0
    bad_h, bad_w = [], []
    for f in glob.glob('lib/ui/**/*.dart', recursive=True):
        lines = Path(f).read_text(encoding='utf-8').split(NL)
        for i, line in enumerate(lines):
            if 'NeuPressable(' not in line:
                continue
            blk = NL.join(lines[i:i + 18])
            pad = re.search(
                r'padding:\s*(?:const\s*)?EdgeInsets\.(all|symmetric|only|fromLTRB)\(([^)]*)\)',
                blk)
            icon = re.search(r'NeuIcon\([^)]*?size:\s*([\d.]+|NeuSpace\.n\d+)', blk, re.S)
            if not pad or not icon:
                continue
            total += 1
            vals = [num(x) for x in re.findall(r'NeuSpace\.n\d+|\d+(?:\.\d+)?', pad.group(2))]
            vals = [v for v in vals if v is not None]
            kind = pad.group(1)
            if kind == 'all':
                hpad = vpad = vals[0] if vals else 0
            elif kind == 'symmetric':
                hpad = vals[0] if vals else 0
                vpad = vals[1] if len(vals) > 1 else 0
            elif kind == 'only':
                hpad = sum(vals[0:2]) if len(vals) > 1 else 0
                vpad = sum(vals[2:4]) if len(vals) > 3 else 0
            else:  # fromLTRB
                hpad = (vals[0] + vals[2]) if len(vals) > 3 else 0
                vpad = (vals[1] + vals[3]) if len(vals) > 3 else 0
            inner = num(icon.group(1))
            h = inner + 2 * vpad
            w = inner + 2 * hpad
            where = f'{f.replace(BS, "/")}:{i + 1}'
            if h < 40:
                bad_h.append((where, round(h, 1)))
            if w < 40:
                bad_w.append((where, round(w, 1)))
    print('带图标的 NeuPressable:', total)
    print('高度 < 40dp:', len(bad_h))
    for x in bad_h[:15]:
        print('   高', x[0], x[1])
    print('宽度 < 40dp:', len(bad_w))
    for x in bad_w[:15]:
        print('   宽', x[0], x[1])
    return 0 if not bad_h and not bad_w else 1


if __name__ == '__main__':
    raise SystemExit(main())
