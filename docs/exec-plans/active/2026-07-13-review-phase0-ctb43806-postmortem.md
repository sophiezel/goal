# CTB-43806 Review 阻塞复盘与 Phase 0–2 落地

**分支：** `enhance/skill-optimization2`  
**日期：** 2026-07-13  
**关联任务：** jian-h5 CTB-43806-A4（证据来源，代码改动仅在 goal 仓）

## 现象

| 阶段 | 墙钟 | 占比 |
|------|------|------|
| plan + implement + quality | ~12 min | ~26% |
| review（含阻塞） | ~31 min | ~67% |
| complete + handoff refresh | ~2 min | ~7% |

Review 根因：**verify-review 全量 test 重复** + **88KB prompt / 61KB working_tree diff** + **DeepSeek 120s 硬超时无 fallback** + **Agent 盲重试**。

## Phase 0 交付

| 项 | 文件 | 效果 |
|----|------|------|
| UVO 去重 | `verify-review.sh` | fresh UVO → 跳过 test/build |
| Packet 瘦身 | `diff_resolver.py`, `assemble-review-packet.sh` | 默认 `code_subject_hash`（src/** only） |
| 降级链 | `review_fallback_orchestrator.py`, `run-independent-review.sh` | API cascade + attempts 审计 |
| Adapter 加固 | `platform_review_adapter_core.py` | `max_tokens=4096`、结构化 timeout |
| 文档 | `ARCHITECTURE.md` §4.3/§4.4 | 降级链与环境变量 |

## Phase 1 交付

| 项 | 文件 | 效果 |
|----|------|------|
| Packet 分片 | `review_packet_shard.py` | 按 list/detail/services/components 拆 diff |
| 并行 L2 + merge | `review_fallback_orchestrator.py` | full depth 多 shard 并行 mock/API |
| review_depth | `review_depth.py` | adaptive/light/full + state 持久化 |
| zh-CN | `merge_review_core.py`, `unified-review-prompt.md` | annex/ transcript 中文 |
| AM-06 | `acceptance-matrix-ratchet.py` | C04 无缝刷新 vs 全页 loading 警告 |
| 编排 | `goal-advance-stage.sh`, `goal-state-schema.md` | review 前 commit + depth 提示 |

## Phase 2 交付

| 项 | 文件 | 效果 |
|----|------|------|
| Layer 3 readonly | `readonly_subagent_review.py` | API 耗尽 → ollama/mock subagent（separation=medium） |
| strict tier 自动升级 | `quality_policy_tier.py`, `gate-guazi-flow-stage.sh` | auth/payment/security write_set → strict |
| Benchmark v2 | `benchmark-pipeline-replay.sh` | CTB-43806 基线对比 + review chain score ≥7/8 |
| Postmortem 模板 | `docs/exec-plans/active/_template-pipeline-postmortem.md` | 可复用复盘结构 |

### 预期改进（CTB-43806 对照）

| 指标 | 优化前 | 目标 |
|------|--------|------|
| T_review | ~31 min | ≤8 min |
| T_retry | 3+ | 0（fail-fast cascade） |
| packet diff | 61KB | ≤25KB（scoped） |
| separation | none（同会话） | medium+（API/readonly） |

## 验证

```bash
cd goal-pipeline/scripts/fixtures/guazi-flow-gate && bash run-all-gate-tests.sh
bash goal-pipeline/scripts/benchmark-pipeline-replay.sh \
  --task-dir goal-pipeline/scripts/fixtures/guazi-flow-gate/plan-good \
  --profile ctb43806
```

## 部署

```bash
cd /Users/xuwei/Profession/goal && bash install.sh --agent cursor
```
