# Goal Pipeline

持久化目标执行管线——与 Claude Code `/goal` 对齐的 5 阶段管线引擎。Agent 接到 goal 后持续执行，直到目标完成或遇到阻塞。

**进化轨（`/goal-pipeline`）零外部 skill 依赖，所有 AI Agent 平台通用。** 兼容轨（`/guazi-flow-goal`）需项目内已安装 `guazi-flow-*` 生态 skill。

## 架构

```
goal-pipeline（通用管线引擎 / 进化轨）
  │
  │  ~/.goal-pipeline/state/ 持久化
  │  /goal-pipeline-* 生命周期命令
  │  goal-stage-driver.sh 为每 turn 进度真相
  │
  └── guazi-flow-goal（可选统一入口 / 兼容轨）
        内含桥接契约（references/bridge-contract.md）
        将 guazi-flow-* 系列适配到 goal-pipeline
```

### 双轨架构

| 轨 | 入口 | 阶段执行 | 外部依赖 |
|----|------|----------|----------|
| **进化轨** | `/goal-pipeline` | `goal-pipeline/stages/goal-*` | 无 |
| **兼容轨** | `/guazi-flow-goal` | 黑盒 `guazi-flow-*` + 质检防火墙 | `guazi-flow-plan` 等生态 skill |

两轨共享：`~/.goal-pipeline/state/`、`handoff/*.json`、`plan-quality-gate.py` / `implement-qc-gate.py` / `quality-gate.sh`。详见 [`goal-pipeline/references/dual-track-contract.md`](goal-pipeline/references/dual-track-contract.md)。

### 质检防火墙（兼容轨插入点）

```text
guazi-flow-plan     → plan-quality-gate.py (PQ-01..14)  → gate --post plan
guazi-flow-implement → implement-qc-gate.py (IQ-01..02) + contract-conformance-check.py (IQ-10) → gate --post implement
quality 阶段         → quality-gate.sh        → gate --post quality
```

契约语义门禁（表驱动）：见 **[声明式契约门禁（术语）](goal-pipeline/references/declarative-contract-gates.md)**；RCA 收尾见 **[rca-plan-closeout-checklist.md](goal-pipeline/references/rca-plan-closeout-checklist.md)**。

进化轨将 PQ/IQ 规则内嵌到 `goal-plan` / `goal-implement` SKILL，并调用同一脚本。

## 5 阶段管线

Agent 可见的 Lean 五阶段（脚本层 `runtime_smoke` 为 `quality` 的别名，不单独暴露）：

```
plan → implement → quality → review ↔ complete
                                ↓
                          not_pass → 修复子循环
```

| 阶段 | 职责 |
|------|------|
| **plan** | 目标澄清 + 范围确定 + 审核通道探测 |
| **implement** | 范围内修改代码，产出候选 diff；运行 UVO（`verification-oracle.sh`） |
| **quality** | 内部编排 smoke / validate? / e2e? + `quality-gate.sh` 汇总（L0+L1） |
| **review** | gate-pre → packet → unified LLM → merge → gate-post |
| **complete** | `verify.sh` 全链校验，`goal.status = complete` |

`quality_policy.tier`：`standard`（validate/e2e 可选）| `strict`（validate+e2e 强制）。写入 `state.json.quality_policy.tier`。

### quality 阶段内部编排

```text
runtime-smoke.sh → validate? → e2e? → quality-gate.sh → handoff/quality.json
```

- L0：handoff 链、UVO（`evidence/verification-oracle.json`）、secret scan
- L1：smoke / validate / e2e / test+lint（由 `quality-gate.sh` 汇总）
- L2：仅当 L1 为 `inconclusive` / `partial` / `skipped` 时触发子域 LLM judge
- review 的独立 LLM 始终为 L2（`run-independent-review.sh --mode unified`）

详见 [`goal-pipeline/references/tiered-adjudication.md`](goal-pipeline/references/tiered-adjudication.md)。

### Review 流程

**用户视图**：确定性检查 → 独立审核 → pass / not_pass 分流

**技术步骤**（Agent 聊天输出 Step 0–4）：

| Step | 脚本 | 说明 |
|------|------|------|
| 0 | `gate --pre review` | scope / secret / packet 就绪（test+lint 已在 UVO + quality 完成） |
| 1 | `assemble-review-packet` | 生成 `handoff/review-packet.json` |
| 2 | `run-independent-review --mode unified` | 跨 provider 独立 LLM → `review-unified.json` |
| 3 | `merge-review-issues` | 合并 issues → `review-fix-input.json` |
| 4 | `gate --post review` | 写入 `handoff/review.json` |

桥接层可在 Step 0 与 Step 2 之间注入 **Step 1.5**（如 `guazi-flow-review`），issues 并入 merge 结果。

## Quick Start

**前置条件**：git、bash、python3

```bash
curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/main/install.sh | bash -s -- --channel stable
```

一键完成：克隆仓库 → 检测环境 → universal 部署 skills（Claude 可选副本）→ 初始化 `~/.goal-pipeline/state/` → 部署 Cursor stop hook → 迁移旧数据

安装完成后，在你的 Agent 中输入：

```
/goal-pipeline 给项目加用户认证
```

## 安装

### 一键安装

安装通道（详见 [goal-pipeline/references/release-channel.md](goal-pipeline/references/release-channel.md)）：

| 通道 | 命令 |
|------|------|
| **stable**（推荐） | `curl .../main/install.sh \| bash -s -- --channel stable` |
| **latest**（main 顶端） | `... \| bash -s -- --channel latest` |
| **pinned**（指定版本） | `... \| bash -s -- --ref v1.0.0` |

```bash
# HTTPS（默认，推荐 stable）
curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/main/install.sh | bash -s -- --channel stable

# latest（滚动 main）
curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/main/install.sh | bash -s -- --channel latest

# 固定 tag（可与 tag 上的 install.sh 组合以保证可复现）
curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/main/install.sh | bash -s -- --ref v1.0.0
curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/refs/tags/v1.0.0/install.sh | bash -s -- --ref v1.0.0

# SSH（需已配置 SSH key）
curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/main/install.sh | bash -s -- --ssh --channel stable

# 仅安装 goal-pipeline（跳过 guazi-flow 系列）
curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/main/install.sh | bash -s -- --no-guazi --channel stable

# 限制检测展示的平台列表（skill 仍写入 ~/.agents/skills）
curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/main/install.sh | bash -s -- --agent cursor --channel stable
```

`install.sh` 是**通用安装入口**：按通道解析 Git 引用后克隆/检出 `~/.goal-pipeline/repository`、软链 skill、部署 `~/.goal-pipeline/state` 下的 **runtime**。通道写入 `config.json` → `install`。**不会**读取 `GOAL_DEV_REPO` 或 `config.json` 里的 `dev_repo`（贡献者 pre-push 除外）。

贡献者本地开发的 pre-push 同步见下方「贡献者开发（可选）」。

### 安装过程

```
==========================================
  goal-pipeline installer
==========================================

  Detected agents: pi, codex, claude_code, cursor   ← 环境检测（非 per-agent 安装）
  State dir:       ~/.goal-pipeline/state
  Install mode:    --symlink
  Clone method:    HTTPS

📦 Cloning repository...
📋 Deploying skills...
  → universal: ~/.agents/skills
    ✅ goal-pipeline → symlink (~/.goal-pipeline/repository/...)
    ✅ guazi-flow-goal → symlink
  cleaning platform duplicates...
  → claude_code: ~/.claude/skills   (optional native copy)
📁 Initializing state directory...
  ✅ config.json created
  ✅ Runtime synced to ~/.goal-pipeline/state/ (scripts + kernel + references)
  ✅ Stop hook deployed to ~/.cursor/hooks/goal-pipeline-stop-hook.sh
```

### 安装布局

应用根目录 **`GOAL_HOME`**（默认 `~/.goal-pipeline`）：

| 层 | 路径 | 用途 |
|----|------|------|
| 应用根 | `~/.goal-pipeline` | `GOAL_HOME`；非 git 仓库 |
| 安装仓 | `~/.goal-pipeline/repository` | `GOAL_PIPELINE_REPO`；`install.sh` 克隆的 skill 源码 |
| 运行时 | `~/.goal-pipeline/state` | `GOAL_STATE_HOME`；任务数据 + 部署的 scripts/kernel/references |
| Skills | `~/.agents/skills` | 软链指向 `repository/` 内 skill |

`~/.goal-pipeline/state/VERSION` 记录 `goal_pipeline_version`（来自 `goal-pipeline/VERSION`）、`install_channel`、`git_tag`、`kernel_tree_hash` 等（doctor 做漂移与更新提示）。

skill 软链指向 `~/.goal-pipeline/repository`；**不要**对 stable/pinned 安装仓手动 `git pull`，请用下方更新命令。

> `--agent X` 仅收窄安装日志中的「Detected agents」列表，并影响是否安装 Claude 副本；**skill 始终写入** `~/.agents/skills`。

### 更新

```bash
# 按 config.json 中的通道更新 repository + runtime + skills
bash ~/.goal-pipeline/state/scripts/goal-install.sh --update

# 切换通道或版本后更新
GOAL_CHANNEL=stable bash ~/.goal-pipeline/state/scripts/goal-install.sh --update
bash ~/.goal-pipeline/state/scripts/goal-install.sh --update --channel latest
bash ~/.goal-pipeline/state/scripts/goal-install.sh --update --ref v1.0.0

# 查看当前通道与 VERSION
bash ~/.goal-pipeline/state/scripts/goal-install.sh --status
# 或（安装仓内）
bash install.sh --status

# 仅重部署 runtime（不拉 git）
bash ~/.goal-pipeline/state/scripts/sync-install-repo.sh --deploy-only
```

仅重部署 skill 软链：

```bash
bash ~/.goal-pipeline/state/scripts/deploy-skills.sh
# 或
bash ~/.goal-pipeline/state/scripts/sync-install-repo.sh --skills-only
```

copy 模式需重新运行安装脚本。

### 诊断与维护

```bash
bash ~/.goal-pipeline/state/scripts/goal-pipeline-doctor.sh <project_root>
```

典型检查项：skill 软链是否指向 `~/.goal-pipeline/repository`（禁止指向开发 clone）、`~/.pi/skills` 等重复项、gate/kernel VERSION drift、审核通道、Cursor stop hook。

`goal-pipeline-doctor.sh` 启动时会尝试后台 `sync-install-repo.sh --quiet`。

**Cursor hooks**（install 默认部署）：

| Hook | 路径 | 作用 |
|------|------|------|
| stop | `~/.cursor/hooks/goal-pipeline-stop-hook.sh` | turn 结束前 `gate --assert-complete`，未完成则继续 |
| session-start | `goal-pipeline-session-start-hook.sh` | **未默认安装**；需手动写入 `hooks.json` 方可启用 active-goal 提醒与后台 sync |

### 贡献者开发（可选）

若你在本地 clone 本仓库参与开发（与 `curl | bash` 安装无关），可使用额外同步工具：

| 层 | 路径 | 用途 |
|----|------|------|
| 开发 | 本地 git clone | 改代码、跑 gate tests、`git push` |
| 安装 | `~/.goal-pipeline/repository` | 与上方相同；可由 pre-push 从开发仓 fast-forward |

**硬规则**：skill 软链**禁止**指向本地开发 clone；`--from-dev` / `DEPLOY_SOURCE` 仅用于维护者把 **runtime**（`scripts/` + `kernel/` + `references/`）从本地 dev clone 部署到 `~/.goal-pipeline/state`，skill 始终从安装仓部署。

首次启用 pre-push hook（在开发 clone 根目录执行一次）：

```bash
bash scripts/setup-dev-sync-hooks.sh
```

之后 `git push` 会自动：同步 `~/.goal-pipeline/repository`、部署 scripts、重部署 skill 软链。

手动从开发 clone 同步：

```bash
bash "${GOAL_STATE_HOME:-$HOME/.goal-pipeline/state}/scripts/sync-install-repo.sh" \
  --from-dev /path/to/your/goal-dev-clone --deploy-only
# 等价：DEPLOY_SOURCE=/path/to/your/goal-dev-clone ... --deploy-only
```

### 卸载

卸载与安装通道无关（移除 skills；`--purge` 删除 `repository` + `state`）。

#### 统一卸载（推荐）

```bash
bash install.sh --uninstall
# 或
bash ~/.goal-pipeline/state/scripts/deploy-skills.sh --uninstall --also-platform-native
```

清除 `~/.agents/skills` 中的 skill、平台目录重复项、以及 `~/.claude/skills` 可选副本。仓库和状态目录默认保留。

`--agent` 在存在 `deploy-skills.sh` 时**不改变**卸载范围；仅当该脚本缺失时，回退逻辑才按检测到的平台列表删除。

#### 彻底卸载（含仓库和状态）

```bash
bash install.sh --uninstall --purge
```

`--purge` 会额外删除：
- `~/.goal-pipeline/repository/`（代码仓库）
- `~/.goal-pipeline/state/`（状态目录，含历史 goal）

#### 手动删除

```bash
rm ~/.agents/skills/goal-pipeline ~/.agents/skills/guazi-flow-goal
rm ~/.claude/skills/goal-pipeline ~/.claude/skills/guazi-flow-goal  # 若存在
rm -rf ~/.goal-pipeline/repository
rm -rf ~/.goal-pipeline/state
```

### 参数

| 参数 | 说明 |
|------|------|
| `--channel stable\|latest\|pinned` | 安装通道（默认 `stable`） |
| `--ref REF` | 固定 tag 或 commit（隐含 pinned） |
| `--update` | 按 config/通道重新同步并部署 |
| `--status` | 打印通道与 VERSION 摘要 |
| `--symlink` | 符号链接（默认） |
| `--copy` | 复制文件 |
| `--ssh` | SSH 克隆 |
| `--agent X` | 限制检测展示的平台；skill 仍部署到 `~/.agents/skills` |
| `--no-guazi` | 仅安装 goal-pipeline |
| `--uninstall` | 统一卸载 skills（universal + 去重 + Claude 副本） |
| `--purge` | 配合 `--uninstall`，同时删除仓库和状态目录 |

### 支持平台

`goal-pipeline` / `guazi-flow-goal` 部署到 **跨平台通用目录** `~/.agents/skills/`（Pi、Cursor 等均会扫描）。Claude Code 额外在 `~/.claude/skills/` 保留一份原生副本。不在 `~/.cursor/skills`、`~/.pi/skills` 等平台目录重复安装，避免 Pi `[Skill conflicts]`。

> 若 `~/.cursor/skills` 已软链到 `~/.agents/skills`（常见配置），`deploy-skills.sh` 会自动跳过对该路径的「重复清理」，避免误删通用入口。`goal-pipeline-doctor.sh` 会报告重复软链。

| 角色 | Skills 目录 | 说明 |
|------|-----------|------|
| **通用（主入口）** | `~/.agents/skills/` | goal-pipeline / guazi-flow-goal 唯一入口 |
| Claude Code（可选副本） | `~/.claude/skills/` | 仅当检测到 `.claude/` |
| 生态 skill | `~/.agents/skills/` | guazi-flow-plan、e2e-device 等第三方 skill 同目录 |
| 运行时 | `~/.goal-pipeline/state/` | `scripts/`、`kernel/`、`references/`（gate / sync / doctor；非 skill） |

检测信号（`install.sh` 用于判定是否安装 Claude 副本等）：

| 平台 | 检测信号 |
|------|---------|
| Claude Code | `.claude/` |
| Cursor | `.cursor/` |
| Pi | `.pi/` 或 `$PI_HOME` |
| Codex | `.codex/` |
| Windsurf | `.windsurf/` |
| Qoder | `.qoder/` |
| 其他 | 见 `install.sh` `detect_all_agents` |

## 使用

### 命令

| 命令 | 操作 |
|------|------|
| `/goal-pipeline <目标>` | 启动新 goal |
| `/goal-pipeline` | 恢复当前 active goal |
| `/goal-pipeline-status` | 查看当前 goal 状态 |
| `/goal-pipeline-pause` | 暂停，释放锁 |
| `/goal-pipeline-resume` | 从断点继续 |
| `/goal-pipeline-clear` | 归档到 archive/ |
| `/goal-pipeline-list` | 查看历史 |

每个 Agent turn 以 `goal-stage-driver.sh` 输出的 `work_order.next_stage` 为进度真相，禁止自行推断阶段。

### guazi-flow-goal（guazi-flow 项目增强入口）

在 guazi-flow 项目中使用，加载 goal-pipeline 并在各阶段调度 guazi-flow-* 增强。

```bash
# 启动（5 阶段：plan → implement → quality → review → complete）
/guazi-flow-goal 给项目加用户认证

# 生命周期命令（/guazi-flow-goal-* 为 /goal-pipeline-* 的别名）
/guazi-flow-goal-status      # 查看状态（含 guazi-flow 任务目录）
/guazi-flow-goal-pause       # 暂停
/guazi-flow-goal-resume      # 继续
/guazi-flow-goal-clear       # 归档
/guazi-flow-goal-list        # 历史
```

| 阶段 | 兼容轨调度 | 防火墙 |
|------|------------|--------|
| plan | guazi-flow-plan | plan-quality-gate.py |
| implement | guazi-flow-implement | implement-qc-gate.py (UVO) |
| quality | goal-quality | quality-gate.sh |
| review | guazi-flow-review（Step 1.5）+ unified LLM | gate pre/post |
| complete | guazi-flow-complete | verify.sh |

与 `/goal-pipeline` 的区别：

- 各阶段自动调度 guazi-flow-plan / implement / review / complete，quality 共用 `goal-quality`
- review 阶段在 unified 独立审核之外，追加 guazi-flow-review 专业审核（Step 1.5）
- state.json 包含 guazi-flow 扩展字段（task 目录、profile、stages、artifact_layout）
- guazi-flow 不可用时自动降级为纯 goal-pipeline 运行

### 示例

```
> /goal-pipeline 给项目加用户认证

[1/5] plan:      🔄 目标规划中...
[1/5] plan:      ✅ plan 卡片已生成

[2/5] implement: 🔄 执行中...
[2/5] implement: ✅ 5 files changed

[3/5] quality:   🔄 smoke + quality-gate...
[3/5] quality:   ✅ quality-gate pass (smoke: localhost:8000, 35s)

[4/5] review:    🔄 Step 2: unified review...
                 审核模型: deepseek-v4-flash (独立于执行模型)
[4/5] review:    ✅ 通过 (1 轮)

[5/5] complete:  🔄 收口中...
[5/5] complete:  ✅ 目标完成
```

**guazi-flow-goal 示例**（guazi-flow 项目增强入口）：

```
> /guazi-flow-goal 给项目加用户认证

🔍 环境检测: profile = h5, guazi_flow_available = true

[1/5] plan:      🔄 guazi-flow-plan 生成结构化文档...
[1/5] plan:      ✅ docs/guazi-flow/user-auth/index.md + 3 units
                 任务: docs/guazi-flow/user-auth/

[2/5] implement: 🔄 guazi-flow-implement (profile/contract 驱动)...
[2/5] implement: ✅ 8 files changed, UVO pass

[3/5] quality:   🔄 smoke + quality-gate...
[3/5] quality:   ✅ quality-gate pass

[4/5] review:    🔄 审核编排...
                 Step 0:   gate --pre → pass
                 Step 1.5: guazi-flow-review → 2 warnings (不阻断)
                 Step 2:   unified LLM deepseek-v4-flash → pass
                 Step 4:   gate --post → handoff/review.json
[4/5] review:    ✅ 通过 (1 轮)

[5/5] complete:  🔄 guazi-flow-complete 收口中...
[5/5] complete:  ✅ 目标完成
                 📁 handoff: quality.json, review.json
                 📁 evidence: verification-oracle.json, review-unified.json
```

### 原生 /goal 集成

平台支持原生 `/goal` 时（Claude Code / Codex / Pi），goal-pipeline 利用平台持久化和 auto-continue 能力，`state.json` 作为双保险。

## 持久化

```
~/.goal-pipeline/state/
├── config.json                     ← API keys + 偏好 + channel_cache
├── projects/
│   └── <project_id>/
│       └── <branch>/<task>/
│           ├── state.json          ← Goal 状态 + quality_policy + artifact_layout
│           ├── handoff/            ← plan.json … quality.json … review.json
│           ├── artifacts/          ← guazi split 模式 Tier-R 产物
│           └── .lock               ← 并发控制
├── archive/                        ← 已归档 goals
└── scripts/                        ← 管线脚本（gate / sync / doctor）

docs/guazi-flow/<task>/             ← 兼容轨任务目录（Tier-G + evidence）
  evidence/
    verification-oracle.json
    review-unified.json
    runtime-smoke.md
```

`project_id = sha256(项目根绝对路径)[:12]`

## 审核通道自动配置

审核模型不可用时，Agent 主动帮用户配置：

- **路径 A**：Ollama 全自动（RAM ≥ 8GB）
- **路径 B**：Gemini 半自动（30 秒）
- **路径 C**：人工审核（逃生通道）

## 与 Claude Code /goal 对齐

| | Claude Code /goal | Goal Pipeline |
|---|---|---|
| 审核 | 每轮评估 | 独立模型 review + 修复子循环 |
| 自动修复 | 无限循环 | 同一 blocker 3 轮无新策略 → 暂停 |
| Budget | Token 预算 | Token 预算 + 三级提示 |
| 持久化 | Session-scoped | 磁盘 state.json（跨 session） |
| 扩展 | 无 | 通过桥接层按需增强 |

## 进一步阅读

- [`ARCHITECTURE.md`](ARCHITECTURE.md) — 完整架构设计
- [`goal-pipeline/references/dual-track-contract.md`](goal-pipeline/references/dual-track-contract.md) — 双轨边界
- [`goal-pipeline/references/tiered-adjudication.md`](goal-pipeline/references/tiered-adjudication.md) — L0/L1/L2 分层裁决

## License

MIT
