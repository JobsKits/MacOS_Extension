#!/bin/zsh
# 脚本自述：
# - 脚本名称：CreateIOSSimulator.zsh。
# - 核心用途：先选本机完整 iPhone / iPad 型号，再选已安装的 iOS Runtime，创建并启动新模拟器。
# - 影响范围：只新增一个模拟器并打开 Simulator，不关闭、删除或重置已有设备，不安装工具或 Runtime。
# - 运行提示：先阅读自述并回车；选择时可取消，最终回车才创建；--help / --check 为只读入口。

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

# >>> Jobs iOS simulator core >>>
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

typeset SCRIPT_DIR=""
typeset SCRIPT_PATH=""
typeset SCRIPT_BASENAME=""
typeset LOG_FILE=""
typeset SIM_MODE="interactive"
typeset SIM_RUN_DIR=""
typeset SIM_ACTIVE_PID=""
typeset SIM_DEVELOPER_DIR=""
typeset SIM_APP=""
typeset SIM_APP_KIND=""
typeset SIM_FZF=""
typeset SIM_SELECTED_ROW=""
typeset SIM_RUNTIME_ID=""
typeset SIM_RUNTIME_NAME=""
typeset SIM_DEVICE_ID=""
typeset SIM_DEVICE_NAME=""
typeset SIM_NAME=""
typeset SIM_UDID=""
typeset SIM_LOG_READY=0
typeset SIM_CANCELLED=0
typeset -a SIM_ROWS

# 仅设置进程内选项、路径及纯文本 / 彩色展示条件。
sim_prepare_context() {
    setopt NO_NOMATCH PIPE_FAIL
    SCRIPT_PATH="${ZSH_ARGZERO:A}"
    SCRIPT_DIR="${SCRIPT_PATH:h}"
    SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
    LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.$$.log"
}
# 同步显示与日志；磁盘日志始终保持纯文本。
sim_log() {
    print -r -- "$1"
    if [[ "$SIM_LOG_READY" == 1 ]]; then
        print -r -- "$1" >> "$LOG_FILE"
    fi
}
# 按 Jobs 标准显示自述，非完整终端自动降级为纯文本。
sim_intro_line() {
    local role="$1" message="$2"
    if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" ]]; then
        if [[ "$role" == title ]]; then
            printf '\033[1;31m%s\033[0m\n' "$message"
        else
            printf '\033[0;34m%s\033[0m\n' "$message"
        fi
    else
        print -r -- "$message"
    fi
}
# 在任何真实动作前解析只读入口，并对交互入口完成终端检查和首次确认。
sim_confirm_entry() {
    case "$#:${1:-}" in
        0:) SIM_MODE=interactive ;;
        1:--help|1:-h) SIM_MODE=help; return 0 ;;
        1:--check) SIM_MODE=check; return 0 ;;
        *) sim_log '✖ 参数无效。使用 --help 查看说明。'; exit 64 ;;
    esac
    if [[ ! -t 0 || ! -t 1 ]]; then
        sim_log '✖ 当前没有可交互终端，请通过 Finder 入口或 Terminal 运行；不会创建模拟器。'
        exit 1
    fi
    local answer=""
    IFS= read -r "?$(jobs_prompt_render "已了解影响，直接回车继续；输入任意字符取消：")" answer || exit 130
    if [[ -n "$answer" ]]; then
        sim_log '➤ 已取消，未创建模拟器。'
        exit 0
    fi
}
# 清理本次私有临时文件，不触碰 CoreSimulator 或其它会话。
sim_cleanup() {
    if [[ -n "$SIM_ACTIVE_PID" ]]; then
        kill -TERM "$SIM_ACTIVE_PID" 2>/dev/null
        /bin/sleep 0.2
        kill -KILL "$SIM_ACTIVE_PID" 2>/dev/null
        wait "$SIM_ACTIVE_PID" 2>/dev/null
        SIM_ACTIVE_PID=""
    fi
    if [[ -n "$SIM_RUN_DIR" && -d "$SIM_RUN_DIR" ]]; then
        /bin/rm -f -- "$SIM_RUN_DIR"/runtimes.json "$SIM_RUN_DIR"/devicetypes.json "$SIM_RUN_DIR"/devices.json "$SIM_RUN_DIR"/command.out
        /bin/rmdir -- "$SIM_RUN_DIR" 2>/dev/null
    fi
}
# 中断只停止当前命令，已创建的设备保留，并显示可追踪的 UDID。
sim_handle_signal() {
    sim_log '⚠ 已停止当前操作。'
    if [[ -n "$SIM_UDID" ]]; then
        sim_log "➤ 新设备已保留：${SIM_NAME}（${SIM_UDID}）。可在 Simulator 中继续启动。"
    fi
    exit 130
}
# zsh 在脚本退出时清理；顶层特殊函数避免函数内部 EXIT trap 提前清理目录。
TRAPEXIT() {
    sim_cleanup
}
# 将终端中断转为有提示的安全停止。
TRAPINT() {
    sim_handle_signal
}
# 关闭终端时保留已创建的设备并停止当前命令。
TRAPHUP() {
    sim_handle_signal
}
# 外部终止遵循相同的保留设备策略。
TRAPTERM() {
    sim_handle_signal
}
# 确认后准备私有临时目录；只读体检仅使用临时快照，不保留日志。
sim_initialize_runtime() {
    local old_umask="$(umask)"
    umask 077
    SIM_RUN_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.XXXXXX")" || exit 1
    if [[ "$SIM_MODE" == interactive ]]; then
        if ! (setopt NO_CLOBBER; : > "$LOG_FILE") 2>/dev/null; then
            sim_log "✖ 无法安全创建日志：${LOG_FILE}"
            /bin/rmdir -- "$SIM_RUN_DIR"
            exit 1
        fi
        SIM_LOG_READY=1
    fi
    umask "$old_umask"
    if [[ "$SIM_MODE" == interactive ]]; then
        sim_log "➤ 创建阶段：只新增模拟器；保留现有设备。日志：${LOG_FILE}"
    else
        sim_log '➤ 操作：只读检查，临时快照退出时清理，不创建日志。'
    fi
}
# 以有限等待运行指定命令，超时停止本次进程，保留输出供错误定位。
sim_run_to_file() {
    local output="$1" limit="$2"
    shift 2
    local ticks=0 result=0
    "$@" > "$output" 2>&1 &
    SIM_ACTIVE_PID=$!
    while kill -0 "$SIM_ACTIVE_PID" 2>/dev/null; do
        if (( ticks >= limit * 10 )); then
            kill -TERM "$SIM_ACTIVE_PID" 2>/dev/null
            /bin/sleep 0.2
            kill -KILL "$SIM_ACTIVE_PID" 2>/dev/null
            wait "$SIM_ACTIVE_PID" 2>/dev/null
            SIM_ACTIVE_PID=""
            sim_log "✖ 命令等待超过 ${limit} 秒：$*"
            return 124
        fi
        /bin/sleep 0.1
        (( ticks += 1 ))
    done
    wait "$SIM_ACTIVE_PID" || result=$?
    SIM_ACTIVE_PID=""
    return "$result"
}
# 使用系统 JXA 解析 simctl JSON，避免依赖 Homebrew、Python 或 jq。
sim_data() {
    /usr/bin/osascript -l JavaScript - "$@" <<'JXA'
ObjC.import('Foundation');
function run(args) {
    function json(path) {
        var data = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
        if (!data) throw Error('无法读取模拟器快照：' + path);
        return JSON.parse(ObjC.unwrap(data));
    }
    function text(value) {
        if (typeof value !== 'string' || !value || /[\x00-\x1f\x7f]/.test(value)) throw Error('模拟器字段无效或包含控制字符');
        return value;
    }
    function id(value, prefix) {
        if (!text(value).startsWith(prefix) || !/^[A-Za-z0-9._-]+$/.test(value)) throw Error('模拟器标识格式无效');
        return value;
    }
    function version(value) {
        if (typeof value !== 'string' || !/^\d+(?:\.\d+){0,2}$/.test(value)) throw Error('系统版本格式无效');
        var parts = value.split('.').map(Number);
        while (parts.length < 3) parts.push(0);
        return parts[0] * 65536 + parts[1] * 256 + parts[2];
    }
    function runtimeList(path) {
        var value = json(path);
        if (!value || !Array.isArray(value.runtimes)) throw Error('Runtime JSON 缺少 runtimes 数组');
        return value.runtimes;
    }
    function deviceList(path) {
        var value = json(path);
        if (!value || !Array.isArray(value.devicetypes)) throw Error('设备 JSON 缺少 devicetypes 数组');
        return value.devicetypes;
    }
    function availableRuntimes(path, arch) {
        var seen = Object.create(null), seenIDs = Object.create(null), rows = [];
        runtimeList(path).forEach(function (entry) {
            if (entry.isAvailable !== true || !/^com\.apple\.CoreSimulator\.SimRuntime\.iOS-/.test(entry.identifier || '')) return;
            if (Array.isArray(entry.supportedArchitectures) && entry.supportedArchitectures.indexOf(arch) < 0) return;
            var name = text(entry.name), identifier = id(entry.identifier, 'com.apple.CoreSimulator.SimRuntime.iOS-');
            var value = version(entry.version);
            if (seen[name] || seenIDs[identifier]) return;
            seen[name] = true;
            seenIDs[identifier] = true;
            rows.push({name:name, id:identifier, value:value, entry:entry});
        });
        rows.sort(function (a,b) { return b.value - a.value || a.name.localeCompare(b.name); });
        return rows;
    }
    function namedDevices(path) {
        var seen = Object.create(null), rows = [];
        deviceList(path).forEach(function (device) {
            if (!/^iPhone |^iPad /.test(device.name || '')) return;
            var identifier = id(device.identifier, 'com.apple.CoreSimulator.SimDeviceType.'), name = text(device.name);
            if (seen[identifier]) return;
            seen[identifier] = true;
            rows.push({name:name, id:identifier, entry:device});
        });
        return rows;
    }
    function runtimeBound(device, prefix) {
        var value = device[prefix + 'RuntimeVersion'];
        if (typeof value === 'number' && isFinite(value) && value >= 0 && Math.floor(value) === value) return value;
        value = device[prefix + 'RuntimeVersionString'];
        return typeof value === 'string' && /^\d+(?:\.\d+){0,2}$/.test(value) ? version(value) : null;
    }
    // 有效标识白名单；字段缺失或为空数组时没有结论，返回 null 交给版本范围判断。
    function supportIdentifiers(runtime) {
        var supported = runtime.entry.supportedDeviceTypes;
        if (!Array.isArray(supported) || supported.length === 0) return null;
        return supported.map(function (entry) {
            var identifier = typeof entry === 'string' ? entry : entry && entry.identifier;
            return typeof identifier === 'string' && /^com\.apple\.CoreSimulator\.SimDeviceType\.[A-Za-z0-9._-]+$/.test(identifier) ? identifier : null;
        });
    }
    // 只排除有明确依据的组合；缺失或不完整的兼容元数据保留为未知。
    function compatibility(device, runtime) {
        var identifiers = supportIdentifiers(runtime);
        if (identifiers) {
            if (identifiers.indexOf(device.id) >= 0) return 2;
            if (identifiers.every(function (identifier) { return identifier !== null; })) return 0;
        }
        var minimum = runtimeBound(device.entry, 'min'), maximum = runtimeBound(device.entry, 'max');
        if (minimum !== null && maximum !== null && minimum > maximum) return 1;
        if (minimum !== null && runtime.value < minimum) return 0;
        if (maximum !== null && runtime.value > maximum) return 0;
        return 1;
    }
    if (args[0] === 'health') return 'jxa-ready';
    if (args[0] === 'app') {
        var appPath = text(args[1]), bundle = $.NSBundle.bundleWithPath(appPath);
        var bundleID = ObjC.unwrap(bundle.bundleIdentifier);
        if (bundleID !== 'com.apple.iphonesimulator' && bundleID !== 'com.apple.dt.Devices') throw Error('模拟器应用 Bundle ID 无效');
        var executable = ObjC.unwrap(bundle.executablePath);
        if (!executable || !$.NSFileManager.defaultManager.isExecutableFileAtPath(executable)) throw Error('模拟器应用可执行文件缺失');
        return bundleID;
    }
    if (args[0] === 'runtimes') {
        return availableRuntimes(args[1], args[2]).map(function (row) { return row.name + '\t' + row.id; }).join('\n');
    }
    if (args[0] === 'devicetypes') {
        return namedDevices(args[1]).map(function (row) { return row.name + '\t' + row.id; }).join('\n');
    }
    if (args[0] === 'preferred-devicetypes') {
        var devices = namedDevices(args[1]), runtimes = availableRuntimes(args[2], args[3]);
        devices.forEach(function (device, index) {
            device.order = index;
            device.rank = runtimes.reduce(function (rank, runtime) { return Math.max(rank, compatibility(device, runtime)); }, 0);
        });
        devices.sort(function (a,b) { return b.rank - a.rank || a.order - b.order; });
        // 无可搭配系统的型号永远走不到命名与创建，标注不会污染设备名。
        return devices.map(function (row) { return (row.rank === 0 ? row.name + '（本机无可搭配系统）' : row.name) + '\t' + row.id; }).join('\n');
    }
    if (args[0] === 'compatible-runtimes') {
        var selectedID = id(args[4], 'com.apple.CoreSimulator.SimDeviceType.');
        var devices = namedDevices(args[3]).filter(function (device) { return device.id === selectedID; });
        if (devices.length !== 1) throw Error('所选型号不属于当前设备清单');
        var runtimes = availableRuntimes(args[1], args[2]);
        runtimes.forEach(function (runtime) { runtime.rank = compatibility(devices[0], runtime); });
        runtimes = runtimes.filter(function (runtime) { return runtime.rank > 0; });
        runtimes.sort(function (a,b) { return b.rank - a.rank || b.value - a.value || a.name.localeCompare(b.name); });
        // 系统名只用于展示与日志，标注不会进入 simctl create 的参数。
        return runtimes.map(function (row) { return (row.rank === 2 ? row.name : row.name + '（未确认支持）') + '\t' + row.id; }).join('\n');
    }
    if (args[0] === 'catalog-summary') {
        var summaryDevices = namedDevices(args[1]), summaryRuntimes = availableRuntimes(args[2], args[3]);
        summaryDevices.forEach(function (device) {
            device.rank = summaryRuntimes.reduce(function (rank, runtime) { return Math.max(rank, compatibility(device, runtime)); }, 0);
        });
        var matched = summaryDevices.filter(function (device) { return device.rank > 0; }).length;
        var lines = ['models\t' + summaryDevices.length + '\t' + matched + '\t' + (summaryDevices.length - matched)];
        summaryRuntimes.forEach(function (runtime) {
            var identifiers = supportIdentifiers(runtime), count = -1;
            if (identifiers && identifiers.every(function (identifier) { return identifier !== null; })) {
                count = summaryDevices.filter(function (device) { return identifiers.indexOf(device.id) >= 0; }).length;
            }
            lines.push('runtime\t' + runtime.name + '\t' + count);
        });
        return lines.join('\n');
    }
    if (args[0] === 'unique-name') {
        var payload = json(args[1]), names = Object.create(null), base = text(args[2]);
        if (!payload || !payload.devices || Array.isArray(payload.devices) || typeof payload.devices !== 'object') throw Error('已有设备 JSON 缺少 devices 对象');
        Object.keys(payload.devices).forEach(function (runtime) {
            if (!Array.isArray(payload.devices[runtime])) throw Error('已有设备 JSON 格式无效');
            payload.devices[runtime].forEach(function (device) { names[text(device.name)] = true; });
        });
        var name = base, suffix = 2;
        while (names[name]) name = base + ' (' + suffix++ + ')';
        return name;
    }
    throw Error('未知数据操作');
}
JXA
}
# 体检当前 Xcode 工具链及系统解析器，不变更 xcode-select 或安装任何依赖。
sim_check_environment() {
    local output="$SIM_RUN_DIR/command.out" simctl_path="" jxa_health="" candidate="" app_kind=""
    if [[ "$(/usr/bin/uname -s)" != Darwin ]]; then
        sim_log '✖ 此脚本仅适用于 macOS。'
        return 1
    fi
    if ! sim_run_to_file "$output" 20 /usr/bin/xcrun --find simctl; then
        sim_log '✖ xcrun 无法定位 simctl。请安装完整 Xcode，完成首次启动与组件安装。'
        sim_log "$(<"$output")"
        return 1
    fi
    simctl_path="$(<"$output")"
    if [[ ! -x "$simctl_path" || "$simctl_path" != */usr/bin/simctl ]]; then
        sim_log "✖ simctl 路径不可执行：${simctl_path}"
        return 1
    fi
    SIM_DEVELOPER_DIR="${simctl_path%/usr/bin/simctl}"
    if ! jxa_health="$(sim_data health 2>&1)" || [[ "$jxa_health" != jxa-ready ]]; then
        sim_log "✖ 系统 JavaScript for Automation 不可用：${jxa_health}"
        return 1
    fi
    SIM_APP=""
    SIM_APP_KIND=""
    for candidate in "$SIM_DEVELOPER_DIR/Applications/Simulator.app" "${SIM_DEVELOPER_DIR:h}/Applications/Simulator.app" "${SIM_DEVELOPER_DIR:h}/Applications/DeviceHub.app"; do
        [[ -d "$candidate" ]] || continue
        if app_kind="$(sim_data app "$candidate" 2>&1)"; then
            SIM_APP="$candidate"
            SIM_APP_KIND="$app_kind"
            break
        fi
    done
    if [[ -z "$SIM_APP" ]]; then
        sim_log "✖ 当前 Xcode 缺少健康的 Simulator / Device Hub：${SIM_DEVELOPER_DIR}"
        return 1
    fi
    sim_log "✔ 当前 Xcode 工具链：${SIM_DEVELOPER_DIR}"
}
# 单独复检选择器，独立入口安装依赖后即可刷新而不重复体检 Xcode。
sim_check_selector() {
    local output="$SIM_RUN_DIR/command.out"
    SIM_FZF="$(command -v fzf 2>/dev/null)"
    if [[ -n "$SIM_FZF" ]]; then
        if ! sim_run_to_file "$output" 5 "$SIM_FZF" --version; then
            SIM_FZF=""
        fi
    fi
    if [[ -n "$SIM_FZF" ]]; then
        sim_log '➤ 选择方式：本机健康 fzf（系统版本按 ← 返回型号，Esc 取消）。'
    else
        sim_log '✖ fzf 缺失或不可用，已停止交互选择；请先运行独立入口的依赖自检，或修复 fzf 后重试。'
        return 1
    fi
}
# 获取结构化清单，任一命令失败都停止，不把错误文本当作设备数据。
sim_load_catalog() {
    local kind="" file=""
    for kind in runtimes devicetypes devices; do
        file="$SIM_RUN_DIR/${kind}.json"
        if ! sim_run_to_file "$file" 30 /usr/bin/xcrun simctl list "$kind" --json; then
            sim_log "✖ 读取模拟器清单失败：xcrun simctl list ${kind} --json"
            sim_log "$(<"$file")"
            return 1
        fi
    done
}
# 选择真实清单行；子层用左键返回，取消与选择器失败分别传播。
sim_choose_row() {
    local title="$1" content="$2" allow_back="${3:-0}" result=0 output="" key=""
    local -a picker_args
    SIM_SELECTED_ROW=""
    SIM_ROWS=("${(@f)content}")
    if [[ -z "$content" || ${#SIM_ROWS} == 0 ]]; then
        return 2
    fi
    sim_log "➤ ${title}"
    [[ -n "$SIM_FZF" ]] || sim_check_selector || return $?
    picker_args=(--delimiter=$'\t' --with-nth=1 --height=60% --reverse --prompt="${title} > " --header='回车确认；Esc / Ctrl+C 取消')
    if (( allow_back )); then
        picker_args+=(--expect=left --header='← 返回型号选择；回车确认；Esc / Ctrl+C 取消')
    fi
    output="$(print -rl -- "${SIM_ROWS[@]}" | /usr/bin/env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_OPTS_FILE "$SIM_FZF" "${picker_args[@]}")" || result=$?
    if (( allow_back && (result == 0 || result == 1) )) && [[ "${output%%$'\n'*}" == left ]]; then
        return 10
    fi
    if (( result == 130 || result == 1 )); then
        SIM_CANCELLED=1
        return 130
    fi
    if (( result != 0 )); then
        sim_log "✖ 选择器执行失败（退出码 ${result}），未创建模拟器。"
        return "$result"
    fi
    if (( allow_back )); then
        key="${output%%$'\n'*}"
        [[ "$key" == left ]] && return 10
        [[ -z "$key" ]] || return 1
        [[ "$output" == *$'\n'* ]] || return 1
        output="${output#*$'\n'}"
    fi
    SIM_SELECTED_ROW="$output"
    if [[ -z "$SIM_SELECTED_ROW" ]]; then
        SIM_CANCELLED=1
        return 130
    fi
    if (( ${SIM_ROWS[(Ie)$SIM_SELECTED_ROW]} == 0 )); then
        sim_log '✖ 选择结果不属于当前清单，已停止。'
        return 1
    fi
}
# 保留完整型号并优先推荐可搭配已装系统的型号，选定后只列匹配该型号的系统。
sim_select_combination() {
    local devices="" runtimes="" total=0 matched=0 result=0
    local -a all_rows matched_rows
    if ! devices="$(sim_data preferred-devicetypes "$SIM_RUN_DIR/devicetypes.json" "$SIM_RUN_DIR/runtimes.json" "$(/usr/bin/uname -m)" 2>&1)"; then
        sim_log "✖ 无法解析设备型号：${devices}"
        return 1
    fi
    if [[ -z "$devices" ]]; then
        sim_log '✖ 当前 Xcode 没有 iPhone / iPad 设备类型，请检查 Xcode 组件后重试。'
        return 1
    fi
    if ! runtimes="$(sim_data runtimes "$SIM_RUN_DIR/runtimes.json" "$(/usr/bin/uname -m)" 2>&1)"; then
        sim_log "✖ 无法解析 Runtime：${runtimes}"
        return 1
    fi
    if [[ -z "$runtimes" ]]; then
        sim_log '✖ 没有本机可用的 iOS Runtime。请在 Xcode → Settings → Components 安装后重试。'
        return 1
    fi
    all_rows=("${(@f)runtimes}")
    total=${#all_rows}
    while true; do
        sim_choose_row '选择 iPhone / iPad 型号' "$devices" || return $?
        SIM_DEVICE_NAME="${SIM_SELECTED_ROW%%$'\t'*}"
        SIM_DEVICE_ID="${SIM_SELECTED_ROW#*$'\t'}"
        if ! runtimes="$(sim_data compatible-runtimes "$SIM_RUN_DIR/runtimes.json" "$(/usr/bin/uname -m)" "$SIM_RUN_DIR/devicetypes.json" "$SIM_DEVICE_ID" 2>&1)"; then
            sim_log "✖ 无法匹配所选型号的系统：${runtimes}"
            return 1
        fi
        if [[ -z "$runtimes" ]]; then
            sim_log "✖ ${SIM_DEVICE_NAME} 没有可搭配的已安装 iOS 系统：本机 ${total} 个已装 iOS 系统都不支持该型号。"
            sim_log '➤ 请在 Xcode 安装该型号可用的 Runtime，或重新选择其它型号；未创建模拟器。'
            return 2
        fi
        matched_rows=("${(@f)runtimes}")
        matched=${#matched_rows}
        # 明确列出匹配数量，避免把本机全部系统当成该型号的可选项。
        sim_log "➤ ${SIM_DEVICE_NAME}：本机已装 ${total} 个 iOS 系统，其中 ${matched} 个匹配该型号。"
        if (( total > matched )); then
            sim_log "➤ 已排除 $(( total - matched )) 个不支持该型号的已装系统，未被 Xcode 明确列出的系统标注为“（未确认支持）”。"
        fi
        jobs_prompt_output sim_log '➤ 已确认支持的最新系统排首位，回车采用首项。'
        result=0
        sim_choose_row '选择 iOS 系统版本' "$runtimes" 1 || result=$?
        if (( result == 10 )); then
            SIM_RUNTIME_NAME=""
            SIM_RUNTIME_ID=""
            sim_log '↩ 已返回型号选择，未创建模拟器。'
            continue
        fi
        (( result == 0 )) || return "$result"
        SIM_RUNTIME_NAME="${SIM_SELECTED_ROW%%$'\t'*}"
        SIM_RUNTIME_ID="${SIM_SELECTED_ROW#*$'\t'}"
        return 0
    done
}
# 创建前刷新已有名称，避开同秒操作或遗留同名设备。
sim_prepare_unique_name() {
    local base="${SIM_DEVICE_NAME}@$(/bin/date '+%Y.%m.%d %H:%M:%S')-${$}" output=""
    if ! sim_run_to_file "$SIM_RUN_DIR/devices.json" 30 /usr/bin/xcrun simctl list devices --json; then
        sim_log '✖ 刷新已有设备失败，已停止创建。'
        sim_log "$(<"$SIM_RUN_DIR/devices.json")"
        return 1
    fi
    if ! output="$(sim_data unique-name "$SIM_RUN_DIR/devices.json" "$base" 2>&1)"; then
        sim_log "✖ 无法确认唯一设备名：${output}"
        return 1
    fi
    SIM_NAME="$output"
}
# 明确展示即将创建的组合；任意非空输入都取消。
sim_confirm_creation() {
    local answer=""
    sim_log "➤ 设备：${SIM_DEVICE_NAME}"
    sim_log "➤ 系统：${SIM_RUNTIME_NAME}"
    sim_log "➤ 新名称：${SIM_NAME}"
    if [[ "$SIM_RUNTIME_NAME" == *未确认支持* ]]; then
        sim_log '⚠ 所选系统未被 Xcode 明确列为支持该型号，创建可能失败；失败时输入 r 可重新选择。'
    fi
    sim_log '➤ 型号与系统分别列出，组合是否受支持由 Xcode 创建命令最终校验；不支持时需输入 r 才重新选择。'
    if ! IFS= read -r "?$(jobs_prompt_render "直接回车创建并启动；输入任意字符取消：")" answer || [[ -n "$answer" ]]; then
        SIM_CANCELLED=1
        return 130
    fi
}
# 仅向父运行器预建的空普通文件交接精确设备标识，不创建路径或跟随符号链接。
sim_publish_created_device() (
    local created_file="${JOBS_FLUTTER_CREATED_DEVICE_FILE:-}" created_fd="" result=0
    [[ -n "$created_file" ]] || return 0
    if [[ ! -f "$created_file" || -L "$created_file" || -s "$created_file" || ! -O "$created_file" ]]; then
        sim_log "✖ 模拟器已创建，但设备交接文件无效；须为本用户预建的空普通文件：${created_file}"
        return 1
    fi
    # 系统 zsh 的 sysopen 不接受含中文的完整路径，父目录由原生 cd 处理。
    if ! cd -- "${created_file:h}" || ! zmodload zsh/system || ! sysopen -w -o nofollow,nonblock -u created_fd "${created_file:t}"; then
        sim_log "✖ 模拟器已创建，但无法打开设备交接文件：${created_file}"
        return 1
    fi
    if [[ -f "/dev/fd/$created_fd" && ! -s "/dev/fd/$created_fd" && -O "/dev/fd/$created_fd" ]]; then
        print -r -- $'ios\t'"$SIM_UDID" >&$created_fd || result=1
    else
        result=1
    fi
    exec {created_fd}>&-
    (( result == 0 )) || sim_log "✖ 模拟器已创建，但设备交接失败；保留设备，请重新选择：${created_file}"
    return "$result"
)
# 只新增并启动选定设备；创建结果不明确时停止，避免重试产生重复设备。
sim_create_and_boot() {
    local output="$SIM_RUN_DIR/command.out" result=0 value=""
    sim_log "➤ 正在创建：${SIM_NAME}"
    sim_run_to_file "$output" 30 /usr/bin/xcrun simctl create "$SIM_NAME" "$SIM_DEVICE_ID" "$SIM_RUNTIME_ID" || result=$?
    value="$(<"$output")"
    if (( result != 0 )); then
        if (( result != 124 )) && [[ "$value" == *'Incompatible device'* ]]; then
            sim_log "⚠ 当前设备 / 系统组合不受支持：${value}"
            return 2
        fi
        sim_log "✖ 创建未成功确认（退出码 ${result}）：${value}"
        sim_log '➤ 已停止，未自动重试。若命令曾超时，请先检查 Simulator 设备列表。'
        return 1
    fi
    if [[ ! "$value" =~ '^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$' ]]; then
        sim_log "✖ 创建命令返回的 UDID 无效：${value}"
        sim_log '➤ 已停止，未自动重试；请检查 Simulator 设备列表。'
        return 1
    fi
    SIM_UDID="$value"
    sim_log "✔ 模拟器已创建：${SIM_NAME}（${SIM_UDID}）"
    if ! sim_run_to_file "$output" 30 /usr/bin/xcrun simctl boot "$SIM_UDID"; then
        sim_log "✖ 启动失败：$(<"$output")"
        sim_log "➤ 新设备已保留。可稍后运行：xcrun simctl boot ${SIM_UDID}"
        return 1
    fi
    if ! sim_run_to_file "$output" 15 /usr/bin/open -a "$SIM_APP"; then
        sim_log "✖ 无法打开模拟器界面：$(<"$output")"
        sim_log "➤ 已保留设备：${SIM_UDID}"
        return 1
    fi
    if ! sim_run_to_file "$output" 120 /usr/bin/xcrun simctl bootstatus "$SIM_UDID"; then
        sim_log "⚠ 设备已创建并发起启动，但尚未确认完成：$(<"$output")"
        sim_log "➤ 请在 Simulator 查看 ${SIM_NAME}（${SIM_UDID}）。"
        return 1
    fi
    sim_log "✔ 新模拟器已完成启动：${SIM_NAME}"
    if [[ "$SIM_APP_KIND" == com.apple.dt.Devices ]]; then
        sim_log "➤ 已打开 Device Hub；可按设备名选中 ${SIM_NAME}（${SIM_UDID}）。"
    fi
    sim_publish_created_device
}
# 仅在明确不兼容且用户输入 r / R 后重选，连续回车不会再弹出列表。
sim_confirm_reselection() {
    local answer=""
    if IFS= read -r "?$(jobs_prompt_render "输入 r 重新选择型号和系统；直接回车或其它输入停止：")" answer && [[ "$answer" == [rR] ]]; then
        return 0
    fi
    sim_log '➤ 已停止，未重复选择或再次创建模拟器。'
    return 1
}
# 交互取消正常返回；成功或普通失败均结束，重选必须再次明确发起。
sim_interactive_loop() {
    local result=0
    while true; do
        result=0
        sim_select_combination || result=$?
        if (( result == 130 )); then
            sim_log '➤ 已取消，未创建模拟器。'
            return 0
        elif (( result == 2 )); then
            # 所选型号没有可搭配系统时同不兼容组合一样，只有明确输入 r 才重选。
            sim_confirm_reselection || return 1
            continue
        elif (( result != 0 )); then
            return "$result"
        fi
        sim_prepare_unique_name || return $?
        if ! sim_confirm_creation; then
            sim_log '➤ 已取消，未创建模拟器。'
            return 0
        fi
        result=0
        sim_create_and_boot || result=$?
        if (( result == 2 )); then
            sim_confirm_reselection || return 1
            continue
        fi
        return "$result"
    done
}
# 显示独立运行接口，不加载或修改模拟器环境。
sim_show_help() {
    sim_log "用法：/bin/zsh \"${SCRIPT_PATH}\" [--help | --check]"
    sim_log '  无参数   在可交互终端中选择并新建一个模拟器。'
    sim_log '  --help   显示帮助；不读取 Xcode 或创建日志。'
    sim_log '  --check  只读体检 Xcode / simctl，并列出完整机型、可搭配系统的机型数量及每个可用 iOS 系统支持的机型数。'
    sim_log '来源：JobsCommand@iOS/其他/【MacOS】📱双击初始化iOS模拟器.command。'
}
# 体检完整机型和可用系统清单，不把独立列出的两者误报为全部兼容。
sim_report_catalog() {
    local rows="" devices="" row="" summary="" rest=""
    local matched=0 unmatched=0
    local -a device_rows
    if ! rows="$(sim_data runtimes "$SIM_RUN_DIR/runtimes.json" "$(/usr/bin/uname -m)" 2>&1)"; then
        sim_log "✖ Runtime 数据无效：${rows}"
        return 1
    fi
    if [[ -z "$rows" ]]; then
        sim_log '✖ 没有本机可用的 iOS Runtime；本次未创建或下载。'
        return 1
    fi
    if ! devices="$(sim_data devicetypes "$SIM_RUN_DIR/devicetypes.json" 2>&1)"; then
        sim_log "✖ 设备型号数据无效：${devices}"
        return 1
    fi
    if [[ -z "$devices" ]]; then
        sim_log '✖ 当前 Xcode 没有 iPhone / iPad 设备类型。'
        return 1
    fi
    device_rows=("${(@f)devices}")
    if ! summary="$(sim_data catalog-summary "$SIM_RUN_DIR/devicetypes.json" "$SIM_RUN_DIR/runtimes.json" "$(/usr/bin/uname -m)" 2>&1)"; then
        sim_log "✖ 无法汇总机型与系统的匹配关系：${summary}"
        return 1
    fi
    rest="${${summary%%$'\n'*}#*$'\t'}" # 跳过 models 后的机型总数，只取可搭配与无可搭配两项。
    rest="${rest#*$'\t'}"
    matched="${rest%%$'\t'*}"
    unmatched="${rest#*$'\t'}"
    sim_log "✔ 完整机型清单：${#device_rows} 个 iPhone / iPad（不按 Runtime 隐藏型号；其中 ${matched} 个已有可搭配系统，${unmatched} 个本机无可搭配系统）"
    for row in "${(@f)${summary#*$'\n'}}"; do
        [[ "${row%%$'\t'*}" == runtime ]] || continue
        rest="${row#*$'\t'}"
        if [[ "${rest#*$'\t'}" == -1 ]]; then
            sim_log "✔ 可用系统：${rest%%$'\t'*}（支持机型数未知）"
        else
            sim_log "✔ 可用系统：${rest%%$'\t'*}（支持 ${rest#*$'\t'} 个机型）"
        fi
    done
    sim_report_default_combination || return $?
    sim_log '➤ 首项优先采用已确认支持的组合；元数据缺失保留候选，仍由 simctl create 最终校验。'
    sim_log '✔ 只读体检完成；未创建、启动、关闭或删除模拟器。'
}
# 只读展示两次回车将选择的组合，便于在目标电脑核对默认值。
sim_report_default_combination() {
    local devices="" device="" runtimes="" runtime=""
    if ! devices="$(sim_data preferred-devicetypes "$SIM_RUN_DIR/devicetypes.json" "$SIM_RUN_DIR/runtimes.json" "$(/usr/bin/uname -m)" 2>&1)"; then
        sim_log "✖ 无法推荐默认型号：${devices}"
        return 1
    fi
    device="${devices%%$'\n'*}"
    if ! runtimes="$(sim_data compatible-runtimes "$SIM_RUN_DIR/runtimes.json" "$(/usr/bin/uname -m)" "$SIM_RUN_DIR/devicetypes.json" "${device#*$'\t'}" 2>&1)"; then
        sim_log "✖ 无法推荐默认系统：${runtimes}"
        return 1
    fi
    if [[ -z "$runtimes" ]]; then
        sim_log '✖ 当前型号与已装系统没有可推荐的组合，请在 Xcode 安装对应 Runtime。'
        return 1
    fi
    runtime="${runtimes%%$'\n'*}"
    jobs_prompt_output sim_log "✔ 回车首选组合：${device%%$'\t'*} / ${runtime%%$'\t'*}"
}
# 将帮助、只读体检与交互创建路由到各自流程，并传播失败状态。
sim_run_requested_action() {
    if [[ "$SIM_MODE" == help ]]; then
        sim_show_help
        return 0
    fi
    sim_initialize_runtime
    sim_check_environment || return $?
    if [[ "$SIM_MODE" == interactive ]]; then
        sim_check_selector || return $?
    fi
    sim_load_catalog || return $?
    if [[ "$SIM_MODE" == check ]]; then
        sim_report_catalog
    else
        sim_interactive_loop
    fi
}
# <<< Jobs iOS simulator core <<<

# 首屏只说明行为并确认，确认前不探测 Xcode 或写日志。
show_script_intro_and_wait() {
    sim_prepare_context
    sim_intro_line title '━━━━━━━━━━ 新建 iOS 模拟器 ━━━━━━━━━━'
    jobs_prompt_output sim_intro_line body '1、完整型号中优先显示有可搭配系统的机型，无可搭配系统的机型带标注；选完型号后只列匹配该型号的系统；一路回车采用首选组合，创建并启动新模拟器。'
    sim_intro_line body '2、保留现有设备与调试会话；不安装工具 / Runtime，不更改 Xcode、Shell 或网络配置。'
    sim_intro_line body '3、Ctrl+C 随时停止；系统选择时 ← 返回型号，Esc / Ctrl+C 取消；创建前会再次确认。'
    sim_intro_line body "日志位置：${LOG_FILE}（确认后创建；只读入口不写日志）"
    sim_confirm_entry "$@"
}
# 编排自述确认与本次请求，所有真实动作都在确认或只读路由后执行。
main() {
    show_script_intro_and_wait "$@" # 首先展示内置自述并校验交互确认或只读入口。
    sim_run_requested_action # 体检工具链与 JSON，再执行本次创建或只读检查。
}

main "$@"
