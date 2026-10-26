#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】♻️双击Git（识别子Git） 提交回退.command
# - 核心用途：soft 撤回所选远端快照或历史提交之后的提交；兼容子模块和嵌套 Git。
# - 影响范围：soft 保留工作区和索引；hard 舍弃已跟踪改动；均只处理选定工作树。
# - 运行提示：多远端快照不同时，Sourcetree 转交终端选择；hard 必须输入 YES。
# shell: zsh

jobs_intro_style() {
  local intro_color=0
  if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
     [ -z "${NO_COLOR+x}" ] && [ "${PLAIN_OUTPUT:-0}" != 1 ] &&
     [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]; then
    intro_color=1
  fi
  /usr/bin/awk -v color="$intro_color" -v role="${1:-body}" '
    BEGIN { esc = sprintf("%c", 27) }
    {
      gsub(esc "\\[[0-9;]*m", "")
      gsub(/\\(033|e|x1[bB])\[[0-9;]*m/, "")
      if (!color || $0 ~ /^[[:space:]]*$/) { print; next }
      numbered = ($0 ~ /^[[:space:]➤ℹ🔹✔⚠]*([0-9]+[、.)）]|[0-9]+️⃣|[-•])/)
      heading = ($0 ~ /^[[:space:]]*#{1,6}[[:space:]]/ || $0 ~ /[：:][[:space:]]*$/ || $0 ~ /^[[:space:]]*[=━─-]{3}/)
      title = (!numbered && (role == "title" || heading))
      if (role == "auto" && !seen && !numbered) title = 1
      if ($0 !~ /^[[:space:]]*[=━─-]+[[:space:]]*$/) seen = 1
      printf "%s%s%s\n", esc (title ? "[1;31m" : "[0;34m"), $0, esc "[0m"
    }
  '
}
RAW_SCRIPT_PATH="$0"
SCRIPT_PATH=""
SCRIPT_BASENAME=""
LOG_FILE=""
LOG_READY=0
IS_SOURCETREE_RUNTIME=0
PLAIN_OUTPUT=0
REPO_ROOT=""
UPSTREAM_REF=""
RESET_TARGET=""
RESET_MODE=""
SELECTION=""
REPO_ARGUMENT=""
REQUESTED_UPSTREAM_REF=""
TERMINAL_SOFT=0
INITIAL_HEAD_REF=""
INITIAL_HEAD_COMMIT=""
REPOSITORY_GIT_DIR=""
typeset -a UPSTREAM_CHOICES=()

# 仅以 Sourcetree 环境标记或父进程确认入口，不把命令行参数当作身份。
is_sourcetree_runtime() {
  /usr/bin/env | /usr/bin/grep -Ei '^SOURCETREE|^SOURCE_TREE' >/dev/null && return 0
  local process_id="$PPID" process_name="" guard=0
  while [[ -n "$process_id" && "$process_id" != 0 && "$guard" -lt 8 ]]; do
    process_name="$(/bin/ps -o comm= -p "$process_id" 2>/dev/null || true)"
    [[ "$process_name" == *SourceTree* || "$process_name" == *Sourcetree* ]] && return 0
    process_id="$(/bin/ps -o ppid= -p "$process_id" 2>/dev/null | /usr/bin/tr -d ' ' || true)"
    guard=$((guard + 1))
  done
  return 1
}
# 准备路径与纯文本输出，首屏不创建日志或改动 Git。
prepare_intro_context() {
  local filename="${RAW_SCRIPT_PATH:t}" candidate="${RAW_SCRIPT_PATH:A}"
  local fallback=""
  for fallback in "${HOME}/SourceTree.command/MacOS/${filename}/${filename}" "${HOME}/Documents/Github/JobsGenesis/SourceTree.command/MacOS/${filename}/${filename}"; do
    [[ -f "$candidate" ]] && break
    [[ -f "$fallback" ]] && candidate="$fallback"
  done
  SCRIPT_PATH="$candidate"
  SCRIPT_BASENAME="${filename:r}"
  LOG_FILE="${${TMPDIR:-/tmp}:A}/${SCRIPT_BASENAME}.$(/bin/date '+%Y%m%d-%H%M%S').$$.log"
  is_sourcetree_runtime && IS_SOURCETREE_RUNTIME=1
  if [[ "${1:-}" == --terminal-soft ]]; then
    TERMINAL_SOFT=1
    IS_SOURCETREE_RUNTIME=0
  fi
  configure_output_mode
}
# 确认前后均配置外部命令的纯文本环境。
configure_output_mode() {
  if [[ "$IS_SOURCETREE_RUNTIME" == 1 || ! -t 1 || -z "${TERM:-}" || "${TERM:-}" == dumb || -n "${NO_COLOR+x}" ]]; then
    PLAIN_OUTPUT=1
    export NO_COLOR=1 FORCE_COLOR=0 CLICOLOR=0 ANSI_COLORS_DISABLED=1 npm_config_color=false
  fi
  return 0
}
strip_ansi_stream() {
  /usr/bin/perl -pe 's/\e\[[0-9;]*[[:alpha:]]//g'
}
# 展示颜色与业务正文分开，路径中的反斜杠保持原值。
log() {
  local level="$1" message="$2" rendered="$2" color=""
  case "$level" in
    info) color=$'\033[1;34m' ;;
    success) color=$'\033[1;32m' ;;
    warn) color=$'\033[1;33m' ;;
    error) color=$'\033[1;31m' ;;
  esac
  [[ "$PLAIN_OUTPUT" == 1 ]] || rendered="${color}${message}"$'\033[0m'
  if [[ "$LOG_READY" == 1 ]]; then
    print -r -- "$rendered" | tee -a "$LOG_FILE"
  else
    print -r -- "$rendered"
  fi
}
info_echo() { log info "ℹ $1"; }
success_echo() { log success "✔ $1"; }
warn_echo() { log warn "⚠ $1"; }
error_echo() { log error "✖ $1"; }
# 自述失败必须终止，不能进入后面的重置逻辑。
show_script_intro_and_wait() {
  prepare_intro_context "$@"
  print -r -- "============================== Git 提交回退 ==============================" | jobs_intro_style title
  print -r -- "脚本名称：${SCRIPT_BASENAME}.command" | jobs_intro_style title
  print -r -- "1、soft 只移动当前分支，保留已有索引和工作区；是否有待提交内容以实际差异为准。" | jobs_intro_style body
  print -r -- "2、Sourcetree 多远端快照不同时转交 Terminal 明确选择；终端也支持选择历史提交 soft 回退。" | jobs_intro_style body
  print -r -- "3、默认采用 upstream；可用 --upstream refs/remotes/远端/分支明确指定，不自动 fetch。" | jobs_intro_style body
  print -r -- "4、soft 目标必须是 HEAD 祖先；选择期间分支或快照变化时停止，请重新核对。" | jobs_intro_style body
  print -r -- "5、所有 hard 模式会舍弃已跟踪的未提交内容，必须输入 YES；不递归重置子模块。" | jobs_intro_style body
  print -r -- "取消方式：Ctrl+C；日志位于 ${LOG_FILE}" | jobs_intro_style body
  if [[ "$IS_SOURCETREE_RUNTIME" == 1 ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    print -u2 -r -- "当前不是 Sourcetree，且没有可交互输入；请在终端重新运行。"
    exit 1
  fi
  read -r '?已了解用途与影响，按回车继续；Ctrl+C 取消：' _ || exit 1
}
initialize_script_runtime() {
  emulate -R zsh
  setopt NO_NOMATCH ERR_EXIT PIPE_FAIL
  export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
  : > "$LOG_FILE"
  LOG_READY=1
  configure_output_mode
}
# 清理仅限本进程的 Git 定位变量，避免父仓环境覆盖明确传入的子仓路径。
isolate_git_context() {
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX GIT_NAMESPACE
}
check_environment() {
  command -v git >/dev/null && git --version >/dev/null || { error_echo "Git 不可用。"; return 1; }
}
# 解析仓库与显式远端引用；终端承接标志只能位于首参数。
parse_arguments() {
  [[ "${1:-}" != --terminal-soft ]] || shift
  while (( $# )); do
    case "$1" in
      --upstream)
        (( $# >= 2 )) && [[ -n "$2" ]] || { error_echo '--upstream 缺少完整远端跟踪引用。'; return 1; }
        REQUESTED_UPSTREAM_REF="$2"
        shift 2
        ;;
      --*) error_echo "未知参数：$1"; return 1 ;;
      *)
        [[ -z "$REPO_ARGUMENT" ]] || { error_echo '只能指定一个仓库目录。'; return 1; }
        REPO_ARGUMENT="$1"
        shift
        ;;
    esac
  done
}
# 拖入路径只做字符串解引用，不执行用户输入。
resolve_repository() {
  local candidate="${1:-${REPO:-}}" entered=""
  if [[ -z "$candidate" ]]; then
    if [[ "$IS_SOURCETREE_RUNTIME" == 1 ]]; then
      error_echo '未收到仓库路径；请在动作参数栏填写 $REPO。'
      return 1
    fi
    info_echo "输入或拖入仓库路径；直接回车使用当前目录：${PWD}"
    read -r 'entered?仓库路径：' || return 1
    candidate="${entered:-$PWD}"
  fi
  candidate="${candidate%$'\r'}"
  [[ -e "$candidate" ]] || candidate="${(Q)candidate}"
  [[ -f "$candidate" ]] && candidate="${candidate:h}"
  [[ -d "$candidate" ]] || { error_echo "目标目录不存在：${candidate}"; return 1; }
  REPO_ROOT="$(git -C "$candidate" rev-parse --show-toplevel 2>/dev/null)" || { error_echo "目标不在 Git 工作树中：${candidate}"; return 1; }
  REPO_ROOT="${REPO_ROOT:A}"
  REPOSITORY_GIT_DIR="$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir)" || return $?
  INITIAL_HEAD_REF="$(git -C "$REPO_ROOT" symbolic-ref --quiet HEAD 2>/dev/null || true)"
  INITIAL_HEAD_COMMIT="$(git -C "$REPO_ROOT" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" || { error_echo '当前仓库尚无有效 HEAD 提交，无法回退。'; return 1; }
  info_echo "当前 Git 仓库：${REPO_ROOT}"
  local parent="$(git -C "$REPO_ROOT" rev-parse --show-superproject-working-tree)"
  [[ -z "$parent" ]] || info_echo "直属父仓：${parent}；本次只回退当前子仓，父仓暂存区不变。"
  return 0
}
# 冲突、未完成操作或游离 HEAD 下不能把回退解释为未推送提交撤回。
check_repository_state() {
  local metadata="" unmerged="" marker=""
  metadata="$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir)" || return $?
  unmerged="$(git -C "$REPO_ROOT" ls-files --unmerged)" || return $?
  if [[ -n "$unmerged" ]]; then
    error_echo "存在未解决冲突，请先处理。"
    return 1
  fi
  for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG rebase-merge rebase-apply sequencer index.lock; do
    [[ ! -e "${metadata}/${marker}" ]] || { error_echo "存在未完成操作或锁：${marker}"; return 1; }
  done
}
# 重新核对仓库、分支与起始提交，交互过程中切换或更新过就停止。
check_reset_context() {
  local metadata="" current_root="" current_ref="" current_commit=""
  metadata="$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir)" || return $?
  current_root="$(git -C "$REPO_ROOT" rev-parse --show-toplevel)" || return $?
  current_ref="$(git -C "$REPO_ROOT" symbolic-ref --quiet HEAD 2>/dev/null || true)"
  current_commit="$(git -C "$REPO_ROOT" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" || return $?
  if [[ "$metadata" != "$REPOSITORY_GIT_DIR" || "${current_root:A}" != "$REPO_ROOT" || "$current_ref" != "$INITIAL_HEAD_REF" || "$current_commit" != "$INITIAL_HEAD_COMMIT" ]]; then
    error_echo '选择或确认期间仓库、分支或 HEAD 已变化；保持现状，请重新运行并核对。'
    return 1
  fi
  check_repository_state
}
# 参数必须是真实完整远端引用，不接受 ~1、^ 或 @{...} 等修订表达式。
verify_upstream_reference() {
  local ref="$1"
  [[ "$ref" == refs/remotes/* ]] && git -C "$REPO_ROOT" check-ref-format "$ref" &&
    git -C "$REPO_ROOT" show-ref --verify --quiet "$ref" || {
      error_echo "远端跟踪引用不存在或格式不完整：${ref}"
      return 1
    }
}
# 收集当前分支各线路已有快照及真实 upstream，不扫描或选择别的仓库。
collect_upstream_choices() {
  local branch="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  local remote="" ref="" configured=""
  UPSTREAM_CHOICES=()
  [[ -n "$branch" ]] || return 0
  configured="$(git -C "$REPO_ROOT" rev-parse --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  if [[ "$configured" == refs/remotes/* ]] && git -C "$REPO_ROOT" rev-parse --verify "${configured}^{commit}" >/dev/null 2>&1; then
    UPSTREAM_CHOICES+=("$configured")
  fi
  for remote in "${(@f)$(git -C "$REPO_ROOT" remote)}"; do
    ref="refs/remotes/${remote}/${branch}"
    if git -C "$REPO_ROOT" rev-parse --verify "${ref}^{commit}" >/dev/null 2>&1; then
      UPSTREAM_CHOICES+=("$ref")
    fi
  done
  UPSTREAM_CHOICES=("${(@u)UPSTREAM_CHOICES}")
}
# 只读取本地跟踪快照；显式选择优先，不因某条线路拒收而自动改用另一条。
resolve_upstream_target() {
  local branch="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  local configured_remote="" ref="" commit=""
  local -a choices=()
  local -A snapshot_commits=()
  [[ -n "$branch" ]] || { error_echo "游离 HEAD 没有明确当前分支，不能回退到远端。"; return 1; }
  configured_remote="$(git -C "$REPO_ROOT" config --get "branch.${branch}.remote" || true)"
  UPSTREAM_REF="$REQUESTED_UPSTREAM_REF"
  if [[ -z "$UPSTREAM_REF" && "$IS_SOURCETREE_RUNTIME" != 1 ]]; then
    collect_upstream_choices
    if (( ${#UPSTREAM_CHOICES} > 1 )); then
      for ref in "${UPSTREAM_CHOICES[@]}"; do
        commit="$(git -C "$REPO_ROOT" rev-parse "$ref")"
        snapshot_commits[$ref]="$commit"
        choices+=("${ref} [${commit[1,12]}]")
      done
      choose_entry '选择本地远端快照（不联网）' 1 "${choices[@]}" || return $?
      [[ -n "$SELECTION" ]] || return 20
      UPSTREAM_REF="${SELECTION%% *}"
    fi
  fi
  [[ -n "$UPSTREAM_REF" ]] || UPSTREAM_REF="$(git -C "$REPO_ROOT" rev-parse --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  if [[ -z "$UPSTREAM_REF" && -z "$configured_remote" ]]; then
    UPSTREAM_REF="refs/remotes/origin/${branch}"
  fi
  verify_upstream_reference "$UPSTREAM_REF" || return $?
  RESET_TARGET="$(git -C "$REPO_ROOT" rev-parse --verify "${UPSTREAM_REF}^{commit}" 2>/dev/null)" || { error_echo "远端跟踪引用不可用：${UPSTREAM_REF}"; return 1; }
  if [[ -n "${snapshot_commits[$UPSTREAM_REF]:-}" && "$RESET_TARGET" != "${snapshot_commits[$UPSTREAM_REF]}" ]]; then
    error_echo '远端跟踪快照在选择期间已变化；没有回退，请重新选择。'
    return 1
  fi
  info_echo "本地跟踪快照：${UPSTREAM_REF} [${RESET_TARGET}]"
}
# 远端 soft 的目标来自已验证的引用，索引和工作区保持原样。
reset_soft_to_remote() {
  resolve_upstream_target || return $?
  reset_soft_to_target "$UPSTREAM_REF"
}
# soft 仅回退到 HEAD 的祖先；提交数不等于净文件差异数。
reset_soft_to_target() {
  local description="$1"
  check_reset_context || return $?
  if ! git -C "$REPO_ROOT" merge-base --is-ancestor "$RESET_TARGET" "$INITIAL_HEAD_COMMIT"; then
    error_echo "目标不是 HEAD 的祖先：${description}；本地可能落后或分叉，请先检查历史。"
    return 1
  fi
  local ahead=""
  ahead="$(git -C "$REPO_ROOT" rev-list --count "${RESET_TARGET}..${INITIAL_HEAD_COMMIT}")" || return $?
  if [[ "$ahead" == 0 ]]; then
    info_echo "HEAD 已与所选目标一致：${description} [${RESET_TARGET}]；本次没有撤回提交。"
    info_echo '这只代表所选线路；其它远端可能尚未同步。撤回已同步提交可在终端选择“选择提交 soft 回退”。'
    report_staged_changes
    return $?
  fi
  info_echo "仅在本地撤回 ${ahead} 个提交到 ${description}，保留工作区及已有索引；其它远端可能已经包含这些提交。"
  check_reset_context || return $?
  run_git reset --soft "$RESET_TARGET" || return $?
  success_echo "已 soft 回退到 ${description} [${RESET_TARGET}]。"
  report_staged_changes
}
# 依据真实索引报告结果，空提交或净变化抵消时不虚报待提交文件。
report_staged_changes() {
  local diff_result=0 summary=""
  git -C "$REPO_ROOT" diff --cached --quiet --ignore-submodules=none || diff_result=$?
  case "$diff_result" in
    0) info_echo '暂存区相对当前 HEAD 没有文件差异；空提交或内容相互抵消时属于正常结果。' ;;
    1)
      summary="$(git -C "$REPO_ROOT" diff --cached --shortstat --ignore-submodules=none)" || return $?
      info_echo "待提交差异：${summary}；请在当前仓库的 Sourcetree 文件状态中核对。"
      ;;
    *) error_echo '无法读取暂存差异，请保留现场检查。'; return "$diff_result" ;;
  esac
}
# 保留外部 Git 的原始退出码，任何重置失败都不能打印成功。
run_git() {
  local -a result_codes=()
  if git -C "$REPO_ROOT" "$@" 2>&1 | strip_ansi_stream | tee -a "$LOG_FILE"; then
    return 0
  else
    result_codes=("${pipestatus[@]}")
  fi
  local result_code=0
  for result_code in "${result_codes[@]}"; do
    (( result_code == 0 )) || return "$result_code"
  done
  return 1
}
# 摘要仅用于 hard 确认期间的变化检测，不修改索引或写入对象库。
capture_hard_reset_state() {
  local index_file="" index_digest=missing worktree_digest="" status_digest=""
  index_file="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-path index)" || return $?
  if [[ -f "$index_file" ]]; then
    index_digest="$(/usr/bin/shasum -a 256 "$index_file")" || return $?
  fi
  worktree_digest="$(git --no-optional-locks -c diff.autoRefreshIndex=false -C "$REPO_ROOT" diff --no-ext-diff --no-textconv --binary --ignore-submodules=all | /usr/bin/shasum -a 256)" || return $?
  status_digest="$(git --no-optional-locks -C "$REPO_ROOT" status --porcelain=v1 -z --untracked-files=all --ignore-submodules=none | /usr/bin/shasum -a 256)" || return $?
  print -r -- "$index_digest" "$worktree_digest" "$status_digest"
}
# hard 以已解析的提交号固定目标，防止 tag 名歧义和确认后引用变化。
confirm_and_reset_hard() {
  local target="$1" description="$2" answer="" commit="" before_state="" current_state=""
  [[ "$IS_SOURCETREE_RUNTIME" != 1 && -t 0 ]] || { error_echo 'hard 回退只允许在独立交互终端确认。'; return 1; }
  check_reset_context || return $?
  commit="$(git -C "$REPO_ROOT" rev-parse --verify "${target}^{commit}" 2>/dev/null)" || { error_echo "所选目标不是有效提交：${description}"; return 1; }
  before_state="$(capture_hard_reset_state)" || return $?
  warn_echo "仓库：${REPO_ROOT}"
  warn_echo "hard 回退目标：${description} [${commit}]；已跟踪的未提交内容会被舍弃。"
  read -r 'answer?输入 YES 执行；其它输入取消：' || return 1
  if [[ "$answer" != YES ]]; then
    info_echo "已取消 hard 回退。"
    return 0
  fi
  check_reset_context || return $?
  current_state="$(capture_hard_reset_state)" || return $?
  [[ "$current_state" == "$before_state" ]] || { error_echo '确认期间索引或已跟踪改动发生变化；未执行 hard 回退，请重新核对。'; return 1; }
  check_reset_context || return $?
  run_git -c submodule.recurse=false reset --hard --no-recurse-submodules "$commit" || return $?
  success_echo "已 hard 回退到 ${commit}；子模块工作树保持原状。"
}
# fzf 区分返回、取消和失败；非根选择按左方向键返回模式层。
choose_entry() {
  local title="$1" allow_back="$2" entry="" output="" selection_result=0
  local -a entries=()
  local -a options=(--no-sort --reverse --no-multi --prompt="${title}：")
  shift 2
  for entry in "$@"; do
    [[ -n "$entry" ]] && entries+=("$entry")
  done
  SELECTION=""
  [[ "${#entries[@]}" -gt 0 ]] || { error_echo "没有可供选择的记录：${title}"; return 1; }
  [[ -t 0 && -t 1 ]] || { error_echo '选择回退目标需要可交互终端。'; return 1; }
  command -v fzf >/dev/null && FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= fzf --version >/dev/null || { error_echo 'fzf 不可用，请先安装或修复后重试。'; return 1; }
  if [[ "$allow_back" == 1 ]]; then
    options+=(--expect=left --header='回车选择，← 返回上一层，Esc 取消')
  else
    options+=(--header='回车选择，Esc 取消')
  fi
  output="$(printf '%s\n' "${entries[@]}" | FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= fzf "${options[@]}")" || selection_result=$?
  if [[ "$allow_back" == 1 && "${output%%$'\n'*}" == left ]]; then
    return 10
  fi
  case "$selection_result" in
    0)
      [[ "$allow_back" != 1 ]] || output="${output#*$'\n'}"
      [[ -n "$output" ]] || return 0
      for entry in "${entries[@]}"; do
        if [[ "$output" == "$entry" ]]; then
          SELECTION="$output"
          return 0
        fi
      done
      error_echo '选择器返回了列表之外的内容，已停止。'
      return 2
      ;;
    1|130) return 0 ;;
    *) error_echo "fzf 选择失败：${selection_result}"; return "$selection_result" ;;
  esac
}
# 提交列表首列始终为完整 hash，不从图形线条里猜目标。
perform_selected_reset() {
  local -a records=()
  case "$RESET_MODE" in
    'soft 回退到 upstream') reset_soft_to_remote ;;
    'hard 回退到 upstream')
      resolve_upstream_target || return $?
      confirm_and_reset_hard "$RESET_TARGET" "$UPSTREAM_REF"
      ;;
    '选择提交 soft 回退'|'选择提交 hard 回退')
      records=("${(@f)$(git -C "$REPO_ROOT" log --all --format='%H %s' --max-count=200)}")
      choose_entry "选择回退后保留的提交" 1 "${records[@]}" || return $?
      [[ -n "$SELECTION" ]] || return 0
      if [[ "$RESET_MODE" == '选择提交 soft 回退' ]]; then
        RESET_TARGET="${SELECTION%% *}"
        reset_soft_to_target "$SELECTION"
      else
        confirm_and_reset_hard "${SELECTION%% *}" "$SELECTION"
      fi
      ;;
    '选择 tag hard 回退')
      records=("${(@f)$(git -C "$REPO_ROOT" tag --sort=-creatordate)}")
      choose_entry "选择 tag" 1 "${records[@]}" || return $?
      [[ -n "$SELECTION" ]] || return 0
      confirm_and_reset_hard "refs/tags/${SELECTION}" "$SELECTION"
      ;;
    '选择 reflog hard 回退')
      records=("${(@f)$(git -C "$REPO_ROOT" reflog --format='%H %gd %gs' --max-count=200)}")
      choose_entry "选择 reflog" 1 "${records[@]}" || return $?
      [[ -n "$SELECTION" ]] || return 0
      confirm_and_reset_hard "${SELECTION%% *}" "$SELECTION"
      ;;
    *) info_echo "已取消回退。" ;;
  esac
}
# 返回键只重进模式层，取消不会执行后续回退。
run_interactive_reset() {
  local result=0
  local -a modes=('soft 回退到 upstream' '选择提交 soft 回退')
  [[ "$TERMINAL_SOFT" == 1 ]] || modes+=('hard 回退到 upstream' '选择提交 hard 回退' '选择 tag hard 回退' '选择 reflog hard 回退')
  while true; do
    choose_entry '选择回退模式' 0 "${modes[@]}" || return $?
    [[ -n "$SELECTION" ]] || { info_echo '已取消回退。'; return 0; }
    RESET_MODE="$SELECTION"
    result=0
    perform_selected_reset || result=$?
    [[ "$result" != 10 ]] || continue
    [[ "$result" != 20 ]] || { info_echo '已取消回退。'; return 0; }
    return "$result"
  done
}
# 使用 argv 与 shell 引号承接明确仓库，终端回退仍需确认和选择。
open_terminal_for_selection() {
  /usr/bin/osascript - "$SCRIPT_PATH" "$REPO_ROOT" <<'APPLESCRIPT'
on run argv
  set shellCommand to "/bin/zsh " & quoted form of item 1 of argv & " --terminal-soft " & quoted form of item 2 of argv & "; jobs_reset_result=$?; printf '\\n提交回退结束，退出码：%s\\n' \"$jobs_reset_result\""
  tell application "Terminal"
    activate
    do script shellCommand
  end tell
end run
APPLESCRIPT
  local launch_result=$?
  (( launch_result == 0 )) || { error_echo 'Terminal 启动失败；仓库未回退，请在终端手动运行。'; return "$launch_result"; }
  info_echo '已转交 Terminal；回车确认后选择回退模式与目标，最终结果在新终端查看。'
}
# 各线路当前分支快照不一致时不能仅按默认 upstream 解释全部推送状态。
dispatch_multiremote_selection() {
  [[ "$IS_SOURCETREE_RUNTIME" == 1 && -z "$REQUESTED_UPSTREAM_REF" ]] || return 0
  collect_upstream_choices
  local ref="" commit=""
  local -a commits=()
  for ref in "${UPSTREAM_CHOICES[@]}"; do
    commit="$(git -C "$REPO_ROOT" rev-parse "$ref")"
    commits+=("$commit")
  done
  commits=("${(@u)commits}")
  (( ${#commits[@]} > 1 )) || return 0
  warn_echo '检测到多条远端线路的本地快照不同；请明确选择，当前还没有执行 reset。'
  for ref in "${UPSTREAM_CHOICES[@]}"; do
    info_echo "${ref} [$(git -C "$REPO_ROOT" rev-parse --short "$ref")]"
  done
  open_terminal_for_selection || exit $?
  exit 0
}
run_reset_workflow() {
  if [[ "$IS_SOURCETREE_RUNTIME" == 1 ]]; then
    reset_soft_to_remote
  else
    run_interactive_reset
  fi
}
print_completion() {
  success_echo "提交回退流程结束；日志：${LOG_FILE}"
}
main() {
  show_script_intro_and_wait "$@" # 首屏自述与确认，Sourcetree 仅跳过入口确认。
  initialize_script_runtime # 确认后准备日志与 Shell 选项。
  isolate_git_context # 隔离继承的 Git 仓库定位变量，保护明确选定的工作树。
  check_environment # 验证 Git 可用。
  parse_arguments "$@" # 解析仓库和显式远端快照，不猜最近失败线路。
  resolve_repository "$REPO_ARGUMENT" # 使用指定工作树，避免误处理外层仓库。
  check_repository_state # 冲突、锁与未完成操作阻止重置。
  dispatch_multiremote_selection # Sourcetree 多线路不一致时转交终端明确选择。
  run_reset_workflow # Sourcetree 执行安全 soft 模式，终端允许选择并确认 hard 模式。
  print_completion # 业务成功后输出结果与日志位置。
}

main "$@"
