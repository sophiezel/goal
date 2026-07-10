# skill-optimization2 关键路径审计（Phase 0 ADR）

**日期**: 2026-07-10  
**分支**: `enhance/skill-optimization2`  
**基线**: `enhance/review`  
**状态**: 已定稿 — 驱动 UVO v2.1 实现

## ADR 摘要（§G）

| # | 决策 | 选定方案 |
|---|------|----------|
| 1 | UVO 权威触发点 | `gate --post implement` 末尾 |
| 2 | `oracle_mode` | standard=`related_union`；strict=`full_suite` |
| 3 | smoke | `pattern_triggered`（路由/App.tsx/config-overrides/package.json scripts → required） |
| 4 | implement-qc-gate.py | thin wrapper → 调 UVO 或只读 evidence |
| 5 | benchmark | 脚本版本 pin 到 goal commit；jian-h5 replay 验收 |

## 昂贵操作审计表

| # | 操作 | 决策 | 理由 |
|---|------|------|------|
| 1 | gate plan post | **Keep** | L0 schema + handoff |
| 2 | plan-quality-gate | **Merge → gate** | 已在 gate plan post 内 |
| 3 | stage-driver mandatory yarn test | **Remove** | 负 ROI，与 UVO 重复 |
| 4 | implement-qc test+build blocker | **Demote** | UVO 一次裁决；IQ 只读 evidence |
| 5 | yarn build:beta | **Merge → UVO** | 仅 1 次 |
| 6 | runtime-smoke | **Conditional** | pattern 触发 |
| 7 | verify-review test+build | **Merge → UVO** | review-pre 只读 freshness |
| 8 | quality-gate smoke rerun | **Remove** | 读 smoke evidence |
| 9 | assemble verify subprocess | **Remove** | 读 UVO JSON |
| 10 | LLM unified review | **Keep + enrich** | reference_impl_diff |
| 11 | validate-pipeline-chain | **Keep 单次** | gate post 内 |
| 12 | noop/stale hash 空转 | **Fix bug** | diff 含 untracked；UVO git_head |

## 目标态

```text
Agent 编码 ←→ [Dev Loop scoped test 非 gate]
  → gate implement post L0
  → verification-oracle 一次
  → gate quality (smoke 条件 + chain)
  → gate review pre (UVO fresh + scope)
  → LLM review 一次
```

## 验收门槛（production）

- L1 Oracle 执行次数 = 1（UVO）
- review-pre 零重跑 test+build
- 脚本墙钟 ≤ 1.3× enhance/review 基线
- jian-h5 replay benchmark pass
- 未过 benchmark 前标记 **experimental**
