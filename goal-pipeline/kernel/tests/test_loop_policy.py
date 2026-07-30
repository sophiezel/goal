#!/usr/bin/env python3
import os
import sys

_ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, _ROOT)
from kernel.review.loop_policy import LoopPolicy

p = LoopPolicy.from_env()
assert p.max_rounds >= 1
assert 0 < p.info_gain_min <= 1
assert p.stagnant_rounds_limit >= 1
print("OK LoopPolicy from_env")
