# Bonsai on Apple Silicon, sandboxed

Run Prism ML's Ternary Bonsai 2 models locally on a Mac's GPU, and use them from the [pi](https://pi.dev) coding agent,
with the model server and the agent each confined by a macOS sandbox.

One command downloads everything, starts the server, and opens pi with the model already configured:

```sh
./bonsai                   # the 27B
BONSAI_MODEL=9B ./bonsai   # or a smaller model
```

## Models

| Preset | Model | Weights | Fits |
|---|---|---|---|
| `27B` (default) | [Ternary Bonsai 2 27B](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf) | 7.2 GB | The full model, with reasoning efforts. 16 GB of memory at least, and 36 GB or more for a 64K context |
| `9B` | [Ternary Bonsai 2 9B](https://huggingface.co/prism-ml/Ternary-Bonsai-2-9B-gguf) | 2.4 GB | A lighter setup, for Macs with less memory |
| `2B` | [Ternary Bonsai 2 2B](https://huggingface.co/prism-ml/Ternary-Bonsai-2-2B-gguf) | 0.5 GB | The lightest setup, for small tasks |

To keep a preset, set `BONSAI_MODEL` in `.env`. To switch a running server, use `BONSAI_MODEL=9B ./bonsai restart`.
`./bonsai models` lists them. See [Models](docs/models.md) for how they differ.

This is an independent project, not affiliated with or endorsed by Prism ML or the authors of pi. It downloads the
model and the runtime from their publishers, and does not redistribute them.

## Why

- **The model needs a special runtime.** Bonsai uses ternary weight formats that stock llama.cpp, Ollama and LM Studio
  cannot run. This uses [PrismML's llama.cpp fork](https://github.com/PrismML-Eng/llama.cpp) at a pinned release.
- **Docker on a Mac cannot reach the GPU.** So the usual way to contain a coding agent would mean giving up Metal. Here,
  everything runs natively under `sandbox-exec` instead.
- **A coding agent runs the commands a model writes.** In its sandbox, the agent can work on one folder, but it cannot
  read your home folder, your keychain or your shell's secrets, and by default it can connect only to the model.

## Status

> [!WARNING]
> The sandbox profiles have not been run on a Mac yet. The scripts and the pi integration pass their tests with a mock
> server, but those tests cannot exercise Seatbelt rules. **Run `./bonsai doctor` before you rely on the sandbox**, and
> expect that some rules may need adjusting. Reports from real machines are very welcome.

## Requirements

- A Mac with Apple Silicon, with disk and memory for the model you pick, as above.
- Node 20.6 or newer, and jq: `brew install node jq`

## Quick start

```sh
git clone <this repository>
cd <this repository>
./bonsai setup     # download the runtime, the model and pi, and verify their checksums
./bonsai up        # start the server
./bonsai doctor    # check that the sandboxes allow and refuse what they should
./bonsai           # open pi
```

Put your projects in `./workspace`, or set `WORKSPACE_DIR` in `.env`. The agent can only work there.

## Commands

| Command | What it does |
|---|---|
| `./bonsai` | Set up if needed, start the server, open pi. Arguments go to pi. |
| `./bonsai setup` | Check the tools, and download the runtime, the selected model and pi |
| `./bonsai models` | List the presets, and which are downloaded |
| `./bonsai up` / `down` / `restart` | Start or stop the server |
| `./bonsai status` / `logs` | See what is running, and follow the server's log |
| `./bonsai detect` | List the Bonsai servers that the agent can see |
| `./bonsai shell` | Open a shell in the agent's sandbox |
| `./bonsai doctor` | Test the sandboxes |

## Documentation

- [Models](docs/models.md): the presets, and how they differ
- [Configuration](docs/configuration.md): every setting in `.env`
- [pi integration](docs/pi-integration.md): model detection, thinking levels and auto-compaction
- [Sandbox](docs/sandbox.md): what each sandbox allows, and its limits
- [Hardening](docs/hardening.md): known gaps, and how to tighten the setup further
- [Troubleshooting](docs/troubleshooting.md): failed checks, memory and empty answers

## Tests

`tests/run.sh` runs `./bonsai`, detection and the pi extension with a mock server and the real pi, on any machine with
bash, curl, jq, node and python. It stubs macOS's tools, so only `./bonsai doctor` tests the sandboxes.

```sh
npm install --prefix /tmp/pi @mariozechner/pi-coding-agent@0.73.1
tests/run.sh /tmp/pi/node_modules/@mariozechner/pi-coding-agent/dist/cli.js
```

## Acknowledgements

Ternary Bonsai 2 and the llama.cpp fork are by [Prism ML](https://prismml.com), and the server settings here follow their
[Bonsai-demo](https://github.com/PrismML-Eng/Bonsai-demo). The models are released under Apache 2.0.

## License

[Apache License 2.0](LICENSE). This covers the code in this repository. The model, the runtime and pi are downloaded from
their publishers, under their own licenses.
