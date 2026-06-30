---
stage: review
result: pass
git_head: "abc123"
review_subject_hash: "deadbeef"
issues_gf_count: 0
merged_result: not_pass---
## 审查范围
test
## 发现项
none
## Goal Pipeline Review

_merged at 2026-06-30T12:11:12Z_

**goal_result**: not_pass
**merged_result**: not_pass
**action**: fix_and_rerun_review

### issues_goal

| ID | Severity | Summary | Root cause |
|----|----------|---------|------------|
| CHK-SCOPE | blocker | verify-review scope failed | implement_error |
| CHK-SECRET | blocker | verify-review secret failed | implement_error |
