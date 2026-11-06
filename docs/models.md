# Models

Three presets serve the sizes of Ternary Bonsai 2. Each pins a Hugging Face commit and the checksums of its files.

| | `2B` | `9B` | `27B` (default) |
|---|---|---|---|
| **Repository** | [2B GGUF](https://huggingface.co/prism-ml/Ternary-Bonsai-2-2B-gguf) | [9B GGUF](https://huggingface.co/prism-ml/Ternary-Bonsai-2-9B-gguf) | [27B GGUF](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf) |
| **`PQ2_0` weights** (default) | 0.52 GB | 2.42 GB | 7.21 GB |
| **`PTQ1_0` weights** | 0.43 GB | 2.00 GB | 5.95 GB |
| **Vision file** (`BONSAI_VISION=1`) | 0.36 GB | 0.62 GB | 0.63 GB |
| **Model id in pi** | `bonsai2-2b-pq2-0` | `bonsai2-9b-pq2-0` | `bonsai2-27b-pq2-0` |
| **Reasoning efforts** | No | No | `xhigh`, `medium` |
| **Largest default context** | 64K | 64K | 128K |

All three have a limit of 262,144 tokens of context, tool calling in their chat templates, and an Apache 2.0 license.

## Switching

```sh
./bonsai models                   # list them
BONSAI_MODEL=9B ./bonsai setup    # download one
BONSAI_MODEL=9B ./bonsai restart  # serve it
```

Or set `BONSAI_MODEL` in `.env`, then run `./bonsai restart`. One server runs at a time, and files you have downloaded stay
in `models/`. `./bonsai` will not replace a server that is already running: if you ask for another model on the command
line, it stops and tells you how to switch, and if only `.env` differs, it uses the running server and says so.

The next time pi starts, detection finds the new model and makes it the default.

## How they differ

Each preset applies the settings in its model card.

**Sampling with thinking on.** The server starts with these. With thinking off, the extension sends the same values on
every size: temperature 0.7, top-p 0.8, top-k 20, min-p 0 and presence penalty 1.5.

| | Temperature | Top-p | Top-k | Min-p | Presence penalty | Penalty window |
|---|---|---|---|---|---|---|
| `2B`, `9B` | 1.0 | 0.95 | 20 | 0 | 1.0 | 64 |
| `27B` | 1.0 | 0.95 | 20 | 0.05 | off | |

**Thinking.** The chat templates of the 2B and 9B have no reasoning effort, so pi's levels differ by thinking budget alone.
See [Thinking levels](pi-integration.md#thinking-levels).

**Output.** Prism's 2B and 9B cards say that even simple prompts can use 3,000 or more thinking tokens, and to allow at
least 8,192 output tokens with thinking on, which here takes a context of 32K or more.

## Memory

The default context comes from your Mac's RAM, not the model, as in Bonsai-demo: 8K up to 11 GB, 16K up to 23 GB, 32K up to
35 GB, and 64K above that (128K above 71 GB on the 27B).

So a smaller model on the same Mac gets the same context, and leaves more memory free. A 2B or 9B on 16 GB has room for more
than the 16K default, and 16K is below the output room Prism advises, so try:

```sh
BONSAI_MODEL=9B BONSAI_CTX=32768 ./bonsai restart
```

Prism publishes the context's cost for the 27B, about 64 KiB per token. It does not publish one for the 2B or 9B.

### Estimated memory by context

In GB, with the default `PQ2_0` weights, and with the vision file where it says so. Only the 27B's figures use a published
cost. **The 2B and 9B figures assume the same 64 KiB per token**, and have not been measured. They have fewer layers, so
their real cost is probably lower.

| Context | Default on | 2B | 2B + vision | 9B | 9B + vision | 27B | 27B + vision |
|---|---|---:|---:|---:|---:|---:|---:|
| 8K | up to 11 GB | 1.1 | 1.4 | 3.0 | 3.6 | 7.7 | 8.4 |
| 16K | up to 23 GB | 1.6 | 2.0 | 3.5 | 4.1 | 8.3 | 8.9 |
| 32K | up to 35 GB | 2.7 | 3.0 | 4.6 | 5.2 | 9.4 | 10.0 |
| 64K | up to 71 GB, or more on the 2B and 9B | 4.8 | 5.2 | 6.7 | 7.3 | 11.5 | 12.1 |
| 128K | more than 71 GB, 27B only | 9.1 | 9.5 | 11.0 | 11.6 | 15.8 | 16.4 |
| 262K | never (the limit) | 17.7 | 18.1 | 19.6 | 20.2 | 24.4 | 25.0 |

These cover the weights, the context's cache and the vision file. They leave out:

- the prompt cache, which can grow to `BONSAI_CACHE_RAM`: by default a quarter of the RAM, at most 24 GiB;
- working memory while reading an image;
- macOS, your other apps, and pi.

macOS also limits how much memory the GPU may use, to less than the whole of the RAM, so leave a good margin.

## What is not known yet

- **Speed on a Mac.** Prism publishes Apple Silicon figures for the 27B only: 18 tokens/s on an M4 Pro to 47 on an M5 Max.
  The smaller models should be faster, but there are no published numbers. `./bonsai bench` measures your Mac: see
  [Checks and benchmarks](checks.md).
- **How they do as coding agents.** Their templates support tool calls, and the agent has been tested with a mock server
  only. Prism's agent demo uses the 27B. Expect less from a smaller model on larger tasks.

## Not included

- **Speculative decoding:** the 9B ships optional drafters, but Bonsai-demo's guidance advises against speculation on Macs.
  The 2B has none.
- **Bonsai 2 4B:** Prism publishes one, but it has no preset here.
- **MLX builds:** these need their own server, so this repository does not use them.
