#!/usr/bin/env python3
"""Layer 3 readonly subagent review — process-isolated LLM fallback when API cascade fails."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from typing import Any

_SCRIPT_ROOT = os.path.dirname(os.path.abspath(__file__))
if _SCRIPT_ROOT not in sys.path:
    sys.path.insert(0, _SCRIPT_ROOT)

from review_packet_shard import build_shards, merge_unified_reviews


def _mock_review(packet: dict[str, Any], channel: str) -> dict[str, Any]:
    """Deterministic fixture path — still emits valid unified JSON with medium separation."""
    changed = len(packet.get("changed_files") or [])
    return {
        "result": "pass",
        "model": "readonly-subagent-mock",
        "provider": "readonly-subagent",
        "separation_confidence": "medium",
        "checklist_goal": [
            {
                "id": "scope_compliant",
                "result": "pass",
                "detail": f"readonly mock：已审 {changed} 个变更文件（fixture）",
            }
        ],
        "checklist_gf": [],
        "issues": [],
        "readonly_subagent": True,
    }


def _call_adapter(
    script_dir: str,
    packet_path: str,
    channel: str,
    verify_json: str,
    timeout_sec: int,
) -> tuple[dict[str, Any] | None, str | None, int]:
    """Try ollama via adapter as readonly subprocess review."""
    adapter = os.path.join(script_dir, "platform-review-adapter.sh")
    if not os.path.isfile(adapter):
        return None, "adapter_missing", 0
    args = [
        adapter,
        "--provider",
        "ollama",
        "--packet",
        packet_path,
        "--verify-json",
        verify_json,
        "--channel",
        channel,
        "--timeout",
        str(timeout_sec),
    ]
    start = time.time()
    try:
        proc = subprocess.run(args, capture_output=True, text=True, timeout=timeout_sec + 10)
        latency_ms = int((time.time() - start) * 1000)
        body = (proc.stdout or "").strip() or "{}"
        parsed = json.loads(body)
        if parsed.get("result") in ("pass", "not_pass"):
            parsed["provider"] = "readonly-subagent"
            parsed["separation_confidence"] = "medium"
            parsed["readonly_subagent"] = True
            return parsed, None, latency_ms
        err = parsed.get("error") or (proc.stderr or "").strip()[:200] or "review_undetermined"
        return parsed, str(err), latency_ms
    except subprocess.TimeoutExpired:
        return None, f"readonly_timeout_{timeout_sec}s", int((time.time() - start) * 1000)
    except json.JSONDecodeError as exc:
        return None, f"json_parse:{exc}", int((time.time() - start) * 1000)


def run_readonly_subagent(
    script_dir: str,
    packet: dict[str, Any],
    verify_json: str,
    channel: str,
    budget_sec: int = 180,
) -> tuple[dict[str, Any] | None, list[dict[str, Any]]]:
    attempts: list[dict[str, Any]] = []
    started = time.time()

    if os.environ.get("GOAL_REVIEW_READONLY_MOCK", "0") == "1":
        body = _mock_review(packet, channel)
        attempts.append(
            {
                "layer": "readonly_subagent",
                "fallback_layer": "readonly_subagent",
                "provider": "readonly-subagent",
                "model": "mock",
                "packet_variant": "mock",
                "latency_ms": 5,
                "result": body.get("result"),
            }
        )
        return body, attempts

    try:
        from review_channel_probe import ollama_reachable

        if not ollama_reachable(timeout=1.0):
            attempts.append(
                {
                    "layer": "readonly_subagent",
                    "fallback_layer": "readonly_subagent",
                    "provider": "ollama",
                    "error": "ollama_skipped_not_listening",
                    "error_kind": "connection_refused",
                    "latency_ms": 0,
                }
            )
            return None, attempts
    except Exception:
        pass

    shards = build_shards(packet, script_dir)
    if len(shards) <= 1:
        shards = [packet]

    per_shard = max(20, budget_sec // max(1, len(shards)))
    bodies: list[dict[str, Any]] = []

    with tempfile.TemporaryDirectory(prefix="goal-readonly-") as tmpdir:
        for shard in shards[:4]:
            remaining = budget_sec - int(time.time() - started)
            if remaining <= 5:
                attempts.append({"layer": "readonly_subagent", "error": "budget_exhausted"})
                break
            timeout = min(per_shard, remaining - 2)
            shard_path = os.path.join(tmpdir, f"{shard.get('shard_id', 'shard')}.json")
            with open(shard_path, "w", encoding="utf-8") as fh:
                json.dump(shard, fh, ensure_ascii=False)
            body, err, latency_ms = _call_adapter(
                script_dir, shard_path, channel, verify_json, timeout
            )
            attempts.append(
                {
                    "layer": "readonly_subagent",
                    "fallback_layer": "readonly_subagent",
                    "provider": "readonly-subagent",
                    "model": "ollama",
                    "packet_variant": shard.get("shard_id", "shard"),
                    "latency_ms": latency_ms,
                    "result": (body or {}).get("result"),
                    "error": err,
                }
            )
            if body:
                bodies.append(body)

    if len(bodies) == len(shards[:4]) and bodies:
        merged = merge_unified_reviews(bodies)
        merged["provider"] = "readonly-subagent"
        merged["separation_confidence"] = "medium"
        merged["readonly_subagent"] = True
        return merged, attempts

    return None, attempts


def main() -> int:
    p = argparse.ArgumentParser(description="Run readonly subagent review (Layer 3)")
    p.add_argument("--script-dir", default=_SCRIPT_ROOT)
    p.add_argument("--packet", required=True)
    p.add_argument("--verify-json", default="{}")
    p.add_argument("--channel", default="unified")
    p.add_argument("--budget-sec", type=int, default=int(os.environ.get("GOAL_REVIEW_READONLY_BUDGET_SEC", "180")))
    p.add_argument("--json", action="store_true", dest="as_json")
    args = p.parse_args()

    packet = json.load(open(args.packet, encoding="utf-8"))
    body, attempts = run_readonly_subagent(
        args.script_dir, packet, args.verify_json, args.channel, args.budget_sec
    )
    out = {"ok": body is not None, "review_body": body, "attempts": attempts}
    print(json.dumps(out, ensure_ascii=False))
    return 0 if body else 1


if __name__ == "__main__":
    raise SystemExit(main())
