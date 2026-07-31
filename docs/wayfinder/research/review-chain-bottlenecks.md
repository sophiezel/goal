# Research: 独立审核链（review-chain）质量与效率瓶颈

**Wayfinder 工单**：[sophiezel/goal#6](https://github.com/sophiezel/goal/issues/6)  
**父地图**：[goal#1 — 交付质量与全链路效率](https://github.com/sophiezel/goal/issues/1)  
**代码事实来源**：`goal-pipeline/scripts/`（截至本稿编写时）

---

## 1. 链路与入口

| 入口 | 职责 |
| --- | --- |
| `goal-run-review-chain.sh` | 编排：channel guard →（assemble + L2 review）或 kernel `cli.py run` → `merge-review-issues.sh` |
| `kernel/review/cli.py run` | 与链路等价的原子三步：`assemble-review-packet.sh` → `run-independent-review.sh` → `merge-review-issues.sh` |
| `goal-advance-stage.sh` | review 阶段建议命令序列（含 `review_depth.py --persist`） |
| `goal-stage-driver.sh` | 解析 `review_track.py`（single/dual），single 时不再 lazy-load `guazi-flow-review` Agent |

**典型 happy path（有可用 API 通道 + 存在 `kernel/review/cli.py`）**

```
review-channel-guard (--resolve, JSON)
  → kernel.review.cli run
       → assemble-review-packet.sh
       → run-independent-review.sh
            → verify-review.sh (默认 scope+secret only)
            → review_fallback_orchestrator.py (API cascade)
       → merge-review-issues.sh
```

**Legacy path（无 kernel CLI）**：guard → assemble → `run-independent-review.sh` → merge。

---

## 2. 确定性 vs LLM 步骤

### 2.1 纯确定性（无模型调用）

| 步骤 | 脚本/模块 | 说明 |
| --- | --- | --- |
| 路径解析 | `resolve-artifact-paths.py` | task/evidence/handoff 目录 SSOT |
| 通道探测 | `review-channel-guard.py` → `detect-review-channels`（+ 可选 short probe） | 结果可经 `GOAL_REVIEW_DETECT_CACHE` 跨 guard / orchestrator 复用（TTL ~10min） |
| 组包 | `assemble-review-packet.sh` | `diff_resolver`、index 切片、UVO 嵌入、rubric excerpt、`review_packet_preflight.run_preflight` |
| 预检 | `review_packet_preflight.py` | PKT-01~04：src 文件、diff 体积、UVO overall、integrity |
| L1 校验 | `verify-review.sh` | review 内默认 `GOAL_SKIP_TEST/BUILD/LINT=1`（UVO 已在 implement post 跑过）；仍跑 scope + secret |
| 深度/轨道 | `review_depth.py`、`review_track.py` | adaptive light/full；single/dual 策略 |
| 合并 | `merge-review-issues.sh` | 将 `review-unified.json` 等与 gate 契约对齐 |
| 确定性「审核」 | `provider=deterministic` | **0 次 LLM**；`run-independent-review.sh` 内 `invocation_count=0`，且 `pass` 会降为 `review_undetermined`（`separation_confidence=low`） |

### 2.2 LLM / 外部推理步骤

| 步骤 | 触发条件 | 独立性含义 |
| --- | --- | --- |
| `platform-review-adapter.sh` | `has_candidates=1` 且非 `deterministic` / `unreachable` | 主 L2：与 implement Agent 不同 provider/model 栈 |
| `review_fallback_orchestrator.py` | 同上；编排多 provider、packet 变体、分片 | 失败时垂直降级（full→scoped）、水平换 provider |
| `readonly_subagent_review` | API cascade 失败后且 Ollama 可达（或 mock） | `separation_confidence=medium`；进程隔离子路径 |
| **Dual track（编排层）** | `review_track=dual` + stage driver | 额外 **guazi-flow-review Agent turn**（与链内 unified channel 不同层）；single track 用 packet 内嵌 rubric + `goal-review` only |

### 2.3 `channel` 与 unified 模式

- `GOAL_REVIEW_MODE` 默认 `unified`；若 packet 中 `guazi_flow_rubric` 无实质内容，**运行时降为 `goal`**（仅 goal checklist channel）。
- Orchestrator `--channel unified|goal` 传给 adapter；**不是**自动两次 LLM（goal + gf 各一遍），除非 adapter/上层显式双调（当前链以单次 cascade + unified 合并为主）。

---

## 3. LLM invocation 次数（数量级）

以下指 **L2 adapter / orchestrator** 成功路径与最坏路径；不含 IDE 内 guazi-flow-review Agent（dual track）。

| 场景 | 典型 invocation | 上界（默认 env） |
| --- | --- | --- |
| 首次 API 成功（small diff, light depth） | **1** | 1 |
| diff > 25KB，首次 full 超时/undetermined | **2**（full + scoped 垂直） | 同 provider 内 ≤2 variants |
| 换 provider 重试 | +1 per candidate | `GOAL_REVIEW_MAX_API_ATTEMPTS` 默认 **3**（strict tier **5**） |
| full depth + 多分片并行 | 每 shard 1 次（并行） | shards × 1（失败可再 scoped）；workers ≤4 |
| readonly 兜底 | +1 | 在 budget 剩余内 |
| **deterministic / 0 channel** | **0** | 0 |
| **unreachable（probe 失败）** | **0**（硬停） | 0 |

**时间预算（与次数相乘）**

- `GOAL_REVIEW_BUDGET_SEC`：默认 480（strict 900）
- `GOAL_REVIEW_ATTEMPT_TIMEOUT_SEC`：默认 90/次
- 最坏粗算：3 providers × (full+scoped) × 90s 量级 → 设计上靠 **unreachable fail-fast**、**consecutive_infra_abort（≥2）**、**budget_exhausted** 截断，避免打满 480×N。

**Token 热点（packet 侧）**

- `diff`：默认最多 **80_000** bytes（`assemble-review-packet.sh --max-diff-bytes`）
- scoped 重试：**25_000** bytes（orchestrator `shrink_packet`）
- 契约字段：pseudocode **4_000** chars；acceptance/design 等多段硬截断
- `guazi_flow_rubric`：excerpt + `skill_summary` ≤2500；scoped 变体再截到 ~1200/字段

---

## 4. Dual vs single track

| 维度 | **dual**（默认） | **single**（`GOAL_REVIEW_TRACK=single` / state `review_policy.track` / P2 后 XS·S + `GOAL_REVIEW_SINGLE_DEFAULT=1`） |
| --- | --- | --- |
| Agent 加载 | `guazi-flow-review` + `goal-review` | 仅 `goal-review`；rubric 由 `assemble` 嵌入 packet |
| 链脚本 | 仍走 `goal-run-review-chain.sh` unified 分支 | 同左；**不减少** orchestrator 的 API 次数，减少的是 **前置 Agent turn** 与上下文加载 |
| 质量权衡 | GF 技能全文 + 独立 Agent 视角 | 依赖 packet 内 rubric excerpt 质量；适合小 tier、eval ≥95% 两轮后翻转 |

解析逻辑：`review_track.py` — env override > state > auto XS/S（需 flag）> default **dual**。

---

## 5. Degraded 模式与独立审核置信度

| 模式 | 触发 | 产物/行为 | 对「独立性」 |
| --- | --- | --- | --- |
| `deterministic_scope_only` | `has_candidates=0`；或 `GOAL_REVIEW_DETERMINISTIC_ONLY=1` | `review-channel-degraded.json`；`provider=deterministic` | **低**；非 L2；结果倾向 `review_undetermined` |
| `channel_unreachable` | keys 在但 short probe 失败 | `separation=blocked`；`CH-UNREACHABLE`；cascade 跳过 | **无 L2**；`review_undetermined`，提示 `GOAL_REVIEW_CURSOR_TASK=1` |
| `GOAL_REVIEW_FORCE_DETERMINISTIC=1` + 已配置通道 | guard 可 block（exit 2） | 链内 forced 分支仍可能跑 deterministic | 人为降级；guard 防静默降级 |
| API `fallback_exhausted` | 候选耗尽 + readonly 失败 | `FB-EXHAUST` / `review_undetermined` | 无有效独立结论 |
| `readonly-subagent` | cascade 后兜底 | `fallback_layer=readonly_subagent` | **中等** separation |
| infra-only blockers | ADP-ERR / FB-EXHAUST / CH-* | `result=review_undetermined`（避免当业务 not_pass） | 区分基建 vs 实现缺陷 |

`run-independent-review.sh` 将 verify 失败与 adapter issues 合并；**业务 not_pass** 与 **通道 undetermined** 通过 `error_kind` / issue id 分流。

---

## 6. Packet 质量风险（误报 / 漏报）

| 风险 | 机制 | 误报 | 漏报 |
| --- | --- | --- | --- |
| diff 截断 | 80k / scoped 25k | LLM 对未包含 hunks 过严/过松 | **未审代码** 漏出 |
| `GOAL_REVIEW_DIFF_SOURCE=code_subject_hash` vs 实现 diff | 默认 hash 路径 | 与评审人直觉不一致 | 评审对象与真实 PR diff 偏离 |
| PKT-01 无 `src/**` | preflight fail | 文档/配置类改动无法进 L2 | 阻止无意义 API 花费 |
| PKT-02 小 diff | <256B 且无 ref branch | 误拦极小修复 | — |
| PKT-03 UVO ≠ pass | 组包前硬失败 | 正确挡 implement 质量债 | — |
| UVO 缺失 | assemble 内 deterministic_checks 标错；preflight 拦 | — | 若绕过 preflight 则 L2 缺 L1 锚点 |
| rubric excerpt | 仅片段 + hash | GF 条款理解偏窄 | **契约边角** 漏检 |
| `issues_gf` 从旧 `review.md` 解析 | 表格行 raw | 陈旧 GF 意见污染 packet | — |
| light depth | 仅 scoped variant | 更快 | 大变更默认 full；边界在 5 files / 25kB |
| 并行 shard 合并 | `merge_unified_reviews` | 分片边界 issue 重复/遗漏 | 跨文件交互缺陷 |

---

## 7. 效率瓶颈（按优先级）

### P0 — 高耗时 × 高频

1. **L2 API cascade**（90s × attempts × variants × shards）— 主时钟；infra 失败时靠 fail-fast，成功时单次通常 1 call。
2. **Dual track 额外 guazi-flow-review Agent** — 与链脚本串行叠加；XS/S single track 是已设计开关。
3. **detect + probe** — 每链至少 1 次；重复调用靠 `GOAL_REVIEW_DETECT_CACHE` 缓解。

### P1 — 中等

4. **assemble-review-packet** — git diff + rubric IO；已避免 subprocess 调 `verify-review`（改读 UVO）。
5. **verify-review 重复** — review 默认 skip test/lint/build；需完整重跑时 `GOAL_REVIEW_FULL_VERIFY=1`。
6. **merge-review-issues** — 通常轻量；依赖上游 unified 体积。

### P2 — 优化余量

7. **review_depth adaptive** — 小变更 light，少 vertical full→scoped。
8. **分片并行** — 仅 `depth=full` 且未 `GOAL_REVIEW_DISABLE_SHARD=1`。
9. **kernel `cli run`** — 减少 shell 分叉与重复 assemble 路径选择。

---

## 8. 提速手段 vs「独立性不降」约束

| 手段 | 节省 | 独立性约束 |
| --- | --- | --- |
| `GOAL_REVIEW_DETECT_CACHE` | 重复 detect/probe | 安全：只读缓存探测结果 |
| review 内 skip test/lint/build | 避免与 UVO 重复 | 安全：scope/secret 仍跑；implement post 须已有 UVO |
| unreachable / 0-channel fail-fast | 避免空烧 240s×N | 安全：不降格为假 pass；显式 undetermined |
| `GOAL_REVIEW_TRACK=single`（XS/S） | 去掉 GF Agent turn | 需 eval 门禁；rubric 仍在 packet |
| `GOAL_REVIEW_DEPTH=light` / adaptive | 少 scoped 重试、不分片 | 大变更保持 full；strict tier 强制 full |
| 并行 shard | wall-clock | 每 shard 仍独立 adapter；合并逻辑须防漏 |
| 提高 `max-diff-bytes` | 减截断漏报 | **损害质量**：更大 token、更慢；应配 depth 而非盲目放大 |
| 跳过 assemble / preflight | 快 | **禁止**：会放大漏报与无 src diff |
| 静默 deterministic | 快 | **禁止**：guard + `separation_confidence` + undetermined 已防假阳性 pass |

---

## 9. 建议后续（与 Wayfinder 衔接）

1. **度量**：从 `evidence/review-run.json` 汇总 `latency_ms`、`attempts[]`、`fallback_layer`、`invocation_count` — 对接 issue #7 耗时看板（依赖 #2 节点清单）。
2. **实验**：XS/S single default 翻转前复跑 `p2-eval-runbook` 两轮 ≥95%。
3. **Packet**：对「截断率 / PKT 失败率 / diff_source 分布」做任务级统计，区分 implement 问题与管线问题。
4. **产品**：`channel_unreachable` 与 `FB-EXHAUST` 统一 UX（Cursor Task vs 修 key），避免与业务 not_pass 混淆。

---

## 10. 关键环境变量速查

| 变量 | 默认 | 作用 |
| --- | --- | --- |
| `GOAL_REVIEW_MODE` | unified | unified→无 rubric 则 goal |
| `GOAL_REVIEW_TRACK` | — | single / dual |
| `GOAL_REVIEW_BUDGET_SEC` | 480 | 总预算 |
| `GOAL_REVIEW_ATTEMPT_TIMEOUT_SEC` | 90 | 单次 adapter |
| `GOAL_REVIEW_MAX_API_ATTEMPTS` | 3 | provider 候选数 |
| `GOAL_REVIEW_DEPTH` | adaptive | light / full |
| `GOAL_REVIEW_FULL_VERIFY` | 0 | 1=review 内全量 verify |
| `GOAL_REVIEW_FORCE_DETERMINISTIC` | — | 强制确定性（受 guard 约束） |
| `GOAL_REVIEW_PROBE` | 1 | 0=跳过连通性 probe（fixture） |
| `GOAL_REVIEW_DISABLE_SHARD` | 0 | 1=禁用分片并行 |
| `GOAL_REVIEW_DETECT_CACHE` | 链内 mktemp | 探测结果共享路径 |

---

## 附录：文件索引

- `goal-pipeline/scripts/goal-run-review-chain.sh`
- `goal-pipeline/scripts/run-independent-review.sh`
- `goal-pipeline/scripts/assemble-review-packet.sh`
- `goal-pipeline/scripts/review_packet_preflight.py`
- `goal-pipeline/scripts/review_fallback_orchestrator.py`
- `goal-pipeline/scripts/review_track.py`
- `goal-pipeline/scripts/review_depth.py`
- `goal-pipeline/scripts/review-channel-guard.py`
- `goal-pipeline/kernel/review/cli.py`
