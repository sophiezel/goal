# jian-h5 SCC-41328 回归验证清单

在 **guazi-flow-goal 原生 gate 加固**后，于 jian-h5 仓库自行验证。不依赖 guazi-flow-audit skill。

任务参考：`docs/guazi-flow/2026-07-04-检测回捞门店寄售工单`（Jira SCC-41328）

## 前置

```bash
cd /path/to/jian-h5
bash /path/to/goal/guazi-flow-goal/scripts/guazi-install.sh
bash /path/to/goal/shared/review-kernel/install.sh
```

## 验收表

| # | 场景 | 操作 | 期望 |
|---|------|------|------|
| 1 | 缺 plan 章节 | 故意删掉 index.md 的 `## 任务目标` 后 `gate --post plan` | exit 1；终端 Issue Board；`evidence/plan-gate-fix-input.json` 存在 |
| 2 | `## 写集` 别名 | 使用 `## 写集`（非 `## 范围与写集`）声明路径后 `gate --post plan` | write_set 非空；handoff/plan.json 含路径 |
| 3 | 空 write_set | plan 通过但 write_set 为空时 `gate --post implement` | exit 1；`evidence/implement-gate-fix-input.json`；消息指向写集章节 |
| 4 | 全链路 | `/guazi-flow-goal` 跑完整任务 | 无手动「开始实现」「继续」；`guazi-advance-stage` 自动链 quality/review |
| 5 | review | 正常完成后 review | 经 `$REVIEW_KERNEL_HOME` review chain；**不**调用 guazi-flow-audit |
| 6 | noop 修复 | gate 失败后不改 index 重跑同一 gate | `blocked(noop_fix)` 或 subject_hash 未变提示 |

## 命令示例

```bash
TASK=docs/guazi-flow/2026-07-04-检测回捞门店寄售工单
GATE="${GUAZI_STATE_HOME:-$HOME/.guazi-flow/state}/scripts/guazi-gate-stage.sh"

# 场景 1
$GATE --task-dir "$TASK" --stage plan --post --mode guazi
cat "$TASK/evidence/plan-gate-fix-input.json" | python3 -m json.tool

# 场景 3（需先有 plan handoff）
$GATE --task-dir "$TASK" --stage implement --post --mode guazi
```

## 对比 SCC-41328 存档

存档路径（audit 仓库）：`tmp/scc-41328-execution-archive-2026-07-05.md`

| 存档问题 | goal 加固后 |
|----------|-------------|
| plan 缺章节靠 audit 发现 | gate plan --post 即拦 |
| `## 写集` 导致空 write_set | gate 兼容 `## 写集` |
| 用户手动喊继续 | driver/advance 自动链（SKILL NEVER 强化） |
| 需 guazi-flow-audit | **零依赖** |

## 通过标准

1. 场景 1–3 结构性拦截在 **goal gate** 完成
2. 场景 4–5 全链路无 audit skill
3. 场景 6 noop 有明确 blocked 信号
