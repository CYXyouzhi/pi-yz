"""MuMu 模拟器交互工具（经 MuMuManager 的 sh 通道）。

踩过的两个坑，都在这里处理掉：

1. App 跑在虚拟 display 上，不是主屏。MuMu 会开多个虚拟屏（有的纯黑），
   所以要探测「哪个 display 有内容」并缓存。
2. input 与 screencap 用的 **不是同一套 display 标识**：
     input     要逻辑 display id（0 / 29 / 30）
     screencap 要物理 token（46198278...，来自 uniqueId "local:xxx"）
   传错不会报错，只是静默无效 —— 之前点了半天没反应就是这个原因。

用法：
  python tool/ctrl.py tap X Y
  python tool/ctrl.py swipe X1 Y1 X2 Y2 [MS]
  python tool/ctrl.py text "ASCII 文本"
  python tool/ctrl.py key BACK|HOME|ENTER|DEL|TAB
  python tool/ctrl.py shot OUT.PNG [--crop-bottom N]
  python tool/ctrl.py displays
"""

import re
import subprocess
import sys
import tempfile

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
import time
from pathlib import Path

MM = r'D:/ruanjian/MuMuPlayer/nx_main/MuMuManager.exe'
SHARED = r'D:/Documents/MuMu共享文件夹/Download'

_app_keys = None  # (logical_id, token)
_cache = {}


def sh(cmd, timeout=40):
    result = subprocess.run(
        [MM, 'sh', '-v', '0', '-c', cmd],
        capture_output=True, text=True, timeout=timeout, errors='replace',
    )
    out = result.stdout.strip()
    if result.stderr.strip():
        out += '\n[stderr] ' + result.stderr.strip()
    return out


def display_map():
    """逻辑 display id ↔ 物理 token。"""
    out = sh('dumpsys display | grep mViewports')
    pairs = []
    for match in re.finditer(r"displayId=(\d+), uniqueId='local:(\d+)'", out):
        pairs.append((int(match.group(1)), int(match.group(2))))
    return pairs


def _luminance(path):
    from PIL import Image
    gray = Image.open(path).convert('L')
    w, h = gray.size
    region = gray.crop((w // 2 - 20, h // 2 - 20, w // 2 + 20, h // 2 + 20))
    pixels = list(region.getdata())
    return sum(pixels) / max(len(pixels), 1)


def resolve_keys(force=False):
    """找到 App 所在的 (逻辑 id, 物理 token)。

    优先非 0 的虚拟屏：display 0 是主屏（桌面/系统设置），
    如果 App 不在前台，主屏也能截到非黑画面，会误将主屏当成 App，
    后续点击就把系统界面点了。
    """
    global _app_keys
    if _app_keys and not force:
        return _app_keys

    from PIL import Image  # noqa: F401

    pairs = display_map()
    virtual = [(l, t) for l, t in pairs if l != 0]
    others = [(l, t) for l, t in pairs if l == 0]
    local = Path(SHARED) / '_probe.png'

    for logical, token in reversed(virtual):
        local.unlink(missing_ok=True)
        sh(f'screencap -d {token} -p /sdcard/Download/_probe.png')
        time.sleep(0.7)
        if not local.exists():
            continue
        try:
            if _luminance(local) >= 8:
                _app_keys = (logical, token)
                local.unlink(missing_ok=True)
                print(f'[ctrl] App: 逻辑 display {logical} / token {token}')
                return _app_keys
        except Exception:
            continue

    # 虚拟屏都是黑的：App 不在前台，退回主屏（仅用于截图确认状态）
    local.unlink(missing_ok=True)
    if others:
        print('[ctrl] 警告：App 不在前台（虚拟屏全黑），暂用主屏')
        _app_keys = others[0]
        return _app_keys
    raise SystemExit('找不到可用 display')


def tap(x, y):
    logical, _ = resolve_keys()
    sh(f'input -d {logical} tap {int(x)} {int(y)}')
    time.sleep(0.5)


def swipe(x1, y1, x2, y2, ms=250):
    logical, _ = resolve_keys()
    sh(f'input -d {logical} swipe {int(x1)} {int(y1)} {int(x2)} {int(y2)} {int(ms)}')
    time.sleep(0.6)


def key(name):
    logical, _ = resolve_keys()
    sh(f'input -d {logical} keyevent {name}')
    time.sleep(0.5)


def text(content):
    logical, _ = resolve_keys()
    safe = content.replace(' ', '%s').replace('"', '\\"')
    sh(f'input -d {logical} text "{safe}"')
    time.sleep(0.3)


def shot(out, half=True):
    from PIL import Image

    _, token = resolve_keys()
    local = Path(SHARED) / '_tap_shot.png'
    local.unlink(missing_ok=True)
    sh(f'screencap -d {token} -p /sdcard/Download/_tap_shot.png')
    time.sleep(0.9)
    if not local.exists():
        _, token = resolve_keys(force=True)
        local.unlink(missing_ok=True)
        sh(f'screencap -d {token} -p /sdcard/Download/_tap_shot.png')
        time.sleep(0.9)
    if not local.exists():
        raise SystemExit('截图未同步到共享目录')

    image_path = Path(out)
    image_path.parent.mkdir(parents=True, exist_ok=True)
    im = Image.open(local)
    if half:
        im.resize((im.width // 2, im.height // 2), Image.LANCZOS).save(image_path)
    else:
        im.save(image_path)
    local.unlink(missing_ok=True)
    print(f'已保存 {out}')


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    command = sys.argv[1]
    if command == 'displays':
        for logical, token in display_map():
            print(f'逻辑 {logical} / token {token}')
        return
    if command == 'tap':
        tap(sys.argv[2], sys.argv[3])
        return
    if command == 'swipe':
        ms = sys.argv[6] if len(sys.argv) > 6 else 250
        swipe(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], ms)
        return
    if command == 'text':
        text(' '.join(sys.argv[2:]))
        return
    if command == 'key':
        key(sys.argv[2])
        return
    if command == 'shot':
        out = sys.argv[2]
        crop_bottom = 0
        if '--crop-bottom' in sys.argv:
            crop_bottom = int(sys.argv[sys.argv.index('--crop-bottom') + 1])
        if crop_bottom:
            from PIL import Image
            # 用系统临时目录、不写死用户名：换台机器也能跑
            temp = str(Path(tempfile.gettempdir()) / 'pi-ctrl-temp.png')
            shot(temp, half=False)
            im = Image.open(temp)
            im.crop((0, im.height - crop_bottom, im.width, im.height)).save(out)
            Path(temp).unlink(missing_ok=True)
            print(f'已保存 {out}')
        else:
            shot(out)
        return
    raise SystemExit(f'未知命令: {command}')


if __name__ == '__main__':
    main()
