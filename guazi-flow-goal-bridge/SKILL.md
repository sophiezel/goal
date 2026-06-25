---
name: guazi-flow-goal-bridge
description: guazi-flow-goal 集成桥接层——goal-pipeline 管线与 guazi-flow-* 系列之间的契约定义和集成规则。加载 goal-pipeline 管线后，按此契约在 plan/implement/review/complete 各阶段按需调用 guazi-flow-* skills。guazi-flow 不可用时 goal-pipeline 独立运行。
---

# Guazi Flow Goal Bridge（集成桥接层）

guazi-flow-goal-bridge 是 goal-pipeline 内核与 guazi-flow-* 系列之间的桥接契约。goal-pipeline 管线独立运行于所有平台，guazi-flow-* 在可用时按此层定义的规则在各阶段被调用。

## goal ↔ guazi-flow 关系

```
goal-pipeline（通用管线）          guazi-flow-* 系列（可选增强）
       │                              │
       └──────── 本层桥接 ─────────────┘
                    
  goal-pipeline 始终独立运行。guazi-flow-* 可用时:
    plan:      替代 goal-pipeline 通用 plan（结构化文档）
    implement: 替代 goal-pipeline 通用 implement（profile/contract 驱动）
    review:    增强 goal-pipeline review（补充专业审核）
    complete:  增强 goal-pipeline complete（补充收口检查）
```

## 前置依赖

- goal-pipeline 管线（`goal-pipeline/SKILL.md`）——始终加载
- guazi-flow-core（`core_skill_dir/SKILL.md`）——条件加载（可用时版本检查）。不可读时 goal-pipeline 独立运行，不阻断。

## 集成规则

详见 `guazi-flow-goal-bridge/references/guazi-flow-integration.md`。

## guazi-flow 扩展字段

Goal 状态文件 `~/.goal-state/projects/<pid>/<branch>/<task>/state.json`
中 guazi-flow 相关扩展字段：

```json
{
  "guazi_flow_available": true,
  "guazi_flow_task": "docs/guazi-flow/<task>",
  "guazi_flow_profile": "h5",
  "guazi_flow_stages": {
    "plan": {"used": true},
    "implement": {"used": true},
    "review": {"used": true},
    "complete": {"used": true}
  }
}
```

guazi-flow 不可用时上述字段全部为空，goal-pipeline 完全独立运行。
