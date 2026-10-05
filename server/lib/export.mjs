// 会话导出：Markdown（给手机看/复制）+ HTML / JSONL（pi 自带的两种落盘格式）。
//
// 为什么要 Markdown 这一路：pi 的 exportToHtml 是把文件写到电脑上，
// 手机上「导出」如果只是得到一个服务端路径，等于没导出。
// Markdown 能直接在 App 里渲染预览、复制、存到手机，才是手机端该有的导出。

import { stripAnsi } from './wire.mjs';
import { dirname, join } from 'node:path';

/** 会话所在目录（导出文件就落在会话旁边，方便在电脑上找） */
function sessionDir(live) {
  const file = live?.session?.sessionFile ?? live?.info?.path ?? null;
  return file ? dirname(file) : null;
}

/** 2026-10-03T05-28-21-102Z（文件名里不能用冒号） */
function stamp() {
  return new Date().toISOString().replace(/[:.]/g, '-');
}

/** 时间戳 → 本地可读时间（导出成人看的文档，用本地时间） */
function fmtTime(ts) {
  if (!ts) return '';
  const d = new Date(ts);
  if (Number.isNaN(d.getTime())) return '';
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ` +
    `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function fmtTokens(n) {
  if (typeof n !== 'number' || n <= 0) return '0';
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(2) + 'M';
  if (n >= 1000) return (n / 1000).toFixed(1) + 'k';
  return String(n);
}

/** 一条消息的文本部分（拼所有 text 块） */
function textOf(message) {
  const content = message?.content;
  if (typeof content === 'string') return stripAnsi(content);
  if (!Array.isArray(content)) return '';
  return content
    .filter((block) => block && block.type === 'text')
    .map((block) => stripAnsi(String(block.text ?? '')))
    .join('\n')
    .trim();
}

function thinkingOf(message) {
  const content = message?.content;
  if (!Array.isArray(content)) return '';
  return content
    .filter((block) => block && block.type === 'thinking')
    .map((block) => stripAnsi(String(block.thinking ?? block.text ?? '')))
    .join('\n')
    .trim();
}

function toolCallsOf(message) {
  const content = message?.content;
  if (!Array.isArray(content)) return [];
  return content.filter((block) => block && block.type === 'toolCall');
}

/** 把一段文本缩进成引用块（用于思考） */
function asQuote(text) {
  return text
    .split('\n')
    .map((line) => (line.trim() ? `> ${line}` : '>'))
    .join('\n');
}

function usageLine(usage) {
  if (!usage) return '';
  const parts = [];
  if (usage.input) parts.push(`输入 ${fmtTokens(usage.input)}`);
  if (usage.output) parts.push(`输出 ${fmtTokens(usage.output)}`);
  if (usage.cacheRead) parts.push(`缓存读 ${fmtTokens(usage.cacheRead)}`);
  if (usage.cacheWrite) parts.push(`缓存写 ${fmtTokens(usage.cacheWrite)}`);
  const cost = usage.cost?.total;
  if (typeof cost === 'number' && cost > 0) parts.push(`$${cost.toFixed(4)}`);
  return parts.join(' · ');
}

/**
 * 生成 Markdown。
 * @param {object} live LiveSession
 * @returns {{markdown: string, filename: string, title: string, stats: object}}
 */
export function sessionToMarkdown(live) {
  const session = live.session;
  const messages = session.messages.filter((m) => m.role !== 'system');
  const firstUser = messages.find((m) => m.role === 'user');
  const title = (session.sessionName || textOf(firstUser) || '(无标题会话)')
    .split('\n')[0]
    .slice(0, 60);
  const stats = typeof session.getSessionStats === 'function' ? session.getSessionStats() : null;
  const times = messages.map((m) => m.timestamp).filter((t) => typeof t === 'number');

  const head = [
    `# ${title}`,
    '',
    `- 会话 ID：\`${session.sessionId ?? live.id}\``,
    `- 工作区：\`${live.cwd}\``,
    `- 模型：${session.model ? `${session.model.name ?? session.model.id} (${session.model.provider})` : '未知'}`,
    `- 思考等级：${session.thinkingLevel ?? '未知'}`,
    ...(times.length ? [`- 时间：${fmtTime(Math.min(...times))} ~ ${fmtTime(Math.max(...times))}`] : []),
    `- 消息：${messages.length} 条${stats ? `（user ${stats.userMessages} · assistant ${stats.assistantMessages} · 工具调用 ${stats.toolCalls}）` : ''}`,
    ...(stats?.tokens ? [`- tokens：合计 ${fmtTokens(stats.tokens.total)}（输入 ${fmtTokens(stats.tokens.input)} · 输出 ${fmtTokens(stats.tokens.output)}）`] : []),
    ...(stats?.cost?.total ? [`- 花费：$${stats.cost.total.toFixed(4)}`] : []),
    '',
    '---',
    '',
  ];

  const body = [];
  for (const message of messages) {
    const role = message.role;
    const time = fmtTime(message.timestamp);

    if (role === 'user') {
      const text = textOf(message);
      const images = Array.isArray(message.content)
        ? message.content.filter((b) => b && (b.type === 'image' || b.type === 'image_url')).length
        : 0;
      body.push(`## 主人${time ? ` · ${time}` : ''}`, '', text || '(空)');
      if (images) body.push('', `_[含 ${images} 张图片]_`);
      body.push('');
      continue;
    }

    if (role === 'assistant') {
      const thinking = thinkingOf(message);
      const text = textOf(message);
      const calls = toolCallsOf(message);
      const usage = usageLine(message.usage);
      body.push(`## pi${time ? ` · ${time}` : ''}${usage ? ` · ${usage}` : ''}`, '');
      if (thinking) body.push('<details><summary>思考</summary>', '', asQuote(thinking), '', '</details>', '');
      if (text) body.push(text, '');
      for (const call of calls) {
        const args = call.arguments ? JSON.stringify(call.arguments) : '';
        body.push(`**工具调用** \`${call.name ?? call.toolName ?? '?'}\``, '', '```json', args.slice(0, 2000), '```', '');
      }
      continue;
    }

    if (role === 'toolResult') {
      const text = textOf(message);
      const name = message.toolName ?? 'tool';
      const mark = message.isError ? '（失败）' : '';
      body.push(`**工具结果** \`${name}\`${mark}`, '', '```', text.slice(0, 4000), '```', '');
      continue;
    }

    if (role === 'branchSummary' || role === 'compactionSummary') {
      const label = role === 'branchSummary' ? '分支摘要' : '上下文压缩摘要';
      body.push(`## ${label}${time ? ` · ${time}` : ''}`, '', textOf(message) || message.summary || '', '');
      continue;
    }

    const text = textOf(message);
    if (text) body.push(`## ${role}${time ? ` · ${time}` : ''}`, '', text, '');
  }

  const markdown = [...head, ...body].join('\n').replace(/\n{4,}/g, '\n\n\n').trim() + '\n';
  const safe = title.replace(/[\\/:*?"<>|]/g, '_').slice(0, 40) || 'session';
  return {
    markdown,
    title,
    filename: `${safe}-${String(session.sessionId ?? live.id).slice(0, 8)}.md`,
    stats,
  };
}

/**
 * 落到服务端磁盘的两种格式（pi 自带实现）。
 * @returns {{html: string|null, jsonl: string|null, errors: string[]}}
 */
export async function exportServerFiles(live) {
  const errors = [];
  let html = null;
  let jsonl = null;
  const dir = sessionDir(live);
  const short = String(live.session?.sessionId ?? live.id).slice(0, 8);
  try {
    // 不给路径的话 HTML 会落在「会话目录」、而 JSONL 会落在进程 cwd（实测），
    // 两个文件分家很难找 —— 统一显式指定到会话目录。
    const target = dir ? join(dir, `pi-session-${stamp()}_${short}.html`) : undefined;
    const result = await live.session.exportToHtml(target);
    html = typeof result === 'string' ? result : (result?.path ?? null);
  } catch (error) {
    errors.push(`HTML 导出失败：${error?.message ?? error}`);
  }
  try {
    const target = dir ? join(dir, `export-${stamp()}_${short}.jsonl`) : undefined;
    jsonl = live.session.exportToJsonl(target);
  } catch (error) {
    errors.push(`JSONL 导出失败：${error?.message ?? error}`);
  }
  return { html, jsonl, errors };
}

/** 读服务端上已经导出的 HTML（供 App/浏览器取内容） */
export async function exportHtmlText(live) {
  const dir = sessionDir(live);
  const short = String(live.session?.sessionId ?? live.id).slice(0, 8);
  const target = dir ? join(dir, `pi-session-${stamp()}_${short}.html`) : undefined;
  const result = await live.session.exportToHtml(target);
  const path = typeof result === 'string' ? result : (result?.path ?? null);
  if (!path) throw new Error('导出失败：没有拿到文件路径');
  const { readFile } = await import('node:fs/promises');
  return { path, html: await readFile(path, 'utf8') };
}
