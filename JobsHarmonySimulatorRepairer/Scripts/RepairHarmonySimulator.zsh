#!/bin/zsh
# 脚本自述：
# - 脚本名称：RepairHarmonySimulator.zsh
# - 核心用途：诊断官方 Harmony 本地模拟器，修复失效 SDK 路径，或按确认启动 / 重启选中实例。
# - 影响范围：SDK 修复前完整备份单一实例；启动 / 重启使用官方 CLI，不删除设备、镜像、锁或应用数据。
# - 运行提示：先打印说明并回车；重启及配置修复须输入 YES；--check 只读，不写本工具日志。

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

HR_BIN=""
HR_LOG=""
HR_CHECK=0
HR_HELP=0
HR_NAME=""
HR_INSTANCES=""
HR_IMAGES=""
HR_INSTANCE_PATH=""
HR_CONFIG=""
HR_SDK=""
HR_BACKUP=""
HR_ISSUES=0
HR_RUNNING=""
HR_COLD_BOOT=0
HR_RECORD_IDENTITY=""
HR_DIRECTORY_IDENTITY=""
HR_CONFIG_IDENTITY=""
HR_OFFICIAL_URL="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-command-line"
HR_TOOLS_HOME="$HOME/Library/Application Support/JobsHarmonySimulator"
typeset -a HR_ROWS=()
# 自述标题和正文在真实终端分层显示，非终端保持纯文本。
hr_intro_line() {
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
# 运行前明确真实可修复范围、取消方式与日志策略。
hr_show_intro() {
  hr_intro_line title '━━━━━━━━━━ Harmony 模拟器检测与修复 ━━━━━━━━━━'
  hr_intro_line body '1、仅处理 Apple Silicon Mac 上官方 DevEco Emulator 清单中的本地实例；不操作真机或 Android AVD。'
  hr_intro_line body '2、检查工具能力、Release 镜像、实例目录和 SDK 路径；支持启动、保留数据冷启动修复及失效 SDK 路径修复。'
  hr_intro_line body '3、重启将中断选中实例的运行任务，输入 YES 才执行。SDK 修复要求所有模拟器已关闭，完整备份后只改选中实例配置。'
  hr_intro_line body '4、不清锁、不删除应用或 userdata、不调整容量、不下载工具镜像，不改系统代理或全局 SDK。'
  jobs_prompt_output hr_intro_line body '5、交互运行先回车；任意非空输入 / Ctrl+C 取消。--check 全程只读且不写本工具日志；修复日志在系统临时目录。'
}
# 命令参数只选择既有实例，不能传入任意命令。
hr_parse() {
  while (( $# )); do
    case "$1" in
      --help|-h) HR_HELP=1 ;;
      --check) HR_CHECK=1 ;;
      --repair) ;;
      --name)
        (( $# > 1 )) || { hr_error '--name 缺少实例名称。'; return 2; }
        HR_NAME="$2"
        shift
        ;;
      *) hr_error "未知参数：$1"; return 2 ;;
    esac
    shift
  done
  [[ -z "$HR_NAME" ]] || hr_valid_name "$HR_NAME" || { hr_error '实例名称无效。'; return 2; }
}
# 帮助模式不探测工具、实例或系统环境。
hr_help() {
  print -r -- '用法：RepairHarmonySimulator.zsh [--repair | --check] [--name 名称] [--help]'
  print -r -- '环境：HARMONY_EMULATOR_BIN 指定官方 Emulator；DEVECO_STUDIO_HOME / TOOL_HOME 指定 DevEco / CLT 根目录。'
  print -r -- '--check 仅查询工具、已下载镜像、既有实例与本地配置；诊断异常返回非零，不写日志。'
  print -r -- 'SDK 路径修复需关闭全部模拟器、输入 YES，完整备份实例后仅修复选中实例 config.ini。'
  print -r -- "官方依据：$HR_OFFICIAL_URL"
}
# 名称沿用官方创建器的保守字符集，阻止选项和控制字符注入。
hr_valid_name() {
  [[ -n "$1" && ${#1} -le 64 && "$1" == [a-zA-Z]* && "$1" != *[^a-zA-Z0-9_+\ ]* && "$1" != *' ' ]]
}
# 终端与独立日志同步保留业务结果。
hr_log() {
  print -r -- "$*"
  [[ -z "$HR_LOG" ]] || print -r -- "$*" >> "$HR_LOG"
  return 0
}
# 失败始终可见且保留非零状态。
hr_error() {
  print -u2 -r -- "✖ $*"
  [[ -z "$HR_LOG" ]] || print -r -- "✖ $*" >> "$HR_LOG"
  return 1
}
# 只在交互授权后创建私有日志，--check 不触发。
hr_initialize_log() {
  local directory=""
  umask 077
  directory="$(/usr/bin/mktemp -d "${${TMPDIR:-/tmp}%/}/JobsHarmonySimulatorRepairer.XXXXXX")" || return 1
  HR_LOG="$directory/RepairHarmonySimulator.log"
  : > "$HR_LOG" || return 1
  hr_log "ℹ 日志：$HR_LOG"
}
# 查询和生命周期命令设定有限超时，超时绝不视为成功。
hr_command() {
  local child_pid watchdog_pid result=0
  "$HR_BIN" "$@" &
  child_pid=$!
  ( /bin/sleep 60; kill -TERM "$child_pid" 2>/dev/null; /bin/sleep 1; kill -KILL "$child_pid" 2>/dev/null ) >/dev/null 2>&1 &
  watchdog_pid=$!
  wait "$child_pid" 2>/dev/null || result=$?
  kill -TERM "$watchdog_pid" 2>/dev/null
  wait "$watchdog_pid" 2>/dev/null
  (( result < 128 )) || print -u2 -r -- 'Emulator 命令超时或被终止（60 秒），保留现场。'
  return "$result"
}
# 仅接受官方 CLI 能力；Android emulator 同名候选无法通过。
hr_capabilities() {
  local output="" option=""
  output="$(hr_command -help 2>&1)" || { hr_error "Emulator -help 失败：$output"; return 1; }
  for option in list details imageList start stop; do
    print -r -- "$output" | /usr/bin/grep -Eqi -- "(^|[^[:alnum:]_-])-${option}([^[:alnum:]_-]|$)" || {
      hr_error "当前 Emulator 缺少 -$option 能力。"
      return 1
    }
  done
  HR_COLD_BOOT=0
  if print -r -- "$output" | /usr/bin/grep -Eqi -- '(^|[^[:alnum:]_-])-bootMode([^[:alnum:]_-]|$)'; then
    HR_COLD_BOOT=1
  fi
}
# 显式坏路径立即停止，自动发现只有唯一健康候选才采用。
hr_find_emulator() {
  local candidate="" directory="" root="${DEVECO_STUDIO_HOME:-${TOOL_HOME:-}}"
  local -a candidates=() compatible=()
  if [[ -n "${HARMONY_EMULATOR_BIN:-}" ]]; then
    [[ -f "$HARMONY_EMULATOR_BIN" && -x "$HARMONY_EMULATOR_BIN" ]] || { hr_error 'HARMONY_EMULATOR_BIN 不是可执行文件。'; return 1; }
    HR_BIN="${HARMONY_EMULATOR_BIN:A}"
    hr_capabilities
    return $?
  fi
  if [[ -n "$root" ]]; then
    [[ -d "$root" ]] || { hr_error "指定工具根目录不存在：$root"; return 1; }
    candidates=("$root/Contents/tools/emulator/Emulator" "$root/tools/emulator/Emulator" "$root/emulator/Emulator")
  else
    candidates=(/Applications/DevEco*.app/Contents/tools/emulator/Emulator(N) "$HOME"/Applications/DevEco*.app/Contents/tools/emulator/Emulator(N) "$HR_TOOLS_HOME"/clt-*/emulator/Emulator(N))
    for directory in "${path[@]}"; do
      [[ -z "$directory" ]] || candidates+=("$directory/Emulator")
    done
  fi
  for candidate in "${candidates[@]}"; do
    [[ -f "$candidate" && -x "$candidate" ]] || continue
    HR_BIN="${candidate:A}"
    if hr_capabilities >/dev/null 2>&1; then compatible+=("$HR_BIN"); fi
  done
  compatible=("${(@u)compatible}")
  (( ${#compatible[@]} == 1 )) || { hr_error "找到 ${#compatible[@]} 个健康 DevEco Emulator；请用 HARMONY_EMULATOR_BIN 指定唯一工具。不会下载或改环境。"; return 1; }
  HR_BIN="${compatible[1]}"
  hr_capabilities
}
# 官方空清单精确文案兼容；其它日志或畸形输出交给 JSON 校验拒绝。
hr_query() {
  local output="" result=0
  output="$(hr_command "$@" 2>&1)" || result=$?
  (( result == 0 )) || { hr_error "Emulator $1 失败（$result）：$output"; return "$result"; }
  if [[ "$*" == '-list -details' && "$output" == '[Empty]' ]] ||
     [[ "$1" == -imageList && "$output" == 'No images matching the criteria were found.' ]]; then
    print -r -- '[]'
  else
    print -r -- "$output"
  fi
}
# 只读取官方字段，原始内容从不求值为代码；重复实例或不明结构停止。
hr_json() {
  (( ${#2} <= 100000 )) || { hr_error '官方 JSON 超过 100 KB，停止。'; return 1; }
  /usr/bin/osascript -l JavaScript - "$@" <<'JXA'
ObjC.import('Foundation');
function run(args) {
  var mode=args[0], input=JSON.parse(args[1]), rows=[], seen=Object.create(null);
  if (mode==='instances' && input && !Array.isArray(input) && typeof input.name==='string') input=[input];
  if (!Array.isArray(input)) throw Error('Expected official JSON array');
  function text(value) {
    if(typeof value!=='string'||!value||/[\u0000-\u001f\u007f-\u009f]/.test(value)) throw Error('Invalid official field');
    return value;
  }
  input.forEach(function(item) {
    if(!item||typeof item!=='object'||Array.isArray(item)) throw Error('Invalid record');
    if(mode==='instances') {
      var name=text(item.name), path=text(item.instancePath), type=text(item.deviceType), running=item.isRunning;
      var uuid=text(item.uuid), flatVersion=item['os.osVersion'], nestedVersion=item.os&&item.os.osVersion;
      if(flatVersion!==undefined&&nestedVersion!==undefined&&flatVersion!==nestedVersion) throw Error('Conflicting os.osVersion');
      var version=text(flatVersion!==undefined?flatVersion:nestedVersion);
      if(!/^[A-Za-z][A-Za-z0-9_+ ]{0,63}$/.test(name)||/ $/.test(name)||seen[name.toLowerCase()]) throw Error('Invalid or duplicate instance name');
      if(running!==true&&running!==false&&running!=='true'&&running!=='false') throw Error('Unknown isRunning');
      seen[name.toLowerCase()]=true;
      rows.push(name+'\t'+path+'\t'+type+'\t'+String(running)+'\t'+uuid+'\t'+version);
    } else if(mode==='images') {
      var type=text(item.deviceType), version=text(item.osVersion), release=text(item.releaseType);
      if(item.downloaded!==true&&item.downloaded!=='true') throw Error('Unexpected non-downloaded image');
      if(release.toLowerCase()==='release') rows.push(type+'\t'+version);
    } else throw Error('Unknown mode');
  });
  return rows.join('\n');
}
JXA
}
# 清单由官方查询读取，未登记实例和真机不进入操作目标。
hr_read_state() {
  local parsed="" images=""
  HR_INSTANCES="$(hr_query -list -details)" || return $?
  parsed="$(hr_json instances "$HR_INSTANCES")" || { hr_error '实例 JSON 结构未知或身份重复，停止。'; return 1; }
  HR_ROWS=("${(@f)parsed}")
  [[ -n "$parsed" ]] || HR_ROWS=()
  HR_IMAGES="$(hr_query -imageList -downloaded true)" || return $?
  images="$(hr_json images "$HR_IMAGES")" || { hr_error '镜像 JSON 无法解析，停止。'; return 1; }
  if [[ -z "$images" ]]; then
    hr_log '⚠ 没有已下载 Release 镜像；需先通过新建入口或 Device Manager 准备。'
    HR_ISSUES=1
  fi
  hr_log "ℹ 官方工具：$HR_BIN；本地实例：${#HR_ROWS[@]}"
}
# 只接受与实例名称一致且无路径链接的本地目录及普通配置。
hr_validate_instance() {
  local name="$1" directory="$2" running="$3" config="" line="" count=0
  [[ "$directory" == /* && "$directory" != *[[:cntrl:]]* && "${directory:t}" == "$name" && -d "$directory" && ! -L "$directory" && "${directory:A}" == "$directory" ]] || { hr_error "实例路径不可靠：$name / $directory"; return 1; }
  config="$directory/config.ini"
  [[ -f "$config" && ! -L "$config" ]] || { hr_error "实例配置不是普通文件：$config"; return 1; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ "$line" == name=* ]]; then
      [[ "$line" == "name=$name" ]] || { hr_error '实例配置 name 与官方清单不一致。'; return 1; }
      (( count += 1 ))
    fi
  done < "$config"
  (( count == 1 )) || { hr_error '实例配置缺少唯一 name，停止自动处理。'; return 1; }
  HR_INSTANCE_PATH="$directory"
  HR_CONFIG="$config"
  [[ "$running" == true || "$running" == false ]] || { hr_error '实例运行状态未知，停止。'; return 1; }
  HR_RUNNING="$running"
}
# HDC 版本检测不连接设备或自动启动服务，SDK 必须真实可用。
hr_sdk_healthy() {
  local sdk="$1"
  [[ "$sdk" == /* && "$sdk" != *[[:cntrl:]]* && -d "$sdk" && ! -L "$sdk" && "${sdk:A}" == "$sdk" &&
     -x "$sdk/default/openharmony/toolchains/hdc" && ! -L "$sdk/default/openharmony/toolchains/hdc" ]] || return 1
  ( HR_BIN="$sdk/default/openharmony/toolchains/hdc"; hr_command -v ) >/dev/null 2>&1
}
# 查询既有配置并定位同一工具附带 SDK，不跨安装猜测或改全局环境。
hr_inspect_sdk() {
  local line="" configured="" count=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ "$line" == sdkPath=* || "$line" == harmonyos.sdk.path=* ]]; then
      (( count += 1 ))
      [[ -z "${line#*=}" ]] || configured="${line#*=}"
    fi
  done < "$HR_CONFIG"
  (( count <= 1 )) || { hr_error 'SDK 配置键重复，需人工核对，未写入。'; return 1; }
  if hr_sdk_healthy "$configured"; then
    hr_log "✔ $HR_NAME SDK / HDC 版本检测通过：$configured"
    HR_SDK=""
    return 0
  fi
  hr_log "⚠ $HR_NAME SDK 路径缺失或 HDC 不可用：${configured:-未配置}"
  HR_SDK="${HR_BIN:h:h}/sdk"
  if ! hr_sdk_healthy "$HR_SDK"; then
    HR_SDK="${HR_BIN:h:h:h}/sdk"
  fi
  if ! hr_sdk_healthy "$HR_SDK"; then
    HR_SDK=""
    hr_log '⚠ 同一工具未找到健康 SDK，请通过 DevEco SDK Manager 准备。'
  fi
  HR_ISSUES=1
}
# 选择单一本地实例；编号默认首项，取消和无效输入不执行动作。
hr_select() {
  local row="" answer="" index=1
  (( ${#HR_ROWS[@]} )) || { hr_error '没有官方登记的本地实例，请先新建 Harmony 模拟器。'; return 1; }
  if [[ -z "$HR_NAME" ]]; then
    for row in "${HR_ROWS[@]}"; do
      hr_log "$index、${row%%$'\t'*}"
      (( index += 1 ))
    done
    IFS= read -r "answer?$(jobs_prompt_render '选择实例（回车选 1；q 取消）：')" || return 130
    [[ "$answer" != q && "$answer" != Q ]] || return 130
    [[ -n "$answer" ]] || answer=1
    [[ "$answer" == <-> ]] && (( answer >= 1 && answer <= ${#HR_ROWS[@]} )) || { hr_error '无效实例编号。'; return 2; }
    HR_NAME="${HR_ROWS[$answer]%%$'\t'*}"
  fi
  hr_revalidate
}
# 每次动作前重新读取官方登记，要求同一名称与同一实例路径。
hr_revalidate() {
  local current="" parsed="" row="" rest="" found=0 old_path="$HR_INSTANCE_PATH"
  local directory="" type="" running="" uuid="" version="" identity="" directory_identity="" config_identity=""
  current="$(hr_query -list -details)" || return $?
  parsed="$(hr_json instances "$current")" || { hr_error '实例复检失败，未执行动作。'; return 1; }
  for row in "${(@f)parsed}"; do
    [[ "${row%%$'\t'*}" == "$HR_NAME" ]] || continue
    rest="${row#*$'\t'}"
    directory="${rest%%$'\t'*}"
    rest="${rest#*$'\t'}"
    type="${rest%%$'\t'*}"
    rest="${rest#*$'\t'}"
    running="${rest%%$'\t'*}"
    rest="${rest#*$'\t'}"
    uuid="${rest%%$'\t'*}"
    version="${rest#*$'\t'}"
    hr_validate_instance "$HR_NAME" "$directory" "$running" || return $?
    identity="$HR_NAME"$'\t'"$directory"$'\t'"$type"$'\t'"$uuid"$'\t'"$version"
    directory_identity="$(/usr/bin/stat -f '%d:%i' "$HR_INSTANCE_PATH")" || return 1
    config_identity="$(/usr/bin/stat -f '%d:%i' "$HR_CONFIG")" || return 1
    if [[ -n "$HR_RECORD_IDENTITY" ]]; then
      [[ "$identity" == "$HR_RECORD_IDENTITY" && "$directory_identity" == "$HR_DIRECTORY_IDENTITY" && "$config_identity" == "$HR_CONFIG_IDENTITY" ]] || {
        hr_error '确认期间实例 UUID、系统版本或目录 / 配置身份已改变，未继续动作。'
        return 1
      }
    else
      HR_RECORD_IDENTITY="$identity"
      HR_DIRECTORY_IDENTITY="$directory_identity"
      HR_CONFIG_IDENTITY="$config_identity"
    fi
    (( found += 1 ))
  done
  (( found == 1 )) || { hr_error '选中实例已消失或不唯一，未执行动作。'; return 1; }
  [[ -z "$old_path" || "$old_path" == "$HR_INSTANCE_PATH" ]] || { hr_error '选中实例路径已改变，未执行动作。'; return 1; }
}
# 保守要求所有模拟器退出；无法读取进程表也停止配置写入。
hr_require_stopped() {
  local processes=""
  hr_revalidate || return $?
  [[ "$HR_RUNNING" == false ]] || { hr_error '选中实例仍在运行，未修改配置。'; return 1; }
  processes="$(/bin/ps -axo comm=)" || { hr_error '无法核对模拟器进程，未修改配置。'; return 1; }
  if print -r -- "$processes" | /usr/bin/awk '
    { n=split($0,p,"/"); name=tolower(p[n]); if(name ~ /qemu|emulator/) found=1 }
    END { exit !found }
  '; then
    hr_error '仍检测到模拟器进程；先关闭全部 Harmony / Android 模拟器，再运行 SDK 修复。不会强杀进程或清锁。'
    return 1
  fi
}
# 修改前完整保留实例；含链接的实例拒绝复制，防止写出边界或漏备数据。
hr_backup_instance() {
  local entry="" required="" available=""
  for entry in "$HR_INSTANCE_PATH"/**/*(ND@); do
    hr_error "实例含符号链接，未备份或修改：$entry"
    return 1
  done
  required="$(/usr/bin/du -sk "$HR_INSTANCE_PATH" | /usr/bin/awk '{print $1}')" || return 1
  available="$(/bin/df -Pk "${HR_INSTANCE_PATH:h}" | /usr/bin/awk 'NR==2 {print $4}')" || return 1
  [[ "$required" == <-> && "$available" == <-> ]] && (( available > required + 1048576 )) || { hr_error '可用空间不足完整备份加 1 GB 余量，未修改。'; return 1; }
  HR_BACKUP="$(/usr/bin/mktemp -d "${HR_INSTANCE_PATH:h}/.${HR_NAME}.jobs-repair-backup.XXXXXX")" || return 1
  /bin/chmod 700 "$HR_BACKUP" || return 1
  hr_log "来源：$HR_INSTANCE_PATH；完整备份目标：$HR_BACKUP/instance"
  /bin/cp -Rp "$HR_INSTANCE_PATH" "$HR_BACKUP/instance" || { hr_error "备份失败，保留现场：$HR_BACKUP"; return 1; }
  /usr/bin/diff -rq "$HR_INSTANCE_PATH" "$HR_BACKUP/instance" >/dev/null || { hr_error '备份逐文件核对失败，未修改。'; return 1; }
}
# 只有失效 SDK 键允许替换，完整备份与并发复检后原子发布。
hr_publish_sdk_config() {
  local temporary="$1" original="$2"
  hr_require_stopped || return $?
  [[ "$(/usr/bin/shasum -a 256 "$HR_CONFIG")" == "$original" ]] || { hr_error '发布前配置内容已改变，保留备份和候选文件，不覆盖。'; return 1; }
  /bin/mv -f "$temporary" "$HR_CONFIG"
}
# SDK 修复将候选文件与真实配置分开，最后一次复检通过才发布。
hr_repair_sdk() {
  local answer="" original="" temporary="" expected_sdk=""
  hr_inspect_sdk || return $?
  [[ -n "$HR_SDK" ]] || { hr_error '无可修复 SDK 路径；已有健康配置或同一工具没有可用 SDK。'; return 1; }
  expected_sdk="$HR_SDK"
  hr_log "目标实例：$HR_NAME；仅修复 config.ini SDK 路径为：$HR_SDK"
  IFS= read -r 'answer?先关闭全部模拟器；输入 YES 完整备份并修复，其他输入取消：' || return 130
  [[ "$answer" == YES ]] || { hr_log '已取消 SDK 修复。'; return 0; }
  hr_revalidate || return $?
  hr_require_stopped || return $?
  original="$(/usr/bin/shasum -a 256 "$HR_CONFIG")" || return 1
  hr_backup_instance || return $?
  hr_revalidate || return $?
  hr_require_stopped || return $?
  [[ "$(/usr/bin/shasum -a 256 "$HR_CONFIG")" == "$original" ]] || { hr_error '备份期间配置变化，保留备份并停止。'; return 1; }
  hr_sdk_healthy "$expected_sdk" || { hr_error 'SDK 在确认期间失效，未修改。'; return 1; }
  temporary="$(/usr/bin/mktemp "$HR_INSTANCE_PATH/.jobs-sdk-repair.XXXXXX")" || return 1
  if /bin/cp -p "$HR_CONFIG" "$temporary" &&
     /usr/bin/awk '!/^sdkPath=/ && !/^harmonyos.sdk.path=/' "$HR_CONFIG" > "$temporary" &&
     print -r -- "sdkPath=$expected_sdk" >> "$temporary" &&
     hr_publish_sdk_config "$temporary" "$original"; then
    hr_log "✔ SDK 路径已修复；完整备份：$HR_BACKUP。尚未验证模拟器开机，请另选启动动作。"
  else
    hr_error "配置发布失败；保留完整备份：$HR_BACKUP；候选配置：$temporary"
    return 1
  fi
  HR_ISSUES=0
  hr_inspect_sdk
  (( ! HR_ISSUES ))
}
# 官方状态轮询到明确布尔值才进入下一步，超时保持未完成。
hr_wait_running() {
  local expected="$1" attempt=0
  for attempt in {1..30}; do
    hr_revalidate || return $?
    [[ "$HR_RUNNING" != "$expected" ]] || return 0
    /bin/sleep 2
  done
  hr_error "实例未在限定时间达到 isRunning=$expected；保留现场，不继续下游动作。"
}
# 生命周期命令保留退出码；停止失败或停机状态未确认绝不继续启动。
hr_lifecycle() {
  local action="$1" answer="" output="" result=0
  if [[ "$action" == restart ]]; then
    (( HR_COLD_BOOT )) || { hr_error '当前 Emulator 未声明 -bootMode，不能执行保留数据冷启动，请更新官方工具。'; return 1; }
    hr_log "⚠ 将对 $HR_NAME 执行保留数据的 coldboot，运行中的应用和调试会话将中断。"
    IFS= read -r 'answer?输入 YES 冷启动修复所选实例，其他输入取消：' || return 130
    [[ "$answer" == YES ]] || { hr_log '已取消重启。'; return 0; }
    hr_revalidate || return $?
    if [[ "$HR_RUNNING" == true ]]; then
      output="$(hr_command -stop "$HR_NAME" 2>&1)" || result=$?
      hr_log "$output"
      (( result == 0 )) || { hr_error "官方停止失败（$result），未继续启动。"; return "$result"; }
    fi
    hr_wait_running false || return $?
  else
    IFS= read -r "answer?$(jobs_prompt_render '回车启动所选实例，任意非空输入取消：')" || return 130
    [[ -z "$answer" ]] || { hr_log '已取消启动。'; return 0; }
    hr_revalidate || return $?
  fi
  result=0
  if [[ "$action" == restart ]]; then
    output="$(hr_command -start "$HR_NAME" -bootMode coldboot 2>&1)" || result=$?
  else
    output="$(hr_command -start "$HR_NAME" 2>&1)" || result=$?
  fi
  hr_log "$output"
  (( result == 0 )) || { hr_error "官方启动失败（$result），请在 DevEco Device Manager 查看，未自动重试。"; return "$result"; }
  hr_wait_running true || return $?
  hr_log '✔ 已验证所选实例 isRunning=true；系统开机完成、HDC 连接和应用运行仍需在模拟器窗口核对。'
}
# 只读模式检查全部或指定实例，发现异常保留失败状态。
hr_diagnose() {
  local row="" rest="" directory="" running="" found=0 requested="$HR_NAME"
  (( ${#HR_ROWS[@]} )) || { hr_error '没有官方登记的本地实例，请先新建 Harmony 模拟器。'; return 1; }
  for row in "${HR_ROWS[@]}"; do
    HR_NAME="${row%%$'\t'*}"
    [[ -z "$requested" || "$requested" == "$HR_NAME" ]] || continue
    (( found += 1 ))
    rest="${row#*$'\t'}"
    directory="${rest%%$'\t'*}"
    rest="${rest#*$'\t'}"
    rest="${rest#*$'\t'}"
    running="${rest%%$'\t'*}"
    hr_validate_instance "$HR_NAME" "$directory" "$running" || return $?
    hr_inspect_sdk || return $?
    hr_log "ℹ 实例：$HR_NAME；目录：$HR_INSTANCE_PATH；isRunning=$HR_RUNNING（系统开机完成仍需窗口核对）。"
  done
  (( found )) || { hr_error '指定实例不在官方清单中，停止。'; return 1; }
  HR_NAME="$requested"
  HR_INSTANCE_PATH=""
  (( ! HR_ISSUES ))
}
# 交互菜单只派发固定动作，未知选择不产生写入。
hr_interactive() {
  local answer=""
  hr_select || return $?
  hr_inspect_sdk || return $?
  hr_log '1、启动选中实例'
  hr_log '2、保留数据冷启动修复选中实例（YES）'
  hr_log '3、完整备份并修复失效 SDK 路径（YES，要求全部模拟器已关闭）'
  jobs_prompt_output hr_log '回车 / q：结束本次诊断。'
  IFS= read -r 'answer?选择：' || return 130
  case "$answer" in
    1) hr_lifecycle start ;;
    2) hr_lifecycle restart ;;
    3) hr_repair_sdk ;;
    ''|q|Q) (( ! HR_ISSUES )) ;;
    *) hr_error '未知动作，未执行修复。'; return 2 ;;
  esac
}
# 确认后才进入平台检测和日志初始化，帮助与只读检查保持无写入。
hr_dispatch() {
  setopt NO_NOMATCH PIPE_FAIL
  hr_parse "$@" || return $?
  if (( HR_HELP )); then hr_help; return 0; fi
  if (( ! HR_CHECK )); then
    [[ -t 0 ]] || { hr_error '请在可交互终端运行；无交互只能使用 --check / --help。'; return 1; }
    local answer=""
    IFS= read -r "answer?$(jobs_prompt_render '已了解用途与影响，回车继续；任意非空输入取消：')" || return 130
    [[ -z "$answer" ]] || { hr_log '已取消。'; return 0; }
  fi
  [[ "$(/usr/bin/uname -s)" == Darwin && "$(/usr/bin/uname -m)" == arm64 ]] || { hr_error '仅支持 Apple Silicon 原生 macOS 终端。'; return 1; }
  (( HR_CHECK )) || hr_initialize_log || return $?
  hr_find_emulator || return $?
  hr_read_state || return $?
  if (( HR_CHECK )); then
    hr_diagnose
  else
    hr_interactive
  fi
}
# 入口仅负责展示用途和编排固定流程。
main() {
  hr_show_intro # 先说明真实修复能力、风险、只读模式与取消方式。
  hr_dispatch "$@" # 参数检查后执行只读诊断或需要明确确认的修复动作。
}

main "$@"
