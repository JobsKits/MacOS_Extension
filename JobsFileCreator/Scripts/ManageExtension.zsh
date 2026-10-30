#!/bin/zsh
# 脚本自述：
# - 脚本名称：ManageExtension.zsh（新建文件后台管理器）。
# - 核心用途：由图形面板管理本功能的安装 / 更新与卸载。
# - 影响范围：仅构建 JobsFileCreator 并管理当前用户对应的 Finder 扩展登记；不创建业务文件。
# - 运行提示：无参数打开面板，点击操作按钮后后台执行；日志在面板及系统临时目录。
# shell: zsh

PROJECT_DIR=""
MANAGER_ACTION=""
MANAGER_NON_INTERACTIVE=0
MANAGER_GUI_SESSION=0
MANAGER_SKIP_RESTART=0
APP_ID="com.jobs.filecreator"
EXTENSION_ID="com.jobs.filecreator.findersync"
APP_PATH=""
EXTENSION_PATH=""
LOG_FILE=""
LOCK_DIR=""
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# 在执行任何系统写操作之前校验完整参数及本包功能边界。
parse_options() {
  local scope="file-create"
  PROJECT_DIR="${ZSH_ARGZERO:A:h:h}"
  while (( $# > 0 )); do
    case "$1" in
      --action) (( $# >= 2 )) || return 2; MANAGER_ACTION="$2"; shift ;;
      --action=*) MANAGER_ACTION="${1#--action=}" ;;
      --features|--scope) (( $# >= 2 )) || return 2; scope="$2"; shift ;;
      --features=*|--scope=*) scope="${1#--*=}" ;;
      --non-interactive) MANAGER_NON_INTERACTIVE=1 ;;
      --gui-session) MANAGER_GUI_SESSION=1 ;;
      --skip-finder-restart) MANAGER_SKIP_RESTART=1 ;;
      --help|-h)
        print -r -- '用法：无参数打开面板；后台 --action install|uninstall --features file-create --non-interactive [--skip-finder-restart]。'
        return 10
        ;;
      *) print -u2 -r -- "✖ 未知参数：$1"; return 2 ;;
    esac
    shift
  done
  [[ "$scope" == file-create ]] || { print -u2 '✖ 本入口仅允许 file-create。'; return 2; }
  if (( MANAGER_NON_INTERACTIVE )) && [[ -z "$MANAGER_ACTION" ]]; then
    print -u2 '✖ 后台调用必须明确指定 --action install 或 uninstall。'
    return 2
  fi
  MANAGER_ACTION="${MANAGER_ACTION:-install}"
  [[ "$MANAGER_ACTION" == install || "$MANAGER_ACTION" == uninstall ]] || return 2
}

# 完整仓使用总面板；整体复制本包后使用随包的单功能面板。
open_management_panel() {
  local total_manager="${PROJECT_DIR:h}/Scripts/ManageFinderExtensions.zsh"
  local arguments=(--scope file-create --action "$MANAGER_ACTION")
  (( ! MANAGER_GUI_SESSION )) || arguments+=(--gui-session)
  if [[ -f "$total_manager" ]]; then
    exec /bin/zsh "$total_manager" "${arguments[@]}"
  fi
  source "$PROJECT_DIR/Scripts/FinderManagerGUI.zsh" || return 1
  jobs_launch_finder_manager_gui "${ZSH_ARGZERO:A}" file-create "$MANAGER_ACTION" "$MANAGER_GUI_SESSION"
}

# 面板点击已完成确认，后台仅显示用途和真实执行日志。
show_worker_intro() {
  print -r -- '━━━━━━━━━━ 新建文件 Finder 扩展管理 ━━━━━━━━━━'
  print -r -- '核心用途：安装 / 更新或卸载“📃 新建文件…”右键菜单。'
  print -r -- "来源：$PROJECT_DIR；仅处理当前用户 $EXTENSION_ID。"
  print -r -- '运行策略：操作按钮已确认，后台执行；保留源码和已创建的文件，结束后刷新 Finder。'
  print -r -- "日志位置：$LOG_FILE"
}

# 业务输出交给外层唯一日志管道，同时进入面板和日志文件。
log() {
  print -r -- "$1"
}

# 使用总面板共用的逐功能状态协议。
emit_progress() {
  local state="$1" message="$2"
  /usr/bin/printf '\nJOBS_MANAGER_EVENT\tfile-create\t%s\t%s\n' "$state" "$message"
}

# 核对实际 App 与内嵌扩展身份，拒绝操作符号链接或未知 Bundle。
is_owned_app() {
  local candidate="$1"
  [[ "$candidate" == /*/JobsFileCreator.app && -d "$candidate" && ! -L "$candidate" ]] || return 1
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$candidate/Contents/Info.plist" 2>/dev/null)" == "$APP_ID" ]]
}

is_owned_extension() {
  local candidate="$1" owner="${1%/Contents/PlugIns/JobsFileCreatorFinderSync.appex}"
  [[ "$candidate" == /*/JobsFileCreator.app/Contents/PlugIns/JobsFileCreatorFinderSync.appex && -d "$candidate" && ! -L "$candidate" ]] || return 1
  is_owned_app "$owner" || return 1
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$candidate/Contents/Info.plist" 2>/dev/null)" == "$EXTENSION_ID" ]]
}

# 只构建自有工程，未挂载任何自动登记 Build Phase。
install_extension() {
  local architecture="$(/usr/bin/uname -m)" attempt=0 registration_attempt=0 registered="" registration_line=""
  log "📦 构建对象：JobsFileCreator；来源：$PROJECT_DIR/JobsFileCreator.xcodeproj"
  log "📂 构建产物：$APP_PATH"
  /usr/bin/xcodebuild \
    -project "$PROJECT_DIR/JobsFileCreator.xcodeproj" \
    -scheme JobsFileCreator \
    -configuration Debug \
    -destination "platform=macOS,arch=$architecture" \
    -derivedDataPath "$PROJECT_DIR/work/DerivedData" \
    build || return $?
  is_owned_extension "$EXTENSION_PATH" || { log '✖ 构建产物身份核验失败。'; return 1; }
  /usr/bin/codesign --verify --deep --strict "$APP_PATH" || return $?
  "$LSREGISTER" -f "$APP_PATH" || return $?
  /usr/bin/open -gj "$APP_PATH" --args --initialize-finder-extension || return $?
  for registration_attempt in 1 2; do
    /usr/bin/pluginkit -a "$EXTENSION_PATH" || return $?
    /usr/bin/pluginkit -e use -i "$EXTENSION_ID" || return $?
    for attempt in {1..20}; do
      registered="$(/usr/bin/pluginkit -m -A -v -i "$EXTENSION_ID" 2>/dev/null)"
      while IFS= read -r registration_line; do
        [[ "$registration_line" == *[[:space:]]"$EXTENSION_PATH" ]] || continue
        if print -r -- "$registration_line" | /usr/bin/grep -q '^[[:space:]]*+'; then
          log '✔ 新建文件扩展已登记并启用。'
          return 0
        fi
      done <<< "$registered"
      /bin/sleep 0.25
    done
    if (( registration_attempt == 1 )); then
      log '⚠ 尚未确认新建文件扩展已启用，后台初始化宿主并仅重试登记一次。'
      /usr/bin/open -gj "$APP_PATH" --args --initialize-finder-extension || return $?
    fi
  done
  log '✖ 未确认当前精确路径已启用，请检查系统设置中的 Finder 扩展开关。'
  return 1
}

# 仅注销已核验的本功能副本；保留产物和业务文件便于恢复。
uninstall_extension() {
  local registered_path="" owner=""
  /usr/bin/pluginkit -e ignore -i "$EXTENSION_ID" || log 'ℹ 扩展可能尚未安装或已停用。'
  /usr/bin/pkill -u "$(/usr/bin/id -u)" -x JobsFileCreator 2>/dev/null || true
  while IFS= read -r registered_path; do
    is_owned_extension "$registered_path" || { log "⚠ 未操作身份无法核验的登记路径：$registered_path"; continue; }
    owner="${registered_path%/Contents/PlugIns/JobsFileCreatorFinderSync.appex}"
    log "注销：$registered_path"
    /usr/bin/pluginkit -r "$registered_path" || return $?
    "$LSREGISTER" -u "$owner" || return $?
  done < <(/usr/bin/pluginkit -m -A -D -vv -i "$EXTENSION_ID" 2>/dev/null | /usr/bin/awk '/Path = / { sub(/^.*Path = /, ""); print }')
  log '✔ 新建文件菜单已停用；源码、构建产物和已创建的文件保留。'
}

# 仅派发已确认的操作，必要时刷新 Finder 使菜单同步。
perform_operation() {
  if [[ "$MANAGER_ACTION" == install ]]; then
    install_extension || return $?
  else
    uninstall_extension || return $?
  fi
  if (( ! MANAGER_SKIP_RESTART )); then
    /usr/bin/killall Finder || log 'ℹ Finder 当前未运行，无需刷新。'
  fi
}

# 用同一输出管道保存完整自述、进度和命令日志。
worker_body() {
  local result=0
  show_worker_intro
  emit_progress running '正在处理'
  perform_operation
  result=$?
  if (( result == 0 )); then
    emit_progress succeeded '成功'
  else
    emit_progress failed '失败，请查看日志'
  fi
  return "$result"
}

# 日志与 GUI 共用输出；互斥锁避免同包并行构建和卸载。
run_worker() {
  local result=0
  APP_PATH="$PROJECT_DIR/work/DerivedData/Build/Products/Debug/JobsFileCreator.app"
  EXTENSION_PATH="$APP_PATH/Contents/PlugIns/JobsFileCreatorFinderSync.appex"
  local temporary_root="${TMPDIR:-/tmp}"
  LOG_FILE="${temporary_root%/}/JobsFileCreatorManage.log"
  LOCK_DIR="$PROJECT_DIR/work/.manager-lock"
  [[ "$(/usr/bin/uname -s)" == Darwin ]] || { log '✖ 仅支持 macOS。'; return 1; }
  /bin/mkdir -p "$PROJECT_DIR/work" || return 1
  /bin/mkdir "$LOCK_DIR" 2>/dev/null || { log '✖ 当前包已有管理任务；请等待结束或检查残留管理锁。'; return 1; }
  trap '/bin/rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
  worker_body 2>&1 | /usr/bin/tee "$LOG_FILE"
  result=${pipestatus[1]}
  /bin/rmdir "$LOCK_DIR" 2>/dev/null || true
  trap - EXIT
  return "$result"
}

# 原生 zsh 的选项只在初始化函数内设置。
initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
}

# 完成参数校验后只选择 GUI 或面板已确认的后台执行。
dispatch_management() {
  local result=0
  parse_options "$@" || { result=$?; (( result == 10 )) && return 0; return "$result"; }
  if (( ! MANAGER_NON_INTERACTIVE )); then
    open_management_panel
    return $?
  fi
  run_worker
}

# 入口只按顺序编排初始化与管理调度。
main() {
  initialize_runtime # 设置当前脚本的原生 zsh 选项。
  dispatch_management "$@" # 校验范围并打开 GUI 或执行已确认的任务。
}

main "$@"
