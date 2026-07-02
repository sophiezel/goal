# Guazi Flow State Schema（扩展字段）

基础 state schema 见 `goal-pipeline/references/goal-state-schema.md`。
本文件仅定义 guazi-flow 集成时的扩展字段和写入边界。

## 项目目录结构（guazi-flow 集成时）

```
~/.goal-state/                              ← goal 全局目录（同基础 schema）
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
    ├── index.md
    ├── evidence/*.md                        ← 任务产物（在项目中，进 git）
    └── units/*.md
```

## guazi-flow 扩展字段

位置: `~/.goal-state/projects/<pid>/<branch>/<task>/state.json`（基础字段见 goal-pipeline schema）

```json
{
  "project_root": "/abs/path/to/project",
  "guazi_flow_available": true,
  "guazi_flow_task": "docs/guazi-flow/<task>",
  "guazi_flow_profile": "h5",
  "guazi_flow_stages": {
    "plan": {"used": true, "skill": "guazi-flow-plan", "gate": {"script": "gate-guazi-flow-stage.sh", "version": 1, "passed_at": "2026-01-01T00:00:00Z", "handoff_hash": "abc123"}}
    "implement": {"used": true},
    "review": {"used": true},
    "complete": {"used": true}
  }
}
```

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

## 兼容迁移

检测 `~/.guazi-flow-goal/` 存在且 `~/.goal-state/` 不存在 → 自动迁移到新路径。
检测 `<project>/.guazi-flow/goal/state.json` 存在 → 迁移到 `~/.goal-state/`，删除旧文件。
`<project>/.guazi-flow/config.local.json` 中 goal 相关字段（api key / review_model）→ 自动迁移到 `~/.goal-state/config.json`，删除旧字段。
