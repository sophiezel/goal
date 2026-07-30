#!/usr/bin/env python3
"""benchmark-compare — compare pre vs post benchmark JSONs (v3 §8.5 #4).

Static replay measures feature wiring (review_chain score), not live wall-clock.
Wall-clock reduction (≥25%) requires a live XS task replay — see p2-eval-runbook.md.
"""
from __future__ import annotations

import argparse
import json
import sys


def load(path: str) -> dict:
    return json.load(open(path, encoding="utf-8"))


def compare(pre: dict, post: dict) -> dict:
    pre_dur = pre.get("duration_ms", 0)
    post_dur = post.get("duration_ms", 0)
    pre_score = pre.get("review_chain", {}).get("score", 0)
    post_score = post.get("review_chain", {}).get("score", 0)
    # For static replay: duration_ms is scan time (lower is not better — it's noise).
    # The real metric is feature score (higher = more optimizations wired).
    # Wall-clock reduction is measured via live replay, not here.
    dur_delta = pre_dur - post_dur
    dur_pct = round((dur_delta / pre_dur) * 100, 2) if pre_dur else 0
    score_delta = post_score - pre_score
    return {
        "pre_duration_ms": pre_dur,
        "post_duration_ms": post_dur,
        "duration_delta_ms": dur_delta,
        "duration_reduction_pct": dur_pct,
        "pre_review_chain_score": pre_score,
        "post_review_chain_score": post_score,
        "review_chain_score_delta": score_delta,
        "note": (
            "Static replay: duration_ms is scan time (noise), not wall-clock. "
            "review_chain_score delta shows newly-wired features. "
            "Wall-clock ≥25% reduction requires live XS replay (see p2-eval-runbook.md)."
        ),
    }


def main() -> int:
    p = argparse.ArgumentParser(description="Compare pre vs post benchmark JSONs")
    p.add_argument("--pre", required=True)
    p.add_argument("--post", required=True)
    p.add_argument("--json", action="store_true", dest="as_json")
    args = p.parse_args()
    result = compare(load(args.pre), load(args.post))
    if args.as_json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(f"pre_duration_ms:     {result['pre_duration_ms']}")
        print(f"post_duration_ms:    {result['post_duration_ms']}")
        print(f"duration_reduction:  {result['duration_reduction_pct']}%")
        print(f"review_chain_score:  {result['pre_review_chain_score']} → {result['post_review_chain_score']} (delta={result['review_chain_score_delta']})")
        print(f"note: {result['note']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
