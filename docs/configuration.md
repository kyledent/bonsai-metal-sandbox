# Configuration

Settings live in `.env`, which `./bonsai` creates from [`.env.example`](../.env.example) on first run. `.env` is
git-ignored. Values are literal, with no quotes or `$VARS`, and a variable already set in your shell wins, so this works
for one run:

```sh
BONSAI_CTX=65536 ./bonsai restart
```

After changing a server setting, run `./bonsai restart`.

## Model and server

| Setting | Default | Meaning |
|---|---|---|
| `BONSAI_MODEL` | `27B` | `2B`, `9B` or `27B`. See [Models](models.md) |
| `BONSAI_QUANT` | `PQ2_0` | `PQ2_0` (the pack Prism measures on Apple Silicon), or `PTQ1_0` (about 17% smaller; where memory is tightest) |
| `BONSAI_MODEL_DIR` | `./models` | Where the GGUF files go |
| `BONSAI_VISION` | `0` | `1` also downloads the vision file (0.4-0.6 GB), and accepts images |
| `BONSAI_CTX` | by RAM | Context in tokens, up to 262144. On the 27B, about 64 KiB of memory per token, on top of the weights |
| `BONSAI_PORTS` | `8080-8083` | Ports that detection tries and the agent may reach. The server listens on the first, on loopback only |
| `BONSAI_REASONING_BUDGET` | a sixteenth of the context | Thinking budget of requests that set none, such as compaction summaries |
| `BONSAI_CACHE_RAM` | a quarter of the RAM, at most 24576 | Prompt cache cap in MiB |
| `BONSAI_API_KEY` | generated | Key for the server's API. If empty, one is generated on first run and kept in `.state/api-key`. The agent can read it. Other programs need it too: `curl -H "Authorization: Bearer $(cat .state/api-key)" ...` |
| `BONSAI_SERVER_ARGS` | none | More `llama-server` arguments, split on spaces |
| `BONSAI_START_TIMEOUT` | `300` | Seconds to wait for the server to load |
| `BONSAI_CHECK_TIMEOUT` | `900` | Seconds to wait for each request of `./bonsai check` and `bench` |

The context by RAM follows Bonsai-demo: 8K up to 11 GB, 16K up to 23 GB, 32K up to 35 GB, 64K up to 71 GB, and above that
128K on the 27B and 64K on the others.

## Agent

| Setting | Default | Meaning |
|---|---|---|
| `WORKSPACE_DIR` | `./workspace` | The folder that the agent works on |
| `BONSAI_AGENT_NETWORK` | `server` | `server`, `loopback` or `open`. See [Sandbox](sandbox.md#agent-network) |
| `BONSAI_THINKING` | `1` | `0` turns thinking off |
| `BONSAI_THINKING_LEVELS` | see [pi integration](pi-integration.md#thinking-levels) | Each level's effort and budget, as `level=effort:budget`. List only the ones you change. Efforts apply to the 27B only |
| `BONSAI_MAX_OUTPUT` | 24576 with thinking, 8192 without | Largest max output for pi. Also capped at a quarter of the context |
| `GH_TOKEN` | none | Token for `gh` and git in the sandbox. The agent can read it, so use a narrow fine-grained token. Only useful with `BONSAI_AGENT_NETWORK=open` |
| `PI_VERSION` | `0.73.1` | The pi release. Change it and run `./bonsai setup` to upgrade |

## Files

Nothing below is committed. All of it is listed in `.gitignore`.

| Path | Contents |
|---|---|
| `.env` | Your settings, which may include tokens |
| `models/` | The GGUF files |
| `.runtime/` | The llama.cpp fork and pi |
| `.state/api-key` | The server's generated API key |
| `.state/home/` | The agent's home: pi's settings, sessions and whatever it installs |
| `.state/server.log` | The server's log |
| `.state/bench.jsonl` | Results of `./bonsai bench` |
| `workspace/` | Your projects |

To start again, stop the server and delete `.state`. To upgrade the runtime, change the pinned release and its checksum
at the top of `bonsai`.
