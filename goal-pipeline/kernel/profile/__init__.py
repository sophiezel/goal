"""Profile-backed pipeline configuration (v1.2 Part J)."""

from kernel.profile.stage_graph import (
    DEFAULT_PROFILE_ID,
    load_stage_graph,
    next_stage_id,
    progress_for_stage,
    validate_gate_lib_mapping,
)

__all__ = [
    "DEFAULT_PROFILE_ID",
    "load_stage_graph",
    "next_stage_id",
    "progress_for_stage",
    "validate_gate_lib_mapping",
]
