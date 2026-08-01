#!/usr/bin/env python3
"""Review kernel B — JSON Schema (draft-07 subset) + fix-input gate semantics."""
from __future__ import annotations

import json
import os
import re
from typing import Any

_GOAL_PIPELINE_ROOT = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
)
_SCHEMAS_DIR = os.path.join(_GOAL_PIPELINE_ROOT, "schemas")

_ARTIFACT_SCHEMA = {
    "review-run.json": "review-run.schema.json",
    "review-unified.json": "review-unified.schema.json",
    "review-fix-input.json": "review-fix-input.schema.json",
}

_FIX_INPUT_ACTIONS = frozenset(
    {
        "proceed_complete",
        "fix_and_rerun_review",
        "mini_replan",
        "blocked_user_decision",
        "blocked_stagnant",
        "switch_to_cursor_task",
        "fix_channel",
    }
)

_ISO8601_RE = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$"
)


def schema_path(name: str) -> str:
    if name.endswith(".schema.json"):
        return os.path.join(_SCHEMAS_DIR, name)
    mapped = _ARTIFACT_SCHEMA.get(name)
    if mapped:
        return os.path.join(_SCHEMAS_DIR, mapped)
    return os.path.join(_SCHEMAS_DIR, name)


def load_schema_file(filename: str) -> dict[str, Any]:
    path = schema_path(filename)
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _type_name(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int) and not isinstance(value, bool):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    return type(value).__name__


def _validate_node(
    value: Any,
    schema: dict[str, Any],
    path: str,
    errors: list[str],
) -> None:
    if not schema:
        return

    for key in ("const", "enum", "type"):
        if key not in schema:
            continue
        if key == "const":
            if value != schema["const"]:
                errors.append(f"{path}: expected const {schema['const']!r}")
            return
        if key == "enum":
            if value not in schema["enum"]:
                errors.append(f"{path}: value {value!r} not in enum")
            return
        types = schema["type"]
        if isinstance(types, str):
            types = [types]
        actual = _type_name(value)
        if actual not in types and not (actual == "integer" and "number" in types):
            errors.append(f"{path}: expected type {types}, got {actual}")
            return
        break

    if "minLength" in schema and isinstance(value, str):
        if len(value) < schema["minLength"]:
            errors.append(f"{path}: string shorter than minLength")
    if "minimum" in schema and isinstance(value, (int, float)):
        if value < schema["minimum"]:
            errors.append(f"{path}: below minimum {schema['minimum']}")
    if schema.get("format") == "date-time" and isinstance(value, str):
        if not _ISO8601_RE.match(value):
            errors.append(f"{path}: invalid date-time")

    if isinstance(value, list):
        if "minItems" in schema and len(value) < schema["minItems"]:
            errors.append(f"{path}: fewer than minItems")
        item_schema = schema.get("items")
        if item_schema:
            for i, item in enumerate(value):
                _validate_node(item, item_schema, f"{path}[{i}]", errors)

    if isinstance(value, dict):
        for req in schema.get("required", []):
            if req not in value:
                errors.append(f"{path}: missing required field {req!r}")
        props = schema.get("properties", {})
        addl = schema.get("additionalProperties", True)
        for k, v in value.items():
            if k in props:
                _validate_node(v, props[k], f"{path}.{k}", errors)
            elif addl is False:
                errors.append(f"{path}: additional property {k!r} not allowed")


def validate_json_schema(doc: Any, schema: dict[str, Any], path: str = "$") -> list[str]:
    errors: list[str] = []
    _validate_node(doc, schema, path, errors)
    return errors


def validate_artifact_file(artifact_basename: str, doc: dict[str, Any]) -> list[str]:
    schema_file = _ARTIFACT_SCHEMA.get(artifact_basename)
    if not schema_file:
        return [f"unknown artifact {artifact_basename!r}"]
    schema = load_schema_file(schema_file)
    return validate_json_schema(doc, schema)


def validate_fix_input_semantics(
    doc: dict[str, Any],
    *,
    max_rounds: int | None = None,
) -> list[str]:
    """Normative rules mirrored from gate-lib/review.sh (B6/B7)."""
    errors: list[str] = []
    action = doc.get("action")
    if action not in _FIX_INPUT_ACTIONS:
        errors.append(f"invalid action: {action!r}")

    merged = doc.get("merged_result")
    if merged not in ("pass", "not_pass"):
        errors.append("invalid merged_result")
    elif merged == "pass" and action != "proceed_complete":
        errors.append("pass requires proceed_complete")
    elif merged == "not_pass" and action == "proceed_complete":
        errors.append("not_pass cannot proceed_complete")

    if doc.get("classification") == "infra_undetermined" and action == "fix_and_rerun_review":
        errors.append("infra_undetermined cannot use fix_and_rerun_review")

    if doc.get("stagnant_blocked") and action != "blocked_stagnant":
        errors.append("stagnant_blocked requires action=blocked_stagnant")

    if max_rounds is None:
        try:
            max_rounds = int(os.environ.get("GOAL_REVIEW_MAX_ROUNDS", "10") or "10")
        except ValueError:
            max_rounds = 10

    round_n = int(doc.get("round") or 0)
    if doc.get("rounds_exhausted") or (
        doc.get("merged_result") == "not_pass"
        and round_n > max_rounds
        and action in ("fix_and_rerun_review", "mini_replan")
    ):
        if not doc.get("rounds_exhausted"):
            errors.append(
                f"review fix rounds exhausted: round={round_n} max={max_rounds}"
            )
    if doc.get("rounds_exhausted") and action != "blocked_user_decision":
        errors.append("rounds_exhausted requires action=blocked_user_decision")

    return errors


def discover_fixture_artifacts(fixtures_root: str) -> list[tuple[str, str]]:
    """Return (path, basename) for review B artifacts under scripts/fixtures."""
    found: list[tuple[str, str]] = []
    for dirpath, _dirnames, filenames in os.walk(fixtures_root):
        for base in _ARTIFACT_SCHEMA:
            if base in filenames:
                found.append((os.path.join(dirpath, base), base))
    return sorted(found)


def validate_fixtures_tree(fixtures_root: str, *, check_semantics: bool = True) -> dict[str, Any]:
    errors: list[str] = []
    checked = 0
    for path, base in discover_fixture_artifacts(fixtures_root):
        try:
            doc = json.load(open(path, encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as e:
            errors.append(f"{path}: cannot read JSON: {e}")
            continue
        for msg in validate_artifact_file(base, doc):
            errors.append(f"{path}: {msg}")
        if check_semantics and base == "review-fix-input.json":
            for msg in validate_fix_input_semantics(doc):
                errors.append(f"{path}: semantics: {msg}")
        checked += 1
    return {"ok": len(errors) == 0, "checked": checked, "errors": errors}
