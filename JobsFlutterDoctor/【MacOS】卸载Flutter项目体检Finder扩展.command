#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】卸载Flutter项目体检Finder扩展.command
# - 核心用途：禁用并注销 JobsFlutterDoctor 的 Finder 扩展，移除已登记的本应用构建产物。
# - 影响范围：仅处理固定 Bundle ID，保留项目源码与 Flutter SDK、FVM 本身；确认后重启 Finder。
# - 运行提示：先阅读内置自述并按回车，再核对路径并输入 YES；其它输入取消。

SCRIPT_DIR=""
SCRIPT_PATH=""
SCRIPT_BASENAME=""
LOG_FILE=""
EXTENSION_ID="com.jobs.JobsFlutterDoctor.FinderSyncExtension"
APP_ID="com.jobs.JobsFlutterDoctor"
EXTENSION_PATHS=()
APP_PATHS=()
# 准备显示路径，不写日志或修改扩展状态。
prepare_display_context() {
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
  SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
  SCRIPT_BASENAME="$(basename "$0" .command)"
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
  intro_line title "================ 【MacOS】卸载Flutter项目体检Finder扩展.command ================"
  intro_line body "1、核心用途：禁用、注销‘Flutter 项目体检’右键菜单。"
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
  [[ "${candidate}" == /* && "${candidate:t}" == 'JobsFlutterDoctor.app' && -d "${candidate}" && ! -L "${candidate}" ]] || return 1
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${candidate}/Contents/Info.plist" 2>/dev/null)" == "${APP_ID}" ]]
}
# 从固定扩展的系统注册信息收集路径，展示给用户核对。
collect_registered_paths() {
  local extension_path=""
  local app_path=""
  while IFS= read -r extension_path; do
    [[ "${extension_path}" == /*'/JobsFlutterDoctor.app/Contents/PlugIns/JobsFlutterDoctorFinderSync.appex' ]] || continue
    EXTENSION_PATHS+=("${extension_path}")
    app_path="${extension_path%/Contents/PlugIns/JobsFlutterDoctorFinderSync.appex}"
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
  /usr/bin/pkill -x 'JobsFlutterDoctor' 2>/dev/null || true
  /usr/bin/pkill -x 'JobsFlutterDoctorFinderSync' 2>/dev/null || true
  for extension_path in "${EXTENSION_PATHS[@]}"; do
    /usr/bin/pluginkit -r "${extension_path}" 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || { log "错误：注销失败 ${extension_path}"; exit 1; }
  done
  for app_path in "${APP_PATHS[@]}"; do
    is_owned_app "${app_path}" || { log "错误：App 核验发生变化，停止删除 ${app_path}"; exit 1; }
    /bin/rm -rf -- "${app_path}" || { log "错误：删除失败 ${app_path}"; exit 1; }
  done
  /bin/rm -f -- '/tmp/JobsFlutterDoctorNeedsFinderRestart'
  log '固定 Finder 扩展已停用；项目源码与 Flutter SDK、FVM 保留。'
}
# 刷新 Finder 使已卸载菜单退出显示。
refresh_finder() {
  /usr/bin/killall Finder 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || log '提示：Finder 当前没有运行，无需重启。'
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

main "$@"
