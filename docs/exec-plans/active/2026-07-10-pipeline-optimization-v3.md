# Pipeline Optimization v3（效率 + 准确性）

**日期**：2026-07-10  
**仓库**：`/Users/xuwei/Profession/goal`（分支 `enhance/skill-optimization2`）  
**校准样本**：jian-h5 中页 feature（非源码依赖）

## 目标

| 维度 | 目标 |
|------|------|
| 效率 | B0→B2 管线门禁墙钟节省 ~84–90%；消灭重试空转 |
| 准确性 | L1 一次 UVO；L2 语义审查；确定性 preflight + AM ratchet |

## 落地能力

| 能力 | 文件 |
|------|------|
| DiffResolver | `goal-pipeline/scripts/diff_resolver.py` + `assemble-review-packet.sh` |
| PacketPreflight PKT-01..04 | `goal-pipeline/scripts/review_packet_preflight.py` |
| code_subject_hash / artifact_hash | `verification_oracle_core.py`, `gate-guazi-flow-stage.sh` |
| Chain exclude-stage | `validate-pipeline-chain.py` + quality post |
| UVO dedup + index basename fix | `verification_oracle_core.py` |
| AM ratchet AM-01..05 | `goal-pipeline/scripts/acceptance-matrix-ratchet.py` |
| L2 prompt 收窄 | `references/unified-review-prompt.md`, `platform_review_adapter_core.py` |
| smoke handoff 自动写 | `runtime-smoke.sh` → `handoff/smoke.json` |

## 验证

```bash
cd /Users/xuwei/Profession/goal
goal-pipeline/scripts/fixtures/guazi-flow-gate/run-all-gate-tests.sh
```

**结果**：2026-07-10 全绿（含 `test-review-packet-preflight.sh`、`test-code-subject-hash.sh`）

## 部署

```bash
bash goal-pipeline/scripts/sync-install-repo.sh --from-dev /Users/xuwei/Profession/goal --deploy-only
```

## 外场决策门（待跑）

- jian-h5 replay：`benchmark-pipeline-replay.sh` + 任务 `docs/guazi-flow/2026-07-10-检测支持3天内回捞收车`
- 目标：B2 ≤8 min，`T_retry=0`

## Agent 工作流（SKILL）

plan → implement → **commit feature** → gates（稳定 `reference_branch` diff）
