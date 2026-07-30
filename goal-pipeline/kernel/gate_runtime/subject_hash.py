"""Code subject hash for noop_fix ratchet."""
from __future__ import annotations

import importlib.util
import os


def code_subject_hash(repo_root: str, write_set: list[str] | None = None, ref_branch: str = "") -> str:
    scripts = os.path.join(os.path.dirname(__file__), "..", "..", "scripts")
    dr_path = os.path.join(scripts, "diff_resolver.py")
    spec = importlib.util.spec_from_file_location("diff_resolver", dr_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("diff_resolver.py missing")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.code_subject_hash(repo_root, write_set, ref_branch)
