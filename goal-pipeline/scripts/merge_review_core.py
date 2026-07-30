#!/usr/bin/env python3
"""merge_review_core — thin CLI wrapper; implementation in kernel.review.merge."""
import os
import sys

_ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(_ROOT, "..")))
from kernel.review import merge as _merge  # noqa: E402

# Re-export for fixture tests that import this module by path.
normalize_issue = _merge.normalize_issue
compute_action = _merge.compute_action
issues_are_infra_only = _merge.issues_are_infra_only
main = _merge.main

if __name__ == "__main__":
    main()
