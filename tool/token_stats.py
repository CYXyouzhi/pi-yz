# -*- coding: utf-8 -*-
"""视觉令牌收敛的统一统计口径 —— 文档与门禁输出都跑它，避免几处数字互相矛盾。

之前的教训：收敛前后我用了三套临时脚本，口径不同（是否跳注释行、是否算 0、
是否把 NeuSpace.nX 解析成数字），于是文档写 29、门禁写 36、审计独立扫出 38。
现在只留这一个口径：**逐行、跳过注释、只算裸数字**。
"""
import re
import glob
from pathlib import Path

BS = chr(92)
NL = chr(10)
NUM = r'(?<![\w.])\d+(?:\.\d+)?(?![\w.])'


def main():
    font = radius = color = edge = sized = space = edge_zero = 0
    for f in glob.glob('lib/**/*.dart', recursive=True):
        if '/theme/' in f.replace(BS, '/'):
            continue
        src = Path(f).read_text(encoding='utf-8')
        for line in src.split(NL):
            if line.strip().startswith('//'):
                continue
            font += len(re.findall(r'fontSize:\s*[0-9.]+', line))
            radius += len(re.findall(r'BorderRadius\.circular\([0-9.]+\)', line))
            color += len(re.findall(r'Color\(0x[0-9A-Fa-f]+\)', line))
            for m in re.finditer(r'EdgeInsets\.(?:all|only|symmetric|fromLTRB)\(([^)]*)\)', line):
                nums = re.findall(NUM, m.group(1))
                edge += len(nums)
                edge_zero += sum(1 for x in nums if float(x) == 0)
            sized += len(re.findall(r'SizedBox\((?:width|height):\s*\d+', line))
        space += len(re.findall(r'NeuSpace\.n\d+', src))
    print('剩余硬编码 fontSize        :', font)
    print('剩余硬编码 radius          :', radius)
    print('剩余硬编码 Color(0x...)    :', color)
    print('剩余硬编码 EdgeInsets 数值 :', edge, '(其中 0 有', edge_zero, '个)')
    print('剩余硬编码 SizedBox        :', sized)
    print('NeuSpace 令牌引用          :', space)


main()
