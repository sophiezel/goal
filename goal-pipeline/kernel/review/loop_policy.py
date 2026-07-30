"""Review-fix loop limits from environment (ReviewKernel LoopPolicy)."""
from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class LoopPolicy:
    max_rounds: int = 10
    info_gain_min: float = 0.10
    stagnant_rounds_limit: int = 2

    @classmethod
    def from_env(cls) -> "LoopPolicy":
        try:
            max_rounds = int(os.environ.get("GOAL_REVIEW_MAX_ROUNDS", "10") or "10")
        except ValueError:
            max_rounds = 10
        try:
            info_gain_min = float(os.environ.get("GOAL_REVIEW_INFO_GAIN_MIN", "0.10") or "0.10")
        except ValueError:
            info_gain_min = 0.10
        try:
            stagnant_rounds_limit = int(os.environ.get("GOAL_REVIEW_STAGNANT_ROUNDS", "2") or "2")
        except ValueError:
            stagnant_rounds_limit = 2
        return cls(
            max_rounds=max_rounds,
            info_gain_min=info_gain_min,
            stagnant_rounds_limit=stagnant_rounds_limit,
        )
