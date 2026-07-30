# Issue Board 增强草案（v3 §8.3 / W0）

> **状态**：草案（P0 产出）。PR4 落地时实现 `format-gate-issues.sh` 增强 + `show_review_issue_board` 展示 stagnant。

## 1. 目标

`show_review_issue_board` 当前只展示 `issues[]` 表格。需增强为：

- 展示 `action` 字段（`blocked_stagnant` / `fix_and_rerun_review` / `proceed_complete` 等）
- 展示 `info_gain` / `stagnant_rounds` / `stagnant_blocked`
- 当 `stagnant_blocked=true` 时，输出 A/B/C 选项提示

## 2. 改动范围（PR4）

### `format-gate-issues.sh`

```diff
+ # 读取 fix-input 顶层字段（非仅 issues[]）
+ fix_doc = json.load(open(fix_input))
+ action = fix_doc.get("action", "")
+ info_gain = fix_doc.get("info_gain")
+ stagnant_rounds = fix_doc.get("stagnant_rounds", 0)
+ stagnant_blocked = fix_doc.get("stagnant_blocked", False)
+
+ # 在 issues 表格后追加
+ if action:
+     print(f"  action: {action}")
+ if info_gain is not None:
+     print(f"  info_gain: {info_gain} (threshold: {fix_doc.get('info_gain_threshold', 0.10)})")
+ if stagnant_rounds:
+     print(f"  stagnant_rounds: {stagnant_rounds}")
+ if stagnant_blocked:
+     print("  ⚠ 熔断: info_gain < threshold 连续 2 轮 → blocked_stagnant")
+     print("  选项: (A) mini-replan  (B) 人工 sign-off  (C) abort")
```

### `show_review_issue_board()`（gate-guazi-flow-stage.sh）

无需改动——已调用 `format-gate-issues.sh --fix-input`，增强自动透传。

## 3. 验收

- `test-merge-review-stagnant.sh` 产出的 fix-input 被 `format-gate-issues.sh` 渲染时含 `blocked_stagnant` + `info_gain` 行
- 现有 `review-fix-input-good` / `review-fix-input-not-pass` fixtures 渲染不回归（无 stagnant 字段时不输出额外行）
