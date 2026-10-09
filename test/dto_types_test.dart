// 五组 DTO 的 fromJson 守卫（消息 / 会话 / 池 / 配置 / 文件）。
//
// 一起测的理由：它们都是**手写解析 + 给默认值**的同一类代码，出错形态也相同 ——
// 不崩，而是「该是目录的显示成文件」「该禁用的 MCP 变成启用」这种安静的错误。
// 所以用例集中在三处最容易写错的地方：
//   1. 默认值（缺字段时给什么）
//   2. 特殊判定（isDir 靠 `type == 'dir'`、isStreaming 靠 `== true` 而不是真值判定）
//   3. 类型容错（服务端给 num / String / Map 的差异）
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/server/types/config.dart';
import 'package:pi_yz/server/types/files.dart';
import 'package:pi_yz/server/types/messages.dart';
import 'package:pi_yz/server/types/pool.dart';
import 'package:pi_yz/server/types/session.dart';

void main() {
  group('messages：内容块', () {
    test('PiToolCall：正常 + arguments 缺失给空 Map', () {
      final c = PiToolCall.fromMap({
        'id': 'call_1',
        'name': 'edit',
        'arguments': {'path': 'a.dart'},
      });
      expect(c.id, 'call_1');
      expect(c.name, 'edit');
      expect(c.arguments['path'], 'a.dart');

      final bare = PiToolCall.fromMap({'id': 'x'});
      expect(bare.arguments, isEmpty);
      expect(bare.name, '');
    });

    test('PiToolCall：arguments 类型不对也不崩', () {
      expect(PiToolCall.fromMap({'arguments': 'oops'}).arguments, isEmpty);
    });

    test('PiImage：data / mimeType（在 PiContent 的分派里构造）', () {
      final img = PiContent.fromJson({
        'type': 'image',
        'data': 'base64...',
        'mimeType': 'image/png',
      }) as PiImage;
      expect(img.data, 'base64...');
      expect(img.mimeType, 'image/png');
    });

    test('PiUsage：tokens 与 cost 两种形状都兼容', () {
      final u = PiUsage.fromJson({
        'input': 100,
        'output': 5,
        'cacheRead': 10,
        'cacheWrite': 0,
        'reasoning': 3,
        'totalTokens': 118,
        'cost': 0.002,
      });
      expect(u.input, 100);
      expect(u.output, 5);
      expect(u.reasoning, 3);
      expect(u.totalTokens, 118);
      expect(u.costTotal, 0.002);

      expect(
        PiUsage.fromJson({
          'cost': {'total': 1.5},
        }).costTotal,
        1.5,
      );
      expect(PiUsage.fromJson({'cost': 'x'}).costTotal, 0.0);
      expect(PiUsage.fromJson({}).input, 0);
    });
  });

  group('messages：PiMessage 的 type 分派', () {
    test('text / thinking / toolCall 各落到对应内容块', () {
      final text = PiMessage.fromJson({
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': '你好'},
        ],
      });
      expect(text.content.single, isA<PiText>());
      expect((text.content.single as PiText).text, '你好');

      final thinking = PiMessage.fromJson({
        'role': 'assistant',
        'content': [
          {'type': 'thinking', 'thinking': '想一下', 'redacted': true},
        ],
      });
      expect((thinking.content.single as PiThinking).redacted, isTrue);

      final call = PiMessage.fromJson({
        'role': 'assistant',
        'content': [
          {'type': 'toolCall', 'id': 'c1', 'name': 'bash'},
        ],
      });
      expect((call.content.single as PiToolCall).name, 'bash');
    });

    test('未知 type：跳过而不是抛（服务端加新类型时不至于整屏白）', () {
      final m = PiMessage.fromJson({
        'role': 'assistant',
        'content': [
          {'type': 'brandNewThing', 'x': 1},
          {'type': 'text', 'text': '还在'},
        ],
      });
      expect(m.content.length, 1);
      expect((m.content.single as PiText).text, '还在');
    });

    test('content 是纯字符串：当成一个文本块（user 消息的常见形状）', () {
      final m = PiMessage.fromJson({'role': 'user', 'content': '你好'});
      expect(m.content.length, 1);
      expect((m.content.single as PiText).text, '你好');
      // 空字符串不该产生一个空气泡
      expect(
        PiMessage.fromJson({'role': 'user', 'content': ''}).content,
        isEmpty,
      );
    });

    test('content 列表里混进字符串 / 数字：字符串当文本，其余跳过', () {
      final m = PiMessage.fromJson({
        'role': 'user',
        'content': ['garbage', 42],
      });
      expect(m.content.length, 1);
      expect((m.content.single as PiText).text, 'garbage');
    });
  });

  group('session：会话与模型', () {
    test('ServerSession：字段齐全', () {
      final s = ServerSession.fromJson({
        'id': '01a11b9d',
        'cwd': 'C:/work/demo',
        'preview': 'hi',
        'messageCount': 8,
        'name': '会话名',
        'created': '2026-10-08T13:04:08.286Z',
        'modified': '2026-10-09T05:44:00.000Z',
        'parentId': null,
      });
      expect(s.id, '01a11b9d');
      expect(s.cwd, 'C:/work/demo');
      expect(s.messageCount, 8);
      expect(s.name, '会话名');
      expect(s.parentId, isNull);
    });

    test('ModelInfo：name 缺失时回退到 id（芯片上不能是空白）', () {
      final m = ModelInfo.fromJson({'provider': 'p', 'id': 'm-1'});
      expect(m.name, 'm-1');
      expect(m.reasoning, isFalse);
      expect(m.contextWindow, isNull);
    });
  });

  group('pool：池与磁盘', () {
    test('PoolSession：isStreaming 只认字面 true', () {
      expect(
        PoolSession.fromJson({'id': 'a', 'isStreaming': true}).isStreaming,
        isTrue,
      );
      // 服务端给 1 / "true" 都不该当成「正在跑」，否则池里会出现假的活动卡
      expect(
        PoolSession.fromJson({'id': 'a', 'isStreaming': 1}).isStreaming,
        isFalse,
      );
      expect(
        PoolSession.fromJson({'id': 'a', 'isStreaming': 'true'}).isStreaming,
        isFalse,
      );
    });

    test('PoolSession：全字段 + 空 JSON 默认值', () {
      final p = PoolSession.fromJson({
        'id': '01a11ed8',
        'cwd': 'C:/x',
        'title': 'hi',
        'messageCount': 8,
        'outputTokens': 725,
        'cost': 0.0072,
        'lastAction': '编辑 a.dart',
        'runningMs': 4000,
        'idleMs': 1200,
      });
      expect(p.outputTokens, 725);
      expect(p.cost, 0.0072);
      expect(p.runningMs, 4000);

      final empty = PoolSession.fromJson({});
      expect(empty.title, '');
      expect(empty.cost, 0.0);
      expect(empty.idleMs, 0);
    });

    test('DiskSession：可选 modified 保留 null', () {
      final d = DiskSession.fromJson({'id': 'x', 'bytes': 1024});
      expect(d.bytes, 1024);
      expect(d.modified, isNull);
    });
  });

  group('config：模型配置 / MCP / 凭据 / 包', () {
    test('McpServerInfo：默认 scope=user、kind=local、enabled=true', () {
      final m = McpServerInfo.fromJson({'name': 'context7'});
      expect(m.scope, 'user');
      expect(m.kind, 'local');
      // 缺 enabled 字段时按「启用」——服务端老版本不返回它
      expect(m.enabled, isTrue);
      expect(m.args, '');
    });

    test('McpServerInfo：显式 disabled 要读出来', () {
      expect(McpServerInfo.fromJson({'enabled': false}).enabled, isFalse);
    });

    test('CredentialInfo：type 默认 api_key', () {
      expect(CredentialInfo.fromJson({'provider': 'kimi'}).type, 'api_key');
      expect(
        CredentialInfo.fromJson({'provider': 'kimi', 'type': 'oauth'}).type,
        'oauth',
      );
    });

    test('PiPackageInfo / PackageUpdateInfo：默认值与可选字段', () {
      final p = PiPackageInfo.fromJson({'source': 'npm:@a/b', 'zhCount': 12});
      expect(p.scope, 'user');
      expect(p.filtered, isFalse);
      expect(p.installedPath, isNull);
      expect(p.zhCount, 12);

      final u = PackageUpdateInfo.fromJson({'source': 'npm:@a/b'});
      expect(u.type, 'npm');
      expect(u.displayName, '');
    });
  });

  group('files：目录与 Git', () {
    test('FileEntry：isDir 靠 type == dir，不看扩展名', () {
      expect(FileEntry.fromJson({'name': 'lib', 'type': 'dir'}).isDir, isTrue);
      expect(
        FileEntry.fromJson({'name': 'a.dart', 'type': 'file'}).isDir,
        isFalse,
      );
      // 名字里带点不代表是目录
      expect(
        FileEntry.fromJson({'name': 'x.dir', 'type': 'file'}).isDir,
        isFalse,
      );
    });

    test('DirListing：entries 过滤掉非 Map 元素', () {
      final d = DirListing.fromJson({
        'path': 'C:/x',
        'parent': 'C:/',
        'entries': [
          'garbage',
          {'name': 'a.txt', 'type': 'file', 'size': 10},
        ],
      });
      expect(d.entries.length, 1);
      expect(d.entries.single.name, 'a.txt');
      expect(d.parent, 'C:/');
      expect(DirListing.fromJson({}).parent, isNull);
    });

    test('FileText：truncated 标志要读出来', () {
      final f = FileText.fromJson({
        'path': 'a.md',
        'text': 'hello',
        'size': 99999,
        'truncated': true,
      });
      expect(f.truncated, isTrue);
      expect(f.size, 99999);
      expect(FileText.fromJson({}).truncated, isFalse);
    });

    test('GitStatusInfo：干净工作区 / 有改动 / 出错三种', () {
      final clean = GitStatusInfo.fromJson({
        'cwd': 'C:/x',
        'isRepo': true,
        'branch': 'main',
        'files': const [],
      });
      expect(clean.isRepo, isTrue);
      expect(clean.branch, 'main');
      expect(clean.files, isEmpty);

      final dirty = GitStatusInfo.fromJson({
        'isRepo': true,
        'files': [
          {'status': 'M', 'path': 'lib/main.dart'},
        ],
      });
      expect(dirty.files.single.status, 'M');
      expect(dirty.files.single.path, 'lib/main.dart');

      final broken = GitStatusInfo.fromJson({'error': 'not a git repo'});
      expect(broken.isRepo, isFalse);
      expect(broken.error, 'not a git repo');
    });
  });
}
