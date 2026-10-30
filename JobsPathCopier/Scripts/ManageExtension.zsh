#!/bin/zsh
# 脚本自述：
# - 脚本名称：ManageExtension.zsh（App 内部后台管理器）
# - 核心用途：一个入口管理本功能的安装 / 更新与卸载。
# - 影响范围：当前用户 Finder 菜单、对应构建产物与专用功能配置；保留源码和业务数据。
# - 运行提示：直接打开 GUI，在面板选择安装 / 更新或卸载；底部实时日志允许复制。
# shell: zsh

MANAGER_ACTION=""
MANAGER_NON_INTERACTIVE=0
MANAGER_SKIP_RESTART=0
MANAGER_REQUESTED_FEATURES=""
MANAGER_ENTRY_DIR=""
MANAGER_GUI_SESSION=0
MANAGER_GUI_LEAF_FEATURES=""
MANAGER_UI_SCOPE="path_copier"
# 支持上级面板在完成确认后调用；显式参数不会改变本目录的功能边界。
manager_parse_options() {
  MANAGER_ENTRY_DIR="${ZSH_ARGZERO:A:h:h}"
  while (( $# > 0 )); do
    case "$1" in
      --action) (( $# >= 2 )) || return 2; MANAGER_ACTION="$2"; shift ;;
      --action=*) MANAGER_ACTION="${1#--action=}" ;;
      --non-interactive) MANAGER_NON_INTERACTIVE=1 ;;
      --gui-session) MANAGER_GUI_SESSION=1 ;;
      --skip-finder-restart) MANAGER_SKIP_RESTART=1 ;;
      --scope|--features) (( $# >= 2 )) || return 2; MANAGER_REQUESTED_FEATURES="$2"; shift ;;
      --features=*) MANAGER_REQUESTED_FEATURES="${1#--features=}" ;;
      --help|-h) print '用法：双击管理，或 --action install|uninstall --non-interactive [--features 功能ID,...] [--skip-finder-restart]'; return 10 ;;
      *) print -u2 -r -- "✖ 未知参数：$1"; return 2 ;;
    esac
    shift
  done
  manager_prepare_gui_features || return $?
  [[ -z "$MANAGER_ACTION" || "$MANAGER_ACTION" == install || "$MANAGER_ACTION" == uninstall ]] || return 2
  (( ! MANAGER_NON_INTERACTIVE )) || [[ -n "$MANAGER_ACTION" ]] || { print -u2 '✖ 非交互调用必须明确 --action。'; return 2; }
}
# 不支持颜色时保留纯文本自述，确认前不创建日志或修改系统。
manager_intro_line() {
  local role="$1" message="$2" code='0;34'
  [[ "$role" != title ]] || code='1;31'
  if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" ]]; then
    /usr/bin/printf '\033[%sm%s\033[0m\n' "$code" "$message"
  else
    print -r -- "$message"
  fi
}
# 上级批量操作只刷新一次 Finder。
manager_restart_finder() {
  (( MANAGER_SKIP_RESTART )) && return 0
  /usr/bin/killall Finder "$@"
}
# 按原有功能白名单把 GUI 叶标识转换为包内动作，事件仍使用原 GUI 标识。
manager_prepare_gui_features() {
  local feature="" mapped="" prepared=() allowed=("${(@s:,:)MANAGER_UI_SCOPE}")
  MANAGER_GUI_LEAF_FEATURES="$MANAGER_REQUESTED_FEATURES"
  [[ -n "$MANAGER_REQUESTED_FEATURES" ]] || { MANAGER_GUI_LEAF_FEATURES="$MANAGER_UI_SCOPE"; return 0; }
  [[ "$MANAGER_REQUESTED_FEATURES" != ,* && "$MANAGER_REQUESTED_FEATURES" != *, && "$MANAGER_REQUESTED_FEATURES" != *,,* ]] || return 2
  for feature in ${(s:,:)MANAGER_REQUESTED_FEATURES}; do
    mapped="$feature"
    case "${MANAGER_ENTRY_DIR:t}" in
      JobsFlutter*)
        if (( ${allowed[(Ie)$feature]} )); then
          mapped="${feature#flutter-}"
        fi
        ;;
      JobsTerminalOpener)
        case "$feature" in
          terminal_open) mapped=open ;;
          file_content) mapped=file-content ;;
          file_merge) mapped=file-merge ;;
          file_split) mapped=file-split ;;
          clean_build_artifacts) mapped=clean-build-artifacts ;;
          codegraph_bootstrap) mapped=codegraph-bootstrap ;;
        esac
        ;;
      JobsIOSTools) [[ "$feature" != pod_install ]] || mapped=ios-pod-install ;;
    esac
    prepared+=("$mapped")
  done
  MANAGER_REQUESTED_FEATURES="${(j:,:)prepared}"
}
# 兼容命令行包内动作，同时把 GUI 范围和状态统一为选择器叶 ID。
manager_gui_identifier() {
  local identifier="$1"
  case "${MANAGER_ENTRY_DIR:t}" in
    JobsFlutter*) [[ "$identifier" == flutter-* ]] || identifier="flutter-$identifier" ;;
    JobsTerminalOpener)
      case "$identifier" in
        open) identifier=terminal_open ;;
        file-content) identifier=file_content ;;
        file-merge) identifier=file_merge ;;
        file-split) identifier=file_split ;;
        clean-build-artifacts) identifier=clean_build_artifacts ;;
        codegraph-bootstrap) identifier=codegraph_bootstrap ;;
      esac
      ;;
    JobsIOSTools) [[ "$identifier" != ios-pod-install ]] || identifier=pod_install ;;
  esac
  print -nr -- "$identifier"
}
# 完整仓转交总管理器的受限范围，独立包使用随包源码且仍能整体复制。
manager_open_gui() {
  local entry="${MANAGER_ENTRY_DIR:h}/Scripts/ManageFinderExtensions.zsh" helper="$MANAGER_ENTRY_DIR/Scripts/FinderManagerGUI.zsh"
  local scope="$MANAGER_UI_SCOPE" identifier="" feature="" selected=() allowed=("${(@s:,:)MANAGER_UI_SCOPE}")
  if [[ -n "$MANAGER_REQUESTED_FEATURES" ]]; then
    for feature in ${(s:,:)MANAGER_REQUESTED_FEATURES}; do
      identifier="$(manager_gui_identifier "$feature")"
      (( ${allowed[(Ie)$identifier]} )) || { print -u2 -r -- "✖ 功能不属于本入口：$feature"; return 2; }
      selected+=("$identifier")
    done
    scope="${(j:,:)selected}"
  fi
  if [[ -f "$entry" ]]; then
    local arguments=(--scope "$scope" --action "${MANAGER_ACTION:-install}")
    (( ! MANAGER_GUI_SESSION )) || arguments+=(--gui-session)
    exec /bin/zsh "$entry" "${arguments[@]}"
  fi
  if [[ ! -f "$helper" ]]; then
    /usr/bin/osascript -e 'display alert "缺少管理面板" message "请保留包含统一功能包的完整 MacOS@Extension 目录。" as critical'
    return 1
  fi
  source "$helper" || return 1
  jobs_launch_finder_manager_gui "${ZSH_ARGZERO:A}" "$scope" "${MANAGER_ACTION:-install}" "$MANAGER_GUI_SESSION"
}
# 后台操作的用途和副作用进入面板日志，不再读取终端输入。
manager_choose_action() {
  manager_intro_line title "━━━━━━━━━━ ${ZSH_ARGZERO:t} ━━━━━━━━━━"
  manager_intro_line body "来源：${MANAGER_ENTRY_DIR}；仅管理当前范围内的 Finder 功能。"
  manager_intro_line body '安装构建并启用菜单；卸载保留未选菜单、源码与业务数据，完成后刷新 Finder。'
  return 0
}
# 逐叶回传真实运行状态；不使用无法核实的百分比。
manager_emit_progress() {
  local state="$1" feature="" message="" identifier=""
  case "$state" in
    running) [[ "$MANAGER_ACTION" == uninstall ]] && message='正在卸载' || message='正在安装 / 更新' ;;
    succeeded) message='成功' ;;
    failed) message='失败，请查看下方日志' ;;
  esac
  for feature in ${(s:,:)MANAGER_GUI_LEAF_FEATURES}; do
    identifier="$feature"
    case "${MANAGER_ENTRY_DIR:t}" in
      JobsFlutter*) [[ "$identifier" == flutter-* ]] || identifier="flutter-$identifier" ;;
      JobsTerminalOpener)
        case "$identifier" in
          open) identifier=terminal_open ;;
          file-content) identifier=file_content ;;
          file-merge) identifier=file_merge ;;
          file-split) identifier=file_split ;;
          clean-build-artifacts) identifier=clean_build_artifacts ;;
          codegraph-bootstrap) identifier=codegraph_bootstrap ;;
        esac
        ;;
      JobsIOSTools) [[ "$identifier" != ios-pod-install ]] || identifier=pod_install ;;
    esac
    /usr/bin/printf '\nJOBS_MANAGER_EVENT\t%s\t%s\t%s\n' "$identifier" "$state" "$message"
  done
}
# 操作选择即最终确认，分支直接执行对应业务。
manager_main() {
  local manager_status=0
  setopt NO_NOMATCH
  manager_parse_options "$@" || { manager_status=$?; (( manager_status == 10 )) && return 0; return "$manager_status"; }
  if (( ! MANAGER_NON_INTERACTIVE )); then
    manager_open_gui
    return $?
  fi
  manager_choose_action || return $?
  manager_emit_progress running
  manager_execute_operation
  manager_status=$?
  if (( manager_status == 0 )); then
    manager_emit_progress succeeded
  else
    manager_emit_progress failed
  fi
  return "$manager_status"
}
# 校验与业务复用原分支；任何失败保留真实退出码。
manager_execute_operation() {
  if [[ "$MANAGER_ACTION" == install ]]; then
    run_install_operation
  else
    run_uninstall_operation
  fi
}

# 原install实现只在所选分支加载，保留可独立复制运行的能力。
run_install_operation() {
(
# 脚本自述：
# - 脚本名称：ManageExtension.zsh（App 内部后台管理器）
# - 核心用途：独立构建、注册并启用“复制绝对路径”Finder 扩展。
# - 影响范围：只构建本工程与启用本扩展，成功后重启 Finder；路径复制发生在右键点击时，安装过程无其它副作用。
# - 运行提示：直接回车安装，输入任意字符后回车跳过；Ctrl+C 取消。

SCRIPT_DIR=""
PROJECT_ROOT=""
LOG_FILE=""
APP_PATH=""
EXTENSION_PATH=""
EXTENSION_ID="com.jobs.JobsPathCopier.FinderSyncExtension"
# 只计算展示位置，不修改目录与系统注册；脚本位于工程根，源码就是本目录。
prepare_display_context() {
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")/.." && pwd)"
  PROJECT_ROOT="${SCRIPT_DIR}"
  LOG_FILE="${TMPDIR:-/tmp/}JobsPathCopierInstall.log"
  APP_PATH="${PROJECT_ROOT}/work/DerivedData/Build/Products/Debug/JobsPathCopier.app"
  EXTENSION_PATH="${APP_PATH}/Contents/PlugIns/JobsPathCopyFinderSync.appex"
}
# 自述的标题红色加粗、正文蓝色，非交互输出使用纯文本。
intro_line() {
  local role="$1" message="$2"
  if [[ -t 1 && -n "${TERM:-}" && "${TERM}" != dumb && -z "${NO_COLOR+x}" ]]; then
    if [[ "$role" == title ]]; then
      /usr/bin/printf '\033[1;31m%s\033[0m\n' "$message"
    else
      /usr/bin/printf '\033[0;34m%s\033[0m\n' "$message"
    fi
  else
    print -r -- "$message"
  fi
}
# 展示安装范围，回车后执行构建与注册，非空输入跳过。
show_script_intro_and_wait() {
  prepare_display_context
  intro_line title '━━━━━━━━━━ 安装复制绝对路径 Finder 扩展 ━━━━━━━━━━'
  intro_line body "1、源码：${PROJECT_ROOT}；构建并注册本工程，不下载第三方依赖。"
  intro_line body "2、产物：${APP_PATH}；请保留该路径供系统启动扩展。"
  intro_line body '3、影响：启用固定扩展并重启 Finder；路径复制发生在右键点击时，安装过程无其它副作用。'
  intro_line body "4、日志：${LOG_FILE}；Ctrl+C 取消。"
  [[ -t 0 ]] || { print -u2 -r -- '错误：请在可交互终端运行。'; exit 1; }
  local answer=""
  IFS= read -r 'answer?直接回车安装；输入任意字符后回车跳过：' || exit 0
  [[ -z "$answer" ]] || exit 0
}
# 确认后初始化当前脚本与独立日志。
initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  : > "$LOG_FILE"
}
# 同步显示并保存安装诊断。
log() {
  print -r -- "$*" | /usr/bin/tee -a "$LOG_FILE"
}
# 检查完整 Xcode 与本工程文件，不自动改 xcode-select。
check_environment() {
  [[ "$(/usr/bin/uname -s)" == Darwin ]] || { log '✖ 仅支持 macOS。'; exit 1; }
  [[ -d "${PROJECT_ROOT}/JobsPathCopier.xcodeproj" ]] || { log '✖ 缺少本工程。'; exit 1; }
  local command_path=""
  for command_path in /usr/bin/xcodebuild /usr/bin/xcrun /usr/bin/pluginkit /usr/bin/open /usr/bin/killall; do
    [[ -x "$command_path" ]] || { log "✖ 缺少系统命令：$command_path"; exit 1; }
  done
  /usr/bin/xcodebuild -version 2>&1 | /usr/bin/tee -a "$LOG_FILE" || { log '✖ 请选择完整 Xcode 并完成首次启动。'; exit 1; }
  /usr/bin/xcrun --sdk macosx --show-sdk-path 2>&1 | /usr/bin/tee -a "$LOG_FILE" || { log '✖ macOS SDK 不可用。'; exit 1; }
}
# 构建时禁止 Build Phase 注册，成功后由本入口统一处理。
build_extension() {
  log "来源：本地源码 ${PROJECT_ROOT}"
  log "目标：${APP_PATH}"
  JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1 /usr/bin/xcodebuild \
    -project "${PROJECT_ROOT}/JobsPathCopier.xcodeproj" \
    -scheme JobsPathCopier -configuration Debug \
    -destination "platform=macOS,arch=$(/usr/bin/uname -m)" \
    -derivedDataPath "${PROJECT_ROOT}/work/DerivedData" build 2>&1 | /usr/bin/tee -a "$LOG_FILE"
  local build_result=${pipestatus[1]}
  (( build_result == 0 )) || { log "✖ 构建失败，退出码 ${build_result}。"; exit "$build_result"; }
  [[ -d "$EXTENSION_PATH" ]] || { log '✖ 构建成功但缺少 Finder 扩展产物。'; exit 1; }
}
# 仅注册固定扩展，在 App 开启后允许系统弹出自动化与扩展权限请求。
register_extension() {
  /usr/bin/pluginkit -a "$EXTENSION_PATH" 2>&1 | /usr/bin/tee -a "$LOG_FILE" || exit 1
  /usr/bin/pluginkit -e use -i "$EXTENSION_ID" 2>&1 | /usr/bin/tee -a "$LOG_FILE" || exit 1
  /usr/bin/open "$APP_PATH" || { log '✖ 无法打开宿主 App。'; exit 1; }
  manager_restart_finder 2>&1 | /usr/bin/tee -a "$LOG_FILE" || log 'ℹ Finder 当前未运行。'
  log "✔ 已提交扩展启用请求；如菜单未出现，请在宿主中打开扩展设置。日志：${LOG_FILE}"
}
# 编排独立安装流程，确认前不产生业务副作用。
main() {
  show_script_intro_and_wait # 先展示范围，等待回车安装或非空输入跳过。
  initialize_runtime # 确认后准备脚本选项和日志。
  check_environment # 核验完整 Xcode、macOS SDK 与工程。
  build_extension # 只构建本工程并阻止重复注册。
  register_extension # 注册固定扩展、打开宿主并刷新 Finder。
}


# 外层统一负责交互；这里仅准备原分支的展示路径与经过验证的功能参数。
show_script_intro_and_wait() {
  (( $+functions[prepare_display_context] )) && prepare_display_context
  return 0
}
main "$@"
)
}

# 原uninstall实现只在所选分支加载，保留可独立复制运行的能力。
run_uninstall_operation() {
(
# 脚本自述：
# - 脚本名称：ManageExtension.zsh（App 内部后台管理器）
# - 核心用途：停止并注销 JobsPathCopier Finder Sync Extension，同时清理旧 Automator 服务版入口。
# - 影响范围：只处理固定扩展、Xcode / 本工作区构建产物和旧 Automator 服务。
# - 运行提示：运行后会先打印内置自述；按回车执行卸载并重启 Finder。按 Ctrl+C 可取消。

# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")/.." && pwd)"
SCRIPT_PATH="${ZSH_ARGZERO:A}"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT_BASENAME="【MacOS】管理复制绝对路径Finder扩展"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"

EXTENSION_ID="com.jobs.JobsPathCopier.FinderSyncExtension"
APP_BUNDLE_ID="com.jobs.JobsPathCopier"
APP_REFRESH_MARKER="/tmp/JobsPathCopierNeedsFinderRestart"
APP_RUNTIME_LOG="/tmp/JobsPathCopier.log"
AUTOMATOR_SERVICE_DIR="${HOME}/Library/Services/复制绝对路径.workflow"
AUTOMATOR_HELPER_SCRIPT="${HOME}/Library/Scripts/Jobs/CopyAbsolutePath.zsh"
LOCAL_DERIVED_DATA_DIR="${WORKSPACE_DIR}/work/JobsPathCopierDerivedData"

log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
color_echo()     { log "\033[1;32m$1\033[0m"; }
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
warm_echo()      { log "\033[1;33m$1\033[0m"; }
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
err_echo()       { log "\033[1;31m$1\033[0m"; }
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
gray_echo()      { log "\033[0;90m$1\033[0m"; }
bold_echo()      { log "\033[1m$1\033[0m"; }
underline_echo() { log "\033[4m$1\033[0m"; }

# 初始化 zsh 运行选项和日志文件。
init_runtime() {
  setopt NO_NOMATCH
  : > "$LOG_FILE"
}
# 打印脚本内置自述并等待用户确认阅读。
show_script_intro_and_wait() {
  clear
  highlight_echo "============================== 脚本自述 ==============================" | jobs_intro_style title
  note_echo "当前脚本：${SCRIPT_PATH}" | jobs_intro_style body
  note_echo "核心用途：卸载 Finder 右键菜单里的“复制绝对路径”。" | jobs_intro_style body
  warn_echo "影响范围：停止并注销 ${EXTENSION_ID}" | jobs_intro_style body
  warn_echo "影响范围：删除 Xcode DerivedData 下的 JobsPathCopier.app 构建产物。" | jobs_intro_style body
  warn_echo "影响范围：删除本工作区 ${LOCAL_DERIVED_DATA_DIR} 旧构建产物。" | jobs_intro_style body
  warn_echo "影响范围：删除 ${APP_REFRESH_MARKER} 运行时刷新标记。" | jobs_intro_style body
  warn_echo "影响范围：删除旧 Automator 服务 ${AUTOMATOR_SERVICE_DIR}" | jobs_intro_style body
  warn_echo "影响范围：自动重启 Finder，刷新 Finder Sync 扩展缓存。" | jobs_intro_style body
  warn_echo "执行策略：按回车后立即开始卸载并重启 Finder；按 Ctrl+C 才会取消。" | jobs_intro_style body
  gray_echo "不会删除 JobsPathCopier 工程源码。" | jobs_intro_style body
  gray_echo "取消方式：按 Ctrl+C 终止，不会继续执行卸载。" | jobs_intro_style body
  gray_echo "日志位置：${LOG_FILE}" | jobs_intro_style body
  highlight_echo "=======================================================================" | jobs_intro_style title
  echo "" | jobs_intro_style body

  if [[ ! -t 0 ]]; then
    error_echo "当前没有可交互输入，无法确认卸载。请在终端里运行本脚本。"
    exit 1
  fi

  local _
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 检查卸载流程依赖的系统命令。
check_environment() {
  local missing_commands=()
  local command_name=""

  for command_name in pluginkit pgrep pkill kill killall rm awk grep sed find xargs; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      missing_commands+=("$command_name")
    fi
  done

  if (( ${#missing_commands[@]} > 0 )); then
    error_echo "缺少必要命令：${(j:, :)missing_commands}"
    exit 1
  fi

  if [[ "$(uname -s)" != "Darwin" ]]; then
    error_echo "当前系统不是 MacOS，无法卸载 Finder 扩展。"
    exit 1
  fi
}
# 输出当前 Finder Sync 扩展注册状态，方便卸载前后对比。
print_current_extension_status() {
  note_echo "当前扩展注册状态："
  /usr/bin/pluginkit -m -i "$EXTENSION_ID" -A -D -vv 2>/dev/null | tee -a "$LOG_FILE" || true
}
# 临时禁用 Finder Sync 扩展，避免卸载过程中被 Finder 再次拉起。
disable_extension() {
  note_echo "禁用 Finder Sync 扩展：${EXTENSION_ID}"
  /usr/bin/pluginkit -e ignore -i "$EXTENSION_ID" 2>&1 | tee -a "$LOG_FILE" || true
}
# 停止仍在运行的宿主 App，避免已删除的构建产物继续驻留。
stop_host_application() {
  local pid=""

  note_echo "停止 JobsPathCopier 宿主 App。"
  /usr/bin/pkill -x 'JobsPathCopier' 2>/dev/null || true
  /usr/bin/pgrep -f '/JobsPathCopier.app/Contents/MacOS/JobsPathCopier' 2>/dev/null | while IFS= read -r pid; do
    if [[ -n "$pid" && "$pid" != "$$" ]]; then
      /bin/kill "$pid" 2>/dev/null || true
    fi
  done
}
# 停止已经被 Finder 拉起的扩展进程。
stop_extension_processes() {
  note_echo "停止 JobsPathCopyFinderSync 扩展进程。"
  /usr/bin/pkill -f 'JobsPathCopyFinderSync.appex/Contents/MacOS/JobsPathCopyFinderSync' 2>/dev/null || true
}
# 清除临时禁用选择并注销 Finder Sync 扩展。
reset_election_and_unregister_extension() {
  note_echo "清除扩展禁用选择，确保下次 Xcode 调试可以重新启用。"
  /usr/bin/pluginkit -e default -i "$EXTENSION_ID" 2>&1 | tee -a "$LOG_FILE" || true

  local extension_paths=()
  extension_paths=("${(@f)$(
    /usr/bin/pluginkit -m -i "$EXTENSION_ID" -A -D -vv 2>/dev/null \
      | /usr/bin/awk -F '= ' '/Path = / {print $2}'
  )}")

  local extension_path=""
  for extension_path in "${extension_paths[@]}"; do
    if [[ -n "$extension_path" && -e "$extension_path" ]]; then
      note_echo "注销扩展路径：${extension_path}"
      /usr/bin/pluginkit -r "$extension_path" 2>&1 | tee -a "$LOG_FILE" || true
    fi
  done
}
# 清理 App 和构建阶段留下的临时标记。
clear_runtime_markers() {
  note_echo "清理 JobsPathCopier 运行时标记。"
  /bin/rm -f "$APP_REFRESH_MARKER" "$APP_RUNTIME_LOG"
}
# 删除 Xcode DerivedData 下的宿主 App 构建产物。
remove_deriveddata_app_bundles() {
  local app_paths=()
  app_paths=("${(@f)$(
    /usr/bin/find "${HOME}/Library/Developer/Xcode/DerivedData" \
      -path '*JobsPathCopier*.app' \
      -type d \
      -print 2>/dev/null
  )}")

  local app_path=""
  for app_path in "${app_paths[@]}"; do
    if [[ -n "$app_path" && "$app_path" == "${HOME}/Library/Developer/Xcode/DerivedData/"* ]]; then
      note_echo "删除构建产物：${app_path}"
      /bin/rm -rf "$app_path"
    fi
  done

  if [[ -d "$LOCAL_DERIVED_DATA_DIR" && "$LOCAL_DERIVED_DATA_DIR" == "${WORKSPACE_DIR}/work/"* ]]; then
    note_echo "删除本工作区旧构建产物：${LOCAL_DERIVED_DATA_DIR}"
    /bin/rm -rf "$LOCAL_DERIVED_DATA_DIR"
  else
    gray_echo "未发现本工作区旧构建产物：${LOCAL_DERIVED_DATA_DIR}"
  fi
}
# 清理旧 Automator 服务版右键入口。
remove_legacy_automator_service() {
  if [[ -d "$AUTOMATOR_SERVICE_DIR" ]]; then
    note_echo "删除旧 Automator 服务：${AUTOMATOR_SERVICE_DIR}"
    /bin/rm -rf "$AUTOMATOR_SERVICE_DIR"
  else
    gray_echo "未发现旧 Automator 服务：${AUTOMATOR_SERVICE_DIR}"
  fi

  if [[ -f "$AUTOMATOR_HELPER_SCRIPT" ]]; then
    note_echo "删除旧 Automator 辅助脚本：${AUTOMATOR_HELPER_SCRIPT}"
    /bin/rm -f "$AUTOMATOR_HELPER_SCRIPT"
  else
    gray_echo "未发现旧 Automator 辅助脚本：${AUTOMATOR_HELPER_SCRIPT}"
  fi
}
# 刷新 MacOS Services 缓存，让“服务”子菜单尽快移除旧入口。
refresh_services_cache() {
  local pbs_path="/System/Library/CoreServices/pbs"

  if [[ -x "$pbs_path" ]]; then
    note_echo "刷新 MacOS Services 缓存。"
    "$pbs_path" -flush 2>&1 | tee -a "$LOG_FILE" || true
  else
    gray_echo "未找到 pbs，跳过 Services 缓存刷新。"
  fi
}
# 重启 Finder，强制清掉 Finder Sync 扩展缓存。
restart_finder_after_uninstall() {
  note_echo "重启 Finder，刷新 Finder Sync 扩展缓存。"
  manager_restart_finder 2>&1 | tee -a "$LOG_FILE" || true
}
# 打印卸载完成后的状态和提示。
print_done_tips() {
  echo ""
  success_echo "卸载流程已完成。"
  gray_echo "Finder 已重启；如果菜单仍短暂显示，请注销后重新登录。"
  gray_echo "工程源码仍保留在 JobsPathCopier。"
  gray_echo "以后重新运行 Xcode 工程时，App 会再次注册并启用 Finder 扩展。"
  gray_echo "日志位置：${LOG_FILE}"
}
# 编排脚本自述、卸载和刷新流程。
main() {
  show_script_intro_and_wait # 展示卸载影响范围，按回车后开始执行。
  init_runtime # 用户确认后初始化日志和 zsh 运行选项。
  check_environment # 检查卸载依赖的系统命令和 MacOS 环境。
  print_current_extension_status # 输出卸载前扩展注册状态，便于排查。
  disable_extension # 临时禁用 Finder Sync Extension，阻止卸载期间重新拉起。
  stop_host_application # 停止宿主 App，释放即将删除的构建产物。
  stop_extension_processes # 停止已运行的扩展进程。
  reset_election_and_unregister_extension # 清除禁用选择并注销 Finder Sync Extension。
  clear_runtime_markers # 清除 App 运行时刷新标记和旧日志。
  remove_deriveddata_app_bundles # 删除 Xcode DerivedData 里的构建产物。
  remove_legacy_automator_service # 清理旧 Automator 服务版入口。
  refresh_services_cache # 刷新 Services 缓存，移除“服务”子菜单旧入口。
  restart_finder_after_uninstall # 重启 Finder，清掉 Finder Sync 扩展缓存。
  print_done_tips # 输出卸载结果和后续提示。
}


# 外层统一负责交互；这里仅准备原分支的展示路径与经过验证的功能参数。
show_script_intro_and_wait() {
  (( $+functions[prepare_display_context] )) && prepare_display_context
  return 0
}
confirm_uninstall() {
  return 0
}
main "$@"
)
}

manager_main "$@"
