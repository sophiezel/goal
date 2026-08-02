# Phase-7 goal-pipeline v1.4 双管线完全独立实现收口

**Map:** [Wayfinder #70 — 完全独立 + 公共服务抽取](https://github.com/sophiezel/goal/issues/70)  
**Spec SSOT:** [optimization-spec-outline-v1.4.md](research/optimization-spec-outline-v1.4.md)  
**宪章:** [two-pipeline-independence-ratification.md](research/two-pipeline-independence-ratification.md)  
**分支:** `feat/pipeline-adapter-boundary`（实现变更待 commit）

## 子票 / V14 闭合

| ID | 摘要 | 关键产物 |
|----|------|----------|
| #73 | 公共服务抽取研究 | [shared-services-extraction-options.md](research/shared-services-extraction-options.md) |
| V14-1 | review-kernel 抽出 | `shared/review-kernel/`、`shared/review-schema/`、`install.sh` |
| V14-2 | goal 删 guazi | 删除 gate-guazi、adapter 夹具、`--mode guazi` 等 |
| V14-3 | goal 接 kernel | `resolve-review-kernel-home.sh`、chain 薄包装 |
| V14-4 | guazi 独立 gate | `guazi-flow-goal/scripts/guazi-gate-stage.sh`、`guazi-install.sh` |
| V14-5 | guazi SKILL 独立 | `guazi-flow-goal/SKILL.md` v1.4 全文 |
| V14-6 | guazi 夹具 | `guazi-flow-goal/fixtures/guazi-gate/` |
| V14-7 | skill 门槛 | [writing-great-skills-dual-pipeline-gate.md](research/writing-great-skills-dual-pipeline-gate.md) |
| V14-8 | sweep | 本文 |

## P2 闭合（2026-08-03）

| 项 | 状态 |
|----|------|
| `guazi-flow-goal/SKILL.md` 全文 v1.4 重写 | ✅ |
| `goal-pipeline/SKILL.md` 去除 guazi 适配叙述 | ✅ |
| guazi 历史文档归档 | ✅ `goal-pipeline/references/archive/v1.3-guazi-bridge/` |
| `audit-skills.sh` | ✅ `goal-pipeline/scripts/audit-skills.sh`，接入 `run-all-gate-tests.sh` |
| guazi 本地 references | ✅ interview/platform/separation/index-lite + `guazi-flow-artifact-schema` |
| guazi runtime bundle | ✅ `guazi-install.sh` + `guazi-advance-stage.sh` + `guazi-env-bootstrap.sh` → `~/.guazi-flow/state/scripts/` |
| guazi 夹具全绿 | ✅ `guazi-flow-goal/fixtures/guazi-gate/run-all-gate-tests.sh` exit 0（含 Tier A `audit-skills`） |
| guazi v1.4 参考文档 | ✅ `bridge-contract.md` / `guazi-flow-state-schema.md` / `guazi-flow-integration.md` 重写；v1.3 → `references/archive/v1.3-bridge/` |
| guazi 参考卫生 | ✅ `index-lite-protocol` / `task-tier-matrix` / `pipeline-doctor` / `failure-code-dictionary` / `plan-before-code` 等指向 `guazi-gate-stage.sh` + `GUAZI_STATE_HOME` |
| v1.3 桥接归档 | ✅ `goal-pipeline-stop-hook` 等 → `references/archive/v1.3-bridge/scripts/`；`test-gf-native-driver` / `test-goal-pipeline-kernel` → `fixtures/guazi-gate/archive/` |
| 夹具路径卫生 | ✅ guazi-gate 主套件统一 `GUAZI_SCRIPTS`；kernel/driver 段在无 bundle 时 SKIP |
| guazi gate-lib fork | ✅ `guazi-flow-goal/scripts/gate-lib/*.sh` 自 `9910d79` 恢复（去除 B3 contract enrich） |

## 验收

```bash
# goal 默认套件（含 Tier A audit-skills）
cd goal-pipeline/scripts/fixtures/goal-gate
GOAL_GATE_COMPAT_WARN=0 bash run-all-gate-tests.sh
# exit 0

# guazi 夹具套件
rm -rf .cache/guazi-fixture-runtime
cd guazi-flow-goal/fixtures/guazi-gate && bash run-all-gate-tests.sh
# exit 0

# 单独 skill 审计
bash goal-pipeline/scripts/audit-skills.sh --tier a
# exit 0

# goal 生产路径零 guazi（不含 fixtures / references / archive）
rg -l 'guazi' goal-pipeline --glob '!fixtures/**' --glob '!references/**' || true

# review-kernel 安装
bash shared/review-kernel/install.sh
test -x ~/.goal-services/review-kernel/bin/run-review-chain.sh

# guazi 安装
bash guazi-flow-goal/scripts/guazi-install.sh
test -x ~/.guazi-flow/state/scripts/guazi-gate-stage.sh
```

## 仍属仓外 / 后续

- 业务仓迁移按 [optimization-spec-outline-v1.4.md](research/optimization-spec-outline-v1.4.md) Part V
- full CI 接入各仓 pipeline（#75 §6 标注为 P2+）

## 与 v1.3 关系

v1.4 **废止** adapter 内嵌模型；goal 默认路径与 guazi 编排 **零交叉依赖**，仅 **review-kernel** 公共服务共用。
