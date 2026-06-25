---
name: goal-pipeline
description: 持久化目标执行管线——与 Claude Code /goal 对齐的 5 阶段管线引擎。使用 `/goal-pipeline <目标>` 启动，Agent 持续执行直到完成或阻塞。Use when user wants autonomous multi-stage goal execution with cross-session recovery, independent model review, and token budget control. 包含：目标澄清访谈、5 阶段管线（plan→implement→smoke→review↩→complete）、独立模型审核、自动修复循环、token 预算控制、跨 session 持久化（~/.goal-state/）。所有平台通用，不依赖任何外部 skill。
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
  输入: diff + 验收标准 + 约束
  → issues[]
  ↓
Step 3: 分流
  pass → complete
  not_pass → 修复子循环
```

**扩展点**：桥接层可在 Step 1 和 Step 2 之间注入额外审核步骤（如专业代码审阅），注入的 issues 合并到 Step 2 的结果中。详见桥接层文档。

### 修复子循环——五种场景分类处理（与 Claude Code /goal 对齐）

**MANDATORY**: 读取 `skill_dir/references/auto-continue-policy.md`（停止条件和空转检测）

```
review not_pass:
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

每个阶段开始和结束时，Agent 必须输出一行摘要：

```
[1/5] plan:      🔄 目标规划中...
[1/5] plan:      ✅ plan 卡片已生成
[2/5] implement: ✅ 5 files changed
[3/5] smoke:     ✅ pnpm run dev → localhost:8000 (35s)
[4/5] review:    🔄 独立模型审核中...
                 审核模型: deepseek-v4-flash (独立于执行模型)
[4/5] review:    ✅ 通过 (1 轮) | 分离置信度: high (跨provider)
[5/5] complete:  ✅ 目标完成
```

review 未通过时输出 issue 变动追踪（✅已解决 / 🔁持续 / 🆕新增），blocked 时输出决策选项 [A/B/C/D]。

### 每阶段必须输出的信息

| 阶段 | 必须输出 |
|------|---------|
| plan | skill 来源 + unit 数 + 任务目录路径 |
| implement | skill 来源 + 文件数 |
| smoke | dev 命令 + URL + 耗时（或跳过原因） |
| review | 审核结论 + 审核模型名 + 分离置信度 + 轮次 + issue 变动 |
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
- 创建 `~/.goal-state/key-pending`
- 用户终端执行: `echo 'key' > ~/.goal-state/key-pending`
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

## 错误处理与边缘场景

| 场景 | 行为 |
|------|------|
| state.json 损坏 | 从 evidence + git log 重建 state，标记 `recovered: true` |
| git 操作失败 | 记录 failure_code，blocked，输出手动修复建议 |
| 非 JS 项目 | runtime-smoke 自动跳过（无法推导 dev 命令）|
| budget ≥100% | 暂停，用户可 extend 或 /goal-pipeline-clear |
| 审核通道全不可用 | 输出告警 + 安装建议，implement 前仍不可用则 blocked |

## 前置依赖

references 加载触发已内嵌在上述工作流步骤中（标有 MANDATORY）。完整列表：

`goal-state-schema.md`（状态持久化）· `separation-strategies.md`（review 阶段）· `interview-protocol.md`（plan 阶段）· `auto-continue-policy.md`（修复子循环）· `crash-recovery.md`（崩溃恢复）· `consistency-check.md`（resume 时）

脚本: `skill_dir/scripts/` — verify.sh / verify-review.sh / detect-review-channels / detect-platform / check-consistency

## 状态持久化

**MANDATORY**: 读取 `skill_dir/references/goal-state-schema.md`（状态模型和持久化）
**MANDATORY**: 崩溃恢复时读取 `skill_dir/references/crash-recovery.md`

`~/.goal-state/projects/<project_id>/<branch>/<task>/state.json`

project_id = sha256(项目根绝对路径)[:12]，branch = git 分支名或 "default"。

跨 session 可恢复。对于支持原生 /goal 的平台（Claude Code / Codex / Pi），同时利用平台持久化能力作为双保险。

## 与 Claude Code /goal 对齐

| 维度 | Claude Code /goal | Goal Pipeline |
|------|-------------------|---------------|
| 审核 | 每轮 Haiku | review 阶段独立模型 + 修复子循环 |
| 自动修复 | 无限 | 同一 blocker 3 轮无新策略 → blocked |
| Budget | Token 预算 | + 80/95/100 三级提示 |
| 持久化 | Session-scoped | 磁盘 state.json（跨 session） |
| 扩展 | 无 | 桥接层按需增强 |

## 原生 Goal 集成

当 `platform.native_goal = true` 时（Claude Code / Codex / Pi），goal-pipeline 利用平台原生 /goal 能力作为执行引擎，state.json 作为双保险。

| 平台 | 原生能力 | 集成方式 |
|------|---------|----------|
| Claude Code | `.claude/` 检测 | `/goal` 创建原生 goal，pause/resume 双向同步 |
| Pi | `propose_goal_draft` | 原生 goal 内执行管线 |
| Codex | `/goal` | 原生 goal 内执行管线 |

**当 `native_goal = false` 时**：goal-pipeline 完全自主管理，不依赖任何平台机制。

## 生命周期管理

所有命令以 `/goal-pipeline` 为前缀。对于支持原生 /goal 的平台，同时提供平台级别名。

| 命令 | 操作 | 对齐 Claude Code |
|------|------|:---:|
| `/goal-pipeline <目标>` | 启动新 goal | /goal |
| `/goal-pipeline` | 恢复当前 active goal | /goal (no args) |
| `/goal-pipeline-status` | 读取 state.json + verify.sh，输出摘要 | /goal status |
| `/goal-pipeline-pause` | status = paused, 释放 .lock, 输出断点 | 暂停 |
| `/goal-pipeline-resume` | **MANDATORY**: 读 `references/consistency-check.md` → check-consistency → status = active | 继续 |
| `/goal-pipeline-clear` | 归档 state.json → archive/，保留 evidence/ | /goal clear |
| `/goal-pipeline-list` | 遍历 archive/，输出历史列表 | /goal list |

### status 输出格式

```
目标: 给项目加用户认证 | 状态: 活跃
管线: plan(✓) → implement(✓) → review( ) → complete( )
进度: 50% (2/4) | 审核: deepseek-v4-flash | 消耗: 2/50 轮
```

### pause / clear 行为

| 操作 | 行为 |
|------|------|
| pause | 写入 pause_reason + paused_at → 释放 .lock → 输出恢复提示 |
| clear | 归档 state.json → archive/<pid>/goal_<id>.json → 保留 evidence/ → 释放 .lock |
