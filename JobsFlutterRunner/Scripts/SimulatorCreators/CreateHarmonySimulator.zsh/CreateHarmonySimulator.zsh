#!/bin/zsh
# 脚本自述：
# - 脚本名称：CreateHarmonySimulator.zsh
# - 核心用途：通过华为官方 Emulator CLI，补齐工具和选中的 Release 镜像，新建并按需启动 Harmony 模拟器。
# - 影响范围：写入 DevEco 默认模拟器实例目录；保留已有设备、镜像、代理和系统配置。
# - 运行提示：回车授权缺工具时从 SDL 镜像安装 CLT；缺镜像走官方下载，--check 只读，许可展示后本人回车同意。

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

# JOBS_SDK_RETRY_BEGIN
# 只处理本轮子树，避免超时或取消后残留下载进程占用 SDK 锁。
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

jobs_sdk_stop_tree() {
    local root="$1" child=""
    for child in $(/usr/bin/pgrep -P "$root" 2>/dev/null); do
        jobs_sdk_stop_tree "$child"
    done
    /bin/kill -TERM "$root" 2>/dev/null || true
    /bin/kill -KILL "$root" 2>/dev/null || true
}
# 状态写标准错误，机器可读的标准输出不混入重试提示。
jobs_sdk_retry_note() {
    print -u2 -r -- "$2"
    [[ -z "$1" ]] || print -r -- "$2" >> "$1"
}
# 本地确定错误应明确失败；下载超时、断流和未知获取失败则继续，无次数/总时长上限。
jobs_sdk_retry() {
    setopt LOCAL_OPTIONS LOCAL_TRAPS
    local title="$1" acquisition_log="$2" attempt=1 result=0 delay="${JOBS_SDK_RETRY_DELAY:-2}" maximum="${JOBS_SDK_RETRY_MAX_DELAY:-30}"
    local task_pid="" offset=0 failure="" interrupted=0 history="${2}.attempts.log"
    shift 2
    [[ "$delay" == <-> && "$maximum" == <-> && "$maximum" -gt 0 && "$delay" -le "$maximum" ]] || return 2
    trap 'interrupted=130; [[ -z "$task_pid" ]] || jobs_sdk_stop_tree "$task_pid"' INT
    trap 'interrupted=143; [[ -z "$task_pid" ]] || jobs_sdk_stop_tree "$task_pid"' TERM
    trap 'interrupted=129; [[ -z "$task_pid" ]] || jobs_sdk_stop_tree "$task_pid"' HUP
    while true; do
        jobs_sdk_retry_note "$acquisition_log" "▶ SDK 获取：$title；第 $attempt 次（失败自动重试，Ctrl+C 结束）"
        offset=0
        [[ ! -f "$acquisition_log" ]] || offset="$(/usr/bin/wc -c < "$acquisition_log")"
        [[ "${JOBS_SDK_LOG_REPLACED:-0}" != 1 ]] || offset=0
        # 显式继承 stdin；后台调用仍能进行工具自身的许可/认证交互。
        "$@" <&0 &
        task_pid=$!
        result=0
        wait "$task_pid" || result=$?
        task_pid=""
        (( interrupted == 0 )) || return "$interrupted"
        if [[ -f "$acquisition_log" ]]; then
            (( $(/usr/bin/wc -c < "$acquisition_log") >= offset )) || offset=0
            print -r -- "━━ $title：第 $attempt 次，退出码 $result ━━" >> "$history"
            /usr/bin/tail -c +$((offset + 1)) "$acquisition_log" >> "$history"
        fi
        failure=""
        if [[ -f "$acquisition_log" ]]; then
            failure="$(/usr/bin/tail -c +$((offset + 1)) "$acquisition_log" | /usr/bin/tail -c 65536)"
        fi
        # 部分获取器下载失败仍返回0，明确失败详情不能冒充SDK就绪。
        if (( result == 0 )) && print -r -- "$failure" | /usr/bin/grep -Eqi 'Failed to download|Error downloading|Unable to download|Could not download|Download failed'; then
            result=1
        fi
        (( result != 0 )) || return 0
        # 超时的调用方应返回124；外部中断状态不能被重试循环吞掉。
        case "$result" in 129|130|131|137|143) return "$result" ;; 126|127) return "$result" ;; esac
        failure=""
        if [[ -f "$acquisition_log" ]]; then
            # 兼容调用方每次重建机器输出文件：缩短后从文件开头读取。
            (( $(/usr/bin/wc -c < "$acquisition_log") >= offset )) || offset=0
            failure="$(/usr/bin/tail -c +$((offset + 1)) "$acquisition_log" | /usr/bin/tail -c 65536)"
        fi
        if print -r -- "$failure" | /usr/bin/grep -Eqi 'File exists|Permission denied|Operation not permitted|No space left on device|Read-only file system|Bad CPU type|Exec format error|unknown option|unrecognized option|invalid argument|version .* (does not exist|not found)|license[^[:cntrl:]]*(not accepted|rejected)|licenses?[^[:cntrl:]]*not accepted|HTTP[^[:cntrl:]]*(401|403|404)|returned error: (401|403|404)|Authentication failed|could not read Username'; then
            jobs_sdk_retry_note "$acquisition_log" "✖ $title 遇到权限、许可、版本或本地环境错误（$result），已停止；请按原始日志处理。"
            return "$result"
        fi
        jobs_sdk_retry_note "$acquisition_log" "⚠ $title 获取未完成（退出码 $result）；${delay} 秒后自动重试，保留已有缓存。"
        /bin/sleep "$delay" &
        task_pid=$!
        wait "$task_pid" || { (( interrupted == 0 )) || return "$interrupted"; return 130; }
        task_pid=""
        (( interrupted == 0 )) || return "$interrupted"
        (( attempt++ ))
        (( delay < maximum )) && delay=$(( delay * 2 ))
        (( delay <= maximum )) || delay="$maximum"
    done
}
# JOBS_SDK_RETRY_END

HS_BIN=""
HS_LOG=""
HS_CHECK=0
HS_HELP=0
HS_PREPARE=0
HS_TOOLS_ONLY=0
HS_START=1
HS_NAME=""
HS_IMAGES=""
HS_INSTANCES=""
HS_TYPE=""
HS_VERSION=""
HS_OFFICIAL_URL="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-command-line"
HS_DOWNLOAD_URL="https://developer.huawei.com/consumer/cn/download/"
HS_CLT_VERSION="6.1.1.280"
HS_CLT_URL="https://libsdl.org/harmonyos-devtools/commandline-tools-mac-arm64-6.1.1.280.zip"
HS_CLT_SIZE=2025336267
# 固定 SDL 镜像快照摘要；不是华为官方公布的校验值。
HS_CLT_SHA256="47d0e558b8285e1452f4d3611863027ec0d1135642761bef23402434e22382d4"
HS_TOOLS_HOME="$HOME/Library/Application Support/JobsHarmonySimulator"
HS_INSTALL_STAGE=""
HS_CAN_BOOTSTRAP=0
HS_LICENSES_CONFIRMED=0
HS_PREFERRED_ROW=""
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
  hs_intro_line title '━━━━━━━━━━ 新建 Harmony 模拟器 ━━━━━━━━━━'
  hs_intro_line body '1、仅支持 Apple Silicon macOS 与具备 -create / -imageList 的官方 DevEco Emulator（6.1.0 Beta1+）。'
  jobs_prompt_output hs_intro_line body '2、缺系统镜像时自动读取官方清单，回车选择最新稳定版手机镜像并下载；随后创建唯一实例并启动。'
  jobs_prompt_output hs_intro_line body '3、下载或启动前展示工具随附的许可原文，回车表示本人同意；任意非空输入取消。不改代理或 Shell 配置。'
  jobs_prompt_output hs_intro_line body '4、回车授权缺工具时从 SDL 第三方镜像免登录下载 Mac ARM64 CLT（约 2.03 GB），校验后新增独立目录；健康工具不升级。'
  hs_intro_line body '   华为官网下载工具需登录；SDL 替代工具包下载，系统镜像由官方 Emulator 下载（可能数 GB），保留已有设备与镜像。'
  hs_intro_line body '➤ SDK 工具包、在线清单和系统镜像获取失败持续自动重试，无次数或总时长上限；Ctrl+C 结束。'
  jobs_prompt_output hs_intro_line body '5、交互入口回车继续，q / Ctrl+C 取消；--prepare 仅准备，--check 只读查询，日志在系统临时目录 JobsHarmonySimulator.* 中。'
}

hs_help() {
  print -r -- '用法：CreateHarmonySimulator.zsh [--create | --prepare | --tools-only | --check] [--name 名称] [--no-start] [--help]'
  print -r -- '--tools-only 只准备 CLT / SDK 工具并由本人阅读许可，不下载系统镜像、不创建或启动设备。'
  print -r -- '环境：HARMONY_EMULATOR_BIN 指定官方 Emulator；DEVECO_STUDIO_HOME / TOOL_HOME 指定 DevEco 或 CLT 根目录。'
  print -r -- 'HARMONY_CLT_ARCHIVE 可指定已下载的 SDL 同版本 ZIP；仍检查固定大小与 SHA-256，不接受任意工具包。'
  print -r -- '--check 仅查询 -help、-imageList -downloaded true、-list -details，不创建、启动或下载。'
  print -r -- '--prepare 补齐缺失工具和选中的 Release 系统镜像，复检完成即退出，不创建设备。'
  print -r -- "SDL 替代下载源：$HS_CLT_URL"
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
      --prepare) HS_PREPARE=1 ;;
      --tools-only) HS_TOOLS_ONLY=1 ;;
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
  (( ! HS_CHECK || ( ! HS_PREPARE && ! HS_TOOLS_ONLY ) )) || { hs_error '--check 与准备模式不能同时使用。'; return 2; }
  (( ! HS_PREPARE || ! HS_TOOLS_ONLY )) || { hs_error '--prepare 与 --tools-only 不能同时使用。'; return 2; }
  [[ -z "$HS_NAME" ]] || hs_valid_name "$HS_NAME" || { hs_error '名称须以英文字母开头，仅含英文字母、数字、空格、下划线或加号；不能以空格结尾，最长 64 字符，不支持连字符 -。'; return 2; }
}

hs_valid_name() {
  local value="$1"
  # 官方 Emulator 拒绝连字符；额外限制首字符、尾空格和长度，使两端一致。
  [[ -n "$value" && ${#value} -le 64 && "$value" == [a-zA-Z]* && "$value" != *[^a-zA-Z0-9_+\ ]* && "$value" != *' ' ]]
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
      hs_error '华为Harmony 本地模拟器仅支持 Apple Silicon（arm64）；Intel Mac 不支持。'
    fi
    return 1
  fi
}

# 显式路径失败即停止，不能静默选到另一套 SDK 或 Android emulator。
hs_find_emulator() {
  HS_CAN_BOOTSTRAP=0
  local requested="${HARMONY_EMULATOR_BIN:-}" root="${DEVECO_STUDIO_HOME:-${TOOL_HOME:-}}" candidate="" directory=""
  local -a candidates=() compatible=()
  if [[ -n "$requested" ]]; then
    [[ -f "$requested" && -x "$requested" ]] || { hs_error "指定 Emulator 不可执行：$requested"; return 1; }
    HS_BIN="${requested:A}"
    hs_log "ℹ 指定工具：$HS_BIN"
    hs_check_capabilities
    return $?
  fi
  if [[ -n "$root" ]]; then
    [[ -d "$root" ]] || { hs_error "指定 DevEco / CLT 目录不存在：$root"; return 1; }
    for candidate in "$root/Contents/tools/emulator/Emulator" "$root/tools/emulator/Emulator" "$root/emulator/Emulator"; do
      [[ ! -f "$candidate" || ! -x "$candidate" ]] || candidates+=("${candidate:A}")
    done
  else
    # macOS 常见卷不区分大小写，PATH 的 Emulator 可能实际是 Android emulator。
    # 收集所有路径并逐个验证能力，不能让首个同名工具遮蔽真正的 DevEco。
    for candidate in /Applications/DevEco*.app/Contents/tools/emulator/Emulator(N) "$HOME"/Applications/DevEco*.app/Contents/tools/emulator/Emulator(N); do
      [[ ! -f "$candidate" || ! -x "$candidate" ]] || candidates+=("${candidate:A}")
    done
    for candidate in "$HS_TOOLS_HOME"/clt-*/emulator/Emulator(N); do
      [[ ! -f "$candidate" || ! -x "$candidate" ]] || candidates+=("${candidate:A}")
    done
    for directory in "${path[@]}"; do
      [[ -n "$directory" ]] || continue
      candidate="$directory/Emulator"
      [[ ! -f "$candidate" || ! -x "$candidate" ]] || candidates+=("${candidate:A}")
    done
  fi
  candidates=("${(@u)candidates}")
  for candidate in "${candidates[@]}"; do
    HS_BIN="$candidate"
    hs_log "ℹ 检查候选工具：$candidate"
    if hs_check_capabilities >/dev/null 2>&1; then
      compatible+=("$candidate")
    else
      hs_log "ℹ 已排除不兼容候选：$candidate"
    fi
  done
  HS_BIN=""
  if (( ${#compatible[@]} == 0 )); then
    [[ -n "$requested$root" ]] || HS_CAN_BOOTSTRAP=1
    hs_error '未找到支持新建 Harmony 模拟器的 DevEco Emulator；Android SDK 的 emulator 不能用于此入口。'
    hs_log '请安装 DevEco Studio 6.1.0 Beta1+，在 Tools → Device Manager → Local Emulator 准备工具与 Release 镜像后重试。'
    hs_log '若已安装到其它位置，可用 HARMONY_EMULATOR_BIN 指定官方 Emulator，或 DEVECO_STUDIO_HOME 指定安装目录。'
    hs_log "官方说明：$HS_OFFICIAL_URL"
    return 1
  fi
  if (( ${#compatible[@]} > 1 )); then
    hs_error "找到 ${#compatible[@]} 个兼容 DevEco Emulator；请用 HARMONY_EMULATOR_BIN 明确指定其中一个。"
    for candidate in "${compatible[@]}"; do hs_log "  $candidate"; done
    return 1
  fi
  HS_BIN="${compatible[1]}"
}

# SDL 包固定版本、大小和快照 SHA-256；先验证再解压，下载内容不会直接执行。
hs_validate_clt_archive() {
  local archive="$1" actual="" listing=""
  actual="$(/usr/bin/stat -f %z "$archive")" || return 1
  [[ "$actual" == "$HS_CLT_SIZE" ]] || { hs_error 'SDL 工具包大小不符，未解压。'; return 1; }
  actual="$(/usr/bin/shasum -a 256 "$archive")" || return 1
  [[ "${actual%% *}" == "$HS_CLT_SHA256" ]] || { hs_error 'SDL 工具包 SHA-256 不符，未解压；请核对下载版本。'; return 1; }
  listing="$(/usr/bin/unzip -Z1 "$archive")" || return 1
  print -r -- "$listing" | /usr/bin/awk '
    !/^(command-line-tools|__MACOSX)\// || /(^|\/)\.\.?(\/|$)/ || /\\/ || /\/\// || /[[:cntrl:]]/ { bad=1 }
    END { exit bad }
  ' || { hs_error 'SDL 工具包包含不安全路径，未解压。'; return 1; }
}

hs_download_clt_archive_once() {
  local destination="$1"
  /usr/bin/curl -q --fail --show-error --location --progress-bar --retry 3 --connect-timeout 20 \
    --continue-at - --max-time 3600 --speed-limit 1024 --speed-time 90 --max-filesize "$HS_CLT_SIZE" \
    --proto '=https' --proto-redir '=https' --output "$destination" "$HS_CLT_URL" 2>&1 | /usr/bin/tee -a "$HS_LOG"
  local result=${pipestatus[1]}
  (( result == 0 )) || {
      hs_error "SDL 下载失败；可手动下载同一 ZIP 并用 HARMONY_CLT_ARCHIVE 指定：$HS_CLT_URL"
      return "$result"
    }
}

hs_download_clt_archive() {
  jobs_sdk_retry 'Harmony CLT 工具包下载' "$HS_LOG" hs_download_clt_archive_once "$@"
}

hs_publish_clt() {
  /usr/bin/osascript -l JavaScript - "$1" "$2" <<'JXA'
ObjC.import('Foundation');
function run(args) {
  var error = Ref();
  if (!$.NSFileManager.defaultManager.moveItemAtPathToPathError(args[0], args[1], error)) {
    throw Error('CLT 目录发布失败；不会覆盖或嵌入已有目录。');
  }
}
JXA
}

hs_cleanup_install() {
  if [[ -n "$HS_INSTALL_STAGE" && "$HS_INSTALL_STAGE" == "$HS_TOOLS_HOME"/.install.* && -d "$HS_INSTALL_STAGE" && ! -L "$HS_INSTALL_STAGE" ]]; then
    /bin/rm -rf -- "$HS_INSTALL_STAGE"
  fi
  HS_INSTALL_STAGE=""
}

hs_perform_clt_install() {
  local stage="$HS_INSTALL_STAGE" archive="${HARMONY_CLT_ARCHIVE:-}" root="" entry="" destination=""
  hs_log "📥 SDL 第三方免登录镜像：$HS_CLT_URL"
  hs_log "ℹ CLT $HS_CLT_VERSION；$HS_CLT_SIZE 字节；快照 SHA-256：$HS_CLT_SHA256"
  hs_log 'ℹ 该摘要固定 SDL 镜像内容，不代表已比对华为官方摘要；包内不含可启动的系统镜像。'
  if [[ -n "$archive" ]]; then
    [[ -f "$archive" ]] || { hs_error 'HARMONY_CLT_ARCHIVE 指定的文件不存在。'; return 1; }
    hs_log "ℹ 使用本地归档：$archive"
  else
    archive="$stage/tools.zip"
    hs_download_clt_archive "$archive" || return 1
  fi
  hs_validate_clt_archive "$archive" || return 1
  hs_log '✔ 工具包校验通过，正在解压依赖；这一步可能需要几分钟。'
  /bin/mkdir "$stage/extract" || return 1
  # macOS bsdtar 默认拒绝目录穿越及经符号链接写出解压根目录。
  /usr/bin/tar -xf "$archive" -C "$stage/extract" --no-same-owner --no-same-permissions || return 1
  root="$stage/extract/command-line-tools"
  [[ -d "$root" && ! -L "$root" && -x "$root/emulator/Emulator" && ! -L "$root/emulator/Emulator" && -f "$root/version.txt" ]] || {
    hs_error 'SDL 包缺少完整 Emulator 或版本文件，未安装。'; return 1
  }
  for entry in "$root"/**/*(ND@); do
    [[ "${entry:A}" == "${root:A}"/* ]] || { hs_error '工具包存在指向安装目录外的符号链接，未安装。'; return 1; }
  done
  HS_BIN="$root/emulator/Emulator"
  if (( HS_TOOLS_ONLY )); then
    [[ -d "$root/sdk/default/openharmony/ets" && -d "$root/sdk/default/openharmony/native" && -x "$root/sdk/default/openharmony/toolchains/hdc" ]] || {
      hs_error 'CLT 包缺少真机所需 OpenHarmony SDK，未安装。'; HS_BIN=""; return 1
    }
  else
    hs_check_capabilities || { HS_BIN=""; return 1; }
  fi
  destination="$HS_TOOLS_HOME/clt-$HS_CLT_VERSION-${${stage:t}#.install.}"
  hs_publish_clt "$root" "$destination" || { HS_BIN=""; return 1; }
  HS_BIN="$destination/emulator/Emulator"
  HARMONY_EMULATOR_BIN="$HS_BIN"
  hs_log "✔ SDL 工具依赖已安装并通过能力复检：$destination"
}

hs_install_clt() {
  setopt LOCAL_TRAPS
  local result=0
  trap 'hs_cleanup_install; return 130' INT TERM HUP
  [[ ! -L "$HS_TOOLS_HOME" && ( ! -e "$HS_TOOLS_HOME" || -d "$HS_TOOLS_HOME" ) ]] || { hs_error '工具安装根目录不是普通目录，停止。'; return 1; }
  /bin/mkdir -p "$HS_TOOLS_HOME" || return 1
  HS_INSTALL_STAGE="$(umask 077; /usr/bin/mktemp -d "$HS_TOOLS_HOME/.install.XXXXXX")" || return 1
  hs_perform_clt_install || result=$?
  hs_cleanup_install
  return "$result"
}

# 将用户选择保留在本次进程；路径只作为参数，不执行 shell 展开或命令。
hs_read_tool_location() {
  local location=""
  IFS= read -r "location?$(jobs_prompt_render '粘贴 DevEco .app / CLT 目录或 Emulator 文件路径（回车返回）：')" || return 130
  [[ -n "$location" ]] || return 0
  location="${(Q)location}"
  [[ "$location" != '~/'* ]] || location="$HOME/${location#\~/}"
  [[ "$location" == /* && "$location" != *[[:cntrl:]]* ]] || { hs_error '请输入现有的绝对路径；不会执行路径中的命令。'; return 1; }
  if [[ -d "$location" ]]; then
    HARMONY_EMULATOR_BIN=""
    DEVECO_STUDIO_HOME="$location"
    TOOL_HOME=""
  elif [[ -f "$location" && -x "$location" ]]; then
    HARMONY_EMULATOR_BIN="$location"
  else
    hs_error "路径不存在或不是可用工具：$location"
    return 1
  fi
}

# 显式工具路径有误时保留手动恢复入口；正常缺镜像直接走官方下载。
hs_preparation_prompt() {
  local answer="" result=0
  while true; do
    hs_log '━━━━━━━━━━ Harmony 环境准备 ━━━━━━━━━━'
    hs_log '尚未具备可用工具。SDL 可免登录下载 CLT；华为官方下载中心需要账号登录。'
    hs_log '1、从 SDL 镜像安装 Mac ARM64 CLT 6.1.1.280（约 2.03 GB）'
    hs_log '3、打开华为官方下载页（备选）'
    hs_log '2、指定已经安装 / 解压的 DevEco .app、CLT 目录或 Emulator 文件'
    jobs_prompt_output hs_log '回车：准备完成，重新检查并继续；q：取消本次操作。'
    IFS= read -r 'answer?选择：' || return 130
    case "$answer" in
      '') return 0 ;;
      q|Q|$'\e') return 130 ;;
      1)
        hs_install_clt || return $?
        return 0
        ;;
      3)
        /usr/bin/open "$HS_DOWNLOAD_URL" || hs_log "⚠ 自动打开失败，请访问：$HS_DOWNLOAD_URL"
        jobs_prompt_output hs_log 'ℹ 终端保留在此；完成准备后回车复检。'
        ;;
      2)
        result=0
        hs_read_tool_location || result=$?
        (( result != 130 )) || return 130
        (( result != 0 )) || return 0
        ;;
      *) hs_log '请输入对应编号，或回车复检；q 取消。' ;;
    esac
  done
}

hs_prepare_environment() {
  local result=0
  while true; do
    result=0
    hs_find_emulator || result=$?
    if (( result != 0 )); then
      (( ! HS_CHECK )) || return "$result"
      if (( HS_CAN_BOOTSTRAP )); then
        hs_install_clt || return $?
        continue
      fi
      hs_preparation_prompt tools || return $?
      continue
    fi
    hs_log "ℹ 已确认官方兼容工具能力：$HS_BIN"
    hs_query_state || return $?
    # --check 如实报告数量；只有交互创建 / 准备需要等待镜像就绪。
    (( ! HS_CHECK )) || return 0
    (( ${#HS_ROWS[@]} == 0 )) || return 0
    hs_install_image
    return $?
  done
}

# 真机只需要工具链；健康 SDK 不以模拟器的 -create 能力或系统镜像为前提。
hs_find_toolchain_root() {
  local candidate="${DEVECO_STUDIO_HOME:-${TOOL_HOME:-}}" sdk="" location="" selected=""
  local -a roots=() usable=()
  if [[ -n "$candidate" ]]; then
    [[ ! -d "$candidate/Contents" ]] || candidate+='/Contents'
    roots=("$candidate")
  else
    roots=(/Applications/DevEco*.app/Contents(N/) "$HOME"/Applications/DevEco*.app/Contents(N/) "$HS_TOOLS_HOME"/clt-*(N/))
  fi
  for location in "${roots[@]}"; do
    sdk="${OHOS_SDK_HOME:-${DEVECO_SDK_HOME:-$location/sdk}/default/openharmony}"
    [[ -d "$sdk/ets" && -d "$sdk/native" && -x "$sdk/toolchains/hdc" ]] || continue
    usable+=("${location:A}")
  done
  (( ${#usable[@]} )) || return 3
  if (( ${#usable[@]} == 1 )); then
    HS_TOOLCHAIN_ROOT="${usable[1]}"
  else
    selected="$(hs_choose '选择鸿蒙工具链' "${usable[@]}")" || return $?
    (( ${usable[(Ie)$selected]} > 0 )) || return 2
    HS_TOOLCHAIN_ROOT="$selected"
  fi
}

hs_prepare_tools_only() {
  local result=0 installed=0 receipt="${JOBS_HARMONY_TOOLS_RECEIPT:-}" sdk=""
  HS_TOOLCHAIN_ROOT=""
  hs_find_toolchain_root || result=$?
  if (( result != 0 )); then
    (( result == 3 )) || return "$result"
    [[ -z "${DEVECO_STUDIO_HOME:-${TOOL_HOME:-}}${DEVECO_SDK_HOME:-}${OHOS_SDK_HOME:-}" ]] || { hs_error '指定工具目录缺少完整 SDK；保留显式选择，未安装另一套工具覆盖。'; return 1; }
    hs_install_clt || return $?
    HS_TOOLCHAIN_ROOT="${HS_BIN:h:h}"
    installed=1
  fi
  if (( installed )); then
    hs_review_licenses || return $?
  fi
  [[ "$HS_TOOLCHAIN_ROOT" == /* && "$HS_TOOLCHAIN_ROOT" != *[[:cntrl:]]* && -d "$HS_TOOLCHAIN_ROOT" ]] || return 1
  sdk="${OHOS_SDK_HOME:-${DEVECO_SDK_HOME:-$HS_TOOLCHAIN_ROOT/sdk}/default/openharmony}"
  [[ -d "$sdk/ets" && -d "$sdk/native" && -x "$sdk/toolchains/hdc" ]] || { hs_error '工具包没有完整的配套 OpenHarmony SDK，保留安装现场且未报告准备成功。'; return 1; }
  if [[ -n "$receipt" ]]; then
    [[ "$receipt" == /* && -f "$receipt" && ! -L "$receipt" && "$receipt" != *[[:cntrl:]]* ]] || { hs_error '工具链回执须为调用方已创建的普通文件。'; return 1; }
    print -r -- "$HS_TOOLCHAIN_ROOT" > "$receipt" || return 1
  fi
  hs_log "✔ 鸿蒙 CLT / SDK 工具已就绪：$HS_TOOLCHAIN_ROOT；未下载镜像、创建或启动设备。"
}

# 已展示原文并取得本次明确同意后，才调用官方接受命令；不在首屏隐含接受协议。
hs_review_licenses() {
  (( ! HS_LICENSES_CONFIRMED )) || return 0
  local directory="${HS_BIN:h}/agreement" file="" answer=""
  local -a files=("$directory/HarmonyOS_SDK_Agreement.txt" "$directory/HarmonyOS_Software_Service_Agreement.txt")
  for file in "${files[@]}"; do
    [[ -s "$file" && -r "$file" ]] || { hs_error "找不到可供阅读的官方许可：$file；未接受许可。"; return 1; }
  done
  for file in "${files[@]}"; do
    hs_log "━━━━━━━━━━ 官方许可原文：$file ━━━━━━━━━━"
    /bin/cat "$file" || return $?
    print
  done
  IFS= read -r "answer?$(jobs_prompt_render '阅读以上全部协议后，回车表示本人同意并继续；任意非空输入取消：')" || return 130
  [[ -z "$answer" ]] || return 130
  hs_run_command -license accept || return $?
  HS_LICENSES_CONFIRMED=1
}

hs_install_image() {
  local catalog="" parsed="" selected="" type="" version="" answer="" row="" found=0 result=0
  local -a available=()
  hs_log 'ℹ 没有本地 Release 镜像，正在读取官方可下载清单（最长 60 秒）…'
  catalog="$(jobs_sdk_retry 'Harmony 官方系统镜像清单' "$HS_LOG" hs_remote_catalog_once)" || return $?
  parsed="$(hs_json available "$catalog")" || { hs_error '官方可下载镜像清单解析失败，未下载或创建。'; return 1; }
  [[ -n "$parsed" ]] || { hs_error '官方没有返回可下载的 Release 镜像，请在 DevEco Device Manager 核对网络或账号要求。'; return 1; }
  available=("${(@f)parsed}")
  selected="$(hs_choose '下载系统镜像（默认最新稳定版手机；可能数 GB）' "${available[@]}")" || return $?
  (( ${available[(Ie)$selected]} )) || { hs_error '选择器返回了无效下载镜像。'; return 2; }
  type="${selected%%$'\t'*}"
  version="${${selected#*$'\t'}%%$'\t'*}"
  hs_log "📥 官方 Emulator 下载：$type / $version；目录沿用 DevEco 既有配置。"
  IFS= read -r "answer?$(jobs_prompt_render '回车下载此镜像；任意非空输入取消：')" || return 130
  [[ -z "$answer" ]] || return 130
  hs_review_licenses || return $?
  # 只在用户确认的新镜像安装中跳过重复确认；创建、启动均不使用 -force。
  jobs_sdk_retry "Harmony 系统镜像 ${type} / ${version}" "$HS_LOG" hs_install_image_once "$type" "$version" || result=$?
  if (( result != 0 )); then
    hs_log '下载已停止。请查看上方原始错误与日志；用户取消或明确环境错误不会继续下游。'
    return "$result"
  fi
  hs_query_state || return $?
  for row in "${HS_ROWS[@]}"; do
    if [[ "${row%%$'\t'*}" == "$type" && "${${row#*$'\t'}%%$'\t'*}" == "$version" ]]; then
      HS_PREFERRED_ROW="$row"
      found=1
      break
    fi
  done
  (( found )) || { hs_error '官方安装命令返回，但选中镜像仍未下载就绪；请查看上方许可、网络或账号提示。未创建，不循环复检。'; return 1; }
  hs_log "✔ 已验证下载镜像：$type / $version"
}

# 官方安装 exit 0 仍须看到精确镜像；缺失时继续获取，绝不创建未就绪设备。
hs_install_image_once() {
  local type="$1" version="$2" output="" parsed="" row=""
  hs_run_command -install -deviceType "$type" -osVersion "$version" -force || return $?
  output="$(hs_query_output -imageList -downloaded true)" || return $?
  parsed="$(hs_json images "$output")" || { hs_error 'invalid argument：本地镜像清单 JSON 无效。'; return 2; }
  for row in "${(@f)parsed}"; do
    if [[ "${row%%$'\t'*}" == "$type" && "${${row#*$'\t'}%%$'\t'*}" == "$version" ]]; then
      return 0
    fi
  done
  hs_log '⚠ SDK 获取未就绪：官方安装返回成功，但选定镜像尚未出现在本地清单；将继续获取。'
  return 1
}

# 远程清单输出供 JSON 解析；重试提示只走标准错误。
hs_remote_catalog_once() {
  local output="" result=0
  output="$(hs_query_output -imageList -downloaded false 2>&1)" || result=$?
  print -r -- "$output" >> "${HS_LOG:-/dev/null}"
  if (( result != 0 )); then
    print -u2 -r -- "$output"
    return "$result"
  fi
  if ! hs_json available "$output" >/dev/null 2>> "${HS_LOG:-/dev/null}"; then
    print -u2 -r -- "$output"
    hs_log '⚠ 官方远程清单尚未返回有效镜像 JSON，将继续获取。' >&2
    return 1
  fi
  print -r -- "$output"
}

# 只对 -help 只读探测设限；创建和启动保留官方交互，不施加该超时。
hs_probe_help() {
  local child_pid watchdog_pid result=0
  "$HS_BIN" -help &
  child_pid=$!
  ( /bin/sleep 15; kill -TERM "$child_pid" 2>/dev/null; /bin/sleep 1; kill -KILL "$child_pid" 2>/dev/null ) >/dev/null 2>&1 &
  watchdog_pid=$!
  wait "$child_pid" 2>/dev/null || result=$?
  kill -TERM "$watchdog_pid" 2>/dev/null
  wait "$watchdog_pid" 2>/dev/null
  (( result < 128 )) || print -u2 -r -- 'Emulator -help 超时或被终止（15 秒）。'
  return "$result"
}

hs_check_capabilities() {
  local help_text="" result=0
  help_text="$(hs_probe_help 2>&1)" || result=$?
  (( result == 0 )) || { hs_error "Emulator -help 失败，退出码 $result：$help_text"; return "$result"; }
  print -r -- "$help_text" | /usr/bin/grep -Eqi -- '(^|[^[:alnum:]_-])-create([^[:alnum:]_-]|$)' &&
    print -r -- "$help_text" | /usr/bin/grep -Eqi -- '(^|[^[:alnum:]_-])-imageList([^[:alnum:]_-]|$)' || {
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
  if (mode !== 'images' && mode !== 'available' && records && !Array.isArray(records) && typeof records === 'object' && typeof records.name === 'string') records = [records];
  if (!Array.isArray(records)) throw new Error('Expected official JSON array for ' + mode);
  function text(value, field) {
    if (typeof value !== 'string' || !value || /[\u0000-\u001f\u007f-\u009f]/.test(value)) throw new Error('Invalid ' + field);
    return value;
  }
  var output = [], seen = Object.create(null);
  records.forEach(function(item) {
    if (!item || typeof item !== 'object' || Array.isArray(item)) throw new Error('Invalid record');
    var line;
    if (mode === 'images' || mode === 'available') {
      var type = text(item.deviceType, 'deviceType'), os = text(item.osVersion, 'osVersion');
      if (os.charAt(0) === '-') throw new Error('Invalid osVersion option');
      var software = text(item.SoftWareVersion, 'SoftWareVersion'), release = text(item.releaseType, 'releaseType');
      if (item.downloaded !== true && item.downloaded !== false && item.downloaded !== 'true' && item.downloaded !== 'false') throw new Error('Invalid downloaded');
      if (String(item.downloaded) !== (mode === 'images' ? 'true' : 'false') || release.toLowerCase() !== 'release') return;
      if (!/^(?:[A-Za-z][A-Za-z0-9_-]*|2in1(?: Foldable)?)$/i.test(type)) throw new Error('Invalid deviceType');
      line = type + '\t' + os + '\t' + software;
    } else if (mode === 'names') {
      line = text(item.name, 'name');
    } else if (mode === 'instancePath') {
      if (text(item.name, 'name') !== argv[2]) return;
      line = text(item.instancePath, 'instancePath');
    } else if (mode === 'connection') {
      if (text(item.name, 'name') !== argv[2]) return;
      var flatPort = item['hw.hdc.port'], nestedPort = item.hw && item.hw.hdc && item.hw.hdc.port;
      if (flatPort !== undefined && nestedPort !== undefined && String(flatPort) !== String(nestedPort)) throw new Error('Conflicting hw.hdc.port representations');
      var port = flatPort !== undefined ? flatPort : nestedPort;
      if (String(item.isRunning) !== 'true' || port === undefined) {
        line = 'waiting';
      } else {
        if (!/^[0-9]+$/.test(String(port)) || Number(port) < 1 || Number(port) > 65535) throw new Error('Invalid hw.hdc.port');
        records.forEach(function(other) {
          if (other === item || String(other.isRunning) !== 'true') return;
          var otherPort = other['hw.hdc.port'] !== undefined ? other['hw.hdc.port'] : other.hw && other.hw.hdc && other.hw.hdc.port;
          if (Number(otherPort) === Number(port)) throw new Error('HDC port shared by multiple instances');
        });
        var sdk = item.sdkPath === undefined || item.sdkPath === '' ? '' : text(item.sdkPath, 'sdkPath');
        line = '127.0.0.1:' + Number(port) + '\t' + sdk + '\t' + text(item.instancePath, 'instancePath');
      }
    } else if (mode === 'verify') {
      var name = text(item.name, 'name');
      if (name !== argv[2]) return;
      if (text(item.deviceType, 'deviceType').toLowerCase() !== argv[3].toLowerCase()) throw new Error('Created deviceType differs');
      var flatVersion = item['os.osVersion'], nestedVersion = item.os && item.os.osVersion;
      if (flatVersion !== undefined && nestedVersion !== undefined && flatVersion !== nestedVersion) throw new Error('Conflicting os.osVersion representations');
      if (text(flatVersion !== undefined ? flatVersion : nestedVersion, 'os.osVersion') !== argv[4]) throw new Error('Created osVersion differs');
      line = name;
    } else throw new Error('Unknown mode');
    if (seen[line] && mode !== 'images' && mode !== 'available') throw new Error('Duplicate instance name');
    if (!seen[line]) output.push(line);
    seen[line] = true;
  });
  if ((mode === 'verify' || mode === 'instancePath' || mode === 'connection') && output.length !== 1) throw new Error('Created instance not uniquely listed');
  if (mode === 'images' || mode === 'available') output.sort(function(a, b) {
    var left = a.split('\t'), right = b.split('\t');
    var phone = Number(right[0].toLowerCase() === 'phone') - Number(left[0].toLowerCase() === 'phone');
    if (phone) return phone;
    if (left[0] !== right[0]) return left[0].localeCompare(right[0]);
    var av = left[1].match(/\d+/g) || [], bv = right[1].match(/\d+/g) || [];
    for (var i = 0; i < Math.max(av.length, bv.length); i++) {
      var delta = Number(bv[i] || 0) - Number(av[i] || 0);
      if (delta) return delta;
    }
    return a.localeCompare(b);
  });
  return output.join('\n');
}
JAVASCRIPT
}

hs_query_state() {
  local result=0 parsed=""
  HS_IMAGES="$(hs_query_output -imageList -downloaded true)" || result=$?
  (( result == 0 )) || { hs_error "Emulator -imageList 失败，退出码 $result。"; return "$result"; }
  parsed="$(hs_json images "$HS_IMAGES")" || { hs_error '镜像 JSON 无法按官方字段解析，未创建模拟器。'; return 1; }
  HS_ROWS=("${(@f)parsed}")
  [[ -n "$parsed" ]] || HS_ROWS=()
  result=0
  HS_INSTANCES="$(hs_query_output -list -details)" || result=$?
  (( result == 0 )) || { hs_error "Emulator -list -details 失败，退出码 $result。"; return "$result"; }
  parsed="$(hs_json names "$HS_INSTANCES")" || { hs_error '实例 JSON 无法按官方字段解析，停止以保护已有设备。'; return 1; }
  HS_NAMES=("${(@f)parsed}")
  [[ -n "$parsed" ]] || HS_NAMES=()
  hs_log "ℹ 已下载 Release 镜像：${#HS_ROWS[@]}；已有实例：${#HS_NAMES[@]}。"
}

# 6.1.1.200 实测空清单使用这两种非 JSON 响应；只接受退出码 0 与精确文案。
hs_query_output() {
  local output="" result=0
  output="$(hs_bounded_query "$@" 2>&1)" || result=$?
  if (( result != 0 )); then print -u2 -r -- "$output"; return "$result"; fi
  if [[ "$1" == '-imageList' && "$output" == 'No images matching the criteria were found.' ]]; then
    print -r -- '[]'
  elif [[ "$*" == '-list -details' && "$output" == '[Empty]' ]]; then
    print -r -- '[]'
  else
    print -r -- "$output"
  fi
}

hs_bounded_query() {
  local child_pid watchdog_pid result=0 started=$SECONDS
  "$HS_BIN" "$@" &
  child_pid=$!
  ( /bin/sleep 60; kill -TERM "$child_pid" 2>/dev/null; /bin/sleep 1; kill -KILL "$child_pid" 2>/dev/null ) >/dev/null 2>&1 &
  watchdog_pid=$!
  wait "$child_pid" 2>/dev/null || result=$?
  kill -TERM "$watchdog_pid" 2>/dev/null
  wait "$watchdog_pid" 2>/dev/null
  if (( result >= 128 && result != 130 && SECONDS - started >= 60 )); then
    print -u2 -r -- 'Emulator 查询超时或被终止（60 秒）。'
    result=124
  fi
  return "$result"
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
  jobs_prompt_output print -u2 -r -- "$prompt（回车选 1；输入 q 取消）："
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
  local row="" selected="" proposed="" answer="" name_type="" suffix=1
  local -a types=() versions=()
  (( ${#HS_ROWS[@]} )) || {
    hs_error '本地镜像复检为空，无法继续创建；请查看前面的下载诊断。'
    hs_log "官方说明：$HS_OFFICIAL_URL"
    return 1
  }
  if [[ -n "$HS_PREFERRED_ROW" ]]; then
    (( ${HS_ROWS[(Ie)$HS_PREFERRED_ROW]} )) || { hs_error '刚下载的镜像未通过本地复检。'; return 1; }
    HS_TYPE="${HS_PREFERRED_ROW%%$'\t'*}"
    selected="${HS_PREFERRED_ROW#*$'\t'}"
  else
    for row in "${HS_ROWS[@]}"; do types+=("${row%%$'\t'*}"); done
    types=("${(@u)types}")
    HS_TYPE="$(hs_choose '设备类型' "${types[@]}")" || return $?
    (( ${types[(Ie)$HS_TYPE]} )) || { hs_error '选择器返回了无效设备类型。'; return 2; }
    for row in "${HS_ROWS[@]}"; do
      [[ "${row%%$'\t'*}" != "$HS_TYPE" ]] || versions+=("${row#*$'\t'}")
    done
    selected="$(hs_choose '已下载 Release 镜像（系统版本 / 详细版本）' "${versions[@]}")" || return $?
    (( ${versions[(Ie)$selected]} )) || { hs_error '选择器返回了无效镜像。'; return 2; }
  fi
  HS_VERSION="${selected%%$'\t'*}"
  if [[ -z "$HS_NAME" ]]; then
    name_type="${HS_TYPE//[^a-zA-Z0-9]/_}"
    proposed="JobsHarmony_${name_type[1,24]}_$(/bin/date +%Y%m%d_%H%M%S)"
    HS_NAME="$proposed"
    while hs_name_exists "$HS_NAME" "${HS_NAMES[@]}"; do
      HS_NAME="${proposed}_${suffix}"
      suffix=$((suffix + 1))
    done
    print -r -- "ℹ 默认唯一名称：$HS_NAME"
    IFS= read -r "answer?$(jobs_prompt_render '模拟器名称（回车使用默认）：')" || return 130
    [[ -z "$answer" ]] || HS_NAME="$answer"
  fi
  hs_valid_name "$HS_NAME" || { hs_error '名称无效：须以英文字母开头，仅含英文字母、数字、空格、下划线或加号，不能以空格结尾，最长 64 字符，不支持连字符 -。未创建模拟器。'; return 2; }
  if hs_name_exists "$HS_NAME" "${HS_NAMES[@]}"; then
    hs_error "已有同名实例：$HS_NAME；不会覆盖。"
    return 1
  fi
}

hs_initialize_log() {
  local directory=""
  umask 077
  directory="$(/usr/bin/mktemp -d "${${TMPDIR:-/tmp}%/}/JobsHarmonySimulator.XXXXXX")" || return 1
  HS_LOG="$directory/CreateHarmonySimulator.log"
  : > "$HS_LOG" || return 1
  hs_log "ℹ 日志：$HS_LOG"
}

# 保留 stdin 和原始退出码；-force 仅用于本人确认后的镜像安装。
hs_run_command() {
  local result=0
  "$HS_BIN" "$@" 2>&1 | /usr/bin/tee -a "$HS_LOG" || result=$?
  (( result == 0 )) || { hs_error "Emulator $1 失败，退出码 $result；保留现场，不删除实例。"; return "$result"; }
}

# 独立 CLT 的 SDK 与 emulator 同级；官方默认推导沿用 Studio 的 tools/emulator 层级，
# 会少一层。只为本次已核验的新实例补 sdkPath；不改全局配置或既有实例。
hs_bind_created_sdk() {
  local sdk="${HS_BIN:h:h}/sdk" directory="" config="" temporary="" line="" found_name=0 found_sdk=0
  [[ -x "$sdk/default/openharmony/toolchains/hdc" ]] || return 0
  directory="$(hs_json instancePath "$1" "$HS_NAME")" || return 1
  [[ "$directory" == /* && "${directory:t}" == "$HS_NAME" && -d "$directory" && ! -L "$directory" ]] || {
    hs_error '新实例路径无效，未写入 SDK 配置。'; return 1
  }
  config="$directory/config.ini"
  [[ -f "$config" && ! -L "$config" ]] || { hs_error '新实例 config.ini 不存在或是符号链接，未写入 SDK 配置。'; return 1; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" != name=* ]] || { [[ "$line" == "name=$HS_NAME" ]] || return 1; (( found_name += 1 )); }
    if [[ "$line" == sdkPath=?* || "$line" == harmonyos.sdk.path=?* ]]; then found_sdk=1; fi
  done < "$config"
  (( found_name == 1 )) || { hs_error '新实例配置中的名称不一致，未写入 SDK 配置。'; return 1; }
  (( ! found_sdk )) || return 0
  temporary="$(/usr/bin/mktemp "$directory/.jobs-sdk.XXXXXX")" || return 1
  if /bin/cp -p "$config" "$temporary" && /usr/bin/awk '!/^sdkPath=\r?$/ && !/^harmonyos.sdk.path=\r?$/' "$config" > "$temporary" &&
      print -r -- "sdkPath=${sdk:A}" >> "$temporary" && /bin/mv -f "$temporary" "$config"; then
    hs_log "✔ 已为新实例配置 CLT SDK：${sdk:A}"
  else
    /bin/rm -f "$temporary"
    hs_error '写入新实例 SDK 路径失败；保留实例，未启动。'; return 1
  fi
}

# 仅向父运行器预建的空普通文件交接已由同实例 HDC 验证的精确目标。
hs_publish_created_device() (
  local created_file="${JOBS_FLUTTER_CREATED_DEVICE_FILE:-}" created_fd="" result=0
  [[ -n "$created_file" ]] || return 0
  if [[ ! -f "$created_file" || -L "$created_file" || -s "$created_file" || ! -O "$created_file" ]]; then
    hs_error "设备交接文件无效；须为本用户预建的空普通文件：$created_file"
    return 1
  fi
  if ! cd -- "${created_file:h}" || ! zmodload zsh/system || ! sysopen -w -o nofollow,nonblock -u created_fd "${created_file:t}"; then
    hs_error "无法打开设备交接文件：$created_file"
    return 1
  fi
  if [[ -f "/dev/fd/$created_fd" && ! -s "/dev/fd/$created_fd" && -O "/dev/fd/$created_fd" ]]; then
    print -r -- $'harmony\t'"$1" >&$created_fd || result=1
  else
    result=1
  fi
  exec {created_fd}>&-
  (( result == 0 )) || hs_error "设备交接失败；保留实例，请重新选择：$created_file"
  return "$result"
)
# SDK 仅来自该新实例元数据或配置；冲突时拒绝使用其它全局 HDC。
hs_created_instance_hdc() {
  local sdk="$1" directory="$2" config="" configured="" candidate="" line="" names=0
  if [[ "$directory" == /* && "${directory:t}" == "$HS_NAME" && -d "$directory" && ! -L "$directory" ]]; then
    config="$directory/config.ini"
    if [[ -f "$config" && ! -L "$config" ]]; then
      while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        if [[ "$line" == name=* ]]; then
          [[ "$line" == "name=$HS_NAME" ]] || return 1
          (( names += 1 ))
        fi
        if [[ "$line" == sdkPath=?* || "$line" == harmonyos.sdk.path=?* ]]; then
          candidate="${line#*=}"
          [[ -z "$configured" || "$configured" == "$candidate" ]] || return 1
          configured="$candidate"
        fi
      done < "$config"
      (( names == 1 )) || return 1
    fi
  fi
  if [[ -n "$sdk" && -n "$configured" && "${sdk:A}" != "${configured:A}" ]]; then
    return 1
  fi
  [[ -n "$sdk" ]] || sdk="$configured"
  [[ "$sdk" == /* && "$sdk" != *[[:cntrl:]]* && -d "$sdk" ]] || return 1
  for candidate in "$sdk/default/openharmony/toolchains/hdc" "$sdk/openharmony/toolchains/hdc" "$sdk/toolchains/hdc" "$sdk/default/harmonyos/toolchains/hdc" "$sdk/harmonyos/toolchains/hdc"; do
    [[ ! -f "$candidate" || ! -x "$candidate" ]] || { print -r -- "$candidate"; return 0; }
  done
  return 1
}
# HDC 查询设短超时，未确认目标时不会写入自动运行回执。
hs_created_hdc_targets() {
  local child_pid="" watchdog_pid="" result=0 started=$SECONDS
  "$1" list targets &
  child_pid=$!
  ( /bin/sleep 10; kill -TERM "$child_pid" 2>/dev/null; /bin/sleep 1; kill -KILL "$child_pid" 2>/dev/null ) >/dev/null 2>&1 &
  watchdog_pid=$!
  wait "$child_pid" 2>/dev/null || result=$?
  kill -TERM "$watchdog_pid" 2>/dev/null
  wait "$watchdog_pid" 2>/dev/null
  if (( result >= 128 && result != 130 && SECONDS - started >= 10 )); then
    result=124
  fi
  return "$result"
}
# 只等待本次新实例：官方端口、同实例 SDK 的 HDC 和父运行器的 Flutter 识别逐层核验。
hs_wait_and_publish_created_device() {
  [[ -n "${JOBS_FLUTTER_CREATED_DEVICE_FILE:-}" ]] || return 0
  local limit="${JOBS_HARMONY_CREATED_DEVICE_WAIT_SECONDS:-240}" started=$SECONDS current="" connection="" identity="" remainder="" sdk="" directory="" hdc="" targets="" result=0
  [[ "$limit" == <-> ]] && (( limit <= 3600 )) || { hs_error '新设备等待时限无效。'; return 2; }
  hs_log "ℹ 等待新实例 $HS_NAME 的精确 HDC 目标（最多 ${limit} 秒），随后交给 Flutter 识别。"
  while true; do
    result=0
    current="$(hs_query_output -list -details)" || result=$?
    case "$result" in 129|130|143) return "$result" ;; esac
    if (( result == 0 )); then
      connection="$(hs_json connection "$current" "$HS_NAME" 2>> "${HS_LOG:-/dev/null}")" || connection=""
      if [[ -n "$connection" && "$connection" != waiting ]]; then
        identity="${connection%%$'\t'*}"
        remainder="${connection#*$'\t'}"
        sdk="${remainder%%$'\t'*}"
        directory="${remainder#*$'\t'}"
        hdc="$(hs_created_instance_hdc "$sdk" "$directory")" || hdc=""
        if [[ -n "$hdc" ]]; then
          result=0
          targets="$(hs_created_hdc_targets "$hdc")" || result=$?
          case "$result" in 129|130|143) return "$result" ;; esac
          if (( result == 0 )) && print -r -- "$targets" | /usr/bin/tr -d '\r' | /usr/bin/grep -Fxq -- "$identity"; then
            hs_log "✔ 已确认新实例 HDC 目标：$identity"
            hs_publish_created_device "$identity"
            return $?
          fi
        else
          hs_log '⚠ 新实例已保留；未找到该实例 SDK 对应的 HDC 或 SDK 配置冲突，不自动选择其它设备。'
          return 0
        fi
      fi
    fi
    (( SECONDS - started < limit )) || break
    /bin/sleep 3
  done
  hs_log '⚠ 新实例已保留；尚未确认实例对应的 HDC 目标，不自动选择其它设备。请在 Flutter 识别后从已有设备中选择。'
  return 0
}

hs_create_and_verify() {
  local answer="" result=0 current="" parsed=""
  hs_log "来源：Huawei DevEco Emulator；工具：$HS_BIN"
  hs_log "目标：DevEco 当前默认实例目录；名称：$HS_NAME；设备：$HS_TYPE；镜像：$HS_VERSION"
  IFS= read -r "answer?$(jobs_prompt_render '回车确认新建；输入任意字符取消：')" || return 130
  [[ -z "$answer" ]] || { hs_log '已取消，未创建模拟器。'; return 0; }
  # 确认期间可能有其它进程创建设备，写入前再检查一次命名冲突。
  current="$(hs_query_output -list -details)" || return $?
  parsed="$(hs_json names "$current")" || return 1
  local -a latest_names=("${(@f)parsed}")
  if hs_name_exists "$HS_NAME" "${latest_names[@]}"; then
    hs_error "名称已被其它操作使用：$HS_NAME；停止，不覆盖。"
    return 1
  fi
  hs_run_command -create "$HS_NAME" -deviceType "$HS_TYPE" -osVersion "$HS_VERSION" || return $?
  current="$(hs_query_output -list -details)" || result=$?
  (( result == 0 )) || { hs_error "创建命令已返回，但实例复检失败（退出码 $result），请在 Device Manager 核对。"; return "$result"; }
  hs_json verify "$current" "$HS_NAME" "$HS_TYPE" "$HS_VERSION" >/dev/null || {
    hs_error '创建命令已返回，但未验证到名称、设备类型和系统版本一致的唯一实例；不启动、不删除。'
    return 1
  }
  hs_bind_created_sdk "$current" || return $?
  hs_log "✔ 已验证新建实例：$HS_NAME"
  if (( HS_START )); then
    hs_review_licenses || return $?
    hs_log 'ℹ 即将交给官方启动流程；如官方额外要求账号授权，请按官方提示完成。'
    hs_run_command -start "$HS_NAME" || return $?
    hs_log '✔ 官方启动命令已返回；最终启动状态请查看模拟器窗口与官方输出。'
  fi
  if (( HS_START )); then
    hs_wait_and_publish_created_device || return $?
  elif [[ -n "${JOBS_FLUTTER_CREATED_DEVICE_FILE:-}" ]]; then
    hs_log 'ℹ 新实例未请求启动，不回传 Flutter 自动运行目标。'
  fi
}

hs_dispatch() {
  setopt NO_NOMATCH PIPE_FAIL
  hs_parse "$@" || return $?
  if (( HS_HELP )); then hs_help; return 0; fi
  if (( ! HS_CHECK )) && [[ "$HS_TOOLS_ONLY" != 1 || "${JOBS_HARMONY_RUN_PREPARE:-0}" != 1 ]]; then
    [[ -t 0 ]] || { hs_error '请在可交互终端运行；无交互时只能使用 --check / --help。'; return 1; }
    local answer=""
    IFS= read -r "answer?$(jobs_prompt_render '已了解用途与影响，按回车继续；非空输入 / Ctrl+C 取消：')" || return 130
    [[ -z "$answer" ]] || { hs_log '已取消，未安装工具或创建模拟器。'; return 0; }
  fi
  hs_check_host || return $?
  (( HS_CHECK )) || hs_initialize_log || return $?
  if (( HS_TOOLS_ONLY )); then
    hs_prepare_tools_only
    return $?
  fi
  local result=0
  hs_prepare_environment || result=$?
  if (( result == 130 )); then
    hs_log '已取消环境准备；未创建模拟器。'
    return 0
  fi
  (( result == 0 )) || return "$result"
  if (( HS_CHECK )); then
    hs_log '✔ 只读检查完成；未创建、启动或下载。'
    return 0
  fi
  if (( HS_PREPARE )); then
    hs_log '✔ 官方工具与已下载 Release 镜像已就绪；--prepare 已完成，未创建或启动模拟器。'
    return 0
  fi
  hs_select_image || return $?
  hs_create_and_verify
}

main() {
  if (( ${argv[(Ie)--tools-only]} > 0 )); then
    hs_log '━━━━━━━━━━ 鸿蒙真机运行工具准备 ━━━━━━━━━━'
    hs_log '复用已有 CLT / SDK；缺少时下载固定摘要工具包，本人阅读官方许可后继续；不下载系统镜像或创建设备。'
  else
    hs_show_intro # 先说明用途、影响、平台要求和取消方式。
  fi
  hs_dispatch "$@" # 只读检查或交互选择本地镜像，创建并核验唯一实例。
}

main "$@"
