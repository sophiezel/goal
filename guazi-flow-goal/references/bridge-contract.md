# Guazi Extension Contract（v1.4 扩展契约）

本文件定义 **guazi-flow-goal 独立管线** 的扩展字段、产物分层与阶段边界。v1.4 **不是** goal-pipeline 的桥接层；两条管线仅共享 **review-kernel** 公共服务。

**SSOT 配套：** `guazi-flow-goal/SKILL.md`、`references/guazi-flow-state-schema.md`、`references/guazi-flow-integration.md`

## NEVER

- **NEVER exec `goal-pipeline/scripts/*` 或读写 `~/.goal-pipeline/`**
- **NEVER 用 goal skill 标记冒充 guazi**（`goal-plan` / `goal-implement` 等仅属 goal-pipeline）
- **NEVER 输出 `[N/5] ✅` 而未 `guazi-gate-stage.sh --post` exit 0**
- **NEVER 在 plan gate 通过前写业务代码**（`plan_code_order` 硬阻断）
- **NEVER 绕过 review-kernel**——MUST assemble → run-review-chain → merge → gate --post review
- **NEVER 在 guazi state 中覆盖非 guazi 命名空间字段**——`guazi_flow_*` / `artifact_layout` 为 guazi 扩展；勿写入 goal 专用 `pipeline_track` 语义

## 管线组件（v1.4）

| 组件 | 路径 |
|------|------|
| Install | `guazi-flow-goal/scripts/guazi-install.sh` → `~/.guazi-flow/` |
| Gate | `$GUAZI_STATE_HOME/scripts/guazi-gate-stage.sh` |
| Advance | `$GUAZI_STATE_HOME/scripts/guazi-advance-stage.sh` |
| Review chain | `$REVIEW_KERNEL_HOME/bin/run-review-chain.sh` |
| State | `$GUAZI_STATE_HOME/projects/<pid>/<branch>/<task>/state.json` |

环境变量：`GUAZI_HOME`（默认 `~/.guazi-flow`）、`GUAZI_STATE_HOME`（默认 `$GUAZI_HOME/state`）、`REVIEW_KERNEL_HOME`。

运行时脚本内若仍 `source goal-env-bootstrap.sh`，仅为 **兼容 shim**（映射 `GOAL_*` ← `GUAZI_*`），不代表依赖 goal-pipeline 安装。

## 任务目录与产物分层

- **默认 task_dir：** `docs/guazi-flow/<task>/`（相对 `project_root`）
- **Tier-G（进 git）：** `index.md`、`evidence/review.md`、`evidence/complete.md`、`evidence/cwiki/**` 等
- **Tier-R（runtime）：** `handoff/*.json`、review annex JSON、fix-input、timing — 由 `artifact_layout.runtime_root` 或 `repo_full` 模式解析

路径解析：`$GUAZI_STATE_HOME/scripts/resolve-artifact-paths.py`（guazi 默认 `docs/guazi-flow/`）。

## 阶段 SKILL 与 gate 映射

| Gate stage | Skill（执行记录标记） | Lazy-load SKILL |
|------------|----------------------|-----------------|
| plan | `guazi-flow-plan` | `guazi-flow-plan` |
| implement | `guazi-flow-implement` | `guazi-flow-implement` |
| quality | `goal-quality`（质检脚本） | `guazi-flow-implement` / quality 子流程 |
| review | unified review + 可选 wrapper | `guazi-flow-review`（`review_track=dual`） |
| complete | `guazi-flow-complete` | `guazi-flow-complete` |

`smoke` 在 default profile 下 **已废弃**为独立 gate stage；runtime smoke 并入 quality 路径。

## 质检防火墙（共享脚本，guazi runtime 调用）

Plan/implement post 经 gate 内嵌调用（脚本位于 `$GUAZI_STATE_HOME/scripts/`）：

- `plan-quality-gate.py`（PQ-01..06）
- `implement-qc-gate.py`（IQ-01..02）
- `contract-conformance-check.py`（IQ-10，index 含 API 映射表时）

这些脚本与 goal-pipeline **同源拷贝**，但 guazi **通过自有 install bundle 部署**，不依赖 `~/.goal-pipeline/`。

## Review 契约（v1.4）

- **主路径：** review-kernel unified 分支（单次 LLM，`review-unified.json`）
- **`review_track=single`（XS/S 快车道）：** 不加载 `guazi-flow-review` wrapper；packet 内嵌 rubric
- **`review_track=dual`：** 可加载 `guazi-flow-review`；merge 层可区分 `channel`（guazi fork 的 `merge.py` 保留 gf 段）
- **统计口径：** `issues_*_count` 来自 `review-unified.json` 按 `channel` 过滤，禁止数 markdown 表格行

## 扩展字段（摘要）

完整 schema 见 `guazi-flow-state-schema.md`。`state.json` 最小集：

```json
{
  "status": "active",
  "project_root": "/abs/path/to/repo",
  "guazi_flow_task": "docs/guazi-flow/<task>",
  "guazi_flow_profile": "h5",
  "guazi_flow_stages": {
    "plan": {"gate": {"passed_at": "2026-01-01T00:00:00Z", "post_exit_code": 0}},
    "implement": {"gate": {"passed_at": "2026-01-01T00:00:00Z", "post_exit_code": 0}}
  },
  "artifact_layout": {
    "mode": "split",
    "repo_task_dir": "docs/guazi-flow/<task>",
    "runtime_root": "/path/to/runtime/artifacts"
  }
}
```

`guazi-advance-stage.sh` 读取 `guazi_flow_stages.*.gate` 与 handoff 新鲜度推进阶段。

## v1.4 废止（勿再文档化）

- `--mode guazi` adapter / `gate-guazi-flow-stage.sh` 薄包装
- `GF_USE_NATIVE_DRIVER` / `gf-stage-driver.sh`
- dual-track `pipeline_track=evolution` 与 goal 降级表
- `guazi_flow_contract_enrich.py`（B3 契约融入脚本）
- goal-pipeline 作为 guazi 运行时 fallback

历史 v1.3 桥接叙述见 `references/archive/v1.3-bridge/bridge-contract.v1.3.md`（若已归档）。

## 边缘场景

| 场景 | 行为 |
|------|------|
| `guazi-install.sh` 未执行 | `blocked(infra_missing)`；**不** fallback goal-pipeline |
| `REVIEW_KERNEL_HOME` 缺失 | review 阶段 blocked；先 `shared/review-kernel/install.sh` |
| gate `--post` 失败 | 读 `evidence/<stage>-gate-fix-input.json`；禁止盲重试 |
| `review_track=single` 且 `gf_skill_attested=true` | gate review post 失败（B8） |
| handoff hash 与 index 漂移 | `refresh-handoffs-after-index.sh` 按 contract/execution 分流 cascade |
