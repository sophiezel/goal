---
name: guazi-flow-goal
description: guazi-flow-goal 统一入口。加载 goal-pipeline 管线引擎，检测 guazi-flow-* 可用性，在 plan/implement/review/complete 各阶段 MUST 调度 guazi-flow 增强。Use when project has guazi-flow-* skills installed and user wants structured docs/evidence/contract-driven execution; otherwise use /goal-pipeline directly. 用户通过 `/guazi-flow-goal <目标>` 触发。包含生命周期管理（status/pause/resume/clear/list）。guazi-flow 不可用时 goal-pipeline 独立运行。
---

# Guazi Flow Goal（统一入口）

加载 goal-pipeline 管线引擎，在 5 阶段管线的每个节点植入 guazi-flow-*。guazi-flow 可用时 MUST 调度，不可用时 goal-pipeline 独立运行。

**本 skill 合并了原 guazi-flow-goal（入口）、guazi-flow-goal-auto（执行引擎）、guazi-flow-goal-manage（生命周期）的全部职责。**

## NEVER

- **NEVER 在 GATE 检查失败后继续执行 guazi-flow 调度**——GATE 不可读必须设 `guazi_flow_available = false` 并降级为纯 goal-pipeline
- **NEVER 跳过 Lazy Loading 直接执行阶段**——不加载阶段 SKILL.md → 产物不符合 guazi-flow schema → review 必定 not_pass
- **NEVER 在 `~/.goal-state/` 中写入 guazi-flow 项目配置**——`.guazi-flow/config.local.json` 只存 JIRA_TOKEN/repos 等 guazi-flow 自身字段，goal 产物不混入
- **NEVER 在 guazi-flow 不可用时强制加载 guazi-flow-* skills**——降级为纯 goal-pipeline 运行，不阻断管线
- **NEVER 修改 goal-pipeline 的 state.json 基础字段**——guazi-flow 扩展字段（guazi_flow_*）只能追加，不覆盖管线字段
- **NEVER 在 guazi-flow-plan 产出前修改项目代码**——plan 未完成时改代码会导致 write_set 不匹配，implement 阶段无法正确驱动
- **NEVER 在 guazi-flow-plan 产出 index.md 前进入 implement**——MUST 先执行 guazi-flow-plan 完整流程（见关键执行协议），验证 index.md 存在且包含必需章节（核心事实/完整伪代码/验收矩阵/执行记录），否则 blocked（failure_code: plan_artifact_missing / plan_schema_incomplete）
- **NEVER 跳过 [1/5] plan 进度输出**——缺少 [1/5] 输出说明 plan 被跳过，必须立即暂停并报告
- **NEVER 在 [5/5] complete 前以「如需继续」「需要我跑 review 吗」交还控制权**——implement 完成 ≠ goal 完成，必须自动进入 review → complete
- **NEVER 跳过 [3/5] smoke 或未跑 gate --post smoke**——runtime-smoke.sh 产出 evidence/runtime-smoke.md 后 MUST gate --stage smoke --post
- **NEVER 跳过 [4/5] review 或未跑 run-independent-review.sh**——review-run.json provenance 缺失则 gate --post review 失败
- **NEVER 自填 review-goal.json 绕过独立审核**——MUST assemble-review-packet → run-independent-review → merge-review-issues
- **NEVER 手改 review 产物**——修复前 MUST Read `evidence/review-fix-input.json`；禁止直接解析 review-goal / review-gf / review.md 做修复分流
- **NEVER 输出 [N/5] ✅ 而未运行 gate --post（exit 0）**——进度行必须对应机器门禁通过
- **NEVER 在 ~/.goal-state/scripts/ 缺失时进入 Phase 2**——先 Pre-flight 部署或 blocked(infra_missing)
- **NEVER 因「需求已清晰」跳过 Phase 1  entirely**——Fast-path 仍须创建 state.json 并输出 Goal 摘要

## 关键执行协议（Phase 2 必读）

guazi_flow_available = true 时，plan 阶段执行方式：

1. **加载**：读取 `guazi-flow-plan/SKILL.md` 全文（MANDATORY，不得跳过）
2. **执行**：按 guazi-flow-plan/SKILL.md 中的完整流程（9 步）逐步执行，读取其必读 references（unified-doc-contract.md / profile-selection.md 等）
3. **不得自行编写**：index.md 必须由 guazi-flow-plan 流程产出，不得自行编写简化版替代——缺少核心事实/完整伪代码/验收矩阵等章节的 index.md 视为无效
4. **完成验证**：产出后检查 index.md 包含必需章节（见 guazi-flow-integration.md 产物质量 GATE）

## 必读 references

### 启动时加载（MANDATORY）

| 文件 | 用途 |
|------|------|
| `goal-pipeline/SKILL.md` | 通用管线引擎定义（管线流程、修复循环、审核、进度可见化） |
| `references/bridge-contract.md` | 桥接契约（goal-pipeline ↔ guazi-flow 映射规则、扩展字段、降级策略） |
| `references/guazi-flow-integration.md` | guazi-flow 调度规则（MUST + 条件触发） |
| `references/guazi-flow-state-schema.md` | guazi-flow 扩展字段定义和写入边界 |
| `goal-pipeline/references/interview-protocol.md` | 三步收敛访谈协议 |
| `goal-pipeline/references/platform-detection.md` | 平台检测和能力矩阵 |
| `goal-pipeline/references/separation-strategies.md` | 审核模型多通道探测策略 |

### guazi-flow 可用性检测

```
加载 goal-pipeline 后：
if guazi-flow-core/SKILL.md 存在（通过 skill 加载机制）:
    检查版本兼容性（bridge-contract.md 中的 required_version）
    ├─ 兼容 → guazi_flow_available = true
    └─ 不兼容 → 警告 + guazi_flow_available = false（降级为纯 goal-pipeline）
else:
    guazi_flow_available = false
    goal-pipeline 独立运行
```

### 阶段 SKILL.md——Lazy Loading（进入对应阶段前 MUST 加载）

**guazi_flow_available = true 时，每个管线阶段开始前 MUST 加载：**

| 阶段 | 必须加载 |
|------|---------|
| plan 开始前 | `guazi-flow-plan/SKILL.md` |
| implement 开始前 | `guazi-flow-implement/SKILL.md` |
| review 开始前 | `guazi-flow-review/SKILL.md` |
| complete 开始前 | `guazi-flow-complete/SKILL.md` |

**不加载 → Agent 不知道 guazi-flow 具体指令 → 产物不符合规范。**

**Do NOT Load**: guazi-flow-review/SKILL.md 在 plan/implement 阶段（仅 review 阶段加载）；guazi-flow-complete/SKILL.md 在 plan/implement/review 阶段。

---

## Phase 1: Goal Engineering

**Before dispatching, ask yourself**: guazi_flow_available? profile? 有无 active goal?

**Before plan, ask yourself**: 用户真实需求是什么（而非表面诉求）？验收标准是否可量化（避免模糊通过）？范围是否过大（宁可收窄再扩展）？

```
Step 1: 环境初始化
  ├─ 运行 detect-platform → 确定平台
  ├─ 读取 references/bridge-contract.md (版本检查) → 确定 guazi_flow_available
  └─ 检查是否已有 active goal
      ├─ 有 → goal_already_active, 提示用户 [继续/清除/查看]
      └─ 无 → 继续

Step 1.5: Pre-flight（MANDATORY，Phase 2 前亦须可用）
  ├─ 检查 ~/.goal-state/scripts/gate-guazi-flow-stage.sh 存在
  ├─ 检查 ~/.goal-state/scripts/goal-advance-stage.sh 存在
  ├─ 检查 ~/.goal-state/references/guazi-flow-artifact-schema/ 存在
  │   任一缺失 → 运行 `bash <goal-repo>/install.sh --agent <detected>` 或 blocked(failure_code: infra_missing)
  └─ 输出: "pre-flight: scripts=OK|MISSING"

Fast-path（用户已提供 JIRA + 明确验收标准时）:
  ├─ Step 2-3 缩减为自动推断（跳过 interview 追问）
  ├─ 仍 MUST 执行 Step 5 创建 state.json
  ├─ 仍 MUST 输出 Goal 结构摘要（1 屏以内，默认确认，用户可打断）
  └─ 不得因「需求清晰」跳过 Phase 1 entirely

Step 2-3: 意图采集 + 自动推断 (interview-protocol.md)
  ├─ 解析用户输入 → 保留原始文本作为 objective
  ├─ 调 guazi-flow-doctor（如果可用）→ 检测 profile/profile_detail
  ├─ scope: git status + 关键词匹配 | constraints: AGENTS.md + profile
  └─ 缺口检测 + 定向追问 (最多 5 题，每题附带默认选项)

Step 4: 生成 + 确认 Goal 结构
  ├─ 组装: 目标描述 + 验收标准 + 范围 + Allowed Files + Out of Scope + Stop Conditions + 约束 + 验证方式
  ├─ 展示给用户确认（含结构化字段摘要）→ 确认/编辑/重新讨论/放弃
  └─ 确认 → 继续 Step 5

Step 5: 初始化 state（路径计算见 goal-pipeline/references/goal-state-schema.md）
  ├─ mkdir -p ~/.goal-state/ → 失败则 blocked（failure_code: state_dir_creation_failed）
  ├─ 创建 state.json（project_id/branch/task 路径见 goal-state-schema.md）
  ├─ 验证 state.json 可读写 → 失败则 blocked（failure_code: state_json_unwritable）
  └─ 检测并迁移旧路径 .guazi-flow/goal/ 产物（若存在）

Step 6: GATE Check（全部满足才进入 Phase 2）
  ├─ [✓] state.json 已创建且 schema 校验通过
  ├─ [✓] 用户已确认 Goal 内容
  ├─ [✓] guazi-flow-* SKILL.md 可加载（或 guazi_flow_available = false）
  ├─ [✓] docs/guazi-flow/ 目录可写（guazi_flow_available=true 时）
  └─ [✓] 输出进度摘要 → 进入 Phase 2

❗ 任一项不满足 → blocked，不得进入 Phase 2。输出失败项 + 修复建议。
```

---

## Phase 2: Pipeline Execution

管线流程详见 `goal-pipeline/SKILL.md`。本层在每个阶段注入 GATE 检查和 guazi-flow-* 调度：

| 阶段 | GATE | 降级 | 自由度 |
|------|------|------|--------|
| plan | 加载 guazi-flow-plan/SKILL.md | goal-pipeline 通用 plan | 中——结构化产出，内容自主 |
| implement | guazi-flow-implement/SKILL.md + index.md 非空 | goal-pipeline 通用 implement | 高——实现方式自主 |
| runtime_smoke | 无 | — | 低——固定脚本 |
| review | 加载 guazi-flow-review/SKILL.md | 仅 goal-pipeline 独立审核 | 低——按流程执行 |
| complete | 加载 guazi-flow-complete/SKILL.md | goal-pipeline 通用 complete | 低——门禁驱动 |


### 硬门禁执行顺序（MANDATORY）

每个 guazi-flow 阶段 MUST 按以下顺序执行（脚本：`~/.goal-state/scripts/gate-guazi-flow-stage.sh`）：

```
gate --pre(<stage>) --mode guazi
  → Read 完整 guazi-flow-<stage>/SKILL.md（Lazy Loading）
  → 按 skill 流程执行（Agent 行为）
  → gate --post(<stage>) --mode guazi   # 校验产物 + 脚本写入 handoff/<stage>.json
  → goal-advance-stage.sh → 立即进入 next_stage
  → exit 0 才允许输出 [N/5] guazi-flow-<stage>: ✅
  → exit 1 → blocked(failure_code=stage_gate_failed)，不得进入下一阶段
```

- handoff 由 gate `--post` 从磁盘产物反推，Agent **禁止**手写 `handoff/*.json`
- `--post` 时传 `--state-file` 更新 `guazi_flow_stages.*.gate`（仅脚本写入 passed_at）
- `gate.passed_at` 仅由脚本写入 state.json（见 `guazi-flow-state-schema.md`）
- review 前：`assemble-review-packet.sh` → 独立审核读 `handoff/review-packet.json`
- review 后：`merge-review-issues.sh` 合并 issues_gf ∪ issues_goal
- 降级 `--mode degraded` 时跳过 guazi handoff 要求，**禁止混用** guazi/goal 产物

详见 `references/stage-handoff-contract.md`。

### Stage Exit（MANDATORY — 每阶段结束，不得跳过）

每个 guazi-flow 阶段结束后 **立即** 执行：

```
1. gate-guazi-flow-stage.sh --task-dir <task> --stage <stage> --post --mode guazi --state-file <state>
2. goal-advance-stage.sh --state-file <state> --task-dir <task> --project-root <repo>
3. 输出: [N/5] guazi-flow-<stage>: ✅（仅 gate exit 0 后）
4. 读取 stdout.next_stage → 立即加载对应 SKILL.md 开始下一阶段
```

**禁止**：
- 询问用户「是否继续 review/complete」
- 输出「实现完成，如需…」类结束语
- 在 next_stage != done 且非 blocked 时结束 turn

Phase 2 每个阶段**开头**亦须运行 `goal-advance-stage.sh`：若 next_stage != 当前阶段 → blocked(wrong_stage)。


**各阶段调度细节**:

- **plan**: MUST 按关键执行协议 4 步执行（加载 → 执行 9 步流程 → 产物质量 GATE → 交叉验证(write_set vs Allowed Files) → 契约融入）
- **implement**: MUST profile/contract/write_set 驱动
- **review**: Step 1.5 注入 guazi-flow-review → issues_gf[] 合并到独立审核结果
- **complete**: MUST guazi-flow 收口检查

### 降级差异（guazi_flow_available = false）

| 维度 | guazi-flow 模式 | 降级为纯 goal-pipeline |
|------|----------------|----------------------|
| plan 产物 | index.md + unit.md（9 步流程） | plan 卡片（三步收敛访谈） |
| 交叉验证 | write_set vs Allowed Files + V# vs 验收矩阵 | 无（plan 质量门槛替代） |
| implement 审计 | diff 合规性审计 5 步 | After-verify 3 步 |
| review | 五步（含 guazi-flow-review + 根因分类） | 三步（确定性检查 + 独立审核 + 分流） |
| evidence 路径 | docs/guazi-flow/<task>/evidence/ | <task_dir>/evidence/ |
| complete 报告 | guazi-flow-complete 收口摘要 + 质量报告 | 仅质量报告 |

**Before review not_pass → 修复子循环, ask**: 这是同一根因的持续，还是新症状？根因未变 → 换策略；新症状 → 评估方向是否正确。

**条件触发阶段**（不可用时跳过，不提供通用替代）：

| 阶段 | 触发条件 |
|------|----------|
| postmerge | resolved_rule_context.postmerge_policy = required |
| validate | 用户显式开启 / validate_policy = required |
| e2e | 用户明确选择 + h5 profile |

管线细节（阶段流程、修复循环、进度输出）由 `goal-pipeline/SKILL.md` 定义。本层只负责 guazi-flow-* 调度。

---


## 生命周期管理

与 goal-pipeline 完全一致，唯一差异是命令前缀为 `guazi-flow-goal-*`（如 `/guazi-flow-goal-status` → `/goal-pipeline-status`）。路径解析同 goal-pipeline（`references/goal-state-schema.md`）。

---

## 写入边界

| 文件 | 操作 |
|------|------|
| `~/.goal-state/config.json` | 创建骨架 + 写 api_keys |
| `~/.goal-state/projects/<pid>/<branch>/<task>/state.json` | 读/写 |
| `~/.goal-state/projects/<pid>/<branch>/<task>/.lock` | 读/写 |
| `~/.goal-state/archive/<pid>/goal_<id>.json` | 写入 |
| `~/.goal-state/scripts/` | 首次部署 |
| `docs/guazi-flow/<task>/**` | 委托 guazi-flow-plan/implement/review/complete |
| `docs/guazi-flow/<task>/index.md` | 桥接层追加 Goal 契约字段（allowed_patterns/exclusions/stop_conditions 子 section） |
| 业务代码 | 委托 guazi-flow-implement 或 goal-pipeline 通用 implement |
| `<project>/.guazi-flow/` | ❌ 不写入 goal 产物 |

## 错误处理

通用错误处理（审核通道不可用、用户中途取消等）同 goal-pipeline。本层特有：

| 场景 | 行为 |
|------|------|
| goal_already_active | 展示当前 goal 状态，提供 [继续/清除/查看] 选项 |
| profile 检测失败 | 询问用户手动指定技术栈 |
| guazi-flow-core 版本不兼容 | 警告 + 降级为纯 goal-pipeline |
| state.json 与 docs/guazi-flow/ 不一致 | 运行 check-consistency 修复或归档重建 |
| guazi-flow-plan 失败 | 输出错误，暂停，让用户修复后重试 |
| plan_artifact_missing（index.md 不存在） | blocked，不得进入 implement，输出失败原因 + 重新调用 guazi-flow-plan 建议 |
| plan_schema_incomplete（index.md 缺少必需章节） | blocked，输出缺失章节列表 + "请重新执行 guazi-flow-plan 完整流程（9 步）"，不得自行补齐简化版 |
| state_dir_creation_failed / state_json_unwritable | blocked，输出权限/路径诊断建议 |

## 完成门禁

- Goal status = complete（goal-pipeline 判定）
- evidence/complete.md 存在且 pass+fresh
- evidence/review.md 存在且 pass+fresh
- guazi-flow 可用时: evidence 符合 guazi-flow schema + index.md 中 allowed_patterns/exclusions/stop_conditions 子 section 存在
