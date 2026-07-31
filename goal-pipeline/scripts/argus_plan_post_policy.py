#!/usr/bin/env python3
"""C1 fe-argus plan post policy — triggers, WO hints, advance gate (no LLM in shell)."""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

TIER_RANK = {"XS": 0, "S": 1, "M": 2, "L": 3, "XL": 4}
VALID_STATUSES = frozenset({"rule_only", "merged", "partial"})
FE_ARGUS_SKILL = "fe-argus"


def _env_truthy(name: str) -> bool:
    return os.environ.get(name, "").strip().lower() in ("1", "true", "yes", "on")


def write_set_has_pages(write_set: list[str]) -> bool:
    for p in write_set:
        norm = str(p).replace("\\", "/")
        if "src/pages/" in norm or norm.startswith("src/pages/"):
            return True
    return False


def fe_argus_skill_required(
    *,
    plan_profile: str = "full",
    task_tier: str = "",
    write_set: list[str] | None = None,
    quality_tier: str = "standard",
) -> tuple[bool, dict[str, Any]]:
    """Return (required, meta) per argus-v2-hybrid.md C1."""
    write_set = write_set or []
    meta: dict[str, Any] = {
        "plan_profile": plan_profile,
        "task_tier": task_tier,
        "quality_tier": quality_tier,
        "write_set_pages": write_set_has_pages(write_set),
        "force_env": _env_truthy("GOAL_ARGUS_SKILL_REQUIRED"),
    }
    if _env_truthy("GOAL_ARGUS_SKILL_REQUIRED"):
        meta["reason"] = "GOAL_ARGUS_SKILL_REQUIRED"
        return True, meta

    profile = (plan_profile or "full").strip().lower()
    tier = (task_tier or "").strip().upper()
    if profile == "lite" or tier == "XS":
        meta["reason"] = "lite_or_xs_exempt"
        return False, meta

    if write_set_has_pages(write_set):
        meta["reason"] = "write_set_pages"
        return True, meta

    if TIER_RANK.get(tier, 0) >= TIER_RANK["S"]:
        meta["reason"] = "task_tier_gte_s"
        return True, meta

    meta["reason"] = "not_triggered"
    return False, meta


def validate_manifest_schema(doc: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if doc.get("schema_version") != 2:
        errors.append("schema_version must be 2")
    status = doc.get("argus_enrich_status")
    if status not in VALID_STATUSES:
        errors.append(f"argus_enrich_status invalid: {status!r}")
    scenarios = doc.get("scenarios")
    if not isinstance(scenarios, list):
        errors.append("scenarios must be a list")
        return errors
    for i, row in enumerate(scenarios):
        if not isinstance(row, dict):
            errors.append(f"scenarios[{i}] must be object")
            continue
        if not str(row.get("id") or "").strip():
            errors.append(f"scenarios[{i}].id required")
        src = row.get("source")
        if src not in ("rule", "argus"):
            errors.append(f"scenarios[{i}].source must be rule|argus")
    return errors


def check_plan_post_complete(
    *,
    plan: dict[str, Any],
    manifest: dict[str, Any] | None,
    quality_tier: str = "standard",
) -> dict[str, Any]:
    """After shell step 1 + optional Agent merge — used before goal-advance-stage leaves plan."""
    required, trig = fe_argus_skill_required(
        plan_profile=str(plan.get("plan_profile") or "full"),
        task_tier=str(plan.get("task_tier") or ""),
        write_set=list(plan.get("write_set") or []),
        quality_tier=quality_tier,
    )
    out: dict[str, Any] = {
        "ok": True,
        "fe_argus_skill_required": required,
        "trigger": trig,
        "pq_warn": [],
    }
    if manifest is None:
        out["ok"] = False
        out["failure_code"] = "argus_manifest_missing"
        return out

    schema_errs = validate_manifest_schema(manifest)
    if schema_errs:
        out["ok"] = False
        out["failure_code"] = "argus_manifest_schema"
        out["errors"] = schema_errs
        return out

    status = str(manifest.get("argus_enrich_status") or "rule_only")
    if required and status == "rule_only":
        out["ok"] = False
        out["failure_code"] = "argus_fe_skill_pending"
        out["message"] = (
            "fe-argus skill merge required before leaving plan "
            "(load fe-argus, INDEX Scenario Q, merge manifest; see docs/goal-pipeline/argus-v2-hybrid.md)"
        )
        return out

    if status == "partial":
        out["pq_warn"].append(
            "argus_enrich_status=partial — document in plan PQ / index 执行记录; do not silent-pass"
        )
    return out


def work_order_argus_block(
    *,
    required: bool,
    script_dir: str,
    task_dir: str,
    handoff_dir: str,
) -> dict[str, Any]:
    """Extra WO fields + mandatory command suffixes for plan stage."""
    py = os.path.join(script_dir, "argus_enrich_plan.py")
    manifest = os.path.join(handoff_dir, "argus-scenario-manifest.json")
    pending = os.path.join(handoff_dir, "fe-argus-scenarios-pending.json")
    if not required:
        return {
            "fe_argus_plan_post": {"required": False, "skill": None},
            "skills_to_load": [],
            "argus_mandatory_suffix": [],
        }
    cmds = [
        f"Load {FE_ARGUS_SKILL}/SKILL.md — INDEX on-demand Scenario Q only (no full scenarios/ scan)",
        f"Write fe-argus scenarios to {pending!r} then merge:",
        (
            f"python3 {py!r} --task-dir {task_dir!r} --handoff-dir {handoff_dir!r} "
            f"--merge-fe-argus-file {pending!r} --merge-status merged "
            f"(on fe-argus failure use --merge-status partial and record PQ warn)"
        ),
        (
            f"python3 {os.path.join(script_dir, 'argus_plan_post_policy.py')!r} "
            f"--check-plan-post --plan-json {os.path.join(handoff_dir, 'plan.json')!r} "
            f"--manifest-json {manifest!r}"
        ),
    ]
    return {
        "fe_argus_plan_post": {
            "required": True,
            "skill": FE_ARGUS_SKILL,
            "after": "gate_plan_post_shell_step1",
            "manifest_path": manifest,
        },
        "skills_to_load": [FE_ARGUS_SKILL],
        "skill_to_load_co": FE_ARGUS_SKILL,
        "argus_mandatory_suffix": cmds,
    }


def _read_index_text(task_dir: Path) -> str:
    index = task_dir / "index.md"
    return index.read_text(encoding="utf-8") if index.is_file() else ""


def _plan_profile_from_index(text: str) -> str:
    m = re.search(r"plan_profile:\s*(\w+)", text, re.I)
    return (m.group(1) if m else "full").strip().lower()


def _write_set_from_index(text: str) -> list[str]:
    import re as _re

    paths: list[str] = []
    m = _re.search(
        r"(?:##\s*(?:write_set|写集|范围与写集)|write_set\s*[:：])\s*\n([\s\S]*?)(?:\n##|\Z)",
        text,
        _re.I,
    )
    if not m:
        return paths
    for line in m.group(1).splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        for tok in _re.findall(r"`([^`]+)`", line):
            paths.append(tok.strip())
        m2 = _re.match(r"[-*]\s+(.+)", line)
        if m2:
            val = m2.group(1).strip().strip("`")
            if val and "/" in val:
                paths.append(val.split()[0] if " " in val else val)
    return list(dict.fromkeys(paths))


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def fe_argus_required_for_task(task_dir: Path) -> tuple[bool, dict[str, Any]]:
    """Best-effort trigger before/after plan.json exists."""
    handoff_plan = task_dir / "handoff" / "plan.json"
    if handoff_plan.is_file():
        plan = load_json(handoff_plan)
        return fe_argus_skill_required(
            plan_profile=str(plan.get("plan_profile") or "full"),
            task_tier=str(plan.get("task_tier") or ""),
            write_set=list(plan.get("write_set") or []),
        )
    text = _read_index_text(task_dir)
    return fe_argus_skill_required(
        plan_profile=_plan_profile_from_index(text),
        task_tier="",
        write_set=_write_set_from_index(text),
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan-json", default="")
    ap.add_argument("--manifest-json", default="")
    ap.add_argument("--quality-tier", default="")
    ap.add_argument("--check-plan-post", action="store_true")
    ap.add_argument("--check-advance", action="store_true")
    ap.add_argument("--resolve-trigger", action="store_true")
    ap.add_argument("--work-order-json", action="store_true")
    ap.add_argument("--script-dir", default="")
    ap.add_argument("--task-dir", default="")
    ap.add_argument("--handoff-dir", default="")
    ap.add_argument("--resolve-from-task-dir", action="store_true")
    args = ap.parse_args()

    if args.resolve_from_task_dir:
        if not args.task_dir:
            print(json.dumps({"error": "task-dir required"}), file=sys.stderr)
            return 2
        required, trig = fe_argus_required_for_task(Path(args.task_dir).resolve())
        print(json.dumps({"fe_argus_skill_required": required, "trigger": trig}, ensure_ascii=False))
        return 0

    if args.resolve_trigger or args.work_order_json:
        if args.work_order_json and args.task_dir and not args.plan_json:
            td = Path(args.task_dir).resolve()
            required, trig = fe_argus_required_for_task(td)
            if args.resolve_trigger:
                print(json.dumps({"fe_argus_skill_required": required, "trigger": trig}, ensure_ascii=False))
                return 0
            handoff = args.handoff_dir or str(td / "handoff")
            block = work_order_argus_block(
                required=required,
                script_dir=args.script_dir or str(Path(__file__).resolve().parent),
                task_dir=str(td),
                handoff_dir=handoff,
            )
            print(json.dumps(block, ensure_ascii=False, indent=2))
            return 0
        if not args.plan_json:
            print(json.dumps({"error": "plan-json required"}), file=sys.stderr)
            return 2
        plan = load_json(Path(args.plan_json))
        qt = args.quality_tier or os.environ.get("GOAL_QUALITY_TIER", "standard")
        required, trig = fe_argus_skill_required(
            plan_profile=str(plan.get("plan_profile") or "full"),
            task_tier=str(plan.get("task_tier") or ""),
            write_set=list(plan.get("write_set") or []),
            quality_tier=qt,
        )
        if args.resolve_trigger:
            print(json.dumps({"fe_argus_skill_required": required, "trigger": trig}, ensure_ascii=False))
            return 0
        block = work_order_argus_block(
            required=required,
            script_dir=args.script_dir or str(Path(__file__).resolve().parent),
            task_dir=args.task_dir or str(plan.get("task_dir") or ""),
            handoff_dir=args.handoff_dir or str(Path(args.plan_json).parent),
        )
        print(json.dumps(block, ensure_ascii=False, indent=2))
        return 0

    if args.check_plan_post or args.check_advance:
        if not args.plan_json:
            print(json.dumps({"ok": False, "error": "plan-json required"}), file=sys.stderr)
            return 2
        plan = load_json(Path(args.plan_json))
        manifest = None
        if args.manifest_json and Path(args.manifest_json).is_file():
            manifest = load_json(Path(args.manifest_json))
        qt = args.quality_tier or os.environ.get("GOAL_QUALITY_TIER", "standard")
        result = check_plan_post_complete(plan=plan, manifest=manifest, quality_tier=qt)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result.get("ok") else 1

    ap.print_help()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
