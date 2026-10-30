#!/bin/zsh
# 脚本自述：
# - 脚本名称：导入 Flutter 第三方依赖。
# - 核心用途：验证工具导出的完整依赖快照，再为当前项目导入本地依赖。
# - 影响范围：仅写当前项目的依赖副本、覆盖声明及备份；不运行 pub get 或下载工具。
# - 运行提示：项目及快照支持输入或拖入；校验通过后输入 YES 才写入，Ctrl+C 取消。

PRIVATE_ONLY=0
typeset -a SCOPE_ARGS=()
if [[ "${1:-}" == --private-only ]]; then
  PRIVATE_ONLY=1
  SCOPE_ARGS=(--private-only)
  shift
fi
SCRIPT_DIR=""
LOG_FILE=""
PROJECT_PATH=""
SOURCE_PATH=""
DART_EXECUTABLE=""
# 根据终端能力显示自述，重定向时不输出颜色控制符。
intro_line() {
  local role="$1" message="$2" code="0;34"
  [[ "$role" == title ]] && code="1;31"
  if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" ]]; then
    printf '\033[%sm%s\033[0m\n' "$code" "$message"
  else
    print -r -- "$message"
  fi
}
# 确认用途后才访问业务路径或创建日志。
show_script_intro_and_wait() {
  if (( PRIVATE_ONLY )); then
    intro_line title '导入Flutter项目工程私库依赖'
    intro_line body '私库模式：Git、path 和自建 Pub 源，含间接私库；不复制公共 Pub 包。'
  else
    intro_line title '导入 Flutter 第三方依赖'
  fi
  intro_line body '1、输入或拖入“提取Flutter第三方依赖”生成的完整目录，不能只选 packages 子目录。'
  intro_line body '2、先核对清单、包名、版本及源码完整性；通过后显示来源、目标和写入计划。'
  intro_line body '3、精确输入 YES 才导入本地依赖并更新覆盖声明；保留原配置备份，不自动 pub get。'
  intro_line body '4、只使用项目 FVM 的原生 Dart；Ctrl+C 或输入结束取消，日志在确认后创建于系统临时目录。'
  local answer=""
  IFS= read -r 'answer?已了解用途与范围，按回车继续；非空取消：' || exit 0
  [[ -z "$answer" ]] || exit 0
}
# 初始化独立日志并检查随包引擎是否完整。
initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  umask 077
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
  LOG_FILE="$(/usr/bin/mktemp "${TMPDIR:-/tmp/}JobsFlutterDependencyImporter.XXXXXX")" || exit 1
  log "日志：$LOG_FILE"
  [[ -f "$SCRIPT_DIR/ImportFlutterDependencies.dart" && -f "$SCRIPT_DIR/ExtractFlutterDependencies.dart" ]] || die '缺少同目录依赖引擎，请保留完整脚本包。'
}
# 同步显示及保存纯文本记录。
log() {
  print -r -- "$1" | /usr/bin/tee -a "$LOG_FILE"
}
# 显示可定位错误并终止。
die() {
  log "✖ $1"
  exit 1
}
# 去掉输入外侧粘贴产生的空白；路径内部空格保持原样。
trim_path_input_boundaries() {
  local whitespace=$' \t\r\n\u00a0\u202f' preceding="" escaped=0
  REPLY="$1"
  while [[ -n "$REPLY" && "$whitespace" == *"${REPLY[1]}"* ]]; do
    REPLY="${REPLY[2,-1]}"
  done
  while [[ -n "$REPLY" && "$whitespace" == *"${REPLY[-1]}"* ]]; do
    preceding="${REPLY[1,-2]}"
    escaped=0
    while [[ "$preceding" == *$'\\' ]]; do
      escaped=$((1 - escaped))
      preceding="${preceding[1,-2]}"
    done
    # 拖入时转义的末尾空白属于真实文件名，不能当作输入装饰裁掉。
    (( escaped )) && break
    REPLY="${REPLY[1,-2]}"
  done
}
# 优先保留真实存在的原路径，再兼容拖入转义及外侧不可见空白，绝不 eval。
normalize_path_input() {
  local raw="${1%$'\r'}" candidate="" variant="" fallback="" parsed=0
  local -a words=() variants=("$raw")
  trim_path_input_boundaries "$raw"
  [[ "$REPLY" == "$raw" ]] || variants+=("$REPLY")
  for variant in "${variants[@]}"; do
    [[ -n "$variant" ]] || continue
    if [[ -e "$variant" ]]; then
      REPLY="$variant"
      return 0
    fi
    if [[ "$variant" != *\\* && "$variant" != \"* && "$variant" != \'* ]]; then
      candidate="$variant"
    else
      words=("${(@z)variant}")
      (( ${#words} == 1 )) || continue
      candidate="${(Q)words[1]}"
    fi
    parsed=1
    [[ -n "$candidate" ]] || continue
    [[ "$candidate" == '~' ]] && candidate="$HOME"
    [[ "$candidate" == '~/'* ]] && candidate="$HOME/${candidate#\~/}"
    [[ "$candidate" != *$'\n'* && "$candidate" != *$'\r'* ]] || die '目录输入不能包含换行。'
    fallback="$candidate"
    if [[ -e "$candidate" ]]; then
      REPLY="$candidate"
      return 0
    fi
  done
  (( parsed )) || die '一次只接受一个目录。'
  [[ -n "$fallback" ]] || die '请输入或拖入一个目录。'
  REPLY="$fallback"
}
# Finder 带入项目；独立运行时同时接受手输或拖入项目及快照。
read_project_and_source() {
  local input=""
  (( $# <= 1 )) || die '用法：ImportFlutterDependencies.zsh [Flutter项目目录]'
  if (( $# == 1 )); then
    PROJECT_PATH="$1"
  else
    IFS= read -r 'input?输入或拖入目标 Flutter 项目文件夹：' || exit 0
    [[ -n "$input" ]] || exit 0
    normalize_path_input "$input"
    PROJECT_PATH="$REPLY"
  fi
  [[ -d "$PROJECT_PATH" && ! -L "$PROJECT_PATH" ]] || die '项目必须是存在的普通文件夹。'
  [[ -f "$PROJECT_PATH/pubspec.yaml" && ! -L "$PROJECT_PATH/pubspec.yaml" ]] || die '项目同层缺少普通 pubspec.yaml。'
  PROJECT_PATH="${PROJECT_PATH:A}"
  while true; do
    IFS= read -r 'input?输入或拖入已导出的依赖目录（空回车重新输入）：' || exit 0
    trim_path_input_boundaries "$input"
    if [[ -z "$REPLY" ]]; then
      log '尚未输入依赖目录，请继续输入或拖入；Ctrl+C 可取消。'
      continue
    fi
    normalize_path_input "$input"
    SOURCE_PATH="$REPLY"
    if [[ -d "$SOURCE_PATH" && ! -L "$SOURCE_PATH" && -f "$SOURCE_PATH/manifest.json" && ! -L "$SOURCE_PATH/manifest.json" && -d "$SOURCE_PATH/packages" && ! -L "$SOURCE_PATH/packages" ]]; then
      SOURCE_PATH="${SOURCE_PATH:A}"
      return 0
    fi
    log '✖ 不是依赖导出目录：需要同层 manifest.json 和 packages/；请重新选择完整快照。'
  done
}
# 复用项目原生 Dart，避免 shim 隐式安装或全局 SDK 回退。
check_environment() {
  local candidate="$PROJECT_PATH/.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart"
  [[ -x "$candidate" ]] || die '项目 FVM Dart 缺失；请先安装/切换项目 SDK。'
  /usr/bin/file -b "${candidate:A}" | /usr/bin/grep -q 'Mach-O' || die '项目 FVM Dart 不是原生二进制。'
  "$candidate" --version </dev/null >/dev/null 2>&1 || die '项目 FVM Dart 不健康。'
  DART_EXECUTABLE="$candidate"
  log "✔ 项目 FVM Dart：$DART_EXECUTABLE"
}
# 完整验证失败时保持原失败码，阻止确认和写入。
validate_import() {
  local validation_result=0
  log "来源快照：$SOURCE_PATH"
  log "目标项目：$PROJECT_PATH"
  "$DART_EXECUTABLE" "$SCRIPT_DIR/ImportFlutterDependencies.dart" \
    --project "$PROJECT_PATH" \
    --source "$SOURCE_PATH" "${SCOPE_ARGS[@]}" \
    --validate-only 2>&1 | /usr/bin/tee -a "$LOG_FILE"
  validation_result=$?
  (( validation_result == 0 )) || exit "$validation_result"
}
# 计划经过确认后重新校验并执行导入，取消不写入项目。
confirm_and_import() {
  local answer="" import_result=0
  IFS= read -r 'answer?校验通过，输入 YES 执行以上导入；其它输入取消：' || exit 0
  if [[ "$answer" != YES ]]; then
    log '已取消，项目未写入。'
    return 0
  fi
  "$DART_EXECUTABLE" "$SCRIPT_DIR/ImportFlutterDependencies.dart" \
    --project "$PROJECT_PATH" \
    --source "$SOURCE_PATH" "${SCOPE_ARGS[@]}" 2>&1 | /usr/bin/tee -a "$LOG_FILE"
  import_result=$?
  if (( import_result != 0 )); then
    log "✖ 导入未完成，退出码 $import_result；日志：$LOG_FILE"
    exit "$import_result"
  fi
  log "✔ 导入完成；日志：$LOG_FILE"
}
# 编排用途说明、路径识别、完整校验与确认写入。
main() {
  show_script_intro_and_wait # 先说明用途并防止误触。
  initialize_runtime # 确认后才创建私有日志。
  read_project_and_source "$@" # 支持 Finder 项目参数和终端拖入快照。
  check_environment # 只使用已有的健康项目 Dart。
  validate_import # 完整识别依赖特征并打印写入计划。
  confirm_and_import # 用户确认后执行引擎的二次校验和导入。
}

main "$@"
