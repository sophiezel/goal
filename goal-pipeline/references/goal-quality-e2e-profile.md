# goal-quality：e2e / validate profile 与 tier 对齐（#19 SSOT）

**Ratified 上下文：** [phase-3-hitl-ratified.md](../../docs/wayfinder/research/phase-3-hitl-ratified.md) #15 C1（PQ/IQ dedupe）、#13 C1（lite 质量面不 skip）。  
**实现：** `goal_quality_e2e_policy.py`；`quality-gate.sh` 在 `quality_policy.tier=strict` 时读取策略；Agent 编排见 `stages/goal-quality/SKILL.md`。

## 轴定义

| 轴 | 来源 | 取值 |
|----|------|------|
| **quality tier** | `state.quality_policy.tier` / `resolve_quality_tier` | `standard` \| `strict` |
| **plan_profile** | `handoff/plan.json` 或 index frontmatter | `lite` \| `full` |
| **repo profile** | `plan.json.profile` 或 index `profile:` | `h5` \| `backend` \| … |

`plan_profile=lite` 仅影响 **Agent 默认是否跑 e2e**（墙钟）；**不**降低 UVO、IQ、ratchet、smoke 硬闸门（#13）。

## Agent 编排默认（goal-quality 内部）

| quality tier | plan_profile | validate | e2e Playwright | test+lint |
|--------------|--------------|----------|----------------|-----------|
| standard | lite / full | 可选 | **默认 off** | **UVO**（implement post） |
| strict | full | 推荐 | h5 **推荐**；非 h5 可选 | **UVO** |
| strict | lite | 推荐 | h5 **推荐**；非 h5 **默认 off**（XS/S 墙钟） | **UVO** |

编排顺序不变：`runtime-smoke.sh` →（Agent 可选 validate/e2e）→ `quality-gate.sh` → `gate --post quality`。

## quality-gate.sh 证据检查（不重跑）

| quality tier | QG-L1-validate | QG-L1-e2e | 说明 |
|--------------|----------------|-----------|------|
| standard | — | — | 不检查 index 是否引用 validate/e2e |
| strict | **WARN** 若 index 无 validate 提及 | **WARN**；`repo_profile=h5` 且无 `evidence/e2e/` 且无 playwright 引用 → **BLOCK** | Phase A2 |

smoke、UVO overall、IQ 结构（quality 路径 `--skip-iq`）见下节 dedupe。

## 与 pipeline-node-catalog 对齐（必要性）

| 节点 | lite | standard | strict |
|------|------|----------|--------|
| UVO（test+build） | **不可 skip** | **不可 skip** | **不可 skip** |
| IQ structural（implement post） | **不可 skip** | **不可 skip** | **不可 skip** |
| `quality-gate` IQ 重跑 | **skip**（`gate-lib/quality.sh --skip-iq`） | 同左 | 同左 |
| runtime-smoke | 条件（pattern / tier） | 同左 | 同左 |
| Agent validate | 可选 | 可选 | 推荐 |
| Agent e2e | 默认 off | 默认 off | h5 推荐 / 非 h5 可选 |
| QG e2e 证据 | — | — | WARN / h5 BLOCK |

## PQ / IQ / UVO dedupe（#15 C1）

| 检查面 | 平面 | quality 阶段行为 |
|--------|------|------------------|
| 矩阵 `verify_command` / PQ-08 | PQ（plan） | 规划契约；**不**由 quality-gate 重跑命令 |
| test / lint / build | UVO（implement） | implement post **hard**；quality-gate **只读** `verification-oracle.json` |
| IQ-10 / contract-conformance | IQ（implement） | implement post **hard** |
| IQ structural in quality-gate | IQ | **跳过**（已在 implement 执行；避免与 UVO 双跑 test） |
| strict e2e 证据 | goal-quality gate | **独立** `QG-L1-e2e`；与 UVO test 退出码 **无** double block |

重复契约键的 PQ↔IQ dedupe（`dedupe_key`）在 plan/implement 闸门；quality 面仅汇总 L0/L1 证据，见 [optimization-spec-outline-v1.md](../../docs/wayfinder/research/optimization-spec-outline-v1.md) Part D。

## 调试

```bash
python3 goal-pipeline/scripts/goal_quality_e2e_policy.py \
  --task-dir docs/guazi-flow/<task> --tier strict --json
```

Fixture：`goal-pipeline/scripts/fixtures/guazi-flow-gate/test-quality-e2e-profile-tier.sh`。
