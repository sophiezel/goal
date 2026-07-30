# Guazi Flow State Schema（扩展字段）

基础 state schema 见 `goal-pipeline/references/goal-state-schema.md`。
本文件仅定义 guazi-flow 集成时的扩展字段和写入边界。

## 项目目录结构（guazi-flow 集成时）

```
~/.goal-pipeline/state/                              ← goal 全局目录（同基础 schema）
├── config.json
├── projects/<pid>/<branch>/<task>/
│   ├── state.json                          ← 含 guazi-flow 扩展字段
│   └── .lock
├── archive/
└── scripts/

<project>/                                   ← 用户项目（不受影响）
├── .guazi-flow/
│   └── config.local.json                    ← JIRA_TOKEN / repos（goal 不碰）
└── docs/guazi-flow/<task>/
    ├── index.md                             ← Tier-G（进 git）
    ├── evidence/review.md                   ← Tier-G gate 产物
    ├── evidence/complete.md                 ← Tier-G
    ├── evidence/cwiki/**                    ← Tier-G
    └── units/*.md

~/.goal-pipeline/state/projects/<pid>/<branch>/<task>/artifacts/   ← Tier-R（不进 git）
├── handoff/*.json
└── evidence/review-unified.json, review-run.json, ...
```

## guazi-flow 扩展字段

位置: `~/.goal-pipeline/state/projects/<pid>/<branch>/<task>/state.json`（基础字段见 goal-pipeline schema）

```json
{
  "project_root": "/abs/path/to/project",
  "guazi_flow_available": true,
  "guazi_flow_task": "docs/guazi-flow/<task>",
  "guazi_flow_profile": "h5",
  "task_tier": "M",
  "task_tier_meta": {
    "signals": ["new_page_dirs:1", "cross_domain:pages+services+App"],
    "p50_wall_min": 45,
    "p90_wall_min": 70,
    "parallel_strategy": "subagent_dag_3_4"
  },
  "guazi_flow_stages": {
    "plan": {"used": true, "skill": "guazi-flow-plan", "gate": {"script": "gate-guazi-flow-stage.sh", "version": 1, "passed_at": "2026-01-01T00:00:00Z", "handoff_hash": "abc123"}},
    "implement": {"used": true},
    "review": {"used": true},
    "complete": {"used": true}
  },
  "artifact_layout": {
    "mode": "split",
    "repo_task_dir": "docs/guazi-flow/<task>",
    "runtime_root": "/Users/you/.goal-state/projects/<pid>/<branch>/<task>/artifacts"
  }
}
```

### task_tier（plan 结束时写入）

见 `goal-pipeline/references/task-tier-matrix.md`。档位由信号自动判定；Agent **不得**把 M/L 压成 XS 硬卡 20m。并行策略（Pack F）按档启用。

### artifact_layout

| 字段 | 说明 |
|------|------|
| `mode` | `split`（默认，新 goal）或 `repo_full`（兼容旧行为） |
| `repo_task_dir` | Tier-G 任务目录（相对或绝对路径） |
| `runtime_root` | Tier-R 根目录（handoff + goal evidence annex） |

路径解析见 `references/artifact-tier-policy.md` 与 `resolve-artifact-paths.py`。
Phase 1 创建 goal 时写入；已有 task 用 `goal-pipeline-doctor.sh --migrate-artifacts` 迁移。

### 字段说明

- `project_root`: 项目根目录绝对路径（Phase 1 Step 5 写入，供 stop hook / goal-advance-stage 匹配 Cursor workspace）
- `guazi_flow_available`: guazi-flow-* 是否可用（启动时检测）
- `guazi_flow_task`: guazi-flow 任务目录路径，仅集成时存在
- `guazi_flow_profile`: 技术栈 profile（h5/react/service/rn 等）
- `guazi_flow_stages`: 各阶段是否使用了 guazi-flow 版本



### guazi_flow_stages.*.gate

每个使用 guazi-flow 的阶段追加 `gate` 对象（**仅 gate 脚本可写 `passed_at`**）：

```json
"gate": {
  "script": "gate-guazi-flow-stage.sh",
  "version": 1,
  "passed_at": "<ISO8601>",
  "handoff_hash": "<sha256[:16] of handoff/<stage>.json>"
}
```

阶段推进条件：`gate.passed_at` 存在且 `handoff/<stage>.json` hash 与 `handoff_hash` 一致。
Agent 禁止手改 `gate.passed_at` 或 `handoff/*.json`。

`guazi_flow_available=false` 时，上述字段全部为空或不存在。goal-pipeline 完全独立运行。

### 写入边界

- 扩展字段只能**追加**到 state.json，不覆盖 `pipeline` / `platform` / `review_config` 等管线字段
- `.guazi-flow/config.local.json` 只存 JIRA_TOKEN / FIGMA_ACCESS_TOKEN / repos 等 guazi-flow 自身字段，**不含任何 goal 产物**
- **Tier-G**（guazi-flow 契约）：写入 `docs/guazi-flow/<task>/` — `index.md`、`evidence/review.md`、`evidence/complete.md`、`evidence/cwiki/**`
- **Tier-R**（goal 运行时）：写入 `artifact_layout.runtime_root` — `handoff/**`、review annex JSON、fix-input、runtime-smoke
- goal **禁止**把 Tier-R 写入 `<project>/.guazi-flow/`
