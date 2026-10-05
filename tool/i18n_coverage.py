#!/usr/bin/env python3
"""界面文案的翻译覆盖情况（task-23）。

**三个必须同时看的数**（前两个版本只看第一个，漏掉了真问题）：

1. 仍在代码里的中文字面量 —— 逐行扫，**不跳过任何行**
2. 定义了但没有任何调用点引用的 i18n key —— 这类说明「英文写好了却没接上」
3. 已接上的调用点数（I18n.t + I18n.tp 都算）

只报第 3 个会产生「覆盖率很高但界面还是中文」的假象：审计就是这么抓出来的。

用法：python tool/i18n_coverage.py [--top 20]
"""
import re
import glob
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

# 中文字面量：单引号字符串里含中文
ZH = re.compile(r"'([^'\n]*[\u4e00-\u9fa5][^'\n]*)'")
# i18n.dart 里的词条：'key': ('中文', 'English'),
ENTRY = re.compile(r"^\s*'([^']+)':\s*\('([^']*)',\s*'([^']*)'\)", re.M)
# 调用点
CALL = re.compile(r"I18n\.(?:t|tp)\('([^']+)'")


def main():
    top = 20
    if '--top' in sys.argv:
        top = int(sys.argv[sys.argv.index('--top') + 1])

    i18n_src = open('lib/server/i18n.dart', encoding='utf-8').read()
    entries = {k: (zh, en) for k, zh, en in ENTRY.findall(i18n_src)}

    # 扫全 lib/ —— 之前只扫 lib/ui/，于是 lib/server/ 的运行时文案（通知/错误/
    # 活动标签）整片漏掉，审计就是这么抓出来的。i18n.dart 是词表本身，排除。
    # 注意：Windows 上 glob 返回的路径用反斜杠，判断前先归一化 —— 否则
    # i18n.dart（词表本身，600+ 条中文）会被当成"未翻译的界面文案"算进去。
    ui_files = []
    for f in sorted(glob.glob('lib/**/*.dart', recursive=True)):
        norm = f.replace(chr(92), '/')
        if norm.endswith('server/i18n.dart'):
            continue
        ui_files.append(norm)
    used_keys = set()
    # 也可能是 I18n.t(变量) 调用的（主题三档就是这么用的）：
    # 没法静态解析，就按「key 的前缀与某个变量调用的上下文同现」保守放过。
    dynamic_prefixes = set()
    for f in ui_files:
        text = open(f, encoding='utf-8').read()
        for m in re.finditer(r"I18n\.t[p]?\(\s*([A-Za-z_$][\w.$]*)", text):
            dynamic_prefixes.add(m.group(1))
    zh_rows = []
    for f in ui_files:
        text = open(f, encoding='utf-8').read()
        used_keys |= set(CALL.findall(text))
        # 键也可能存在变量或列表里（例：(ThemeMode.dark, 'theme.dark')），
        # 凡是作为字符串字面量出现过的 key 都算被引用
        used_keys |= set(re.findall(r"'([a-zA-Z][A-Za-z0-9_.]*)'", text))
        for i, line in enumerate(text.split('\n'), 1):
            if line.strip().startswith('//'):
                continue
            for m in ZH.finditer(line):
                s = m.group(1).strip()
                if s:
                    zh_rows.append((f, i, s))

    # 与变量调用同名前缀的 key 不计入「闲置」（例如 theme.* ← option.$2）
    def looks_dynamic(k):
        return any(k.startswith(prefix + '.') or prefix.startswith(k.split('.')[0])
                   for prefix in dynamic_prefixes if prefix)

    unused = {k: v for k, v in entries.items()
              if k not in used_keys and not looks_dynamic(k)}
    # 只关心「中文里还有汉字」的词条（纯英文的像 'pi-mobile' 不算）
    unused_zh = {k: v for k, v in unused.items() if re.search(r'[\u4e00-\u9fa5]', v[0])}

    print('=' * 68)
    print(f'① 代码里仍是中文字面量：{len(zh_rows)} 处')
    for f, i, s in zh_rows[:top]:
        print(f'     {f.split("/")[-1]}:{i}  {s[:52]}')
    if len(zh_rows) > top:
        print(f'     …另有 {len(zh_rows) - top} 处')

    print()
    print(f'② 定义了却没有调用点的 key：{len(unused)} 个（其中含中文的 {len(unused_zh)} 个）')
    for k, (zh, en) in list(unused_zh.items())[:top]:
        print(f'     {k}  {zh[:30]} → {en[:36]}')

    print()
    print(f'③ 已接上的 i18n 调用点：{len(used_keys)} 个 key 在用（词表共 {len(entries)} 条）')
    print('=' * 68)
    if len(zh_rows) == 0 and len(unused_zh) == 0:
        print('✅ 代码里没有中文残留，词表也没有闲置条目')
    else:
        print('⚠ 只要 ① 或 ② 不为 0，英文模式下就一定有中文漏出来')


if __name__ == '__main__':
    main()
