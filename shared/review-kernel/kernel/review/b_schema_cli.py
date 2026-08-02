#!/usr/bin/env python3
"""CLI for review kernel B schema validation."""
import argparse
import json
import os
import sys

_ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)

from kernel.review import b_schema  # noqa: E402


def main() -> int:
    p = argparse.ArgumentParser(description="Validate review kernel B JSON artifacts")
    sub = p.add_subparsers(dest="cmd", required=True)

    p_file = sub.add_parser("validate-file", help="Validate one artifact file")
    p_file.add_argument("path", help="Path to review-run|unified|fix-input JSON")
    p_file.add_argument("--no-semantics", action="store_true")

    p_fix = sub.add_parser("validate-fix-input", help="Validate review-fix-input.json")
    p_fix.add_argument("path")

    p_tree = sub.add_parser("validate-fixtures", help="Validate all fixture review artifacts")
    p_tree.add_argument(
        "--fixtures-root",
        default=os.path.join(_ROOT, "scripts", "fixtures"),
        help="Root of goal-pipeline/scripts/fixtures",
    )
    p_tree.add_argument("--no-semantics", action="store_true")

    args = p.parse_args()

    if args.cmd == "validate-file":
        base = os.path.basename(args.path)
        doc = json.load(open(args.path, encoding="utf-8"))
        errors = b_schema.validate_artifact_file(base, doc)
        if not args.no_semantics and base == "review-fix-input.json":
            errors.extend(b_schema.validate_fix_input_semantics(doc))
    elif args.cmd == "validate-fix-input":
        doc = json.load(open(args.path, encoding="utf-8"))
        errors = b_schema.validate_artifact_file("review-fix-input.json", doc)
        errors.extend(b_schema.validate_fix_input_semantics(doc))
    elif args.cmd == "validate-fixtures":
        out = b_schema.validate_fixtures_tree(
            args.fixtures_root,
            check_semantics=not args.no_semantics,
        )
        print(json.dumps(out, ensure_ascii=False, indent=2))
        return 0 if out["ok"] else 1
    else:
        return 2

    out = {"ok": len(errors) == 0, "errors": errors}
    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0 if out["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
