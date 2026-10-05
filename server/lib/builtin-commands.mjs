// 内置命令拦截表 —— 主人最初担心的那一层。
//
// 背景：pi 的 prompt() 只会自动处理三类输入：
//   ① 扩展注册的命令（/mycommand）
//   ② prompt 模板（/template）
//   ③ 技能命令（/skill:name）
// 而 CLI 里那些内置命令（/model、/compact、/new…）由交互层实现，
// 在 RPC 模式下由结构化命令实现，SDK 既不提供清单也不认这些文本。
//
// 所以如果不拦：
//   用户打 /model → 被当成普通文本发给模型 → 浪费 token 且行为错误
//
// 拦截规则（简单且安全）：
//   命中本表 → 自己执行，绝不发给模型
//   未命中   → 原样交给 session.prompt()，由 pi 判断是资源命令还是普通文本
//
// 代价：本表是唯一需要自己维护的东西（约 15 条，每条一行映射）。

import { success, failure, clipModel } from './protocol.mjs';

/** 客户端拿到 kind 后决定怎么展示 */
const picker = (pickerKind, title, options) => ({
  kind: 'picker',
  picker: pickerKind,
  title,
  options,
});

const text = (message, extra = {}) => ({ kind: 'text', text: message, ...extra });

const data = (payload, title) => ({ kind: 'data', title, data: payload });

/**
 * 内置命令清单。同时作为 get_commands 的 ④ 类来源，
 * 让手机端的 "/" 补全能列出它们。
 */
export const BUILTIN_COMMANDS = [
  { name: 'model', description: '选择或切换模型', argHint: '[provider/id]' },
  { name: 'thinking', description: '设置思考等级', argHint: '[off|low|medium|high]' },
  { name: 'compact', description: '压缩上下文', argHint: '[说明]' },
  { name: 'new', description: '新建会话' },
  { name: 'name', description: '设置会话名', argHint: '[名称]' },
  { name: 'session', description: '查看会话统计' },
  { name: 'tree', description: '查看会话分支树' },
  { name: 'copy', description: '取出最后一条回复' },
  { name: 'reload', description: '重载扩展、技能与模板' },
  { name: 'export', description: '导出会话为 HTML' },
  { name: 'abort', description: '停止当前运行' },
  { name: 'clear', description: '清空排队消息' },
  { name: 'help', description: '列出全部可用命令' },
];

/** 手机端暂不支持、但也不该被当成普通文本发给模型的命令 */
const UNSUPPORTED = new Map([
  ['settings', '设置界面请在电脑端的 pi 里操作'],
  ['scoped-models', '循环模型配置请在电脑端操作'],
  ['login', '登录请在电脑端操作'],
  ['logout', '登出请在电脑端操作'],
  ['trust', '项目信任请在电脑端操作'],
  ['llama', 'llama.cpp 管理请在电脑端操作'],
  ['share', '分享功能手机端暂未实现'],
  ['bug', '问题报告请在电脑端操作'],
  ['hotkeys', '快捷键是终端专有功能'],
  ['changelog', '更新日志请在电脑端查看'],
  ['quit', '手机端请直接断开连接'],
  ['import', '导入会话请在电脑端操作'],
  ['resume', '手机端请在会话列表里切换'],
  ['fork', '分支功能手机端暂未实现'],
  ['clone', '克隆功能手机端暂未实现'],
]);

const HANDLERS = {
  // ---- 模型 ----
  async model({ session }, args) {
    const models = session.modelRuntime.getAvailableSnapshot();
    const asOption = (m) => ({
      value: `${m.provider}/${m.id}`,
      label: m.name ?? m.id,
      group: m.provider,
      current: m.provider === session.model?.provider && m.id === session.model?.id,
    });

    if (!args) {
      return picker('model', '选择模型', models.map(asOption));
    }

    // 精确匹配优先
    const exact = models.find((m) => `${m.provider}/${m.id}` === args)
      ?? models.find((m) => m.id === args);
    if (exact) {
      await session.setModel(exact);
      return text(`已切换到 ${exact.provider}/${exact.id}`);
    }

    // 模糊匹配：实测 33 个模型里名字含 "deepseek" 的有多个，
    // 自动挑一个会切错模型，所以只在唯一命中时才切换，否则让用户选
    const needle = args.toLowerCase();
    const fuzzy = models.filter(
      (m) => m.id.toLowerCase().includes(needle) || (m.name ?? '').toLowerCase().includes(needle),
    );
    if (fuzzy.length === 0) return text(`未找到模型：${args}`);
    if (fuzzy.length === 1) {
      await session.setModel(fuzzy[0]);
      return text(`已切换到 ${fuzzy[0].provider}/${fuzzy[0].id}`);
    }
    return picker('model', `匹配「${args}」的模型（${fuzzy.length} 个）`, fuzzy.map(asOption));
  },

  // ---- 思考等级 ----
  async thinking({ session }, args) {
    const levels = session.getAvailableThinkingLevels();
    if (!args) {
      return picker(
        'thinking',
        '思考等级',
        levels.map((level) => ({
          value: level,
          label: level,
          current: level === session.thinkingLevel,
        })),
      );
    }
    if (!levels.includes(args)) {
      return text(`无效等级：${args}（可选：${levels.join(' / ')}）`);
    }
    session.setThinkingLevel(args);
    return text(`思考等级已设为 ${args}`);
  },

  // ---- 压缩 ----
  compact({ session }, args) {
    // 不 await：压缩可能跑几十秒，客户端通过 compaction_start/end 事件看进度
    void session.compact(args || undefined).catch((error) => {
      console.error('[builtin] 压缩失败:', error?.message ?? error);
    });
    return text('已开始压缩上下文');
  },

  // ---- 会话 ----
  async new({ pool, live }) {
    const created = await pool.create(live.cwd);
    return text(`已新建会话（${created.id.slice(0, 8)}）`, { switchTo: created.id });
  },

  name({ session }, args) {
    if (!args) {
      return text(session.sessionName ? `当前会话名：${session.sessionName}` : '当前会话未命名');
    }
    session.setSessionName(args);
    return text(`会话名已设为「${args}」`);
  },

  session({ session }) {
    const stats = session.getSessionStats();
    return data(stats, '会话统计');
  },

  tree({ session }) {
    const manager = session.sessionManager;
    return data({ tree: manager.getTree(), leafId: manager.getLeafId() }, '会话分支');
  },

  copy({ session }) {
    const last = session.getLastAssistantText();
    return last ? text(last, { clipboard: true }) : text('还没有可复制的回复');
  },

  async reload({ session }) {
    await session.reload();
    return text('已重载扩展、技能与模板');
  },

  async export({ session }) {
    const result = await session.exportToHtml();
    return text(`已导出到服务端：${result?.path ?? '(未知路径)'}`);
  },

  async abort({ session }) {
    await session.abort();
    return text('已停止当前运行');
  },

  clear({ session }) {
    const cleared = session.clearQueue();
    const total = (cleared.steering?.length ?? 0) + (cleared.followUp?.length ?? 0);
    return text(total > 0 ? `已清空 ${total} 条排队消息` : '队列本来就是空的');
  },

  // ---- 帮助 ----
  help({ session }) {
    const extension = session.extensionRunner?.getRegisteredCommands?.() ?? [];
    const templates = session.promptTemplates ?? [];
    const skills = session.resourceLoader?.getSkills?.().skills ?? [];
    const lines = [
      '内置命令：',
      ...BUILTIN_COMMANDS.map((c) => `  /${c.name}${c.argHint ? ' ' + c.argHint : ''} — ${c.description}`),
    ];
    if (extension.length) {
      lines.push('', '扩展命令：', ...extension.map((c) => `  /${c.invocationName} — ${c.description ?? ''}`));
    }
    if (templates.length) {
      lines.push('', '提示模板：', ...templates.map((t) => `  /${t.name} — ${t.description ?? ''}`));
    }
    if (skills.length) {
      lines.push('', `技能命令：${skills.length} 个（/skill:名称）`);
    }
    return text(lines.join('\n'));
  },
};

/**
 * 尝试把一条以 / 开头的输入当作内置命令执行。
 *
 * @returns {{handled: boolean, response?: object}}
 */
export async function tryBuiltinCommand(ctx, message, commandId) {
  if (typeof message !== 'string' || !message.startsWith('/')) return { handled: false };

  // 只认单行命令：换行后的内容是参数（比如 /compact 的自定义说明）
  const matched = message.match(/^\/([a-zA-Z0-9_:-]+)(?:\s+([\s\S]*))?$/);
  if (!matched) return { handled: false };

  const name = matched[1];
  const args = (matched[2] ?? '').trim();

  // 明确不支持的：给提示，绝不发给模型
  const unsupportedReason = UNSUPPORTED.get(name);
  if (unsupportedReason) {
    return {
      handled: true,
      response: success(commandId, 'prompt', {
        disposition: 'handled',
        builtin: text(`/${name}：${unsupportedReason}`),
      }),
    };
  }

  const handler = HANDLERS[name];
  if (!handler) return { handled: false }; // 交给 pi：扩展命令 / 模板 / 技能 / 普通文本

  try {
    const payload = await handler(ctx, args);
    return {
      handled: true,
      response: success(commandId, 'prompt', {
        disposition: 'handled',
        builtin: { name, ...payload },
      }),
    };
  } catch (error) {
    return {
      handled: true,
      response: failure(commandId, 'prompt', `/${name} 执行失败：${error?.message ?? error}`),
    };
  }
}
