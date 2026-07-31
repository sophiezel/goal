# Guazi Flow 集成规则

guazi-flow-goal 作为 goal-pipeline 内核与 guazi-flow-* 系列之间的桥接层。
goal-pipeline 内核独立运行。guazi-flow-* 可用时按本规则调度。

## 原生编排（双管线解耦 M4）

- `GF_USE_NATIVE_DRIVER=1` 时使用 `goal-pipeline/scripts/gf-stage-driver.sh`（设置 `GOAL_PIPELINE_ID=guazi-flow-goal` 与 rubric adapter）。
- 默认 `GF_USE_NATIVE_DRIVER=0` 仍走 `goal-stage-driver.sh`（兼容）。
- Gate 薄包装：`gate-gf-stage.sh` → `gate-guazi-flow-stage.sh`（共享 GateRuntime）。

**本机 runtime**：gate / complete / review merge 依赖 `~/.goal-pipeline/state/kernel/`（由 `install.sh` 或 `sync-install-repo.sh --deploy-only` 部署）。仅更新 skill 软链不会同步 kernel。

```
加载 goal-pipeline 后，在 skill_dir 加载完成之后:

if guazi-flow-core/SKILL.md 存在（通过 skill 加载机制）:
    guazi_flow_available = true
    加载 core_skill_dir/SKILL.md（版本检查）
else:
    guazi_flow_available = false
    纯 goal-pipeline 模式运行
```

## 调度规则

### 第一类：管线核心阶段——guazi-flow 可用则 MUST 使用

| 阶段 | guazi-flow 版本 | goal-pipeline 降级版本 |
|------|----------------|-------------|
| plan | guazi-flow-plan | goal-pipeline 通用 plan |
| implement | guazi-flow-implement | goal-pipeline 通用 implement |
| review | guazi-flow-review + goal-pipeline 独立审核（**两者都运行**） | 仅 goal-pipeline 独立审核 |
| complete | guazi-flow-complete | goal-pipeline 通用 complete |
| runtime_smoke / quality | 始终用 goal-quality + quality-gate | goal-pipeline 通用 quality |

### 第二类：条件触发阶段——按 guazi-flow 自身规则决定

| 阶段 | 触发条件 | guazi-flow 版本 |
|------|---------|---------------|
| postmerge | resolved_rule_context.postmerge_policy = required | guazi-flow-postmerge |
| validate | 用户显式开启 或 任务文档 validate=enabled 或 resolved_rule_context.validate_policy = required | guazi-flow-validate |
| e2e | Goal Engineering 阶段用户明确选择 + h5 profile | guazi-flow-e2e |

不可用时跳过，不提供 goal-pipeline 通用替代。

---

## 声明式契约门禁（术语）

当次 `index.md` / `handoff/decisions.json` 里写明的 API、参数、集成约定，由 **plan/implement 的 gate** 做自洽与落地检查（PQ-10～PQ-14、IQ-10）。  
**不叫**某个 Jira 的「缺陷类型」；引擎不硬编码具体项目或 `request_key` 取值。  

完整说明：[`goal-pipeline/references/declarative-contract-gates.md`](../../goal-pipeline/references/declarative-contract-gates.md)。  
`delivery-quality.json` 仅汇总管线 handoff/耗时等，**不**判定上述契约是否满足。

---

## 各阶段集成策略

### plan 阶段

```
if guazi_flow_available:
    → 调 guazi-flow-doctor（环境诊断）
    → 调 guazi-flow-plan（MUST，产出 docs/guazi-flow/<task>/index.md + unit.md）
       guazi-flow-plan 执行完毕，不做任何干预
    → 硬门禁（机器可验证，替代纯文本 GATE）:
       ```bash
       gate-guazi-flow-stage.sh --task-dir docs/guazi-flow/<task> --stage plan --pre --mode guazi
       # ... 执行 guazi-flow-plan 9 步 ...
       gate-guazi-flow-stage.sh --task-dir docs/guazi-flow/<task> --stage plan --post --mode guazi
       python3 plan-quality-gate.py --task-dir docs/guazi-flow/<task>  # 亦在 gate --post 内强制执行
       ```
       - `--post` 校验 index.md schema（frontmatter + 核心事实/完整伪代码/验收与验证矩阵/执行记录）
       - 通过则写入 `handoff/plan.json`（含 `plan_profile`）；失败 exit 1 → blocked(plan_schema_incomplete)
       - 简化 index（如缺完整伪代码）**无法通过** plan gate
       - **Index-Lite（XS/S）**：`plan_profile: lite` 时按 [`plan-index-rules-lite.json`](../../goal-pipeline/references/guazi-flow-artifact-schema/plan-index-rules-lite.json) 校验
         - 6 段（合并「范围与写集」）、伪代码 ≥80 chars、PQ-08 warn only
         - PQ-01/02/05/07 **不降级**（仍 block）；详见 [`index-lite-protocol.md`](../../goal-pipeline/references/index-lite-protocol.md)
         - 路由由 [`resolve_plan_index_rules.py`](../../goal-pipeline/scripts/resolve_plan_index_rules.py) 决定（env > plan.json M+ > frontmatter plan_profile > plan.json XS/S > 预估算）

    → 交叉验证（产物质量 GATE 通过后，契约融入之前）:
       1. write_set vs Allowed Files:
          从 index.md 提取 write_set 文件列表
          从 Phase 1 Goal 结构提取 Allowed Files
          write_set 文件 ⊆ Allowed Files?
          超出 → 追加 warn 到 index.md（不阻断，guazi-flow-plan 可能有合理扩展）
       2. 验证清单 vs 验收矩阵:
          从 Phase 1 Goal 结构提取 V#1..V#N
          从 index.md 提取验收与验证矩阵
          V# 全部被矩阵覆盖?
          缺口 → 记录为 plan_gap（review 阶段重点检查）
       3. 交叉验证结果写入 state.json.cross_validation
       4. decisions.json vs index（若存在 `handoff/decisions.json`）:
          `integration.*` 须在 index「设计与接口」/ API 映射表中出现且无矛盾
          缺失或 hash 不一致 → PQ-12 block（见 `plan-quality-gate.py`）
    → 契约融入（后置，纯追加，不修改 index.md 已有内容）:
       读取 Phase 1 Goal 结构: Allowed Files / Out of Scope / Stop Conditions
       追加到 index.md 对应字段的子 section:
         - Allowed Files → write_set 下 ### allowed_patterns
         - Out of Scope  → scope 下 ### exclusions
         - Stop Conditions → contract 下 ### stop_conditions
       冲突检测: write_set 文件不在 allowed_patterns 内 → 追加 warn 备注（不阻断）
       融入失败（如 index.md 不存在）→ 静默跳过，不影响后续阶段
       state.json.guazi_flow_contract_enriched = true/false
    → state.json.guazi_flow_task = "docs/guazi-flow/<task>"
    → 输出: "[1/5] guazi-flow-plan: ✅ 生成 N 个 unit (+ 交叉验证 + 契约融入)"
else:
    → goal-pipeline 通用 plan（访谈 + plan 卡片）
    → 输出: "[1/5] plan: ✅ (guazi-flow 不可用)"
```

### implement 阶段

```
if guazi_flow_available:
    → guazi-flow-implement（MUST，profile/contract/write_set 驱动）
    → diff 合规性审计（guazi-flow-implement 完成后）:
       1. git diff --name-only → 变更文件列表
       2. 对比 write_set: 全部在 write_set 内? 超出 → warn
       3. 对比 Allowed Files: 全部在 Allowed Files 内? 超出 → warn
       4. 检查 Stop Conditions: 新增依赖? 修改接口协议? 命中 → 暂停
       5. 审计结果写入 evidence/implement.md scope_compliance 字段
    → **D2/D5 auto-fix（C1）**：仅在 implement 阶段改 diff；`gate --post` 跑 `ux-auto-fix-audit.py` → `evidence/ux-autofix.json`（S+ strict block，XS/S warn）。见 `goal-pipeline/references/ux-auto-fix-c1.md`
    → 写入 evidence/implement.md（guazi-flow schema）
    → gate --post(implement) → implement-qc-gate + **contract-conformance-check (IQ-10)** + **ux-auto-fix-audit** → goal-advance-stage.sh → **立即**进入 [3/5] quality
    → 输出: "[2/5] guazi-flow-implement: ✅ X files changed"
else:
    → goal-pipeline 通用 implement
    → 输出: "[2/5] implement: ✅ (guazi-flow 不可用)"
```



### implement 阶段 Stage Exit 与 chain 校验

implement 业务完成后的 **唯一合法出口**：

```
gate --post(implement) → validate-pipeline-chain (exit 0) → goal-advance-stage → 立即 quality/review
```

- `validate-pipeline-chain` 检测到「执行记录表明 implement 完成但无 handoff/implement.json」→ **error**（failure: implement_gate_pending）
- Agent 禁止在 chain 报错或 gate 未 exit 0 时输出 `[2/5] implement: ✅`

### quality 阶段——gate 对齐

**Step 0**: implement gate --post 通过后 **立即** `runtime-smoke.sh`
**Step 1**: `quality-gate.sh` 汇总 L0+L1
**Step 2**: `gate --stage quality --post` → handoff/quality.json
- skipped（无 dev 命令）允许继续 review，但须记录 classification: none
- not_pass 须带 classification（environmental | code_issue | runtime_crash）
**Step 3**: `goal-advance-stage.sh` → review

**NEVER [3/5] ✅ 而无 handoff/quality.json gate.passed_at**

### review 阶段——增量注入

基础三步审核流程（Step 1/2/3）由 `goal-pipeline/SKILL.md` review 阶段定义。
guazi-flow 可用时，在基础流程中注入两个增量步骤：

**Step 0**: `gate --pre(review)` — implement handoff fresh
**Step 1.5 注入（guazi-flow-review）** — **仅 `review_track=dual` 时执行**（v3 §8.2）:
  专业代码审阅：读 index.md/unit.md/Figma/evidence
  检查：契约可追溯、前置状态、E2E 证据、视觉契约
  → issues_gf[]
  `review_track=single`（XS/S 快车道）时 **跳过本步**：rubric 经 `assemble-review-packet.sh` 嵌入 packet，`goal-run-review-chain.sh` unified 分支直接产出 issues；不加载 `guazi-flow-review/SKILL.md`
  不可用 → issues_gf = []

**Step 4.5 注入（根因分类）**:
  对每个 blocker issue 标注根因:
  - plan_gap: 对照 index.md/unit.md，plan 未覆盖此场景
  - implement_error: plan 有要求但 diff 未满足
  - spec_ambiguity: 需求源本身模糊
  Step 2 前: `assemble-review-packet.sh` → handoff/review-packet.json
Step 5: `merge-review-issues.sh` 合并 issues
Step 6: `gate --post(review)` — merged result=pass 才过
根因分布写入 evidence/review.md root_cause_summary
  修复策略路由:
  - plan_gap > 50% → mini-replan（调 guazi-flow-plan 更新 index.md）
  - implement_error > 50% → 进入修复子循环
  - spec_ambiguity 存在 → blocked + 用户决策

**合并与去重规则**:
  issues = 去重(issues_gf ∪ issues_goal)
  result = 两者都 pass ? pass : not_pass
  格式归一化: issues_goal 包含 file/line_range/evidence 可选字段。
             issues_gf 可能不含这些字段。
  去重规则: 相同 file + 相似 description 视为重复，保留信息更丰富的版本。

修复子循环决策树见 `goal-pipeline/SKILL.md`——五种场景 + 完整决策树。

### complete 阶段

```
if guazi_flow_available:
    → guazi-flow-complete（MUST，完整收口门禁）
    → 输出: "[5/5] guazi-flow-complete: ✅"
else:
    → goal-pipeline 通用 complete
    → 输出: "[5/5] complete: ✅ (guazi-flow 不可用)"
```

## state.json guazi-flow 扩展字段

```json
{
  "guazi_flow_available": true,
  "guazi_flow_task": "docs/guazi-flow/<task>",
  "guazi_flow_stages": {
    "plan": {"used": true},
    "implement": {"used": true},
    "review": {"used": true},
    "complete": {"used": true}
  }
}
```

`guazi_flow_available=false` 时，上述字段全部为空或 false。goal-pipeline 完全独立运行。

## task_dir 映射

guazi-flow 集成时，task_dir 由 guazi-flow-plan 确定：

```
task_dir = "docs/guazi-flow/<task>"
```

state.json 中 `guazi_flow_task` 字段记录此路径。goal-pipeline 通过此字段定位任务产物。


## 硬门禁脚本（goal 侧，不修改 guazi-flow-*）

| 脚本 | 用途 |
|------|------|
| `gate-guazi-flow-stage.sh` | plan/implement/review/complete `--pre`/`--post` |
| `format-gate-issues.sh` | gate 失败时 Issue Board 终端输出 |
| `assemble-review-packet.sh` | review Step 2 输入包 |
| `merge-review-issues.sh` | 合并 issues_gf + issues_goal |

### plan/implement gate 契约（对齐 unified-doc，零 audit 依赖）

plan `--post` 除 index schema 外 **显式**校验：

- 必填章节：`## 概览`、`## 任务目标`、`## 范围与非目标`、`## 核心事实`、`## 完整伪代码`、`## 验收与验证矩阵`、`## 执行记录`
- `write_set` 提取兼容：`## 范围与写集`、`## 写集`、`## write_set`

implement `--post`：`write_set` 为空 → fail（消息指向 index.md 章节）。

gate 失败时写入 `evidence/<stage>-gate-fix-input.json`（机器路由）；Agent **只读** fix-input 修复，禁止 Judge 会话直接改产物。

`subject_hash` 与上轮 fix-input 相同且仍 fail → `blocked(noop_fix)`。

implement `--post`: diff ⊆ write_set + 执行记录含 guazi-flow-implement。
review `--post`: evidence/review.md frontmatter + Goal annex；merged result=pass 才过。
complete `--post`: index current_stage=complete + review pass+fresh。


## 阶段跳过检测（MANDATORY）

implement 完成后 **review 不是可选增强**——guazi-flow 模式下 review = guazi-flow-review **+** goal-pipeline 独立审核（并集），complete 前 MUST 全部通过。

Agent 在每个阶段结束时运行：

```bash
goal-advance-stage.sh --state-file ~/.goal-pipeline/state/projects/<pid>/<branch>/<task>/state.json \
  --task-dir docs/guazi-flow/<task> --project-root <repo_root>
```

| 检测信号 | 判定 | 行为 |
|---------|------|------|
| next_stage=review 且 Agent 准备结束 turn | 阶段跳过 | Stop Hook / assert-complete 拦截 |
| 有 index.md + 代码 diff 但无 handoff/review.json | review 未执行 | blocked(stage_skipped) |
| 输出了 [2/5] ✅ 但无 [3/5]/[4/5] | 管线中断 | 立即续跑 next_stage，不得询问用户 |
| gate --post 未 exit 0 却输出 ✅ | 伪造进度 | NEVER，blocked(stage_gate_failed) |

Stop Hook 调用：`gate-guazi-flow-stage.sh --assert-complete --state-file ... --task-dir ... --project-root ...`
exit 2 → 注入 followup 继续 pipeline。


Handoff 规范：`references/stage-handoff-contract.md`。


## Review 统一通道（v2.3）

独立审核 `run-independent-review.sh --mode unified` 在 packet 中携带 `guazi_flow_rubric` + `goal_checklist`，**单次** LLM 调用产出 `review-unified.json`（`gf_skill_attested: true`，issues 带 `channel`）。执行 Agent **只读** `evidence/review-fix-input.json` 驱动修复子循环。
