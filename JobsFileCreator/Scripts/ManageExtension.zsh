#!/bin/zsh
# 脚本自述：
# - 脚本名称：ManageExtension.zsh（新建文件后台管理器）。
# - 核心用途：由图形面板管理本功能的安装 / 更新、卸载与构建产物清理。
# - 影响范围：仅构建 JobsFileCreator 并管理当前用户对应的 Finder 扩展登记；不创建业务文件。
# - 运行提示：无参数打开面板，点击操作按钮后后台执行；日志在面板及系统临时目录。
# shell: zsh

PROJECT_DIR=""
MANAGER_ACTION=""
MANAGER_STOP_REQUEST_FILE="${JOBS_FINDER_STOP_REQUEST_FILE:-}"
MANAGER_NON_INTERACTIVE=0
MANAGER_GUI_SESSION=0
MANAGER_SKIP_RESTART=0
APP_ID="com.jobs.filecreator"
EXTENSION_ID="com.jobs.filecreator.findersync"
APP_PATH=""
EXTENSION_PATH=""
LOG_FILE=""
LOCK_DIR=""
MANAGER_LOCK_HELD=0
MANAGER_LOCK_IDENTITY=""
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# 在执行任何系统写操作之前校验完整参数及本包功能边界。
parse_options() {
  local install_location="${JOBS_FINDER_INSTALL_LOCATION:-build}" cleanup_build_products="${JOBS_FINDER_CLEANUP_BUILD_PRODUCTS:-0}"
  local scope="file-create"
  PROJECT_DIR="${ZSH_ARGZERO:A:h:h}"
  while (( $# > 0 )); do
    case "$1" in
      --action) (( $# >= 2 )) || return 2; MANAGER_ACTION="$2"; shift ;;
      --action=*) MANAGER_ACTION="${1#--action=}" ;;
      --features|--scope) (( $# >= 2 )) || return 2; scope="$2"; shift ;;
      --features=*|--scope=*) scope="${1#--*=}" ;;
      --install-location) (( $# >= 2 )) || return 2; install_location="$2"; shift ;;
      --install-location=*) install_location="${1#--install-location=}" ;;
      --cleanup-build-products) cleanup_build_products=1 ;;
      --stop-request-file) (( $# >= 2 )) && [[ "$2" == /* ]] || return 2; MANAGER_STOP_REQUEST_FILE="$2"; shift ;;
      --stop-request-file=*) MANAGER_STOP_REQUEST_FILE="${1#--stop-request-file=}"; [[ "$MANAGER_STOP_REQUEST_FILE" == /* ]] || return 2 ;;
      --non-interactive) MANAGER_NON_INTERACTIVE=1 ;;
      --gui-session) MANAGER_GUI_SESSION=1 ;;
      --skip-finder-restart) MANAGER_SKIP_RESTART=1 ;;
      --help|-h)
        print -r -- '用法：无参数打开面板；后台 --action install|uninstall|cleanup --features file-create --non-interactive [--skip-finder-restart] [--install-location build|applications] [--cleanup-build-products] [--stop-request-file PATH]。'
        return 10
        ;;
      *) print -u2 -r -- "✖ 未知参数：$1"; return 2 ;;
    esac
    shift
  done
  [[ "$install_location" == build || "$install_location" == applications ]] || { print -u2 "✖ 安装位置必须是 build 或 applications。"; return 2; }
  [[ "$cleanup_build_products" == 0 || "$cleanup_build_products" == 1 ]] || { print -u2 '✖ 构建产物清理开关必须是 0 或 1。'; return 2; }
  if [[ "$cleanup_build_products" == 1 && ( "$install_location" != applications || "${MANAGER_ACTION:-install}" != install ) ]]; then
    print -u2 '✖ 仅安装到应用程序目录时允许清除此轮构建产物。'
    return 2
  fi
  [[ "$MANAGER_ACTION" != cleanup || "$install_location" == applications ]] || { print -u2 '✖ 独立清理仅允许应用程序目录模式。'; return 2; }
  [[ -z "$MANAGER_STOP_REQUEST_FILE" || "$MANAGER_STOP_REQUEST_FILE" == /* ]] || { print -u2 '✖ 停止请求文件必须使用绝对路径。'; return 2; }
  export JOBS_FINDER_STOP_REQUEST_FILE="$MANAGER_STOP_REQUEST_FILE"
  export JOBS_FINDER_CLEANUP_BUILD_PRODUCTS="$cleanup_build_products"
  export JOBS_FINDER_INSTALL_LOCATION="$install_location"
  [[ "$scope" == file-create ]] || { print -u2 '✖ 本入口仅允许 file-create。'; return 2; }
  if (( MANAGER_NON_INTERACTIVE )) && [[ -z "$MANAGER_ACTION" ]]; then
    print -u2 '✖ 后台调用必须明确指定 --action install 或 uninstall。'
    return 2
  fi
  MANAGER_ACTION="${MANAGER_ACTION:-install}"
  [[ "$MANAGER_ACTION" == install || "$MANAGER_ACTION" == uninstall || "$MANAGER_ACTION" == cleanup ]] || return 2
}

# 完整仓使用总面板；整体复制本包后使用随包的单功能面板。
open_management_panel() {
  local -x JOBS_FINDER_STOP_REQUEST_FILE=""
  local total_manager="${PROJECT_DIR:h}/Scripts/ManageFinderExtensions.zsh"
  local arguments=(--scope file-create --action "$MANAGER_ACTION" --install-location "$JOBS_FINDER_INSTALL_LOCATION")
  [[ "${JOBS_FINDER_CLEANUP_BUILD_PRODUCTS:-0}" != 1 ]] || arguments+=(--cleanup-build-products)
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
  if [[ "$MANAGER_ACTION" == cleanup ]]; then
    print -r -- '核心用途：清理已安装联合 App 对应的新建文件构建产物。'
    print -r -- "来源：$PROJECT_DIR；保留已安装 App、菜单配置、登记与业务文件。"
    print -r -- '运行策略：仅校验通过后清理此构建单元；未就绪或仍运行时保留产物。'
    return 0
  fi
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

# 从本包加载部署函数；独立复制不依赖上级仓库。
manager_load_deployment() {
  local package_root="${PROJECT_DIR:-${ZSH_ARGZERO:A:h:h}}"
  source "$package_root/Scripts/【MacOS】AppDeployment.zsh/【MacOS】AppDeployment.zsh"
}
# 只清理当前宿主的历史构建根，保留已安装 App、功能配置和登记。
manager_cleanup_existing_build_products() {
  manager_load_deployment || return $?
  local built_app=""
  built_app="$(manager_built_application_path)" || return $?
  jobs_deployment_cleanup_existing_build_products "$built_app" "${built_app:h:h:h:h}" com.jobs.filecreator JobsFileCreatorFinderSync.appex com.jobs.filecreator.findersync
}
# 总面板可传入它自己的构建产物，但不能改变本包 App 名与身份。
manager_built_application_path() {
  local package_root="${PROJECT_DIR:-${ZSH_ARGZERO:A:h:h}}" built_app=""
  built_app="${JOBS_FINDER_BUILT_APP_PATH:-$package_root/work/DerivedData/Build/Products/Debug/JobsFileCreator.app}"
  [[ "$built_app" == /* && "${built_app:t}" == JobsFileCreator.app ]] || return 2
  print -r -- "$built_app"
}
# 只读取进程的真实可执行路径，不能按模糊名称结束面板或其它应用。
manager_host_process_records() {
  /bin/ps -ww -U "$(/usr/bin/id -u)" -o pid=,comm=
}
# 上层已核验精确 Bundle 路径，仅向该宿主实例请求正常退出。
manager_signal_host_termination() {
  local current_path=""
  current_path="$(/bin/ps -ww -p "$1" -o comm= 2>/dev/null)" || return 0
  [[ "$current_path" == "$2" ]] || { print -u2 '✖ 宿主进程路径已变化，未结束该进程。'; return 1; }
  /bin/kill -TERM "$1"
}
# 等待旧宿主退出，避免随后 open 复用仍在原构建位置运行的实例。
manager_wait_host_termination() {
  local attempt=0
  for attempt in {1..30}; do
    /bin/kill -0 "$1" 2>/dev/null || return 0
    /bin/sleep 0.1
  done
  print -u2 -r -- "✖ 旧宿主尚未退出，请退出该宿主后重新安装：$1"
  return 1
}
# 安装切换仅停止已核验 App 的宿主；保留其它应用、面板及未知同名进程。
manager_stop_previous_hosts() {
  local candidate="" expected="" process_id="" executable_path="" applications_root="" records=""
  local candidates=("$MANAGER_DEPLOYMENT_BUILT_APP_PATH" "$APP_PATH" "${JOBS_DEPLOYMENT_PREVIOUS_APPS[@]}") executables=()
  typeset -U candidates executables
  applications_root="$(jobs_deployment_applications_root)" || return $?
  candidates+=("$applications_root/JobsFileCreator.app")
  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" ]] || continue
    jobs_deployment_validate_app "$candidate" com.jobs.filecreator JobsFileCreatorFinderSync.appex com.jobs.filecreator.findersync >/dev/null 2>&1 || continue
    executables+=("$candidate/Contents/MacOS/JobsFileCreator")
  done
  records="$(manager_host_process_records)" || return $?
  while read -r process_id executable_path; do
    [[ "$process_id" == <-> && "$process_id" != "$$" && "$process_id" != "$PPID" ]] || continue
    (( ${executables[(Ie)$executable_path]} )) || continue
    print -r -- "ℹ 退出旧宿主实例：$executable_path（PID $process_id）"
    manager_signal_host_termination "$process_id" "$executable_path" || return $?
    manager_wait_host_termination "$process_id" || return $?
  done <<< "$records"
}
# 构建完成后部署完整 App，再让原登记逻辑使用选中位置。
manager_deploy_built_application() {
  manager_load_deployment || exit $?
  local built_app="$APP_PATH"
  MANAGER_DEPLOYMENT_BUILT_APP_PATH="$built_app"
  jobs_deployment_install "$built_app" com.jobs.filecreator JobsFileCreatorFinderSync.appex com.jobs.filecreator.findersync || exit $?
  APP_PATH="$(jobs_deployment_app_path "$built_app")" || exit $?
  EXTENSION_PATH="$APP_PATH/Contents/PlugIns/JobsFileCreatorFinderSync.appex"
  jobs_deployment_retire_other_copies "$APP_PATH" com.jobs.filecreator JobsFileCreatorFinderSync.appex com.jobs.filecreator.findersync || exit $?
  manager_stop_previous_hosts || exit $?
}
# 仅在部署提交后清理本包此次 DerivedData；失败只提示，不撤回已安装的 App。
manager_cleanup_build_products() {
  [[ "${JOBS_FINDER_CLEANUP_BUILD_PRODUCTS:-0}" == 1 ]] || return 0
  local package_root="${PROJECT_DIR:-${ZSH_ARGZERO:A:h:h}}"
  if ! jobs_deployment_cleanup_build_products "$MANAGER_DEPLOYMENT_BUILT_APP_PATH" "$package_root/work/DerivedData" com.jobs.filecreator JobsFileCreatorFinderSync.appex com.jobs.filecreator.findersync; then
    print -u2 -r -- '⚠ App 已安装成功，但清除此轮构建产物失败；已保留应用程序目录中的 App，请查看日志。'
  fi
  return 0
}
# 登记和配置均成功才释放旧 App 备份；退出失败由部署事务恢复。
manager_commit_deployment() {
  jobs_deployment_commit || exit $?
  manager_cleanup_build_products
}
# 精确删除所选位置；不枚举或全局禁用同 ID 的其它副本。
manager_remove_selected_application() {
  if [[ "${JOBS_FINDER_INSTALL_LOCATION:-build}" == applications ]]; then
    jobs_deployment_uninstall "$1" com.jobs.filecreator JobsFileCreatorFinderSync.appex com.jobs.filecreator.findersync
  else
    jobs_deployment_validate_app "$1" com.jobs.filecreator JobsFileCreatorFinderSync.appex com.jobs.filecreator.findersync || return $?
    jobs_deployment_unregister_app "$1" JobsFileCreatorFinderSync.appex || return $?
    /bin/rm -r -- "$1"
  fi
}
# 共享叶移除先保留其它配置，最后一叶才删除本次选中位置的 App。
manager_uninstall_selected_application() {
  manager_load_deployment || return $?
  local built_app="" selected_app="" other_enabled=0 config="" configured="" entry="" normalized="" temporary=""
  local allowed=() requested=() remaining=() values=()
  built_app="$(manager_built_application_path)" || return $?
  selected_app="$(jobs_deployment_app_path "$built_app")" || return $?
  if [[ ! -e "$selected_app" && ! -L "$selected_app" ]]; then
    print -r -- "ℹ 所选位置未安装，无需卸载：$selected_app"
    return 0
  fi
  jobs_deployment_validate_app "$selected_app" com.jobs.filecreator JobsFileCreatorFinderSync.appex com.jobs.filecreator.findersync || return $?
  jobs_deployment_has_other_enabled "$selected_app" com.jobs.filecreator.findersync || other_enabled=$?
  (( other_enabled <= 1 )) || return "$other_enabled"
  if (( other_enabled == 0 )); then
    print -r -- 'ℹ 另一位置的副本正在使用；只移除所选副本，保留公共配置。'
    manager_remove_selected_application "$selected_app"
    return $?
  fi
  manager_remove_selected_application "$selected_app" || return $?
  manager_restart_finder 2>/dev/null || true
}

# 本包由 perform_operation 统一刷新，部署辅助流程不重复刷新 Finder。
manager_restart_finder() {
  return 0
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
  manager_deploy_built_application # 应用程序模式完整复制后改用部署 App。
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
          manager_commit_deployment
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

# 只卸载所选位置；保留另一位置的副本和全部业务文件。
uninstall_extension() {
  manager_uninstall_selected_application
}

# 仅派发已确认的操作，必要时刷新 Finder 使菜单同步。
perform_operation() {
  if [[ "$MANAGER_ACTION" == install ]]; then
    local install_result=0
    install_extension || install_result=$?
    if (( install_result )); then
      (( ! $+functions[jobs_deployment_rollback] )) || jobs_deployment_rollback
      return "$install_result"
    fi
  else
    uninstall_extension || return $?
  fi
  if (( ! MANAGER_SKIP_RESTART )); then
    /usr/bin/killall Finder || log 'ℹ Finder 当前未运行，无需刷新。'
  fi
}

# 用同一输出管道保存完整自述、进度和命令日志。
worker_body() {
  # 管道子 Shell 不继承外层退出陷阱；本陷阱与整次业务同寿命。
  TRAPEXIT() {
    local original_result=$?
    (( ! $+functions[jobs_deployment_rollback] )) || jobs_deployment_rollback
    manager_release_worker_lock
    return "$original_result"
  }
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
  MANAGER_LOCK_IDENTITY="$(/usr/bin/stat -f '%d:%i' "$LOCK_DIR")" || { /bin/rmdir "$LOCK_DIR"; return 1; }
  MANAGER_LOCK_HELD=1
  worker_body 2>&1 | /usr/bin/tee "$LOG_FILE"
  result=${pipestatus[1]}
  manager_release_worker_lock
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
  if [[ "$MANAGER_ACTION" == cleanup ]]; then
    show_worker_intro
    emit_progress running '正在清理构建产物'
    manager_cleanup_existing_build_products
    result=$?
    if (( result == 0 )); then
      emit_progress succeeded '成功'
    else
      emit_progress failed '失败，请查看日志'
    fi
    return "$result"
  fi
  run_worker
}

# 只释放本次成功取得且身份未变化的锁，防止子 Shell 与父进程误删新任务的锁。
manager_release_worker_lock() {
  if (( MANAGER_LOCK_HELD )) && [[ "$LOCK_DIR" == "$PROJECT_DIR/work/.manager-lock" && -d "$LOCK_DIR" && ! -L "$LOCK_DIR" ]]; then
    if [[ "$(/usr/bin/stat -f '%d:%i' "$LOCK_DIR" 2>/dev/null)" == "$MANAGER_LOCK_IDENTITY" ]]; then
      /bin/rmdir "$LOCK_DIR" 2>/dev/null || true
    fi
  fi
  MANAGER_LOCK_HELD=0
}

# 已提交事务无操作；GUI / 参数失败未加载模块时不执行恢复。
TRAPEXIT() {
  local original_result=$?
  if [[ "$MANAGER_ACTION" != cleanup ]]; then
    (( ! $+functions[jobs_deployment_rollback] )) || jobs_deployment_rollback
  fi
  manager_release_worker_lock
  return "$original_result"
}

# 入口只按顺序编排初始化与管理调度。
main() {
  initialize_runtime # 设置当前脚本的原生 zsh 选项。
  dispatch_management "$@" # 校验范围并打开 GUI 或执行已确认的任务。
}

main "$@"
