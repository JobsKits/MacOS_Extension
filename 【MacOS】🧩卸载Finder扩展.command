#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】🧩卸载Finder扩展.command
# - 核心用途：用 fzf 选择并卸载本目录内的 Finder Sync Extension 功能，支持全选。
# - 影响范围：会停止宿主 App 和 Finder Sync Extension，注销扩展，清理构建产物、运行标记和旧 Automator 服务，并重启 Finder。
# - 运行提示：运行后会先打印内置自述；按回车确认后进入 fzf 多选，按 Tab 选择，选定后按回车执行卸载。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
WORKSPACE_DIR="${SCRIPT_DIR}"
SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="${TMPDIR:-/tmp/}${SCRIPT_BASENAME}.log"
ALL_OPTION="全选｜卸载全部 Finder 扩展"
FINAL_EXIT_STATUS=0
SELECTED_KEYS=()
SUCCEEDED_FEATURES=()
FAILED_FEATURES=()

FEATURE_KEYS=(git_remote path_copier terminal_opener)
typeset -A FEATURE_TITLE
typeset -A FEATURE_PROJECT_DIR
typeset -A FEATURE_APP_NAME
typeset -A FEATURE_EXTENSION_PROCESS_NAME
typeset -A FEATURE_EXTENSION_ID
typeset -A FEATURE_REFRESH_MARKER
typeset -A FEATURE_RUNTIME_LOG
typeset -A FEATURE_AUTOMATOR_SERVICE_DIR
typeset -A FEATURE_AUTOMATOR_HELPER_SCRIPT
typeset -A FEATURE_KEY_BY_TITLE

FEATURE_TITLE[git_remote]="打开 Git 远程地址"
FEATURE_PROJECT_DIR[git_remote]="JobsGitRemoteOpener"
FEATURE_APP_NAME[git_remote]="JobsGitRemoteOpener"
FEATURE_EXTENSION_PROCESS_NAME[git_remote]="JobsGitRemoteFinderSync"
FEATURE_EXTENSION_ID[git_remote]="com.jobs.JobsGitRemoteOpener.FinderSyncExtension"
FEATURE_REFRESH_MARKER[git_remote]="/tmp/JobsGitRemoteOpenerNeedsFinderRestart"
FEATURE_RUNTIME_LOG[git_remote]="/tmp/JobsGitRemoteOpener.log"
FEATURE_AUTOMATOR_SERVICE_DIR[git_remote]="${HOME}/Library/Services/打开Git远程地址.workflow"
FEATURE_AUTOMATOR_HELPER_SCRIPT[git_remote]="${HOME}/Library/Scripts/Jobs/OpenGitRemoteInBrowser.zsh"
FEATURE_KEY_BY_TITLE[${FEATURE_TITLE[git_remote]}]="git_remote"

FEATURE_TITLE[path_copier]="复制绝对路径"
FEATURE_PROJECT_DIR[path_copier]="JobsPathCopier"
FEATURE_APP_NAME[path_copier]="JobsPathCopier"
FEATURE_EXTENSION_PROCESS_NAME[path_copier]="JobsPathCopyFinderSync"
FEATURE_EXTENSION_ID[path_copier]="com.jobs.JobsPathCopier.FinderSyncExtension"
FEATURE_REFRESH_MARKER[path_copier]="/tmp/JobsPathCopierNeedsFinderRestart"
FEATURE_RUNTIME_LOG[path_copier]="/tmp/JobsPathCopier.log"
FEATURE_AUTOMATOR_SERVICE_DIR[path_copier]="${HOME}/Library/Services/复制绝对路径.workflow"
FEATURE_AUTOMATOR_HELPER_SCRIPT[path_copier]="${HOME}/Library/Scripts/Jobs/CopyAbsolutePath.zsh"
FEATURE_KEY_BY_TITLE[${FEATURE_TITLE[path_copier]}]="path_copier"

FEATURE_TITLE[terminal_opener]="用终端打开"
FEATURE_PROJECT_DIR[terminal_opener]="JobsTerminalOpener"
FEATURE_APP_NAME[terminal_opener]="JobsTerminalOpener"
FEATURE_EXTENSION_PROCESS_NAME[terminal_opener]="JobsTerminalFinderSync"
FEATURE_EXTENSION_ID[terminal_opener]="com.jobs.JobsTerminalOpener.FinderSyncExtension"
FEATURE_REFRESH_MARKER[terminal_opener]="/tmp/JobsTerminalOpenerNeedsFinderRestart"
FEATURE_RUNTIME_LOG[terminal_opener]="/tmp/JobsTerminalOpener.log"
FEATURE_AUTOMATOR_SERVICE_DIR[terminal_opener]="${HOME}/Library/Services/用终端打开.workflow"
FEATURE_AUTOMATOR_HELPER_SCRIPT[terminal_opener]="${HOME}/Library/Scripts/Jobs/OpenInTerminal.zsh"
FEATURE_KEY_BY_TITLE[${FEATURE_TITLE[terminal_opener]}]="terminal_opener"

# 判断当前终端是否适合输出 ANSI 彩色文本。
supports_color() {
  [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != "dumb" && -z "${NO_COLOR:-}" ]]
}
# 输出文本并同步追加到日志文件。
log() {
  print -r -- "$1" | tee -a "$LOG_FILE"
}
# 按需给日志文本套色，非 TTY 环境自动降级为纯文本。
color_log() {
  local code="$1"
  local message="$2"

  if supports_color; then
    log "$(printf '\033[%sm%s\033[0m' "$code" "$message")"
  else
    log "$message"
  fi
}
# 输出普通绿色提示。
color_echo() {
  color_log "1;32" "$1"
}
# 输出信息提示。
info_echo() {
  color_log "1;34" "ℹ $1"
}
# 输出成功提示。
success_echo() {
  color_log "1;32" "✔ $1"
}
# 输出警告提示。
warn_echo() {
  color_log "1;33" "⚠ $1"
}
# 输出温馨提示。
warm_echo() {
  color_log "1;33" "$1"
}
# 输出说明提示。
note_echo() {
  color_log "1;35" "➤ $1"
}
# 输出错误提示。
error_echo() {
  color_log "1;31" "✖ $1"
}
# 输出错误纯文本。
err_echo() {
  color_log "1;31" "$1"
}
# 输出调试提示。
debug_echo() {
  color_log "1;35" "🐞 $1"
}
# 输出高亮提示。
highlight_echo() {
  color_log "1;36" "🔹 $1"
}
# 输出次要说明。
gray_echo() {
  color_log "0;90" "$1"
}
# 输出加粗文本。
bold_echo() {
  color_log "1" "$1"
}
# 输出下划线文本。
underline_echo() {
  color_log "4" "$1"
}
# 判断是否可以安全清屏，避免瘦身终端里出现 TERM 报错。
can_clear_terminal() {
  [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]
}
# 打印脚本内置自述并等待用户确认阅读。
show_script_intro_and_wait() {
  can_clear_terminal && clear
  highlight_echo "============================== 脚本自述 =============================="
  note_echo "当前脚本：${SCRIPT_PATH}"
  note_echo "核心用途：用 fzf 选择并卸载 Finder 右键增强功能。"
  note_echo "可选功能：打开 Git 远程地址、复制绝对路径、用终端打开。"
  warn_echo "影响范围：会禁用并注销选中的 Finder Sync Extension。"
  warn_echo "影响范围：会停止对应宿主 App 和已运行的扩展进程。"
  warn_echo "影响范围：会删除 Xcode DerivedData 和本工作区 work 下的构建产物。"
  warn_echo "影响范围：会删除旧 Automator 服务入口和运行时刷新标记。"
  warn_echo "影响范围：卸载完成后会重启 Finder，刷新右键菜单缓存。"
  warn_echo "运行策略：按回车后进入 fzf；选中后再次按回车开始卸载。"
  gray_echo "fzf 操作：Tab 多选，Enter 确认；选择“${ALL_OPTION}”会卸载全部功能。"
  gray_echo "不会删除三个工程源码目录。"
  gray_echo "日志位置：${LOG_FILE}"
  highlight_echo "======================================================================="
  echo ""

  if [[ ! -t 0 ]]; then
    error_echo "当前没有可交互输入，无法进入 fzf 选择。请在终端里运行本脚本。"
    exit 1
  fi

  local _
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 初始化 zsh 运行选项和日志文件。
init_runtime() {
  setopt NO_NOMATCH
  : > "$LOG_FILE"
}
# 检查系统命令和 MacOS 环境是否满足卸载要求。
check_environment() {
  local missing_commands=()
  local command_name=""

  if [[ "$(uname -s)" != "Darwin" ]]; then
    error_echo "当前系统不是 MacOS，无法卸载 Finder 扩展。"
    exit 1
  fi

  for command_name in fzf pluginkit pgrep pkill kill killall rm awk grep find tee sed; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      missing_commands+=("$command_name")
    fi
  done

  if (( ${#missing_commands[@]} > 0 )); then
    error_echo "缺少必要命令：${(j:, :)missing_commands}"
    if (( ${missing_commands[(Ie)fzf]} > 0 )); then
      gray_echo "安装 fzf 可执行：brew install fzf"
    fi
    exit 1
  fi
}
# 生成 fzf 多选列表。
print_fzf_options() {
  local key=""

  print -r -- "$ALL_OPTION"
  for key in "${FEATURE_KEYS[@]}"; do
    print -r -- "${FEATURE_TITLE[$key]}"
  done
}
# 去重追加一个待卸载功能。
append_selected_key_if_needed() {
  local key="$1"
  local existed_key=""

  for existed_key in "${SELECTED_KEYS[@]}"; do
    [[ "$existed_key" == "$key" ]] && return 0
  done
  SELECTED_KEYS+=("$key")
}
# 把 fzf 选择结果解析成工程 key 列表。
parse_fzf_selection() {
  local selection_output="$1"
  local selected_line=""
  local key=""

  SELECTED_KEYS=()
  while IFS= read -r selected_line; do
    if [[ "$selected_line" == "$ALL_OPTION" ]]; then
      SELECTED_KEYS=("${FEATURE_KEYS[@]}")
      return 0
    fi

    key="${FEATURE_KEY_BY_TITLE[$selected_line]}"
    [[ -n "$key" ]] && append_selected_key_if_needed "$key"
  done <<< "$selection_output"
}
# 使用 fzf 选择本次需要卸载的功能。
select_features_with_fzf() {
  local selection_output=""
  local fzf_status=0

  selection_output="$(print_fzf_options | fzf --multi --cycle --height=60% --border --prompt="选择要卸载的功能 > " --header="Tab 多选，Enter 确认；选“${ALL_OPTION}”会卸载全部。")"
  fzf_status=$?

  if (( fzf_status != 0 )); then
    warn_echo "已取消选择，未执行卸载。"
    exit 0
  fi

  if [[ -z "$selection_output" ]]; then
    warn_echo "没有选择任何功能，未执行卸载。"
    exit 0
  fi

  parse_fzf_selection "$selection_output"
  if (( ${#SELECTED_KEYS[@]} == 0 )); then
    warn_echo "没有解析到有效功能，未执行卸载。"
    exit 0
  fi
}
# 输出用户已经选择的功能，便于日志排查。
print_selected_features() {
  local key=""

  note_echo "本次准备卸载的功能："
  for key in "${SELECTED_KEYS[@]}"; do
    gray_echo "- ${FEATURE_TITLE[$key]}"
  done
}
# 等待用户回车确认后开始卸载。
confirm_uninstall_with_enter() {
  echo ""
  warn_echo "即将卸载以上 Finder 扩展，并删除对应构建产物与旧 Automator 服务。"
  gray_echo "按回车开始卸载；按 Ctrl+C 取消。"

  local _
  IFS= read -r "?➤ " _
}
# 返回指定功能的本地 DerivedData 目录。
local_derived_data_dir_for_key() {
  local key="$1"

  print -r -- "${WORKSPACE_DIR}/work/${FEATURE_PROJECT_DIR[$key]}DerivedData"
}
# 输出当前 Finder Sync 扩展注册状态，方便卸载前后对比。
print_current_extension_status() {
  local key="$1"
  local extension_id="${FEATURE_EXTENSION_ID[$key]}"

  note_echo "当前扩展注册状态：${extension_id}"
  /usr/bin/pluginkit -m -i "$extension_id" -A -D -vv 2>/dev/null | tee -a "$LOG_FILE" || true
}
# 临时禁用 Finder Sync 扩展，避免卸载过程中被 Finder 再次拉起。
disable_extension() {
  local key="$1"
  local extension_id="${FEATURE_EXTENSION_ID[$key]}"

  note_echo "禁用 Finder Sync 扩展：${extension_id}"
  /usr/bin/pluginkit -e ignore -i "$extension_id" 2>&1 | tee -a "$LOG_FILE" || true
}
# 停止仍在运行的宿主 App，避免已删除的构建产物继续驻留。
stop_host_application() {
  local key="$1"
  local app_name="${FEATURE_APP_NAME[$key]}"
  local pid=""

  note_echo "停止 ${app_name} 宿主 App。"
  /usr/bin/pkill -x "$app_name" 2>/dev/null || true
  /usr/bin/pgrep -f "/${app_name}.app/Contents/MacOS/${app_name}" 2>/dev/null | while IFS= read -r pid; do
    if [[ -n "$pid" && "$pid" != "$$" ]]; then
      /bin/kill "$pid" 2>/dev/null || true
    fi
  done
}
# 停止已经被 Finder 拉起的扩展进程。
stop_extension_processes() {
  local key="$1"
  local extension_process_name="${FEATURE_EXTENSION_PROCESS_NAME[$key]}"

  note_echo "停止 ${extension_process_name} 扩展进程。"
  /usr/bin/pkill -f "${extension_process_name}.appex/Contents/MacOS/${extension_process_name}" 2>/dev/null || true
}
# 清除临时禁用选择并注销 Finder Sync 扩展。
reset_election_and_unregister_extension() {
  local key="$1"
  local extension_id="${FEATURE_EXTENSION_ID[$key]}"
  local extension_paths=()
  local extension_path=""

  note_echo "清除扩展禁用选择，确保下次 Xcode 调试可以重新启用。"
  /usr/bin/pluginkit -e default -i "$extension_id" 2>&1 | tee -a "$LOG_FILE" || true

  extension_paths=("${(@f)$(
    /usr/bin/pluginkit -m -i "$extension_id" -A -D -vv 2>/dev/null \
      | /usr/bin/awk -F '= ' '/Path = / {print $2}'
  )}")

  if (( ${#extension_paths[@]} == 0 )); then
    gray_echo "未发现可注销的扩展路径：${extension_id}"
    return 0
  fi

  for extension_path in "${extension_paths[@]}"; do
    if [[ -n "$extension_path" && -e "$extension_path" ]]; then
      note_echo "注销扩展路径：${extension_path}"
      /usr/bin/pluginkit -r "$extension_path" 2>&1 | tee -a "$LOG_FILE" || true
    else
      gray_echo "扩展路径不存在，跳过注销：${extension_path}"
    fi
  done
}
# 清理 App 和构建阶段留下的临时标记。
clear_runtime_markers() {
  local key="$1"
  local refresh_marker="${FEATURE_REFRESH_MARKER[$key]}"
  local runtime_log="${FEATURE_RUNTIME_LOG[$key]}"

  note_echo "清理 ${FEATURE_APP_NAME[$key]} 运行时标记。"
  /bin/rm -f "$refresh_marker" "$runtime_log"
}
# 删除 Xcode DerivedData 下的宿主 App 构建产物。
remove_xcode_deriveddata_app_bundles() {
  local key="$1"
  local app_name="${FEATURE_APP_NAME[$key]}"
  local derived_data_root="${HOME}/Library/Developer/Xcode/DerivedData"
  local app_paths=()
  local app_path=""
  local delete_status=0

  if [[ ! -d "$derived_data_root" ]]; then
    gray_echo "未发现 Xcode DerivedData 目录：${derived_data_root}"
    return 0
  fi

  app_paths=("${(@f)$(
    /usr/bin/find "$derived_data_root" \
      -path "*${app_name}*.app" \
      -type d \
      -print 2>/dev/null
  )}")

  if (( ${#app_paths[@]} == 0 )); then
    gray_echo "未发现 Xcode DerivedData 下的 ${app_name}.app 构建产物。"
    return 0
  fi

  for app_path in "${app_paths[@]}"; do
    if [[ -n "$app_path" && "$app_path" == "${derived_data_root}/"* ]]; then
      note_echo "删除构建产物：${app_path}"
      /bin/rm -rf "$app_path" || delete_status=1
    else
      warn_echo "路径不在 Xcode DerivedData 内，跳过删除：${app_path}"
    fi
  done

  return "$delete_status"
}
# 删除本工作区 work 下的构建产物。
remove_local_deriveddata_dir() {
  local key="$1"
  local local_derived_data_dir=""

  local_derived_data_dir="$(local_derived_data_dir_for_key "$key")"
  if [[ -d "$local_derived_data_dir" && "$local_derived_data_dir" == "${WORKSPACE_DIR}/work/"* ]]; then
    note_echo "删除本工作区旧构建产物：${local_derived_data_dir}"
    /bin/rm -rf "$local_derived_data_dir"
    return $?
  fi

  gray_echo "未发现本工作区旧构建产物：${local_derived_data_dir}"
  return 0
}
# 清理旧 Automator 服务版右键入口。
remove_legacy_automator_service() {
  local key="$1"
  local service_dir="${FEATURE_AUTOMATOR_SERVICE_DIR[$key]}"
  local helper_script="${FEATURE_AUTOMATOR_HELPER_SCRIPT[$key]}"
  local delete_status=0

  if [[ -d "$service_dir" ]]; then
    note_echo "删除旧 Automator 服务：${service_dir}"
    /bin/rm -rf "$service_dir" || delete_status=1
  else
    gray_echo "未发现旧 Automator 服务：${service_dir}"
  fi

  if [[ -f "$helper_script" ]]; then
    note_echo "删除旧 Automator 辅助脚本：${helper_script}"
    /bin/rm -f "$helper_script" || delete_status=1
  else
    gray_echo "未发现旧 Automator 辅助脚本：${helper_script}"
  fi

  return "$delete_status"
}
# 卸载单个 Finder 扩展功能。
uninstall_feature() {
  local key="$1"
  local feature_status=0

  highlight_echo "============================== ${FEATURE_TITLE[$key]} =============================="
  print_current_extension_status "$key"
  disable_extension "$key"
  stop_host_application "$key"
  stop_extension_processes "$key"
  reset_election_and_unregister_extension "$key"
  clear_runtime_markers "$key" || feature_status=1
  remove_xcode_deriveddata_app_bundles "$key" || feature_status=1
  remove_local_deriveddata_dir "$key" || feature_status=1
  remove_legacy_automator_service "$key" || feature_status=1

  return "$feature_status"
}
# 逐个卸载用户选择的 Finder 扩展功能。
uninstall_selected_features() {
  local key=""

  FINAL_EXIT_STATUS=0
  for key in "${SELECTED_KEYS[@]}"; do
    if uninstall_feature "$key"; then
      SUCCEEDED_FEATURES+=("${FEATURE_TITLE[$key]}")
    else
      FAILED_FEATURES+=("${FEATURE_TITLE[$key]}")
      FINAL_EXIT_STATUS=1
    fi
  done
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
# 卸载成功后统一重启 Finder，刷新右键菜单缓存。
restart_finder_after_uninstall() {
  if (( ${#SUCCEEDED_FEATURES[@]} == 0 )); then
    warn_echo "没有成功卸载的功能，跳过 Finder 重启。"
    return 0
  fi

  note_echo "重启 Finder，刷新 Finder Sync 右键菜单缓存。"
  /usr/bin/killall Finder 2>&1 | tee -a "$LOG_FILE" || true
}
# 输出卸载结果、日志路径和后续排查提示。
print_done_tips() {
  local feature_name=""

  echo ""
  if (( ${#SUCCEEDED_FEATURES[@]} > 0 )); then
    success_echo "卸载成功："
    for feature_name in "${SUCCEEDED_FEATURES[@]}"; do
      gray_echo "- ${feature_name}"
    done
  fi

  if (( ${#FAILED_FEATURES[@]} > 0 )); then
    error_echo "卸载存在失败项："
    for feature_name in "${FAILED_FEATURES[@]}"; do
      gray_echo "- ${feature_name}"
    done
    gray_echo "请查看日志中的 rm / pluginkit 输出。"
  fi

  gray_echo "日志位置：${LOG_FILE}"
  gray_echo "工程源码仍保留在本目录；以后重新运行安装脚本或 Xcode 工程，会再次注册 Finder 扩展。"
  gray_echo "如果 Finder 菜单仍短暂显示，请注销后重新登录。"
  return "$FINAL_EXIT_STATUS"
}
# 编排脚本自述、功能选择、卸载和结果汇总。
main() {
  show_script_intro_and_wait # 展示卸载用途和影响范围，按回车后进入选择流程。
  init_runtime # 用户确认后初始化日志和 zsh 运行选项。
  check_environment # 检查 fzf、pluginkit、进程和删除命令。
  select_features_with_fzf # 使用 fzf 多选本次需要卸载的 Finder 扩展功能。
  print_selected_features # 输出已选择功能，方便卸载日志追踪。
  confirm_uninstall_with_enter # 选中功能后回车确认开始卸载。
  uninstall_selected_features # 逐个停用、注销并清理选中的 Finder Sync Extension。
  refresh_services_cache # 刷新 Services 缓存，移除旧 Automator 服务入口。
  restart_finder_after_uninstall # 对成功卸载的功能统一重启 Finder 刷新右键菜单。
  print_done_tips # 汇总卸载结果、日志路径和后续提示。
}

main "$@"
