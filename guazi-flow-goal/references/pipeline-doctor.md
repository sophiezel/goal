# Pipeline Doctor（guazi v1.4）

guazi 独立栈无 `goal-pipeline-doctor.sh`。等价检查：

```bash
# 安装与 gate 入口
bash guazi-flow-goal/scripts/guazi-install.sh
test -x "$GUAZI_STATE_HOME/scripts/guazi-gate-stage.sh"
test -x "$GUAZI_STATE_HOME/scripts/guazi-advance-stage.sh"

# review-kernel
bash shared/review-kernel/install.sh
test -x "$REVIEW_KERNEL_HOME/bin/run-review-chain.sh"
```

业务仓内可用 `guazi-flow-doctor`（若 marketplace 已装）做 profile / 环境诊断。  
goal 侧 doctor：`goal-pipeline/scripts/goal-pipeline-doctor.sh`（**只读参考**，非 guazi 运行时依赖）。
