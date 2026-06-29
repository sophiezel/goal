# Stage Handoff Contract

guazi-flow-goal 阶段衔接的单一事实来源。硬约束：**不修改 guazi-flow-* skill**；handoff 由 goal 侧 `gate-guazi-flow-stage.sh` 生成。

## 阶段替代 / 并集策略

| 管线阶段 | guazi_flow_available=true | guazi_flow_available=false |
|---------|----------------------------|---------------------------|
| plan | 仅 guazi-flow-plan | goal-pipeline plan 卡片 |
| implement | 仅 guazi-flow-implement | goal-pipeline implement |
| runtime_smoke | goal-pipeline 脚本 | 同左 |
| review | guazi-flow-review **+** goal-pipeline 独立审核（并集） | 仅 goal-pipeline review |
| complete | guazi-flow-complete + goal-pipeline 质量报告 | 仅 goal-pipeline complete |

## Handoff 路径

```
docs/guazi-flow/<task>/handoff/plan.json
docs/guazi-flow/<task>/handoff/implement.json
docs/guazi-flow/<task>/handoff/review.json
docs/guazi-flow/<task>/handoff/review-packet.json
```

## Orchestrator 顺序（guazi-flow-goal Phase 2）

```
gate --pre(<stage>)
  → Read 完整 guazi-flow-<stage>/SKILL.md
  → 按 skill 执行
  → gate --post(<stage>)   # 校验产物 + 写 handoff/*.json
  → exit 0 才允许输出 [N/5] guazi-flow-<stage>: ✅
  → exit 1 → blocked(stage_gate_failed)
```

## handoff/*.json Schema

### plan.json

```json
{
  "stage": "plan",
  "schema_version": 1,
  "skill_expected": "guazi-flow-plan",
  "skill_executed": true,
  "task_dir": "docs/guazi-flow/<task>",
  "profile": "h5",
  "profile_detail": "react",
  "write_set": ["routes.ts", "src/..."],
  "acceptance_matrix_ids": ["C01", "C02"],
  "index_schema_hash": "<sha256[:16]>",
  "git_head": "<16>",
  "artifact_paths": ["index.md"],
  "warnings": [],
  "gate": { "script": "gate-guazi-flow-stage.sh", "version": 1, "passed_at": "<iso8601>" }
}
```

### implement.json

```json
{
  "stage": "implement",
  "schema_version": 1,
  "skill_expected": "guazi-flow-implement",
  "skill_executed": true,
  "write_set": [],
  "changed_files": [],
  "git_head": "",
  "candidate_diff_hash": "",
  "artifact_paths": ["index.md"],
  "gate": { "script": "gate-guazi-flow-stage.sh", "version": 1, "passed_at": "" }
}
```

### review.json

```json
{
  "stage": "review",
  "schema_version": 1,
  "result": "pass",
  "review_subject_hash": "",
  "git_head": "",
  "issues_gf_count": 0,
  "issues_goal_count": 0,
  "root_cause_summary": {},
  "artifact_paths": ["evidence/review.md", "evidence/review-goal.json"],
  "gate": { "script": "gate-guazi-flow-stage.sh", "version": 1, "passed_at": "" }
}
```

## 各阶段 skill 指纹产物（gate 校验）

| 阶段 | 必须磁盘证据 |
|------|-------------|
| plan | index.md：frontmatter 四字段 + 核心事实/完整伪代码/验收与验证矩阵/执行记录 |
| implement | index 执行记录含 guazi-flow-implement；diff ⊆ write_set |
| review | evidence/review.md 标准 frontmatter + 章节；review-goal annex 或 review-goal.json |
| complete | index flow.current_stage=complete；执行记录含 guazi-flow-complete；review pass+fresh |

## ReviewPacket

由 `assemble-review-packet.sh` 从 handoff 链 + index + diff + verify-review 输出组装。详见 `goal-pipeline/references/review-packet-schema.md`。
