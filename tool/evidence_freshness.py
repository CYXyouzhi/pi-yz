#!/usr/bin/env python
"""证据新鲜度门禁：截图必须晚于 APK，APK 必须晚于源码。

## 为什么需要这道门禁

这套验证流程里最容易犯、也最难自己发现的错，是**拿旧构建的截图当新改动的证据**：

  · 改完代码忘了重新构建，直接装旧 APK 截图；
  · 为了修正则误删，从备份恢复某个文件，把另一处改动一起带走了；
  · 截图拍完又改了一行代码，图还在文档里当证据用。

三种情况下截图**看起来都完全正常** —— 它证明的只是旧版本。本轮迭代里审计
抓出过好几次这种问题，而我自己没发现。

## 判据

一条时间链，必须单调不减（容忍 `--tol` 秒的文件系统粒度）：

    源码最后修改  ≤  APK 构建时间  ≤  截图文件时间

任何一环倒退，就说明「这张图证明不了当前源码」。

> 注意它**不能**证明图里的内容对 —— 只证明「图是这份代码构建出来的产物」。
> 内容对不对要靠人看图和 contract 清单。

## 用法

    python tool/evidence_freshness.py docs/verify/space-rework/*.png
    python tool/evidence_freshness.py --apk build/app/outputs/flutter-apk/app-debug.apk shots/*.png
    python tool/evidence_freshness.py --selftest        # 自检门禁本身有效

退出码：0 = 全部新鲜；1 = 有过期或缺失的证据。
"""

from __future__ import annotations

import argparse
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# 参与构建产物的源码范围。改动这些文件里的任何一个，都该重新构建以后再截图。
SOURCE_GLOBS = (
    "lib/**/*.dart",
    "test/**/*.dart",
    "pubspec.yaml",
    "android/app/build.gradle",
    "android/app/build.gradle.kts",
    "android/build.gradle",
)

APK_CANDIDATES = (
    "build/app/outputs/flutter-apk/app-debug.apk",
    "build/app/outputs/flutter-apk/app-release.apk",
)

TOL = 2.0  # 秒。文件系统时间粒度与「同一秒内先构建后截图」都靠它兜住


def fmt(ts: float) -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(ts))


def rel(p: Path | None) -> str:
    if p is None:
        return "(无)"
    try:
        return str(p.relative_to(ROOT))
    except ValueError:
        return str(p)


def newest_source() -> tuple[float, Path | None]:
    """参与构建的源码里，最后被修改的那个的时间与路径。"""
    newest, path = 0.0, None
    for pattern in SOURCE_GLOBS:
        for p in ROOT.glob(pattern):
            m = p.stat().st_mtime
            if m > newest:
                newest, path = m, p
    return newest, path


def newest_apk(explicit: str | None) -> tuple[float, Path | None]:
    """最新的 APK。显式指定时只用一个。"""
    if explicit:
        p = Path(explicit)
        if not p.is_absolute():
            p = ROOT / p
        return (p.stat().st_mtime, p) if p.exists() else (0.0, None)
    best: tuple[float, Path | None] = (0.0, None)
    for c in APK_CANDIDATES:
        p = ROOT / c
        if p.exists():
            m = p.stat().st_mtime
            if m > best[0]:
                best = (m, p)
    return best


def check(src_t: float, src_p: Path | None, apk_t: float, apk_p: Path | None,
          shots: list[str], tol: float) -> list[str]:
    """返回问题清单，空列表 = 通过。抽出来是为了 --selftest 能直接调。"""
    bad: list[str] = []
    if apk_p is None:
        bad.append("找不到 APK —— 无法证明任何截图是当前源码构建的")
        return bad
    if apk_t + tol < src_t:
        bad.append(
            f"APK 比源码旧 {(src_t - apk_t) / 60:.1f} 分钟"
            f"（源码 {rel(src_p)}）—— 先重新构建再截图"
        )
    for s in shots:
        p = Path(s)
        if not p.is_absolute():
            p = ROOT / p
        if not p.exists():
            bad.append(f"{s} 不存在")
            continue
        t = p.stat().st_mtime
        if t + tol < apk_t:
            bad.append(f"{s} 早于 APK {(apk_t - t) / 60:.1f} 分钟")
        if t + tol < src_t:
            bad.append(f"{s} 早于源码 {(src_t - t) / 60:.1f} 分钟")
    return bad


def selftest() -> int:
    """自检：确认这道门禁真的能拦下过期证据，而不是恒返回 0。"""
    print("=== 自检：门禁能否拦下过期证据 ===")
    failures = []
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        shot = tmp / "shot.png"
        shot.write_bytes(b"x")

        base = 1_700_000_000.0
        cases = [
            ("全部新鲜（图 > APK > 源码）", base, base + 10, base + 20, []),
            ("APK 早于源码", base + 10, base, base + 20, ["apk"]),
            ("截图早于 APK", base, base + 10, base + 5, ["shot"]),
            # APK 晚于源码（这一环没问题），只有图早于两者
            ("截图早于源码", base + 10, base + 20, base, ["shot"]),
        ]
        for name, src_t, apk_t, shot_t, expect in cases:
            _setmtime(shot, shot_t)
            issues = check(src_t, tmp / "src.dart", apk_t, tmp / "app.apk",
                           [str(shot)], TOL)
            got = "干净" if not issues else "拦下"
            want = "干净" if not expect else "拦下"
            kinds = []
            if any("APK 比源码旧" in i or "找不到 APK" in i for i in issues):
                kinds.append("apk")
            if any(i.startswith(str(shot)) for i in issues):
                kinds.append("shot")
            ok = got == want and set(kinds) == set(expect)
            print(f"  {'✓' if ok else '✗'} {name}: 期望 {want}{expect}，实际 {got}{kinds}")
            if not ok:
                failures.append(name)

    print()
    if failures:
        print(f"自检失败：{', '.join(failures)}")
        return 1
    print("自检通过：四种场景的判定都符合预期")
    return 0


def _setmtime(p: Path, ts: float) -> None:
    import os

    os.utime(p, (ts, ts))


def main() -> int:
    ap = argparse.ArgumentParser(description="证据新鲜度门禁")
    ap.add_argument("shots", nargs="*", help="截图路径")
    ap.add_argument("--apk", help="显式指定 APK（默认取 build 下最新的一个）")
    ap.add_argument("--tol", type=float, default=TOL, help=f"时间倒挂容忍秒数（默认 {TOL}）")
    ap.add_argument("--selftest", action="store_true", help="自检门禁本身")
    a = ap.parse_args()

    if a.selftest:
        return selftest()

    if not a.shots:
        ap.error("至少给一个截图路径，或用 --selftest")

    src_t, src_p = newest_source()
    apk_t, apk_p = newest_apk(a.apk)

    print("=== 证据新鲜度门禁 ===")
    print(f"源码最新改动 : {fmt(src_t)}  {rel(src_p)}")
    print(f"APK 构建时间 : {fmt(apk_t)}  {rel(apk_p)}")
    print()
    print("截图：")
    for s in a.shots:
        p = Path(s)
        if not p.is_absolute():
            p = ROOT / p
        if p.exists():
            print(f"  · {s}  {fmt(p.stat().st_mtime)}")
        else:
            print(f"  · {s}  (不存在)")
    print()

    bad = check(src_t, src_p, apk_t, apk_p, a.shots, a.tol)
    if bad:
        print(f"✗ 门禁不通过（{len(bad)} 项）：")
        for b in bad:
            print(f"    - {b}")
        return 1
    print("✓ 门禁通过：所有证据都晚于源码与 APK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
