# Guazi Flow State Schema（v1.4）

本文件定义 **guazi-flow-goal 独立栈** 的 `state.json` 字段、目录布局与写入边界。  
**不**以 `goal-pipeline/references/goal-state-schema.md` 为主路径；guazi 状态存放在 `GUAZI_STATE_HOME`。

**相关：** `bridge-contract.md`、`guazi-flow-integration.md`、`references/artifact-tier-policy.md`

## 目录布局

```
~/.guazi-flow/                                    ← GUAZI_HOME（默认）
├── state/                                        ← GUAZI_STATE_HOME
│   ├── guazi-install-meta.env                    ← 安装时写入 GUAZI_PIPELINE_REPO
│   ├── projects/<pid>/<branch>/<task>/
│   │   ├── state.json
│   │   └── .lock
│   ├── scripts/                                  ← guazi-install 部署（gate、advance、PQ/IQ…）
│   ├── kernel/                                   ← review kernel 副本 + guazi merge.py overlay
│   ├── references/                               ← guazi-flow-artifact-schema、profiles、本文档等
│   ├── schemas/
│   └── archive/

<project>/                                        ← 用户业务仓
├── .guazi-flow/config.local.json                 ← JIRA/FIGMA token（guazi 专用，不含 Tier-R）
└── docs/guazi-flow/<task>/                       ← Tier-G 任务根（默认 repo_task_dir）
    ├── index.md
    ├── evidence/review.md
    ├── evidence/complete.md
    └── units/*.md

<runtime_root>/                                   ← Tier-R（split 模式，通常不进 git）
├── handoff/*.json
└── evidence/review-unified.json, review-run.json, *-gate-fix-input.json, …
```

安装：`bash guazi-flow-goal/scripts/guazi-install.sh`（或 `GUAZI_INSTALL_TARGET` 指向 fixture cache）。

## state.json 示例

路径：`$GUAZI_STATE_HOME/projects/<pid>/<branch>/<task>/state.json`

```json
{
  "status": "active",
  "current_stage": "implement",
  "project_root": "/abs/path/to/project",
  "guazi_flow_task": "docs/guazi-flow/<task>",
  "guazi_flow_profile": "h5",
  "profile_detail": "react",
  "task_tier": "M",
  "task_tier_meta": {
    "signals": ["new_page_dirs:1"],
    "parallel_strategy": "subagent_dag_3_4"
  },
  "guazi_flow_stages": {
    "plan": {
      "used": true,
      "skill": "guazi-flow-plan",
      "gate": {
        "script": "guazi-gate-stage.sh",
        "version": 1,
        "passed_at": "2026-01-01T00:00:00Z",
        "post_exit_code": 0,
        "handoff_hash": "abc123def4567890"
      }
    },
    "implement": {
      "used": true,
      "skill": "guazi-flow-implement",
      "gate": {
        "script": "guazi-gate-stage.sh",
        "version": 1,
        "passed_at": "2026-01-01T00:00:00Z",
        "post_exit_code": 0
      }
    }
  },
  "artifact_layout": {
    "mode": "split",
    "repo_task_dir": "docs/guazi-flow/<task>",
    "runtime_root": "/Users/you/.guazi-flow/state/projects/<pid>/<branch>/<task>/artifacts"
  },
  "review_config": {
    "track": "single"
  }
}
```

### 字段说明

| 字段 | 写入方 | 说明 |
|------|--------|------|
| `project_root` | Phase 1 / init | 业务仓绝对路径；advance、gate `--project-root` 解析用 |
| `guazi_flow_task` | Phase 1 | 相对 `project_root` 的任务目录，默认 `docs/guazi-flow/<task>` |
| `guazi_flow_profile` / `profile_detail` | Phase 1 / plan | 技术栈 profile（h5、service、rn…） |
| `guazi_flow_stages` | gate `--post`、advance | 各阶段 gate 通过记录；**`guazi-advance-stage.sh` 读 `guazi_flow_stages` 或 `pipeline_stages`** |
| `artifact_layout` | Phase 1 | `split`（推荐）或 `repo_full`；见 `artifact-tier-policy.md` |
| `task_tier` / `task_tier_meta` | plan post（`task_tier.py`） | XS–XL；见 `task-tier-matrix.md` |
| `review_config.track` | plan post（`review_track.py`） | `single` \| `dual` |

### guazi_flow_stages.*.gate

仅 **gate `--post` 成功** 后由 gate 脚本写入 `passed_at` / `post_exit_code` / `handoff_hash`。Agent **禁止**手改 `handoff/*.json` 或伪造 `passed_at`。

```json
"gate": {
  "script": "guazi-gate-stage.sh",
  "version": 1,
  "passed_at": "<ISO8601Z>",
  "post_exit_code": 0,
  "handoff_hash": "<sha256[:16] of handoff/<stage>.json>"
}
```

## 路径解析

```bash
eval "$(python3 "$GUAZI_STATE_HOME/scripts/resolve-artifact-paths.py" \
  --task-dir "$TASK" --project-root "$REPO" --state-file "$STATE" --format shell)"
# → REPO_TASK_DIR, HANDOFF_DIR, GOAL_EVIDENCE_DIR, …
```

`GOAL_*` 环境变量名在 resolver 输出中仍为历史兼容名，物理路径指向 guazi runtime。

## 写入边界

- **Tier-G** 仅写入 `docs/guazi-flow/<task>/` 下契约可见文件
- **Tier-R** 写入 `artifact_layout.runtime_root`（handoff、review annex、fix-input）
- **禁止** 将 Tier-R 写入 `<project>/.guazi-flow/`
- **禁止** 将 guazi 产物写入 `~/.goal-pipeline/`
- 扩展字段 **追加** 到 state.json；勿用 guazi 字段覆盖无关第三方键

## 与 goal-pipeline 的关系（v1.4）

- guazi **不共享** `~/.goal-pipeline/state` 安装目录
- 运行时 shim（`goal-env-bootstrap-compat.sh`）仅让遗留脚本解析 `GOAL_STATE_HOME` → `GUAZI_STATE_HOME`
- 需要对比 goal 通用 schema 时，只读参考 `goal-pipeline/references/goal-state-schema.md`，**不以之为 guazi 主路径**

## v1.4 变更摘要

| v1.3 | v1.4 |
|------|------|
| `~/.goal-pipeline/state` | `~/.guazi-flow/state` |
| `gate-guazi-flow-stage.sh` | `guazi-gate-stage.sh` |
| `goal-advance-stage.sh` | `guazi-advance-stage.sh` |
| `guazi_flow_contract_enriched` | **删除**（无 B3 enrich 脚本） |
| goal 降级 / bridge 层 | **删除** — 独立管线 |

历史 v1.3 正文见 `references/archive/v1.3-bridge/guazi-flow-state-schema.v1.3.md`（若已归档）。
