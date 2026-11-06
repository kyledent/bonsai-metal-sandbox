# Troubleshooting

## A `./bonsai doctor` check fails

The profiles are the most likely cause, particularly on a macOS version they have not met. See what was refused:

```sh
log show --last 5m --style compact --predicate 'sender == "Sandbox"'
```

Then allow the path or service in [`sandbox/server.sb`](../sandbox/server.sb) or [`sandbox/agent.sb`](../sandbox/agent.sb),
as narrowly as you can.

- **"sees Metal without a sandbox" fails:** the problem is the binary, or the Mac, and not the sandbox.
- **Only "sees Metal in the sandbox" fails:** the server's profile is missing something Metal needs.
- **"it can run a program at all" fails:** `sandbox-exec` could not use the profile. Run it by hand to see the error.
- **A refusal check reports "it was allowed":** the sandbox is not doing its job. Do not rely on it until that is fixed.

## The server stops while loading

`./bonsai up` prints the end of the log, and the whole of it is in `.state/server.log`.

- **Out of memory:** lower `BONSAI_CTX`, use `BONSAI_QUANT=PTQ1_0`, or use a smaller [model](models.md).
- **M5 on macOS 26.2 to 26.4:** Prism's workaround is `GGML_METAL_TENSOR_DISABLE=1 ./bonsai restart`. If it persists, also
  set `BONSAI_CTX=16384`.
- **"unknown" quantization type or garbled output:** that is a binary other than the fork. Stock llama.cpp cannot run
  these files.

## Empty or cut-off answers

The model thinks before it answers, and the thinking counts against the output limit. Prism's advice is 16K of output or
more, with a 64K context. Raise `BONSAI_CTX` if you have the memory, or lower the thinking level. See
[the table](pi-integration.md#auto-compaction) for the limits at each context.

## It is slow

- Check for Low Power Mode, which throttles inference hard (System Settings, Battery).
- A long first prompt is read at 125-765 tokens/s on M4 Pro to M5 Max. Thinking at the `high` level can take minutes
  before the answer starts.
- Lower the thinking level with Shift+Tab. `medium` often gets as good an answer when the output limit is moderate.

## The agent cannot do something

- **npm, pip, `git push` or `curl` fail:** the default network reaches only the model. See
  [Agent network](sandbox.md#agent-network).
- **A tool is missing:** the agent's `PATH` has the system's tools, Homebrew and node, but nothing from your home folder,
  such as pyenv or nvm's other versions. Use Homebrew, or install it in the agent's home.
- **Your git identity is missing:** the agent has its own home, so set it there with `./bonsai shell`, then `git config
  --global user.name ...`.
- **Pasting images does not work:** the sandbox blocks the clipboard. Refer to an image file in the workspace instead.

## The wrong model answers

`./bonsai` does not replace a server that is already running. Run `./bonsai status` to see which model it serves, then
`BONSAI_MODEL=9B ./bonsai restart` to switch. Set `BONSAI_MODEL` in `.env` to keep the choice.

## pi shows no Bonsai model

Run `./bonsai status` and `./bonsai detect`. The server has to be ready, and its model id has to contain `bonsai`. A
server on a port outside `BONSAI_PORTS` is not found, and the sandbox will not let the agent reach it.

## Malformed tool calls

Tool calls sometimes come out malformed, or loop. Prism lists it as a known limitation of the model. See
[KNOWN_ISSUES.md](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf/blob/main/KNOWN_ISSUES.md).
