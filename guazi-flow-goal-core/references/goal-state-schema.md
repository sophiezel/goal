# Goal State Schema

## 目录结构

```
~/.guazi-flow-goal/                       ← 全局目录（goal 所有产物）
├── config.json                           ← API key + 偏好 + 通道缓存（跨项目通用）
├── projects/
│   └── <project_id>/                    ← sha256(项目根绝对路径)[:12]
│       ├── project.json                  ← {name, root}
│       └── <branch>/                     ← 分支名 or "default"
│           └── <task>/                   ← task slug
│               ├── state.json            ← Goal 状态
│               └── .lock                 ← 并发控制
├── archive/
│   └── <project_id>/
│       └── goal_<id>.json
└── scripts/                              ← 首次部署
    ├── verify.sh
    ├── verify-review.sh
    ├── detect-review-channels
    └── check-consistency

<project>/                                ← 用户项目（不受影响）
├── .guazi-flow/
│   └── config.local.json                 ← JIRA_TOKEN / repos（goal 不碰）
└── docs/guazi-flow/<task>/
    ├── index.md
    ├── evidence/*.md                     ← 任务产物（在项目中，进 git）
    └── units/*.md
```

## 全局配置文件

位置: `~/.guazi-flow-goal/config.json`

```json
{
  "version": 1,
  "api_keys": {
    "OPENAI_API_KEY": "...",
    "ANTHROPIC_API_KEY": "...",
    "GEMINI_API_KEY": "...",
    "GROQ_API_KEY": "...",
    "DEEPSEEK_API_KEY": "..."
  },
  "review_model": "auto",
  "human_review_accepted": false,
  "channel_cache": {
    "last_probed": "ISO8601",
    "channels": {
      "openai/gpt-4o-mini": {"available": true, "last_seen": "ISO"}
    }
  }
}
```

**项目级 `.guazi-flow/config.local.json` 不含任何 goal 产物**：仅 JIRA_TOKEN、FIGMA_ACCESS_TOKEN、repos 等 guazi-flow 自身字段。

## Goal 状态文件

位置: `~/.guazi-flow-goal/projects/<project_id>/<branch>/<task>/state.json`

```json
{
  "version": 1,
  "goal_id": "<timestamp>-<8hex>",
  "project_id": "<sha256(项目根绝对路径)[:12]>",
  "project_name": "my-project",
  "branch": "feature/auth | main | default",
  "objective": "用户目标描述文本（Goal Engineering 产出）",
  "status": "active | paused | complete | blocked | aborted",
  "sisyphus": false,
  "guazi_flow_task": "docs/guazi-flow/<task>",
  "platform": {
    "agent": "codex | claude_code | cursor | windsurf | pi | generic",
    "native_goal": false,
    "agent_mode_continuous": true
  },
  "review_config": {
    "model": "openai/gpt-4o-mini",
    "provider": "openai",
    "separation_confidence": "high | medium",
    "source": "env_var | agent_introspection | ollama_list | user_config"
  },
  "pipeline": {
    "plan": {"status": "done | pending | failed", "evidence_fresh": true},
    "implement": {"status": "done | in_progress | pending | failed", "evidence_fresh": true},
    "review": {"status": "done | in_progress | pending | failed", "evidence_fresh": true},
    "complete": {"status": "done | pending | failed", "evidence_fresh": true}
  },
  "created_at": "ISO8601",
  "updated_at": "ISO8601",
  "pause_reason": "",
  "usage": {
    "turns": 0,
    "tokens_approx": 0
  },
  "budget": {
    "max_turns": 50,
    "current_turn": 0
  },
  "failure_codes": [],
  "last_error": ""
}
```

## Global Config Schema

`~/.guazi-flow-goal/config.json`:

```json
{
  "version": 1,
  "api_keys": {
    "OPENAI_API_KEY": "...",
    "ANTHROPIC_API_KEY": "...",
    "GEMINI_API_KEY": "...",
    "GROQ_API_KEY": "...",
    "DEEPSEEK_API_KEY": "..."
  },
  "review_model": "auto",
  "human_review_accepted": false,
  "channel_cache": {
    "last_probed": "ISO8601",
    "channels": {}
  }
}
```

- `api_keys`: provider → key 映射，写入此文件而非环境变量
- `review_model`: 用户显式覆盖，`"auto"` 表示自动选择
- `human_review_accepted`: 用户是否已接受人工审核模式（全局偏好，非单 goal 决定）
- `channel_cache`: 通道探测结果，每次 Goal 启动刷新

## 状态转换规则

### 创建
- 计算 `project_id = sha256($(git rev-parse --show-toplevel))[:12]`
- 解析 `branch = $(git rev-parse --abbrev-ref HEAD)` or `"default"`
- 检查 `.lock` — 若存在且进程存活 → `goal_already_active`
- 若旧路径 `<project>/.guazi-flow/goal/state.json` 存在 → 迁移到新路径，删除旧文件
- 否则 → 创建新路径 state.json, status = active

### Active → Blocked
- 任一阶段 not_pass 且不可自动恢复
- `failure_codes` 非空且含需用户干预的错误码
- 审核不可用 (`review_unavailable`)

### Active → Paused
- 用户执行 `/guazi-flow-goal-pause`
- 记录 `pause_reason`

### Paused → Active
- 用户执行 `/guazi-flow-goal-resume`
- 运行 `check-consistency` 校验状态一致性
- 若一致性 broken → 修复后继续；若无法修复 → blocked

### Active/Blocked → Complete
- `verify.sh` 输出 `completion_condition_met: true`

### Active/Blocked/Paused → Aborted
- 用户执行 `/guazi-flow-goal-clear`
- state.json 归档到 `~/.guazi-flow-goal/archive/<project_id>/goal_<id>.json`
- 不删除 `docs/guazi-flow/<task>/evidence/`（管线产物保留）

## 并发控制

粒度: `(project_id, branch, task)` 三元组。

锁文件: `~/.guazi-flow-goal/projects/<project_id>/<branch>/<task>/.lock`

- 记录: `pid + created_at + heartbeat_at`
- 同三元组只允许一个 active goal
- 不同分支/不同 task/不同 project_id 可并行
- Stale lock: heartbeat 超 5min + pid 不存活 → 接管

## 持久化保证

- 每次状态变更后 `fsync` state.json
- 崩溃恢复从 state.json + git + evidence 重建
- `state.json` 优先于 agent 内存状态

## 兼容迁移

检测 `<project>/.guazi-flow/goal/state.json` 存在 → 自动迁移到新路径，删除旧文件。
`<project>/.guazi-flow/config.local.json` 中 goal 相关字段（api key / review_model）→ 自动迁移到 `~/.guazi-flow-goal/config.json`，删除旧字段。
