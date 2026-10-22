#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】🐦Flutter项目体检.command
# - 核心用途：默认检查 Flutter 开发环境，也可显式选择 pub-get 或 clean-get。
# - 影响范围：doctor 只请求诊断（SDK 自身可能准备缓存）；pub-get 写入依赖；clean-get 还会清理缓存。
# - 运行提示：终端回车确认；Sourcetree 连续执行；--help / --check 只读且无等待。
# shell: zsh

readonly SCRIPT_SOURCE="$0"
SCRIPT_PATH=""
SCRIPT_DIR=""
SCRIPT_BASENAME=""
LOG_FILE=""
LOG_READY=0
IS_SOURCETREE_RUNTIME=0
PLAIN_OUTPUT=0
READ_ONLY_MODE=""
PARSE_ERROR=""
FLUTTER_ROOT=""
ACTION="doctor"
typeset -a POSITIONAL_ARGS=() FLUTTER_CMD=() DART_CMD=()

# Sourcetree 的参数环境和父进程可证明入口身份，非 TTY 本身不构成身份。
is_sourcetree_runtime() {
  env | grep -Eqi '^(SOURCETREE|SOURCE_TREE)' && return 0
  local parent_pid="$PPID" command_name="" guard=0
  while [[ -n "$parent_pid" && "$parent_pid" != 0 && "$guard" -lt 8 ]]; do
    command_name="$(ps -o comm= -p "$parent_pid" 2>/dev/null)"
    [[ "$command_name" == *SourceTree* || "$command_name" == *Sourcetree* ]] && return 0
    parent_pid="$(ps -o ppid= -p "$parent_pid" 2>/dev/null | tr -d ' ')"
    guard=$((guard + 1))
  done
  return 1
}
# 使用真实源码位置；兼容 Sourcetree 只给脚本文件名的入口。
resolve_script_path() {
  local candidate="" script_name="${SCRIPT_SOURCE:t}"
  for candidate in "$SCRIPT_SOURCE" "$PWD/$SCRIPT_SOURCE" \
    "$HOME/SourceTree.command/$script_name/$script_name" \
    "$HOME/Documents/Github/JobsGenesis/SourceTree.command/$script_name/$script_name"; do
    if [[ -f "$candidate" ]]; then
      print -r -- "${candidate:A}"
      return 0
    fi
  done
  print -r -- "$PWD/$script_name"
}
# 第一屏自述前设置纯文本上下文，外部命令也复用同一过滤器。
prepare_plain_output_context() {
  if [[ "$IS_SOURCETREE_RUNTIME" == 1 || ! -t 1 || -z "${TERM:-}" || "${TERM:-}" == dumb || -n "${NO_COLOR+x}" || "${JOBS_PLAIN_OUTPUT:-0}" == 1 ]]; then
    PLAIN_OUTPUT=1
    export NO_COLOR=1 FORCE_COLOR=0 CLICOLOR=0 ANSI_COLORS_DISABLED=1 npm_config_color=false
  fi
}
# 过滤脚本与外部工具的 ANSI 控制码。
strip_ansi_text() {
  /usr/bin/perl -pe 's/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/\e\][^\a]*(?:\a|\e\\)//g'
}
# 按字面文字同步输出终端和确认后的日志。
log() {
  if [[ "$LOG_READY" == 1 ]]; then
    printf '%s\n' "$1" | strip_ansi_text | tee -a "$LOG_FILE"
  else
    printf '%s\n' "$1" | strip_ansi_text
  fi
}
# 输出当前步骤或环境信息。
info_echo() { log "ℹ $1"; }
# 输出已验证完成的步骤。
success_echo() { log "✔ $1"; }
# 输出需要用户注意的条件。
warn_echo() { log "⚠ $1"; }
# 输出失败原因。
error_echo() { log "✖ $1"; }
# 输出路径和计划等次要信息。
gray_echo() { log "$1"; }
# 自述采用红色粗体标题和蓝色常规正文，受限输出降级纯文本。
intro_line() {
  local role="$1" message="$2" color='\033[0;34m'
  [[ "$role" == title ]] && color='\033[1;31m'
  if [[ "$PLAIN_OUTPUT" == 1 ]]; then
    print -r -- "$message"
  else
    printf '%b%s%b\n' "$color" "$message" '\033[0m'
  fi
}
# 只读选项可位于路径前后；其余参数仍按原入口顺序解释。
parse_script_arguments() {
  local argument="" literal=0
  for argument in "$@"; do
    if [[ "$literal" == 1 ]]; then
      POSITIONAL_ARGS+=("$argument")
      continue
    fi
    case "$argument" in
      --) literal=1 ;;
      --help|-h) READ_ONLY_MODE=help ;;
      --check) [[ "$READ_ONLY_MODE" == help ]] || READ_ONLY_MODE=check ;;
      -*) PARSE_ERROR="未知参数：$argument" ;;
      *) POSITIONAL_ARGS+=("$argument") ;;
    esac
  done
}
# 确认前只解析参数与展示说明，不创建日志、不调用 SDK。
show_script_intro_and_wait() {
  setopt NO_NOMATCH PIPE_FAIL
  SCRIPT_PATH="$(resolve_script_path)"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
  LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.log"
  is_sourcetree_runtime && IS_SOURCETREE_RUNTIME=1
  prepare_plain_output_context
  parse_script_arguments "$@"
  intro_line title "================ 脚本内置自述 ================"
  intro_line title "脚本名称：${SCRIPT_BASENAME}.command"
  intro_line body "1、用途：默认检查 Flutter 开发环境，也可显式选择 pub-get 或 clean-get。"
  intro_line body "2、影响：doctor 只请求诊断（SDK 自身可能准备缓存）；pub-get 写入依赖；clean-get 还会清理缓存。"
  intro_line body "3、策略：Sourcetree 连续执行；独立终端回车确认；Ctrl+C 取消。"
  intro_line body "4、只读：--help 查看参数；--check 检查路径、SDK 和计划，不调用 SDK、不写日志。"
  intro_line body "日志位置：$LOG_FILE"
  intro_line title "=============================================="
  if [[ -n "$READ_ONLY_MODE" ]]; then
    return 0
  fi
  [[ -z "$PARSE_ERROR" ]] || return 0
  if [[ "$IS_SOURCETREE_RUNTIME" == 1 ]]; then
    gray_echo '已识别为 Sourcetree 动作，无交互连续执行。'
  elif [[ ! -t 0 ]]; then
    error_echo '当前不是 Sourcetree 且没有可交互输入；请在终端运行，或使用 --check。'
    exit 1
  else
    IFS= read -r '?已了解用途与影响，按回车继续；Ctrl+C 取消：' _ || exit 1
  fi
}
# 保留用户 PATH 的选路优先级，仅在当前进程补齐常用工具目录。
initialize_script_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  export PATH="${PATH:-}:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.pub-cache/bin:$HOME/.fvm/bin:/opt/homebrew/bin:/usr/local/bin"
  prepare_plain_output_context
  if [[ -z "$READ_ONLY_MODE" && -z "$PARSE_ERROR" ]]; then
    : > "$LOG_FILE" || { print -r -- "日志不可写：$LOG_FILE" >&2; exit 1; }
    LOG_READY=1
  fi
}
# 先保留真实存在的路径，避免破坏文件名内合法引号和反斜杠。
normalize_flutter_input() {
  local input_value="$1"
  if [[ -e "$input_value" ]]; then
    print -r -- "$input_value"
    return 0
  fi
  input_value="${input_value%$'\r'}"
  input_value="${input_value%$'\n'}"
  if [[ "$input_value" == \"*\" || "$input_value" == \'*\' ]]; then
    input_value="${input_value[2,-2]}"
  fi
  [[ "$input_value" == '~/'* ]] && input_value="$HOME/${input_value#\~/}"
  [[ -e "$input_value" ]] || input_value="${(Q)input_value}"
  print -r -- "$input_value"
}
# 保守解析常用块映射和单行 flow 映射，不执行 YAML 标签、锚点或外部代码。
pubspec_query() {
  /usr/bin/perl - "$FLUTTER_ROOT/pubspec.yaml" "$1" "${2:-}" <<'PERL'
use strict;
use warnings;
my ($file, $mode, $wanted) = @ARGV;
open my $fh, '<:raw', $file or exit 2;
local $/; my $text = <$fh>; close $fh;
exit 2 if length($text) > 1048576 || $text =~ /\0/;
$text =~ s/^\xEF\xBB\xBF//;
$text =~ s/\r\n/\n/g;
sub trim { my $s = shift; $s =~ s/^\s+|\s+$//g; return $s; }
# 只接受引号和 flow 容器外的分隔符。
sub delimiter {
  my ($source, $wanted, $comments) = @_;
  my ($quote, $depth, $escaped) = ('', 0, 0);
  for (my $i = 0; $i < length($source); $i++) {
    my $c = substr($source, $i, 1);
    if ($quote ne '') {
      if ($quote eq '"' && $c eq '\\' && !$escaped) { $escaped = 1; next; }
      if ($c eq $quote && !$escaped) {
        if ($quote eq "'" && substr($source, $i + 1, 1) eq "'") { $i++; next; }
        $quote = '';
      }
      $escaped = 0;
    } elsif ($c eq '"' || $c eq "'") { $quote = $c; }
    elsif ($c eq $wanted && $depth == 0) {
      return $i if !$comments || !$i || substr($source, $i - 1, 1) =~ /\s/;
    } elsif ($c eq '{' || $c eq '[') { $depth++; }
    elsif ($c eq '}' || $c eq ']') { $depth--; }
  }
  return -1;
}
sub yaml_scalar {
  my $s = trim(shift);
  return undef unless length $s;
  if ($s =~ /^'((?:[^']|'')*)'$/s) { $s = $1; $s =~ s/''/'/g; return $s; }
  if ($s =~ /^"([^"\\]*)"$/s) { return $1; }
  return undef if $s =~ /[{}\[\],:#&*!|>"']/;
  return $s;
}
sub pair {
  my $s = shift;
  my $hash = delimiter($s, '#', 1);
  $s = substr($s, 0, $hash) if $hash >= 0;
  my $colon = delimiter($s, ':', 0);
  return () if $colon < 0;
  my $key = yaml_scalar(substr($s, 0, $colon));
  return () unless defined($key) && length($key);
  return ($key, trim(substr($s, $colon + 1)));
}
sub flow {
  my $s = trim(shift);
  die "unsupported flow" unless $s =~ /^\{(.*)\}$/s;
  my $rest = trim($1); my %result;
  while (length $rest) {
    my $comma = delimiter($rest, ',', 0);
    my $part = $comma >= 0 ? substr($rest, 0, $comma) : $rest;
    my ($key, $value) = pair($part);
    die "invalid flow" unless defined($key) && length($value) && !exists($result{$key});
    $result{$key} = $value =~ /^\{/ ? flow($value) : yaml_scalar($value);
    $rest = $comma >= 0 ? trim(substr($rest, $comma + 1)) : '';
  }
  return \%result;
}
my @entries;
for my $line (split /\n/, $text) {
  next if $line =~ /^\s*(?:#.*)?$/;
  exit 2 if $line =~ /^\s*(?:---|\.\.\.)\s*$/ || $line =~ /^ *\t/;
  my ($spaces) = $line =~ /^( *)/;
  my ($key, $value) = pair(substr($line, length($spaces)));
  push @entries, [length($spaces), $key, $value];
}
sub block {
  my ($index, $depth) = @_;
  my %result;
  while ($$index < @entries && $entries[$$index][0] == $depth) {
    my ($indent, $key, $value) = @{$entries[$$index]};
    $$index++;
    my $node;
    if (defined($key)) {
      die "duplicate mapping" if exists($result{$key});
      if (!length($value) && $$index < @entries && $entries[$$index][0] > $depth) {
        $node = block($index, $entries[$$index][0]);
      } elsif ($value =~ /^\{/) { $node = flow($value); }
      else { $node = yaml_scalar($value); }
      $result{$key} = $node;
    }
    # description 块字符串或其它不支持正文中的伪键不能抬升到根层。
    $$index++ while $$index < @entries && $entries[$$index][0] > $depth;
  }
  return \%result;
}
my ($root, $index) = (undef, 0);
eval { die "no root mapping" unless @entries && $entries[0][0] == 0; $root = block(\$index, 0); };
exit 2 if $@ || $index != @entries;
sub mapping { return ref($_[0]) eq 'HASH'; }
my $ok = 0;
if ($mode eq 'flutter') {
  my $deps = $root->{dependencies};
  $ok = mapping($deps) && mapping($deps->{flutter}) && defined($deps->{flutter}{sdk}) && !ref($deps->{flutter}{sdk}) && $deps->{flutter}{sdk} eq 'flutter';
} elsif ($mode eq 'dependency') {
  for my $section ('dependencies', 'dev_dependencies') {
    my $deps = $root->{$section};
    $ok = 1 if mapping($deps) && exists($deps->{$wanted});
  }
} elsif ($mode eq 'config') {
  $ok = mapping($root->{$wanted});
} elsif ($mode eq 'generate') {
  $ok = mapping($root->{flutter}) && defined($root->{flutter}{generate}) && !ref($root->{flutter}{generate}) && $root->{flutter}{generate} eq 'true';
}
exit($ok ? 0 : 1);
PERL
}
# 只查询依赖分区的直属包声明。
pubspec_has_dependency() {
  pubspec_query dependency "$1"
}
# Flutter 工程需声明 flutter 依赖，避免误选普通 Dart 包。
is_flutter_project() {
  local previous_root="$FLUTTER_ROOT" result=1
  FLUTTER_ROOT="$1"
  if [[ -f "$1/pubspec.yaml"  ]] && pubspec_query flutter; then
    result=0
  fi
  FLUTTER_ROOT="$previous_root"
  return "$result"
}
# 就近向上查找；向下扫描只接受唯一工程，跳过依赖、供应商和缓存。
resolve_flutter_project() {
  local base="$(normalize_flutter_input "${1:-${PROJECT_DIR:-${REPO:-$PWD}}}")"
  local current="" candidate="" found_specs=""
  local -a candidates=()
  [[ -f "$base" ]] && base="${base:h}"
  [[ -d "$base" ]] || { error_echo "工程路径不存在：$base"; return 1; }
  base="${base:A}"
  [[ "$base" != / && "$base" != "${HOME:A}" ]] || { error_echo '请指定工程目录，不扫描根目录或整个用户目录。'; return 1; }
  current="$base"
  while [[ "$current" != / ]]; do
    if is_flutter_project "$current"; then
      FLUTTER_ROOT="$current"
      return 0
    fi
    current="${current:h}"
  done
  found_specs="$(find "$base" \( -type d \( -name .git -o -name node_modules -o -name Pods -o -name PodsManual -o -name 'ManualBy*Pods*' -o -name .dart_tool -o -name .fvm -o -name build -o -name DerivedData -o -name .import_backup -o -name vendor -o -name third_party -o -name ThirdParty \) -prune \) -o \( -type f -name pubspec.yaml -print0 \))" || { error_echo "扫描工程失败：$base"; return 1; }
  for candidate in "${(@0)found_specs}"; do
    [[ -n "$candidate" ]] || continue
    is_flutter_project "${candidate:h}" && candidates+=("${candidate:h}")
  done
  if (( ${#candidates[@]} != 1 )); then
    error_echo "需要唯一 Flutter 工程，当前候选数量：${#candidates[@]}；pubspec 应声明 dependencies.flutter.sdk: flutter（支持常见块 / 单行 flow 映射）。"
    for candidate in "${candidates[@]}"; do
      gray_echo "候选：$candidate"
    done
    return 1
  fi
  FLUTTER_ROOT="${candidates[1]}"
}
# 固定版本工程缺少 SDK 时停止，避免隐式安装或悄悄切换全局版本。
choose_project_flutter() {
  local flutter_executable=""
  cd "$FLUTTER_ROOT" || return 1
  if [[ -x "$FLUTTER_ROOT/.fvm/flutter_sdk/bin/flutter" ]]; then
    flutter_executable="$FLUTTER_ROOT/.fvm/flutter_sdk/bin/flutter"
  elif [[ -f .fvmrc || -f .fvm/fvm_config.json || -e .fvm/flutter_sdk || -L .fvm/flutter_sdk ]]; then
    error_echo '工程固定的 FVM SDK 不可用；请先在工程中完成 fvm install / fvm use，再重试。'
    return 1
  elif command -v flutter >/dev/null 2>&1; then
    flutter_executable="${commands[flutter]:A}"
  else
    error_echo '没有可用 Flutter SDK；请检查当前 PATH 或项目 FVM 配置。'
    return 1
  fi
  FLUTTER_CMD=("$flutter_executable")
  DART_CMD=("${flutter_executable:h}/dart")
  info_echo "工程目录：$FLUTTER_ROOT"
  info_echo "Flutter 命令：${(q)FLUTTER_CMD[1]}"
}
# 在原始命令和日志管道之间保留退出码；命令失败优先返回其原码。
run_flutter_step() {
  local title="$1" result=0 code=0
  local -a step_codes=()
  shift
  info_echo "开始：$title"
  "$@" 2>&1 | strip_ansi_text | tee -a "$LOG_FILE"
  step_codes=("${pipestatus[@]}")
  for code in "${step_codes[@]}"; do
    if (( code != 0 )); then
      result="$code"
      break
    fi
  done
  if (( result != 0 )); then
    error_echo "$title 失败，退出码：$result；后续步骤已停止。"
    return "$result"
  fi
  success_echo "完成：$title"
}
# 高风险选项只在真实终端承接，并要求精确 YES；无交互入口不能绕过。
confirm_risky_options() {
  local message="$1" answer=""
  warn_echo "$message"
  if [[ "$IS_SOURCETREE_RUNTIME" == 1 || ! -t 0 || ! -t 1 ]]; then
    error_echo '该选项需要可交互终端和精确 YES 确认；请在终端独立运行。'
    return 1
  fi
  IFS= read -r '?输入精确大写 YES 继续，其它输入取消：' answer || return 1
  [[ "$answer" == YES ]] || { error_echo '已取消危险选项。'; return 1; }
}
# 说明参数、默认行为及只读入口。
show_usage() {
  print -r -- '用法：脚本 [--check|--help] [Flutter 工程路径] [doctor|pub-get|clean-get]'
  print -r -- '默认 doctor：flutter doctor -v，诊断有警告或错误时返回非零。'
  print -r -- 'pub-get：显式拉取依赖；clean-get：终端精确 YES 后清理并拉取依赖。'
  print -r -- '--check：只显示工程、SDK 和命令计划；--help：显示参数。'
}
# Flutter doctor 可能在发现环境问题时返回 0，需同时检查诊断结论。
run_flutter_doctor() {
  run_flutter_step 'flutter doctor -v' "${FLUTTER_CMD[@]}" doctor -v || return $?
  if grep -Eq '^[[:space:]]*\[(!|✗|✘|x|X)\]|Doctor found issues in|Doctor summary.*issues' "$LOG_FILE"; then
    warn_echo 'Flutter doctor 报告环境警告或错误；诊断未通过，请按上方输出处理。'
    return 1
  fi
  success_echo 'Flutter doctor 未报告环境警告或错误。'
}
# 定位工程并顺序执行显式选择的业务。
run_original_logic() {
  (( $# <= 2 )) || { show_usage; return 2; }
  ACTION="${2:-doctor}"
  case "$ACTION" in
    doctor|pub-get|clean-get) ;;
    *) error_echo "未知动作：$ACTION"; show_usage; return 2 ;;
  esac
  resolve_flutter_project "${1:-}" || return $?
  choose_project_flutter || return $?
  case "$ACTION" in
    doctor) gray_echo '计划：flutter doctor -v' ;;
    pub-get) gray_echo '计划：flutter pub get' ;;
    clean-get) gray_echo '计划：flutter clean → flutter pub get（终端 YES 确认）' ;;
  esac
  [[ "$READ_ONLY_MODE" == check ]] && return 0
  case "$ACTION" in
    doctor) run_flutter_doctor || return $? ;;
    pub-get) run_flutter_step 'flutter pub get' "${FLUTTER_CMD[@]}" pub get || return $? ;;
    clean-get)
      confirm_risky_options 'flutter clean 会清理当前工程构建和工具生成目录。' || return $?
      run_flutter_step 'flutter clean' "${FLUTTER_CMD[@]}" clean || return $?
      run_flutter_step 'flutter pub get' "${FLUTTER_CMD[@]}" pub get || return $?
      ;;
  esac
}
# 只读入口与真实业务在同一解析路径上运行，保留最终失败状态。
run_checked_business() {
  local result=0
  [[ -z "$PARSE_ERROR" ]] || { error_echo "$PARSE_ERROR"; exit 2; }
  if [[ "$READ_ONLY_MODE" == help ]]; then
    show_usage
    return 0
  fi
  if run_original_logic "${POSITIONAL_ARGS[@]}"; then
    if [[ "$READ_ONLY_MODE" == check ]]; then
      success_echo '只读检查完成；未调用 SDK、写日志或执行工程命令。'
    else
      success_echo "脚本执行结束。日志：$LOG_FILE"
    fi
  else
    result=$?
    error_echo "脚本执行失败，退出码：$result。"
    [[ "$LOG_READY" == 1 ]] && gray_echo "日志：$LOG_FILE"
    exit "$result"
  fi
}
# 按自述、初始化、业务顺序编排入口。
main() {
  show_script_intro_and_wait "$@" # 第一屏自述及终端防误触确认。
  initialize_script_runtime # 初始化当前进程和确认后日志。
  run_checked_business # 统一分派只读检查和真实业务。
}

main "$@"
