"""Write stage gate fix-input JSON (GateRuntime)."""
from __future__ import annotations

import json
import os
from typing import Any


def write_fix_input(
    path: str,
    stage: str,
    subject_hash: str,
    action: str,
    issues: list[dict[str, Any]],
    extra: dict[str, Any] | None = None,
) -> str:
    doc = {
        "schema_version": 1,
        "stage": stage,
        "subject_hash": subject_hash,
        "action": action,
        "issues": issues,
    }
    if extra:
        doc.update(extra)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
        f.write("\n")
    return path
