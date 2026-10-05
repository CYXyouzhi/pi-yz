// 通信层端到端验证：直接用手机端那套 ServerClient 连真实服务端。
//
// 跑法（先启动服务端：node index.mjs --token testtoken123）
//   dart run tool/test_server_client.dart

import 'dart:async';

import '../lib/server/chat_reducer.dart';
import '../lib/server/server_client.dart';
import '../lib/server/server_types.dart';

Future<void> main() async {
  final client = ServerClient(host: '127.0.0.1', port: 30142, token: 'testtoken123');

  print('=== 1. 健康检查 ===');
  final health = await client.health();
  print('ok=${health.ok} pi=${health.piVersion} 活跃会话=${health.activeSessions}');

  print('\n=== 2. 会话列表 ===');
  final sessions = await client.listSessions();
  print('共 ${sessions.length} 条');
  for (final session in sessions.take(3)) {
    print('  ${session.id.substring(0, 8)} | ${session.workspaceName} | ${session.displayTitle}');
  }

  print('\n=== 3. 新建会话 ===');
  final sessionId = await client.createSession('C:/Users/YOUZHI/Desktop/1/pi-mobile');
  print('会话 id: $sessionId');

  print('\n=== 4. 订阅事件流 ===');
  final reducer = ChatReducer();
  final eventTypes = <String>[];
  var snapshotSeen = false;
  String? pendingUiId;
  final done = Completer<void>();

  final subscription = client.events(sessionId).listen(
    (event) {
      if (event.name == 'snapshot') {
        final snapshot = SessionSnapshot.fromJson(event.data);
        reducer.applySnapshot(snapshot);
        snapshotSeen = true;
        print('快照: 模型=${snapshot.model?.name} 等级=${snapshot.thinkingLevel} 消息=${snapshot.messages.length}');
        return;
      }
      if (event.name == 'status') {
        print('状态帧: ${event.data['phase']}');
        return;
      }
      eventTypes.add(event.type ?? '?');
      reducer.applyEvent(event);
      // 扩展报错与 UI 请求要看详情，不能只记类型
      if (event.type == 'extension_error') {
        print('  ⚠ 扩展错误: ${event.data}');
      } else if (event.type == 'extension_ui_request') {
        print('  ↳ UI 请求: method=${event.data['method']} '
            'title=${event.data['title']} message=${event.data['message']} '
            'statusKey=${event.data['statusKey']}');
        if (event.data['method'] == 'confirm' || event.data['method'] == 'select') {
          pendingUiId = event.data['id'] as String?;
        }
      }
      if (event.type == 'agent_settled' && !done.isCompleted) done.complete();
    },
    onError: (Object error) {
      print('流错误: $error');
      if (!done.isCompleted) done.complete();
    },
  );

  // 等快照到达
  for (var i = 0; i < 100 && !snapshotSeen; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  print('快照已收到: $snapshotSeen');

  print('\n=== 5. 发送消息 ===');
  final stopwatch = Stopwatch()..start();
  final response = await client.command(sessionId, {
    'id': 'test-1',
    'type': 'prompt',
    'message': '只回复两个字：收到',
  });
  print('命令响应: ${response.success} (${stopwatch.elapsedMilliseconds}ms) data=${response.data}');

  print('\n=== 6. 等待完成 ===');
  await done.future.timeout(const Duration(seconds: 60), onTimeout: () {});
  print('总耗时: ${stopwatch.elapsedMilliseconds}ms');

  print('\n=== 7. 归约结果 ===');
  print('消息数: ${reducer.messages.length}');
  for (final message in reducer.messages) {
    final preview = message.text.replaceAll('\n', ' ').trim();
    print('  [${message.role}] ${preview.length > 60 ? '${preview.substring(0, 60)}…' : preview}');
  }
  print('事件序列: ${eventTypes.join(' → ')}');

  print('\n=== 8. 内置命令（不该触发模型） ===');
  final before = eventTypes.length;
  final builtin = await client.command(sessionId, {
    'id': 'test-2',
    'type': 'prompt',
    'message': '/model',
  });
  print('响应: success=${builtin.success}');
  print('builtin: kind=${builtin.builtin?['kind']} picker=${builtin.builtin?['picker']} '
      '选项=${(builtin.builtin?['options'] as List?)?.length}');
  await Future<void>.delayed(const Duration(milliseconds: 500));
  print('期间新增事件: ${eventTypes.length - before} 条（应为 0）');

  print('\n=== 9. 扩展 UI 桥接 ===');
  final uiFuture = client.command(sessionId, {
    'id': 'test-3',
    'type': 'debug_ui',
    'method': 'confirm',
    'args': ['测试确认', '这是一条测试消息'],
  });
  await Future<void>.delayed(const Duration(milliseconds: 900));
  if (pendingUiId != null) {
    final accepted = await client.respondToUi(sessionId, pendingUiId!, {'confirmed': true});
    print('回应已接受: $accepted');
  } else {
    print('未收到对话框请求');
  }
  CommandResponse? uiResult;
  try {
    uiResult = await uiFuture.timeout(const Duration(seconds: 5));
  } on TimeoutException {
    uiResult = null;
  }
  print('扩展拿到的返回值: ${uiResult?.data}');

  await subscription.cancel();
  await client.dispose();
  print('\n完成');
}
