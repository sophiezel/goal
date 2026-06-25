# Interview Protocol

## 设计原则

**用户不需要手写标准 Goal Prompt。** goal-pipeline 通过渐进式结构化访谈自动生成。

## Goal Schema（管线推进所需的最小信息集）

| 字段 | 优先级 | 来源 | 缺失时行为 |
|------|:--:|------|------|
| objective | P0 | 用户输入 | 无法创建 goal |
| profile | P0 | 自动检测 | 自动检测，用户确认 |
| scope | P1 | git status / 项目结构推断 | 推断后确认，不确定则追问 |
| acceptance_criteria | P1 | 追问（提供选项） | 可先推进 plan，plan 阶段细化 |
| constraints | P1 | `AGENTS.md` / profile 推断 | 自动推断，用户可追加 |
| verification | P1 | `package.json` scripts.test 推断 | 自动推断，用户可调整 |
| budget | P2 | 默认值 | `max_turns=50` |

## 访谈流程（三步收敛）

### Step 1: 自由输入

用户可以说任何内容，哪怕只有三个字：
- "加个登录"
- "修 bug"
- "重构 auth 模块"
- "优化首页加载速度"

解析关键词: 动作(add/fix/refactor/optimize) + 对象(模块/功能) + 期望结果。

### Step 2: 自动推断

在追问之前，尽可能从环境推断:

```
1. profile 推断:
   → 读 package.json / go.mod / 项目结构 → 推断技术栈

2. scope 推断:
   ├─ git diff → 已修改文件列表
   ├─ 关键词匹配 → grep 找相关文件
   └─ 默认 → 整个项目

3. constraints 推断:
   ├─ 读 AGENTS.md / CLAUDE.md / .cursorrules
   └─ 读项目配置文件默认约束

4. verification 推断:
   ├─ 读 package.json scripts.test → npm test
   ├─ H5 → npm test + playwright
   ├─ Service → go test
   └─ 无 → 手动验证

5. acceptance_criteria 推断 (最弱):
   └─ 从用户原始输入提取关键词
   └─ 提取不到 → 追问
```

### Step 3: 定向追问

只追问 Step 2 推断失败 + P0/P1 缺失的字段。每个问题给选项，用户选字母即可。

**最多 3-5 个问题。** 不过度访谈。

**追问模板示例**：

```
🔍 让我确认几个关键点:

Q1: <缺失字段1>? 
    [A] <默认选项1>   [B] <选项2>   [C] 自定义

Q2: <缺失字段2>?
    [A] <选项1>   [B] <选项2>

Q3: 验收标准? (如何判断目标已完成)
    [A] 测试全通过   [B] 功能可用   [C] review通过   [D] 全部

(按字母选择，如 "A, B, D")
```

## Goal 结构模板（统一中间表示）

访谈完成后，生成统一 Goal 结构：

```markdown
## Goal: <一句话目标>

### 目标描述
<完整描述>

### 验收标准
- [ ] <标准1>
- [ ] <标准2>

### 范围
- 涉及: <模块/文件列表>
- 禁止修改: <约束>

### 约束
- 来自项目规则: <规则>
- 来自技术栈: <profile>
- 用户指定: <用户约束>

### 验证方式
- 自动验证: <命令>
- 人工验证: <需确认方面>
```

## 访谈示例

```
用户: /goal-pipeline 加个登录

Agent:
  🔍 检测到: React + TypeScript 项目
  📋 让我确认几个关键点:

  Q1: 登录方式?
      [A] 用户名+密码   [B] OAuth (Google/GitHub)   [C] 手机验证码

  Q2: 是否需要注册功能?
      [A] 仅登录   [B] 含注册

  Q3: 完成标准?
      [A] 测试全通过   [B] 功能可正常使用   [C] 以上全部

> A, A, C

Agent:
  ✅ Goal 已生成: <task_dir>/
  📊 管线: plan → implement → review → complete
  🔍 审核: ollama/qwen2.5:7b (本地免费) | 通道探测中...
  
  确认开始执行? [Y/n]
```

## 用户确认

生成 Goal 后必须展示给用户确认。用户可以:
- 直接确认 (Y) → 进入 Phase 2 (Pipeline Execution)
- 编辑修改 → 用户修改后重新确认
- 重新讨论 → 回到 Step 1
- 放弃 → 退出
