#!/bin/zsh
# 脚本自述：
# - 脚本名称：RepairAndroidSimulator.zsh
# - 核心用途：只对 Android Emulator 执行存储诊断与逐项确认的修复。
# - 影响范围：选定模拟器的安装位置、编译缓存、明确包名或备份后的 AVD 配置。
# - 运行提示：--check 只查询；交互修复先阅读自述，危险动作输入 YES；不安装工具、不 Wipe Data。

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
LOG_FILE=""
MODE="repair"
REQUESTED_SERIAL=""
ADB_BIN=""
EMULATOR_BIN=""
DEVICE_ID=""
AVD_NAME=""
AVD_HOME=""
AVD_PATH=""
AVD_DESCRIPTOR=""
CONFIG_PATH=""
BACKUP_PATH=""
THRESHOLD_MB=800
DEVICE_SERIALS=()
# 给交互终端突出自述标题，日志与非交互输出保持纯文本。
intro_line() {
  local role="$1"
  local message="$2"
  if [[ -t 1 && -n "${TERM:-}" && "${TERM}" != dumb && -z "${NO_COLOR+x}" ]]; then
    if [[ "$role" == title ]]; then
      /usr/bin/printf '\033[1;31m%s\033[0m\n' "$message"
    else
      /usr/bin/printf '\033[0;34m%s\033[0m\n' "$message"
    fi
  else
    print -r -- "$message"
  fi
}
# 第一屏声明作用范围；只读与帮助参数允许无交互执行。
show_script_intro_and_wait() {
  intro_line title '━━━━━━━━━━ Android 模拟器检测与修复 ━━━━━━━━━━'
  intro_line body '1、用途：诊断 /data 空间与安装位置；仅接受 Android Emulator，排除物理真机。'
  intro_line body '2、影响：每项修复单独确认；卸载删除所选包数据，容量配置须先停机并完整备份 AVD。'
  intro_line body '3、边界：不自动安装 SDK，不批量删内置应用，不 Wipe Data；配置增大不保证已有 userdata 扩容。'
  intro_line body '4、策略：--check 只查询且不写本工具日志；修复日志位于系统临时目录的 JobsAndroidSimulatorRepairer-*.log。'
  jobs_prompt_output intro_line body '5、取消：直接回车跳过可选操作，危险操作只接受 YES；Ctrl+C 随时停止。'
  if (( ${@[(Ie)--check]} || ${@[(Ie)--help]} || ${@[(Ie)-h]} )); then
    return 0
  fi
  [[ -t 0 ]] || { print -u2 -r -- '错误：修复需要可交互终端；诊断可使用 --check。'; exit 1; }
  read -r "?$(jobs_prompt_render '已了解用途，按回车进入；Ctrl+C 取消：')" _ || exit 0
}
# 严格解析固定入口，不提供绕过确认的自动同意参数。
parse_arguments() {
  while (( $# > 0 )); do
    case "$1" in
      --check) MODE="check"; shift ;;
      --repair) shift ;;
      --serial)
        (( $# >= 2 )) || { print -u2 -r -- '错误：--serial 缺少值。'; exit 2; }
        REQUESTED_SERIAL="$2"
        shift 2
        ;;
      --help|-h)
        print -r -- '用法：/bin/zsh RepairAndroidSimulator.zsh [--check|--repair] [--serial emulator-5554]'
        print -r -- '可用环境：ANDROID_ADB_BIN、ANDROID_EMULATOR_BIN、ANDROID_SDK_ROOT、ANDROID_HOME、ANDROID_AVD_HOME、ANDROID_USER_HOME。'
        exit 0
        ;;
      *) print -u2 -r -- "错误：未知参数 $1"; exit 2 ;;
    esac
  done
  if [[ -n "$REQUESTED_SERIAL" && ! "$REQUESTED_SERIAL" =~ '^emulator-[0-9]+$' ]]; then
    print -u2 -r -- '错误：仅允许 emulator-数字 形式的 Android Emulator 序列号。'
    exit 2
  fi
}
# 用户确认后才准备日志；只读模式不创建文件。
initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  umask 077
  SCRIPT_DIR="${ZSH_ARGZERO:A:h}"
  if [[ "$MODE" == repair ]]; then
    LOG_FILE="$(/usr/bin/mktemp "${TMPDIR:-/tmp/}JobsAndroidSimulatorRepairer-XXXXXX.log")" || exit 1
  fi
}
# 清除终端控制序列，避免设备输出污染终端或持久日志。
safe_text() {
  /usr/bin/awk 'BEGIN { esc=sprintf("%c",27) } { gsub(esc "\\[[0-?]*[ -/]*[@-~]", ""); gsub(/[\001-\010\013-\037\177]/, ""); print }'
}
# 同步输出纯文本；只读模式只显示到标准输出。
log() {
  if [[ -n "$LOG_FILE" ]]; then
    print -r -- "$*" | safe_text | jobs_prompt_tee "$LOG_FILE"
  else
    print -r -- "$*" | safe_text
  fi
}
# 普通修复直接回车跳过；非空输入才执行。
ask_run() {
  local answer=""
  read -r "answer?$(jobs_prompt_render "$1（直接回车跳过，输入任意字符后回车执行）：")" || return 1
  [[ -n "$answer" ]]
}
# 删除、缓存重置及容量修改必须精确输入 YES。
confirm_yes() {
  local answer=""
  log "⚠ $1"
  read -r 'answer?输入 YES 执行，其它输入取消：' || return 1
  [[ "$answer" == YES ]]
}
# 按显式覆盖、当前 PATH 和标准 SDK 目录发现已有工具，不安装未知软件。
discover_tools() {
  local candidate=""
  local root=""
  local roots=("${ANDROID_SDK_ROOT:-}" "${ANDROID_HOME:-}" "${HOME}/Library/Android/sdk")
  if [[ -n "${ANDROID_ADB_BIN:-}" ]]; then
    [[ -x "$ANDROID_ADB_BIN" && -f "$ANDROID_ADB_BIN" ]] || { log '错误：ANDROID_ADB_BIN 不可执行。'; exit 1; }
    ADB_BIN="$ANDROID_ADB_BIN"
  else
    candidate="$(command -v adb 2>/dev/null)"
    [[ -n "$candidate" && -f "$candidate" && -x "$candidate" ]] && ADB_BIN="$candidate"
    for root in "${roots[@]}"; do
      [[ -z "$ADB_BIN" && -n "$root" && -x "$root/platform-tools/adb" ]] && ADB_BIN="$root/platform-tools/adb"
    done
  fi
  [[ -n "$ADB_BIN" ]] || { log '错误：未找到 adb；请先在 Android Studio 的 SDK Manager 准备 Android SDK Platform-Tools。'; exit 1; }
  "$ADB_BIN" version >/dev/null 2>&1 || { log "错误：adb 健康检查失败：$ADB_BIN"; exit 1; }
  if [[ -n "${ANDROID_EMULATOR_BIN:-}" ]]; then
    [[ -x "$ANDROID_EMULATOR_BIN" && -f "$ANDROID_EMULATOR_BIN" ]] || { log '错误：ANDROID_EMULATOR_BIN 不可执行。'; exit 1; }
    EMULATOR_BIN="$ANDROID_EMULATOR_BIN"
  else
    candidate="$(command -v emulator 2>/dev/null)"
    [[ -n "$candidate" && -f "$candidate" && -x "$candidate" ]] && EMULATOR_BIN="$candidate"
    roots+=("${ADB_BIN:A:h:h}")
    for root in "${roots[@]}"; do
      [[ -z "$EMULATOR_BIN" && -n "$root" && -x "$root/emulator/emulator" ]] && EMULATOR_BIN="$root/emulator/emulator"
    done
  fi
  if [[ -n "$EMULATOR_BIN" ]] && ! "$EMULATOR_BIN" -version >/dev/null 2>&1; then
    log "警告：emulator 不健康，禁止自动冷启动：$EMULATOR_BIN"
    EMULATOR_BIN=""
  fi
  log "ADB：$ADB_BIN"
  log "Emulator：${EMULATOR_BIN:-未找到；容量流程不会自动冷启动}"
}
# 只收集已在线的 emulator-数字 设备；未经授权与物理设备不进入选择。
collect_devices() {
  local output=""
  output="$("$ADB_BIN" devices 2>&1)" || { log "错误：adb devices 失败：$output"; exit 1; }
  DEVICE_SERIALS=("${(@f)$(print -r -- "$output" | /usr/bin/awk '$1 ~ /^emulator-[0-9]+$/ && $2 == "device" {print $1}')}")
  DEVICE_SERIALS=("${(@)DEVICE_SERIALS:#}")
  (( ${#DEVICE_SERIALS[@]} > 0 )) || { log '错误：未发现在线 Android Emulator；请先启动 AVD。物理真机不会列入。'; exit 1; }
}
# 从 emulator console 取得真实 AVD 名称，并复验 qemu 属性。
device_avd_name() {
  local serial="$1"
  local result=""
  local name=""
  [[ "$serial" =~ '^emulator-[0-9]+$' ]] || return 1
  result="$("$ADB_BIN" -s "$serial" emu avd name 2>/dev/null)" || return 1
  name="$(print -r -- "$result" | /usr/bin/tr -d '\r' | /usr/bin/awk 'NF && $0 != "OK" { print; exit }')"
  [[ "$name" =~ '^[A-Za-z0-9_.-]+$' && "$name" != . && "$name" != .. ]] || return 1
  result="$("$ADB_BIN" -s "$serial" shell getprop ro.kernel.qemu 2>/dev/null)" || return 1
  [[ "${result//$'\r'/}" == 1 ]] || return 1
  print -r -- "$name"
}
# 每次写操作前复验 serial 与 AVD，防止选择期间设备被替换。
ensure_selected_device() {
  local current=""
  current="$(device_avd_name "$DEVICE_ID")" || { log '错误：设备已离线或无法确认 Android Emulator 身份。'; return 1; }
  [[ "$current" == "$AVD_NAME" ]] || { log '错误：同一序列号现已指向其它 AVD，已停止。'; return 1; }
}
# 单设备直接选定，多设备使用编号；不把提示混入返回值。
select_device() {
  local index=0
  local answer=""
  if [[ -n "$REQUESTED_SERIAL" ]]; then
    (( ${DEVICE_SERIALS[(Ie)$REQUESTED_SERIAL]} )) || { log '错误：指定模拟器不在线。'; exit 1; }
    DEVICE_ID="$REQUESTED_SERIAL"
  elif (( ${#DEVICE_SERIALS[@]} == 1 )); then
    DEVICE_ID="${DEVICE_SERIALS[1]}"
  else
    for (( index=1; index <= ${#DEVICE_SERIALS[@]}; index++ )); do
      log "$index、${DEVICE_SERIALS[$index]}"
    done
    read -r "answer?$(jobs_prompt_render '选择模拟器序号（直接回车取消）：')" || exit 0
    [[ "$answer" =~ '^[0-9]+$' && ${#answer} -le 3 ]] || exit 0
    index=$((10#$answer))
    (( index >= 1 && index <= ${#DEVICE_SERIALS[@]} )) || { log '错误：序号不在列表中。'; exit 1; }
    DEVICE_ID="${DEVICE_SERIALS[$index]}"
  fi
  AVD_NAME="$(device_avd_name "$DEVICE_ID")" || { log '错误：无法确认所选 Android Emulator 的 AVD 身份。'; exit 1; }
  log "选择：$DEVICE_ID；AVD：$AVD_NAME"
}
# 解析 df 的 Available 列；无法识别时返回失败，不伪造 0 或空间充足。
space_report() {
  local output=""
  local available=""
  output="$("$ADB_BIN" -s "$DEVICE_ID" shell df -k /data 2>&1)" || { log "错误：空间查询失败：$output"; return 1; }
  available="$(print -r -- "$output" | /usr/bin/tr -d '\r' | /usr/bin/awk 'NR==1 { for(i=1;i<=NF;i++) if($i=="Available" || $i=="Avail") col=i; next } col && NF>=col {v=$col} END {if(v ~ /^[0-9]+$/) print v}')"
  [[ "$available" =~ '^[0-9]+$' && ${#available} -le 14 ]] || { log "错误：无法解析 /data 可用空间：$output"; return 1; }
  log "/data 可用：$(( available / 1024 )) MB；提示阈值：$THRESHOLD_MB MB。"
  if (( available / 1024 < THRESHOLD_MB )); then
    log '警告：空间偏低；按需选择修复动作。'
    return 1
  fi
  return 0
}
# 取得 /data 当前文件系统总量；未知格式时拒绝容量修改。
data_total_mb() {
  local output=""
  local total=""
  output="$("$ADB_BIN" -s "$DEVICE_ID" shell df -k /data 2>/dev/null)" || return 1
  total="$(print -r -- "$output" | /usr/bin/tr -d '\r' | /usr/bin/awk 'NR==1 {for(i=1;i<=NF;i++) if($i=="1K-blocks" || $i=="1024-blocks") col=i; next} col && NF>=col {v=$col} END {if(v ~ /^[0-9]+$/) print v}')"
  [[ "$total" =~ '^[0-9]+$' && ${#total} -le 14 ]] || return 1
  print -r -- "$(( (total + 1023) / 1024 ))"
}
# 显示安装位置和空间；诊断错误保留非零退出码。
diagnose_device() {
  local location=""
  local failed=0
  ensure_selected_device || return 1
  location="$("$ADB_BIN" -s "$DEVICE_ID" shell pm get-install-location 2>&1)" || { log "错误：安装位置查询失败：$location"; return 1; }
  log "设备：$DEVICE_ID；AVD：$AVD_NAME；安装位置：$location"
  location="${location//$'\r'/}"
  [[ "$location" =~ '^0([[:space:]]*\[[^]]*\])?[[:space:]]*$' ]] || { log '警告：默认安装位置不是 0（自动）或响应无法识别。'; failed=1; }
  space_report || failed=1
  return "$failed"
}
# 只读模式支持指定设备或依次报告全部模拟器，不初始化日志和 AVD 配置。
run_checks_if_requested() {
  [[ "$MODE" == check ]] || return 0
  local serial=""
  local failed=0
  for serial in "${DEVICE_SERIALS[@]}"; do
    [[ -z "$REQUESTED_SERIAL" || "$REQUESTED_SERIAL" == "$serial" ]] || continue
    DEVICE_ID="$serial"
    AVD_NAME="$(device_avd_name "$serial")" || { log "错误：无法确认 $serial 的 AVD 身份。"; failed=1; continue; }
    diagnose_device || failed=1
  done
  if [[ -n "$REQUESTED_SERIAL" ]] && (( ! ${DEVICE_SERIALS[(Ie)$REQUESTED_SERIAL]} )); then
    log '错误：指定模拟器不在线。'
    failed=1
  fi
  exit "$failed"
}
# 确认后恢复安装位置，并查询实际结果，失败不报告修复成功。
fix_install_location() {
  ask_run '恢复当前模拟器的默认安装位置 0（自动）' || return 0
  ensure_selected_device || return 1
  local output=""
  output="$("$ADB_BIN" -s "$DEVICE_ID" shell pm set-install-location 0 2>&1)" || { log "错误：安装位置修改失败：$output"; return 1; }
  if print -r -- "$output" | /usr/bin/grep -Eiq 'error|failure|exception|unknown|not found'; then
    log "错误：设备拒绝安装位置修改：$output"
    return 1
  fi
  output="$("$ADB_BIN" -s "$DEVICE_ID" shell pm get-install-location 2>&1)" || { log "错误：安装位置复检失败：$output"; return 1; }
  output="${output//$'\r'/}"
  [[ "$output" =~ '^0([[:space:]]*\[[^]]*\])?[[:space:]]*$' ]] || { log "错误：安装位置未确认恢复为自动：$output"; return 1; }
  log '✔ 已回读确认安装位置为 0（自动）。'
  space_report
}
# 缓存重置可触发之后重新编译，只在明确 YES 后执行。
reset_compile_cache() {
  confirm_yes '重置所选模拟器全部包的编译状态；之后启动应用可能重新编译，空间收益需复检。' || return 0
  ensure_selected_device || return 1
  local output=""
  output="$("$ADB_BIN" -s "$DEVICE_ID" shell cmd package compile --reset -a 2>&1)" || { log "错误：编译状态重置失败或设备不支持：$output"; return 1; }
  if print -r -- "$output" | /usr/bin/grep -Eiq 'failure|error|exception|unknown|not found'; then
    log "错误：设备拒绝编译状态重置：$output"
    return 1
  fi
  log '编译状态重置命令已完成；以下空间查询决定实际结果。'
  space_report
}
# 仅卸载用户明确指定且精确存在的第三方包，禁止内置包清单或模糊匹配。
uninstall_exact_package() {
  local package=""
  local packages=""
  local output=""
  read -r "package?$(jobs_prompt_render '输入完整第三方包名（直接回车取消）：')" || return 0
  [[ -n "$package" ]] || return 0
  [[ "$package" =~ '^[A-Za-z][A-Za-z0-9_]*([.][A-Za-z][A-Za-z0-9_]*)+$' && ${#package} -le 255 ]] || { log '错误：包名格式非法。'; return 1; }
  ensure_selected_device || return 1
  packages="$("$ADB_BIN" -s "$DEVICE_ID" shell pm list packages -3 2>&1)" || { log "错误：第三方包清单查询失败：$packages"; return 1; }
  print -r -- "$packages" | /usr/bin/tr -d '\r' | /usr/bin/grep -Fxq -- "package:$package" || { log '错误：该精确包名不在第三方应用清单；未卸载。'; return 1; }
  confirm_yes "卸载 $package，删除该包在 $DEVICE_ID 上的应用与数据。" || return 0
  ensure_selected_device || return 1
  output="$("$ADB_BIN" -s "$DEVICE_ID" uninstall "$package" 2>&1)" || { log "错误：卸载失败：$output"; return 1; }
  [[ "${output//$'\r'/}" == Success ]] || { log "错误：设备未确认卸载成功：$output"; return 1; }
  log "✔ 设备报告已卸载：$package"
  space_report
}
# 配置与描述符只接受真实目录，拒绝符号链接和 AVD 根之外的写入。
resolve_avd_paths() {
  local descriptor_path=""
  local relative_path=""
  AVD_HOME="${ANDROID_AVD_HOME:-${ANDROID_USER_HOME:-${HOME}/.android}/avd}"
  [[ "$AVD_HOME" == /* && -d "$AVD_HOME" && ! -L "$AVD_HOME" ]] || { log '错误：AVD 根目录不是普通绝对目录。'; return 1; }
  AVD_HOME="${AVD_HOME:A}"
  AVD_DESCRIPTOR="$AVD_HOME/$AVD_NAME.ini"
  [[ -f "$AVD_DESCRIPTOR" && ! -L "$AVD_DESCRIPTOR" ]] || { log '错误：找不到普通 AVD .ini 描述符。'; return 1; }
  if ! /usr/bin/awk -F= '$1=="path" {paths++} $1=="path.rel" {relative++} END {exit (paths>1 || relative>1)}' "$AVD_DESCRIPTOR"; then
    log '错误：AVD 描述符含重复 path 或 path.rel，无法确认解释一致。'
    return 1
  fi
  descriptor_path="$(/usr/bin/awk -F= '$1=="path" {sub(/^[^=]*=/, ""); print; exit}' "$AVD_DESCRIPTOR")"
  relative_path="$(/usr/bin/awk -F= '$1=="path.rel" {sub(/^[^=]*=/, ""); print; exit}' "$AVD_DESCRIPTOR")"
  if [[ -n "$descriptor_path" ]]; then
    AVD_PATH="$descriptor_path"
  elif [[ -n "$relative_path" ]]; then
    AVD_PATH="${AVD_HOME:h}/$relative_path"
  else
    AVD_PATH="$AVD_HOME/$AVD_NAME.avd"
  fi
  [[ "$AVD_PATH" == /* && -d "$AVD_PATH" && ! -L "$AVD_PATH" ]] || { log '错误：AVD 描述符指向非普通绝对目录。'; return 1; }
  AVD_PATH="${AVD_PATH:A}"
  [[ "$AVD_PATH" == "$AVD_HOME/"* && "$AVD_PATH" != "$AVD_HOME" ]] || { log '错误：AVD 位于所选 AVD 根之外；请在 Device Manager 人工处理。'; return 1; }
  CONFIG_PATH="$AVD_PATH/config.ini"
  [[ -f "$CONFIG_PATH" && ! -L "$CONFIG_PATH" ]] || { log '错误：config.ini 缺失或为符号链接。'; return 1; }
  [[ -z "$(/usr/bin/find "$AVD_PATH" -type l -print)" ]] || { log '错误：AVD 内存在符号链接；已拒绝自动写入和备份。'; return 1; }
  [[ "$(/usr/bin/awk -F= '$1=="AvdId" {n++} END {print n+0}' "$CONFIG_PATH")" == 1 ]] || { log '错误：config.ini 的 AvdId 缺失或重复。'; return 1; }
  [[ "$(/usr/bin/awk -F= '$1=="AvdId" {print $2; exit}' "$CONFIG_PATH")" == "$AVD_NAME" ]] || { log '错误：config.ini 的 AvdId 与在线模拟器不匹配。'; return 1; }
}
# 自定义 userdata、只读实例或无法确认运行参数时禁止自动容量调整。
validate_default_userdata() {
  local processes=""
  local matching=""
  local image=""
  if /usr/bin/awk -F= '($1=="disk.dataPartition.path" || $1=="disk.dataPartition.initPath") && length($2)>0 {found=1} END {exit !found}' "$CONFIG_PATH"; then
    log '错误：存在显式 disk.dataPartition.path 或 disk.dataPartition.initPath；不会只备份默认目录后修改自定义数据。'
    return 1
  fi
  processes="$(/bin/ps -axo command=)" || return 1
  matching="$(print -r -- "$processes" | /usr/bin/awk -v name="$AVD_NAME" -v directory="$AVD_PATH" '
    /qemu-system|\/emulator/ && (index($0," -avd " name " ") || index($0," -avd " name)==length($0)-length(" -avd " name)+1 || index($0," @" name " ") || index($0,directory)) {print}
  ')"
  [[ -n "$matching" ]] || { log '错误：无法确认当前 AVD 的进程参数；容量配置请在 Device Manager 人工处理。'; return 1; }
  if print -r -- "$matching" | /usr/bin/grep -Eq -- '(^|[[:space:]])-(data|datadir|read-only)([[:space:]=]|$)'; then
    log '错误：当前实例使用 -data、-datadir 或 -read-only；自动容量调整已拒绝。'
    return 1
  fi
  for image in "$AVD_PATH/userdata-qemu.img" "$AVD_PATH/userdata.img"; do
    [[ ! -e "$image" || ( -f "$image" && ! -L "$image" ) ]] || { log '错误：userdata 不是普通文件。'; return 1; }
  done
}
# 把官方配置中的字节或 K/M/G 大小转成 MB；未知单位拒绝推断。
size_in_mb() {
  local value="$1"
  local number=""
  local multiplier=1
  [[ "$value" =~ '^[1-9][0-9]{0,11}([KkMmGg])?$' ]] || return 1
  number="${value%[KkMmGg]}"
  case "$value" in
    *[Gg]) multiplier=1024 ;;
    *[Mm]) multiplier=1 ;;
    *[Kk]) print -r -- "$(( (number + 1023) / 1024 ))"; return 0 ;;
    *) print -r -- "$(( (number + 1048575) / 1048576 ))"; return 0 ;;
  esac
  print -r -- "$(( number * multiplier ))"
}
# 停机必须同时满足 ADB 消失、锁释放、匹配进程退出，任一不确定都停止。
avd_is_stopped() {
  local devices=""
  local locks=("$AVD_PATH"/*.lock(N) "$AVD_PATH"/**/*.lock(N))
  local processes=""
  devices="$("$ADB_BIN" devices 2>/dev/null)" || return 1
  print -r -- "$devices" | /usr/bin/awk -v serial="$DEVICE_ID" '$1==serial {found=1} END {exit !found}' && return 1
  (( ${#locks[@]} == 0 )) || return 1
  processes="$(/bin/ps -axo command=)" || return 1
  print -r -- "$processes" | /usr/bin/awk -v name="$AVD_NAME" -v directory="$AVD_PATH" '
    /qemu-system|\/emulator/ && (index($0," -avd " name " ") || index($0," -avd " name)==length($0)-length(" -avd " name)+1 || index($0," @" name " ") || index($0,directory)) {found=1}
    END {exit !found}
  ' && return 1
  return 0
}
# 发出指定 emulator 的停机命令并有界等待，超时保留原配置。
stop_selected_avd() {
  ensure_selected_device || return 1
  local output=""
  local attempt=0
  output="$("$ADB_BIN" -s "$DEVICE_ID" emu kill 2>&1)" || { log "错误：模拟器未接受停机：$output"; return 1; }
  for attempt in {1..30}; do
    if avd_is_stopped; then
      log '✔ 设备已离线、锁已释放，未发现匹配运行进程。'
      return 0
    fi
    /bin/sleep 1
  done
  log '错误：30 秒内无法确认完全停机；未备份或修改配置，不删除残留锁。'
  return 1
}
# 按逻辑体积估算备份空间，完整保存 AVD 后才允许改配置。
backup_stopped_avd() {
  local target_mb="$1"
  local required_kb=""
  local available_kb=""
  required_kb="$(/usr/bin/du -A -sk "$AVD_PATH" | /usr/bin/awk '{print $1}')" || return 1
  available_kb="$(/bin/df -k "$AVD_HOME" | /usr/bin/awk 'END {print $4}')" || return 1
  [[ "$required_kb" =~ '^[0-9]+$' && "$available_kb" =~ '^[0-9]+$' ]] || { log '错误：无法确认备份磁盘空间。'; return 1; }
  (( available_kb > required_kb + target_mb * 1024 + 1048576 )) || { log '错误：可用空间不足以备份完整 AVD、预留目标容量并保留 1 GB 余量。'; return 1; }
  BACKUP_PATH="$(/usr/bin/mktemp -d "$AVD_HOME/.$AVD_NAME.repair-backup.XXXXXX")" || return 1
  log "来源：$AVD_PATH 与 $AVD_DESCRIPTOR"
  log "完整备份目标：$BACKUP_PATH；备份失败时保留现场，配置不会修改。"
  /usr/bin/ditto --norsrc --noextattr "$AVD_PATH" "$BACKUP_PATH/avd" || { log '错误：完整 AVD 备份失败；未修改配置。'; return 1; }
  /bin/cp -p "$AVD_DESCRIPTOR" "$BACKUP_PATH/$AVD_NAME.ini" || { log '错误：AVD 描述符备份失败；未修改配置。'; return 1; }
  /usr/bin/diff -qr "$AVD_PATH" "$BACKUP_PATH/avd" >/dev/null || { log '错误：完整 AVD 备份字节校验失败；未修改配置。'; return 1; }
}
# 仅增大配置，停机与备份再次验证后原子替换；不自行操作 userdata 或 qcow2。
write_larger_config() {
  local target_mb="$1"
  local stage=""
  avd_is_stopped || { log '错误：备份期间模拟器重新运行；未修改配置。'; return 1; }
  /usr/bin/cmp -s "$CONFIG_PATH" "$BACKUP_PATH/avd/config.ini" || { log '错误：备份后配置发生变化；未修改。'; return 1; }
  stage="$(/usr/bin/mktemp "$AVD_PATH/.jobs-config.XXXXXX")" || return 1
  if ! /usr/bin/awk -v size="${target_mb}M" 'BEGIN {seen=0} /^disk[.]dataPartition[.]size=/ {if(!seen) print "disk.dataPartition.size=" size; seen=1; next} {print} END {if(!seen) print "disk.dataPartition.size=" size}' "$CONFIG_PATH" > "$stage"; then
    /bin/rm -f -- "$stage"
    log '错误：配置草稿写入失败；原配置保留。'
    return 1
  fi
  /bin/chmod "$(/usr/bin/stat -f '%Lp' "$CONFIG_PATH")" "$stage" || return 1
  avd_is_stopped || { /bin/rm -f -- "$stage"; log '错误：模拟器重新启动；取消配置写入。'; return 1; }
  /bin/mv -f -- "$stage" "$CONFIG_PATH" || { log '错误：配置替换失败；请保留备份。'; return 1; }
  log "✔ 配置已写为 ${target_mb}M；完整备份：$BACKUP_PATH"
  log '这只确认配置值，不代表已有 userdata 文件系统已扩容；冷启动可能改写现有数据镜像。'
}
# 经单独确认以禁用快照加载的方式启动，并等待真实设备启动后查询空间。
cold_boot_and_recheck() {
  local before_total_mb="$1"
  local after_total_mb=""
  [[ -n "$EMULATOR_BIN" ]] || { log '待验证：未找到健康 emulator；请在 Device Manager 使用 Cold Boot，启动后重新执行 --check。'; return 2; }
  ask_run '使用 -no-snapshot-load 冷启动此 AVD（不使用 -wipe-data）；可能由 Emulator 调整已有 userdata' || { log '待验证：已跳过冷启动，仅配置已改变，容量尚未确认。'; return 2; }
  avd_is_stopped || { log '错误：AVD 已有运行实例，未重复启动。'; return 1; }
  log "启动：$EMULATOR_BIN -avd $AVD_NAME -no-snapshot-load"
  /usr/bin/nohup "$EMULATOR_BIN" -avd "$AVD_NAME" -no-snapshot-load < /dev/null 2>&1 | safe_text >> "$LOG_FILE" &!
  local attempt=0
  local serial=""
  local name=""
  local booted=""
  for attempt in {1..60}; do
    for serial in "${(@f)$("$ADB_BIN" devices 2>/dev/null | /usr/bin/awk '$1 ~ /^emulator-[0-9]+$/ && $2=="device" {print $1}')}"; do
      name="$(device_avd_name "$serial")" || continue
      [[ "$name" == "$AVD_NAME" ]] || continue
      booted="$("$ADB_BIN" -s "$serial" shell getprop sys.boot_completed 2>/dev/null)" || continue
      [[ "${booted//$'\r'/}" == 1 ]] || continue
      DEVICE_ID="$serial"
      log '冷启动后的实际空间复检：'
      diagnose_device || return 1
      after_total_mb="$(data_total_mb)" || { log '错误：启动后无法读取 /data 总量，容量未确认。'; return 1; }
      if (( after_total_mb <= before_total_mb )); then
        log "待验证：/data 总量没有增加（之前 $before_total_mb MB，现在 $after_total_mb MB）；配置不等于扩容生效。"
        return 2
      fi
      log "✔ 已复核 /data 总量增加（$before_total_mb → $after_total_mb MB），且可用空间达到阈值。"
      return 0
    done
    /bin/sleep 2
  done
  log '警告：120 秒内未确认启动完成；不认定容量生效。稍后重新执行 --check。'
  return 1
}
# 容量修复只接受更大的已知配置，先停机、完整备份，再改配置与可选冷启动。
increase_avd_capacity() {
  ensure_selected_device || return 1
  resolve_avd_paths || return 1
  local current=""
  local current_mb=""
  local target=""
  local target_mb=""
  local count=""
  local total_mb=""
  local image=""
  local image_bytes=""
  local initial_checksum=""
  count="$(/usr/bin/awk '/^disk[.]dataPartition[.]size=/ {n++} END {print n+0}' "$CONFIG_PATH")"
  [[ "$count" == 1 ]] || { log '错误：容量配置缺失或重复；无法确认不缩容，停止自动修改。'; return 1; }
  current="$(/usr/bin/awk -F= '$1=="disk.dataPartition.size" {print $2}' "$CONFIG_PATH")"
  current_mb="$(size_in_mb "$current")" || { log "错误：无法识别现有容量 $current；停止自动修改。"; return 1; }
  validate_default_userdata || return 1
  total_mb="$(data_total_mb)" || { log '错误：无法读取 /data 总量；不推断安全扩容值。'; return 1; }
  initial_checksum="$(/usr/bin/cksum "$CONFIG_PATH")" || return 1
  log "AVD：$AVD_PATH；当前配置：$current（约 $current_mb MB）。"
  read -r "target?$(jobs_prompt_render '目标容量（如 8G、12G，直接回车取消）：')" || return 0
  [[ -n "$target" ]] || return 0
  target_mb="$(size_in_mb "$target")" || { log '错误：容量须为正整数与可选 K/M/G 单位。'; return 1; }
  (( target_mb > current_mb && target_mb <= 1048576 )) || { log '错误：目标必须严格大于当前容量，且不超过 1 TB；不会缩容。'; return 1; }
  (( target_mb > total_mb )) || { log '错误：目标没有超过现有 /data 文件系统总量，已拒绝。'; return 1; }
  for image in "$AVD_PATH/userdata-qemu.img" "$AVD_PATH/userdata.img"; do
    [[ -f "$image" ]] || continue
    image_bytes="$(/usr/bin/stat -f '%z' "$image")" || return 1
    [[ "$image_bytes" =~ '^[0-9]+$' ]] || return 1
    (( target_mb * 1048576 > image_bytes )) || { log '错误：目标没有超过现有 userdata 镜像逻辑大小，已拒绝。'; return 1; }
  done
  confirm_yes "停止 $AVD_NAME、完整备份后把配置增大到 $target。备份可能很大；已有 userdata 不保证扩容，冷启动可能改写数据镜像。" || return 0
  stop_selected_avd || return 1
  resolve_avd_paths || return 1
  [[ "$(/usr/bin/cksum "$CONFIG_PATH")" == "$initial_checksum" ]] || { log '错误：等待期间 config.ini 发生变化；未备份或修改。'; return 1; }
  backup_stopped_avd "$target_mb" || return 1
  write_larger_config "$target_mb" || return 1
  cold_boot_and_recheck "$total_mb"
}
# 交互菜单始终从诊断开始，各动作失败保留现场并回到菜单。
run_repair_menu() {
  local answer=""
  local failed=0
  diagnose_device || log '警告：初始诊断不完整；请先检查 adb 与模拟器。'
  while true; do
    log '1、重新诊断  2、恢复默认安装位置  3、重置编译状态  4、卸载精确第三方包  5、增加 AVD 容量配置  0、退出'
    read -r "answer?$(jobs_prompt_render '选择动作（直接回车退出）：')" || break
    case "$answer" in
      1) diagnose_device || { log '本项诊断未通过。'; failed=1; } ;;
      2) fix_install_location || { log '本项修复未完成。'; failed=1; } ;;
      3) reset_compile_cache || { log '本项修复未完成。'; failed=1; } ;;
      4) uninstall_exact_package || { log '本项修复未完成。'; failed=1; } ;;
      5) increase_avd_capacity || { log '本项容量流程未完成；配置与备份状态以以上日志为准。'; failed=1; } ;;
      0|'') break ;;
      *) log '请输入列表内序号。' ;;
    esac
  done
  diagnose_device || { log '最终诊断未通过或设备处于停机待验证状态。'; failed=1; }
  log "流程结束；操作和复检结果见日志：$LOG_FILE"
  return "$failed"
}
# 编排自述、只读诊断或经过确认的交互修复。
main() {
  show_script_intro_and_wait "$@" # 先说明影响、风险、取消方式和只读入口。
  parse_arguments "$@" # 严格解析动作与模拟器序列号。
  initialize_runtime # 确认后初始化选项，修复模式才创建私有日志。
  discover_tools # 发现并复检已有 SDK 工具，不安装软件。
  collect_devices # 排除物理真机，只收集在线 Emulator。
  run_checks_if_requested # 只读模式查询后退出，不进入任何修复。
  select_device # 在终端内确定唯一 AVD 与序列号。
  run_repair_menu # 每项修复独立确认并复查实际空间。
}

main "$@"
