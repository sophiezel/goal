# Goal Pipeline 架构设计文档

> 持久化目标执行管线——与 Claude Code /goal 对齐的 5 阶段管线引擎  
> 零外部依赖，所有 AI Agent 平台通用

---

## 目录

- [1. 设计理念](#1-设计理念)
- [2. 系统架构](#2-系统架构)
- [3. 管线设计](#3-管线设计)
- [4. 审核机制设计](#4-审核机制设计)
- [5. 质量门禁体系](#5-质量门禁体系)
- [6. 修复子循环](#6-修复子循环)
- [7. 状态持久化](#7-状态持久化)
- [8. 平台适配](#8-平台适配)
- [9. guazi-flow 增强层](#9-guazi-flow-增强层)
- [10. NEVER 规则（质量红线）](#10-never-规则质量红线)
- [11. 文件结构](#11-文件结构)

---

## 1. 设计理念

### 1.1 核心哲学

**Goal = 持久化的工程目标，Agent 持续执行直到完成或阻塞。**

与传统"一问一答"式 AI 辅助编码不同，goal-pipeline 将 AI Agent 视为**自主执行者**：
- Agent 接到 goal 后不释放控制权，持续执行直到目标完成
- 跨 session 可恢复——状态持久化在磁盘，不依赖平台内存
- 独立审核——执行者 ≠ 审核者，防止自评偏差

### 1.2 与 Claude Code /goal 对齐

| 维度 | Claude Code /goal | Goal Pipeline |
|------|-------------------|---------------|
| 审核 | 每轮 Haiku | review 阶段独立模型 + 修复子循环 |
| 自动修复 | 无限 | 同一 blocker 3 轮无新策略 → blocked |
| Budget | Token 预算 | + 80/95/100 三级提示 |
| 持久化 | Session-scoped | 磁盘 state.json（跨 session） |
| 平台 | Claude Code only | 所有平台通用 |

### 1.3 零依赖原则

goal-pipeline **不依赖任何外部 skill**：
- 不依赖 guazi-flow-*
- 不依赖平台特定 API
- 审核通过 API 直调（curl/python），不依赖 sub_agent

这保证了 goal-pipeline 可以在任何 AI Agent 平台上独立运行。

---

## 2. 系统架构

### 2.1 双层架构

```
┌─────────────────────────────────────────────────────────────┐
│                   guazi-flow-goal（增强层）                    │
│  检测 guazi-flow-* 可用性 → 在各阶段注入结构化文档/证据/契约    │
└─────────────────────────────────────────────────────────────┘
                              ↓ 委托
┌─────────────────────────────────────────────────────────────┐
│                   goal-pipeline（核心引擎）                    │
│  5 阶段管线 + 独立审核 + 修复循环 + 状态持久化 + Budget 控制    │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 执行模型

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
    ├─ plan:         目标澄清 + 范围确定
    ├─ implement:    Agent 在范围内修改代码
    ├─ [runtime_smoke]: 验证项目可启动
    ├─ review:       独立模型审核
    │                pass → advance
    │                not_pass → 修复子循环
    └─ complete:     所有门禁通过 → goal.status = complete
```

### 2.3 Skill 文件组织

```
goal-pipeline/
├── SKILL.md                          # 核心引擎定义（291 行）
├── references/                       # 按需加载的参考文档
│   ├── auto-continue-policy.md       # 停止条件和空转检测
│   ├── consistency-check.md          # resume 时一致性校验
│   ├── crash-recovery.md             # 崩溃恢复策略
│   ├── goal-state-schema.md          # 状态持久化 schema
│   ├── interview-protocol.md         # 三步收敛访谈协议
│   ├── platform-detection.md         # 平台检测和能力矩阵
│   └── separation-strategies.md      # 审核模型多通道策略
└── scripts/                          # 确定性检查脚本
    ├── verify.sh                     # 管线状态检查
    ├── verify-review.sh              # review 确定性检查
    ├── detect-review-channels        # 审核通道探测
    ├── detect-platform               # 平台检测
    ├── check-consistency             # 一致性校验
    └── runtime-smoke.sh              # 运行时冒烟测试

guazi-flow-goal/
├── SKILL.md                          # 增强层入口（190 行）
└── references/
    ├── bridge-contract.md            # 桥接契约
    ├── guazi-flow-integration.md     # guazi-flow 调度规则
    └── guazi-flow-state-schema.md    # guazi-flow 扩展字段
```

---

## 3. 管线设计

### 3.1 五阶段管线

```
plan → implement → [runtime_smoke] → review → complete
  ↓        ↓              ↓              ↓         ↓
 文档    代码          可运行        独立审核   全部门禁通过
```

### 3.2 plan 阶段：三步收敛访谈

**设计原则**：用户不需要手写标准 Goal Prompt。通过渐进式结构化访谈自动生成。

#### Goal Schema（管线推进所需的最小信息集）

| 字段 | 优先级 | 来源 | 缺失时行为 |
|------|:--:|------|------|
| objective | P0 | 用户输入 | 无法创建 goal |
| profile | P0 | 自动检测 | 自动检测，用户确认 |
| scope | P1 | git status / 项目结构推断 | 推断后确认，不确定则追问 |
| acceptance_criteria | P1 | 追问（提供选项） | 可先推进 plan，plan 阶段细化 |
| constraints | P1 | `AGENTS.md` / profile 推断 | 自动推断，用户可追加 |
| verification | P1 | `package.json` scripts.test 推断 | 自动推断，用户可调整 |
| budget | P2 | 默认值 | `max_turns=50` |

#### 访谈流程

```
Step 1: 自由输入
  用户说任何内容："加个登录"、"修 bug"、"重构 auth 模块"
  
Step 2: 自动推断（在追问之前）
  ├─ profile: 读 package.json / go.mod / 项目结构
  ├─ scope: git diff + 关键词匹配 + 默认整个项目
  ├─ constraints: 读 AGENTS.md / CLAUDE.md / .cursorrules
  ├─ verification: 读 package.json scripts.test
  └─ acceptance_criteria: 从用户输入提取关键词（最弱推断）

Step 3: 定向追问（只追问推断失败的 P0/P1 字段）
  每个问题给选项，用户选字母即可
  最多 3-5 个问题，不过度访谈
```

#### Goal 结构模板（统一中间表示）

```markdown
## Goal: <一句话目标>

### 目标描述
<完整描述>

### 验收标准
- [ ] <标准1>
- [ ] <标准2>

### 范围
- 涉及: <模块/文件列表>
- 禁止修改: <约束>

### 约束
- 来自项目规则: <规则>
- 来自技术栈: <profile>

### 验证方式
- 自动验证: <命令>
- 人工验证: <需确认方面>
```

### 3.3 implement 阶段

Agent 在确定的范围内修改代码，产出候选 diff。

- guazi-flow 可用时：按 profile/contract/write_set 驱动
- guazi-flow 不可用时：goal-pipeline 通用实现

### 3.4 runtime_smoke 阶段（条件触发）

如果 `goal/scripts/runtime-smoke.sh` 可用，implement 之后运行：

```
推导 dev 命令 → 安装依赖（如需要）→ 启动 → HTTP 探测
  ├─ pass → 写入 evidence/runtime-smoke.md → 继续 review
  ├─ not_pass → blocked（暂停等用户决策）
  └─ 无法推导 dev 命令 → skipped
```

### 3.5 review 阶段（详见第 4 节）

独立模型审核，三步流程。

### 3.6 complete 阶段

所有门禁汇聚点：

| 门禁 | 条件 | 验证方式 |
|------|------|----------|
| review pass | 独立模型审核通过 | evidence/review.md result=pass |
| runtime_smoke pass | 项目能跑 | evidence/runtime-smoke.md result=pass |
| evidence fresh | 证据对应的 git HEAD = 当前 HEAD | verify.sh 对比 git_head |
| verify.sh | completion_condition_met: true | 脚本最终判定 |

---

## 4. 审核机制设计

### 4.1 核心原则

**执行者 ≠ 审核者。** 实现代码的模型不得审核自己的代码。

独立性等级：跨 provider > 同 provider 不同规格 > 同 model（不允许）

### 4.2 三步审核流程

```
implement complete
  ↓
Step 1: 确定性检查（verify-review.sh，0 模型调用）
  ├─ scope: 修改文件是否在 write_set 范围内
  ├─ secret: 正则扫描 8 种密钥模式
  ├─ test: 运行 npm test / go test
  └─ lint: 运行 eslint
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

### 4.3 Step 1: 确定性检查（零成本、快速）

由 `verify-review.sh` 脚本执行，**不调用任何 AI 模型**：

| 检查项 | 做什么 | 实现 |
|--------|--------|------|
| **scope** | git diff 的文件是否在 write_set 范围内 | 前缀匹配 |
| **secret** | 扫描 API_KEY、sk-、AKIA、ghp_ 等 8 种模式 | grep + 正则 |
| **test** | 运行项目测试 | npm test / go test |
| **lint** | 代码风格检查 | eslint |

**为什么零成本更重要**：这些检查能发现审核模型容易漏掉的问题（如 secret 泄露），且不消耗 token。

### 4.4 Step 2: 独立模型审核

#### 候选池收集（并行探测，不短路）

所有来源同时探测，收集到候选池，然后统一排序：

| 来源 | 探测方式 | 排序权重 |
|------|---------|:--:|
| **全局配置** | 读取 `~/.goal-state/config.json` | 最高 |
| **标准环境变量** | `$OPENAI_API_KEY` / `$ANTHROPIC_API_KEY` / ... | 正常 |
| **Agent 自省** | agent 回答 provider + model | 正常 |
| **Ollama 本地** | `ollama list` | 正常 |
| **免费 API** | 需用户注册（引导阶段） | - |

#### 排序规则（按独立性，非按来源）

```
1. 过滤: 排除 available=false、同 model 自审

2. 分组:
   Group A: same_provider_as_exec = false（跨 provider）
   Group B: same_provider_as_exec = true（同 provider，不同 model）

3. 排序:
   Group A 排前（跨 provider 更独立）
   组内按成本排序: gpt-4o-mini > gemini-flash > groq > 本地

4. 选取: 排序后第一位即为最优
```

#### 为什么跨 provider 优先

| 维度 | 跨 provider | 同 provider |
|------|:--:|:--:|
| 自评偏差 | ✅ 消除 | ✅ 消除 |
| 共享训练盲点 | ✅ 消除 | ⚠️ 可能存在 |
| API 单点故障 | ✅ 互为备份 | ❌ 同时不可用 |
| 成本 | gpt-4o-mini $0.15/1M | haiku $0.80/1M |

#### 执行 Provider → Flash 模型映射

| 执行 Provider | Flash 模型 |
|:--|------|
| Anthropic | claude-haiku-4-5 |
| OpenAI | gpt-4o-mini |
| DeepSeek | deepseek-v4-flash |
| Google/Gemini | gemini-2.0-flash |
| Groq | llama-3.3-70b-versatile |
| Ollama 本地 | 模型列表中最小的模型 |

#### 分离置信度

| 置信度 | 条件 | 行为 |
|:--:|------|------|
| **high** | 审核模型 ≠ 执行模型，且不同 provider | 自动通过 |
| **medium** | 审核模型 ≠ 执行模型，同 provider 不同规格 | 自动通过 + 标注 |
| - | 审核模型 = 执行模型（任何情况） | **不允许** |

#### 审核 Prompt 设计（防止确认偏误）

```markdown
## 角色
你是独立代码审核者。你不是这段代码的实现者。
你的唯一职责：根据任务契约，客观评审候选 diff。

## 任务契约
{contract}      ← 从 index.md 验收标准 + unit.md 契约提取

## 候选 Diff
{diff}          ← git diff 完整输出

## 约束
- 允许修改的文件: {write_set}
- 项目规则: {constraints}

## 输出格式
只输出一个 JSON object，每条 issue 不超过 80 字。
{
  "result": "pass | not_pass",
  "issues": [
    { "severity": "blocker | warning | uncertain", ... }
  ]
}
```

**关键**：审核模型**看不到执行模型的推理过程**（reasoning chain），只看到 diff + 验收标准 + 约束。这是为了防止确认偏误——LLM 看到实现推理后会倾向于认同实现。

### 4.5 审核通道自动配置

审核模型不可用时，Agent 主动帮用户配置：

```
路径 A（Ollama 全自动，零手动）:
  检测: RAM ≥ 8GB + macOS/Linux
  Agent: brew install ollama && ollama pull llama3.2:3b
  用户仅需回答 "Y"

路径 B（Gemini 半自动，30秒）:
  Agent 打开 https://aistudio.google.com/apikey
  创建 ~/.goal-state/key-pending
  用户终端执行: echo 'key' > ~/.goal-state/key-pending
  key 永不在 chat 中出现

路径 C（人工审核）: A/B 都不可用时的逃生通道
```

决策顺序：RAM ≥ 8GB → 首推 Ollama 全自动；否则 → Gemini 半自动；都不可用 → 人工

---

## 5. 质量门禁体系

### 5.1 五层质量门禁

```
用户目标
  ↓
[第1层] plan 阶段 — 确定验收标准（"什么算完成"）
  ↓
[第2层] implement — Agent 产出候选 diff
  ↓
[第3层] runtime_smoke — 项目能跑起来吗？
  ↓
[第4层] review — 三步审核（确定性检查 → 独立模型审核 → 分流）
         ↓ not_pass
       修复子循环（分类 → 决策 → 重试）
  ↓
[第5层] complete — 所有 evidence pass+fresh → 最终交付
```

### 5.2 门禁详情

| 层 | 门禁 | 验证方式 | 失败行为 |
|---|------|----------|----------|
| plan | Goal 结构完整 + 用户确认 | 访谈协议 | 重新讨论 |
| implement | 代码产出 + 在 write_set 范围内 | verify-review.sh scope | 修复子循环 |
| runtime_smoke | 项目可启动 | HTTP 探测 | blocked |
| review | 独立模型审核通过 | JSON 解析 | 修复子循环 |
| complete | 全部门禁 pass + evidence fresh | verify.sh | 不允许标记 complete |

### 5.3 Evidence Freshness 机制

每个阶段的证据文件（`evidence/<stage>.md`）记录生成时的 git HEAD：

```
evidence git_head == 当前 git HEAD → fresh
evidence git_head != 当前 git HEAD → stale（需重跑）
```

这确保了"代码变更后，之前的审核结论可能失效"。

---

## 6. 修复子循环

### 6.1 智能分类

review not_pass 后不是简单重试，而是**智能分类 + 策略切换**：

```
每轮 review 结果对比:
  ├─ persistent:  前轮有、本轮仍在的同一 blocker
  ├─ new_blocker: 前轮没有的新 blocker
  ├─ new_warning: 前轮没有的新 warning
  └─ resolved:    前轮有但本轮消失的 issue
```

### 6.2 决策树

```
review not_pass:
  │
  ├─ persistent + 无新策略 + 已 3 轮 → blocked
  │   "同一 issue 已尝试 3 种策略仍未解决"
  │
  ├─ persistent + 有新策略 → 自动修复（换策略继续）
  │
  ├─ new_blocker + 比旧 blocker 更严重 → blocked
  ├─ new_blocker + 伴随旧 blocker 减少 → 自动修复（方向对）
  ├─ new_blocker + scope 扩大 → blocked
  │
  ├─ 仅 new_warning → 自动修复（不阻断）
  │
  └─ resolved + 无 persistent + 无 new_blocker → 继续（在进步）
  
  兜底:
    连续 3 轮 issue 总数未减少 → blocked
    同一 issue 出现→消失→又出现 → flaky → blocked
    轮次 > 10 → 警告但不强制阻断
```

### 6.3 思维框架（guazi-flow 增强）

**修复前先判断**：这是同一根因的持续，还是新症状？
- 根因未变 → 换策略
- 新症状 → 评估方向是否正确

---

## 7. 状态持久化

### 7.1 目录结构

```
~/.goal-state/                              ← 全局目录
├── config.json                           ← API key + 偏好 + 通道缓存
├── projects/
│   └── <project_id>/                    ← sha256(项目根绝对路径)[:12]
│       └── <branch>/                     ← 分支名 or "default"
│           └── <task>/                   ← task slug
│               ├── state.json            ← Goal 状态
│               └── .lock                 ← 并发控制
├── archive/
│   └── <project_id>/
│       └── goal_<id>.json
└── scripts/                              ← 首次部署
```

### 7.2 state.json Schema

```json
{
  "version": 1,
  "goal_id": "<timestamp>-<8hex>",
  "project_id": "<sha256[:12]>",
  "objective": "用户目标描述",
  "status": "active | paused | complete | blocked | aborted",
  "platform": { "agent": "cursor", "native_goal": false },
  "review_config": { "model": "openai/gpt-4o-mini", "separation_confidence": "high" },
  "pipeline": {
    "plan": { "status": "done", "evidence_fresh": true },
    "implement": { "status": "done", "evidence_fresh": true },
    "review": { "status": "in_progress", "evidence_fresh": true }
  },
  "budget": { "max_turns": 50, "current_turn": 2, "tokens_used": 0 }
}
```

### 7.3 崩溃恢复

| 场景 | 检测 | 恢复方法 |
|------|------|---------|
| Agent crash | 下次启动时检测 state.json | 运行恢复流程 |
| state.json 损坏 | JSON parse 失败 | 从 git + evidence 重建 |
| .lock 残留 | lock 中 pid 不存活 | 接管 lock，继续 |
| Goal 状态与管线不一致 | check-consistency | 以管线事实为准 |

### 7.4 并发控制

粒度: `(project_id, branch, task)` 三元组。

- 同三元组只允许一个 active goal
- 不同分支/不同 task/不同 project_id 可并行
- Stale lock: heartbeat 超 5min + pid 不存活 → 接管

---

## 8. 平台适配

### 8.1 平台检测

| 平台 | 检测信号 | Skills 目录 |
|------|---------|-------------|
| Claude Code | `.claude/` | `~/.claude/skills/` |
| Cursor | `.cursor/` | `~/.cursor/skills/` |
| Codex | `.codex/` | `~/.codex/skills/` |
| Pi | `.pi/` 或 `$PI_HOME` | `~/.pi/skills/` |
| Windsurf | `.windsurf/` | `~/.windsurf/skills/` |
| Qoder | `.qoder/` | `~/.qoder/skills/` |
| Hermes | `.hermes/` | `~/.hermes/skills/` |
| Continue | `.continue/` | `~/.continue/skills/` |
| Roo | `.roo/` | `~/.roo/skills/` |
| Generic | fallback | `~/.agents/skills/` |

### 8.2 能力矩阵

| 能力 | Pi | Codex | Claude Code | Cursor | Windsurf | Generic |
|------|:--:|:--:|:--:|:--:|:--:|:--:|
| agent_mode_continuous | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| native_goal | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| sub_agent | ✅ | ⚠️ | ⚠️ | ❌ | ❌ | ❌ |
| api_call (curl) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

**关键**：goal-pipeline 使用 `agent_mode_continuous`（所有平台可用）作为执行引擎，**不依赖** native_goal 或 sub_agent。

### 8.3 原生 Goal 集成

当 `platform.native_goal = true` 时（Claude Code / Codex / Pi），利用平台原生 /goal 能力，state.json 作为双保险：

| 平台 | 原生能力 | 集成方式 |
|------|---------|----------|
| Claude Code | `.claude/` 检测 | `/goal` 创建原生 goal，pause/resume 双向同步 |
| Pi | `propose_goal_draft` | 原生 goal 内执行管线 |
| Codex | `/goal` | 原生 goal 内执行管线 |

当 `native_goal = false` 时：goal-pipeline 完全自主管理。

---

## 9. guazi-flow 增强层

### 9.1 定位

guazi-flow-goal 是 goal-pipeline 的**增强层**，不是替代品。当项目安装了 guazi-flow-* skills 时，在各阶段注入结构化文档/证据/契约驱动。

### 9.2 阶段 GATE 表

| 阶段 | GATE（guazi_flow_available=true 时） | guazi-flow 调度 | 降级 |
|------|--------------------------------------|----------------|------|
| plan | 加载 guazi-flow-plan/SKILL.md | MUST：产出 index.md + unit.md | goal-pipeline 通用 plan |
| implement | 加载 guazi-flow-implement/SKILL.md | MUST：profile/contract/write_set 驱动 | goal-pipeline 通用 implement |
| runtime_smoke | 无 GATE | 始终用 goal-pipeline 通用脚本 | — |
| review | 加载 guazi-flow-review/SKILL.md | Step 1.5 注入：guazi-flow-review → issues_gf[] | 仅 goal-pipeline 独立审核 |
| complete | 加载 guazi-flow-complete/SKILL.md | MUST：guazi-flow 收口检查 | goal-pipeline 通用 complete |

### 9.3 Lazy Loading

guazi-flow 可用时，每个管线阶段开始前 **MUST 加载**对应 SKILL.md：
- 不加载 → Agent 不知道 guazi-flow 具体指令 → 产物不符合规范
- Do NOT Load：review SKILL 在 plan/implement 阶段；complete SKILL 在 plan/implement/review 阶段


### 9.5 Handoff Bundle 与 Review 并集

```
gate --post(plan)      → handoff/plan.json      (index schema hash)
gate --post(implement) → handoff/implement.json (candidate_diff_hash)
assemble-review-packet → handoff/review-packet.json
guazi-flow-review      → evidence/review.md (issues_gf)
goal-pipeline Step 2   → evidence/review-goal.json (issues_goal)
merge-review-issues    → evidence/review.md annex
gate --post(review)    → handoff/review.json
gate --post(complete)  → handoff/complete.json
```

- plan/implement/complete：**替代**（guazi vs goal-pipeline 互斥）
- review：**并集**（guazi-flow-review + goal-pipeline 独立审核，merged result 两者都 pass 才 complete）
- handoff 由 goal 侧 gate 从磁盘产物反推，**不修改 guazi-flow-* skill**

### 9.4 降级策略

guazi-flow-core 不可用时：
- `guazi_flow_available = false`
- goal-pipeline 独立运行
- 不阻断管线

---

## 10. NEVER 规则（质量红线）

### 10.1 goal-pipeline NEVER

| NEVER | 为什么 |
|-------|--------|
| 跳过 Step 1 确定性检查直接调审核模型 | 零成本检查能发现 secret 泄露、scope 越界 |
| 在同一 blocker 上无限重试 | 3 轮无新策略必须 blocked，避免 token 浪费 |
| 让审核模型与执行模型使用同一 provider | 共享训练盲点，审核独立性受损 |
| 在 review 通过前将 status 设为 complete | complete 需要全部门禁通过 |
| 在 state.json 中存储明文 API key | key 存入 config.json，state.json 仅存审核结论 |
| 在管线执行中途把控制权还给用户 | 除非命中 blocked 条件或 budget 耗尽 |
| 让审核模型看到执行模型的 reasoning chain | 产生确认偏误，倾向认同实现 |
| 在 review not_pass 时修改验收标准来通过 | "降标准而非修代码"的反模式 |

### 10.2 guazi-flow-goal NEVER

| NEVER | 为什么 |
|-------|--------|
| GATE 检查失败后继续执行 guazi-flow 调度 | 必须降级为纯 goal-pipeline |
| 跳过 Lazy Loading 直接执行阶段 | 产物不符合 guazi-flow schema |
| 在 `~/.goal-state/` 中写入 guazi-flow 项目配置 | 写入边界隔离 |
| guazi-flow 不可用时强制加载 guazi-flow-* | 降级运行，不阻断 |
| 修改 goal-pipeline 的 state.json 基础字段 | 扩展字段只能追加 |
| guazi-flow-plan 产出前修改项目代码 | write_set 不匹配 |

---

## 11. 文件结构

### 11.1 项目结构

```
goal/
├── goal-pipeline/
│   ├── SKILL.md                          # 核心引擎定义
│   ├── references/                       # 按需加载的参考文档
│   │   ├── auto-continue-policy.md
│   │   ├── consistency-check.md
│   │   ├── crash-recovery.md
│   │   ├── goal-state-schema.md
│   │   ├── interview-protocol.md
│   │   ├── platform-detection.md
│   │   └── separation-strategies.md
│   └── scripts/                          # 确定性检查脚本
│       ├── verify.sh
│       ├── verify-review.sh
│       ├── detect-review-channels
│       ├── detect-platform
│       ├── check-consistency
│       └── runtime-smoke.sh
├── guazi-flow-goal/
│   ├── SKILL.md                          # 增强层入口
│   └── references/
│       ├── bridge-contract.md
│       ├── guazi-flow-integration.md
│       └── guazi-flow-state-schema.md
├── install.sh                            # 一键安装脚本
├── README.md
└── ARCHITECTURE.md                       # 本文档
```

### 11.2 安装与卸载

```bash
# 一键安装（自动检测所有平台）
curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/main/install.sh | bash

# 指定平台安装
bash install.sh --agent cursor

# 一键卸载
bash install.sh --uninstall

# 彻底卸载（含仓库和状态）
bash install.sh --uninstall --purge
```

### 11.3 渐进披露（三层架构）

| 层 | 何时加载 | 内容 |
|----|---------|------|
| Metadata (frontmatter) | always | name + description |
| SKILL.md Body | 触发后 | 核心定义、NEVER、执行模型 |
| references/ | MANDATORY 标记处 | 详细协议、schema、策略 |

---

## 附录：进度可见化规范

每个阶段开始和结束时，Agent 必须输出：

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

review 未通过时输出 issue 变动追踪（✅已解决 / 🔁持续 / 🆕新增）。

---

*文档版本: 1.0*  
*最后更新: 2025-06*
