# Artifact Tier Policy（产物分层契约）

guazi-flow-goal 与 goal-pipeline 的**单一事实来源**：哪些产物进项目 git，哪些留在 `~/.goal-pipeline/state`。

## 分层

| 层级 | 名称 | 位置 | 进 git | 说明 |
|------|------|------|:------:|------|
| **Tier-G** | guazi-flow 契约产物 | `<project>/docs/guazi-flow/<task>/` | **是** | 与 guazi-flow-core 一致，随 MR 提交 |
| **Tier-R** | goal 运行时产物 | `~/.goal-pipeline/state/projects/<pid>/<branch>/<task>/artifacts/` | **否** | 编排、审核、修复循环；可跨 session 恢复 |
| **Tier-S** | goal 编排状态 | `~/.goal-pipeline/state/.../state.json` + `.lock` | **否** | 已有，不变 |

## Tier-G（repo，commit）

```
docs/guazi-flow/<task>/
├── index.md
├── units/**/*.md
└── evidence/
    ├── review.md          # guazi-flow-complete 硬门禁
    ├── complete.md        # guazi-flow 收口摘要
    ├── implement.md       # guazi-flow-implement 审计（如有）
    └── cwiki/**           # 需求/接口来源
```

## Tier-R（goal-state，不 commit）

```
~/.goal-pipeline/state/projects/<pid>/<branch>/<task>/artifacts/
├── handoff/
│   ├── plan.json
│   ├── implement.json
│   ├── smoke.json
│   ├── review-packet.json
│   ├── review.json
│   ├── merge-result.json
│   └── complete.json
└── evidence/
    ├── runtime-smoke.md
    ├── review-unified.json
    ├── review-run.json
    ├── review-fix-input.json
    ├── review-transcript.md
    └── *-gate-fix-input.json
```

`handoff/review-packet.json` 含完整 diff，体积大、可由 `assemble-review-packet.sh` 重建，**禁止**进 git。

## 布局模式

`state.json.artifact_layout.mode`：

| mode | 行为 |
|------|------|
| `split` | **新 goal 默认** — Tier-G 在 repo，Tier-R 在 goal-state |
| `repo_full` | 兼容旧行为 — 全部写在 `docs/guazi-flow/<task>/` |

环境变量覆盖（CI / 无 goal-state）：

- `GOAL_ARTIFACT_MODE=repo_full` — 强制全在 task_dir
- `GOAL_ARTIFACT_MODE=split` — 强制 split（需可解析 runtime_root）

## 路径解析

所有 goal 脚本通过 `resolve-artifact-paths.py` 解析路径，**禁止**硬编码 `task_dir/handoff`（split 模式下会错）。

```bash
eval "$(python3 ~/.goal-pipeline/state/scripts/resolve-artifact-paths.py \
  --task-dir docs/guazi-flow/<task> \
  --state-file ~/.goal-pipeline/state/projects/.../state.json \
  --format shell)"
# 导出: ARTIFACT_MODE REPO_TASK_DIR RUNTIME_ROOT HANDOFF_DIR REPO_EVIDENCE_DIR GOAL_EVIDENCE_DIR
```

## MR 提交清单

**应提交**：`index.md`、Tier-G `evidence/*.md`（review/complete/implement）、`evidence/cwiki/**`、业务代码。

**不应提交**：`handoff/`、Tier-R `evidence/*`（见 `guazi-flow-goal/templates/docs-guazi-flow.gitignore`）。

## index.md 桥接

complete 阶段在 repo `index.md` §执行记录追加一行摘要，例如：

```
review: evidence/review.md pass | goal-runtime: ~/.goal-pipeline/state/.../artifacts (review-run d9451f6c, deepseek/deepseek-v4-flash)
```

MR 审查者无需打开 goal-state 即可看到审核结论。

## 写入边界

- goal **禁止**把 Tier-R 写入 `<project>/.guazi-flow/`
- guazi-flow-* skill **不修改**；路径分流由 goal 脚本完成
- `merge-review-issues` 的 merged 结果仍写 **repo** `evidence/review.md`

## 迁移与清理

已有 task 目录含 `handoff/` 时：

```bash
goal-pipeline-doctor.sh --migrate-artifacts --task-dir docs/guazi-flow/<task> --state-file ~/.goal-pipeline/state/.../state.json
```

split 模式下每次 `resolve-artifact-paths.py --ensure-state` 或 `gate --post` 成功后会 **purge** repo 中误写的 Tier-R（`handoff/`、review annex JSON 等），Tier-G 不受影响。防泄漏靠写入路径 + purge + migrate，**不在** repo 内生成 `docs/guazi-flow/.gitignore`。

手动清理：

```bash
goal-pipeline-doctor.sh --purge-repo-tier-r --task-dir docs/guazi-flow/<task> --state-file ~/.goal-pipeline/state/.../state.json
```
