// pi requests for Ternary Bonsai 2 27B. bonsai-detect installs this file as ~/.pi/agent/extensions/bonsai-thinking.ts.
//
// pi's qwen-chat-template format sends only chat_template_kwargs.enable_thinking, so every level would think the same
// way. This adds, as top-level fields (a budget inside chat_template_kwargs is ignored), the template's
// reasoning_effort and the fork's thinking_budget_tokens for the level in use, to each request to a bonsai* provider.
// The thinking counts in max_tokens, so the budget is cut to leave room for the answer.
//
// Only the 27B's template has efforts and preserve_thinking. On the 2B and 9B, the levels differ by budget alone, and
// thinking off is chat_template_kwargs.enable_thinking=false, which this also sets on the 27B.
//
// It also applies the workarounds in the model's KNOWN_ISSUES.md for agent loops: thinking off is reasoning_effort
// "none" (a budget of 0 does not turn it off), and with it off the model card's instruct sampling; empty tool
// arguments become "{}" (HTTP 500 otherwise); earlier reasoning is not sent back or rendered, for which pi's
// preserve_thinking is turned off (it defeats the prompt cache).
//
// BONSAI_THINKING_LEVELS overrides the table: "low=medium:2048,medium=medium:4096,high=xhigh:8192,xhigh=xhigh:16384"
// (pi level = effort:budget; a budget of 0 means all of max_tokens but the room for the answer).
// Compaction summaries do not pass through this hook; they get the server's --reasoning-budget and default effort, and
// their empty tool arguments and reasoning are not an issue, as pi sends them the conversation as text.
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

type Level = { effort: string; budget: number };

const DEFAULTS: Record<string, Level> = {
	low: { effort: "medium", budget: 2048 },
	medium: { effort: "medium", budget: 4096 },
	high: { effort: "xhigh", budget: 8192 },
	xhigh: { effort: "xhigh", budget: 16384 },
};
const ANSWER_ROOM = 4096; // tokens kept for the answer after the thinking

function levels(): Record<string, Level> {
	const out = { ...DEFAULTS };
	for (const item of (process.env.BONSAI_THINKING_LEVELS ?? "").split(",")) {
		const m = item.trim().match(/^(\w+)=(xhigh|medium|low):(\d+)$/);
		if (m) out[m[1]] = { effort: m[2], budget: Number(m[3]) };
	}
	return out;
}

function cleanMessage(message: Record<string, any>): Record<string, any> {
	if (message.role !== "assistant") return message;
	const { reasoning_content, reasoning, ...rest } = message;
	if (rest.tool_calls) {
		rest.tool_calls = rest.tool_calls.map((call: Record<string, any>) =>
			call.function && !String(call.function.arguments ?? "").trim()
				? { ...call, function: { ...call.function, arguments: "{}" } }
				: call,
		);
	}
	return rest;
}

export default function (pi: ExtensionAPI) {
	const table = levels();
	pi.on("before_provider_request", (event, ctx) => {
		const p = event.payload as Record<string, any> | undefined;
		if (!p || !ctx.model?.provider.startsWith("bonsai")) return;
		const hasEfforts = /27b/i.test(ctx.model.id);
		const kwargs = { ...p.chat_template_kwargs, ...(hasEfforts ? { preserve_thinking: false } : {}) };
		const out = { ...p, messages: (p.messages ?? []).map(cleanMessage), chat_template_kwargs: kwargs };
		if (p.chat_template_kwargs?.enable_thinking !== true) {
			return {
				...out,
				chat_template_kwargs: { ...kwargs, enable_thinking: false },
				...(hasEfforts ? { reasoning_effort: "none" } : {}),
				temperature: p.temperature ?? 0.7,
				top_p: p.top_p ?? 0.8,
				top_k: p.top_k ?? 20,
				min_p: p.min_p ?? 0,
				presence_penalty: p.presence_penalty ?? 1.5,
			};
		}
		const level = table[pi.getThinkingLevel()];
		if (!level) return out;
		const maxNew = Number(p.max_completion_tokens ?? p.max_tokens ?? 0);
		let budget = level.budget;
		if (maxNew > 0) budget = budget > 0 ? Math.min(budget, maxNew - ANSWER_ROOM) : maxNew - ANSWER_ROOM;
		return {
			...out,
			...(hasEfforts ? { reasoning_effort: level.effort } : {}),
			thinking_budget_tokens: Math.max(512, budget),
		};
	});
}
