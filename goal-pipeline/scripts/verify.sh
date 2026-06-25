#!/bin/bash
# verify.sh - guazi-flow-goal 管线状态检查
# 最小依赖: bash + git
# 可选增强: jq (用于 JSON 解析), python3 (jq 降级)

set -euo pipefail

TASK_DIR="${1:-}"
FORMAT="${2:-text}"  # text | json

# === 工具检测 ===
has_jq() { command -v jq &>/dev/null; }
has_python() { command -v python3 &>/dev/null; }
has_git() { command -v git &>/dev/null; }

# === JSON 解析 (python3 优先, 纯bash grep 降级) ===
parse_json_field() {
  # $1: json string, $2: key
  local val
  if has_python; then
    val=$(echo "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$2',''))" 2>/dev/null || echo "")
  else
    # Pure bash: grep for "key":"value" or "key": value
    val=$(echo "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//')
    [ -z "$val" ] && val=$(echo "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*[^,}]*" | head -1 | sed 's/.*:[[:space:]]*//')
  fi
  echo "$val"
}
parse_yaml_frontmatter() {
  local file="$1"
  local key="$2"
  
  # extract frontmatter lines (between first pair of ---)
  local fm_text
  fm_text=$(sed -n '/^---$/,/^---$/p' "$file" | sed '1d;$d')
  
  # Handle nested keys like "flow.current_stage"
  local top_key="${key%%.*}"
  local sub_key="${key#*.}"
  
  if [ "$top_key" = "$sub_key" ]; then
    # Simple key (no nesting): use grep
    echo "$fm_text" | grep "^${key}:" | head -1 | sed "s/^${key}: *//"
  else
    # Nested key: extract the top-level block first, then sub-key
    local in_block=false
    local indent_level=""
    while IFS= read -r line; do
      if [ "$in_block" = false ]; then
        if echo "$line" | grep -q "^${top_key}:"; then
          in_block=true
        fi
      else
        # Check if still in block (indented or empty)
        if [ -z "$line" ] || echo "$line" | grep -q "^  "; then
          if echo "$line" | grep -q "^  ${sub_key}:"; then
            echo "$line" | sed "s/^  ${sub_key}: *//"
            return 0
          fi
        else
          # Left the indented block
          return 0
        fi
      fi
    done <<< "$fm_text"
  fi
}

# === Git HEAD ===
get_git_head() {
  if has_git; then
    git -C "${GIT_ROOT:-.}" rev-parse HEAD 2>/dev/null | cut -c1-16 || echo "unknown"
  else
    echo "no-git"
  fi
}

# === 主逻辑 ===
main() {
  local task_dir="${TASK_DIR:-docs/guazi-flow/}"
  local root="${GIT_ROOT:-.}"
  
  # 查找任务目录
  if [ -z "$TASK_DIR" ]; then
    task_dir=$(find "$root/docs/guazi-flow" -name "index.md" -maxdepth 3 2>/dev/null | head -1 | xargs dirname)
    if [ -z "$task_dir" ]; then
      echo '{"error":"no task found","next_action":"run guazi-flow-plan first"}'
      return 1
    fi
  fi
  
  local index_file="$root/$task_dir/index.md"
  
  if [ ! -f "$index_file" ]; then
    echo "{\"error\":\"index.md not found at $index_file\",\"next_action\":\"run guazi-flow-plan\"}"
    return 1
  fi
  
  # 读取 current_stage
  local current_stage=""
  current_stage=$(parse_yaml_frontmatter "$index_file" "flow.current_stage" 2>/dev/null || echo "")
  if [ -z "$current_stage" ]; then
    current_stage=$(parse_yaml_frontmatter "$index_file" "current_stage" 2>/dev/null || echo "unknown")
  fi
  
  local git_head
  git_head=$(get_git_head)
  
  # 检查证据文件
  check_evidence() {
    local stage="$1"
    local evidence_file="$root/$task_dir/evidence/${stage}.md"
    if [ -f "$evidence_file" ]; then
      local result=""
      result=$(parse_yaml_frontmatter "$evidence_file" "result" 2>/dev/null || echo "unknown")
      local ev_git_head=""
      ev_git_head=$(parse_yaml_frontmatter "$evidence_file" "git_head" 2>/dev/null || echo "unknown")
      local fresh="unknown"
      if [ "$ev_git_head" = "$git_head" ]; then
        fresh="fresh"
      else
        fresh="stale"
      fi
      echo "{\"file\":\"$evidence_file\",\"result\":\"$result\",\"fresh\":\"$fresh\"}"
    else
      echo "{\"file\":\"$evidence_file\",\"result\":\"missing\"}"
    fi
  }
  
  local plan_evidence impl_evidence review_evidence complete_evidence
  plan_evidence=$(check_evidence "plan")
  impl_evidence=$(check_evidence "implement")
  review_evidence=$(check_evidence "review")
  complete_evidence=$(check_evidence "complete")
  
  # 确定管线状态
  local pipeline_stages=("plan" "implement" "review" "complete")
  local stage_status=()
  local completion_pct=0
  local active_stage=""
  local next_action=""
  local completion_met="false"
  
  # 简化版本: 按阶段顺序检查
  local stage_idx=0
  for stage in "${pipeline_stages[@]}"; do
    local ev
    ev=$(check_evidence "$stage")
    local result
    result=$(parse_json_field "$ev" "result")
    [ -z "$result" ] && result="missing"
    local fresh
    fresh=$(parse_json_field "$ev" "fresh")
    [ -z "$fresh" ] && fresh="unknown"
    
    if [ "$result" = "pass" ] && [ "$fresh" = "fresh" ]; then
      stage_status+=("$stage:done")
      completion_pct=$(( (stage_idx + 1) * 25 ))
    elif [ "$result" = "not_pass" ]; then
      stage_status+=("$stage:failed")
      active_stage="$stage"
      next_action="fix issues in $stage stage and re-run"
      break
    elif [ "$result" = "pass" ] && [ "$fresh" = "stale" ]; then
      stage_status+=("$stage:stale")
      active_stage="$stage"
      next_action="re-run $stage stage (evidence stale)"
      break
    else
      stage_status+=("$stage:pending")
      if [ -z "$active_stage" ]; then
        active_stage="$stage"
        next_action="execute $stage stage"
      fi
      break
    fi
    stage_idx=$((stage_idx + 1))
  done
  
  # 检查是否全部完成
  if [ "$current_stage" = "complete" ] && [ "$(parse_json_field "$complete_evidence" "result")" = "pass" ]; then
    completion_met="true"
    active_stage="complete"
    next_action="goal achieved"
    completion_pct=100
  fi
  
  # 构建管线显示
  local pipeline_str=""
  for s in "${stage_status[@]}"; do
    local stage_name="${s%%:*}"
    local stage_state="${s##*:}"
    case "$stage_state" in
      done)   pipeline_str="${pipeline_str}${stage_name}(✓) → " ;;
      failed) pipeline_str="${pipeline_str}${stage_name}(✗) → " ;;
      stale)  pipeline_str="${pipeline_str}${stage_name}(⚠) → " ;;
      pending)pipeline_str="${pipeline_str}${stage_name}( ) → " ;;
    esac
  done
  pipeline_str="${pipeline_str% → }"
  
  # 输出
  if [ "$FORMAT" = "json" ]; then
    cat <<EOF
{
  "goal_status": "active",
  "current_stage": "$active_stage",
  "stage_status": "$current_stage",
  "next_action": "$next_action",
  "pipeline": "$pipeline_str",
  "completion_pct": $completion_pct,
  "completion_condition_met": $completion_met,
  "git_head": "$git_head",
  "task_dir": "$task_dir",
  "blockers": []
}
EOF
  else
    echo "🎯 Goal Status: active"
    echo "📊 Pipeline:    $pipeline_str"
    echo "📍 Stage:       $active_stage ($current_stage)"
    echo "📈 Progress:    ${completion_pct}%"
    echo "🔄 Next:        $next_action"
    echo "📁 Task:        $task_dir"
    echo "🔖 Git HEAD:    $git_head"
    if [ "$completion_met" = "true" ]; then
      echo "✅ Completion:  CONDITION MET"
    fi
  fi
}

main "$@"
