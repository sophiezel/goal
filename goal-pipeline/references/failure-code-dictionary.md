# Failure Code Dictionary（质量面 / 控制面）

机器可读副本：[`failure-codes.json`](./failure-codes.json)。

原则：**宁 blocked，不 silent pass**。降级必须写 `separation` / `confidence`，不得标 full pass。

## 声明覆盖的缺陷类（0 漏出）

| 缺陷类 | failure_code(s) | 闸门 |
|--------|-----------------|------|
| 无契约 / 顺序颠倒 | `plan_code_order`, `plan_gate_missing`, `plan_artifact_missing`, `plan_schema_incomplete` | Kernel + plan gate |
| write_set 越界 | `write_set_violation` | implement gate |
| 无机器验证 | `uvo_not_pass`, `verification_oracle_failed` | implement post UVO |
| 矩阵未覆盖 | `am_ratchet_failed` | AM ratchet |
| 空/假 diff 过 review | `packet_preflight_failed`, `review_forged` | packet preflight / review-run |
| 自评伪装独立审 | `review_undetermined`, `review_degraded_as_pass`, `review_channel_missing` | ChannelPolicy |
| secret / 保护分支 | `suspected_secret`, `protected_branch` | L0 / delivery |
| 无证据合入 | `delivery_evidence_missing`, `review_stale`, `postmerge_required` | Delivery Gate / `quality_plane_check` complete |
| 修复无效 | `noop_fix` | subject_hash ratchet |
| 修复轮次耗尽 | `review_rounds_exhausted` | merge + review gate post (`GOAL_REVIEW_MAX_ROUNDS`) |
| 状态分裂 | `project_id_mismatch`, `state_ambiguous` | 数据面 SSOT |
| 基础设施 | `infra_missing` | preflight / doctor |

## 降级语义

| 码 | 含义 | 是否可 complete |
|----|------|-----------------|
| `review_undetermined` | 无可用独立通道且未显式 degraded 证据 | **否**（除非 CI `FORCE_DETERMINISTIC` + goal mode 且 evidence 标明） |
| `review_degraded_as_pass` | 把 degraded 当成 full pass | **否** — doctor/complete 硬拦 |
| separation=`degraded` + result=`pass` | 仅当 review.md 显式 `confidence: degraded` 且 gate 接受策略 | 允许 complete，但 doctor 记 warning |

## 与 silent pass

禁止：手写 `review-unified.json` / 无 `review-run.json` 宣称 pass；跳过 UVO 仍 gate implement post。对应码：`review_forged`、`uvo_skipped_illegally`。

## Judge / Executor（fix-input 路由）

| 资产 | 规则 |
|------|------|
| `evidence/*-gate-fix-input.json` / `review-fix-input.json` | gate 失败后的**唯一**修复指令源 |
| Kernel WO | `blocked` 时 `mandatory_commands` 指向读 fix-input；禁止未读乱修 |
| quality_plane_check / complete | 禁止 silent pass；假 review / 跳 UVO 硬失败；`postmerge_policy=required` 时缺 `evidence/postmerge.md` pass → `postmerge_required` |

完成侧：`gate --post complete` / `gate --assert-complete` / `goal-pipeline-kernel complete` 均强制 `quality_plane_check --mode complete`（禁止绕过 forged/degraded 检测）。
