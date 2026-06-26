# 审核通道自动配置

审核模型不可用时，Agent 主动帮用户配置：

## 路径 A（Ollama 全自动，零手动）

- 检测: RAM ≥ 8GB + macOS/Linux
- Agent: `brew install ollama && ollama pull llama3.2:3b`（或 qwen2.5:7b 如果 ≥16GB）
- 用户仅需回答 "Y"

## 路径 B（Gemini 半自动，30秒）

- Agent 打开 https://aistudio.google.com/apikey
- 创建 `~/.goal-state/key-pending`
- 用户终端执行: `echo 'key' > ~/.goal-state/key-pending`
- key 永不在 chat 中出现
- Agent 验证 → 写入 config.json → 删除临时文件

## 路径 C（人工审核）

A/B 都不可用时的逃生通道。

## 用户自定义审核模型

用户可通过 `~/.goal-state/config.json` 显式指定审核模型，覆盖所有自动选择。详见 `separation-strategies.md` 的"用户自定义审核模型"章节。
