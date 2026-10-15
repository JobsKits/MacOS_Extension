#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】🧾更新gitmodules.command
# - 核心用途：发现直属子 Git，一次完成 .gitmodules、gitlink、本地登记与元数据归集。
# - 影响范围：增量暂存关联配置与新 gitlink；保留源码、既有指针、远端和其它暂存内容，不提交、不推送。
# - 运行提示：先回车查看计划；计划后回车跳过、输入任意字符执行；--dry-run 仅预览。
# shell: zsh

SCRIPT_FILE="${(%):-%x}"
SCRIPT_DIR=""
SCRIPT_PATH=""
LOG_FILE=""
REPO_ROOT=""
PARENT_GIT_DIR=""
MODULES_FILE=""
PLAN_DIR=""
PLAN_FILE=""
BACKUP_DIR=""
LOCK_DIR=""
LOCK_OWNED=0
MUTATING=0
CLEANED=0
DRY_RUN="${DRY_RUN:-0}"
PHASE="初始化"
INDEX_BEFORE=""
CONFIG_BEFORE=""
MODULES_BEFORE=""
MODULES_INDEXED=0
typeset -ga CHILDREN WORK_ITEMS ISSUES
typeset -gA SECTION_NAMES SECTION_PATHS CHILD_HEADS CHILD_URLS CHILD_BRANCHES
typeset -gA CHILD_GIT_DIRS CHILD_MODES NEED_GITLINK NEED_ABSORB

# 渲染自述的红色标题与蓝色正文，非彩色终端保留纯文本。
intro_line() {
  local role="$1" message="$2" color="0;34"
  [[ "$role" == title ]] && color="1;31"
  if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" ]]; then
    printf '\033[%sm%s\033[0m\n' "$color" "$message"
  else
    print -r -- "$message"
  fi
}
# 在任何实际操作前展示固定说明，help / dry-run 可作为非交互只读入口。
show_script_intro_and_wait() {
  local argument="" answer=""
  SCRIPT_DIR="${SCRIPT_FILE:A:h}"
  SCRIPT_PATH="${SCRIPT_DIR}/${SCRIPT_FILE:t}"
  LOG_FILE="${TMPDIR:-/tmp}"
  LOG_FILE="${LOG_FILE%/}/【MacOS】🧾更新gitmodules.$$.log"
  intro_line title '【MacOS】🧾更新gitmodules.command · 父子 Git 一次关联'
  intro_line body '1、只扫描目标父仓第一层真实子 Git，补齐配置、gitlink、本地登记和 Git 元数据归集。'
  intro_line body '2、保留已有 URL、分支、提交指针和其它暂存内容；保留源码，不联网、不提交、不推送。'
  intro_line body '3、先预检并展示计划；回车跳过，输入任意字符后回车执行完整关联。'
  intro_line body '4、执行前在父仓实际 Git 目录内备份关联配置和索引；失败停止并显示阶段和恢复位置。'
  intro_line body "日志：${LOG_FILE}；--dry-run / DRY_RUN=1 只预览，Ctrl+C 取消。"
  for argument in "$@"; do
    case "$argument" in
      --help|-h) print -r -- '用法：脚本 [--dry-run]；脚本放在仓库根目录或其直属同名脚本目录。'; exit 0 ;;
      --dry-run) DRY_RUN=1 ;;
      *) print -u2 -r -- "未知参数：${argument}"; exit 1 ;;
    esac
  done
  [[ "$DRY_RUN" == 0 || "$DRY_RUN" == 1 ]] || { print -u2 -- 'DRY_RUN 只能为 0 或 1。'; exit 1; }
  [[ "$DRY_RUN" == 1 ]] && return 0
  [[ -t 0 ]] || { print -u2 -- '没有可交互输入，请在终端运行，或使用 --dry-run。'; exit 1; }
  IFS= read -r 'answer?已了解影响范围，按回车查看计划；Ctrl+C 取消：' || exit 1
}
# 统一输出到终端和日志，不把用户路径当作转义序列执行。
log() {
  print -r -- "$*" | tee -a "$LOG_FILE"
}
# 输出失败原因，让主流程在对应步骤立即停止。
fail() {
  log "✖ $*"
  return 1
}
# 只移除当前进程创建的临时文件和锁，不自动回滚其它 Git 操作。
cleanup() {
  local result="${1:-0}"
  if (( CLEANED )); then return 0; fi
  CLEANED=1
  if (( result != 0 )); then
    print -u2 -r -- "✖ 已停止，阶段：${PHASE}；日志：${LOG_FILE}"
    if (( MUTATING )); then
      print -u2 -r -- "部分关联操作可能已完成，请核对 git status；备份：${BACKUP_DIR}"
    fi
  fi
  if (( LOCK_OWNED )); then
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
  if [[ -n "$PLAN_DIR" && -d "$PLAN_DIR" ]]; then
    rm -f -- "$PLAN_DIR/gitmodules" "$PLAN_DIR/index-gitmodules" "$PLAN_DIR/index-entries"
    rmdir "$PLAN_DIR" 2>/dev/null || true
  fi
  return 0
}
# 在脚本整体退出时清理；zsh 函数内的 EXIT trap 会过早触发，不能在初始化函数中注册。
TRAPEXIT() {
  local exit_code=$?
  cleanup "$exit_code"
  return "$exit_code"
}
# zsh 的 ERR_EXIT 在函数返回失败时可能跳过 EXIT trap，错误分支显式完成清理。
TRAPZERR() {
  local failure_code=$?
  cleanup "$failure_code"
  exit "$failure_code"
}
# 中断保留非零状态，让统一退出处理报告已完成阶段。
TRAPINT() {
  cleanup 130
  exit 130
}
# 终止保留非零状态，避免留下本进程创建的脚本锁。
TRAPTERM() {
  cleanup 143
  exit 143
}
# 确认后集中初始化运行选项、日志、进程状态和退出清理。
initialize_runtime() {
  set -e
  set -o pipefail
  setopt NO_NOMATCH
  export GIT_OPTIONAL_LOCKS=0 GIT_LITERAL_PATHSPECS=1 GIT_TERMINAL_PROMPT=0
  CHILDREN=(); WORK_ITEMS=(); ISSUES=()
  SECTION_NAMES=(); SECTION_PATHS=(); CHILD_HEADS=(); CHILD_URLS=(); CHILD_BRANCHES=()
  CHILD_GIT_DIRS=(); CHILD_MODES=(); NEED_GITLINK=(); NEED_ABSORB=()
  : > "$LOG_FILE"
}
# 为后续并发变更检测记录文件内容，不存在的文件使用独立标识。
file_checksum() {
  if [[ -f "$1" ]]; then
    cksum < "$1"
  else
    print -r -- absent
  fi
}
# 定位父仓并检查环境，拒绝继承外部 Git 定位变量或越界的配置文件。
check_environment() {
  local variable="" common="" candidate="" root=""
  PHASE="父仓预检"
  command -v git >/dev/null 2>&1 || { fail '未找到 Git。'; return 1; }
  git --version >/dev/null || return 1
  for variable in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR; do
    [[ -z "${(P)variable}" ]] || { fail "检测到 ${variable}，请在普通仓库终端运行。"; return 1; }
  done
  if [[ -e "$SCRIPT_DIR/.git" ]]; then
    candidate="$SCRIPT_DIR"
  elif [[ -e "${SCRIPT_DIR:h}/.git" ]]; then
    candidate="${SCRIPT_DIR:h}"
  else
    fail '脚本应位于父仓根目录，或其直属的同名脚本目录。'; return 1
  fi
  root="$(git -C "$candidate" rev-parse --show-toplevel)" || return 1
  REPO_ROOT="${root:A}"
  [[ "$REPO_ROOT" == "${candidate:A}" ]] || { fail '脚本目录不对应独立父仓根目录。'; return 1; }
  PARENT_GIT_DIR="$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir)" || return 1
  PARENT_GIT_DIR="${PARENT_GIT_DIR:A}"
  common="$(git -C "$REPO_ROOT" rev-parse --git-common-dir)" || return 1
  [[ "$common" == /* ]] || common="$REPO_ROOT/$common"
  [[ "${common:A}" == "$PARENT_GIT_DIR" ]] || { fail '父仓是链接工作树，请在主工作树完成关联。'; return 1; }
  MODULES_FILE="$REPO_ROOT/.gitmodules"
  [[ ! -L "$MODULES_FILE" && ( ! -e "$MODULES_FILE" || -f "$MODULES_FILE" ) ]] || { fail '.gitmodules 必须是普通文件。'; return 1; }
  [[ ! -e "$PARENT_GIT_DIR/index.lock" ]] || { fail 'Git 索引正在被其它操作占用。'; return 1; }
  [[ ! -L "$PARENT_GIT_DIR/index" && ! -L "$PARENT_GIT_DIR/config" ]] || { fail '索引或 Git 配置是符号链接，停止写入。'; return 1; }
  [[ ! -L "$PARENT_GIT_DIR/jobs-submodule-backups" && ( ! -e "$PARENT_GIT_DIR/jobs-submodule-backups" || -d "$PARENT_GIT_DIR/jobs-submodule-backups" ) ]] || { fail '关联备份目录不是父仓 Git 目录内的真实目录。'; return 1; }
  [[ -z "$(git -C "$REPO_ROOT" ls-files --unmerged)" ]] || { fail '父仓存在未解决的索引冲突。'; return 1; }
  if git -C "$REPO_ROOT" ls-files --error-unmatch -- .gitmodules >/dev/null 2>&1; then
    MODULES_INDEXED=1
    git -C "$REPO_ROOT" diff --quiet -- .gitmodules || { fail '.gitmodules 存在未暂存差异；请先处理该文件的暂存边界。'; return 1; }
  elif git -C "$REPO_ROOT" cat-file -e HEAD:.gitmodules 2>/dev/null; then
    fail '.gitmodules 已被暂存删除，保留该选择，请先处理暂存边界。'; return 1
  fi
  if [[ -f "$MODULES_FILE" ]]; then
    git config --file "$MODULES_FILE" --list >/dev/null || { fail '.gitmodules 语法无效。'; return 1; }
  fi
  PLAN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jobs-gitmodules.XXXXXXXX")" || return 1
  PLAN_FILE="$PLAN_DIR/gitmodules"
  if [[ -f "$MODULES_FILE" ]]; then cp -p "$MODULES_FILE" "$PLAN_FILE"; else : > "$PLAN_FILE"; fi
  INDEX_BEFORE="$(file_checksum "$PARENT_GIT_DIR/index")"
  CONFIG_BEFORE="$(file_checksum "$PARENT_GIT_DIR/config")"
  MODULES_BEFORE="$(file_checksum "$MODULES_FILE")"
  log "父仓：${REPO_ROOT}"
}
# 读取已有 section 与 path 映射，其它字段和暂时未检出的目录全部保留。
load_existing_modules() {
  local record="" key="" sub_path="" section=""
  PHASE="读取已有登记"
  [[ -f "$MODULES_FILE" ]] || return 0
  while IFS= read -r -d '' record; do
    key="${record%%$'\n'*}"; sub_path="${record#*$'\n'}"
    section="${key#submodule.}"; section="${section%.path}"
    [[ -n "$sub_path" && -n "$section" ]] || { fail '.gitmodules 的 path 或 section 为空。'; return 1; }
    if [[ -n "${SECTION_NAMES[$sub_path]:-}" || -n "${SECTION_PATHS[$section]:-}" ]]; then
      fail ".gitmodules 的 path 或 section 重复：${sub_path}"; return 1
    fi
    SECTION_NAMES[$sub_path]="$section"
    SECTION_PATHS[$section]="$sub_path"
  done < <(git config --null --file "$MODULES_FILE" --get-regexp '^submodule\..*\.path$' || true)
}
# 判断名称是否适合用作子模块名称，防止 Git 元数据路径穿越。
valid_name() {
  local value="$1"
  [[ -n "$value" && "$value" != /* && "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *$'\t'* && "$value" != *\\* ]] || return 1
  [[ "/$value/" != */../* && "/$value/" != */./* && "$value" != -* ]]
}
# 只接受已配置的普通 Git 地址，不把带凭据 URL 写入共享配置和日志。
valid_url() {
  local value="$1" authority=""
  [[ -n "$value" && "$value" != -* && "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *$'\t'* && "$value" != *'::'* ]] || return 1
  if [[ "$value" == http://* || "$value" == https://* ]]; then
    authority="${value#*://}"; authority="${authority%%/*}"
    [[ "$authority" != *@* && "$value" != *\?* && "$value" != *\#* ]] || return 1
  elif [[ "$value" == ssh://* ]]; then
    authority="${value#*://}"; authority="${authority%%/*}"
    if [[ "$authority" == *@* ]]; then [[ "${authority%%@*}" != *:* ]] || return 1; fi
  fi
  return 0
}
# 预检单个子仓；任何冲突都在实际写入前收集并报告。
inspect_child() {
  local child="$1" sub_path="${1:t}" section="" top="" oid="" url="" stored_url="" branch=""
  local git_dir="" common="" target="" entry="" header="" mode="" entry_path=""
  local need_link=1 need_absorb=0 needs_work=0 ignored_result=0
  [[ ! -L "$child" && ! -L "$child/.git" ]] || { ISSUES+=("${sub_path}：工作目录或 .git 是符号链接"); return 0; }
  valid_name "$sub_path" || { ISSUES+=("${sub_path}：名称含不支持的控制字符或路径片段"); return 0; }
  top="$(git -C "$child" rev-parse --show-toplevel 2>/dev/null)" || { ISSUES+=("${sub_path}：无法读取独立仓库"); return 0; }
  [[ "${top:A}" == "${child:A}" ]] || { ISSUES+=("${sub_path}：不是独立子仓根目录"); return 0; }
  oid="$(git -C "$child" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" || { ISSUES+=("${sub_path}：没有可登记的 HEAD 提交"); return 0; }
  section="${SECTION_NAMES[$sub_path]:-$sub_path}"
  valid_name "$section" || { ISSUES+=("${sub_path}：section 不能安全映射到 modules 目录"); return 0; }
  if [[ -n "${SECTION_PATHS[$section]:-}" && "${SECTION_PATHS[$section]}" != "$sub_path" ]]; then
    ISSUES+=("${sub_path}：section 名已被其它路径占用"); return 0
  fi
  url="$(git config --file "$PLAN_FILE" --get "submodule.${section}.url" 2>/dev/null || true)"
  stored_url="$url"
  [[ -n "$url" ]] || url="$(git -C "$child" remote get-url origin 2>/dev/null || true)"
  valid_url "$url" || { ISSUES+=("${sub_path}：缺少可共享的 origin URL，或地址含凭据 / 不支持的协议"); return 0; }
  git_dir="$(git -C "$child" rev-parse --absolute-git-dir)" || return 1
  git_dir="${git_dir:A}"
  common="$(git -C "$child" rev-parse --git-common-dir)" || return 1
  [[ "$common" == /* ]] || common="$child/$common"
  [[ "${common:A}" == "$git_dir" ]] || { ISSUES+=("${sub_path}：链接工作树不作为普通子模块迁移"); return 0; }
  target="$PARENT_GIT_DIR/modules/$section"
  if [[ -L "$PARENT_GIT_DIR/modules" || "$target" != "${target:A}" ]]; then
    ISSUES+=("${sub_path}：目标 modules 路径含符号链接"); return 0
  fi
  if [[ "$git_dir" != "$target" ]]; then
    if [[ -e "$target" || -L "$target" ]]; then
      ISSUES+=("${sub_path}：目标 modules 元数据已存在，需先核对归属"); return 0
    fi
    if [[ ! -d "$child/.git" ]]; then
      ISSUES+=("${sub_path}：.git 指向外部元数据，需单独核对迁移边界"); return 0
    fi
    if [[ -d "$git_dir/worktrees" && -n "$(ls -A "$git_dir/worktrees")" ]]; then
      ISSUES+=("${sub_path}：元数据仍管理其它链接工作树"); return 0
    fi
    need_absorb=1
  fi
  git -C "$REPO_ROOT" ls-files --stage -z -- "$sub_path" > "$PLAN_DIR/index-entries" || return 1
  while IFS= read -r -d '' entry; do
    header="${entry%%$'\t'*}"; entry_path="${entry#*$'\t'}"; mode="${header%% *}"
    if [[ "$entry_path" != "$sub_path" || "$mode" != 160000 || "${header##* }" != 0 ]]; then
      ISSUES+=("${sub_path}：父仓已按普通文件跟踪该目录，或索引类型存在冲突"); return 0
    fi
    need_link=0
  done < "$PLAN_DIR/index-entries"
  if (( need_link )) && [[ -n "$(git -C "$REPO_ROOT" ls-tree HEAD -- "$sub_path" 2>/dev/null)" ]]; then
    ISSUES+=("${sub_path}：该路径已暂存删除，保留用户原有暂存选择"); return 0
  fi
  if (( need_link )); then
    if (unset GIT_LITERAL_PATHSPECS; git -C "$REPO_ROOT" check-ignore --quiet -- "$sub_path"); then
      ISSUES+=("${sub_path}：被父仓忽略规则排除，未强行登记"); return 0
    else
      ignored_result=$?
      (( ignored_result == 1 )) || { fail "${sub_path}：无法检查忽略规则"; return 1; }
    fi
  fi
  branch="$(git config --file "$PLAN_FILE" --get "submodule.${section}.branch" 2>/dev/null || true)"
  if [[ -z "$branch" && -z "${SECTION_NAMES[$sub_path]:-}" ]]; then
    branch="$(git -C "$child" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  fi
  if [[ -z "${SECTION_NAMES[$sub_path]:-}" ]]; then
    git config --file "$PLAN_FILE" "submodule.${section}.path" "$sub_path" || return 1
  fi
  if [[ -z "$stored_url" ]]; then
    git config --file "$PLAN_FILE" "submodule.${section}.url" "$url" || return 1
  fi
  if [[ -n "$branch" && -z "${SECTION_NAMES[$sub_path]:-}" ]]; then
    git config --file "$PLAN_FILE" "submodule.${section}.branch" "$branch" || return 1
  fi
  CHILDREN+=("$sub_path")
  SECTION_NAMES[$sub_path]="$section"; SECTION_PATHS[$section]="$sub_path"
  CHILD_HEADS[$sub_path]="$oid"; CHILD_URLS[$sub_path]="$url"; CHILD_BRANCHES[$sub_path]="$branch"
  CHILD_GIT_DIRS[$sub_path]="$git_dir"; NEED_GITLINK[$sub_path]=$need_link; NEED_ABSORB[$sub_path]=$need_absorb
  if (( need_link || need_absorb )); then needs_work=1; fi
  if ! git -C "$REPO_ROOT" config --get "submodule.${section}.url" >/dev/null; then needs_work=1; fi
  if (( needs_work )); then WORK_ITEMS+=("$sub_path"); fi
  return 0
}
# 仅扫描直属目录，跳过依赖、构建、供应商目录和软链接。
discover_and_plan() {
  local child="" name="" problem="" section="" other=""
  PHASE="子仓预检与计划"
  for child in "$REPO_ROOT"/*(DN/); do
    name="${child:t}"
    case "$name" in
      .git|node_modules|Pods|PodsManual|ManualBy*Pods@Pods|.dart_tool|build|DerivedData|dist|work|.venv|.venv-*|venv|vendor|third_party) continue ;;
    esac
    [[ -e "$child/.git" || -L "$child/.git" ]] || continue
    inspect_child "$child" || return 1
  done
  for name in "${CHILDREN[@]}"; do
    section="${SECTION_NAMES[$name]}"
    for other in "${(@k)SECTION_PATHS}"; do
      [[ "$section" == "$other" ]] && continue
      if [[ "$section/" == "$other/"* || "$other/" == "$section/"* ]]; then
        ISSUES+=("${name}：section ${section} 与 ${other} 的 modules 元数据路径重叠")
      fi
    done
  done
  if (( ${#ISSUES} )); then
    for problem in "${ISSUES[@]}"; do log "✖ ${problem}"; done
    fail '预检未通过，尚未修改父子仓配置、索引或元数据。'; return 1
  fi
}
# 展示完整计划；不删除旧登记，也不刷新已经存在的 gitlink 指针。
show_plan() {
  local sub_path=""
  PHASE="展示关联计划"
  log '========== 增量关联计划 =========='
  for sub_path in "${CHILDREN[@]}"; do
    log "${sub_path}：新增 gitlink=${NEED_GITLINK[$sub_path]}，归集元数据=${NEED_ABSORB[$sub_path]}；已有指针保留"
  done
  if [[ -f "$MODULES_FILE" ]]; then
    diff -u "$MODULES_FILE" "$PLAN_FILE" || [[ $? == 1 ]]
  else
    cat "$PLAN_FILE"
  fi
  log '旧 section、相对 URL、分支、扩展字段和暂未检出的子模块均保留。'
}
# 执行前确认计划仍对应当前状态，防止覆盖并行的 Git 操作。
recheck_plan() {
  local sub_path=""
  [[ "$INDEX_BEFORE" == "$(file_checksum "$PARENT_GIT_DIR/index")" && "$CONFIG_BEFORE" == "$(file_checksum "$PARENT_GIT_DIR/config")" && "$MODULES_BEFORE" == "$(file_checksum "$MODULES_FILE")" ]] || { fail '父仓配置或索引在预览后发生变化，请重新运行。'; return 1; }
  for sub_path in "${CHILDREN[@]}"; do
    [[ "${CHILD_HEADS[$sub_path]}" == "$(git -C "$REPO_ROOT/$sub_path" rev-parse HEAD)" ]] || { fail "${sub_path}：HEAD 在预览后变化，请重新运行。"; return 1; }
    [[ "${CHILD_GIT_DIRS[$sub_path]}" == "$(git -C "$REPO_ROOT/$sub_path" rev-parse --absolute-git-dir)" ]] || { fail "${sub_path}：Git 元数据位置在预览后变化。"; return 1; }
  done
}
# 在父仓 Git 目录内备份关联文件，失败时可核对，不复制源码和第三方目录。
backup_association_state() {
  local name=""
  PHASE="备份关联状态"
  LOCK_DIR="$PARENT_GIT_DIR/jobs-gitmodules.lock"
  mkdir "$LOCK_DIR" 2>/dev/null || { fail "已有脚本锁：${LOCK_DIR}"; return 1; }
  LOCK_OWNED=1
  recheck_plan || return 1
  mkdir -p "$PARENT_GIT_DIR/jobs-submodule-backups" || return 1
  BACKUP_DIR="$(mktemp -d "$PARENT_GIT_DIR/jobs-submodule-backups/$(date '+%Y.%m.%d %H-%M-%S').XXXXXXXX")" || return 1
  for name in index config; do
    if [[ -f "$PARENT_GIT_DIR/$name" ]]; then cp -p "$PARENT_GIT_DIR/$name" "$BACKUP_DIR/$name" || return 1; fi
  done
  if [[ -f "$MODULES_FILE" ]]; then cp -p "$MODULES_FILE" "$BACKUP_DIR/gitmodules" || return 1; fi
  print -r -- "$REPO_ROOT" > "$BACKUP_DIR/parent-path"
  log "关联配置与索引备份：${BACKUP_DIR}"
}
# 写入增量配置、只补缺失的 gitlink，并使用 Git 官方命令归集元数据。
apply_associations() {
  local sub_path="" section=""
  PHASE="写入关联配置"
  MUTATING=1
  if [[ ! -f "$MODULES_FILE" ]] || ! cmp -s "$MODULES_FILE" "$PLAN_FILE"; then
    cp -p "$PLAN_FILE" "$MODULES_FILE" || return 1
    git -C "$REPO_ROOT" add -- .gitmodules || return 1
  elif ! git -C "$REPO_ROOT" ls-files --error-unmatch -- .gitmodules >/dev/null 2>&1; then
    git -C "$REPO_ROOT" add -- .gitmodules || return 1
  fi
  for sub_path in "${CHILDREN[@]}"; do
    section="${SECTION_NAMES[$sub_path]}"
    if (( ${NEED_GITLINK[$sub_path]} )); then
      PHASE="登记 gitlink：${sub_path}"
      git -C "$REPO_ROOT" update-index --add --cacheinfo 160000 "${CHILD_HEADS[$sub_path]}" "$sub_path" || return 1
    fi
    PHASE="本地登记：${sub_path}"
    git -C "$REPO_ROOT" submodule init -- "$sub_path" || return 1
    if (( ${NEED_ABSORB[$sub_path]} )); then
      PHASE="归集 Git 元数据：${sub_path}"
      git -C "$REPO_ROOT" submodule absorbgitdirs -- "$sub_path" || return 1
    fi
  done
}
# 核验登记、160000 指针、父子关系和真实元数据目录，任一失败都不报完成。
verify_associations() {
  local sub_path="" section="" actual="" superproject="" entry=""
  PHASE="核验关联"
  git -C "$REPO_ROOT" ls-files --error-unmatch -- .gitmodules >/dev/null || { fail '.gitmodules 尚未登记到父仓索引。'; return 1; }
  for sub_path in "${CHILDREN[@]}"; do
    section="${SECTION_NAMES[$sub_path]}"
    [[ "$(git config --file "$MODULES_FILE" --get "submodule.${section}.path")" == "$sub_path" ]] || return 1
    [[ "$(git config --file "$MODULES_FILE" --get "submodule.${section}.url")" == "${CHILD_URLS[$sub_path]}" ]] || return 1
    entry="$(git -C "$REPO_ROOT" ls-files --stage -- "$sub_path")" || return 1
    [[ "$entry" == 160000\ * ]] || { fail "缺少 gitlink：${sub_path}"; return 1; }
    actual="$(git -C "$REPO_ROOT/$sub_path" rev-parse --absolute-git-dir)" || return 1
    [[ "${actual:A}" == "$PARENT_GIT_DIR/modules/$section" && -f "$REPO_ROOT/$sub_path/.git" ]] || { fail "元数据归集未完成：${sub_path}"; return 1; }
    superproject="$(git -C "$REPO_ROOT/$sub_path" rev-parse --show-superproject-working-tree)" || return 1
    [[ "${superproject:A}" == "$REPO_ROOT" ]] || { fail "父仓关系不一致：${sub_path}"; return 1; }
    [[ "$(git -C "$REPO_ROOT/$sub_path" rev-parse HEAD)" == "${CHILD_HEADS[$sub_path]}" ]] || { fail "子仓提交意外变化：${sub_path}"; return 1; }
    git -C "$REPO_ROOT" config --get "submodule.${section}.url" >/dev/null || return 1
  done
  log "✔ 已核验 ${#CHILDREN} 个直属子仓的完整关联；未提交、未推送。"
  git -C "$REPO_ROOT" status --short
}
# 单次运行完成确认、备份、登记、归集与核验；预览和重复运行不制造变更。
run_business() {
  local answer="" same=0
  if [[ -f "$MODULES_FILE" ]] && cmp -s "$MODULES_FILE" "$PLAN_FILE"; then same=1; fi
  if (( same && MODULES_INDEXED && ${#WORK_ITEMS} == 0 )); then
    log '✔ 已有登记完整，无需更新已有 gitlink 或元数据。'; return 0
  fi
  if (( ${#CHILDREN} == 0 )); then
    log '没有发现待关联的直属子仓；保留已有配置。'; return 0
  fi
  if [[ "$DRY_RUN" == 1 ]]; then
    log 'DRY_RUN=1：仅预检与预览，没有修改父子仓的配置、索引或元数据。'; return 0
  fi
  IFS= read -r 'answer?确认按计划完成全部父子关联？直接回车跳过；输入任意字符后回车执行：' || return 1
  if [[ -z "$answer" ]]; then log '已跳过，尚未修改父子仓。'; return 0; fi
  backup_association_state || return 1
  apply_associations || return 1
  verify_associations || return 1
}
# 编排自述、只读预检、增量计划和完整本地关联。
main() {
  show_script_intro_and_wait "$@" # 先说明影响范围，写入流程须有交互确认。
  initialize_runtime # 初始化日志、选项、数组与清理逻辑。
  check_environment # 定位当前父仓并保护索引和配置边界。
  load_existing_modules # 保留已有子模块映射和扩展配置。
  discover_and_plan # 扫描直属子仓并在写入前检查冲突。
  show_plan # 展示需要补齐的登记、gitlink 和元数据迁移。
  run_business # 一次完成备份、关联、归集及核验。
}
main "$@"
