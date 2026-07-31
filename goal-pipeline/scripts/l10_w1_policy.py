#!/usr/bin/env python3
"""Shared L10 / W1 disposition policy (complete gate + leakage bookkeeping)."""
from __future__ import annotations

_W1_CLOSED = frozenset({"pass", "waive", "deferred", "waived"})
_SOFT_SEVERITY = frozenset({"soft", "warn", "info", "low"})

__all__ = ["W1_CLOSED", "l10_row_blocks_complete"]


def l10_row_blocks_complete(row: dict) -> bool:
    """B3: default soft + open rows do not block complete; hard/escalated do."""
    status = str(row.get("w1_status") or "open").lower()
    if status in _W1_CLOSED:
        return False
    severity = str(row.get("severity") or "soft").lower()
    if row.get("escalated_to_l9") or row.get("l9_escalated"):
        return True
    if severity in ("hard", "blocker", "block", "critical"):
        return True
    if severity in _SOFT_SEVERITY:
        return False
    return False


W1_CLOSED = _W1_CLOSED
