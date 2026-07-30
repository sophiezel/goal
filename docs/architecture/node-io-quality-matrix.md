# Node I/O Quality Matrix（节点 I/O 质量矩阵 SSOT）

> v3 §0 节点级优化的质量矩阵。每节点声明：输入契约、输出产物、L0/L1/L2 检查、当前漏洞、优化动作。

| 节点 | 输入 | 输出 | Port / 机械校验 | L0 检查 | L1 检查 | L2 生产 | 漏洞 | 优化动作 |
|------|------|------|-----------------|---------|---------|--------|------|----------|
| **plan** | JIRA / 验收标准 / Figma | `index.md` + `handoff/plan.json` | `validate-stage-port.py --stage plan` | PQ-01..09、index_schema_hash | eval `no-skip-plan-gate` | plan_gap 逃逸 | 仪式长 / 模糊验收 | **Index-Lite**（XS/S 6 段）；PQ-08 机器可验列；AM-06..10 |
| **implement** | `plan.json` + `index.md` | `implement.json` + `verification-oracle.json` | `--stage implement` + `implement-qc-gate` | write_set subset、UVO pass、AM-01..10 | IQ 结构、secret scan | write_set 越界 | 越界靠自觉 | **write_set pre-BLOCK**（P4 W1.5）；AM-07 phantom path |
| **quality** | `implement.json` | `quality.json` + `runtime-smoke.md` | `--stage quality` + `quality-gate.sh` | UVO fresh、chain、secret | smoke、IQ 结构 | e2e 漏测 | e2e 仅 WARN | **Phase A2**：strict+h5 e2e **BLOCK** |
| **review** | `quality.json` + review-packet | `review-fix-input.json` | `--stage review` + `merge_review_core` / kernel merge | schema、stagnant、commit | unified issues、A/B Jaccard | review_gap 逃逸 | 双轨冗余 / 空转 | **单轨**（XS/S）；**info_gain 熔断**；**commit-before-review** |
| **complete** | 全 handoff 链 | `complete.json` + `delivery-quality.json` | `--require-delivery` + `validate-pipeline-chain.sh` | chain fresh、quality_plane_check | delivery v2 字段 | 无 postmortem 闭环 | — | **delivery-quality** schema；**leak-rate 面板**；**escape-register** |

## 漏出率目标

| 层 | 目标 | 触发动作 |
|----|------|----------|
| 全局 leak_rate | <10% | ≥10% → 开 audit PoC（W2b） |
| review_gap（single vs dual） | ≤5% | >5% → 回滚 single 默认 |
| plan_gap | 0 | PQ-01/02/05/07 block 不降级 |

## Phase A2 e2e BLOCK 边界

- **仅** `quality_policy.tier=strict` 且 `profile=h5`：quality-gate 检查 `evidence/e2e/` 存在或 index 引用 playwright 且 exit 0 → BLOCK
- standard / 非 h5：保持 WARN，避免小任务墙钟翻倍

## Phase B 自进化闭环

```
escape-register.json (逃逸登记)
  → postmortem（必填：逃逸节点 + 本应拦截的 gate 规则 ID）
  → evals/cases/escapes/*.yaml（自动生成 skill-upper 格式）
  → skill-up run（回归）
  → gate 规则更新（人工审核 PR）
```
