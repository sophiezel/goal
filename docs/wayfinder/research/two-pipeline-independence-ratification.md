# goal-pipeline 与 guazi-flow-goal 完全独立宪章（Map #70）

**Closes:** [GitHub #72](https://github.com/sophiezel/goal/issues/72)  
**Map:** [#70 完全独立 + 公共服务抽取](https://github.com/sophiezel/goal/issues/70)  
**Ratification:** 用户 HITL Q1–Q5（2026-08-03）  
**前置：** [#71 双向耦合盘点](./two-pipeline-bidirectional-coupling-inventory.md) · v1.3 @ `9910d79` · [#55 C1](./goal-pipeline-decouple-matt-ratification.md)（本宪章 **收紧** v1.3 adapter 内嵌模型）

---

## 1. 裁决摘要

| # | 议题 | **裁决** |
|---|------|----------|
| **Q1** | goal-pipeline 内 guazi adapter | **A — 全部删除**（含 `--mode guazi` 核心分支）；guazi 从 `9910d79` fork/重建，**不**做目录迁出 |
| **Q2** | guazi-flow-goal 允许依赖 | **B — 仅消费共享 review-kernel**；gate/handoff/编排全自建 |
| **Q3** | 运行时 home | **C — 三路径：** `~/.goal-pipeline/` · `~/.guazi-flow/` · `~/.goal-services/review-kernel/` |
| **Q4** | install / CI / compat | **A — 立即分轨**；无 minor compat 窗 |
| **Q5** | review-kernel 退化 | **C — 双 fork 允许 + 共享 schema 契约族**（`@goal/review-schema@1.x`） |

---

## 2. Q1 — goal-pipeline 零 guazi（normative）

### 2.1 必须删除（非「迁出」）

| 类别 | 处置 |
|------|------|
| Compat 入口 | `gate-guazi-flow-stage.sh`、`gate-gf-stage.sh`、`gf-stage-driver.sh` — **删除** |
| Gate 核心 | `gate-goal-stage.sh` 内 **`--mode guazi` / `GATE_MODE=guazi` 全部分支** — **删除** |
| Gate-lib | `gate-lib/*.sh` 内 guazi/index 仪式分支 — **删除或 goal-only** |
| Review | `issues_gf`、`review_track=dual`、`platform_review_adapter*` — **删除** |
| 夹具 | `fixtures/guazi-adapter-gate/`、`fixtures/guazi-flow-gate/` — **从 goal 仓删除**（guazi fork 自取） |
| Schema fallback | `references/guazi-flow-artifact-schema/` fallback — **删除** |
| 叙事 | `SKILL.md` Guazi appendix、`pipeline_track=guazi` — **删除** |

### 2.2 guazi 侧义务

- 从 baseline **`9910d79`** fork gate 栈、guazi 夹具、guazi 专用 gate-lib 分支（实现地图定义具体路径）
- **禁止** 运行时调用 `goal-pipeline/scripts/*` 或 `~/.goal-pipeline/state/scripts/` 上的 guazi 路径

### 2.3 与 v1.3 / #55 关系

- v1.3 **reject** 延续：adapter 内嵌 goal-pipeline、`--mode guazi` compat 窗
- #55 轴 1 C1「adapter 显式 opt-in」→ 本宪章 **升级为**「adapter **不在** goal-pipeline 仓内存在」

---

## 3. Q2 — guazi 依赖面（normative）

| 允许 | 禁止 |
|------|------|
| **共享 review-kernel**（chain、packet preflight、invoke、merge、B schemas CLI） | goal-pipeline 脚本树、goal gate、goal stage driver |
| guazi 自研 gate / handoff / `guazi-flow-*` 编排 | `goal-advance-stage.sh` / `goal-stage-driver.sh` 直接 exec |
| env 指向 `~/.goal-services/review-kernel/` | 读写 `~/.goal-pipeline/`（Q3） |

**review-kernel 边界（一等公民）：**

- 编排 SSOT：`goal-run-review-chain.sh` **语义** → 抽为管线无关入口（spec v1.4 命名）
- Python：`kernel/review/*` → 迁入或复制到公共服务包
- Wrapper SKILL：`goal-review` / `guazi-flow-review` **各自管线**，仅 **消费** kernel 工件

---

## 4. Q3 — 三路径部署（normative）

| 路径 | Owner | 内容 |
|------|-------|------|
| `~/.goal-pipeline/` | goal-pipeline | state、goal scripts、Tier-R artifacts、goal install |
| `~/.guazi-flow/` | guazi-flow-goal | state、guazi scripts、Tier-R、guazi install |
| `~/.goal-services/review-kernel/` | 公共服务（仓内 `shared/review-kernel/` 或等价） | chain、kernel Python、共享 schemas、CLI |

- 两管线 **互不写入** 对方 home
- review-kernel 只读安装可被两管线引用；版本由共享 schema semver 约束（Q5）

---

## 5. Q4 — 立即分轨（normative）

| 面 | 规则 |
|----|------|
| goal CI | 仅 `fixtures/goal-gate/`；删除 guazi 套件 |
| guazi CI | `guazi-adapter-gate` 等价套件在 guazi 仓 |
| install | `sync-install-repo.sh` / `deploy-skills.sh` **goal-only**；guazi 独立 install 脚本 |
| compat | **无** `DEPRECATED` 保留窗；`gate-guazi-flow-stage.sh` 不存在 |
| 业务仓 | 未迁完者 pin guazi 新 install 或 frozen guazi 基线；**goal 不提供桥** |

---

## 6. Q5 — 双 fork + 共享 schema（normative）

### 6.1 优先路径

1. 抽出 **单 review-kernel 包** → `~/.goal-services/review-kernel/`
2. goal 与 guazi **同包**、不同 wrapper SKILL

### 6.2 退化路径（抽取失败或无法共用实现）

| 层 | 规则 |
|----|------|
| **实现** | 允许 fork：`goal-pipeline/kernel/review` 与 `guazi-review-kernel` 各自演进 |
| **契约** | **强制统一** schema 族：`review-run`、`review-unified`、`review-fix-input`、`review-packet` |
| **Semver** | 共享 `@goal/review-schema@1.x`（名称 spec v1.4 定稿）；breaking 须两实现同步 major |
| **互操作** | chain 产出工件 **可互换**；第三方可只依赖 schema 接入 |

### 6.3 Reject

- 双 fork 且 schema 各自漂移（Q5 选项 B 未采纳）
- 为等单包而 **阻塞** guazi 独立（Q5 选项 A 未采纳）

---

## 7. 下游规格义务（#73 / #74）

| 票 | 产出 |
|----|------|
| [#73](https://github.com/sophiezel/goal/issues/73) | `shared-services-extraction-options.md` — review-kernel 包布局、API、从 `9910d79` 迁移步骤 |
| [#74](https://github.com/sophiezel/goal/issues/74) | `optimization-spec-outline-v1.4.md` — 拓扑、实现地图拆分、业务仓迁移 playbook 纲要 |
| [#75](https://github.com/sophiezel/goal/issues/75) | writing-great-skills 双管线合入门槛 |

---

## 8. Out of scope（本宪章不 reopen）

- guazi-flow-* skill **业务内容**重写
- 业务仓功能交付
- 将两管线重新合并为单一路径
- goal-pipeline 为 guazi 保留任何 compat wrapper

---

## 9. Checklist

- [x] Q1–Q5 HITL 齐备
- [x] 产出路径：`docs/wayfinder/research/two-pipeline-independence-ratification.md`
