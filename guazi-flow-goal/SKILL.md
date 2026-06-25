---
name: guazi-flow-goal
description: guazi-flow-goal 统一入口。加载 goal-pipeline 管线引擎，检测 guazi-flow-* 可用性，在 plan/implement/review/complete 各阶段 MUST 调度 guazi-flow 增强。用户通过 `/guazi-flow-goal <目标>` 触发。包含生命周期管理（status/pause/resume/clear/list）。guazi-flow 不可用时 goal-pipeline 独立运行。
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

## 必读 references

### 启动时加载（MANDATORY）

| 文件 | 用途 |
|------|------|
| `goal-pipeline/SKILL.md` | 通用管线引擎定义（管线流程、修复循环、审核、进度可见化） |
| `guazi-flow-goal-bridge/SKILL.md` | 桥接层（goal-pipeline ↔ guazi-flow 关系） |
| `guazi-flow-goal-bridge/references/guazi-flow-integration.md` | guazi-flow 调度规则（MUST + 条件触发） |
| `goal-pipeline/references/interview-protocol.md` | 三步收敛访谈协议 |
| `goal-pipeline/references/platform-detection.md` | 平台检测和能力矩阵 |
| `goal-pipeline/references/separation-strategies.md` | 审核模型多通道探测策略 |

### guazi-flow 可用性检测

```
加载 goal-pipeline 后：
if guazi-flow-core/SKILL.md 存在（通过 skill 加载机制）:
    guazi_flow_available = true
    加载 guazi-flow-core/SKILL.md（版本检查）
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

---

## Phase 1: Goal Engineering

**Before dispatching, ask yourself**: guazi_flow_available? profile? 有无 active goal?

```
Step 1: 环境初始化
  ├─ 运行 detect-platform → 确定平台
  ├─ 加载 guazi-flow-goal-bridge (版本检查) → 确定 guazi_flow_available
  └─ 检查是否已有 active goal
      ├─ 有 → goal_already_active, 提示用户 [继续/清除/查看]
      └─ 无 → 继续

Step 2-3: 意图采集 + 自动推断 (interview-protocol.md)
  ├─ 解析用户输入 → 保留原始文本作为 objective
  ├─ 调 guazi-flow-doctor（如果可用）→ 检测 profile/profile_detail
  ├─ scope: git status + 关键词匹配 | constraints: AGENTS.md + profile
  └─ 缺口检测 + 定向追问 (最多 5 题，每题附带默认选项)

Step 4: 生成 + 确认 Goal 结构
  ├─ 组装: 目标描述 + 验收标准 + 范围 + 约束 + 验证方式
  ├─ 展示给用户确认 → 确认/编辑/重新讨论/放弃
  └─ 确认 → 继续 Step 5

Step 5: 初始化 state
  ├─ 确保 ~/.goal-state/ 目录存在 + 首次部署脚本
  ├─ 计算 project_id = sha256(项目根绝对路径)[:12]
  ├─ 解析 branch = git rev-parse --abbrev-ref HEAD or "default"
  ├─ 创建 ~/.goal-state/projects/<pid>/<branch>/<task>/state.json
  └─ 检测并迁移旧路径 .guazi-flow/goal/ 产物（若存在）

Step 6: Gate Check（全部满足才进入 Phase 2）
  ├─ [✓] state.json 已创建且 schema 校验通过
  ├─ [✓] 用户已确认 Goal 内容
  ├─ [✓] guazi-flow-* SKILL.md 可加载（或 guazi_flow_available = false）
  └─ [✓] 输出进度摘要 → 进入 Phase 2
```

---

## Phase 2: Pipeline Execution

管线流程详见 `goal-pipeline/SKILL.md`。本层在每个阶段注入 GATE 检查和 guazi-flow-* 调度：

| 阶段 | GATE（guazi_flow_available=true 时） | guazi-flow 调度 | 降级 |
|------|--------------------------------------|----------------|------|
| plan | 加载 guazi-flow-plan/SKILL.md | MUST：产出 docs/guazi-flow/<task>/index.md + unit.md | goal-pipeline 通用 plan |
| implement | 加载 guazi-flow-implement/SKILL.md | MUST：profile/contract/write_set 驱动 | goal-pipeline 通用 implement |
| runtime_smoke | 无 GATE | 始终用 goal-pipeline 通用脚本 | — |
| review | 加载 guazi-flow-review/SKILL.md | Step 1.5 注入：guazi-flow-review → issues_gf[] | 仅 goal-pipeline 独立审核 |
| complete | 加载 guazi-flow-complete/SKILL.md | MUST：guazi-flow 收口检查 | goal-pipeline 通用 complete |

**条件触发阶段**（不可用时跳过，不提供通用替代）：

| 阶段 | 触发条件 |
|------|----------|
| postmerge | resolved_rule_context.postmerge_policy = required |
| validate | 用户显式开启 / validate_policy = required |
| e2e | 用户明确选择 + h5 profile |

管线细节（阶段流程、修复循环、进度输出）由 `goal-pipeline/SKILL.md` 定义。本层只负责 guazi-flow-* 调度。

---


## 生命周期管理

| 命令 | 操作 |
|------|------|
| `/goal-pipeline-status` (别名 `/guazi-flow-goal-status`) | 读取 state.json + verify.sh，输出中文摘要 |
| `/goal-pipeline-pause` (别名 `/guazi-flow-goal-pause`) | status = paused, 释放 .lock |
| `/goal-pipeline-resume` (别名 `/guazi-flow-goal-resume`) | check-consistency → status = active |
| `/goal-pipeline-clear` (别名 `/guazi-flow-goal-clear`) | 归档 state.json → archive/，保留 evidence/ |
| `/goal-pipeline-list` (别名 `/guazi-flow-goal-list`) | 遍历 archive/*/goal_*.json，输出历史列表 |

### status 输出格式

```
🎯 当前目标: 给项目加用户认证
📊 状态: 活跃
📍 管线: plan(✓) → implement(✓) → review( ) → complete( )
📈 进度: 50% (第 2/4 步)
📁 任务: docs/guazi-flow/user-auth/
🔍 审核: deepseek-v4-flash | 分离置信度: high
📊 消耗: 2 轮 / 最大 50 轮
```

### 路径解析

- `project_id = sha256($(git rev-parse --show-toplevel))[:12]`
- `branch = $(git rev-parse --abbrev-ref HEAD)` or `"default"`
- state.json: `~/.goal-state/projects/<pid>/<branch>/<task>/state.json`

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
| 业务代码 | 委托 guazi-flow-implement 或 goal-pipeline 通用 implement |
| `<project>/.guazi-flow/` | ❌ 不写入 goal 产物 |

## 错误处理

| 场景 | 行为 |
|------|------|
| goal_already_active | 展示当前 goal 状态，提供 [继续/清除/查看] 选项 |
| profile 检测失败 | 询问用户手动指定技术栈 |
| guazi-flow-core 版本不兼容 | 警告 + 降级为纯 goal-pipeline |
| state.json 与 docs/guazi-flow/ 不一致 | 运行 check-consistency 修复或归档重建 |
| guazi-flow-plan 失败 | 输出错误，暂停，让用户修复后重试 |
| 审核通道全部不可用 | 输出告警 + 安装建议，implement 前仍不可用则暂停 |
| 用户中途取消 | 不创建 state.json，不残留 |

## 完成门禁

- Goal status = complete（goal-pipeline 判定）
- evidence/complete.md 存在且 pass+fresh
- evidence/review.md 存在且 pass+fresh
- guazi-flow 可用时: evidence 符合 guazi-flow schema
