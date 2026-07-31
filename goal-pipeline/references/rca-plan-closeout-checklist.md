# RCA 计划收尾清单（最小 PR）

> 对应 goal 仓 RCA 计划在**接线与运维**上的收尾项（计划正文见 `.cursor/plans/`，不在此仓提交）。
> 声明式契约门禁术语见 [`declarative-contract-gates.md`](declarative-contract-gates.md)。

## PR-1 编排接线（代码，本仓）

| # | 项 | 验收 |
|---|-----|------|
| 1.1 | `implement --post`：存在 `handoff/integration-manifest.json` 时跑 `integration-contract-check.sh` | `grep integration-contract-check gate-lib/implement.sh`；fixture `test-implement-integration-wired.sh` |
| 1.2 | 通过后写 `evidence/integration-barrier.json`（`passed: true`） | implement post 成功且 manifest 存在时文件存在 |
| 1.3 | `validate-pipeline-chain`：有 manifest 无 barrier 时 warn | 链校验输出含 `integration-barrier` |
| 1.4 | 进化轨 `goal-implement/SKILL.md` 写明 post gate 含 IQ-10 + 可选 integration | 文档与兼容轨一致 |

**不纳入本 PR（避免范围膨胀）**

- `GOAL_CROSS_VAL_STRICT` / V# cross_val 改 block（需产品拍板 strict 默认）
- `state.multi_goal[]` 自动写 state 字段（Phase1 仍靠 Agent + 文档）
- 修改 `~/.agents/skills/guazi-flow-*`

## PR-2 本机 kernel 同步（运维）

```bash
cd /path/to/goal
bash install.sh --deploy-only
# 或你们文档中的 sync-install-repo.sh --deploy-only
```

| 验收 | 命令 |
|------|------|
| 脚本已部署 | `ls ~/.goal-pipeline/state/scripts/contract-conformance-check.py` |
| doctor 无契约脚本缺失 | `python3 goal-pipeline/scripts/four_planes_doctor.py --format text` 中 `quality.contract_*` 为 ok |

## PR-3 确定性回归（CI / 本地）

```bash
bash goal-pipeline/scripts/fixtures/guazi-flow-gate/run-all-gate-tests.sh
# 或至少：
bash goal-pipeline/scripts/fixtures/guazi-flow-gate/test-contract-gate.sh
bash goal-pipeline/scripts/fixtures/guazi-flow-gate/test-plan-quality-gate.sh
```

## PR-4 LLM eval（可选，发版前）

```bash
cd goal-pipeline
skill-up run evals/eval.yaml --iteration 1 --output-dir ../goal-pipeline-workspace
```

见 [`p2-eval-runbook.md`](p2-eval-runbook.md)。**不阻塞** PR-1 合并；发版或改 SKILL 话术时跑。

## PR-5 文档（已合入可勾选）

- [x] [`declarative-contract-gates.md`](declarative-contract-gates.md)
- [x] README / `dual-track-contract` / `guazi-flow-integration` 引用
- [x] 本清单全部 PR 完成后，在 CHANGELOG 或 release note 写一行「声明式契约门禁 + integration manifest barrier」（见 [`docs/RELEASE-v1.0.3.md`](../../docs/RELEASE-v1.0.3.md)）

## 完成定义

1. PR-1 合并 + PR-3 绿  
2. 维护者本机 PR-2 执行一次  
3. PR-4 按团队节奏  
