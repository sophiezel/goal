#!/usr/bin/env python3
"""review-channel-guard — block silent deterministic downgrade when API/Ollama is configured.

Usage:
  review-channel-guard.py --resolve [--provider P] [--model M] [--force-det 0|1] [--mode dual|goal]
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
    detect = os.path.join(script_dir(), "detect-review-channels")
    if not os.path.isfile(detect):
        return {"has_candidates": False, "selected": None, "error": "detect-review-channels missing"}
    proc = subprocess.run(
        ["python3", detect, "--json"],
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
    selected = detect_doc.get("selected") or {}
    sel_provider = str(selected.get("provider") or "")
    sel_model = str(selected.get("model") or "")

    if force_det and has_candidates:
        return (
            provider or "deterministic",
            model,
            True,
            f"GOAL_REVIEW_FORCE_DETERMINISTIC=1 is not allowed when review channel is configured ({selected_label(selected)})",
        )

    resolved_provider = provider.strip()
    resolved_model = model.strip()

    if not resolved_provider:
        if has_candidates and sel_provider:
            resolved_provider = sel_provider
            if not resolved_model and sel_model:
                resolved_model = sel_model
        else:
            resolved_provider = "deterministic"

    if force_det and not has_candidates:
        return "deterministic", resolved_model, False, None

    if has_candidates and resolved_provider == "deterministic":
        return (
            resolved_provider,
            resolved_model,
            True,
            f"provider=deterministic is not allowed when review channel is configured ({selected_label(selected)})",
        )

    if (
        has_candidates
        and sel_provider
        and resolved_provider == sel_provider
        and sel_model
        and not resolved_model
    ):
        resolved_model = sel_model

    if not has_candidates and mode == "dual" and resolved_provider == "deterministic":
        # Caller may mark review_undetermined; not a hard block without configured channels.
        pass

    return resolved_provider, resolved_model, False, None


def emit_shell(provider: str, model: str, has_candidates: bool, deterministic_only: bool) -> None:
    def q(value: str) -> str:
        return value.replace("'", "'\"'\"'")

    print(f"export REVIEW_HAS_CANDIDATES={'1' if has_candidates else '0'}")
    print(f"export RESOLVED_REVIEW_PROVIDER='{q(provider)}'")
    print(f"export RESOLVED_REVIEW_MODEL='{q(model)}'")
    print(f"export GOAL_REVIEW_DETERMINISTIC_ONLY={'1' if deterministic_only else '0'}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Enforce configured independent review channel")
    parser.add_argument("--resolve", action="store_true", help="Resolve provider/model and print shell exports")
    parser.add_argument("--check", action="store_true", help="Validate provider selection only")
    parser.add_argument("--provider", default="", help="Requested provider (empty = auto)")
    parser.add_argument("--model", default="", help="Requested model")
    parser.add_argument("--force-det", default="0", choices=("0", "1"), help="GOAL_REVIEW_FORCE_DETERMINISTIC")
    parser.add_argument("--mode", default="dual", choices=("dual", "goal"))
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
    deterministic_only = (
        not force_det
        and args.mode == "dual"
        and provider == "deterministic"
        and not has_candidates
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
                    "provider": provider,
                    "model": model,
                    "deterministic_only": deterministic_only,
                    "selected": detect_doc.get("selected"),
                },
                ensure_ascii=False,
            )
        )
    else:
        emit_shell(provider, model, has_candidates, deterministic_only)
    return 0


if __name__ == "__main__":
    sys.exit(main())
