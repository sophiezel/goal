"""Resolve engineering_pack (optimization-spec v1.2 Part K)."""

from __future__ import annotations

from typing import Any

from kernel.profile.stage_graph import DEFAULT_PROFILE_ID, load_profile_document

ENGINEERING_PACK_VALUES = frozenset({"none", "grill", "to_specs", "grill_to_specs"})

# Agent skill names (goal-pipeline/skills/goal-engineering/*); not English marketplace SSOT.
PACK_TO_SKILL_NAMES: dict[str, tuple[str, ...]] = {
    "none": (),
    "grill": ("goal-engineering-grill",),
    "to_specs": ("goal-engineering-to-specs",),
    "grill_to_specs": ("goal-engineering-grill", "goal-engineering-to-specs"),
}

SKILL_NAME_TO_SUBDIR: dict[str, str] = {
    "goal-engineering-grill": "grill",
    "goal-engineering-to-specs": "to-specs",
}

SKILL_REPO_ROOT = "goal-pipeline/skills/goal-engineering"


def normalize_pack(raw: str | None) -> str:
    if raw is None or str(raw).strip() == "":
        return "none"
    val = str(raw).strip()
    if val not in ENGINEERING_PACK_VALUES:
        raise ValueError(
            f"engineering_pack {val!r} invalid; expected one of {sorted(ENGINEERING_PACK_VALUES)}"
        )
    return val


def resolve_engineering_pack(
    *,
    profile_id: str | None = None,
    plan_json: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Return pack enum + skill names for Phase 1 soft-load (plan stage only)."""
    pid = DEFAULT_PROFILE_ID
    if plan_json:
        pid = str(plan_json.get("pipeline_profile") or plan_json.get("profile") or pid)
    if profile_id:
        pid = profile_id

    pack_raw: str | None = None
    source = f"profile:{pid}"
    if plan_json and plan_json.get("engineering_pack") is not None:
        pack_raw = str(plan_json.get("engineering_pack"))
        source = "plan.json"
    else:
        doc = load_profile_document(pid)
        if doc.get("engineering_pack") is not None:
            pack_raw = str(doc.get("engineering_pack"))

    pack = normalize_pack(pack_raw)
    skills = list(PACK_TO_SKILL_NAMES[pack])
    skill_paths = [
        f"{SKILL_REPO_ROOT}/{SKILL_NAME_TO_SUBDIR[s]}/SKILL.md"
        for s in skills
    ]
    return {
        "profile_id": pid,
        "engineering_pack": pack,
        "source": source,
        "skills_to_load": skills,
        "skill_paths": skill_paths,
    }


def merge_plan_phase_skills(
    primary_skill: str | None,
    engineering_doc: dict[str, Any],
) -> list[str]:
    """Primary plan skill first, then pack skills (deduped)."""
    out: list[str] = []
    if primary_skill:
        out.append(primary_skill)
    for s in engineering_doc.get("skills_to_load") or []:
        if s and s not in out:
            out.append(s)
    return out
