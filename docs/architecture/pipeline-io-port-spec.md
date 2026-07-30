# Pipeline I/O Port Spec

跨管线（goal-pipeline / guazi-flow-goal）统一的阶段产物契约。外部服务只依赖本规范，不依赖具体 Skill 路径。

**机械校验**：`goal-pipeline/scripts/validate-stage-port.py --task-dir <repo_task_dir> [--state-file <state.json>]`

**链路校验**：`validate-pipeline-chain.sh`（新鲜度、反伪造、顺序）

## StagePort 表

| Stage | 输入 handoff | 输出 handoff | 关键 evidence | 校验 |
|-------|-------------|-------------|---------------|------|
| plan | — | `plan.json` | `index.md` | `--stage plan` |
| implement | `plan.json` | `implement.json` | `verification-oracle.json` | `--stage implement` |
| quality | `implement.json` | `quality.json` 或 `smoke.json` | `runtime-smoke.md` | `--stage quality` |
| review-pre | `quality.json` | — | clean git | `check_commit_before_review.py` |
| review | packet | `review.json` | `review-fix-input.json`, `review-run.json` | `--stage review` |
| complete | 全链 | `complete.json` | **`delivery-quality.json`** | `--stage complete` |

Handoff 根目录由 `resolve-artifact-paths.py` 解析（split / repo_full）。

## handoff 必填字段（摘要）

### plan.json

- `stage`, `schema_version`, `skill_expected`, `write_set`
- 推荐：`task_tier`, `plan_profile`, `index_contract_hash`

### implement.json

- `stage`, `schema_version`, `write_set`, `candidate_diff_hash` 或 `code_subject_hash`

### quality.json / smoke.json

- `stage`, `schema_version`, `result` 或 gate 等价字段

### review.json

- `stage`, `schema_version`, `result`（`pass` 方可 complete）

### complete.json

- `stage`, `schema_version`, `skill_executed`

### delivery-quality.json（complete post 写入）

- `schema_version` ≥ 1
- v2 推荐：`timing`, `loops`, `review_provenance`, `pipeline_id`

## fix-input 族

| 产物 | 用途 |
|------|------|
| `evidence/*-gate-fix-input.json` | plan/implement gate 失败 |
| `evidence/review-fix-input.json` | review 合并与 loop 决策 |

review-fix-input 在 round>1 时应含 `info_gain`、`subject_hash`（由 merge 写入）。

## 引用

- [CONTEXT.md](../../CONTEXT.md)
- [node-io-quality-matrix.md](./node-io-quality-matrix.md)
- [stage-handoff-contract.md](../../guazi-flow-goal/references/stage-handoff-contract.md)
