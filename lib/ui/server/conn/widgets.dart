import 'package:flutter/material.dart';

import '../../../server/discovery.dart';
import '../../../server/server_profile.dart';
import '../../../server/i18n.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../neu_icons.dart';
import '../../neu_section.dart';

/// _cmdRow 的组件化版本。
class CmdRow extends StatelessWidget {
  const CmdRow({super.key, required this.command, required this.label, required this.onCopy});

  final String command;
  final String label;
  final void Function(String text, String label) onCopy;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return NeuPressable(
        onTap: () => onCopy(command, label),
        radius: NeuRadii.sm,
        padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                command,
                style: TextStyle(fontSize: NeuFonts.sub, color: t.accentInk),
              ),
            ),
            const SizedBox(width: NeuSpace.n8),
            NeuIcon(IconId.copy, size: 14, color: t.muted),
          ],
        ),
      );
  }
}

/// _tunnelOption 的组件化版本。
class TunnelOption extends StatelessWidget {
  const TunnelOption({super.key, required this.value, required this.current, required this.onPick});

  final String value;
  final String current;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final selected = current == value;
      final isCf = value == 'cloudflare';
      final label = I18n.t(isCf ? 'remote.optCloudflare' : 'remote.optSsh');
      final hint = I18n.t(isCf ? 'remote.optCloudflareHint' : 'remote.optSshHint');
      return NeuPressable(
        onTap: () => onPick(value),
        radius: NeuRadii.sm,
        // 选中 = 按进去（设计稿 .wsg-item.active 的那套语义）
        flat: !selected,
        alwaysInset: selected,
        padding:
            const EdgeInsets.symmetric(horizontal: NeuSpace.n10, vertical: NeuSpace.n10),
        child: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? t.accentInk : t.muted, width: 2),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration:
                            BoxDecoration(shape: BoxShape.circle, color: t.accentInk),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: NeuSpace.n8),
            // 名称不允许被压掉（它是选项的主信息），说明文字才让位
            Text(label,
                maxLines: 1,
                style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.fg)),
            const SizedBox(width: NeuSpace.n8),
            Expanded(
              child: Text(hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: NeuFonts.label, color: t.muted)),
            ),
          ],
        ),
      );
  }
}

/// _ownToolSection 的组件化版本。
class OwnToolSection extends StatelessWidget {
  const OwnToolSection({super.key, required this.ownRemote, required this.onSave});

  final TextEditingController? ownRemote;
  final Future<void> Function(String raw) onSave;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(I18n.t('remote.ownTitle'),
              style: TextStyle(
                  fontSize: NeuFonts.bodySmall,
                  fontWeight: FontWeight.w700,
                  color: t.fg)),
          const SizedBox(height: NeuSpace.n2),
          Text(I18n.t('remote.ownHint'),
              style: TextStyle(fontSize: NeuFonts.label, height: 1.5, color: t.muted)),
          const SizedBox(height: NeuSpace.n8),
          TextField(
            controller: ownRemote,
            style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.fg),
            decoration: InputDecoration(
              hintText: I18n.t('remote.ownPlaceholder'),
              hintStyle: TextStyle(fontSize: NeuFonts.label, color: t.muted),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(NeuRadii.sm)),
            ),
            onSubmitted: onSave,
          ),
          const SizedBox(height: NeuSpace.n8),
          NeuPressable(
            onTap: () => onSave(ownRemote?.text ?? ''),
            radius: NeuRadii.sm,
            padding: EdgeInsets.symmetric(vertical: NeuSpace.n10),
            child: Center(
              child: Text(I18n.t('remote.ownSave'),
                  style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.accentInk)),
            ),
          ),
        ],
      );
  }
}

/// 连接页的标题栏：返回键 + 标题 + 一句副标题。
///
/// 抽出来是因为它**不依赖页面任何状态** —— 纯粹是「返回 + 标题 + 说明」。
/// 不持有状态，所以做成 StatelessWidget 是最自然的。
class ConnPageHeader extends StatelessWidget {
  const ConnPageHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            NeuPressable(
              onTap: () => Navigator.of(context).maybePop(),
              radius: 12,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n12),
                child: NeuIcon(IconId.chevronLeft, size: 16),
              ),
            ),
            SizedBox(width: NeuSpace.n10),
            Text(
              I18n.t('ui.b1a9635c77'),
              style: TextStyle(
                fontSize: NeuFonts.pageTitle,
                fontWeight: FontWeight.w700,
                color: t.onBg,
              ),
            ),
          ],
        ),
        SizedBox(height: NeuSpace.n6),
        Text(
          I18n.t('ui.445cf3f727'),
          style: TextStyle(fontSize: NeuFonts.sub, color: t.onBgDim),
        ),
        const SizedBox(height: NeuSpace.n14),
      ],
    );
  }
}

/// 「快速连接」分组：分组头 + 局域网扫描按钮。
///
/// **内容真的跟着收起/展开** —— 之前出过一个 bug：只画一个带箭头的标题、
/// 内容却无条件渲染，点标题只会翻转箭头，块根本折不起来。
/// （审计把「_section(...) 带 onToggle」和「内容有没有包在 if 里」对了一遍才抓到的。）
///
/// 展开状态**不在组件里** —— 它存在页面的 `_expanded` 集合中（切页不丢），
/// 组件只负责画 + 回调。
class QuickConnectSection extends StatelessWidget {
  const QuickConnectSection({
    super.key,
    required this.expanded,
    required this.scanning,
    required this.onToggle,
    required this.onScan,
    required this.onDiagnose,
    required this.scanNote,
    required this.found,
    required this.onUseDiscovered,
  });

  final bool expanded;

  /// 正在扫描：按钮变 spinner 且不可再点（避免叠着发起两次扫描）。
  final bool scanning;

  /// 扫描后的一句提示（「找到 2 台」「没找到，检查是否同一网络」…）。
  /// 没扫过时为 null。
  final String? scanNote;

  /// 扫描发现的服务器。点一台直接切过去。
  final List<DiscoveredServer> found;

  final VoidCallback onToggle;
  final VoidCallback onScan;
  final VoidCallback onDiagnose;
  final ValueChanged<DiscoveredServer> onUseDiscovered;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NeuSection(
          title: I18n.t('conn.groupQuick'),
          icon: IconId.sync,
          summary: I18n.t('ui.e33ff6aad6'),
          open: expanded,
          onToggle: onToggle,
        ),
        if (expanded) ...[
          // ---- 局域网扫描（合同①）：不用手输 IP ----
          NeuPressable(
            onTap: scanning ? null : onScan,
            radius: NeuRadii.md,
            padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                NeuIcon(
                  scanning ? IconId.spinner : IconId.sync,
                  size: 15,
                  color: t.accentInk,
                ),
                SizedBox(width: NeuSpace.n7),
                Text(
                  scanning ? I18n.t('ui.eb0bc967a8') : I18n.t('ui.3a8e52efff'),
                  style: TextStyle(
                    fontSize: NeuFonts.bodyMid,
                    color: t.accentInk,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: NeuSpace.n10),

          // ---- 连接诊断（合同③）：把「连不上」拆成能动手的原因 ----
          NeuPressable(
            onTap: onDiagnose,
            radius: NeuRadii.md,
            padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                NeuIcon(IconId.sync, size: 15, color: t.muted),
                const SizedBox(width: NeuSpace.n7),
                Text(
                  I18n.t('ui.diagnoseBtn'),
                  style: TextStyle(
                    fontSize: NeuFonts.bodyMid,
                    color: t.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (scanNote != null)
            Padding(
              padding: const EdgeInsets.only(top: NeuSpace.n8),
              child: Text(
                scanNote!,
                style: TextStyle(fontSize: NeuFonts.label, height: 1.6, color: t.onBgDim),
              ),
            ),
          for (final server in found)
            Padding(
              padding: const EdgeInsets.only(top: NeuSpace.n8),
              child: NeuPressable(
                onTap: () => onUseDiscovered(server),
                padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n10),
                child: Row(
                  children: [
                    NeuIcon(IconId.server, size: 16, color: t.accentInk),
                    const SizedBox(width: NeuSpace.n10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(server.name,
                              style: TextStyle(fontSize: NeuFonts.bodyMid, color: t.fg)),
                          Text(
                            '${server.endpoint} · pi ${server.piVersion}'
                            '${server.pairingOpen ? I18n.t('ui.b4912bca07') : I18n.t('ui.3b07ed0da7')}',
                            style: TextStyle(fontSize: NeuFonts.label, color: t.muted),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      server.pairingOpen ? I18n.t('ui.e33ff6aad6') : I18n.t('ui.fad7c8a21f'),
                      style: TextStyle(fontSize: NeuFonts.sub, color: t.accentInk),
                    ),
                  ],
                ),
              ),
            ),
          SizedBox(height: NeuSpace.n18),
        ],
      ],
    );
  }
}

/// 连接动作区：测试结果条 + 「测试连接 / 保存并连接」+ 诊断入口。
///
/// 测试结果不单独弹 toast，而是**常驻在按钮上方**（`testResult`）——
/// 用户点完测试往往要看一眼结果再决定下一步，弹出来 3 秒消失反而碍事。
class ConnectionActions extends StatelessWidget {
  const ConnectionActions({
    super.key,
    required this.testResult,
    required this.testOk,
    required this.testing,
    required this.onTest,
    required this.onSaveAndConnect,
    required this.onDiagnose,
  });

  /// 上次测试的结果文案；没测过时为 null（那条提示就不显示）。
  final String? testResult;

  /// 测试是否通过 —— 决定结果条的图标与颜色（对勾/警告）。
  final bool testOk;

  /// 正在测试：按钮变 spinner 且不可再点。
  final bool testing;

  final VoidCallback onTest;
  final VoidCallback onSaveAndConnect;
  final VoidCallback onDiagnose;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (testResult != null)
          Padding(
            padding: const EdgeInsets.only(bottom: NeuSpace.n10),
            child: Row(
              children: [
                NeuIcon(
                  testOk ? IconId.check : IconId.warn,
                  size: 14,
                  color: testOk ? t.success : t.danger,
                ),
                const SizedBox(width: NeuSpace.n8),
                Expanded(
                  child: Text(
                    testResult!,
                    style: TextStyle(fontSize: NeuFonts.sub, color: testOk ? t.success : t.danger),
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: NeuPressable(
                onTap: testing ? null : onTest,
                radius: NeuRadii.md,
                padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (testing)
                      NeuIcon(IconId.spinner, size: 15, color: t.muted)
                    else
                      NeuIcon(IconId.sync, size: 15, color: t.muted),
                    SizedBox(width: NeuSpace.n7),
                    Text(I18n.t('ui.69e74756bc'),
                        style: TextStyle(fontSize: NeuFonts.bodyTight, color: t.muted)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: NeuSpace.n10),
            Expanded(
              child: NeuPressable(
                onTap: onSaveAndConnect,
                radius: NeuRadii.md,
                padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    NeuIcon(IconId.power, size: 15, color: t.accentInk),
                    SizedBox(width: NeuSpace.n7),
                    Text(
                      I18n.t('ui.e8ba811b3f'),
                      style: TextStyle(
                          fontSize: NeuFonts.bodyTight, color: t.accentInk, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: NeuSpace.n12),
        NeuPressable(
          onTap: onDiagnose,
          radius: NeuRadii.md,
          padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              NeuIcon(IconId.info, size: 15, color: t.muted),
              SizedBox(width: NeuSpace.n7),
              Text(I18n.t('ui.d0bacac615'),
                  style: TextStyle(fontSize: NeuFonts.bodyMid, color: t.muted)),
            ],
          ),
        ),
      ],
    );
  }
}

/// 服务端启动向导：两条命令 + 一键复制。
///
/// 两条命令**并排给**：`/mobile start` 是已经在 pi 里时最快的，
/// `node server/index.mjs` 是从零起服务端用的。不替用户选，各给一条。
class ServerStartupGuide extends StatelessWidget {
  const ServerStartupGuide({super.key, required this.onCopy});

  /// 复制命令。动作留在页面（要弹 toast），组件只报告要复制什么。
  /// 收 (命令文本, 显示名) 两个参数，与 CmdRow 一致。
  final void Function(String text, String label) onCopy;

  static const String _cmdViaPi = '/mobile start';
  static const String _cmdViaNode = 'node server/index.mjs --host 0.0.0.0';

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return NeuRaised(
      radius: NeuRadii.lg,
      padding: const EdgeInsets.all(NeuSpace.n14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              NeuIcon(IconId.terminal, size: 15, color: t.accentInk),
              SizedBox(width: NeuSpace.n8),
              Text(I18n.t('ui.fb75dd5ecd'),
                  style: TextStyle(
                      fontSize: NeuFonts.bodyMid, fontWeight: FontWeight.w700, color: t.fg)),
            ],
          ),
          SizedBox(height: NeuSpace.n10),
          Text(
            // ignore: prefer_interpolation_to_compose_strings
            '${I18n.t('ui.da96bf7843')}'
            '${I18n.t('ui.e28ad37f63')}',
            style: TextStyle(fontSize: NeuFonts.label, height: 1.7, color: t.onBgDim),
          ),
          SizedBox(height: NeuSpace.n6),
          CmdRow(
            command: _cmdViaPi,
            label: I18n.t('common.command'),
            onCopy: onCopy,
          ),
          SizedBox(height: NeuSpace.n10),
          Text(
            I18n.t('ui.282652e49f'),
            style: TextStyle(fontSize: NeuFonts.label, height: 1.7, color: t.onBgDim),
          ),
          SizedBox(height: NeuSpace.n6),
          CmdRow(
            command: _cmdViaNode,
            label: I18n.t('common.command'),
            onCopy: onCopy,
          ),
          SizedBox(height: NeuSpace.n10),
          Text(
            // ignore: prefer_interpolation_to_compose_strings
            '${I18n.t('ui.e2c2055ec7')}'
            '${I18n.t('ui.44d23ca46b')}',
            style: TextStyle(fontSize: NeuFonts.label, height: 1.7, color: t.onBgDim),
          ),
        ],
      ),
    );
  }
}

/// 「已保存的服务器」分组：分组头（带「＋新增」）+ 展开后的配置列表。
///
/// **点整行 = 一键切过去**（合同②）；要改配置点右边那支笔。
/// 没有「＋新增」这个入口的话，用户就只能改现有配置，永远存不下第二台机器。
///
/// 展开状态存在页面的 `_expanded` 里，组件不持有状态 —— 只画 + 回调。
class SavedProfilesSection extends StatelessWidget {
  const SavedProfilesSection({
    super.key,
    required this.profiles,
    required this.editingId,
    required this.expanded,
    required this.onToggle,
    required this.onSwitchTo,
    required this.onEdit,
    required this.onDelete,
    required this.onNew,
  });

  final List<ServerProfile> profiles;

  /// 正在编辑的那台配置 id；那一行会高亮并显示对勾。
  final String? editingId;

  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<ServerProfile> onSwitchTo;
  final ValueChanged<ServerProfile> onEdit;
  final ValueChanged<ServerProfile> onDelete;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    if (profiles.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: NeuSection(
                title: I18n.t('ui.f8dfedcd8a'),
                icon: IconId.server,
                summary: '${profiles.length}',
                open: expanded,
                onToggle: onToggle,
              ),
            ),
            // Spacer 交给 Expanded + NeuSection
            NeuPressable(
              onTap: onNew,
              radius: 10,
              padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n14, vertical: NeuSpace.n10),
              child: Row(
                children: [
                  NeuIcon(IconId.plus, size: 13, color: t.accentInk),
                  SizedBox(width: NeuSpace.n4),
                  Text(I18n.t('ui.66ab5e9f24'),
                      style: TextStyle(fontSize: NeuFonts.sub, color: t.accentInk)),
                ],
              ),
            ),
          ],
        ),
        // 内容必须真的跟着收起/展开，不能只翻箭头（审计抓过一次）
        if (expanded) ...[
          const SizedBox(height: NeuSpace.n8),
          for (final profile in profiles)
            NeuPressable(
              flat: editingId != profile.id,
              alwaysInset: editingId == profile.id,
              onTap: () => onSwitchTo(profile),
              padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n10),
              margin: const EdgeInsets.only(bottom: NeuSpace.n6),
              child: Row(
                children: [
                  NeuIcon(IconId.server, size: 16, color: t.accentInk),
                  SizedBox(width: NeuSpace.n10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name.trim().isEmpty ? I18n.t('ui.7f0425a8a6') : profile.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: NeuFonts.bodyMid, color: t.fg),
                        ),
                        Text(
                          profile.endpoint,
                          style: TextStyle(fontSize: NeuFonts.label, color: t.muted),
                        ),
                      ],
                    ),
                  ),
                  if (editingId == profile.id)
                    NeuIcon(IconId.check, size: 16, color: t.accentInk),
                  const SizedBox(width: NeuSpace.n8),
                  NeuPressable(
                    onTap: () => onEdit(profile),
                    radius: 10,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n10),
                      child: NeuIcon(IconId.pen, size: 14),
                    ),
                  ),
                  const SizedBox(width: NeuSpace.n6),
                  NeuPressable(
                    onTap: () => onDelete(profile),
                    radius: 10,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n10),
                      child: NeuIcon(IconId.trash, size: 14),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
