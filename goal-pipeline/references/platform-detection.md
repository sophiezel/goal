# Platform Detection

## 检测方法

`scripts/detect-platform` 输出 JSON:

```json
{
  "agent": "pi | codex | claude_code | cursor | windsurf | generic",
  "version": "version_string_or_unknown",
  "capabilities": {
    "agent_mode_continuous": true,
    "native_goal": false,
    "sub_agent": true,
    "model_switch": true,
    "api_call": true
  }
}
```

## 检测信号

| Platform | Detection Signal | Priority |
|----------|-----------------|----------|
| **Pi** | `PI_*` 环境变量存在, `.pi/` 目录存在, agent 工具包含 `propose_goal_draft` | 1 (most specific) |
| **Codex** | `CODEX_HOME` 环境变量, `codex` CLI 可用, `.codex/` 配置目录 | 2 |
| **Claude Code** | `.claude/` 目录存在, `CLAUDE_CODE_*` 变量, 或 agent 识别自身为 Claude | 3 |
| **Cursor** | `.cursor/` 目录存在, `CURSOR_*` 变量, 或 IDE 标识 | 4 |
| **Windsurf** | `.windsurf/` 目录存在, `WINDSURF_*` 变量 | 5 |
| **Generic** | 以上全部不命中 | fallback |

## 检测逻辑（bash 实现）

```bash
detect_platform() {
  # 1. Pi
  if [ -n "${PI_HOME:-}" ] || [ -d ".pi" ] || [ -n "${PI_AGENT:-}" ]; then
    echo "pi"; return
  fi
  
  # 2. Codex
  if [ -n "${CODEX_HOME:-}" ] || command -v codex &>/dev/null; then
    echo "codex"; return
  fi
  
  # 3. Claude Code
  if [ -d ".claude" ] || [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    echo "claude_code"; return
  fi
  
  # 4. Cursor
  if [ -d ".cursor" ] || [ -n "${CURSOR_SESSION:-}" ]; then
    echo "cursor"; return
  fi
  
  # 5. Windsurf
  if [ -d ".windsurf" ] || [ -n "${WINDSURF_HOME:-}" ]; then
    echo "windsurf"; return
  fi
  
  # 6. Generic
  echo "generic"
}
```

## 能力矩阵

| Capability | Pi | Codex | Claude Code | Cursor | Windsurf | Generic |
|-----------|:--:|:--:|:--:|:--:|:--:|:--:|
| agent_mode_continuous | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| native_goal | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| sub_agent | ✅ | ⚠️ | ⚠️ | ❌ | ❌ | ❌ |
| model_switch (programmatic) | ✅ | ❌ | ⚠️ | ❌ | ❌ | ❌ |
| api_call (curl) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### 能力说明

- **agent_mode_continuous**: Agent 能否在一个 turn 内持续执行多步操作（所有平台 ✅）
- **native_goal**: 平台是否有原生 goal 机制（Pi:/goals, Codex:/goal, ClaudeCode:/goal）
- **sub_agent**: 能否程序化 spawn 独立子 agent（Pi: Agent tool, Codex: side chat）
- **model_switch**: 能否程序化切换模型（Pi: Agent tool model param）
- **api_call**: 能否通过 curl/python 调外部 API（所有平台 ✅）

## 重要说明

**不依赖 native_goal。** guazi-flow-goal 使用 agent_mode_continuous（所有平台可用）作为执行引擎。native_goal 仅作为可选增强，用于跨 session 持久化恢复等场景。

**不依赖 sub_agent 做审核分离。** 审核分离通过 API 直调独立模型实现，所有平台统一支持。
