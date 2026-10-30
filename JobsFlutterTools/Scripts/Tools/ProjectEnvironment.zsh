#!/bin/zsh
# 脚本自述：
# - 只供 source：共享项目环境读取、日志和 fzf 选择，不运行安装或业务入口。
# - 只读取普通小型配置，不执行项目配置；日志过滤 ANSI 与 URL 凭据。

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
        print -r -- "$1" | pe_filter_log | /usr/bin/tee -a "$PE_LOG_FILE"
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
    IFS= read -r 'answer?输入任意字符安装 fzf；回车取消：' || return 130
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
    PE_CONFIG_FLUTTER="$(/usr/bin/plutil -extract FlutterPath raw -o - "$config" 2>/dev/null)" || return 1
    PE_CONFIG_JAVA="$(/usr/bin/plutil -extract JavaHome raw -o - "$config" 2>/dev/null)" || return 1
    [[ "$PE_CONFIG_FLUTTER" == /* && "$PE_CONFIG_JAVA" == /* ]] || return 1
    PE_PLATFORM="$platform"
}
