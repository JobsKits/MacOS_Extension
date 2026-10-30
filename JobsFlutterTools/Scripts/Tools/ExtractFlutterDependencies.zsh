#!/bin/zsh
# 脚本自述：
# - 脚本名称：提取 Flutter 第三方依赖。
# - 核心用途：复制已解析 Pub 第三方包及许可证，包含直接、间接和开发依赖。
# - 影响范围：只读项目及缓存，向指定目录新建独立源码快照，不下载或改写依赖。
# - 运行提示：先回车确认；项目和目标支持输入或拖入，目标直接回车为系统桌面。

PRIVATE_ONLY=0
typeset -a SCOPE_ARGS=()
if [[ "${1:-}" == --private-only ]]; then
  PRIVATE_ONLY=1
  SCOPE_ARGS=(--private-only)
  shift
fi
SCRIPT_DIR=""
SCRIPT_PATH=""
LOG_FILE=""
PROJECT_PATH=""
DESTINATION_PATH=""
DART_EXECUTABLE=""
# 自述根据终端能力降级为纯文本，不给日志加入 ANSI。
intro_line() {
  local role="$1" message="$2" code="0;34"
  [[ "$role" == title ]] && code="1;31"
  if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" ]]; then
    printf '\033[%sm%s\033[0m\n' "$code" "$message"
  else
    print -r -- "$message"
  fi
}
# 业务开始前打印内置自述并等待回车，EOF 与非空输入取消。
show_script_intro_and_wait() {
  if (( PRIVATE_ONLY )); then
    intro_line title '提取Flutter项目工程私库依赖'
    intro_line body '私库模式：Git、path 和自建 Pub 源，含间接私库；不复制公共 Pub 包。'
  else
    intro_line title '提取 Flutter 第三方依赖'
  fi
  intro_line body '1、复制实际解析的 Pub 直接、间接、开发依赖及插件包内平台源码。'
  intro_line body '2、只读源项目与缓存；输出独立目录、依赖清单和许可证，不自动 pub get。'
  intro_line body '3、目标可输入或拖入，直接回车使用系统桌面；Ctrl+C 随时取消。'
  intro_line body '4、日志在确认后创建于系统临时目录；缺失或损坏的 Dart 需自行修复。'
  local answer=""
  IFS= read -r 'answer?已了解用途与范围，按回车继续；非空取消：' || exit 0
  [[ -z "$answer" ]] || exit 0
}
# 初始化日志、定位同目录引擎；环境变更仅作用于本进程。
initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  umask 077
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
  SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
  LOG_FILE="$(/usr/bin/mktemp "${TMPDIR:-/tmp/}JobsFlutterDependencyExtractor.XXXXXX")" || exit 1
  [[ -f "$SCRIPT_DIR/ExtractFlutterDependencies.dart" ]] || die '缺少同目录 ExtractFlutterDependencies.dart，请保留完整脚本包。'
  log "日志：$LOG_FILE"
}
# 同步打印并保存纯文本业务记录。
log() {
  print -r -- "$1" | /usr/bin/tee -a "$LOG_FILE"
}
# 输出可定位的错误并终止。
die() {
  log "✖ $1"
  exit 1
}
# 将普通路径和 Terminal 拖入的 Shell 单词还原为数据，绝不 eval。
normalize_path_input() {
  local raw="$1" candidate="" word=""
  local -a words=()
  raw="${raw%$'\r'}"
  if [[ -e "$raw" ]]; then
    REPLY="$raw"
    return 0
  fi
  if [[ "$raw" != *\\* && "$raw" != \"* && "$raw" != \'* ]]; then
    candidate="$raw"
    [[ "$candidate" == '~' ]] && candidate="$HOME"
    [[ "$candidate" == '~/'* ]] && candidate="$HOME/${candidate#\~/}"
    [[ -n "$candidate" ]] || die '请输入或拖入一个目录。'
    REPLY="$candidate"
    return 0
  fi
  # zsh 的 z/Q 只做词法解析及去引号，不执行变量、替换或重定向。
  words=("${(@z)raw}")
  for word in "${words[@]}"; do
    candidate="${(Q)word}"
    [[ -n "$candidate" ]] || continue
    [[ "${#words}" == 1 ]] || die '一次只接受一个目录，请重新运行。'
  done
  [[ "${#words}" == 1 ]] || die '请输入或拖入一个目录。'
  [[ "$candidate" == '~' ]] && candidate="$HOME"
  [[ "$candidate" == '~/'* ]] && candidate="$HOME/${candidate#\~/}"
  [[ "$candidate" != *$'\n'* && "$candidate" != *$'\r'* ]] || die '交互路径不能含换行；请使用命令参数。'
  REPLY="$candidate"
}
# Finder 已带入项目时直接使用参数，桌面入口则要求输入或拖入。
read_project_and_destination() {
  local input="" desktop=""
  (( $# <= 1 )) || die '用法：脚本 [Flutter项目目录]'
  if (( $# == 1 )); then
    PROJECT_PATH="$1"
  else
    IFS= read -r 'input?输入或拖入 Flutter 项目文件夹：' || exit 0
    normalize_path_input "$input"
    PROJECT_PATH="$REPLY"
  fi
  [[ -d "$PROJECT_PATH" && ! -L "$PROJECT_PATH" ]] || die '项目必须是存在的普通文件夹。'
  PROJECT_PATH="${PROJECT_PATH:A}"
  [[ -f "$PROJECT_PATH/pubspec.yaml" && ! -L "$PROJECT_PATH/pubspec.yaml" ]] || die '所选目录同层缺少普通 pubspec.yaml。'
  desktop="$(/usr/bin/osascript -e 'POSIX path of (path to desktop folder)' 2>/dev/null)" || desktop=""
  [[ -n "$desktop" ]] || desktop="$HOME/Desktop"
  IFS= read -r "input?输入或拖入输出父目录（直接回车：${desktop}）：" || exit 0
  if [[ -z "$input" ]]; then
    DESTINATION_PATH="$desktop"
  else
    normalize_path_input "$input"
    DESTINATION_PATH="$REPLY"
  fi
}
# 只复用 Flutter 自带的原生 Dart，不执行会隐式下载的 FVM / Flutter shim。
check_environment() {
  local candidate="$PROJECT_PATH/.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart"
  [[ -x "$candidate" ]] || die '项目 FVM Dart 缺失；不会回退全局 SDK。'
  /usr/bin/file -b "${candidate:A}" | /usr/bin/grep -q 'Mach-O' || die '项目 FVM Dart 不是原生二进制；请修复项目 SDK。'
  "$candidate" --version </dev/null >/dev/null 2>&1 || die '项目 FVM Dart 不健康。'
  DART_EXECUTABLE="$candidate"
  log "✔ 项目 FVM Dart：$DART_EXECUTABLE"
}

# 参数逐项传给 Dart；管道保留引擎失败码，不把部分复制误报为成功。
run_extraction() {
  local extraction_result=0
  log "来源项目：$PROJECT_PATH"
  log "输出父目录：$DESTINATION_PATH"
  "$DART_EXECUTABLE" "$SCRIPT_DIR/ExtractFlutterDependencies.dart" \
    --project "$PROJECT_PATH" \
    --destination "$DESTINATION_PATH" "${SCOPE_ARGS[@]}" 2>&1 | /usr/bin/tee -a "$LOG_FILE"
  extraction_result=$?
  if (( extraction_result != 0 )); then
    log "✖ 未完成，退出码 $extraction_result；日志：$LOG_FILE"
    exit "$extraction_result"
  fi
  log "✔ 完成。日志：$LOG_FILE"
}
# 自述确认后才创建日志并访问业务路径。
main() {
  show_script_intro_and_wait # 展示范围并等待回车，避免双击误触。
  initialize_runtime # 初始化私有日志与同目录引擎路径。
  read_project_and_destination "$@" # 读取项目和可拖入目标，空目标默认桌面。
  check_environment # 体检已有原生 Dart，不隐式下载或修改配置。
  run_extraction # 执行本地快照并保留失败码。
}

main "$@"
