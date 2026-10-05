# -*- coding: utf-8 -*-
"""i18n 六项审计。

为什么要比 i18n_coverage.py 多做几项：覆盖率脚本只查「中文字面量」和
「定义了却没调用点」，于是三类真缺陷看不见 ——
  1) 引用了但词表里没有的 key（I18n.t 找不到就原样返回 key，界面直接显示
     `lang.zh` 这种内部串）；而且这类 key 常常是**动态**取用的
     （`I18n.t(option.$2)`），只扫 `I18n.t('字面量')` 同样看不见；
  2) 某个调用点传给 tp 的参数名与词条占位符不一致（界面显示 `{n}`）；
     旧检查把同一 key 在所有调用点传的参数取**并集**，会让「别处传对了」
     掩盖「这里传错了」，本脚本**逐调用点**检查；
  3) 词条值写得不对：中文值里残留 `${...}`（中文模式显示 `${ext}` 字面量）、
     或**值被截断**（历史上正则解析词条行时被值内的 \\' 截断过，写回就成了半截串）、
     或英文值里混进中文、或中英文占位符集合不一致。

解析词条行**不用正则**：改为找 `': ('` 与最后一个 `', '` 手工切分，
这样值里出现 \\' 或 ', ' 都不会把匹配弄断。

用法：python tool/i18n_audit.py   （六项全 0 时退出码 0）
"""
import glob
import re
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

BS = chr(92)
I18N_FILE = 'lib/server/i18n.dart'

ZH_LIT = re.compile(r"'[^'\n]*[\u4e00-\u9fa5][^'\n]*'")
PH = re.compile(r'\{([^{}]*)\}')
LIT_CALL = re.compile(r"I18n\.(t|tp)\(\s*'([^']+)'")
ANY_STR = re.compile(r"'([a-zA-Z][A-Za-z0-9_.]*)'")
PREFIXES = ('lang', 'theme', 'tab', 'common', 'ui', 'start', 'chat', 'nav', 'app')
KEYLIKE = re.compile(r"'((?:%s)\.[A-Za-z0-9_.]+)'" % '|'.join(PREFIXES))
TP_CALL = re.compile(r"I18n\.tp\(\s*'([^']+)'\s*,\s*\{")
# 值被截断的痕迹：以这些符号结尾，说明当年的解析在中途断了
BROKEN_TAIL = ('.', '(', '[', 'split(', 'replaceFirst(', '${', ',')


def norm(p):
    return p.replace(BS, '/')


def parse_entry(line):
    """解析一行词条：'key': ('zh', 'en'),  —— 手工切分，不用正则。"""
    t = line.strip()
    if not t.startswith("'") or not t.endswith("'),"):
        return None
    i = t.find("': ('")
    if i < 0:
        return None
    body = t[i + 5:-3]
    j = body.rfind("', '")
    if j < 0:
        return None
    return t[1:i], body[:j], body[j + 4:]


def load_entries():
    ents = {}
    for line in Path(I18N_FILE).read_text(encoding='utf-8').split('\n'):
        e = parse_entry(line)
        if e:
            ents[e[0]] = (e[1], e[2])
    return ents


def dart_files():
    return [f for f in glob.glob('lib/**/*.dart', recursive=True)
            if norm(f) != I18N_FILE]


def scan():
    zh_rows, literals, lit_calls, tp_calls, keylike = [], set(), [], [], set()
    for f in dart_files():
        text = Path(f).read_text(encoding='utf-8')
        for i, line in enumerate(text.split('\n'), 1):
            if line.strip().startswith('//'):
                continue
            for m in ZH_LIT.finditer(line):
                zh_rows.append((norm(f), i, m.group(0)))
            literals |= set(ANY_STR.findall(line))
        keylike |= set(KEYLIKE.findall(text))
        for m in LIT_CALL.finditer(text):
            lit_calls.append((norm(f), text[:m.start()].count('\n') + 1,
                             m.group(1), m.group(2)))
        # tp 调用点：花括号配对取参数表，支持跨行
        for m in TP_CALL.finditer(text):
            depth, j = 0, m.end() - 1
            while j < len(text):
                if text[j] == '{':
                    depth += 1
                elif text[j] == '}':
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            args = set(re.findall(r"'(\w+)':", text[m.end() - 1:j]))
            tp_calls.append((norm(f), text[:m.start()].count('\n') + 1, m.group(1), args))
    # 词表文件自身的内部引用（describe() 里的裸 t('key')）也算「被引用」，
    # 否则那条词条会被 ② 误报成闲置。
    inner = Path(I18N_FILE).read_text(encoding='utf-8')
    literals |= set(re.findall(r"(?<![\w.])t[p]?\(\s*'((?:%s)\.[A-Za-z0-9_.]+)'"
                            % '|'.join(PREFIXES), inner))
    return zh_rows, literals, lit_calls, tp_calls, keylike


def main():
    ents = load_entries()
    zh_rows, literals, lit_calls, tp_calls, keylike = scan()
    problems = 0
    print('=' * 70)
    print(f'词表条目：{len(ents)}')

    print(f'① 代码里仍是中文字面量：{len(zh_rows)} 处')
    for f, i, s in zh_rows[:10]:
        print(f'     {f}:{i}  {s[:52]}')
    problems += len(zh_rows)

    no_call = [k for k in ents
               if k not in literals and k not in {c[3] for c in lit_calls}]
    print(f'② 定义了却没有引用：{len(no_call)} 个')
    for k in no_call[:10]:
        print(f'     {k}  {ents[k][0][:34]}')
    problems += len(no_call)

    # ③ 引用未定义：字面调用 ∪ 形如 key 的字符串字面量（含动态取用的）
    referenced = {c[3] for c in lit_calls} | keylike
    undef = sorted(k for k in referenced if k not in ents)
    print(f'③ 引用了却未定义（界面会显示内部 key）：{len(undef)} 个')
    for k in undef[:12]:
        sites = [f'{Path(f).name}:{i}' for f, i, fn, kk in lit_calls if kk == k][:3]
        where = ', '.join(sites) if sites else '（动态取用）'
        print(f'     {k}  ← {where}')
    problems += len(undef)

    bad_tp = []
    for f, i, k, args in tp_calls:
        if k not in ents:
            continue
        missing = {x for x in (set(PH.findall(ents[k][0])) | set(PH.findall(ents[k][1])))
                   if x not in args}
        if missing:
            bad_tp.append((f, i, k, sorted(missing), sorted(args), ents[k][0][:26]))
    print(f'④ 逐调用点 tp 参数不匹配：{len(bad_tp)} 个调用点')
    for f, i, k, missing, args, zh in bad_tp[:12]:
        print(f'     {Path(f).name}:{i}  {k}  缺 {missing}  传了 {args}  | {zh}')
    problems += len(bad_tp)

    # ⑤ 英文值里含中文（lang.* 除外：语言名按惯例用其自身语言显示）
    zh_in_en = [(k, v[1]) for k, v in ents.items()
                if re.search(r'[\u4e00-\u9fa5]', v[1]) and not k.startswith('lang.')]
    print(f'⑤ 英文值里含中文（英文模式会漏中文）：{len(zh_in_en)} 条')
    for k, v in zh_in_en[:8]:
        print(f'     {k}  {v[:44]}')
    problems += len(zh_in_en)

    ph_mismatch = [k for k, (zh, en) in ents.items()
                   if sorted(PH.findall(zh)) != sorted(PH.findall(en))]
    print(f'⑥ 中英文占位符集合不一致：{len(ph_mismatch)} 条')
    for k in ph_mismatch[:8]:
        print(f'     {k}  ZH:{ents[k][0][:30]}  EN:{ents[k][1][:30]}')
    problems += len(ph_mismatch)

    broken = []
    for k, v in ents.items():
        zh = v[0]
        why = []
        if BS + '${' in zh:
            why.append('插值残留（应直接写 {n}）')
        if (BS + BS) in zh:
            why.append('双重转义')
        if zh.endswith(BROKEN_TAIL):
            why.append('疑似截断')
        if re.search(re.escape(BS + chr(39)), zh):
            why.append('代码残片')
        if why:
            broken.append((k, zh + '   <- ' + '、'.join(why)))

    print(f'⑦ 中文值疑似被截断或残留插值：{len(broken)} 条')
    for k, v in broken[:10]:
        print(f'     {k}  {v[:52]!r}')
    problems += len(broken)
    # ⑧ 用 t() 调用了含占位符的词条：占位符不会被替换，界面直接显示 {n}
    bad_t = []
    for f, i, fn, k in lit_calls:
        if fn != 't' or k not in ents:
            continue
        if PH.findall(ents[k][0]) or PH.findall(ents[k][1]):
            bad_t.append((f, i, k, ents[k][0][:34]))
    print(f'⑧ 用 t() 调用含占位符的词条（应改用 tp）：{len(bad_t)} 个调用点')
    for f, i, k, zh in bad_t[:12]:
        print(f'     {Path(f).name}:{i}  {k}  {zh}')
    problems += len(bad_t)


    # ⑨ 词表文件**自身**引用的 key 是否都已定义。
    # 为什么单独查：dart_files() 为了不把词条值当成漏翻文案而排除了 i18n.dart，
    # 于是从 describe() 这类内部方法引用未定义 key 就成了盲区
    # （common.untranslated 正是这样漏过了一整轮）。
    # 注意内部调用写的是裸 t('key')，而不是 I18n.t('key')。
    inner = Path(I18N_FILE).read_text(encoding='utf-8')
    inner_refs = set(re.findall(r"(?<![\w.])t[p]?\(\s*'((?:%s)\.[A-Za-z0-9_.]+)'"
                                % '|'.join(PREFIXES), inner))
    inner_undef = sorted(k for k in inner_refs if k not in ents)
    print(f'⑨ 词表自身引用了却未定义：{len(inner_undef)} 个')
    for k in inner_undef[:10]:
        print(f'     {k}')
    problems += len(inner_undef)
    print('=' * 70)
    print('✅ 九项全部为 0' if problems == 0 else f'⚠ 共 {problems} 个问题待处理')
    return 0 if problems == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
