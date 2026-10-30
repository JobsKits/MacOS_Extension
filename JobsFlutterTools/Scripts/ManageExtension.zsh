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
MANAGER_UI_SCOPE="flutter-project-setup,flutter-run,flutter-pub-get,flutter-android-dependencies,flutter-pods-dependencies,flutter-spm-dependencies,flutter-ohos-dependencies,flutter-native-dependencies,flutter-flutter-precache,flutter-web-dependencies,flutter-extract,flutter-export-private-dependencies,flutter-import-dependencies,flutter-import-private-dependencies,flutter-export-gradle-dependencies,flutter-import-gradle-dependencies,flutter-export-pods-dependencies,flutter-import-pods-dependencies,flutter-export-spm-dependencies,flutter-import-spm-dependencies,flutter-export-ohos-dependencies,flutter-import-ohos-dependencies,flutter-export-native-dependencies,flutter-import-native-dependencies,flutter-export-precache-dependencies,flutter-import-precache-dependencies,flutter-export-web-dependencies,flutter-import-web-dependencies,flutter-sdk-version,flutter-sdk-manage,flutter-ohos-sdk-manage,flutter-java-manage,flutter-gradle-download,flutter-codegen,flutter-package-ios,flutter-package-android,flutter-package-ohos,flutter-native-doctor,flutter-harmony-doctor,flutter-repair-android,flutter-repair-imports,flutter-repair-namespace,flutter-repair-package-imports,flutter-clean-build-artifacts,flutter-maintenance"
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
  if [[ -n "$MANAGER_REQUESTED_FEATURES" ]]; then
    local feature="" allowed=(project-setup run pub-get android-dependencies pods-dependencies spm-dependencies ohos-dependencies native-dependencies flutter-precache web-dependencies extract export-private-dependencies import-dependencies import-private-dependencies export-gradle-dependencies import-gradle-dependencies export-pods-dependencies import-pods-dependencies export-spm-dependencies import-spm-dependencies export-ohos-dependencies import-ohos-dependencies export-native-dependencies import-native-dependencies export-precache-dependencies import-precache-dependencies export-web-dependencies import-web-dependencies sdk-version sdk-manage ohos-sdk-manage java-manage gradle-download package-ios package-android package-ohos codegen native-doctor harmony-doctor repair-android repair-imports repair-namespace repair-package-imports clean-build-artifacts maintenance) requested=("${(@s:,:)MANAGER_REQUESTED_FEATURES}")
    for feature in "${requested[@]}"; do
      (( ${allowed[(Ie)$feature]} )) || { print -u2 -r -- "✖ 未知功能动作：$feature"; return 2; }
    done
  fi
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
  manager_validate_existing_configuration || return $?
  if [[ "$MANAGER_ACTION" == install ]]; then
    run_install_operation
  else
    run_uninstall_operation
  fi
}

# 损坏的已有配置不能被安装覆盖或被卸载解释成空选择。
manager_validate_existing_configuration() {
  local config="${HOME}/Library/Application Support/JobsFinderExtensions/flutter-tools-features.conf" configured="" feature="" allowed=(project-setup run pub-get android-dependencies pods-dependencies spm-dependencies ohos-dependencies native-dependencies flutter-precache web-dependencies extract export-private-dependencies import-dependencies import-private-dependencies export-gradle-dependencies import-gradle-dependencies export-pods-dependencies import-pods-dependencies export-spm-dependencies import-spm-dependencies export-ohos-dependencies import-ohos-dependencies export-native-dependencies import-native-dependencies export-precache-dependencies import-precache-dependencies export-web-dependencies import-web-dependencies sdk-version sdk-manage ohos-sdk-manage java-manage gradle-download package-ios package-android package-ohos codegen native-doctor harmony-doctor repair-android repair-imports repair-namespace repair-package-imports clean-build-artifacts maintenance)
  [[ -e "$config" || -L "$config" ]] || return 0
  [[ -f "$config" && -r "$config" && ! -L "$config" && ! -L "${config:h}" ]] || { print -u2 '✖ 已有功能配置类型或权限异常，停止。'; return 1; }
  configured="$(<"$config")" || return 1
  [[ -z "$configured" || ( "$configured" != ,* && "$configured" != *, && "$configured" != *,,* ) ]] || { print -u2 '✖ 已有功能配置CSV损坏，停止。'; return 1; }
  for feature in ${(s:,:)configured}; do
    (( ${allowed[(Ie)$feature]} )) || { print -u2 '✖ 已有功能配置包含未知动作，停止。'; return 1; }
  done
}

# 共享宿主只减去指定动作；仍有其它动作时保留完整 App 和配置。
manager_plan_shared_removal() {
  MANAGER_PARTIAL_REMOVAL=0
  [[ -n "$MANAGER_REQUESTED_FEATURES" ]] || return 0
  local config="${HOME}/Library/Application Support/JobsFinderExtensions/flutter-tools-features.conf" feature="" configured="" temporary=""
  local allowed=(project-setup run pub-get android-dependencies pods-dependencies spm-dependencies ohos-dependencies native-dependencies flutter-precache web-dependencies extract export-private-dependencies import-dependencies import-private-dependencies export-gradle-dependencies import-gradle-dependencies export-pods-dependencies import-pods-dependencies export-spm-dependencies import-spm-dependencies export-ohos-dependencies import-ohos-dependencies export-native-dependencies import-native-dependencies export-precache-dependencies import-precache-dependencies export-web-dependencies import-web-dependencies sdk-version sdk-manage ohos-sdk-manage java-manage gradle-download package-ios package-android package-ohos codegen native-doctor harmony-doctor repair-android repair-imports repair-namespace repair-package-imports clean-build-artifacts maintenance) requested=("${(@s:,:)MANAGER_REQUESTED_FEATURES}") enabled=() remaining=()
  for feature in "${requested[@]}"; do
    (( ${allowed[(Ie)$feature]} )) || { print -u2 -r -- "✖ 未知动作：$feature"; return 2; }
  done
  if [[ -f "$config" ]]; then
    configured="$(<"$config")"
    enabled=(${(s:,:)configured})
  else
    local metadata=""
    metadata="$(/usr/bin/pluginkit -m -i "$EXTENSION_ID" -A -D -vv 2>/dev/null)"
    if print -r -- "$metadata" | /usr/bin/grep -q '^+'; then
      enabled=("${allowed[@]}")
    else
      enabled=()
    fi
  fi
  for feature in "${enabled[@]}"; do
    (( ${allowed[(Ie)$feature]} )) || { print -u2 '✖ 已有功能配置无法解析，停止卸载。'; return 1; }
    (( ${requested[(Ie)$feature]} )) || remaining+=("$feature")
  done
  (( ${#remaining} > 0 )) || return 0
  [[ ! -L "$config" && ! -L "${config:h}" ]] || { print -u2 '✖ 配置路径是符号链接，停止。'; return 1; }
  /bin/mkdir -p "${config:h}" || return 1
  temporary="$(/usr/bin/mktemp "${config}.XXXXXX")" || return 1
  if ! print -nr -- "${(j:,:)remaining}" > "$temporary" || ! /bin/chmod 600 "$temporary" || ! /bin/mv -f "$temporary" "$config"; then
    /bin/rm -f -- "$temporary"
    return 1
  fi
  print -r -- "✔ 仅关闭所选动作，保留：${(j:,:)remaining}"
  manager_restart_finder 2>/dev/null || true
  MANAGER_PARTIAL_REMOVAL=1
}
# 旧单项入口安装时合并该动作；不指定范围的独立包入口启用全部动作。
manager_persist_flutter_selection() {
  local config="${HOME}/Library/Application Support/JobsFinderExtensions/flutter-tools-features.conf" feature="" temporary="" existing=""
  local allowed=(project-setup run pub-get android-dependencies pods-dependencies spm-dependencies ohos-dependencies native-dependencies flutter-precache web-dependencies extract export-private-dependencies import-dependencies import-private-dependencies export-gradle-dependencies import-gradle-dependencies export-pods-dependencies import-pods-dependencies export-spm-dependencies import-spm-dependencies export-ohos-dependencies import-ohos-dependencies export-native-dependencies import-native-dependencies export-precache-dependencies import-precache-dependencies export-web-dependencies import-web-dependencies sdk-version sdk-manage ohos-sdk-manage java-manage gradle-download package-ios package-android package-ohos codegen native-doctor harmony-doctor repair-android repair-imports repair-namespace repair-package-imports clean-build-artifacts maintenance) requested=() result=()
  typeset -U result
  if [[ -n "$MANAGER_REQUESTED_FEATURES" ]]; then
    requested=("${(@s:,:)MANAGER_REQUESTED_FEATURES}")
    [[ ! -f "$config" ]] || existing="$(<"$config")"
    result=(${(s:,:)existing})
  else
    requested=("${allowed[@]}")
  fi
  for feature in "${requested[@]}"; do
    (( ${allowed[(Ie)$feature]} )) || { log "✖ 未知 Flutter 动作：$feature"; return 2; }
    result+=("$feature")
  done
  /bin/mkdir -p "${config:h}" || return 1
  temporary="$(/usr/bin/mktemp "${config}.XXXXXX")" || return 1
  if ! print -nr -- "${(j:,:)result}" > "$temporary" || ! /bin/chmod 600 "$temporary" || ! /bin/mv -f "$temporary" "$config"; then
    /bin/rm -f -- "$temporary"
    return 1
  fi
}

# 原install实现只在所选分支加载，保留可独立复制运行的能力。
run_install_operation() {
(
# 脚本自述：
# - 脚本名称：ManageExtension.zsh（App 内部后台管理器）
# - 核心用途：独立构建、注册并启用 Flutter 开发辅助工具 Finder 扩展。
# - 影响范围：构建本工程、启用全部 Flutter 子动作并重启 Finder；不安装 SDK 或执行项目业务。
# - 运行提示：直接回车安装，输入任意字符后回车跳过；Ctrl+C 取消。

SCRIPT_DIR=""
PROJECT_ROOT=""
LOG_FILE=""
APP_PATH=""
EXTENSION_PATH=""
EXTENSION_ID="com.jobs.JobsFlutterTools.FinderSyncExtension"
# 只计算展示位置，不修改目录与系统注册；脚本位于工程根，源码就是本目录。
prepare_display_context() {
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")/.." && pwd)"
  PROJECT_ROOT="${SCRIPT_DIR}"
  LOG_FILE="${TMPDIR:-/tmp/}JobsFlutterToolsInstall.log"
  APP_PATH="${PROJECT_ROOT}/work/DerivedData/Build/Products/Debug/JobsFlutterTools.app"
  EXTENSION_PATH="${APP_PATH}/Contents/PlugIns/JobsFlutterToolsFinderSync.appex"
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
  intro_line title '━━━━━━━━━━ 安装 Flutter 开发辅助工具 Finder 扩展 ━━━━━━━━━━'
  intro_line body "1、源码：${PROJECT_ROOT}；构建并注册本工程，不下载第三方依赖。"
  intro_line body "2、产物：${APP_PATH}；请保留该路径供系统启动扩展。"
  intro_line body '3、影响：启用全部 Flutter 子动作、停用旧 Flutter 菜单并重启 Finder；需要逐项选择请运行上级总安装器。'
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
  [[ -d "${PROJECT_ROOT}/JobsFlutterTools.xcodeproj" ]] || { log '✖ 缺少本工程。'; exit 1; }
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
    -project "${PROJECT_ROOT}/JobsFlutterTools.xcodeproj" \
    -scheme JobsFlutterTools -configuration Debug \
    -destination "platform=macOS,arch=$(/usr/bin/uname -m)" \
    -derivedDataPath "${PROJECT_ROOT}/work/DerivedData" build 2>&1 | /usr/bin/tee -a "$LOG_FILE"
  local build_result=${pipestatus[1]}
  (( build_result == 0 )) || { log "✖ 构建失败，退出码 ${build_result}。"; exit "$build_result"; }
  [[ -d "$EXTENSION_PATH" ]] || { log '✖ 构建成功但缺少 Finder 扩展产物。'; exit 1; }
}
# 独立安装明确启用全部子动作；总安装器负责按本次勾选写入精确清单。
persist_all_flutter_features() {
  local config_dir="${HOME}/Library/Application Support/JobsFinderExtensions"
  local config_path="${config_dir}/flutter-tools-features.conf"
  local temporary_path=""
  /bin/mkdir -p "$config_dir" || return 1
  temporary_path="$(/usr/bin/mktemp "${config_path}.XXXXXX")" || return 1
  if ! print -nr -- 'project-setup,run,pub-get,android-dependencies,pods-dependencies,spm-dependencies,ohos-dependencies,native-dependencies,flutter-precache,web-dependencies,extract,export-private-dependencies,import-dependencies,import-private-dependencies,export-gradle-dependencies,import-gradle-dependencies,export-pods-dependencies,import-pods-dependencies,export-spm-dependencies,import-spm-dependencies,export-ohos-dependencies,import-ohos-dependencies,export-native-dependencies,import-native-dependencies,export-precache-dependencies,import-precache-dependencies,export-web-dependencies,import-web-dependencies,sdk-version,sdk-manage,ohos-sdk-manage,java-manage,gradle-download,package-ios,package-android,package-ohos,codegen,native-doctor,harmony-doctor,repair-android,repair-imports,repair-namespace,repair-package-imports,clean-build-artifacts,maintenance' > "$temporary_path" ||
     ! /bin/chmod 600 "$temporary_path" || ! /bin/mv -f "$temporary_path" "$config_path"; then
    /bin/rm -f -- "$temporary_path"
    log '✖ 无法保存 Flutter 子功能选择。'
    return 1
  fi
  log "✔ 全部 Flutter 子功能已启用：${config_path}"
}
# 仅注册固定扩展，在 App 开启后允许系统弹出自动化与扩展权限请求。
register_extension() {
  /usr/bin/pluginkit -a "$EXTENSION_PATH" 2>&1 | /usr/bin/tee -a "$LOG_FILE" || exit 1
  /usr/bin/pluginkit -e use -i "$EXTENSION_ID" 2>&1 | /usr/bin/tee -a "$LOG_FILE" || exit 1
  persist_all_flutter_features || exit 1
  /bin/zsh "$PROJECT_ROOT/Scripts/Tools/RetireLegacyFlutterMenus.zsh" || exit 1
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
persist_all_flutter_features() {
  manager_persist_flutter_selection
}
main "$@"
)
}

# 原uninstall实现只在所选分支加载，保留可独立复制运行的能力。
run_uninstall_operation() {
(
# 脚本自述：
# - 脚本名称：ManageExtension.zsh（App 内部后台管理器）
# - 核心用途：禁用并注销 JobsFlutterTools 的 Finder 扩展，移除已登记的本应用构建产物。
# - 影响范围：仅处理固定 Bundle ID，保留项目源码与 Flutter SDK、FVM 本身；确认后重启 Finder。
# - 运行提示：先阅读内置自述并按回车，再核对路径并输入 YES；其它输入取消。

SCRIPT_DIR=""
SCRIPT_PATH=""
SCRIPT_BASENAME=""
LOG_FILE=""
EXTENSION_ID="com.jobs.JobsFlutterTools.FinderSyncExtension"
APP_ID="com.jobs.JobsFlutterTools"
EXTENSION_PATHS=()
APP_PATHS=()
# 准备显示路径，不写日志或修改扩展状态。
prepare_display_context() {
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")/.." && pwd)"
  SCRIPT_PATH="${ZSH_ARGZERO:A}"
  SCRIPT_BASENAME="【MacOS】管理Flutter开发辅助工具Finder扩展"
  LOG_FILE="${TMPDIR:-/tmp/}${SCRIPT_BASENAME}.log"
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
  intro_line body "1、核心用途：禁用、注销‘Flutter 开发辅助工具’右键菜单。"
  intro_line body "2、影响范围：只删除 Bundle ID 为 ${APP_ID} 的已登记 App；保留源码与 Flutter SDK、FVM 本身。"
  intro_line body "3、执行策略：回车后先显示待处理路径；输入 YES 才卸载并重启 Finder，其它输入取消。"
  intro_line body "4、取消方式：按 Ctrl+C；非交互输入会退出。"
  intro_line body "5、日志位置：${LOG_FILE}"
  if [[ ! -t 0 ]]; then
    intro_line body "错误：没有可交互输入，请在终端中执行。"
    exit 1
  fi
  read -r '?已了解用途，按回车查看待卸载路径；Ctrl+C 取消：' _
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
  for executable in /usr/bin/pluginkit /usr/libexec/PlistBuddy /usr/bin/awk /usr/bin/pkill /usr/bin/killall /bin/rm; do
    [[ -x "${executable}" ]] || { log "错误：缺少 ${executable}"; exit 1; }
  done
}
# 精确核对 App 名称、真实目录和 Bundle ID，避免删除其它应用。
is_owned_app() {
  local candidate="$1"
  [[ "${candidate}" == /* && "${candidate:t}" == 'JobsFlutterTools.app' && -d "${candidate}" && ! -L "${candidate}" ]] || return 1
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${candidate}/Contents/Info.plist" 2>/dev/null)" == "${APP_ID}" ]]
}
# 从固定扩展的系统注册信息收集路径，展示给用户核对。
collect_registered_paths() {
  local extension_path=""
  local app_path=""
  while IFS= read -r extension_path; do
    [[ "${extension_path}" == /*'/JobsFlutterTools.app/Contents/PlugIns/JobsFlutterToolsFinderSync.appex' ]] || continue
    EXTENSION_PATHS+=("${extension_path}")
    app_path="${extension_path%/Contents/PlugIns/JobsFlutterToolsFinderSync.appex}"
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
  read -r '?输入 YES 卸载上述固定扩展并重启 Finder，其它输入取消：' answer
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
  /usr/bin/pkill -x 'JobsFlutterTools' 2>/dev/null || true
  /usr/bin/pkill -x 'JobsFlutterToolsFinderSync' 2>/dev/null || true
  for extension_path in "${EXTENSION_PATHS[@]}"; do
    /usr/bin/pluginkit -r "${extension_path}" 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || { log "错误：注销失败 ${extension_path}"; exit 1; }
  done
  for app_path in "${APP_PATHS[@]}"; do
    is_owned_app "${app_path}" || { log "错误：App 核验发生变化，停止删除 ${app_path}"; exit 1; }
    /bin/rm -rf -- "${app_path}" || { log "错误：删除失败 ${app_path}"; exit 1; }
  done
  /bin/rm -f -- '/tmp/JobsFlutterToolsNeedsFinderRestart'
  /bin/rm -f -- "${HOME}/Library/Application Support/JobsFinderExtensions/flutter-tools-features.conf" || { log '错误：无法删除 Flutter 子功能选择。'; exit 1; }
  log '固定 Finder 扩展已停用；项目源码与 Flutter SDK、FVM 保留。'
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
prepare_display_context
manager_plan_shared_removal || exit $?
(( MANAGER_PARTIAL_REMOVAL )) && exit 0
main "$@"
)
}

manager_main "$@"
