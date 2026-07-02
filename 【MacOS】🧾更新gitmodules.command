#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】🧾更新gitmodules.command
# - 核心用途：按工程根目录第一层真实子 Git 目录刷新或生成 .gitmodules。
# - 影响范围：只改写或新建当前工程根目录下的 .gitmodules，不自动 stage、commit、push，也不改子仓库内容。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，写入前再次回车确认。

SCRIPT_FILE="${(%):-%x}"
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_FILE")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$SCRIPT_FILE")"
SCRIPT_BASENAME="$(basename "$SCRIPT_FILE" | sed 's/\.[^.]*$//')"
REPO_ROOT="$SCRIPT_DIR"
GITMODULES_FILE="${REPO_ROOT}/.gitmodules"
LOG_FILE="${TMPDIR:-/tmp/}${SCRIPT_BASENAME}.log"
DRY_RUN="${DRY_RUN:-0}"

typeset -ga CURRENT_SUBGIT_DIRS
typeset -ga WRITABLE_SUBGIT_DIRS
typeset -ga SKIPPED_SUBGIT_DIRS
typeset -ga INFERRED_SUBGIT_DIRS
typeset -ga STALE_GITMODULE_PATHS
typeset -gA EXISTING_SECTION_NAMES
typeset -gA EXISTING_BRANCHES
typeset -gA SUBMODULE_URLS
typeset -gA SUBMODULE_BRANCHES
CURRENT_SUBGIT_DIRS=()
WRITABLE_SUBGIT_DIRS=()
SKIPPED_SUBGIT_DIRS=()
INFERRED_SUBGIT_DIRS=()
STALE_GITMODULE_PATHS=()

# 输出日志并同步写入日志文件。
log() {
  echo -e "$1" | tee -a "$LOG_FILE"
}
# 按当前输出级别记录普通信息。
info_echo() {
  log "\033[1;34mℹ $1\033[0m"
}
# 按当前输出级别记录成功信息。
success_echo() {
  log "\033[1;32m✔ $1\033[0m"
}
# 按当前输出级别记录警告信息。
warn_echo() {
  log "\033[1;33m⚠ $1\033[0m"
}
# 按当前输出级别记录说明信息。
note_echo() {
  log "\033[1;35m➤ $1\033[0m"
}
# 按当前输出级别记录错误信息。
error_echo() {
  log "\033[1;31m✖ $1\033[0m"
}
# 按当前输出级别记录高亮信息。
highlight_echo() {
  log "\033[1;36m🔹 $1\033[0m"
}
# 按当前输出级别记录次要信息。
gray_echo() {
  log "\033[0;90m$1\033[0m"
}
# 打印脚本内置自述，避免误触后直接修改 .gitmodules。
show_script_intro_and_wait() {
  clear 2>/dev/null || true
  print -r -- '============================== 脚本内置自述 =============================='
  print -r -- '脚本名称：【MacOS】🧾更新gitmodules.command'
  print -r -- '核心用途：扫描当前工程根目录第一层带 .git 的目录，并据此刷新或生成 .gitmodules。'
  print -r -- '影响范围：只改写或新建 .gitmodules；不会自动 git add、commit、push，也不会修改子仓库内容。'
  print -r -- '运行策略：先展示扫描结果和 diff，真正写入前直接回车执行，输入任意字符跳过。'
  print -r -- "日志位置：${LOG_FILE}"
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。'
  print -r -- '============================================================================'
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '当前没有可交互输入，请在终端中重新运行。'
    return 1
  fi
  echo ""
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 普通写入动作直接回车执行，输入任意字符后跳过。
ask_enter_to_run() {
  local message="$1"
  local answer=""
  read -r "?${message}（直接回车执行；输入任意字符后回车跳过）：" answer
  [[ -z "$answer" ]]
}
# 初始化 Shell 运行选项和日志文件。
initialize_script_runtime() {
  set -e
  set -o pipefail
  setopt NO_NOMATCH
  if [[ "$SCRIPT_FILE" != /* ]]; then
    SCRIPT_FILE="${PWD}/${SCRIPT_FILE}"
  fi
  : > "$LOG_FILE"
}
# 检查当前目录和 Git 命令是否满足刷新条件。
check_environment() {
  local git_root=""

  if ! command -v git >/dev/null 2>&1; then
    error_echo "未找到 git 命令，请先确认 Git 已安装。"
    return 1
  fi

  if [[ ! -d "${REPO_ROOT}/.git" && ! -f "${REPO_ROOT}/.git" ]]; then
    error_echo "脚本所在目录不是 Git 仓库根目录：${REPO_ROOT}"
    return 1
  fi

  git_root="$(git -C "$REPO_ROOT" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -z "$git_root" || "$git_root" != "$REPO_ROOT" ]]; then
    error_echo "脚本必须放在目标 Git 仓库根目录运行：${REPO_ROOT}"
    return 1
  fi
}
# 判断数组中是否包含指定值。
array_contains() {
  local needle="$1"
  shift || true
  local item=""
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}
# 读取已有 .gitmodules 的 path、section 和 branch，用于保留原 section 名。
load_existing_gitmodules() {
  local key=""
  local sub_path=""
  local section=""
  local branch=""

  EXISTING_SECTION_NAMES=()
  EXISTING_BRANCHES=()
  [[ -f "$GITMODULES_FILE" ]] || return 0

  while read -r key sub_path; do
    [[ -n "$key" && -n "$sub_path" ]] || continue
    section="${key#submodule.}"
    section="${section%.path}"
    EXISTING_SECTION_NAMES[$sub_path]="$section"
    branch="$(git -C "$REPO_ROOT" config -f "$GITMODULES_FILE" --get "submodule.${section}.branch" 2>/dev/null || true)"
    [[ -n "$branch" ]] && EXISTING_BRANCHES[$sub_path]="$branch"
  done < <(git -C "$REPO_ROOT" config -f "$GITMODULES_FILE" --get-regexp '^submodule\..*\.path$' 2>/dev/null || true)
}
# 扫描工程根目录第一层真实存在的子 Git 目录。
discover_current_subgit_dirs() {
  local marker=""
  local child_dir=""
  local sub_path=""

  CURRENT_SUBGIT_DIRS=()
  while IFS= read -r -d '' marker; do
    child_dir="$(dirname "$marker")"
    sub_path="${child_dir#${REPO_ROOT}/}"
    [[ "$sub_path" == "$child_dir" ]] && continue
    CURRENT_SUBGIT_DIRS+=("$sub_path")
  done < <(find "$REPO_ROOT" -mindepth 2 -maxdepth 2 \( -type f -name .git -o -type d -name .git \) -print0)

  if [[ ${#CURRENT_SUBGIT_DIRS[@]} -gt 0 ]]; then
    CURRENT_SUBGIT_DIRS=("${(@f)$(printf '%s\n' "${CURRENT_SUBGIT_DIRS[@]}" | sort -u)}")
  fi

  if [[ ${#CURRENT_SUBGIT_DIRS[@]} -eq 0 ]]; then
    error_echo "未在工程根目录第一层发现任何带 .git 的子目录。"
    return 1
  fi
}
# 按 Jobs 目录命名推导缺失的 GitHub origin URL。
infer_origin_url_for_subgit() {
  local sub_path="$1"
  local sub_dir="${REPO_ROOT}/${sub_path}"
  local base_name=""
  local repo_name=""

  base_name="$(basename "$sub_path")"
  if [[ "$base_name" == *.py ]]; then
    repo_name="${base_name%.py}"
    if [[ -d "${sub_dir}/${repo_name}" ]]; then
      print -r -- "git@github.com:JobsKits/${repo_name}.git"
      return 0
    fi
  fi

  return 1
}
# 判断当前 URL 是否来自目录名兜底推导。
is_inferred_origin_url() {
  local sub_path="$1"
  local current_url="$2"
  local sub_dir="${REPO_ROOT}/${sub_path}"
  local section="${EXISTING_SECTION_NAMES[$sub_path]:-}"
  local direct_url=""
  local existing_url=""
  local inferred_url=""

  direct_url="$(git -C "$sub_dir" config --get remote.origin.url 2>/dev/null || true)"
  [[ -n "$direct_url" ]] && return 1

  if [[ -n "$section" ]]; then
    existing_url="$(git -C "$REPO_ROOT" config -f "$GITMODULES_FILE" --get "submodule.${section}.url" 2>/dev/null || true)"
    [[ -n "$existing_url" ]] && return 1
  fi

  inferred_url="$(infer_origin_url_for_subgit "$sub_path" || true)"
  [[ -n "$inferred_url" && "$current_url" == "$inferred_url" ]]
}
# 读取子 Git 当前可用的 origin URL，必要时回退到旧 .gitmodules。
read_origin_url_for_subgit() {
  local sub_path="$1"
  local sub_dir="${REPO_ROOT}/${sub_path}"
  local section="${EXISTING_SECTION_NAMES[$sub_path]:-}"
  local url=""

  url="$(git -C "$sub_dir" config --get remote.origin.url 2>/dev/null || true)"
  if [[ -n "$url" ]]; then
    print -r -- "$url"
    return 0
  fi

  if [[ -n "$section" ]]; then
    url="$(git -C "$REPO_ROOT" config -f "$GITMODULES_FILE" --get "submodule.${section}.url" 2>/dev/null || true)"
    if [[ -n "$url" ]]; then
      print -r -- "$url"
      return 0
    fi
  fi

  url="$(infer_origin_url_for_subgit "$sub_path" || true)"
  if [[ -n "$url" ]]; then
    print -r -- "$url"
    return 0
  fi

  return 1
}
# 读取子 Git 分支名，detached HEAD 时尽量使用远端 main 或已有配置。
read_branch_for_subgit() {
  local sub_path="$1"
  local sub_dir="${REPO_ROOT}/${sub_path}"
  local branch=""
  local origin_head=""

  branch="$(git -C "$sub_dir" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [[ -n "$branch" ]]; then
    print -r -- "$branch"
    return 0
  fi

  branch="${EXISTING_BRANCHES[$sub_path]:-}"
  if [[ -n "$branch" ]]; then
    print -r -- "$branch"
    return 0
  fi

  origin_head="$(git -C "$sub_dir" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  origin_head="${origin_head#origin/}"
  if [[ -n "$origin_head" && "$origin_head" != "refs/remotes/origin/HEAD" ]]; then
    print -r -- "$origin_head"
    return 0
  fi

  if git -C "$sub_dir" show-ref --verify --quiet refs/remotes/origin/main 2>/dev/null; then
    print -r -- "main"
    return 0
  fi

  print -r -- "main"
}
# 收集可写入 .gitmodules 的子 Git 元数据，缺少 URL 的目录只提示并跳过。
collect_submodule_metadata() {
  local sub_path=""
  local url=""
  local branch=""

  WRITABLE_SUBGIT_DIRS=()
  SKIPPED_SUBGIT_DIRS=()
  INFERRED_SUBGIT_DIRS=()
  SUBMODULE_URLS=()
  SUBMODULE_BRANCHES=()
  for sub_path in "${CURRENT_SUBGIT_DIRS[@]}"; do
    url="$(read_origin_url_for_subgit "$sub_path" || true)"
    if [[ -z "$url" ]]; then
      SKIPPED_SUBGIT_DIRS+=("$sub_path")
      continue
    fi

    branch="$(read_branch_for_subgit "$sub_path")"
    SUBMODULE_URLS[$sub_path]="$url"
    SUBMODULE_BRANCHES[$sub_path]="$branch"
    WRITABLE_SUBGIT_DIRS+=("$sub_path")
    if is_inferred_origin_url "$sub_path" "$url"; then
      INFERRED_SUBGIT_DIRS+=("$sub_path")
    fi
  done

  if [[ ${#WRITABLE_SUBGIT_DIRS[@]} -eq 0 ]]; then
    error_echo "没有发现可写入 .gitmodules 的子 Git；请先确认至少一个子目录配置了 origin URL。"
    return 1
  fi
}
# 找出 .gitmodules 中已经不存在于磁盘真实子 Git 目录的旧 path。
collect_stale_gitmodules_paths() {
  local sub_path=""

  STALE_GITMODULE_PATHS=()
  for sub_path in "${(@k)EXISTING_SECTION_NAMES}"; do
    if ! array_contains "$sub_path" "${CURRENT_SUBGIT_DIRS[@]}"; then
      STALE_GITMODULE_PATHS+=("$sub_path")
    fi
  done

  if [[ ${#STALE_GITMODULE_PATHS[@]} -gt 0 ]]; then
    STALE_GITMODULE_PATHS=("${(@f)$(printf '%s\n' "${STALE_GITMODULE_PATHS[@]}" | sort -u)}")
  fi
}
# 打印扫描结果，方便写入前人工确认。
print_scan_report() {
  local sub_path=""

  highlight_echo "============================== 当前真实子 Git 目录 =============================="
  for sub_path in "${CURRENT_SUBGIT_DIRS[@]}"; do
    note_echo "$sub_path"
  done
  highlight_echo "============================================================================="
  echo ""

  highlight_echo "============================== 将写入 .gitmodules 的目录 =============================="
  for sub_path in "${WRITABLE_SUBGIT_DIRS[@]}"; do
    note_echo "${sub_path} -> ${SUBMODULE_URLS[$sub_path]} (${SUBMODULE_BRANCHES[$sub_path]})"
  done
  highlight_echo "=================================================================================="
  echo ""

  if [[ ${#SKIPPED_SUBGIT_DIRS[@]} -gt 0 ]]; then
    warn_echo "以下子 Git 缺少 origin URL，本次不会写入 .gitmodules："
    for sub_path in "${SKIPPED_SUBGIT_DIRS[@]}"; do
      warn_echo "$sub_path"
    done
    echo ""
  fi

  if [[ ${#INFERRED_SUBGIT_DIRS[@]} -gt 0 ]]; then
    warn_echo "以下子 Git 的 origin 无法直接读取，已按目录名兜底推导 URL："
    for sub_path in "${INFERRED_SUBGIT_DIRS[@]}"; do
      warn_echo "${sub_path} -> ${SUBMODULE_URLS[$sub_path]}"
    done
    echo ""
  fi

  if [[ ${#STALE_GITMODULE_PATHS[@]} -gt 0 ]]; then
    warn_echo "以下旧 .gitmodules path 已不在磁盘真实子 Git 中，本次会移除："
    for sub_path in "${STALE_GITMODULE_PATHS[@]}"; do
      warn_echo "$sub_path"
    done
    echo ""
  fi
}
# 按收集到的真实子 Git 元数据生成新的 .gitmodules 内容。
build_gitmodules_file() {
  local target_file="$1"
  local sub_path=""
  local section=""

  : > "$target_file"
  for sub_path in "${WRITABLE_SUBGIT_DIRS[@]}"; do
    section="${EXISTING_SECTION_NAMES[$sub_path]:-$sub_path}"
    {
      printf '[submodule "%s"]\n' "$section"
      printf '\tpath = %s\n' "$sub_path"
      printf '\turl = %s\n' "${SUBMODULE_URLS[$sub_path]}"
      printf '\tbranch = %s\n' "${SUBMODULE_BRANCHES[$sub_path]}"
    } >> "$target_file"
  done
}
# 打印本次计划写入的 .gitmodules diff。
print_planned_diff() {
  local planned_file="$1"

  highlight_echo "============================== 计划变更 diff =============================="
  if [[ -f "$GITMODULES_FILE" ]]; then
    diff -u "$GITMODULES_FILE" "$planned_file" 2>&1 | tee -a "$LOG_FILE" || true
  else
    cat "$planned_file" | tee -a "$LOG_FILE"
  fi
  highlight_echo "==========================================================================="
}
# 将计划内容写入 .gitmodules，DRY_RUN 模式只打印不落盘。
write_gitmodules_file() {
  local planned_file="$1"

  if [[ "$DRY_RUN" == "1" ]]; then
    warn_echo "DRY_RUN=1，本次只预览，不写入 .gitmodules。"
    return 0
  fi

  cp "$planned_file" "$GITMODULES_FILE"
  success_echo ".gitmodules 已按当前真实子 Git 目录刷新。"
}
# 打印刷新后的 Git 状态和 .gitmodules 差异。
print_final_report() {
  highlight_echo "============================== 当前 .gitmodules diff =============================="
  if git -C "$REPO_ROOT" ls-files --error-unmatch .gitmodules >/dev/null 2>&1; then
    git -C "$REPO_ROOT" diff -- .gitmodules 2>&1 | tee -a "$LOG_FILE" || true
  else
    warn_echo ".gitmodules 当前还没有被 Git 跟踪，下面是本次生成内容："
    cat "$GITMODULES_FILE" | tee -a "$LOG_FILE"
  fi
  highlight_echo "================================================================================"
  echo ""
  highlight_echo "============================== 当前 git status =============================="
  git -C "$REPO_ROOT" status --short 2>&1 | tee -a "$LOG_FILE" || true
  highlight_echo "==========================================================================="
  note_echo "日志文件：${LOG_FILE}"
}
# 执行预览、确认和写入 .gitmodules 的核心流程。
run_business() {
  local planned_file=""

  planned_file="$(mktemp "/tmp/${SCRIPT_BASENAME}.gitmodules.XXXXXX")"
  build_gitmodules_file "$planned_file"
  print_scan_report
  print_planned_diff "$planned_file"

  if [[ -f "$GITMODULES_FILE" ]] && cmp -s "$GITMODULES_FILE" "$planned_file"; then
    success_echo ".gitmodules 已经和当前可写入的子 Git 目录一致，无需更新。"
    rm -f "$planned_file"
    return 0
  fi

  echo ""
  if ! ask_enter_to_run "确认用上述内容更新 .gitmodules 吗？"; then
    warn_echo "用户选择跳过 .gitmodules 更新。"
    rm -f "$planned_file"
    return 0
  fi

  write_gitmodules_file "$planned_file"
  if [[ "$DRY_RUN" == "1" ]]; then
    rm -f "$planned_file"
    return 0
  fi
  rm -f "$planned_file"
  print_final_report
}
# 编排脚本的高层业务流程。
main() {
  show_script_intro_and_wait # 展示脚本内置自述，并完成第一层防误触确认。
  initialize_script_runtime # 初始化 Shell 选项和日志，确保后续命令失败能及时中断。
  check_environment # 检查 Git 命令和脚本所在仓库根目录是否可用。
  load_existing_gitmodules # 读取旧配置，用于保留已有 section 名和分支配置。
  discover_current_subgit_dirs # 扫描根目录第一层真实存在的子 Git 目录。
  collect_submodule_metadata # 收集每个可写入子 Git 的 URL 和分支。
  collect_stale_gitmodules_paths # 识别旧配置中已经失效的 path。
  run_business # 展示计划变更，并在二次确认后刷新 .gitmodules。
}

main "$@"
