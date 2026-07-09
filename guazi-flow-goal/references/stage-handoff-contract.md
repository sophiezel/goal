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

## Handoff 路径（split 模式，默认）

Tier-R handoff **不在 repo**。路径由 `resolve-artifact-paths.py` 解析为 `HANDOFF_DIR`：

```
~/.goal-state/projects/<pid>/<branch>/<task>/artifacts/handoff/
├── plan.json
├── implement.json
├── smoke.json
├── review.json
├── review-packet.json
├── merge-result.json
└── complete.json
```

repo（Tier-G）仅保留：

```
docs/guazi-flow/<task>/
├── index.md
└── evidence/review.md | complete.md | cwiki/** ...
```

`repo_full` 兼容模式：handoff 仍在 `docs/guazi-flow/<task>/handoff/`（旧行为，新 goal 禁止默认使用）。

## handoff JSON 路径字段

| 字段 | 含义 |
|------|------|
| `artifact_paths` | **Tier-G**，相对 `docs/guazi-flow/<task>/`（进 git） |
| `runtime_artifact_paths` | **Tier-R**，相对 `artifacts/` 根（goal-state，不进 git） |

示例：`review.json` 中 `artifact_paths: ["evidence/review.md"]`，`runtime_artifact_paths: ["evidence/review-run.json", ...]`。

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
  "write_set_normalized": true,
  "acceptance_matrix_ids": ["C01", "C02"],
  "index_contract_hash": "<sha256[:16] of contract sections only>",
  "index_execution_tail_hash": "<sha256[:16] of ## 执行记录 and after>",
  "index_schema_hash": "<alias of index_contract_hash for legacy consumers>",
  "verification": {
    "test_pattern": "optional",
    "build_command": "optional e.g. CI= yarn build:beta"
  },
  "git_head": "<16>",
  "artifact_paths": ["index.md"],
  "warnings": [],
  "gate": { "script": "gate-guazi-flow-stage.sh", "version": 1, "passed_at": "<iso8601>" }
}
```

**`index_contract_hash` 语义（重要）**：

- 指纹覆盖：YAML frontmatter（排除 `current_stage`）+ `## 概览` 至 `## 验收与验证矩阵` 等契约段
- **排除** `## 执行记录` 及之后内容（implement/review 追加日志不得使 plan handoff stale）
- `review --pre` 仅当 `index_contract_hash` 变化时 FAIL（真 mini-replan）
- 仅执行记录变化时：跑 `refresh-handoffs-after-index.sh --cascade implement`（刷新 implement + packet），**禁止**当作 mini-replan
- 旧字段 `index_schema_hash` 若为全文 hash，由 refresh/plan post 迁移为 contract hash

**write_set 规范化**：`src/foo/**` → `src/foo/`；`write_set_normalized: true` 表示已规范化。
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
  "artifact_paths": ["evidence/review.md"],
  "runtime_artifact_paths": ["evidence/review-unified.json", "evidence/review-fix-input.json", "evidence/review-run.json"],
  "gate": { "script": "gate-guazi-flow-stage.sh", "version": 1, "passed_at": "" }
}
```

## 各阶段 skill 指纹产物（gate 校验）

| 阶段 | 必须磁盘证据 |
|------|-------------|
| plan | index.md：frontmatter 四字段 + 核心事实/完整伪代码/验收与验证矩阵/执行记录 |
| implement | index 执行记录含 guazi-flow-implement；diff ⊆ write_set |
| review | evidence/review.md（repo Tier-G）；review-unified/review-run 等 annex 在 goal-state `artifacts/evidence/` |
| complete | index flow.current_stage=complete；执行记录含 guazi-flow-complete；review pass+fresh |

## ReviewPacket

由 `assemble-review-packet.sh` 从 handoff 链 + index + diff + verify-review 输出组装。详见 `goal-pipeline/references/review-packet-schema.md`。
