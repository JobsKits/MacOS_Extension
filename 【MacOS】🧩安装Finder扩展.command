#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】🧩安装Finder扩展.command
# - 核心用途：用原生复选框 UI 选择并安装本目录内的 Finder Sync Extension 功能，支持全选与全不选。
# - 影响范围：会构建、注册并启用选中的 Finder 扩展，保存 Terminal 功能选择，并重启 Finder 刷新右键菜单。
# - 运行提示：运行后会先打印内置自述；按回车确认后，在原生 UI 中勾选需要安装的右键菜单功能。

# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
jobs_intro_style() {
  local intro_color=0
  if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
     [ -z "${NO_COLOR+x}" ] && [ "${PLAIN_OUTPUT:-0}" != 1 ] &&
     [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]; then
    intro_color=1
  fi
  /usr/bin/awk -v color="$intro_color" -v role="${1:-body}" '
    BEGIN { esc = sprintf("%c", 27) }
    {
      gsub(esc "\\[[0-9;]*m", "")
      gsub(/\\(033|e|x1[bB])\[[0-9;]*m/, "")
      if (!color || $0 ~ /^[[:space:]]*$/) { print; next }
      numbered = ($0 ~ /^[[:space:]➤ℹ🔹✔⚠]*([0-9]+[、.)）]|[0-9]+️⃣|[-•])/)
      heading = ($0 ~ /^[[:space:]]*#{1,6}[[:space:]]/ || $0 ~ /[：:][[:space:]]*$/ || $0 ~ /^[[:space:]]*[=━─-]{3}/)
      title = (!numbered && (role == "title" || heading))
      if (role == "auto" && !seen && !numbered) title = 1
      if ($0 !~ /^[[:space:]]*[=━─-]+[[:space:]]*$/) seen = 1
      printf "%s%s%s\n", esc (title ? "[1;31m" : "[0;34m"), $0, esc "[0m"
    }
  '
}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
WORKSPACE_DIR="${SCRIPT_DIR}"
SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="${TMPDIR:-/tmp/}${SCRIPT_BASENAME}.log"
BUILD_CONFIGURATION="Debug"
FEATURE_SELECTOR_SOURCE_PATH="${WORKSPACE_DIR}/Scripts/SelectFinderExtensionFeatures.swift"
FEATURE_SELECTOR_BINARY_PATH="${WORKSPACE_DIR}/work/SelectFinderExtensionFeatures"
TERMINAL_FEATURE_CONFIG_DIR=""
TERMINAL_FEATURE_CONFIG_PATH=""
FINAL_EXIT_STATUS=0
SELECTED_KEYS=()
SELECTED_FUNCTION_IDS=()
SUCCEEDED_FEATURES=()
FAILED_FEATURES=()
REGISTERED_PATHS=()
TERMINAL_OPENER_ENABLED_FEATURES=""

FEATURE_KEYS=(git_remote git_remote_copier path_copier xcode_opener vscode_opener android_studio_opener flutter_version_manager git-pull flutter-dependency-extract flutter-run ios-simulator-create terminal_opener)
typeset -A FEATURE_TITLE
typeset -A FEATURE_PROJECT_DIR
typeset -A FEATURE_SCHEME
typeset -A FEATURE_APP_NAME
typeset -A FEATURE_APP_ID
typeset -A FEATURE_EXTENSION_NAME
typeset -A FEATURE_EXTENSION_ID
typeset -A SELECTABLE_FUNCTION_TITLE
typeset -A SELECTABLE_FUNCTION_PROJECT_KEY
typeset -A SELECTABLE_FUNCTION_TERMINAL_ACTION

FEATURE_TITLE[git_remote]="打开 Git 远程地址"
FEATURE_PROJECT_DIR[git_remote]="JobsGitRemoteOpener"
FEATURE_SCHEME[git_remote]="JobsGitRemoteOpener"
FEATURE_APP_NAME[git_remote]="JobsGitRemoteOpener"
FEATURE_EXTENSION_NAME[git_remote]="JobsGitRemoteFinderSync.appex"
FEATURE_EXTENSION_ID[git_remote]="com.jobs.JobsGitRemoteOpener.FinderSyncExtension"

FEATURE_TITLE[git_remote_copier]="复制 Git 远程地址"
FEATURE_PROJECT_DIR[git_remote_copier]="JobsGitRemoteCopier"
FEATURE_SCHEME[git_remote_copier]="JobsGitRemoteCopier"
FEATURE_APP_NAME[git_remote_copier]="JobsGitRemoteCopier"
FEATURE_EXTENSION_NAME[git_remote_copier]="JobsGitRemoteCopyFinderSync.appex"
FEATURE_EXTENSION_ID[git_remote_copier]="com.jobs.JobsGitRemoteCopier.FinderSyncExtension"

FEATURE_TITLE[path_copier]="复制绝对路径"
FEATURE_PROJECT_DIR[path_copier]="JobsPathCopier"
FEATURE_SCHEME[path_copier]="JobsPathCopier"
FEATURE_APP_NAME[path_copier]="JobsPathCopier"
FEATURE_EXTENSION_NAME[path_copier]="JobsPathCopyFinderSync.appex"
FEATURE_EXTENSION_ID[path_copier]="com.jobs.JobsPathCopier.FinderSyncExtension"

FEATURE_TITLE[xcode_opener]="用 Xcode 打开项目"
FEATURE_PROJECT_DIR[xcode_opener]="JobsXcodeOpener"
FEATURE_SCHEME[xcode_opener]="JobsXcodeOpener"
FEATURE_APP_NAME[xcode_opener]="JobsXcodeOpener"
FEATURE_EXTENSION_NAME[xcode_opener]="JobsXcodeFinderSync.appex"
FEATURE_EXTENSION_ID[xcode_opener]="com.jobs.JobsXcodeOpener.FinderSyncExtension"

FEATURE_TITLE[vscode_opener]="用 VSCode 打开项目"
FEATURE_PROJECT_DIR[vscode_opener]="JobsVSCodeOpener"
FEATURE_SCHEME[vscode_opener]="JobsVSCodeOpener"
FEATURE_APP_NAME[vscode_opener]="JobsVSCodeOpener"
FEATURE_EXTENSION_NAME[vscode_opener]="JobsVSCodeFinderSync.appex"
FEATURE_EXTENSION_ID[vscode_opener]="com.jobs.JobsVSCodeOpener.FinderSyncExtension"

FEATURE_TITLE[android_studio_opener]="用 Android Studio 打开项目"
FEATURE_PROJECT_DIR[android_studio_opener]="JobsAndroidStudioOpener"
FEATURE_SCHEME[android_studio_opener]="JobsAndroidStudioOpener"
FEATURE_APP_NAME[android_studio_opener]="JobsAndroidStudioOpener"
FEATURE_EXTENSION_NAME[android_studio_opener]="JobsAndroidStudioFinderSync.appex"
FEATURE_EXTENSION_ID[android_studio_opener]="com.jobs.JobsAndroidStudioOpener.FinderSyncExtension"

FEATURE_TITLE[flutter_version_manager]="安装/切换 Flutter SDK（FVM）"
FEATURE_PROJECT_DIR[flutter_version_manager]="JobsFlutterVersionMgr"
FEATURE_SCHEME[flutter_version_manager]="JobsFlutterVersionMgr"
FEATURE_APP_NAME[flutter_version_manager]="JobsFlutterVersionMgr"
FEATURE_EXTENSION_NAME[flutter_version_manager]="JobsFlutterVersionFinderSync.appex"
FEATURE_EXTENSION_ID[flutter_version_manager]="com.jobs.JobsFlutterVersionMgr.FinderSyncExtension"

FEATURE_TITLE[git-pull]="拉取 Git 到最新"
FEATURE_PROJECT_DIR[git-pull]="JobsGitPuller"
FEATURE_SCHEME[git-pull]="JobsGitPuller"
FEATURE_APP_NAME[git-pull]="JobsGitPuller"
FEATURE_EXTENSION_NAME[git-pull]="JobsGitPullFinderSync.appex"
FEATURE_EXTENSION_ID[git-pull]="com.jobs.JobsGitPuller.FinderSyncExtension"

FEATURE_TITLE[flutter-dependency-extract]="提取 Flutter 第三方依赖"
FEATURE_PROJECT_DIR[flutter-dependency-extract]="JobsFlutterDependencyExtractor"
FEATURE_SCHEME[flutter-dependency-extract]="JobsFlutterDependencyExtractor"
FEATURE_APP_NAME[flutter-dependency-extract]="JobsFlutterDependencyExtractor"
FEATURE_EXTENSION_NAME[flutter-dependency-extract]="JobsFlutterDependencyFinderSync.appex"
FEATURE_EXTENSION_ID[flutter-dependency-extract]="com.jobs.JobsFlutterDependencyExtractor.FinderSync"

FEATURE_TITLE[flutter-run]="运行 Flutter 项目"
FEATURE_PROJECT_DIR[flutter-run]="JobsFlutterRunner"
FEATURE_SCHEME[flutter-run]="JobsFlutterRunner"
FEATURE_APP_NAME[flutter-run]="JobsFlutterRunner"
FEATURE_EXTENSION_NAME[flutter-run]="JobsFlutterRunFinderSync.appex"
FEATURE_EXTENSION_ID[flutter-run]="com.jobs.JobsFlutterRunner.FinderSyncExtension"

FEATURE_TITLE[ios-simulator-create]="新建 iOS 模拟器"
FEATURE_PROJECT_DIR[ios-simulator-create]="JobsIOSSimulatorCreator"
FEATURE_SCHEME[ios-simulator-create]="JobsIOSSimulatorCreator"
FEATURE_APP_NAME[ios-simulator-create]="JobsIOSSimulatorCreator"
FEATURE_APP_ID[ios-simulator-create]="com.jobs.iossimulatorcreator"
FEATURE_EXTENSION_NAME[ios-simulator-create]="JobsIOSSimulatorFinderSync.appex"
FEATURE_EXTENSION_ID[ios-simulator-create]="com.jobs.iossimulatorcreator.findersync"

FEATURE_TITLE[terminal_opener]="JobsTerminalOpener"
FEATURE_PROJECT_DIR[terminal_opener]="JobsTerminalOpener"
FEATURE_SCHEME[terminal_opener]="JobsTerminalOpener"
FEATURE_APP_NAME[terminal_opener]="JobsTerminalOpener"
FEATURE_EXTENSION_NAME[terminal_opener]="JobsTerminalFinderSync.appex"
FEATURE_EXTENSION_ID[terminal_opener]="com.jobs.JobsTerminalOpener.FinderSyncExtension"

SELECTABLE_FUNCTION_IDS=(git_remote git_remote_copier path_copier xcode_opener vscode_opener android_studio_opener flutter_version_manager git-pull flutter-dependency-extract flutter-run ios-simulator-create terminal_open pod_install flutter_pub_get codegraph_bootstrap git_empty_commit_push)
SELECTABLE_FUNCTION_TITLE[git_remote]="打开 Git 远程地址"
SELECTABLE_FUNCTION_PROJECT_KEY[git_remote]="git_remote"
SELECTABLE_FUNCTION_TITLE[git_remote_copier]="复制 Git 远程地址"
SELECTABLE_FUNCTION_PROJECT_KEY[git_remote_copier]="git_remote_copier"
SELECTABLE_FUNCTION_TITLE[path_copier]="复制绝对路径"
SELECTABLE_FUNCTION_PROJECT_KEY[path_copier]="path_copier"
SELECTABLE_FUNCTION_TITLE[xcode_opener]="用 Xcode 打开项目"
SELECTABLE_FUNCTION_PROJECT_KEY[xcode_opener]="xcode_opener"
SELECTABLE_FUNCTION_TITLE[vscode_opener]="用 VSCode 打开项目"
SELECTABLE_FUNCTION_PROJECT_KEY[vscode_opener]="vscode_opener"
SELECTABLE_FUNCTION_TITLE[android_studio_opener]="用 Android Studio 打开项目"
SELECTABLE_FUNCTION_PROJECT_KEY[android_studio_opener]="android_studio_opener"
SELECTABLE_FUNCTION_TITLE[flutter_version_manager]="安装/切换 Flutter SDK（FVM）"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter_version_manager]="flutter_version_manager"
SELECTABLE_FUNCTION_TITLE[git-pull]="拉取 Git 到最新"
SELECTABLE_FUNCTION_PROJECT_KEY[git-pull]="git-pull"
SELECTABLE_FUNCTION_TITLE[flutter-dependency-extract]="提取 Flutter 第三方依赖"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-dependency-extract]="flutter-dependency-extract"
SELECTABLE_FUNCTION_TITLE[flutter-run]="运行 Flutter 项目"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter-run]="flutter-run"
SELECTABLE_FUNCTION_TITLE[ios-simulator-create]="新建 iOS 模拟器"
SELECTABLE_FUNCTION_PROJECT_KEY[ios-simulator-create]="ios-simulator-create"
SELECTABLE_FUNCTION_TITLE[terminal_open]="用终端打开"
SELECTABLE_FUNCTION_PROJECT_KEY[terminal_open]="terminal_opener"
SELECTABLE_FUNCTION_TERMINAL_ACTION[terminal_open]="open"
SELECTABLE_FUNCTION_TITLE[pod_install]="pod install"
SELECTABLE_FUNCTION_PROJECT_KEY[pod_install]="terminal_opener"
SELECTABLE_FUNCTION_TERMINAL_ACTION[pod_install]="pod-install"
SELECTABLE_FUNCTION_TITLE[flutter_pub_get]="在终端执行 flutter pub get"
SELECTABLE_FUNCTION_PROJECT_KEY[flutter_pub_get]="terminal_opener"
SELECTABLE_FUNCTION_TERMINAL_ACTION[flutter_pub_get]="flutter-pub-get"
SELECTABLE_FUNCTION_TITLE[codegraph_bootstrap]="更新代码地图（.codegraph）"
SELECTABLE_FUNCTION_PROJECT_KEY[codegraph_bootstrap]="terminal_opener"
SELECTABLE_FUNCTION_TERMINAL_ACTION[codegraph_bootstrap]="codegraph-bootstrap"
SELECTABLE_FUNCTION_TITLE[git_empty_commit_push]="在终端创建空白 Commit 并 Push"
SELECTABLE_FUNCTION_PROJECT_KEY[git_empty_commit_push]="terminal_opener"
SELECTABLE_FUNCTION_TERMINAL_ACTION[git_empty_commit_push]="git-empty-commit-push"

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
  highlight_echo "============================== 脚本自述 ==============================" | jobs_intro_style title
  note_echo "当前脚本：${SCRIPT_PATH}" | jobs_intro_style body
  note_echo "核心用途：用原生复选框 UI 选择并安装 Finder 右键增强功能。" | jobs_intro_style body
  note_echo "可选功能：共 ${#SELECTABLE_FUNCTION_IDS[@]} 项；JobsTerminalOpener 内含 5 项，可分别勾选。" | jobs_intro_style body
  warn_echo "影响范围：会调用 xcodebuild 构建选中的 macOS App。" | jobs_intro_style body
  warn_echo "影响范围：会注册并启用对应 Finder Sync Extension。" | jobs_intro_style body
  warn_echo "影响范围：会保存 JobsTerminalOpener 的功能选择，之后也可在 App 内修改。" | jobs_intro_style body
  warn_echo "影响范围：安装成功后会重启 Finder，刷新右键菜单缓存。" | jobs_intro_style body
  warn_echo "运行策略：按回车后打开原生勾选窗口；按 Ctrl+C 或窗口中的“取消”可以终止。" | jobs_intro_style body
  gray_echo "UI 操作：可“全选”或“全不选”，选好后点击“安装”；未勾选时安装按钮置灰。" | jobs_intro_style body
  gray_echo "日志位置：${LOG_FILE}" | jobs_intro_style body
  highlight_echo "=======================================================================" | jobs_intro_style title
  echo "" | jobs_intro_style body

  if [[ ! -t 0 ]]; then
    error_echo "当前没有可交互输入，无法进入安装选择。请在终端里运行本脚本。"
    exit 1
  fi

  local _
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 初始化 zsh 运行选项和日志文件。
init_runtime() {
  setopt NO_NOMATCH
  : > "$LOG_FILE"
  if [[ -z "${HOME:-}" || ! -d "$HOME" ]]; then
    error_echo "无法确定当前用户目录，不能安全保存 Terminal 功能选择。"
    exit 1
  fi
  TERMINAL_FEATURE_CONFIG_DIR="${HOME}/Library/Application Support/JobsTerminalOpener"
  TERMINAL_FEATURE_CONFIG_PATH="${TERMINAL_FEATURE_CONFIG_DIR}/EnabledFinderMenuFeatures.txt"
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
# 返回指定 Finder 扩展功能对应的 Xcode 工程路径。
project_file_for_key() {
  local key="$1"

  print -r -- "${WORKSPACE_DIR}/${FEATURE_PROJECT_DIR[$key]}/${FEATURE_PROJECT_DIR[$key]}.xcodeproj"
}
# 判断本仓全部 Finder 扩展工程的配置文件是否齐全。
feature_projects_ready() {
  local key=""
  local project_file=""

  for key in "${FEATURE_KEYS[@]}"; do
    project_file="$(project_file_for_key "$key")"
    [[ ! -f "${project_file}/project.pbxproj" ]] && return 1
  done

  return 0
}
# 输出缺失的本仓工程配置和完整源码取得方式。
print_missing_feature_projects() {
  local key=""
  local project_file=""

  error_echo "Finder 扩展工程源码不完整；${#FEATURE_KEYS[@]} 个工程均随当前仓库统一管理。"
  for key in "${FEATURE_KEYS[@]}"; do
    project_file="$(project_file_for_key "$key")"
    if [[ ! -f "${project_file}/project.pbxproj" ]]; then
      gray_echo "- ${FEATURE_TITLE[$key]}：${project_file}/project.pbxproj"
    fi
  done
  error_echo "请重新取得包含全部工程源码的完整 MacOS@Extension 仓库后重试。"
}
# 缺少工程配置时停止安装，避免使用不完整的仓库源码。
ensure_feature_projects_exist() {
  feature_projects_ready && return 0

  print_missing_feature_projects
  return 1
}
# 检查系统命令、MacOS 环境和工程结构是否满足安装要求。
check_environment() {
  local missing_commands=()
  local command_name=""

  if [[ "$(uname -s)" != "Darwin" ]]; then
    error_echo "当前系统不是 MacOS，无法安装 Finder 扩展。"
    exit 1
  fi

  for command_name in osascript xcodebuild pluginkit open killall pkill grep head awk find mkdir tee sed; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      missing_commands+=("$command_name")
    fi
  done

  if (( ${#missing_commands[@]} > 0 )); then
    error_echo "缺少必要命令：${(j:, :)missing_commands}"
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

  if [[ ! -f "$FEATURE_SELECTOR_SOURCE_PATH" ]]; then
    error_echo "未找到 Finder 功能选择 UI 源码：${FEATURE_SELECTOR_SOURCE_PATH}"
    exit 1
  fi

  ensure_feature_projects_exist || exit 1
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
# 去重追加一个用户勾选的右键菜单功能。
append_selected_function_id_if_needed() {
  local function_id="$1"
  local existed_function_id=""

  for existed_function_id in "${SELECTED_FUNCTION_IDS[@]}"; do
    [[ "$existed_function_id" == "$function_id" ]] && return 1
  done
  SELECTED_FUNCTION_IDS+=("$function_id")
  return 0
}
# 把原生 UI 返回的功能标识解析成工程和 Terminal 子功能。
parse_feature_selection() {
  local selection_output="$1"
  local selected_function_id=""
  local project_key=""
  local terminal_action=""
  local terminal_actions=()

  SELECTED_KEYS=()
  SELECTED_FUNCTION_IDS=()
  TERMINAL_OPENER_ENABLED_FEATURES=""
  for selected_function_id in ${(s:,:)selection_output}; do
    project_key="${SELECTABLE_FUNCTION_PROJECT_KEY[$selected_function_id]}"
    if [[ -z "$project_key" ]]; then
      error_echo "功能选择 UI 返回了未知标识：${selected_function_id}"
      return 1
    fi

    append_selected_function_id_if_needed "$selected_function_id" || continue
    append_selected_key_if_needed "$project_key"
    if [[ "$project_key" == "terminal_opener" ]]; then
      terminal_action="${SELECTABLE_FUNCTION_TERMINAL_ACTION[$selected_function_id]}"
      [[ -n "$terminal_action" ]] && terminal_actions+=("$terminal_action")
    fi
  done
  TERMINAL_OPENER_ENABLED_FEATURES="${(j:,:)terminal_actions}"
}
# 编译功能选择窗口（源码更新后自动重编），产物缓存在 work 目录。
build_feature_selector_if_needed() {
  if [[ -x "$FEATURE_SELECTOR_BINARY_PATH" && ! "$FEATURE_SELECTOR_SOURCE_PATH" -nt "$FEATURE_SELECTOR_BINARY_PATH" ]]; then
    return 0
  fi

  note_echo "正在编译功能选择窗口（首次或源码更新后会多几秒）..."
  /bin/mkdir -p "${WORKSPACE_DIR}/work"
  /usr/bin/xcrun swiftc -O "$FEATURE_SELECTOR_SOURCE_PATH" -o "$FEATURE_SELECTOR_BINARY_PATH" 2>&1 | tee -a "$LOG_FILE"
  if (( ${pipestatus[1]} != 0 )); then
    error_echo "功能选择窗口编译失败，无法继续安装。"
    return 1
  fi

  return 0
}

# 使用原生 macOS 复选框 UI 选择本次需要安装的右键菜单功能。
select_features_with_ui() {
  local selection_output=""
  local selector_status=0

  build_feature_selector_if_needed || exit 1
  selection_output="$("$FEATURE_SELECTOR_BINARY_PATH")"
  selector_status=$?

  if (( selector_status != 0 )); then
    error_echo "Finder 功能选择 UI 运行失败，退出码：${selector_status}"
    exit "$selector_status"
  fi

  if [[ "$selection_output" == "__CANCELLED__" ]]; then
    warn_echo "已取消功能选择，未执行安装。"
    exit 0
  fi
  if [[ "$selection_output" == "__NONE__" || -z "$selection_output" ]]; then
    warn_echo "没有选择任何功能，未执行安装。"
    exit 0
  fi

  parse_feature_selection "$selection_output" || exit 1
  if (( ${#SELECTED_KEYS[@]} == 0 || ${#SELECTED_FUNCTION_IDS[@]} == 0 )); then
    warn_echo "没有解析到有效功能，未执行安装。"
    exit 0
  fi
}
# 输出用户已经选择的功能，便于日志排查。
print_selected_features() {
  local selected_function_id=""

  note_echo "本次准备安装的功能："
  for selected_function_id in "${SELECTED_FUNCTION_IDS[@]}"; do
    gray_echo "- ${SELECTABLE_FUNCTION_TITLE[$selected_function_id]}"
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
  local extra_build_settings=()

  derived_data_dir="$(derived_data_dir_for_key "$key")"
  destination="platform=macOS,arch=$(get_cpu_arch)"
  /bin/mkdir -p "${WORKSPACE_DIR}/work"

  note_echo "开始构建：${FEATURE_TITLE[$key]}"
  gray_echo "工程路径：${project_file}"
  gray_echo "构建缓存：${derived_data_dir}"
  gray_echo "注册策略：构建阶段跳过自动注册，构建完成后由当前安装脚本统一处理。"
  if [[ "$key" == "terminal_opener" ]]; then
    extra_build_settings+=("JOBS_TERMINAL_ENABLED_FEATURES=${TERMINAL_OPENER_ENABLED_FEATURES}")
    gray_echo "Terminal 右键功能：${TERMINAL_OPENER_ENABLED_FEATURES}"
  fi

  JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1 /usr/bin/xcodebuild \
    -project "$project_file" \
    -scheme "${FEATURE_SCHEME[$key]}" \
    -configuration "$BUILD_CONFIGURATION" \
    -destination "$destination" \
    -derivedDataPath "$derived_data_dir" \
    "${extra_build_settings[@]}" \
    build 2>&1 | tee -a "$LOG_FILE"
  build_status=${pipestatus[1]}

  if (( build_status != 0 )); then
    error_echo "构建失败：${FEATURE_TITLE[$key]}"
    return "$build_status"
  fi

  success_echo "构建完成：${FEATURE_TITLE[$key]}"
  return 0
}
# 只查询当前产物的注册状态，旧路径已启用不能代替本次安装成功。
status_line_for_extension() {
  local extension_id="$1"
  local extension_path="$2"
  local lines=""
  local current_line=""

  lines="$(/usr/bin/pluginkit -m -p com.apple.FinderSync -A -v 2>/dev/null | /usr/bin/grep -F "$extension_id" || true)"
  while IFS= read -r current_line; do
    if [[ "$current_line" == *[[:space:]]"$extension_path" ]]; then
      print -r -- "$current_line"
      return 0
    fi
  done <<< "$lines"

  return 1
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
# 返回宿主 Bundle ID，保留旧功能按产品名推导的兼容规则。
app_bundle_id_for_key() {
  local key="$1"

  print -r -- "${FEATURE_APP_ID[$key]:-com.jobs.${FEATURE_APP_NAME[$key]}}"
}
# 从 LaunchServices / PlugInKit 里收集当前功能可能残留的注册路径。
collect_registered_paths_for_feature() {
  local key="$1"
  local app_id="$(app_bundle_id_for_key "$key")"
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
# 后台启动宿主完成初始化，新模拟器宿主只接受显式初始化参数。
open_host_for_extension_registration() {
  local key="$1"
  local app_path="$2"
  local open_arguments=(-gj "$app_path")

  if [[ "$key" == "ios-simulator-create" ]]; then
    open_arguments+=(--args --initialize-finder-extension)
  fi
  /usr/bin/open "${open_arguments[@]}"
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
  open_host_for_extension_registration "$key" "$app_path" 2>&1 | tee -a "$LOG_FILE" || true
  /bin/sleep 2
  /usr/bin/pluginkit -e use -i "$extension_id" 2>&1 | tee -a "$LOG_FILE" || true

  if wait_until_extension_enabled "$extension_id" "$extension_path"; then
    success_echo "扩展已启用：${FEATURE_TITLE[$key]}"
    return 0
  fi

  error_echo "扩展启用超时：${FEATURE_TITLE[$key]}"
  return 1
}
# 保存 JobsTerminalOpener 的右键功能选择，供宿主 App 和 Finder 扩展共同读取。
persist_terminal_feature_selection() {
  local key="$1"

  [[ "$key" != "terminal_opener" ]] && return 0
  if ! /bin/mkdir -p "$TERMINAL_FEATURE_CONFIG_DIR"; then
    error_echo "无法创建 Terminal 功能配置目录：${TERMINAL_FEATURE_CONFIG_DIR}"
    return 1
  fi
  if ! print -nr -- "$TERMINAL_OPENER_ENABLED_FEATURES" > "$TERMINAL_FEATURE_CONFIG_PATH"; then
    error_echo "无法保存 Terminal 功能选择：${TERMINAL_FEATURE_CONFIG_PATH}"
    return 1
  fi

  success_echo "Terminal 功能选择已保存，之后可在 JobsTerminalOpener App 内修改。"
  return 0
}
# 安装单个 Finder 扩展功能。
install_feature() {
  local key="$1"

  highlight_echo "============================== ${FEATURE_TITLE[$key]} =============================="
  build_feature "$key" || return 1
  register_and_enable_feature "$key" || return 1
  persist_terminal_feature_selection "$key" || return 1
  return 0
}
# 把一个工程的安装结果展开为用户勾选的右键菜单功能。
record_project_install_result() {
  local key="$1"
  local did_succeed="$2"
  local selected_function_id=""

  for selected_function_id in "${SELECTED_FUNCTION_IDS[@]}"; do
    [[ "${SELECTABLE_FUNCTION_PROJECT_KEY[$selected_function_id]}" != "$key" ]] && continue
    if [[ "$did_succeed" == "1" ]]; then
      SUCCEEDED_FEATURES+=("${SELECTABLE_FUNCTION_TITLE[$selected_function_id]}")
    else
      FAILED_FEATURES+=("${SELECTABLE_FUNCTION_TITLE[$selected_function_id]}")
    fi
  done
}
# 逐个安装用户选择的 Finder 扩展功能。
install_selected_features() {
  local key=""

  FINAL_EXIT_STATUS=0
  for key in "${SELECTED_KEYS[@]}"; do
    if install_feature "$key"; then
      record_project_install_result "$key" "1"
    else
      record_project_install_result "$key" "0"
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
  check_environment # 检查原生 UI、xcodebuild、pluginkit 和本仓工程配置，缺失时停止安装。
  select_features_with_ui # 使用原生复选框 UI 选择每个 Finder 右键菜单功能。
  print_selected_features # 输出已选择功能，方便安装日志追踪。
  install_selected_features # 逐个构建、注册并启用选中的 Finder Sync Extension。
  restart_finder_after_install # 对成功安装的功能统一重启 Finder 刷新右键菜单。
  print_done_tips # 汇总安装结果、日志路径和后续排查提示。
}

main "$@"
