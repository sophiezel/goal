"""RubricProvider — inject project rubric into review packet (kernel has no hardcoded guazi paths)."""
from __future__ import annotations

import os
from abc import ABC, abstractmethod
from typing import Any


class RubricProvider(ABC):
    @abstractmethod
    def skill_summary(self, max_chars: int = 4000) -> str:
        ...

    @abstractmethod
    def channel_name(self) -> str:
        ...


class NullRubricProvider(RubricProvider):
    def skill_summary(self, max_chars: int = 4000) -> str:
        return ""

    def channel_name(self) -> str:
        return "goal"


class GuaziRubricAdapter(RubricProvider):
    """Resolve guazi-flow-review SKILL.md via explicit paths (injected by guazi pipeline)."""

    def __init__(self, skill_paths: list[str] | None = None):
        self._paths = skill_paths or []

    def _resolve_path(self) -> str:
        for p in self._paths:
            p = os.path.expanduser(p)
            if p and os.path.isfile(p):
                return p
        env = os.environ.get("GUAZI_FLOW_REVIEW_SKILL", "").strip()
        if env and os.path.isfile(os.path.expanduser(env)):
            return os.path.expanduser(env)
        return ""

    def skill_summary(self, max_chars: int = 4000) -> str:
        path = self._resolve_path()
        if not path:
            return ""
        text = open(path, encoding="utf-8").read()
        return text[:max_chars]

    def channel_name(self) -> str:
        return "guazi-flow-review"


def provider_from_env() -> RubricProvider:
    if os.environ.get("GOAL_REVIEW_RUBRIC_PROVIDER", "").lower() in ("guazi", "guazi-flow-review"):
        paths = []
        git_root = os.environ.get("GOAL_PROJECT_ROOT", "")
        if git_root:
            paths.append(os.path.join(git_root, ".agents", "skills", "guazi-flow-review", "SKILL.md"))
        paths.extend(
            [
                os.path.expanduser("~/.agents/skills/guazi-flow-review/SKILL.md"),
                os.path.expanduser("~/.claude/skills/guazi-flow-review/SKILL.md"),
            ]
        )
        return GuaziRubricAdapter(paths)
    return NullRubricProvider()
