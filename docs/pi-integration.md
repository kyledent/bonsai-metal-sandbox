# pi integration

Every time pi starts, `bonsai-detect` finds the running Bonsai servers and writes pi's configuration, so there is nothing
to set by hand. **pi's auto-compaction and thinking levels both work with this model**, and the defaults depend on the
size of the context.

All of this applies to pi 0.73.1, the pinned version. pi's files are in the agent's own home, at
`.state/home/.pi/agent/`.

## Model detection

`bonsai-detect` asks each port in `BONSAI_PORTS` for `/health`, `/props` and `/v1/models`. A server counts when its model
id contains `bonsai`, so a second server you started yourself shows up, and another model on the same port does not.

Each one becomes a provider `bonsai-<port>` in `models.json`, with the model id, context and image support that the
server reports:

```json
{
  "providers": {
    "bonsai-8080": {
      "baseUrl": "http://127.0.0.1:8080/v1",
      "api": "openai-completions",
      "apiKey": "none",
      "compat": {
        "supportsDeveloperRole": false,
        "supportsReasoningEffort": false,
        "thinkingFormat": "qwen-chat-template"
      },
      "models": [{
        "id": "bonsai2-27b-pq2-0",
        "name": "bonsai2-27b-pq2-0 (:8080, 65536 ctx)",
        "reasoning": true,
        "input": ["text"],
        "contextWindow": 65536,
        "maxTokens": 16384,
        "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
        "thinkingLevelMap": {"minimal": null, "low": "medium", "medium": "medium", "high": "xhigh", "xhigh": "xhigh"}
      }]
    }
  }
}
```

Providers whose names start with `bonsai` belong to the script, and each run replaces them. Your other providers are
kept. If you start a server while pi is open, run `./bonsai detect` in a second terminal, then open `/model`.

## Thinking levels

Change the level with Shift+Tab, or start with `--thinking <level>`. The default is `high`, set by
`defaultThinkingLevel` in `settings.json`.

| pi level | Effort sent to the model | Thinking budget (tokens) |
|---|---|---|
| `off` | `none` | |
| `minimal` | hidden: the template has nothing below `low` | |
| `low` | `medium` | 2,048 |
| `medium` | `medium` | 4,096 |
| `high` (default) | `xhigh` | 8,192 |
| `xhigh` | `xhigh` | 16,384 |

pi on its own sends only `chat_template_kwargs.enable_thinking`, so all its levels would think alike. The
`bonsai-thinking` extension adds the effort and the budget to each request, as top-level fields, since the server
ignores a budget inside `chat_template_kwargs`. `bonsai-detect` installs it in `extensions/`.

On the 27B, this deliberately differs from the model's own names in two places, both from Prism's
[known issues](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf/blob/main/KNOWN_ISSUES.md): `high` is an HTTP 500,
and `low` thinks about as long as `xhigh`. With thinking off, the extension also applies the model card's sampling for
that mode.

**On the 2B and 9B, the effort column does not apply.** Their chat templates have no reasoning effort, so the extension
sends only the budget, and the levels differ by how long the model may think. `off` sets `enable_thinking` to false. The
extension tells them apart by the model id, which has to contain `27b` for efforts to be sent.

- **To change the table**, set `BONSAI_THINKING_LEVELS`, for example `high=medium:6000`. pi's `thinkingBudgets` setting
  has no effect here.
- **To turn thinking off altogether**, set `BONSAI_THINKING=0`.
- **Time:** at Prism's 18-47 tokens/s on M4 Pro to M5 Max, 8K of thinking takes 3-7 minutes, and it stays in the context
  until compaction.

The output limit caps the budgets: the thinking counts in it, and 4,096 tokens are kept for the answer. See the table
below.

## Auto-compaction

pi summarizes older messages when `context tokens > context window - reserveTokens`. It checks this when an agent run
ends, so one run of tool calls has to fit in the reserve. If a run does overflow, pi recognizes llama.cpp's "exceeds the
available context size" error, compacts, and retries once. `/compact` does it by hand.

`bonsai-detect` writes these values, sized from the smallest context found, but only where you have not set a value:

| Context (by RAM) | Max output | Budget cap per level | `reserveTokens` | `keepRecentTokens` | Summary max output | Server budget |
|---|---|---|---|---|---|---|
| 8K (up to 11 GB) | 2,048 | 512 | 2,048 | 1,638 | 1,638 | 512 |
| 16K (up to 23 GB) | 4,096 | 512 | 4,096 | 3,276 | 3,276 | 1,024 |
| 32K (up to 35 GB) | 8,192 | 4,096 | 8,192 | 6,553 | 6,553 | 2,048 |
| 64K (up to 71 GB) | 16,384 | 12,288 | 16,384 | 13,107 | 13,107 | 4,096 |
| 128K (more, 27B only) | 24,576 | 20,480 | 24,576 | 20,000 | 19,660 | 8,192 |

Below 64K the levels start to merge, and on 16K or less they are all the same. If you can spare the memory, use a larger
`BONSAI_CTX`.

Summary requests come from pi directly and skip the extension, so they use the server's `--reasoning-budget` and, on the
27B, the default effort, which is `xhigh`. That is why the server's budget is only a sixteenth of the context: a larger one could
use up a summary's whole output on thinking. Set it with `BONSAI_REASONING_BUDGET`.

To change compaction, edit `settings.json`. The values are written once, so after a big change to the context, edit or
delete them and run `./bonsai detect`:

```json
{
  "compaction": {"enabled": true, "reserveTokens": 16384, "keepRecentTokens": 13107}
}
```

Each compaction has a cost: the server reads the summarized conversation again as a new prompt, at 125-765 tokens/s on M4
Pro to M5 Max.

## Other defaults

`bonsai-detect` also sets these, again only where you have not set a value:

- `retry.provider.timeoutMs`: 1 hour, as a long prompt read takes minutes.
- `retry.provider.maxRetries`: 0, and `retry.maxRetries`: 1. The server has one slot, so a retry would wait behind the
  request it is still reading.
- `defaultProvider` and `defaultModel`: the first server found, if none is set, the default server is gone, or it now
  serves another model, as it does after you switch presets.

The extension also applies Prism's workarounds for agent loops: empty tool arguments become `{}`, which otherwise cause an
HTTP 500, and earlier reasoning is not sent back, which otherwise defeats the prompt cache.

## What has been tested

`tests/run.sh` runs the real pi 0.73.1 against a mock server, and checks the requests it sends:

- `off`, `low`, `medium`, `high` and `xhigh`: the effort and the budget in each request to the 27B.
- `off` and the default level on the 9B: a budget and no effort, and `enable_thinking` set to false when off.
- Auto-compaction: a summary request follows when the server reports a full context, with the expected output limit.

The real model has not been part of these tests, so the mock cannot show how well it thinks or summarizes. The retry after
an overflow comes from reading pi's source, and has not been run against the fork's error message.
