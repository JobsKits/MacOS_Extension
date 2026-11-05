#!/bin/zsh
# 脚本自述：
# - 脚本名称：ManageExtension.zsh（App 内部后台管理器）
# - 核心用途：一个入口管理本功能的安装 / 更新、卸载与构建产物清理。
# - 影响范围：当前用户 Finder 菜单、对应构建产物与专用功能配置；保留源码和业务数据。
# - 运行提示：直接打开 GUI，在面板选择安装 / 更新或卸载；底部实时日志允许复制。
# shell: zsh

MANAGER_ACTION=""
MANAGER_STOP_REQUEST_FILE="${JOBS_FINDER_STOP_REQUEST_FILE:-}"
MANAGER_NON_INTERACTIVE=0
MANAGER_SKIP_RESTART=0
MANAGER_REQUESTED_FEATURES=""
MANAGER_ENTRY_DIR=""
MANAGER_GUI_SESSION=0
MANAGER_GUI_LEAF_FEATURES=""
MANAGER_UI_SCOPE="flutter-sdk-manage"
# 支持上级面板在完成确认后调用；显式参数不会改变本目录的功能边界。
manager_parse_options() {
  local install_location="${JOBS_FINDER_INSTALL_LOCATION:-build}" cleanup_build_products="${JOBS_FINDER_CLEANUP_BUILD_PRODUCTS:-0}"
  MANAGER_ENTRY_DIR="${ZSH_ARGZERO:A:h:h}"
  while (( $# > 0 )); do
    case "$1" in
      --action) (( $# >= 2 )) || return 2; MANAGER_ACTION="$2"; shift ;;
      --action=*) MANAGER_ACTION="${1#--action=}" ;;
      --install-location) (( $# >= 2 )) || return 2; install_location="$2"; shift ;;
      --install-location=*) install_location="${1#--install-location=}" ;;
      --cleanup-build-products) cleanup_build_products=1 ;;
      --stop-request-file) (( $# >= 2 )) && [[ "$2" == /* ]] || return 2; MANAGER_STOP_REQUEST_FILE="$2"; shift ;;
      --stop-request-file=*) MANAGER_STOP_REQUEST_FILE="${1#--stop-request-file=}"; [[ "$MANAGER_STOP_REQUEST_FILE" == /* ]] || return 2 ;;
      --non-interactive) MANAGER_NON_INTERACTIVE=1 ;;
      --gui-session) MANAGER_GUI_SESSION=1 ;;
      --skip-finder-restart) MANAGER_SKIP_RESTART=1 ;;
      --scope|--features) (( $# >= 2 )) || return 2; MANAGER_REQUESTED_FEATURES="$2"; shift ;;
      --features=*) MANAGER_REQUESTED_FEATURES="${1#--features=}" ;;
      --help|-h) print '用法：双击管理，或 --action install|uninstall|cleanup --non-interactive [--features 功能ID,...] [--skip-finder-restart] [--install-location build|applications] [--cleanup-build-products] [--stop-request-file PATH]'; return 10 ;;
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
  manager_prepare_gui_features || return $?
  [[ -z "$MANAGER_ACTION" || "$MANAGER_ACTION" == install || "$MANAGER_ACTION" == uninstall || "$MANAGER_ACTION" == cleanup ]] || return 2
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
    if [[ "$MANAGER_ACTION" == cleanup ]]; then
      local cleanup_identifier="$(manager_gui_identifier "$mapped")"
      (( ${allowed[(Ie)$cleanup_identifier]} )) || { print -u2 -r -- "✖ 功能不属于本入口：$feature"; return 2; }
    fi
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
  local -x JOBS_FINDER_STOP_REQUEST_FILE=""
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
    local arguments=(--scope "$scope" --action "${MANAGER_ACTION:-install}" --install-location "$JOBS_FINDER_INSTALL_LOCATION")
    [[ "${JOBS_FINDER_CLEANUP_BUILD_PRODUCTS:-0}" != 1 ]] || arguments+=(--cleanup-build-products)
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
  manager_intro_line body '安装构建并启用菜单；卸载保留未选菜单；清理只删除已安装 App 对应构建产物。'
  return 0
}
# 逐叶回传真实运行状态；不使用无法核实的百分比。
manager_emit_progress() {
  local state="$1" feature="" message="" identifier=""
  case "$state" in
    running)
      case "$MANAGER_ACTION" in
        uninstall) message='正在卸载' ;;
        cleanup) message='正在清理构建产物' ;;
        *) message='正在安装 / 更新' ;;
      esac
      ;;
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
  if [[ "$MANAGER_ACTION" == cleanup ]]; then
    run_cleanup_operation
    return $?
  fi
  if [[ "$MANAGER_ACTION" == install ]]; then
    run_install_operation
  else
    run_uninstall_operation
  fi
}

# 兼容功能固定为所属 Flutter 叶子；常规安装与卸载都由统一包承接。
run_flutter_operation() {
  local action="$1" entry="${MANAGER_ENTRY_DIR:h}/JobsFlutterTools/Scripts/ManageExtension.zsh"
  local extra=() allowed=(sdk-manage) requested=() feature="" selected_features='sdk-manage'
  if [[ -n "$MANAGER_REQUESTED_FEATURES" ]]; then
    requested=("${(@s:,:)MANAGER_REQUESTED_FEATURES}")
    for feature in "${requested[@]}"; do
      (( ${allowed[(Ie)$feature]} )) || { print -u2 -r -- "✖ 功能不属于本入口：$feature"; return 2; }
    done
    selected_features="$MANAGER_REQUESTED_FEATURES"
  fi
  [[ -f "$entry" ]] || { print -u2 '✖ 请保留包含 JobsFlutterTools 的完整 MacOS@Extension 目录。'; return 1; }
  (( ! MANAGER_SKIP_RESTART )) || extra+=(--skip-finder-restart)
  [[ "${JOBS_FINDER_CLEANUP_BUILD_PRODUCTS:-0}" != 1 ]] || extra+=(--cleanup-build-products)
  [[ -z "$MANAGER_STOP_REQUEST_FILE" ]] || extra+=(--stop-request-file "$MANAGER_STOP_REQUEST_FILE")
  /bin/zsh "$entry" --action "$action" --features "$selected_features" --non-interactive "${extra[@]}"
}
run_install_operation() {
  run_flutter_operation install
}
# 独立清理沿用所属宿主和功能白名单，不运行安装或卸载。
run_cleanup_operation() {
  run_flutter_operation cleanup
}
run_uninstall_operation() {
  run_flutter_operation uninstall
}

manager_main "$@"
