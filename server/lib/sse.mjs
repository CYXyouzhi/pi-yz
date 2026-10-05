// SSE 事件流。
//
// 设计要点（照 pi-web 踩过的坑）：
//   1. 先开流，再等会话就绪，最后发快照 —— 避免"连接建立但客户端不知道状态"
//   2. 快照期间的事件先缓冲，快照发完再按序补发 —— 不丢事件，宁可重复
//   3. 背压：手机切后台/锁屏时会停止读取，积压全部留在服务端内存里
//   4. 心跳 30s，防止中间层掐掉空闲连接

import { isDroppable, sanitizeMessages } from './wire.mjs';

const HEARTBEAT_MS = 30_000;

// 超过这个积压就丢弃"后续事件能修复它"的增量（delta、工具进度）
const HIGH_WATER_BYTES = 512 * 1024;
// 超过这个积压就直接断流，让客户端重连后重新拿快照
const BACKLOG_LIMIT_BYTES = 16 * 1024 * 1024;

// 快照只发最近这么多条消息。
//
// 实测一个用很久的会话有 523 条上下文消息（原始记录 1275 条、59MB），
// 一次全发出去手机端要等很久，看起来就是「历史不显示」。
// 更早的消息用 get_history 往上翻页。
const SNAPSHOT_MESSAGE_LIMIT = 60;

/** 构造客户端连接时需要的初始状态 */
export async function buildSnapshot(live) {
  const session = live.session;
  // 剔除 system 消息：实测那条携带整个 prompt 与全部工具 schema，约 52KB
  const all = session.messages.filter((m) => m.role !== 'system');
  const recent = all.length > SNAPSHOT_MESSAGE_LIMIT
    ? all.slice(-SNAPSHOT_MESSAGE_LIMIT)
    : all;

  return {
    sessionId: live.id,
    cwd: live.cwd,
    model: session.model
      ? {
        provider: session.model.provider,
        id: session.model.id,
        name: session.model.name ?? session.model.id,
        contextWindow: session.model.contextWindow ?? null,
      }
      : null,
    thinkingLevel: session.thinkingLevel,
    isStreaming: session.isStreaming,
    sessionName: session.sessionName,
    autoCompactionEnabled: session.autoCompactionEnabled,
    // 已完成的上下文消息：客户端据此渲染历史，之后靠事件增量维护
    messages: sanitizeMessages(recent),
    // 历史分页信息
    historyTotal: all.length,
    historyHasMore: all.length > recent.length,
  };
}

/**
 * 建立一条 SSE 流。
 * @param {import('node:http').IncomingMessage} req
 * @param {import('node:http').ServerResponse} res
 * @param {() => Promise<import('./live-session.mjs').LiveSession>} openLive 惰性打开会话
 */
export function openEventStream(req, res, openLive) {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache, no-transform',
    Connection: 'keep-alive',
    // 让 nginx 之类的反代不要缓冲（局域网直连用不到，留着无妨）
    'X-Accel-Buffering': 'no',
  });

  let closed = false;
  let unsubscribe = null;
  let heartbeat = null;
  let droppedCount = 0;

  const cleanup = (reason) => {
    if (closed) return;
    closed = true;
    if (heartbeat) clearInterval(heartbeat);
    unsubscribe?.();
    if (reason) console.log(`[sse] 关闭 ${reason}`);
  };

  const sendRaw = (text) => {
    if (closed) return;
    // res.writableLength = 已排队但还没写进 socket 的字节数
    const queued = res.writableLength;
    if (queued > BACKLOG_LIMIT_BYTES) {
      console.warn(`[sse] 客户端积压 ${Math.round(queued / 1024)}KB 超限，断开让客户端重连`);
      cleanup('积压超限');
      res.destroy();
      return;
    }
    try {
      res.write(text);
    } catch {
      cleanup('写入失败');
    }
  };

  const sendEvent = (event) => {
    if (closed) return;
    if (isDroppable(event) && res.writableLength > HIGH_WATER_BYTES) {
      droppedCount += 1;
      return; // 静默丢弃：后续的 *_end / 下一条 update 会覆盖它
    }
    sendRaw(`data: ${JSON.stringify(event)}\n\n`);
  };

  const sendNamed = (name, payload) => {
    sendRaw(`event: ${name}\ndata: ${JSON.stringify(payload)}\n\n`);
  };

  // 客户端断开
  req.on('close', () => cleanup('客户端断开'));
  res.on('error', () => cleanup('响应出错'));

  // 心跳：注释行，不会触发客户端的 message 回调
  heartbeat = setInterval(() => sendRaw(': ping\n\n'), HEARTBEAT_MS);
  heartbeat.unref?.();

  // 先告诉客户端"正在准备会话"，避免长时间静默
  sendNamed('status', { phase: 'connecting' });

  void (async () => {
    let live;
    try {
      live = await openLive();
    } catch (error) {
      sendNamed('status', { phase: 'error', message: String(error?.message ?? error) });
      cleanup('打开会话失败');
      res.end();
      return;
    }
    if (closed) return;

    // 先订阅再取快照：中间产生的事件先缓冲，保证不丢
    const buffered = [];
    let snapshotSent = false;
    unsubscribe = live.subscribe((event) => {
      if (event.type === 'session_shutdown') {
        sendNamed('status', { phase: 'shutdown' });
        cleanup('会话关闭');
        res.end();
        return;
      }
      if (!snapshotSent) {
        buffered.push(event);
        return;
      }
      sendEvent(event);
    });

    try {
      const snapshot = await buildSnapshot(live);
      if (closed) return;
      sendNamed('snapshot', snapshot);
      snapshotSent = true;
      for (const event of buffered) sendEvent(event);
    } catch (error) {
      sendNamed('status', { phase: 'error', message: String(error?.message ?? error) });
      cleanup('快照失败');
      res.end();
      return;
    }

    console.log(`[sse] 已连接 ${live.id}（缓冲补发 ${buffered.length} 条）`);
  })();
}
