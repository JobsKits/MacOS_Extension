#!/bin/zsh
# 脚本自述：
# - 脚本名称：ManageExtension.zsh（App 内部后台管理器）
# - 核心用途：一个入口管理本功能的安装 / 更新、卸载与构建产物清理。
# - 影响范围：当前用户 Finder 菜单、对应构建产物与专用功能配置；保留源码和业务数据。
# - 运行提示：直接打开 GUI，在面板选择安装 / 更新或卸载；底部实时日志允许复制。
# shell: zsh

# >>> Jobs terminal style protection v1 >>>
# 临时保护当前终端配色，业务进程自行管理原有退出清理。
jobs_terminal_style_run() {
    # 无法可靠保存原色时，沿用脚本已有的纯文本约定。
    jobs_terminal_style_plain() {
        PLAIN_OUTPUT=1
        NO_COLOR=1
        FORCE_COLOR=0
        CLICOLOR=0
        ANSI_COLORS_DISABLED=1
        npm_config_color=false
        export PLAIN_OUTPUT NO_COLOR FORCE_COLOR CLICOLOR ANSI_COLORS_DISABLED npm_config_color
        if "$@"; then
            jobs_style_exit_status=0
        else
            jobs_style_exit_status=$?
        fi
        exit "$jobs_style_exit_status"
    }
    if [ ! -t 0 ] || [ ! -t 1 ] || [ -z "${TERM:-}" ] ||
       [ "${TERM:-}" = dumb ] || [ "${NO_COLOR+x}" = x ] ||
       [ "${PLAIN_OUTPUT:-0}" = 1 ] || [ "${IS_SOURCETREE_RUNTIME:-0}" = 1 ] ||
       env | LC_ALL=C grep -qiE '^(SOURCETREE|SOURCE_TREE)'; then
        if "$@"; then
            jobs_style_exit_status=0
        else
            jobs_style_exit_status=$?
        fi
        exit "$jobs_style_exit_status"
    fi
    if [ -n "${TMUX:-}${STY:-}" ]; then
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_tty=$(tty 2>/dev/null) || jobs_terminal_style_plain "$@"
    if ! ps -o pgid= -o tpgid= -p "$$" 2>/dev/null |
         LC_ALL=C awk 'NF == 2 && $1 == $2 && $1 > 0 { foreground = 1 } END { exit !foreground }'; then
        jobs_terminal_style_plain "$@"
    fi
    case ${JOBS_TERMINAL_STYLE_OWNER:-} in
        ''|*[!0-9]*) ;;
        *)
            if [ "${JOBS_TERMINAL_STYLE_TTY:-}" = "$jobs_style_tty" ] &&
               kill -0 "$JOBS_TERMINAL_STYLE_OWNER" 2>/dev/null; then
                if "$@"; then
                    jobs_style_exit_status=0
                else
                    jobs_style_exit_status=$?
                fi
                exit "$jobs_style_exit_status"
            fi
            ;;
    esac
    jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_terminal_style_plain "$@"
    jobs_style_saved=''
    jobs_style_saved_rows=''
    jobs_style_applied_rows=''
    jobs_style_changed=0
    jobs_style_applied_complete=0
    jobs_style_query_active=0
    jobs_style_recovery=''
    jobs_style_exit_status=0
    jobs_style_esc=$(printf '\033')
    jobs_style_bel=$(printf '\007')
    # 只接受本次请求对应的 RGB 响应；非协议输入使本次探测失败。
    jobs_terminal_style_query() {
        jobs_style_query_key=$1
        printf '\033]%s;?\007' "$jobs_style_query_key" > /dev/tty || return 1
        jobs_style_reply=''
        for jobs_style_attempt in 1 2 3; do
            jobs_style_piece=$(dd bs=256 count=1 2>/dev/null < /dev/tty)
            jobs_style_reply=$jobs_style_reply$jobs_style_piece
            case $jobs_style_reply in
                *"$jobs_style_bel"|*"$jobs_style_esc\\") break ;;
                '') ;;
                "$jobs_style_esc"*) ;;
                *) break ;;
            esac
        done
        case $jobs_style_reply in
            "$jobs_style_esc]$jobs_style_query_key;rgb:"*"$jobs_style_bel")
                jobs_style_rgb=${jobs_style_reply#"$jobs_style_esc]$jobs_style_query_key;rgb:"}
                jobs_style_rgb=${jobs_style_rgb%"$jobs_style_bel"}
                ;;
            "$jobs_style_esc]$jobs_style_query_key;rgb:"*"$jobs_style_esc\\")
                jobs_style_rgb=${jobs_style_reply#"$jobs_style_esc]$jobs_style_query_key;rgb:"}
                jobs_style_rgb=${jobs_style_rgb%"$jobs_style_esc\\"}
                ;;
            *) return 1 ;;
        esac
        jobs_style_normalized=$(printf '%s\n' "$jobs_style_rgb" | LC_ALL=C awk -F/ '
            NF != 3 { exit 1 }
            {
                for (i = 1; i <= 3; i++) {
                    h = tolower($i)
                    if (length(h) < 1 || length(h) > 4 || h ~ /[^0-9a-f]/) exit 1
                    n = 0
                    for (j = 1; j <= length(h); j++) n = n * 16 + index("0123456789abcdef", substr(h, j, 1)) - 1
                    value[i] = int(n * 65535 / (16 ^ length(h) - 1) + 0.5)
                }
                printf "%d/%d/%d", value[1], value[2], value[3]
            }
        ') || return 1
        [ -n "$jobs_style_normalized" ]
    }
    # 查询可用不代表终端允许改色，按目标值核对实际生效结果。
    jobs_terminal_style_accepts_target() {
        jobs_style_requested_hex=''
        case $1 in
            10|12) jobs_style_requested_hex=ffffff ;;
            11) jobs_style_requested_hex=000000 ;;
            '4;'*)
                jobs_style_requested_index=0
                for jobs_style_requested_color in 000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff; do
                    if [ "4;$jobs_style_requested_index" = "$1" ]; then
                        jobs_style_requested_hex=$jobs_style_requested_color
                        break
                    fi
                    jobs_style_requested_index=$((jobs_style_requested_index + 1))
                done
                ;;
        esac
        [ -n "$jobs_style_requested_hex" ] || return 1
        printf '%s|%s\n' "$jobs_style_normalized" "$jobs_style_requested_hex" | LC_ALL=C awk -F'|' '
            function hexbyte(h) {
                return (index("0123456789abcdef", substr(h, 1, 1)) - 1) * 16 + index("0123456789abcdef", substr(h, 2, 1)) - 1
            }
            {
                if (split($1, actual, "/") != 3 || length($2) != 6) exit 1
                for (i = 1; i <= 3; i++) {
                    difference = actual[i] - hexbyte(substr($2, i * 2 - 1, 2)) * 257
                    if (difference < -255 || difference > 255) exit 1
                }
            }
        '
    }
    # 检测到后续改色时只恢复仍由本次保护持有的项，保留独立恢复入口。
    jobs_terminal_style_cleanup() {
        jobs_style_result=$1
        trap '' HUP INT TERM
        if [ "$jobs_style_query_active" = 1 ]; then
            stty "$jobs_style_stty" 2>/dev/null < /dev/tty || :
            jobs_style_query_active=0
        fi
        if [ "$jobs_style_changed" = 1 ]; then
            jobs_style_cleanup_ok=0
            jobs_style_conflicts=''
            jobs_style_restore_safe=''
            if [ "$jobs_style_applied_complete" = 1 ]; then
                jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_style_stty=''
                if [ -n "$jobs_style_stty" ] && stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
                    jobs_style_query_active=1
                    jobs_style_cleanup_ok=1
                    while IFS='|' read -r jobs_style_key jobs_style_expected jobs_style_original; do
                        [ -n "$jobs_style_key" ] || continue
                        if ! jobs_terminal_style_query "$jobs_style_key"; then
                            jobs_style_cleanup_ok=0
                            break
                        fi
                        if [ "$jobs_style_normalized" = "$jobs_style_expected" ]; then
                            jobs_style_restore_safe=$jobs_style_restore_safe$jobs_style_original
                        else
                            jobs_style_conflicts="$jobs_style_conflicts $jobs_style_key"
                        fi
                    done <<JOBS_STYLE_APPLIED
$jobs_style_applied_rows
JOBS_STYLE_APPLIED
                    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || jobs_style_cleanup_ok=0
                    jobs_style_query_active=0
                fi
            fi
            if [ "$jobs_style_cleanup_ok" = 1 ] && printf '%s\033[0m' "$jobs_style_restore_safe" > /dev/tty; then
                if [ -z "$jobs_style_conflicts" ]; then
                    rm -f "$jobs_style_recovery"
                    rmdir "${jobs_style_recovery%/*}" 2>/dev/null || :
                else
                    printf '检测到运行期间的配色变更，已保留这些项：%s\n' "$jobs_style_conflicts" >&2
                    printf '确认要覆盖后续改色时才使用恢复入口：sh "%s"\n' "$jobs_style_recovery" >&2
                    [ "$jobs_style_result" -ne 0 ] || jobs_style_result=1
                fi
            else
                printf '终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh "%s"\n' "$jobs_style_recovery" >&2
                [ "$jobs_style_result" -ne 0 ] || jobs_style_result=1
            fi
        fi
        if [ "${2:-}" = continue ]; then
            jobs_style_cleanup_status=$jobs_style_result
            return 0
        fi
        exit "$jobs_style_result"
    }
    trap 'jobs_terminal_style_cleanup "$jobs_style_exit_status"' 0
    trap 'jobs_style_exit_status=129; exit 129' HUP
    trap 'jobs_style_exit_status=130; exit 130' INT
    trap 'jobs_style_exit_status=143; exit 143' TERM
    if ! stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_query_active=1
    jobs_style_probe_ok=1
    for jobs_style_key in 10 11 12 '4;0' '4;1' '4;2' '4;3' '4;4' '4;5' '4;6' '4;7' '4;8' '4;9' '4;10' '4;11' '4;12' '4;13' '4;14' '4;15'; do
        if ! jobs_terminal_style_query "$jobs_style_key"; then
            jobs_style_probe_ok=0
            break
        fi
        jobs_style_saved=$jobs_style_saved$jobs_style_reply
        jobs_style_saved_rows="$jobs_style_saved_rows$jobs_style_key|$jobs_style_reply
"
    done
    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=0
    if [ "$jobs_style_probe_ok" != 1 ]; then
        printf '%s\n' '终端不支持完整配色保存，或启动时收到其它输入；保留原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_recovery_dir=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/jobs-terminal-style.XXXXXX") || jobs_terminal_style_plain "$@"
    jobs_style_recovery=$jobs_style_recovery_dir/restore.sh
    if ! (umask 077; {
        printf '#!/bin/sh\n'
        printf '[ -t 0 ] && [ "$(tty)" = '\''%s'\'' ] || { printf '\''请在原终端运行恢复入口。\\n'\'' >&2; exit 1; }\n' "$jobs_style_tty"
        printf 'printf '\''本操作会覆盖此终端当前配色。确认恢复脚本启动前的配色，请输入 YES：'\'' >&2\n'
        printf 'IFS= read -r jobs_restore_choice\n[ "$jobs_restore_choice" = YES ] || exit 1\n'
        printf 'printf '\''%%s\\033[0m'\'' '\''%s'\'' > /dev/tty\n' "$jobs_style_saved"
    } > "$jobs_style_recovery"); then
        printf '%s\n' '无法保存终端配色恢复入口；保留原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    printf '正在准备本次终端临时配色；强退后恢复入口：sh "%s"\n' "$jobs_style_recovery" >&2
    jobs_style_changed=1
    printf '\033]10;#ffffff\007\033]11;#000000\007\033]12;#ffffff\007' > /dev/tty
    jobs_style_index=0
    for jobs_style_color in 000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff; do
        printf '\033]4;%s;#%s\007' "$jobs_style_index" "$jobs_style_color" > /dev/tty
        jobs_style_index=$((jobs_style_index + 1))
    done
    printf '\033[0m' > /dev/tty
    jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || { jobs_style_exit_status=1; exit 1; }
    stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=1
    jobs_style_probe_ok=1
    jobs_style_targets_ok=1
    while IFS='|' read -r jobs_style_key jobs_style_original; do
        [ -n "$jobs_style_key" ] || continue
        if ! jobs_terminal_style_query "$jobs_style_key"; then
            jobs_style_probe_ok=0
            break
        fi
        jobs_style_applied_rows="$jobs_style_applied_rows$jobs_style_key|$jobs_style_normalized|$jobs_style_original
"
        if ! jobs_terminal_style_accepts_target "$jobs_style_key"; then
            jobs_style_targets_ok=0
        fi
    done <<JOBS_STYLE_ORIGINAL
$jobs_style_saved_rows
JOBS_STYLE_ORIGINAL
    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=0
    if [ "$jobs_style_probe_ok" != 1 ]; then
        printf '%s\n' '无法核实本次临时配色，已停止启动业务。' >&2
        jobs_style_exit_status=1
        exit 1
    fi
    jobs_style_applied_complete=1
    if [ "$jobs_style_targets_ok" != 1 ]; then
        jobs_terminal_style_cleanup 0 continue
        jobs_style_changed=0
        if [ "$jobs_style_cleanup_status" != 0 ]; then
            jobs_style_exit_status=1
            exit 1
        fi
        trap 'jobs_style_exit_status=129; exit 129' HUP
        trap 'jobs_style_exit_status=130; exit 130' INT
        trap 'jobs_style_exit_status=143; exit 143' TERM
        printf '%s\n' '终端未接受本次配色，已恢复原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    printf '%s\n' '本次终端已临时使用黑底白字。' >&2
    JOBS_TERMINAL_STYLE_TTY=$jobs_style_tty
    JOBS_TERMINAL_STYLE_OWNER=$$
    export JOBS_TERMINAL_STYLE_TTY JOBS_TERMINAL_STYLE_OWNER
    if "$@"; then
        jobs_style_exit_status=0
    else
        jobs_style_exit_status=$?
    fi
    exit "$jobs_style_exit_status"
}
# 仅监督直接执行的入口；被 source 时不切换配色、不重新执行业务。
jobs_terminal_style_bootstrap() {
    jobs_style_bootstrap_script=$1
    shift
    if [ -n "${ZSH_VERSION:-}" ]; then
        case ${ZSH_EVAL_CONTEXT:-} in
            *:file|*:file:*) return 0 ;;
        esac
    elif [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE:-$jobs_style_bootstrap_script}" != "$jobs_style_bootstrap_script" ]; then
        return 0
    fi
    if [ "${JOBS_TERMINAL_STYLE_REEXEC:-}" = "$jobs_style_bootstrap_script" ]; then
        unset JOBS_TERMINAL_STYLE_REEXEC
        return 0
    fi
    if [ ! -t 0 ] || [ ! -t 1 ] || [ -z "${TERM:-}" ] ||
       [ "${TERM:-}" = dumb ] || [ "${NO_COLOR+x}" = x ] ||
       [ "${PLAIN_OUTPUT:-0}" = 1 ] || [ "${IS_SOURCETREE_RUNTIME:-0}" = 1 ] ||
       [ -n "${TMUX:-}${STY:-}" ] ||
       env | LC_ALL=C grep -qiE '^(SOURCETREE|SOURCE_TREE)'; then
        return 0
    fi
    case ${JOBS_TERMINAL_STYLE_OWNER:-} in
        ''|*[!0-9]*) ;;
        *)
            if kill -0 "$JOBS_TERMINAL_STYLE_OWNER" 2>/dev/null &&
               [ "${JOBS_TERMINAL_STYLE_TTY:-}" = "$(tty 2>/dev/null)" ]; then
                return 0
            fi
            ;;
    esac
    JOBS_TERMINAL_STYLE_REEXEC=$jobs_style_bootstrap_script
    export JOBS_TERMINAL_STYLE_REEXEC
    jobs_terminal_style_run /bin/zsh "$jobs_style_bootstrap_script" "$@"
    jobs_style_bootstrap_result=$?
    exit "$jobs_style_bootstrap_result"
}
jobs_terminal_style_bootstrap "$0" "$@"
# <<< Jobs terminal style protection v1 <<<

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

MANAGER_ACTION=""
MANAGER_STOP_REQUEST_FILE="${JOBS_FINDER_STOP_REQUEST_FILE:-}"
MANAGER_NON_INTERACTIVE=0
MANAGER_SKIP_RESTART=0
MANAGER_REQUESTED_FEATURES=""
MANAGER_ENTRY_DIR=""
MANAGER_GUI_SESSION=0
MANAGER_GUI_LEAF_FEATURES=""
MANAGER_UI_SCOPE="run-revoke"
# 支持上级面板在完成确认后调用；显式参数不会改变本目录的功能边界。
manager_parse_options() {
  local install_location="${JOBS_FINDER_INSTALL_LOCATION:-build}" cleanup_build_products="${JOBS_FINDER_CLEANUP_BUILD_PRODUCTS:-0}"
  MANAGER_ENTRY_DIR="${ZSH_ARGZERO:A:h:h}"
  while (( $# > 0 )); do
    case "$1" in
      --action) (( $# >= 2 )) || return 2; MANAGER_ACTION="$2"; shift ;;
      --action=*) MANAGER_ACTION="${1#--action=}" ;;
      --install-location) (( $# >= 2 )) || return 2; install_location="$2"; shift ;;
      --install-location=*) install_location="${1#--install-location=}" ;;
      --cleanup-build-products) cleanup_build_products=1 ;;
      --stop-request-file) (( $# >= 2 )) && [[ "$2" == /* ]] || return 2; MANAGER_STOP_REQUEST_FILE="$2"; shift ;;
      --stop-request-file=*) MANAGER_STOP_REQUEST_FILE="${1#--stop-request-file=}"; [[ "$MANAGER_STOP_REQUEST_FILE" == /* ]] || return 2 ;;
      --non-interactive) MANAGER_NON_INTERACTIVE=1 ;;
      --gui-session) MANAGER_GUI_SESSION=1 ;;
      --skip-finder-restart) MANAGER_SKIP_RESTART=1 ;;
      --scope|--features) (( $# >= 2 )) || return 2; MANAGER_REQUESTED_FEATURES="$2"; shift ;;
      --features=*) MANAGER_REQUESTED_FEATURES="${1#--features=}" ;;
      --help|-h) print '用法：双击管理，或 --action install|uninstall|cleanup --non-interactive [--features 功能ID,...] [--skip-finder-restart] [--install-location build|applications] [--cleanup-build-products] [--stop-request-file PATH]'; return 10 ;;
      *) print -u2 -r -- "✖ 未知参数：$1"; return 2 ;;
    esac
    shift
  done
  [[ "$install_location" == build || "$install_location" == applications ]] || { print -u2 "✖ 安装位置必须是 build 或 applications。"; return 2; }
  [[ "$cleanup_build_products" == 0 || "$cleanup_build_products" == 1 ]] || { print -u2 '✖ 构建产物清理开关必须是 0 或 1。'; return 2; }
  if [[ "$cleanup_build_products" == 1 && ( "$install_location" != applications || "${MANAGER_ACTION:-install}" != install ) ]]; then
    print -u2 '✖ 仅安装到应用程序目录时允许清除此轮构建产物。'
    return 2
  fi
  [[ "$MANAGER_ACTION" != cleanup || "$install_location" == applications ]] || { print -u2 '✖ 独立清理仅允许应用程序目录模式。'; return 2; }
  [[ -z "$MANAGER_STOP_REQUEST_FILE" || "$MANAGER_STOP_REQUEST_FILE" == /* ]] || { print -u2 '✖ 停止请求文件必须使用绝对路径。'; return 2; }
  export JOBS_FINDER_STOP_REQUEST_FILE="$MANAGER_STOP_REQUEST_FILE"
  export JOBS_FINDER_CLEANUP_BUILD_PRODUCTS="$cleanup_build_products"
  export JOBS_FINDER_INSTALL_LOCATION="$install_location"
  manager_prepare_gui_features || return $?
  [[ -z "$MANAGER_ACTION" || "$MANAGER_ACTION" == install || "$MANAGER_ACTION" == uninstall || "$MANAGER_ACTION" == cleanup ]] || return 2
  (( ! MANAGER_NON_INTERACTIVE )) || [[ -n "$MANAGER_ACTION" ]] || { print -u2 '✖ 非交互调用必须明确 --action。'; return 2; }
}
# 不支持颜色时保留纯文本自述，确认前不创建日志或修改系统。
manager_intro_line() {
  local role="$1" message="$2" code='0;34'
  [[ "$role" != title ]] || code='1;31'
  if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" ]]; then
    /usr/bin/printf '\033[%sm%s\033[0m\n' "$code" "$message"
  else
    print -r -- "$message"
  fi
}
# 上级批量操作只刷新一次 Finder。
manager_restart_finder() {
  (( MANAGER_SKIP_RESTART )) && return 0
  /usr/bin/killall Finder "$@"
}
# 按原有功能白名单把 GUI 叶标识转换为包内动作，事件仍使用原 GUI 标识。
manager_prepare_gui_features() {
  local feature="" mapped="" prepared=() allowed=("${(@s:,:)MANAGER_UI_SCOPE}")
  MANAGER_GUI_LEAF_FEATURES="$MANAGER_REQUESTED_FEATURES"
  [[ -n "$MANAGER_REQUESTED_FEATURES" ]] || { MANAGER_GUI_LEAF_FEATURES="$MANAGER_UI_SCOPE"; return 0; }
  [[ "$MANAGER_REQUESTED_FEATURES" != ,* && "$MANAGER_REQUESTED_FEATURES" != *, && "$MANAGER_REQUESTED_FEATURES" != *,,* ]] || return 2
  for feature in ${(s:,:)MANAGER_REQUESTED_FEATURES}; do
    mapped="$feature"
    case "${MANAGER_ENTRY_DIR:t}" in
      JobsFlutter*)
        if (( ${allowed[(Ie)$feature]} )); then
          mapped="${feature#flutter-}"
        fi
        ;;
      JobsTerminalOpener)
        case "$feature" in
          terminal_open) mapped=open ;;
          file_content) mapped=file-content ;;
          file_merge) mapped=file-merge ;;
          file_split) mapped=file-split ;;
          clean_build_artifacts) mapped=clean-build-artifacts ;;
          codegraph_bootstrap) mapped=codegraph-bootstrap ;;
        esac
        ;;
      JobsIOSTools) [[ "$feature" != pod_install ]] || mapped=ios-pod-install ;;
    esac
    if [[ "$MANAGER_ACTION" == cleanup ]]; then
      local cleanup_identifier="$(manager_gui_identifier "$mapped")"
      (( ${allowed[(Ie)$cleanup_identifier]} )) || { print -u2 -r -- "✖ 功能不属于本入口：$feature"; return 2; }
    fi
    prepared+=("$mapped")
  done
  MANAGER_REQUESTED_FEATURES="${(j:,:)prepared}"
}
# 兼容命令行包内动作，同时把 GUI 范围和状态统一为选择器叶 ID。
manager_gui_identifier() {
  local identifier="$1"
  case "${MANAGER_ENTRY_DIR:t}" in
    JobsFlutter*) [[ "$identifier" == flutter-* ]] || identifier="flutter-$identifier" ;;
    JobsTerminalOpener)
      case "$identifier" in
        open) identifier=terminal_open ;;
        file-content) identifier=file_content ;;
        file-merge) identifier=file_merge ;;
        file-split) identifier=file_split ;;
        clean-build-artifacts) identifier=clean_build_artifacts ;;
        codegraph-bootstrap) identifier=codegraph_bootstrap ;;
      esac
      ;;
    JobsIOSTools) [[ "$identifier" != ios-pod-install ]] || identifier=pod_install ;;
  esac
  print -nr -- "$identifier"
}
# 完整仓转交总管理器的受限范围，独立包使用随包源码且仍能整体复制。
manager_open_gui() {
  local -x JOBS_FINDER_STOP_REQUEST_FILE=""
  local entry="${MANAGER_ENTRY_DIR:h}/Scripts/ManageFinderExtensions.zsh" helper="$MANAGER_ENTRY_DIR/Scripts/FinderManagerGUI.zsh"
  local scope="$MANAGER_UI_SCOPE" identifier="" feature="" selected=() allowed=("${(@s:,:)MANAGER_UI_SCOPE}")
  if [[ -n "$MANAGER_REQUESTED_FEATURES" ]]; then
    for feature in ${(s:,:)MANAGER_REQUESTED_FEATURES}; do
      identifier="$(manager_gui_identifier "$feature")"
      (( ${allowed[(Ie)$identifier]} )) || { print -u2 -r -- "✖ 功能不属于本入口：$feature"; return 2; }
      selected+=("$identifier")
    done
    scope="${(j:,:)selected}"
  fi
  if [[ -f "$entry" ]]; then
    local arguments=(--scope "$scope" --action "${MANAGER_ACTION:-install}" --install-location "$JOBS_FINDER_INSTALL_LOCATION")
    [[ "${JOBS_FINDER_CLEANUP_BUILD_PRODUCTS:-0}" != 1 ]] || arguments+=(--cleanup-build-products)
    (( ! MANAGER_GUI_SESSION )) || arguments+=(--gui-session)
    exec /bin/zsh "$entry" "${arguments[@]}"
  fi
  if [[ ! -f "$helper" ]]; then
    /usr/bin/osascript -e 'display alert "缺少管理面板" message "请保留包含统一功能包的完整 MacOS@Extension 目录。" as critical'
    return 1
  fi
  source "$helper" || return 1
  jobs_launch_finder_manager_gui "${ZSH_ARGZERO:A}" "$scope" "${MANAGER_ACTION:-install}" "$MANAGER_GUI_SESSION"
}
# 后台操作的用途和副作用进入面板日志，不再读取终端输入。
manager_choose_action() {
  manager_intro_line title "━━━━━━━━━━ ${ZSH_ARGZERO:t} ━━━━━━━━━━"
  manager_intro_line body "来源：${MANAGER_ENTRY_DIR}；仅管理当前范围内的 Finder 功能。"
  manager_intro_line body '安装构建并启用菜单；卸载保留未选菜单；清理只删除已安装 App 对应构建产物。'
  return 0
}
# 逐叶回传真实运行状态；不使用无法核实的百分比。
manager_emit_progress() {
  local state="$1" feature="" message="" identifier=""
  case "$state" in
    running)
      case "$MANAGER_ACTION" in
        uninstall) message='正在卸载' ;;
        cleanup) message='正在清理构建产物' ;;
        *) message='正在安装 / 更新' ;;
      esac
      ;;
    succeeded) message='成功' ;;
    failed) message='失败，请查看下方日志' ;;
  esac
  for feature in ${(s:,:)MANAGER_GUI_LEAF_FEATURES}; do
    identifier="$feature"
    case "${MANAGER_ENTRY_DIR:t}" in
      JobsFlutter*) [[ "$identifier" == flutter-* ]] || identifier="flutter-$identifier" ;;
      JobsTerminalOpener)
        case "$identifier" in
          open) identifier=terminal_open ;;
          file-content) identifier=file_content ;;
          file-merge) identifier=file_merge ;;
          file-split) identifier=file_split ;;
          clean-build-artifacts) identifier=clean_build_artifacts ;;
          codegraph-bootstrap) identifier=codegraph_bootstrap ;;
        esac
        ;;
      JobsIOSTools) [[ "$identifier" != ios-pod-install ]] || identifier=pod_install ;;
    esac
    /usr/bin/printf '\nJOBS_MANAGER_EVENT\t%s\t%s\t%s\n' "$identifier" "$state" "$message"
  done
}
# 操作选择即最终确认，分支直接执行对应业务。
manager_main() {
  local manager_status=0
  setopt NO_NOMATCH
  manager_parse_options "$@" || { manager_status=$?; (( manager_status == 10 )) && return 0; return "$manager_status"; }
  if (( ! MANAGER_NON_INTERACTIVE )); then
    manager_open_gui
    return $?
  fi
  manager_choose_action || return $?
  manager_emit_progress running
  manager_execute_operation
  manager_status=$?
  if (( manager_status == 0 )); then
    manager_emit_progress succeeded
  else
    manager_emit_progress failed
  fi
  return "$manager_status"
}
# 校验与业务复用原分支；任何失败保留真实退出码。
manager_execute_operation() {
  if [[ "$MANAGER_ACTION" == cleanup ]]; then
    run_cleanup_operation
    return $?
  fi
  if [[ "$MANAGER_ACTION" == install ]]; then
    run_install_operation
  else
    run_uninstall_operation
  fi
}

# 从本包加载部署函数；独立复制不依赖上级仓库。
manager_load_deployment() {
  local package_root="${MANAGER_ENTRY_DIR:-${ZSH_ARGZERO:A:h:h}}"
  source "$package_root/Scripts/【MacOS】AppDeployment.zsh/【MacOS】AppDeployment.zsh"
}
# 只清理当前宿主的历史构建根，保留已安装 App、功能配置和登记。
manager_cleanup_existing_build_products() {
  manager_load_deployment || return $?
  local built_app=""
  built_app="$(manager_built_application_path)" || return $?
  jobs_deployment_cleanup_existing_build_products "$built_app" "${built_app:h:h:h:h}" com.jobs.JobsRunAuthorizationRevoker JobsRunAuthorizationRevokerFinderSync.appex com.jobs.JobsRunAuthorizationRevoker.FinderSyncExtension
}
# 清理入口不进入共享叶配置校验、安装或卸载分支。
run_cleanup_operation() {
  manager_cleanup_existing_build_products
}
# 总面板可传入它自己的构建产物，但不能改变本包 App 名与身份。
manager_built_application_path() {
  local package_root="${MANAGER_ENTRY_DIR:-${ZSH_ARGZERO:A:h:h}}" built_app=""
  built_app="${JOBS_FINDER_BUILT_APP_PATH:-$package_root/work/DerivedData/Build/Products/Debug/JobsRunAuthorizationRevoker.app}"
  [[ "$built_app" == /* && "${built_app:t}" == JobsRunAuthorizationRevoker.app ]] || return 2
  print -r -- "$built_app"
}
# 构建完成后部署完整 App，再让原登记逻辑使用选中位置。
manager_deploy_built_application() {
  manager_load_deployment || exit $?
  local built_app="$APP_PATH"
  MANAGER_DEPLOYMENT_BUILT_APP_PATH="$built_app"
  jobs_deployment_install "$built_app" com.jobs.JobsRunAuthorizationRevoker JobsRunAuthorizationRevokerFinderSync.appex com.jobs.JobsRunAuthorizationRevoker.FinderSyncExtension || exit $?
  APP_PATH="$(jobs_deployment_app_path "$built_app")" || exit $?
  EXTENSION_PATH="$APP_PATH/Contents/PlugIns/JobsRunAuthorizationRevokerFinderSync.appex"
  jobs_deployment_retire_other_copies "$APP_PATH" com.jobs.JobsRunAuthorizationRevoker JobsRunAuthorizationRevokerFinderSync.appex com.jobs.JobsRunAuthorizationRevoker.FinderSyncExtension || exit $?
}
# 只在安装子 Shell 退出时回滚未提交事务；GUI 或构建失败前不调用未加载的模块。
manager_exit_deployment() {
  local original_result="${1:-$?}"
  (( ! $+functions[jobs_deployment_rollback] )) || jobs_deployment_rollback
  return "$original_result"
}
# 仅在部署提交后清理本包此次 DerivedData；失败只提示，不撤回已安装的 App。
manager_cleanup_build_products() {
  [[ "${JOBS_FINDER_CLEANUP_BUILD_PRODUCTS:-0}" == 1 ]] || return 0
  local package_root="${MANAGER_ENTRY_DIR:-${ZSH_ARGZERO:A:h:h}}"
  if ! jobs_deployment_cleanup_build_products "$MANAGER_DEPLOYMENT_BUILT_APP_PATH" "$package_root/work/DerivedData" com.jobs.JobsRunAuthorizationRevoker JobsRunAuthorizationRevokerFinderSync.appex com.jobs.JobsRunAuthorizationRevoker.FinderSyncExtension; then
    print -u2 -r -- '⚠ App 已安装成功，但清除此轮构建产物失败；已保留应用程序目录中的 App，请查看日志。'
  fi
  return 0
}
# 登记和配置均成功才释放旧 App 备份；退出失败由部署事务恢复。
manager_commit_deployment() {
  jobs_deployment_commit || exit $?
  manager_cleanup_build_products
}
# 精确删除所选位置；不枚举或全局禁用同 ID 的其它副本。
manager_remove_selected_application() {
  if [[ "${JOBS_FINDER_INSTALL_LOCATION:-build}" == applications ]]; then
    jobs_deployment_uninstall "$1" com.jobs.JobsRunAuthorizationRevoker JobsRunAuthorizationRevokerFinderSync.appex com.jobs.JobsRunAuthorizationRevoker.FinderSyncExtension
  else
    jobs_deployment_validate_app "$1" com.jobs.JobsRunAuthorizationRevoker JobsRunAuthorizationRevokerFinderSync.appex com.jobs.JobsRunAuthorizationRevoker.FinderSyncExtension || return $?
    jobs_deployment_unregister_app "$1" JobsRunAuthorizationRevokerFinderSync.appex || return $?
    /bin/rm -r -- "$1"
  fi
}
# 共享叶移除先保留其它配置，最后一叶才删除本次选中位置的 App。
manager_uninstall_selected_application() {
  manager_load_deployment || return $?
  local built_app="" selected_app="" other_enabled=0 config="" configured="" entry="" normalized="" temporary=""
  local allowed=() requested=() remaining=() values=()
  built_app="$(manager_built_application_path)" || return $?
  selected_app="$(jobs_deployment_app_path "$built_app")" || return $?
  if [[ ! -e "$selected_app" && ! -L "$selected_app" ]]; then
    print -r -- "ℹ 所选位置未安装，无需卸载：$selected_app"
    return 0
  fi
  jobs_deployment_validate_app "$selected_app" com.jobs.JobsRunAuthorizationRevoker JobsRunAuthorizationRevokerFinderSync.appex com.jobs.JobsRunAuthorizationRevoker.FinderSyncExtension || return $?
  jobs_deployment_has_other_enabled "$selected_app" com.jobs.JobsRunAuthorizationRevoker.FinderSyncExtension || other_enabled=$?
  (( other_enabled <= 1 )) || return "$other_enabled"
  if (( other_enabled == 0 )); then
    print -r -- 'ℹ 另一位置的副本正在使用；只移除所选副本，保留公共配置。'
    manager_remove_selected_application "$selected_app"
    return $?
  fi
  manager_remove_selected_application "$selected_app" || return $?
  manager_restart_finder 2>/dev/null || true
}

# 原install实现只在所选分支加载，保留可独立复制运行的能力。
run_install_operation() {
(
# EXIT 属于整个安装子 Shell，不能在部署辅助函数返回时提前回滚。
TRAPEXIT() {
  local original_result=$?
  if (( $+functions[manager_exit_deployment] )); then
    manager_exit_deployment "$original_result"
  fi
  return "$original_result"
}
# 脚本自述：
# - 脚本名称：ManageExtension.zsh（App 内部后台管理器）
# - 核心用途：独立构建、注册并启用“移除执行权限”文件右键扩展。
# - 影响范围：只构建本工程、启用固定扩展并刷新 Finder；不修改任何目标文件权限。
# - 运行提示：阅读自述后，直接回车安装；输入任意字符后回车跳过，Ctrl+C 取消。
# shell: zsh
#
#  Scripts/ManageExtension.zsh
#  JobsRunAuthorizationRevoker
#
#  Created by Jobs on 2026年10月24日，星期六.
#

SCRIPT_DIR=""
PROJECT_ROOT=""
LOG_FILE=""
APP_PATH=""
EXTENSION_PATH=""
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
APP_ID="com.jobs.JobsRunAuthorizationRevoker"
EXTENSION_ID="com.jobs.JobsRunAuthorizationRevoker.FinderSyncExtension"
# 计算源码、产物和日志的位置，确认前不写文件。
prepare_display_context() {
  local temporary_root="${TMPDIR:-/tmp}"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")/.." && pwd)"
  PROJECT_ROOT="${SCRIPT_DIR}"
  LOG_FILE="${temporary_root%/}/JobsRunAuthorizationRevokerInstall.log"
  APP_PATH="${PROJECT_ROOT}/work/DerivedData/Build/Products/Debug/JobsRunAuthorizationRevoker.app"
  EXTENSION_PATH="${APP_PATH}/Contents/PlugIns/JobsRunAuthorizationRevokerFinderSync.appex"
}
# 彩色终端突出自述层级，其余环境输出纯文本。
intro_line() {
  local role="$1"
  local message="$2"
  if [[ -t 1 && -n "${TERM:-}" && "${TERM}" != dumb && -z "${NO_COLOR+x}" ]]; then
    if [[ "${role}" == title ]]; then
      /usr/bin/printf '\033[1;31m%s\033[0m\n' "${message}"
    else
      /usr/bin/printf '\033[0;34m%s\033[0m\n' "${message}"
    fi
  else
    print -r -- "${message}"
  fi
}
# 先说明安装范围，再等待回车安装或非空输入跳过。
show_script_intro_and_wait() {
  prepare_display_context
  intro_line title '━━━━━━━━━━ 安装移除执行权限 Finder 扩展 ━━━━━━━━━━'
  intro_line body "1、来源：本地源码 ${PROJECT_ROOT}。"
  intro_line body "2、目标：${APP_PATH}；系统从此处启动扩展，请保留产物。"
  intro_line body '3、影响：构建并启用“移除执行权限”，刷新 Finder；安装时不修改任何目标文件权限。'
  jobs_prompt_output intro_line body '4、运行策略：直接回车安装；输入任意字符后回车跳过。Ctrl+C 取消。'
  intro_line body "5、日志：${LOG_FILE}。"
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '✖ 请在可交互终端运行。'
    exit 1
  fi
  local answer=""
  IFS= read -r "answer?$(jobs_prompt_render '直接回车安装；输入任意字符后回车跳过：')" || exit 0
  [[ -z "${answer}" ]] || exit 0
}
# 确认后开启 zsh 选项与本次日志。
initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  : > "${LOG_FILE}" || exit 1
}
# 将安装结果同时写入终端和日志。
log() {
  print -r -- "$*" | jobs_prompt_tee "${LOG_FILE}"
}
# 验证完整 Xcode 与 SDK，保持现有开发目录配置。
check_environment() {
  [[ "$(/usr/bin/uname -s)" == Darwin ]] || { log '✖ 仅支持 macOS。'; exit 1; }
  [[ -f "${PROJECT_ROOT}/JobsRunAuthorizationRevoker.xcodeproj/project.pbxproj" ]] || { log '✖ 缺少工程源码。'; exit 1; }
  local executable=""
  for executable in /usr/bin/xcodebuild /usr/bin/xcrun /usr/bin/pluginkit /usr/bin/open /usr/bin/killall /usr/bin/codesign /usr/bin/pkill /usr/libexec/PlistBuddy "${LSREGISTER}"; do
    [[ -x "${executable}" ]] || { log "✖ 缺少系统命令：${executable}"; exit 1; }
  done
  /usr/bin/xcodebuild -version 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || { log '✖ 完整 Xcode 不可用，请先完成首次启动。'; exit 1; }
  /usr/bin/xcrun --sdk macosx --show-sdk-path 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || { log '✖ macOS SDK 不可用。'; exit 1; }
}
# 只构建本工程，注册由安装器统一负责。
build_extension() {
  log "来源：本地源码 ${PROJECT_ROOT}"
  log "目标：${APP_PATH}"
  JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1 /usr/bin/xcodebuild \
    -project "${PROJECT_ROOT}/JobsRunAuthorizationRevoker.xcodeproj" \
    -scheme JobsRunAuthorizationRevoker \
    -configuration Debug \
    -destination "platform=macOS,arch=$(/usr/bin/uname -m)" \
    -derivedDataPath "${PROJECT_ROOT}/work/DerivedData" \
    build 2>&1 | /usr/bin/tee -a "${LOG_FILE}"
  local build_result=${pipestatus[1]}
  (( build_result == 0 )) || { log "✖ 构建失败，退出码 ${build_result}。"; exit "${build_result}"; }
  [[ -d "${EXTENSION_PATH}" ]] || { log '✖ 缺少 Finder 扩展产物。'; exit 1; }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP_PATH}/Contents/Info.plist")" == "${APP_ID}" ]] || { log '✖ App 身份不匹配。'; exit 1; }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${EXTENSION_PATH}/Contents/Info.plist")" == "${EXTENSION_ID}" ]] || { log '✖ 扩展身份不匹配。'; exit 1; }
  /usr/bin/codesign --verify --deep --strict "${APP_PATH}" 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || { log '✖ 产物签名验证失败。'; exit 1; }
}
# 按本功能的 Bundle ID 注销旧宿主 URL 登记，保留所有 App 文件。
unregister_previous_hosts() {
  local registered_app=""
  /usr/bin/pkill -x JobsRunAuthorizationRevoker 2>/dev/null || true
  while IFS= read -r registered_app; do
    [[ "${registered_app}" == /*'/JobsRunAuthorizationRevoker.app' && "${registered_app}" != "${APP_PATH}" ]] || continue
    if [[ -e "${registered_app}" ]]; then
      [[ -d "${registered_app}" && ! -L "${registered_app}" ]] || continue
      [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${registered_app}/Contents/Info.plist" 2>/dev/null)" == "${APP_ID}" ]] || continue
    fi
    log "ℹ 注销本宿主旧 URL 登记：${registered_app}"
    "${LSREGISTER}" -u "${registered_app}" 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || exit 1
  done < <("${LSREGISTER}" -dump 2>/dev/null | /usr/bin/awk -v expected="${APP_ID}" '
    function flush() {
      if (identifier == expected && bundle_path != "") print bundle_path
      identifier = ""; bundle_path = ""
    }
    /^--------------------------------------------------------------------------------$/ { flush(); next }
    /^path:[[:space:]]+/ {
      bundle_path = $0
      sub(/^path:[[:space:]]+/, "", bundle_path)
      sub(/[[:space:]]+[(]0x[0-9a-fA-F]+[)].*$/, "", bundle_path)
    }
    /^identifier:[[:space:]]+/ { identifier = $0; sub(/^identifier:[[:space:]]+/, "", identifier) }
    END { flush() }
  ')
}
# 注销同 ID 的旧路径，避免两种安装入口留下多个有效副本。
unregister_previous_copies() {
  local registered_path=""
  while IFS= read -r registered_path; do
    [[ "${registered_path}" == /*'/JobsRunAuthorizationRevoker.app/Contents/PlugIns/JobsRunAuthorizationRevokerFinderSync.appex' ]] || continue
    [[ "${registered_path}" != "${EXTENSION_PATH}" ]] || continue
    if [[ -e "${registered_path}" || -L "${registered_path}" ]]; then
      [[ -d "${registered_path}" && ! -L "${registered_path}" ]] || continue
      [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${registered_path}/Contents/Info.plist" 2>/dev/null)" == "${EXTENSION_ID}" ]] || continue
    fi
    log "ℹ 注销本扩展旧副本：${registered_path}"
    /usr/bin/pluginkit -r "${registered_path}" 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || exit 1
  done < <(/usr/bin/pluginkit -m -i "${EXTENSION_ID}" -A -D -vv 2>/dev/null | /usr/bin/awk '/Path = / { sub(/^.*Path = /, ""); print }')
}
# 注册固定扩展并初始化宿主，首次使用时由系统处理权限。
register_extension() {
  unregister_previous_copies
  unregister_previous_hosts
  "${LSREGISTER}" -f "${APP_PATH}" 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || { log '✖ 宿主 URL 注册失败。'; exit 1; }
  /usr/bin/pluginkit -a "${EXTENSION_PATH}" 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || exit 1
  /usr/bin/pluginkit -e use -i "${EXTENSION_ID}" 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || exit 1
  /usr/bin/open -n "${APP_PATH}" --args --initialize-finder-extension || { log '✖ 无法初始化宿主。'; exit 1; }
  manager_restart_finder 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || log 'ℹ Finder 当前未运行。'
  log '✔ 已请求启用扩展。只选中一个普通文件后右键，选择“移除执行权限”。'
  log 'ℹ 菜单未出现时，在系统设置的 Finder 扩展中启用 JobsRunAuthorizationRevoker；首次操作允许控制 Terminal。'
}
# 编排确认、自检、构建与扩展注册。
main() {
  show_script_intro_and_wait # 先说明源码、产物、影响及取消方式。
  initialize_runtime # 确认后准备本次运行日志。
  check_environment # 核验完整开发工具链与工程。
  build_extension # 独立构建并验证 App 身份和签名。
  manager_deploy_built_application # 把完整 App 部署至本次选择的位置，失败保留原安装。
  register_extension # 注册固定扩展并刷新文件菜单。
  manager_commit_deployment # 登记成功后提交部署事务。
}


# 外层统一负责交互；这里仅准备原分支的展示路径与经过验证的功能参数。
show_script_intro_and_wait() {
  (( $+functions[prepare_display_context] )) && prepare_display_context
  return 0
}
main "$@"
)
}

# 原uninstall实现只在所选分支加载，保留可独立复制运行的能力。
run_uninstall_operation() {
(
# 脚本自述：
# - 脚本名称：ManageExtension.zsh（App 内部后台管理器）
# - 核心用途：禁用并注销 JobsRunAuthorizationRevoker 的 Finder 扩展，移除已登记的本应用构建产物。
# - 影响范围：仅处理固定 Bundle ID，保留项目源码和所有曾授权的文件；确认后重启 Finder。
# - 运行提示：先阅读内置自述并按回车，再核对路径并输入 YES；其它输入取消。
# shell: zsh
#
#  Scripts/ManageExtension.zsh
#  JobsRunAuthorizationRevoker
#
#  Created by Jobs on 2026年10月24日，星期六.
#

SCRIPT_DIR=""
SCRIPT_PATH=""
SCRIPT_BASENAME=""
LOG_FILE=""
EXTENSION_ID="com.jobs.JobsRunAuthorizationRevoker.FinderSyncExtension"
APP_ID="com.jobs.JobsRunAuthorizationRevoker"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
EXTENSION_PATHS=()
APP_PATHS=()
# 准备显示路径，不写日志或修改扩展状态。
prepare_display_context() {
  local temporary_root="${TMPDIR:-/tmp}"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")/.." && pwd)"
  SCRIPT_PATH="${ZSH_ARGZERO:A}"
  SCRIPT_BASENAME="【MacOS】管理解除运行授权Finder扩展"
  LOG_FILE="${temporary_root%/}/${SCRIPT_BASENAME}.log"
}
# 为交互终端显示红色标题和蓝色正文，其它输出保持纯文本。
intro_line() {
  local role="$1"
  local message="$2"
  if [[ -t 1 && -n "${TERM:-}" && "${TERM}" != dumb && -z "${NO_COLOR+x}" ]]; then
    if [[ "${role}" == title ]]; then
      /usr/bin/printf '\033[1;31m%s\033[0m\n' "${message}"
    else
      /usr/bin/printf '\033[0;34m%s\033[0m\n' "${message}"
    fi
  else
    print -r -- "${message}"
  fi
}
# 先展示固定自述，再等待用户确认阅读，避免误触卸载。
show_script_intro_and_wait() {
  prepare_display_context
  intro_line title "================ Scripts/ManageExtension.zsh ================"
  intro_line body "1、核心用途：禁用、注销‘移除执行权限’右键菜单。"
  intro_line body "2、影响范围：只删除 Bundle ID 为 ${APP_ID} 的已登记 App；保留源码和所有曾授权的文件。"
  jobs_prompt_output intro_line body "3、执行策略：回车后先显示待处理路径；输入 YES 才卸载并重启 Finder，其它输入取消。"
  intro_line body "4、取消方式：按 Ctrl+C；非交互输入会退出。"
  intro_line body "5、日志位置：${LOG_FILE}"
  if [[ ! -t 0 ]]; then
    intro_line body "错误：没有可交互输入，请在终端中执行。"
    exit 1
  fi
  read -r "?$(jobs_prompt_render '已了解用途，按回车查看待卸载路径；Ctrl+C 取消：')" _ || exit 0
}
# 用户确认阅读后初始化日志及 zsh 选项。
initialize_runtime() {
  setopt NO_NOMATCH
  setopt PIPE_FAIL
  : > "${LOG_FILE}"
}
# 同步输出到终端和本次运行日志。
log() {
  print -r -- "$1" | jobs_prompt_tee "${LOG_FILE}"
}
# 检查本次卸载需要的系统工具。
check_environment() {
  local executable=""
  [[ "$(/usr/bin/uname -s)" == Darwin ]] || { log '错误：仅支持 macOS。'; exit 1; }
  for executable in /usr/bin/pluginkit /usr/libexec/PlistBuddy /usr/bin/awk /usr/bin/pkill /usr/bin/killall /bin/rm "${LSREGISTER}"; do
    [[ -x "${executable}" ]] || { log "错误：缺少 ${executable}"; exit 1; }
  done
}
# 精确核对 App 名称、真实目录和 Bundle ID，避免删除其它应用。
is_owned_app() {
  local candidate="$1"
  [[ "${candidate}" == /* && "${candidate:t}" == 'JobsRunAuthorizationRevoker.app' && -d "${candidate}" && ! -L "${candidate}" ]] || return 1
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${candidate}/Contents/Info.plist" 2>/dev/null)" == "${APP_ID}" ]]
}
# 从固定扩展的系统注册信息收集路径，展示给用户核对。
collect_registered_paths() {
  local extension_path=""
  local app_path=""
  while IFS= read -r extension_path; do
    [[ "${extension_path}" == /*'/JobsRunAuthorizationRevoker.app/Contents/PlugIns/JobsRunAuthorizationRevokerFinderSync.appex' ]] || continue
    if [[ -e "${extension_path}" || -L "${extension_path}" ]]; then
      [[ -d "${extension_path}" && ! -L "${extension_path}" ]] || continue
      [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${extension_path}/Contents/Info.plist" 2>/dev/null)" == "${EXTENSION_ID}" ]] || continue
    fi
    EXTENSION_PATHS+=("${extension_path}")
    app_path="${extension_path%/Contents/PlugIns/JobsRunAuthorizationRevokerFinderSync.appex}"
    if is_owned_app "${app_path}" && (( ! ${APP_PATHS[(Ie)${app_path}]} )); then
      APP_PATHS+=("${app_path}")
    fi
  done < <(/usr/bin/pluginkit -m -i "${EXTENSION_ID}" -A -D -vv 2>/dev/null | /usr/bin/awk '/Path = / { sub(/^.*Path = /, ""); print }')
  log "扩展 ID：${EXTENSION_ID}"
  for extension_path in "${EXTENSION_PATHS[@]}"; do
    log "注销路径：${extension_path}"
  done
  for app_path in "${APP_PATHS[@]}"; do
    log "删除已核验 App：${app_path}"
  done
  if (( ${#EXTENSION_PATHS[@]} == 0 )); then
    log '没有发现已登记副本；仅清除扩展启用状态并刷新 Finder。'
  fi
}
# 删除 App 和重启 Finder 之前要求明确输入 YES。
confirm_uninstall() {
  local answer=""
  IFS= read -r 'answer?输入 YES 卸载上述固定扩展并重启 Finder，其它输入取消：' || exit 0
  if [[ "${answer}" != YES ]]; then
    log '已取消，没有修改应用或扩展注册。'
    exit 0
  fi
}
# 停用并注销指定扩展，只移除二次核验通过的自有 App。
uninstall_extension() {
  local extension_path=""
  local app_path=""
  /usr/bin/pluginkit -e ignore -i "${EXTENSION_ID}" 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || log '提示：扩展可能已经停用或未安装。'
  /usr/bin/pkill -x 'JobsRunAuthorizationRevoker' 2>/dev/null || true
  /usr/bin/pkill -x 'JobsRunAuthorizationRevokerFinderSync' 2>/dev/null || true
  for extension_path in "${EXTENSION_PATHS[@]}"; do
    /usr/bin/pluginkit -r "${extension_path}" 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || { log "错误：注销失败 ${extension_path}"; exit 1; }
  done
  for app_path in "${APP_PATHS[@]}"; do
    is_owned_app "${app_path}" || { log "错误：App 核验发生变化，停止删除 ${app_path}"; exit 1; }
    "${LSREGISTER}" -u "${app_path}" 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || { log "错误：宿主 URL 注销失败 ${app_path}"; exit 1; }
    /bin/rm -rf -- "${app_path}" || { log "错误：删除失败 ${app_path}"; exit 1; }
  done
  /bin/rm -f -- '/tmp/JobsRunAuthorizationRevokerNeedsFinderRestart'
  log '固定 Finder 扩展已停用；项目源码与所有曾授权的文件保留。'
}
# 刷新 Finder 使已卸载菜单退出显示。
refresh_finder() {
  manager_restart_finder 2>&1 | /usr/bin/tee -a "${LOG_FILE}" || log '提示：Finder 当前没有运行，无需重启。'
  log "卸载完成，日志：${LOG_FILE}"
}
# 编排自述、核验、明确确认和卸载。
main() {
  show_script_intro_and_wait # 先展示内置自述并等待阅读确认。
  initialize_runtime # 确认阅读后初始化选项和日志。
  check_environment # 检查系统和卸载命令。
  collect_registered_paths # 收集并显示固定扩展的真实注册路径。
  confirm_uninstall # 删除 App 及重启 Finder 前要求输入 YES。
  uninstall_extension # 精确注销扩展并清理核验通过的 App。
  refresh_finder # 刷新 Finder 并显示日志位置。
}


# 外层统一负责交互；卸载只进入所选位置实现，旧全副本枚举不参与本次管理。
manager_uninstall_selected_application
)
}

manager_main "$@"
