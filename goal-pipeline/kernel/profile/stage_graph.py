"""Resolve profile stage_graph (optimization-spec v1.2 Part J)."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

DEFAULT_PROFILE_ID = "default"

# v1.1 Part F.2 primary r_layer per stage id (default profile equivalence).
F2_PRIMARY_R_LAYER: dict[str, str] = {
    "plan": "R1",
    "implement": "R3",
    "quality": "R3",
    "review": "R4",
    "complete": "R4",
}

DEFAULT_STAGE_IDS: tuple[str, ...] = (
    "plan",
    "implement",
    "quality",
    "review",
    "complete",
)

# Aliases used by advance/gate (smoke → quality graph node).
STAGE_ID_ALIASES: dict[str, str] = {
    "smoke": "quality",
    "runtime_smoke": "quality",
}


def _goal_pipeline_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _profile_path(profile_id: str) -> Path:
    return _goal_pipeline_root() / "references" / "profiles" / profile_id / "pipeline.profile.json"


def _normalize_node(raw: dict[str, Any]) -> dict[str, Any]:
    sid = str(raw.get("id") or "").strip()
    gate_id = str(raw.get("gate_stage_id") or sid).strip()
    r_layer = str(raw.get("r_layer") or "").strip()
    if not sid or not gate_id or not r_layer:
        raise ValueError(f"stage_graph node missing id/r_layer/gate_stage_id: {raw!r}")
    node: dict[str, Any] = {
        "id": sid,
        "r_layer": r_layer,
        "gate_stage_id": gate_id,
    }
    if "r_layers_active" in raw:
        node["r_layers_active"] = list(raw["r_layers_active"])
    if raw.get("r_layers_note"):
        node["r_layers_note"] = raw["r_layers_note"]
    return node


def load_profile_document(profile_id: str = DEFAULT_PROFILE_ID) -> dict[str, Any]:
    path = _profile_path(profile_id)
    if not path.is_file():
        raise FileNotFoundError(f"pipeline profile not found: {path}")
    doc = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(doc, dict):
        raise ValueError(f"invalid profile document: {path}")
    return doc


def load_stage_graph(
    *,
    profile_id: str | None = None,
    plan_json: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Return {profile_id, stage_graph: [nodes...]} with plan.json override winning."""
    pid = DEFAULT_PROFILE_ID
    if plan_json:
        pid = str(plan_json.get("pipeline_profile") or plan_json.get("profile") or pid)
    if profile_id:
        pid = profile_id

    if plan_json and plan_json.get("stage_graph"):
        nodes = [_normalize_node(n) for n in plan_json["stage_graph"]]
        return {"profile_id": pid, "stage_graph": nodes, "source": "plan.json"}

    doc = load_profile_document(pid)
    nodes = [_normalize_node(n) for n in doc.get("stage_graph") or []]
    if not nodes:
        raise ValueError(f"profile {pid!r} has empty stage_graph")
    return {"profile_id": pid, "stage_graph": nodes, "source": f"profile:{pid}"}


def stage_ids(graph_doc: dict[str, Any]) -> list[str]:
    return [n["id"] for n in graph_doc.get("stage_graph") or []]


def canonical_stage_id(stage: str) -> str:
    return STAGE_ID_ALIASES.get(stage, stage)


def next_stage_id(current: str, graph_doc: dict[str, Any]) -> str:
    cur = canonical_stage_id(current)
    ids = stage_ids(graph_doc)
    if cur not in ids:
        return current
    idx = ids.index(cur)
    if idx + 1 >= len(ids):
        return ids[-1]
    return ids[idx + 1]


def progress_for_stage(stage: str, graph_doc: dict[str, Any]) -> str:
    sid = canonical_stage_id(stage)
    ids = stage_ids(graph_doc)
    if sid not in ids:
        return f"[?] {stage}"
    n = ids.index(sid) + 1
    total = len(ids)
    return f"[{n}/{total}] {sid}"


def validate_gate_lib_mapping(graph_doc: dict[str, Any], scripts_dir: Path) -> list[str]:
    """Return list of errors; empty if every gate_stage_id maps to gate-lib/*.sh."""
    errors: list[str] = []
    lib = scripts_dir / "gate-lib"
    for node in graph_doc.get("stage_graph") or []:
        gid = node["gate_stage_id"]
        sh = lib / f"{gid}.sh"
        if not sh.is_file():
            errors.append(f"gate_stage_id {gid!r} has no gate-lib/{gid}.sh")
    return errors


def assert_default_f2_equivalence(graph_doc: dict[str, Any]) -> list[str]:
    """Verify default profile matches v1.1 F.2 stage order and primary r_layer."""
    errors: list[str] = []
    ids = stage_ids(graph_doc)
    if tuple(ids) != DEFAULT_STAGE_IDS:
        errors.append(f"default stage order {ids!r} != F.2 {DEFAULT_STAGE_IDS!r}")
    for node in graph_doc.get("stage_graph") or []:
        sid = node["id"]
        exp = F2_PRIMARY_R_LAYER.get(sid)
        if exp and node.get("r_layer") != exp:
            errors.append(f"stage {sid!r} r_layer {node.get('r_layer')!r} != F.2 {exp!r}")
    return errors
