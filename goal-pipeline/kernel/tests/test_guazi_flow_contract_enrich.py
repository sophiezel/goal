"""Unit tests for guazi_flow_contract_enrich (B3)."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

_SCRIPTS = Path(__file__).resolve().parents[2] / "scripts"
sys.path.insert(0, str(_SCRIPTS))

from guazi_flow_contract_enrich import (  # noqa: E402
    _contract_complete,
    enrich_index,
    implement_pre_allowed,
)


def test_enrich_appends_goal_contract(tmp_path: Path) -> None:
    index = tmp_path / "index.md"
    index.write_text(
        "## write_set\n\n- `src/a.ts`\n",
        encoding="utf-8",
    )
    plan = {"write_set": ["src/a.ts"]}
    result = enrich_index(index, plan=plan)
    assert result.ok
    text = index.read_text(encoding="utf-8")
    assert _contract_complete(text)


def test_implement_pre_blocks_explicit_false(tmp_path: Path) -> None:
    index = tmp_path / "index.md"
    index.write_text("## write_set\n\n- x\n", encoding="utf-8")
    plan = {"write_set": ["x"]}
    state = {"guazi_flow_contract_enriched": False}
    ok, reason = implement_pre_allowed(index, plan, state, "block")
    assert not ok
    assert reason == "guazi_flow_contract_enriched=false"


def test_implement_pre_legacy_write_set(tmp_path: Path) -> None:
    index = tmp_path / "index.md"
    index.write_text("## write_set\n\n- x\n", encoding="utf-8")
    plan = {"write_set": ["x"]}
    ok, _ = implement_pre_allowed(index, plan, {}, "block")
    assert ok


def test_implement_pre_plan_stamp(tmp_path: Path) -> None:
    index = tmp_path / "index.md"
    index.write_text("## write_set\n\n", encoding="utf-8")
    plan = {"contract_enriched": True, "write_set": []}
    ok, reason = implement_pre_allowed(index, plan, {}, "block")
    assert ok
    assert reason == "plan.contract_enriched"
