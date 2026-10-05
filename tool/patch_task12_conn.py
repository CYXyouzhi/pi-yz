# 把「扫描局域网 / 一键切换 / 诊断入口 / 启动向导」接进连接页。
#
# 为什么用补丁脚本而不是直接改文件：连接页有 400+ 行界面代码，
# 手工在中间插片段很容易插错位置；脚本用 assert 卡住每一处锚点，
# 对不上就直接报错，不会把文件改坏。

from pathlib import Path

p = Path('lib/ui/server/conn_page.dart')
s = p.read_text(encoding='utf-8')

# ---- A) 扫描区：插在「已保存」列表之前 ----
old_a = """            const SizedBox(height: 18),

            if (_profiles.isNotEmpty) ...["""
new_a = """            const SizedBox(height: 14),

            // ---- 局域网扫描（合同①）：不用手输 IP ----
            NeuPressable(
              onTap: _scanning ? null : _scan,
              radius: NeuRadii.md,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  NeuIcon(
                    _scanning ? IconId.spinner : IconId.sync,
                    size: 15,
                    color: t.accentInk,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    _scanning ? '正在扫局域网…' : '扫描局域网',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: t.accentInk,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (_scanNote != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _scanNote!,
                  style: TextStyle(fontSize: 11.5, height: 1.6, color: t.onBgDim),
                ),
              ),
            for (final server in _found)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: NeuPressable(
                  onTap: () => _useDiscovered(server),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      NeuIcon(IconId.server, size: 16, color: t.accentInk),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(server.name,
                                style: TextStyle(fontSize: 13.5, color: t.fg)),
                            Text(
                              '${server.endpoint} · pi ${server.piVersion}'
                              '${server.pairingOpen ? ' · 可配对' : ' · 未开配对窗口'}',
                              style: TextStyle(fontSize: 11.5, color: t.muted),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        server.pairingOpen ? '配对' : '选中',
                        style: TextStyle(fontSize: 12.5, color: t.accentInk),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 18),

            if (_profiles.isNotEmpty) ...["""
assert s.count(old_a) == 1, f'A 锚点命中 {s.count(old_a)} 次'
s = s.replace(old_a, new_a)

# ---- B) 已保存项：点一下 = 一键切换；右侧加「编辑」笔 ----
old_b1 = """                  onTap: () => setState(() => _fill(profile)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),"""
new_b1 = """                  // 点整行 = 一键切过去（合同②）；要改配置点右边那支笔
                  onTap: () => _switchTo(profile),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),"""
assert s.count(old_b1) == 1, f'B1 锚点命中 {s.count(old_b1)} 次'
s = s.replace(old_b1, new_b1)

old_b2 = """                      if (_editingId == profile.id)
                        NeuIcon(IconId.check, size: 16, color: t.accentInk),
                      const SizedBox(width: 8),
                      NeuPressable(
                        onTap: () => _delete(profile),"""
new_b2 = """                      if (_editingId == profile.id)
                        NeuIcon(IconId.check, size: 16, color: t.accentInk),
                      const SizedBox(width: 8),
                      NeuPressable(
                        onTap: () => setState(() => _fill(profile)),
                        radius: 10,
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: NeuIcon(IconId.pen, size: 14),
                        ),
                      ),
                      const SizedBox(width: 6),
                      NeuPressable(
                        onTap: () => _delete(profile),"""
assert s.count(old_b2) == 1, f'B2 锚点命中 {s.count(old_b2)} 次'
s = s.replace(old_b2, new_b2)

# ---- C) 底部：诊断入口 + 启动向导 ----
old_c = """            const SizedBox(height: 12),
            Text(
              '服务端启动方式：在远端执行 node index.mjs --host 0.0.0.0，'
              '启动时会打印监听地址与 token。',
              style: TextStyle(fontSize: 11.5, height: 1.7, color: t.onBgDim),
            ),"""
new_c = """            const SizedBox(height: 12),
            NeuPressable(
              onTap: _openDiagnose,
              radius: NeuRadii.md,
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  NeuIcon(IconId.info, size: 15, color: t.muted),
                  const SizedBox(width: 7),
                  Text('连接诊断（端口 / 延迟 / 鉴权逐项查）',
                      style: TextStyle(fontSize: 13.5, color: t.muted)),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ---- 服务端启动向导（合同④）：命令可一键复制 ----
            NeuRaised(
              radius: NeuRadii.lg,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      NeuIcon(IconId.terminal, size: 15, color: t.accentInk),
                      const SizedBox(width: 8),
                      Text('在电脑上启动服务端',
                          style: TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700, color: t.fg)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '方式一（推荐）：在电脑的 pi 里输入下面这行 —— 服务在后台跑，'
                    '并在终端打印手机该填的地址与 token。',
                    style: TextStyle(fontSize: 11.5, height: 1.7, color: t.onBgDim),
                  ),
                  const SizedBox(height: 6),
                  _cmdRow(t, _cmdViaPi, '命令'),
                  const SizedBox(height: 10),
                  Text(
                    '方式二：在 pi-mobile 目录里直接跑（前台运行，Ctrl+C 停止）',
                    style: TextStyle(fontSize: 11.5, height: 1.7, color: t.onBgDim),
                  ),
                  const SizedBox(height: 6),
                  _cmdRow(t, _cmdViaNode, '命令'),
                  const SizedBox(height: 10),
                  Text(
                    '启动后本页点「扫描局域网」就能直接找到这台电脑；'
                    '终端里那行「配对码」填进去即可，不用手动复制 token。',
                    style: TextStyle(fontSize: 11.5, height: 1.7, color: t.onBgDim),
                  ),
                ],
              ),
            ),"""
assert s.count(old_c) == 1, f'C 锚点命中 {s.count(old_c)} 次'
s = s.replace(old_c, new_c)

# ---- D) 命令行的渲染小部件 ----
old_d = """  Widget _field("""
new_d = """  /// 一行可复制的命令：整行都能点，免得手指戳不准那个小图标
  Widget _cmdRow(NeuTokens t, String command, String label) {
    return NeuPressable(
      onTap: () => _copy(command, label),
      radius: NeuRadii.sm,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              command,
              style: TextStyle(fontSize: 12.5, color: t.accentInk),
            ),
          ),
          const SizedBox(width: 8),
          NeuIcon(IconId.copy, size: 14, color: t.muted),
        ],
      ),
    );
  }

  Widget _field("""
assert s.count(old_d) == 1, f'D 锚点命中 {s.count(old_d)} 次'
s = s.replace(old_d, new_d)

p.write_text(s, encoding='utf-8')
print('conn_page.dart 已接上：扫描 / 一键切换 / 诊断入口 / 启动向导')
