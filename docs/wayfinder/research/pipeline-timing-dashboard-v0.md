# Pipeline timing dashboard v0（低保真报告规格）

> **Wayfinder [#7](https://github.com/sophiezel/goal/issues/7)** — 节点耗时与产物质量看板草案。  
> **节点命名 SSOT**：[pipeline-node-catalog.md](pipeline-node-catalog.md)（#2）。  
> **样本路径**：jian-h5 CTB-44243 · IQ-10 修复后 implement post pass — [iq10-handoff-fix-run-log.md](iq10-handoff-fix-run-log.md)。

## 目标（v0）

用 **Markdown 报告模板**（后续可换静态 HTML）汇总单次 guazi-flow-goal 运行的效率面，不要求新运行时依赖：

1. **五阶段墙钟**（plan → implement → quality → review → complete），与 gate 边界 `record-pipeline-timing` 对齐。
2. **implement 内 UVO 子步骤**（scope / secret / lint / typecheck / test:* / build）及 `duration_ms`、跳过/缓存标记。
3. **重复运行标记**（同 stage 多次 `start`、review `attempt` substep、noop_fix 重试）。
4. **SLA 提示** — 与 `pipeline-postmortem.py` 的 `sla_hints` 及 task_tier 叙事一致（v0 人工对照，无自动 breach code）。
5. **高耗时低价值候选** — 规则表驱动标注（见 §5）。

## 输入 SSOT（只读）

| 产物 | 路径 | 度量字段 |
|------|------|----------|
| Stage timing | `evidence/pipeline-timing.json` | `stages.<stage>.duration_ms`, `started_at_utc`, `events[]`, `substeps` |
| UVO | `evidence/verification-oracle.json` | `duration_ms`, `steps[].{id,duration_ms,ok,pass,command,cmd,output}` |
| Smoke | `evidence/runtime-smoke.md` | frontmatter `duration_ms`, `dev_cmd` |
| Review | `evidence/review-run.json` | `latency_ms`, `invocation_count`, `provider` |
| Blocked 复盘 | `pipeline-postmortem.py` 输出 | `stages_timed`, `recommendations`, `sla_hints` |
| Handoff 完成点 | `handoff/*.json` → `gate.passed_at` | 与 timing end 交叉校验 |

`resolve-artifact-paths` 下 goal evidence 与 repo `docs/guazi-flow/<task>/evidence` 可能 split；看板生成器须与 gate 相同解析路径。

## `pipeline-timing.json` 形状（v0 schema）

与 `goal-pipeline/scripts/record-pipeline-timing.py` 一致：

```json
{
  "schema_version": 1,
  "timezone": "UTC",
  "updated_at_utc": "2026-08-01T00:00:00Z",
  "stages": {
    "plan": {
      "started_at_utc": "2026-08-01T00:00:00Z",
      "last_timestamp_utc": "2026-08-01T00:02:00Z",
      "duration_ms": 120000,
      "events": [
        { "event": "start", "timestamp_utc": "..." },
        { "event": "mark", "timestamp_utc": "...", "substep": "cwiki", "duration_ms": 30000 },
        { "event": "end", "timestamp_utc": "...", "duration_ms": 120000 }
      ],
      "substeps": {
        "cwiki": { "duration_ms": 30000, "last_timestamp_utc": "...", "events": [] },
        "attempt": { "duration_ms": 900, "events": [] }
      }
    },
    "implement": { "events": [], "duration_ms": 600000 },
    "quality": {},
    "review": {},
    "complete": {}
  }
}
```

**Stage 键（与 #2 Node name 映射）**

| `stages` key | Catalog 节点 |
|--------------|----------------|
| `plan` | plan gate --pre/post |
| `implement` | implement gate --pre/post（含 UVO / IQ / contract-conformance，墙钟边界） |
| `quality` | quality gate --post（含 runtime-smoke） |
| `review` | review gate --pre/post + review chain |
| `complete` | complete gate --pre/post |

遗留 `smoke` stage 键若存在，v0 报告合并进 **quality** 行（与 `delivery_report.py` 一致）。

**重复运行**：对 `events` 中 `event=="start"` 计数 `>1` 时，报告标注 `retry_count` 并用 `last_timestamp_utc` 与 `started_at_utc` 差值作墙钟上界（CTB-43532 fixture 仅 plan 多次 start、无 end — 见缺口）。

## UVO `steps[]` 形状（v0 子步骤表）

`verification_oracle_core.py` 写入；典型 `id`：

| step `id` | 含义 | 报告列 |
|-----------|------|--------|
| `scope` | write_set / diff 范围 | pass, duration_ms（常为 0） |
| `secret` | 密钥扫描 | pass |
| `lint` | lint 命令 | pass, duration_ms, output_tail |
| `typecheck` | tsc / 类型检查 | ok, duration_ms |
| `test:<profile>` | 并行测试槽 | ok, duration_ms, source=`uvo_parallel` |
| `build` | build:beta 等 | ok, duration_ms；`command`/`output` 含 **skipped** / UVO cache hit |

顶层 `verification-oracle.json` 另有 `duration_ms`（整段 UVO 墙钟）、`code_subject_hash`、`smoke_required`。

IQ-10 样本（implement post pass）：UVO **pass**，build **skipped**（同 hash 缓存）— 报告须在 UVO 小节显式标 **低价值重复风险已规避** vs **IQ-10 曾 fail 的独立路径**。

## v0 Markdown 报告节（模板）

```markdown
# Pipeline timing — {task_id} ({git_short_head})

## Summary
| Stage | Wall ms | SLA hint | Retries | Notes |
| plan | … | tier default | … | … |
…

## UVO (implement gate)
| Step | ms | Pass | Note |
| build | 0 | yes | skipped — cache hit |

## Review provenance
latency_ms, invocations, channels

## Postmortem / SLA
(paste pipeline-postmortem json or bullets)

## Low-value / high-cost flags
- [ ] …
```

## SLA 对齐（v0）

| 来源 | 字段 | v0 用法 |
|------|------|---------|
| `pipeline-postmortem.py` | `sla_hints.target_total_min`（`40-50`） | Summary 脚注 |
| `pipeline-postmortem.py` | `zero_plan_code_order_leaks` | 与 failure_code 并列 |
| `task-tier-matrix.md` / plan.json `task_tier` | 分层验证深度 | UVO 行注释「XS 可跳过 build」等 |
| `efficiency_plane_check.py` | `timezone==UTC` | 报告头校验 |

自动 SLA breach **不在 v0**；`delivery_report._ms_for` 读 `wall_ms`/`ms` 与 recorder 写的 `duration_ms` 不一致 — 看板 v0 **以 `pipeline-timing.json` 的 `duration_ms` 为准**。

## 高耗时低价值候选（规则 v0）

| 规则 ID | 条件 | 标注 |
|---------|------|------|
| R1 | UVO step `build` + output 含 `cache hit` / `skipped` 且 stage `implement.duration_ms` 仍 > SLA 分位 | Gate 墙钟含 Agent，非 build |
| R2 | 同 stage `start` 事件 ≥ 2 且无对应 `end` | 中断重试 / 泄漏 start |
| R3 | `review.substeps.attempt` 存在且 `duration_ms` 极小 | 快速失败轮次 |
| R4 | UVO pass + `contract-conformance` / IQ 曾 fail（旁证 JSON） | 质量漏出 vs 验证耗时 |
| R5 | `runtime-smoke` duration 高但 `smoke_required=false` 仍执行 | 效率面冗余（需 tier 上下文） |

## 缺口与 v1

1. Substep 默认未接线（catalog §耗时钩子缺口）— v0 报告 **有则展示，无则 N/A**。
2. 无仓库内 HTML prototype 文件；v1 目标：`docs/wayfinder/prototypes/pipeline-timing-report.html` + `render-timing-report.py`。
3. 与 `optimization-spec-outline-v0.md` P1 合并时，增加「效率验收」检查项：单次 run 须能生成上述 Markdown。

## 使用说明（维护者）

1. 选定 `TASK_DIR` 与 `STATE_FILE`（与 gate 相同）。
2. 确认 `evidence/pipeline-timing.json` 存在且 `timezone` 为 `UTC`。
3. 手工或由脚本填充 §模板；blocked 时并行运行：  
   `pipeline-postmortem.py --state-file "$STATE" --task-dir "$TASK_DIR" --format json`
4. 对照 [pipeline-node-catalog.md](pipeline-node-catalog.md) 核对 stage 名与节点表。

---

*v0 — 2026-08-01 — Wayfinder #7.*
