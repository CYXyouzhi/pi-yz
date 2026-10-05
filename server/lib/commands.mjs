// 命令层：语义照 dist/modes/rpc/rpc-mode.js 实现（那是 pi 官方的 RPC 服务器）。
//
// 手机端只有一个入口：
//   POST /api/sessions/:id/command   body = { id, type, ...参数 }
//
// 响应格式与 pi 的 RPC 协议一致：
//   { id, type:"response", command, success:true, data }
//   { id, type:"response", command, success:false, error }
//
// 之所以照抄而不是自创：pi 的扩展会检查命令语义（比如 prompt 的 disposition），
// 保持一致可以让扩展在手机端和在 CLI 里行为相同。

import { withChineseDescriptions } from './hanhua.mjs';
import { SessionManager } from '@earendil-works/pi-coding-agent';
import { resolveSessionMeta } from './sessions.mjs';

import { success, failure, clipModel } from './protocol.mjs';
import { BUILTIN_COMMANDS, tryBuiltinCommand } from './builtin-commands.mjs';

export async function executeCommand(ctx, command) {
  const { session, live, pool } = ctx;
  const id = command.id;

  switch (command.type) {
    // ==================== 对话 ====================
    case 'prompt': {
      // 先试内置命令拦截。命中就自己执行，绝不发给模型。
      // 未命中才交给 pi，由它判断是扩展命令 / 提示模板 / 技能命令 / 普通文本。
      const intercepted = await tryBuiltinCommand(ctx, command.message, id);
      if (intercepted.handled) return intercepted.response;

      // 照 pi 的做法：预检通过就立即响应，真正的运行结果通过事件流推送。
      //
      // 但 HTTP 是请求-响应模型，不能像 RPC 那样只靠 stdout：
      // 扩展命令可能在执行中弹出对话框并阻塞很久（实测 /汉化 就会），
      // 那时 preflightResult 一直不回调，请求就挂死了。
      // 所以加一个兜底超时，先告诉客户端「已收到」。
      return new Promise((resolve) => {
        let responded = false;
        const done = (response) => {
          if (responded) return;
          responded = true;
          clearTimeout(fallback);
          resolve(response);
        };
        const fallback = setTimeout(() => {
          done(success(id, 'prompt', { disposition: 'pending' }));
        }, 3000);

        session
          .prompt(command.message, {
            images: command.images,
            streamingBehavior: command.streamingBehavior,
            source: 'rpc',
            preflightResult: (disposition) => done(success(id, 'prompt', { disposition })),
          })
          .then(() => done(success(id, 'prompt', { disposition: 'started' })))
          .catch((error) => done(failure(id, 'prompt', error)));
      });
    }

    case 'steer': {
      const disposition = await session.steer(command.message, command.images, { source: 'rpc' });
      return success(id, 'steer', { disposition });
    }

    case 'follow_up': {
      const disposition = await session.followUp(command.message, command.images, { source: 'rpc' });
      return success(id, 'follow_up', { disposition });
    }

    case 'abort': {
      await session.abort();
      return success(id, 'abort');
    }

    case 'clear_queue': {
      return success(id, 'clear_queue', session.clearQueue());
    }

    // ==================== 状态 ====================
    case 'get_state': {
      return success(id, 'get_state', {
        model: clipModel(session.model),
        thinkingLevel: session.thinkingLevel,
        isStreaming: session.isStreaming,
        isCompacting: session.isCompacting,
        steeringMode: session.steeringMode,
        followUpMode: session.followUpMode,
        sessionId: session.sessionId,
        sessionName: session.sessionName,
        autoCompactionEnabled: session.autoCompactionEnabled,
        messageCount: session.messages.length,
        pendingMessageCount: session.pendingMessageCount,
        steeringQueue: session.getSteeringMessages(),
        followUpQueue: session.getFollowUpMessages(),
        // 服务端附加信息：客户端要显示"当前在哪个项目"
        cwd: live.cwd,
        // 注意：不返回 sessionFile —— 那是服务端的本地路径
      });
    }

    case 'get_messages': {
      // 当前分支的模型上下文消息。压缩发生后早期消息会被摘要替代，
      // 要看完整历史应使用 get_entries。
      return success(id, 'get_messages', { messages: session.messages });
    }

    // 历史分页：取更早的消息（快照只给了最近几十条）
    case 'get_history': {
      const all = session.messages.filter((m) => m.role !== 'system');
      const limit = Math.min(Math.max(Number(command.limit) || 40, 1), 200);
      // before 是「已加载的最早一条在全集里的下标」，未传则从末尾算
      const before = Number.isFinite(Number(command.before))
        ? Number(command.before)
        : all.length;
      const start = Math.max(0, before - limit);
      return success(id, 'get_history', {
        messages: all.slice(start, before),
        start,
        before,
        total: all.length,
        hasMore: start > 0,
      });
    }

    case 'get_entries': {
      const manager = session.sessionManager;
      let entries = manager.getEntries();
      if (command.since !== undefined) {
        const index = entries.findIndex((entry) => entry.id === command.since);
        if (index === -1) return failure(id, 'get_entries', `Entry not found: ${command.since}`);
        entries = entries.slice(index + 1);
      }
      return success(id, 'get_entries', { entries, leafId: manager.getLeafId() });
    }

    case 'get_last_assistant_text': {
      return success(id, 'get_last_assistant_text', { text: session.getLastAssistantText() });
    }

    // 复制会话：把源会话的完整历史写成一个新会话（新 ID，header 里记录 parentSession）。
    //
    // 这是「在当前节点分出一条新支」的做法：用 SessionManager.forkFrom，
    // 不碰源会话文件（所以不会把主人的会话改坏），也不需要 AgentSessionRuntime。
    case 'clone_session': {
      const targetId = String(command.sessionId ?? '').trim();
      let sourceFile = session.sessionFile;
      let targetCwd = live.cwd;

      if (targetId && targetId !== session.sessionId) {
        const meta = await resolveSessionMeta(targetId);
        sourceFile = meta.path;
        targetCwd = meta.cwd;
      }
      if (!sourceFile) {
        return failure(id, 'clone_session', '当前会话还没落盘（先发一条消息）');
      }

      const forked = SessionManager.forkFrom(sourceFile, targetCwd);
      return success(id, 'clone_session', {
        sessionId: forked.getSessionId(),
        cwd: targetCwd,
        sourceId: targetId || session.sessionId,
      });
    }

    // 从某条历史消息分出一条新会话（= 复制完整历史 + 把新会话的叶子回退到该节点）。
    //
    // 两步都是官方支持的能力（forkFrom 复制、navigateTree 回退），
    // 不需要 AgentSessionRuntime；源会话始终不被修改。
    case 'fork_from_message': {
      const entryId = String(command.entryId ?? '').trim();
      if (!entryId) return failure(id, 'fork_from_message', '缺少 entryId');
      const sourceFile = session.sessionFile;
      if (!sourceFile) {
        return failure(id, 'fork_from_message', '当前会话还没落盘（先发一条消息）');
      }

      const forked = SessionManager.forkFrom(sourceFile, live.cwd);
      const newId = forked.getSessionId();

      // 打开新会话并把叶子回退到目标节点；回退后剩下的旧路径会留在文件里当旁支
      const child = await pool.open(newId);
      const result = await child.session.navigateTree(entryId, {});

      return success(id, 'fork_from_message', {
        sessionId: newId,
        cwd: live.cwd,
        cancelled: result?.cancelled ?? false,
        editorText: result?.editorText ?? null,
      });
    }

    // 会话分支树（手机上只读浏览 + 可切换）
    case 'get_tree': {
      const manager = session.sessionManager;
      return success(id, 'get_tree', {
        tree: manager.getTree(),
        leafId: manager.getLeafId(),
      });
    }

    // 切到树里的另一个节点（同一会话内换分支）。
    // 不需要 AgentSessionRuntime：navigateTree 是 AgentSession 自己的方法。
    case 'navigate_tree': {
      const targetId = String(command.targetId ?? '').trim();
      if (!targetId) return failure(id, 'navigate_tree', '缺少 targetId');
      const result = await session.navigateTree(targetId, {
        summarize: command.summarize === true,
        customInstructions: command.customInstructions,
        replaceInstructions: command.replaceInstructions,
        label: command.label,
      });
      return success(id, 'navigate_tree', {
        cancelled: result?.cancelled ?? false,
        editorText: result?.editorText ?? null,
        leafId: session.sessionManager.getLeafId(),
      });
    }

    case 'get_session_stats': {
      return success(id, 'get_session_stats', session.getSessionStats());
    }

    // ==================== 可用命令（slash 的自动补全数据源） ====================
    case 'get_commands': {
      const commands = [];
      // ① 扩展注册的命令
      for (const item of session.extensionRunner?.getRegisteredCommands?.() ?? []) {
        commands.push({
          name: item.invocationName,
          description: item.description,
          source: 'extension',
          sourceInfo: item.sourceInfo,
        });
      }
      // ② prompt 模板
      for (const template of session.promptTemplates) {
        commands.push({
          name: template.name,
          description: template.description,
          source: 'prompt',
          sourceInfo: template.sourceInfo,
        });
      }
      // ③ 技能（名字带 skill: 前缀）
      for (const skill of session.resourceLoader?.getSkills?.().skills ?? []) {
        commands.push({
          name: `skill:${skill.name}`,
          description: skill.description,
          source: 'skill',
          sourceInfo: skill.sourceInfo,
          sourcePath: skill.filePath ?? null,
        });
      }
      // ④ 内置命令：pi 的 get_commands 不会报它们（CLI 里由交互层实现），
      //    由我们维护（见 lib/builtin-commands.mjs）
      for (const item of BUILTIN_COMMANDS) {
        commands.push({
          name: item.name,
          description: item.description,
          argHint: item.argHint,
          source: 'builtin',
        });
      }
      // 同 config-info：补中文说明（开关语言的展示交给 App）
      return success(id, 'get_commands', { commands: withChineseDescriptions(commands) });
    }

    // ==================== 模型 ====================
    case 'get_available_models': {
      const models = session.modelRuntime.getAvailableSnapshot();
      return success(id, 'get_available_models', { models: models.map(clipModel) });
    }

    case 'set_model': {
      const models = session.modelRuntime.getAvailableSnapshot();
      const found = models.find(
        (m) => m.provider === command.provider && m.id === command.modelId,
      );
      if (!found) {
        return failure(id, 'set_model', `Model not found: ${command.provider}/${command.modelId}`);
      }
      await session.setModel(found);
      return success(id, 'set_model', clipModel(found));
    }

    case 'cycle_model': {
      const result = await session.cycleModel();
      if (!result) return success(id, 'cycle_model', { model: null });
      return success(id, 'cycle_model', {
        model: clipModel(result.model),
        thinkingLevel: result.thinkingLevel,
      });
    }

    // ==================== 思考等级 ====================
    case 'get_available_thinking_levels': {
      return success(id, 'get_available_thinking_levels', {
        levels: session.getAvailableThinkingLevels(),
        current: session.thinkingLevel,
      });
    }

    case 'set_thinking_level': {
      session.setThinkingLevel(command.level);
      return success(id, 'set_thinking_level', { level: session.thinkingLevel });
    }

    // ==================== 压缩 ====================
    case 'compact': {
      const result = await session.compact(command.instructions);
      return success(id, 'compact', result);
    }

    case 'abort_compaction': {
      session.abortCompaction();
      return success(id, 'abort_compaction');
    }

    case 'set_auto_compaction': {
      session.setAutoCompactionEnabled(Boolean(command.enabled));
      return success(id, 'set_auto_compaction', { enabled: session.autoCompactionEnabled });
    }

    // ==================== 会话元信息 ====================
    case 'set_session_name': {
      const name = String(command.name ?? '').trim();
      if (!name) return failure(id, 'set_session_name', '会话名不能为空');
      session.setSessionName(name);
      return success(id, 'set_session_name', { name });
    }

    // 重命名「任意」会话（不只是当前跑着的那条）。
    // 不在池里时临时打开改名再释放：改名会往会话文件写一条 session_info，
    // 所以即使马上 dispose 也已经持久化了。
    case 'rename_session': {
      const targetId = String(command.sessionId ?? '').trim();
      const name = String(command.name ?? '').trim();
      if (!targetId) return failure(id, 'rename_session', '缺少 sessionId');
      if (!name) return failure(id, 'rename_session', '会话名不能为空');

      const existing = pool.get(targetId);
      if (existing) {
        existing.session.setSessionName(name);
        return success(id, 'rename_session', { sessionId: targetId, name, reused: true });
      }

      const opened = await pool.open(targetId);
      try {
        opened.session.setSessionName(name);
      } finally {
        await pool.dispose(targetId);
      }
      return success(id, 'rename_session', { sessionId: targetId, name, reused: false });
    }

    // ==================== 直接执行 shell ====================
    case 'bash': {
      const result = await session.executeBash(command.command);
      return success(id, 'bash', result);
    }

    case 'abort_bash': {
      session.abortBash();
      return success(id, 'abort_bash');
    }

    // ==================== 调试：直接驱动扩展 UI 上下文 ====================
    // 用途：验证“服务端 → SSE → 手机端 → HTTP 回应”这条链路。
    // 调用会阻塞，直到客户端回应或超时，所以不要在前台等太久。
    case 'debug_ui': {
      const ui = live.ui?.context;
      if (!ui) return failure(id, 'debug_ui', '会话未绑定 UI 上下文');
      const method = String(command.method ?? '');
      if (typeof ui[method] !== 'function') {
        return failure(id, 'debug_ui', `未知的 UI 方法: ${method}`);
      }
      const result = await ui[method](...(command.args ?? []));
      return success(id, 'debug_ui', { result: result ?? null });
    }

    // ==================== 会话生命周期（池操作） ====================
    case 'new_session': {
      const created = await pool.create(command.cwd ?? live.cwd);
      // 新会话是独立的一条；客户端拿到 id 后切换过去
      return success(id, 'new_session', { sessionId: created.id, cwd: created.cwd });
    }

    default:
      return failure(id, command.type, `Unknown command: ${command.type}`);
  }
}
