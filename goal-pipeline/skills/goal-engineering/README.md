# goal-engineering skill pack (v1.2 Part K + v1.3 Part P)

Simplified **grill** / **to-specs** / **prototype** / **handoff** / **tdd** derivatives for Phase 1 (R1–R3). SSOT lives in this repo — **not** the English Cursor marketplace Matt skills.

| Pack profile value | Skills loaded (plan / implement) |
|--------------------|----------------------------------|
| `none` | — |
| `grill` | [grill](grill/SKILL.md) |
| `to_specs` | [to-specs](to-specs/SKILL.md) |
| `grill_to_specs` | grill → to-specs |
| `prototype` | grill → [prototype](prototype/SKILL.md) → [handoff](handoff/SKILL.md) |
| `handoff` | [handoff](handoff/SKILL.md) |
| `full_matt` | grill → (to-specs \| prototype per `workflow_profile`) → handoff |

**workflow_profile** (`spec_path` | `prototype_path` | `hybrid`) 决定 R1–R2 链形态，与 `stage_graph` gate 正交。Resolver: `kernel/profile/workflow_profile.py`.

Configure via `references/profiles/<id>/pipeline.profile.json` → `engineering_pack` + `workflow_profile`, or `handoff/plan.json` override.

Resolver: `goal-pipeline/scripts/resolve_engineering_pack.py`

See [LICENSE](LICENSE), [goal-engineering-pack-v2-prototype.md](../../../docs/wayfinder/research/goal-engineering-pack-v2-prototype.md), and [optimization-spec-outline-v1.2.md](../../../docs/wayfinder/research/optimization-spec-outline-v1.2.md) Part K.
