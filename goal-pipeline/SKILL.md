---
name: goal-pipeline
description: 持久化目标执行管线——与 Claude Code /goal 对齐的 5 阶段管线引擎。使用 `/goal-pipeline <目标>` 启动，Agent 持续执行直到完成或阻塞。包含：目标澄清访谈、5 阶段管线（plan→implement→smoke→review↩→complete）、独立模型审核、自动修复循环、token 预算控制、跨 session 持久化（~/.guazi-flow-goal/）。所有平台通用，不依赖任何外部 skill。
---

# Goal Pipeline

持久化目标执行管线——与 Claude Code /goal 对齐的 5 阶段管线引擎。零外部依赖，所有平台通用。

## 核心定位

Goal 是一个持久化的工程目标。Agent 接到 goal 后持续执行，不把控制权还给用户，直到目标完成或遇到无法自动恢复的阻塞。

与 Claude Code /goal 对齐：独立审核者、自动修复循环、budget 控制、暂停/恢复。

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

- 从用户输入解析目标、推断范围、确定验收标准
- 产出 plan 卡片（纯文本）
- 环境预检：审核通道探测（并行探测 + 跨 provider 优先排序）

### implement 阶段

Agent 在确定的范围内修改代码，产出候选 diff。

### runtime_smoke 阶段（条件触发）

如果 `goal/scripts/runtime-smoke.sh` 可用，implement 之后运行：
- 推导 dev 命令 → 安装依赖（如需要）→ 启动 → HTTP 探测
- pass → 写入 evidence/runtime-smoke.md → 继续 review
- not_pass → blocked（暂停等用户决策）
- 无法推导 dev 命令 → skipped

### review 阶段——统一五步流程

guazi-flow 可用时，guazi-flow-review 和 goal 独立审核**两者都运行**。guazi-flow 不可用时仅运行 goal 独立审核。

```
implement complete
  ↓
Step 1: 确定性检查（verify-review.sh，0 模型调用）
  scope + secret + test + lint
  任一 not_pass → 修复子循环
  全部 pass → 继续
  ↓
Step 2: guazi-flow-review（如果 guazi-flow 可用）
  专业代码审阅：读 index.md/unit.md/Figma/evidence
  检查：契约可追溯、前置状态、E2E 证据、视觉契约
  → issues_gf[]
  不可用 → issues_gf = []
  ↓
Step 3: goal 独立审核（始终执行）
  独立 API 模型（跨 provider 优先，与执行模型不同 provider）
  输入: diff + 验收标准 + 约束
  → issues_goal[]
  ↓
Step 4: 合并结论
  issues = 去重(issues_gf ∪ issues_goal)
  result = 两者都 pass ? pass : not_pass
  ↓
Step 5: 分流
  pass → complete
  not_pass → 修复子循环（使用合并 issues）
```

### 修复子循环——五种场景分类处理（与 Claude Code /goal 对齐）

```
review 合并结论 not_pass:
  │
  ├─ 分类 issues（vs 前轮）:
  │   ├─ persistent: 前轮有、本轮仍在的同一 blocker
  │   ├─ new_blocker: 前轮没有的 blocker
  │   ├─ new_warning: 前轮没有的 warning
  │   └─ resolved: 前轮有但本轮消失的 issue
  │
  ├─ 决策:
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
      review pass + smoke not_pass → blocked（非代码问题）
```

**为什么不是每轮都调审核模型**：Goal 有明确的管线阶段，review 是集中的审核节点。not_pass 时进入修复子循环，持续到 pass 或命中 blocked 条件。

## 进度可见化规范

每个阶段开始和结束时，Agent 必须输出一行摘要。

### 正常流程

```
[1/5] plan:      🔄 guazi-flow-plan 生成任务文档...
[1/5] plan:      ✅ 2 个 unit → docs/guazi-flow/<task>/

[2/5] implement: 🔄 guazi-flow-implement 执行中...
[2/5] implement: ✅ 5 files changed

[3/5] smoke:     🔄 runtime-smoke 验证项目启动...
[3/5] smoke:     ✅ pnpm run dev → localhost:8000 (35s)

[4/5] review:    🔄 guazi-flow-review + 独立模型审核中...
                 审核模型: deepseek-v4-flash (独立于执行模型)
[4/5] review:    ✅ 通过 (1 轮)
                 gf-review: pass | 独立审核: pass
                 分离置信度: high (跨provider)

[5/5] complete:  🔄 guazi-flow-complete 收口中...
[5/5] complete:  ✅ 目标完成
```

### review 进行中（含 issue 变化追踪）

```
[4/5] review: ❌ 未通过 (第 2 轮)
  变动:
    ✅ 已解决: authService 返回缺少 user 字段
    🔁 持续: refreshToken 实现不符合契约 (第 2 轮)
    🆕 新增: Login.tsx 表单校验遗漏 (warning)
  当前: 1 blocker + 1 warning
  修复中...
```

### review 阻塞

```
[4/5] review: ❌ 未通过 (第 4 轮)
  变动:
    🔁 持续: refreshToken 实现不符合契约 (3 轮, 3 种策略已耗尽)
  ⚠️ 同一 issue 已尝试 3 种策略仍未解决。
  请选择: [A] 人工修复 [B] 简化契约 [C] 跳过此问题 [D] 放弃
```

### guazi-flow 不可用时

```
[1/5] plan:      🔄 goal 通用 plan 执行中...
[1/5] plan:      ✅ (guazi-flow 不可用)

[4/5] review:    🔄 独立审核中... openai/gpt-4o-mini
[4/5] review:    ✅ 通过 (1 轮)
                 分离置信度: high (跨provider)
```

### 每阶段必须输出的信息

| 阶段 | 必须输出 |
|------|---------|
| plan | skill 来源 + unit 数 + 任务目录路径 |
| implement | skill 来源 + 文件数 |
| smoke | dev 命令 + URL + 耗时（或跳过原因） |
| review | 两个审核结论 + 审核模型名 + 分离置信度 + 轮次 + issue 变动 |
| complete | 最终状态 + 总轮次 + token 估算 |
| blocked | 阻塞原因 + 阶段 + 决策选项 |
| budget ≥80% | 已消耗 X/Y tokens |

### complete 阶段

- review pass + runtime_smoke pass+fresh
- 所有 evidence 齐全且 fresh
- verify.sh → completion_condition_met: true
- goal.status = complete

## 审核通道自动配置

审核模型不可用时，Agent 主动帮用户配置：

**路径 A（Ollama 全自动，零手动）**:
- 检测: RAM ≥ 8GB + macOS/Linux
- Agent: `brew install ollama && ollama pull llama3.2:3b`（或 qwen2.5:7b 如果 ≥16GB）
- 用户仅需回答 "Y"

**路径 B（Gemini 半自动，30秒）**:
- Agent 打开 https://aistudio.google.com/apikey
- 创建 `~/.guazi-flow-goal/key-pending`
- 用户终端执行: `echo 'key' > ~/.guazi-flow-goal/key-pending`
- key 永不在 chat 中出现
- Agent 验证 → 写入 config.json → 删除临时文件

**路径 C（人工审核）**: A/B 都不可用时的逃生通道

详见 `skill_dir/references/separation-strategies.md`。

## Budget 控制

与 Claude Code 对齐的预算模型：

```json
{
  "max_tokens": 200000,
  "warning_threshold": 0.8,
  "tokens_used": 0,
  "review_tokens_used": 0,
  "max_turns": 50,
  "current_turn": 0
}
```

- `< 80%`: 静默
- `≥ 80%`: 轻量提示
- `≥ 95%`: 警告
- `≥ 100%`: 暂停，用户可 extend

审核 token 单独统计（API 直调精确值），执行 token 估算（无 API usage 时按字符数/4）。

## 前置依赖

加载以下 references（记 skill 资源目录为 `skill_dir`）:

- `skill_dir/references/goal-state-schema.md` — 状态模型和持久化
- `skill_dir/references/separation-strategies.md` — 审核模型通道策略
- `skill_dir/references/interview-protocol.md` — 目标澄清访谈
- `skill_dir/references/auto-continue-policy.md` — 停止条件和空转检测
- `skill_dir/references/crash-recovery.md` — 崩溃恢复
- `skill_dir/references/consistency-check.md` — 状态一致性

脚本: `skill_dir/scripts/verify.sh` / `verify-review.sh` / `detect-review-channels` / `detect-platform` / `check-consistency`

## 状态持久化

`~/.guazi-flow-goal/projects/<project_id>/<branch>/<task>/state.json`

project_id = sha256(项目根绝对路径)[:12]，branch = git 分支名或 "default"。

跨 session 可恢复，不依赖平台原生 goal 机制。

## 与 Claude Code /goal 对齐

| | Claude Code /goal | Goal |
|---|---|---|
| 审核者 | Haiku 每轮评估 | 独立模型 review 阶段评估 + not_pass → 修复子循环 |
| 审核反馈 | 传给 Agent 下一轮 | issues+guidance → Agent 针对性修复 → re-review |
| 自动修复 | 无限（持续到 pass 或 budget 耗尽） | 同一 blocker 3 轮无新策略 → 暂停 |
| Budget | Token 预算 | Token 预算 + 80/95/100 三级提示 |
| 暂停/恢复 | 用户 pause/resume | blocked → 用户决策 → resume |
| 持久化 | Session-scoped | 磁盘 state.json（跨 session） |
| 与外部 skill | 无 | guazi-flow-* 按需增强（不影响独立运行） |
