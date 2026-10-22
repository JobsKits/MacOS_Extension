#!/bin/zsh
# 脚本自述：
# - 脚本名称：CreateHarmonySimulator.zsh
# - 核心用途：通过华为官方 Emulator CLI，选择已下载 Release 镜像，新建并按需启动鸿蒙模拟器。
# - 影响范围：写入 DevEco 默认模拟器实例目录；保留已有设备、镜像、代理和系统配置。
# - 运行提示：先展示内置自述并回车确认；--check 只读，缺少本地镜像时停止，不下载或代答许可。

HS_BIN=""
HS_LOG=""
HS_CHECK=0
HS_HELP=0
HS_START=1
HS_NAME=""
HS_IMAGES=""
HS_INSTANCES=""
HS_TYPE=""
HS_VERSION=""
HS_OFFICIAL_URL="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-command-line"
typeset -a HS_NAMES=()
typeset -a HS_ROWS=()

hs_intro_line() {
  local role="$1" message="$2"
  if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" ]]; then
    if [[ "$role" == title ]]; then
      printf '\033[1;31m%s\033[0m\n' "$message"
    else
      printf '\033[0;34m%s\033[0m\n' "$message"
    fi
  else
    print -r -- "$message"
  fi
}
# 任何运行入口先展示固定说明，帮助和只读检查由后续流程直接分流。
hs_show_intro() {
  hs_intro_line title '━━━━━━━━━━ 新建鸿蒙模拟器 ━━━━━━━━━━'
  hs_intro_line body '1、仅支持 Apple Silicon macOS 与具备 -create / -imageList 的官方 DevEco Emulator（6.1.0 Beta1+）。'
  hs_intro_line body '2、选择已下载的 Release 镜像，新建唯一名称的实例；保留所有已有模拟器与镜像。'
  hs_intro_line body '3、不下载镜像、不自动接受许可、不改代理或 Shell 配置；启动保留官方许可交互。'
  hs_intro_line body '4、交互入口回车继续，Ctrl+C 取消；--check 只读查询，日志在系统临时目录 JobsHarmonySimulator.* 中。'
}

hs_help() {
  print -r -- '用法：CreateHarmonySimulator.zsh [--create] [--name 名称] [--no-start] [--check] [--help]'
  print -r -- '环境：HARMONY_EMULATOR_BIN 指定官方 Emulator；DEVECO_STUDIO_HOME / TOOL_HOME 指定 DevEco 或 CLT 根目录。'
  print -r -- '--check 仅查询 -help、-imageList -downloaded true、-list -details，不创建、启动或下载。'
  print -r -- "官方说明：$HS_OFFICIAL_URL"
}

hs_error() {
  print -u2 -r -- "✖ $*"
  [[ -z "$HS_LOG" ]] || print -r -- "✖ $*" >> "$HS_LOG"
  return 1
}

hs_log() {
  print -r -- "$*"
  [[ -z "$HS_LOG" ]] || print -r -- "$*" >> "$HS_LOG"
  return 0
}

hs_parse() {
  while (( $# )); do
    case "$1" in
      --help|-h) HS_HELP=1 ;;
      --check) HS_CHECK=1 ;;
      --create) ;;
      --no-start) HS_START=0 ;;
      --name)
        (( $# > 1 )) || { hs_error '--name 缺少名称。'; return 2; }
        HS_NAME="$2"
        shift
        ;;
      *) hs_error "未知参数：$1"; return 2 ;;
    esac
    shift
  done
  [[ -z "$HS_NAME" ]] || hs_valid_name "$HS_NAME" || { hs_error '名称不能以 - 开头、含路径分隔符或控制字符，最长 80 字符。'; return 2; }
}

hs_valid_name() {
  local value="$1"
  [[ -n "$value" && ${#value} -le 80 && "$value" != -* && "$value" != *'/'* && "$value" != *'\'* && "$value" != *[[:cntrl:]]* ]]
}

# 常用 macOS 卷不区分大小写，预检按更保守的名称规则保护既有实例。
hs_name_exists() {
  local requested="$1" existing=""
  shift
  for existing in "$@"; do
    [[ "${existing:l}" != "${requested:l}" ]] || return 0
  done
  return 1
}

hs_check_host() {
  [[ "$(/usr/bin/uname -s)" == Darwin ]] || { hs_error '本入口只支持 macOS。'; return 1; }
  if [[ "$(/usr/bin/uname -m)" != arm64 ]]; then
    if [[ "$(/usr/sbin/sysctl -n sysctl.proc_translated 2>/dev/null)" == 1 ]]; then
      hs_error '当前 Terminal 在 Rosetta 下运行；请关闭“使用 Rosetta 打开”，从 Apple Silicon 原生终端重新运行。'
    else
      hs_error '华为鸿蒙本地模拟器仅支持 Apple Silicon（arm64）；Intel Mac 不支持。'
    fi
    return 1
  fi
}

# 显式路径失败即停止，不能静默选到另一套 SDK 或 Android emulator。
hs_find_emulator() {
  local requested="${HARMONY_EMULATOR_BIN:-}" root="${DEVECO_STUDIO_HOME:-${TOOL_HOME:-}}" candidate=""
  local -a candidates=()
  if [[ -n "$requested" ]]; then
    [[ -f "$requested" && -x "$requested" ]] || { hs_error "指定 Emulator 不可执行：$requested"; return 1; }
    HS_BIN="${requested:A}"
    return 0
  fi
  if [[ -n "$root" ]]; then
    [[ -d "$root" ]] || { hs_error "指定 DevEco / CLT 目录不存在：$root"; return 1; }
    for candidate in "$root/Contents/tools/emulator/Emulator" "$root/tools/emulator/Emulator" "$root/emulator/Emulator"; do
      [[ ! -f "$candidate" || ! -x "$candidate" ]] || candidates+=("${candidate:A}")
    done
  else
    candidate="$(command -v Emulator 2>/dev/null)" || candidate=""
    [[ -z "$candidate" || ! -f "$candidate" || ! -x "$candidate" ]] || candidates+=("${candidate:A}")
    for candidate in /Applications/DevEco*.app/Contents/tools/emulator/Emulator(N) "$HOME"/Applications/DevEco*.app/Contents/tools/emulator/Emulator(N); do
      [[ ! -f "$candidate" || ! -x "$candidate" ]] || candidates+=("${candidate:A}")
    done
  fi
  candidates=("${(@u)candidates}")
  (( ${#candidates[@]} == 1 )) || {
    hs_error "找到 ${#candidates[@]} 个可用 Emulator；请用 HARMONY_EMULATOR_BIN 明确指定官方工具。"
    hs_log "请在 DevEco Studio Device Manager 准备工具；说明：$HS_OFFICIAL_URL"
    return 1
  }
  HS_BIN="${candidates[1]}"
}

hs_check_capabilities() {
  local help_text="" result=0
  help_text="$("$HS_BIN" -help 2>&1)" || result=$?
  (( result == 0 )) || { hs_error "Emulator -help 失败，退出码 $result：$help_text"; return "$result"; }
  print -r -- "$help_text" | /usr/bin/grep -Fqi -- '-create' &&
    print -r -- "$help_text" | /usr/bin/grep -Fqi -- '-imageList' || {
      hs_error '当前工具未同时提供 -create 与 -imageList；请准备 DevEco Studio 6.1.0 Beta1+，不能用 Android emulator 替代。'
      return 1
    }
}

# 只解析官方 JSON 字段，拒绝畸形、控制字符和混入的日志；输入从不作为代码执行。
hs_json() {
  (( ${#2} <= 100000 )) || { hs_error 'CLI JSON 超过 100 KB，请在 DevEco Device Manager 检查。'; return 1; }
  /usr/bin/osascript -l JavaScript - "$@" <<'JAVASCRIPT'
ObjC.import('Foundation');
function run(argv) {
  var mode = argv[0], records = JSON.parse(argv[1]);
  if (mode !== 'images' && records && !Array.isArray(records) && typeof records === 'object' && typeof records.name === 'string') records = [records];
  if (!Array.isArray(records)) throw new Error('Expected official JSON array for ' + mode);
  function text(value, field) {
    if (typeof value !== 'string' || !value || /[\u0000-\u001f\u007f-\u009f]/.test(value)) throw new Error('Invalid ' + field);
    return value;
  }
  var output = [], seen = Object.create(null);
  records.forEach(function(item) {
    if (!item || typeof item !== 'object' || Array.isArray(item)) throw new Error('Invalid record');
    var line;
    if (mode === 'images') {
      var type = text(item.deviceType, 'deviceType'), os = text(item.osVersion, 'osVersion');
      var software = text(item.SoftWareVersion, 'SoftWareVersion'), release = text(item.releaseType, 'releaseType');
      if (item.downloaded !== true && item.downloaded !== false && item.downloaded !== 'true' && item.downloaded !== 'false') throw new Error('Invalid downloaded');
      if (String(item.downloaded) !== 'true' || release.toLowerCase() !== 'release') return;
      if (!/^[A-Za-z][A-Za-z0-9_-]*$/.test(type)) throw new Error('Invalid deviceType');
      line = type + '\t' + os + '\t' + software;
    } else if (mode === 'names') {
      line = text(item.name, 'name');
    } else if (mode === 'verify') {
      var name = text(item.name, 'name');
      if (name !== argv[2]) return;
      if (text(item.deviceType, 'deviceType').toLowerCase() !== argv[3].toLowerCase()) throw new Error('Created deviceType differs');
      var flatVersion = item['os.osVersion'], nestedVersion = item.os && item.os.osVersion;
      if (flatVersion !== undefined && nestedVersion !== undefined && flatVersion !== nestedVersion) throw new Error('Conflicting os.osVersion representations');
      if (text(flatVersion !== undefined ? flatVersion : nestedVersion, 'os.osVersion') !== argv[4]) throw new Error('Created osVersion differs');
      line = name;
    } else throw new Error('Unknown mode');
    if (seen[line] && mode !== 'images') throw new Error('Duplicate instance name');
    if (!seen[line]) output.push(line);
    seen[line] = true;
  });
  if (mode === 'verify' && output.length !== 1) throw new Error('Created instance not uniquely listed');
  return output.join('\n');
}
JAVASCRIPT
}

hs_query_state() {
  local result=0 parsed=""
  HS_IMAGES="$("$HS_BIN" -imageList -downloaded true)" || result=$?
  (( result == 0 )) || { hs_error "Emulator -imageList 失败，退出码 $result。"; return "$result"; }
  parsed="$(hs_json images "$HS_IMAGES")" || { hs_error '镜像 JSON 无法按官方字段解析，未创建模拟器。'; return 1; }
  HS_ROWS=("${(@f)parsed}")
  [[ -n "$parsed" ]] || HS_ROWS=()
  result=0
  HS_INSTANCES="$("$HS_BIN" -list -details)" || result=$?
  (( result == 0 )) || { hs_error "Emulator -list -details 失败，退出码 $result。"; return "$result"; }
  parsed="$(hs_json names "$HS_INSTANCES")" || { hs_error '实例 JSON 无法按官方字段解析，停止以保护已有设备。'; return 1; }
  HS_NAMES=("${(@f)parsed}")
  [[ -n "$parsed" ]] || HS_NAMES=()
  hs_log "ℹ 已下载 Release 镜像：${#HS_ROWS[@]}；已有实例：${#HS_NAMES[@]}。"
}

hs_choose() {
  local prompt="$1" choice="" answer="" index=1 fzf=""
  shift
  local -a options=("$@")
  (( ${#options[@]} )) || return 1
  fzf="$(command -v fzf 2>/dev/null)" || fzf=""
  if [[ -n "$fzf" && -x "$fzf" ]] && "$fzf" --version >/dev/null 2>&1; then
    print -rl -- "${options[@]}" | /usr/bin/env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_OPTS_FILE -u FZF_DEFAULT_COMMAND \
      "$fzf" --no-multi --layout=reverse --height=14 --border --prompt="$prompt > " --header='回车选首项；Esc / Ctrl+C 取消'
    return $?
  fi
  print -u2 -r -- "$prompt（回车选 1；输入 q 取消）："
  for choice in "${options[@]}"; do
    print -u2 -r -- "$index、$choice"
    index=$((index + 1))
  done
  IFS= read -r answer || return 130
  [[ "$answer" != q && "$answer" != Q ]] || return 130
  [[ -n "$answer" ]] || answer=1
  [[ "$answer" == <-> ]] && (( answer >= 1 && answer <= ${#options[@]} )) || { hs_error '选择编号无效。'; return 2; }
  print -r -- "${options[$answer]}"
}

hs_select_image() {
  local row="" selected="" proposed="" answer="" suffix=1
  local -a types=() versions=()
  (( ${#HS_ROWS[@]} )) || {
    hs_error '没有已下载的 Release 镜像；请在 DevEco Studio → Tools → Device Manager → Local Emulator 下载匹配 Mac ARM 的镜像，再重新运行本入口。'
    hs_log "官方说明：$HS_OFFICIAL_URL"
    return 1
  }
  for row in "${HS_ROWS[@]}"; do types+=("${row%%$'\t'*}"); done
  types=("${(@ou)types}")
  HS_TYPE="$(hs_choose '设备类型' "${types[@]}")" || return $?
  (( ${types[(Ie)$HS_TYPE]} )) || { hs_error '选择器返回了无效设备类型。'; return 2; }
  for row in "${HS_ROWS[@]}"; do
    [[ "${row%%$'\t'*}" != "$HS_TYPE" ]] || versions+=("${row#*$'\t'}")
  done
  selected="$(hs_choose '已下载 Release 镜像（系统版本 / 详细版本）' "${versions[@]}")" || return $?
  (( ${versions[(Ie)$selected]} )) || { hs_error '选择器返回了无效镜像。'; return 2; }
  HS_VERSION="${selected%%$'\t'*}"
  if [[ -z "$HS_NAME" ]]; then
    proposed="JobsHarmony-${HS_TYPE}-$(/bin/date +%Y%m%d-%H%M%S)"
    HS_NAME="$proposed"
    while hs_name_exists "$HS_NAME" "${HS_NAMES[@]}"; do
      HS_NAME="${proposed}-${suffix}"
      suffix=$((suffix + 1))
    done
    print -r -- "ℹ 默认唯一名称：$HS_NAME"
    IFS= read -r 'answer?模拟器名称（回车使用默认）：' || return 130
    [[ -z "$answer" ]] || HS_NAME="$answer"
  fi
  hs_valid_name "$HS_NAME" || { hs_error '名称无效，未创建模拟器。'; return 2; }
  if hs_name_exists "$HS_NAME" "${HS_NAMES[@]}"; then
    hs_error "已有同名实例：$HS_NAME；不会覆盖。"
    return 1
  fi
}

hs_initialize_log() {
  local directory=""
  umask 077
  directory="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp/}/JobsHarmonySimulator.XXXXXX")" || return 1
  HS_LOG="$directory/CreateHarmonySimulator.log"
  : > "$HS_LOG" || return 1
  hs_log "ℹ 日志：$HS_LOG"
}

# 保留 stdin 给官方工具的原生许可提示，不传 -force，不代输 yes。
hs_run_command() {
  local result=0
  "$HS_BIN" "$@" 2>&1 | /usr/bin/tee -a "$HS_LOG" || result=$?
  (( result == 0 )) || { hs_error "Emulator $1 失败，退出码 $result；保留现场，不删除实例。"; return "$result"; }
}

hs_create_and_verify() {
  local answer="" result=0 current="" parsed=""
  hs_log "来源：Huawei DevEco Emulator；工具：$HS_BIN"
  hs_log "目标：DevEco 当前默认实例目录；名称：$HS_NAME；设备：$HS_TYPE；镜像：$HS_VERSION"
  IFS= read -r 'answer?回车确认新建；输入任意字符取消：' || return 130
  [[ -z "$answer" ]] || { hs_log '已取消，未创建模拟器。'; return 0; }
  # 确认期间可能有其它进程创建设备，写入前再检查一次命名冲突。
  current="$("$HS_BIN" -list -details)" || return $?
  parsed="$(hs_json names "$current")" || return 1
  local -a latest_names=("${(@f)parsed}")
  if hs_name_exists "$HS_NAME" "${latest_names[@]}"; then
    hs_error "名称已被其它操作使用：$HS_NAME；停止，不覆盖。"
    return 1
  fi
  hs_run_command -create "$HS_NAME" -deviceType "$HS_TYPE" -osVersion "$HS_VERSION" || return $?
  current="$("$HS_BIN" -list -details)" || result=$?
  (( result == 0 )) || { hs_error "创建命令已返回，但实例复检失败（退出码 $result），请在 Device Manager 核对。"; return "$result"; }
  hs_json verify "$current" "$HS_NAME" "$HS_TYPE" "$HS_VERSION" >/dev/null || {
    hs_error '创建命令已返回，但未验证到名称、设备类型和系统版本一致的唯一实例；不启动、不删除。'
    return 1
  }
  hs_log "✔ 已验证新建实例：$HS_NAME"
  if (( HS_START )); then
    hs_log 'ℹ 即将交给官方启动流程；首次许可请自行阅读并选择。要求开发者登录的镜像请在 Device Manager 启动。'
    hs_run_command -start "$HS_NAME" || return $?
    hs_log '✔ 官方启动命令已返回；最终启动状态请查看模拟器窗口与官方输出。'
  fi
}

hs_dispatch() {
  setopt NO_NOMATCH PIPE_FAIL
  hs_parse "$@" || return $?
  if (( HS_HELP )); then hs_help; return 0; fi
  if (( ! HS_CHECK )); then
    [[ -t 0 ]] || { hs_error '请在可交互终端运行；无交互时只能使用 --check / --help。'; return 1; }
    local answer=""
    IFS= read -r 'answer?已了解用途与影响，按回车继续；Ctrl+C 取消：' || return 130
  fi
  hs_check_host || return $?
  hs_find_emulator || return $?
  hs_log "ℹ 候选工具：$HS_BIN"
  hs_check_capabilities || return $?
  hs_log "ℹ 已确认官方兼容工具能力：$HS_BIN"
  hs_query_state || return $?
  if (( HS_CHECK )); then
    hs_log '✔ 只读检查完成；未创建、启动或下载。'
    return 0
  fi
  hs_initialize_log || return $?
  hs_select_image || return $?
  hs_create_and_verify
}

main() {
  hs_show_intro # 先说明用途、影响、平台要求和取消方式。
  hs_dispatch "$@" # 只读检查或交互选择本地镜像，创建并核验唯一实例。
}

main "$@"
