# Kernel 迁移兼容窗

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
