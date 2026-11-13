#!/bin/zsh
# 脚本自述：
# - 只供 source：共享项目环境读取、日志和 fzf 选择，不运行安装或业务入口。
# - 只读取普通小型配置，不执行项目配置；日志过滤 ANSI 与 URL 凭据。

# JOBS_INPUT_CHOICE_STYLE_BEGIN
# 只展示提示选项；不读取答案、不改变默认值、返回码或业务环境。
jobs_prompt_color_ready() {
  [ -z "${NO_COLOR+x}" ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
    [ "${PLAIN_OUTPUT:-0}" != 1 ] && [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]
}
# 原生 awk 分段着色；任意/非空输入优先，括号内外沿用同一个选项。
jobs_prompt_format() {
  /usr/bin/awk -v color="${1:-0}" -v lines="${2:-0}" -v keep="${3:-0}" '
    function typedEnter(value, start, prefix) {
      prefix = substr(value, 1, start - 1)
      gsub(/[“”‘’「」『』"]/, "", prefix)
      gsub(sprintf("%c", 39), "", prefix)
      if (prefix ~ /(空格|[Ss][Pp][Aa][Cc][Ee])[[:space:]]*(后|再|并|[Tt][Hh][Ee][Nn])?[[:space:]]*$/) return 1
      return prefix ~ /(输入|键入|填写|[Tt]ype)[^；;|]*[[:alnum:]_+-]+[[:space:]]*(后|再|并)?[[:space:]]*$/
    }
    function greenPosition(value, token, start) {
      if (match(value, /(直接|仅|只需|只|按下|按)?[[:space:]]*(回车|回車)/)) {
        start = RSTART
        return typedEnter(value, start) ? 0 : start
      }
      if (!match(value, /(^|[^[:alnum:]_])([Ee][Nn][Tt][Ee][Rr]|[Rr][Ee][Tt][Uu][Rr][Nn])([^[:alnum:]_]|$)/)) return 0
      start = RSTART
      token = substr(value, RSTART, RLENGTH)
      match(token, /[Ee][Nn][Tt][Ee][Rr]|[Rr][Ee][Tt][Uu][Rr][Nn]/)
      start += RSTART - 1
      return typedEnter(value, start) ? 0 : start
    }
    function segment(value, inherited, start, kind, prefix, body, red, green, connector, left, right, splitAt) {
      if (value == "") return value
      kind = inherited
      start = 1
      if (!kind) {
        if (match(value, /(输入)?(任意|任何)(非空)?(字符|内容|输入|键)|非空(字符|内容|输入)?|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key/)) {
          red = RSTART
        }
        green = greenPosition(value)
        if (red && green && green < red) {
          left = substr(value, 1, red - 1)
          right = substr(value, red)
          connector = ""
          if (match(left, /(或者|或)[[:space:]]*$/)) {
            connector = substr(left, RSTART)
            left = substr(left, 1, RSTART - 1)
          }
          return segment(left, 0) connector segment(right, 31)
        }
        if (red && green && red < green && match(value, /或[[:space:]]*(直接|仅|只需|只|按下|按)?(回车|回車)/)) {
          splitAt = RSTART
          return segment(substr(value, 1, splitAt - 1), 31) "或" segment(substr(value, splitAt + length("或")), 0)
        }
        if (red) {
          kind = 31
          start = red
        } else if (green) {
          kind = 32
          start = green
        }
      }
      if (!kind || !color) return value
      prefix = substr(value, 1, start - 1)
      body = substr(value, start)
      return prefix esc "[1;" kind "m" body esc "[0m"
    }
    function render(value, output, part, boundary, inherited, kind, consumed, depth, original) {
      original = value
      gsub(esc "\\[[0-9;]*m", "", value)
      if (color && keep && !greenPosition(value) && value !~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) return original
      output = ""
      inherited = 0
      depth = 0
      while (match(value, /[；;\/|，,、？?：:=＝（）()\[\]【】]/)) {
        part = substr(value, 1, RSTART - 1)
        boundary = substr(value, RSTART, RLENGTH)
        consumed = RSTART + RLENGTH
        output = output segment(part, inherited) boundary
        if (boundary ~ /[（(\[【]/) {
          depth++
          if (part ~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) inherited = 31
          else if (greenPosition(part)) inherited = 32
        } else if (boundary ~ /[）)\]】]/) {
          if (depth) depth--
        } else if (boundary ~ /[：:=＝]/) {
          if (!inherited) {
            if (part ~ /(任意|任何|非空|其它输入|其他输入)/) inherited = 31
            else if (greenPosition(part)) inherited = 32
          }
        } else if (!depth) inherited = 0
        value = substr(value, consumed)
      }
      return output segment(value, inherited)
    }
    BEGIN { esc = sprintf("%c", 27); first = 1 }
    {
      if (lines == 2) {
        if (!first) printf "%s\n", render(pending)
        pending = $0
        first = 0
        next
      }
      if (!lines && !first) printf "\n"
      printf "%s", render($0)
      if (lines) printf "\n"
      first = 0
    }
    END {
      if (lines == 2 && !first) {
        sub(sprintf("%c", 1) "$", "", pending)
        printf "%s", render(pending)
      }
    }
  '
}
# read 的命令替换会使 stdout 成为管道，按输入与提示所在 stderr 判断终端。
jobs_prompt_render() {
  local jobs_prompt_color=0
  if [ -t 0 ] && [ -t 2 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  printf "%s" "$1" | jobs_prompt_format "$jobs_prompt_color" 0
}
# 仅放在显示链末端；tee 在此函数之前接收纯文本，不把 ANSI 写入日志。
jobs_prompt_stream() {
  local jobs_prompt_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  jobs_prompt_format "$jobs_prompt_color" 1 1
}
# 显示管道保留原末尾换行；只删除本轮追加的最后一个结束标记。
jobs_prompt_filter() {
  local jobs_prompt_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  { /bin/cat; printf '\001'; } | jobs_prompt_format "$jobs_prompt_color" 2 1
}
# 仅包装原 printf/echo/print 展示，原参数、尾换行与显示命令退出码保持不变。
jobs_prompt_output() {
  local jobs_prompt_status=0 jobs_prompt_stderr=0 jobs_prompt_arg="" jobs_prompt_previous=""
  if [ "${1:-}" = print ]; then
    for jobs_prompt_arg in "$@"; do
      case "$jobs_prompt_arg" in -?*u2*|-u2) jobs_prompt_stderr=1 ;; esac
      if [ "$jobs_prompt_previous" = -u ] && [ "$jobs_prompt_arg" = 2 ]; then jobs_prompt_stderr=1; fi
      jobs_prompt_previous="$jobs_prompt_arg"
      [ "$jobs_prompt_arg" != -- ] || break
    done
  fi
  if [ -n "${ZSH_VERSION:-}" ]; then
    if [ "$jobs_prompt_stderr" = 1 ]; then
      "$@" 2>&1 | jobs_prompt_filter >&2
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    else
      "$@" | jobs_prompt_filter
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    fi
  elif [ -n "${BASH_VERSION:-}" ]; then
    "$@" | jobs_prompt_filter
    jobs_prompt_status=$(( ${PIPESTATUS[0]} != 0 ? ${PIPESTATUS[0]} : ${PIPESTATUS[1]} ))
  else
    "$@" | jobs_prompt_filter
    jobs_prompt_status=$?
  fi
  return "$jobs_prompt_status"
}
# 仅替换日志 primitive 的 tee：磁盘同步追加纯文，终端保留非选项原色。
jobs_prompt_tee() {
  local jobs_prompt_log="$1" jobs_prompt_line="" jobs_prompt_newline=0
  while :; do
    jobs_prompt_line=""
    if IFS= read -r jobs_prompt_line; then jobs_prompt_newline=1; else jobs_prompt_newline=0; [ -n "$jobs_prompt_line" ] || break; fi
    if [ "$jobs_prompt_newline" = 1 ]; then
      { printf '%s\n' "$jobs_prompt_line"; printf '\001'; } | jobs_prompt_format 0 2 >> "$jobs_prompt_log" || return $?
      printf '%s\n' "$jobs_prompt_line" | jobs_prompt_filter || return $?
    else
      { printf '%s' "$jobs_prompt_line"; printf '\001'; } | jobs_prompt_format 0 2 >> "$jobs_prompt_log" || return $?
      printf '%s' "$jobs_prompt_line" | jobs_prompt_filter || return $?
    fi
  done
}
# JOBS_INPUT_CHOICE_STYLE_END

typeset -g PE_TOOLS_DIR="${${(%):-%x}:A:h}" PE_LOG_FILE="" PE_RUN_DIR="" PE_PROJECT=""
typeset -g PE_FZF="" PE_SELECTION="" PE_CONFIG_FLUTTER="" PE_CONFIG_JAVA="" PE_PLATFORM=""
typeset -gA PE_EVENT_VERSIONS=()
# 输出脱敏纯文本日志，保留第三方退出码由调用者负责。
pe_filter_log() {
    /usr/bin/perl -pe 'BEGIN { $|=1 } s/\e\[[0-?]*[ -\/]*[@-~]//g; s{(https?://)[^/\s@]+@}{${1}[REDACTED]@}g; s{(https?://[^\s?]+)\?[^\s]*}{${1}?[REDACTED]}g'
}
# 将消息同步到终端与当前运行日志。
pe_log() {
    if [[ -n "$PE_LOG_FILE" ]]; then
        print -r -- "$1" | pe_filter_log | jobs_prompt_tee "$PE_LOG_FILE"
    else
        print -r -- "$1" | pe_filter_log
    fi
}
# 向GUI私有事件文件追加结构化里程碑；没有GUI时保持终端脚本独立可用。
pe_event() {
    local event_file="${JOBS_FLUTTER_SETUP_EVENTS:-}" identifier="$1" parent="$2" title="$3" state="$4" message="${5:-}" version="${6:-}"
    if [[ -n "$version" ]]; then PE_EVENT_VERSIONS[$identifier]="$version";
    else version="${PE_EVENT_VERSIONS[$identifier]:-}"; fi
    [[ -n "$event_file" ]] || return 0
    [[ "$event_file" == /* && -d "${event_file:h}" && ! -L "${event_file:h}" && ! -L "$event_file" && ( ! -e "$event_file" || -f "$event_file" ) ]] || { pe_log '⚠ GUI事件文件身份异常，未写入里程碑。'; return 1; }
    case "$state" in pending|running|succeeded|failed|attention) ;; *) return 2 ;; esac
    /usr/bin/osascript -l JavaScript - "$identifier" "$parent" "$title" "$state" "$message" "$version" >> "$event_file" <<'JXA'
function run(a) { return JSON.stringify({id:a[0],parent:a[1],title:a[2],state:a[3],message:a[4],version:a[5]}); }
JXA
}
# 按工具输出格式读取真实版本，跳过Gem/Ruby警告中的其它组件版本。
pe_semantic_version() {
    /usr/bin/perl -e '
        my($file,$tool)=@ARGV; $tool//=""; open my $in,"<",$file or exit 1;
        my $v=qr/([0-9]+\.[0-9]+(?:\.[0-9]+)?(?:[-+][0-9A-Za-z.-]+)?)/;
        while (<$in>) {
            s/\e\[[0-?]*[ -\/]*[@-~]//g; s/\r?\n$//;
            if ($tool eq "pods") {if (/^\s*(?:CocoaPods\s+)?$v\s*$/i) {print $1; last;}}
            elsif ($tool eq "bundler") {if (/^\s*Bundler\s+(?:version\s+)?$v\s*$/i) {print $1; last;}}
            elsif ($tool eq "fvm") {if (/^\s*(?:FVM(?:\s+version)?[:\s]+)?v?$v\s*$/i) {print $1; last;}}
            elsif ($tool eq "jenv") {if (/^\s*jenv\s+(?:version\s+)?$v\s*$/i) {print $1; last;}}
            elsif ($tool eq "dart") {if (/^Dart SDK version:\s*$v\b/) {print $1; last;}}
            elsif ($tool eq "browser") {if (/^\s*((?:Google Chrome(?: for Testing)?|Microsoft Edge|Chromium|Brave Browser|Vivaldi)\s+$v.*)$/i) {print $1; last;}}
            elsif (/\b$v/) {print $1; last;}
        }
    ' "$1" "${2:-}"
}
# 自述标题红色加粗、正文蓝色，非终端保持纯文本。
pe_intro_line() {
    local role="$1" message="$2"
    if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" ]]; then
        if [[ "$role" == title ]]; then printf '\033[1;31m%s\033[0m\n' "$message";
        else printf '\033[0;34m%s\033[0m\n' "$message"; fi
    else
        print -r -- "$message"
    fi
}
# 只认所选目录自身的 Flutter 声明，拒绝链接目录和清单。
pe_validate_project() {
    local target="$1" kind=""
    [[ "$target" == /* && "$target" != / && -d "$target" && ! -L "${target%/}" && -f "$target/pubspec.yaml" && ! -L "$target/pubspec.yaml" ]] || return 2
    kind="$(/bin/zsh "$PE_TOOLS_DIR/CleanBuildArtifacts.zsh" "$target" --detect 2>/dev/null)" || return 2
    [[ "$kind" == Flutter ]] || return 2
    PE_PROJECT="${target:A}"
}
# 进入已确认流程后创建独立日志，不重用或清空前次运行记录。
pe_initialize_runtime() {
    setopt NO_NOMATCH PIPE_FAIL
    umask 077
    PE_RUN_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/JobsFlutterEnvironment.XXXXXX")" || return 1
    PE_LOG_FILE="$PE_RUN_DIR/environment.log"
    : > "$PE_LOG_FILE"
    pe_log "➤ 日志与配置快照：$PE_RUN_DIR"
}
# 同步运行命令并保留真实错误码；参数绝不交给 eval。
pe_run_logged() {
    local result=0 raw_file=""
    raw_file="$(/usr/bin/mktemp "$PE_RUN_DIR/command.raw.XXXXXX")" || return 1
    "$@" 2>&1 | /usr/bin/tee "$raw_file" >(pe_filter_log >> "$PE_LOG_FILE")
    result=${pipestatus[1]}
    return "$result"
}
# 发现可用 fzf，缺少时在确认后通过已有 Homebrew 补齐一次。
pe_ensure_fzf() {
    local candidate="" brew="" answer=""
    for candidate in "$(command -v fzf 2>/dev/null)" /opt/homebrew/bin/fzf /usr/local/bin/fzf; do
        if [[ -x "$candidate" ]] && "$candidate" --version >/dev/null 2>&1; then PE_FZF="$candidate"; return 0; fi
    done
    for candidate in "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [[ -x "$candidate" ]] && "$candidate" --version >/dev/null 2>&1; then brew="$candidate"; break; fi
    done
    if [[ -z "$brew" ]]; then
        source "$PE_TOOLS_DIR/SetupHomebrew.zsh" || return $?
        pe_prepare_homebrew || return $?
        brew="$PJ_BREW"
    fi
    pe_log '➤ fzf 不可用；来源：https://formulae.brew.sh/formula/fzf；安装到当前 Homebrew 前缀。'
    IFS= read -r "answer?$(jobs_prompt_render '输入任意字符安装 fzf；回车取消：')" || return 130
    [[ -n "$answer" ]] || return 130
    pe_run_logged /usr/bin/env HOMEBREW_NO_AUTO_UPDATE=1 "$brew" install fzf || return $?
    candidate="$(HOMEBREW_NO_AUTO_UPDATE=1 "$brew" --prefix)/bin/fzf"
    [[ -x "$candidate" ]] && "$candidate" --version >/dev/null 2>&1 || { pe_log '✖ fzf 安装后仍不可用。'; return 1; }
    PE_FZF="$candidate"
}
# fzf 单选携带左返回，验证返回值必须来自展示清单。
pe_select() {
    local prompt="$1" rows="$2" selected="" result=0
    selected="$(print -r -- "$rows" | FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE=/dev/null "$PE_FZF" --no-multi --height=60% --layout=reverse --delimiter=$'\t' --expect=left --prompt="$prompt > " --header='Enter 选择；← 返回上一层；Esc 取消；首项为默认')" || result=$?
    [[ "${selected%%$'\n'*}" != left ]] || return 10
    (( result == 0 )) || { (( result == 1 || result == 130 )) && return 130; return "$result"; }
    selected="${selected#*$'\n'}"
    [[ -n "$selected" ]] && print -r -- "$rows" | /usr/bin/grep -Fqx -- "$selected" || return 2
    PE_SELECTION="${selected%%$'\t'*}"
}
# 配置只允许普通小型 JSON；平台不一致和损坏配置都明确停止。
pe_read_environment() {
    local config="$PE_PROJECT/.jobs/flutter-environment.json" size="" platform=""
    PE_CONFIG_FLUTTER="" PE_CONFIG_JAVA="" PE_PLATFORM=""
    [[ ! -L "$PE_PROJECT/.jobs" && ! -L "$config" ]] || { pe_log '✖ .jobs 或环境配置是符号链接，已停止。'; return 1; }
    [[ -e "$config" ]] || return 0
    [[ -f "$config" ]] || return 1
    size="$(/usr/bin/stat -f '%l:%z' "$config")" || return 1
    [[ "${size%%:*}" == 1 && "${size#*:}" -le 65536 ]] || { pe_log '✖ 环境配置超过64KiB或含硬链接。'; return 1; }
    /usr/bin/plutil -convert xml1 -o /dev/null "$config" >/dev/null 2>&1 || { pe_log '✖ 环境配置损坏；请检查原文件后重新配置。'; return 1; }
    platform="$(/usr/bin/plutil -extract Platform raw -o - "$config" 2>/dev/null)"
    [[ -z "$platform" || "$platform" == MacOS ]] || { pe_log "✖ 环境配置来自 $platform，请在本机重新配置，保留旧文件作为参考。"; return 1; }
    PE_CONFIG_FLUTTER="$(/usr/bin/plutil -extract FlutterPath raw -o - "$config" 2>/dev/null)" || { pe_log "✖ 环境记录缺少FlutterPath：$config；请重新一键配置。"; return 1; }
    PE_CONFIG_JAVA="$(/usr/bin/plutil -extract JavaHome raw -o - "$config" 2>/dev/null)" || { pe_log "✖ 环境记录缺少JavaHome：$config；请重新一键配置。"; return 1; }
    [[ "$PE_CONFIG_FLUTTER" == /* ]] || { pe_log '✖ 环境记录FlutterPath不是绝对路径，请重新一键配置。'; return 1; }
    if [[ -z "$PE_CONFIG_JAVA" ]]; then
        [[ "$(/usr/bin/plutil -extract JavaMode raw -o - "$config" 2>/dev/null)" == none ]] || { pe_log '✖ 空JavaHome必须明确标记JavaMode为none，请重新一键配置。'; return 1; }
    else
        [[ "$PE_CONFIG_JAVA" == /* ]] || { pe_log '✖ 环境记录JavaHome不是绝对路径，请重新一键配置。'; return 1; }
    fi
    PE_PLATFORM="$platform"
}
