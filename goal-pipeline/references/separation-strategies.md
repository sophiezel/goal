# Separation Strategies

## 核心原则

**执行者 ≠ 审核者。** 实现代码的模型不得审核自己的代码。

独立性等级:跨 provider > 同 provider 不同规格 > 同 model(不允许)。

---

## 候选通道收集(并行探测,不短路)

所有来源同时探测,收集到一个候选池,然后统一排序。不因某个来源先返回就停止。

### 候选来源

| 来源 | 探测方式 | 排序权重 |
|------|---------|:--:|
| **全局配置** | 读取 `~/.goal-state/config.json` 的 `api_keys` 字段 | 最高(用户显式配置)|
| **标准环境变量** | `$OPENAI_API_KEY` / `$ANTHROPIC_API_KEY` / `$GEMINI_API_KEY` / `$GROQ_API_KEY` / `$DEEPSEEK_API_KEY` | 正常 |
| **Agent 自省** | agent 回答 provider + model | 正常 |
| **Ollama 本地** | `ollama list` | 正常 |
| **免费 API** | 需用户注册(引导阶段) | - |

所有来源并行探测,收集到候选池后按独立性排序,不使用层级短路。

### 候选池模型示例

```json
{
  "execution": {"provider": "deepseek", "model": "deepseek-v4-pro"},
  "candidates": [
    {
      "provider": "deepseek",
      "model": "deepseek-v4-flash",
      "source": "agent_introspection",
      "same_provider_as_exec": true,
      "available": true
    },
    {
      "provider": "openai",
      "model": "gpt-4o-mini",
      "source": "env_var",
      "same_provider_as_exec": false,
      "available": true
    },
    {
      "provider": "ollama",
      "model": "qwen2.5:7b",
      "source": "ollama_list",
      "same_provider_as_exec": false,
      "available": false
    }
  ]
}
```

---

## 排序规则(按独立性,非按来源)

```
1. 过滤: 排除 available=false 的候选
        排除 model = 执行 model 的候选(同模型自审)

2. 分组:
   Group A: same_provider_as_exec = false(跨 provider)
   Group B: same_provider_as_exec = true(同 provider,不同 model)

3. 排序:
   Group A 排在前(跨 provider 更独立)
   Group A 内部: 按成本排序(gpt-4o-mini > gemini-flash > groq > 本地)
   Group B 内部: 同上

4. 选取: 排序后第一位即为最优
```

### 为什么跨 provider 优先

| 维度 | 跨 provider | 同 provider |
|------|:--:|:--:|
| 自评偏差 | ✅ | ✅ |
| 共享训练盲点 | ✅ 消除 | ⚠️ 可能存在 |
| API 单点故障 | ✅ 互为备份 | ❌ 同时不可用 |
| 成本 | gpt-4o-mini $0.15/1M | haiku $0.80/1M |
| 用户操作 | 已有 key → 零操作 | 已有 key → 零操作 |

跨 provider 在独立性和韧性上全面优于同 provider,且不增加用户成本。同 provider 是备选,不是首选。

### 执行 Provider → Flash 模型映射(用于同 provider 候选构建)

| 执行 Provider | Flash 模型 |
|:--|------|
| Anthropic | claude-haiku-4-5 |
| OpenAI | gpt-4o-mini |
| DeepSeek | deepseek-v4-flash |
| Google/Gemini | gemini-2.0-flash |
| Groq | llama-3.3-70b-versatile |
| Ollama 本地 | 同模型列表中最小的模型 |

---

## 选择流程

```
静默预检(/goal-pipeline 入口) / Step 0 权威选择 / review 失败重试:

1. 检查用户显式配置 review_model → 使用,跳过自动选择

2. 收集候选池(并行探测所有来源)
   ├─ Agent 自省: provider=X, model=Y, 能切换model→构造同provider候选
   ├─ 环境变量: 遍历5个标准变量,每个有效key构造一个候选
   ├─ Ollama: ollama list → 构造本地候选
   └─ 用户历史选择(review_channels.json)→ 引用但不重复探测

3. 过滤 + 排序
   ├─ 排除不可用、同model自审
   ├─ 跨provider候选排前
   └─ 同组内按成本排序

4. 选取结果
   ├─ 有候选 → 选定最优,写入 state.json.review_config
   │   └─ { model, provider, separation_confidence, source }
   │
   └─ 无候选 → 进入引导

5. 引导——Agent 主动配置审核通道（零手动目标）

   **Ollama 全自动路径**（用户只需同意，真正零手动）:
   - 检测: RAM ≥ 8GB + macOS/Linux
   - Agent: "我可自动安装 ollama + <model>(~XX GB下载)。确认? [Y/n]"
   - 用户 Y → Agent: brew install ollama && ollama pull <model>
   - 完全无人操作，永久零配置

   **Gemini 半自动路径**（30秒, key 永不在 chat 出现）:
   - Agent 打开 https://aistudio.google.com/apikey
   - 创建 ~/.goal-state/key-pending
   - 用户终端执行: echo 'key' > ~/.goal-state/key-pending
   - Agent 验证 API → 写入 config.json → 删除临时文件

   **人工审核**（逃生通道）: Ollama / Gemini 均不可用时

   决策顺序: RAM ≥ 8GB → 首推 Ollama 全自动; 否则 → Gemini 半自动; 都不可用 → 人工
```

---

## 分离置信度

| 置信度 | 条件 | 行为 |
|:--:|------|------|
| **high** | 审核模型 ≠ 执行模型,且不同 provider | 自动通过 |
| **medium** | 审核模型 ≠ 执行模型,同 provider 不同规格 | 自动通过 + 标注 |
| - | 审核模型 = 执行模型(任何情况)| **不允许** |

---

## 静默预检

`/goal-pipeline` 入口处,访谈开始前执行。职责:提前发现不可用,在投入用户时间之前告警。

若有候选 → 静默,继续访谈。用户全程无感知。

若无候选 → 告知并引导(此时尚未进入访谈,零沉没成本):

**API key 脱敏规则**:只写变量名和占位符 `"你的key"`,不写任何格式提示。必须告诉用户写到 `~/.goal-state/config.json` 这个文件,不可只说"设为环境变量"。严禁用户将 key 粘贴到 chat 中。

```
⚠️ Goal 需要独立审核,但当前环境无可用审核模型。

推荐配置(30 秒,免费,一次配置所有项目通用):

  注册 Gemini API key: https://aistudio.google.com/apikey
  获取后,打开 ~/.goal-state/config.json
  在 api_keys 中添加: "GEMINI_API_KEY": "你的key"
  → 该文件在 home 目录,不在 git 仓库中,不会泄露

  如已有 OpenAI / Anthropic / DeepSeek key,同样在 api_keys 中添加。

写入后回复 "已配置" → 自动继续,不需要重新 /goal-pipeline

⚠️ 不要把 key 粘贴到聊天中
───────────────────────────
其他选项:
[本地] brew install ollama && ollama pull qwen2.5:7b  (需 ≥X GB RAM)
[人工] 你来判定 review 结果
[放弃]
```

引导内容根据预检结果动态生成:推荐已注册但未设变量的 provider、检测 RAM 给出模型建议、网络不可达时隐藏 API 选项。

用户配置后回复"已配置" → 重新探测 → 命中 → 原地继续访谈。不需要重新 `/goal-pipeline`。

---

## 审核 Prompt 模板

```markdown
## 角色
你是独立代码审核者。你不是这段代码的实现者。
你的唯一职责:根据任务契约,客观评审候选 diff。

## 任务契约
{contract}

## 候选 Diff
```diff
{diff}
```

## 约束
- 允许修改的文件(write_set): {write_set}
- 项目规则: {constraints}
- 修改白名单(allowed_files): {allowed_files}
- 明确排除(out_of_scope): {out_of_scope}

## Evaluator Checklist
按以下维度逐项检查，每项给出 pass/fail/skip。P0 项 fail → result=not_pass；P1 项 fail → 生成 blocker issue：
1. [P0] 目标达成：候选 diff 是否真正解决了任务契约中的每个验收标准？
2. [P0] 范围合规：是否所有修改都在 Allowed Files 白名单内？是否有 Out of Scope 的改动？
3. [P1] 证据充分：是否运行了要求的验证命令？结论是否有 diff 内容支撑？
4. [P1] 副作用：是否新增依赖、配置、权限或数据库迁移？
5. [P1] 完整性：是否有未验证的路径被标记为已完成？
6. [P0] 安全性：是否泄漏 secret、token 或敏感信息？

## 输出格式
只输出一个 JSON object,不要额外文字。每条 issue 描述不超过 80 字。
```json
{
  "result": "pass | not_pass",
  "issues": [
    {
      "severity": "blocker | warning | uncertain",
      "file": "src/auth/login.ts",
      "line_range": "42-58",
      "description": "简短描述（不超过 80 字）",
      "evidence": "diff 中该函数缺少 error boundary，第 45 行直接 throw",
      "suggestion": "简短建议"
    }
  ],
  "summary": "一句话总结",
  "checklist": {
    "goal_achieved": "pass | fail",
    "scope_compliant": "pass | fail",
    "evidence_sufficient": "pass | fail",
    "side_effects": "pass | fail | skip",
    "completeness": "pass | fail",
    "security": "pass | fail | skip"
  }
}
```

注意：`file` 和 `line_range` 为可选字段。当 issue 不针对特定代码位置时（如"缺少整体测试"），可省略。
```

## 审核 Prompt 构建规则

1. `{contract}`: 从 `index.md` 验收标准 + `unit.md` 契约提取
2. `{diff}`: `git diff -U5 HEAD` 完整输出(5 行上下文 + 行号标注, 若 >8KB 截断为前 8KB + 文件列表)
3. `{write_set}`: 从 `index.md` 或 `unit.md` 提取
4. `{constraints}`: 从 profile + 项目规则文件提取
5. `{allowed_files}`: 纯 goal-pipeline 模式从 Goal 结构提取；guazi-flow-goal 模式从 `index.md` 的 `write_set` 下 `### allowed_patterns` 子 section 提取
6. `{out_of_scope}`: 纯 goal-pipeline 模式从 Goal 结构提取；guazi-flow-goal 模式从 `index.md` 的 `scope` 下 `### exclusions` 子 section 提取

## JSON 解析与重试

```python
def parse_review_response(content):
    try: return json.loads(content)
    except: pass
    match = re.search(r'```json\s*\n(.*?)\n```', content, re.DOTALL)
    if match:
        try: return json.loads(match.group(1))
        except: pass
    return None  # triggers review_undetermined
```

## Checklist 字段容错

旧模型或部分模型可能不返回 `checklist` 字段。解析后进行归一化：

```python
def normalize_review(review):
    if not review.get("checklist"):
        review["checklist"] = {}  # 空 checklist，不阻断分流
    return review
```

## 用户自定义审核模型

`~/.goal-state/config.json` 中显式指定,覆盖所有自动选择:

```json
{
  "review_model": "openai/gpt-4o-mini"
}
```
