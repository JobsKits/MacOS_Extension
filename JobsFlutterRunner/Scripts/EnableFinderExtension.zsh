#!/bin/zsh
# 脚本自述：
# - 脚本名称：EnableFinderExtension.zsh
# - 核心用途：在 Xcode 构建后注册、启用并刷新 JobsFlutterRunner Finder Sync Extension。
# - 影响范围：只影响 com.jobs.JobsFlutterRunner.FinderSyncExtension 和 Finder 进程刷新。
# - 运行提示：由 Xcode Build Phase 自动调用，不需要手动运行。

LOG_FILE="/tmp/JobsFlutterRunnerBuildPhase.log"
REFRESH_MARKER="/tmp/JobsFlutterRunnerNeedsFinderRestart"
EXTENSION_ID="com.jobs.JobsFlutterRunner.FinderSyncExtension"
APP_PROCESS_NAME="JobsFlutterRunner"
APP_PATH="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
EXTENSION_PATH="${APP_PATH}/Contents/PlugIns/JobsFlutterRunFinderSync.appex"

# 展示固定自述；Xcode 构建为已声明自动入口，手动运行仍需确认。
show_script_intro_and_wait() {
  print -r -- '━━━━━━━━━━ JobsFlutterRunner 构建后启用 Finder 扩展 ━━━━━━━━━━'
  print -r -- '用途：注册并启用当前 App 内置扩展；成功后重启 Finder 刷新菜单。'
  print -r -- "日志：${LOG_FILE}；外层安装器与隔离构建可用 JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1 跳过。"
  print -r -- '取消：手动运行时按 Ctrl+C；Xcode 构建中可停止构建。'
  if [[ "${JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE:-0}" == 1 ]]; then
    return 0
  fi
  if [[ -n "${TARGET_BUILD_DIR:-}" && -n "${WRAPPER_NAME:-}" ]]; then
    print -r -- '运行策略：Xcode Build Phase 自动执行已声明的注册流程。'
    return 0
  fi
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '错误：缺少 Xcode 构建上下文且无法交互；未修改扩展。'
    exit 1
  fi
  read -r '?手动运行仅支持已有 Xcode 构建上下文；按回车检查，Ctrl+C 取消：' _ || exit 1
}
# 在跳过开关处理后初始化当前脚本，拒绝不完整的构建路径。
initialize_build_context() {
  setopt NO_NOMATCH
  set +e
  if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${WRAPPER_NAME:-}" || "${WRAPPER_NAME}" != 'JobsFlutterRunner.app' ]]; then
    print -u2 -r -- '错误：当前不是此 App 的 Xcode 构建上下文；未修改扩展。'
    exit 1
  fi
}
# 查询当前 Finder Sync 扩展注册状态。
status_line() {
  local lines=""
  local current_line=""
  lines="$(/usr/bin/pluginkit -m -p com.apple.FinderSync -A -v 2>/dev/null | /usr/bin/grep -F "${EXTENSION_ID}" || true)"
  current_line="$(print -r -- "${lines}" | /usr/bin/grep -F "${EXTENSION_PATH}" | /usr/bin/head -n 1 || true)"
  if [[ -n "${current_line}" ]]; then
    print -r -- "${current_line}"
    return 0
  fi

  print -r -- "${lines}" | /usr/bin/head -n 1
}
# 判断外层安装脚本是否已经接管扩展注册和启用。
should_skip_build_phase_enable() {
  [[ "${JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE:-0}" == "1" ]]
}
# 外层安装脚本接管时跳过 Build Phase 内的注册副作用。
skip_enable_when_requested() {
  if should_skip_build_phase_enable; then
    echo "skip build phase enable: outer installer will register and enable Finder Sync extension"
    exit 0
  fi
}
# 停止上一轮 Xcode 调试残留的宿主 App。
stop_stale_host_app() {
  /usr/bin/pkill -x "${APP_PROCESS_NAME}" 2>/dev/null || true
  echo "stop stale host app exit=$?"
}
# 注册当前构建产物里的 Finder Sync 扩展。
register_extension() {
  /usr/bin/pluginkit -a "${EXTENSION_PATH}"
  echo "pluginkit register exit=$?"
}
# 请求系统启用 Finder Sync 扩展。
enable_extension() {
  /usr/bin/pluginkit -e use -i "${EXTENSION_ID}"
  echo "pluginkit enable exit=$?"
}
# 等待 pluginkit 异步登记完成，并在扩展出现后再次启用到 + 状态。
wait_until_extension_enabled() {
  local attempt=""
  local line=""

  for attempt in {1..90}; do
    line="$(status_line)"
    echo "poll ${attempt}=${line}" >&2
    if [[ "${line}" == +* ]]; then
      print -r -- "${line}"
      return 0
    fi
    if [[ -n "${line}" ]]; then
      /usr/bin/pluginkit -e use -i "${EXTENSION_ID}"
      echo "pluginkit retry enable ${attempt} exit=$?" >&2
    fi
    if (( attempt % 10 == 0 )); then
      /usr/bin/pluginkit -a "${EXTENSION_PATH}"
      echo "pluginkit retry register ${attempt} exit=$?" >&2
    fi
    /bin/sleep 0.5
  done

  return 1
}
# 重启 Finder，让 Finder Sync 右键菜单缓存立刻刷新。
restart_finder() {
  echo "restart Finder for FinderSync cache"
  /usr/bin/killall Finder
  echo "killall Finder exit=$?"
}
# 完成一次构建后的扩展注册、启用和 Finder 刷新。
run_enable_flow() {
  echo "[$(/bin/date)] Enable Finder Extension"
  echo "APP_PATH=${APP_PATH}"
  echo "EXTENSION_PATH=${EXTENSION_PATH}"

  local before_line=""
  local after_line=""
  before_line="$(status_line)"
  echo "before=${before_line}"
  stop_stale_host_app

  if [[ ! -d "${EXTENSION_PATH}" ]]; then
    echo "missing extension path"
    /usr/bin/touch "${REFRESH_MARKER}"
    return 0
  fi

  register_extension
  enable_extension
  after_line="$(wait_until_extension_enabled)"
  echo "after=${after_line}"

  if [[ "${after_line}" == +* ]]; then
    restart_finder
    /bin/rm -f "${REFRESH_MARKER}"
    return 0
  fi

  echo "extension not enabled after polling, keep marker for App launch"
  /usr/bin/touch "${REFRESH_MARKER}"
}
# 保存注册诊断；扩展激活失败交给宿主重试，不阻断 App 构建。
enable_extension_with_logging() {
  run_enable_flow >> "${LOG_FILE}" 2>&1
  return 0
}
# 编排 Xcode Build Phase 自动启用扩展流程。
main() {
  show_script_intro_and_wait # 先说明自动注册范围、跳过方式和日志位置。
  skip_enable_when_requested # 外层安装脚本接管时，避免 Build Phase 重复注册并卡住构建。
  initialize_build_context # 初始化 zsh 并核验当前 App 构建上下文。
  enable_extension_with_logging # 注册并启用扩展，保存诊断并按需刷新 Finder。
}

main "$@"
