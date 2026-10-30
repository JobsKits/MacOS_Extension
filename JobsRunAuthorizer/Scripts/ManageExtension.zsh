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
MANAGER_UI_SCOPE="run-authorize"
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
# - 核心用途：独立构建、注册并启用“运行授权”文件右键扩展。
# - 影响范围：只构建本工程、启用固定扩展并刷新 Finder；不修改任何目标文件权限。
# - 运行提示：阅读自述后，直接回车安装；输入任意字符后回车跳过，Ctrl+C 取消。
# shell: zsh
#
#  Scripts/ManageExtension.zsh
#  JobsRunAuthorizer
#
#  Created by Jobs on 2026年10月22日，星期四.
#

SCRIPT_DIR=""
PROJECT_ROOT=""
LOG_FILE=""
APP_PATH=""
EXTENSION_PATH=""
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
APP_ID="com.jobs.JobsRunAuthorizer"
EXTENSION_ID="com.jobs.JobsRunAuthorizer.FinderSyncExtension"
# 计算源码、产物和日志的位置，确认前不写文件。
prepare_display_context() {
  local temporary_root="${TMPDIR:-/tmp}"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")/.." && pwd)"
  PROJECT_ROOT="${SCRIPT_DIR}"
  LOG_FILE="${temporary_root%/}/JobsRunAuthorizerInstall.log"
  APP_PATH="${PROJECT_ROOT}/work/DerivedData/Build/Products/Debug/JobsRunAuthorizer.app"
  EXTENSION_PATH="${APP_PATH}/Contents/PlugIns/JobsRunAuthorizerFinderSync.appex"
}
# 彩色终端突出自述层级，其余环境输出纯文本。
intro_line() {
  local role="$1"
  local message="$2"
  if [[ -t 1 && -n "${TERM:-}" && "${TERM}" != dumb && -z "${NO_COLOR+x}" ]]; then
    if [[ "${role}" == title ]]; then
      /usr/bin/printf '\033[1;31m%s\033[0m\n' "${message}"
    else
      /usr/bin/printf '\033[0;34m%s\033[0m\n' "${message}"
    fi
  else
    print -r -- "${message}"
  fi
}
# 先说明安装范围，再等待回车安装或非空输入跳过。
show_script_intro_and_wait() {
  prepare_display_context
  intro_line title '━━━━━━━━━━ 安装运行授权 Finder 扩展 ━━━━━━━━━━'
  intro_line body "1、来源：本地源码 ${PROJECT_ROOT}。"
  intro_line body "2、目标：${APP_PATH}；系统从此处启动扩展，请保留产物。"
  intro_line body '3、影响：构建并启用“运行授权”，刷新 Finder；安装时不修改任何目标文件权限。'
  intro_line body '4、运行策略：直接回车安装；输入任意字符后回车跳过。Ctrl+C 取消。'
  intro_line body "5、日志：${LOG_FILE}。"
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '✖ 请在可交互终端运行。'
    exit 1
  fi
  local answer=""
  IFS= read -r 'answer?直接回车安装；输入任意字符后回车跳过：' || exit 0
  [[ -z "${answer}" ]] || exit 0
}
# 确认后开启 zsh 选项与本次日志。
initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  : > "${LOG_FILE}" || exit 1
}
# 将安装结果同时写入终端和日志。
log() {
  print -r -- "$*" | /usr/bin/tee -a "${LOG_FILE}"
}
# 验证完整 Xcode 与 SDK，保持现有开发目录配置。
check_environment() {
  [[ "$(/usr/bin/uname -s)" == Darwin ]] || { log '✖ 仅支持 macOS。'; exit 1; }
  [[ -f "${PROJECT_ROOT}/JobsRunAuthorizer.xcodeproj/project.pbxproj" ]] || { log '✖ 缺少工程源码。'; exit 1; }
  local executable=""
  for executable in /usr/bin/xcodebuild /usr/bin/xcrun /usr/bin/pluginkit /usr/bin/open /usr/bin/killall /usr/bin/codesign /usr/bin/pkill /usr/libexec/PlistBuddy "${LSREGISTER}"; do
    [[ -x "${executable}" ]] || { log "✖ 缺少系统命令：${executable}"; exit 1; }
  done
  /usr/bin/xcodebuild -version 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || { log '✖ 完整 Xcode 不可用，请先完成首次启动。'; exit 1; }
  /usr/bin/xcrun --sdk macosx --show-sdk-path 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || { log '✖ macOS SDK 不可用。'; exit 1; }
}
# 只构建本工程，注册由安装器统一负责。
build_extension() {
  log "来源：本地源码 ${PROJECT_ROOT}"
  log "目标：${APP_PATH}"
  JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1 /usr/bin/xcodebuild \
    -project "${PROJECT_ROOT}/JobsRunAuthorizer.xcodeproj" \
    -scheme JobsRunAuthorizer \
    -configuration Debug \
    -destination "platform=macOS,arch=$(/usr/bin/uname -m)" \
    -derivedDataPath "${PROJECT_ROOT}/work/DerivedData" \
    build 2>&1 | /usr/bin/tee -a "${LOG_FILE}"
  local build_result=${pipestatus[1]}
  (( build_result == 0 )) || { log "✖ 构建失败，退出码 ${build_result}。"; exit "${build_result}"; }
  [[ -d "${EXTENSION_PATH}" ]] || { log '✖ 缺少 Finder 扩展产物。'; exit 1; }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP_PATH}/Contents/Info.plist")" == "${APP_ID}" ]] || { log '✖ App 身份不匹配。'; exit 1; }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${EXTENSION_PATH}/Contents/Info.plist")" == "${EXTENSION_ID}" ]] || { log '✖ 扩展身份不匹配。'; exit 1; }
  /usr/bin/codesign --verify --deep --strict "${APP_PATH}" 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || { log '✖ 产物签名验证失败。'; exit 1; }
}
# 按本功能的 Bundle ID 注销旧宿主 URL 登记，保留所有 App 文件。
unregister_previous_hosts() {
  local registered_app=""
  /usr/bin/pkill -x JobsRunAuthorizer 2>/dev/null || true
  while IFS= read -r registered_app; do
    [[ "${registered_app}" == /*'/JobsRunAuthorizer.app' && "${registered_app}" != "${APP_PATH}" ]] || continue
    if [[ -e "${registered_app}" ]]; then
      [[ -d "${registered_app}" && ! -L "${registered_app}" ]] || continue
      [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${registered_app}/Contents/Info.plist" 2>/dev/null)" == "${APP_ID}" ]] || continue
    fi
    log "ℹ 注销本宿主旧 URL 登记：${registered_app}"
    "${LSREGISTER}" -u "${registered_app}" 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || exit 1
  done < <("${LSREGISTER}" -dump 2>/dev/null | /usr/bin/awk -v expected="${APP_ID}" '
    function flush() {
      if (identifier == expected && bundle_path != "") print bundle_path
      identifier = ""; bundle_path = ""
    }
    /^--------------------------------------------------------------------------------$/ { flush(); next }
    /^path:[[:space:]]+/ {
      bundle_path = $0
      sub(/^path:[[:space:]]+/, "", bundle_path)
      sub(/[[:space:]]+[(]0x[0-9a-fA-F]+[)].*$/, "", bundle_path)
    }
    /^identifier:[[:space:]]+/ { identifier = $0; sub(/^identifier:[[:space:]]+/, "", identifier) }
    END { flush() }
  ')
}
# 注销同 ID 的旧路径，避免两种安装入口留下多个有效副本。
unregister_previous_copies() {
  local registered_path=""
  while IFS= read -r registered_path; do
    [[ "${registered_path}" == /*'/JobsRunAuthorizer.app/Contents/PlugIns/JobsRunAuthorizerFinderSync.appex' ]] || continue
    [[ "${registered_path}" != "${EXTENSION_PATH}" ]] || continue
    if [[ -e "${registered_path}" || -L "${registered_path}" ]]; then
      [[ -d "${registered_path}" && ! -L "${registered_path}" ]] || continue
      [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${registered_path}/Contents/Info.plist" 2>/dev/null)" == "${EXTENSION_ID}" ]] || continue
    fi
    log "ℹ 注销本扩展旧副本：${registered_path}"
    /usr/bin/pluginkit -r "${registered_path}" 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || exit 1
  done < <(/usr/bin/pluginkit -m -i "${EXTENSION_ID}" -A -D -vv 2>/dev/null | /usr/bin/awk '/Path = / { sub(/^.*Path = /, ""); print }')
}
# 注册固定扩展并初始化宿主，首次使用时由系统处理权限。
register_extension() {
  unregister_previous_copies
  unregister_previous_hosts
  "${LSREGISTER}" -f "${APP_PATH}" 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || { log '✖ 宿主 URL 注册失败。'; exit 1; }
  /usr/bin/pluginkit -a "${EXTENSION_PATH}" 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || exit 1
  /usr/bin/pluginkit -e use -i "${EXTENSION_ID}" 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || exit 1
  /usr/bin/open -n "${APP_PATH}" --args --initialize-finder-extension || { log '✖ 无法初始化宿主。'; exit 1; }
  manager_restart_finder 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || log 'ℹ Finder 当前未运行。'
  log '✔ 已请求启用扩展。只选中一个普通文件后右键，选择“运行授权”。'
  log 'ℹ 菜单未出现时，在系统设置的 Finder 扩展中启用 JobsRunAuthorizer；首次操作允许控制 Terminal。'
}
# 编排确认、自检、构建与扩展注册。
main() {
  show_script_intro_and_wait # 先说明源码、产物、影响及取消方式。
  initialize_runtime # 确认后准备本次运行日志。
  check_environment # 核验完整开发工具链与工程。
  build_extension # 独立构建并验证 App 身份和签名。
  register_extension # 注册固定扩展并刷新文件菜单。
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
# - 核心用途：禁用并注销 JobsRunAuthorizer 的 Finder 扩展，移除已登记的本应用构建产物。
# - 影响范围：仅处理固定 Bundle ID，保留项目源码和所有曾授权的文件；确认后重启 Finder。
# - 运行提示：先阅读内置自述并按回车，再核对路径并输入 YES；其它输入取消。
# shell: zsh
#
#  Scripts/ManageExtension.zsh
#  JobsRunAuthorizer
#
#  Created by Jobs on 2026年10月22日，星期四.
#

SCRIPT_DIR=""
SCRIPT_PATH=""
SCRIPT_BASENAME=""
LOG_FILE=""
EXTENSION_ID="com.jobs.JobsRunAuthorizer.FinderSyncExtension"
APP_ID="com.jobs.JobsRunAuthorizer"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
EXTENSION_PATHS=()
APP_PATHS=()
# 准备显示路径，不写日志或修改扩展状态。
prepare_display_context() {
  local temporary_root="${TMPDIR:-/tmp}"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")/.." && pwd)"
  SCRIPT_PATH="${ZSH_ARGZERO:A}"
  SCRIPT_BASENAME="【MacOS】管理运行授权Finder扩展"
  LOG_FILE="${temporary_root%/}/${SCRIPT_BASENAME}.log"
}
# 为交互终端显示红色标题和蓝色正文，其它输出保持纯文本。
intro_line() {
  local role="$1"
  local message="$2"
  if [[ -t 1 && -n "${TERM:-}" && "${TERM}" != dumb && -z "${NO_COLOR+x}" ]]; then
    if [[ "${role}" == title ]]; then
      /usr/bin/printf '\033[1;31m%s\033[0m\n' "${message}"
    else
      /usr/bin/printf '\033[0;34m%s\033[0m\n' "${message}"
    fi
  else
    print -r -- "${message}"
  fi
}
# 先展示固定自述，再等待用户确认阅读，避免误触卸载。
show_script_intro_and_wait() {
  prepare_display_context
  intro_line title "================ Scripts/ManageExtension.zsh ================"
  intro_line body "1、核心用途：禁用、注销‘运行授权’右键菜单。"
  intro_line body "2、影响范围：只删除 Bundle ID 为 ${APP_ID} 的已登记 App；保留源码和所有曾授权的文件。"
  intro_line body "3、执行策略：回车后先显示待处理路径；输入 YES 才卸载并重启 Finder，其它输入取消。"
  intro_line body "4、取消方式：按 Ctrl+C；非交互输入会退出。"
  intro_line body "5、日志位置：${LOG_FILE}"
  if [[ ! -t 0 ]]; then
    intro_line body "错误：没有可交互输入，请在终端中执行。"
    exit 1
  fi
  read -r '?已了解用途，按回车查看待卸载路径；Ctrl+C 取消：' _ || exit 0
}
# 用户确认阅读后初始化日志及 zsh 选项。
initialize_runtime() {
  setopt NO_NOMATCH
  setopt PIPE_FAIL
  : > "${LOG_FILE}"
}
# 同步输出到终端和本次运行日志。
log() {
  print -r -- "$1" | /usr/bin/tee -a "${LOG_FILE}"
}
# 检查本次卸载需要的系统工具。
check_environment() {
  local executable=""
  [[ "$(/usr/bin/uname -s)" == Darwin ]] || { log '错误：仅支持 macOS。'; exit 1; }
  for executable in /usr/bin/pluginkit /usr/libexec/PlistBuddy /usr/bin/awk /usr/bin/pkill /usr/bin/killall /bin/rm "${LSREGISTER}"; do
    [[ -x "${executable}" ]] || { log "错误：缺少 ${executable}"; exit 1; }
  done
}
# 精确核对 App 名称、真实目录和 Bundle ID，避免删除其它应用。
is_owned_app() {
  local candidate="$1"
  [[ "${candidate}" == /* && "${candidate:t}" == 'JobsRunAuthorizer.app' && -d "${candidate}" && ! -L "${candidate}" ]] || return 1
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${candidate}/Contents/Info.plist" 2>/dev/null)" == "${APP_ID}" ]]
}
# 从固定扩展的系统注册信息收集路径，展示给用户核对。
collect_registered_paths() {
  local extension_path=""
  local app_path=""
  while IFS= read -r extension_path; do
    [[ "${extension_path}" == /*'/JobsRunAuthorizer.app/Contents/PlugIns/JobsRunAuthorizerFinderSync.appex' ]] || continue
    if [[ -e "${extension_path}" || -L "${extension_path}" ]]; then
      [[ -d "${extension_path}" && ! -L "${extension_path}" ]] || continue
      [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${extension_path}/Contents/Info.plist" 2>/dev/null)" == "${EXTENSION_ID}" ]] || continue
    fi
    EXTENSION_PATHS+=("${extension_path}")
    app_path="${extension_path%/Contents/PlugIns/JobsRunAuthorizerFinderSync.appex}"
    if is_owned_app "${app_path}" && (( ! ${APP_PATHS[(Ie)${app_path}]} )); then
      APP_PATHS+=("${app_path}")
    fi
  done < <(/usr/bin/pluginkit -m -i "${EXTENSION_ID}" -A -D -vv 2>/dev/null | /usr/bin/awk '/Path = / { sub(/^.*Path = /, ""); print }')
  log "扩展 ID：${EXTENSION_ID}"
  for extension_path in "${EXTENSION_PATHS[@]}"; do
    log "注销路径：${extension_path}"
  done
  for app_path in "${APP_PATHS[@]}"; do
    log "删除已核验 App：${app_path}"
  done
  if (( ${#EXTENSION_PATHS[@]} == 0 )); then
    log '没有发现已登记副本；仅清除扩展启用状态并刷新 Finder。'
  fi
}
# 删除 App 和重启 Finder 之前要求明确输入 YES。
confirm_uninstall() {
  local answer=""
  IFS= read -r 'answer?输入 YES 卸载上述固定扩展并重启 Finder，其它输入取消：' || exit 0
  if [[ "${answer}" != YES ]]; then
    log '已取消，没有修改应用或扩展注册。'
    exit 0
  fi
}
# 停用并注销指定扩展，只移除二次核验通过的自有 App。
uninstall_extension() {
  local extension_path=""
  local app_path=""
  /usr/bin/pluginkit -e ignore -i "${EXTENSION_ID}" 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || log '提示：扩展可能已经停用或未安装。'
  /usr/bin/pkill -x 'JobsRunAuthorizer' 2>/dev/null || true
  /usr/bin/pkill -x 'JobsRunAuthorizerFinderSync' 2>/dev/null || true
  for extension_path in "${EXTENSION_PATHS[@]}"; do
    /usr/bin/pluginkit -r "${extension_path}" 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || { log "错误：注销失败 ${extension_path}"; exit 1; }
  done
  for app_path in "${APP_PATHS[@]}"; do
    is_owned_app "${app_path}" || { log "错误：App 核验发生变化，停止删除 ${app_path}"; exit 1; }
    "${LSREGISTER}" -u "${app_path}" 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || { log "错误：宿主 URL 注销失败 ${app_path}"; exit 1; }
    /bin/rm -rf -- "${app_path}" || { log "错误：删除失败 ${app_path}"; exit 1; }
  done
  /bin/rm -f -- '/tmp/JobsRunAuthorizerNeedsFinderRestart'
  log '固定 Finder 扩展已停用；项目源码与所有曾授权的文件保留。'
}
# 刷新 Finder 使已卸载菜单退出显示。
refresh_finder() {
  manager_restart_finder 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || log '提示：Finder 当前没有运行，无需重启。'
  log "卸载完成，日志：${LOG_FILE}"
}
# 编排自述、核验、明确确认和卸载。
main() {
  show_script_intro_and_wait # 先展示内置自述并等待阅读确认。
  initialize_runtime # 确认阅读后初始化选项和日志。
  check_environment # 检查系统和卸载命令。
  collect_registered_paths # 收集并显示固定扩展的真实注册路径。
  confirm_uninstall # 删除 App 及重启 Finder 前要求输入 YES。
  uninstall_extension # 精确注销扩展并清理核验通过的 App。
  refresh_finder # 刷新 Finder 并显示日志位置。
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
