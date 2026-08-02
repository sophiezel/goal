#!/usr/bin/env python3
"""ReviewKernel.invoke boundary — run L2 independent review subprocess."""
from __future__ import annotations

import os
import subprocess
import sys
from typing import Sequence


def invoke_independent_review(
    scripts_dir: str,
    task_dir: str,
    state_file: str = "",
    project_root: str = "",
    mode: str = "unified",
) -> int:
    script = os.path.join(scripts_dir, "run-independent-review.sh")
    if not os.path.isfile(script):
        raise FileNotFoundError(script)
    cmd: Sequence[str] = ["bash", script, "--task-dir", task_dir]
    if state_file:
        cmd += ["--state-file", state_file]
    if project_root:
        cmd += ["--project-root", project_root]
    env = os.environ.copy()
    env["GOAL_REVIEW_MODE"] = mode
    return subprocess.call(cmd, env=env)


if __name__ == "__main__":
    scripts = os.path.join(os.path.dirname(__file__), "..", "..", "scripts")
    sys.exit(
        invoke_independent_review(
            scripts,
            sys.argv[1],
            os.environ.get("GOAL_STATE_FILE", ""),
            os.environ.get("GOAL_PROJECT_ROOT", ""),
        )
    )
