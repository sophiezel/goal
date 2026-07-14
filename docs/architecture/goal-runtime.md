# Goal Runtime — 四平面工程化运行时

`guazi-flow-goal` 的目标态：宿主无关的 **Pipeline Kernel**，需求直出高质量代码。

## 五要素（不可裁）

| 要素 | 含义 |
|------|------|
| 北星 | 澄清→契约→实现→验证→独立审→收口→交付 |
| 四平面 | 控制 / 数据 / 质量 / 效率 — 缺一不可 |
| 收敛 | 旁路脚本并入平面；对外只留 Kernel + doctor |
| 协议 | 每回合 `kernel next` → 执行 FrozenWorkOrder → `kernel gate` |
| 0 漏出 | 声明缺陷类上漏出率趋近 0（见失败码字典） |

## 四平面

| 平面 | 职责 | 运行入口 |
|------|------|----------|
| **控制面** | 阶段机、冻结工单、能力边界 | `goal-pipeline-kernel` |
| **数据面** | handoff/state SSOT、HashPolicy | resolve + validate-state + refresh 规则 |
| **质量面** | UVO/AM/preflight/ChannelPolicy/Delivery | gate + review-chain + 失败码 |
| **效率面** | 去重验证、fail-fast、timing SLA | WO 约束 + timing/postmortem/benchmark |

详契约：[`goal-pipeline/references/failure-code-dictionary.md`](../../goal-pipeline/references/failure-code-dictionary.md)、[`four-planes-checklist.json`](../../goal-pipeline/references/four-planes-checklist.json)。

## Core vs Host

| 层级 | 保证 |
|------|------|
| **Core（必达）** | 走 Kernel 则阶段序语义成立；合入须过质量面/交付证据；doctor 可检四平面 |
| **Host（可选加强）** | 宿主 permission/adapter 按 WO.capability 拒 Write；`doctor` 报 `host_guard=on|off` |

**诚实边界**：Kernel **不**等于物理禁写磁盘。无视 `kernel next` 直接改 `src` 仍可能发生；交付闸与质量面拦截的是「合入/完赛」，不是 OS ACL。

## Agent 回合协议（唯一）

```text
goal-pipeline-kernel init   # 如无 state
goal-pipeline-kernel next   # → FrozenWorkOrder JSON
# 仅执行 WO.mandatory_commands / skill_to_load；禁止并列写代码 Todo
goal-pipeline-kernel gate --stage <s> --post
goal-pipeline-kernel next   # 下一阶段或 done
# 退出：goal-pipeline-kernel complete | gate --assert-complete
```

旧脚本（`goal-stage-driver.sh`、`gate-guazi-flow-stage.sh` 等）为 **Kernel 内部实现**，兼容期内仍可直接调用，doctor 告警优先改用 Kernel。

## 反过度设计（白名单）

禁止：

- 横向第 N 旁路 guard 作为独立产品叙事
- 平行重写稳定的 UVO/AM 内核（只允许归位/契约化）
- 宣称「无宿主仍无法 Write」
- 空目录树装作平面已落地（每平面须有 doctor 检查 + fixture）

允许：

- 薄 facade 包装现有门禁
- 失败码字典与四平面 checklist 产品化
- 可选 host adapter 消费同一 capability

## 分期

Wave 顺序交付四平面不变量；**分期 ≠ 砍平面**。

| Wave | 交付 |
|------|------|
| 0 | 本文件 + failure-codes + checklist |
| 1 | `goal-pipeline-kernel` + Turn Protocol |
| 2 | `data_plane_check` / validate-state / hash policy |
| 3 | `quality_plane_check` / 声明缺陷类 0 silent pass |
| 4 | `efficiency_plane_check` / timing+benchmark |
| 5 | `migration-compat.md` + adapters + 外场度量模板 |

过程验收：`four_planes_doctor.py` 与 `fixtures/.../test-goal-pipeline-kernel.sh`。
