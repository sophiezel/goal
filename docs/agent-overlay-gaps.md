# Agent overlay gaps (Profession/goal)

**Scope:** Project overlay only (`AGENTS.md` + `.cursor/rules/goal-agent-iron.mdc`).  
**Do not** edit `guazi-flow-*` / `guazi-flow-goal` / `goal-pipeline` SKILL.md or gate scripts for these gaps.

Hard gates already cover: plan-before-code, `write_set`, UVO / implement-qc, independent review, stop hook, `noop_fix`, repair-round limits, `task_tier`, secret scan on changed files.

| Gap (pre-gate session behavior) | Why gates are late | Overlay rule |
|---------------------------------|--------------------|--------------|
| Path/API hallucination from write-without-read | Surfaces at UVO/typecheck after edits | AGENTS §2 Read-before-write |
| Blind local patch thrash before gate | `noop_fix` / repair rounds fire after failed gate | AGENTS §3 Patch cap |
| Claiming `[N/5] ✅` without gate exit 0 | Skill NEVER exists; easy to ignore in chat | AGENTS §1 Done = gate exit 0 |
| Destructive / High-Risk ops | Partial secret/scope checks; not full HITL | AGENTS §4 High-Risk HITL |
| Implement while requirements/scope unclear | `write_set` catches drift after the fact | AGENTS §5 Scope → Phase 1 / plan |

Single source of truth for the six rules: [`AGENTS.md`](../AGENTS.md) (mirrored in `.cursor/rules/goal-agent-iron.mdc` with `alwaysApply: true`).
