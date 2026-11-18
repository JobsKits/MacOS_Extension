#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】routes.zsh
# - 核心用途：从正式 main 验证直连探测、实时代理发现和业务命令单次执行。
# - 影响范围：只读同包源码；所有 HOME、探测和 Git 调用都替换为隔离夹具。
# - 运行提示：不连接公网，不修改用户 Git、系统代理或真实仓库。
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
    jobs_style_original_rows=''
    jobs_style_applied_rows=''
    jobs_style_changed=0
    jobs_style_applied_complete=0
    jobs_style_query_active=0
    jobs_style_recovery=''
    jobs_style_exit_status=0
    jobs_style_esc=$(printf '\033')
    jobs_style_bel=$(printf '\007')
    # 完整颜色帧有界重发；设置核验与退出恢复容忍帧外回车和明确方向键。
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
                    # 设置核验与退出恢复阶段允许帧外的明确控制键，普通文字仍然失败。
                    if [ "$jobs_style_query_phase" = cleanup ] || [ "$jobs_style_query_phase" = applied ]; then
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
                            jobs_style_phase_control_keys=$(( ${jobs_style_phase_control_keys:-0} + 1 ))
                            if [ "$jobs_style_phase_control_keys" -gt 64 ]; then
                                jobs_style_query_failure='本阶段已识别控制键超过 64 个，已停止自动恢复'
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
    # 核验中断时重新读取当前值，只撤回仍等于本轮目标值的颜色。
    jobs_terminal_style_rollback() {
        jobs_style_rollback_issue='无法读取或设置原终端输入模式'
        jobs_style_rollback_safe=''
        jobs_style_rollback_conflicts=''
        jobs_style_phase_control_keys=0
        jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_style_stty=''
        if [ -n "$jobs_style_stty" ] && stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
            jobs_style_query_active=1
            jobs_style_rollback_ok=1
            while IFS='|' read -r jobs_style_key jobs_style_original_normalized jobs_style_original; do
                [ -n "$jobs_style_key" ] || continue
                if ! jobs_terminal_style_query "$jobs_style_key" cleanup; then
                    jobs_style_rollback_ok=0
                    jobs_style_rollback_issue="回退颜色项 $jobs_style_key：$jobs_style_query_failure"
                    break
                fi
                if [ "$jobs_style_normalized" = "$jobs_style_original_normalized" ]; then
                    continue
                elif jobs_terminal_style_accepts_target "$jobs_style_key"; then
                    jobs_style_rollback_safe=$jobs_style_rollback_safe$jobs_style_original
                else
                    jobs_style_rollback_conflicts="$jobs_style_rollback_conflicts $jobs_style_key"
                fi
            done <<JOBS_STYLE_ROLLBACK
$jobs_style_original_rows
JOBS_STYLE_ROLLBACK
            stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_rollback_ok=0; jobs_style_rollback_issue='无法恢复原终端输入模式'; }
            jobs_style_query_active=0
            if [ "$jobs_style_rollback_ok" = 1 ] && printf '%s\033[0m' "$jobs_style_rollback_safe" > /dev/tty; then
                if [ -z "$jobs_style_rollback_conflicts" ]; then
                    rm -f "$jobs_style_recovery"
                    rmdir "${jobs_style_recovery%/*}" 2>/dev/null || :
                    return 0
                fi
                printf '检测到运行期间的配色变更，已保留这些项：%s\n' "$jobs_style_rollback_conflicts" >&2
                jobs_style_rollback_issue="核验中断后检测到其它配色变更：$jobs_style_rollback_conflicts"
            fi
        fi
        printf '终端配色未能安全自动恢复（%s）；确认覆盖当前配色后可运行：sh "%s"\n' "$jobs_style_rollback_issue" "$jobs_style_recovery" >&2
        return 1
    }
    # 检测到后续改色时只恢复仍由本次保护持有的项，保留独立恢复入口。
    jobs_terminal_style_cleanup() {
        jobs_style_result=$1
        trap '' HUP INT TERM
        if [ "$jobs_style_query_active" = 1 ]; then
            stty "$jobs_style_stty" 2>/dev/null < /dev/tty || :
            jobs_style_query_active=0
        fi
        if [ "$jobs_style_changed" = 1 ] && [ "$jobs_style_applied_complete" != 1 ]; then
            if jobs_terminal_style_rollback; then
                jobs_style_changed=0
            else
                [ "$jobs_style_result" -ne 0 ] || jobs_style_result=1
            fi
            if [ "${2:-}" = continue ]; then
                jobs_style_cleanup_status=$jobs_style_result
                return 0
            fi
            exit "$jobs_style_result"
        fi
        if [ "$jobs_style_changed" = 1 ]; then
            jobs_style_cleanup_ok=0
            jobs_style_cleanup_issue='无法读取或设置原终端输入模式，或临时配色未完成核验'
            jobs_style_conflicts=''
            jobs_style_restore_safe=''
            jobs_style_phase_control_keys=0
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
        jobs_style_original_rows="$jobs_style_original_rows$jobs_style_key|$jobs_style_normalized|$jobs_style_reply
"
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
    jobs_style_phase_control_keys=0
    while IFS='|' read -r jobs_style_key jobs_style_original; do
        [ -n "$jobs_style_key" ] || continue
        if ! jobs_terminal_style_query "$jobs_style_key" applied; then
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
        printf '临时配色核验失败（颜色项 %s：%s），正在核对原色恢复。\n' "$jobs_style_key" "$jobs_style_query_failure" >&2
        jobs_terminal_style_cleanup 0 continue
        jobs_style_changed=0
        if [ "$jobs_style_cleanup_status" != 0 ]; then
            jobs_style_exit_status=1
            exit 1
        fi
        trap 'jobs_style_exit_status=129; jobs_terminal_style_cleanup 129 continue; jobs_style_changed=0; exit 129' HUP
        trap 'jobs_style_exit_status=130; jobs_terminal_style_cleanup 130 continue; jobs_style_changed=0; exit 130' INT
        trap 'jobs_style_exit_status=143; jobs_terminal_style_cleanup 143 continue; jobs_style_changed=0; exit 143' TERM
        printf '%s\n' '已恢复原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
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
    jobs_style_applied_complete=1
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

typeset -g ROUTE_TEST_ROOT='' ROUTE_WRAPPER='' ROUTE_TEMP='' ROUTE_LIBRARY=''
typeset -g CASE_DIR='' CASE_RESULT=0 PASSED=0 FAILED=0
typeset -g TARGET_FIXTURE='' SYSTEM_SNAPSHOT='' PROXY_HTTP=200 DIRECT_HTTP=200
typeset -g PROXY_RESULT=0 DIRECT_RESULT=0 BUSINESS_RESULT=0
typeset -g BUSINESS_STDOUT='' BUSINESS_STDERR='' EXPLICIT_CONFIG=0 EXPLICIT_REMOTE_CONFIG=0
typeset -g FIXTURE_PROXY_ENV_NAME='' FIXTURE_PROXY_ENV_VALUE='' FIXTURE_NO_PROXY=''
typeset -g PROBE_FAILURE_PORT='' DEFAULT_REMOTE='origin'
typeset -g FIXTURE_ROUTE_PRIORITY=direct
typeset -ga FIXTURE_ARGS

# 只回收本测试自身 mktemp 创建的目录。
cleanup_route_tests() {
    [[ -n "$ROUTE_TEMP" && -d "$ROUTE_TEMP" ]] || return 0
    /usr/bin/find "$ROUTE_TEMP" -type f -delete
    /usr/bin/find "$ROUTE_TEMP" -type l -delete
    /usr/bin/find "$ROUTE_TEMP" -depth -type d -empty -delete
}
# 退出时回收本测试拥有的临时夹具。
TRAPEXIT() {
    cleanup_route_tests
}
# 中断后不再执行后续用例。
TRAPINT() {
    exit 130
}
# 终止时交由退出钩子清理。
TRAPTERM() {
    exit 143
}
# 只移除正式入口的最终调用；所有被测分支仍来自生产 wrapper。
prepare_route_suite() {
    setopt NO_NOMATCH
    ROUTE_TEST_ROOT="${${(%):-%x}:A:h:h}"
    ROUTE_WRAPPER="${ROUTE_TEST_ROOT:h}/bin/【MacOS】git.zsh/【MacOS】git.zsh"
    ROUTE_TEMP="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-git-route-tests.XXXXXXXX")" || exit 1
    ROUTE_LIBRARY="${ROUTE_TEMP}/library.zsh"
    /usr/bin/sed '$d' "$ROUTE_WRAPPER" > "$ROUTE_LIBRARY"
}
# 生成可在每次调用前改变端口的系统代理快照。
proxy_snapshot() {
    print -r -- "<dictionary> {
  HTTPSEnable : 1
  HTTPSProxy : 127.0.0.1
  HTTPSPort : $1
  HTTPEnable : 1
  HTTPProxy : 127.0.0.1
  HTTPPort : $1
}"
}
# 每个用例都有独立 HOME；夹具状态不接触真实代理或 Git 配置。
reset_case() {
    CASE_DIR="${ROUTE_TEMP}/case-$1"
    /bin/mkdir -p "${CASE_DIR}/home" "${CASE_DIR}/tmp" "${CASE_DIR}/calls"
    TARGET_FIXTURE='https://git.example.test/team/project.git'
    SYSTEM_SNAPSHOT="$(proxy_snapshot 8101)"
    DIRECT_HTTP=200
    DIRECT_RESULT=0
    PROXY_HTTP=200
    PROXY_RESULT=0
    BUSINESS_RESULT=0
    BUSINESS_STDOUT=''
    BUSINESS_STDERR=''
    EXPLICIT_CONFIG=0
    EXPLICIT_REMOTE_CONFIG=0
    FIXTURE_PROXY_ENV_NAME=''
    FIXTURE_PROXY_ENV_VALUE=''
    FIXTURE_NO_PROXY=''
    PROBE_FAILURE_PORT=''
    DEFAULT_REMOTE=origin
    FIXTURE_ROUTE_PRIORITY=direct
    FIXTURE_ARGS=( push origin main:main )
}
# 元数据调用只提供固定只读结果；真实业务 argv 逐项记录且绝不执行 Git。
fixture_real_git() {
    local argument='' command='' invocation=0
    for argument in "$@"; do
        case "$argument" in
            config|remote|symbolic-ref|ls-files|clone|fetch|pull|push|ls-remote|--version|status)
                command="$argument"
                break
                ;;
        esac
    done
    case "$command" in
        config)
            if (( EXPLICIT_CONFIG )) && [[ "$*" == *'--get-urlmatch http.proxy '* ]]; then
                (( EXPLICIT_CONFIG == 2 )) || print -r -- 'http://explicit.example.test:9999'
                return 0
            fi
            if (( EXPLICIT_REMOTE_CONFIG )) && [[ "$*" == *'.proxy'* ]]; then
                print -r -- 'http://explicit.example.test:9999'
                return 0
            fi
            return 1
            ;;
        remote)
            if [[ "$*" == *'get-url '* ]]; then
                print -r -- "$TARGET_FIXTURE"
            else
                print -r -- "$DEFAULT_REMOTE"
            fi
            return 0
            ;;
        symbolic-ref)
            print -r -- main
            return 0
            ;;
        ls-files)
            return 0
            ;;
        clone|fetch|pull|push|ls-remote|--version|status)
            if [[ "$command" == ls-remote && "$*" == *'ls-remote --get-url '* && " ${ORIGINAL_ARGS[*]} " != *' --get-url '* ]]; then
                print -r -- "$TARGET_FIXTURE"
                return 0
            fi
            if [[ -f "${CASE_DIR}/business-count" ]]; then
                invocation="$(<"${CASE_DIR}/business-count")"
            fi
            (( invocation++ ))
            print -r -- "$invocation" > "${CASE_DIR}/business-count"
            printf '%s\0' "$@" > "${CASE_DIR}/calls/${invocation}.argv"
            print -rn -- "$BUSINESS_STDOUT"
            print -rn -u2 -- "$BUSINESS_STDERR"
            return "$BUSINESS_RESULT"
            ;;
    esac
    print -u2 -r -- "unexpected fixture Git command: ${command}"
    return 99
}
# 从生产 main 进入，仅替换进程外边界；不替换策略、参数解析或目标解析函数。
invoke_case() {
    (
        unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY no_proxy NO_PROXY
        unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_CONFIG_SYSTEM GIT_CONFIG_GLOBAL
        export HOME="${CASE_DIR}/home" TMPDIR="${CASE_DIR}/tmp/"
        export JOBS_GIT_CONNECT_TIMEOUT=1 JOBS_GIT_PROBE_TIMEOUT=1
        if [[ "$FIXTURE_ROUTE_PRIORITY" == __default__ ]]; then
            unset JOBS_GIT_ROUTE_PRIORITY
        else
            export JOBS_GIT_ROUTE_PRIORITY="$FIXTURE_ROUTE_PRIORITY"
        fi
        [[ -n "$FIXTURE_PROXY_ENV_NAME" ]] && export "${FIXTURE_PROXY_ENV_NAME}=${FIXTURE_PROXY_ENV_VALUE}"
        [[ -n "$FIXTURE_NO_PROXY" ]] && export "NO_PROXY=${FIXTURE_NO_PROXY}"
        source "$ROUTE_LIBRARY" || exit 99
        # 用同一夹具接收策略内的只读解析和最终业务。
        real_git() {
            fixture_real_git "$@"
        }
        # 模拟完整直通入口的退出语义。
        exec_real_git() {
            fixture_real_git "$@"
            exit $?
        }
        # 记录实时系统代理读取，防止测试意外访问真实配置。
        system_proxy_snapshot() {
            print -r -- snapshot >> "${CASE_DIR}/snapshot-calls"
            print -r -- "$SYSTEM_SNAPSHOT"
        }
        # 记录探测次序及无凭据站点，返回指定连接结果。
        curl_head_status() {
            local proxy="${1-}"
            print -r -- "${proxy:-DIRECT}" >> "${CASE_DIR}/probes"
            print -r -- "$TARGET_ROOT" >> "${CASE_DIR}/probe-targets"
            if [[ -z "$proxy" ]]; then
                print -rn -- "$DIRECT_HTTP"
                return "$DIRECT_RESULT"
            fi
            if [[ -n "$PROBE_FAILURE_PORT" && "$proxy" == *":${PROBE_FAILURE_PORT}" ]]; then
                print -rn -- 000
                return 7
            fi
            print -rn -- "$PROXY_HTTP"
            return "$PROXY_RESULT"
        }
        main "${FIXTURE_ARGS[@]}"
    ) > "${CASE_DIR}/stdout" 2> "${CASE_DIR}/stderr"
    CASE_RESULT=$?
}
# 累计断言并输出不含凭据的失败定位。
assert_equal() {
    local actual="$1" expected="$2" label="$3"
    if [[ "$actual" == "$expected" ]]; then
        (( PASSED++ ))
        return 0
    fi
    (( FAILED++ ))
    print -u2 -r -- "FAIL ${label}: expected=[$expected] actual=[$actual]"
    return 1
}
# 缺少记录表示该外部动作没有发生。
read_fixture() {
    [[ -f "$1" ]] && print -rn -- "$(<"$1")"
    return 0
}
# 逐项比较 NUL 分隔的参数，保留空格和配置作用域。
assert_argv() {
    local file="$1" label="$2" item='' index=0
    shift 2
    local -a expected=( "$@" ) actual=()
    if [[ -f "$file" ]]; then
        while IFS= read -r -d $'\0' item; do
            actual+=( "$item" )
        done < "$file"
    fi
    assert_equal "${#actual}" "${#expected}" "${label}-argc" || return 1
    for (( index = 1; index <= ${#expected}; index++ )); do
        assert_equal "${actual[index]}" "${expected[index]}" "${label}-argument-${index}" || return 1
    done
    return 0
}
# 确认业务执行次数，元数据读取不计入业务。
assert_business_count() {
    assert_equal "$(read_fixture "${CASE_DIR}/business-count")" "$1" "$2"
}
# 五类 HTTP 业务都先探测直连，再只调用一次业务命令。
test_supported_commands() {
    local command=''
    for command in clone fetch pull ls-remote push; do
        reset_case "supported-${command}"
        case "$command" in
            clone) FIXTURE_ARGS=( clone "$TARGET_FIXTURE" '/tmp/destination with spaces' ) ;;
            ls-remote) FIXTURE_ARGS=( ls-remote "$TARGET_FIXTURE" HEAD ) ;;
            push) FIXTURE_ARGS=( push origin main:main ) ;;
            *) FIXTURE_ARGS=( "$command" origin main ) ;;
        esac
        invoke_case
        assert_equal "$CASE_RESULT" 0 "${command}-direct-exit"
        assert_equal "$(read_fixture "${CASE_DIR}/probes")" DIRECT "${command}-direct-probe"
        assert_equal "$(read_fixture "${CASE_DIR}/snapshot-calls")" '' "${command}-no-proxy-discovery"
        assert_business_count 1 "${command}-business-once"
        assert_argv "${CASE_DIR}/calls/1.argv" "${command}-original-argv" "${FIXTURE_ARGS[@]}"

        DIRECT_HTTP=000
        DIRECT_RESULT=7
        /bin/rm -f "${CASE_DIR}/business-count" "${CASE_DIR}/probes" "${CASE_DIR}/snapshot-calls"
        invoke_case
        assert_equal "$CASE_RESULT" 0 "${command}-fallback-exit"
        assert_equal "$(read_fixture "${CASE_DIR}/probes")" $'DIRECT\nhttp://127.0.0.1:8101' "${command}-fallback-probe-order"
        assert_business_count 1 "${command}-fallback-business-once"
        assert_argv "${CASE_DIR}/calls/1.argv" "${command}-fallback-argv" \
            -c http.https://git.example.test/.proxy=http://127.0.0.1:8101 "${FIXTURE_ARGS[@]}"
    done
}
# 不需要 HTTP 网络的查询、本地目标和 SSH 目标完全直通。
test_passthrough_boundaries() {
    local label=''
    local -a labels=( version status clone-help fetch-help pull-short-help push-help ls-remote-help get-url ssh local file-url unknown-option )
    for label in "${labels[@]}"; do
        reset_case "passthrough-${label}"
        case "$label" in
            version) FIXTURE_ARGS=( --version --build-options ) ;;
            status) FIXTURE_ARGS=( status --short ) ;;
            clone-help) FIXTURE_ARGS=( clone --help ) ;;
            fetch-help) FIXTURE_ARGS=( fetch --help ) ;;
            pull-short-help) FIXTURE_ARGS=( pull -h ) ;;
            push-help) FIXTURE_ARGS=( push --help ) ;;
            ls-remote-help) FIXTURE_ARGS=( ls-remote --help ) ;;
            get-url) FIXTURE_ARGS=( ls-remote --get-url origin ) ;;
            ssh) TARGET_FIXTURE='git@git.example.test:team/project.git'; FIXTURE_ARGS=( fetch origin ) ;;
            local) TARGET_FIXTURE='/tmp/local repo.git'; FIXTURE_ARGS=( clone "$TARGET_FIXTURE" '/tmp/destination with spaces' ) ;;
            file-url) TARGET_FIXTURE='file:///tmp/local.git'; FIXTURE_ARGS=( ls-remote "$TARGET_FIXTURE" ) ;;
            unknown-option) FIXTURE_ARGS=( push --future-option origin main ) ;;
        esac
        invoke_case
        assert_equal "$CASE_RESULT" 0 "${label}-exit"
        assert_equal "$(read_fixture "${CASE_DIR}/probes")" '' "${label}-no-probe"
        assert_equal "$(read_fixture "${CASE_DIR}/snapshot-calls")" '' "${label}-no-proxy-discovery"
        assert_business_count 1 "${label}-business-once"
        assert_argv "${CASE_DIR}/calls/1.argv" "${label}-argv" "${FIXTURE_ARGS[@]}"
    done
}
# DNS、连接和超时是换路条件；每次读取当下系统端口而不硬编码。
test_dynamic_proxy_fallback() {
    local code=0 port=0
    for code in 6 7 28; do
        reset_case "fallback-${code}"
        DIRECT_HTTP=000
        DIRECT_RESULT="$code"
        port=$(( 9000 + code ))
        SYSTEM_SNAPSHOT="$(proxy_snapshot "$port")"
        invoke_case
        assert_equal "$CASE_RESULT" 0 "fallback-${code}-exit"
        assert_equal "$(read_fixture "${CASE_DIR}/probes")" $'DIRECT\n'"http://127.0.0.1:${port}" "fallback-${code}-probe-order"
        assert_equal "$(read_fixture "${CASE_DIR}/snapshot-calls")" snapshot "fallback-${code}-live-snapshot"
        assert_business_count 1 "fallback-${code}-business-once"
        assert_argv "${CASE_DIR}/calls/1.argv" "fallback-${code}-argv" \
            -c "http.https://git.example.test/.proxy=http://127.0.0.1:${port}" push origin main:main
    done
}
# SourceTree 前置参数、配置作用域、路径空格和 refspec 不被重排或丢失。
test_global_arguments_and_output() {
    reset_case global-arguments
    DIRECT_HTTP=000
    DIRECT_RESULT=7
    BUSINESS_RESULT=73
    BUSINESS_STDOUT=$'business stdout\nwithout-final-newline'
    BUSINESS_STDERR=$'business stderr\nwithout-final-newline'
    FIXTURE_ARGS=( --no-optional-locks -c color.diff=false -ccore.quotepath=false -C '/tmp/repo with spaces' --git-dir=.git --work-tree '/tmp/work tree' --exec-path=/usr/libexec/git-core --config-env=credential.helper=JOBS_TEST_CREDENTIAL push -v origin 'refs/heads/main:refs/heads/main' )
    invoke_case
    assert_equal "$CASE_RESULT" 73 proxy-business-exit-code
    assert_business_count 1 failed-business-not-replayed
    assert_argv "${CASE_DIR}/calls/1.argv" global-arguments \
        --no-optional-locks -c color.diff=false -ccore.quotepath=false -C '/tmp/repo with spaces' --git-dir=.git --work-tree '/tmp/work tree' --exec-path=/usr/libexec/git-core --config-env=credential.helper=JOBS_TEST_CREDENTIAL \
        -c http.https://git.example.test/.proxy=http://127.0.0.1:8101 push -v origin 'refs/heads/main:refs/heads/main'
    assert_equal "$(read_fixture "${CASE_DIR}/stdout")" "$BUSINESS_STDOUT" business-stdout
    assert_equal "$([[ "$(read_fixture "${CASE_DIR}/stderr")" == *"$BUSINESS_STDERR" ]] && print yes || print no)" yes business-stderr-preserved
}
# 代理关闭时直连仍正常；两路都不通时不启动一次已知会阻塞的业务请求。
test_unavailable_routes() {
    reset_case proxy-disabled-direct-success
    SYSTEM_SNAPSHOT='<dictionary> {}'
    invoke_case
    assert_equal "$CASE_RESULT" 0 disabled-proxy-direct-success
    assert_business_count 1 disabled-proxy-business-once
    assert_equal "$(read_fixture "${CASE_DIR}/snapshot-calls")" '' disabled-proxy-not-needed
    reset_case dead-proxy-direct-success
    PROXY_RESULT=7
    PROXY_HTTP=000
    invoke_case
    assert_equal "$CASE_RESULT" 0 dead-proxy-direct-success
    assert_equal "$(read_fixture "${CASE_DIR}/probes")" DIRECT dead-proxy-not-needed
    assert_business_count 1 dead-proxy-direct-once
    reset_case no-route-no-proxy
    DIRECT_RESULT=28
    DIRECT_HTTP=000
    SYSTEM_SNAPSHOT='<dictionary> {}'
    invoke_case
    assert_equal "$CASE_RESULT" 128 no-route-exit
    assert_business_count '' no-route-business-not-started
    assert_equal "$(read_fixture "${CASE_DIR}/probes")" DIRECT no-route-single-probe
    reset_case no-route-dead-proxy
    DIRECT_RESULT=7
    DIRECT_HTTP=000
    PROXY_RESULT=7
    PROXY_HTTP=000
    invoke_case
    assert_equal "$CASE_RESULT" 128 dead-proxy-exit
    assert_business_count '' dead-proxy-business-not-started
    assert_equal "$(read_fixture "${CASE_DIR}/probes")" $'DIRECT\nhttp://127.0.0.1:8101' dead-proxy-deduplicated
}
# 已收到 HTTP 响应和 TLS 错误都交由 Git 一次处理，不把认证或证书问题误判为路由。
test_http_and_tls_boundaries() {
    local code=0
    for code in 200 301 401 403 404 500; do
        reset_case "http-${code}"
        DIRECT_HTTP="$code"
        BUSINESS_RESULT=23
        invoke_case
        assert_equal "$CASE_RESULT" 23 "http-${code}-business-exit"
        assert_business_count 1 "http-${code}-business-once"
        assert_equal "$(read_fixture "${CASE_DIR}/probes")" DIRECT "http-${code}-no-fallback"
        assert_equal "$(read_fixture "${CASE_DIR}/snapshot-calls")" '' "http-${code}-no-discovery"
    done
    for code in 35 51 60; do
        reset_case "tls-${code}"
        DIRECT_HTTP=000
        DIRECT_RESULT="$code"
        BUSINESS_RESULT=128
        invoke_case
        assert_equal "$CASE_RESULT" 128 "tls-${code}-business-exit"
        assert_business_count 1 "tls-${code}-business-once"
        assert_equal "$(read_fixture "${CASE_DIR}/probes")" DIRECT "tls-${code}-no-fallback"
        assert_equal "$(read_fixture "${CASE_DIR}/snapshot-calls")" '' "tls-${code}-no-discovery"
    done
}
# 代理 TLS 差异交给该链路上的 Git 校验，407 不当作目标站点可达。
test_proxy_probe_boundaries() {
    local code=0
    for code in 35 51 60; do
        reset_case "proxy-tls-${code}"
        DIRECT_HTTP=000
        DIRECT_RESULT=7
        PROXY_HTTP=000
        PROXY_RESULT="$code"
        BUSINESS_RESULT=128
        SYSTEM_SNAPSHOT+=$'\nSOCKSEnable : 1\nSOCKSProxy : localhost\nSOCKSPort : 8102'
        invoke_case
        assert_equal "$CASE_RESULT" 128 "proxy-tls-${code}-git-result"
        assert_business_count 1 "proxy-tls-${code}-business-once"
        assert_equal "$(read_fixture "${CASE_DIR}/probes")" $'DIRECT\nhttp://127.0.0.1:8101' "proxy-tls-${code}-no-next-route"
        assert_argv "${CASE_DIR}/calls/1.argv" "proxy-tls-${code}-selected-argv" \
            -c http.https://git.example.test/.proxy=http://127.0.0.1:8101 push origin main:main
    done
    reset_case proxy-authentication
    DIRECT_HTTP=000
    DIRECT_RESULT=7
    PROXY_HTTP=407
    invoke_case
    assert_equal "$CASE_RESULT" 128 proxy-407-not-target-response
    assert_business_count '' proxy-407-business-not-started
    reset_case proxy-candidate-order
    DIRECT_HTTP=000
    DIRECT_RESULT=7
    PROBE_FAILURE_PORT=8101
    SYSTEM_SNAPSHOT+=$'\nSOCKSEnable : 1\nSOCKSProxy : localhost\nSOCKSPort : 8102'
    invoke_case
    assert_equal "$CASE_RESULT" 0 second-proxy-candidate-exit
    assert_business_count 1 second-proxy-candidate-business-once
    assert_equal "$(read_fixture "${CASE_DIR}/probes")" $'DIRECT\nhttp://127.0.0.1:8101\nsocks5h://localhost:8102' second-proxy-candidate-order
    assert_argv "${CASE_DIR}/calls/1.argv" second-proxy-candidate-argv \
        -c http.https://git.example.test/.proxy=socks5h://localhost:8102 push origin main:main
    reset_case lsremote-heads-short
    FIXTURE_ARGS=( ls-remote -h "$TARGET_FIXTURE" )
    invoke_case
    assert_equal "$CASE_RESULT" 0 lsremote-h-means-heads-exit
    assert_equal "$(read_fixture "${CASE_DIR}/probes")" DIRECT lsremote-h-means-heads-probe
    assert_business_count 1 lsremote-heads-business-once
}
# 明确代理（含显式空值）由调用者掌控，策略不覆盖该选择。
test_explicit_proxy_boundaries() {
    local label=''
    for label in config config-empty remote-config environment environment-empty; do
        reset_case "explicit-${label}"
        DIRECT_HTTP=000
        DIRECT_RESULT=7
        case "$label" in
            config) EXPLICIT_CONFIG=1; FIXTURE_ARGS=( -c http.proxy=http://explicit.example.test:9999 push origin main ) ;;
            config-empty) EXPLICIT_CONFIG=2; FIXTURE_ARGS=( -c http.proxy= push origin main ) ;;
            remote-config) EXPLICIT_REMOTE_CONFIG=1 ;;
            environment) FIXTURE_PROXY_ENV_NAME=https_proxy; FIXTURE_PROXY_ENV_VALUE='http://explicit.example.test:9999' ;;
            environment-empty) FIXTURE_PROXY_ENV_NAME=https_proxy ;;
        esac
        invoke_case
        assert_equal "$CASE_RESULT" 0 "explicit-${label}-exit"
        assert_business_count 1 "explicit-${label}-business-once"
        assert_equal "$(read_fixture "${CASE_DIR}/probes")" '' "explicit-${label}-no-probe"
        assert_equal "$(read_fixture "${CASE_DIR}/snapshot-calls")" '' "explicit-${label}-no-discovery"
        assert_argv "${CASE_DIR}/calls/1.argv" "explicit-${label}-original-argv" "${FIXTURE_ARGS[@]}"
    done
}
# NO_PROXY 及系统例外不能把旁路主机导向代理。
test_proxy_bypass() {
    reset_case no-proxy-boundary
    DIRECT_HTTP=000
    DIRECT_RESULT=7
    FIXTURE_NO_PROXY='.example.test'
    invoke_case
    assert_equal "$CASE_RESULT" 128 no-proxy-failed-direct-exit
    assert_equal "$(read_fixture "${CASE_DIR}/probes")" DIRECT no-proxy-no-proxy-probe
    assert_business_count '' no-proxy-business-not-started
    reset_case system-exception
    DIRECT_HTTP=000
    DIRECT_RESULT=7
    SYSTEM_SNAPSHOT+=$'\nExceptionsList : <array> {\n  0 : *.example.test\n}'
    invoke_case
    assert_equal "$CASE_RESULT" 128 system-exception-exit
    assert_equal "$(read_fixture "${CASE_DIR}/probes")" DIRECT system-exception-no-proxy-probe
    assert_business_count '' system-exception-business-not-started
    local index=0
    local -a labels=( ipv4-cidr ipv6-cidr simple-host )
    local -a rules=( '127.0/8' '::1/128' '' )
    local -a targets=( 'http://127.0.0.2/team.git' 'http://[::1]/team.git' 'https://intranet/team.git' )
    for (( index = 1; index <= ${#labels}; index++ )); do
        reset_case "bypass-${labels[index]}"
        DIRECT_HTTP=000
        DIRECT_RESULT=7
        TARGET_FIXTURE="${targets[index]}"
        SYSTEM_SNAPSHOT+=$'\nExceptionsList : <array> {\n  0 : '"${rules[index]}"$'\n}'
        [[ "${labels[index]}" != simple-host ]] || SYSTEM_SNAPSHOT+=$'\nExcludeSimpleHostnames : 1'
        invoke_case
        assert_equal "$CASE_RESULT" 128 "${labels[index]}-bypass-exit"
        assert_equal "$(read_fixture "${CASE_DIR}/probes")" DIRECT "${labels[index]}-no-proxy-probe"
        assert_business_count '' "${labels[index]}-business-not-started"
    done
}
# 去除 URL 凭据及路径再探测，审计仅包含经过校验的路由信息。
test_secret_boundaries() {
    reset_case secret-boundaries
    TARGET_FIXTURE='https://user:fixture-secret@git.example.test/private.git?token=query-secret'
    FIXTURE_ARGS=( clone "$TARGET_FIXTURE" '/tmp/private destination' )
    DIRECT_HTTP=000
    DIRECT_RESULT=7
    invoke_case
    assert_equal "$CASE_RESULT" 0 secret-route-success
    assert_business_count 1 secret-business-once
    assert_equal "$(read_fixture "${CASE_DIR}/probe-targets")" $'https://git.example.test/\nhttps://git.example.test/' secret-free-probe-root
    local leaked=no
    /usr/bin/grep -ERiq 'fixture-secret|query-secret|private.git|user:' "${CASE_DIR}/home" && leaked=yes
    assert_equal "$leaked" no secret-free-audit
    assert_equal "$(/usr/bin/stat -f '%Lp' "${CASE_DIR}/home/Library/Logs/JobsGitNetworkStrategy/push.log")" 600 private-audit-permission
    assert_equal "$(/usr/bin/stat -f '%Lp' "${CASE_DIR}/home/Library/Logs/JobsGitNetworkStrategy")" 700 private-audit-directory
}
# 系统代理优先时直达代理；不可用或 VPN 关闭才探测直连。
test_system_priority_routes() {
    reset_case default-system-priority
    FIXTURE_ROUTE_PRIORITY=__default__
    invoke_case
    assert_equal "$CASE_RESULT" 0 default-system-priority-exit
    assert_equal "$(read_fixture "${CASE_DIR}/probes")" http://127.0.0.1:8101 default-system-priority-no-direct-probe
    assert_equal "$(read_fixture "${CASE_DIR}/snapshot-calls")" snapshot default-system-priority-live-discovery
    assert_business_count 1 default-system-priority-business-once
    assert_argv "${CASE_DIR}/calls/1.argv" default-system-priority-argv \
        -c http.https://git.example.test/.proxy=http://127.0.0.1:8101 push origin main:main
    reset_case system-proxy-first
    FIXTURE_ROUTE_PRIORITY=system
    BUSINESS_RESULT=73
    invoke_case
    assert_equal "$CASE_RESULT" 73 system-proxy-business-exit
    assert_equal "$(read_fixture "${CASE_DIR}/probes")" http://127.0.0.1:8101 system-proxy-no-direct-probe
    assert_equal "$(read_fixture "${CASE_DIR}/snapshot-calls")" snapshot system-proxy-live-discovery
    assert_business_count 1 system-proxy-failure-not-replayed
    assert_argv "${CASE_DIR}/calls/1.argv" system-proxy-argv \
        -c http.https://git.example.test/.proxy=http://127.0.0.1:8101 push origin main:main
    reset_case system-dead-proxy-direct-success
    FIXTURE_ROUTE_PRIORITY=system
    PROXY_HTTP=000
    PROXY_RESULT=7
    invoke_case
    assert_equal "$CASE_RESULT" 0 system-dead-proxy-direct-exit
    assert_equal "$(read_fixture "${CASE_DIR}/probes")" $'http://127.0.0.1:8101\nDIRECT' system-dead-proxy-direct-order
    assert_business_count 1 system-dead-proxy-direct-once
    assert_argv "${CASE_DIR}/calls/1.argv" system-direct-original-argv "${FIXTURE_ARGS[@]}"
    reset_case system-vpn-closed
    FIXTURE_ROUTE_PRIORITY=system
    SYSTEM_SNAPSHOT='<dictionary> {}'
    invoke_case
    assert_equal "$CASE_RESULT" 0 system-vpn-closed-exit
    assert_equal "$(read_fixture "${CASE_DIR}/probes")" DIRECT system-vpn-closed-direct-only
    assert_business_count 1 system-vpn-closed-business-once
    reset_case system-both-routes-failed
    FIXTURE_ROUTE_PRIORITY=system
    DIRECT_HTTP=000
    DIRECT_RESULT=28
    PROXY_HTTP=000
    PROXY_RESULT=7
    invoke_case
    assert_equal "$CASE_RESULT" 128 system-both-routes-failed-exit
    assert_equal "$(read_fixture "${CASE_DIR}/probes")" $'http://127.0.0.1:8101\nDIRECT' system-both-routes-failed-order
    assert_business_count '' system-both-routes-no-business
    reset_case system-vpn-closed-direct-failed
    FIXTURE_ROUTE_PRIORITY=system
    DIRECT_HTTP=000
    DIRECT_RESULT=6
    SYSTEM_SNAPSHOT='<dictionary> {}'
    invoke_case
    assert_equal "$CASE_RESULT" 128 system-vpn-closed-direct-failed-exit
    assert_equal "$(read_fixture "${CASE_DIR}/probes")" DIRECT system-vpn-closed-failed-direct-only
    assert_business_count '' system-vpn-closed-failed-no-business
}
# 系统优先保持代理认证、TLS、明确代理与旁路的既有语义。
test_system_priority_boundaries() {
    local code=0
    reset_case system-proxy-407
    FIXTURE_ROUTE_PRIORITY=system
    PROXY_HTTP=407
    invoke_case
    assert_equal "$CASE_RESULT" 0 system-proxy-407-direct-exit
    assert_equal "$(read_fixture "${CASE_DIR}/probes")" $'http://127.0.0.1:8101\nDIRECT' system-proxy-407-direct-order
    assert_business_count 1 system-proxy-407-direct-once
    for code in 35 51 60; do
        reset_case "system-proxy-tls-${code}"
        FIXTURE_ROUTE_PRIORITY=system
        PROXY_HTTP=000
        PROXY_RESULT="$code"
        BUSINESS_RESULT=128
        invoke_case
        assert_equal "$CASE_RESULT" 128 "system-proxy-tls-${code}-git-exit"
        assert_equal "$(read_fixture "${CASE_DIR}/probes")" http://127.0.0.1:8101 "system-proxy-tls-${code}-no-direct"
        assert_business_count 1 "system-proxy-tls-${code}-business-once"
        assert_argv "${CASE_DIR}/calls/1.argv" "system-proxy-tls-${code}-argv" \
            -c http.https://git.example.test/.proxy=http://127.0.0.1:8101 push origin main:main
    done
    reset_case system-explicit-proxy
    FIXTURE_ROUTE_PRIORITY=system
    EXPLICIT_CONFIG=1
    invoke_case
    assert_equal "$CASE_RESULT" 0 system-explicit-proxy-exit
    assert_equal "$(read_fixture "${CASE_DIR}/probes")" '' system-explicit-proxy-no-probe
    assert_equal "$(read_fixture "${CASE_DIR}/snapshot-calls")" '' system-explicit-proxy-no-discovery
    assert_business_count 1 system-explicit-proxy-business-once
    reset_case system-no-proxy-rule
    FIXTURE_ROUTE_PRIORITY=system
    FIXTURE_NO_PROXY='.example.test'
    invoke_case
    assert_equal "$CASE_RESULT" 0 system-no-proxy-direct-exit
    assert_equal "$(read_fixture "${CASE_DIR}/probes")" DIRECT system-no-proxy-no-proxy-probe
    assert_business_count 1 system-no-proxy-business-once
    reset_case system-no-proxy-rule-direct-failed
    FIXTURE_ROUTE_PRIORITY=system
    FIXTURE_NO_PROXY='.example.test'
    DIRECT_HTTP=000
    DIRECT_RESULT=7
    invoke_case
    assert_equal "$CASE_RESULT" 128 system-no-proxy-failed-exit
    assert_equal "$(read_fixture "${CASE_DIR}/probes")" DIRECT system-no-proxy-failed-no-proxy-probe
    assert_business_count '' system-no-proxy-failed-no-business
}
# 打印离线边界；本次验证已获任务授权，运行中可随时 Ctrl+C。
show_route_intro() {
    print -r -- 'Jobs Git 动态链路离线验证：生产 main + 隔离 HOME；全部 Git / 网络外部边界由夹具替换。'
    print -r -- '运行策略：无交互完成离线用例；Ctrl+C 取消；用例记录仅存临时目录，退出时清理。'
}
# 输出汇总并传播失败状态。
finish_route_suite() {
    print -r -- "Jobs Git 动态链路离线验证：${PASSED} 项通过，${FAILED} 项失败。"
    (( FAILED == 0 ))
}
# 编排内置说明、隔离夹具和生产入口验证。
main() {
  show_route_intro # 先说明验证范围、取消方式和临时记录。
  prepare_route_suite # 定位生产源码并创建专属临时目录。
  test_supported_commands # 覆盖五类网络业务的直连和代理路径。
  test_passthrough_boundaries # 验证查询、帮助、SSH 和本地目标直接透传。
  test_dynamic_proxy_fallback # 验证 DNS、连接和超时失败后的实时换路。
  test_global_arguments_and_output # 验证 SourceTree 参数、输出和失败码保留。
  test_unavailable_routes # 验证关闭代理、死代理和两路均失败的快速退出。
  test_http_and_tls_boundaries # 验证认证和证书问题不会触发路由切换。
  test_proxy_probe_boundaries # 验证代理 TLS 差异、407 和失效候选的处理。
  test_explicit_proxy_boundaries # 验证显式代理和空值配置优先级。
  test_proxy_bypass # 验证系统例外及 NO_PROXY 的旁路边界。
  test_secret_boundaries # 验证探测和审计不泄露 URL 凭据。
  test_system_priority_routes # 验证系统代理优先及代理不可用时的直连回退。
  test_system_priority_boundaries # 验证系统优先下的认证、TLS、显式和旁路边界。
  finish_route_suite # 输出断言统计并保留失败退出码。
}

main "$@"
