# Plan-before-code（硬门禁）

阶段序是安全属性，不是文档建议。

## 规则

`¬plan_gate_passed ⇒ ¬write(src ∪ write_set)`

判定：`handoff/plan.json.gate.passed_at` 存在且 `post_exit_code==0`（缺省兼容仅 `passed_at`）。

## 拦截面

| 层 | 入口 | 行为 |
|----|------|------|
| Gate pre plan | `gate-guazi-flow-stage.sh --stage plan --pre` | 脏 src → `plan_code_order` |
| Gate pre implement | `--stage implement --pre` | 无 plan gate → fail；通过后允许写代码 |
| Assert | `assert-plan-before-code.sh` | 独立预检 / driver / advance |
| Advance | `goal-advance-stage.sh` | next=plan 且脏树 → blocked，不默许「脏树补 plan」 |
| Driver | `goal-stage-driver.sh` | `code_writes_allowed`；plan 阶段 NEVER 写 src |

## 修复

1. `git stash` / reset 护栏路径  
2. 完成 `guazi-flow-plan` + `gate --post plan`  
3. 再进入 implement

## 时区

`evidence/pipeline-timing.json` 仅写 `timestamp_utc`（`Z` 后缀 = UTC）。
