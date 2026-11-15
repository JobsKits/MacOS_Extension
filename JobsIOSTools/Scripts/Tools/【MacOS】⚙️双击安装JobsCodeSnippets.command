#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】⚙️双击安装JobsCodeSnippets.command
# - 核心用途：检查当前用户 Xcode CodeSnippets，缺失时安装，已有 Git 仓库时保留本地改动并升级。
# - 影响范围：仅当前用户 CodeSnippets 与同级私有备份；不自动 commit、push 或重启 Xcode。
# - 运行提示：先回车确认自述，再输入任意字符执行；--finder 接收 iOS 工程，--check 只读检查。
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
    # 完整颜色帧有界重发；仅退出恢复容忍帧外回车和明确方向键。
    jobs_terminal_style_query() {
        jobs_style_query_key=$1
        jobs_style_reply=''
        jobs_style_query_buffer=''
        jobs_style_query_target_reply=''
        jobs_style_query_target_normalized=''
        jobs_style_query_target_rgb=''
        jobs_style_query_st="${jobs_style_esc}\\"
        jobs_style_query_stale_count=0
        jobs_style_query_phase=${2:-strict}
        jobs_style_query_cr=$(printf '\r')
        jobs_style_query_lf=$(printf '\n.')
        jobs_style_query_lf=${jobs_style_query_lf%.}
        jobs_style_query_failure='未收到目标颜色的完整答复（最多 3 次查询，每次约 2 秒）'
        for jobs_style_query_round in 1 2 3; do
            printf '\033]%s;?\007' "$jobs_style_query_key" > /dev/tty || {
                jobs_style_query_failure='无法向原终端发送配色查询'
                return 1
            }
            for jobs_style_attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
                # 哨兵保留末尾换行，不能把只有回车的键盘输入误当成无答复。
                jobs_style_piece=$(dd bs=256 count=1 2>/dev/null < /dev/tty; printf '.')
                jobs_style_piece=${jobs_style_piece%.}
                jobs_style_query_buffer=$jobs_style_query_buffer$jobs_style_piece
                while [ -n "$jobs_style_query_buffer" ]; do
                    # 仅退出恢复阶段允许帧外的明确控制键，普通文字仍然失败。
                    if [ "$jobs_style_query_phase" = cleanup ]; then
                        jobs_style_query_control_sequence=''
                        jobs_style_query_control_partial=0
                        case $jobs_style_query_buffer in
                            "$jobs_style_query_cr"*) jobs_style_query_control_sequence=$jobs_style_query_cr ;;
                            "$jobs_style_query_lf"*) jobs_style_query_control_sequence=$jobs_style_query_lf ;;
                        esac
                        if [ -z "$jobs_style_query_control_sequence" ]; then
                            for jobs_style_query_direction in A B C D; do
                                for jobs_style_query_control_candidate in \
                                    "${jobs_style_esc}[${jobs_style_query_direction}" \
                                    "${jobs_style_esc}O${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;2${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;3${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;4${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;5${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;6${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;7${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;8${jobs_style_query_direction}"; do
                                    case $jobs_style_query_buffer in
                                        "$jobs_style_query_control_candidate"*)
                                            jobs_style_query_control_sequence=$jobs_style_query_control_candidate
                                            break 2
                                            ;;
                                    esac
                                    case $jobs_style_query_control_candidate in
                                        "$jobs_style_query_buffer"*) jobs_style_query_control_partial=1 ;;
                                    esac
                                done
                            done
                        fi
                        if [ -n "$jobs_style_query_control_sequence" ]; then
                            jobs_style_cleanup_control_keys=$(( ${jobs_style_cleanup_control_keys:-0} + 1 ))
                            if [ "$jobs_style_cleanup_control_keys" -gt 64 ]; then
                                jobs_style_query_failure='退出恢复期间已识别控制键超过 64 个，已停止自动恢复'
                                return 1
                            fi
                            jobs_style_query_buffer=${jobs_style_query_buffer#"$jobs_style_query_control_sequence"}
                            continue
                        fi
                        if [ "$jobs_style_query_control_partial" = 1 ]; then
                            break
                        fi
                    fi
                    case $jobs_style_query_buffer in
                        "$jobs_style_esc"|"$jobs_style_esc]") break ;;
                        "$jobs_style_esc]"*) ;;
                        *) jobs_style_query_failure='收到非配色查询输入，已停止读取'; return 1 ;;
                    esac
                    jobs_style_query_head=''
                    jobs_style_query_terminator=''
                    case $jobs_style_query_buffer in
                        *"$jobs_style_bel"*)
                            jobs_style_query_head=${jobs_style_query_buffer%%"$jobs_style_bel"*}
                            jobs_style_query_terminator=$jobs_style_bel
                            ;;
                    esac
                    case $jobs_style_query_buffer in
                        *"$jobs_style_query_st"*)
                            jobs_style_query_st_head=${jobs_style_query_buffer%%"$jobs_style_query_st"*}
                            if [ -z "$jobs_style_query_terminator" ] ||
                               [ "${#jobs_style_query_st_head}" -lt "${#jobs_style_query_head}" ]; then
                                jobs_style_query_head=$jobs_style_query_st_head
                                jobs_style_query_terminator=$jobs_style_query_st
                            fi
                            ;;
                    esac
                    [ -n "$jobs_style_query_terminator" ] || break
                    jobs_style_query_frame=$jobs_style_query_head$jobs_style_query_terminator
                    jobs_style_query_buffer=${jobs_style_query_buffer#"$jobs_style_query_frame"}
                    jobs_style_query_body=${jobs_style_query_head#"$jobs_style_esc]"}
                    case $jobs_style_query_body in
                        *';rgb:'*) ;;
                        *) jobs_style_query_failure='配色答复格式或 RGB 数据无效'; return 1 ;;
                    esac
                    jobs_style_query_frame_key=${jobs_style_query_body%%';rgb:'*}
                    case $jobs_style_query_frame_key in
                        10|11|12|'4;'[0-9]|'4;1'[0-5]) ;;
                        *) jobs_style_query_failure='收到不属于本次颜色协议的答复'; return 1 ;;
                    esac
                    jobs_style_query_frame_rgb=${jobs_style_query_body#"$jobs_style_query_frame_key;rgb:"}
                    jobs_style_query_frame_normalized=$(printf '%s\n' "$jobs_style_query_frame_rgb" | LC_ALL=C awk -F/ '
                        BEGIN { valid = 1 }
                        NR != 1 || NF != 3 { valid = 0; exit }
                        {
                            for (i = 1; i <= 3; i++) {
                                h = tolower($i)
                                if (length(h) < 1 || length(h) > 4 || h ~ /[^0-9a-f]/) {
                                    valid = 0
                                    exit
                                }
                                n = 0
                                for (j = 1; j <= length(h); j++) n = n * 16 + index("0123456789abcdef", substr(h, j, 1)) - 1
                                value[i] = int(n * 65535 / (16 ^ length(h) - 1) + 0.5)
                            }
                        }
                        END {
                            if (!valid || NR != 1) exit 1
                            printf "%d/%d/%d", value[1], value[2], value[3]
                        }
                    ')
                    if [ -z "$jobs_style_query_frame_normalized" ]; then
                        jobs_style_query_failure='配色答复格式或 RGB 数据无效'
                        return 1
                    fi
                    if [ "$jobs_style_query_frame_key" = "$jobs_style_query_key" ]; then
                        if [ -n "$jobs_style_query_target_reply" ] &&
                           [ "$jobs_style_query_target_normalized" != "$jobs_style_query_frame_normalized" ]; then
                            jobs_style_query_failure='同一颜色的重复答复不一致，已停止自动恢复'
                            return 1
                        fi
                        jobs_style_query_target_reply=$jobs_style_query_frame
                        jobs_style_query_target_normalized=$jobs_style_query_frame_normalized
                        jobs_style_query_target_rgb=$jobs_style_query_frame_rgb
                    else
                        jobs_style_query_stale_count=$((jobs_style_query_stale_count + 1))
                        if [ "$jobs_style_query_stale_count" -gt 128 ]; then
                            jobs_style_query_failure='收到过多旧颜色答复，已停止读取'
                            return 1
                        fi
                    fi
                done
                if [ -n "$jobs_style_query_target_reply" ] && [ -z "$jobs_style_query_buffer" ]; then
                    jobs_style_reply=$jobs_style_query_target_reply
                    jobs_style_normalized=$jobs_style_query_target_normalized
                    jobs_style_rgb=$jobs_style_query_target_rgb
                    return 0
                fi
            done
            # 残缺帧不能通过重发拼成另一个答复，更不能被当成键盘空输入。
            if [ -n "$jobs_style_query_buffer" ]; then
                jobs_style_query_failure='配色答复帧不完整，已停止自动恢复'
                return 1
            fi
        done
        return 1
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
            jobs_style_cleanup_issue='无法读取或设置原终端输入模式，或临时配色未完成核验'
            jobs_style_conflicts=''
            jobs_style_restore_safe=''
            jobs_style_cleanup_control_keys=0
            if [ "$jobs_style_applied_complete" = 1 ]; then
                jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_style_stty=''
                if [ -n "$jobs_style_stty" ] && stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
                    jobs_style_query_active=1
                    jobs_style_cleanup_ok=1
                    while IFS='|' read -r jobs_style_key jobs_style_expected jobs_style_original; do
                        [ -n "$jobs_style_key" ] || continue
                        if ! jobs_terminal_style_query "$jobs_style_key" cleanup; then
                            jobs_style_cleanup_ok=0
                            jobs_style_cleanup_issue="颜色项 $jobs_style_key：$jobs_style_query_failure"
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
                    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_cleanup_ok=0; jobs_style_cleanup_issue='无法恢复原终端输入模式'; }
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
                printf '终端配色未能安全自动恢复（%s）；确认覆盖当前配色后可运行：sh "%s"\n' "$jobs_style_cleanup_issue" "$jobs_style_recovery" >&2
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
    trap 'jobs_style_exit_status=129; jobs_terminal_style_cleanup 129 continue; jobs_style_changed=0; exit 129' HUP
    trap 'jobs_style_exit_status=130; jobs_terminal_style_cleanup 130 continue; jobs_style_changed=0; exit 130' INT
    trap 'jobs_style_exit_status=143; jobs_terminal_style_cleanup 143 continue; jobs_style_changed=0; exit 143' TERM
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
        trap 'jobs_style_exit_status=129; jobs_terminal_style_cleanup 129 continue; jobs_style_changed=0; exit 129' HUP
        trap 'jobs_style_exit_status=130; jobs_terminal_style_cleanup 130 continue; jobs_style_changed=0; exit 130' INT
        trap 'jobs_style_exit_status=143; jobs_terminal_style_cleanup 143 continue; jobs_style_changed=0; exit 143' TERM
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

SCRIPT_DIR=""
SCRIPT_PATH=""
CODE_SNIPPETS_PATH=""
LOG_FILE=""
RUN_MODE="normal"
PROJECT_DIR=""
TRANSACTION_DIR=""
LOCK_DIR=""
LOCK_HELD=0
SWAP_STARTED=0
COLOR_OUTPUT=0
ACTION_APPROVED=0
REPO_URLS=(https://github.com/JobsKits/JobsCodeSnippets.git https://gitee.com/JobsGo/jobs-code-snippetsJobsCodeSnippets.git)

# 只初始化进程内路径；--check 不创建文件或修改 Git 索引缓存。
configure_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  SCRIPT_DIR="${${(%):-%x}:A:h}"
  SCRIPT_PATH="$SCRIPT_DIR/${0:t}"
  CODE_SNIPPETS_PATH="$HOME/Library/Developer/Xcode/UserData/CodeSnippets"
  LOG_FILE="${TMPDIR:-/tmp}/JobsCodeSnippets-$(date +%Y%m%d-%H%M%S)-$$.log"
  if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" ]]; then
    COLOR_OUTPUT=1
  fi
  case "${1:-}" in
    --check|--help) RUN_MODE="${1#--}"; [[ $# == 1 ]] ;;
    --finder) RUN_MODE=finder; PROJECT_DIR="${2:-}"; [[ $# == 2 && -n "$PROJECT_DIR" ]] ;;
    "") [[ $# == 0 ]] ;;
    *) return 1 ;;
  esac
}
# 按终端能力显示纯文本或指定颜色。
display_line() {
  local tone="$1" message="$2"
  if (( COLOR_OUTPUT )); then
    print -r -- $'\e['"${tone}m${message}"$'\e[0m'
  else
    print -r -- "$message"
  fi
}
# 终端与独立日志同步记录业务结果。
log_message() {
  local tone="$1" message="$2"
  display_line "$tone" "$message"
  print -r -- "$message" >> "$LOG_FILE"
}
# 自述先于任何真实业务，普通动作的空输入一律跳过。
show_script_intro_and_wait() {
  configure_runtime "$@" || { print -u2 -r -- '用法：脚本 [--check | --finder <iOS工程路径> | --help]'; exit 2; }
  display_line '1;31' '================ JobsCodeSnippets 安装 / 升级 ================'
  display_line '0;34' "1、目标：$CODE_SNIPPETS_PATH"
  display_line '0;34' '2、缺失时安装；已有仓库时保存暂存、未暂存和未跟踪内容，再拉取合并。'
  display_line '0;34' '3、不自动生成提交或推送；冲突恢复原状，保留副本供手动合并。'
  display_line '0;34' '4、仅操作当前用户代码片段；成功后需要自行重新打开 Xcode。'
  display_line '0;34' "日志：$LOG_FILE（--check / --help 不写日志）"
  jobs_prompt_output display_line '0;34' '取消：按 Ctrl+C；执行选择直接回车跳过。'
  [[ "$RUN_MODE" != check && "$RUN_MODE" != help ]] || return 0
  [[ -t 0 ]] || { print -u2 -r -- '✖ 请在可交互 Terminal 中运行。'; exit 1; }
  local answer=""
  read -r "?$(jobs_prompt_render '已了解用途与影响，按回车继续；Ctrl+C 取消：')" answer || exit 1
  read -r "?$(jobs_prompt_render '安装 / 升级：直接回车跳过；输入任意字符后回车执行：')" answer || exit 1
  [[ -n "$answer" ]] && ACTION_APPROVED=1
  return 0
}
# 忽略调用者的 Git 仓库定位变量，防止从工程右键时误操作项目仓库。
snippet_git() {
  local repo="$1"
  shift
  (
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
    export GIT_OPTIONAL_LOCKS=0 GIT_TERMINAL_PROMPT=0
    export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=10}"
    command git -C "$repo" -c core.hooksPath=/dev/null -c gc.auto=0 -c maintenance.auto=false \
      -c merge.autostash=false -c rerere.enabled=false "$@"
  )
}
# 保留 Git 退出码并过滤输出中的 URL 敏感信息。
run_git() {
  snippet_git "$@" 2>&1 | sed -E 's#(https?://)[^/@[:space:]]+@#\1[REDACTED]@#g; s#(https?://[^?#[:space:]]+)[?#][^[:space:]]*#\1[REDACTED]#g' | tee -a "$LOG_FILE"
}
# 只脱敏展示副本，不改动真实传输地址。
redact_url() {
  print -r -- "$1" | sed -E 's#(https?://)[^/@]+@#\1[REDACTED]@#g; s#[?#].*$##'
}
# 在传输前突出来源、分支和实际安装位置。
show_source() {
  local repo="$1" configured="$2" branch="${3:-远端默认分支}" actual
  actual="$(snippet_git "$repo" ls-remote --get-url "$configured")" || return 1
  log_message '1;36' '━━━━━━━━━━ 来源｜JobsCodeSnippets ━━━━━━━━━━'
  log_message '1;36' "配置来源：$(redact_url "$configured")"
  log_message '1;36' "生效地址：$(redact_url "$actual")（本地 Git 规则展开）"
  log_message '1;36' "分支：$branch"
  log_message '1;36' "目标：$CODE_SNIPPETS_PATH"
}
# 工程仅负责决定菜单资格，不作为代码片段安装位置。
validate_finder_project() {
  [[ "$RUN_MODE" == finder ]] || return 0
  local item="$PROJECT_DIR" candidate
  [[ -d "$item" && ! -L "$item" && "${item:A}" != "${HOME:A}/Desktop" ]] || return 1
  if [[ "$item" == *.xcodeproj && -f "$item/project.pbxproj" ]] ||
     [[ "$item" == *.xcworkspace && -f "$item/contents.xcworkspacedata" ]]; then
    return 0
  fi
  [[ -f "$item/Package.swift" || -f "$item/Podfile" ]] && return 0
  for candidate in "$item"/*(ND); do
    if [[ -d "$candidate" && ( "${candidate:e:l}" == xcodeproj || "${candidate:e:l}" == xcworkspace ) ]] ||
       [[ -f "$candidate" && "${candidate:e}" == podspec ]]; then
      return 0
    fi
  done
  return 1
}
# 只接管独立安装仓，外部元数据 / 未完成操作交给人工处理。
validate_installed_repo() {
  local repo="$1" marker root
  [[ -d "$repo/.git" && ! -L "$repo" && ! -L "$repo/.git" ]] || return 1
  root="$(snippet_git "$repo" rev-parse --show-toplevel)" || return 1
  [[ "${root:A}" == "${repo:A}" ]] || return 1
  snippet_git "$repo" rev-parse --verify HEAD >/dev/null || return 1
  snippet_git "$repo" symbolic-ref -q HEAD >/dev/null || return 1
  [[ -z "$(snippet_git "$repo" config --get core.worktree)" ]] || return 1
  [[ ! -e "$repo/.git/objects/info/alternates" && ! -e "$repo/.git/commondir" && ! -e "$repo/.git/worktrees" ]] || return 1
  [[ -z "$(find "$repo/.git" -type l -print -quit)" ]] || return 1
  [[ -z "$(find "$repo/.git" -name '*.lock' -print -quit)" ]] || return 1
  for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply sequencer index.lock; do
    [[ ! -e "$repo/.git/$marker" ]] || return 1
  done
  [[ -z "$(snippet_git "$repo" ls-files --unmerged)" ]] || return 1
  [[ -z "$(snippet_git "$repo" ls-files -v | awk '/^[a-zS] / { print; exit }')" ]] || return 1
  [[ -z "$(snippet_git "$repo" ls-files --debug | awk '/flags: / && $NF != "0" { print; exit }')" ]] || return 1
  [[ -z "$(snippet_git "$repo" ls-files --stage | awk '$1 == "160000" { print; exit }')" ]] || return 1
}
# 检查实际依赖与 Finder 项目边界，失败即停止入口。
check_environment() {
  command -v git >/dev/null && git --version >/dev/null || { print -u2 -r -- '✖ Git / Xcode Command Line Tools 不可用，请先修复开发工具。'; exit 1; }
  validate_finder_project || { print -u2 -r -- '✖ 请选择有效的 iOS / Xcode 工程或工程目录。'; exit 1; }
}
# 只读报告当前安装形态，未知目录不接管。
report_state() {
  if [[ "$RUN_MODE" == help ]]; then
    print -r -- '参数：--check 只读检查安装位置；--finder <工程路径> 供 iOS 右键菜单调用。'
    return 0
  fi
  if [[ ! -e "$CODE_SNIPPETS_PATH" && ! -L "$CODE_SNIPPETS_PATH" ]]; then
    print -r -- 'ℹ 尚未安装，将克隆到当前用户 CodeSnippets 目录。'
  elif validate_installed_repo "$CODE_SNIPPETS_PATH"; then
    print -r -- '✔ 已安装，将按当前分支明确配置的上游升级。'
    snippet_git "$CODE_SNIPPETS_PATH" status --short
  elif [[ -d "$CODE_SNIPPETS_PATH" && ! -L "$CODE_SNIPPETS_PATH" && -z "$(ls -A "$CODE_SNIPPETS_PATH")" ]]; then
    print -r -- 'ℹ CodeSnippets 为空，将安装。'
  else
    print -u2 -r -- "✖ 目标不是可安全升级的独立 Git 仓库，或有未完成操作；原内容保留：$CODE_SNIPPETS_PATH"
    exit 1
  fi
}
# 只释放当前进程成功获取的空锁目录。
release_lock() {
  if (( LOCK_HELD )); then
    rmdir "$LOCK_DIR" 2>/dev/null || print -u2 -r -- "⚠ 请检查本次锁：$LOCK_DIR"
    LOCK_HELD=0
  fi
}
# 发布中断时恢复被移开的旧目录，始终保留备份。
handle_interrupt() {
  trap '' INT TERM HUP
  if (( SWAP_STARTED )) && [[ ! -e "$CODE_SNIPPETS_PATH" && ! -L "$CODE_SNIPPETS_PATH" && -d "$TRANSACTION_DIR/previous" ]]; then
    mv "$TRANSACTION_DIR/previous" "$CODE_SNIPPETS_PATH" || print -u2 -r -- "✖ 恢复失败，请从 $TRANSACTION_DIR/previous 恢复。"
  fi
  print -u2 -r -- "⚠ 操作中断；原始备份 / 候选副本：${TRANSACTION_DIR:-尚未创建}"
  release_lock
  exit 130
}
# 取得固定目标锁并建立私有完整快照。
prepare_transaction() {
  local parent="${CODE_SNIPPETS_PATH:h}"
  mkdir -p "$parent" || return 1
  LOCK_DIR="$parent/.JobsCodeSnippets.lock"
  mkdir "$LOCK_DIR" 2>/dev/null || { log_message '1;31' "✖ 已有操作或遗留锁：$LOCK_DIR；确认没有运行后再人工移除空锁目录。"; return 1; }
  LOCK_HELD=1
  trap release_lock EXIT
  trap handle_interrupt INT TERM HUP
  TRANSACTION_DIR="$(umask 077; mktemp -d "$parent/.JobsCodeSnippets.XXXXXXXX")" || return 1
  if [[ -d "$CODE_SNIPPETS_PATH" ]]; then
    cp -pR "$CODE_SNIPPETS_PATH" "$TRANSACTION_DIR/original" || return 1
  fi
  log_message '0;35' "➤ 事务与原始备份：$TRANSACTION_DIR"
}
# 在完整副本上拉取及合并，分别恢复工作区和原暂存部分。
update_candidate() {
  local repo="$TRANSACTION_DIR/candidate" branch remote merge_ref url saved_stash=""
  cp -pR "$TRANSACTION_DIR/original" "$repo" || return 1
  validate_installed_repo "$repo" || return 1
  branch="$(snippet_git "$repo" symbolic-ref --short HEAD)" || return 1
  remote="$(snippet_git "$repo" config --get "branch.$branch.remote")" || return 1
  merge_ref="$(snippet_git "$repo" config --get "branch.$branch.merge")" || return 1
  [[ -n "$remote" && "$remote" != . && "$merge_ref" == refs/heads/* && "$merge_ref" != *$'\n'* ]] || return 1
  url="$(snippet_git "$repo" remote get-url "$remote")" || return 1
  show_source "$repo" "$url" "${merge_ref#refs/heads/}" || return 1
  if [[ -n "$(snippet_git "$repo" status --porcelain=v1 --untracked-files=all)" ]]; then
    log_message '0;34' 'ℹ 在候选副本保存暂存区、未暂存及未跟踪内容，不向分支生成提交。'
    run_git "$repo" stash push --include-untracked -m 'JobsCodeSnippets update safety' || return 1
    saved_stash="$(snippet_git "$repo" rev-parse refs/stash)" || return 1
    [[ -z "$(snippet_git "$repo" status --porcelain=v1 --untracked-files=all)" ]] || return 1
  fi
  run_git "$repo" fetch --no-tags -- "$remote" "$merge_ref" || return 1
  run_git "$repo" merge --ff --no-commit --no-edit --no-autostash --no-overwrite-ignore FETCH_HEAD || return 1
  if [[ -n "$saved_stash" ]]; then
    # 分叉合并已有暂存结果，plain apply 恢复工作区，再单独三方恢复原暂存部分。
    cp -p "$repo/.git/index" "$TRANSACTION_DIR/merged.index" || return 1
    snippet_git "$repo" diff --binary --full-index --no-ext-diff --no-textconv "$saved_stash^1" "$saved_stash^2" > "$TRANSACTION_DIR/staged.patch" || return 1
    run_git "$repo" stash apply "$saved_stash" || return 1
    cp -p "$TRANSACTION_DIR/merged.index" "$repo/.git/index" || return 1
    if [[ -s "$TRANSACTION_DIR/staged.patch" ]]; then
      run_git "$repo" apply --3way --cached "$TRANSACTION_DIR/staged.patch" || return 1
    fi
    [[ "$(snippet_git "$repo" rev-parse refs/stash)" == "$saved_stash" ]] || return 1
    run_git "$repo" stash drop 'stash@{0}' || return 1
  fi
  [[ -z "$(snippet_git "$repo" ls-files --unmerged)" ]] || return 1
  if [[ -f "$repo/.git/MERGE_HEAD" ]]; then
    log_message '1;33' '⚠ 分支存在分叉，已合并到暂存区且未生成 commit；请自行审阅并提交后再升级。'
  fi
  log_message '1;32' "✔ 已取得来源 $(redact_url "$url")；候选 HEAD：$(snippet_git "$repo" rev-parse --short HEAD)"
}
# 首次安装按明确来源依次尝试，失败目录单独保留。
install_candidate() {
  local url attempt=0 destination
  for url in "${REPO_URLS[@]}"; do
    (( attempt += 1 ))
    destination="$TRANSACTION_DIR/clone-$attempt"
    show_source "${CODE_SNIPPETS_PATH:h}" "$url" || return 1
    if run_git "${CODE_SNIPPETS_PATH:h}" clone --no-hardlinks -- "$url" "$destination"; then
      mv "$destination" "$TRANSACTION_DIR/candidate" || return 1
      log_message '1;32' "✔ 克隆成功，来源：$(redact_url "$url")"
      return 0
    fi
    log_message '1;33' "⚠ 克隆失败，保留失败副本，尝试下一来源：$(redact_url "$url")"
  done
  return 1
}
# 记录权限、归属、修改时间与链接本体，路径用 NUL 分隔。
record_metadata() {
  local root="$1" output="$2" item metadata
  (
    for item in "$root" "$root"/**/*(DN); do
      metadata="$(stat -f '%p:%u:%g:%m' "$item")" || return 1
      printf '%s\0%s\0' "${item#$root}" "$metadata"
      if [[ -L "$item" ]]; then
        readlink "$item" || return 1
      fi
      printf '\0'
    done
  ) > "$output"
}
# 逐个比较普通文件，避免递归 diff 解引用符号链接。
compare_original_files() {
  local original="$TRANSACTION_DIR/original" item relative
  for item in "$original"/**/*(DN); do
    [[ ! -L "$item" && -f "$item" ]] || continue
    relative="${item#$original/}"
    cmp -s "$item" "$CODE_SNIPPETS_PATH/$relative" || return 1
  done
}
# 内容、权限和链接目标均无变化才允许发布候选。
publish_candidate() {
  if [[ -d "$TRANSACTION_DIR/original" ]]; then
    record_metadata "$CODE_SNIPPETS_PATH" "$TRANSACTION_DIR/current.metadata" || return 1
    record_metadata "$TRANSACTION_DIR/original" "$TRANSACTION_DIR/original.metadata" || return 1
    if ! compare_original_files ||
       ! cmp -s "$TRANSACTION_DIR/current.metadata" "$TRANSACTION_DIR/original.metadata"; then
      log_message '1;31' '✖ 原目录在操作期间发生变化，保留双方副本，停止替换。'
      return 1
    fi
    SWAP_STARTED=1
    mv "$CODE_SNIPPETS_PATH" "$TRANSACTION_DIR/previous" || return 1
  elif [[ -e "$CODE_SNIPPETS_PATH" || -L "$CODE_SNIPPETS_PATH" ]]; then
    return 1
  fi
  if [[ -e "$CODE_SNIPPETS_PATH" || -L "$CODE_SNIPPETS_PATH" ]] || ! mv -n "$TRANSACTION_DIR/candidate" "$CODE_SNIPPETS_PATH" || [[ -e "$TRANSACTION_DIR/candidate" ]]; then
    if (( SWAP_STARTED )) && [[ ! -e "$CODE_SNIPPETS_PATH" && ! -L "$CODE_SNIPPETS_PATH" ]]; then
      mv "$TRANSACTION_DIR/previous" "$CODE_SNIPPETS_PATH" || log_message '1;31' "✖ 请手动从 $TRANSACTION_DIR/previous 恢复目标。"
    fi
    return 1
  fi
  SWAP_STARTED=0
  log_message '1;32' "✔ 安装 / 升级完成：$CODE_SNIPPETS_PATH"
  log_message '0;35' "➤ 原始备份保留在：$TRANSACTION_DIR；请自行重新打开 Xcode。"
}
# 确认后编排事务并将失败状态传回调用方。
run_business() {
  [[ "$RUN_MODE" != check && "$RUN_MODE" != help && "$ACTION_APPROVED" == 1 ]] || return 0
  LOG_FILE="$(umask 077; mktemp "${LOG_FILE%.log}.XXXXXXXX.log")" || return 1
  display_line '0;35' "➤ 实际日志：$LOG_FILE"
  prepare_transaction || return 1
  if [[ -d "$TRANSACTION_DIR/original/.git" ]]; then
    update_candidate || { log_message '1;31' "✖ 拉取或合并失败，安装目录与暂存区保持更新前原状。请手动合并；失败副本与 stash：$TRANSACTION_DIR/candidate；日志：$LOG_FILE"; return 1; }
  else
    install_candidate || { log_message '1;31' "✖ 安装失败，原目录保留。日志：$LOG_FILE"; return 1; }
  fi
  publish_candidate || return 1
}
# 入口只编排说明、自检、安装状态和真实业务。
main() {
  show_script_intro_and_wait "$@" # 展示内置自述，解析只读与 Finder 入口并确认动作。
  check_environment # 检查 Git 健康与 Finder 项目边界。
  report_state # 对齐当前用户实际安装目录并报告安全状态。
  run_business # 在隔离副本安装或升级，成功后发布并保留备份。
}

main "$@"
