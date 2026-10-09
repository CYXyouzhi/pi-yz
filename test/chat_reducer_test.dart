// ChatReducer 的事件归约守卫。
//
// 它是**纯逻辑**（事件进、状态出），也是会话页所有显示内容的中转站：
// 消息列表、流式状态、工具运行状态、本轮耗时、排队计数全在这里维护。
// 之前只有一个用例蹭到过它，覆盖率 1%。
//
// 用例分四组：生命周期、消息与流式、工具运行、快照与历史。
// 断言尽量避开具体文案（只判断「有没有提示」），免得受界面语言影响。
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/server/chat_models.dart';
import 'package:pi_yz/server/chat_reducer.dart';
import 'package:pi_yz/server/server_types.dart';

ServerEvent ev(String type, [Map<String, dynamic> data = const {}]) =>
    ServerEvent('message', {'type': type, ...data});

Map<String, dynamic> assistantJson({
  List<Map<String, dynamic>> content = const [],
  String? timestamp,
}) => {
  'role': 'assistant',
  'content': content,
  // null-aware 元素：没传 timestamp 时这个键直接不出现在 Map 里
  'timestamp': ?timestamp,
};

void main() {
  group('生命周期：运行状态与本轮耗时', () {
    test('agent_start 开始计时；agent_settled 结算并归零', () {
      final r = ChatReducer();
      expect(r.isRunning, isFalse);
      expect(r.runStartedAt, isNull);

      expect(r.applyEvent(ev('agent_start')), isTrue);
      expect(r.isRunning, isTrue);
      expect(r.runStartedAt, isNotNull);

      expect(r.applyEvent(ev('agent_settled')), isTrue);
      expect(r.isRunning, isFalse);
      expect(r.isStreaming, isFalse);
      expect(r.runStartedAt, isNull);
      // lastRunMs 是本轮耗时（毫秒），刚跑完必然是个非负数
      expect(r.lastRunMs, greaterThanOrEqualTo(0));
    });

    test('agent_start 会清掉上一条提示（新的一轮开始了）', () {
      final r = ChatReducer();
      r.applyEvent(ev('agent_end', {'willRetry': true}));
      expect(r.notice, isNotNull);
      r.applyEvent(ev('agent_start'));
      expect(r.notice, isNull);
    });

    test('agent_end 带 willRetry：给一句提示（用户要知道它在重试）', () {
      final r = ChatReducer();
      r.applyEvent(ev('agent_end', {'willRetry': true}));
      expect(r.notice, isNotNull);

      final r2 = ChatReducer();
      r2.applyEvent(ev('agent_end', {'willRetry': false}));
      expect(r2.notice, isNull);
    });

    test('model_change：提示里带上新的 provider 与模型（额度兜底切模型要让人看见）', () {
      final r = ChatReducer();
      r.applyEvent(
        ev('model_change', {'provider': 'kimi', 'modelId': 'kimi-k2'}),
      );
      expect(r.notice, isNotNull);
      expect(r.notice, contains('kimi'));
    });

    test('model_change 两个字段都空：不产生空提示', () {
      final r = ChatReducer();
      expect(r.applyEvent(ev('model_change')), isTrue);
      expect(r.notice, isNull);
    });
  });

  group('消息与流式', () {
    test('message_start 助手消息：入列 + 进入流式态', () {
      final r = ChatReducer();
      expect(r.messages, isEmpty);

      final ok = r.applyEvent(
        ev('message_start', {'message': assistantJson()}),
      );
      expect(ok, isTrue);
      expect(r.messages.length, 1);
      expect(r.messages.single.role, 'assistant');
      expect(r.messages.single.streaming, isTrue);
      expect(r.isStreaming, isTrue);
    });

    test('message_start 用户消息：不入流式态（只有 start/end）', () {
      final r = ChatReducer();
      r.applyEvent(
        ev('message_start', {
          'message': {'role': 'user', 'content': '你好'},
        }),
      );
      expect(r.messages.single.streaming, isFalse);
      expect(r.isStreaming, isFalse);
    });

    test('message_start 缺 message / 是 system：都不改状态、返回 false', () {
      final r = ChatReducer();
      expect(r.applyEvent(ev('message_start')), isFalse);
      expect(
        r.applyEvent(
          ev('message_start', {
            'message': {'role': 'system', 'content': 'x'},
          }),
        ),
        isFalse,
      );
      expect(r.messages, isEmpty);
    });

    test('增量事件不带 timestamp 时用本机时间兜底（否则「本轮耗时」永远算不出）', () {
      final r = ChatReducer();
      r.applyEvent(ev('message_start', {'message': assistantJson()}));
      expect(r.messages.single.timestamp, isNotNull);
    });

    test('未知事件类型：返回 false，不改任何状态', () {
      final r = ChatReducer();
      expect(r.applyEvent(ev('something_brand_new')), isFalse);
      expect(r.messages, isEmpty);
      expect(r.isRunning, isFalse);
    });
  });

  group('工具运行状态', () {
    test('tool_execution_start 建条目；同 id 再来一次不重复建', () {
      final r = ChatReducer();
      expect(
        r.applyEvent(
          ev('tool_execution_start', {'toolCallId': 'c1', 'toolName': 'bash'}),
        ),
        isTrue,
      );
      expect(r.tools.length, 1);
      expect(r.toolRunOf('c1')!.name, 'bash');
      expect(r.toolRunOf('c1')!.status, ToolStatus.running);

      r.applyEvent(
        ev('tool_execution_start', {'toolCallId': 'c1', 'toolName': 'bash'}),
      );
      expect(r.tools.length, 1, reason: '同一个工具调用不该出现两条');
    });

    test('tool_execution_start 没有 toolCallId：返回 false（无从归属）', () {
      final r = ChatReducer();
      expect(
        r.applyEvent(ev('tool_execution_start', {'toolName': 'bash'})),
        isFalse,
      );
      expect(r.tools, isEmpty);
    });

    test('tool_execution_end：错误置 error，正常置 done', () {
      final r = ChatReducer();
      r.applyEvent(
        ev('tool_execution_start', {'toolCallId': 'c1', 'toolName': 'bash'}),
      );
      r.applyEvent(
        ev('tool_execution_end', {'toolCallId': 'c1', 'isError': true}),
      );
      expect(r.toolRunOf('c1')!.status, ToolStatus.error);

      r.applyEvent(
        ev('tool_execution_start', {'toolCallId': 'c2', 'toolName': 'read'}),
      );
      r.applyEvent(ev('tool_execution_end', {'toolCallId': 'c2'}));
      expect(r.toolRunOf('c2')!.status, ToolStatus.done);
    });

    test('tool_execution_end 撞上未知 id：返回 false，不抛', () {
      final r = ChatReducer();
      expect(
        r.applyEvent(ev('tool_execution_end', {'toolCallId': 'nope'})),
        isFalse,
      );
      expect(r.applyEvent(ev('tool_execution_end')), isFalse);
    });

    test('toolRunOf 查不到就是 null（界面按「还没记录」处理）', () {
      expect(ChatReducer().toolRunOf('nope'), isNull);
      expect(ChatReducer().toolRunOf(null), isNull);
    });
  });

  group('排队与提示', () {
    test('queue_update：两条队列的长度分别计数', () {
      final r = ChatReducer();
      r.applyEvent(
        ev('queue_update', {
          'steering': ['a', 'b'],
          'followUp': ['c'],
        }),
      );
      expect(r.queuedSteering, 2);
      expect(r.queuedFollowUp, 1);

      r.applyEvent(
        ev('queue_update', {'steering': const [], 'followUp': const []}),
      );
      expect(r.queuedSteering, 0);
      expect(r.queuedFollowUp, 0);
    });

    test('queue_update 字段缺失：按 0 处理，不抛', () {
      final r = ChatReducer();
      expect(r.applyEvent(ev('queue_update')), isTrue);
      expect(r.queuedSteering, 0);
    });

    test('session_info_changed：会话名跟着变', () {
      final r = ChatReducer();
      r.applyEvent(ev('session_info_changed', {'name': '新名字'}));
      expect(r.sessionName, '新名字');
      r.applyEvent(ev('session_info_changed', {}));
      expect(r.sessionName, isNull);
    });

    test('thinking_level_changed：思考等级跟着变', () {
      final r = ChatReducer();
      r.applyEvent(ev('thinking_level_changed', {'level': 'high'}));
      expect(r.thinkingLevel, 'high');
    });
  });

  group('快照、合并与历史分页', () {
    test('applySnapshot：先清空再灌入（切会话时不能残留上一条会话的消息）', () {
      final r = ChatReducer();
      r.applyEvent(
        ev('message_start', {
          'message': {'role': 'user', 'content': '旧会话的消息'},
        }),
      );
      r.applyEvent(
        ev('tool_execution_start', {'toolCallId': 'old', 'toolName': 'bash'}),
      );

      r.applySnapshot(
        SessionSnapshot(
          sessionId: 's2',
          cwd: 'C:/another',
          messages: [
            PiMessage.fromJson({'role': 'user', 'content': '新会话'}),
          ],
          thinkingLevel: 'high',
          isStreaming: false,
          autoCompactionEnabled: false,
          historyTotal: 3,
          historyHasMore: true,
        ),
      );

      expect(r.messages.length, 1);
      expect(r.messages.single.role, 'user');
      expect(r.tools, isEmpty, reason: '换会话后旧的工具条目必须清掉');
      expect(r.cwd, 'C:/another');
      expect(r.thinkingLevel, 'high');
      expect(r.autoCompactionEnabled, isFalse);
      expect(r.historyTotal, 3);
      expect(r.historyHasMore, isTrue);
    });

    test('mergeSnapshot：只补差集，已有消息不重复', () {
      final r = ChatReducer();
      r.applySnapshot(
        SessionSnapshot(
          sessionId: 's1',
          cwd: 'C:/x',
          messages: [
            PiMessage.fromJson({'role': 'user', 'content': '第一条'}),
          ],
          thinkingLevel: 'medium',
          isStreaming: false,
        ),
      );
      final before = r.messages.length;

      r.mergeSnapshot(
        SessionSnapshot(
          sessionId: 's1',
          cwd: 'C:/x',
          messages: [
            PiMessage.fromJson({'role': 'user', 'content': '第一条'}),
          ],
          thinkingLevel: 'medium',
          isStreaming: false,
        ),
      );
      expect(r.messages.length, before, reason: '同一条消息不该被塞进来两遍');
    });

    test('prependHistory：更早的挪到前面，并更新分页游标', () {
      final r = ChatReducer();
      r.applySnapshot(
        SessionSnapshot(
          sessionId: 's1',
          cwd: 'C:/x',
          messages: [
            PiMessage.fromJson({'role': 'user', 'content': '现有'}),
          ],
          thinkingLevel: 'medium',
          isStreaming: false,
        ),
      );
      r.prependHistory(
        [
          PiMessage.fromJson({'role': 'user', 'content': '更早'}),
        ],
        5,
        true,
      );
      expect(r.messages.first.text, '更早');
      expect(r.historyStart, 5);
      expect(r.historyHasMore, isTrue);
    });
  });

  group('reset', () {
    test('reset 清空消息、工具与本轮状态', () {
      final r = ChatReducer();
      r.applyEvent(ev('agent_start'));
      r.applyEvent(
        ev('message_start', {
          'message': {'role': 'user', 'content': 'x'},
        }),
      );
      r.applyEvent(
        ev('tool_execution_start', {'toolCallId': 'c1', 'toolName': 'bash'}),
      );
      r.applyEvent(
        ev('queue_update', {
          'steering': ['a'],
        }),
      );

      r.reset();

      expect(r.messages, isEmpty);
      expect(r.tools, isEmpty);
      expect(r.isRunning, isFalse);
      expect(r.isStreaming, isFalse);
      expect(r.runStartedAt, isNull);
      expect(r.queuedSteering, 0);
    });
  });
}
