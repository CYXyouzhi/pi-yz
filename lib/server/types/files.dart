// files 领域的数据模型
//
// 由 server_types.dart 拆分而来（原文件保留为 barrel，
// 所以调用方 import 路径不用改）。




/// 文件条目（目录列表里的一项）
class FileEntry {
  const FileEntry({
    required this.name,
    required this.path,
    required this.isDir,
    this.size = 0,
  });

  final String name;
  final String path;
  final bool isDir;
  final int size;

  factory FileEntry.fromJson(Map<String, dynamic> json) => FileEntry(
        name: json['name'] as String? ?? '',
        path: json['path'] as String? ?? '',
        isDir: json['type'] == 'dir',
        size: (json['size'] as num?)?.toInt() ?? 0,
      );
}

/// 目录列表


/// 目录列表
class DirListing {
  const DirListing({required this.path, required this.entries, this.parent});

  final String path;
  final String? parent;
  final List<FileEntry> entries;

  factory DirListing.fromJson(Map<String, dynamic> json) => DirListing(
        path: json['path'] as String? ?? '',
        parent: json['parent'] as String?,
        entries: (json['entries'] as List?)
                ?.whereType<Map>()
                .map((e) => FileEntry.fromJson(e.cast<String, dynamic>()))
                .toList() ??
            const [],
      );
}

/// 文本文件内容


/// 文本文件内容
class FileText {
  const FileText({
    required this.path,
    required this.text,
    required this.size,
    required this.truncated,
  });

  final String path;
  final String text;
  final int size;
  final bool truncated;

  factory FileText.fromJson(Map<String, dynamic> json) => FileText(
        path: json['path'] as String? ?? '',
        text: json['text'] as String? ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
        truncated: json['truncated'] as bool? ?? false,
      );
}

/// git status 的一条变更


/// git status 的一条变更
class GitChange {
  const GitChange({required this.status, required this.path});
  final String status;
  final String path;

  factory GitChange.fromJson(Map<String, dynamic> json) => GitChange(
        status: json['status'] as String? ?? '',
        path: json['path'] as String? ?? '',
      );
}


class GitStatusInfo {
  const GitStatusInfo({
    required this.cwd,
    required this.files,
    required this.isRepo,
    this.branch,
    this.error,
  });

  final String cwd;
  final List<GitChange> files;
  final bool isRepo;
  final String? branch;
  final String? error;

  factory GitStatusInfo.fromJson(Map<String, dynamic> json) => GitStatusInfo(
        cwd: json['cwd'] as String? ?? '',
        isRepo: json['isRepo'] as bool? ?? false,
        branch: json['branch'] as String?,
        error: json['error'] as String?,
        files: (json['files'] as List?)
                ?.whereType<Map>()
                .map((e) => GitChange.fromJson(e.cast<String, dynamic>()))
                .toList() ??
            const [],
      );
}


class GitDiffInfo {
  const GitDiffInfo({required this.diff, required this.empty, this.path});
  final String diff;
  final bool empty;
  final String? path;

  factory GitDiffInfo.fromJson(Map<String, dynamic> json) => GitDiffInfo(
        diff: json['diff'] as String? ?? '',
        empty: json['empty'] as bool? ?? true,
        path: json['path'] as String?,
      );
}

/// @ 引用候选


/// @ 引用候选
class FileRef {
  const FileRef({required this.name, required this.path, required this.relative});
  final String name;
  final String path;
  final String relative;

  factory FileRef.fromJson(Map<String, dynamic> json) => FileRef(
        name: json['name'] as String? ?? '',
        path: json['path'] as String? ?? '',
        relative: json['relative'] as String? ?? '',
      );
}

/// MCP 服务器（只读列举）


/// 原始文件（图片 / PDF 预览）
class RawFileData {
  const RawFileData({required this.bytes, required this.contentType, required this.kind});

  final List<int> bytes;
  final String contentType;

  /// image | pdf | audio | video | text | binary
  final String kind;

  int get size => bytes.length;
}

/// 一个 git worktree


/// 一个 git worktree
class WorktreeInfo {
  const WorktreeInfo({
    required this.path,
    this.branch,
    this.head,
    this.detached = false,
    this.isMain = false,
  });

  final String path;
  final String? branch;
  final String? head;
  final bool detached;
  final bool isMain;

  factory WorktreeInfo.fromJson(Map<String, dynamic> json) => WorktreeInfo(
        path: json['path'] as String? ?? '',
        branch: json['branch'] as String?,
        head: json['head'] as String?,
        detached: json['detached'] as bool? ?? false,
        isMain: json['isMain'] as bool? ?? false,
      );
}

/// 会话导出（Markdown 文本），给 App 预览/复制/存手机用


/// 会话导出（Markdown 文本），给 App 预览/复制/存手机用
class ExportMarkdown {
  const ExportMarkdown({
    required this.markdown,
    required this.filename,
    required this.title,
  });

  final String markdown;
  final String filename;
  final String title;
}

/// 会话统计（`get_session_stats`）
