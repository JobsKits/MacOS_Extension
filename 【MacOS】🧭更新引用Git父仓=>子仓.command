#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】🧭更新引用Git父仓=>子仓.command
# - 核心用途：以磁盘第一层现存子 Git 为准，对齐父仓子模块登记和当前提交指针。
# - 影响范围：清理缺失关联、暂存当前 HEAD、初始化本地登记并用 Git 官方命令归集元数据。
# - 运行提示：先回车查看计划；再回车跳过、输入任意字符执行；保留源码、分支与真实远端，不联网、不提交、不推送。
# shell: zsh

SCRIPT_SOURCE="${(%):-%x}"
SCRIPT_DIR=""
SCRIPT_PATH=""
SCRIPT_BASENAME=""
LOG_FILE=""
PARENT_REPO_DIR=""
PARENT_GIT_DIR=""
TEMP_DIR=""
BACKUP_DIR=""
LOCK_DIR=""
LOCK_OWNED=0
CLEANED=0
MUTATING=0
DRY_RUN="${DRY_RUN:-0}"
PHASE="初始化"
INDEX_BEFORE=""
CONFIG_BEFORE=""
MODULES_BEFORE=""
PARENT_HEAD_BEFORE=""
typeset -ga CURRENT_SUBGIT_DIRS STALE_GITLINKS
typeset -gA SUBMODULE_URLS REGISTRATION_URLS EXISTING_SECTION_NAMES EXISTING_SECTION_PATHS
typeset -gA CHILD_GIT_DIRS CHILD_HEADS CHILD_BRANCHES CHILD_REFS CHILD_INDEXES CHILD_STATES CHILD_REMOTES CHILD_CONFIGS
typeset -gA NEED_ABSORB NEED_WORKTREE RENAMED_FROM

# 红色标题与蓝色正文仅用于可彩色终端，自述不读取外部文件。
intro_line() {
  local role="$1" message="$2" color="0;34"
  [[ "$role" == title ]] && color="1;31"
  if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" &&
        "${PLAIN_OUTPUT:-0}" != 1 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]]; then
    printf '\033[%sm%s\033[0m\n' "$color" "$message"
  else
    print -r -- "$message"
  fi
}
# 先显示固定自述，再允许终端确认；预览入口不进入写入流程。
show_script_intro_and_wait() {
  local argument="" answer=""
  SCRIPT_DIR="${SCRIPT_SOURCE:A:h}"
  SCRIPT_PATH="${SCRIPT_DIR}/${SCRIPT_SOURCE:t}"
  SCRIPT_BASENAME="${SCRIPT_SOURCE:t:r}"
  LOG_FILE="${TMPDIR:-/tmp}"
  LOG_FILE="${LOG_FILE%/}/${SCRIPT_BASENAME}.$$.log"
  intro_line title '【MacOS】🧭更新引用Git父仓=>子仓.command · 按磁盘修复子模块关联'
  intro_line body '1、只扫描父仓第一层现存子 Git；缺失目录的登记和旧 gitlink 会移除，未下载的子模块也在此范围。'
  intro_line body '2、保留仍存在条目的 URL、分支与扩展字段；暂存子仓当前 HEAD，不拉取、不切分支、不提交、不推送。'
  intro_line body '3、先预检和展示计划，再确认执行；使用 Git absorbgitdirs 归集，不手工移动或覆盖 Git 元数据。'
  intro_line body '4、执行前备份关联配置与索引；元数据归属不明、冲突或链接工作树直接停止。'
  intro_line body "日志：${LOG_FILE}；--dry-run / DRY_RUN=1 只预览，Ctrl+C 取消。"
  for argument in "$@"; do
    case "$argument" in
      --help|-h) print -r -- '用法：脚本 [--dry-run]；放在父仓根目录或其直属同名脚本目录。'; exit 0 ;;
      --dry-run) DRY_RUN=1 ;;
      *) print -u2 -r -- "未知参数：${argument}"; exit 1 ;;
    esac
  done
  [[ "$DRY_RUN" == 0 || "$DRY_RUN" == 1 ]] || { print -u2 -- 'DRY_RUN 只能为 0 或 1。'; exit 1; }
  [[ "$DRY_RUN" == 1 ]] && return 0
  [[ -t 0 ]] || { print -u2 -- '没有可交互输入，请在终端运行，或使用 --dry-run。'; exit 1; }
  IFS= read -r 'answer?已了解影响范围，按回车查看计划；Ctrl+C 取消：' || exit 1
}
# 日志使用原始字符串，避免路径中的反斜线被解释。
log() {
  print -r -- "$*" | tee -a "$LOG_FILE"
}
info_echo() { log "ℹ $*"; }
warn_echo() { log "⚠ $*"; }
success_echo() { log "✔ $*"; }
error_echo() { log "✖ $*"; }
# 失败始终返回非零，让统一错误处理报告实际阶段。
fail() {
  error_echo "$*"
  return 1
}
# 清理只涉及本进程的临时文件和锁，失败时保留备份与已完成状态。
cleanup() {
  local result="${1:-0}" temporary=""
  if (( CLEANED )); then return 0; fi
  CLEANED=1
  if (( result != 0 )); then
    print -u2 -r -- "✖ 已停止，阶段：${PHASE}；日志：${LOG_FILE}"
    if (( MUTATING )); then print -u2 -r -- "部分修复可能已完成，请核对状态；备份：${BACKUP_DIR}"; fi
  fi
  if (( LOCK_OWNED )); then rmdir "$LOCK_DIR" 2>/dev/null || true; fi
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    for temporary in "$TEMP_DIR"/*(DN.); do rm -f -- "$temporary"; done
    rmdir "$TEMP_DIR" 2>/dev/null || true
  fi
  return 0
}
TRAPEXIT() {
  local exit_code=$?
  cleanup "$exit_code"
  return "$exit_code"
}
TRAPZERR() {
  local failure_code=$?
  cleanup "$failure_code"
  exit "$failure_code"
}
TRAPINT() {
  cleanup 130
  exit 130
}
TRAPTERM() {
  cleanup 143
  exit 143
}
# 确认后集中设置选项与状态，文件顶部不执行探测或写入。
initialize_script_runtime() {
  set -e
  set -o pipefail
  setopt NO_NOMATCH
  export GIT_OPTIONAL_LOCKS=0 GIT_LITERAL_PATHSPECS=1 GIT_TERMINAL_PROMPT=0
  CURRENT_SUBGIT_DIRS=(); STALE_GITLINKS=()
  SUBMODULE_URLS=(); REGISTRATION_URLS=(); EXISTING_SECTION_NAMES=(); EXISTING_SECTION_PATHS=()
  CHILD_GIT_DIRS=(); CHILD_HEADS=(); CHILD_BRANCHES=(); CHILD_REFS=(); CHILD_INDEXES=()
  CHILD_STATES=(); CHILD_REMOTES=(); CHILD_CONFIGS=(); NEED_ABSORB=(); NEED_WORKTREE=(); RENAMED_FROM=()
  : > "$LOG_FILE"
}
# 根目录入口优先处理自身；包目录入口只向上一层定位。
resolve_parent_repo_dir() {
  if [[ -e "$SCRIPT_DIR/.git" ]]; then
    print -r -- "$SCRIPT_DIR"
  elif [[ "${SCRIPT_DIR:t}" == "${SCRIPT_SOURCE:t}" && -e "${SCRIPT_DIR:h}/.git" ]]; then
    print -r -- "${SCRIPT_DIR:h}"
  else
    return 1
  fi
}
file_checksum() {
  if [[ -f "$1" ]]; then cksum < "$1"; else print -r -- absent; fi
}
array_contains() {
  local needle="$1" item=""
  shift
  for item in "$@"; do [[ "$item" == "$needle" ]] && return 0; done
  return 1
}
# section 可有多层名称，但不能越过 modules 根或含控制字符。
valid_name() {
  local value="$1"
  [[ -n "$value" && "$value" != /* && "$value" != -* && "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *$'\t'* && "$value" != *\\* ]] || return 1
  [[ "/$value/" != */../* && "/$value/" != */./* && "$value" != */ && "$value" != *//* ]]
}
valid_url() {
  local value="$1" authority=""
  [[ -n "$value" && "$value" != -* && "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *$'\t'* && "$value" != *'::'* && "$value" != *\?* && "$value" != *\#* ]] || return 1
  if [[ "$value" == http://* || "$value" == https://* ]]; then
    authority="${value#*://}"; authority="${authority%%/*}"
    [[ "$authority" != *@* ]] || return 1
  elif [[ "$value" == ssh://* ]]; then
    authority="${value#*://}"; authority="${authority%%/*}"
    if [[ "$authority" == *@* ]]; then [[ "${authority%%@*}" != *:* ]] || return 1; fi
  fi
  return 0
}
# 解析可证明仓库层级的托管地址；本地路径、未知协议和歧义路径不参与相对化。
hosted_url_parts() {
  local value="$1" rest="" authority="" repository_path="" namespace="" repository=""
  [[ -n "$value" && "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *$'\t'* && "$value" != *\?* && "$value" != *\#* && "$value" != *\* ]] || return 1
  case "$value" in
    http://*|https://*|ssh://*)
      rest="${value#*://}"
      [[ "$rest" == */* ]] || return 1
      authority="${rest%%/*}"; repository_path="${rest#*/}"
      if [[ "$value" == ssh://* ]]; then
        [[ "${authority%%@*}" != *:* || "$authority" != *@* ]] || return 1
      else
        [[ "$authority" != *@* ]] || return 1
      fi
      authority="${authority##*@}"
      ;;
    *://*) return 1 ;;
    *:*)
      authority="${value%%:*}"; repository_path="${value#*:}"
      [[ "$authority" != */* && "$authority" != -* && "$repository_path" != /* ]] || return 1
      authority="${authority##*@}"
      ;;
    *) return 1 ;;
  esac
  [[ -n "$authority" && "$authority" != *[[:space:]@/]* && "$repository_path" == */* && "$repository_path" != /* && "$repository_path" != */ && "$repository_path" != *//* ]] || return 1
  [[ "/$repository_path/" != */../* && "/$repository_path/" != */./* && "$repository_path" != '~'* ]] || return 1
  namespace="${repository_path%/*}"; repository="${repository_path##*/}"; repository="${repository%.git}"
  [[ -n "$repository" && "$repository" != . && "$repository" != .. && "$repository" != -* ]] || return 1
  if [[ "$authority" == *:* ]]; then
    authority="${value%%://*}://${authority}"
  fi
  print -rl -- "${(L)authority}" "$namespace" "$repository"
}
# 只有父子所有已配置托管线路逐一同站同命名空间、子仓名称一致时生成共享相对 URL。
relative_submodule_url() {
  local parent_repo="$1" child_repo="$2" selected_url="$3" record="" remote_url="" endpoint="" repository="" key="" repo=""
  local -a parts
  local -A parent_endpoints child_endpoints
  hosted_url_parts "$selected_url" >/dev/null || return 1
  for repo in "$parent_repo" "$child_repo"; do
    while IFS= read -r -d '' record; do
      remote_url="${record#*$'\n'}"
      parts=("${(@f)$(hosted_url_parts "$remote_url")}")
      (( ${#parts} == 3 )) || return 1
      endpoint="${parts[1]}/${parts[2]}"
      if [[ "$repo" == "$parent_repo" ]]; then
        parent_endpoints[$endpoint]=1
      else
        [[ -z "$repository" || "$repository" == "${parts[3]}" ]] || return 1
        repository="${parts[3]}"
        child_endpoints[$endpoint]=1
      fi
    done < <(git -C "$repo" --work-tree="$repo" config --local --null --get-regexp '^remote\..*\.url$' 2>/dev/null || true)
  done
  (( ${#parent_endpoints} && ${#parent_endpoints} == ${#child_endpoints} )) || return 1
  for key in "${(@k)parent_endpoints}"; do
    [[ -n "${child_endpoints[$key]:-}" ]] || return 1
  done
  [[ -n "$repository" ]] || return 1
  print -r -- "../${repository}.git"
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
# 计算从指定目录到目标路径的相对路径，避免嵌套子模块写坏 .git 指针。
relative_path_from_dir() {
  local target="$1"
  local from_dir="$2"
  local target_abs=""
  local from_abs=""
  local idx=1
  local i=0
  local -a target_parts
  local -a from_parts
  local -a rel_parts

  target_abs="$(normalize_existing_path "$target")"
  from_abs="$(normalize_existing_path "$from_dir")"
  target_abs="${target_abs:A}"
  from_abs="${from_abs:A}"
  target_parts=("${(@s:/:)target_abs}")
  from_parts=("${(@s:/:)from_abs}")

  while [[ $idx -le ${#target_parts[@]} && $idx -le ${#from_parts[@]} && "${target_parts[$idx]}" == "${from_parts[$idx]}" ]]; do
    idx=$((idx + 1))
  done

  rel_parts=()
  for ((i=idx; i<=${#from_parts[@]}; i++)); do
    [[ -n "${from_parts[$i]}" ]] && rel_parts+=("..")
  done
  for ((i=idx; i<=${#target_parts[@]}; i++)); do
    [[ -n "${target_parts[$i]}" ]] && rel_parts+=("${target_parts[$i]}")
  done

  if [[ ${#rel_parts[@]} -eq 0 ]]; then
    print -r -- "."
  else
    local IFS="/"
    print -r -- "${rel_parts[*]}"
  fi
}
# 先检查父仓边界和索引，再建立只读计划所需的临时目录。
check_environment() {
  local variable="" root="" common="" file=""
  PHASE="父仓预检"
  command -v git >/dev/null 2>&1 || { fail '未找到 Git。'; return 1; }
  git --version >/dev/null || return 1
  for variable in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR; do
    [[ -z "${(P)variable}" ]] || { fail "检测到 ${variable}，请在普通仓库终端运行。"; return 1; }
  done
  PARENT_REPO_DIR="$(resolve_parent_repo_dir)" || { fail '脚本应位于父仓根目录或其直属同名脚本目录。'; return 1; }
  root="$(git -C "$PARENT_REPO_DIR" rev-parse --show-toplevel)" || return 1
  [[ "${root:A}" == "$PARENT_REPO_DIR" ]] || { fail '目标不是独立父仓根目录。'; return 1; }
  PARENT_GIT_DIR="$(git -C "$PARENT_REPO_DIR" rev-parse --absolute-git-dir)" || return 1
  PARENT_GIT_DIR="${PARENT_GIT_DIR:A}"
  common="$(git -C "$PARENT_REPO_DIR" rev-parse --git-common-dir)" || return 1
  [[ "$common" == /* ]] || common="$PARENT_REPO_DIR/$common"
  [[ "${common:A}" == "$PARENT_GIT_DIR" ]] || { fail '父仓是链接工作树，请在主工作树修复。'; return 1; }
  for file in "$PARENT_GIT_DIR/index" "$PARENT_GIT_DIR/config" "$PARENT_REPO_DIR/.gitmodules" "$PARENT_GIT_DIR/modules" "$PARENT_GIT_DIR/jobs-submodule-backups"; do
    [[ ! -L "$file" ]] || { fail "配置、索引或元数据路径是符号链接：${file}"; return 1; }
  done
  [[ ! -e "$PARENT_GIT_DIR/index.lock" ]] || { fail '父仓索引正被其它操作占用。'; return 1; }
  [[ ! -e "$PARENT_REPO_DIR/.gitmodules" || -f "$PARENT_REPO_DIR/.gitmodules" ]] || { fail '.gitmodules 不是普通文件。'; return 1; }
  [[ -z "$(git -C "$PARENT_REPO_DIR" ls-files --unmerged)" ]] || { fail '父仓存在未解决的索引冲突。'; return 1; }
  if git -C "$PARENT_REPO_DIR" ls-files --error-unmatch -- .gitmodules >/dev/null 2>&1; then
    git -C "$PARENT_REPO_DIR" diff --quiet -- .gitmodules || { fail '.gitmodules 有未暂存差异，请先处理暂存边界。'; return 1; }
  elif git -C "$PARENT_REPO_DIR" cat-file -e HEAD:.gitmodules 2>/dev/null; then
    fail '.gitmodules 已被暂存删除，请先处理该选择。'; return 1
  fi
  if [[ -f "$PARENT_REPO_DIR/.gitmodules" ]]; then git config --file "$PARENT_REPO_DIR/.gitmodules" --list >/dev/null || return 1; fi
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jobs-reference-repair.XXXXXXXX")" || return 1
  INDEX_BEFORE="$(file_checksum "$PARENT_GIT_DIR/index")"
  CONFIG_BEFORE="$(file_checksum "$PARENT_GIT_DIR/config")"
  MODULES_BEFORE="$(file_checksum "$PARENT_REPO_DIR/.gitmodules")"
  PARENT_HEAD_BEFORE="$(git -C "$PARENT_REPO_DIR" rev-parse --verify HEAD 2>/dev/null || print -r -- unborn)"
}
# 保留已有 section / URL / branch / 扩展字段，重复和越界映射在写入前阻断。
load_existing_submodule_sections() {
  local record="" key="" sub_path="" section="" file="$PARENT_REPO_DIR/.gitmodules"
  EXISTING_SECTION_NAMES=(); EXISTING_SECTION_PATHS=()
  [[ -f "$file" ]] || return 0
  while IFS= read -r -d '' record; do
    key="${record%%$'\n'*}"; sub_path="${record#*$'\n'}"
    section="${key#submodule.}"; section="${section%.path}"
    valid_name "$sub_path" && valid_name "$section" || { fail '子模块 section 或 path 不安全。'; return 1; }
    [[ -z "${EXISTING_SECTION_NAMES[$sub_path]:-}" && -z "${EXISTING_SECTION_PATHS[$section]:-}" ]] || { fail '子模块 section 或 path 重复。'; return 1; }
    EXISTING_SECTION_NAMES[$sub_path]="$section"; EXISTING_SECTION_PATHS[$section]="$sub_path"
  done < <(git config --null --file "$file" --get-regexp '^submodule\..*\.path$' 2>/dev/null || true)
}
# 只扫描第一层真实目录，跳过依赖、供应商与构建目录。
discover_current_subgit_dirs() {
  local child="" name=""
  CURRENT_SUBGIT_DIRS=()
  while IFS= read -r -d '' child; do
    name="${child:t}"
    case "$name" in
      .git|node_modules|Pods|PodsManual|ManualBy*Pods@Pods|.dart_tool|build|DerivedData|dist|.venv|venv|vendor|third_party) continue ;;
    esac
    [[ -e "$child/.git" || -L "$child/.git" ]] || continue
    valid_name "$name" || { fail '子仓目录名含不支持的控制字符。'; return 1; }
    CURRENT_SUBGIT_DIRS+=("$name")
  done < <(find "$PARENT_REPO_DIR" -mindepth 1 -maxdepth 1 -type d -print0)
  (( ${#CURRENT_SUBGIT_DIRS} )) || { fail '没有发现第一层子 Git；停止，避免误清理全部登记。'; return 1; }
}
# 直接读取标记以兼容目录改名后旧 core.worktree 已失效的正常子模块。
read_child_gitdir() {
  local child="$1" pointer="" marker="$1/.git"
  [[ ! -L "$marker" ]] || return 1
  if [[ -d "$marker" ]]; then
    print -r -- "${marker:A}"
  elif [[ -f "$marker" ]]; then
    pointer="$(< "$marker")"
    [[ "$pointer" == 'gitdir: '* && "$pointer" != *$'\n'* ]] || return 1
    pointer="${pointer#gitdir: }"
    [[ "$pointer" == /* ]] || pointer="$child/$pointer"
    [[ -d "$pointer" ]] || return 1
    print -r -- "${pointer:A}"
  else
    return 1
  fi
}
# 读状态均显式指定工作目录；不切换分支或刷新磁盘索引。
child_digest() {
  local child="$1" git_dir="$2" kind="$3"
  case "$kind" in
    refs) git --git-dir="$git_dir" --work-tree="$child" for-each-ref --format='%(refname) %(objectname)' | cksum ;;
    state) git --git-dir="$git_dir" --work-tree="$child" status --porcelain=v1 -z --untracked-files=all | cksum ;;
    remote) (git --git-dir="$git_dir" --work-tree="$child" config --local --null --get-regexp '^remote\.' || true) | cksum ;;
  esac
}
# 验明元数据归属；目录改名沿用可证明的原 section，不搬移或覆盖 gitdir。
inspect_child_metadata() {
  local sub_path="$1" child="$PARENT_REPO_DIR/$1" git_dir="" common="" section="" module_name="" previous="" target="" worktree="" entry="" header="" entry_path="" oid="" file="" indexed=0
  [[ -n "$PARENT_GIT_DIR" ]] || PARENT_GIT_DIR="$(git -C "$PARENT_REPO_DIR" rev-parse --absolute-git-dir)"
  git_dir="$(read_child_gitdir "$child")" || { fail "${sub_path}：.git 指针失效或类型不安全，未自动猜测元数据。"; return 1; }
  common="$(git --git-dir="$git_dir" --work-tree="$child" rev-parse --git-common-dir)" || return 1
  [[ "$common" == /* ]] || common="$git_dir/$common"
  [[ "${common:A}" == "$git_dir" ]] || { fail "${sub_path}：链接工作树不作为普通子模块整理。"; return 1; }
  [[ "$(git --git-dir="$git_dir" --work-tree="$child" config --bool core.bare)" != true ]] || { fail "${sub_path}：不处理裸仓。"; return 1; }
  if [[ -d "$git_dir/worktrees" && -n "$(ls -A "$git_dir/worktrees")" ]]; then fail "${sub_path}：元数据还管理其它链接工作树。"; return 1; fi
  for file in config index HEAD; do [[ ! -L "$git_dir/$file" ]] || { fail "${sub_path}：Git ${file} 是符号链接。"; return 1; }; done
  [[ ! -e "$git_dir/index.lock" && ! -e "$git_dir/config.lock" ]] || { fail "${sub_path}：Git 元数据正被占用。"; return 1; }
  oid="$(git --git-dir="$git_dir" --work-tree="$child" rev-parse --verify 'HEAD^{commit}')" || { fail "${sub_path}：没有有效 HEAD。"; return 1; }
  [[ -z "$(git --git-dir="$git_dir" --work-tree="$child" ls-files --unmerged)" ]] || { fail "${sub_path}：存在未解决的索引冲突。"; return 1; }
  section="${EXISTING_SECTION_NAMES[$sub_path]:-}"
  if [[ -f "$child/.git" ]]; then
    [[ "$git_dir" == "$PARENT_GIT_DIR/modules/"* ]] || { fail "${sub_path}：.git 指向本父仓 modules 之外，停止。"; return 1; }
    module_name="${git_dir#"$PARENT_GIT_DIR/modules/"}"
    valid_name "$module_name" || return 1
    if [[ -n "$section" && "$section" != "$module_name" ]]; then fail "${sub_path}：登记 section 与真实元数据位置不一致。"; return 1; fi
    section="$module_name"
    previous="${EXISTING_SECTION_PATHS[$section]:-}"
    if [[ -n "$previous" && "$previous" != "$sub_path" ]]; then
      if array_contains "$previous" "${CURRENT_SUBGIT_DIRS[@]}"; then fail "${sub_path}：元数据已被其它现存子仓登记。"; return 1; fi
      RENAMED_FROM[$section]="$previous"
      unset "EXISTING_SECTION_NAMES[$previous]"
      EXISTING_SECTION_NAMES[$sub_path]="$section"; EXISTING_SECTION_PATHS[$section]="$sub_path"
    fi
  fi
  [[ -n "$section" ]] || section="$sub_path"
  valid_name "$section" || return 1
  target="$PARENT_GIT_DIR/modules/$section"
  [[ "$target" == "${target:A}" ]] || { fail "${sub_path}：modules 目标含符号链接。"; return 1; }
  if [[ "$git_dir" != "$target" && ( -e "$target" || -L "$target" ) ]]; then fail "${sub_path}：modules 目标已有另一套元数据，停止以免覆盖。"; return 1; fi
  worktree="$(git --git-dir="$git_dir" --work-tree="$child" config --get core.worktree || true)"
  NEED_WORKTREE[$sub_path]=0
  if [[ -n "$worktree" ]]; then
    [[ "$worktree" == /* ]] || worktree="$git_dir/$worktree"
    if [[ "${worktree:A}" != "${child:A}" ]]; then
      [[ ! -e "$worktree" ]] || { fail "${sub_path}：元数据仍指向另一现存工作目录。"; return 1; }
      NEED_WORKTREE[$sub_path]=1
    fi
  elif [[ -f "$child/.git" ]]; then
    NEED_WORKTREE[$sub_path]=1
  fi
  while IFS= read -r -d '' entry; do
    header="${entry%%$'\t'*}"; entry_path="${entry#*$'\t'}"
    [[ "$entry_path" == "$sub_path" && "${header%% *}" == 160000 && "${header##* }" == 0 ]] || { fail "${sub_path}：父仓按普通文件跟踪该目录或存在索引冲突。"; return 1; }
    indexed=1
  done < <(git -C "$PARENT_REPO_DIR" ls-files --stage -z -- "$sub_path")
  if (( ! indexed )) && [[ -n "$(git -C "$PARENT_REPO_DIR" ls-tree HEAD -- "$sub_path" 2>/dev/null)" ]]; then fail "${sub_path}：父仓已暂存删除该路径，请先处理该选择。"; return 1; fi
  CHILD_GIT_DIRS[$sub_path]="$git_dir"; CHILD_HEADS[$sub_path]="$oid"
  CHILD_BRANCHES[$sub_path]="$(git --git-dir="$git_dir" --work-tree="$child" symbolic-ref --quiet HEAD || print -r -- detached)"
  CHILD_REFS[$sub_path]="$(child_digest "$child" "$git_dir" refs)"
  CHILD_INDEXES[$sub_path]="$(file_checksum "$git_dir/index")"
  CHILD_STATES[$sub_path]="$(child_digest "$child" "$git_dir" state)"
  CHILD_REMOTES[$sub_path]="$(child_digest "$child" "$git_dir" remote)"
  CHILD_CONFIGS[$sub_path]="$(file_checksum "$git_dir/config")"
  NEED_ABSORB[$sub_path]=0
  [[ "$git_dir" == "$target" ]] || NEED_ABSORB[$sub_path]=1
  EXISTING_SECTION_NAMES[$sub_path]="$section"
}
# 来源始终取真实 origin；登记 URL 单独保存，不反写子仓远端。
read_origin_url_for_subgit() {
  git --git-dir="${CHILD_GIT_DIRS[$1]}" --work-tree="$PARENT_REPO_DIR/$1" config --get remote.origin.url
}
collect_submodule_urls() {
  local sub_path="" url="" section="" stored="" relative_url="" other="" other_path=""
  PHASE="子仓元数据预检"
  SUBMODULE_URLS=(); REGISTRATION_URLS=()
  for sub_path in "${CURRENT_SUBGIT_DIRS[@]}"; do
    inspect_child_metadata "$sub_path" || return 1
    section="${EXISTING_SECTION_NAMES[$sub_path]}"
    for other in "${(@k)EXISTING_SECTION_NAMES}"; do
      [[ "$other" == "$sub_path" || "${EXISTING_SECTION_NAMES[$other]}" != "$section" ]] || { fail '多个子仓映射到同一个 section。'; return 1; }
    done
    url="$(read_origin_url_for_subgit "$sub_path")" || { fail "${sub_path}：缺少真实 origin URL。"; return 1; }
    valid_url "$url" || { fail "${sub_path}：origin 地址含凭据、控制字符或不支持的格式。"; return 1; }
    SUBMODULE_URLS[$sub_path]="$url"
    stored="$(git config --file "$PARENT_REPO_DIR/.gitmodules" --get "submodule.${section}.url" 2>/dev/null || true)"
    if [[ -n "$stored" ]]; then
      valid_url "$stored" || { fail "${sub_path}：登记 URL 不安全。"; return 1; }
      REGISTRATION_URLS[$sub_path]="$stored"
    elif relative_url="$(relative_submodule_url "$PARENT_REPO_DIR" "$PARENT_REPO_DIR/$sub_path" "$url")"; then
      REGISTRATION_URLS[$sub_path]="$relative_url"
    else
      REGISTRATION_URLS[$sub_path]="$url"
      warn_echo "${sub_path}：各线路映射无法统一证明，保留明确原地址。"
    fi
  done
  for sub_path in "${CURRENT_SUBGIT_DIRS[@]}"; do
    section="${EXISTING_SECTION_NAMES[$sub_path]}"
    for other_path in "${CURRENT_SUBGIT_DIRS[@]}"; do
      [[ "$sub_path" == "$other_path" ]] && continue
      other="${EXISTING_SECTION_NAMES[$other_path]}"
      [[ "$section/" != "$other/"* ]] || { fail 'section 元数据目录存在嵌套冲突。'; return 1; }
    done
  done
}
# 将目录变化和将清理的指针明示出来，路径全程按 NUL 边界读取。
print_preflight_report() {
  local sub_path="" section="" entry="" header="" entry_path=""
  PHASE="展示修复计划"
  log "父仓：${PARENT_REPO_DIR}"
  for sub_path in "${CURRENT_SUBGIT_DIRS[@]}"; do
    section="${EXISTING_SECTION_NAMES[$sub_path]}"
    log "保留 ${sub_path}：section=${section}，暂存当前 HEAD=${CHILD_HEADS[$sub_path]}，归集元数据=${NEED_ABSORB[$sub_path]}"
    if [[ -n "${RENAMED_FROM[$section]:-}" ]]; then log "目录改名：${RENAMED_FROM[$section]} → ${sub_path}；保留原 section 与元数据位置"; fi
  done
  for section in "${(@k)EXISTING_SECTION_PATHS}"; do
    sub_path="${EXISTING_SECTION_PATHS[$section]}"
    if ! array_contains "$sub_path" "${CURRENT_SUBGIT_DIRS[@]}"; then log "移除缺失登记：${sub_path}（section=${section}）"; fi
  done
  STALE_GITLINKS=()
  while IFS= read -r -d '' entry; do
    header="${entry%%$'\t'*}"; entry_path="${entry#*$'\t'}"
    [[ "${header%% *}" == 160000 ]] || continue
    if ! array_contains "$entry_path" "${CURRENT_SUBGIT_DIRS[@]}"; then STALE_GITLINKS+=("$entry_path"); log "仅移出父仓索引：${entry_path}；磁盘文件不删除"; fi
  done < <(git -C "$PARENT_REPO_DIR" ls-files --stage -z)
  log '缺失 / 未下载的子模块关联也会清理；源码、子仓提交、分支和真实远端保留。'
  git -C "$PARENT_REPO_DIR" status --short || warn_echo '普通 status 暂不可用，已通过显式元数据预检。'
}
# 防止预览期间另一个 Git 操作改变已检查的父子仓状态。
recheck_plan() {
  local sub_path="" git_dir="" child=""
  [[ "$INDEX_BEFORE" == "$(file_checksum "$PARENT_GIT_DIR/index")" && "$CONFIG_BEFORE" == "$(file_checksum "$PARENT_GIT_DIR/config")" && "$MODULES_BEFORE" == "$(file_checksum "$PARENT_REPO_DIR/.gitmodules")" ]] || { fail '父仓配置或索引在预览后变化，请重新运行。'; return 1; }
  [[ "$PARENT_HEAD_BEFORE" == "$(git -C "$PARENT_REPO_DIR" rev-parse --verify HEAD 2>/dev/null || print -r -- unborn)" ]] || { fail '父仓 HEAD 已变化。'; return 1; }
  for sub_path in "${CURRENT_SUBGIT_DIRS[@]}"; do
    git_dir="${CHILD_GIT_DIRS[$sub_path]}"; child="$PARENT_REPO_DIR/$sub_path"
    [[ "$git_dir" == "$(read_child_gitdir "$child")" && "${CHILD_HEADS[$sub_path]}" == "$(git --git-dir="$git_dir" --work-tree="$child" rev-parse HEAD)" && "${CHILD_CONFIGS[$sub_path]}" == "$(file_checksum "$git_dir/config")" && "${CHILD_INDEXES[$sub_path]}" == "$(file_checksum "$git_dir/index")" ]] || { fail "${sub_path}：元数据在预览后变化。"; return 1; }
  done
}
# 只备份关联文件和子仓标记 / 配置，不复制源码或整个提交历史。
backup_association_state() {
  local file="" sub_path="" destination="" number=0
  PHASE="备份修复状态"
  LOCK_DIR="$PARENT_GIT_DIR/jobs-reference-repair.lock"
  mkdir "$LOCK_DIR" 2>/dev/null || { fail '已有引用修复脚本锁，请核对其它进程。'; return 1; }
  LOCK_OWNED=1
  recheck_plan || return 1
  mkdir -p "$PARENT_GIT_DIR/jobs-submodule-backups" || return 1
  BACKUP_DIR="$(mktemp -d "$PARENT_GIT_DIR/jobs-submodule-backups/reference.XXXXXXXX")" || return 1
  for file in index config; do if [[ -f "$PARENT_GIT_DIR/$file" ]]; then cp -p "$PARENT_GIT_DIR/$file" "$BACKUP_DIR/$file" || return 1; fi; done
  if [[ -f "$PARENT_REPO_DIR/.gitmodules" ]]; then cp -p "$PARENT_REPO_DIR/.gitmodules" "$BACKUP_DIR/gitmodules" || return 1; fi
  for sub_path in "${CURRENT_SUBGIT_DIRS[@]}"; do
    number=$((number + 1)); destination="$BACKUP_DIR/child-${number}"
    mkdir "$destination" || return 1
    print -r -- "$sub_path" > "$destination/path"
    cp -p "${CHILD_GIT_DIRS[$sub_path]}/config" "$destination/config" || return 1
    if [[ -f "$PARENT_REPO_DIR/$sub_path/.git" ]]; then cp -p "$PARENT_REPO_DIR/$sub_path/.git" "$destination/git-marker" || return 1; fi
  done
  log "修复配置与索引备份：${BACKUP_DIR}"
}
# 按现存目录对齐 path，保留仍存在 / 可证明改名的 section 及扩展字段。
rewrite_gitmodules() {
  local tmp_file="" sub_path="" section="" stored="" branch="" file="$PARENT_REPO_DIR/.gitmodules" existed=0
  tmp_file="$(mktemp)" || return 1
  if [[ -f "$file" ]]; then cp -p "$file" "$tmp_file" || return 1; fi
  for section in "${(@k)EXISTING_SECTION_PATHS}"; do
    sub_path="${EXISTING_SECTION_PATHS[$section]}"
    if ! array_contains "$sub_path" "${CURRENT_SUBGIT_DIRS[@]}"; then git config --file "$tmp_file" --remove-section "submodule.${section}" || return 1; fi
  done
  for sub_path in "${CURRENT_SUBGIT_DIRS[@]}"; do
    section="${EXISTING_SECTION_NAMES[$sub_path]}"
    existed=0
    if git config --file "$tmp_file" --get "submodule.${section}.path" >/dev/null; then existed=1; fi
    git config --file "$tmp_file" "submodule.${section}.path" "$sub_path" || return 1
    stored="$(git config --file "$tmp_file" --get "submodule.${section}.url" 2>/dev/null || true)"
    if [[ -z "$stored" ]]; then git config --file "$tmp_file" "submodule.${section}.url" "${REGISTRATION_URLS[$sub_path]}" || return 1; fi
    if (( ! existed )); then
      branch="$(git --git-dir="${CHILD_GIT_DIRS[$sub_path]}" --work-tree="$PARENT_REPO_DIR/$sub_path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
      if [[ -n "$branch" ]]; then git config --file "$tmp_file" "submodule.${section}.branch" "$branch" || return 1; fi
    fi
    EXISTING_SECTION_PATHS[$section]="$sub_path"
  done
  if [[ ! -f "$file" ]] || ! cmp -s "$tmp_file" "$file"; then cp -p "$tmp_file" "$file" || return 1; fi
  rm -f -- "$tmp_file"
}
# 仅修复已经验明归属且旧目录不存在的 core.worktree，不改写 .git 标记或 origin。
repair_all_subgit_metadata() {
  local sub_path="" git_dir="" relative="" child=""
  for sub_path in "${CURRENT_SUBGIT_DIRS[@]}"; do
    if (( ${NEED_WORKTREE[$sub_path]:-0} )); then
      git_dir="${CHILD_GIT_DIRS[$sub_path]}"; child="$PARENT_REPO_DIR/$sub_path"
      relative="$(relative_path_from_dir "$PARENT_REPO_DIR/$sub_path" "$git_dir")" || return 1
      git --git-dir="$git_dir" --work-tree="$child" config core.worktree "$relative" || return 1
    fi
  done
}
# 只改索引中的 gitlink，不把子仓内容作为父仓普通文件暂存。
stage_current_gitlinks() {
  local sub_path=""
  git -C "$PARENT_REPO_DIR" add -- .gitmodules || return 1
  for sub_path in "${STALE_GITLINKS[@]}"; do git -C "$PARENT_REPO_DIR" update-index --force-remove -- "$sub_path" || return 1; done
  for sub_path in "${CURRENT_SUBGIT_DIRS[@]}"; do git -C "$PARENT_REPO_DIR" update-index --add --cacheinfo 160000 "${CHILD_HEADS[$sub_path]}" "$sub_path" || return 1; done
}
# 迁移只交给 Git；任何目标冲突或命令失败都会中断，不吞掉错误。
absorb_gitdirs_if_needed() {
  local sub_path="" target="" git_dir=""
  for sub_path in "${CURRENT_SUBGIT_DIRS[@]}"; do
    git_dir="$(read_child_gitdir "$PARENT_REPO_DIR/$sub_path")" || return 1
    target="$PARENT_GIT_DIR/modules/${EXISTING_SECTION_NAMES[$sub_path]}"
    if [[ "$git_dir" != "$target" && ( -e "$target" || -L "$target" ) ]]; then fail "${sub_path}：迁移目标已存在，未覆盖。"; return 1; fi
    git -C "$PARENT_REPO_DIR" submodule absorbgitdirs -- "$sub_path" || { fail "${sub_path}：Git 元数据归集失败。"; return 1; }
    CHILD_GIT_DIRS[$sub_path]="$(read_child_gitdir "$PARENT_REPO_DIR/$sub_path")" || return 1
  done
}
# 清理父仓本地旧登记；重新 init 只同步父仓 URL，不修改子仓真实 origin。
sync_submodule_config() {
  local record="" key="" section="" sub_path=""
  while IFS= read -r -d '' record; do
    key="${record%%$'\n'*}"; section="${key#submodule.}"; section="${section%.url}"
    sub_path="${EXISTING_SECTION_PATHS[$section]:-}"
    if ! array_contains "$sub_path" "${CURRENT_SUBGIT_DIRS[@]}"; then git -C "$PARENT_REPO_DIR" config --local --remove-section "submodule.${section}" || return 1; fi
  done < <(git -C "$PARENT_REPO_DIR" config --local --null --get-regexp '^submodule\..*\.url$' 2>/dev/null || true)
  for sub_path in "${CURRENT_SUBGIT_DIRS[@]}"; do
    section="${EXISTING_SECTION_NAMES[$sub_path]}"
    if git -C "$PARENT_REPO_DIR" config --local --get-all "submodule.${section}.url" >/dev/null; then git -C "$PARENT_REPO_DIR" config --local --unset-all "submodule.${section}.url" || return 1; fi
    git -C "$PARENT_REPO_DIR" submodule init -- "$sub_path" || return 1
  done
}
# 核验目录、登记、指针与原有子仓状态；失败不输出完成。
verify_alignment() {
  local sub_path="" child="" git_dir="" section="" entry="" header="" entry_path="" count=0
  PHASE="核验修复"
  for sub_path in "${CURRENT_SUBGIT_DIRS[@]}"; do
    child="$PARENT_REPO_DIR/$sub_path"; section="${EXISTING_SECTION_NAMES[$sub_path]}"
    git_dir="$(read_child_gitdir "$child")" || return 1
    [[ -f "$child/.git" && "$git_dir" == "$PARENT_GIT_DIR/modules/$section" ]] || { fail "${sub_path}：标准元数据布局未完成。"; return 1; }
    [[ "$(git config --file "$PARENT_REPO_DIR/.gitmodules" --get "submodule.${section}.path")" == "$sub_path" ]] || return 1
    [[ "${CHILD_HEADS[$sub_path]}" == "$(git -C "$child" rev-parse HEAD)" && "${CHILD_BRANCHES[$sub_path]}" == "$(git -C "$child" symbolic-ref --quiet HEAD || print -r -- detached)" ]] || { fail "${sub_path}：提交或分支意外变化。"; return 1; }
    [[ "${CHILD_INDEXES[$sub_path]}" == "$(file_checksum "$git_dir/index")" && "${CHILD_REFS[$sub_path]}" == "$(child_digest "$child" "$git_dir" refs)" && "${CHILD_REMOTES[$sub_path]}" == "$(child_digest "$child" "$git_dir" remote)" && "${CHILD_STATES[$sub_path]}" == "$(child_digest "$child" "$git_dir" state)" ]] || { fail "${sub_path}：索引、工作区、引用或真实远端意外变化。"; return 1; }
    [[ "$(git -C "$child" rev-parse --show-superproject-working-tree)" == "$PARENT_REPO_DIR" ]] || { fail "${sub_path}：父子仓关系不一致。"; return 1; }
    entry="$(git -C "$PARENT_REPO_DIR" ls-files --stage -- "$sub_path")"
    [[ "$entry" == "160000 ${CHILD_HEADS[$sub_path]} 0"$'\t'* ]] || { fail "${sub_path}：父仓指针未对齐当前 HEAD。"; return 1; }
  done
  while IFS= read -r -d '' entry; do
    header="${entry%%$'\t'*}"; entry_path="${entry#*$'\t'}"
    [[ "${header%% *}" == 160000 ]] || continue
    array_contains "$entry_path" "${CURRENT_SUBGIT_DIRS[@]}" || { fail '父仓仍残留旧 gitlink。'; return 1; }
    count=$((count + 1))
  done < <(git -C "$PARENT_REPO_DIR" ls-files --stage -z)
  (( count == ${#CURRENT_SUBGIT_DIRS} )) || return 1
  [[ "$PARENT_HEAD_BEFORE" == "$(git -C "$PARENT_REPO_DIR" rev-parse --verify HEAD 2>/dev/null || print -r -- unborn)" ]] || { fail '父仓 HEAD 意外变化。'; return 1; }
}
# 只在核验通过后说明完成，日志保留备份位置。
print_final_report() {
  success_echo "已完成 ${#CURRENT_SUBGIT_DIRS} 个直属子仓关联修复；未联网、未提交、未推送。"
  git -C "$PARENT_REPO_DIR" status --short
}
# 执行写入前的确认，空输入和预览入口都保留原状态。
confirm_plan() {
  local answer=""
  PHASE="确认修复计划"
  if [[ "$DRY_RUN" == 1 ]]; then log 'DRY_RUN=1：只预检与预览，没有修改父子仓配置、索引或元数据。'; exit 0; fi
  IFS= read -r 'answer?确认按磁盘现状修复？直接回车跳过；输入任意字符后回车执行：' || return 1
  if [[ -z "$answer" ]]; then log '已跳过修复。'; exit 0; fi
}
# 进入写入阶段后，错误处理会报告可能保留的部分操作与备份位置。
begin_repair() {
  PHASE="写入修复"
  MUTATING=1
}
# 高层步骤集中编排；各入口均包含完整实现，不转调外部脚本。
main() {
  show_script_intro_and_wait "$@" # 首先显示内置自述并处理预览 / 交互确认。
  initialize_script_runtime # 初始化选项、日志及本进程状态。
  check_environment # 确认父仓定位、工作树类型与索引写入边界。
  discover_current_subgit_dirs # 扫描第一层现存子 Git，跳过依赖和供应商目录。
  load_existing_submodule_sections # 保留已有 section 和共享配置。
  collect_submodule_urls # 验明元数据、改名归属及真实远端，保存原始状态。
  print_preflight_report # 明示保留、改名、缺失登记清理和当前指针计划。
  confirm_plan # 默认跳过；明确确认后才允许写入。
  backup_association_state # 加锁、复核预览状态并备份配置与索引。
  begin_repair # 标记写入阶段，失败时保留明确恢复线索。
  rewrite_gitmodules # 按磁盘目录对齐登记，保留 URL、分支和扩展字段。
  repair_all_subgit_metadata # 只修正已证明失效的 core.worktree，不移动元数据。
  stage_current_gitlinks # 移除缺失指针并暂存现存子仓当前 HEAD。
  absorb_gitdirs_if_needed # 使用 Git 官方命令归集独立元数据，失败即停。
  sync_submodule_config # 对齐父仓本地登记，保留所有子仓真实 origin。
  verify_alignment # 核验关联、元数据以及提交、分支、远端、索引和源码状态。
  print_final_report # 验证通过后输出结果与待审查状态。
}

main "$@"
