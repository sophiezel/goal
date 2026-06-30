#!/usr/bin/env python3
"""platform_review_adapter_core — HTTP backends for independent dual-channel review."""
import json, os, sys, urllib.request, urllib.error

PROMPT_PATH = os.path.join(os.path.dirname(__file__), "..", "references", "review-packet-prompt.md")

GF_RUBRIC = """You are guazi-flow-review. Evaluate against acceptance matrix and pseudocode.
Output JSON only: {"result":"pass|not_pass","issues":[{"id":"GF01","severity":"blocker|warning","summary":"...","file":"","line_range":"","suggestion":"","root_cause":"implement_error|plan_gap|spec_ambiguity"}],"checklist":[],"model":"...","tokens":{}}
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


def build_user_prompt(packet, channel):
    packet_s = json.dumps(packet, ensure_ascii=False)[:14000]
    if channel == "guazi-flow-review":
        return GF_RUBRIC + "\nPacket:\n" + packet_s
    prompt_ref = ""
    if os.path.isfile(PROMPT_PATH):
        prompt_ref = open(PROMPT_PATH, encoding="utf-8").read()[:4000]
    return prompt_ref + "\n\nPacket:\n" + packet_s


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
        return call_anthropic(key, model or "claude-haiku-4-5", system, user)
    if provider == "gemini":
        if not key:
            raise RuntimeError("GEMINI_API_KEY missing")
        return call_gemini(key, model or "gemini-2.0-flash", system, user)
    if provider == "ollama":
        return call_ollama(model or "llama3.2", system, user)
    if provider in bases:
        if not key:
            raise RuntimeError(f"{provider} API key missing")
        return call_openai_compat(bases[provider], key, model or "gpt-4o-mini", system, user, provider)
    raise RuntimeError(f"unsupported provider: {provider}")


def main():
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("--provider", required=True)
    p.add_argument("--model", default="")
    p.add_argument("--packet", required=True)
    p.add_argument("--channel", default="goal", choices=["goal", "guazi-flow-review", "dual"])
    args = p.parse_args()
    packet = json.load(open(args.packet, encoding="utf-8"))
    if args.channel == "dual":
        goal = invoke(args.provider, args.model, packet, "goal")
        gf = invoke(args.provider, args.model, packet, "guazi-flow-review")
        gf["skill"] = "guazi-flow-review"
        gf["skill_attested"] = True
        print(json.dumps({"goal": goal, "guazi-flow-review": gf}, ensure_ascii=False))
        return
    out = invoke(args.provider, args.model, packet, args.channel)
    if args.channel == "guazi-flow-review":
        out["skill"] = "guazi-flow-review"
        out["skill_attested"] = True
    print(json.dumps(out, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(json.dumps({"result": "review_undetermined", "issues": [{"id": "ADP-ERR", "severity": "medium", "summary": str(e)[:200]}], "checklist": [], "error": str(e)}))
        sys.exit(0)
