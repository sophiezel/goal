# Pipeline Doctor

运行 `goal-pipeline-doctor.sh <project_root>` 检查：

- VERSION / gate_script_hash 漂移
- goal-stage-driver、recover、review-chain 脚本是否已部署
- hooks.json stop hook 与 loop_limit
- review channel 可用性
- active goal 的 stage driver 快照

详见 `docs/architecture/pipeline-orchestration.md`。
