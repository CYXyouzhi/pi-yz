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

  // 流式增量：一条助手消息在生成时会拆成几十个 message_update 事件，
  // 这里管「把碎片拼回去」。之前这一整块（_onMessageUpdate / _onMessageEnd）
  // 覆盖率接近 0 —— 而它是聊天页正文的唯一来源。
  group('流式增量：把碎片拼回一条消息', () {
    ChatReducer withAssistant() {
      final r = ChatReducer();
      r.applyEvent(ev('message_start', {'message': assistantJson()}));
      return r;
    }

    ServerEvent delta(String type, [Map<String, dynamic> extra = const {}]) =>
        ev('message_update', {
          'assistantMessageEvent': {'type': type, ...extra},
        });

    test('text_delta：按到达顺序累加到正文，并返回 true 让界面重绘', () {
      final r = withAssistant();
      expect(r.applyEvent(delta('text_delta', {'delta': '你好'})), isTrue);
      expect(r.applyEvent(delta('text_delta', {'delta': '，世界'})), isTrue);
      expect(r.messages.single.text, '你好，世界');
    });

    test('thinking_delta：累进「思考」，不跟正文混在一起', () {
      final r = withAssistant();
      r.applyEvent(delta('thinking_delta', {'delta': '先想一下'}));
      expect(r.messages.single.thinking, '先想一下');
      expect(r.messages.single.text, isEmpty, reason: '思考不该混进正文');
    });

    test('start / end / toolcall_delta 类不触发重绘（没有新内容）', () {
      final r = withAssistant();
      for (final type in [
        'text_start',
        'text_end',
        'thinking_start',
        'thinking_end',
        'toolcall_delta',
      ]) {
        expect(r.applyEvent(delta(type)), isFalse, reason: '$type 不该让界面重绘');
      }
    });

    test('toolcall_start：补出工具名与 id（参数要等 message_end）', () {
      final r = withAssistant();
      expect(
        r.applyEvent(delta('toolcall_start', {'id': 'c1', 'toolName': 'bash'})),
        isTrue,
      );
      final call = r.messages.single.toolCalls.single;
      expect(call.id, 'c1');
      expect(call.name, 'bash');
      expect(call.arguments, isEmpty, reason: '流式期间的参数还不完整，先不解析');
    });

    test('toolcall_end：用完整参数替换掉最后一个（参数真正到手的地方）', () {
      final r = withAssistant();
      r.applyEvent(delta('toolcall_start', {'id': 'c1', 'toolName': 'bash'}));
      expect(
        r.applyEvent(
          delta('toolcall_end', {
            'toolCall': {
              'id': 'c1',
              'name': 'bash',
              'arguments': {'command': 'ls'},
            },
          }),
        ),
        isTrue,
      );
      expect(r.messages.single.toolCalls.single.arguments['command'], 'ls');
    });

    test('还没有助手消息时：返回 false，绝不凭空造一条消息出来', () {
      final r = ChatReducer();
      expect(r.applyEvent(delta('text_delta', {'delta': 'x'})), isFalse);
      expect(r.messages, isEmpty);
    });

    test('assistantMessageEvent 不是对象 / 缺 type：返回 false 且不抛', () {
      final r = withAssistant();
      expect(
        r.applyEvent(ev('message_update', {'assistantMessageEvent': 'oops'})),
        isFalse,
      );
      expect(
        r.applyEvent(
          ev('message_update', {
            'assistantMessageEvent': {'x': 1},
          }),
        ),
        isFalse,
      );
      expect(r.messages.single.text, isEmpty);
    });
  });

  group('message_end：一条消息的收口', () {
    test('同 role：吸收进上一条，而不是新开一条（否则流式消息会被拆成两条）', () {
      final r = ChatReducer();
      r.applyEvent(ev('message_start', {'message': assistantJson()}));
      r.applyEvent(
        ev('message_update', {
          'assistantMessageEvent': {'type': 'text_delta', 'delta': '前半'},
        }),
      );

      r.applyEvent(
        ev('message_end', {
          'message': assistantJson(
            content: [
              {'type': 'text', 'text': '前半后半'},
            ],
          ),
        }),
      );

      expect(r.messages, hasLength(1), reason: '不该变成两条');
      expect(r.messages.single.text, contains('前半后半'));
      expect(r.isStreaming, isFalse, reason: '消息收口后要退出流式态');
    });

    test('role=system：完全忽略（系统通知不该出现在聊天列表里）', () {
      final r = ChatReducer();
      expect(
        r.applyEvent(
          ev('message_end', {
            'message': {'role': 'system', 'content': '内部提示'},
          }),
        ),
        isFalse,
      );
      expect(r.messages, isEmpty);
    });

    test('没有对应的 start（事件丢了）：补一条，内容不许丢', () {
      final r = ChatReducer();
      expect(
        r.applyEvent(
          ev('message_end', {
            'message': assistantJson(
              content: [
                {'type': 'text', 'text': '只有结尾'},
              ],
            ),
          }),
        ),
        isTrue,
      );
      expect(r.messages, hasLength(1));
      expect(r.messages.single.text, contains('只有结尾'));
    });

    test('message 不是对象：返回 false', () {
      final r = ChatReducer();
      expect(r.applyEvent(ev('message_end', {'message': 'oops'})), isFalse);
    });
  });

  group('工具执行中的实时输出', () {
    ChatReducer withTool() {
      final r = ChatReducer();
      r.applyEvent(
        ev('tool_execution_start', {'toolCallId': 't1', 'toolName': 'bash'}),
      );
      return r;
    }

    test('partialResult 是字符串：直接当输出', () {
      final r = withTool();
      expect(
        r.applyEvent(
          ev('tool_execution_update', {
            'toolCallId': 't1',
            'partialResult': '第一行',
          }),
        ),
        isTrue,
      );
      expect(r.toolRunOf('t1')!.output, contains('第一行'));
    });

    test('partialResult 是 content 数组：只拼 text 片段，忽略图片等', () {
      final r = withTool();
      r.applyEvent(
        ev('tool_execution_update', {
          'toolCallId': 't1',
          'partialResult': {
            'content': [
              {'type': 'text', 'text': 'A'},
              {'type': 'image', 'data': 'xxx'},
              {'type': 'text', 'text': 'B'},
            ],
          },
        }),
      );
      expect(r.toolRunOf('t1')!.output, contains('AB'));
    });

    test('partialResult 是 {text: ...}：照样能取出来', () {
      final r = withTool();
      r.applyEvent(
        ev('tool_execution_update', {
          'toolCallId': 't1',
          'partialResult': {'text': '来自 text 字段'},
        }),
      );
      expect(r.toolRunOf('t1')!.output, contains('来自 text 字段'));
    });

    test('取不出文本：返回 false，不改工具卡片', () {
      final r = withTool();
      expect(
        r.applyEvent(
          ev('tool_execution_update', {
            'toolCallId': 't1',
            'partialResult': 42,
          }),
        ),
        isFalse,
      );
    });

    test('未知 id：返回 false 且不抛', () {
      final r = withTool();
      expect(
        r.applyEvent(
          ev('tool_execution_update', {
            'toolCallId': 'nope',
            'partialResult': 'x',
          }),
        ),
        isFalse,
      );
    });
  });

  group('自动压缩与自动重试：都要让用户看得见', () {
    test('compaction_start：给一句提示', () {
      final r = ChatReducer();
      expect(r.applyEvent(ev('compaction_start')), isTrue);
      expect(r.notice, isNotNull);
    });

    test('compaction_end：带 errorMessage 时提示里含原因，否则清掉提示', () {
      final r = ChatReducer();
      r.applyEvent(ev('compaction_start'));
      r.applyEvent(ev('compaction_end', {'errorMessage': '上下文太长了'}));
      expect(r.notice, contains('上下文太长了'));

      r.applyEvent(ev('compaction_end', {}));
      expect(r.notice, isNull, reason: '压缩完了就该把提示收掉');
    });

    test('auto_retry_start：提示里带上第几次 / 共几次', () {
      final r = ChatReducer();
      r.applyEvent(ev('auto_retry_start', {'attempt': 2, 'maxAttempts': 3}));
      expect(r.notice, contains('2'));
      expect(r.notice, contains('3'));
    });

    test('auto_retry_end：成功则清提示，失败则留一句', () {
      final r = ChatReducer();
      r.applyEvent(ev('auto_retry_start', {'attempt': 1, 'maxAttempts': 3}));
      r.applyEvent(ev('auto_retry_end', {'success': true}));
      expect(r.notice, isNull);

      r.applyEvent(ev('auto_retry_start', {'attempt': 1, 'maxAttempts': 3}));
      r.applyEvent(ev('auto_retry_end', {'success': false}));
      expect(r.notice, isNotNull);
    });

    test('session_shutdown：运行与流式都停，并留下提示', () {
      final r = ChatReducer();
      r.applyEvent(ev('agent_start'));
      expect(r.isRunning, isTrue);

      expect(r.applyEvent(ev('session_shutdown')), isTrue);
      expect(r.isRunning, isFalse, reason: '会话关了就不该再显示「运行中」');
      expect(r.isStreaming, isFalse);
      expect(r.notice, isNotNull);
    });
  });
}
