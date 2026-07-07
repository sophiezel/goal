#!/usr/bin/env python3
"""platform_review_adapter_core — HTTP backends for unified independent review."""
import json
import os
import sys
import urllib.error
import urllib.request

UNIFIED_PROMPT_PATH = os.path.join(os.path.dirname(__file__), "..", "references", "unified-review-prompt.md")
GOAL_PROMPT_PATH = os.path.join(os.path.dirname(__file__), "..", "references", "review-packet-prompt.md")

UNIFIED_OUTPUT_HINT = """
Return JSON only with keys:
schema_version, result, checklist_goal, checklist_gf, issues, root_cause_summary (optional).
Each issue must have channel (goal|guazi-flow-review), severity, summary; blockers need file+evidence.
"""


def load_config():
    cfg_path = os.path.expanduser(os.environ.get("GOAL_STATE_HOME", "~/.goal-state") + "/config.json")
    try:
        return json.load(open(cfg_path, encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def api_key_for(provider, cfg):
    mapping = {
        "openai": "OPENAI_API_KEY",
        "anthropic": "ANTHROPIC_API_KEY",
        "deepseek": "DEEPSEEK_API_KEY",
        "gemini": "GEMINI_API_KEY",
        "groq": "GROQ_API_KEY",
    }
    env = mapping.get(provider, "")
    if env and os.environ.get(env):
        return os.environ[env]
    return (cfg.get("api_keys") or {}).get(env, "")


def http_json(url, headers, body, timeout=120):
    req = urllib.request.Request(url, data=json.dumps(body).encode("utf-8"), headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def call_openai_compat(base_url, api_key, model, system, user, provider_label):
    url = base_url.rstrip("/") + "/chat/completions"
    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    body = {
        "model": model,
        "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
        "temperature": 0.1,
        "response_format": {"type": "json_object"},
    }
    data = http_json(url, headers, body)
    text = data["choices"][0]["message"]["content"]
    out = json.loads(text)
    out.setdefault("model", model)
    out.setdefault("tokens", data.get("usage", {}))
    out["provider"] = provider_label
    return out


def call_anthropic(api_key, model, system, user):
    url = "https://api.anthropic.com/v1/messages"
    headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "Content-Type": "application/json",
    }
    body = {
        "model": model,
        "max_tokens": 4096,
        "system": system,
        "messages": [{"role": "user", "content": user}],
    }
    data = http_json(url, headers, body)
    text = data["content"][0]["text"]
    out = json.loads(text)
    out.setdefault("model", model)
    out.setdefault("tokens", data.get("usage", {}))
    out["provider"] = "anthropic"
    return out


def call_gemini(api_key, model, system, user):
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
    headers = {"Content-Type": "application/json"}
    body = {
        "contents": [{"parts": [{"text": system + "\n\n" + user}]}],
        "generationConfig": {"temperature": 0.1, "responseMimeType": "application/json"},
    }
    data = http_json(url, headers, body)
    text = data["candidates"][0]["content"]["parts"][0]["text"]
    out = json.loads(text)
    out.setdefault("model", model)
    out["provider"] = "gemini"
    return out


def call_ollama(model, system, user):
    url = "http://127.0.0.1:11434/api/chat"
    body = {
        "model": model,
        "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
        "stream": False,
        "format": "json",
    }
    req = urllib.request.Request(url, data=json.dumps(body).encode("utf-8"), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=180) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    text = data["message"]["content"]
    out = json.loads(text)
    out.setdefault("model", model)
    out["provider"] = "ollama"
    return out


def _read_prompt(path, fallback=""):
    if os.path.isfile(path):
        return open(path, encoding="utf-8").read()
    return fallback


def build_unified_prompt(packet, diff_budget=60000):
    """Structured prompt: metadata + checklists + diff (separate byte budget)."""
    parts = []
    prompt_doc = _read_prompt(UNIFIED_PROMPT_PATH, UNIFIED_OUTPUT_HINT)
    parts.append(prompt_doc[:5000])
    parts.append(UNIFIED_OUTPUT_HINT)

    changed = packet.get("changed_files") or []
    if changed:
        parts.append("\n## changed_files\n" + json.dumps(changed[:200], ensure_ascii=False))

    det = packet.get("deterministic_checks") or {}
    if det:
        parts.append("\n## deterministic_checks\n" + json.dumps(det, ensure_ascii=False)[:4000])

    goal_cl = packet.get("goal_checklist") or []
    if goal_cl:
        parts.append("\n## goal_checklist (Part A)\n" + json.dumps(goal_cl, ensure_ascii=False)[:4000])

    gf = packet.get("guazi_flow_rubric") or {}
    if gf and any(gf.values()):
        parts.append("\n## guazi_flow_rubric (Part B)\n" + json.dumps(gf, ensure_ascii=False)[:6000])

    vc = packet.get("verification_checklist") or []
    if vc:
        parts.append("\n## verification_checklist IDs\n" + json.dumps(vc[:100], ensure_ascii=False))

    contract = packet.get("contract") or {}
    if contract.get("acceptance_matrix"):
        parts.append("\n## acceptance_matrix excerpt\n" + str(contract.get("acceptance_matrix", ""))[:3000])

    diff_text = packet.get("diff") or ""
    diff_bytes = diff_text.encode("utf-8")
    if len(diff_bytes) > diff_budget:
        diff_text = diff_bytes[:diff_budget].decode("utf-8", errors="ignore") + "\n...[diff truncated]..."
    parts.append("\n## diff\n" + diff_text)

    meta = {
        "task_dir": packet.get("task_dir", ""),
        "hashes": packet.get("hashes", {}),
        "constraints": packet.get("constraints", {}),
    }
    parts.append("\n## packet_meta\n" + json.dumps(meta, ensure_ascii=False)[:3000])
    return "\n".join(parts)


def build_goal_prompt(packet):
    prompt_ref = _read_prompt(GOAL_PROMPT_PATH, "")[:4000]
    packet_s = json.dumps(packet, ensure_ascii=False)[:14000]
    return prompt_ref + "\n\nPacket:\n" + packet_s


def build_user_prompt(packet, channel):
    if channel == "unified":
        return build_unified_prompt(packet)
    return build_goal_prompt(packet)


def normalize_unified_out(out, packet):
    out.setdefault("schema_version", 1)
    out.setdefault("checklist_goal", [])
    out.setdefault("checklist_gf", [])
    out.setdefault("issues", [])
    rubric = packet.get("guazi_flow_rubric") or {}
    has_gf = bool(rubric and any(rubric.values()))
    out["gf_skill_attested"] = has_gf
    if "result" not in out:
        blockers = [i for i in out.get("issues", []) if i.get("severity") == "blocker"]
        out["result"] = "not_pass" if blockers else "pass"
    return out


def invoke(provider, model, packet, channel):
    cfg = load_config()
    system = "Return valid JSON only. No markdown fences."
    user = build_user_prompt(packet, channel)
    key = api_key_for(provider, cfg)
    bases = {
        "openai": "https://api.openai.com/v1",
        "deepseek": "https://api.deepseek.com/v1",
        "groq": "https://api.groq.com/openai/v1",
    }
    if provider == "anthropic":
        if not key:
            raise RuntimeError("ANTHROPIC_API_KEY missing")
        out = call_anthropic(key, model or "claude-haiku-4-5", system, user)
    elif provider == "gemini":
        if not key:
            raise RuntimeError("GEMINI_API_KEY missing")
        out = call_gemini(key, model or "gemini-2.0-flash", system, user)
    elif provider == "ollama":
        out = call_ollama(model or "llama3.2", system, user)
    elif provider in bases:
        if not key:
            raise RuntimeError(f"{provider} API key missing")
        out = call_openai_compat(bases[provider], key, model or "gpt-4o-mini", system, user, provider)
    else:
        raise RuntimeError(f"unsupported provider: {provider}")

    if channel == "unified":
        return normalize_unified_out(out, packet)
    return out


def main():
    import argparse

    p = argparse.ArgumentParser()
    p.add_argument("--provider", required=True)
    p.add_argument("--model", default="")
    p.add_argument("--packet", required=True)
    p.add_argument("--channel", default="unified", choices=["goal", "unified"])
    args = p.parse_args()
    packet = json.load(open(args.packet, encoding="utf-8"))
    out = invoke(args.provider, args.model, packet, args.channel)
    print(json.dumps(out, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(
            json.dumps(
                {
                    "result": "review_undetermined",
                    "issues": [{"id": "ADP-ERR", "severity": "medium", "summary": str(e)[:200], "channel": "goal"}],
                    "checklist_goal": [],
                    "checklist_gf": [],
                    "error": str(e),
                }
            )
        )
        sys.exit(0)
