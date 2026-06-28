#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】🧩安装Finder扩展.command
# - 核心用途：用 fzf 选择并安装本目录内的 Finder Sync Extension 功能，支持全选。
# - 影响范围：会调用 xcodebuild 构建选中的 macOS App，注册并启用 Finder Sync Extension，并重启 Finder 刷新右键菜单。
# - 运行提示：运行后会先打印内置自述；按回车确认后进入 fzf 多选，按 Tab 选择，按 Enter 安装。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
WORKSPACE_DIR="${SCRIPT_DIR}"
SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="${TMPDIR:-/tmp/}${SCRIPT_BASENAME}.log"
BUILD_CONFIGURATION="Debug"
ALL_OPTION="全选｜安装全部 Finder 扩展"
FINAL_EXIT_STATUS=0
SELECTED_KEYS=()
SUCCEEDED_FEATURES=()
FAILED_FEATURES=()
REGISTERED_PATHS=()

FEATURE_KEYS=(git_remote path_copier terminal_opener)
typeset -A FEATURE_TITLE
typeset -A FEATURE_PROJECT_DIR
typeset -A FEATURE_SCHEME
typeset -A FEATURE_APP_NAME
typeset -A FEATURE_EXTENSION_NAME
typeset -A FEATURE_EXTENSION_ID
typeset -A FEATURE_KEY_BY_TITLE

FEATURE_TITLE[git_remote]="打开 Git 远程地址"
FEATURE_PROJECT_DIR[git_remote]="JobsGitRemoteOpener"
FEATURE_SCHEME[git_remote]="JobsGitRemoteOpener"
FEATURE_APP_NAME[git_remote]="JobsGitRemoteOpener"
FEATURE_EXTENSION_NAME[git_remote]="JobsGitRemoteFinderSync.appex"
FEATURE_EXTENSION_ID[git_remote]="com.jobs.JobsGitRemoteOpener.FinderSyncExtension"
FEATURE_KEY_BY_TITLE[${FEATURE_TITLE[git_remote]}]="git_remote"

FEATURE_TITLE[path_copier]="复制绝对路径"
FEATURE_PROJECT_DIR[path_copier]="JobsPathCopier"
FEATURE_SCHEME[path_copier]="JobsPathCopier"
FEATURE_APP_NAME[path_copier]="JobsPathCopier"
FEATURE_EXTENSION_NAME[path_copier]="JobsPathCopyFinderSync.appex"
FEATURE_EXTENSION_ID[path_copier]="com.jobs.JobsPathCopier.FinderSyncExtension"
FEATURE_KEY_BY_TITLE[${FEATURE_TITLE[path_copier]}]="path_copier"

FEATURE_TITLE[terminal_opener]="用终端打开"
FEATURE_PROJECT_DIR[terminal_opener]="JobsTerminalOpener"
FEATURE_SCHEME[terminal_opener]="JobsTerminalOpener"
FEATURE_APP_NAME[terminal_opener]="JobsTerminalOpener"
FEATURE_EXTENSION_NAME[terminal_opener]="JobsTerminalFinderSync.appex"
FEATURE_EXTENSION_ID[terminal_opener]="com.jobs.JobsTerminalOpener.FinderSyncExtension"
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
  note_echo "核心用途：用 fzf 选择并安装 Finder 右键增强功能。"
  note_echo "可选功能：打开 Git 远程地址、复制绝对路径、用终端打开。"
  warn_echo "影响范围：会调用 xcodebuild 构建选中的 macOS App。"
  warn_echo "影响范围：会注册并启用对应 Finder Sync Extension。"
  warn_echo "影响范围：安装成功后会重启 Finder，刷新右键菜单缓存。"
  warn_echo "运行策略：按回车后进入 fzf；按 Ctrl+C 可以取消。"
  gray_echo "fzf 操作：Tab 多选，Enter 确认；选择“${ALL_OPTION}”会安装全部功能。"
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
# 获取当前 Mac CPU 架构，用于收敛 xcodebuild 目标。
get_cpu_arch() {
  [[ "$(uname -m)" == "arm64" ]] && print -r -- "arm64" || print -r -- "x86_64"
}
# 返回 LaunchServices 注册工具路径。
lsregister_path() {
  local tool_path="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

  [[ -x "$tool_path" ]] && print -r -- "$tool_path"
}
# 检查系统命令、MacOS 环境和工程结构是否满足安装要求。
check_environment() {
  local missing_commands=()
  local command_name=""
  local key=""
  local project_dir=""
  local project_file=""

  if [[ "$(uname -s)" != "Darwin" ]]; then
    error_echo "当前系统不是 MacOS，无法安装 Finder 扩展。"
    exit 1
  fi

  for command_name in fzf xcodebuild pluginkit open killall pkill grep head awk find mkdir tee sed; do
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

  if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
    error_echo "未检测到 Xcode 命令行工具，请先安装或选择 Xcode。"
    gray_echo "可执行：xcode-select --install"
    exit 1
  fi

  if [[ -z "$(lsregister_path)" ]]; then
    error_echo "未找到 LaunchServices 注册工具 lsregister。"
    exit 1
  fi

  for key in "${FEATURE_KEYS[@]}"; do
    project_dir="${WORKSPACE_DIR}/${FEATURE_PROJECT_DIR[$key]}"
    project_file="${project_dir}/${FEATURE_PROJECT_DIR[$key]}.xcodeproj"
    if [[ ! -d "$project_dir" || ! -d "$project_file" ]]; then
      error_echo "工程结构缺失：${project_file}"
      exit 1
    fi
  done
}
# 生成 fzf 多选列表。
print_fzf_options() {
  local key=""

  print -r -- "$ALL_OPTION"
  for key in "${FEATURE_KEYS[@]}"; do
    print -r -- "${FEATURE_TITLE[$key]}"
  done
}
# 去重追加一个待安装功能。
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
# 使用 fzf 选择本次需要安装的功能。
select_features_with_fzf() {
  local selection_output=""
  local fzf_status=0

  selection_output="$(print_fzf_options | fzf --multi --cycle --height=60% --border --prompt="选择要安装的功能 > " --header="Tab 多选，Enter 确认；选“${ALL_OPTION}”会安装全部。")"
  fzf_status=$?

  if (( fzf_status != 0 )); then
    warn_echo "已取消选择，未执行安装。"
    exit 0
  fi

  if [[ -z "$selection_output" ]]; then
    warn_echo "没有选择任何功能，未执行安装。"
    exit 0
  fi

  parse_fzf_selection "$selection_output"
  if (( ${#SELECTED_KEYS[@]} == 0 )); then
    warn_echo "没有解析到有效功能，未执行安装。"
    exit 0
  fi
}
# 输出用户已经选择的功能，便于日志排查。
print_selected_features() {
  local key=""

  note_echo "本次准备安装的功能："
  for key in "${SELECTED_KEYS[@]}"; do
    gray_echo "- ${FEATURE_TITLE[$key]}"
  done
}
# 返回指定功能的本地 DerivedData 目录。
derived_data_dir_for_key() {
  local key="$1"

  print -r -- "${WORKSPACE_DIR}/work/${FEATURE_PROJECT_DIR[$key]}DerivedData"
}
# 返回指定功能构建后的宿主 App 路径。
app_path_for_key() {
  local key="$1"
  local derived_data_dir=""

  derived_data_dir="$(derived_data_dir_for_key "$key")"
  print -r -- "${derived_data_dir}/Build/Products/${BUILD_CONFIGURATION}/${FEATURE_APP_NAME[$key]}.app"
}
# 返回指定功能构建后的 Finder Sync appex 路径。
extension_path_for_key() {
  local key="$1"
  local app_path=""

  app_path="$(app_path_for_key "$key")"
  print -r -- "${app_path}/Contents/PlugIns/${FEATURE_EXTENSION_NAME[$key]}"
}
# 返回指定功能构建目录下的散落 appex 路径。
standalone_extension_path_for_key() {
  local key="$1"
  local derived_data_dir=""

  derived_data_dir="$(derived_data_dir_for_key "$key")"
  print -r -- "${derived_data_dir}/Build/Products/${BUILD_CONFIGURATION}/${FEATURE_EXTENSION_NAME[$key]}"
}
# 运行 xcodebuild 构建指定功能的宿主 App 和 Finder Sync Extension。
build_feature() {
  local key="$1"
  local project_file="${WORKSPACE_DIR}/${FEATURE_PROJECT_DIR[$key]}/${FEATURE_PROJECT_DIR[$key]}.xcodeproj"
  local derived_data_dir=""
  local destination=""
  local build_status=0

  derived_data_dir="$(derived_data_dir_for_key "$key")"
  destination="platform=macOS,arch=$(get_cpu_arch)"
  /bin/mkdir -p "${WORKSPACE_DIR}/work"

  note_echo "开始构建：${FEATURE_TITLE[$key]}"
  gray_echo "工程路径：${project_file}"
  gray_echo "构建缓存：${derived_data_dir}"
  gray_echo "注册策略：构建阶段跳过自动注册，构建完成后由当前安装脚本统一处理。"

  JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1 /usr/bin/xcodebuild \
    -project "$project_file" \
    -scheme "${FEATURE_SCHEME[$key]}" \
    -configuration "$BUILD_CONFIGURATION" \
    -destination "$destination" \
    -derivedDataPath "$derived_data_dir" \
    build 2>&1 | tee -a "$LOG_FILE"
  build_status=${pipestatus[1]}

  if (( build_status != 0 )); then
    error_echo "构建失败：${FEATURE_TITLE[$key]}"
    return "$build_status"
  fi

  success_echo "构建完成：${FEATURE_TITLE[$key]}"
  return 0
}
# 查询 Finder Sync 扩展当前注册状态。
status_line_for_extension() {
  local extension_id="$1"
  local extension_path="$2"
  local lines=""
  local current_line=""

  lines="$(/usr/bin/pluginkit -m -p com.apple.FinderSync -A -v 2>/dev/null | /usr/bin/grep -F "$extension_id" || true)"
  current_line="$(print -r -- "$lines" | /usr/bin/grep -F "$extension_path" | /usr/bin/head -n 1 || true)"
  if [[ -n "$current_line" ]]; then
    print -r -- "$current_line"
    return 0
  fi

  print -r -- "$lines" | /usr/bin/head -n 1
}
# 等待 pluginkit 完成异步登记并进入启用状态。
wait_until_extension_enabled() {
  local extension_id="$1"
  local extension_path="$2"
  local attempt=""
  local line=""

  for attempt in {1..90}; do
    line="$(status_line_for_extension "$extension_id" "$extension_path")"
    gray_echo "轮询 ${attempt}/90：${line:-未登记}"
    if [[ "$line" == +* ]]; then
      return 0
    fi
    if [[ -n "$line" ]]; then
      /usr/bin/pluginkit -e use -i "$extension_id" 2>&1 | tee -a "$LOG_FILE" || true
    fi
    /bin/sleep 0.5
  done

  return 1
}
# 去重收集一个路径。
append_unique_path_if_needed() {
  local candidate_path="$1"
  local existed_path=""

  [[ -z "$candidate_path" ]] && return 0
  for existed_path in "${REGISTERED_PATHS[@]}"; do
    [[ "$existed_path" == "$candidate_path" ]] && return 0
  done
  REGISTERED_PATHS+=("$candidate_path")
}
# 从 LaunchServices / PlugInKit 里收集当前功能可能残留的注册路径。
collect_registered_paths_for_feature() {
  local key="$1"
  local app_id="com.jobs.${FEATURE_APP_NAME[$key]}"
  local extension_id="${FEATURE_EXTENSION_ID[$key]}"
  local extension_name="${FEATURE_EXTENSION_NAME[$key]}"
  local lsregister=""
  local registered_path=""

  REGISTERED_PATHS=()
  lsregister="$(lsregister_path)"

  while IFS= read -r registered_path; do
    append_unique_path_if_needed "$registered_path"
  done < <(
    /usr/bin/pluginkit -m -i "$extension_id" -A -D -vv 2>/dev/null \
      | /usr/bin/awk -F '= ' '/Path = / {print $2}'
  )

  while IFS= read -r registered_path; do
    append_unique_path_if_needed "$registered_path"
  done < <(
    "$lsregister" -dump 2>/dev/null | /usr/bin/awk -v app_id="$app_id" -v extension_id="$extension_id" '
      function flush_record() {
        if ((bundle_id == app_id || bundle_id == extension_id) && bundle_path != "") {
          print bundle_path
        }
        bundle_id = ""
        bundle_path = ""
      }
      /^--------------------------------------------------------------------------------$/ {
        flush_record()
        next
      }
      /^path:[[:space:]]+/ {
        bundle_path = $0
        sub(/^path:[[:space:]]+/, "", bundle_path)
        sub(/[[:space:]]+[(]0x[0-9a-fA-F]+[)].*$/, "", bundle_path)
      }
      /^identifier:[[:space:]]+/ {
        bundle_id = $0
        sub(/^identifier:[[:space:]]+/, "", bundle_id)
      }
      END {
        flush_record()
      }
    '
  )

  append_unique_path_if_needed "$(standalone_extension_path_for_key "$key")"
  while IFS= read -r registered_path; do
    append_unique_path_if_needed "$registered_path"
  done < <(
    /usr/bin/find "${HOME}/Library/Developer/Xcode/DerivedData" \
      \( -path "*/Build/Products/${BUILD_CONFIGURATION}/${extension_name}" -o -path "*/Index.noindex/Build/Products/${BUILD_CONFIGURATION}/${extension_name}" \) \
      -type d \
      -print 2>/dev/null
  )
}
# 清理同 Bundle ID 的旧注册记录，避免 Finder 发现阶段跳过当前扩展。
cleanup_stale_registration_records() {
  local key="$1"
  local app_path="$2"
  local extension_path="$3"
  local extension_id="${FEATURE_EXTENSION_ID[$key]}"
  local lsregister=""
  local registered_path=""

  lsregister="$(lsregister_path)"
  collect_registered_paths_for_feature "$key"

  note_echo "清理旧扩展注册记录：${extension_id}"
  for registered_path in "${REGISTERED_PATHS[@]}"; do
    [[ -z "$registered_path" ]] && continue
    if [[ "$registered_path" == "$app_path" || "$registered_path" == "$extension_path" ]]; then
      continue
    fi

    gray_echo "移除旧 LaunchServices 记录：${registered_path}"
    "$lsregister" -u "$registered_path" 2>&1 | tee -a "$LOG_FILE" || true

    if [[ -e "$registered_path" ]]; then
      /usr/bin/pluginkit -r "$registered_path" 2>&1 | tee -a "$LOG_FILE" || true
    fi
  done
}
# 先停止旧扩展进程，避免 Finder 持有旧构建产物。
stop_feature_processes() {
  local key="$1"
  local app_name="${FEATURE_APP_NAME[$key]}"
  local extension_process_name="${FEATURE_EXTENSION_NAME[$key]%.appex}"

  /usr/bin/pkill -x "$app_name" 2>/dev/null || true
  /usr/bin/pkill -f "${extension_process_name}.appex/Contents/MacOS/${extension_process_name}" 2>/dev/null || true
}
# 注册宿主 App 到 LaunchServices。
register_app_with_launchservices() {
  local app_path="$1"
  local lsregister=""
  local register_status=0

  lsregister="$(lsregister_path)"
  note_echo "注册宿主 App 到 LaunchServices：${app_path}"
  "$lsregister" -f "$app_path" 2>&1 | tee -a "$LOG_FILE"
  register_status=${pipestatus[1]}
  if (( register_status != 0 )); then
    error_echo "LaunchServices 注册失败：${app_path}"
    return "$register_status"
  fi

  return 0
}
# 注册并启用构建产物中的 Finder Sync Extension。
register_and_enable_feature() {
  local key="$1"
  local app_path=""
  local extension_path=""
  local extension_id="${FEATURE_EXTENSION_ID[$key]}"

  app_path="$(app_path_for_key "$key")"
  extension_path="$(extension_path_for_key "$key")"

  if [[ ! -d "$app_path" ]]; then
    error_echo "未找到构建后的 App：${app_path}"
    return 1
  fi

  if [[ ! -d "$extension_path" ]]; then
    error_echo "未找到构建后的 Finder Sync Extension：${extension_path}"
    return 1
  fi

  stop_feature_processes "$key"
  cleanup_stale_registration_records "$key" "$app_path" "$extension_path"
  register_app_with_launchservices "$app_path" || return 1

  note_echo "清除当前扩展旧登记：${extension_path}"
  /usr/bin/pluginkit -r "$extension_path" 2>&1 | tee -a "$LOG_FILE" || true

  note_echo "注册扩展：${extension_id}"
  /usr/bin/pluginkit -a "$extension_path" 2>&1 | tee -a "$LOG_FILE"
  if (( ${pipestatus[1]} != 0 )); then
    error_echo "pluginkit 注册失败：${extension_path}"
    return 1
  fi

  note_echo "启用扩展：${extension_id}"
  /usr/bin/pluginkit -e use -i "$extension_id" 2>&1 | tee -a "$LOG_FILE"
  if (( ${pipestatus[1]} != 0 )); then
    error_echo "pluginkit 启用失败：${extension_id}"
    return 1
  fi

  if wait_until_extension_enabled "$extension_id" "$extension_path"; then
    success_echo "扩展已启用：${FEATURE_TITLE[$key]}"
    return 0
  fi

  warn_echo "扩展尚未进入启用状态，尝试后台启动宿主 App 完成自注册。"
  /usr/bin/open -gj "$app_path" 2>&1 | tee -a "$LOG_FILE" || true
  /bin/sleep 2
  /usr/bin/pluginkit -e use -i "$extension_id" 2>&1 | tee -a "$LOG_FILE" || true

  if wait_until_extension_enabled "$extension_id" "$extension_path"; then
    success_echo "扩展已启用：${FEATURE_TITLE[$key]}"
    return 0
  fi

  error_echo "扩展启用超时：${FEATURE_TITLE[$key]}"
  return 1
}
# 安装单个 Finder 扩展功能。
install_feature() {
  local key="$1"

  highlight_echo "============================== ${FEATURE_TITLE[$key]} =============================="
  build_feature "$key" || return 1
  register_and_enable_feature "$key" || return 1
  return 0
}
# 逐个安装用户选择的 Finder 扩展功能。
install_selected_features() {
  local key=""

  FINAL_EXIT_STATUS=0
  for key in "${SELECTED_KEYS[@]}"; do
    if install_feature "$key"; then
      SUCCEEDED_FEATURES+=("${FEATURE_TITLE[$key]}")
    else
      FAILED_FEATURES+=("${FEATURE_TITLE[$key]}")
      FINAL_EXIT_STATUS=1
    fi
  done
}
# 安装成功后统一重启 Finder，刷新右键菜单缓存。
restart_finder_after_install() {
  if (( ${#SUCCEEDED_FEATURES[@]} == 0 )); then
    warn_echo "没有成功安装的功能，跳过 Finder 重启。"
    return 0
  fi

  note_echo "重启 Finder，刷新 Finder Sync 右键菜单缓存。"
  note_echo "重启 PlugInKit Daemon，刷新扩展发现索引。"
  /usr/bin/pkill -x pkd 2>/dev/null || true
  /usr/bin/killall Finder 2>&1 | tee -a "$LOG_FILE" || true
}
# 输出安装结果、日志路径和后续排查提示。
print_done_tips() {
  local feature_name=""

  echo ""
  if (( ${#SUCCEEDED_FEATURES[@]} > 0 )); then
    success_echo "安装成功："
    for feature_name in "${SUCCEEDED_FEATURES[@]}"; do
      gray_echo "- ${feature_name}"
    done
  fi

  if (( ${#FAILED_FEATURES[@]} > 0 )); then
    error_echo "安装失败："
    for feature_name in "${FAILED_FEATURES[@]}"; do
      gray_echo "- ${feature_name}"
    done
    gray_echo "请查看日志中的 xcodebuild / pluginkit 输出。"
  fi

  gray_echo "日志位置：${LOG_FILE}"
  gray_echo "如果 Finder 右键菜单仍未出现，请到 系统设置 -> 隐私与安全性 -> 扩展 -> Finder 扩展 中确认开关。"
  return "$FINAL_EXIT_STATUS"
}
# 编排脚本自述、功能选择、安装和结果汇总。
main() {
  show_script_intro_and_wait # 展示安装用途和影响范围，按回车后进入选择流程。
  init_runtime # 用户确认后初始化日志和 zsh 运行选项。
  check_environment # 检查 fzf、xcodebuild、pluginkit 和工程结构。
  select_features_with_fzf # 使用 fzf 多选本次需要安装的 Finder 扩展功能。
  print_selected_features # 输出已选择功能，方便安装日志追踪。
  install_selected_features # 逐个构建、注册并启用选中的 Finder Sync Extension。
  restart_finder_after_install # 对成功安装的功能统一重启 Finder 刷新右键菜单。
  print_done_tips # 汇总安装结果、日志路径和后续排查提示。
}

main "$@"
