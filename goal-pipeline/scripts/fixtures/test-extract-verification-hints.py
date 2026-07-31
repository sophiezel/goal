#!/usr/bin/env python3
"""Regression: test_pattern must not become '=' from markdown table pipes."""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "index_contract_hash.py"
spec = importlib.util.spec_from_file_location("ich", SCRIPT)
mod = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(mod)


def test_prefers_longest_identifier_over_quoted_partial() -> None:
    text = """
| C01 | `CI=true yarn test --testPathPattern=suspectedDealerCollectionApproval` |
| log | `CI=true yarn test --testPathPattern='suspectedDealerCollectionApproval\\|App.test'` |
"""
    hints = mod.extract_verification_hints(text)
    assert hints.get("test_pattern") == "suspectedDealerCollectionApproval"


def test_rejects_equals_only() -> None:
    text = "broken --testPathPattern= | next"
    hints = mod.extract_verification_hints(text)
    assert "test_pattern" not in hints


if __name__ == "__main__":
    test_prefers_longest_identifier_over_quoted_partial()
    test_rejects_equals_only()
    print("ok")
