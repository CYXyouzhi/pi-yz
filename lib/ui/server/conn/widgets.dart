import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../server/discovery.dart';
import '../../../server/server_profile.dart';
import '../../../server/server_store.dart';
import '../../../server/i18n.dart';
import '../../../theme/design_tokens.dart';
import '../../../theme/neu.dart';
import '../../neu_icons.dart';
import '../../neu_section.dart';
import '../../neu_toast.dart';

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
/// 连接动作：手动添加连接 + 连接诊断。
///
/// 以前这里是「测试连接 / 保存并使用」两个按钮，数据源是页面内联表单的
/// `_host` / `_port` / `_token` controller —— 但表单早已搬进 conn_edit_page，
/// 那三个 controller 在配置连接页**没有任何输入框**（getter 永远是空字符串）。
/// 结果：点「测试连接」只会弹「请填写主机地址」，而页面上根本没有可填的地方。
///
/// 所以这一块从「动作」改成「入口」：表单和测试都回到 conn_edit_page
/// （那里有同样的测试连接 + 保存并连接，且数据来自真实输入框）。
class ConnectionActions extends StatelessWidget {
  const ConnectionActions({
    super.key,
    required this.onNew,
    required this.onDiagnose,
  });

  /// 打开「新增连接」子页（完整表单 + 测试连接）。
  final VoidCallback onNew;

  final VoidCallback onDiagnose;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NeuPressable(
          onTap: onNew,
          radius: NeuRadii.md,
          padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              NeuIcon(IconId.plus, size: 15, color: t.accentInk),
              SizedBox(width: NeuSpace.n7),
              Text(
                I18n.t('conn.manualAdd'),
                style: TextStyle(
                    fontSize: NeuFonts.bodyTight, color: t.accentInk, fontWeight: FontWeight.w600),
              ),
            ],
          ),
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
    // 空列表**不能**整块隐藏 —— 那样第一次用的用户既看不到「已保存」，
    // 也看不到「+ 新增」，等于没有任何手动配置入口（只剩局域网扫描；
    // 外网穿透、手填 IP 全进不来）。分组头与「+ 新增」始终显示，
    // 列表内容按 expanded 展开（为空时给一句占位说明）。
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
          if (profiles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: NeuSpace.n6),
              child: Text(I18n.t('conn.noSavedYet'),
                  style: TextStyle(fontSize: NeuFonts.label, color: t.muted)),
            ),
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

/// 远程访问卡（task-18）：不在同一局域网也能连。
///
/// **外层必须是 RepaintBoundary** —— 这块是页面上最大的阴影图层
/// （NeuRaised + 内部一堆 NeuPressable，每个都带两个大 blur 的 BoxShadow）。
/// 不隔离的话滚动时它会跟着视口一起重绘，实测用户反映「手指滑、画面跟不上」；
/// 隔离后滚动只移动已画好的图层，不再重新做高斯模糊。
///
/// 内容按 store 的远程状态分两态：已开（给地址 + 用/停）与未开（选隧道 + 启动）。
/// 「用你自己的工具」两部分并列显示，与隧道开没开无关。
class RemoteAccessCard extends StatelessWidget {
  const RemoteAccessCard({
    super.key,
    required this.store,
    required this.tunnelPref,
    required this.ownRemote,
    required this.showThreat,
    required this.onPickTunnel,
    required this.onToggleThreat,
    required this.onUseAddress,
    required this.onSaveOwnAddress,
  });

  /// 唯一状态源。组件读它的 remote / remoteBusy，写操作用它的
  /// startRemote / stopRemote —— 但**不持有**任何状态，全部由页面传进来。
  final ServerStore store;

  /// 选中的隧道：cloudflare / ssh。
  final String tunnelPref;

  /// 用户自己工具的地址输入框（手填的那份）。控制器由页面持有 ——
  /// 页面负责它的 dispose，组件只读它的值。
  final TextEditingController ownRemote;

  /// 威胁模型说明展开与否。
  final bool showThreat;

  final ValueChanged<String> onPickTunnel;
  final VoidCallback onToggleThreat;
  final ValueChanged<String> onUseAddress;
  final Future<void> Function(String) onSaveOwnAddress;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
      // RepaintBoundary：这块是页面上最大的阴影图层（NeuRaised + 内部一堆
      // NeuPressable，每个都带两个大 blur 的 BoxShadow）。不隔离的话，
      // 滚动时它会跟着视口一起重绘 —— 实测用户反映「手指滑、画面跟不上」。
      // 隔离后滚动只移动已画好的图层，不再重新做高斯模糊。
      return RepaintBoundary(
        child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final r = store.remote;
          final up = r.status == 'up' && r.url.isNotEmpty;
          final starting = store.remoteBusy || r.status == 'starting';
          return NeuRaised(
            radius: NeuRadii.md,
            padding: const EdgeInsets.all(NeuSpace.n14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: up ? t.success : (starting ? t.warn : t.muted),
                      ),
                    ),
                    SizedBox(width: NeuSpace.n8),
                    Text(I18n.t('ui.0959028680'),
                        style: TextStyle(
                            fontSize: NeuFonts.bodyTight, fontWeight: FontWeight.w700, color: t.fg)),
                    SizedBox(width: NeuSpace.n8),
                    Expanded(
                      child: Text(
                        up
                            ? I18n.tp('ui.bb06dd8151', {'provider': r.providerLabel})
                            : (starting ? I18n.t('ui.592ff57b9b') : I18n.t('ui.ea4a363d8f')),
                        style: TextStyle(
                            fontSize: NeuFonts.small,
                            color: up ? t.success : t.muted),
                      ),
                    ),
                    if (starting)
                      NeuIcon(IconId.spinner, size: 14, color: t.muted),
                  ],
                ),
                if (up) ...[
                  const SizedBox(height: NeuSpace.n8),
                  GestureDetector(
                    onTap: () async {
                      // 隧道地址又长又随机，手抄必错 —— 点一下复制
                      await Clipboard.setData(ClipboardData(text: r.url));
                      // 这里用的是 builder 的 context，判断也要用它的 mounted
                      if (!context.mounted) return;
                      NeuToast.show(context, message: I18n.t('ui.d988ff0fb5'), icon: IconId.check);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n10, vertical: NeuSpace.n9),
                      decoration: BoxDecoration(
                        color: t.well,
                        borderRadius: BorderRadius.circular(NeuRadii.sm),
                      ),
                      child: Text(
                        r.url,
                        style: TextStyle(
                            fontSize: NeuFonts.sub, color: t.accentInk, fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                  const SizedBox(height: NeuSpace.n10),
                  Row(
                    children: [
                      Expanded(
                        child: NeuPressable(
                          // 隧道地址又长又随机，而且每次重开都变 —— 让用户手抄一遍
                          // 再填进表单是最容易出错的一步，这里一步到位
                          onTap: () => onUseAddress(r.url),
                          radius: NeuRadii.sm,
                          padding: EdgeInsets.symmetric(vertical: NeuSpace.n10),
                          child: Center(
                            child: Text(I18n.t('ui.bd939b977d'),
                                style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.accentInk)),
                          ),
                        ),
                      ),
                      const SizedBox(width: NeuSpace.n8),
                      Expanded(
                        child: NeuPressable(
                          onTap: () async {
                            await store.stopRemote();
                            if (!context.mounted) return;
                            NeuToast.show(context,
                                message: I18n.t('ui.1b730b15b4'),
                                icon: IconId.check);
                          },
                          radius: NeuRadii.sm,
                          padding: EdgeInsets.symmetric(vertical: NeuSpace.n10),
                          child: Center(
                            child: Text(I18n.t('ui.e21425f183'),
                                style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.danger)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  SizedBox(height: NeuSpace.n6),
                  Text(
                    I18n.t('ui.b645389837'),
                    style: TextStyle(fontSize: NeuFonts.label, height: 1.5, color: t.muted),
                  ),
                  if (r.error.isNotEmpty) ...[
                    const SizedBox(height: NeuSpace.n8),
                    Text(
                      r.error,
                      style: TextStyle(fontSize: NeuFonts.label, height: 1.5, color: t.danger),
                    ),
                  ],
                  const SizedBox(height: NeuSpace.n10),
                  // ── ① 让 App 开一条隧道：选走哪条道 ──
                  Text(I18n.t('remote.managedTitle'),
                      style: TextStyle(
                          fontSize: NeuFonts.bodySmall,
                          fontWeight: FontWeight.w700,
                          color: t.fg)),
                  const SizedBox(height: NeuSpace.n2),
                  Text(I18n.t('remote.managedHint'),
                      style: TextStyle(fontSize: NeuFonts.label, color: t.muted)),
                  const SizedBox(height: NeuSpace.n6),
                  TunnelOption(
                    value: 'cloudflare',
                    current: tunnelPref,
                    onPick: onPickTunnel,
                  ),
                  const SizedBox(height: NeuSpace.n4),
                  TunnelOption(
                    value: 'ssh',
                    current: tunnelPref,
                    onPick: onPickTunnel,
                  ),
                  const SizedBox(height: NeuSpace.n10),
                  NeuPressable(
                    onTap: starting
                        ? null
                        : () async {
                            final ok = await store.startRemote(prefer: tunnelPref);
                            if (!context.mounted) return;
                            NeuToast.show(
                              context,
                              message: ok ? I18n.t('ui.3fc0cf9dc3') : I18n.tp('ui.54e7e0babb', {'error': store.remote.error}),
                              icon: ok ? IconId.check : IconId.warn,
                            );
                          },
                    radius: NeuRadii.sm,
                    padding: EdgeInsets.symmetric(vertical: NeuSpace.n11),
                    child: Center(
                      child: Text(
                        starting ? I18n.t('ui.18a16fa829') : I18n.t('ui.d89ca63cd0'),
                        style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.accentInk),
                      ),
                    ),
                  ),
                ],
                // ── ② 用你自己的工具 ──（与上面隧道是并列的两种做法，
                // 所以不管隧道开没开都显示）
                const SizedBox(height: NeuSpace.n12),
                Divider(height: 1, color: t.border),
                const SizedBox(height: NeuSpace.n10),
                OwnToolSection(ownRemote: ownRemote, onSave: onSaveOwnAddress),
                const SizedBox(height: NeuSpace.n10),
                GestureDetector(
                  onTap: onToggleThreat,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      NeuIcon(IconId.info, size: 13, color: t.muted),
                      SizedBox(width: NeuSpace.n6),
                      Text(I18n.t('ui.cead89f9f1'),
                          style: TextStyle(fontSize: NeuFonts.label, color: t.muted)),
                      const SizedBox(width: NeuSpace.n4),
                      NeuIcon(showThreat ? IconId.chevronDown : IconId.chevronRight,
                          size: 12, color: t.muted),
                    ],
                  ),
                ),
                if (showThreat) ...[
                  SizedBox(height: NeuSpace.n8),
                  for (final line in (r.threatModel.isEmpty
                      ? [
                          I18n.t('ui.5a54a90ba5'),
                        ]
                      : r.threatModel))
                    Padding(
                      padding: const EdgeInsets.only(bottom: NeuSpace.n5),
                      child: Text('· $line',
                          style: TextStyle(
                              fontSize: NeuFonts.label, height: 1.5, color: t.muted)),
                    ),
                ],
              ],
            ),
          );
        },
        ),
      );
  
}
}
