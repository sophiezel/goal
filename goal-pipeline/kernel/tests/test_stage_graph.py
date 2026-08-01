#!/usr/bin/env python3
import os
import sys

_ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, _ROOT)

from kernel.profile.stage_graph import (  # noqa: E402
    assert_default_f2_equivalence,
    load_stage_graph,
    next_stage_id,
    progress_for_stage,
)

g = load_stage_graph(profile_id="default")
assert not assert_default_f2_equivalence(g)
assert next_stage_id("plan", g) == "implement"
assert next_stage_id("quality", g) == "review"
assert progress_for_stage("review", g) == "[4/5] review"
print("OK kernel.profile.stage_graph unit")
