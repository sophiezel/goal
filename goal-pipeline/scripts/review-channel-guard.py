#!/usr/bin/env python3
"""review-channel-guard — block silent deterministic downgrade when API/Ollama is configured.

Usage:
  review-channel-guard.py --resolve [--provider P] [--model M] [--force-det 0|1] [--mode unified|goal]
  review-channel-guard.py --check [--provider P] [--force-det 0|1]

Exit 0 when allowed; exit 2 when downgrade is blocked.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys


def script_dir() -> str:
    return os.path.dirname(os.path.abspath(__file__))


def load_detect() -> dict:
    # Shared TTL cache — same review chain may call guard + orchestrator multiple times.
    try:
        from review_channel_detect_cache import load_detect as cached_load

        return cached_load(script_dir())
    except Exception:
        detect = os.path.join(script_dir(), "detect-review-channels")
        if not os.path.isfile(detect):
            return {"has_candidates": False, "selected": None, "error": "detect-review-channels missing"}
        args = ["python3", detect, "--json"]
        # Default probe ON for review orchestration; fixtures set GOAL_REVIEW_PROBE=0.
        if os.environ.get("GOAL_REVIEW_PROBE", "1") == "0":
            args.append("--no-probe")
        else:
            args.append("--probe")
        proc = subprocess.run(
            args,
            capture_output=True,
            text=True,
            env=os.environ.copy(),
        )
        if proc.returncode != 0:
            return {
                "has_candidates": False,
                "selected": None,
                "error": (proc.stderr or proc.stdout or "detect failed").strip(),
            }
        try:
            return json.loads(proc.stdout)
        except json.JSONDecodeError as exc:
            return {"has_candidates": False, "selected": None, "error": f"detect JSON parse error: {exc}"}


def selected_label(selected: dict | None) -> str:
    if not selected:
        return "configured channel"
    provider = selected.get("provider") or "unknown"
    model = selected.get("model") or ""
    return f"{provider}/{model}" if model else provider


def resolve_provider(
    detect_doc: dict,
    provider: str,
    model: str,
    force_det: bool,
    mode: str,
) -> tuple[str, str, bool, str | None]:
    has_candidates = bool(detect_doc.get("has_candidates"))
    configured_keys = bool(detect_doc.get("configured_keys"))
    unreachable = bool(detect_doc.get("configured_but_unreachable"))
    # Keys present (even if currently unreachable) must not silently downgrade to deterministic.
    anti_downgrade = has_candidates or configured_keys or unreachable
    selected = detect_doc.get("selected") or {}
    sel_provider = str(selected.get("provider") or "")
    sel_model = str(selected.get("model") or "")
    emergency = os.environ.get("GOAL_REVIEW_EMERGENCY", "0") == "1"

    if force_det and anti_downgrade and not emergency:
        label = selected_label(selected) if has_candidates else "configured API keys (unreachable or pending)"
        return (
            provider or "deterministic",
            model,
            True,
            f"GOAL_REVIEW_FORCE_DETERMINISTIC=1 is not allowed when review channel is configured ({label})",
        )

    resolved_provider = provider.strip()
    resolved_model = model.strip()

    if not resolved_provider:
        if has_candidates and sel_provider:
            resolved_provider = sel_provider
            if not resolved_model and sel_model:
                resolved_model = sel_model
        elif unreachable and not emergency:
            # Fail-fast path: caller should write review_channel_unreachable + cursor-task.
            resolved_provider = "unreachable"
        else:
            resolved_provider = "deterministic"

    if force_det and not anti_downgrade:
        return "deterministic", resolved_model, False, None

    if anti_downgrade and resolved_provider == "deterministic" and not emergency:
        label = selected_label(selected) if has_candidates else "configured API keys"
        return (
            resolved_provider,
            resolved_model,
            True,
            f"provider=deterministic is not allowed when review channel is configured ({label})",
        )

    if (
        has_candidates
        and sel_provider
        and resolved_provider == sel_provider
        and sel_model
        and not resolved_model
    ):
        resolved_model = sel_model

    if not has_candidates and mode == "unified" and resolved_provider == "deterministic":
        # Caller may mark review_undetermined; not a hard block without configured channels.
        pass

    return resolved_provider, resolved_model, False, None


def emit_shell(
    provider: str,
    model: str,
    has_candidates: bool,
    deterministic_only: bool,
    unreachable: bool,
) -> None:
    def q(value: str) -> str:
        return value.replace("'", "'\"'\"'")

    print(f"export REVIEW_HAS_CANDIDATES={'1' if has_candidates else '0'}")
    print(f"export REVIEW_CHANNEL_UNREACHABLE={'1' if unreachable else '0'}")
    print(f"export RESOLVED_REVIEW_PROVIDER='{q(provider)}'")
    print(f"export RESOLVED_REVIEW_MODEL='{q(model)}'")
    print(f"export GOAL_REVIEW_DETERMINISTIC_ONLY={'1' if deterministic_only else '0'}")
    if unreachable:
        # Hint for Agent / adapter: prefer Cursor Task over burning cascade budget.
        print("export GOAL_REVIEW_CURSOR_TASK_HINT=1")


def main() -> int:
    parser = argparse.ArgumentParser(description="Enforce configured independent review channel")
    parser.add_argument("--resolve", action="store_true", help="Resolve provider/model and print shell exports")
    parser.add_argument("--check", action="store_true", help="Validate provider selection only")
    parser.add_argument("--provider", default="", help="Requested provider (empty = auto)")
    parser.add_argument("--model", default="", help="Requested model")
    parser.add_argument("--force-det", default="0", choices=("0", "1"), help="GOAL_REVIEW_FORCE_DETERMINISTIC")
    parser.add_argument("--mode", default="unified", choices=("unified", "goal"))
    parser.add_argument("--format", default="text", choices=("text", "json"))
    args = parser.parse_args()

    if not args.resolve and not args.check:
        parser.error("one of --resolve or --check is required")

    detect_doc = load_detect()
    force_det = args.force_det == "1"
    provider, model, blocked, reason = resolve_provider(
        detect_doc,
        args.provider,
        args.model,
        force_det,
        args.mode,
    )
    has_candidates = bool(detect_doc.get("has_candidates"))
    unreachable = bool(detect_doc.get("configured_but_unreachable"))
    deterministic_only = (
        not force_det
        and args.mode == "unified"
        and provider == "deterministic"
        and not has_candidates
        and not unreachable
        and not bool(detect_doc.get("configured_keys"))
    )

    if blocked:
        if args.format == "json":
            print(
                json.dumps(
                    {
                        "ok": False,
                        "blocked": True,
                        "reason": reason,
                        "has_candidates": has_candidates,
                        "configured_but_unreachable": unreachable,
                        "provider": provider,
                        "selected": detect_doc.get("selected"),
                    },
                    ensure_ascii=False,
                )
            )
        else:
            print(f"review-channel-guard: BLOCKED — {reason}", file=sys.stderr)
            if detect_doc.get("error"):
                print(f"review-channel-guard: detect error: {detect_doc['error']}", file=sys.stderr)
        return 2

    if args.check:
        if args.format == "json":
            print(
                json.dumps(
                    {
                        "ok": True,
                        "blocked": False,
                        "has_candidates": has_candidates,
                        "configured_but_unreachable": unreachable,
                        "provider": provider,
                        "model": model,
                        "selected": detect_doc.get("selected"),
                    },
                    ensure_ascii=False,
                )
            )
        return 0

    if args.format == "json":
        print(
            json.dumps(
                {
                    "ok": True,
                    "has_candidates": has_candidates,
                    "configured_but_unreachable": unreachable,
                    "provider": provider,
                    "model": model,
                    "deterministic_only": deterministic_only,
                    "selected": detect_doc.get("selected"),
                },
                ensure_ascii=False,
            )
        )
    else:
        emit_shell(provider, model, has_candidates, deterministic_only, unreachable)
    return 0


if __name__ == "__main__":
    sys.exit(main())
