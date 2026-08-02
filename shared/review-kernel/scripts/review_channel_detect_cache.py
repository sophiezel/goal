#!/usr/bin/env python3
"""Shared detect-review-channels cache for a single review chain (TTL ~10min).

Avoids 3× network probe in:
  goal-run-review-chain → run-independent-review → review_fallback_orchestrator
"""
from __future__ import annotations

import json
import os
import subprocess
import tempfile
import time
from typing import Any


def cache_path() -> str:
    override = os.environ.get("GOAL_REVIEW_DETECT_CACHE", "").strip()
    if override:
        return override
    return os.path.join(tempfile.gettempdir(), "goal-review-detect-cache.json")


def cache_ttl_sec() -> int:
    try:
        return int(os.environ.get("GOAL_REVIEW_DETECT_CACHE_TTL_SEC", "600") or "600")
    except ValueError:
        return 600


def _read_cache(path: str) -> dict[str, Any] | None:
    if not os.path.isfile(path):
        return None
    try:
        doc = json.load(open(path, encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    ts = float(doc.get("cached_at") or 0)
    if time.time() - ts > cache_ttl_sec():
        return None
    payload = doc.get("payload")
    if not isinstance(payload, dict):
        return None
    return payload


def _write_cache(path: str, payload: dict[str, Any]) -> None:
    try:
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"cached_at": time.time(), "payload": payload}, f, ensure_ascii=False)
        os.replace(tmp, path)
    except OSError:
        pass


def load_detect(script_dir: str, *, use_cache: bool = True) -> dict[str, Any]:
    """Run detect-review-channels --json [--probe], optionally reading/writing TTL cache."""
    detect = os.path.join(script_dir, "detect-review-channels")
    empty: dict[str, Any] = {"has_candidates": False, "ranked": [], "selected": None}
    if not os.path.isfile(detect):
        return {**empty, "error": "detect-review-channels missing"}

    probe_on = os.environ.get("GOAL_REVIEW_PROBE", "1") != "0"
    path = cache_path()
    if use_cache and probe_on and os.environ.get("GOAL_REVIEW_DETECT_CACHE_BYPASS", "0") != "1":
        cached = _read_cache(path)
        if cached is not None:
            cached = dict(cached)
            cached["_from_cache"] = True
            return cached

    args = ["python3", detect, "--json"]
    args.append("--no-probe" if not probe_on else "--probe")
    try:
        proc = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=45,
            env=os.environ.copy(),
        )
    except subprocess.TimeoutExpired:
        return {**empty, "error": "detect timeout"}
    if proc.returncode != 0:
        return {
            **empty,
            "error": (proc.stderr or proc.stdout or "detect failed").strip()[:400],
        }
    try:
        payload = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        return {**empty, "error": f"detect JSON parse error: {exc}"}

    if use_cache and probe_on and isinstance(payload, dict):
        _write_cache(path, payload)
    return payload if isinstance(payload, dict) else empty
