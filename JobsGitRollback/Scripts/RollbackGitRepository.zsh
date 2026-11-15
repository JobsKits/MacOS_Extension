#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】♻️双击Git（识别子Git） 提交回退.command
# - 核心用途：soft 撤回所选远端快照或历史提交之后的提交；兼容子模块和嵌套 Git。
# - 影响范围：soft 保留工作区和索引；hard 舍弃已跟踪改动；均只处理选定工作树。
# - 运行提示：多远端快照不同时，Sourcetree 转交终端选择；hard 必须输入 YES。
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

jobs_intro_style() {
  local intro_color=0
  if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
     [ -z "${NO_COLOR+x}" ] && [ "${PLAIN_OUTPUT:-0}" != 1 ] &&
     [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]; then
    intro_color=1
  fi
  /usr/bin/awk -v color="$intro_color" -v role="${1:-body}" '
    BEGIN { esc = sprintf("%c", 27) }
    {
      gsub(esc "\\[[0-9;]*m", "")
      gsub(/\\(033|e|x1[bB])\[[0-9;]*m/, "")
      if (!color || $0 ~ /^[[:space:]]*$/) { print; next }
      numbered = ($0 ~ /^[[:space:]➤ℹ🔹✔⚠]*([0-9]+[、.)）]|[0-9]+️⃣|[-•])/)
      heading = ($0 ~ /^[[:space:]]*#{1,6}[[:space:]]/ || $0 ~ /[：:][[:space:]]*$/ || $0 ~ /^[[:space:]]*[=━─-]{3}/)
      title = (!numbered && (role == "title" || heading))
      if (role == "auto" && !seen && !numbered) title = 1
      if ($0 !~ /^[[:space:]]*[=━─-]+[[:space:]]*$/) seen = 1
      printf "%s%s%s\n", esc (title ? "[1;31m" : "[0;34m"), $0, esc "[0m"
    }
  '
}
RAW_SCRIPT_PATH="$0"
SCRIPT_PATH=""
SCRIPT_BASENAME=""
LOG_FILE=""
LOG_READY=0
IS_SOURCETREE_RUNTIME=0
PLAIN_OUTPUT=0
REPO_ROOT=""
UPSTREAM_REF=""
RESET_TARGET=""
RESET_MODE=""
SELECTION=""
REPO_ARGUMENT=""
REQUESTED_UPSTREAM_REF=""
TERMINAL_SOFT=0
INITIAL_HEAD_REF=""
INITIAL_HEAD_COMMIT=""
REPOSITORY_GIT_DIR=""
typeset -a UPSTREAM_CHOICES=()

# 仅以 Sourcetree 环境标记或父进程确认入口，不把命令行参数当作身份。
is_sourcetree_runtime() {
  /usr/bin/env | /usr/bin/grep -Ei '^SOURCETREE|^SOURCE_TREE' >/dev/null && return 0
  local process_id="$PPID" process_name="" guard=0
  while [[ -n "$process_id" && "$process_id" != 0 && "$guard" -lt 8 ]]; do
    process_name="$(/bin/ps -o comm= -p "$process_id" 2>/dev/null || true)"
    [[ "$process_name" == *SourceTree* || "$process_name" == *Sourcetree* ]] && return 0
    process_id="$(/bin/ps -o ppid= -p "$process_id" 2>/dev/null | /usr/bin/tr -d ' ' || true)"
    guard=$((guard + 1))
  done
  return 1
}
# 准备路径与纯文本输出，首屏不创建日志或改动 Git。
prepare_intro_context() {
  local filename="${RAW_SCRIPT_PATH:t}" candidate="${RAW_SCRIPT_PATH:A}"
  local fallback=""
  for fallback in "${HOME}/SourceTree.command/MacOS/${filename}/${filename}" "${HOME}/Documents/Github/JobsGenesis/SourceTree.command/MacOS/${filename}/${filename}"; do
    [[ -f "$candidate" ]] && break
    [[ -f "$fallback" ]] && candidate="$fallback"
  done
  SCRIPT_PATH="$candidate"
  SCRIPT_BASENAME="${filename:r}"
  LOG_FILE="${${TMPDIR:-/tmp}:A}/${SCRIPT_BASENAME}.$(/bin/date '+%Y%m%d-%H%M%S').$$.log"
  is_sourcetree_runtime && IS_SOURCETREE_RUNTIME=1
  if [[ "${1:-}" == --terminal-soft ]]; then
    TERMINAL_SOFT=1
    IS_SOURCETREE_RUNTIME=0
  fi
  configure_output_mode
}
# 确认前后均配置外部命令的纯文本环境。
configure_output_mode() {
  if [[ "$IS_SOURCETREE_RUNTIME" == 1 || ! -t 1 || -z "${TERM:-}" || "${TERM:-}" == dumb || -n "${NO_COLOR+x}" ]]; then
    PLAIN_OUTPUT=1
    export NO_COLOR=1 FORCE_COLOR=0 CLICOLOR=0 ANSI_COLORS_DISABLED=1 npm_config_color=false
  fi
  return 0
}
strip_ansi_stream() {
  /usr/bin/perl -pe 's/\e\[[0-9;]*[[:alpha:]]//g'
}
# 展示颜色与业务正文分开，路径中的反斜杠保持原值。
log() {
  local level="$1" message="$2" rendered="$2" color=""
  case "$level" in
    info) color=$'\033[1;34m' ;;
    success) color=$'\033[1;32m' ;;
    warn) color=$'\033[1;33m' ;;
    error) color=$'\033[1;31m' ;;
  esac
  [[ "$PLAIN_OUTPUT" == 1 ]] || rendered="${color}${message}"$'\033[0m'
  if [[ "$LOG_READY" == 1 ]]; then
    print -r -- "$rendered" | jobs_prompt_tee "$LOG_FILE"
  else
    print -r -- "$rendered"
  fi
}
info_echo() { log info "ℹ $1"; }
success_echo() { log success "✔ $1"; }
warn_echo() { log warn "⚠ $1"; }
error_echo() { log error "✖ $1"; }
# 自述失败必须终止，不能进入后面的重置逻辑。
show_script_intro_and_wait() {
  prepare_intro_context "$@"
  print -r -- "============================== Git 提交回退 ==============================" | jobs_intro_style title
  print -r -- "脚本名称：${SCRIPT_BASENAME}.command" | jobs_intro_style title
  print -r -- "1、soft 只移动当前分支，保留已有索引和工作区；是否有待提交内容以实际差异为准。" | jobs_intro_style body
  print -r -- "2、Sourcetree 多远端快照不同时转交 Terminal 明确选择；终端也支持选择历史提交 soft 回退。" | jobs_intro_style body
  print -r -- "3、默认采用 upstream；可用 --upstream refs/remotes/远端/分支明确指定，不自动 fetch。" | jobs_intro_style body
  print -r -- "4、soft 目标必须是 HEAD 祖先；选择期间分支或快照变化时停止，请重新核对。" | jobs_intro_style body
  print -r -- "5、所有 hard 模式会舍弃已跟踪的未提交内容，必须输入 YES；不递归重置子模块。" | jobs_intro_style body
  print -r -- "取消方式：Ctrl+C；日志位于 ${LOG_FILE}" | jobs_intro_style body
  if [[ "$IS_SOURCETREE_RUNTIME" == 1 ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    print -u2 -r -- "当前不是 Sourcetree，且没有可交互输入；请在终端重新运行。"
    exit 1
  fi
  read -r "?$(jobs_prompt_render '已了解用途与影响，按回车继续；Ctrl+C 取消：')" _ || exit 1
}
initialize_script_runtime() {
  emulate -R zsh
  setopt NO_NOMATCH ERR_EXIT PIPE_FAIL
  export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
  : > "$LOG_FILE"
  LOG_READY=1
  configure_output_mode
}
# 清理仅限本进程的 Git 定位变量，避免父仓环境覆盖明确传入的子仓路径。
isolate_git_context() {
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX GIT_NAMESPACE
}
check_environment() {
  command -v git >/dev/null && git --version >/dev/null || { error_echo "Git 不可用。"; return 1; }
}
# 解析仓库与显式远端引用；终端承接标志只能位于首参数。
parse_arguments() {
  [[ "${1:-}" != --terminal-soft ]] || shift
  while (( $# )); do
    case "$1" in
      --upstream)
        (( $# >= 2 )) && [[ -n "$2" ]] || { error_echo '--upstream 缺少完整远端跟踪引用。'; return 1; }
        REQUESTED_UPSTREAM_REF="$2"
        shift 2
        ;;
      --*) error_echo "未知参数：$1"; return 1 ;;
      *)
        [[ -z "$REPO_ARGUMENT" ]] || { error_echo '只能指定一个仓库目录。'; return 1; }
        REPO_ARGUMENT="$1"
        shift
        ;;
    esac
  done
}
# 拖入路径只做字符串解引用，不执行用户输入。
resolve_repository() {
  local candidate="${1:-${REPO:-}}" entered=""
  if [[ -z "$candidate" ]]; then
    if [[ "$IS_SOURCETREE_RUNTIME" == 1 ]]; then
      error_echo '未收到仓库路径；请在动作参数栏填写 $REPO。'
      return 1
    fi
    jobs_prompt_output info_echo "输入或拖入仓库路径；直接回车使用当前目录：${PWD}"
    read -r 'entered?仓库路径：' || return 1
    candidate="${entered:-$PWD}"
  fi
  candidate="${candidate%$'\r'}"
  [[ -e "$candidate" ]] || candidate="${(Q)candidate}"
  [[ -f "$candidate" ]] && candidate="${candidate:h}"
  [[ -d "$candidate" ]] || { error_echo "目标目录不存在：${candidate}"; return 1; }
  REPO_ROOT="$(git -C "$candidate" rev-parse --show-toplevel 2>/dev/null)" || { error_echo "目标不在 Git 工作树中：${candidate}"; return 1; }
  REPO_ROOT="${REPO_ROOT:A}"
  REPOSITORY_GIT_DIR="$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir)" || return $?
  INITIAL_HEAD_REF="$(git -C "$REPO_ROOT" symbolic-ref --quiet HEAD 2>/dev/null || true)"
  INITIAL_HEAD_COMMIT="$(git -C "$REPO_ROOT" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" || { error_echo '当前仓库尚无有效 HEAD 提交，无法回退。'; return 1; }
  info_echo "当前 Git 仓库：${REPO_ROOT}"
  local parent="$(git -C "$REPO_ROOT" rev-parse --show-superproject-working-tree)"
  [[ -z "$parent" ]] || info_echo "直属父仓：${parent}；本次只回退当前子仓，父仓暂存区不变。"
  return 0
}
# 冲突、未完成操作或游离 HEAD 下不能把回退解释为未推送提交撤回。
check_repository_state() {
  local metadata="" unmerged="" marker=""
  metadata="$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir)" || return $?
  unmerged="$(git -C "$REPO_ROOT" ls-files --unmerged)" || return $?
  if [[ -n "$unmerged" ]]; then
    error_echo "存在未解决冲突，请先处理。"
    return 1
  fi
  for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG rebase-merge rebase-apply sequencer index.lock; do
    [[ ! -e "${metadata}/${marker}" ]] || { error_echo "存在未完成操作或锁：${marker}"; return 1; }
  done
}
# 重新核对仓库、分支与起始提交，交互过程中切换或更新过就停止。
check_reset_context() {
  local metadata="" current_root="" current_ref="" current_commit=""
  metadata="$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir)" || return $?
  current_root="$(git -C "$REPO_ROOT" rev-parse --show-toplevel)" || return $?
  current_ref="$(git -C "$REPO_ROOT" symbolic-ref --quiet HEAD 2>/dev/null || true)"
  current_commit="$(git -C "$REPO_ROOT" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" || return $?
  if [[ "$metadata" != "$REPOSITORY_GIT_DIR" || "${current_root:A}" != "$REPO_ROOT" || "$current_ref" != "$INITIAL_HEAD_REF" || "$current_commit" != "$INITIAL_HEAD_COMMIT" ]]; then
    error_echo '选择或确认期间仓库、分支或 HEAD 已变化；保持现状，请重新运行并核对。'
    return 1
  fi
  check_repository_state
}
# 参数必须是真实完整远端引用，不接受 ~1、^ 或 @{...} 等修订表达式。
verify_upstream_reference() {
  local ref="$1"
  [[ "$ref" == refs/remotes/* ]] && git -C "$REPO_ROOT" check-ref-format "$ref" &&
    git -C "$REPO_ROOT" show-ref --verify --quiet "$ref" || {
      error_echo "远端跟踪引用不存在或格式不完整：${ref}"
      return 1
    }
}
# 收集当前分支各线路已有快照及真实 upstream，不扫描或选择别的仓库。
collect_upstream_choices() {
  local branch="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  local remote="" ref="" configured=""
  UPSTREAM_CHOICES=()
  [[ -n "$branch" ]] || return 0
  configured="$(git -C "$REPO_ROOT" rev-parse --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  if [[ "$configured" == refs/remotes/* ]] && git -C "$REPO_ROOT" rev-parse --verify "${configured}^{commit}" >/dev/null 2>&1; then
    UPSTREAM_CHOICES+=("$configured")
  fi
  for remote in "${(@f)$(git -C "$REPO_ROOT" remote)}"; do
    ref="refs/remotes/${remote}/${branch}"
    if git -C "$REPO_ROOT" rev-parse --verify "${ref}^{commit}" >/dev/null 2>&1; then
      UPSTREAM_CHOICES+=("$ref")
    fi
  done
  UPSTREAM_CHOICES=("${(@u)UPSTREAM_CHOICES}")
}
# 只读取本地跟踪快照；显式选择优先，不因某条线路拒收而自动改用另一条。
resolve_upstream_target() {
  local branch="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  local configured_remote="" ref="" commit=""
  local -a choices=()
  local -A snapshot_commits=()
  [[ -n "$branch" ]] || { error_echo "游离 HEAD 没有明确当前分支，不能回退到远端。"; return 1; }
  configured_remote="$(git -C "$REPO_ROOT" config --get "branch.${branch}.remote" || true)"
  UPSTREAM_REF="$REQUESTED_UPSTREAM_REF"
  if [[ -z "$UPSTREAM_REF" && "$IS_SOURCETREE_RUNTIME" != 1 ]]; then
    collect_upstream_choices
    if (( ${#UPSTREAM_CHOICES} > 1 )); then
      for ref in "${UPSTREAM_CHOICES[@]}"; do
        commit="$(git -C "$REPO_ROOT" rev-parse "$ref")"
        snapshot_commits[$ref]="$commit"
        choices+=("${ref} [${commit[1,12]}]")
      done
      choose_entry '选择本地远端快照（不联网）' 1 "${choices[@]}" || return $?
      [[ -n "$SELECTION" ]] || return 20
      UPSTREAM_REF="${SELECTION%% *}"
    fi
  fi
  [[ -n "$UPSTREAM_REF" ]] || UPSTREAM_REF="$(git -C "$REPO_ROOT" rev-parse --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  if [[ -z "$UPSTREAM_REF" && -z "$configured_remote" ]]; then
    UPSTREAM_REF="refs/remotes/origin/${branch}"
  fi
  verify_upstream_reference "$UPSTREAM_REF" || return $?
  RESET_TARGET="$(git -C "$REPO_ROOT" rev-parse --verify "${UPSTREAM_REF}^{commit}" 2>/dev/null)" || { error_echo "远端跟踪引用不可用：${UPSTREAM_REF}"; return 1; }
  if [[ -n "${snapshot_commits[$UPSTREAM_REF]:-}" && "$RESET_TARGET" != "${snapshot_commits[$UPSTREAM_REF]}" ]]; then
    error_echo '远端跟踪快照在选择期间已变化；没有回退，请重新选择。'
    return 1
  fi
  info_echo "本地跟踪快照：${UPSTREAM_REF} [${RESET_TARGET}]"
}
# 远端 soft 的目标来自已验证的引用，索引和工作区保持原样。
reset_soft_to_remote() {
  resolve_upstream_target || return $?
  reset_soft_to_target "$UPSTREAM_REF"
}
# soft 仅回退到 HEAD 的祖先；提交数不等于净文件差异数。
reset_soft_to_target() {
  local description="$1"
  check_reset_context || return $?
  if ! git -C "$REPO_ROOT" merge-base --is-ancestor "$RESET_TARGET" "$INITIAL_HEAD_COMMIT"; then
    error_echo "目标不是 HEAD 的祖先：${description}；本地可能落后或分叉，请先检查历史。"
    return 1
  fi
  local ahead=""
  ahead="$(git -C "$REPO_ROOT" rev-list --count "${RESET_TARGET}..${INITIAL_HEAD_COMMIT}")" || return $?
  if [[ "$ahead" == 0 ]]; then
    info_echo "HEAD 已与所选目标一致：${description} [${RESET_TARGET}]；本次没有撤回提交。"
    info_echo '这只代表所选线路；其它远端可能尚未同步。撤回已同步提交可在终端选择“选择提交 soft 回退”。'
    report_staged_changes
    return $?
  fi
  info_echo "仅在本地撤回 ${ahead} 个提交到 ${description}，保留工作区及已有索引；其它远端可能已经包含这些提交。"
  check_reset_context || return $?
  run_git reset --soft "$RESET_TARGET" || return $?
  success_echo "已 soft 回退到 ${description} [${RESET_TARGET}]。"
  report_staged_changes
}
# 依据真实索引报告结果，空提交或净变化抵消时不虚报待提交文件。
report_staged_changes() {
  local diff_result=0 summary=""
  git -C "$REPO_ROOT" diff --cached --quiet --ignore-submodules=none || diff_result=$?
  case "$diff_result" in
    0) info_echo '暂存区相对当前 HEAD 没有文件差异；空提交或内容相互抵消时属于正常结果。' ;;
    1)
      summary="$(git -C "$REPO_ROOT" diff --cached --shortstat --ignore-submodules=none)" || return $?
      info_echo "待提交差异：${summary}；请在当前仓库的 Sourcetree 文件状态中核对。"
      ;;
    *) error_echo '无法读取暂存差异，请保留现场检查。'; return "$diff_result" ;;
  esac
}
# 保留外部 Git 的原始退出码，任何重置失败都不能打印成功。
run_git() {
  local -a result_codes=()
  if git -C "$REPO_ROOT" "$@" 2>&1 | strip_ansi_stream | tee -a "$LOG_FILE"; then
    return 0
  else
    result_codes=("${pipestatus[@]}")
  fi
  local result_code=0
  for result_code in "${result_codes[@]}"; do
    (( result_code == 0 )) || return "$result_code"
  done
  return 1
}
# 摘要仅用于 hard 确认期间的变化检测，不修改索引或写入对象库。
capture_hard_reset_state() {
  local index_file="" index_digest=missing worktree_digest="" status_digest=""
  index_file="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-path index)" || return $?
  if [[ -f "$index_file" ]]; then
    index_digest="$(/usr/bin/shasum -a 256 "$index_file")" || return $?
  fi
  worktree_digest="$(git --no-optional-locks -c diff.autoRefreshIndex=false -C "$REPO_ROOT" diff --no-ext-diff --no-textconv --binary --ignore-submodules=all | /usr/bin/shasum -a 256)" || return $?
  status_digest="$(git --no-optional-locks -C "$REPO_ROOT" status --porcelain=v1 -z --untracked-files=all --ignore-submodules=none | /usr/bin/shasum -a 256)" || return $?
  print -r -- "$index_digest" "$worktree_digest" "$status_digest"
}
# hard 以已解析的提交号固定目标，防止 tag 名歧义和确认后引用变化。
confirm_and_reset_hard() {
  local target="$1" description="$2" answer="" commit="" before_state="" current_state=""
  [[ "$IS_SOURCETREE_RUNTIME" != 1 && -t 0 ]] || { error_echo 'hard 回退只允许在独立交互终端确认。'; return 1; }
  check_reset_context || return $?
  commit="$(git -C "$REPO_ROOT" rev-parse --verify "${target}^{commit}" 2>/dev/null)" || { error_echo "所选目标不是有效提交：${description}"; return 1; }
  before_state="$(capture_hard_reset_state)" || return $?
  warn_echo "仓库：${REPO_ROOT}"
  warn_echo "hard 回退目标：${description} [${commit}]；已跟踪的未提交内容会被舍弃。"
  read -r 'answer?输入 YES 执行；其它输入取消：' || return 1
  if [[ "$answer" != YES ]]; then
    info_echo "已取消 hard 回退。"
    return 0
  fi
  check_reset_context || return $?
  current_state="$(capture_hard_reset_state)" || return $?
  [[ "$current_state" == "$before_state" ]] || { error_echo '确认期间索引或已跟踪改动发生变化；未执行 hard 回退，请重新核对。'; return 1; }
  check_reset_context || return $?
  run_git -c submodule.recurse=false reset --hard --no-recurse-submodules "$commit" || return $?
  success_echo "已 hard 回退到 ${commit}；子模块工作树保持原状。"
}
# fzf 区分返回、取消和失败；非根选择按左方向键返回模式层。
choose_entry() {
  local title="$1" allow_back="$2" entry="" output="" selection_result=0
  local -a entries=()
  local -a options=(--no-sort --reverse --no-multi --prompt="${title}：")
  shift 2
  for entry in "$@"; do
    [[ -n "$entry" ]] && entries+=("$entry")
  done
  SELECTION=""
  [[ "${#entries[@]}" -gt 0 ]] || { error_echo "没有可供选择的记录：${title}"; return 1; }
  [[ -t 0 && -t 1 ]] || { error_echo '选择回退目标需要可交互终端。'; return 1; }
  command -v fzf >/dev/null && FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= fzf --version >/dev/null || { error_echo 'fzf 不可用，请先安装或修复后重试。'; return 1; }
  if [[ "$allow_back" == 1 ]]; then
    options+=(--expect=left --header='回车选择，← 返回上一层，Esc 取消')
  else
    options+=(--header='回车选择，Esc 取消')
  fi
  output="$(printf '%s\n' "${entries[@]}" | FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= fzf "${options[@]}")" || selection_result=$?
  if [[ "$allow_back" == 1 && "${output%%$'\n'*}" == left ]]; then
    return 10
  fi
  case "$selection_result" in
    0)
      [[ "$allow_back" != 1 ]] || output="${output#*$'\n'}"
      [[ -n "$output" ]] || return 0
      for entry in "${entries[@]}"; do
        if [[ "$output" == "$entry" ]]; then
          SELECTION="$output"
          return 0
        fi
      done
      error_echo '选择器返回了列表之外的内容，已停止。'
      return 2
      ;;
    1|130) return 0 ;;
    *) error_echo "fzf 选择失败：${selection_result}"; return "$selection_result" ;;
  esac
}
# 提交列表首列始终为完整 hash，不从图形线条里猜目标。
perform_selected_reset() {
  local -a records=()
  case "$RESET_MODE" in
    'soft 回退到 upstream') reset_soft_to_remote ;;
    'hard 回退到 upstream')
      resolve_upstream_target || return $?
      confirm_and_reset_hard "$RESET_TARGET" "$UPSTREAM_REF"
      ;;
    '选择提交 soft 回退'|'选择提交 hard 回退')
      records=("${(@f)$(git -C "$REPO_ROOT" log --all --format='%H %s' --max-count=200)}")
      choose_entry "选择回退后保留的提交" 1 "${records[@]}" || return $?
      [[ -n "$SELECTION" ]] || return 0
      if [[ "$RESET_MODE" == '选择提交 soft 回退' ]]; then
        RESET_TARGET="${SELECTION%% *}"
        reset_soft_to_target "$SELECTION"
      else
        confirm_and_reset_hard "${SELECTION%% *}" "$SELECTION"
      fi
      ;;
    '选择 tag hard 回退')
      records=("${(@f)$(git -C "$REPO_ROOT" tag --sort=-creatordate)}")
      choose_entry "选择 tag" 1 "${records[@]}" || return $?
      [[ -n "$SELECTION" ]] || return 0
      confirm_and_reset_hard "refs/tags/${SELECTION}" "$SELECTION"
      ;;
    '选择 reflog hard 回退')
      records=("${(@f)$(git -C "$REPO_ROOT" reflog --format='%H %gd %gs' --max-count=200)}")
      choose_entry "选择 reflog" 1 "${records[@]}" || return $?
      [[ -n "$SELECTION" ]] || return 0
      confirm_and_reset_hard "${SELECTION%% *}" "$SELECTION"
      ;;
    *) info_echo "已取消回退。" ;;
  esac
}
# 返回键只重进模式层，取消不会执行后续回退。
run_interactive_reset() {
  local result=0
  local -a modes=('soft 回退到 upstream' '选择提交 soft 回退')
  [[ "$TERMINAL_SOFT" == 1 ]] || modes+=('hard 回退到 upstream' '选择提交 hard 回退' '选择 tag hard 回退' '选择 reflog hard 回退')
  while true; do
    choose_entry '选择回退模式' 0 "${modes[@]}" || return $?
    [[ -n "$SELECTION" ]] || { info_echo '已取消回退。'; return 0; }
    RESET_MODE="$SELECTION"
    result=0
    perform_selected_reset || result=$?
    [[ "$result" != 10 ]] || continue
    [[ "$result" != 20 ]] || { info_echo '已取消回退。'; return 0; }
    return "$result"
  done
}
# 使用 argv 与 shell 引号承接明确仓库，终端回退仍需确认和选择。
open_terminal_for_selection() {
  /usr/bin/osascript - "$SCRIPT_PATH" "$REPO_ROOT" <<'APPLESCRIPT'
on run argv
  set shellCommand to "/bin/zsh " & quoted form of item 1 of argv & " --terminal-soft " & quoted form of item 2 of argv & "; jobs_reset_result=$?; printf '\\n提交回退结束，退出码：%s\\n' \"$jobs_reset_result\""
  tell application "Terminal"
    activate
    do script shellCommand
  end tell
end run
APPLESCRIPT
  local launch_result=$?
  (( launch_result == 0 )) || { error_echo 'Terminal 启动失败；仓库未回退，请在终端手动运行。'; return "$launch_result"; }
  jobs_prompt_output info_echo '已转交 Terminal；回车确认后选择回退模式与目标，最终结果在新终端查看。'
}
# 各线路当前分支快照不一致时不能仅按默认 upstream 解释全部推送状态。
dispatch_multiremote_selection() {
  [[ "$IS_SOURCETREE_RUNTIME" == 1 && -z "$REQUESTED_UPSTREAM_REF" ]] || return 0
  collect_upstream_choices
  local ref="" commit=""
  local -a commits=()
  for ref in "${UPSTREAM_CHOICES[@]}"; do
    commit="$(git -C "$REPO_ROOT" rev-parse "$ref")"
    commits+=("$commit")
  done
  commits=("${(@u)commits}")
  (( ${#commits[@]} > 1 )) || return 0
  warn_echo '检测到多条远端线路的本地快照不同；请明确选择，当前还没有执行 reset。'
  for ref in "${UPSTREAM_CHOICES[@]}"; do
    info_echo "${ref} [$(git -C "$REPO_ROOT" rev-parse --short "$ref")]"
  done
  open_terminal_for_selection || exit $?
  exit 0
}
run_reset_workflow() {
  if [[ "$IS_SOURCETREE_RUNTIME" == 1 ]]; then
    reset_soft_to_remote
  else
    run_interactive_reset
  fi
}
print_completion() {
  success_echo "提交回退流程结束；日志：${LOG_FILE}"
}
main() {
  show_script_intro_and_wait "$@" # 首屏自述与确认，Sourcetree 仅跳过入口确认。
  initialize_script_runtime # 确认后准备日志与 Shell 选项。
  isolate_git_context # 隔离继承的 Git 仓库定位变量，保护明确选定的工作树。
  check_environment # 验证 Git 可用。
  parse_arguments "$@" # 解析仓库和显式远端快照，不猜最近失败线路。
  resolve_repository "$REPO_ARGUMENT" # 使用指定工作树，避免误处理外层仓库。
  check_repository_state # 冲突、锁与未完成操作阻止重置。
  dispatch_multiremote_selection # Sourcetree 多线路不一致时转交终端明确选择。
  run_reset_workflow # Sourcetree 执行安全 soft 模式，终端允许选择并确认 hard 模式。
  print_completion # 业务成功后输出结果与日志位置。
}

main "$@"
