#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】🧭更新引用Git父仓=>子仓.command
# - 核心用途：执行“🧭更新引用Git父仓=>子仓”对应的 Git / Sourcetree 自动化操作。
# - 影响范围：可能修改当前仓库、工作区、分支、菜单配置或 Git 索引。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。

SCRIPT_SOURCE="$0"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$SCRIPT_SOURCE")"
SCRIPT_BASENAME=$(basename "$SCRIPT_SOURCE" | sed 's/\.[^.]*$//')
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"

PARENT_REPO_DIR="$SCRIPT_DIR"

typeset -ga CURRENT_SUBGIT_DIRS
typeset -gA SUBMODULE_URLS
CURRENT_SUBGIT_DIRS=()
# 输出日志并同步写入日志文件。
log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
color_echo()     { log "\033[1;32m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warm_echo()      { log "\033[1;33m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
err_echo()       { log "\033[1;31m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
gray_echo()      { log "\033[0;90m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
bold_echo()      { log "\033[1m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
underline_echo() { log "\033[4m$1\033[0m"; }
# 打印脚本内置自述，避免双击误触后直接修改 Git 元数据。
show_script_intro_and_wait() {
  clear 2>/dev/null || true
  print -r -- '============================== 脚本内置自述 =============================='
  print -r -- '脚本名称：【MacOS】🧭更新引用Git父仓=>子仓.command'
  print -r -- '核心用途：以脚本所在目录作为父 Git，按同级真实子 Git 目录对齐 .gitmodules 和 gitlink。'
  print -r -- '影响范围：可能修改 .gitmodules、父仓库索引 gitlink、本地 .git/config 和子目录 .git 指针。'
  print -r -- '运行策略：先展示当前真实子 Git 和 git status，再由二次确认决定是否执行修复。'
  print -r -- "日志位置：${LOG_FILE}"
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。'
  print -r -- '============================================================================'
  echo ""
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 修复动作默认执行，输入任意字符后跳过。
ask_enter_to_run() {
  local message="$1"
  local answer=""
  read -r "?${message}（直接回车执行；输入任意字符后回车跳过）：" answer
  [[ -z "$answer" ]]
}
# 检查命令和父仓库环境是否满足修复条件。
check_environment() {
  if ! command -v git >/dev/null 2>&1; then
    error_echo "未找到 git 命令，请先确认 Git 已安装。"
    return 1
  fi

  if [[ ! -d "${PARENT_REPO_DIR}/.git" && ! -f "${PARENT_REPO_DIR}/.git" ]]; then
    error_echo "脚本所在目录不是 Git 仓库：${PARENT_REPO_DIR}"
    return 1
  fi

  if ! git -C "$PARENT_REPO_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
    error_echo "无法识别父 Git 仓库：${PARENT_REPO_DIR}"
    return 1
  fi
}
# 判断数组里是否包含指定路径。
array_contains() {
  local needle="$1"
  shift || true
  local item=""
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}
# 把路径规整为绝对路径，路径不存在时原样返回。
normalize_existing_path() {
  local input_path="$1"
  local parent_dir=""
  local base_name=""

  if [[ -d "$input_path" ]]; then
    cd "$input_path" 2>/dev/null && pwd -P
    return 0
  fi

  parent_dir="$(dirname "$input_path")"
  base_name="$(basename "$input_path")"
  if [[ -d "$parent_dir" ]]; then
    printf '%s/%s\n' "$(cd "$parent_dir" && pwd -P)" "$base_name"
  else
    print -r -- "$input_path"
  fi
}
# 读取 Git 配置文件里 origin 远端地址，避免坏 worktree 导致 git config 失败。
read_origin_from_config_file() {
  local config_file="$1"
  [[ -f "$config_file" ]] || return 1

  awk '
    /^\[remote "origin"\]/ { in_origin = 1; next }
    /^\[/ { in_origin = 0 }
    in_origin && /^[[:space:]]*url[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*/, "")
      print
      exit
    }
  ' "$config_file"
}
# 根据子目录名推导父仓库 .git/modules 下的标准 gitdir。
module_dir_for_path() {
  local sub_path="$1"
  print -r -- "${PARENT_REPO_DIR}/.git/modules/${sub_path}"
}
# 读取子 Git 当前可用的 origin URL。
read_origin_url_for_subgit() {
  local sub_path="$1"
  local sub_dir="${PARENT_REPO_DIR}/${sub_path}"
  local git_marker="${sub_dir}/.git"
  local standard_module_dir=""
  local marker_gitdir=""
  local marker_module_dir=""
  local url=""

  url="$(git -C "$sub_dir" config --get remote.origin.url 2>/dev/null || true)"
  if [[ -n "$url" ]]; then
    print -r -- "$url"
    return 0
  fi

  standard_module_dir="$(module_dir_for_path "$sub_path")"
  url="$(git --git-dir="$standard_module_dir" --work-tree="$sub_dir" config --get remote.origin.url 2>/dev/null || true)"
  if [[ -n "$url" ]]; then
    print -r -- "$url"
    return 0
  fi

  url="$(read_origin_from_config_file "${standard_module_dir}/config" || true)"
  if [[ -n "$url" ]]; then
    print -r -- "$url"
    return 0
  fi

  if [[ -f "$git_marker" ]]; then
    marker_gitdir="$(sed -n 's/^gitdir:[[:space:]]*//p' "$git_marker" | head -n 1)"
    if [[ -n "$marker_gitdir" ]]; then
      [[ "$marker_gitdir" != /* ]] && marker_gitdir="${sub_dir}/${marker_gitdir}"
      marker_module_dir="$(normalize_existing_path "$marker_gitdir")"
      url="$(read_origin_from_config_file "${marker_module_dir}/config" || true)"
      if [[ -n "$url" ]]; then
        print -r -- "$url"
        return 0
      fi
    fi
  fi

  url="$(git -C "$PARENT_REPO_DIR" config -f .gitmodules --get "submodule.${sub_path}.url" 2>/dev/null || true)"
  if [[ -n "$url" ]]; then
    print -r -- "$url"
    return 0
  fi

  return 1
}
# 扫描父仓库第一层真实存在的子 Git 目录。
discover_current_subgit_dirs() {
  local marker=""
  local child_dir=""
  local sub_name=""

  CURRENT_SUBGIT_DIRS=()
  while IFS= read -r -d '' marker; do
    child_dir="$(dirname "$marker")"
    sub_name="$(basename "$child_dir")"
    [[ "$sub_name" == ".git" ]] && continue
    CURRENT_SUBGIT_DIRS+=("$sub_name")
  done < <(find "$PARENT_REPO_DIR" -mindepth 2 -maxdepth 2 \( -type f -name .git -o -type d -name .git \) -print0)

  if [[ ${#CURRENT_SUBGIT_DIRS[@]} -gt 0 ]]; then
    CURRENT_SUBGIT_DIRS=("${(@f)$(printf '%s\n' "${CURRENT_SUBGIT_DIRS[@]}" | sort)}")
  fi

  if [[ ${#CURRENT_SUBGIT_DIRS[@]} -eq 0 ]]; then
    error_echo "未在父仓库第一层发现任何带 .git 的子目录。"
    return 1
  fi
}
# 收集每个真实子 Git 的远端地址，无法识别时停止，避免写坏 .gitmodules。
collect_submodule_urls() {
  local sub_path=""
  local url=""

  SUBMODULE_URLS=()
  for sub_path in "${CURRENT_SUBGIT_DIRS[@]}"; do
    url="$(read_origin_url_for_subgit "$sub_path" || true)"
    if [[ -z "$url" ]]; then
      error_echo "无法读取子 Git 的 origin URL：${sub_path}"
      err_echo "请先进入该目录确认 remote.origin.url，再重新运行本脚本。"
      return 1
    fi
    SUBMODULE_URLS[$sub_path]="$url"
  done
}
# 打印修复前状态，让用户看清楚 Git 输出和磁盘真实情况的差异。
print_preflight_report() {
  local sub_path=""

  bold_echo "父 Git 仓库：${PARENT_REPO_DIR}"
  bold_echo "脚本路径：${SCRIPT_PATH}"
  bold_echo "日志文件：${LOG_FILE}"
  echo ""

  highlight_echo "============================== 当前真实子 Git 目录 =============================="
  for sub_path in "${CURRENT_SUBGIT_DIRS[@]}"; do
    note_echo "${sub_path} -> ${SUBMODULE_URLS[$sub_path]}"
  done
  highlight_echo "==============================================================================="
  echo ""

  highlight_echo "============================== 当前 git status =============================="
  if ! git -C "$PARENT_REPO_DIR" status --short 2>&1 | tee -a "$LOG_FILE"; then
    warn_echo "普通 git status 当前失败，脚本会继续按磁盘真实子 Git 目录修复。"
  fi
  highlight_echo "==========================================================================="
}
# 将旧 gitdir 元数据移动或指向当前目录名对应的位置。
repair_subgit_gitdir_pointer() {
  local sub_path="$1"
  local sub_dir="${PARENT_REPO_DIR}/${sub_path}"
  local git_marker="${sub_dir}/.git"
  local desired_relative="../.git/modules/${sub_path}"
  local desired_module_dir=""
  local current_gitdir=""
  local current_module_dir=""
  local url="${SUBMODULE_URLS[$sub_path]}"

  desired_module_dir="$(module_dir_for_path "$sub_path")"
  mkdir -p "${PARENT_REPO_DIR}/.git/modules"

  if [[ -f "$git_marker" ]]; then
    current_gitdir="$(sed -n 's/^gitdir:[[:space:]]*//p' "$git_marker" | head -n 1)"
    if [[ -n "$current_gitdir" ]]; then
      [[ "$current_gitdir" != /* ]] && current_gitdir="${sub_dir}/${current_gitdir}"
      current_module_dir="$(normalize_existing_path "$current_gitdir")"
      if [[ "$current_module_dir" != "$desired_module_dir" && -d "$current_module_dir" && ! -e "$desired_module_dir" ]]; then
        info_echo "迁移 gitdir：${current_module_dir} -> ${desired_module_dir}"
        mv "$current_module_dir" "$desired_module_dir"
      fi
    fi
    print -r -- "gitdir: ${desired_relative}" > "$git_marker"
  fi

  if [[ -d "$desired_module_dir" ]]; then
    git --git-dir="$desired_module_dir" --work-tree="$sub_dir" config core.worktree "../../../${sub_path}" >/dev/null 2>&1 || true
    git --git-dir="$desired_module_dir" --work-tree="$sub_dir" config remote.origin.url "$url" >/dev/null 2>&1 || true
  fi
}
# 按当前真实子 Git 目录重写 .gitmodules。
rewrite_gitmodules() {
  local tmp_file=""
  local sub_path=""

  tmp_file="$(mktemp)"
  for sub_path in "${CURRENT_SUBGIT_DIRS[@]}"; do
    {
      printf '[submodule "%s"]\n' "$sub_path"
      printf '\tpath = %s\n' "$sub_path"
      printf '\turl = %s\n' "${SUBMODULE_URLS[$sub_path]}"
      printf '\tbranch = main\n'
    } >> "$tmp_file"
  done

  mv "$tmp_file" "${PARENT_REPO_DIR}/.gitmodules"
  success_echo "已按当前真实子 Git 目录重写 .gitmodules。"
}
# 清理父仓库索引里已经不存在于磁盘当前子 Git 目录的旧 gitlink。
remove_stale_gitlinks_from_index() {
  local gitlink=""

  while IFS= read -r gitlink; do
    [[ -z "$gitlink" ]] && continue
    if ! array_contains "$gitlink" "${CURRENT_SUBGIT_DIRS[@]}"; then
      warn_echo "移除旧 gitlink（只移出父仓库索引，不删除磁盘文件）：${gitlink}"
      git -C "$PARENT_REPO_DIR" rm --cached --ignore-unmatch -- "$gitlink"
    fi
  done < <(git -C "$PARENT_REPO_DIR" ls-files -s | awk '$1 == "160000" {print $4}' | sort)
}
# 暂存当前真实子 Git 目录，使父仓库 gitlink 和磁盘形态一致。
stage_current_gitlinks() {
  local sub_path=""

  git -C "$PARENT_REPO_DIR" add .gitmodules
  remove_stale_gitlinks_from_index

  for sub_path in "${CURRENT_SUBGIT_DIRS[@]}"; do
    git -C "$PARENT_REPO_DIR" add -- "$sub_path"
  done
}
# 把普通嵌套 Git 吸收到父仓库 .git/modules 下，形成标准子模块元数据。
absorb_gitdirs_if_needed() {
  local sub_path=""

  for sub_path in "${CURRENT_SUBGIT_DIRS[@]}"; do
    git -C "$PARENT_REPO_DIR" submodule absorbgitdirs -- "$sub_path" >/dev/null 2>&1 || true
  done
}
# 清理本地 .git/config 里已经不属于当前目录形态的旧 submodule section。
clean_local_submodule_config() {
  local key=""
  local section=""

  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    section="${key#submodule.}"
    section="${section%.url}"
    if ! array_contains "$section" "${CURRENT_SUBGIT_DIRS[@]}"; then
      warn_echo "清理本地旧 submodule 配置：${section}"
      git -C "$PARENT_REPO_DIR" config --remove-section "submodule.${section}" 2>/dev/null || true
    fi
  done < <(git -C "$PARENT_REPO_DIR" config --name-only --get-regexp '^submodule\..*\.url$' 2>/dev/null || true)
}
# 重新注册并同步当前 .gitmodules 到本地 Git 配置。
sync_submodule_config() {
  git -C "$PARENT_REPO_DIR" submodule init
  git -C "$PARENT_REPO_DIR" submodule sync --recursive
}
# 对齐每个子 Git 的模块目录和远端地址。
repair_all_subgit_metadata() {
  local sub_path=""

  for sub_path in "${CURRENT_SUBGIT_DIRS[@]}"; do
    repair_subgit_gitdir_pointer "$sub_path"
  done
}
# 校验磁盘目录、.gitmodules 和父仓库 gitlink 三者是否完全一致。
verify_alignment() {
  local current_file=""
  local modules_file=""
  local gitlinks_file=""
  local diff_modules=""
  local diff_gitlinks=""

  current_file="$(mktemp)"
  modules_file="$(mktemp)"
  gitlinks_file="$(mktemp)"

  printf '%s\n' "${CURRENT_SUBGIT_DIRS[@]}" | sort > "$current_file"
  git -C "$PARENT_REPO_DIR" config -f .gitmodules --get-regexp 'submodule\..*\.path' 2>/dev/null | awk '{print $2}' | sort > "$modules_file"
  git -C "$PARENT_REPO_DIR" ls-files -s | awk '$1 == "160000" {print $4}' | sort > "$gitlinks_file"

  diff_modules="$(comm -3 "$current_file" "$modules_file" || true)"
  diff_gitlinks="$(comm -3 "$current_file" "$gitlinks_file" || true)"

  rm -f "$current_file" "$modules_file" "$gitlinks_file"

  if [[ -n "$diff_modules" ]]; then
    error_echo ".gitmodules 和磁盘真实子 Git 目录仍不一致："
    err_echo "$diff_modules"
    return 1
  fi

  if [[ -n "$diff_gitlinks" ]]; then
    error_echo "父仓库 gitlink 和磁盘真实子 Git 目录仍不一致："
    err_echo "$diff_gitlinks"
    return 1
  fi

  success_echo "磁盘真实子 Git 目录、.gitmodules、父仓库 gitlink 已完全一致。"
}
# 打印修复后的 Git 状态和子模块状态。
print_final_report() {
  highlight_echo "============================== 修复后 git submodule status =============================="
  git -C "$PARENT_REPO_DIR" submodule status --recursive 2>&1 | tee -a "$LOG_FILE" || true
  highlight_echo "======================================================================================"
  echo ""

  highlight_echo "============================== 修复后 git status =============================="
  git -C "$PARENT_REPO_DIR" status --short 2>&1 | tee -a "$LOG_FILE" || true
  highlight_echo "============================================================================="
}
# 真实修复流程：以磁盘目录为基准重建子模块元数据。
run_business() {
  print_preflight_report
  echo ""
  warn_echo "本脚本会修改 .gitmodules、父仓库索引中的 gitlink、本地 .git/config 和子目录 .git 指针。"
  gray_echo "不会删除当前磁盘上的子 Git 目录；旧 gitlink 只会执行 git rm --cached。"
  echo ""

  if ! ask_enter_to_run "确认按当前磁盘子 Git 目录对齐父 Git 子模块吗？"; then
    warn_echo "用户选择跳过修复。"
    return 0
  fi

  repair_all_subgit_metadata
  rewrite_gitmodules
  stage_current_gitlinks
  absorb_gitdirs_if_needed
  repair_all_subgit_metadata
  clean_local_submodule_config
  sync_submodule_config
  verify_alignment
  print_final_report
}
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  set -e
  setopt NO_NOMATCH
  set -o pipefail
  if [[ "$SCRIPT_SOURCE" != /* ]]; then
    SCRIPT_SOURCE="${PWD}/${SCRIPT_SOURCE}"
  fi
  : > "$LOG_FILE"
}
# 编排脚本的高层业务流程。
main() {
  show_script_intro_and_wait # 展示脚本内置自述，并按运行入口完成防误触确认。
  initialize_script_runtime # 初始化 Shell 选项、日志、依赖和入口运行状态。
  check_environment # 检查当前环境与执行条件是否满足脚本要求。
  discover_current_subgit_dirs # 扫描父仓库第一层真实存在的子 Git 目录。
  collect_submodule_urls # 收集每个真实子 Git 的远端地址。
  run_business # 执行以磁盘目录为基准的子模块对齐流程。
}

main "$@"
