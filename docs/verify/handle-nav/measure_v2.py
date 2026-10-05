#!/usr/bin/env python
"""量会话页「消息区」占屏高比例 —— v2。

## 为什么不复用 space-rework/measure.py

旧脚本按「每行有没有暗像素」切段、取**最长段**当消息区。它有两个问题：

1. **标题栏与消息区之间没有空白分行** —— 标题栏的图标/文字行和消息区被算成
   同一段。旧输出 `y0-876 ≈ 584 逻辑 = 91%` 里，那段其实是
   「屏幕顶（含状态栏）+ 标题栏 + 消息区」，**不是纯消息区**。
2. **空会话量不出来** —— 消息区只有中间一个图标两行字，最长段会落到标题栏上
   （曾算出 2%）。

## 本脚本的口径

   消息区 = 从【标题栏内容的下沿】到【输入区卡片的上沿】

两个边界都用**亮度剖面**定位，而不是「有没有暗像素」：

  · 标题栏下沿：顶部区域内**最后一个有内容笔画的行**（内容比背景暗）。
  · 输入区上沿：输入区卡片上边缘有一条 NeuRaised 的白色高光，亮度会先升到
    局部峰值、再突然回落 —— 回落那一行就是卡片实体边界。

对空会话同样有效：两个边界都与消息内容无关。

用法：
    python docs/verify/handle-nav/measure_v2.py docs/verify/handle-nav/t1-01-*.png
"""

from __future__ import annotations

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
from pathlib import Path

from PIL import Image

# 截图是物理分辨率的一半（工具约定）。逻辑高 = 截图高 × 2/3。
SCREENSHOT_TO_LOGIC = 2 / 3

DARK = 200      # 低于它算「有内容笔画」
MIN_DARK = 3    # 一行至少这么多暗像素才算有内容（滤掉抗锯齿噪点）
GAP_ROWS = 8    # 同一块内容内部的允许间隙（行）。标题栏两行之间实测 7 行
HEADER_MAX_LOGIC = 90  # 标题栏不可能比这更高；超过就说明把消息内容误并进来了


def row_dark_count(px, width: int, y: int) -> int:
    n = 0
    for x in range(0, width, 2):
        r, g, b = px[x, y]
        if (r + g + b) / 3 < DARK:
            n += 1
    return n


def luminance(px, x: int, y: int) -> float:
    r, g, b = px[x, y]
    return (r + g + b) / 3


def find_header_bottom(px, width: int, height: int) -> int:
    """标题栏内容的下沿。

    做法：从屏幕顶往下找**第一块内容**（内部允许 ≤ GAP_ROWS 行的间隙），
    返回它的结束行。

    · 标题栏第 1 行与第 2 行之间实测有 ~7 行间隙（行高分隔），所以间隙阈值定在 8；
    · 标题栏与第一条消息之间的间隙更长（实测 ≥ 11 行），因此不会被误并；
    · 再加一道上限：标题栏不可能超过 HEADER_MAX_LOGIC 逻辑高，超过就夹住 ——
      万某张图的标题栏与消息挨得太紧，至少不会把整屏都算成标题栏。
    """
    cap = int(HEADER_MAX_LOGIC / SCREENSHOT_TO_LOGIC)
    last = 0
    gap = 0
    for y in range(min(cap, height)):
        if row_dark_count(px, width, y) >= MIN_DARK:
            last = y
            gap = 0
        else:
            gap += 1
            if last > 0 and gap > GAP_ROWS:
                break  # 超出允许间隙 → 第一块内容结束
    return last


def find_composer_top(px, width: int, height: int) -> tuple[int, str]:
    """输入区卡片的上沿。

    做法：在屏幕下半部取若干列（避开中间的文字与图标），对每列找
    「亮度局部峰值之后第一次明显回落」的行，然后取这些列的中位数。
    """
    probes = [width // 12, width // 8, width // 4]  # 靠左，避开输入框文字
    candidates: list[int] = []
    for x in probes:
        best = None
        for y in range(height // 2, height - 20):
            prev = luminance(px, x, y - 1)
            cur = luminance(px, x, y)
            # 卡片上沿：刚从高光峰值跌下来的那一步，且跌得够明显
            if prev - cur >= 5 and prev >= 225:
                best = y
                break
        if best is not None:
            candidates.append(best)
    if not candidates:
        return -1, '未找到（亮度剖面无「高光后回落」特征）'
    candidates.sort()
    return candidates[len(candidates) // 2], f'{len(candidates)}/{len(probes)} 列命中'


def main(paths: list[str]) -> int:
    rc = 0
    for p in paths:
        im = Image.open(p).convert('RGB')
        W, H = im.size
        px = im.load()
        logic_h = round(H * SCREENSHOT_TO_LOGIC)

        header_bottom = find_header_bottom(px, W, H)
        composer_top, note = find_composer_top(px, W, H)

        print(f'=== {p} ===')
        print(f'  截图 {W}x{H}  逻辑高 {logic_h}（系数 2/3）')
        if composer_top < 0:
            print(f'  ✗ 输入区上沿定位失败：{note}')
            rc = 1
            continue

        msg_top = header_bottom * SCREENSHOT_TO_LOGIC
        msg_bottom = composer_top * SCREENSHOT_TO_LOGIC
        msg_h = msg_bottom - msg_top
        pct = msg_h / logic_h * 100
        pct_top = msg_bottom / logic_h * 100

        print(f'  标题栏内容下沿 : y={header_bottom:>3} 逻辑 {msg_top:>5.1f}')
        print(f'  输入区卡片上沿 : y={composer_top:>3} 逻辑 {msg_bottom:>5.1f}   （{note}）')
        print(f'  【口径 A】屏幕顶 -> 输入区上沿 : {msg_bottom:>5.1f} = {pct_top:.1f}%'
              f'   ← 与旧 gates.txt 的 91% 同口径（含标题栏）')
        print(f'  【口径 B】标题栏下沿 -> 输入区上沿（纯消息区）: {msg_h:>5.1f} = {pct:.1f}%')
        print(f'  屏幕底条款占用 : 逻辑 {logic_h - msg_bottom:>5.1f} = '
              f'{(logic_h - msg_bottom) / logic_h * 100:.1f}%'
              f'（输入区卡片 + 把手 + 系统手势条）')
        print()
    return rc


if __name__ == '__main__':
    args = sys.argv[1:]
    if not args:
        args = [str(Path('docs/verify/handle-nav/t1-01-default-collapsed.png'))]
    sys.exit(main(args))
