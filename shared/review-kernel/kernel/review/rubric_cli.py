#!/usr/bin/env python3
"""CLI: emit rubric excerpt JSON for assemble-review-packet.sh"""
import json
import os
import sys

_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, _ROOT)
from kernel.review.rubric import provider_from_env  # noqa: E402


def main():
    max_chars = int(os.environ.get("GOAL_RUBRIC_MAX_CHARS", "4000"))
    prov = provider_from_env()
    print(json.dumps({"channel": prov.channel_name(), "excerpt": prov.skill_summary(max_chars)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
