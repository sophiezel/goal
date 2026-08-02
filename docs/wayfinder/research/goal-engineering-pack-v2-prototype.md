# goal-engineering v2 Skill Pack 原型（Phase-6 / Map #53）

**Closes:** [GitHub #57](https://github.com/sophiezel/goal/issues/57)  
**Map:** [#53](https://github.com/sophiezel/goal/issues/53)  
**输入：** [#54 能力清单](./matt-engineering-skill-canon-phase6.md) · [#55 ratification](./goal-pipeline-decouple-matt-ratification.md) · [#56 耦合审计](./goal-pipeline-guazi-decouple-inventory.md)

**性质：** 可评审原型（文档 + 示例 JSON）；**不** 替换生产 gate、**不** 删除 guazi-flow-*。

---

## 1. 目标目录树（v2）

```
goal-pipeline/skills/goal-engineering/
├── README.md                    # pack 索引 + LICENSE 指针
├── LICENSE                      # 已有
├── grill/
│   └── SKILL.md                 # v2：一问一答；写 goal task brief（非 guazi index）
├── to-specs/
│   └── SKILL.md                 # v2：验收矩阵 → plan.json 字段建议
├── prototype/
│   ├── SKILL.md                 # 新增：UI + logic 分支；A/B/C 变体
│   └── references/
│       ├── ui-prototype.md
│       └── logic-prototype.md
├── handoff/
│   └── SKILL.md                 # 新增：原型 → implement 交接；设计决策 + 资产链接
├── tdd/
│   └── SKILL.md                 # 新增：implement 子策略；红-绿-重构
└── _evals/                      # defer：与 goal-pipeline/evals 对齐
    └── README.md
```

**不 fork 进 pack（out-of-band）：** wayfinder、to-tickets、loop-me、ask-matt — 见 #54 §8。

**stage 内核（非 pack）：** `stages/goal-implement`、`stages/goal-review` — Matt 能力通过 `skill_to_load` 注入，不新增 gate stage 名。

---

## 2. R 层挂载点

| Skill | R 层 | 加载时机 | `skill_to_load` 来源 | 硬 gate |
|-------|------|----------|----------------------|---------|
| grill | R1 | plan Phase 1 | `engineering_pack` 含 grill* | PQ / plan post **不替代** |
| to-specs | R2 | plan Phase 1 末 / spec_path | engineering_pack | plan post |
| prototype | R1–R2 | plan 内会话；`workflow_profile=prototype_path` | engineering_pack 含 prototype | **无** 新 gate |
| handoff | R2→R3 | prototype 满意后 | engineering_pack 含 handoff | plan post 写入 handoff 扩展 |
| tdd | R3 | implement 每 ticket | implement WO `skills` | implement post |

---

## 3. Profile 字段（与 `stage_graph` 正交）

### 3.1 `engineering_pack`（扩展枚举）

| 值 | 加载 skills | 说明 |
|----|-------------|------|
| `none` | — | v1.2 默认 |
| `grill` | grill | v1.2 |
| `to_specs` | to-specs | v1.2 |
| `grill_to_specs` | grill → to-specs | v1.2 |
| `prototype` | grill → prototype → handoff | 高保真路径 |
| `handoff` | handoff | 仅交接（已有原型资产时） |
| `full_matt` | grill →（to-specs \| prototype 按 workflow）→ handoff | hybrid 解析见下 |

### 3.2 `workflow_profile`（**新增**）

| 值 | Matt 链（软） | 典型场景 |
|----|---------------|----------|
| `spec_path` | grill → to-specs | 行为已清、文字规格足够 |
| `prototype_path` | grill → prototype → handoff | UI/交互/逻辑需可运行资产 |
| `hybrid` | grill；信号触发 to-specs **或** prototype | Wayfinder 默认叙事 |

**解析规则（草案）：**

1. `workflow_profile` 决定 **R1–R2 链形态**。
2. `engineering_pack` 决定 **实际加载哪些 SKILL 文件**（必须 ⊆ workflow 允许集）。
3. `stage_graph` 决定 **哪些 gate stage 跑**（与 Matt 链无关）。

### 3.3 示例 JSON

见仓库文件：

- [`goal-pipeline/references/profiles/_examples/xs-prototype-path.pipeline.profile.json`](../../../goal-pipeline/references/profiles/_examples/xs-prototype-path.pipeline.profile.json)
- [`goal-pipeline/references/profiles/_examples/xs-spec-path.pipeline.profile.json`](../../../goal-pipeline/references/profiles/_examples/xs-spec-path.pipeline.profile.json)

---

## 4. XS 任务 — 最小高保真路径叙事

**场景：** 单文件工具函数 + 边界行为不清晰，需要 logic prototype 验证。

**Profile：** `xs-prototype-path`（`workflow_profile: prototype_path`，`engineering_pack: prototype`）

### 4.1 软加载（Matt）

| 步骤 | Skill | 动作 |
|------|-------|------|
| 1 | grill | 2–3 轮一问一答：输入/输出/边界 |
| 2 | prototype | 生成终端 logic prototype；跑 3 个边界用例 |
| 3 | handoff | 写入 `handoff/plan.json` 扩展 `prototype_assets[]` + 设计决策 bullet |

### 4.2 仍跑的 gate（硬）

| Stage | pre | post | 说明 |
|-------|-----|------|------|
| plan | ✓ | ✓ | PQ + plan.json；**不** 要求 guazi index |
| implement | ✓ | ✓ | write_set + UVO；内嵌 **tdd** 子策略 |
| quality | — | ✓ | v1.2 B1：quality 主轨 |
| review | ✓ | ✓ | single-track + chain |
| complete | ✓ | ✓ | delivery-quality |

### 4.3 不跑 / 省略

- fe-argus / index 六段仪式（`plan_profile: goal_lite`）
- smoke advance 轨（B1 deprecated）
- Wayfinder / to-tickets（out-of-band）
- guazi-flow-* 上游 skill lazy-load

### 4.4 与 spec_path 对比（同 XS）

| | spec_path | prototype_path |
|---|-----------|----------------|
| engineering_pack | `grill_to_specs` | `prototype` |
| 规划产出 | 验收矩阵草稿 | 可运行 logic prototype |
| plan post 输入 | `acceptance_matrix_ids` | `prototype_assets` + 矩阵简表 |
| token 成本 | 低 | 中（prototype 会话） |

---

## 5. `handoff/plan.json` 扩展字段（草案，#58 入 spec）

```json
{
  "workflow_profile": "prototype_path",
  "engineering_pack": "prototype",
  "prototype_assets": [
    {
      "type": "logic",
      "path": "evidence/prototype-logic-v1/",
      "decisions": ["边界：空输入返回 ErrNotFound", "不持久化副作用"]
    }
  ],
  "design_decisions": [
    "采用 prototype v2 变体 B 的错误码映射"
  ]
}
```

**normative 时机：** v1.3 Part P；实现轨 Impl-7 加 schema 字段。

---

## 6. 与 v1.2 差异

| 项 | v1.2 | v2 原型 |
|----|------|---------|
| pack skills | grill, to-specs stub | + prototype, handoff, tdd |
| workflow_profile | 无 | spec / prototype / hybrid |
| 任务文档根 | grill stub → guazi index | goal task brief |
| prototype gate | 无 | 仍无（软 skill only） |

---

## 7. 验收（#57）

- [x] v2 目录树 + R 层挂载表
- [x] engineering_pack + workflow_profile JSON 示例
- [x] XS 最小高保真路径叙事
- [x] 未改生产 gate / 未删 guazi
