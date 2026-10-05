// 事件裁剪层：pi 的原始事件 → 手机端事件
//
// 实测依据（一次 ls 对话）：
//   原始 296,881 字节 → 裁剪后约 30,000 字节，省 90%
//
// 六条规则，每条都有实测数字支撑：
//   1. toJsonEvent       剔除 delta 里的 cumulative snapshot   省 36%
//   2. 丢 system 消息事件  整个 prompt + 全部工具 schema        省 35%
//   3. agent_end 压缩     它把 messages 数组又塞了一遍          省 18%
//   4. tool_execution_end 剔除 result（可达 1MiB 的原始输出）
//   5. tool_execution_update 按 toolCallId 合并（大输出场景省 MB 级）
//   6. 丢 entry_appended  携带整条 entry，扩展可写 1MiB

// pi 内部有官方实现（dist/modes/json-event.js），但没从包入口导出，
// 用深路径拿；万一 pi 改了内部结构就退回本地等价实现。
let toJsonEvent;
try {
  const entry = import.meta.resolve('@earendil-works/pi-coding-agent');
  ({ toJsonEvent } = await import(new URL('./modes/json-event.js', entry).href));
} catch (error) {
  console.warn('[wire] 未能加载官方 toJsonEvent，使用本地实现:', error?.message ?? error);
  toJsonEvent = localToJsonEvent;
}

/** 官方 toJsonEvent 的等价实现（照抄 dist/modes/json-event.js） */
function localToJsonEvent(event) {
  if (event.type !== 'message_update') return event;
  const inner = event.assistantMessageEvent;
  let slim = inner;
  if ('partial' in inner) {
    const { partial: _partial, ...rest } = inner;
    slim = rest;
    if (inner.type === 'toolcall_start') {
      const toolCall = inner.partial?.content?.[inner.contentIndex];
      if (toolCall?.type === 'toolCall') {
        slim = { ...rest, id: toolCall.id, toolName: toolCall.name };
      }
    }
  }
  return { type: 'message_update', usage: event.message?.usage, assistantMessageEvent: slim };
}

/** 系统消息事件：携带整个 prompt 与全部工具 schema，客户端从不渲染 */
function isSystemMessageEvent(event) {
  return (event.type === 'message_start' || event.type === 'message_end')
    && event.message?.role === 'system';
}

// ----------------------------------------------------------------
// ANSI 转义序列剔除
//
// 扩展会把终端着色写进文本（实测思考内容里出现
// `\u001b[38;2;167;152;215mThinking:`），手机上就显示成 `□[38;2;...m` 乱码。
//
// 为什么放服务端剥而不是客户端：流式的 delta 可能把一条 ANSI 序列切成两半，
// 逐块剥离会漏。在服务端剥，message_end 的权威内容一定是干净的。
// ----------------------------------------------------------------
const ANSI_PATTERN = new RegExp([
  '\\u001b\\][^\\u0007\\u001b]*(?:\\u0007|\\u001b\\\\)', // OSC ... BEL/ST
  '\\u001b\\[[0-9;?]*[ -/]*[@-~]', // CSI（颜色、光标）
  '\\u001b[()][A-Za-z0-9]', // 字符集切换
  '\\u001b[@-Z\\\\-_]', // 其它双字节转义
].join('|'), 'g');

export function stripAnsi(text) {
  return typeof text === 'string' && text.includes('\u001b')
    ? text.replace(ANSI_PATTERN, '')
    : text;
}

/** 剔除消息里文本与思考块的 ANSI 序列（返回新对象，不改原数据） */
function sanitizeMessage(message) {
  if (!message || typeof message !== 'object') return message;
  const content = message.content;
  if (typeof content === 'string') {
    const cleaned = stripAnsi(content);
    return cleaned === content ? message : { ...message, content: cleaned };
  }
  if (!Array.isArray(content)) return message;

  let changed = false;
  const next = content.map((block) => {
    if (!block || typeof block !== 'object') return block;
    if (block.type === 'text' && typeof block.text === 'string') {
      const cleaned = stripAnsi(block.text);
      if (cleaned !== block.text) {
        changed = true;
        return { ...block, text: cleaned };
      }
    } else if (block.type === 'thinking' && typeof block.thinking === 'string') {
      const cleaned = stripAnsi(block.thinking);
      if (cleaned !== block.thinking) {
        changed = true;
        return { ...block, thinking: cleaned };
      }
    }
    return block;
  });
  return changed ? { ...message, content: next } : message;
}

/** 导出给快照用：把一批消息的 ANSI 清一下 */
export function sanitizeMessages(messages) {
  return messages.map(sanitizeMessage);
}

/** 工具的部分结果（bash 滚动输出等）里同样可能带 ANSI */
function sanitizePartialResult(partialResult) {
  if (!partialResult || typeof partialResult !== 'object') {
    return typeof partialResult === 'string' ? stripAnsi(partialResult) : partialResult;
  }
  const content = partialResult.content;
  if (!Array.isArray(content)) {
    return typeof partialResult.text === 'string'
      ? { ...partialResult, text: stripAnsi(partialResult.text) }
      : partialResult;
  }
  let changed = false;
  const next = content.map((block) => {
    if (block && block.type === 'text' && typeof block.text === 'string') {
      const cleaned = stripAnsi(block.text);
      if (cleaned !== block.text) {
        changed = true;
        return { ...block, text: cleaned };
      }
    }
    return block;
  });
  return changed ? { ...partialResult, content: next } : partialResult;
}

/** 客户端从其他接口取 entry，这条事件只带来体积 */
const DROPPED_EVENT_TYPES = new Set(['entry_appended']);

/**
 * 裁剪单条事件。
 * @returns 客户端事件，或 null 表示丢弃
 */
export function toClientEvent(event) {
  if (DROPPED_EVENT_TYPES.has(event.type)) return null;
  if (isSystemMessageEvent(event)) return null;

  // 1. 官方瘦身：delta 只保留增量，不重复携带完整消息
  let slim;
  try {
    slim = toJsonEvent(event);
  } catch {
    // message_update 非 assistant 角色时官方实现会抛错，此时原样保留
    slim = event;
  }

  // 3. agent_end 携带完整 messages 数组（含那条 52KB 的 system 消息）
  if (slim.type === 'agent_end') {
    return { type: 'agent_end', willRetry: slim.willRetry ?? false };
  }

  // 4. tool_execution_end 的 result 可达 1MiB；客户端只读 ids，
  //    结果内容随后会作为 toolResult 消息送达
  if (slim.type === 'tool_execution_end') {
    const { result: _result, ...rest } = slim;
    return rest;
  }

  // 文本与思考块里的 ANSI 着色：手机上会显示成乱码，剥掉
  if (slim.message) {
    const cleaned = sanitizeMessage(slim.message);
    if (cleaned !== slim.message) slim = { ...slim, message: cleaned };
  }
  if (slim.type === 'message_update' && slim.assistantMessageEvent) {
    const inner = slim.assistantMessageEvent;
    if (typeof inner.delta === 'string') {
      const cleaned = stripAnsi(inner.delta);
      if (cleaned !== inner.delta) {
        slim = { ...slim, assistantMessageEvent: { ...inner, delta: cleaned } };
      }
    }
  }

  // 5. 工具进度里也可能带 ANSI（bash 输出的颜色），一并剥掉
  if (slim.type === 'tool_execution_update' && slim.partialResult) {
    const cleaned = sanitizePartialResult(slim.partialResult);
    if (cleaned !== slim.partialResult) {
      slim = { ...slim, partialResult: cleaned };
    }
  }

  return slim;
}

/** 该事件是否"后续事件能修复它"（背压时可安全丢弃） */
export function isDroppable(event) {
  if (event.type === 'tool_execution_update') return true;
  if (event.type === 'bash_execution_update') return true;
  if (event.type !== 'message_update') return false;
  const inner = event.assistantMessageEvent;
  return typeof inner?.type === 'string' && inner.type.endsWith('_delta');
}

/** 嵌套工具调用：另一个工具在运行中发起的调用，模型看不到，客户端也不必细看 */
export function isNestedToolEvent(event) {
  return (event.type === 'tool_execution_start'
    || event.type === 'tool_execution_update'
    || event.type === 'tool_execution_end')
    && typeof event.parentToolCallId === 'string'
    && event.parentToolCallId !== '';
}
