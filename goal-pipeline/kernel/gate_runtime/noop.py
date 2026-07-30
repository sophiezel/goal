"""noop_fix guard — same subject_hash across fix rounds."""
from __future__ import annotations


def is_noop_fix(previous_hash: str, current_hash: str) -> bool:
    if not previous_hash or not current_hash:
        return False
    return previous_hash == current_hash
