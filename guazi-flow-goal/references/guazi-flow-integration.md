# Guazi Flow 集成规则（v1.4）

guazi-flow-goal 是 **独立五阶段管线**，调度 guazi-flow-* marketplace skills + 本仓 gate/advance 脚本。  
**不**加载 goal-pipeline；**不**使用 `~/.goal-pipeline/`。

**必读配套：** `bridge-contract.md`、`guazi-flow-state-schema.md`、`guazi-flow-goal/SKILL.md`

## Pre-flight（MANDATORY）

```bash
bash guazi-flow-goal/scripts/guazi-install.sh
# → ~/.guazi-flow/state/scripts/guazi-gate-stage.sh
# → ~/.guazi-flow/state/scripts/guazi-advance-stage.sh
bash shared/review-kernel/install.sh   # → REVIEW_KERNEL_HOME
```

缺失 → `blocked(infra_missing)`。**禁止** fallback 到 goal-pipeline。

## 阶段调度

| 阶段 | Skill | Gate |
|------|-------|------|
| plan | guazi-flow-plan | `guazi-gate-stage.sh --stage plan --pre\|--post --mode guazi` |
| implement | guazi-flow-implement | 同上 implement |
| quality | goal-quality 脚本族 | `--stage quality`（smoke 并入 quality，无独立 smoke stage） |
| review | review-kernel + 可选 guazi-flow-review | `--stage review`；chain 经 `$REVIEW_KERNEL_HOME` |
| complete | guazi-flow-complete | `--stage complete` |

条件触发（guazi-flow 自身规则，无 goal 替代）：

| 阶段 | 触发 |
|------|------|
| postmerge | `postmerge_policy=required` → guazi-flow-postmerge |
| validate | 用户开启或 `validate_policy=required` → guazi-flow-validate |
| e2e | Goal Engineering 选型 + h5 profile → guazi-flow-e2e |

## Turn 协议（每 Agent turn）

```bash
# 1. 读 state
# 2. blocked → 按 fix-input 修复，禁止新功能
# 3. 每阶段：
guazi-gate-stage.sh --task-dir <task> --project-root <repo> \
  --stage <stage> --pre --mode guazi --state-file <state>
# → Read guazi-flow-<stage>/SKILL.md 全文并执行
guazi-gate-stage.sh --stage <stage> --post --mode guazi --state-file <state> --project-root <repo>
# 4. 阶段结束：
guazi-advance-stage.sh --state-file <state> --task-dir <task> --project-root <repo>
```

**NEVER** 在 gate `--post` exit 0 前输出 `[N/5] ✅`。

## plan 阶段要点

1. `guazi-flow-plan` 产出 `docs/guazi-flow/<task>/index.md`（+ units）
2. Gate `--post plan` 校验 index schema（`guazi-flow-artifact-schema/plan-index-rules.json`）
3. 内嵌 `plan-quality-gate.py`（PQ 防火墙）
4. 写入 `handoff/plan.json`（含 `write_set`、`task_tier`、`review_policy`）
5. `argus_enrich_plan` / fe-argus manifest（L10，plan post 必填路径）
6. Index-Lite：见 `index-lite-protocol.md`；规则路由 `resolve_plan_index_rules.py`（`GATE_MODE=guazi`）

**v1.4 删除：** `guazi_flow_contract_enrich.py` 契约融入（B3）；不再写 `guazi_flow_contract_enriched`。

## implement 阶段要点

1. `--pre`：`assert_plan_before_code` + 非空 `write_set` + plan handoff 存在
2. `guazi-flow-implement` 在 write_set 内改代码
3. `--post`：`implement-qc-gate.py`、可选 IQ-10、`ux-auto-fix-audit.py`
4. 执行记录须含 `guazi-flow-implement`
5. **唯一合法出口：** `gate --post implement` → `validate-pipeline-chain` → `guazi-advance-stage` → quality

## quality 阶段要点

implement post 后立即 runtime-smoke（若 profile 要求）→ `quality-gate.sh` → `gate --stage quality --post` → advance → review。

**NEVER** `[3/5] ✅` 而无 `handoff/quality.json` 的 `gate.passed_at`。

## review 阶段要点

```
gate --pre(review)
→ assemble-review-packet.sh
→ $REVIEW_KERNEL_HOME/bin/run-review-chain.sh  # 或 cli.py run
→ merge-review-issues.sh
→ gate --post(review)
```

- `review_track=single`：跳过 `guazi-flow-review` wrapper；unified 单次 LLM
- `review_track=dual`：可加载 `guazi-flow-review`；B8 校验 `gf_skill_attested`
- 修复子循环只读 `evidence/review-fix-input.json`

## complete 阶段要点

`guazi-flow-complete` + `gate --post complete` + `quality_plane_check --mode complete`（含 postmerge policy）。

## 硬门禁脚本（guazi runtime）

| 脚本 | 用途 |
|------|------|
| `guazi-gate-stage.sh` | 五阶段 `--pre`/`--post` |
| `guazi-advance-stage.sh` | 状态机 next_stage |
| `validate-pipeline-chain.py` | handoff 链完整性 |
| `refresh-handoffs-after-index.sh` | index 漂移 cascade（guazi gate） |
| `assemble-review-packet.sh` / `merge-review-issues.sh` | review（经 review-kernel 或 state scripts） |

Gate 失败 → `evidence/<stage>-gate-fix-input.json`。`subject_hash` 不变仍 fail → `blocked(noop_fix)`。

## 阶段跳过检测

```bash
guazi-advance-stage.sh --state-file "$GUAZI_STATE_HOME/projects/.../state.json" \
  --task-dir docs/guazi-flow/<task> --project-root <repo>
```

Stop hook：`guazi-gate-stage.sh --assert-complete --state-file ... --task-dir ... --project-root ...`

| 信号 | 行为 |
|------|------|
| next_stage≠done 却结束 turn | 拦截 |
| 有 diff 无 `handoff/review.json` | `blocked(stage_skipped)` |
| gate 未 exit 0 却 ✅ | `blocked(stage_gate_failed)` |

Handoff 规范：`stage-handoff-contract.md`。

## 声明式契约门禁

index / `handoff/decisions.json` 中的 API、集成约定由 plan/implement gate 检查（PQ-10～14、IQ-10）。  
说明：`goal-pipeline/references/declarative-contract-gates.md`（只读参考，guazi 经自有 scripts 调用）。

## v1.4 废止

- `GF_USE_NATIVE_DRIVER`、`gf-stage-driver.sh`、`gate-gf-stage.sh`
- goal 降级表与 `guazi_flow_available=false → 纯 goal` 叙事
- `~/.goal-pipeline/state/kernel` 作为 guazi 运行时依赖

历史 v1.3 全文：`references/archive/v1.3-bridge/guazi-flow-integration.v1.3.md`
