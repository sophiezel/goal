"""Resolve workflow_profile (optimization-spec v1.3 Part P)."""

from __future__ import annotations

from typing import Any

from kernel.profile.stage_graph import DEFAULT_PROFILE_ID, load_profile_document

WORKFLOW_PROFILE_VALUES = frozenset({"spec_path", "prototype_path", "hybrid"})

# Allowed engineering_pack subsets per workflow (soft-load guidance)
WORKFLOW_ALLOWED_PACKS: dict[str, frozenset[str]] = {
    "spec_path": frozenset(
        {"none", "grill", "to_specs", "grill_to_specs", "full_matt"}
    ),
    "prototype_path": frozenset(
        {"none", "grill", "prototype", "handoff", "full_matt"}
    ),
    "hybrid": frozenset(
        {
            "none",
            "grill",
            "to_specs",
            "grill_to_specs",
            "prototype",
            "handoff",
            "full_matt",
        }
    ),
}


def normalize_workflow_profile(raw: str | None) -> str:
    if raw is None or str(raw).strip() == "":
        return "hybrid"
    val = str(raw).strip()
    if val not in WORKFLOW_PROFILE_VALUES:
        raise ValueError(
            f"workflow_profile {val!r} invalid; expected one of {sorted(WORKFLOW_PROFILE_VALUES)}"
        )
    return val


def resolve_workflow_profile(
    *,
    profile_id: str | None = None,
    plan_json: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Return workflow_profile enum + allowed engineering_pack values."""
    pid = DEFAULT_PROFILE_ID
    if plan_json:
        pid = str(plan_json.get("pipeline_profile") or plan_json.get("profile") or pid)
    if profile_id:
        pid = profile_id

    wf_raw: str | None = None
    source = f"profile:{pid}"
    if plan_json and plan_json.get("workflow_profile") is not None:
        wf_raw = str(plan_json.get("workflow_profile"))
        source = "plan.json"
    else:
        doc = load_profile_document(pid)
        if doc.get("workflow_profile") is not None:
            wf_raw = str(doc.get("workflow_profile"))

    workflow_profile = normalize_workflow_profile(wf_raw)
    return {
        "profile_id": pid,
        "workflow_profile": workflow_profile,
        "source": source,
        "allowed_engineering_packs": sorted(WORKFLOW_ALLOWED_PACKS[workflow_profile]),
    }
