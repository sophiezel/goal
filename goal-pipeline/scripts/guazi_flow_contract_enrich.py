#!/usr/bin/env python3
"""B3: append Goal contract sections to index.md; persist guazi_flow_contract_enriched."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

GOAL_HEADING = "## Goal 契约"
SUB_ALLOWED = "### allowed_patterns"
SUB_EXCLUSIONS = "### exclusions"
SUB_STOP = "### stop_conditions"

_DEFAULT_STOP = [
    "需要新增未声明外部依赖时停止",
    "修改超出 Allowed Files 范围时停止",
]


@dataclass
class EnrichResult:
    ok: bool
    enriched: bool
    reason: str = ""
    warnings: list[str] | None = None


def _list_from_state(state: dict[str, Any]) -> tuple[list[str], list[str], list[str]]:
    goal = state.get("goal") if isinstance(state.get("goal"), dict) else {}
    allowed = state.get("allowed_files") or goal.get("allowed_files") or []
    exclusions = state.get("out_of_scope") or goal.get("out_of_scope") or []
    stops = state.get("stop_conditions") or goal.get("stop_conditions") or []
    if isinstance(allowed, str):
        allowed = [allowed]
    if isinstance(exclusions, str):
        exclusions = [exclusions]
    if isinstance(stops, str):
        stops = [stops]
    return [str(x).strip() for x in allowed if str(x).strip()], [
        str(x).strip() for x in exclusions if str(x).strip()
    ], [str(x).strip() for x in stops if str(x).strip()]


def _write_set_from_plan(plan: dict[str, Any] | None) -> list[str]:
    if not plan:
        return []
    ws = plan.get("write_set") or []
    if not isinstance(ws, list):
        return []
    return [str(p).strip() for p in ws if str(p).strip()]


def _parse_write_set_from_index(text: str) -> list[str]:
    m = re.search(
        r"(?:^##\s*(?:write_set|写集|范围与写集)\s*$)(.+?)(?=^##\s|\Z)",
        text,
        re.MULTILINE | re.DOTALL | re.IGNORECASE,
    )
    if not m:
        return []
    paths: list[str] = []
    for line in m.group(1).splitlines():
        line = line.strip().lstrip("-*•").strip()
        if not line or line.startswith("#"):
            continue
        line = re.sub(r"^\d+\.\s*", "", line)
        token = line.split()[0] if line else ""
        if token and not token.startswith("`"):
            paths.append(token.strip("`"))
        elif token.startswith("`"):
            paths.append(token.strip("`"))
    return paths


def _has_subsection(text: str, heading: str) -> bool:
    if heading not in text:
        return False
    idx = text.index(heading)
    tail = text[idx + len(heading) :]
    body = tail.split("\n##", 1)[0]
    return bool(re.search(r"^\s*[-*]", body, re.MULTILINE))


def _contract_complete(text: str) -> bool:
    return _has_subsection(text, SUB_ALLOWED) and _has_subsection(text, SUB_EXCLUSIONS) and _has_subsection(
        text, SUB_STOP
    )


def _bullets(items: list[str]) -> str:
    if not items:
        return "- (none declared)\n"
    return "".join(f"- {line}\n" for line in items)


def _append_contract_block(text: str, allowed: list[str], exclusions: list[str], stops: list[str]) -> str:
    if _contract_complete(text):
        return text
    parts: list[str] = []
    if GOAL_HEADING not in text:
        parts.append(GOAL_HEADING)
    if not _has_subsection(text, SUB_ALLOWED):
        parts.append(f"{SUB_ALLOWED}\n\n{_bullets(allowed)}")
    if not _has_subsection(text, SUB_EXCLUSIONS):
        parts.append(f"{SUB_EXCLUSIONS}\n\n{_bullets(exclusions)}")
    if not _has_subsection(text, SUB_STOP):
        parts.append(f"{SUB_STOP}\n\n{_bullets(stops or _DEFAULT_STOP)}")
    if not parts:
        return text
    return text.rstrip() + "\n\n" + "\n\n".join(parts) + "\n"


def load_profile_policy(profile_id: str | None, plan: dict[str, Any] | None) -> str:
    pid = profile_id or "default"
    if plan:
        pid = str(plan.get("pipeline_profile") or plan.get("profile") or pid)
    root = Path(__file__).resolve().parents[1]
    path = root / "references" / "profiles" / pid / "pipeline.profile.json"
    policy = "block"
    if path.is_file():
        try:
            doc = json.loads(path.read_text(encoding="utf-8"))
            ce = doc.get("contract_enrich") or {}
            if isinstance(ce, dict) and ce.get("policy"):
                policy = str(ce["policy"]).lower()
            elif doc.get("contract_enrich_policy"):
                policy = str(doc["contract_enrich_policy"]).lower()
        except (OSError, json.JSONDecodeError):
            pass
    return policy


def enrich_index(
    index_path: Path,
    *,
    state: dict[str, Any] | None = None,
    plan: dict[str, Any] | None = None,
    policy: str = "block",
) -> EnrichResult:
    if not index_path.is_file():
        return EnrichResult(ok=False, enriched=False, reason="index.md missing")

    text = index_path.read_text(encoding="utf-8")
    if _contract_complete(text):
        return EnrichResult(ok=True, enriched=True, reason="already_present")

    state = state or {}
    allowed, exclusions, stops = _list_from_state(state)
    if not allowed:
        allowed = _write_set_from_plan(plan) or _parse_write_set_from_index(text)
    if not allowed:
        msg = "no allowed_files or write_set to enrich Goal contract"
        if policy == "waive":
            return EnrichResult(ok=True, enriched=False, reason=msg, warnings=[msg])
        return EnrichResult(ok=False, enriched=False, reason=msg)

    if not exclusions:
        exclusions = ["(derive from index scope / out-of-scope sections)"]
    if not stops:
        stops = list(_DEFAULT_STOP)

    try:
        new_text = _append_contract_block(text, allowed, exclusions, stops)
        index_path.write_text(new_text, encoding="utf-8")
    except OSError as e:
        return EnrichResult(ok=False, enriched=False, reason=str(e))

    return EnrichResult(ok=True, enriched=True, reason="appended_goal_contract")


def persist_state_flag(state_path: Path, enriched: bool, *, waived: bool = False) -> None:
    script_dir = Path(__file__).resolve().parent
    sys.path.insert(0, str(script_dir))
    from atomic_json import write_state_atomic  # noqa: WPS433

    doc = json.loads(state_path.read_text(encoding="utf-8"))
    doc["guazi_flow_contract_enriched"] = bool(enriched)
    if waived:
        w2 = doc.setdefault("w2_notes", [])
        if isinstance(w2, list):
            note = "contract_enrich_waived (B3 profile waive)"
            if note not in w2:
                w2.append(note)
    write_state_atomic(str(state_path), doc)


def implement_pre_allowed(
    index_path: Path,
    plan: dict[str, Any] | None,
    state: dict[str, Any] | None,
    policy: str = "block",
) -> tuple[bool, str]:
    if policy == "waive":
        return True, "waived"
    state = state or {}
    plan = plan or {}
    if state.get("guazi_flow_contract_enriched") is False:
        return False, "guazi_flow_contract_enriched=false"
    if plan.get("contract_enriched") is True:
        return True, "plan.contract_enriched"
    if index_path.is_file():
        text = index_path.read_text(encoding="utf-8")
        if _contract_complete(text):
            return True, "index_contract_complete"
    if plan.get("contract_enriched") is None and state.get("guazi_flow_contract_enriched") is None:
        if _write_set_from_plan(plan) or (index_path.is_file() and _parse_write_set_from_index(index_path.read_text(encoding="utf-8"))):
            return True, "legacy_handoff_pending_replan"
    return False, "contract_enrich_required"


def main() -> int:
    ap = argparse.ArgumentParser(description="Goal contract enrich into index.md (B3)")
    ap.add_argument("--task-dir", type=Path, default=None)
    ap.add_argument("--index", type=Path, default=None)
    ap.add_argument("--plan-json", type=Path, default=None)
    ap.add_argument("--state-file", type=Path, default=None)
    ap.add_argument("--profile", default=None)
    ap.add_argument("--check-implement-pre", action="store_true")
    ap.add_argument("--format", choices=("json", "text"), default="json")
    args = ap.parse_args()

    if args.check_implement_pre:
        if not args.task_dir and not args.plan_json:
            print(json.dumps({"ok": False, "error": "task-dir or plan-json required"}), file=sys.stderr)
            return 2
        task_dir = args.task_dir or Path(".")
        index = args.index or (task_dir / "index.md")
        plan_path = args.plan_json or (task_dir / "handoff" / "plan.json")
        plan = json.loads(plan_path.read_text(encoding="utf-8")) if plan_path.is_file() else {}
        state = None
        if args.state_file and args.state_file.is_file():
            state = json.loads(args.state_file.read_text(encoding="utf-8"))
        policy = load_profile_policy(args.profile, plan)
        ok, reason = implement_pre_allowed(index, plan, state, policy)
        print(json.dumps({"ok": ok, "reason": reason, "policy": policy}, ensure_ascii=False))
        return 0 if ok else 1

    if not args.task_dir:
        print(json.dumps({"ok": False, "error": "--task-dir required"}), file=sys.stderr)
        return 2
    index = args.index or (args.task_dir / "index.md")
    plan_path = args.plan_json or (args.task_dir / "handoff" / "plan.json")
    plan = None
    if plan_path.is_file():
        plan = json.loads(plan_path.read_text(encoding="utf-8"))

    state: dict[str, Any] | None = None
    if args.state_file and args.state_file.is_file():
        state = json.loads(args.state_file.read_text(encoding="utf-8"))

    policy = load_profile_policy(args.profile, plan)
    result = enrich_index(index, state=state, plan=plan, policy=policy)

    out = {
        "ok": result.ok,
        "enriched": result.enriched,
        "reason": result.reason,
        "policy": policy,
        "warnings": result.warnings or [],
    }

    if args.state_file and args.state_file.is_file():
        flag = result.enriched or result.reason == "already_present"
        if not result.ok:
            flag = False
        persist_state_flag(
            args.state_file,
            flag,
            waived=bool(result.warnings) and policy == "waive" and result.ok,
        )

    if args.format == "text":
        print(result.reason)
    else:
        print(json.dumps(out, ensure_ascii=False))

    return 0 if result.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
