# Plan-before-code（硬门禁）

阶段序是安全属性，不是文档建议。

## 规则

`¬plan_gate_passed ⇒ ¬write(src ∪ write_set)`

判定：`handoff/plan.json.gate.passed_at` 存在且 `post_exit_code==0`（缺省兼容仅 `passed_at`）。

## 拦截面

| 层 | 入口 | 行为 |
|----|------|------|
| Gate pre plan | `guazi-gate-stage.sh --stage plan --pre` | 脏 src → `plan_code_order` |
| Gate pre implement | `--stage implement --pre` | 无 plan gate → fail；通过后允许写代码 |
| Assert | `assert-plan-before-code.sh` | 独立预检 / advance |
| Advance | `guazi-advance-stage.sh` | next=plan 且脏树 → blocked，不默许「脏树补 plan」 |

> Goal 轨仍使用 `gate-goal-stage.sh` / `goal-advance-stage.sh`；guazi v1.4 独立安装后入口为 `guazi-gate-stage.sh` / `guazi-advance-stage.sh`（`$GUAZI_STATE_HOME/scripts/`）。

## goal-plan 步骤（默认轨）

1. Phase 1 访谈（`interview-protocol.md`）→ plan 卡片 / goal brief
2. `gate-goal-stage.sh --stage plan --pre`
3. 按 `goal-plan` SKILL 产出范围、验收标准、Allowed Files（`docs/goal/<task>/` 或 profile `task_docs_root`）
4. `plan-quality-gate.py`（PQ 防火墙）
5. `gate-goal-stage.sh --stage plan --post` → `handoff/plan.json`
6. `validate-pipeline-chain.sh` → 才允许 `[2/5] implement`

`plan_profile: goal_lite`（纯 goal XS/S）：不强制 guazi index 六段；gate 放宽 index 硬校验，PQ/plan post 仍须 exit 0。

## guazi 适配轨（可选）

`pipeline_track=guazi` 时步骤 3 可对照 `guazi-flow-plan`；gate 入口为 `guazi-gate-stage.sh`（经 `guazi-install` 部署到 `GUAZI_STATE_HOME`）。

## 修复

1. `git stash` / reset 护栏路径  
2. 完成 `goal-plan` + `gate --post plan`  
3. 再进入 implement

## 时区

`evidence/pipeline-timing.json` 仅写 `timestamp_utc`（`Z` 后缀 = UTC）。
