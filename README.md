# Goal Pipeline

持久化目标执行管线——与 Claude Code `/goal` 对齐的 5 阶段管线引擎。Agent 接到 goal 后持续执行，直到目标完成或遇到阻塞。

**零外部依赖，所有 AI Agent 平台通用。**

## 架构

```
goal-pipeline（通用管线引擎）
  │
  │  ~/.goal-state/ 持久化
  │  /goal-pipeline-* 生命周期命令
  │
  └── guazi-flow-goal（可选统一入口）
        内含桥接契约（references/bridge-contract.md）
        将 guazi-flow-* 系列适配到 goal-pipeline
```

## 5 阶段管线

```
plan → implement → runtime_smoke → review ↔ complete
                                ↓
                          not_pass → 修复子循环
```

| 阶段 | 职责 |
|------|------|
| **plan** | 目标澄清 + 范围确定 + 审核通道探测 |
| **implement** | Agent 在范围内修改代码，产出候选 diff |
| **runtime_smoke** | 验证项目可启动（条件触发） |
| **review** | 三步审核：确定性检查 → 独立模型审核 → 分流 |
| **complete** | 所有门禁通过，goal 完成 |

### 三步审核流程

```
Step 1: 确定性检查（0 模型调用）— scope + secret + test + lint
Step 2: 独立审核（跨 provider API 模型）— diff + 验收标准 → issues[]
Step 3: 分流 — pass → complete / not_pass → 修复子循环
```

桥接层可在 Step 1 和 Step 2 之间注入额外审核步骤。

## Quick Start

**前置条件**：git、bash、python3

```bash
curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/main/install.sh | bash
```

一键完成：克隆仓库 → 检测平台 → 部署 skills → 初始化 `~/.goal-state/` → 迁移旧数据

安装完成后，在你的 Agent 中输入：

```
/goal-pipeline 给项目加用户认证
```

## 安装

### 一键安装

```bash
# HTTPS（默认，推荐）
curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/main/install.sh | bash

# SSH（需已配置 SSH key）
curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/main/install.sh | bash -s -- --ssh

# 仅安装 goal-pipeline（跳过 guazi-flow 系列）
curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/main/install.sh | bash -s -- --no-guazi

# 指定平台
curl -fsSL https://raw.githubusercontent.com/sophiezel/goal/main/install.sh | bash -s -- --agent cursor
```

### 安装过程

```
==========================================
  goal-pipeline installer
==========================================

  Detected agents: pi, codex, claude_code, cursor   ← 检测到多个平台
  State dir:       ~/.goal-state
  Install mode:    --symlink
  Clone method:    HTTPS

📦 Cloning repository...
📋 Deploying skills...
  → pi:          ~/.pi/skills/
    ✅ goal-pipeline → symlink
    ✅ guazi-flow-goal → symlink
  → cursor:      ~/.cursor/skills/
    ✅ goal-pipeline → symlink
    ✅ guazi-flow-goal → symlink
  ...
📁 Initializing state directory...
  ✅ config.json created
  ✅ Scripts deployed to ~/.goal-state/scripts/
```

> 只安装到特定平台：`bash install.sh --agent cursor`

### 更新

symlink 模式（默认）下，只需：

```bash
cd ~/.goal-pipeline-repo && git pull
```

copy 模式需重新运行安装脚本。

### 卸载

```bash
# 删除 skills 链接
rm ~/.claude/skills/goal-pipeline
rm ~/.claude/skills/guazi-flow-goal

# 删除仓库
rm -rf ~/.goal-pipeline-repo

# 删除状态（可选，会丢失历史 goal）
rm -rf ~/.goal-state
```

### 参数

| 参数 | 说明 |
|------|------|
| `--symlink` | 符号链接（默认，git pull 自动更新） |
| `--copy` | 复制文件 |
| `--ssh` | SSH 克隆 |
| `--agent X` | 强制指定平台（跳过自动检测） |
| `--no-guazi` | 仅安装 goal-pipeline |

### 支持平台

自动检测并部署到对应 skills 目录：

| 平台 | Skills 目录 | 检测信号 |
|------|-----------|---------|
| Claude Code | `~/.claude/skills/` | `.claude/` |
| Cursor | `~/.cursor/skills/` | `.cursor/` |
| Codex | `~/.codex/skills/` | `.codex/` |
| Pi | `~/.pi/skills/` | `.pi/` 或 `$PI_HOME` |
| Windsurf | `~/.windsurf/skills/` | `.windsurf/` |
| Qoder | `~/.qoder/skills/` | `.qoder/` |
| Hermes | `~/.hermes/skills/` | `.hermes/` |
| Continue | `~/.continue/skills/` | `.continue/` |
| Roo | `~/.roo/skills/` | `.roo/` |
| Generic | `~/.agents/skills/` | fallback |

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

### guazi-flow-goal（guazi-flow 项目增强入口）

在 guazi-flow 项目中使用，加载 goal-pipeline 并在各阶段调度 guazi-flow-* 增强。

```bash
# 启动（触发 /guazi-flow-plan → /guazi-flow-implement → /guazi-flow-review → /guazi-flow-complete）
/guazi-flow-goal 给项目加用户认证

# 生命周期命令（/guazi-flow-goal-* 为 /goal-pipeline-* 的别名）
/guazi-flow-goal-status      # 查看状态（含 guazi-flow 任务目录）
/guazi-flow-goal-pause       # 暂停
/guazi-flow-goal-resume      # 继续
/guazi-flow-goal-clear       # 归档
/guazi-flow-goal-list        # 历史
```

与 `/goal-pipeline` 的区别：

- 各阶段自动调度 guazi-flow-plan / guazi-flow-implement / guazi-flow-review / guazi-flow-complete
- review 阶段在 goal-pipeline 独立审核之外，追加 guazi-flow-review 专业审核（Step 1.5）
- state.json 包含 guazi-flow 扩展字段（task 目录、profile、stages）
- guazi-flow 不可用时自动降级为纯 goal-pipeline 运行

### 示例

```
> /goal-pipeline 给项目加用户认证

[1/5] plan:      🔄 目标规划中...
[1/5] plan:      ✅ plan 卡片已生成

[2/5] implement: 🔄 执行中...
[2/5] implement: ✅ 5 files changed

[3/5] smoke:     🔄 runtime-smoke 验证项目启动...
[3/5] smoke:     ✅ pnpm run dev → localhost:8000 (35s)

[4/5] review:    🔄 独立模型审核中...
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
[2/5] implement: ✅ 8 files changed, contract 全部匹配

[3/5] smoke:     🔄 runtime-smoke 验证项目启动...
[3/5] smoke:     ✅ pnpm run dev → localhost:8000 (35s)

[4/5] review:    🔄 三步审核...
                 Step 1:   verify-review.sh → pass
                 Step 1.5: guazi-flow-review → 2 warnings (不阻断)
                 Step 2:   独立模型 deepseek-v4-flash → pass
[4/5] review:    ✅ 通过 (1 轮)

[5/5] complete:  🔄 guazi-flow-complete 收口中...
[5/5] complete:  ✅ 目标完成
                 📁 evidence: review.md, complete.md, runtime-smoke.md
```

### 原生 /goal 集成

平台支持原生 `/goal` 时（Claude Code / Codex / Pi），goal-pipeline 利用平台持久化和 auto-continue 能力，`state.json` 作为双保险。

## 持久化

```
~/.goal-state/
├── config.json                     ← API keys + 偏好
├── projects/
│   └── <project_id>/
│       └── <branch>/<task>/
│           ├── state.json          ← Goal 状态
│           └── .lock               ← 并发控制
├── archive/                        ← 已归档 goals
└── scripts/                        ← 管线脚本
```

`project_id = sha256(项目根绝对路径)[:12]`

### 迁移

首次安装自动检测并迁移旧数据：

- `~/.guazi-flow-goal/` → `~/.goal-state/`

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

## License

MIT
