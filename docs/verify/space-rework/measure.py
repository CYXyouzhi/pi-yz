# -*- coding: utf-8 -*-
"""量消息区占屏高比例。截图 540x960（物理 1080x1920 的一半），逻辑 = 截图 x2/3，屏高 640。"""
import sys
from PIL import Image


def main(path):
    im = Image.open(path).convert('RGB')
    W, H = im.size
    px = im.load()

    def has_content(y):
        return sum(1 for x in range(0, W, 3) if sum(px[x, y]) < 480) > 2

    segs, cur = [], None
    for y in range(H):
        c = has_content(y)
        if c and cur is None:
            cur = y
        elif not c and cur is not None:
            if y - cur > 2:
                segs.append((cur, y - 1, y - cur))
            cur = None
    L = H * 2 // 3
    print(f'{path}  逻辑高 {L}')
    for s in segs[:8]:
        print(f'   y{s[0]:>4}-{s[1]:<4} 截图{s[2]:>3} 逻辑{s[2] * 2 // 3:>3}')
    # 消息区 = **最长的那一段**。不能用"第 2 段"：标题栏收起时第 1 段就是消息区；
    # 标题栏与活动条都收起时只剩"消息区 + 输入区"，第 2 段会取到输入区（曾算出 2%）。
    if segs:
        msg = max(segs, key=lambda x: x[2])
        logic = (msg[1] - msg[0]) * 2 // 3
        print(f'   消息区（最长段 y{msg[0]}-{msg[1]}）≈ {logic} 逻辑 = {logic / L * 100:.0f}%')


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'docs/verify/space-rework/t7-final-70pct.png')
