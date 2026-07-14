#!/bin/bash
# test-adapter-content-fallback.sh — empty content + reasoning_content parses; empty both → empty_content
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$DIR/../.." && pwd)"

python3 - "$SCRIPTS" << 'PY'
import importlib.util, json, os, sys

scripts = sys.argv[1]
spec = importlib.util.spec_from_file_location(
    "platform_review_adapter_core",
    os.path.join(scripts, "platform_review_adapter_core.py"),
)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

# content preferred
assert mod._message_text_for_json({"content": '{"a":1}', "reasoning_content": "noise"}) == '{"a":1}'
# fallback to reasoning
assert mod._message_text_for_json({"content": "", "reasoning_content": '{"a":2}'}) == '{"a":2}'
assert mod._message_text_for_json({"content": "   ", "reasoning_content": '{"a":3}'}) == '{"a":3}'
assert mod._message_text_for_json({}) == ""

out = mod._parse_model_json('```json\n{"result":"pass"}\n```')
assert out["result"] == "pass"

try:
    mod._parse_model_json("")
    raise SystemExit("expected empty_content")
except RuntimeError as e:
    assert "empty_content" in str(e), e

# Monkeypatch http_json: empty content + reasoning JSON (DeepSeek thinking morph)
captured = {}

def fake_http_ok(url, headers, body, timeout=120):
    captured["body"] = body
    return {
        "choices": [
            {
                "message": {
                    "content": "",
                    "reasoning_content": '{"result":"pass","issues":[]}',
                }
            }
        ],
        "usage": {"completion_tokens": 10},
    }

mod.http_json = fake_http_ok
out = mod.call_openai_compat(
    "https://api.deepseek.com/v1",
    "k",
    "deepseek-v4-flash",
    "sys",
    "user",
    "deepseek",
    disable_thinking=True,
)
assert out["result"] == "pass"
assert captured["body"].get("thinking") == {"type": "disabled"}, captured["body"]
assert out["provider"] == "deepseek"

# truly empty → empty_content error kind path
def fake_http_empty(url, headers, body, timeout=120):
    return {"choices": [{"message": {"content": "", "reasoning_content": ""}}], "usage": {}}

mod.http_json = fake_http_empty
try:
    mod.call_openai_compat("https://x/v1", "k", "m", "s", "u", "deepseek", disable_thinking=True)
    raise SystemExit("expected empty_content raise")
except RuntimeError as e:
    assert "empty_content" in str(e), e

print("adapter content fallback OK")
PY

echo "test-adapter-content-fallback passed"
