#!/bin/bash
# Tests of everything but the Seatbelt rules themselves, on any machine with bash, curl, jq, node and python:
# ./bonsai, bonsai-detect and the extension, with a mock llama-server and the real pi. sandbox-exec and the other
# macOS tools are stubs here, so the sandboxes are checked only by ./bonsai doctor on a Mac.
#
#   tests/run.sh PI_CLI     PI_CLI: dist/cli.js of an installed @mariozechner/pi-coding-agent
set -uo pipefail

PI_CLI=$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
PYTHON=$(command -v python3 2>/dev/null) && "$PYTHON" -c '' 2>/dev/null || PYTHON=$(command -v python)
PORT=18080
OTHER_PORT=18081
WORK=$(mktemp -d)
FAILS=0
OTHER_PID=

cleanup() {
    (cd "$WORK/repo" 2>/dev/null && ./bonsai down >/dev/null 2>&1)
    [ -z "$OTHER_PID" ] || kill "$OTHER_PID" 2>/dev/null
    rm -rf "$WORK"
}
trap cleanup EXIT

check() { # label, then a command that must succeed
    local label=$1; shift
    if "$@"; then echo "ok    $label"; else echo "FAIL  $label"; FAILS=$((FAILS + 1)); fi
}

# --- Static checks
for f in bonsai agent/bin/bonsai-detect agent/bin/pi tests/run.sh; do
    check "bash -n $f" bash -n "$SRC/$f"
done
balanced() { "$PYTHON" -I -c '
import re, sys
text = re.sub(r"#\"[^\"]*\"|\"[^\"]*\"|;.*", "", open(sys.argv[1]).read())
depth = 0
for c in text:
    depth += (c == "(") - (c == ")")
    if depth < 0: sys.exit(1)
sys.exit(depth != 0)' "$1"; }
for f in sandbox/server.sb sandbox/agent.sb; do check "balanced parens $f" balanced "$SRC/$f"; done

# --- A copy of the repo, with stubs for what only a Mac has, and for what setup would download
mkdir -p "$WORK/stubs" "$WORK/repo"
cp -R "$SRC/bonsai" "$SRC/agent" "$SRC/sandbox" "$SRC/.env.example" "$WORK/repo/"
cd "$WORK/repo" || exit 1
stub() { printf '#!/bin/bash\n%s\n' "$2" > "$WORK/stubs/$1"; chmod +x "$WORK/stubs/$1"; }
stub uname 'case "$1" in -s) echo Darwin ;; -m) echo arm64 ;; esac'
echo 34359738368 > "$WORK/memsize"
stub sysctl "cat '$WORK/memsize'"
stub getconf "echo '$WORK'"
# Record the profile and its parameters, then run the program
stub sandbox-exec "
log='$WORK/sandbox.log'
while [ \$# -gt 0 ]; do
    case \"\$1\" in
        -f) echo \"profile \$2\" >> \"\$log\"; shift 2 ;;
        -D) echo \"param \$2\" >> \"\$log\"; shift 2 ;;
        *) break ;;
    esac
done
echo \"exec \$*\" >> \"\$log\"
exec \"\$@\""
stub ps "tr '\\0' ' ' < /proc/\$2/cmdline 2>/dev/null; echo llama-server"
# The agent's PATH holds jq's folder, so these two reach it wherever this machine keeps them (jq.exe: without its CRs)
stub curl "exec '$(command -v curl)' \"\$@\""
stub jq "set -o pipefail; '$(command -v jq)' \"\$@\" | tr -d '\\r'"
export PATH="$WORK/stubs:$PATH"

LLAMA_DIR=.runtime/llama/prism-b10828-a153697
mkdir -p "$LLAMA_DIR" models .runtime/pi/bin
printf '#!/bin/bash\nexec "%s" -I "%s" --record "%s" --usage-file "%s" "$@"\n' "$PYTHON" "$SRC/tests/mock_llama.py" "$WORK/requests.jsonl" "$WORK/usage" > "$LLAMA_DIR/llama-server"
# Node on Windows ignores HOME; on macOS pi finds this folder by itself
printf '#!/bin/bash\nexport PI_CODING_AGENT_DIR="$HOME/.pi/agent"\nexec node "%s" "$@"\n' "$PI_CLI" > .runtime/pi/bin/pi
chmod +x "$LLAMA_DIR/llama-server" .runtime/pi/bin/pi
: > models/Ternary-Bonsai-2-27B-PQ2_0.gguf

export BONSAI_PORTS="$PORT-$OTHER_PORT"
WORKSPACE_FILE=workspace/big.txt
mkdir -p workspace

# --- Server start and flags
check "./bonsai up starts the server" ./bonsai up
contains() { grep -q -- "$2" "$1"; }
check "server runs under its profile" contains "$WORK/sandbox.log" 'profile .*sandbox/server.sb'
check "server gets its port as a parameter" contains "$WORK/sandbox.log" "param PORT=$PORT"
# 32 GB: the 32K tier, a 2K budget for requests without one, and an 8 GiB prompt cache
check "server command has the Prism flags" contains "$WORK/sandbox.log" \
    "exec .*llama-server -m .*PQ2_0.gguf --host 127.0.0.1 --port $PORT --alias bonsai2-27b-pq2-0 -ngl 99 -fa on -c 32768 --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.05 --jinja --reasoning-format deepseek --reasoning-budget 2048 --parallel 1 --cache-ram 8192"
check "./bonsai status reports it" sh -c './bonsai status | grep -q "ready: bonsai2-27b-pq2-0"'

# --- Detection, in the agent's sandbox wrapper
"$PYTHON" -I "$SRC/tests/mock_llama.py" --port "$OTHER_PORT" --alias qwen-other &
OTHER_PID=$!
sleep 1
AH=.state/home/.pi/agent
mkdir -p "$AH"
echo '{"providers": {"mine": {"baseUrl": "http://x"}, "bonsai-9": {"baseUrl": "http://stale"}}}' > "$AH/models.json"
check "./bonsai detect runs" ./bonsai detect
query() { jq -e "$2" "$AH/$1" >/dev/null; }
check "provider written with the server's id and ctx" query models.json \
    ".providers[\"bonsai-$PORT\"].models[0] | .id == \"bonsai2-27b-pq2-0\" and .contextWindow == 32768 and .maxTokens == 8192"
check "other llama-server is left out" query models.json ".providers | has(\"bonsai-$OTHER_PORT\") | not"
check "stale bonsai provider is replaced" query models.json '.providers | has("bonsai-9") | not'
check "other provider is kept" query models.json '.providers | has("mine")'
check "text only without an mmproj" query models.json ".providers[\"bonsai-$PORT\"].models[0].input == [\"text\"]"
check "default model set" query settings.json ".defaultProvider == \"bonsai-$PORT\" and .defaultModel == \"bonsai2-27b-pq2-0\""
check "compaction sized from the context" query settings.json '.compaction.reserveTokens == 8192 and .compaction.keepRecentTokens == 6553'
check "extension installed" test -f "$AH/extensions/bonsai-thinking.ts"
check "agent runs under its profile" contains "$WORK/sandbox.log" 'profile .*\.state/agent.sb'
check "agent's generated profile allows the server ports only" sh -c \
    "grep -q 'remote ip \"localhost:$PORT\"' .state/agent.sb && ! grep -q 'localhost:\*' .state/agent.sb"

# The calling shell's secrets stay out of the sandbox, and BONSAI_ settings go in
printf '#!/bin/bash\nenv > "%s"\n' "$WORK/agent.env" > agent/bin/bonsai-detect.real
mv agent/bin/bonsai-detect agent/bin/bonsai-detect.saved
mv agent/bin/bonsai-detect.real agent/bin/bonsai-detect
SECRET_TOKEN=x BONSAI_THINKING_LEVELS=low=medium:1 ./bonsai detect
mv agent/bin/bonsai-detect.saved agent/bin/bonsai-detect
check "a secret of the calling shell stays out" sh -c "! grep -q SECRET_TOKEN '$WORK/agent.env'"
check "BONSAI_ settings go in" contains "$WORK/agent.env" BONSAI_THINKING_LEVELS=low=medium:1
check "HOME is the agent's own" contains "$WORK/agent.env" 'HOME=.*\.state/home'

# --- The real pi with the extension: what does a request look like?
last_request() { tail -n 1 "$WORK/requests.jsonl"; }
ask() {
    rm -f "$WORK/requests.jsonl"
    ./bonsai pi --no-session -p "ping" "$@" > "$WORK/pi.out" 2>&1 && return 0
    sed "s/^/      pi: /" "$WORK/pi.out"; return 1
}

check "pi answers through the mock server" ask
check "pi printed the answer" contains "$WORK/pi.out" pong
req() { last_request | jq -e "$1" >/dev/null; }
# 32K context: max output 8K (a quarter), so the 8K budget is cut to leave 4K for the answer
check "default level: xhigh, budget cut to fit" req '.reasoning_effort == "xhigh" and .thinking_budget_tokens == 4096 and .max_tokens // .max_completion_tokens == 8192 and .chat_template_kwargs.enable_thinking == true'
check "one leading system message" req '[.messages[] | select(.role == "system" or .role == "developer")] | length == 1 and .[0].role == "system"'
check "system message comes first" req '.messages[0].role == "system"'

check "pi --thinking medium" ask --thinking medium
check "medium: medium with a 4K budget" req '.reasoning_effort == "medium" and .thinking_budget_tokens == 4096'
check "pi --thinking low" ask --thinking low
check "low: never the template's low" req '.reasoning_effort == "medium" and .thinking_budget_tokens == 2048'
check "pi --thinking off" ask --thinking off
check "off: effort none and instruct sampling" req '.reasoning_effort == "none" and .temperature == 0.7 and .top_p == 0.8 and .presence_penalty == 1.5 and .min_p == 0'

check "extension workarounds" node --experimental-strip-types --no-warnings "$SRC/tests/extension.mjs" "$SRC/agent/share/bonsai-thinking.ts"

check "pi --thinking xhigh" ask --thinking xhigh
check "xhigh: xhigh, budget cut to fit" req '.reasoning_effort == "xhigh" and .thinking_budget_tokens == 4096'

# --- Auto-compaction: pi, with the settings from detection, summarizes once the server reports a full context
"$PYTHON" -I -c 'print("filler text " * 4000)' > "$WORKSPACE_FILE"
echo 30000 > "$WORK/usage"
rm -f "$WORK/requests.jsonl"
compact_run() {
    ./bonsai pi --no-session -p @big.txt first second third > "$WORK/pi.out" 2>&1 && return 0
    sed "s/^/      pi: /" "$WORK/pi.out"; return 1
}
check "pi runs with a full context" compact_run
rm -f "$WORK/usage"
summary() { jq -e 'select(.messages[0].content | tostring | test("summar"; "i"))' "$WORK/requests.jsonl" > "$WORK/summary.json"; }
check "auto-compaction sent a summary request" summary
check "summary: 80% of the reserve as max output" jq -es '.[0] | (.max_tokens // .max_completion_tokens) == 6553' "$WORK/summary.json"
check "summary: uses the server's budget, not the extension's" jq -es 'length > 0 and (.[0] | has("thinking_budget_tokens") | not)' "$WORK/summary.json"

# --- Presets
: > models/Ternary-Bonsai-2-9B-PQ2_0.gguf
: > models/Ternary-Bonsai-2-2B-PQ2_0.gguf
models_list() { local out; out=$(./bonsai models); echo "$out" | grep -q '9B .*Ternary-Bonsai-2-9B-PQ2_0.gguf (downloaded)'; }
check "./bonsai models lists the presets" models_list
check "./bonsai models marks the selected one" sh -c './bonsai models | grep -q "27B .*(downloaded, selected)"'
check "an unknown preset is refused" sh -c '! BONSAI_MODEL=8B ./bonsai status 2>/dev/null'
check "asking for another preset does not replace a running server" sh -c '! BONSAI_MODEL=9B ./bonsai up 2>/dev/null'
: > "$WORK/sandbox.log"
check "restart switches to the 9B" env BONSAI_MODEL=9b ./bonsai restart
check "9B: its file, and the small models' sampling" contains "$WORK/sandbox.log" \
    "exec .*llama-server -m .*Ternary-Bonsai-2-9B-PQ2_0.gguf .*--alias bonsai2-9b-pq2-0 -ngl 99 -fa on -c 32768 --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0 --presence-penalty 1.0 --repeat-penalty 1.0 --repeat-last-n 64 --jinja"
check ".env's preset does not replace a running server" sh -c './bonsai up | grep -q "running 9B-PQ2_0"'
check "pi runs on the 9B" ask
check "default model follows the preset" query settings.json '.defaultModel == "bonsai2-9b-pq2-0"'
check "9B: a budget, and no effort" req 'has("reasoning_effort") == false and .thinking_budget_tokens == 4096 and .model == "bonsai2-9b-pq2-0"'
check "pi --thinking off on the 9B" ask --thinking off
check "9B off: enable_thinking false, no effort" req '.chat_template_kwargs.enable_thinking == false and (has("reasoning_effort") | not) and .presence_penalty == 1.5'
: > "$WORK/sandbox.log"
check "restart switches to the 2B" env BONSAI_MODEL=2B ./bonsai restart
check "2B: its file" contains "$WORK/sandbox.log" 'exec .*Ternary-Bonsai-2-2B-PQ2_0.gguf'
echo 137438953472 > "$WORK/memsize"
: > "$WORK/sandbox.log"
check "restart on 128 GB" env BONSAI_MODEL=9B ./bonsai restart
check "9B on 128 GB: the top tier is the 27B's only" contains "$WORK/sandbox.log" 'exec .* -c 65536 '
: > "$WORK/sandbox.log"
check "restart the 27B on 128 GB" env BONSAI_MODEL=27B ./bonsai restart
check "27B on 128 GB: the top tier" contains "$WORK/sandbox.log" 'exec .* -c 131072 '

# --- Restart and stop
check "./bonsai down stops it" ./bonsai down
check "./bonsai down twice is fine" ./bonsai down
check "no server answers after down" sh -c "! curl -fsS -m 2 http://127.0.0.1:$PORT/health >/dev/null 2>&1"
rm -f "$WORK/stubs/sandbox-exec"
check "refuses to run without sandbox-exec" sh -c '! ./bonsai status >/dev/null 2>&1'

echo
if [ "$FAILS" -gt 0 ]; then echo "$FAILS failed"; exit 1; fi
echo "All passed."
