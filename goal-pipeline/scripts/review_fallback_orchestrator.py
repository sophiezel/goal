#!/usr/bin/env python3
"""Review fallback orchestrator — API cascade, packet variants, optional parallel sharding."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any

_SCRIPT_ROOT = os.path.dirname(os.path.abspath(__file__))
if _SCRIPT_ROOT not in sys.path:
    sys.path.insert(0, _SCRIPT_ROOT)

from readonly_subagent_review import run_readonly_subagent
from review_depth import load_state, persist_review_policy, resolve_review_depth
from review_packet_shard import build_shards, merge_unified_reviews


def tier_limits(state: dict[str, Any]) -> tuple[int, int, int]:
    """Return (budget_sec, max_api_attempts, readonly_budget_sec) for tier."""
    tier = str((state.get("quality_policy") or {}).get("tier") or "standard").lower()
    if tier == "strict":
        return (
            int(os.environ.get("GOAL_REVIEW_BUDGET_SEC", "900")),
            int(os.environ.get("GOAL_REVIEW_MAX_API_ATTEMPTS", "5")),
            int(os.environ.get("GOAL_REVIEW_READONLY_BUDGET_SEC", "300")),
        )
    return (
        int(os.environ.get("GOAL_REVIEW_BUDGET_SEC", "480")),
        int(os.environ.get("GOAL_REVIEW_MAX_API_ATTEMPTS", "3")),
        int(os.environ.get("GOAL_REVIEW_READONLY_BUDGET_SEC", "180")),
    )


def load_detect(script_dir: str) -> dict[str, Any]:
    # Shared TTL cache with review-channel-guard (same review chain).
    try:
        from review_channel_detect_cache import load_detect as cached_load

        return cached_load(script_dir)
    except Exception:
        detect = os.path.join(script_dir, "detect-review-channels")
        if not os.path.isfile(detect):
            return {"has_candidates": False, "ranked": [], "selected": None}
        args = ["python3", detect, "--json"]
        if os.environ.get("GOAL_REVIEW_PROBE", "1") == "0":
            args.append("--no-probe")
        else:
            args.append("--probe")
        proc = subprocess.run(args, capture_output=True, text=True, timeout=45)
        if proc.returncode != 0:
            return {
                "has_candidates": False,
                "ranked": [],
                "selected": None,
                "error": (proc.stderr or proc.stdout)[:200],
            }
        try:
            return json.loads(proc.stdout)
        except json.JSONDecodeError:
            return {"has_candidates": False, "ranked": [], "selected": None}


def _flush_attempts(attempts: list[dict[str, Any]]) -> None:
    path = os.environ.get("GOAL_REVIEW_ATTEMPTS_PATH", "").strip()
    if not path:
        return
    try:
        with open(path, "w", encoding="utf-8") as fh:
            json.dump({"attempts": attempts, "partial": True}, fh, ensure_ascii=False)
    except OSError:
        pass


def _unreachable_result(
    preferred_provider: str,
    preferred_model: str,
    detect_doc: dict[str, Any],
    attempts: list[dict[str, Any]],
    started: float,
    budget_sec: int,
    depth: str,
    depth_meta: dict[str, Any],
) -> dict[str, Any]:
    attempts.append(
        {
            "layer": "preflight",
            "fallback_layer": "connectivity_probe",
            "provider": "detect-review-channels",
            "error": "review_channel_unreachable",
            "error_kind": "review_channel_unreachable",
            "detail": "configured API keys present but short probe failed; cascade skipped",
        }
    )
    _flush_attempts(attempts)
    return {
        "ok": False,
        "review_body": {
            "result": "review_undetermined",
            "error_kind": "review_channel_unreachable",
            "issues": [
                {
                    "id": "CH-UNREACHABLE",
                    "severity": "blocker",
                    "summary": "Review API channels unreachable (short probe failed) — skip cascade; use Cursor Task (GOAL_REVIEW_CURSOR_TASK=1) or fix network",
                    "channel": "goal",
                    "root_cause": "infra_channel",
                    "suggestion": "switch_to_cursor_task",
                }
            ],
            "checklist_goal": [],
            "checklist_gf": [],
        },
        "provider": preferred_provider or "unreachable",
        "model": preferred_model,
        "fallback_layer": "hard_stop_unreachable",
        "review_depth": depth,
        "depth_meta": depth_meta,
        "attempts": attempts,
        "budget_sec": budget_sec,
        "elapsed_ms": int((time.time() - started) * 1000),
        "configured_but_unreachable": True,
        "detect": {
            "has_candidates": detect_doc.get("has_candidates"),
            "configured_keys": detect_doc.get("configured_keys"),
        },
    }

def candidate_key(c: dict[str, Any]) -> tuple[str, str]:
    return (str(c.get("provider") or ""), str(c.get("model") or ""))


def build_candidate_list(
    detect_doc: dict[str, Any],
    preferred_provider: str,
    preferred_model: str,
    max_attempts: int,
) -> list[dict[str, Any]]:
    ranked = list(detect_doc.get("ranked") or [])
    out: list[dict[str, Any]] = []
    seen: set[tuple[str, str]] = set()

    if preferred_provider and preferred_provider not in ("deterministic", ""):
        entry = {"provider": preferred_provider, "model": preferred_model or ""}
        key = candidate_key(entry)
        if key not in seen:
            seen.add(key)
            out.append(entry)

    for item in ranked:
        key = candidate_key(item)
        if key in seen:
            continue
        seen.add(key)
        out.append({"provider": item.get("provider"), "model": item.get("model") or ""})
        if len(out) >= max_attempts:
            break

    if not out and preferred_provider and preferred_provider not in ("deterministic", ""):
        out.append({"provider": preferred_provider, "model": preferred_model or ""})
    return out[:max_attempts]


def shrink_packet(packet: dict[str, Any], variant: str, scoped_diff_budget: int = 25000) -> dict[str, Any]:
    p = json.loads(json.dumps(packet))
    if variant == "scoped":
        diff = p.get("diff") or ""
        enc = diff.encode("utf-8")
        if len(enc) > scoped_diff_budget:
            diff = enc[:scoped_diff_budget].decode("utf-8", errors="ignore") + "\n...[scoped diff truncated]..."
        p["diff"] = diff
        rubric = p.get("guazi_flow_rubric") or {}
        p["guazi_flow_rubric"] = {k: (v[:1200] if isinstance(v, str) else v) for k, v in rubric.items()}
        contract = p.get("contract") or {}
        p["contract"] = {k: (v[:1500] if isinstance(v, str) else v) for k, v in contract.items()}
    p["_packet_variant"] = variant
    return p


def packet_variants(packet: dict[str, Any], *, light_only: bool = False) -> list[tuple[str, dict[str, Any]]]:
    if light_only:
        return [("scoped", shrink_packet(packet, "scoped"))]
    diff_len = len((packet.get("diff") or "").encode("utf-8"))
    variants: list[tuple[str, dict[str, Any]]] = [("full", packet)]
    if diff_len > 25000:
        variants.append(("scoped", shrink_packet(packet, "scoped")))
    return variants


def call_adapter(
    script_dir: str,
    provider: str,
    model: str,
    packet_path: str,
    channel: str,
    verify_json: str,
    timeout_sec: int,
) -> tuple[dict[str, Any], str | None, int]:
    adapter = os.path.join(script_dir, "platform-review-adapter.sh")
    args = [
        adapter,
        "--provider",
        provider,
        "--packet",
        packet_path,
        "--verify-json",
        verify_json,
        "--channel",
        channel,
        "--timeout",
        str(timeout_sec),
    ]
    if model:
        args.extend(["--model", model])
    start = time.time()
    try:
        proc = subprocess.run(args, capture_output=True, text=True, timeout=timeout_sec + 15)
        latency_ms = int((time.time() - start) * 1000)
        body = (proc.stdout or "").strip() or "{}"
        parsed = json.loads(body)
        err = parsed.get("error")
        if parsed.get("result") in ("pass", "not_pass"):
            return parsed, None, latency_ms
        if err:
            return parsed, str(err)[:200], latency_ms
        if proc.stderr.strip():
            return parsed, proc.stderr.strip()[:200], latency_ms
        return parsed, "review_undetermined", latency_ms
    except subprocess.TimeoutExpired:
        latency_ms = int((time.time() - start) * 1000)
        return (
            {"result": "review_undetermined", "error_kind": "timeout"},
            f"adapter_timeout_{timeout_sec}s",
            latency_ms,
        )
    except json.JSONDecodeError as exc:
        latency_ms = int((time.time() - start) * 1000)
        return {"result": "review_undetermined"}, f"json_parse:{exc}", latency_ms


def review_packet_once(
    script_dir: str,
    tmpdir: str,
    packet: dict[str, Any],
    provider: str,
    model: str,
    channel: str,
    verify_json: str,
    timeout_sec: int,
    *,
    light_only: bool = False,
    tag: str = "",
) -> tuple[dict[str, Any] | None, list[dict[str, Any]]]:
    attempts: list[dict[str, Any]] = []
    for variant_name, variant_packet in packet_variants(packet, light_only=light_only):
        suffix = f"{tag}-{variant_name}" if tag else variant_name
        variant_path = os.path.join(tmpdir, f"{provider}-{suffix}.json")
        with open(variant_path, "w", encoding="utf-8") as fh:
            json.dump(variant_packet, fh, ensure_ascii=False)
        parsed, err, latency_ms = call_adapter(
            script_dir, provider, model, variant_path, channel, verify_json, timeout_sec
        )
        attempts.append(
            {
                "layer": "shard" if tag else ("api" if variant_name == "full" else "vertical"),
                "fallback_layer": "packet_shard" if tag else ("api_horizontal" if variant_name == "full" else "packet_vertical"),
                "provider": provider,
                "model": model,
                "packet_variant": variant_name,
                "shard_id": tag or variant_packet.get("shard_id", ""),
                "latency_ms": latency_ms,
                "result": parsed.get("result"),
                "error": err,
                "error_kind": parsed.get("error_kind") or ("timeout" if err and "timeout" in str(err).lower() else ""),
            }
        )
        if parsed.get("result") in ("pass", "not_pass"):
            return parsed, attempts
        retryable = err and (
            "timeout" in str(err).lower()
            or "undetermined" in str(parsed.get("result", ""))
            or parsed.get("error_kind") == "timeout"
        )
        if variant_name == "full" and retryable:
            continue
        break
    return None, attempts


def run_fallback(
    script_dir: str,
    packet_path: str,
    verify_json: str,
    channel: str,
    preferred_provider: str,
    preferred_model: str,
    budget_sec: int,
    attempt_timeout_sec: int,
    max_api_attempts: int,
    candidates_override: list[dict[str, Any]] | None = None,
    state_file: str = "",
    review_depth: str = "",
) -> dict[str, Any]:
    started = time.time()
    packet = json.load(open(packet_path, encoding="utf-8"))
    state = load_state(state_file)
    tier_budget, tier_max_api, readonly_budget = tier_limits(state)
    budget_sec = min(budget_sec, tier_budget) if budget_sec else tier_budget
    max_api_attempts = min(max_api_attempts, tier_max_api) if max_api_attempts else tier_max_api

    depth, depth_meta = resolve_review_depth(packet, state, explicit=review_depth)
    persist_review_policy(state_file, depth, depth_meta)

    detect_doc = load_detect(script_dir)
    attempts: list[dict[str, Any]] = []

    # Fail-fast: keys configured but short probe failed → never burn 240s×N cascade.
    if (
        not candidates_override
        and detect_doc.get("configured_but_unreachable")
        and not detect_doc.get("has_candidates")
        and os.environ.get("GOAL_REVIEW_EMERGENCY", "0") != "1"
    ):
        return _unreachable_result(
            preferred_provider,
            preferred_model,
            detect_doc,
            attempts,
            started,
            budget_sec,
            depth,
            depth_meta,
        )

    candidates = candidates_override or build_candidate_list(
        detect_doc, preferred_provider, preferred_model, max_api_attempts
    )
    # Drop ollama from API cascade if daemon is down (defense in depth).
    try:
        from review_channel_probe import ollama_reachable

        if not ollama_reachable(timeout=1.0):
            candidates = [c for c in candidates if str(c.get("provider") or "") != "ollama"]
    except Exception:
        pass

    light_only = depth == "light"
    use_shards = depth == "full" and os.environ.get("GOAL_REVIEW_DISABLE_SHARD", "0") != "1"
    shard_packets = build_shards(packet, script_dir) if use_shards else [packet]
    parallel_shards = len(shard_packets) > 1

    consecutive_infra = 0
    with tempfile.TemporaryDirectory(prefix="goal-review-pkt-") as tmpdir:
        try:
            return _run_cascade_body(
                script_dir=script_dir,
                packet=packet,
                verify_json=verify_json,
                channel=channel,
                preferred_provider=preferred_provider,
                preferred_model=preferred_model,
                budget_sec=budget_sec,
                attempt_timeout_sec=attempt_timeout_sec,
                candidates=candidates,
                detect_doc=detect_doc,
                attempts=attempts,
                started=started,
                depth=depth,
                depth_meta=depth_meta,
                light_only=light_only,
                shard_packets=shard_packets,
                parallel_shards=parallel_shards,
                readonly_budget=readonly_budget,
                tmpdir=tmpdir,
            )
        except (KeyboardInterrupt, SystemExit):
            _flush_attempts(attempts)
            raise
        except Exception:
            _flush_attempts(attempts)
            raise


def _run_cascade_body(
    *,
    script_dir: str,
    packet: dict[str, Any],
    verify_json: str,
    channel: str,
    preferred_provider: str,
    preferred_model: str,
    budget_sec: int,
    attempt_timeout_sec: int,
    candidates: list[dict[str, Any]],
    detect_doc: dict[str, Any],
    attempts: list[dict[str, Any]],
    started: float,
    depth: str,
    depth_meta: dict[str, Any],
    light_only: bool,
    shard_packets: list[dict[str, Any]],
    parallel_shards: bool,
    readonly_budget: int,
    tmpdir: str,
) -> dict[str, Any]:
    consecutive_infra = 0
    for cand in candidates:
        provider = str(cand.get("provider") or "")
        model = str(cand.get("model") or "")
        if not provider or provider in ("deterministic", "unreachable"):
            continue

        remaining = budget_sec - int(time.time() - started)
        if remaining <= 5:
            attempts.append({"layer": "api", "provider": provider, "error": "budget_exhausted"})
            _flush_attempts(attempts)
            break

        timeout_sec = min(attempt_timeout_sec, max(10, remaining - 5))

        if parallel_shards:
            shard_timeout = max(15, timeout_sec // max(1, len(shard_packets)))
            bodies: list[dict[str, Any]] = []
            with ThreadPoolExecutor(max_workers=min(4, len(shard_packets))) as pool:
                futures = {
                    pool.submit(
                        review_packet_once,
                        script_dir,
                        tmpdir,
                        sp,
                        provider,
                        model,
                        channel,
                        verify_json,
                        shard_timeout,
                        light_only=light_only,
                        tag=str(sp.get("shard_id") or "shard"),
                    ): sp
                    for sp in shard_packets
                }
                for fut in as_completed(futures):
                    body, shard_attempts = fut.result()
                    attempts.extend(shard_attempts)
                    _flush_attempts(attempts)
                    if body:
                        bodies.append(body)
            if len(bodies) == len(shard_packets):
                merged = merge_unified_reviews(bodies)
                return {
                    "ok": True,
                    "review_body": merged,
                    "provider": provider,
                    "model": str(merged.get("model") or model or provider),
                    "fallback_layer": "packet_shard_parallel",
                    "review_depth": depth,
                    "depth_meta": depth_meta,
                    "attempts": attempts,
                    "budget_sec": budget_sec,
                    "elapsed_ms": int((time.time() - started) * 1000),
                }
            consecutive_infra += 1
            if consecutive_infra >= 2:
                attempts.append(
                    {
                        "layer": "api",
                        "error": "consecutive_infra_abort",
                        "error_kind": "review_channel_unreachable",
                    }
                )
                _flush_attempts(attempts)
                break
            continue

        body, single_attempts = review_packet_once(
            script_dir,
            tmpdir,
            packet,
            provider,
            model,
            channel,
            verify_json,
            timeout_sec,
            light_only=light_only,
        )
        attempts.extend(single_attempts)
        _flush_attempts(attempts)
        if body:
            layer = (
                "packet_vertical"
                if light_only
                else (single_attempts[-1].get("fallback_layer") if single_attempts else "api_horizontal")
            )
            return {
                "ok": True,
                "review_body": body,
                "provider": provider,
                "model": str(body.get("model") or model or provider),
                "fallback_layer": layer,
                "review_depth": depth,
                "depth_meta": depth_meta,
                "attempts": attempts,
                "budget_sec": budget_sec,
                "elapsed_ms": int((time.time() - started) * 1000),
            }
        # Abort cascade early when attempts look like infra timeouts / connection errors.
        last_err = " ".join(str(a.get("error") or "") for a in single_attempts[-2:])
        if any(x in last_err.lower() for x in ("timeout", "connection refused", "unreachable", "timed out")):
            consecutive_infra += 1
        else:
            consecutive_infra = 0
        if consecutive_infra >= 2:
            attempts.append(
                {
                    "layer": "api",
                    "error": "consecutive_infra_abort",
                    "error_kind": "review_channel_unreachable",
                }
            )
            _flush_attempts(attempts)
            break

    # Layer 3 — readonly subagent (process-isolated; separation_confidence=medium)
    # Enter when: detect has LLM channels, OR API cascade already attempted a non-det
    # provider (e.g. --candidates-json override), OR fixture mock (GOAL_REVIEW_READONLY_MOCK=1).
    # Skip when zero channels and no attempts — ChannelPolicy fail-fast to hard_stop.
    remaining_ro = budget_sec - int(time.time() - started)
    readonly_mock = os.environ.get("GOAL_REVIEW_READONLY_MOCK", "0") == "1"
    attempted_llm = any(
        (a.get("provider") or "") not in ("", "deterministic", "unreachable", "detect-review-channels")
        for a in attempts
    )
    ollama_up = False
    try:
        from review_channel_probe import ollama_reachable

        ollama_up = ollama_reachable(timeout=1.0)
    except Exception:
        ollama_up = False

    # Skip readonly→ollama when daemon is down (prevents Connection refused noise).
    if remaining_ro > 10 and (readonly_mock or ((detect_doc.get("has_candidates") or attempted_llm) and ollama_up)):
        ro_budget = min(readonly_budget, remaining_ro - 5)
        if readonly_mock:
            ro_budget = max(ro_budget, 30)
        ro_body, ro_attempts = run_readonly_subagent(
            script_dir, packet, verify_json, channel, ro_budget
        )
        attempts.extend(ro_attempts)
        _flush_attempts(attempts)
        if ro_body:
            return {
                "ok": True,
                "review_body": ro_body,
                "provider": "readonly-subagent",
                "model": str(ro_body.get("model") or "readonly-subagent"),
                "fallback_layer": "readonly_subagent",
                "review_depth": depth,
                "depth_meta": depth_meta,
                "attempts": attempts,
                "budget_sec": budget_sec,
                "elapsed_ms": int((time.time() - started) * 1000),
            }
    elif attempted_llm and not ollama_up and not readonly_mock:
        attempts.append(
            {
                "layer": "readonly_subagent",
                "fallback_layer": "readonly_subagent",
                "provider": "ollama",
                "error": "ollama_skipped_not_listening",
                "error_kind": "connection_refused",
            }
        )
        _flush_attempts(attempts)

    emergency = os.environ.get("GOAL_REVIEW_EMERGENCY", "0") == "1"
    infra_abort = any(
        (a.get("error_kind") == "review_channel_unreachable")
        or "consecutive_infra_abort" in str(a.get("error") or "")
        for a in attempts
    )
    if infra_abort:
        exhaust_summary = (
            "Review API 通道预检/连续 infra 失败 — 已跳过满预算 cascade；请 GOAL_REVIEW_CURSOR_TASK=1 或修复网络"
        )
        error_kind = "review_channel_unreachable"
        issue_id = "CH-UNREACHABLE"
        root_cause = "infra_channel"
    else:
        exhaust_summary = (
            "review 降级链已耗尽（含 readonly subagent）— 请配置 API key 或显式 GOAL_REVIEW_EMERGENCY=1"
            if not emergency
            else "review 降级链已耗尽 — emergency 模式需人工写入 review-unified.json"
        )
        error_kind = "fallback_exhausted"
        issue_id = "FB-EXHAUST"
        root_cause = "infra_channel"
    out = {
        "ok": False,
        "review_body": {
            "result": "review_undetermined",
            "issues": [
                {
                    "id": issue_id,
                    "severity": "blocker" if infra_abort else "medium",
                    "summary": exhaust_summary,
                    "channel": "goal",
                    "root_cause": root_cause,
                    "suggestion": "switch_to_cursor_task" if infra_abort else "fix_channel",
                }
            ],
            "checklist_goal": [],
            "checklist_gf": [],
            "error_kind": error_kind,
            "emergency_bypass": emergency,
        },
        "provider": preferred_provider,
        "model": preferred_model,
        "fallback_layer": "hard_stop",
        "review_depth": depth,
        "depth_meta": depth_meta,
        "attempts": attempts,
        "budget_sec": budget_sec,
        "elapsed_ms": int((time.time() - started) * 1000),
    }
    _flush_attempts(attempts)
    return out


def main() -> int:
    p = argparse.ArgumentParser(description="Run review with API fallback cascade")
    p.add_argument("--script-dir", required=True)
    p.add_argument("--packet", required=True)
    p.add_argument("--verify-json", default="{}")
    p.add_argument("--channel", default="unified", choices=["goal", "unified"])
    p.add_argument("--provider", default="")
    p.add_argument("--model", default="")
    p.add_argument("--state-file", default=os.environ.get("GOAL_STATE_FILE", ""))
    p.add_argument("--review-depth", default=os.environ.get("GOAL_REVIEW_DEPTH", ""))
    p.add_argument("--budget-sec", type=int, default=int(os.environ.get("GOAL_REVIEW_BUDGET_SEC", "480")))
    p.add_argument("--attempt-timeout-sec", type=int, default=int(os.environ.get("GOAL_REVIEW_ATTEMPT_TIMEOUT_SEC", "90")))
    p.add_argument("--max-api-attempts", type=int, default=int(os.environ.get("GOAL_REVIEW_MAX_API_ATTEMPTS", "3")))
    p.add_argument("--candidates-json", default="", help="fixture override: JSON array of {provider,model}")
    args = p.parse_args()

    override = None
    if args.candidates_json.strip():
        override = json.loads(args.candidates_json)

    # Ensure script dir on path for sibling imports when invoked as file
    if args.script_dir not in sys.path:
        sys.path.insert(0, args.script_dir)

    result = run_fallback(
        args.script_dir,
        args.packet,
        args.verify_json,
        args.channel,
        args.provider,
        args.model,
        args.budget_sec,
        args.attempt_timeout_sec,
        args.max_api_attempts,
        candidates_override=override,
        state_file=args.state_file,
        review_depth=args.review_depth,
    )
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
