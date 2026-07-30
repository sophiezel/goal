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

**用途**：complete 阶段的**管线可观测性快照**（不是业务验收、不是某框架/需求的打分）。只汇总 handoff 链是否齐全、各阶段 gate 时间、review 轮次、逃逸登记等**与任务内容无关**的元数据，供 leak-rate 面板、ADR-0004 strict 完整性检查、事后分析。

- `schema_version` ≥ 1
- v2 推荐：`timing`, `loops`, `review_provenance`, `pipeline_id`
- v2 可选：`gate_evidence_rollup` — 扫描 `evidence/*.json` 中带顶层 `passed` 的门禁产物（如 UVO、契约检查），**按文件名汇总**，不解析业务字段

业务契约是否满足，由 **当次 index/plan 表 + 各 stage gate** 判定；不写入 delivery-quality 的业务常量。

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
