#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】卸载iOS辅助工具Finder扩展.command
# - 核心用途：禁用并注销 JobsIOSTools 的 Finder 扩展，移除已登记的本应用构建产物。
# - 影响范围：仅处理固定 Bundle ID，保留项目源码和全部 iOS 项目文件；确认后重启 Finder。
# - 运行提示：先阅读内置自述并按回车，再核对路径并输入 YES；其它输入取消。
# shell: zsh
#
#  【MacOS】卸载iOS辅助工具Finder扩展.command
#  JobsIOSTools
#
#  Created by Jobs on 2026年10月22日，星期四.
#

NON_INTERACTIVE=0
SKIP_ENABLE=0
ALL_FEATURES=(ios-disable-sandbox ios-install-cocoapods ios-pods-source-github ios-extract-pods ios-pod-install ios-pod-update ios-xcode-dependencies ios-pod-repo-update ios-pod-build-check ios-code-snippets ios-clean-build-artifacts)
REQUESTED_FEATURES=()
REMAINING_FEATURES=()
FEATURE_CONFIG="${HOME}/Library/Application Support/JobsIOSTools/EnabledFeatures.txt"
SCRIPT_DIR=""
SCRIPT_PATH=""
SCRIPT_BASENAME=""
LOG_FILE=""
EXTENSION_ID="com.jobs.JobsIOSTools.FinderSyncExtension"
APP_ID="com.jobs.JobsIOSTools"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
EXTENSION_PATHS=()
APP_PATHS=()
# 准备显示路径，不写日志或修改扩展状态。
prepare_display_context() {
  local temporary_root="${TMPDIR:-/tmp}"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
  SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "${BASH_SOURCE[0]:-${(%):-%x}}")"
  SCRIPT_BASENAME="$(basename "${SCRIPT_PATH}" .command)"
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
  parse_feature_options "$@"
  intro_line title "================ 【MacOS】卸载iOS辅助工具Finder扩展.command ================"
  intro_line body "1、核心用途：禁用、注销‘iOS辅助工具’右键菜单。"
  intro_line body "2、影响范围：只删除 Bundle ID 为 ${APP_ID} 的已登记 App；保留源码和全部 iOS 项目文件。"
  intro_line body "3、执行策略：回车后先显示待处理路径；输入 YES 才卸载并重启 Finder，其它输入取消。"
  intro_line body "4、取消方式：按 Ctrl+C；非交互输入会退出。"
  intro_line body "5、日志位置：${LOG_FILE}"
  (( NON_INTERACTIVE == 0 )) || return 0
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
  [[ "${candidate}" == /* && "${candidate:t}" == 'JobsIOSTools.app' && -d "${candidate}" && ! -L "${candidate}" ]] || return 1
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${candidate}/Contents/Info.plist" 2>/dev/null)" == "${APP_ID}" ]]
}
# 从固定扩展的系统注册信息收集路径，展示给用户核对。
collect_registered_paths() {
  if (( ${#REMAINING_FEATURES[@]} > 0 )); then
    log '仅修改所选功能配置，保留 App 与 Finder 扩展登记。'
    return 0
  fi
  local extension_path=""
  local app_path=""
  while IFS= read -r extension_path; do
    [[ "${extension_path}" == /*'/JobsIOSTools.app/Contents/PlugIns/JobsIOSToolsFinderSync.appex' ]] || continue
    if [[ -e "${extension_path}" || -L "${extension_path}" ]]; then
      [[ -d "${extension_path}" && ! -L "${extension_path}" ]] || continue
      [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${extension_path}/Contents/Info.plist" 2>/dev/null)" == "${EXTENSION_ID}" ]] || continue
    fi
    EXTENSION_PATHS+=("${extension_path}")
    app_path="${extension_path%/Contents/PlugIns/JobsIOSToolsFinderSync.appex}"
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
  (( NON_INTERACTIVE == 0 )) || return 0
  local answer=""
  local prompt='输入 YES 卸载上述固定扩展并重启 Finder，其它输入取消：'
  (( ${#REMAINING_FEATURES[@]} == 0 )) || prompt='输入 YES 关闭所选功能并刷新 Finder（保留其它功能），其它输入取消：'
  IFS= read -r "answer?$prompt" || exit 0
  if [[ "${answer}" != YES ]]; then
    log '已取消，没有修改应用或扩展注册。'
    exit 0
  fi
}
# 停用并注销指定扩展，只移除二次核验通过的自有 App。
uninstall_extension() {
  if (( ${#REMAINING_FEATURES[@]} > 0 )); then
    write_feature_configuration "${(j:,:)REMAINING_FEATURES}" || { log '✖ 功能配置保存失败。'; exit 1; }
    log "✔ 仅关闭所选功能；保留：${(j:,:)REMAINING_FEATURES}"
    return 0
  fi
  local extension_path=""
  local app_path=""
  /usr/bin/pluginkit -e ignore -i "${EXTENSION_ID}" 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || log '提示：扩展可能已经停用或未安装。'
  /usr/bin/pkill -x 'JobsIOSTools' 2>/dev/null || true
  /usr/bin/pkill -x 'JobsIOSToolsFinderSync' 2>/dev/null || true
  for extension_path in "${EXTENSION_PATHS[@]}"; do
    /usr/bin/pluginkit -r "${extension_path}" 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || { log "错误：注销失败 ${extension_path}"; exit 1; }
  done
  for app_path in "${APP_PATHS[@]}"; do
    is_owned_app "${app_path}" || { log "错误：App 核验发生变化，停止删除 ${app_path}"; exit 1; }
    "${LSREGISTER}" -u "${app_path}" 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || { log "错误：宿主 URL 注销失败 ${app_path}"; exit 1; }
    /bin/rm -rf -- "${app_path}" || { log "错误：删除失败 ${app_path}"; exit 1; }
  done
  /bin/rm -f -- '/tmp/JobsIOSToolsNeedsFinderRestart'
  /bin/rm -f -- "$FEATURE_CONFIG"
  log '固定 Finder 扩展已停用；项目源码与全部 iOS 项目文件保留。'
}
# 刷新 Finder 使已卸载菜单退出显示。
refresh_finder() {
  /usr/bin/killall Finder 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || log '提示：Finder 当前没有运行，无需重启。'
  log "卸载完成，日志：${LOG_FILE}"
}
# 读取固定功能参数，不触碰磁盘；总面板明确选择后可使用非交互模式。
parse_feature_options() {
  local raw_features="${JOBS_INSTALL_FEATURES:-}"
  while (( $# > 0 )); do
    case "$1" in
      --features) (( $# >= 2 )) || { print -u2 -r -- '✖ --features 缺少参数。'; exit 1; }; raw_features="$2"; shift ;;
      --features=*) raw_features="${1#--features=}" ;;
      --non-interactive) NON_INTERACTIVE=1 ;;
      --skip-enable) SKIP_ENABLE=1 ;;
      *) print -u2 -r -- "✖ 未知参数：$1"; exit 1 ;;
    esac
    shift
  done
  [[ -n "$raw_features" ]] || raw_features="${(j:,:)ALL_FEATURES}"
  REQUESTED_FEATURES=(${(s:,:)raw_features})
  local feature="" index=1
  for feature in "${REQUESTED_FEATURES[@]}"; do
    [[ "$feature" != ios-clean-cache ]] || feature=ios-clean-build-artifacts
    REQUESTED_FEATURES[$index]="$feature"
    (( index += 1 ))
    (( ${ALL_FEATURES[(Ie)$feature]} > 0 )) || { print -u2 -r -- "✖ 未知功能：$feature"; exit 1; }
  done
}

# 保存用户级配置，避免下一轮构建覆盖；固定顺序便于审查。
write_feature_configuration() {
  local value="$1"
  local directory="${FEATURE_CONFIG:h}"
  /bin/mkdir -p "$directory" || return 1
  local temporary="$(/usr/bin/mktemp "$directory/.EnabledFeatures.XXXXXX")" || return 1
  /usr/bin/printf '%s\n' "$value" > "$temporary" || { /bin/rm -f "$temporary"; return 1; }
  /bin/chmod 644 "$temporary" || { /bin/rm -f "$temporary"; return 1; }
  /bin/mv -f "$temporary" "$FEATURE_CONFIG"
}
# 逐项移除所选功能；仍有功能时保留同一个 App 和扩展登记。
plan_feature_removal() {
  local configured="${(j:,:)ALL_FEATURES}"
  [[ ! -f "$FEATURE_CONFIG" ]] || configured="$(/bin/cat "$FEATURE_CONFIG")"
  local -a enabled=(${(s:,:)configured})
  (( ${enabled[(Ie)ios-clean-cache]} == 0 )) || enabled+=(ios-clean-build-artifacts)
  local feature=""
  for feature in "${ALL_FEATURES[@]}"; do
    if (( ${enabled[(Ie)$feature]} > 0 && ${REQUESTED_FEATURES[(Ie)$feature]} == 0 )); then
      REMAINING_FEATURES+=("$feature")
    fi
  done
  log "关闭功能：${(j:,:)REQUESTED_FEATURES}"
  log "保留功能：${(j:,:)REMAINING_FEATURES}"
}

# 编排自述、核验、明确确认和卸载。
main() {
  show_script_intro_and_wait "$@" # 先展示内置自述并等待阅读确认。
  initialize_runtime # 确认阅读后初始化选项和日志。
  check_environment # 检查系统和卸载命令。
  plan_feature_removal # 只计划所选功能的移除。
  collect_registered_paths # 收集并显示固定扩展的真实注册路径。
  confirm_uninstall # 删除 App 及重启 Finder 前要求输入 YES。
  uninstall_extension # 精确注销扩展并清理核验通过的 App。
  refresh_finder # 刷新 Finder 并显示日志位置。
}

main "$@"
