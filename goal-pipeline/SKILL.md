---
name: goal-pipeline
description: 持久化目标执行管线引擎。使用 `/goal-pipeline <目标>` 启动，Agent 持续执行直到完成或阻塞。Use when user wants autonomous multi-stage goal execution with cross-session recovery, independent model review, and token budget control. 包含目标澄清访谈、5阶段管线、自动修复循环。所有平台通用，不依赖外部 skill。
---

# Goal Pipeline

持久化目标执行管线——与 Claude Code /goal 对齐的 5 阶段管线引擎。零外部依赖，所有平台通用。

## 核心定位

Goal 是一个持久化的工程目标。Agent 接到 goal 后持续执行，不把控制权还给用户，直到目标完成或遇到无法自动恢复的阻塞。

与 Claude Code /goal 对齐：独立审核者、自动修复循环、budget 控制、暂停/恢复。

## NEVER

- **NEVER 跳过 Step 1 确定性检查直接调审核模型**——确定性检查零成本（无模型调用），且能发现 secret 泄漏、scope 越界等审核模型容易漏掉的问题
- **NEVER 在同一 blocker 上无限重试**——同一 issue 已尝试 3 种策略仍未解决必须 blocked，避免 token 浪费
- **NEVER 让审核模型与执行模型使用同一 provider**——分离置信度降为 medium，审核独立性受损
- **NEVER 在 review 通过前将 goal.status 设为 complete**——complete 需要所有门禁（review + smoke + evidence + verify.sh）全部通过
- **NEVER 在 state.json 中存储明文 API key**——key 存入 `~/.goal-state/config.json`，state.json 仅存审核结论
- **NEVER 在管线执行中途把控制权还给用户**——除非命中 blocked 条件或 budget 耗尽，Agent 必须持续执行
- **NEVER 让审核模型看到执行模型的 reasoning chain**——LLM 看到实现推理后会产生确认偏误，倾向于认同实现而非独立判断
- **NEVER 在 review not_pass 时修改验收标准来通过**——这是“降标准而非修代码”的反模式，必须修复实现而非弱化标准
- **NEVER 在 implement 阶段忽略 plan 的结构化字段**——Allowed Files / Stop Conditions 在 Phase 1 确定后即生效，忽略会导致 scope 蔓延、review 无法准确定位

## 执行模型

```
/goal-pipeline "<目标>"
  ↓
Phase 1: Goal Engineering（访谈引导）
  ├─ 澄清目标 → 推断范围 → 确定验收标准
  └─ 产出: plan 卡片 + state.json
  ↓
Phase 2: Pipeline Execution（Agent 持续执行）
  │
  while goal.status == active:
    │
    ├─ plan:     目标澄清 + 范围确定
    ├─ implement: Agent 在范围内修改代码
    ├─ [runtime_smoke]: 验证项目可启动（如果 runtime-smoke.sh 可用）
    ├─ review:   独立模型审核（跨 provider API 直调）
    │            pass → advance
    │            not_pass → 修复子循环
    └─ complete: 所有门禁通过 → goal.status = complete
```

## 管线详解

### plan 阶段

**MANDATORY**: 开始前读取 `skill_dir/references/interview-protocol.md`（三步收敛访谈协议）
**Do NOT Load**: separation-strategies.md（plan 阶段不需要审核通道）

- 从用户输入解析目标（低自由度——三步收敛协议固定流程）、推断范围（中自由度——Agent 自主判断 Out of Scope 边界）、确定验收标准
- 产出 plan 卡片（含 Allowed Files / Out of Scope / Stop Conditions / 验证清单 V#1..V#N 结构化字段）
- plan 产物最小质量门槛（纯 goal-pipeline 模式；guazi-flow 模式下由 guazi-flow-plan 保障，跳过此步）：
  1. 验收标准可测性: 每条含 pass/fail 判定方式
     BAD: "功能正常" | GOOD: "GET /api/users 返回 200 + 列表非空"
     不满足 → 要求重写
  2. Allowed Files 完整性: 覆盖 plan 提到的所有模块
     plan 提到"修改列表页"但 Allowed Files 不含列表页路径 → 告警
  3. 验证清单 V#1..V#N: 从验收标准推导，写入 plan 卡片
     作为 implement 覆盖声明和 review 覆盖检查的锚点
- 环境预检：审核通道探测（并行探测 + 跨 provider 优先排序）

### implement 阶段

**Before implementing, ask yourself**:
- [1/5] plan 是否已完成且输出正常？缺少 plan 输出 → blocked，不得继续
- 修改是否在 Allowed Files 白名单内？超范围 → 输出告警，需用户确认或缩小范围
- 是否命中 Stop Conditions（新增依赖/改接口协议）？命中 → 暂停并报告
- 能否用更小步幅完成？小步幅 → review 更精准、修复更快

Agent 在确定的范围内修改代码，产出候选 diff。

**After implementing, verify（纯模式执行；guazi-flow 模式下由 diff 合规性审计覆盖）**：
- diff 文件是否全部在 Allowed Files 范围内？
  超出 → 告警 + 记录超出文件及理由
- 是否引入新依赖或修改接口协议（Stop Conditions）？
  命中 → 暂停并报告
- 逐项声明验证清单覆盖: V#1=addressed / V#2=addressed / ...
  未覆盖项 → 记录原因（依赖联调/超出范围/待后续实现）
  覆盖声明必须基于 diff 中可见的代码事实


### review 分步聊天输出（MANDATORY）

每步 MUST 在聊天中输出一行，再执行脚本：

1. `[4/5] review Step 0: gate --pre` → 展示 verify-review overall
2. `[4/5] review Step 1: (已收敛) run-independent-review --mode dual` → dual-channel 含 guazi-flow rubric
3. `[4/5] review Step 2: assemble-review-packet` → 展示 packet_hash
4. `[4/5] review Step 3: run-independent-review` → 展示 review-run.json provider/latency/issues
5. `[4/5] review Step 4: merge-review-issues` → 展示 merged_result
6. `[4/5] review Step 5: gate --post` → 展示 handoff/review.json

可选落盘：`evidence/review-transcript.md`（merge 脚本自动写入 provenance 表）

### runtime_smoke 阶段（条件触发）

如果 `goal/scripts/runtime-smoke.sh` 可用，implement 之后运行：
- 推导 dev 命令 → 安装依赖（如需要）→ 启动 → HTTP 探测
- pass → 写入 evidence/runtime-smoke.md → 继续 review
- not_pass → 分类记录后继续 review（不阻断）：
  环境问题（端口冲突/依赖缺失）→ 标记 environmental
  代码问题（编译失败/类型错误）→ 标记 code_issue（review Step 1 覆盖）
  运行时崩溃 → 标记 runtime_crash（review 作为 Critical 处理）
  输出："[3/5] smoke: X <原因>（诊断信号，review 将验证）"
- 无法推导 dev 命令 → skipped

### review 阶段——三步审核流程

**MANDATORY**: 开始前读取 `skill_dir/references/separation-strategies.md`（审核模型通道策略）

```
implement complete
  ↓
Step 1: 确定性检查（verify-review.sh，0 模型调用）
  scope + secret + test + lint
  任一 not_pass → 修复子循环
  全部 pass → 继续
  ↓
Step 2: 独立审核（始终执行）
  独立 API 模型（跨 provider 优先，与执行模型不同 provider）
  输入: diff + 验收标准 + 约束 + Evaluator Checklist
  → issues[]（含 file/line_range/evidence 可选字段 + checklist 维度评估）
  ↓
Step 3: 分流
  pass → complete
  not_pass → 修复子循环
```

**扩展点**：桥接层可在 Step 1 和 Step 2 之间注入额外审核步骤（如专业代码审阅），注入的 issues 合并到 Step 2 的结果中。详见桥接层文档。

### 修复子循环——五种场景分类处理（与 Claude Code /goal 对齐）

**MANDATORY**: 读取 `skill_dir/references/auto-continue-policy.md`（停止条件和空转检测）

```
**MUST 只读** `evidence/review-fix-input.json` 的 `action` / `issues` / `next_steps`——禁止直接解析 review-goal / review-gf / review.md。

review not_pass:
  │
  ├─ 分类 issues（vs 前轮）:
  │   ├─ persistent: 前轮有、本轮仍在的同一 blocker（file 相同 + description 相似）
  │   ├─ new_blocker: 前轮没有的 blocker
  │   ├─ new_warning: 前轮没有的 warning
  │   └─ resolved: 前轮有但本轮消失的 issue
  │
  ├─ 根因分类（每个 blocker issue 标注）:
  │   ├─ plan_gap: plan 未覆盖此场景 / 验收标准不清晰 / 验证清单缺失
  │   │   → 修复策略: mini-replan（见下）
  │   ├─ implement_error: plan/验证清单有要求但实现偏离
  │   │   → 修复策略: 按 plan 修正实现（当前修复子循环）
  │   └─ spec_ambiguity: 需求本身模糊 / 多种理解均合理
  │       → 修复策略: blocked + 列出选项 [A/B/C/D] 用户决策
  │
  ├─ 决策（增加根因感知）:
  │   │
  │   ├─ plan_gap 占多数 → mini-replan（轻量 replan，不重走完整 plan）
  │   │   1. 更新 plan 卡片: 补充遗漏的 Allowed Files / 验收标准 / 验证清单
  │   │   2. 更新 state.json plan 字段
  │   │   3. 回到 implement（基于补充后的 plan 重新实现）
  │   │   4. replan_count++
  │   │   5. replan_count > 2 → blocked（plan 反复补充说明需求不清晰）
  │   │   guazi-flow 模式: mini-replan 改为调 guazi-flow-plan 更新 index.md
  │   │
  │   ├─ implement_error 占多数 → 进入下方场景决策树
  │   │
  │   ├─ spec_ambiguity 存在 → blocked + 用户选项 [A/B/C/D]
  │   │
  │   ├─ persistent + 无新策略 + 已 3 轮 → blocked
  │   │   "同一 issue 已尝试 3 种策略仍未解决"
  │   │
  │   ├─ persistent + 有新策略 → 自动修复（换策略继续）
  │   │
  │   ├─ new_blocker + 比旧 blocker 更严重 → blocked
  │   ├─ new_blocker + 伴随旧 blocker 减少 → 自动修复（方向对）
  │   ├─ new_blocker + scope 扩大 → blocked
  │   │
  │   ├─ 仅 new_warning → 自动修复（不阻断）
  │   │
  │   └─ resolved + 无 persistent + 无 new_blocker → 继续（在进步）
  │
  ├─ 兜底:
  │   ├─ 连续 3 轮 issue 总数未减少 → blocked
  │   ├─ 同一 issue 出现→消失→又出现 → flaky → blocked
  │   └─ 轮次 >10 → 警告但不强制阻断
  │
  └─ smoke 冲突:
      review pass + smoke 标记 code_issue/runtime_crash → 记录但不阻断
      review pass + smoke 标记 environmental → 忽略
```

**为什么不是每轮都调审核模型**：Goal 有明确的管线阶段，review 是集中的审核节点。not_pass 时进入修复子循环，持续到 pass 或命中 blocked 条件。

## 进度可见化规范

每个阶段开始和结束时，Agent 必须输出一行摘要：

```
[1/5] plan:      🔄 目标规划中...
[1/5] plan:      ✅ plan 卡片已生成
[2/5] implement: ✅ 5 files changed
[3/5] smoke:     ✅ pnpm run dev → localhost:8000 (35s)
[4/5] review:    🔄 独立模型审核中...
                 审核模型: deepseek-v4-flash (独立于执行模型)
                 Evaluator Checklist: 6 维度检查
[4/5] review:    ✅ 通过 (1 轮) | 分离置信度: high (跨provider)
                 [fail] src/auth/login.ts:42-58 缺少 error boundary
                 [pass] src/auth/service.ts:10-30 token 验证正确
[5/5] complete:  ✅ 目标完成
```

guazi-flow-* 可用时，进度输出使用实际 skill 全名：
`[1/5] guazi-flow-plan:` / `[2/5] guazi-flow-implement:` / `[4/5] review (guazi-flow + pipeline):` / `[5/5] guazi-flow-complete:`
guazi-flow 不可用时使用通用名: plan / implement / smoke / review / complete

review 未通过时输出 issue 变动追踪（✅已解决 / 🔁持续 / 🆕新增），blocked 时输出决策选项 [A/B/C/D]。implement 阶段修改超出 Allowed Files 白名单时输出 ⚠️ 告警。

### 每阶段必须输出的信息

| 阶段 | 必须输出 |
|------|---------|
| plan | skill 来源 + unit 数 + 任务目录路径 |
| implement | skill 来源 + 文件数 + Allowed Files 合规状态 |
| smoke | dev 命令 + URL + 耗时（或跳过原因） |
| review | 审核结论 + 审核模型名 + 分离置信度 + 轮次 + issue 变动（含 file:line 定位） |
| complete | 最终状态 + 总轮次 + token 估算 |
| blocked | 阻塞原因 + 阶段 + 决策选项 |
| budget ≥80% | 已消耗 X/Y tokens |

## Evidence 路径

纯 goal-pipeline 模式: `<task_dir>/evidence/`（task_dir = state.json 中的 task 路径）
guazi-flow 模式: `docs/guazi-flow/<task>/evidence/`（由 guazi-flow-plan 确定）

evidence 文件清单：
- runtime-smoke.md — smoke 阶段产出
- review.md — review 阶段产出
- implement.md — implement 阶段产出（guazi-flow 模式）
- complete.md — complete 阶段产出（guazi-flow 模式）

### complete 阶段

- review pass + runtime_smoke pass+fresh
- 所有 evidence 齐全且 fresh
- verify.sh → completion_condition_met: true
- goal.status = complete

**交付质量报告（complete 门禁通过后输出）**：
- review 摘要: 总轮次 / blocker 数 / 根因分布(plan_gap/implement_error/spec_ambiguity)
- 验证覆盖率: V# verified / V# gap / V# failed
- scope 合规: Allowed Files 告警次数 / Stop Conditions 触发次数
- 效率: 首轮 pass? / 修复子循环次数 / replan 次数 / token 估算
- guazi-flow 模式: guazi-flow-complete 收口摘要已含 completed_actions/residual_risks/wiki_update/next_action，质量报告不重复这些字段

## 审核通道自动配置

**MANDATORY**: 读取 `skill_dir/references/review-channel-setup.md`（三路径自动配置 + 用户自定义模型）

审核模型不可用时自动探测配置（Ollama 零手动 / Gemini 半自动 / 人工审核逃生通道）。

## Budget 控制

**MANDATORY**: 读取 `skill_dir/references/budget-control.md`（预算模型 + 阈值行为 + token 统计规则）

80/95/100 三级阈值提示。审核 token 单独统计，执行 token 按字符数/4 估算。

## 错误处理与边缘场景

| 场景 | 行为 |
|------|------|
| state.json 损坏 | 从 evidence + git log 重建 state，标记 `recovered: true` |
| git 操作失败 | 记录 failure_code，blocked，输出手动修复建议 |
| 非 JS 项目 | runtime-smoke 自动跳过（无法推导 dev 命令）|
| budget ≥100% | 暂停，用户可 extend 或 /goal-pipeline-clear |
| 审核通道全不可用 | 输出告警 + 安装建议，implement 前仍不可用则 blocked |
| 契约融入失败 | 静默跳过，state.json 记录 `contract_enriched=false`，不阻断后续阶段 |

## 前置依赖

10 references（加载触发已内嵌在上述工作流步骤中标有 MANDATORY）+ 6 脚本（`skill_dir/scripts/`），完整列表见 `references/` 目录。

## 状态持久化

**MANDATORY**: 读取 `skill_dir/references/goal-state-schema.md`（状态模型和持久化）
**MANDATORY**: 崩溃恢复时读取 `skill_dir/references/crash-recovery.md`

跨 session 可恢复，state.json 路径和 project_id 计算详见 goal-state-schema.md。原生 /goal 平台双保险。

## 与 Claude Code /goal 对齐

关键差异：审核独立性（跨 provider 独立模型 vs 每轮 Haiku）· 修复有界（3 轮 blocked vs 无限）· 跨 session 持久化（磁盘 vs Session-scoped）· 桥接层扩展。

## 原生 Goal 集成

当 `platform.native_goal = true` 时（Claude Code / Codex / Pi），goal-pipeline 利用平台原生 /goal 能力作为执行引擎，state.json 作为双保险。详见 `references/platform-detection.md` 的平台能力矩阵。`native_goal = false` 时完全自主管理。

## 生命周期管理

**MANDATORY**: 读取 `skill_dir/references/lifecycle.md`（命令表 + status 格式 + pause/clear 行为）

7 个命令：start / resume / status / pause / resume / clear / list。对齐 Claude Code /goal。
