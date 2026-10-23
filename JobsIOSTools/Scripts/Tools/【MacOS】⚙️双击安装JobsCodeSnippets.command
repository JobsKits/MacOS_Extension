#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】⚙️双击安装JobsCodeSnippets.command
# - 核心用途：检查当前用户 Xcode CodeSnippets，缺失时安装，已有 Git 仓库时保留本地改动并升级。
# - 影响范围：仅当前用户 CodeSnippets 与同级私有备份；不自动 commit、push 或重启 Xcode。
# - 运行提示：先回车确认自述，再输入任意字符执行；--finder 接收 iOS 工程，--check 只读检查。
# shell: zsh

SCRIPT_DIR=""
SCRIPT_PATH=""
CODE_SNIPPETS_PATH=""
LOG_FILE=""
RUN_MODE="normal"
PROJECT_DIR=""
TRANSACTION_DIR=""
LOCK_DIR=""
LOCK_HELD=0
SWAP_STARTED=0
COLOR_OUTPUT=0
ACTION_APPROVED=0
REPO_URLS=(https://github.com/JobsKits/JobsCodeSnippets.git https://gitee.com/JobsGo/jobs-code-snippetsJobsCodeSnippets.git)

# 只初始化进程内路径；--check 不创建文件或修改 Git 索引缓存。
configure_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  SCRIPT_DIR="${${(%):-%x}:A:h}"
  SCRIPT_PATH="$SCRIPT_DIR/${0:t}"
  CODE_SNIPPETS_PATH="$HOME/Library/Developer/Xcode/UserData/CodeSnippets"
  LOG_FILE="${TMPDIR:-/tmp}/JobsCodeSnippets-$(date +%Y%m%d-%H%M%S)-$$.log"
  if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" ]]; then
    COLOR_OUTPUT=1
  fi
  case "${1:-}" in
    --check|--help) RUN_MODE="${1#--}"; [[ $# == 1 ]] ;;
    --finder) RUN_MODE=finder; PROJECT_DIR="${2:-}"; [[ $# == 2 && -n "$PROJECT_DIR" ]] ;;
    "") [[ $# == 0 ]] ;;
    *) return 1 ;;
  esac
}
# 按终端能力显示纯文本或指定颜色。
display_line() {
  local tone="$1" message="$2"
  if (( COLOR_OUTPUT )); then
    print -r -- $'\e['"${tone}m${message}"$'\e[0m'
  else
    print -r -- "$message"
  fi
}
# 终端与独立日志同步记录业务结果。
log_message() {
  local tone="$1" message="$2"
  display_line "$tone" "$message"
  print -r -- "$message" >> "$LOG_FILE"
}
# 自述先于任何真实业务，普通动作的空输入一律跳过。
show_script_intro_and_wait() {
  configure_runtime "$@" || { print -u2 -r -- '用法：脚本 [--check | --finder <iOS工程路径> | --help]'; exit 2; }
  display_line '1;31' '================ JobsCodeSnippets 安装 / 升级 ================'
  display_line '0;34' "1、目标：$CODE_SNIPPETS_PATH"
  display_line '0;34' '2、缺失时安装；已有仓库时保存暂存、未暂存和未跟踪内容，再拉取合并。'
  display_line '0;34' '3、不自动生成提交或推送；冲突恢复原状，保留副本供手动合并。'
  display_line '0;34' '4、仅操作当前用户代码片段；成功后需要自行重新打开 Xcode。'
  display_line '0;34' "日志：$LOG_FILE（--check / --help 不写日志）"
  display_line '0;34' '取消：按 Ctrl+C；执行选择直接回车跳过。'
  [[ "$RUN_MODE" != check && "$RUN_MODE" != help ]] || return 0
  [[ -t 0 ]] || { print -u2 -r -- '✖ 请在可交互 Terminal 中运行。'; exit 1; }
  local answer=""
  read -r '?已了解用途与影响，按回车继续；Ctrl+C 取消：' answer || exit 1
  read -r '?安装 / 升级：直接回车跳过；输入任意字符后回车执行：' answer || exit 1
  [[ -n "$answer" ]] && ACTION_APPROVED=1
  return 0
}
# 忽略调用者的 Git 仓库定位变量，防止从工程右键时误操作项目仓库。
snippet_git() {
  local repo="$1"
  shift
  (
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
    export GIT_OPTIONAL_LOCKS=0 GIT_TERMINAL_PROMPT=0
    export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=10}"
    command git -C "$repo" -c core.hooksPath=/dev/null -c gc.auto=0 -c maintenance.auto=false \
      -c merge.autostash=false -c rerere.enabled=false "$@"
  )
}
# 保留 Git 退出码并过滤输出中的 URL 敏感信息。
run_git() {
  snippet_git "$@" 2>&1 | sed -E 's#(https?://)[^/@[:space:]]+@#\1[REDACTED]@#g; s#(https?://[^?#[:space:]]+)[?#][^[:space:]]*#\1[REDACTED]#g' | tee -a "$LOG_FILE"
}
# 只脱敏展示副本，不改动真实传输地址。
redact_url() {
  print -r -- "$1" | sed -E 's#(https?://)[^/@]+@#\1[REDACTED]@#g; s#[?#].*$##'
}
# 在传输前突出来源、分支和实际安装位置。
show_source() {
  local repo="$1" configured="$2" branch="${3:-远端默认分支}" actual
  actual="$(snippet_git "$repo" ls-remote --get-url "$configured")" || return 1
  log_message '1;36' '━━━━━━━━━━ 来源｜JobsCodeSnippets ━━━━━━━━━━'
  log_message '1;36' "配置来源：$(redact_url "$configured")"
  log_message '1;36' "生效地址：$(redact_url "$actual")（本地 Git 规则展开）"
  log_message '1;36' "分支：$branch"
  log_message '1;36' "目标：$CODE_SNIPPETS_PATH"
}
# 工程仅负责决定菜单资格，不作为代码片段安装位置。
validate_finder_project() {
  [[ "$RUN_MODE" == finder ]] || return 0
  local item="$PROJECT_DIR" candidate
  [[ -d "$item" && ! -L "$item" && "${item:A}" != "${HOME:A}/Desktop" ]] || return 1
  if [[ "$item" == *.xcodeproj && -f "$item/project.pbxproj" ]] ||
     [[ "$item" == *.xcworkspace && -f "$item/contents.xcworkspacedata" ]]; then
    return 0
  fi
  [[ -f "$item/Package.swift" || -f "$item/Podfile" ]] && return 0
  for candidate in "$item"/*(ND); do
    if [[ -d "$candidate" && ( "${candidate:e:l}" == xcodeproj || "${candidate:e:l}" == xcworkspace ) ]] ||
       [[ -f "$candidate" && "${candidate:e}" == podspec ]]; then
      return 0
    fi
  done
  return 1
}
# 只接管独立安装仓，外部元数据 / 未完成操作交给人工处理。
validate_installed_repo() {
  local repo="$1" marker root
  [[ -d "$repo/.git" && ! -L "$repo" && ! -L "$repo/.git" ]] || return 1
  root="$(snippet_git "$repo" rev-parse --show-toplevel)" || return 1
  [[ "${root:A}" == "${repo:A}" ]] || return 1
  snippet_git "$repo" rev-parse --verify HEAD >/dev/null || return 1
  snippet_git "$repo" symbolic-ref -q HEAD >/dev/null || return 1
  [[ -z "$(snippet_git "$repo" config --get core.worktree)" ]] || return 1
  [[ ! -e "$repo/.git/objects/info/alternates" && ! -e "$repo/.git/commondir" && ! -e "$repo/.git/worktrees" ]] || return 1
  [[ -z "$(find "$repo/.git" -type l -print -quit)" ]] || return 1
  [[ -z "$(find "$repo/.git" -name '*.lock' -print -quit)" ]] || return 1
  for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply sequencer index.lock; do
    [[ ! -e "$repo/.git/$marker" ]] || return 1
  done
  [[ -z "$(snippet_git "$repo" ls-files --unmerged)" ]] || return 1
  [[ -z "$(snippet_git "$repo" ls-files -v | awk '/^[a-zS] / { print; exit }')" ]] || return 1
  [[ -z "$(snippet_git "$repo" ls-files --debug | awk '/flags: / && $NF != "0" { print; exit }')" ]] || return 1
  [[ -z "$(snippet_git "$repo" ls-files --stage | awk '$1 == "160000" { print; exit }')" ]] || return 1
}
# 检查实际依赖与 Finder 项目边界，失败即停止入口。
check_environment() {
  command -v git >/dev/null && git --version >/dev/null || { print -u2 -r -- '✖ Git / Xcode Command Line Tools 不可用，请先修复开发工具。'; exit 1; }
  validate_finder_project || { print -u2 -r -- '✖ 请选择有效的 iOS / Xcode 工程或工程目录。'; exit 1; }
}
# 只读报告当前安装形态，未知目录不接管。
report_state() {
  if [[ "$RUN_MODE" == help ]]; then
    print -r -- '参数：--check 只读检查安装位置；--finder <工程路径> 供 iOS 右键菜单调用。'
    return 0
  fi
  if [[ ! -e "$CODE_SNIPPETS_PATH" && ! -L "$CODE_SNIPPETS_PATH" ]]; then
    print -r -- 'ℹ 尚未安装，将克隆到当前用户 CodeSnippets 目录。'
  elif validate_installed_repo "$CODE_SNIPPETS_PATH"; then
    print -r -- '✔ 已安装，将按当前分支明确配置的上游升级。'
    snippet_git "$CODE_SNIPPETS_PATH" status --short
  elif [[ -d "$CODE_SNIPPETS_PATH" && ! -L "$CODE_SNIPPETS_PATH" && -z "$(ls -A "$CODE_SNIPPETS_PATH")" ]]; then
    print -r -- 'ℹ CodeSnippets 为空，将安装。'
  else
    print -u2 -r -- "✖ 目标不是可安全升级的独立 Git 仓库，或有未完成操作；原内容保留：$CODE_SNIPPETS_PATH"
    exit 1
  fi
}
# 只释放当前进程成功获取的空锁目录。
release_lock() {
  if (( LOCK_HELD )); then
    rmdir "$LOCK_DIR" 2>/dev/null || print -u2 -r -- "⚠ 请检查本次锁：$LOCK_DIR"
    LOCK_HELD=0
  fi
}
# 发布中断时恢复被移开的旧目录，始终保留备份。
handle_interrupt() {
  trap '' INT TERM HUP
  if (( SWAP_STARTED )) && [[ ! -e "$CODE_SNIPPETS_PATH" && ! -L "$CODE_SNIPPETS_PATH" && -d "$TRANSACTION_DIR/previous" ]]; then
    mv "$TRANSACTION_DIR/previous" "$CODE_SNIPPETS_PATH" || print -u2 -r -- "✖ 恢复失败，请从 $TRANSACTION_DIR/previous 恢复。"
  fi
  print -u2 -r -- "⚠ 操作中断；原始备份 / 候选副本：${TRANSACTION_DIR:-尚未创建}"
  release_lock
  exit 130
}
# 取得固定目标锁并建立私有完整快照。
prepare_transaction() {
  local parent="${CODE_SNIPPETS_PATH:h}"
  mkdir -p "$parent" || return 1
  LOCK_DIR="$parent/.JobsCodeSnippets.lock"
  mkdir "$LOCK_DIR" 2>/dev/null || { log_message '1;31' "✖ 已有操作或遗留锁：$LOCK_DIR；确认没有运行后再人工移除空锁目录。"; return 1; }
  LOCK_HELD=1
  trap release_lock EXIT
  trap handle_interrupt INT TERM HUP
  TRANSACTION_DIR="$(umask 077; mktemp -d "$parent/.JobsCodeSnippets.XXXXXXXX")" || return 1
  if [[ -d "$CODE_SNIPPETS_PATH" ]]; then
    cp -pR "$CODE_SNIPPETS_PATH" "$TRANSACTION_DIR/original" || return 1
  fi
  log_message '0;35' "➤ 事务与原始备份：$TRANSACTION_DIR"
}
# 在完整副本上拉取及合并，分别恢复工作区和原暂存部分。
update_candidate() {
  local repo="$TRANSACTION_DIR/candidate" branch remote merge_ref url saved_stash=""
  cp -pR "$TRANSACTION_DIR/original" "$repo" || return 1
  validate_installed_repo "$repo" || return 1
  branch="$(snippet_git "$repo" symbolic-ref --short HEAD)" || return 1
  remote="$(snippet_git "$repo" config --get "branch.$branch.remote")" || return 1
  merge_ref="$(snippet_git "$repo" config --get "branch.$branch.merge")" || return 1
  [[ -n "$remote" && "$remote" != . && "$merge_ref" == refs/heads/* && "$merge_ref" != *$'\n'* ]] || return 1
  url="$(snippet_git "$repo" remote get-url "$remote")" || return 1
  show_source "$repo" "$url" "${merge_ref#refs/heads/}" || return 1
  if [[ -n "$(snippet_git "$repo" status --porcelain=v1 --untracked-files=all)" ]]; then
    log_message '0;34' 'ℹ 在候选副本保存暂存区、未暂存及未跟踪内容，不向分支生成提交。'
    run_git "$repo" stash push --include-untracked -m 'JobsCodeSnippets update safety' || return 1
    saved_stash="$(snippet_git "$repo" rev-parse refs/stash)" || return 1
    [[ -z "$(snippet_git "$repo" status --porcelain=v1 --untracked-files=all)" ]] || return 1
  fi
  run_git "$repo" fetch --no-tags -- "$remote" "$merge_ref" || return 1
  run_git "$repo" merge --ff --no-commit --no-edit --no-autostash --no-overwrite-ignore FETCH_HEAD || return 1
  if [[ -n "$saved_stash" ]]; then
    # 分叉合并已有暂存结果，plain apply 恢复工作区，再单独三方恢复原暂存部分。
    cp -p "$repo/.git/index" "$TRANSACTION_DIR/merged.index" || return 1
    snippet_git "$repo" diff --binary --full-index --no-ext-diff --no-textconv "$saved_stash^1" "$saved_stash^2" > "$TRANSACTION_DIR/staged.patch" || return 1
    run_git "$repo" stash apply "$saved_stash" || return 1
    cp -p "$TRANSACTION_DIR/merged.index" "$repo/.git/index" || return 1
    if [[ -s "$TRANSACTION_DIR/staged.patch" ]]; then
      run_git "$repo" apply --3way --cached "$TRANSACTION_DIR/staged.patch" || return 1
    fi
    [[ "$(snippet_git "$repo" rev-parse refs/stash)" == "$saved_stash" ]] || return 1
    run_git "$repo" stash drop 'stash@{0}' || return 1
  fi
  [[ -z "$(snippet_git "$repo" ls-files --unmerged)" ]] || return 1
  if [[ -f "$repo/.git/MERGE_HEAD" ]]; then
    log_message '1;33' '⚠ 分支存在分叉，已合并到暂存区且未生成 commit；请自行审阅并提交后再升级。'
  fi
  log_message '1;32' "✔ 已取得来源 $(redact_url "$url")；候选 HEAD：$(snippet_git "$repo" rev-parse --short HEAD)"
}
# 首次安装按明确来源依次尝试，失败目录单独保留。
install_candidate() {
  local url attempt=0 destination
  for url in "${REPO_URLS[@]}"; do
    (( attempt += 1 ))
    destination="$TRANSACTION_DIR/clone-$attempt"
    show_source "${CODE_SNIPPETS_PATH:h}" "$url" || return 1
    if run_git "${CODE_SNIPPETS_PATH:h}" clone --no-hardlinks -- "$url" "$destination"; then
      mv "$destination" "$TRANSACTION_DIR/candidate" || return 1
      log_message '1;32' "✔ 克隆成功，来源：$(redact_url "$url")"
      return 0
    fi
    log_message '1;33' "⚠ 克隆失败，保留失败副本，尝试下一来源：$(redact_url "$url")"
  done
  return 1
}
# 记录权限、归属、修改时间与链接本体，路径用 NUL 分隔。
record_metadata() {
  local root="$1" output="$2" item metadata
  (
    for item in "$root" "$root"/**/*(DN); do
      metadata="$(stat -f '%p:%u:%g:%m' "$item")" || return 1
      printf '%s\0%s\0' "${item#$root}" "$metadata"
      if [[ -L "$item" ]]; then
        readlink "$item" || return 1
      fi
      printf '\0'
    done
  ) > "$output"
}
# 逐个比较普通文件，避免递归 diff 解引用符号链接。
compare_original_files() {
  local original="$TRANSACTION_DIR/original" item relative
  for item in "$original"/**/*(DN); do
    [[ ! -L "$item" && -f "$item" ]] || continue
    relative="${item#$original/}"
    cmp -s "$item" "$CODE_SNIPPETS_PATH/$relative" || return 1
  done
}
# 内容、权限和链接目标均无变化才允许发布候选。
publish_candidate() {
  if [[ -d "$TRANSACTION_DIR/original" ]]; then
    record_metadata "$CODE_SNIPPETS_PATH" "$TRANSACTION_DIR/current.metadata" || return 1
    record_metadata "$TRANSACTION_DIR/original" "$TRANSACTION_DIR/original.metadata" || return 1
    if ! compare_original_files ||
       ! cmp -s "$TRANSACTION_DIR/current.metadata" "$TRANSACTION_DIR/original.metadata"; then
      log_message '1;31' '✖ 原目录在操作期间发生变化，保留双方副本，停止替换。'
      return 1
    fi
    SWAP_STARTED=1
    mv "$CODE_SNIPPETS_PATH" "$TRANSACTION_DIR/previous" || return 1
  elif [[ -e "$CODE_SNIPPETS_PATH" || -L "$CODE_SNIPPETS_PATH" ]]; then
    return 1
  fi
  if [[ -e "$CODE_SNIPPETS_PATH" || -L "$CODE_SNIPPETS_PATH" ]] || ! mv -n "$TRANSACTION_DIR/candidate" "$CODE_SNIPPETS_PATH" || [[ -e "$TRANSACTION_DIR/candidate" ]]; then
    if (( SWAP_STARTED )) && [[ ! -e "$CODE_SNIPPETS_PATH" && ! -L "$CODE_SNIPPETS_PATH" ]]; then
      mv "$TRANSACTION_DIR/previous" "$CODE_SNIPPETS_PATH" || log_message '1;31' "✖ 请手动从 $TRANSACTION_DIR/previous 恢复目标。"
    fi
    return 1
  fi
  SWAP_STARTED=0
  log_message '1;32' "✔ 安装 / 升级完成：$CODE_SNIPPETS_PATH"
  log_message '0;35' "➤ 原始备份保留在：$TRANSACTION_DIR；请自行重新打开 Xcode。"
}
# 确认后编排事务并将失败状态传回调用方。
run_business() {
  [[ "$RUN_MODE" != check && "$RUN_MODE" != help && "$ACTION_APPROVED" == 1 ]] || return 0
  LOG_FILE="$(umask 077; mktemp "${LOG_FILE%.log}.XXXXXXXX.log")" || return 1
  display_line '0;35' "➤ 实际日志：$LOG_FILE"
  prepare_transaction || return 1
  if [[ -d "$TRANSACTION_DIR/original/.git" ]]; then
    update_candidate || { log_message '1;31' "✖ 拉取或合并失败，安装目录与暂存区保持更新前原状。请手动合并；失败副本与 stash：$TRANSACTION_DIR/candidate；日志：$LOG_FILE"; return 1; }
  else
    install_candidate || { log_message '1;31' "✖ 安装失败，原目录保留。日志：$LOG_FILE"; return 1; }
  fi
  publish_candidate || return 1
}
# 入口只编排说明、自检、安装状态和真实业务。
main() {
  show_script_intro_and_wait "$@" # 展示内置自述，解析只读与 Finder 入口并确认动作。
  check_environment # 检查 Git 健康与 Finder 项目边界。
  report_state # 对齐当前用户实际安装目录并报告安全状态。
  run_business # 在隔离副本安装或升级，成功后发布并保留备份。
}

main "$@"
