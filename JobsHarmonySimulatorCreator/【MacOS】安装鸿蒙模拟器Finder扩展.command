#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】安装鸿蒙模拟器Finder扩展.command
# - 核心用途：独立构建、注册并启用“新建 Harmony 模拟器”桌面右键扩展。
# - 影响范围：只构建本工程、启用固定扩展并刷新 Finder；不创建模拟器或下载运行时。
# - 运行提示：阅读自述后，直接回车安装；输入任意字符后回车跳过，Ctrl+C 取消。

SCRIPT_DIR=""
PROJECT_ROOT=""
LOG_FILE=""
APP_PATH=""
EXTENSION_PATH=""
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
APP_ID="com.jobs.harmonysimulatorcreator"
EXTENSION_ID="com.jobs.harmonysimulatorcreator.findersync"
# 计算源码、产物和日志的位置，确认前不写文件。
prepare_display_context() {
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
  PROJECT_ROOT="${SCRIPT_DIR}"
  LOG_FILE="${TMPDIR:-/tmp/}JobsHarmonySimulatorCreatorInstall.log"
  APP_PATH="${PROJECT_ROOT}/work/DerivedData/Build/Products/Debug/JobsHarmonySimulatorCreator.app"
  EXTENSION_PATH="${APP_PATH}/Contents/PlugIns/JobsHarmonySimulatorFinderSync.appex"
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
  intro_line title '━━━━━━━━━━ 安装 Harmony 模拟器 Finder 扩展 ━━━━━━━━━━'
  intro_line body "1、来源：本地源码 ${PROJECT_ROOT}。"
  intro_line body "2、目标：${APP_PATH}；系统从此处启动扩展，请保留产物。"
  intro_line body '3、影响：构建并启用“新建 Harmony 模拟器”，刷新 Finder；不创建、删除模拟器，不下载运行时。'
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
  [[ -f "${PROJECT_ROOT}/JobsHarmonySimulatorCreator.xcodeproj/project.pbxproj" ]] || { log '✖ 缺少工程源码。'; exit 1; }
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
    -project "${PROJECT_ROOT}/JobsHarmonySimulatorCreator.xcodeproj" \
    -scheme JobsHarmonySimulatorCreator \
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
  /usr/bin/pkill -x JobsHarmonySimulatorCreator 2>/dev/null || true
  while IFS= read -r registered_app; do
    [[ "${registered_app}" == /*'/JobsHarmonySimulatorCreator.app' && "${registered_app}" != "${APP_PATH}" ]] || continue
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
    [[ "${registered_path}" == /*'/JobsHarmonySimulatorCreator.app/Contents/PlugIns/JobsHarmonySimulatorFinderSync.appex' ]] || continue
    [[ "${registered_path}" != "${EXTENSION_PATH}" ]] || continue
    if [[ -f "${registered_path}/Contents/Info.plist" ]]; then
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
  /usr/bin/killall Finder 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || log 'ℹ Finder 当前未运行。'
  log '✔ 已请求启用扩展。在桌面空白处右键，选择“新建 Harmony 模拟器”。'
  log 'ℹ 菜单未出现时，在系统设置的 Finder 扩展中启用 JobsHarmonySimulatorCreator；首次操作允许控制 Terminal。'
}
# 编排确认、自检、构建与扩展注册。
main() {
  show_script_intro_and_wait # 先说明源码、产物、影响及取消方式。
  initialize_runtime # 确认后准备本次运行日志。
  check_environment # 核验完整开发工具链与工程。
  build_extension # 独立构建并验证 App 身份和签名。
  register_extension # 注册固定扩展并刷新桌面菜单。
}

main "$@"
