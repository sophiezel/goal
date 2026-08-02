#!/bin/bash
# test-fix-input-issue-order.sh — substantive blockers before G000 in fix-input ordering
set -euo pipefail
python3 - << 'PY'
import json

def rank(i):
    iid = i.get("id") or ""
    if iid == "G000":
        return (2, iid)
    if i.get("severity") in ("blocker", "block"):
        return (0, iid)
    return (1, iid)

merged = [
    {"id": "IQ-10", "severity": "blocker", "summary": "contract"},
    {"id": "G000", "severity": "blocker", "summary": "noop"},
]
merged.sort(key=rank)
assert merged[0]["id"] == "IQ-10"
assert merged[-1]["id"] == "G000"
print("fix-input issue order OK")
PY
echo "test-fix-input-issue-order passed"
