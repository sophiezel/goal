#!/usr/bin/env python3
import os
import sys

_ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, _ROOT)
from kernel.gate_runtime.noop import is_noop_fix

assert is_noop_fix("abc", "abc") is True
assert is_noop_fix("abc", "def") is False
assert is_noop_fix("", "abc") is False
print("OK kernel noop guard")
