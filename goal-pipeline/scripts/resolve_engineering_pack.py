#!/usr/bin/env python3
"""CLI: resolve engineering_pack (v1.2 Part K) from profile / plan.json."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_ROOT))

from kernel.profile.engineering_pack import resolve_engineering_pack  # noqa: E402


def _read_plan(path: Path | None) -> dict | None:
    if not path or not path.is_file():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    p = argparse.ArgumentParser(description="Resolve engineering_pack for Phase 1 soft-load")
    p.add_argument("--profile", default=None)
    p.add_argument("--plan-json", type=Path, default=None)
    p.add_argument("--task-dir", type=Path, default=None)
    p.add_argument("--validate-stubs", action="store_true", help="ensure SKILL.md stubs exist on disk")
    args = p.parse_args()

    plan_path = args.plan_json
    if args.task_dir and not plan_path:
        plan_path = args.task_dir / "handoff" / "plan.json"
    plan = _read_plan(plan_path)

    try:
        doc = resolve_engineering_pack(profile_id=args.profile, plan_json=plan)
    except (OSError, ValueError, json.JSONDecodeError) as e:
        print(json.dumps({"ok": False, "error": str(e)}), file=sys.stderr)
        return 2

    if args.validate_stubs:
        repo_root = _ROOT.parent
        missing: list[str] = []
        for rel in doc.get("skill_paths") or []:
            path = repo_root / rel
            if not path.is_file():
                missing.append(str(rel))
        doc["stubs_ok"] = not missing
        doc["missing_skill_paths"] = missing
        if missing:
            print(json.dumps(doc, ensure_ascii=False, indent=2))
            return 1

    print(json.dumps({"ok": True, **doc}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
