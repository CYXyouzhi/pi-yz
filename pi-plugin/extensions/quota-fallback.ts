/**
 * quota-fallback —— 额度兜底插件（pi 扩展）
 *
 * 干什么：
 *   主模型因为「额度 / 计费」原因失败时（opencode-go 的 GoUsageLimitError、
 *   "Monthly usage limit reached"、insufficient_quota、out of budget、quota exceeded 等），
 *   自动切到备用 provider（默认 DeepSeek 官方 deepseek/deepseek-flash），
 *   并在本轮结束时请求一次继续，让 agent 接着把没干完的活干完。
 *   全程不需要人点任何东西 —— 适用于「人已经睡了」的场景。
 *
 * 为什么能这么干（pi 扩展 API）：
 *   - pi.on("message_end")：拿到每条最终消息，能看出 assistant.stopReason === "error" 和 errorMessage；
 *   - pi.setModel(model)：会话内直接换模型，下一条请求就用新模型；
 *   - pi.sendUserMessage(text, { deliverAs: "followUp" })：排一条待发的用户消息。
 *     pi 判断「能不能继续」是 canContinue = contextCanContinue || pendingCustomContext
 *       || (boundary==="turn_end" ? 有排队消息 : 最后一条是 assistant && 有排队消息)，
 *     最后一条恰是那条报错消息（assistant），所以只要排了消息，pi 就会自己再跑一轮。
 *     注意：不能「在 agent_before_settle 边界里切模型 + 返回 continue」，
 *     pi 会报 "requested continuation without runnable model context"（实测过）。
 *
 * 配置：~/.pi/agent/quota-fallback.json（不存在则用代码里的默认值）
 *   {
 *     "enabled": true,
 *     "fallback": { "provider": "deepseek", "model": "deepseek-flash" },
 *     "patterns": ["GoUsageLimitError", "insufficient_quota", "..."],
 *     "maxPerSession": 3
 *   }
 *
 * 安装：文件放到 ~/.pi/agent/extensions/ 下即可（pi 启动自动加载）
 * 试用：pi --extension <此文件路径>
 * 关闭：配置里 "enabled": false，或删掉本文件
 *
 * 命令：
 *   /quota-fallback          看状态（当前模型、备用模型、本会话已切次数、配置来源）
 *   /quota-fallback on|off   本次会话临时开关
 *   /quota-fallback switch   立刻手动切到备用模型（用来验证切换链路）
 */

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

/** 与 pi 内部 NON_RETRYABLE_PROVIDER_LIMIT_ERROR_PATTERN 对齐的默认匹配表 */
const DEFAULT_PATTERNS = [
  "GoUsageLimitError",
  "FreeUsageLimitError",
  "usage limit reached",
  // DeepSeek 官方余额不足的**原文**（实测 402 返回 {"message":"Insufficient Balance"}）。
  // 这条必须单独加：早前表里只有 "available balance"，那是另一家的措辞 ——
  // 真跑起来这家的额度错误根本没被认出来（task-20 合同②用真实报错逐条比出来的）。
  "insufficient balance",
  "available balance",
  "insufficient_quota",
  "out of budget",
  "quota exceeded",
  "billing",
  "subscription_sharing_usage_limit_exceeded",
];

type Config = {
  enabled: boolean;
  fallback: { provider: string; model: string };
  patterns: string[];
  maxPerSession: number;
};

const DEFAULTS: Config = {
  enabled: true,
  fallback: { provider: "deepseek", model: "deepseek-flash" },
  patterns: DEFAULT_PATTERNS,
  maxPerSession: 3,
};

function agentDir(): string {
  return join(homedir(), ".pi", "agent");
}

function loadConfig(): { config: Config; source: string } {
  const file = join(agentDir(), "quota-fallback.json");
  if (!existsSync(file)) return { config: DEFAULTS, source: "内置默认" };
  try {
    const raw = JSON.parse(readFileSync(file, "utf-8")) as Partial<Config>;
    const config: Config = {
      enabled: raw.enabled ?? DEFAULTS.enabled,
      fallback: { ...DEFAULTS.fallback, ...(raw.fallback ?? {}) },
      patterns: raw.patterns?.length ? raw.patterns : DEFAULT_PATTERNS,
      maxPerSession: raw.maxPerSession ?? DEFAULTS.maxPerSession,
    };
    return { config, source: file };
  } catch (error) {
    return { config: DEFAULTS, source: `${file}（解析失败，改用内置默认：${String(error)}）` };
  }
}

function matchesQuota(text: string, patterns: string[]): string | undefined {
  const lower = text.toLowerCase();
  return patterns.find((p) => lower.includes(p.toLowerCase()));
}

function label(model: { provider: string; id: string } | undefined | null): string {
  return model ? `${model.provider}/${model.id}` : "未知模型";
}

export default function quotaFallback(pi: ExtensionAPI) {
  let { config, source } = loadConfig();
  let enabled = config.enabled;
  /** 本会话已切换次数：防止备用模型也失败时来回横跳 */
  let switched = 0;
  let busy = false;

  pi.on("message_end", async (event, ctx: ExtensionContext) => {
    if (!enabled || busy) return;
    const message = event.message as {
      role?: string;
      stopReason?: string;
      errorMessage?: string;
    };
    if (message?.role !== "assistant") return;
    if (message.stopReason !== "error" || !message.errorMessage) return;

    const hit = matchesQuota(message.errorMessage, config.patterns);
    if (!hit) return;

    const reason = message.errorMessage;
    const current = ctx.model as { provider: string; id: string } | undefined;

    if (switched >= config.maxPerSession) {
      ctx.ui.notify(
        `额度兜底：本会话已切换 ${switched} 次（上限 ${config.maxPerSession}），不再自动切换`,
        "error",
      );
      return;
    }
    const target = ctx.modelRegistry.find(config.fallback.provider, config.fallback.model);
    if (!target) {
      ctx.ui.notify(
        `额度兜底：找不到备用模型 ${config.fallback.provider}/${config.fallback.model}，请检查 models.json 或 provider 配置`,
        "error",
      );
      return;
    }
    if (current && current.provider === target.provider && current.id === target.id) {
      ctx.ui.notify(`额度兜底：备用模型 ${label(target)} 也失败了，停止自动切换`, "error");
      return;
    }

    busy = true;
    try {
      // ① 立刻换模型：下一条请求就走备用 provider
      const ok = await pi.setModel(target);
      if (!ok) {
        ctx.ui.notify(
          `额度兜底：切到 ${label(target)} 失败（多半是没配该 provider 的凭据）`,
          "error",
        );
        return;
      }
      switched += 1;

      // ② 留一条审计记录（不进模型上下文，只挂在会话里）
      pi.appendEntry("quota-fallback", {
        at: new Date().toISOString(),
        from: label(current),
        to: label(target),
        reason,
        index: switched,
      });

      // ③ 排一条 followUp：pi 看到有排队消息就会自己再跑一轮，本轮的工作接着干
      pi.sendUserMessage(
        `[额度兜底·自动切换] 上一个 provider（${label(current)}）因为额度/计费原因不可用，` +
          `已自动切换到 ${label(target)}（原因：${hit}）。请从刚才中断的地方继续完成未完成的工作；` +
          `已经做过的事不要重复，如果刚才那一步的结果已经拿到就直接往后走。`,
        { deliverAs: "followUp" },
      );

      ctx.ui.notify(
        `额度兜底：已切到 ${label(target)}，正在继续（第 ${switched} 次）`,
        "info",
      );
    } finally {
      busy = false;
    }
  });

  pi.registerCommand("quota-fallback", {
    description: "额度兜底：查看状态 / on / off / switch 手动切换",
    handler: async (args, ctx) => {
      const arg = (args ?? "").trim().toLowerCase();
      const current = ctx.model as { provider: string; id: string } | undefined;

      if (arg === "reload") {
        ({ config, source } = loadConfig());
        enabled = config.enabled;
        ctx.ui.notify(`额度兜底：配置已重读（${source}）`, "info");
        return;
      }
      if (arg === "on" || arg === "off") {
        enabled = arg === "on";
        ctx.ui.notify(`额度兜底：本次会话已${enabled ? "开启" : "关闭"}`, "info");
        return;
      }
      if (arg === "switch") {
        const target = ctx.modelRegistry.find(config.fallback.provider, config.fallback.model);
        if (!target) {
          ctx.ui.notify(`额度兜底：找不到 ${config.fallback.provider}/${config.fallback.model}`, "error");
          return;
        }
        const ok = await pi.setModel(target);
        ctx.ui.notify(
          ok ? `额度兜底：已手动切到 ${label(target)}` : `额度兜底：切换失败（缺凭据？）`,
          ok ? "info" : "error",
        );
        return;
      }

      ctx.ui.notify(
        [
          `额度兜底：${enabled ? "开启" : "关闭"}（配置：${source}）`,
          `当前模型：${label(current)}`,
          `备用模型：${config.fallback.provider}/${config.fallback.model}`,
          `本会话已切换：${switched} / ${config.maxPerSession}`,
          `匹配关键字：${config.patterns.slice(0, 4).join(" / ")}${config.patterns.length > 4 ? " …" : ""}`,
        ].join("\n"),
        "info",
      );
    },
  });
}
