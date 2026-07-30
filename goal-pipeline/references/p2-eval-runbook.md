# P2 Eval Run Command (v3 §8.5 #2, §10.2 D9–D10)

> Run the 4-case eval suite × 2 consecutive rounds. Pass_rate ≥95% in both rounds → flip XS/S default to single.

## Prerequisites

- `skill-up` CLI installed (see `~/.claude/skills/skill-upper/SKILL.md`)
- Agent engine credentials configured (Claude Code / Codex / etc.)
- Eval cases registered in `goal-pipeline/evals/eval.yaml`

## Run (2 consecutive rounds)

> `--iteration 1` = 单轮 8 case；`--iteration 0` = 自动追加到下一个 `iteration-<N>` 目录。  
> **不要**用 `--iteration 2` 表示「第 2 轮」——那会一次跑 2 轮。

```bash
cd goal-pipeline

# Round 1（产物 → goal-pipeline-workspace/iteration-<N>/）
skill-up run evals/eval.yaml --iteration 1 --output-dir ../goal-pipeline-workspace
R1_DIR=$(ls -d ../goal-pipeline-workspace/iteration-* | sort -V | tail -1)
PASS_R1=$(python3 -c "
import json, glob
reports = sorted(glob.glob('$R1_DIR/**/grading.json', recursive=True))
passed = sum(1 for p in reports if json.load(open(p)).get('summary',{}).get('failed',1)==0)
print(passed / len(reports) if reports else 0)
")

# Round 2
skill-up run evals/eval.yaml --iteration 1 --output-dir ../goal-pipeline-workspace
R2_DIR=$(ls -d ../goal-pipeline-workspace/iteration-* | sort -V | tail -1)
PASS_R2=$(python3 -c "
import json, glob
reports = sorted(glob.glob('$R2_DIR/**/grading.json', recursive=True))
passed = sum(1 for p in reports if json.load(open(p)).get('summary',{}).get('failed',1)==0)
print(passed / len(reports) if reports else 0)
")

# Gate: both rounds ≥95%
python3 -c "
r1, r2 = float('$PASS_R1'), float('$PASS_R2')
assert r1 >= 0.95 and r2 >= 0.95, f'eval failed: r1={r1} r2={r2}'
print(f'eval passed: r1={r1} r2={r2}')
"
```

## Eval cases (9)

完整列表见 `goal-pipeline/evals/eval.yaml`。核心 4 项 + 契约语义：

| Case | File | Validates |
|------|------|-----------|
| `index-lite-plan-gate` | `evals/cases/index-lite-plan-gate.yaml` | §8.1 XS/S lite index but gate not skipped |
| `xs-review-single-track` | `evals/cases/xs-review-single-track.yaml` | §8.2 single-track no guazi-flow-review lazy-load |
| `review-stagnant-blocked` | `evals/cases/review-stagnant-blocked.yaml` | §8.3 info_gain 熔断 → blocked_stagnant |
| `no-skip-plan-gate` | `evals/cases/no-skip-plan-gate.yaml` | (existing) plan gate not skipped |
| `contract-semantic-gates` | `evals/cases/contract-semantic-gates.yaml` | PQ-10/IQ-10 不得为赶进度绕过 |

## After eval passes — flip XS/S default to single

```bash
# Set the default-flip env (persist in shell profile or CI env)
export GOAL_REVIEW_SINGLE_DEFAULT=1
# Verify
python3 goal-pipeline/scripts/review_track.py --state-file <state-with-task_tier=XS> --format json
# → {"track": "single", "reason": "auto_xs_s", "task_tier": "XS"}
```

## L0 A/B Jaccard (deterministic, runs without LLM)

```bash
bash goal-pipeline/scripts/fixtures/guazi-flow-gate/test-review-ab-jaccard.sh
# → Jaccard >= 0.95, no new blockers
```

## Contract semantic gates (deterministic, no LLM)

```bash
bash goal-pipeline/scripts/fixtures/guazi-flow-gate/test-contract-gate.sh
# PQ-10 negative + IQ-10 positive/negative on synthetic fixtures
```

## Rollback

If review_gap escape rate >5% within 30 days (§8.5 #2 L2):

```bash
unset GOAL_REVIEW_SINGLE_DEFAULT   # revert to dual default
# or per-task: GOAL_REVIEW_TRACK=dual
```
