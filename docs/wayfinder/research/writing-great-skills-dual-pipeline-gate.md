# writing-great-skills 双管线合入门槛

**Closes:** [GitHub #75](https://github.com/sophiezel/goal/issues/75)  
**Map:** [#70 完全独立 + 公共服务抽取](https://github.com/sophiezel/goal/issues/70)  
**Ratification:** 用户 HITL **全采纳推荐**（2026-08-03）  
**参照：** Matt `/writing-great-skills` · [optimization-spec-outline-v1.4.md](optimization-spec-outline-v1.4.md)

---

## 1. 裁决摘要

| # | 议题 | **裁决** |
|---|------|----------|
| Q1 | 审计范围 | **Tier A/B/C 三级**（见 §2） |
| Q2 | FAIL 与 merge block | Tier A 结构/边界 FAIL + Tier B 新 skill 未过 checklist → **block** |
| Q3 | CI 形态 | v1.4.0 **文档化人工 gate** + 轻量 `audit-skills.sh`；full CI **P2** |
| Q4 | 审计时机 | 规划收口 ratify；实现 PR 触达 SKILL；**v1.4.0 tag** 前 Tier A 全量复审 |
| Q5 | guazi-flow-review（marketplace） | **不纳入** Tier A；仅本仓 `guazi-flow-goal/SKILL.md` |

---

## 2. 审计范围

### Tier A — 合入 blocker（必须 pass）

| 路径 | 理由 |
|------|------|
| `goal-pipeline/SKILL.md` | 管线入口 |
| `goal-pipeline/stages/**/SKILL.md`（5） | stage 编排 |
| `guazi-flow-goal/SKILL.md` | guazi 入口 |
| `shared/review-kernel/**` 文档面（SKILL 或 README+references 等价） | 公共服务 |

### Tier B — 实现 PR blocker

| 路径 | 理由 |
|------|------|
| `goal-pipeline/skills/goal-engineering/**/SKILL.md` | Matt pack |
| 任意 **新增或重写** 的 `**/SKILL.md`（goal-pipeline、guazi-flow-goal、shared） | 变更面 |

### Tier C — warn only

- `references/*.md` 中被 SKILL 显式引用的协议文档

### 排除

- `fixtures/**`、wayfinder 研究稿、`references/archive/**`
- 仓外 **guazi-flow-*** marketplace skills（瓜子仓自行审计）

---

## 3. Pass / fail 与 merge block

| 级别 | 条件 | merge |
|------|------|-------|
| **FAIL** | Tier A：无 `description`、无 NEVER 块、触发模糊、与 spec v1.4 边界冲突 | **block** |
| **FAIL** | Tier B：新增/重写 skill 未过 §4 checklist | **block** |
| **WARN** | Tier C 或风格项 | 不 block；PR 评论记录 |
| **PASS** | 全部 FAIL 项清零 | 允许 |

---

## 4. Checklist（writing-great-skills 摘要）

- [ ] `description` 含 **何时使用** + **何时不用**
- [ ] 命令式 NEVER ≤7 条，可机读验证
- [ ] 与 v1.4 拓扑一致（goal 无 guazi；guazi 无 goal-pipeline 脚本依赖）
- [ ] 外部依赖写清 env（`REVIEW_KERNEL_HOME`、`GUAZI_STATE_HOME` 等）
- [ ] 无硬编码业务仓路径
- [ ] eval 或 fixture 指针存在（Tier A/B）

---

## 5. 审计时机

| 时机 | Tier | 动作 |
|------|------|------|
| **规划收口**（#70 map close） | — | 本文 ratify |
| **v1.4 实现 PR**（触达 SKILL） | 触达的 A + 全部 B | PR checklist |
| **release tag v1.4.0** | A 全量 | 发布门禁 |

---

## 6. 实现轨（P2）

- `scripts/audit-skills.sh`：结构 lint（description、NEVER 存在性）
- CI 接入 goal / guazi 仓各自 pipeline

---

## 7. Checklist

- [x] Q1–Q5 HITL 全采纳推荐
- [x] 产出路径：本文
