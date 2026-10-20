#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】安装Flutter版本管理Finder扩展.command
# - 核心用途：独立构建、注册并启用 Flutter SDK 版本管理 Finder 扩展。
# - 影响范围：只构建本工程与启用本扩展，成功后重启 Finder；不安装 FVM 或 Flutter SDK。
# - 运行提示：直接回车跳过，输入任意字符后回车开始；Ctrl+C 取消。

SCRIPT_DIR=""
PROJECT_ROOT=""
LOG_FILE=""
APP_PATH=""
EXTENSION_PATH=""
EXTENSION_ID="com.jobs.JobsFlutterVersionMgr.FinderSyncExtension"
# 只计算展示位置，不修改目录与系统注册。
prepare_display_context() {
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
  PROJECT_ROOT="${SCRIPT_DIR:h}"
  LOG_FILE="${TMPDIR:-/tmp/}JobsFlutterVersionMgrInstall.log"
  APP_PATH="${PROJECT_ROOT}/work/DerivedData/Build/Products/Debug/JobsFlutterVersionMgr.app"
  EXTENSION_PATH="${APP_PATH}/Contents/PlugIns/JobsFlutterVersionFinderSync.appex"
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
# 展示安装范围，只有非空输入才执行构建与注册。
show_script_intro_and_wait() {
  prepare_display_context
  intro_line title '━━━━━━━━━━ 安装 Flutter 版本管理 Finder 扩展 ━━━━━━━━━━'
  intro_line body "1、源码：${PROJECT_ROOT}；构建并注册本工程，不下载第三方依赖。"
  intro_line body "2、产物：${APP_PATH}；请保留该路径供系统启动扩展。"
  intro_line body '3、影响：启用固定扩展并重启 Finder；FVM、fzf 和 Flutter 安装由项目右键动作另行确认。'
  intro_line body "4、日志：${LOG_FILE}；Ctrl+C 取消。"
  [[ -t 0 ]] || { print -u2 -r -- '错误：请在可交互终端运行。'; exit 1; }
  local answer=""
  IFS= read -r 'answer?直接回车跳过；输入任意字符后回车安装：' || exit 0
  [[ -n "$answer" ]] || exit 0
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
  [[ -d "${PROJECT_ROOT}/JobsFlutterVersionMgr.xcodeproj" ]] || { log '✖ 缺少本工程。'; exit 1; }
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
    -project "${PROJECT_ROOT}/JobsFlutterVersionMgr.xcodeproj" \
    -scheme JobsFlutterVersionMgr -configuration Debug \
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
  /usr/bin/killall Finder 2>&1 | /usr/bin/tee -a "$LOG_FILE" || log 'ℹ Finder 当前未运行。'
  log "✔ 已提交扩展启用请求；如菜单未出现，请在宿主中打开扩展设置。日志：${LOG_FILE}"
}
# 编排独立安装流程，确认前不产生业务副作用。
main() {
  show_script_intro_and_wait # 先展示范围并等待非空确认。
  initialize_runtime # 确认后准备脚本选项和日志。
  check_environment # 核验完整 Xcode、macOS SDK 与工程。
  build_extension # 只构建本工程并阻止重复注册。
  register_extension # 注册固定扩展、打开宿主并刷新 Finder。
}

main "$@"
