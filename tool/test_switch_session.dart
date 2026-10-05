// 复现「切换会话后 SSE 不重连」的问题。
//
// 模拟 App 的操作序列：新建 → 等快照 → 打开历史 → 等快照 → 再打开另一条 → 等快照

import 'dart:async';

import '../lib/server/server_client.dart';
import '../lib/server/server_types.dart';

Future<void> main() async {
  final client = ServerClient(host: '127.0.0.1', port: 30142, token: 'test-token-abc123');

  final sessions = await client.listSessions();
  print('历史会话 ${sessions.length} 条');

  // 场景 1：新建会话
  print('\n--- 场景 1：新建会话 ---');
  final newId = await client.createSession(Directory.current.path);
  print('新会话: ${newId.substring(0, 8)}');
  await _probe(client, newId, '新建的会话');

  // 场景 2：打开第一条历史会话
  print('\n--- 场景 2：打开历史会话 A ---');
  await _probe(client, sessions[0].id, '历史会话 A');

  // 场景 3：再打开另一条（模拟连续切换）
  print('\n--- 场景 3：打开历史会话 B ---');
  await _probe(client, sessions[1].id, '历史会话 B');

  // 场景 4：同一 client 上连续取消再重连（模拟 store.openSession 的做法）
  print('\n--- 场景 4：cancel 后立即 relisten ---');
  for (final id in [sessions[0].id, sessions[1].id, sessions[2].id]) {
    final completer = Completer<void>();
    final sub = client.events(id).listen(
      (event) {
        if (event.name == 'snapshot' && !completer.isCompleted) completer.complete();
      },
      onError: (Object error) {
        print('  错误: $error');
        if (!completer.isCompleted) completer.complete();
      },
    );
    await completer.future.timeout(const Duration(seconds: 8), onTimeout: () {});
    print('  ${id.substring(0, 8)} → 收到快照: ${completer.isCompleted}');
    await sub.cancel();
  }

  await client.dispose();
  print('\n完成');
}

/// 单独连一条 SSE，确认快照能否到达
Future<void> _probe(ServerClient client, String sessionId, String label) async {
  final completer = Completer<void>();
  final subscription = client.events(sessionId).listen(
    (event) {
      if (event.name == 'snapshot') {
        final snapshot = SessionSnapshot.fromJson(event.data);
        print('$label → 快照: ${snapshot.messages.length} 条消息, cwd=${snapshot.cwd}');
        if (!completer.isCompleted) completer.complete();
      }
    },
    onError: (Object error) {
      print('$label → 错误: $error');
      if (!completer.isCompleted) completer.complete();
    },
  );
  await completer.future.timeout(const Duration(seconds: 8), onTimeout: () {
    print('$label → 超时，未收到快照！');
  });
  await subscription.cancel();
  await Future<void>.delayed(const Duration(milliseconds: 200));
}
