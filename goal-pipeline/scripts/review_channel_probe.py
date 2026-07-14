#!/usr/bin/env python3
"""Short-timeout reachability probes for review API providers and Ollama."""
from __future__ import annotations

import json
import os
import socket
import urllib.error
import urllib.request
from typing import Any


DEFAULT_PROBE_TIMEOUT_SEC = float(os.environ.get("GOAL_REVIEW_PROBE_TIMEOUT_SEC", "6"))


def tcp_open(host: str, port: int, timeout: float = 1.0) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def ollama_reachable(timeout: float = 1.0) -> bool:
    return tcp_open("127.0.0.1", 11434, timeout=timeout)


def _http_probe(url: str, headers: dict[str, str] | None, timeout: float) -> tuple[bool, str]:
    req = urllib.request.Request(url, headers=headers or {}, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            # Any HTTP response means TLS+TCP path works (401/404 still reachable).
            _ = resp.getcode()
            return True, f"http_{_}"
    except urllib.error.HTTPError as e:
        return True, f"http_{e.code}"
    except Exception as e:  # noqa: BLE001 — probe surface is intentionally broad
        return False, str(e)[:160]


_PROVIDER_HOSTS = {
    "openai": ("api.openai.com", 443),
    "deepseek": ("api.deepseek.com", 443),
    "groq": ("api.groq.com", 443),
    "anthropic": ("api.anthropic.com", 443),
    "gemini": ("generativelanguage.googleapis.com", 443),
}


def probe_provider(provider: str, api_key: str, timeout: float | None = None) -> dict[str, Any]:
    """Return {reachable, detail} for a configured provider.

    TCP-first (hard fail under ~2–3s) then cheap HTTP GET; avoids burning full
    cascade budgets when TLS/DNS is wedged.
    """
    t = DEFAULT_PROBE_TIMEOUT_SEC if timeout is None else timeout
    provider = (provider or "").lower()
    if provider == "ollama":
        ok = ollama_reachable(min(t, 2.0))
        return {"reachable": ok, "detail": "tcp_11434_ok" if ok else "tcp_11434_refused"}

    if not api_key:
        return {"reachable": False, "detail": "missing_api_key"}

    host_port = _PROVIDER_HOSTS.get(provider)
    if not host_port:
        return {"reachable": True, "detail": "probe_skipped_unknown_provider"}

    host, port = host_port
    tcp_t = min(3.0, max(1.0, t * 0.5))
    if not tcp_open(host, port, timeout=tcp_t):
        return {"reachable": False, "detail": f"tcp_{host}_{port}_failed"}

    if provider == "openai":
        url = "https://api.openai.com/v1/models"
        headers = {"Authorization": f"Bearer {api_key}"}
    elif provider == "deepseek":
        url = "https://api.deepseek.com/v1/models"
        headers = {"Authorization": f"Bearer {api_key}"}
    elif provider == "groq":
        url = "https://api.groq.com/openai/v1/models"
        headers = {"Authorization": f"Bearer {api_key}"}
    elif provider == "anthropic":
        url = "https://api.anthropic.com/v1/models"
        headers = {"x-api-key": api_key, "anthropic-version": "2023-06-01"}
    elif provider == "gemini":
        url = f"https://generativelanguage.googleapis.com/v1beta/models?key={api_key}"
        headers = {}
    else:
        return {"reachable": True, "detail": "tcp_ok"}

    http_t = min(t, 4.0)
    ok, detail = _http_probe(url, headers, http_t)
    return {"reachable": ok, "detail": detail}


def probe_enabled() -> bool:
    return os.environ.get("GOAL_REVIEW_PROBE", "1") != "0"


def annotate_candidates(candidates: list[dict[str, Any]], key_lookup) -> list[dict[str, Any]]:
    """Annotate candidates with reachable flag. key_lookup(provider)->api_key.

    Probes unique providers in parallel; total wall clock ~ one probe timeout, not N×timeout.
    """
    if not probe_enabled():
        for c in candidates:
            c.setdefault("reachable", True)
            c.setdefault("reachability", {"skipped": True})
        return candidates

    from concurrent.futures import ThreadPoolExecutor, as_completed

    providers = sorted({str(c.get("provider") or "") for c in candidates if c.get("provider")})
    results: dict[str, dict[str, Any]] = {}

    def _one(prov: str) -> tuple[str, dict[str, Any]]:
        if prov == "ollama":
            return prov, probe_provider("ollama", "")
        return prov, probe_provider(prov, key_lookup(prov) or "")

    # Cap workers; hard deadline so a wedged TLS call cannot stall detect for tens of seconds.
    deadline = min(10.0, max(DEFAULT_PROBE_TIMEOUT_SEC + 1.0, 6.0))
    pool = ThreadPoolExecutor(max_workers=min(6, max(1, len(providers))))
    futs = {pool.submit(_one, p): p for p in providers if p}
    try:
        for fut in as_completed(futs, timeout=deadline):
            prov, info = fut.result()
            results[prov] = info
    except TimeoutError:
        for fut, prov in futs.items():
            if prov not in results:
                results[prov] = {"reachable": False, "detail": "probe_deadline_exceeded"}
    finally:
        # Do not wait for wedged TLS threads — cancel and return immediately.
        try:
            pool.shutdown(wait=False, cancel_futures=True)
        except TypeError:
            pool.shutdown(wait=False)

    for c in candidates:
        prov = str(c.get("provider") or "")
        info = results.get(prov) or {"reachable": False, "detail": "probe_missing"}
        c["reachable"] = bool(info.get("reachable"))
        c["reachability"] = info
    return candidates


def is_infra_error_text(text: str) -> bool:
    s = (text or "").lower()
    needles = (
        "timeout",
        "timed out",
        "connection refused",
        "connection reset",
        "network is unreachable",
        "name or service not known",
        "temporary failure in name resolution",
        "ssl",
        "tls",
        "empty_content",
        "fallback_exhausted",
        "review_channel_unreachable",
        "adapter_timeout",
        "unreachable",
        "http error",
        "urlerror",
    )
    return any(n in s for n in needles)


def issue_is_infra(issue: dict[str, Any]) -> bool:
    iid = str(issue.get("id") or "").upper()
    if iid.startswith("ADP-ERR") or iid in ("FB-EXHAUST", "CH-UNREACHABLE", "CH-PROBE"):
        return True
    root = str(issue.get("root_cause") or "").lower()
    if root in ("infra_channel", "infra", "review_channel", "network"):
        return True
    blob = " ".join(
        str(issue.get(k) or "")
        for k in ("summary", "evidence", "error", "error_kind", "suggestion")
    )
    return is_infra_error_text(blob)


if __name__ == "__main__":
    # tiny CLI for manual probing
    import sys

    prov = sys.argv[1] if len(sys.argv) > 1 else "deepseek"
    key = os.environ.get(
        {
            "deepseek": "DEEPSEEK_API_KEY",
            "gemini": "GEMINI_API_KEY",
            "openai": "OPENAI_API_KEY",
            "anthropic": "ANTHROPIC_API_KEY",
            "groq": "GROQ_API_KEY",
        }.get(prov, ""),
        "",
    )
    print(json.dumps(probe_provider(prov, key), ensure_ascii=False))
