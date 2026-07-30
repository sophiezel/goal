# Kernel 迁移兼容窗

## 安装布局（2.3+）

自 `goal_pipeline_version` **2.3.0-dual-pipeline-kernel** 起，`sync-install-repo.sh` / `install.sh` 除 `~/.goal-pipeline/state/scripts/` 外，还会部署：

| 路径 | 内容 |
|------|------|
| `~/.goal-pipeline/state/kernel/` | `goal-pipeline/kernel`（review merge、delivery metrics、gate_runtime 等） |
| `~/.goal-pipeline/state/references/` | 四平面与 eval 相关只读引用 |
| `~/.goal-pipeline/state/schemas/` | 可选；JSON schema 副本 |
| `~/.goal-pipeline/state/VERSION` | 含 `kernel_version`、`kernel_tree_hash` |

从 2.2 升级：执行一次 `sync-install-repo.sh --deploy-only` 或重跑 `install.sh`；若仅有旧 `scripts/` 而无 `kernel/`，complete / review merge 会失败。

## 目录布局（2.4+ / 3.0 安装通道）

| 变量 | 默认路径 |
|------|----------|
| `GOAL_HOME` | `~/.goal-pipeline` |
| `GOAL_PIPELINE_REPO` | `$GOAL_HOME/repository` |
| `GOAL_STATE_HOME` | `$GOAL_HOME/state` |

无旧版 `$HOME` 路径迁移；新装仅使用上表。`install.sh --uninstall --purge` 删除 `repository/` 与 `state/`（及空的 `GOAL_HOME`）。

自 **3.0** 起，安装/更新通过 **通道** 解析 Git 引用（见 [`release-channel.md`](./release-channel.md)）：

| 通道 | 含义 |
|------|------|
| `stable`（默认） | 最新非预发布 SemVer tag |
| `latest` | `origin/main` 顶端 |
| `pinned` | `--ref` 指定 tag 或 commit |

`config.json` → `install` 与 `~/.goal-pipeline/state/VERSION` 记录当前通道与解析结果。

## 状态

| 阶段 | 对外推荐 | 旧入口 |
|------|----------|--------|
| 当前（compat） | `goal-pipeline-kernel` | driver / gate / advance 仍可用 |
| deprecate 告警 | `four_planes_doctor` / `kernel next` 信封列出 `deprecated_direct_scripts` | 直调仍执行 |
| 未来 | 仅 Kernel | 旧脚本仅内部 |

## Agent / skill

- `guazi-flow-goal` / `goal-pipeline` SKILL 已改为 Kernel 协议。
- Stop hook 可继续调用 `gate --assert-complete`（内部）。

## 度量（Wave 5）

外场任务建议记录：

| 指标 | 来源 |
|------|------|
| 协议合规 | 是否始终 `kernel next` / 有无并列写码 Todo |
| 效率 | `evidence/pipeline-timing.json` UTC；对照 A4/B1 |
| 漏出 | failure-codes 声明类是否出现 silent pass |

模板：[`measure-field-template.json`](./measure-field-template.json)
