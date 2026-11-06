// bonsai-thinking.ts on payloads that a one-prompt pi run does not produce: replayed tool calls and reasoning.
import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

const { default: extension } = await import(pathToFileURL(process.argv[2]).href);

let hook;
let level = "high";
extension({ on: (_, fn) => (hook = fn), getThinkingLevel: () => level });
const bonsai = { model: { provider: "bonsai-8080", id: "bonsai2-27b-pq2-0" } };
const small = { model: { provider: "bonsai-8080", id: "bonsai2-9b-pq2-0" } };

const messages = [
	{ role: "system", content: "s" },
	{
		role: "assistant",
		content: "",
		reasoning_content: "long thought",
		tool_calls: [
			{ id: "1", function: { name: "a", arguments: "" } },
			{ id: "2", function: { name: "b", arguments: '{"x":1}' } },
		],
	},
	{ role: "tool", tool_call_id: "1", content: "r" },
];
const on = { messages, max_tokens: 24576, chat_template_kwargs: { enable_thinking: true } };

const out = hook({ payload: on }, bonsai);
assert.equal(out.messages[1].reasoning_content, undefined, "reasoning is not sent back");
assert.equal(out.messages[1].tool_calls[0].function.arguments, "{}", "empty arguments become {}");
assert.equal(out.messages[1].tool_calls[1].function.arguments, '{"x":1}', "other arguments are kept");
assert.deepEqual(out.messages[2], messages[2], "other messages are kept");
assert.deepEqual(out.chat_template_kwargs, { enable_thinking: true, preserve_thinking: false });
assert.equal(out.reasoning_effort, "xhigh");
assert.equal(out.thinking_budget_tokens, 8192);

level = "xhigh";
assert.equal(hook({ payload: on }, bonsai).thinking_budget_tokens, 16384);

// The client's own sampling wins when thinking is off
const off = hook({ payload: { messages, temperature: 0.2, chat_template_kwargs: { enable_thinking: false } } }, bonsai);
assert.equal(off.reasoning_effort, "none");
assert.equal(off.temperature, 0.2);
assert.equal(off.presence_penalty, 1.5);

assert.equal(hook({ payload: on }, { model: { provider: "openai", id: "x" } }), undefined, "other providers are left alone");

// The 2B and 9B templates have no efforts and no preserve_thinking
level = "high";
const smallOn = hook({ payload: on }, small);
assert.equal(smallOn.reasoning_effort, undefined);
assert.equal(smallOn.thinking_budget_tokens, 8192);
assert.deepEqual(smallOn.chat_template_kwargs, { enable_thinking: true });
assert.equal(smallOn.messages[1].tool_calls[0].function.arguments, "{}");
const smallOff = hook({ payload: { messages } }, small);
assert.equal(smallOff.reasoning_effort, undefined);
assert.deepEqual(smallOff.chat_template_kwargs, { enable_thinking: false });
assert.equal(smallOff.presence_penalty, 1.5);
