"""截取 MuMu 模拟器窗口（选面积最大的那个，必要时恢复显示）。

用法：python tool/shot.py [输出文件名] [--crop-bottom N]
"""

import ctypes
import sys
from ctypes import wintypes

from PIL import ImageGrab

user32 = ctypes.windll.user32

SW_RESTORE = 9
SW_SHOW = 5


def find_mumu_windows():
    found = []

    def callback(hwnd, _):
        if not user32.IsWindowVisible(hwnd):
            return True
        length = user32.GetWindowTextLengthW(hwnd)
        if length == 0:
            return True
        buf = ctypes.create_unicode_buffer(length + 1)
        user32.GetWindowTextW(hwnd, buf, length + 1)
        title = buf.value
        # MuMu 的安卓窗口标题是「MuMu安卓设备」
        if 'MuMu' in title and '模' not in title and '模' not in title:
            rect = wintypes.RECT()
            user32.GetWindowRect(hwnd, ctypes.byref(rect))
            area = (rect.right - rect.left) * (rect.bottom - rect.top)
            found.append((area, hwnd, title, rect))
        return True

    proc = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)
    user32.EnumWindows(proc(callback), 0)
    found.sort(key=lambda item: -item[0])
    return found


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else 'shot.png'
    crop_bottom = 0
    if '--crop-bottom' in sys.argv:
        crop_bottom = int(sys.argv[sys.argv.index('--crop-bottom') + 1])

    windows = find_mumu_windows()
    if not windows:
        print('未找到 MuMu 窗口')
        return 1

    for area, hwnd, title, rect in windows[:3]:
        print(f'候选窗口: {title!r} 区域={rect.left},{rect.top},{rect.right},{rect.bottom} 面积={area}')

    area, hwnd, title, rect = windows[0]
    # 最小化时 rect 会是负值/异常，先恢复
    if rect.right - rect.left < 400:
        user32.ShowWindow(hwnd, SW_RESTORE)
        user32.SetForegroundWindow(hwnd)
        import time
        time.sleep(1.2)
        user32.GetWindowRect(hwnd, ctypes.byref(rect))

    image = ImageGrab.grab(bbox=(rect.left, rect.top, rect.right, rect.bottom))
    if crop_bottom:
        width, height = image.size
        image = image.crop((0, height - crop_bottom, width, height))
    image.save(out)
    print(f'已保存 {out} 尺寸={image.size}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
