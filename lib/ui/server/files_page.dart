// 工作区文件浏览 + Git 变更查看 + worktree。
//
// 手机上的取舍：
//   · 文本不内嵌编辑（回电脑改更顺），但**支持上传**（手机里的截图/日志随手丢进工作区）
//   · 目录列表与 Git 变更合成一页：看一眼「改了什么」和「文件在哪」是同一件事
//   · 图片直接渲染；PDF/音频/视频/pdf 这类不能内嵌的，给尺寸+路径，不假装能预览
//   · 文件预览用底部面板而不是新页面：看完随手退回来，不丢层级


import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../server/server_store.dart';
import '../../server/i18n.dart';
import '../../server/server_types.dart';
import '../../theme/design_tokens.dart';
import '../../theme/neu.dart';
import '../neu_icons.dart';
import '../neu_toast.dart';

class WorkspaceFilesPage extends StatefulWidget {
  const WorkspaceFilesPage({
    super.key,
    required this.store,
    required this.cwd,
    this.initialPath,
  });

  final ServerStore store;
  final String cwd;
  final String? initialPath;

  @override
  State<WorkspaceFilesPage> createState() => _WorkspaceFilesPageState();
}

class _WorkspaceFilesPageState extends State<WorkspaceFilesPage> {
  DirListing? _listing;
  GitStatusInfo? _git;
  List<WorktreeInfo> _worktrees = const [];
  bool _loading = true;
  String? _error;
  late String _path;

  /// 能直接内嵌渲染的图片
  static const _imageExts = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'};

  /// 不能内嵌预览、但有意义的办公/媒体格式（给尺寸与路径，别假装能看）
  static const _docExts = {
    '.pdf', '.docx', '.doc', '.xlsx', '.pptx', '.zip', '.7z', '.rar',
    '.mp3', '.wav', '.m4a', '.ogg', '.mp4', '.mov', '.webm', '.apk',
  };

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath ?? widget.cwd;
    _load();
  }

  Future<void> _load() async {
    final listing = await widget.store.listFiles(path: _path);
    final git = await widget.store.gitStatus(widget.cwd);
    final worktrees = await widget.store.worktrees(widget.cwd);
    if (!mounted) return;
    setState(() {
      _listing = listing;
      _git = git;
      _worktrees = worktrees;
      _loading = false;
      _error = listing == null ? I18n.t('ui.7bb952c3c4') : null;
    });
  }

  /// 进入某个目录 / 上一层。
  ///
  /// 关键：**先把新目录读到手，成功了才改 _path**。
  /// 以前是先改 _path 再读，一旦读取失败（比如上一层超出允许范围），
  /// 界面会停在「路径已经变了、列表还是旧的/空的」的半死状态 ——
  /// 用户报的「返回上一级却没回之前一级」就是这么来的。
  Future<void> _openDir(String target) async {
    if (_loading) return;
    final previous = _path;
    setState(() {
      _loading = true;
      _error = null;
    });
    final listing = await widget.store.listFiles(path: target);
    final git = await widget.store.gitStatus(widget.cwd);
    final worktrees = await widget.store.worktrees(widget.cwd);
    if (!mounted) return;
    setState(() {
      if (listing == null) {
        // 失败：路径不动，把原因说清楚
        _path = previous;
        _error = I18n.tp('ui.2b039aa291', {'target': target});
      } else {
        _path = listing.path.isEmpty ? target : listing.path;
        _listing = listing;
        _error = null;
      }
      _git = git;
      _worktrees = worktrees;
      _loading = false;
    });
  }

  /// 回到真正的上一级目录（不是根目录、也不跳级）
  Future<void> _goUp() async {
    final parent = _listing?.parent;
    if (parent == null) return;
    await _openDir(parent);
  }

  Future<void> _enter(FileEntry entry) async {
    if (entry.isDir) {
      await _openDir(entry.path);
      return;
    }
    final lower = entry.path.toLowerCase();
    final ext = lower.contains('.') ? lower.substring(lower.lastIndexOf('.')) : '';
    if (_imageExts.contains(ext)) {
      await _previewImage(entry.path);
      return;
    }
    if (_docExts.contains(ext)) {
      await _previewUnsupported(entry.path, ext);
      return;
    }
    await _preview(entry.path);
  }

  /// 图片预览：拉原始字节直接渲染（不能走文本接口，二进制会变乱码）
  Future<void> _previewImage(String filePath) async {
    final data = await widget.store.rawFile(filePath);
    if (!mounted) return;
    if (data == null) return;
    if (data.kind != 'image') {
      NeuToast.show(context, message: I18n.tp('ui.8e735016cc', {'type': data.contentType}), icon: IconId.warn);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final t = sheetContext.neu;
        final name = filePath.replaceAll('\\', '/').split('/').last;
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85),
          decoration: BoxDecoration(
            color: t.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(NeuRadii.lg)),
          ),
          padding: const EdgeInsets.fromLTRB(NeuSpace.n16, NeuSpace.n10, NeuSpace.n16, NeuSpace.n20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sheetHandle(t),
              const SizedBox(height: NeuSpace.n10),
              Row(
                children: [
                  Expanded(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: NeuFonts.bodyLg, fontWeight: FontWeight.w700, color: t.fg)),
                  ),
                  Text('${(data.size / 1024).toStringAsFixed(1)} KB',
                      style: TextStyle(fontSize: NeuFonts.badge, color: t.muted)),
                ],
              ),
              const SizedBox(height: NeuSpace.n12),
              Flexible(
                child: SingleChildScrollView(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(NeuRadii.md),
                    child: Image.memory(Uint8List.fromList(data.bytes), fit: BoxFit.contain),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 不能内嵌预览的格式：如实说明，并把路径给出来（能复制走）
  Future<void> _previewUnsupported(String filePath, String ext) async {
    final name = filePath.replaceAll('\\', '/').split('/').last;
    final t = context.neu;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      // 不打开这个开关，弹层最高只有半屏，小屏手机上内容会被切掉
      isScrollControlled: true,
      builder: (sheetContext) {
        final st = sheetContext.neu;
        return Container(
          decoration: BoxDecoration(
            color: st.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(NeuRadii.lg)),
          ),
          padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n10, NeuSpace.n18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sheetHandle(st),
              const SizedBox(height: NeuSpace.n12),
              Text(name, style: TextStyle(fontSize: NeuFonts.bodyLg, fontWeight: FontWeight.w700, color: st.fg)),
              SizedBox(height: NeuSpace.n8),
              Text(
                '${I18n.tp('ui.d99dc368ab', {
                  'ext': ext.replaceFirst('.', '').toUpperCase(),
                })}'
                '${I18n.tp('ui.ef2e6f8ec0', {'path': filePath})}',
                style: TextStyle(fontSize: NeuFonts.sub, color: st.muted, height: 1.7),
              ),
              const SizedBox(height: NeuSpace.n14),
              NeuPressable(
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: filePath));
                  if (!sheetContext.mounted) return;
                  Navigator.of(sheetContext).pop();
                  NeuToast.show(sheetContext, message: I18n.t('ui.42c4e29d47'), icon: IconId.check);
                },
                radius: NeuRadii.sm,
                padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    NeuIcon(IconId.cmd, size: 14, color: t.accentInk),
                    SizedBox(width: NeuSpace.n8),
                    Text(I18n.t('ui.f4130cae7d'), style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.accentInk)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 手机上选一个文件传到当前目录
  Future<void> _pickAndUpload() async {
    final t = context.neu;
    // file_picker 13 的 API：pickFile() 单个文件 + readAsBytes()
    final picked = await FilePicker.pickFile();
    if (!mounted || picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    if (bytes.isEmpty) {
      NeuToast.show(context, message: I18n.t('ui.dad890d59d'), icon: IconId.warn);
      return;
    }
    final ok = await widget.store.uploadFile(
      dir: _path,
      name: picked.name,
      bytes: bytes,
    );
    if (!mounted) return;
    if (ok) {
      await _load();
      return;
    }
    // 同名不覆盖：问一句再传（服务端拒绝时给的就是这句）
    final overwrite = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: t.bg,
        title: Text(I18n.t('ui.9a2a7b9e12'), style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle)),
        content: Text(I18n.tp('ui.6e4f2b46a6', {'name': picked.name}),
            style: TextStyle(color: t.muted, fontSize: NeuFonts.bodyMid, height: 1.6)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(I18n.t('common.cancel'), style: TextStyle(color: t.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(I18n.t('ui.e09fea40f7'), style: TextStyle(color: t.danger)),
          ),
        ],
      ),
    );
    if (overwrite != true || !mounted) return;
    final retried = await widget.store.uploadFile(
      dir: _path,
      name: picked.name,
      bytes: bytes,
      overwrite: true,
    );
    if (retried) await _load();
  }

  Widget _sheetHandle(NeuTokens t) => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: t.muted.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(NeuRadii.hairline),
          ),
        ),
      );

  /// 文件预览：底部面板 + 等宽文本；git 仓库里额外给一个「看 diff」
  Future<void> _preview(String filePath) async {
    final file = await widget.store.readFile(filePath);
    if (!mounted) return;
    if (file == null) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final t = sheetContext.neu;
        final tail = filePath.replaceAll('\\', '/').split('/').last;
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
          ),
          decoration: BoxDecoration(
            color: t.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(NeuRadii.lg)),
          ),
          padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n10, NeuSpace.n18, NeuSpace.n20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.muted.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(NeuRadii.hairline),
                  ),
                ),
              ),
              const SizedBox(height: NeuSpace.n12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: NeuFonts.sectionTitle,
                        fontWeight: FontWeight.w700,
                        color: t.onBg,
                      ),
                    ),
                  ),
                  if (_git?.isRepo == true)
                    NeuPressable(
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _showDiff(filePath);
                      },
                      radius: 12,
                      padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n7),
                      child: Text(I18n.t('ui.30570a7afa'), style: TextStyle(fontSize: NeuFonts.sub, color: t.accentInk)),
                    ),
                ],
              ),
              SizedBox(height: NeuSpace.n2),
              Text(
                '${_readableSize(file.size)}${file.truncated ? I18n.t('ui.70a59fefaa') : ''}',
                style: TextStyle(fontSize: NeuFonts.label, color: t.muted),
              ),
              const SizedBox(height: NeuSpace.n12),
              Flexible(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: NeuDecorations.wellGradient(t),
                    borderRadius: BorderRadius.circular(NeuRadii.sm),
                    boxShadow: NeuShadows.insetSm(t),
                  ),
                  padding: const EdgeInsets.all(NeuSpace.n10),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      file.text,
                      style: TextStyle(
                        fontSize: NeuFonts.label,
                        height: 1.55,
                        fontFamily: 'monospace',
                        color: t.fg,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// diff 视图：按行着色（+ 绿 / - 红 / @@ 蓝）
  Future<void> _showDiff(String? filePath) async {
    final diff = await widget.store.gitDiff(widget.cwd, path: filePath);
    if (!mounted || diff == null) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final t = sheetContext.neu;
        final lines = diff.diff.split('\n');
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
          ),
          decoration: BoxDecoration(
            color: t.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(NeuRadii.lg)),
          ),
          padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n10, NeuSpace.n18, NeuSpace.n20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.muted.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(NeuRadii.hairline),
                  ),
                ),
              ),
              SizedBox(height: NeuSpace.n12),
              Text(
                filePath == null
                    ? I18n.t('ui.d597968aea')
                    : filePath.replaceAll('\\', '/').split('/').last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: NeuFonts.sectionTitle,
                  fontWeight: FontWeight.w700,
                  color: t.onBg,
                ),
              ),
              SizedBox(height: NeuSpace.n10),
              Flexible(
                child: diff.empty
                    ? Text(I18n.t('ui.87afad55b5'), style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.muted))
                    : Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: NeuDecorations.wellGradient(t),
                          borderRadius: BorderRadius.circular(NeuRadii.sm),
                          boxShadow: NeuShadows.insetSm(t),
                        ),
                        padding: const EdgeInsets.all(NeuSpace.n10),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final line in lines)
                                Text(
                                  line.isEmpty ? ' ' : line,
                                  style: TextStyle(
                                    fontSize: NeuFonts.badge,
                                    height: 1.5,
                                    fontFamily: 'monospace',
                                    color: line.startsWith('+')
                                        ? t.success
                                        : line.startsWith('-')
                                            ? t.danger
                                            : line.startsWith('@@')
                                                ? t.accentInk
                                                : t.fg,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _readableSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    // 物理返回键（Android 三键/手势）：还能上一级就上一级，到顶了才退出页面。
    // 文件浏览器在手机上的返回语义就是这个，跟「进来一次就得一路退出去」不同。
    return PopScope(
      canPop: _listing?.parent == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goUp();
      },
      child: _buildPage(context),
    );
  }

  Widget _buildPage(BuildContext context) {
    final t = context.neu;
    final tail = _path.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).lastOrNull ?? _path;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n8, NeuSpace.n12, NeuSpace.n8),
              child: Row(
                children: [
                  NeuPressable(
                    onTap: () => Navigator.of(context).maybePop(),
                    radius: 12,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n12),
                      child: NeuIcon(IconId.chevronLeft, size: 16),
                    ),
                  ),
                  const SizedBox(width: NeuSpace.n8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: NeuFonts.heading,
                            fontWeight: FontWeight.w700,
                            color: t.onBg,
                          ),
                        ),
                        // 面包屑（task-21 合同⑤的重做项）：
                        // 原来这里只是把整条路径当一行灰字显示，看得见、点不动。
                        // 手机上从深层目录回跳两级，点段比连点两次「上一级」精确得多。
                        _breadcrumb(t),
                      ],
                    ),
                  ),
                  if (_listing?.parent != null)
                    NeuPressable(
                      onTap: _goUp,
                      radius: 12,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n12),
                        child: NeuIcon(IconId.chevronDown, size: 16),
                      ),
                    ),
                  NeuPressable(
                    onTap: _pickAndUpload,
                    radius: 12,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n12),
                      child: NeuIcon(IconId.download, size: 16),
                    ),
                  ),
                  NeuPressable(
                    onTap: _load,
                    radius: 12,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n12),
                      child: NeuIcon(IconId.sync, size: 16),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          NeuIcon(IconId.spinner, size: 22, color: t.accentInk),
                          SizedBox(height: NeuSpace.n10),
                          Text(I18n.t('common.loading'), style: TextStyle(fontSize: NeuFonts.sub, color: t.onBgDim)),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n4, NeuSpace.n18, 40),
                      children: [
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: NeuSpace.n20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    NeuIcon(IconId.warn, size: 16, color: t.danger),
                                    const SizedBox(width: NeuSpace.n8),
                                    Expanded(
                                      child: Text(_error!,
                                          style: TextStyle(fontSize: NeuFonts.sub, color: t.danger)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: NeuSpace.n10),
                                // 读不到目录时给一个重试（先补连接再重读）
                                NeuPressable(
                                  onTap: () async {
                                    await widget.store.ensureConnected();
                                    await _load();
                                  },
                                  radius: NeuRadii.sm,
                                  padding: EdgeInsets.symmetric(
                                      horizontal: NeuSpace.n16, vertical: NeuSpace.n9),
                                  child: Text(I18n.t('common.retry'),
                                      style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.accentInk)),
                                ),
                              ],
                            ),
                          ),
                        if (_git != null && _git!.isRepo) ...[
                          _section(t, 'Git · ${_git!.branch ?? '-'}'),
                          NeuRaised(
                            radius: NeuRadii.md,
                            level: NeuLevel.small,
                            padding: const EdgeInsets.all(NeuSpace.n6),
                            child: Column(
                              children: [
                                if (_git!.files.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: NeuSpace.n10),
                                    child: Text(I18n.t('ui.af825e2845'),
                                        style: TextStyle(fontSize: NeuFonts.sub, color: t.muted)),
                                  )
                                else ...[
                                  for (var i = 0; i < _git!.files.length && i < 40; i++) ...[
                                    if (i > 0) Container(height: 1, color: t.border),
                                    _gitRow(t, _git!.files[i]),
                                  ],
                                  if (_git!.files.length > 40)
                                    Padding(
                                      padding: const EdgeInsets.only(top: NeuSpace.n6),
                                      child: Text(
                                        I18n.tp('ui.b7efc0c5ef', {'n': _git!.files.length - 40}),
                                        style: TextStyle(fontSize: NeuFonts.badge, color: t.muted),
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: NeuSpace.n16),
                        ],
                        _section(t, 'Worktrees${_worktrees.isEmpty ? '' : '（${_worktrees.length}）'}'),
                        NeuRaised(
                          radius: NeuRadii.md,
                          level: NeuLevel.small,
                          padding: const EdgeInsets.all(NeuSpace.n6),
                          child: Column(
                            children: [
                              if (_worktrees.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: NeuSpace.n10),
                                  child: Text(
                                    _git?.isRepo == true ? I18n.t('ui.3ac69ac199') : I18n.t('ui.eb6e66be0f'),
                                    style: TextStyle(fontSize: NeuFonts.sub, color: t.muted),
                                  ),
                                )
                              else
                                for (var i = 0; i < _worktrees.length; i++) ...[
                                  if (i > 0) Container(height: 1, color: t.border),
                                  _worktreeRow(t, _worktrees[i]),
                                ],
                              if (_git?.isRepo == true) ...[
                                Container(height: 1, color: t.border),
                                NeuPressable(
                                  onTap: _addWorktreeDialog,
                                  flat: true,
                                  padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      NeuIcon(IconId.plus, size: 15, color: t.accentInk),
                                      SizedBox(width: NeuSpace.n8),
                                      Text(I18n.t('ui.caccdc5cc0'),
                                          style: TextStyle(fontSize: NeuFonts.bodyMid, color: t.accentInk)),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        SizedBox(height: NeuSpace.n16),
                        _section(t, I18n.t('ui.767fa455bb')),
                        NeuRaised(
                          radius: NeuRadii.md,
                          level: NeuLevel.small,
                          padding: const EdgeInsets.all(NeuSpace.n6),
                          child: Column(
                            children: [
                              if ((_listing?.entries ?? []).isEmpty)
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: NeuSpace.n10),
                                  child: Text(I18n.t('ui.a21f6ab17d'), style: TextStyle(fontSize: NeuFonts.sub, color: t.muted)),
                                ),
                              for (var i = 0; i < (_listing?.entries.length ?? 0); i++) ...[
                                if (i > 0) Container(height: 1, color: t.border),
                                _fileRow(t, _listing!.entries[i]),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(NeuTokens t, String title) => Padding(
        padding: const EdgeInsets.only(top: NeuSpace.n14, bottom: NeuSpace.n8),
        child: Text(
          title,
          style: TextStyle(
            fontSize: NeuFonts.sectionTitle,
            fontWeight: FontWeight.w700,
            color: t.onBg,
          ),
        ),
      );

  /// 一个 worktree：主工作树不能删；其它可以删、可以「用它开会话」
  Widget _worktreeRow(NeuTokens t, WorktreeInfo wt) {
    final short =
        wt.path.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).lastOrNull ?? wt.path;
    final branch = wt.branch ?? (wt.detached ? '(detached)' : I18n.t('ui.a3645c3f66'));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n10, vertical: NeuSpace.n8),
      child: Row(
        children: [
          NeuIcon(IconId.folder, size: 15, color: wt.isMain ? t.accentInk : t.muted),
          const SizedBox(width: NeuSpace.n10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(short,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.fg)),
                    ),
                    if (wt.isMain) ...[
                      SizedBox(width: NeuSpace.n6),
                      Text(I18n.t('ui.36e8fd3177'), style: TextStyle(fontSize: NeuFonts.tiny, color: t.accentInk)),
                    ],
                  ],
                ),
                Text(
                  '$branch · ${wt.path}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: NeuFonts.micro, color: t.muted),
                ),
              ],
            ),
          ),
          NeuPressable(
            onTap: () => _openSessionIn(wt.path),
            radius: 10,
            padding: EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
            child: Text(I18n.t('ui.c33f0e7bb9'), style: TextStyle(fontSize: NeuFonts.badge, color: t.accentInk)),
          ),
          if (!wt.isMain)
            NeuPressable(
              onTap: () => _removeWorktree(wt),
              radius: 10,
              padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
              child: NeuIcon(IconId.trash, size: 14, color: t.danger),
            ),
        ],
      ),
    );
  }

  /// 在指定目录开一条新会话（worktree 的主要用途：在那儿干活）
  Future<void> _openSessionIn(String dir) async {
    final id = await widget.store.createSession(dir);
    if (!mounted) return;
    if (id == null) return;
    await widget.store.openSession(id);
    if (!mounted) return;
    NeuToast.show(context, message: I18n.t('ui.be925b16ea'), icon: IconId.check);
  }

  Future<void> _addWorktreeDialog() async {
    final dirController = TextEditingController(text: '${widget.cwd.replaceAll('\\', '/')}-wt');
    final branchController = TextEditingController(text: 'feature/');
    final t = context.neu;
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: t.bg,
          title: Text(I18n.t('ui.caccdc5cc0'), style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: dirController,
                style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.fg),
                decoration: InputDecoration(
                  labelText: I18n.t('ui.52ff644bf2'),
                  labelStyle: TextStyle(fontSize: NeuFonts.small, color: t.muted),
                  helperText: I18n.t('ui.e139dcc6af'),
                  helperStyle: TextStyle(fontSize: NeuFonts.micro, color: t.muted),
                ),
              ),
              const SizedBox(height: NeuSpace.n12),
              TextField(
                controller: branchController,
                style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.fg),
                decoration: InputDecoration(
                  labelText: I18n.t('ui.6ae804fad2'),
                  labelStyle: TextStyle(fontSize: NeuFonts.small, color: t.muted),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(I18n.t('common.cancel'), style: TextStyle(color: t.muted)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(I18n.t('ui.d9ac9228e8'), style: TextStyle(color: t.accentInk)),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final created = await widget.store.addWorktree(
        cwd: widget.cwd,
        dir: dirController.text.trim(),
        branch: branchController.text.trim(),
      );
      if (created) await _load();
    } finally {
      dirController.dispose();
      branchController.dispose();
    }
  }

  Future<void> _removeWorktree(WorktreeInfo wt) async {
    final t = context.neu;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: t.bg,
        title: Text(I18n.t('ui.d6b068b05f'), style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle)),
        content: Text(
          I18n.tp('ui.7fdeeb20cd', {'path': wt.path}),
          style: TextStyle(color: t.muted, fontSize: NeuFonts.bodySmall, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(I18n.t('common.cancel'), style: TextStyle(color: t.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(I18n.t('common.delete'), style: TextStyle(color: t.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final removed = await widget.store.removeWorktree(widget.cwd, wt.path);
    if (removed) await _load();
  }

  Widget _gitRow(NeuTokens t, GitChange change) {
    final statusColor = change.status == '??'
        ? t.accentInk
        : change.status.contains('D')
            ? t.danger
            : t.success;
    return NeuPressable(
      flat: true,
      onTap: () => _showDiff(change.path),
      padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n10, vertical: NeuSpace.n10),
      child: Row(
        children: [
          Container(
            width: 26,
            alignment: Alignment.centerLeft,
            child: Text(
              change.status.isEmpty ? 'M' : change.status,
              style: TextStyle(fontSize: NeuFonts.badge, fontFamily: 'monospace', color: statusColor),
            ),
          ),
          const SizedBox(width: NeuSpace.n6),
          Expanded(
            child: Text(
              change.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: NeuFonts.sub, color: t.fg),
            ),
          ),
          NeuIcon(IconId.chevronRight, size: 13, color: t.muted),
        ],
      ),
    );
  }

  /// 面包屑：把路径切成可点的一段段，最后一段是不可点的当前目录
  Widget _breadcrumb(NeuTokens t) {
    final parts =
        _path.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return const SizedBox.shrink();

    final segments = <(String, String)>[];
    var acc = '';
    for (var i = 0; i < parts.length; i++) {
      acc = i == 0 ? parts[i] : '$acc/${parts[i]}';
      segments.add((parts[i], acc));
    }

    return SizedBox(
      height: 22,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: segments.length,
        itemBuilder: (context, i) {
          final seg = segments[i];
          final last = i == segments.length - 1;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n1),
                  child: Text('/',
                      style: TextStyle(fontSize: NeuFonts.label, color: t.muted)),
                ),
              NeuPressable(
                // 当前目录不可点（点了没意义）
                onTap: last ? null : () => _openDir(seg.$2),
                radius: 6,
                padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n4, vertical: NeuSpace.n2),
                child: Text(
                  seg.$1,
                  style: TextStyle(
                    fontSize: NeuFonts.label,
                    color: last ? t.fg : t.accentInk,
                    fontWeight: last ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 按扩展名给文件配图标（task-21 合同⑤的重做项）。
  ///
  /// 原来文件一律用 `terminal` 图标 —— 那是"命令行"的意思，放在一份 README.md
  /// 或一张截图上毫无信息量。改成一类一个图标之后，扫一眼目录就知道
  /// 哪些是代码、哪些是文档、哪些是图片。
  static IconId _iconForEntry(FileEntry entry) {
    if (entry.isDir) return IconId.folder;
    final n = entry.name.toLowerCase();
    if (n.endsWith('.md') || n.endsWith('.txt') || n.endsWith('.rst')) return IconId.pen;
    if (n.endsWith('.png') ||
        n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.webp') ||
        n.endsWith('.gif') ||
        n.endsWith('.svg')) {
      return IconId.image;
    }
    if (n.endsWith('.dart') ||
        n.endsWith('.js') ||
        n.endsWith('.mjs') ||
        n.endsWith('.ts') ||
        n.endsWith('.py') ||
        n.endsWith('.kt') ||
        n.endsWith('.swift') ||
        n.endsWith('.json') ||
        n.endsWith('.yaml') ||
        n.endsWith('.yml') ||
        n.endsWith('.sh')) {
      return IconId.cmd;
    }
    return IconId.bubble;
  }

  Widget _fileRow(NeuTokens t, FileEntry entry) {
    return NeuPressable(
      flat: true,
      onTap: () => _enter(entry),
      // 行高从 10 提到 13：手指点的目标高过 44dp 才不会误触下一行
      padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n10, vertical: NeuSpace.n13),
      child: Row(
        children: [
          NeuIcon(
            _iconForEntry(entry),
            size: 16,
            color: entry.isDir ? t.accentInk : t.muted,
          ),
          const SizedBox(width: NeuSpace.n10),
          Expanded(
            child: Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: NeuFonts.bodyMid, color: t.fg),
            ),
          ),
          if (!entry.isDir)
            Text(
              _readableSize(entry.size),
              style: TextStyle(fontSize: NeuFonts.micro, color: t.muted),
            ),
          const SizedBox(width: NeuSpace.n6),
          NeuIcon(IconId.chevronRight, size: 13, color: t.muted),
        ],
      ),
    );
  }
}
