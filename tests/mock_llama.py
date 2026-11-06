#!/usr/bin/env python3
"""A stand-in for llama-server: the endpoints that ./bonsai, bonsai-detect and pi use. Records chat requests."""
import argparse
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--alias", default="bonsai2-27b-pq2-0")
    parser.add_argument("--list-devices", action="store_true")
    parser.add_argument("-c", type=int, default=65536)
    parser.add_argument("--record", default=None)
    parser.add_argument("--vision", action="store_true")
    parser.add_argument("--usage-file", default=None, help="prompt tokens to report, read at each request")
    args, _ = parser.parse_known_args()
    if args.list_devices:
        print("Available devices:\n  MTL0: Apple M4 Pro (mock)")
        return

    key = os.environ.get("LLAMA_API_KEY")  # as llama-server: every endpoint but /health needs it, when set

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def refused(self):
            if not key or self.headers.get("Authorization") == f"Bearer {key}":
                return False
            self.send_error(401)
            return True

        def send_json(self, value):
            body = json.dumps(value).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path == "/health":
                self.send_json({"status": "ok"})
            elif self.refused():
                pass
            elif self.path == "/props":
                self.send_json({
                    "model_alias": args.alias,
                    "default_generation_settings": {"n_ctx": args.c},
                    "modalities": {"vision": args.vision},
                })
            elif self.path == "/v1/models":
                self.send_json({"data": [{"id": args.alias}]})
            else:
                self.send_error(404)

        def do_POST(self):
            request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            if self.refused():
                return
            if args.record:
                with open(args.record, "a", encoding="utf-8") as f:
                    f.write(json.dumps(request) + "\n")
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            for delta, finish in (({"role": "assistant", "content": "pong"}, None), ({}, "stop")):
                chunk = {
                    "id": "mock", "object": "chat.completion.chunk", "created": 0, "model": args.alias,
                    "choices": [{"index": 0, "delta": delta, "finish_reason": finish}],
                }
                self.wfile.write(f"data: {json.dumps(chunk)}\n\n".encode())
            if args.usage_file and os.path.exists(args.usage_file):
                with open(args.usage_file, encoding="utf-8") as f:
                    prompt = int(f.read())
                chunk = {
                    "id": "mock", "object": "chat.completion.chunk", "created": 0, "model": args.alias, "choices": [],
                    "usage": {"prompt_tokens": prompt, "completion_tokens": 1, "total_tokens": prompt + 1},
                }
                self.wfile.write(f"data: {json.dumps(chunk)}\n\n".encode())
            self.wfile.write(b"data: [DONE]\n\n")

    HTTPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    sys.exit(main())
