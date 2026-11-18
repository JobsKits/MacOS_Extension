#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】update.command
# - 核心用途：按项更新 macOS 开发工具并核验结果，区分失败、跳过和部分完成。
# - 影响范围：所选工具、用户 Shell 配置、SDK 和包缓存。
# - Flutter 边界：只升级已配置的独立全局 SDK，未安装则跳过；项目 FVM SDK 保持原绑定。
# - 运行提示：显示内置自述后自动更新，不等待回车或逐项选择；可能要求一次系统密码，Ctrl+C 可取消。

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

# >>> Jobs list parent confirmation >>>
# 只读确认键；返回码20仅交给实际启动本功能的list父菜单。
jobs_list_confirm_start() {
  emulate -L zsh
  local jobs_list_key='' jobs_list_prefix='' jobs_list_direction=''
  [[ -t 0 ]] || return 130
  print -u2 -n -r -- "$(jobs_prompt_render '按回车继续；← 返回功能菜单；Esc / Ctrl+C 取消：')"
  while true; do
    IFS= read -rsk1 jobs_list_key || return 130
    case "$jobs_list_key" in
      $'\r'|$'\n') print -u2; return 0 ;;
      $'\e')
        jobs_list_prefix=''
        IFS= read -rsk1 -t 0.12 jobs_list_prefix || { print -u2; return 130; }
        case "$jobs_list_prefix" in
          '['|'O')
            jobs_list_direction=''
            IFS= read -rsk1 -t 0.12 jobs_list_direction || { print -u2; return 130; }
            [[ "$jobs_list_direction" != D ]] || { print -u2; return 20; }
            ;;
          *) print -u2; return 130 ;;
        esac
        ;;
      $'\003') print -u2; return 130 ;;
    esac
  done
}
# 独立启动保留原read参数；list来源的返回/取消立即结束子脚本而不执行业务。
jobs_list_intro_read() {
  if [[ "${JOBS_LIST_PARENT_MENU:-}" != list ]]; then
    builtin read "$@"
    return $?
  fi
  local jobs_list_confirm_status=0
  jobs_list_confirm_start || jobs_list_confirm_status=$?
  (( jobs_list_confirm_status == 0 )) || exit "$jobs_list_confirm_status"
}
# <<< Jobs list parent confirmation <<<



# ============================================================
# 【MacOS】update.command - macOS 开发环境升级维护
# ============================================================
# 原则：维护 【MacOS】install.command 安装的工具链；业务仓库更新由独立 Git 操作负责。
# 说明：
# 1. 适合 .command 双击运行，也可终端执行。
# 2. 启动后先显示内置自述，再自动执行全部适用更新项。
# 3. 不等待逐项或收尾输入；未完成项汇总后退出，需要重试时再运行 update。
# 4. 单项失败不阻断后续更新项；所选任务未全部完成时最终返回非零。
# 5. 不存在的工具不在 update 中静默安装，只提示回到 【MacOS】install.command 补装。
# ============================================================

# ---------- 基础路径 ----------
# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。

# >>> Jobs Homebrew install choice >>>
# 输出安装诊断，避免混入返回的命令路径。
# JOBS_INPUT_CHOICE_STYLE_BEGIN
# 只展示提示选项；不读取答案、不改变默认值、返回码或业务环境。
# URL仅供显示；纯文本日志传color=0。
jobs_url_format() {
  LC_ALL=en_US.UTF-8 /usr/bin/awk -v color="${1:-0}" -v lines="${2:-1}" '
    # URL 范围只在展示文本上识别；不会改写真实请求或输出数据。
    function urlInit() {
      urlPattern = "[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]<>\"" sprintf("%c", 39) esc "]+"
      urlPunctuationCount = split("，|。|；|：|！|？|、|（|）|【|】|《|》|「|」|『|』|“|”|‘|’", urlPunctuation, "\\|")
    }
    function urlCount(value, token, total, idx) {
      total = 0
      for (idx = 1; idx <= length(value); idx++) if (substr(value, idx, 1) == token) total++
      return total
    }
    function urlTrim(value, idx, at, last) {
      for (idx = 1; idx <= urlPunctuationCount; idx++) {
        at = index(value, urlPunctuation[idx])
        if (at) value = substr(value, 1, at - 1)
      }
      while (length(value)) {
        last = substr(value, length(value), 1)
        if (index(".,;:!?", last) > 0 || (last == ")" && urlCount(value, ")") > urlCount(value, "(")) ||
            (last == "]" && urlCount(value, "]") > urlCount(value, "[")) || (last == "}" && urlCount(value, "}") > urlCount(value, "{"))) {
          value = substr(value, 1, length(value) - 1)
        } else break
      }
      return value
    }
    function urlClean(value, preserve, output, token, start, size) {
      gsub(esc "\\][^" esc sprintf("%c", 7) "]*(" sprintf("%c", 7) "|" esc "\\\\)", "", value)
      output = ""
      while (match(value, esc "\\[[0-?]*[ -/]*[@-~]")) {
        start = RSTART; size = RLENGTH; token = substr(value, start, size)
        output = output substr(value, 1, start - 1)
        if (preserve && token ~ /m$/) output = output token
        value = substr(value, start + size)
      }
      return output value
    }
    # 题干分段前临时遮蔽地址，地址里的 Enter、/、?、= 不参与选项识别。
    function urlProtect(value, output, at, size, token, marker, number, original) {
      urlProtectedCount = 0; output = ""; original = value; number = 0
      while (match(value, urlPattern)) {
        at = RSTART; size = RLENGTH; token = urlTrim(substr(value, at, size))
        do { marker = sprintf("%c", 2) "U" ++number sprintf("%c", 3) } while (index(original, marker))
        urlProtected[++urlProtectedCount] = token; urlMarkers[urlProtectedCount] = marker
        output = output substr(value, 1, at - 1) marker
        value = substr(value, at + length(token))
      }
      return output value
    }
    function urlRestore(value, idx, token, at) {
      for (idx = urlProtectedCount; idx > 0; idx--) {
        token = urlMarkers[idx]
        while ((at = index(value, token))) value = substr(value, 1, at - 1) urlProtected[idx] substr(value, at + length(token))
      }
      return value
    }
    # 保存原 SGR 的有效序列；RGB 中的零值不能误认为整体复位。
    function urlTrack(tokens, token, code, idx, total, reset, fields) {
      while (match(tokens, esc "\\[[0-9;:]*m")) {
        token = substr(tokens, RSTART, RLENGTH)
        tokens = substr(tokens, RSTART + RLENGTH)
        code = substr(token, 3, length(token) - 3); reset = (code == "")
        total = split(code, fields, ";")
        for (idx = 1; idx <= total; idx++) {
          if (fields[idx] == "0") reset = 1
          if ((fields[idx] == "38" || fields[idx] == "48" || fields[idx] == "58") && idx < total) {
            if (fields[idx + 1] == "2") idx += 4
            else if (fields[idx + 1] == "5") idx += 2
          }
        }
        if (reset) urlActive = ""
        urlActive = urlActive token
      }
    }
    # 用可见字符位置映射原 SGR，URL 内已有样式也会重新覆为绿下划线。
    function urlRender(value, output, visible, rest, key, at, size, token, idx, offset, url, inURL) {
      value = urlClean(value, color)
      if (!color) return value
      for (key in urlStyles) delete urlStyles[key]
      for (key in urlStarts) delete urlStarts[key]
      for (key in urlEnds) delete urlEnds[key]
      visible = ""; rest = value
      while (match(rest, esc "\\[[0-9;:]*m")) {
        at = RSTART; size = RLENGTH; token = substr(rest, at, size)
        visible = visible substr(rest, 1, at - 1)
        urlStyles[length(visible) + 1] = urlStyles[length(visible) + 1] token
        rest = substr(rest, at + size)
      }
      visible = visible rest; rest = visible; offset = 0
      while (match(rest, urlPattern)) {
        at = RSTART; size = RLENGTH; url = urlTrim(substr(rest, at, size))
        urlStarts[offset + at] = 1; urlEnds[offset + at + length(url) - 1] = 1
        offset += at + length(url) - 1; rest = substr(visible, offset + 1)
      }
      output = ""; inURL = 0
      for (idx = 1; idx <= length(visible) + 1; idx++) {
        if (idx in urlStyles) {
          token = urlStyles[idx]; output = output token; urlTrack(token)
          if (inURL) output = output esc "[32;4m"
        }
        if (idx > length(visible)) break
        if (idx in urlStarts) { output = output esc "[32;4m"; inURL = 1 }
        output = output substr(visible, idx, 1)
        if (idx in urlEnds) { output = output esc "[0m" urlActive; inURL = 0 }
      }
      return output
    }
    BEGIN { esc = sprintf("%c", 27); first = 1; urlInit() }
    {
      if (lines == 2) {
        if (!first) printf "%s\n", urlRender(pending)
        pending = $0; first = 0
      } else {
        if (!lines && !first) printf "\n"
        printf "%s", urlRender($0)
        if (lines) printf "\n"
        first = 0
      }
    }
    END {
      if (lines == 2 && !first) {
        sub(sprintf("%c", 1) "$", "", pending)
        printf "%s", urlRender(pending)
      }
    }
  '
}
# URL仅供显示；纯文本日志传color=0。
jobs_url_stream() {
  local url_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then url_color=1; fi
  jobs_url_format "$url_color" "${1:-1}"
}
jobs_prompt_color_ready() {
  env | LC_ALL=C /usr/bin/grep -qiE '^(SOURCETREE|SOURCE_TREE)' && return 1
  [ -z "${NO_COLOR+x}" ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
    [ "${PLAIN_OUTPUT:-0}" != 1 ] && [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]
}
# 原生 awk 分段着色；任意/非空输入优先，括号内外沿用同一个选项。
jobs_prompt_format() {
  # 中文字符类按UTF-8字符处理，仅约束此awk进程，保留调用者locale。
  LC_ALL=en_US.UTF-8 /usr/bin/awk -v color="${1:-0}" -v lines="${2:-0}" -v keep="${3:-0}" -v question="${4:-0}" '
    # URL 范围只在展示文本上识别；不会改写真实请求或输出数据。
    function urlInit() {
      urlPattern = "[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]<>\"" sprintf("%c", 39) esc "]+"
      urlPunctuationCount = split("，|。|；|：|！|？|、|（|）|【|】|《|》|「|」|『|』|“|”|‘|’", urlPunctuation, "\\|")
    }
    function urlCount(value, token, total, idx) {
      total = 0
      for (idx = 1; idx <= length(value); idx++) if (substr(value, idx, 1) == token) total++
      return total
    }
    function urlTrim(value, idx, at, last) {
      for (idx = 1; idx <= urlPunctuationCount; idx++) {
        at = index(value, urlPunctuation[idx])
        if (at) value = substr(value, 1, at - 1)
      }
      while (length(value)) {
        last = substr(value, length(value), 1)
        if (index(".,;:!?", last) > 0 || (last == ")" && urlCount(value, ")") > urlCount(value, "(")) ||
            (last == "]" && urlCount(value, "]") > urlCount(value, "[")) || (last == "}" && urlCount(value, "}") > urlCount(value, "{"))) {
          value = substr(value, 1, length(value) - 1)
        } else break
      }
      return value
    }
    function urlClean(value, preserve, output, token, start, size) {
      gsub(esc "\\][^" esc sprintf("%c", 7) "]*(" sprintf("%c", 7) "|" esc "\\\\)", "", value)
      output = ""
      while (match(value, esc "\\[[0-?]*[ -/]*[@-~]")) {
        start = RSTART; size = RLENGTH; token = substr(value, start, size)
        output = output substr(value, 1, start - 1)
        if (preserve && token ~ /m$/) output = output token
        value = substr(value, start + size)
      }
      return output value
    }
    # 题干分段前临时遮蔽地址，地址里的 Enter、/、?、= 不参与选项识别。
    function urlProtect(value, output, at, size, token, marker, number, original) {
      urlProtectedCount = 0; output = ""; original = value; number = 0
      while (match(value, urlPattern)) {
        at = RSTART; size = RLENGTH; token = urlTrim(substr(value, at, size))
        do { marker = sprintf("%c", 2) "U" ++number sprintf("%c", 3) } while (index(original, marker))
        urlProtected[++urlProtectedCount] = token; urlMarkers[urlProtectedCount] = marker
        output = output substr(value, 1, at - 1) marker
        value = substr(value, at + length(token))
      }
      return output value
    }
    function urlRestore(value, idx, token, at) {
      for (idx = urlProtectedCount; idx > 0; idx--) {
        token = urlMarkers[idx]
        while ((at = index(value, token))) value = substr(value, 1, at - 1) urlProtected[idx] substr(value, at + length(token))
      }
      return value
    }
    # 保存原 SGR 的有效序列；RGB 中的零值不能误认为整体复位。
    function urlTrack(tokens, token, code, idx, total, reset, fields) {
      while (match(tokens, esc "\\[[0-9;:]*m")) {
        token = substr(tokens, RSTART, RLENGTH)
        tokens = substr(tokens, RSTART + RLENGTH)
        code = substr(token, 3, length(token) - 3); reset = (code == "")
        total = split(code, fields, ";")
        for (idx = 1; idx <= total; idx++) {
          if (fields[idx] == "0") reset = 1
          if ((fields[idx] == "38" || fields[idx] == "48" || fields[idx] == "58") && idx < total) {
            if (fields[idx + 1] == "2") idx += 4
            else if (fields[idx + 1] == "5") idx += 2
          }
        }
        if (reset) urlActive = ""
        urlActive = urlActive token
      }
    }
    # 用可见字符位置映射原 SGR，URL 内已有样式也会重新覆为绿下划线。
    function urlRender(value, output, visible, rest, key, at, size, token, idx, offset, url, inURL) {
      value = urlClean(value, color)
      if (!color) return value
      for (key in urlStyles) delete urlStyles[key]
      for (key in urlStarts) delete urlStarts[key]
      for (key in urlEnds) delete urlEnds[key]
      visible = ""; rest = value
      while (match(rest, esc "\\[[0-9;:]*m")) {
        at = RSTART; size = RLENGTH; token = substr(rest, at, size)
        visible = visible substr(rest, 1, at - 1)
        urlStyles[length(visible) + 1] = urlStyles[length(visible) + 1] token
        rest = substr(rest, at + size)
      }
      visible = visible rest; rest = visible; offset = 0
      while (match(rest, urlPattern)) {
        at = RSTART; size = RLENGTH; url = urlTrim(substr(rest, at, size))
        urlStarts[offset + at] = 1; urlEnds[offset + at + length(url) - 1] = 1
        offset += at + length(url) - 1; rest = substr(visible, offset + 1)
      }
      output = ""; inURL = 0
      for (idx = 1; idx <= length(visible) + 1; idx++) {
        if (idx in urlStyles) {
          token = urlStyles[idx]; output = output token; urlTrack(token)
          if (inURL) output = output esc "[32;4m"
        }
        if (idx > length(visible)) break
        if (idx in urlStarts) { output = output esc "[32;4m"; inURL = 1 }
        output = output substr(visible, idx, 1)
        if (idx in urlEnds) { output = output esc "[0m" urlActive; inURL = 0 }
      }
      return output
    }
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
    function segment(value, inherited, is_question, start, kind, prefix, body, red, green, connector, left, right, splitAt) {
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
          return segment(left, 0, is_question) connector segment(right, 31, 0)
        }
        if (red && green && red < green && match(value, /或[[:space:]]*(直接|仅|只需|只|按下|按)?(回车|回車)/)) {
          splitAt = RSTART
          return segment(substr(value, 1, splitAt - 1), 31, is_question) "或" segment(substr(value, splitAt + length("或")), 0, 0)
        }
        if (red) {
          kind = 31
          start = red
        } else if (green) {
          kind = 32
          start = green
        }
      }
      if (!color) return value
      if (!kind) return is_question && value !~ /^[[:space:]]*$/ ? esc "[1;36m" value esc "[0m" : value
      prefix = substr(value, 1, start - 1)
      body = substr(value, start)
      if (is_question && prefix !~ /^[[:space:]]*$/) prefix = esc "[1;36m" prefix esc "[0m"
      return prefix esc "[1;" kind "m" body esc "[0m"
    }
    function render(value, output, part, boundary, inherited, kind, consumed, depth, original, question_body) {
      original = value
      value = urlProtect(urlClean(value, 0))
      if (color && keep && !greenPosition(value) && value !~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) return urlRender(original)
      output = ""
      inherited = 0
      depth = 0
      question_body = question
      while (match(value, /[；;\/|，,、？?：:=＝（）()\[\]【】]/)) {
        part = substr(value, 1, RSTART - 1)
        boundary = substr(value, RSTART, RLENGTH)
        consumed = RSTART + RLENGTH
        output = output segment(part, inherited, question_body) boundary
        if (inherited || greenPosition(part) || part ~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) question_body = 0
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
      return urlRender(urlRestore(output segment(value, inherited, question_body) (question && color ? esc "[0m" : "")))
    }
    BEGIN { esc = sprintf("%c", 27); first = 1; urlInit() }
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
  printf "%s" "$1" | jobs_prompt_format "$jobs_prompt_color" 0 0 1
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

jobs_brew_note() {
  jobs_prompt_output print -u2 -r -- "ℹ $*"
}
# 验证候选能够执行；共享安装只读不代表未安装。
jobs_brew_candidate_ok() {
  local candidate="$1" prefix
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  HOMEBREW_NO_AUTO_UPDATE=1 "$candidate" --version >/dev/null 2>&1 || return 1
  prefix="$("$candidate" --prefix 2>/dev/null)" || return 1
  [[ "$prefix" == /* && -d "$prefix" ]]
}
# 发现既有健康安装，不以目录可写性决定是否重新安装。
jobs_brew_find() {
  local candidate
  local -a candidates
  candidates=("${JOBS_HOMEBREW_BIN:-}" "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew
    "${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}/bin/brew" "$HOME/.homebrew/bin/brew")
  for candidate in "${candidates[@]}"; do
    if jobs_brew_candidate_ok "$candidate"; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}
# 计算官方系统目录；实际支持范围和授权交由官方安装器处理。
jobs_brew_system_prefix() {
  case "$(/usr/bin/uname -m)" in
    arm64) print -r -- /opt/homebrew ;;
    *) print -r -- /usr/local ;;
  esac
}
# 缺失时强提示选择安装路径；YES 只表示选择系统目录，不验证密码或权限。
jobs_brew_choose_installation() {
  jobs_brew_note 'Homebrew 尚未就绪；update 不询问安装路径，请先运行安装入口补齐。'
  return 1
}
# 将官方系统安装器下载到临时文件后执行，失败不自动改装到用户目录。
# 共用原生依赖获取：jobs_brew_download_file。
jobs_brew_download_file() {
  local destination="$1" description="$2" download_url attempt download_result=1 http_code
  local retry_round=0 retry_delay=1 round_has_retryable=0
  local -a request_headers download_urls
  local -A blocked_urls
  shift 2
  download_urls=("$@")
  (( ${#download_urls} > 0 )) || { jobs_brew_note '没有已声明的官方获取地址。'; return 2; }
  while true; do
    (( retry_round += 1 ))
    round_has_retryable=0
    for download_url in "${download_urls[@]}"; do
      [[ -z "${blocked_urls[$download_url]:-}" ]] || continue
      request_headers=()
      if [[ "$download_url" == https://api.github.com/repos/Homebrew/install/contents/install.sh\?ref=HEAD ]]; then
        request_headers=(-H 'Accept: application/vnd.github.raw+json')
      fi
      for attempt in 1 2 3; do
        jobs_brew_note "下载${description}（第 $retry_round 轮，第 $attempt 次）：$download_url"
        download_result=0
        http_code="$(curl -q -fsSL --proto '=https' --proto-redir '=https' \
          --connect-timeout 10 --max-time 30 "${request_headers[@]}" \
          --write-out '%{http_code}' "$download_url" -o "$destination" \
          2> >(tee -a "${LOG_FILE:-/dev/null}" >&2))" || download_result=$?
        if (( download_result == 0 )); then
          return 0
        fi
        rm -f -- "$destination" || return 1
        jobs_brew_note "${description}下载失败：curl 退出码 $download_result，HTTP ${http_code:-未知}。"
        case "$download_result" in
          129|130|143) return "$download_result" ;;
          5|6|7|18|28|35|52|55|56) ;;
          22)
            if [[ "$http_code" != 408 && "$http_code" != 429 && "$http_code" != 5[0-9][0-9] ]]; then
              blocked_urls[$download_url]=1
              break
            fi
            ;;
          *) blocked_urls[$download_url]=1; break ;;
        esac
        if (( attempt < 3 )); then
          jobs_brew_note '临时连接失败，1 秒后重试同一官方地址；Ctrl+C 可取消。'
          sleep 1 || return $?
        fi
      done
      if [[ -z "${blocked_urls[$download_url]:-}" ]]; then
        round_has_retryable=1
      fi
      jobs_brew_note '当前地址尚未取得可用响应；如有下一已声明官方地址，将按原顺序尝试，安装目录不变。'
    done
    if (( round_has_retryable == 0 )); then
      jobs_brew_note "获取${description}遇到确定错误，停止；未执行安装。日志：${LOG_FILE:-终端输出}。"
      return "$download_result"
    fi
    jobs_brew_note "官方来源暂时不可用，${retry_delay} 秒后继续下一轮；不设总次数或总时长上限，按 Ctrl+C 取消。"
    sleep "$retry_delay" || return $?
    if (( retry_delay < 30 )); then
      retry_delay=$(( retry_delay * 2 ))
      (( retry_delay <= 30 )) || retry_delay=30
    fi
  done
}

# 共用原生依赖获取：jobs_brew_stop_acquisition_tree。
jobs_brew_stop_acquisition_tree() {
  local root="$1" child=""
  for child in $(/usr/bin/pgrep -P "$root" 2>/dev/null); do
    jobs_brew_stop_acquisition_tree "$child"
  done
  /bin/kill -TERM "$root" 2>/dev/null || true
  /bin/kill -KILL "$root" 2>/dev/null || true
}

# 共用原生依赖获取：jobs_brew_fetch_release。
jobs_brew_fetch_release() {
  setopt LOCAL_OPTIONS LOCAL_TRAPS NO_ERREXIT
  local git_bin="$1" release_tag="$2" stage="$3" target="${3}/brew"
  local attempt_log="${3}/git-fetch-attempt.log" history="${3}/git-fetch-history.log"
  local attempt=1 result=0 delay=1 task_pid="" interrupted=0 failure=""
  [[ "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' && "$stage" == /* &&
     "${stage:t}" == .jobs-homebrew.* && -d "$stage" && ! -L "$stage" && ! -e "$target" && ! -L "$target" ]] || {
    jobs_brew_note 'Homebrew 获取版本或私有暂存路径无效，未执行 Git 获取。'
    return 2
  }
  "$git_bin" init --quiet "$target" || { result=$?; jobs_brew_note "Homebrew 暂存仓初始化失败（$result）：$target"; return "$result"; }
  "$git_bin" -C "$target" remote add origin https://github.com/Homebrew/brew.git || return $?
  trap 'interrupted=130; [[ -z "$task_pid" ]] || jobs_brew_stop_acquisition_tree "$task_pid"' INT
  trap 'interrupted=143; [[ -z "$task_pid" ]] || jobs_brew_stop_acquisition_tree "$task_pid"' TERM
  trap 'interrupted=129; [[ -z "$task_pid" ]] || jobs_brew_stop_acquisition_tree "$task_pid"' HUP
  while true; do
    jobs_brew_note "获取 Homebrew 官方版本 $release_tag（第 $attempt 次）：https://github.com/Homebrew/brew.git → $target；失败自动重试，Ctrl+C 取消。"
    : > "$attempt_log" || return 1
    print -r -- "━━ Homebrew $release_tag：第 $attempt 次 ━━" >> "$history" || return 1
    (
      local -a acquisition_statuses
      LC_ALL=C GIT_TERMINAL_PROMPT=0 "$git_bin" -C "$target" -c color.ui=false \
        -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 fetch --progress --depth 1 origin "refs/tags/$release_tag" 2>&1 |
        jobs_prompt_tee "$history" | jobs_prompt_tee "${LOG_FILE:-/dev/null}" | jobs_prompt_tee "$attempt_log" >&2
      acquisition_statuses=("${pipestatus[@]}")
      (( acquisition_statuses[2] == 0 && acquisition_statuses[3] == 0 && acquisition_statuses[4] == 0 )) || exit 74
      exit "${acquisition_statuses[1]}"
    ) <&0 &
    task_pid=$!
    result=0
    wait "$task_pid" || result=$?
    task_pid=""
    (( interrupted == 0 )) || return "$interrupted"
    jobs_brew_note "Homebrew $release_tag 获取第 $attempt 次退出码：$result。"
    if (( result == 0 )); then
      "$git_bin" -C "$target" checkout --quiet --detach FETCH_HEAD || return $?
      return 0
    fi
    case "$result" in
      74) jobs_brew_note "Homebrew 获取日志写入失败，停止；请检查磁盘空间、路径和权限。"; return 74 ;;
      129|130|131|137|143|126|127) return "$result" ;;
    esac
    failure="$(/usr/bin/tail -c 65536 "$attempt_log")" || return 1
    if print -r -- "$failure" | /usr/bin/grep -Eqi \
      'Permission denied|Operation not permitted|No space left on device|Read-only file system|File exists|already exists and is not an empty directory|Bad CPU type|Exec format error|unknown option|unrecognized option|invalid argument|couldn.t find remote ref|Remote branch .* not found|repository .* not found|Authentication failed|could not read Username|terminal prompts disabled|HTTP[^[:cntrl:]]*(401|403|404)|returned error: (401|403|404)|SSL certificate problem|certificate verify failed|unable to get local issuer certificate'; then
      jobs_brew_note "Homebrew 官方版本获取遇到本地、认证、证书或版本确定错误（$result），已停止；请核对日志：${LOG_FILE:-$history}。"
      return "$result"
    fi
    jobs_brew_note "Homebrew 网络获取尚未完成，保留本轮已收对象，${delay} 秒后继续；不设总次数或总时长上限，Ctrl+C 取消。"
    sleep "$delay" &
    task_pid=$!
    wait "$task_pid" || { result=$?; (( interrupted == 0 )) || return "$interrupted"; return "$result"; }
    task_pid=""
    (( interrupted == 0 )) || return "$interrupted"
    (( attempt += 1 ))
    (( delay >= 30 )) || delay=$(( delay * 2 ))
    (( delay <= 30 )) || delay=30
  done
}

# 共用原生依赖获取：jobs_brew_stop_failed_install。
jobs_brew_stop_failed_install() {
  case "$1" in
    129|130|143) exit "$1" ;;
    *) exit 1 ;;
  esac
}

jobs_brew_install_system() {
  local installer system_prefix="$(jobs_brew_system_prefix)" installer_result=0
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方安装器。"; return 1; }
  installer="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-install.XXXXXX")" || return 1
  if jobs_brew_download_file "$installer" 'Homebrew 官方安装器' \
      https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh \
      'https://api.github.com/repos/Homebrew/install/contents/install.sh?ref=HEAD'; then
    if [[ ! -s "$installer" || "$(head -n 1 "$installer")" != '#!/bin/bash' ]] || ! /bin/bash -n "$installer"; then
      rm -f -- "$installer"
      jobs_brew_note '官方安装器响应为空或内容校验失败（可能是 HTML / JSON 错误页）；未执行安装。'
      return 1
    fi
  else
    installer_result=$?
    rm -f -- "$installer"
    jobs_brew_note "系统目录安装器下载失败（curl 退出码 $installer_result）；尚未执行安装，不自动切换安装路径。"
    return "$installer_result"
  fi
  /bin/bash "$installer" || installer_result=$?
  rm -- "$installer"
  if (( installer_result != 0 )); then
    jobs_brew_note "系统目录安装失败（退出码 $installer_result）；停止，不自动切换安装路径。"
    return "$installer_result"
  fi
  typeset -g JOBS_HOMEBREW_BIN="$system_prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "官方安装器结束后未找到健康 Homebrew：$JOBS_HOMEBREW_BIN"; return 1; }
}
# 克隆官方稳定版本到用户目录；不覆盖非空目录，不调用 sudo。
jobs_brew_install_user() {
  local prefix="${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}" stage release_tag git_bin release_result=0
  [[ "$prefix" == /* && "$prefix" != / && "$prefix" != *[[:space:]:]* ]] || {
    jobs_brew_note "Homebrew 用户前缀须为不含空白或冒号的绝对目录：$prefix"
    return 1
  }
  if [[ -L "$prefix" || ( -e "$prefix" && ! -d "$prefix" ) || ( -d "$prefix" && -n "$(ls -A "$prefix" 2>/dev/null)" ) ]]; then
    jobs_brew_note "用户安装目标非空或不是普通目录，不覆盖：$prefix"
    return 1
  fi
  git_bin="$(command -v git 2>/dev/null)"
  [[ -n "$git_bin" ]] && "$git_bin" --version >/dev/null 2>&1 || { jobs_brew_note "用户目录安装需要可用 Git；请先准备 Git / Command Line Tools。"; return 1; }
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方稳定版本。"; return 1; }
  export HOMEBREW_NO_SUDO=1
  mkdir -p "${prefix:h}" || return 1
  stage="$(mktemp -d "${prefix:h}/.jobs-homebrew.XXXXXX")" || return 1
  if jobs_brew_download_file "$stage/release.json" 'Homebrew 官方稳定版本' \
      https://api.github.com/repos/Homebrew/brew/releases/latest; then
    release_result=0
  else
    release_result=$?
    rm -r -- "$stage"
    jobs_brew_note "获取官方稳定版本已停止（退出码 $release_result），未执行安装。"
    return "$release_result"
  fi
  release_tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$stage/release.json" | head -n 1)"
  if [[ ! "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    rm -r -- "$stage"
    jobs_brew_note '官方版本响应无有效 tag，停止；不重试版本解析或执行安装。'
    return 1
  fi
  if jobs_brew_fetch_release "$git_bin" "$release_tag" "$stage"; then
    release_result=0
  else
    release_result=$?
    rm -r -- "$stage"
    jobs_brew_note "Homebrew 官方版本获取已停止（退出码 $release_result），未执行安装。"
    return "$release_result"
  fi
  if ! "$git_bin" -C "$stage/brew" checkout -b stable ||
     ! "$git_bin" -C "$stage/brew" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' ||
     ! mkdir -p "$stage/brew/Cellar" "$stage/brew/Caskroom" "$stage/brew/etc" "$stage/brew/var"; then
    rm -r -- "$stage"
    jobs_brew_note "Homebrew 用户目录初始化失败，停止安装。"
    return 1
  fi
  # 空目录也只在下载成功后移除，避免提前改动用户的目标目录。
  if [[ -d "$prefix" ]] && ! rmdir -- "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  if ! mv "$stage/brew" "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  rm -r -- "$stage"
  typeset -g JOBS_HOMEBREW_BIN="$prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "用户目录安装后复检失败：$prefix"; return 1; }
}
# 只更新本模块的 shellenv 配置块，并保留配置文件的符号链接和权限。
jobs_brew_save_shellenv() {
  local profile_file="$HOME/.zprofile" profile_stage shellenv_line current_shell="${SHELL:-/bin/zsh}"
  [[ "${current_shell##*/}" != bash ]] || profile_file="$HOME/.bash_profile"
  shellenv_line='eval "$('"${(q)JOBS_HOMEBREW_BIN}"' shellenv)"'
  profile_stage="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-profile.XXXXXX")" || return 1
  if [[ -e "$profile_file" || -L "$profile_file" ]]; then
    awk '
      $0 == "# >>> Jobs Homebrew shellenv >>>" { inside = 1; block = $0 ORS; next }
      inside {
        block = block $0 ORS
        if ($0 == "# <<< Jobs Homebrew shellenv <<<") { inside = 0; block = "" }
        next
      }
      { print }
      END { if (inside) printf "%s", block }
    ' "$profile_file" > "$profile_stage" || { rm -- "$profile_stage"; return 1; }
  fi
  {
    print -r -- '# >>> Jobs Homebrew shellenv >>>'
    print -rl -- "$shellenv_line" '# <<< Jobs Homebrew shellenv <<<'
  } >> "$profile_stage"
  if ! cmp -s "$profile_stage" "$profile_file"; then
    cat "$profile_stage" > "$profile_file" || { rm -- "$profile_stage"; jobs_brew_note "无法写入用户配置：$profile_file"; return 1; }
  fi
  rm -- "$profile_stage"
}
# 激活当前进程并验证 Ruby 命令层；只有新安装才持久化 shellenv。
jobs_brew_activate() {
  local brew_env
  brew_env="$("$JOBS_HOMEBREW_BIN" shellenv)" || return 1
  eval "$brew_env" || return 1
  typeset -g JOBS_HOMEBREW_PREFIX="$("$JOBS_HOMEBREW_BIN" --prefix)"
  export PATH="$JOBS_HOMEBREW_PREFIX/bin:$JOBS_HOMEBREW_PREFIX/sbin:$PATH"
  rehash
  HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" config >/dev/null || { jobs_brew_note "Homebrew 命令层复检失败，停止后续业务。"; return 1; }
  if [[ "${1:-}" == installed ]]; then
    if [[ "${JOBS_HOMEBREW_INSTALL_MODE:-}" == user && -z "${HOMEBREW_CASK_OPTS:-}" ]]; then
      export HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications"
    fi
    jobs_brew_save_shellenv || return 1
  fi
}
# 在原版安装位置复用或安装 Homebrew，安装失败必须终止外层业务。
jobs_brew_install_or_exit() {
  local installed=""
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    jobs_brew_note "演练：Homebrew 系统路径 $(jobs_brew_system_prefix)；用户路径 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}；未询问或执行安装。"
    return 0
  fi
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    jobs_brew_choose_installation || exit 1
    case "$JOBS_HOMEBREW_INSTALL_MODE" in
      system) jobs_brew_install_system || jobs_brew_stop_failed_install $? ;;
      user) jobs_brew_install_user || jobs_brew_stop_failed_install $? ;;
      *) jobs_brew_note "安装路径选择无效，停止。"; exit 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || exit 1
}
# <<< Jobs Homebrew install choice <<<
# >>> Jobs embedded Python runtime >>>
# 输出诊断，不污染函数返回的解释器路径。
_jobs_python_note() {
  jobs_prompt_output print -u2 -r -- "$*"
}
# 标识当前 zsh 进程及其子 shell，避免继承环境绕过确认。
_jobs_python_process_token() {
  print -r -- "$$:${ZSH_SUBSHELL:-0}"
}
# update 默认授权本轮维护；只读预检仍禁止安装或修复。
_jobs_python_has_authorization() {
  [[ "${DRY_RUN:-0}" != 1 && "${_JOBS_PYTHON_READONLY:-0}" != 1 ]] || return 1
  (( JOBS_UPDATE_TRUST_MODE != 1 )) || return 0
  [[ -t 0 && -t 2 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 && "${DRY_RUN:-0}" != 1 ]] || return 1
  [[ "${parameters[_JOBS_PYTHON_CONFIRMED_PROCESS]:-}" != *export* &&
     "${_JOBS_PYTHON_CONFIRMED_PROCESS:-}" == "$(_jobs_python_process_token)" ]]
}
# 记录调用方已完成的终端确认；非交互入口只允许后续只读检查。
jobs_python_mark_confirmed() {
  emulate -L zsh
  if [[ -t 0 && -t 2 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 && "${DRY_RUN:-0}" != 1 ]]; then
    typeset -g +x _JOBS_PYTHON_CONFIRMED_PROCESS="$(_jobs_python_process_token)"
  fi
  return 0
}
# 在业务自述之后确认本次 Homebrew 更新及 Python 环境准备。
jobs_python_confirm_prepare() {
  emulate -L zsh
  local answer=""
  _jobs_python_has_authorization && return 0
  _jobs_python_note "${1:-Python 环境预检：更新 Homebrew；Python 不满足业务版本时经确认安装或修复。}"
  if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 || "${DRY_RUN:-0}" == 1 ]]; then
    _jobs_python_note "✖ 环境准备需要终端确认；当前未更新或安装任何环境。"
    return 1
  fi
  print -u2 -n -r -- "$(jobs_prompt_render '➤ 按回车准备环境；任意非空输入（含空格）取消：')"
  if ! IFS= read -r answer || [[ -n "$answer" ]]; then
    _jobs_python_note '✖ 已取消环境准备。'
    return 1
  fi
  jobs_python_mark_confirmed
}
# 对缺失依赖和已有虚拟环境修复使用统一的必需动作确认。
_jobs_python_confirm_required() {
  emulate -L zsh
  local answer=""
  if ! _jobs_python_has_authorization; then
    _jobs_python_note "✖ $1；需要在终端确认后重试，未执行安装或修复。"
    return 1
  fi
  if (( JOBS_UPDATE_TRUST_MODE == 1 )); then
    _jobs_python_note "➤ 无人值守：$1"
    return 0
  fi
  print -u2 -n -r -- "$(jobs_prompt_render "➤ $1；直接回车执行，任意非空输入（含空格）取消：")"
  if ! IFS= read -r answer || [[ -n "$answer" ]]; then
    _jobs_python_note '✖ 已取消，停止当前流程。'
    return 1
  fi
}
# 校验版本参数，避免把调用参数作为公式或命令选项解释。
_jobs_python_validate_arguments() {
  emulate -L zsh
  local minimum="$1" formula="$2" maximum="${3:-}"
  if [[ ! "$minimum" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ||
        ( -n "$maximum" && ! "$maximum" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ) ||
        ! "$formula" =~ '^python(@[0-9]+\.[0-9]+)?$' ]]; then
    _jobs_python_note "✖ Python 版本或 Homebrew 公式参数无效：$minimum / $formula / $maximum"
    return 1
  fi
  if [[ -n "$maximum" ]] && ! _jobs_python_version_less "$minimum" "$maximum"; then
    _jobs_python_note '✖ Python 最低版本必须小于排他上限。'
    return 1
  fi
}
# 以数值逐段比较版本，不依赖任何 Python 运行时。
_jobs_python_version_less() {
  emulate -L zsh
  local -a left right
  local component left_value right_value
  left=("${(@s:.:)1}")
  right=("${(@s:.:)2}")
  for component in 1 2 3; do
    left_value=$((10#${left[$component]:-0}))
    right_value=$((10#${right[$component]:-0}))
    (( left_value < right_value )) && return 0
    (( left_value > right_value )) && return 1
  done
  return 1
}
# 验证本脚本内封装的 Homebrew 接口，不读取外部函数库。
_jobs_python_load_brew_helpers() {
  emulate -L zsh
  local helper
  for helper in jobs_brew_find jobs_brew_choose_installation jobs_brew_install_system jobs_brew_install_user jobs_brew_activate; do
    (( $+functions[$helper] )) || { _jobs_python_note "✖ 脚本内置 Homebrew 接口缺失：$helper"; return 1; }
  done
}
# 验证解释器版本、标准库与归属，返回可机器判断的状态码。
_jobs_python_probe() {
  emulate -L zsh
  local candidate="$1" minimum="$2" maximum="$3" tree="$4" mode="$5"
  [[ -x "$candidate" ]] || return 1
  PYTHONDONTWRITEBYTECODE=1 "$candidate" -c '
import sys
def version(value):
    return tuple((list(map(int, value.split("."))) + [0, 0, 0])[:3])
actual = tuple(sys.version_info[:3])
if actual < version(sys.argv[1]):
    sys.exit(2)
if sys.argv[2] and actual >= version(sys.argv[2]):
    sys.exit(5)
try:
    import venv
    from pathlib import Path
    if actual >= (3, 11, 0):
        import tomllib
except Exception as error:
    print("Python standard library unavailable: " + str(error), file=sys.stderr)
    sys.exit(3)
try:
    target = Path(sys.argv[3]).resolve()
    executable = Path(sys.executable).resolve()
    if sys.argv[4] == "venv":
        if Path(sys.prefix).resolve() != target or sys.prefix == sys.base_prefix:
            sys.exit(4)
    else:
        executable.relative_to(target)
except (ValueError, OSError):
    sys.exit(4)
print("JOBS_PYTHON_OK|" + ".".join(map(str, actual)) + "|" + str(executable))
' "$minimum" "$maximum" "$tree" "$mode"
}
# 验证公式路径属于当前 Homebrew Cellar，再寻找该公式内的健康解释器。
_jobs_python_find_formula_python() {
  emulate -L zsh
  local minimum="$1" formula="$2" maximum="${3:-}"
  local cellar_root formula_cellar formula_prefix candidate probe_result probe_code=1 version_suffix actual_formula python3_command link_target
  local -a candidates runtime_bins
  cellar_root="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" --cellar 2>/dev/null)" || return 1
  formula_cellar="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" --cellar "$formula" 2>/dev/null)" || return 1
  actual_formula="${formula_cellar:t}"
  [[ "$cellar_root" == /* && "$cellar_root" != / && "$formula_cellar" == /* &&
     "${formula_cellar:A}" == "${cellar_root:A}/$actual_formula" &&
     ( "$actual_formula" == "$formula" ||
       ( "$formula" == python && "$actual_formula" =~ '^python@[0-9]+\.[0-9]+$' ) ) ]] || {
    _jobs_python_note "✖ Homebrew 公式 Cellar 路径异常：$formula_cellar"
    return 4
  }
  formula_prefix="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" --prefix "$formula" 2>/dev/null)" || return 1
  if [[ "$formula_prefix" == /* && ! -e "$formula_prefix" && ! -L "$formula_prefix" ]]; then
    return 1
  fi
  if [[ -L "$formula_prefix" && ! -e "$formula_prefix" ]]; then
    link_target="$(/usr/bin/readlink "$formula_prefix")" || return 4
    [[ "$link_target" == /* ]] || link_target="${formula_prefix:h}/$link_target"
    if [[ "${link_target:a}" == "${formula_cellar:A}/"* ]]; then
      return 1
    fi
    _jobs_python_note "✖ 损坏的公式链接指向外部路径：$formula_prefix"
    return 4
  fi
  [[ "$formula_prefix" == /* && "${formula_prefix:A}" == "${formula_cellar:A}/"* && -d "$formula_prefix" ]] || {
    _jobs_python_note "✖ Homebrew 公式前缀不属于指定公式：$formula_prefix"
    return 4
  }
  version_suffix="${actual_formula#python@}"
  [[ "$actual_formula" != python ]] || version_suffix=3
  candidates=("$formula_prefix/libexec/bin/python3" "$formula_prefix/bin/python$version_suffix" "$formula_prefix/bin/python3")
  runtime_bins=()
  for candidate in "$formula_prefix/libexec/bin" "$formula_prefix/bin"; do
    if [[ -d "$candidate" && "${candidate:A}" == "${formula_prefix:A}/"* ]]; then
      runtime_bins+=("$candidate")
    fi
  done
  for candidate in "${candidates[@]}"; do
    [[ -x "$candidate" ]] || continue
    probe_code=0
    probe_result="$(_jobs_python_probe "$candidate" "$minimum" "$maximum" "${formula_cellar:A}" runtime 2>&1)" || probe_code=$?
    if (( probe_code == 0 )) && [[ "$probe_result" == JOBS_PYTHON_OK\|* ]]; then
      python3_command=""
      local runtime_bin
      for runtime_bin in "${runtime_bins[@]}"; do
        if [[ -x "$runtime_bin/python3" ]]; then
          python3_command="$runtime_bin/python3"
          break
        fi
      done
      if [[ -z "$python3_command" ]] ||
         ! _jobs_python_probe "$python3_command" "$minimum" "$maximum" "${formula_cellar:A}" runtime >/dev/null 2>&1; then
        _jobs_python_note "✖ 公式缺少健康的 python3 命令入口：$formula_prefix"
        return 3
      fi
      typeset -gx JOBS_PYTHON_BIN="$candidate"
      typeset -g +x _JOBS_PYTHON_SELECTED_PROCESS="$(_jobs_python_process_token)"
      typeset -g +x _JOBS_PYTHON_SELECTED_BIN="$candidate"
      typeset -g +x _JOBS_PYTHON_SELECTED_TREE="${formula_cellar:A}"
      export PATH="${(j.:.)runtime_bins}:$PATH"
      rehash
      _jobs_python_note "✔ 复用 Homebrew Python：$candidate（${${probe_result#*|}%%|*}）"
      return 0
    fi
    (( probe_code != 0 )) || probe_code=1
    [[ "$probe_code" != 2 && "$probe_code" != 5 ]] || break
  done
  return "$probe_code"
}
# 在当前进程一次更新 Homebrew；失败不进入 Python 安装或业务。
_jobs_python_update_brew_once() {
  emulate -L zsh
  local brew_key="${JOBS_HOMEBREW_BIN:A}" token="$(_jobs_python_process_token)"
  _jobs_python_has_authorization || return 1
  if [[ "${parameters[_JOBS_PYTHON_UPDATED_BREWS]:-}" != association* ||
        "${parameters[_JOBS_PYTHON_UPDATED_BREWS]:-}" == *export* ]]; then
    unset _JOBS_PYTHON_UPDATED_BREWS
    typeset -gA +x _JOBS_PYTHON_UPDATED_BREWS
  fi
  [[ "${_JOBS_PYTHON_UPDATED_BREWS[$brew_key]:-}" != "$token" ]] || return 0
  _jobs_python_note "ℹ 更新 Homebrew 本体及公式索引：$JOBS_HOMEBREW_BIN update"
  if ! jobs_update_run_brew_update "$JOBS_HOMEBREW_BIN"; then
    _jobs_python_note '✖ Homebrew 更新失败，停止 Python 准备；未升级其它公式。'
    return 1
  fi
  jobs_brew_activate || { _jobs_python_note '✖ Homebrew 更新后激活或健康复检失败。'; return 1; }
  _JOBS_PYTHON_UPDATED_BREWS[$brew_key]="$token"
}
# 全新 Mac 缺少 CLT 时只请求系统安装一次，完成对话框后由用户重新运行。
_jobs_python_require_clt_for_install() {
  emulate -L zsh
  local developer_directory git_command token="$(_jobs_python_process_token)"
  [[ "$(/usr/bin/uname -s)" == Darwin ]] || return 0
  developer_directory="$(/usr/bin/xcode-select -p 2>/dev/null)" || developer_directory=""
  git_command="$(command -v git 2>/dev/null)"
  if [[ -n "$developer_directory" && -d "$developer_directory" && -n "$git_command" ]] &&
     "$git_command" --version >/dev/null 2>&1; then
    return 0
  fi
  if [[ "${parameters[_JOBS_PYTHON_CLT_REQUESTED_PROCESS]:-}" != *export* &&
        "${_JOBS_PYTHON_CLT_REQUESTED_PROCESS:-}" == "$token" ]]; then
    _jobs_python_note '✖ 已请求 Command Line Tools 安装；请完成系统对话框后重新运行脚本。'
    return 1
  fi
  _jobs_python_confirm_required '缺少可用 Git / Command Line Tools，将打开 Apple 系统安装对话框' || return 1
  typeset -g +x _JOBS_PYTHON_CLT_REQUESTED_PROCESS="$token"
  if ! /usr/bin/xcode-select --install; then
    _jobs_python_note '✖ 无法发起 Command Line Tools 安装；请先在系统中安装或修复开发者工具。'
    return 1
  fi
  _jobs_python_note 'ℹ 已请求系统安装；请完成 Command Line Tools 对话框后重新运行，本次不继续安装 Homebrew。'
  return 1
}
# 准备必经的 Homebrew 通道，缺失时复用内置安装路径选择。
_jobs_python_prepare_brew() {
  emulate -L zsh
  local installed=""
  _jobs_python_load_brew_helpers || return 1
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    if (( JOBS_UPDATE_TRUST_MODE == 1 )); then
      _jobs_python_note '✖ 未找到健康 Homebrew，无法执行全量升级；请先运行 【MacOS】install.command 完成安装路径配置。'
      return 1
    fi
    if ! _jobs_python_has_authorization; then
      _jobs_python_note '✖ 缺少健康 Homebrew；请在终端确认环境准备，未执行安装。'
      return 1
    fi
    _jobs_python_require_clt_for_install || return 1
    jobs_brew_choose_installation || return 1
    case "${JOBS_HOMEBREW_INSTALL_MODE:-}" in
      system) jobs_brew_install_system || return $? ;;
      user) jobs_brew_install_user || return $? ;;
      *) _jobs_python_note '✖ Homebrew 安装路径选择无效，停止。'; return 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || { _jobs_python_note '✖ Homebrew 激活或健康检查失败。'; return 1; }
  if _jobs_python_has_authorization; then
    _jobs_python_update_brew_once || return 1
  else
    _jobs_python_note 'ℹ 当前未获得终端确认，仅只读检查已有 Homebrew / Python，不更新或安装。'
  fi
}
# 更新 Homebrew 后只处理业务指定的 Python 公式，并立即复检。
jobs_python_ensure() {
  emulate -L zsh
  local minimum="${1:-}" formula="${2:-python@3.13}" maximum="${3:-}"
  local probe_code=0 action=install installed_versions=""
  unset JOBS_PYTHON_BIN
  _jobs_python_validate_arguments "$minimum" "$formula" "$maximum" || return 1
  _jobs_python_prepare_brew || return 1
  _jobs_python_find_formula_python "$minimum" "$formula" "$maximum" || probe_code=$?
  (( probe_code != 0 )) || return 0
  if ! _jobs_python_has_authorization; then
    _jobs_python_note "✖ $formula 不满足 Python $minimum${maximum:+ 至小于 $maximum}；无交互确认，停止。"
    return 1
  fi
  if (( probe_code == 4 )); then
    _jobs_python_note '✖ Python 或公式路径归属异常，停止；不覆盖外部解释器。'
    return 1
  fi
  if (( probe_code == 5 )); then
    _jobs_python_note "✖ $formula 的 Python 版本高于业务允许范围（须小于 $maximum）；停止，不尝试无效升级。"
    return 1
  fi
  installed_versions="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" list --versions "$formula" 2>/dev/null)" || installed_versions=""
  if [[ -n "$installed_versions" ]]; then
    action=reinstall
    (( probe_code != 2 )) || action=upgrade
  fi
  _jobs_python_confirm_required "必需的 $formula 未就绪，执行 brew $action $formula" || return 1
  if ! jobs_update_run_brew_adaptive_cmd "准备 Python：brew $action $formula" plain "$JOBS_HOMEBREW_BIN" "$action" "$formula"; then
    _jobs_python_note "✖ brew $action $formula 失败；停止，不重复安装。"
    return 1
  fi
  jobs_brew_activate || return 1
  if ! _jobs_python_find_formula_python "$minimum" "$formula" "$maximum"; then
    _jobs_python_note "✖ $formula 安装或修复后仍不满足要求；停止下游业务。"
    return 1
  fi
}
# 拒绝空目录、根目录及符号链接路径，防止虚拟环境修复涉及其它目录。
_jobs_python_validate_venv_path() {
  emulate -L zsh
  local supplied="${1:-}" absolute
  [[ -n "$supplied" ]] || { _jobs_python_note '✖ 虚拟环境路径不能为空。'; return 1; }
  absolute="${supplied:a}"
  if [[ "$absolute" == / || "$absolute" == "${HOME:a}" || "$absolute" != "${absolute:A}" ||
        -L "$absolute" || ( -e "$absolute" && ! -d "$absolute" ) ]]; then
    _jobs_python_note "✖ 虚拟环境须为独立真实目录，拒绝危险路径：$supplied"
    return 1
  fi
  if [[ -d "$absolute" && ! -f "$absolute/pyvenv.cfg" && ! -e "$absolute/bin/python" &&
        ! -L "$absolute/bin/python" && "${absolute:t}" != .venv && "${absolute:t}" != venv ]]; then
    _jobs_python_note "✖ 目录不是可识别的虚拟环境，不移动源码或用户目录：$absolute"
    return 1
  fi
  print -r -- "$absolute"
}
# 复用健康虚拟环境；旧坏环境完整改名备份后重建，不删除原目录。
jobs_python_prepare_venv() {
  emulate -L zsh
  local supplied="${1:-}" minimum="${2:-}" maximum="${3:-}" environment candidate probe_result backup suffix=0
  _jobs_python_validate_arguments "$minimum" python "${maximum:-}" || return 1
  environment="$(_jobs_python_validate_venv_path "$supplied")" || return 1
  candidate="$environment/bin/python"
  if [[ -d "$environment" ]] &&
     probe_result="$(_jobs_python_probe "$candidate" "$minimum" "$maximum" "$environment" venv 2>&1)" &&
     [[ "$probe_result" == JOBS_PYTHON_OK\|* ]]; then
    _jobs_python_note "✔ 复用虚拟环境：$environment"
    return 0
  fi
  if ! _jobs_python_has_authorization; then
    _jobs_python_note "✖ 虚拟环境缺失或不健康，需要终端确认后准备：$environment"
    return 1
  fi
  if [[ -z "${JOBS_PYTHON_BIN:-}" || ! -x "$JOBS_PYTHON_BIN" ||
        "${parameters[_JOBS_PYTHON_SELECTED_PROCESS]:-}" == *export* ||
        "${parameters[_JOBS_PYTHON_SELECTED_BIN]:-}" == *export* ||
        "${parameters[_JOBS_PYTHON_SELECTED_TREE]:-}" == *export* ||
        "${_JOBS_PYTHON_SELECTED_PROCESS:-}" != "$(_jobs_python_process_token)" ||
        "${_JOBS_PYTHON_SELECTED_BIN:-}" != "$JOBS_PYTHON_BIN" ]]; then
    _jobs_python_note '✖ 尚未选定健康 Homebrew Python，请先调用 jobs_python_ensure。'
    return 1
  fi
  if ! _jobs_python_probe "$JOBS_PYTHON_BIN" "$minimum" "$maximum" "$_JOBS_PYTHON_SELECTED_TREE" runtime >/dev/null 2>&1; then
    _jobs_python_note '✖ 已选择的 Homebrew Python 不满足虚拟环境版本要求，停止。'
    return 1
  fi
  if [[ -d "$environment" ]]; then
    _jobs_python_confirm_required "修复旧或损坏的虚拟环境 $environment（完整改名备份）" || return 1
    backup="$environment.backup.$(/bin/date '+%Y%m%d-%H%M%S').$$"
    while [[ -e "$backup" || -L "$backup" ]]; do
      (( suffix += 1 ))
      backup="$environment.backup.$(/bin/date '+%Y%m%d-%H%M%S').$$.$suffix"
    done
    if ! mv -- "$environment" "$backup"; then
      _jobs_python_note "✖ 原虚拟环境备份失败，停止：$environment"
      return 1
    fi
    _jobs_python_note "ℹ 原虚拟环境已完整保留：$backup"
  fi
  if ! PYTHONDONTWRITEBYTECODE=1 "$JOBS_PYTHON_BIN" -m venv "$environment"; then
    _jobs_python_note "✖ 虚拟环境创建失败，停止；备份保持原状：${backup:-无旧环境}"
    return 1
  fi
  if ! probe_result="$(_jobs_python_probe "$candidate" "$minimum" "$maximum" "$environment" venv 2>&1)" ||
     [[ "$probe_result" != JOBS_PYTHON_OK\|* ]]; then
    _jobs_python_note "✖ 虚拟环境创建后复检失败，停止：$environment"
    return 1
  fi
  _jobs_python_note "✔ 虚拟环境已就绪：$environment"
}
# <<< Jobs embedded Python runtime <<<

# 编排本文件内嵌的环境自检，保留当前入口的确认和版本要求。
jobs_envupdate_python_preflight() {
  local _JOBS_PYTHON_READONLY=0
  case "${1:-interactive}" in
    confirmed) jobs_python_mark_confirmed ;;
    unattended)
      (( JOBS_UPDATE_TRUST_MODE == 1 )) || return 1
      ;;
    readonly) _JOBS_PYTHON_READONLY=1 ;;
    *)
      if [[ -t 0 && -t 2 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]]; then
        jobs_python_confirm_prepare || return 1
      fi
      ;;
  esac
  jobs_python_ensure 3.11 python@3.13
}

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
  ' | jobs_prompt_filter
}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
source "${SCRIPT_DIR:h}/_lib/【MacOS】FlutterSDK网络入口.zsh/【MacOS】FlutterSDK网络入口.zsh"
SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.log"
JOBS_UPDATE_TRUST_MODE=1
JOBS_UPDATE_SUDO_KEEPALIVE_PID=''
JOBS_UPDATE_LOG_READY=1
JOBS_UPDATE_ENTRY_READY=0
JOBS_UPDATE_ENTRY_EXIT_CODE=0
JOBS_UPDATE_COCOAPODS_BREW_UPDATED=0
JOBS_UPDATE_FAILURE_COUNT=0
JOBS_UPDATE_HEALTH_WARNING_COUNT=0
JOBS_UPDATE_SKIP_COUNT=0
JOBS_UPDATE_COMMAND_COUNT=0
JOBS_UPDATE_FAILED_STEPS=0
JOBS_UPDATE_PARTIAL_STEPS=0
JOBS_UPDATE_SKIPPED_STEPS=0
JOBS_UPDATE_SUCCEEDED_STEPS=0
typeset -a JOBS_UPDATE_FAILED_DESCRIPTIONS=()
typeset -a JOBS_UPDATE_RETRY_TITLES=()
typeset -a JOBS_UPDATE_RETRY_CALLBACKS=()
JOBS_UPDATE_RETRY_SKIP_COUNT=0
JOBS_UPDATE_RETRY_HEALTH_WARNING_COUNT=0
typeset -a JOBS_UPDATE_COMMAND_OUTPUT_FILES=()
readonly JOBS_UPDATE_NETWORK_PROBE_URL="https://formulae.brew.sh/api/formula.jws.json"
readonly JOBS_UPDATE_NETWORK_PROBE_BYTES=1048576
readonly JOBS_UPDATE_NETWORK_PROBE_TIMEOUT_SECONDS=8
readonly JOBS_UPDATE_MAX_LOW_SPEED_LIMIT_BPS=1
readonly JOBS_UPDATE_MIN_LOW_SPEED_LIMIT_BPS=1
readonly JOBS_UPDATE_FINAL_LOW_SPEED_LIMIT_BPS=1
readonly JOBS_UPDATE_LOW_SPEED_SECONDS=60
readonly JOBS_UPDATE_FINAL_LOW_SPEED_SECONDS=120
readonly JOBS_UPDATE_PROGRESS_INTERVAL_SECONDS=20
JOBS_UPDATE_NETWORK_READY=0
JOBS_UPDATE_PREFERRED_IP_FAMILY="ipv4"
JOBS_UPDATE_SECONDARY_IP_FAMILY="ipv6"
JOBS_UPDATE_IPV4_PROBE_SPEED=0
JOBS_UPDATE_IPV6_PROBE_SPEED=0
JOBS_UPDATE_ACTIVE_LOW_SPEED_LIMIT_BPS=0
JOBS_UPDATE_ACTIVE_LOW_SPEED_SECONDS=0
JOBS_UPDATE_BREW_CURLRC=""
JOBS_UPDATE_LAST_BREW_OUTPUT_FILE=""
JOBS_UPDATE_PROGRESS_MONITOR_PID=""
JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC=""
JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC_WAS_SET=0
typeset -A JOBS_UPDATE_BREW_UPDATE_RESULTS=()
JOBS_UPDATE_DEFER_BREW_FAILURE=0


# ---------- 工具清单：必须与 【MacOS】install.command 保持同源 ----------
readonly -a BREW_CASKS=(
  hammerspoon
  flutter
  trex
  vlc
  jdownloader
  codex-app
  codex
  github-store
  jtool2
  motrix
  onlyoffice
  pot
  qlcolorcode
  temurin@17
)

readonly -a BREW_FORMULAE=(
  agg
  asciinema
  caddy
  cloudflared
  git-lfs
  gh
  nushell
  rbenv
  ruby
  node
  jenv
  openjdk
  openjdk@17
  openjdk@21
  fvm
  pnpm
  python
  python3
  python-tk@3.14
  pyinstaller
  pyside
  cocoapods
  fastlane
  mysql
  hugo
  yt-dlp
  ffmpeg
  cmake
  graphviz
  sevenzip
  go-task
  uv
  fzf
  glow
  lazygit
  dufs
  git-filter-repo
  nginx
  radare2
)
# ---------- 彩色日志 ----------
# 判断终端是否允许彩色展示；日志文件始终保留纯文本。
jobs_update_color_enabled() {
  [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" &&
     "${PLAIN_OUTPUT:-0}" != 1 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]]
}
# 同步显示命令流并写入纯文本日志，可额外保存本次命令输出供结果核验。
jobs_update_log_stream() {
  local use_color=0 stream_log='' stream_output="${1:-}"
  jobs_update_color_enabled && use_color=1
  (( JOBS_UPDATE_LOG_READY == 0 )) || stream_log="$LOG_FILE"
  JOBS_UPDATE_STREAM_LOG_FILE="$stream_log" JOBS_UPDATE_STREAM_OUTPUT_FILE="$stream_output" \
    /usr/bin/awk -v use_color="$use_color" '
      BEGIN {
        esc = sprintf("%c", 27)
        log_file = ENVIRON["JOBS_UPDATE_STREAM_LOG_FILE"]
        output_file = ENVIRON["JOBS_UPDATE_STREAM_OUTPUT_FILE"]
        if (log_file != "") { printf "%s", "" >> log_file; fflush(log_file) }
        if (output_file != "") { printf "%s", "" >> output_file; fflush(output_file) }
      }
      {
        clean = $0
        gsub(esc "\\[[0-9;?]*[ -/]*[@-~]", "", clean)
        print (use_color ? $0 : clean)
        if (log_file != "") print clean >> log_file
        if (output_file != "") print clean >> output_file
        fflush()
      }
    '
}
# 统一处理展示颜色与日志落盘；确认前仅展示，不覆盖已有日志。
log() {
  printf '%b\n' "$1" | jobs_update_log_stream
}
# 按当前输出级别记录终端信息，并同步写入脚本日志。
color_echo()     { log "\033[1;32m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warm_echo()      { log "\033[1;33m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
err_echo()       { log "\033[1;31m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
gray_echo()      { log "\033[0;90m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
bold_echo()      { log "\033[1m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
underline_echo() { log "\033[4m$1\033[0m"; }
# ---------- 通用基础函数 ----------
print_divider() {
  gray_echo "------------------------------------------------------------------------"
}
# 封装 jobs_update_has 对应的独立处理逻辑。
jobs_update_has() {
  command -v "$1" >/dev/null 2>&1
}
# 打印 【MacOS】update.command 的参数说明。
jobs_update_show_usage() {
  cat <<'EOFUSAGE' | jobs_prompt_filter
用法：
  update
  【MacOS】update.command

默认自动执行全部适用更新项；终端与右键菜单使用同一策略。
启动时可能要求一次管理员密码，本轮保活，后续命令使用 sudo -n。
不等待自述确认、逐项选择或收尾重试；未完成项汇总后非零退出。
需要重新尝试时直接再运行 update；Ctrl+C 可取消本轮。

参数：
  -h, --help  显示本说明。
EOFUSAGE
}
# 解析 【MacOS】update.command 的运行参数。
jobs_update_parse_args() {
  local arg=""

  for arg in "$@"; do
    case "$arg" in
      -h|--help)
        jobs_update_show_usage
        return 2
        ;;
      *)
        error_echo "未知参数：${arg}"
        jobs_update_show_usage
        return 1
        ;;
    esac
  done
}
# 仅在本轮存活期间刷新已有授权；不保存密码或修改 sudoers。
jobs_update_start_sudo_keepalive() {
  [[ -z "$JOBS_UPDATE_SUDO_KEEPALIVE_PID" ]] || return 0
  local update_pid="$$"
  (
    while /bin/sleep 45; do
      kill -0 "$update_pid" 2>/dev/null || break
      sudo -n -v >/dev/null 2>&1 || break
    done
  ) </dev/null >/dev/null 2>&1 &
  JOBS_UPDATE_SUDO_KEEPALIVE_PID=$!
}
# 停止本轮保活及其 sleep 子进程，不撤销用户此前已有的 sudo 凭证。
jobs_update_stop_sudo_keepalive() {
  local keepalive_parent=''
  if [[ "$JOBS_UPDATE_SUDO_KEEPALIVE_PID" == <-> ]]; then
    keepalive_parent="$(/bin/ps -o ppid= -p "$JOBS_UPDATE_SUDO_KEEPALIVE_PID" 2>/dev/null | /usr/bin/tr -d ' ')"
    if [[ "$keepalive_parent" == "$$" ]]; then
      jobs_update_specs_terminate_tree "$JOBS_UPDATE_SUDO_KEEPALIVE_PID"
      wait "$JOBS_UPDATE_SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
  fi
  JOBS_UPDATE_SUDO_KEEPALIVE_PID=''
}
# 将必要的密码输入集中到终端启动阶段，后台与后续更新始终禁止密码交互。
jobs_update_prepare_unattended_mode() {
  if (( JOBS_UPDATE_TRUST_MODE != 1 )); then
    return 0
  fi

  echo ""
  warn_echo "默认低打扰模式：自动执行全部适用更新项，并为已知确认点自动输入 y。"
  warm_echo "管理员权限：终端启动时授权一次，本轮自动保活；后续命令统一使用 sudo -n。"
  gray_echo "安全边界：脚本不保存、不传递管理员密码，也不自动修改 sudoers。"
  if sudo -n -v >/dev/null 2>&1; then
    jobs_update_start_sudo_keepalive
  elif [[ -t 0 && -t 2 ]]; then
    note_echo '本轮将升级系统工具和不可写的全局包；请在启动阶段完成一次管理员授权，之后可离开。'
    if sudo -v; then
      jobs_update_start_sudo_keepalive
    else
      warn_echo '启动阶段未取得管理员授权；继续可执行更新，受限命令将明确报告未完成。'
    fi
  else
    warn_echo '后台未取得通用管理员授权；仍尝试精确命令授权，受限命令会明确报告未完成。'
  fi
}
# 展示当前更新项并自动执行，不读取键盘输入。
jobs_update_prompt_run() {
  local title="$1" detail="$2"
  echo ""
  highlight_echo "$title"
  gray_echo "$detail"
  note_echo '默认自动执行；按 Ctrl+C 可取消本轮。'
  return 0
}
# 登记最终失败；保留状态，避免上层继续执行时被 || true 吞掉。
jobs_update_record_failure() {
  local desc="$1" exit_code="${2:-1}"
  (( JOBS_UPDATE_FAILURE_COUNT += 1 ))
  JOBS_UPDATE_FAILED_DESCRIPTIONS+=("${desc}（${exit_code}）")
  return 0
}
# 登记明确跳过，让缺少环境或权限的项目不再显示更新完成。
jobs_update_record_skip() {
  (( JOBS_UPDATE_SKIP_COUNT += 1 ))
  warn_echo "已跳过：$1"
}
# 只识别明确失败行，避免把普通版本说明中的 error 一词当成错误。
jobs_update_output_has_failure() {
  /usr/bin/awk '
    BEGIN { esc = sprintf("%c", 27) }
    {
      gsub(esc "\\[[0-9;]*[A-Za-z]", "")
      if ($0 ~ /^[[:space:]]*([Ee][Rr][Rr][Oo][Rr]:|ERROR[[:space:]]*:|fatal:|curl: \\([1-9][0-9]*\\)|npm (ERR!|error)([[:space:]]|$)|No pubspec[.]yaml found[.]|SocketException:|ProcessException:)/ ||
          $0 ~ /未执行 Git 网络命令|There was an error updating|[Cc]ould not resolve host:|[Ff]ailed to connect to .* port [0-9]/ ||
          $0 ~ /^[[:space:]]*([Ff]ailed to download|[Dd]ownload failed:)/) failed = 1
    }
    END { exit !failed }
  ' "$1"
}
# 识别 sudo 自身的明确授权拒绝，保留真实的未完成原因。
jobs_update_output_is_sudo_denied() {
  /usr/bin/grep -Eqi '^sudo:.*(a password is required|a terminal is required|no tty present|authentication (is required|failure)|not in the sudoers|not allowed to (run sudo|execute)|may not run sudo)|^[Ss]orry, user .* is not allowed to execute' "$1"
}
# 统一核对退出码、落盘结果及第三方明确错误输出。
jobs_update_finish_command() {
  local desc="$1" exit_code="$2" output_file="$3" log_exit_code="${4:-0}" result_mode="${5:-plain}"
  if (( log_exit_code != 0 )); then
    warn_echo "${desc}：输出记录失败（exit code: ${log_exit_code}），不能确认本次结果。"
    (( exit_code == 0 )) && exit_code="$log_exit_code"
  fi
  if (( exit_code == 0 )) && jobs_update_output_has_failure "$output_file"; then
    exit_code=1
    warn_echo "${desc}：命令返回 0，但输出包含明确失败，按未完成处理。"
  fi
  if [[ "$result_mode" == sudo ]] && (( exit_code != 0 && log_exit_code == 0 )) && jobs_update_output_is_sudo_denied "$output_file"; then
    warn_echo "${desc}：缺少该命令的管理员授权。"
    warm_echo '请在终端重新运行 update，在启动阶段完成授权；后台任务须预先具备对应授权。'
  fi
  (( JOBS_UPDATE_COMMAND_COUNT += 1 ))
  /bin/rm -f -- "$output_file" "${output_file}.status"
  if (( exit_code == 0 )); then
    success_echo "$desc：完成"
  else
    jobs_update_record_failure "$desc" "$exit_code"
    warn_echo "$desc：失败（exit code: ${exit_code}）"
  fi
  return "$exit_code"
}
# 实时落盘但让被调 Shell 函数留在当前进程；花括号等待输出消费者写完。
jobs_update_execute_logged() {
  local desc="$1" input_mode="$2" output_file='' exit_code=0 log_exit_code=1
  local JOBS_UPDATE_COMMAND_LOG_ACTIVE=1
  shift 2
  output_file="$(mktemp "${TMPDIR:-/tmp}/jobs-update-command.XXXXXXXX")" || {
    jobs_update_record_failure "$desc（无法创建输出记录）" 1
    return 1
  }
  JOBS_UPDATE_COMMAND_OUTPUT_FILES+=("$output_file")
  if [[ "$input_mode" == yes ]]; then
    { "$@" <<< 'y'; exit_code=$?; } > >(jobs_update_log_stream "$output_file"; print -r -- "$?" > "${output_file}.status") 2>&1
  else
    { "$@" </dev/null; exit_code=$?; } > >(jobs_update_log_stream "$output_file"; print -r -- "$?" > "${output_file}.status") 2>&1
  fi
  if [[ -r "${output_file}.status" ]]; then
    IFS= read -r log_exit_code < "${output_file}.status" || log_exit_code=1
    [[ "$log_exit_code" == <-> ]] || log_exit_code=1
  fi
  jobs_update_finish_command "$desc" "$exit_code" "$output_file" "$log_exit_code" "$input_mode"
}
# 主流程退出或中断时回收本脚本创建的命令输出，不扫描其它临时文件。
jobs_update_cleanup_command_outputs() {
  local output_file=''
  for output_file in "${JOBS_UPDATE_COMMAND_OUTPUT_FILES[@]}"; do
    [[ "${output_file:t}" == jobs-update-command.* ]] || continue
    /bin/rm -f -- "$output_file" "${output_file}.status"
  done
  JOBS_UPDATE_COMMAND_OUTPUT_FILES=()
}
# 汇总当前步骤内的真实失败和跳过，同时允许继续执行后续项目。
jobs_update_run_step() {
  local title="$1"
  local failures_before="$JOBS_UPDATE_FAILURE_COUNT" skips_before="$JOBS_UPDATE_SKIP_COUNT"
  local commands_before="$JOBS_UPDATE_COMMAND_COUNT"
  shift

  echo ""
  highlight_echo "$title"
  print_divider

  "$@"
  local exit_code=$?

  if (( exit_code != 0 && JOBS_UPDATE_FAILURE_COUNT == failures_before && JOBS_UPDATE_SKIP_COUNT == skips_before )); then
    jobs_update_record_failure "$title" "$exit_code"
  fi
  if (( JOBS_UPDATE_FAILURE_COUNT > failures_before )); then
    (( JOBS_UPDATE_FAILED_STEPS += 1 ))
    warn_echo "$title：未完成（失败 $(( JOBS_UPDATE_FAILURE_COUNT - failures_before )) 项），继续后续更新项"
  elif (( JOBS_UPDATE_SKIP_COUNT > skips_before )); then
    if (( JOBS_UPDATE_COMMAND_COUNT > commands_before )); then
      (( JOBS_UPDATE_PARTIAL_STEPS += 1 ))
      warn_echo "$title：部分执行（跳过 $(( JOBS_UPDATE_SKIP_COUNT - skips_before )) 项）"
    else
      (( JOBS_UPDATE_SKIPPED_STEPS += 1 ))
      warn_echo "$title：已跳过"
    fi
  else
    (( JOBS_UPDATE_SUCCEEDED_STEPS += 1 ))
    success_echo "$title：完成"
  fi

  return 0
}
# 登记未完成的已选更新组；成功和纯跳过项不进入重试队列。
jobs_update_run_selected_step() {
  local title="$1" callback="$2"
  local failed_before="$JOBS_UPDATE_FAILED_STEPS" partial_before="$JOBS_UPDATE_PARTIAL_STEPS"
  local skips_before="$JOBS_UPDATE_SKIP_COUNT" health_before="$JOBS_UPDATE_HEALTH_WARNING_COUNT"
  jobs_update_run_step "$title" "$callback"
  if (( JOBS_UPDATE_FAILED_STEPS > failed_before || JOBS_UPDATE_PARTIAL_STEPS > partial_before )); then
    JOBS_UPDATE_RETRY_TITLES+=("$title")
    JOBS_UPDATE_RETRY_CALLBACKS+=("$callback")
    (( JOBS_UPDATE_RETRY_SKIP_COUNT += JOBS_UPDATE_SKIP_COUNT - skips_before ))
    (( JOBS_UPDATE_RETRY_HEALTH_WARNING_COUNT += JOBS_UPDATE_HEALTH_WARNING_COUNT - health_before ))
  fi
  return 0
}
# 结束本轮并保留未完成结果，避免收尾等待输入。
jobs_update_confirm_retry() {
  info_echo '本轮不等待重试确认；未完成结果已保留，需要重试时直接再运行 update。'
  return 1
}
# 每次确认只执行一轮未完成组，按最新结果汇总并保留历史日志。
jobs_update_retry_unfinished() {
  local ran_count="$1" retry_round=0 retry_index=0 brew_key=''
  local -a retry_titles retry_callbacks
  while (( ${#JOBS_UPDATE_RETRY_TITLES[@]} > 0 )); do
    info_echo "待重试更新组：${#JOBS_UPDATE_RETRY_TITLES[@]} 项。组内将重新检查并执行所需维护。"
    for (( retry_index = 1; retry_index <= ${#JOBS_UPDATE_RETRY_TITLES[@]}; retry_index++ )); do
      note_echo "${JOBS_UPDATE_RETRY_TITLES[$retry_index]}"
    done
    jobs_update_confirm_retry || break

    retry_titles=("${JOBS_UPDATE_RETRY_TITLES[@]}")
    retry_callbacks=("${JOBS_UPDATE_RETRY_CALLBACKS[@]}")
    JOBS_UPDATE_FAILURE_COUNT=0
    JOBS_UPDATE_FAILED_STEPS=0
    JOBS_UPDATE_PARTIAL_STEPS=0
    JOBS_UPDATE_FAILED_DESCRIPTIONS=()
    (( JOBS_UPDATE_SKIP_COUNT -= JOBS_UPDATE_RETRY_SKIP_COUNT ))
    (( JOBS_UPDATE_HEALTH_WARNING_COUNT -= JOBS_UPDATE_RETRY_HEALTH_WARNING_COUNT ))
    JOBS_UPDATE_RETRY_TITLES=()
    JOBS_UPDATE_RETRY_CALLBACKS=()
    JOBS_UPDATE_RETRY_SKIP_COUNT=0
    JOBS_UPDATE_RETRY_HEALTH_WARNING_COUNT=0
    for brew_key in "${(@k)JOBS_UPDATE_BREW_UPDATE_RESULTS}"; do
      if (( JOBS_UPDATE_BREW_UPDATE_RESULTS[$brew_key] != 0 )); then
        unset "JOBS_UPDATE_BREW_UPDATE_RESULTS[$brew_key]"
      fi
    done
    jobs_update_cleanup_network_strategy
    (( retry_round += 1 ))
    highlight_echo "开始第 ${retry_round} 轮重试：${#retry_titles[@]} 个未完成更新组。"
    for (( retry_index = 1; retry_index <= ${#retry_titles[@]}; retry_index++ )); do
      jobs_update_run_selected_step "${retry_titles[$retry_index]}" "${retry_callbacks[$retry_index]}"
    done
    jobs_update_print_summary "$ran_count"
  done
  (( JOBS_UPDATE_FAILURE_COUNT == 0 && JOBS_UPDATE_SKIP_COUNT == 0 ))
}
# 封装 jobs_update_run_cmd 对应的独立处理逻辑。
jobs_update_run_cmd() {
  local desc="$1"
  shift

  note_echo "$desc"
  debug_echo "执行命令：$*"

  jobs_update_execute_logged "$desc" plain "$@"
}
# 统一执行需要管理员权限的命令，确保无人值守时不会停在密码提示。
jobs_update_run_sudo_cmd() {
  local desc="$1"
  shift

  if (( JOBS_UPDATE_TRUST_MODE == 1 )); then
    note_echo "$desc（无人值守）"
    debug_echo "执行命令：sudo -n $*"
    jobs_update_execute_logged "$desc（无人值守）" sudo sudo -n "$@"
    return $?
  fi

  jobs_update_run_cmd "$desc" sudo "$@"
}
# npm 全局包可能遗留为 root 所有；仅在目标不可写时进入统一提权策略。
jobs_update_run_npm_global_cmd() {
  local desc="$1"
  local package_relative_path="$2"
  local npm_root=""
  local package_path=""
  shift 2

  npm_root="$(npm root -g 2>/dev/null || true)"
  package_path="${npm_root}/${package_relative_path}"

  if [[ -n "$npm_root" ]] && { { [[ -e "$package_path" ]] && [[ ! -w "$package_path" ]]; } || { [[ ! -e "$package_path" ]] && [[ ! -w "$npm_root" ]]; }; }; then
    warn_echo "npm 全局包目录当前用户不可写：${package_path}"
    jobs_update_run_sudo_cmd "$desc" npm "$@"
    return $?
  fi

  jobs_update_run_cmd "$desc" npm "$@"
}
# 封装 jobs_update_run_sh 对应的独立处理逻辑。
jobs_update_run_sh() {
  local desc="$1"
  local cmd="$2"

  jobs_update_run_cmd "$desc" /bin/zsh -c "$cmd"
}
# 对已知会询问 y/n 的命令定点输入 y，避免托管模式中途卡住。
jobs_update_run_cmd_with_yes() {
  local desc="$1"
  shift

  note_echo "$desc"
  debug_echo "执行命令：printf 'y\\n' | $*"

  jobs_update_execute_logged "$desc" yes "$@"
}
# 返回指定 IP 协议对应的 curl 参数。
jobs_update_ip_family_curl_flag() {
  case "$1" in
    ipv4) print -r -- "--ipv4" ;;
    ipv6) print -r -- "--ipv6" ;;
    *) return 1 ;;
  esac
}
# 使用小流量分段下载测量指定 IP 协议的实时速度。
jobs_update_measure_ip_family_speed() {
  local family="$1"
  local family_flag=""
  local range_end=$((JOBS_UPDATE_NETWORK_PROBE_BYTES - 1))
  local speed=""

  family_flag="$(jobs_update_ip_family_curl_flag "$family")" || {
    print -r -- "0"
    return 0
  }
  speed="$(/usr/bin/curl "$family_flag" \
    --location \
    --silent \
    --fail \
    --output /dev/null \
    --range "0-${range_end}" \
    --connect-timeout 5 \
    --max-time "$JOBS_UPDATE_NETWORK_PROBE_TIMEOUT_SECONDS" \
    --write-out '%{speed_download}' \
    "$JOBS_UPDATE_NETWORK_PROBE_URL" 2>/dev/null || true)"
  speed="${speed%%.*}"
  [[ "$speed" == <-> ]] || speed=0
  print -r -- "$speed"
}
# 把字节每秒转换成便于日志阅读的 KiB/s。
jobs_update_format_download_speed() {
  local speed="${1:-0}"

  if [[ "$speed" != <-> ]] || (( speed <= 0 )); then
    print -r -- "不可用"
    return 0
  fi
  print -r -- "$((speed / 1024)) KiB/s"
}
# 返回指定 IP 协议的测速结果。
jobs_update_probe_speed_for_family() {
  case "$1" in
    ipv4) print -r -- "$JOBS_UPDATE_IPV4_PROBE_SPEED" ;;
    ipv6) print -r -- "$JOBS_UPDATE_IPV6_PROBE_SPEED" ;;
    *) print -r -- "0" ;;
  esac
}
# 只检测接近停滞的传输；API 单点测速不能代表并发 bottle 的速度。
jobs_update_adaptive_low_speed_limit_for_family() {
  print -r -- "$JOBS_UPDATE_MIN_LOW_SPEED_LIMIT_BPS"
}
# 写入仅供本轮 update 使用的 Homebrew curl 配置。
jobs_update_write_brew_curlrc() {
  local family="$1"
  local guard_mode="${2:-adaptive}"
  local family_option=""
  local speed_limit=0
  local speed_seconds=0

  [[ -n "$JOBS_UPDATE_BREW_CURLRC" ]] || return 1
  family_option="$(jobs_update_ip_family_curl_flag "$family")" || return 1
  case "$guard_mode" in
    adaptive)
      speed_limit="$(jobs_update_adaptive_low_speed_limit_for_family "$family")"
      speed_seconds=$JOBS_UPDATE_LOW_SPEED_SECONDS
      ;;
    final)
      speed_limit=$JOBS_UPDATE_FINAL_LOW_SPEED_LIMIT_BPS
      speed_seconds=$JOBS_UPDATE_FINAL_LOW_SPEED_SECONDS
      ;;
    *)
      return 1
      ;;
  esac
  JOBS_UPDATE_ACTIVE_LOW_SPEED_LIMIT_BPS=$speed_limit
  JOBS_UPDATE_ACTIVE_LOW_SPEED_SECONDS=$speed_seconds

  {
    if (( JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC_WAS_SET == 1 )); then
      if [[ "$JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC" == /* && -f "$JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC" ]]; then
        print -r -- "config = \"${JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC}\""
      elif [[ -f "${HOME}/.curlrc" ]]; then
        print -r -- "config = \"${HOME}/.curlrc\""
      fi
    fi
    print -r -- "$family_option"
    print -r -- "--connect-timeout 10"
    print -r -- "--speed-limit ${speed_limit}"
    print -r -- "--speed-time ${speed_seconds}"
  } > "$JOBS_UPDATE_BREW_CURLRC"
}
# 选择探测速度更快的 IP 协议，并让后续 Homebrew 下载复用该选择。
jobs_update_select_preferred_ip_family() {
  JOBS_UPDATE_IPV4_PROBE_SPEED="$(jobs_update_measure_ip_family_speed ipv4)"
  JOBS_UPDATE_IPV6_PROBE_SPEED="$(jobs_update_measure_ip_family_speed ipv6)"

  info_echo "Homebrew 下载线路探测：IPv4=$(jobs_update_format_download_speed "$JOBS_UPDATE_IPV4_PROBE_SPEED")，IPv6=$(jobs_update_format_download_speed "$JOBS_UPDATE_IPV6_PROBE_SPEED")"
  if (( JOBS_UPDATE_IPV6_PROBE_SPEED > JOBS_UPDATE_IPV4_PROBE_SPEED )); then
    JOBS_UPDATE_PREFERRED_IP_FAMILY="ipv6"
    JOBS_UPDATE_SECONDARY_IP_FAMILY="ipv4"
  else
    JOBS_UPDATE_PREFERRED_IP_FAMILY="ipv4"
    JOBS_UPDATE_SECONDARY_IP_FAMILY="ipv6"
  fi

  if (( JOBS_UPDATE_IPV4_PROBE_SPEED == 0 && JOBS_UPDATE_IPV6_PROBE_SPEED == 0 )); then
    warn_echo "IPv4 / IPv6 探测均未获得有效速度，先从 IPv4 开始；正式下载失败后仍会自动切换。"
  else
    success_echo "Homebrew 下载首选线路：${JOBS_UPDATE_PREFERRED_IP_FAMILY}"
  fi
}
# 初始化整轮 update 共用的 Homebrew 自适应下载策略。
jobs_update_ensure_network_strategy() {
  if (( JOBS_UPDATE_NETWORK_READY == 1 )); then
    return 0
  fi
  if [[ ! -x /usr/bin/curl ]]; then
    warn_echo "未找到 /usr/bin/curl，Homebrew 下载将沿用默认网络策略。"
    return 1
  fi

  if (( ${+HOMEBREW_CURLRC} )); then
    JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC_WAS_SET=1
    JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC="$HOMEBREW_CURLRC"
  fi
  JOBS_UPDATE_BREW_CURLRC="$(mktemp -t jobs_update_homebrew_curlrc.XXXXXX)" || return 1
  jobs_update_select_preferred_ip_family
  jobs_update_write_brew_curlrc "$JOBS_UPDATE_PREFERRED_IP_FAMILY" adaptive || return 1
  export HOMEBREW_CURLRC="$JOBS_UPDATE_BREW_CURLRC"
  JOBS_UPDATE_NETWORK_READY=1
  note_echo "已启用本轮 Homebrew 下载策略：测速只决定 curl 协议顺序；仅在传输近乎停滞时超时，失败后有限重试。Git 拉取沿用已有网络策略。"
}
# 清理临时网络配置，并恢复用户原有的 Homebrew curl 设置。
jobs_update_cleanup_network_strategy() {
  jobs_update_cleanup_command_outputs
  if (( JOBS_UPDATE_NETWORK_READY != 1 )) && [[ -z "$JOBS_UPDATE_BREW_CURLRC" && -z "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" ]]; then
    return 0
  fi
  jobs_update_stop_brew_progress_monitor
  if [[ -n "$JOBS_UPDATE_BREW_CURLRC" && -f "$JOBS_UPDATE_BREW_CURLRC" ]]; then
    rm -f "$JOBS_UPDATE_BREW_CURLRC"
  fi
  if [[ -n "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" && -f "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" ]]; then
    rm -f "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"
  fi
  if (( JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC_WAS_SET == 1 )); then
    export HOMEBREW_CURLRC="$JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC"
  else
    unset HOMEBREW_CURLRC
  fi
  JOBS_UPDATE_NETWORK_READY=0
  JOBS_UPDATE_BREW_CURLRC=''
  JOBS_UPDATE_LAST_BREW_OUTPUT_FILE=''
  JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC=''
  JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC_WAS_SET=0
}
# 更新首选 IP 协议，并重写后续 Homebrew 下载使用的速度守卫。
jobs_update_prefer_ip_family() {
  local family="$1"

  JOBS_UPDATE_PREFERRED_IP_FAMILY="$family"
  if [[ "$family" == "ipv4" ]]; then
    JOBS_UPDATE_SECONDARY_IP_FAMILY="ipv6"
  else
    JOBS_UPDATE_SECONDARY_IP_FAMILY="ipv4"
  fi
  jobs_update_write_brew_curlrc "$family" adaptive
}
# 汇总 Homebrew 未完成下载缓存的当前字节数。
jobs_update_homebrew_incomplete_bytes() {
  local cache_dir="${HOMEBREW_CACHE:-${HOME}/Library/Caches/Homebrew}/downloads"
  local file=""
  local size=0
  local total=0

  [[ -d "$cache_dir" ]] || {
    print -r -- "0"
    return 0
  }
  while IFS= read -r -d '' file; do
    size="$(stat -f '%z' "$file" 2>/dev/null || print -r -- "0")"
    [[ "$size" == <-> ]] || size=0
    total=$((total + size))
  done < <(find "$cache_dir" -type f -name '*.incomplete' -print0 2>/dev/null)
  print -r -- "$total"
}
# 把字节数转换成便于进度日志阅读的大小。
jobs_update_format_download_bytes() {
  local bytes="${1:-0}"

  [[ "$bytes" == <-> ]] || bytes=0
  if (( bytes >= 1048576 )); then
    print -r -- "$((bytes / 1048576)) MiB"
  elif (( bytes >= 1024 )); then
    print -r -- "$((bytes / 1024)) KiB"
  else
    print -r -- "${bytes} B"
  fi
}
# 在 Homebrew 隐藏 curl 进度条时输出缓存增长心跳。
jobs_update_monitor_brew_progress() {
  local desc="$1"
  local family="$2"
  local previous_bytes=""
  local current_bytes=""
  local delta_bytes=0

  previous_bytes="$(jobs_update_homebrew_incomplete_bytes)"
  while true; do
    sleep "$JOBS_UPDATE_PROGRESS_INTERVAL_SECONDS"
    current_bytes="$(jobs_update_homebrew_incomplete_bytes)"
    if (( current_bytes > previous_bytes )); then
      delta_bytes=$((current_bytes - previous_bytes))
      info_echo "${desc}（curl ${family}）仍在执行：观察到缓存最近增加 $(jobs_update_format_download_bytes "$delta_bytes")，未完成缓存共 $(jobs_update_format_download_bytes "$current_bytes")；个别资源可能已失败，最终以命令结果为准。"
    else
      gray_echo "${desc}（${family}）仍在执行，暂未观察到下载缓存增长；若持续低于阈值将自动超时。"
    fi
    previous_bytes=$current_bytes
  done
}
# 启动单个 Homebrew 命令对应的进度心跳。
jobs_update_start_brew_progress_monitor() {
  jobs_update_stop_brew_progress_monitor
  jobs_update_monitor_brew_progress "$1" "$2" &
  JOBS_UPDATE_PROGRESS_MONITOR_PID=$!
}
# 停止当前 Homebrew 进度心跳并回收后台进程。
jobs_update_stop_brew_progress_monitor() {
  [[ -n "$JOBS_UPDATE_PROGRESS_MONITOR_PID" ]] || return 0
  jobs_update_specs_terminate_tree "$JOBS_UPDATE_PROGRESS_MONITOR_PID"
  wait "$JOBS_UPDATE_PROGRESS_MONITOR_PID" 2>/dev/null || true
  JOBS_UPDATE_PROGRESS_MONITOR_PID=""
}
# 判断 Homebrew 失败是否来自下载链路，以免对安装或权限错误盲目换线。
jobs_update_brew_failure_is_network_related() {
  [[ -n "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" && -f "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" ]] || return 1
  if grep -Eqi 'Permission denied|Authentication failed|SSL certificate problem|certificate verify failed|returned error: (401|403)|HTTP(/[0-9.]+)? (401|403)|Repository not found' "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"; then
    return 1
  fi
  grep -Eqi 'curl: \([0-9]+\)|Failed to download resource|Download failed|Could not resolve host|Failed to connect|Couldn.t connect|Connection timed out|Operation timed out|Operation too slow|SSL connect error|Recv failure|Send failure|HTTP/[0-9.]+ stream|unable to access|Fetching .+ failed|Could not read from remote repository|网络.*不可达|未执行 Git 网络命令' "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"
}
# 只识别 update 的系统锁冲突，不能把权限或其它安装错误当作网络重试。
jobs_update_brew_failure_is_update_locked() {
  [[ -f "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" ]] || return 1
  grep -Eqi 'Another .*brew update.*process is already running|lockf:.*already locked' "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"
}
# 等待现有 Homebrew update 释放系统锁；不删除锁文件，也不终止其它任务。
jobs_update_wait_brew_update_lock() {
  local argument='' brew_command='' action='' brew_prefix='' lock_file=''
  local timeout="${JOBS_UPDATE_BREW_LOCK_TIMEOUT_SECONDS:-120}" elapsed=0
  [[ "$timeout" == <-> ]] && (( timeout >= 1 && timeout <= 600 )) || timeout=120
  for argument in "$@"; do
    if [[ -n "$brew_command" ]]; then
      action="$argument"
      break
    fi
    [[ "${argument:t}" == brew ]] && brew_command="$argument"
  done
  [[ -n "$brew_command" && "$action" == update && -x /usr/bin/lockf ]] || return 1
  brew_prefix="$(HOMEBREW_NO_AUTO_UPDATE=1 "$brew_command" --prefix 2>/dev/null)" || return 1
  [[ "$brew_prefix" == /* && "$brew_prefix" != *$'\n'* ]] || return 1
  lock_file="$brew_prefix/var/homebrew/locks/update"
  warn_echo "检测到 Homebrew update 锁占用，最多等待 ${timeout} 秒；保留原任务和锁文件。"
  while true; do
    [[ ! -L "$lock_file" ]] || return 1
    [[ -e "$lock_file" ]] || return 0
    [[ -f "$lock_file" ]] || return 1
    if /usr/bin/lockf -k -s -t 0 "$lock_file" /usr/bin/true; then
      info_echo 'Homebrew update 系统锁已释放，重新执行本次命令。'
      return 0
    fi
    if (( elapsed >= timeout )); then
      warn_echo "Homebrew update 锁仍被占用，停止本次重试；未删除锁或终止原任务。"
      return 1
    fi
    sleep 1
    (( elapsed += 1 ))
  done
}
# 使用指定 IP 协议执行一次 Homebrew 下载命令。
jobs_update_run_brew_network_attempt() {
  local desc="$1"
  local confirmation_mode="$2"
  local family="$3"
  local guard_mode="$4"
  local retries=0
  local -a brew_env
  local -a attempt_status
  shift 4

  jobs_update_write_brew_curlrc "$family" "$guard_mode" || return 1
  [[ -n "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" ]] || return 1
  : > "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"
  note_echo "${desc}（curl ${family}，连续 ${JOBS_UPDATE_ACTIVE_LOW_SPEED_SECONDS} 秒低于 ${JOBS_UPDATE_ACTIVE_LOW_SPEED_LIMIT_BPS} B/s 时终止下载；Git 连接不受 IP 切换控制）"
  debug_echo "执行命令：HOMEBREW_CURLRC=<临时配置> HOMEBREW_CURL_RETRIES=${retries} $*"
  jobs_update_start_brew_progress_monitor "$desc" "$family"
  brew_env=(env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1
    HOMEBREW_CURLRC="$JOBS_UPDATE_BREW_CURLRC" HOMEBREW_CURL_RETRIES="$retries"
    HOMEBREW_CURL_SPEED_LIMIT="$JOBS_UPDATE_ACTIVE_LOW_SPEED_LIMIT_BPS"
    HOMEBREW_CURL_SPEED_TIME="$JOBS_UPDATE_ACTIVE_LOW_SPEED_SECONDS"
    GIT_HTTP_LOW_SPEED_LIMIT=1 GIT_HTTP_LOW_SPEED_TIME=60
    GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/usr/bin/false GCM_INTERACTIVE=never)
  local git_wrapper="${SCRIPT_DIR:h}/_lib/jobs_git_network_strategy/bin/git"
  local brew_argument='' brew_action='' found_brew=0
  for brew_argument in "$@"; do
    if (( found_brew == 1 )); then
      brew_action="$brew_argument"
      break
    fi
    [[ "${brew_argument:t}" == brew ]] && found_brew=1
  done
  if (( ! ${+HOMEBREW_GIT_PATH} )) && [[ -x "$git_wrapper" ]]; then
    brew_env+=("HOMEBREW_GIT_PATH=$git_wrapper")
    # update 的 Shell 入口可能优先选择系统 Git；显式复用其现有执行入口。
    if [[ "$brew_action" == update ]] && (( ! ${+GIT_EXECUTABLE} )); then
      brew_env+=("GIT_EXECUTABLE=$git_wrapper")
      info_echo "Homebrew update Git 复用 Jobs 网络入口：$git_wrapper；代理仅影响本次 Git 及子进程，退出即撤回，审计沿用 Jobs Git 日志。"
    fi
  fi

  if [[ "$confirmation_mode" == "yes" ]]; then
    printf 'y\n' | "${brew_env[@]}" "$@" 2>&1 | jobs_update_log_stream "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"
    attempt_status=("${pipestatus[@]}")
    local exit_code=${attempt_status[2]}
    if (( attempt_status[3] != 0 )); then
      exit_code=1
    fi
  else
    "${brew_env[@]}" "$@" </dev/null 2>&1 | jobs_update_log_stream "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"
    attempt_status=("${pipestatus[@]}")
    local exit_code=${attempt_status[1]}
    if (( attempt_status[2] != 0 )); then
      exit_code=1
    fi
  fi
  if (( exit_code == 0 )) && grep -Eqi '(^|[[:space:]])(Error:|fatal:)|Failed to download resource|Download failed|未执行 Git 网络命令' "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"; then
    exit_code=1
    warn_echo "${desc}：命令返回 0，但输出包含明确失败，按未完成处理。"
  fi
  jobs_update_stop_brew_progress_monitor

  if (( exit_code == 0 )); then
    success_echo "${desc}（${family}）：完成"
  else
    warn_echo "${desc}（${family}）：失败（exit code: ${exit_code}）"
  fi
  return $exit_code
}
# 锁冲突独立等待一次；网络换线不能解除其它进程持有的系统锁。
jobs_update_run_brew_waiting_attempt() {
  local desc="$1" confirmation_mode="$2" family="$3" guard_mode="$4" exit_code=0
  shift 4
  jobs_update_run_brew_network_attempt "$desc" "$confirmation_mode" "$family" "$guard_mode" "$@"
  exit_code=$?
  if (( exit_code != 0 )) && jobs_update_brew_failure_is_update_locked; then
    if jobs_update_wait_brew_update_lock "$@"; then
      jobs_update_run_brew_network_attempt "$desc" "$confirmation_mode" "$family" "$guard_mode" "$@"
      return $?
    fi
  fi
  return "$exit_code"
}
# 为所有 Homebrew 更新下载提供低速换线和有限重试。
jobs_update_run_brew_adaptive_cmd() {
  local desc="$1"
  local confirmation_mode="$2"
  local primary_family=""
  local secondary_family=""
  local exit_code=0
  shift 2
  (( JOBS_UPDATE_COMMAND_COUNT += 1 ))

  if ! jobs_update_ensure_network_strategy; then
    if [[ "$confirmation_mode" == "yes" ]]; then
      jobs_update_run_cmd_with_yes "$desc" "$@"
    else
      jobs_update_run_cmd "$desc" "$@"
    fi
    return $?
  fi
  if [[ -n "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" && -f "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" ]]; then
    rm -f "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"
  fi
  JOBS_UPDATE_LAST_BREW_OUTPUT_FILE="$(mktemp -t jobs_update_brew_output.XXXXXX)" || return 1
  primary_family="$JOBS_UPDATE_PREFERRED_IP_FAMILY"
  secondary_family="$JOBS_UPDATE_SECONDARY_IP_FAMILY"

  jobs_update_run_brew_waiting_attempt "$desc" "$confirmation_mode" "$primary_family" adaptive "$@"
  exit_code=$?
  if (( exit_code == 0 )); then
    jobs_update_prefer_ip_family "$primary_family"
    return 0
  fi
  if ! jobs_update_brew_failure_is_network_related; then
    (( JOBS_UPDATE_DEFER_BREW_FAILURE == 1 )) || jobs_update_record_failure "$desc" "$exit_code"
    return $exit_code
  fi

  warn_echo "Homebrew 下载或 Git 拉取失败；将 curl 切换到 ${secondary_family} 后重试，保留现有下载缓存。"
  jobs_update_run_brew_waiting_attempt "$desc" "$confirmation_mode" "$secondary_family" adaptive "$@"
  exit_code=$?
  if (( exit_code == 0 )); then
    jobs_update_prefer_ip_family "$secondary_family"
    return 0
  fi
  if ! jobs_update_brew_failure_is_network_related; then
    (( JOBS_UPDATE_DEFER_BREW_FAILURE == 1 )) || jobs_update_record_failure "$desc" "$exit_code"
    return $exit_code
  fi

  warn_echo "两轮均未完成；使用 curl ${primary_family} 做最后一次停滞时限更宽的尝试。不可达网络仍会失败，不表示 Git 线路已恢复。"
  jobs_update_run_brew_waiting_attempt "$desc" "$confirmation_mode" "$primary_family" final "$@"
  exit_code=$?
  jobs_update_prefer_ip_family "$primary_family"
  if (( exit_code != 0 && JOBS_UPDATE_DEFER_BREW_FAILURE != 1 )); then
    jobs_update_record_failure "$desc" "$exit_code"
  fi
  return $exit_code
}
# 执行 brew update，遇到 Homebrew API 下载失败时自动降级为本地 tap 更新。
jobs_update_run_brew_update() {
  local brew_bin="${1:-$(find_brew_bin)}"
  local JOBS_UPDATE_DEFER_BREW_FAILURE=1
  [[ -n "$brew_bin" ]] || return 1
  local brew_key="${brew_bin:A}"
  if [[ -n "${JOBS_UPDATE_BREW_UPDATE_RESULTS[$brew_key]:-}" ]]; then
    local previous_result="${JOBS_UPDATE_BREW_UPDATE_RESULTS[$brew_key]}"
    if (( previous_result == 0 )); then
      info_echo "复用本轮已成功更新的 Homebrew 索引：$brew_bin"
    else
      warn_echo "本轮 Homebrew 索引更新已失败，停止依赖该索引的升级；修复网络后重新运行：$brew_bin update"
    fi
    return "$previous_result"
  fi
  jobs_update_run_brew_adaptive_cmd "brew update（更新软件列表）" plain "$brew_bin" update
  local exit_code=$?

  if (( exit_code == 0 )); then
    JOBS_UPDATE_BREW_UPDATE_RESULTS[$brew_key]=0
    return 0
  fi

  if [[ -n "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" ]] && grep -Eq "formulae\\.brew\\.sh/api|Failed to download .*\\.jws\\.json" "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"; then
    warn_echo "brew update API 数据下载失败，将使用 HOMEBREW_NO_INSTALL_FROM_API=1 降级重试。"
    warm_echo "说明：该模式会跳过 formulae.brew.sh API JSON 下载，改用本地 tap 更新，通常更慢但更稳。"
    jobs_update_run_brew_adaptive_cmd "brew update（本地 tap 降级重试）" plain env HOMEBREW_NO_INSTALL_FROM_API=1 "$brew_bin" update
    exit_code=$?
  else
    warn_echo "brew update（更新软件列表）：失败（exit code: ${exit_code}）"
  fi

  JOBS_UPDATE_BREW_UPDATE_RESULTS[$brew_key]=$exit_code
  (( exit_code == 0 )) || jobs_update_record_failure "Homebrew 本体及公式索引更新" "$exit_code"
  return $exit_code
}
# 执行 brew upgrade，托管模式下自动确认 Homebrew 的 y/n 提示。
jobs_update_run_brew_upgrade() {
  if (( JOBS_UPDATE_TRUST_MODE == 1 )); then
    jobs_update_run_brew_adaptive_cmd "brew upgrade（升级已安装 formula）" yes brew upgrade
    return $?
  fi

  jobs_update_run_brew_adaptive_cmd "brew upgrade（升级已安装 formula）" plain brew upgrade
}
# 执行 brew cask 全局升级，托管模式下自动确认 Homebrew 的 y/n 提示。
jobs_update_run_brew_cask_upgrade() {
  if (( JOBS_UPDATE_TRUST_MODE == 1 )); then
    jobs_update_run_brew_adaptive_cmd "brew upgrade --cask（升级已安装 cask）" yes brew upgrade --cask
    return $?
  fi

  jobs_update_run_brew_adaptive_cmd "brew upgrade --cask（升级已安装 cask）" plain brew upgrade --cask
}
# 封装 append_once 对应的独立处理逻辑。
append_once() {
  local line="$1"
  local file="${2:-$HOME/.zshrc}"

  mkdir -p "$(dirname "$file")" || return $?
  touch "$file" || return $?

  if grep -Fqx "$line" "$file"; then
    return 0
  else
    local match_result=$?
    (( match_result == 1 )) || return "$match_result"
  fi

  print -r -- "" >> "$file" || return $?
  print -r -- "$line" >> "$file"
}
# 封装 append_comment_once 对应的独立处理逻辑。
append_comment_once() {
  local comment="$1"
  local file="$2"

  mkdir -p "$(dirname "$file")" || return $?
  touch "$file" || return $?

  if grep -Fqx "$comment" "$file"; then
    return 0
  else
    local match_result=$?
    (( match_result == 1 )) || return "$match_result"
  fi

  print -r -- "" >> "$file" || return $?
  print -r -- "$comment" >> "$file"
}
# 解析并返回后续流程需要的目标信息。
find_brew_bin() {
  jobs_brew_find
}
# 执行对应的环境配置或同步处理。
setup_brew_shellenv() {
  local brew_bin="$1"
  local shellenv_line="eval \"\$(${(q)brew_bin} shellenv)\"" shellenv_output=''

  if [[ ! -x "$brew_bin" ]]; then
    warn_echo "Homebrew 可执行文件不存在或不可执行：${brew_bin}"
    return 1
  fi
  shellenv_output="$("$brew_bin" shellenv)" || {
    jobs_update_record_failure "Homebrew shellenv：$brew_bin" 1
    return 1
  }
  eval "$shellenv_output" || {
    jobs_update_record_failure "激活 Homebrew shellenv：$brew_bin" 1
    return 1
  }

  local target_file
  for target_file in "${HOME}/.zprofile" "${HOME}/.zshrc"; do
    if ! append_comment_once "# Homebrew shellenv" "$target_file" ||
       ! append_once "$shellenv_line" "$target_file"; then
      jobs_update_record_failure "写入 Homebrew 环境配置：$target_file" 1
      warn_echo "Homebrew 环境配置写入失败：$target_file"
      return 1
    fi
    success_echo "已确认 Homebrew 环境变量配置：${target_file}"
  done

  hash -r 2>/dev/null || true
}
# 封装 require_brew_or_skip 对应的独立处理逻辑。
require_brew_or_skip() {
  local brew_bin=""

  if brew_bin="$(find_brew_bin)"; then
    setup_brew_shellenv "$brew_bin" || return $?
    return 0
  fi

  jobs_update_record_skip "未检测到 Homebrew，跳过当前更新项。请先运行 【MacOS】install.command 安装 Homebrew。"
  return 1
}
# 执行对应的环境配置或同步处理。
setup_fzf_shellenv() {
  if ! jobs_update_has brew; then
    jobs_update_record_skip '未检测到 Homebrew，无法准备 fzf Shell 配置。'
    return 0
  fi

  local fzf_base=""
  fzf_base="$(brew --prefix fzf 2>/dev/null)" || {
    jobs_update_record_failure '读取 fzf 安装位置' 1
    warn_echo '读取 fzf 安装位置失败，未写入 Shell 配置。'
    return 1
  }

  if [[ -n "$fzf_base" && -d "$fzf_base" ]]; then
    if ! append_comment_once "# fzf" "${HOME}/.zshrc" ||
       ! append_once '[ -f "$(brew --prefix)/opt/fzf/shell/key-bindings.zsh" ] && source "$(brew --prefix)/opt/fzf/shell/key-bindings.zsh"' "${HOME}/.zshrc" ||
       ! append_once '[ -f "$(brew --prefix)/opt/fzf/shell/completion.zsh" ] && source "$(brew --prefix)/opt/fzf/shell/completion.zsh"' "${HOME}/.zshrc"; then
      jobs_update_record_failure "写入 fzf Shell 配置：${HOME}/.zshrc" 1
      warn_echo "fzf Shell 配置写入失败：${HOME}/.zshrc"
      return 1
    fi
    success_echo "已确认 fzf shell 配置：${HOME}/.zshrc"
  else
    jobs_update_record_failure "检查 fzf 安装目录：${fzf_base}" 1
    warn_echo "fzf 安装目录不存在，未写入 Shell 配置：${fzf_base}"
    return 1
  fi
}
# 检查当前运行条件是否满足后续流程要求。
ensure_jenv_init() {
  if ! append_comment_once "# jenv" "${HOME}/.zshrc" ||
     ! append_once 'export PATH="$HOME/.jenv/bin:$PATH"' "${HOME}/.zshrc" ||
     ! append_once 'eval "$(jenv init -)"' "${HOME}/.zshrc"; then
    jobs_update_record_failure "写入 jenv 初始化配置：${HOME}/.zshrc" 1
    warn_echo "jenv 初始化配置写入失败：${HOME}/.zshrc"
    return 1
  fi
  success_echo "已确认 jenv 初始化配置：${HOME}/.zshrc"
}
# 检查当前运行条件是否满足后续流程要求。
ensure_rbenv_init() {
  if ! append_comment_once "# rbenv" "${HOME}/.zshrc" ||
     ! append_once 'eval "$(rbenv init - zsh)"' "${HOME}/.zshrc"; then
    jobs_update_record_failure "写入 rbenv 初始化配置：${HOME}/.zshrc" 1
    warn_echo "rbenv 初始化配置写入失败：${HOME}/.zshrc"
    return 1
  fi
  success_echo "已确认 rbenv 初始化配置：${HOME}/.zshrc"
}
# 封装 post_openjdk_hint 对应的独立处理逻辑。
post_openjdk_hint() {
  warm_echo "openjdk 更新完成后，如需让系统 java 指向 Homebrew openjdk，可按需执行："
  warm_echo '  sudo ln -sfn "$(brew --prefix)/opt/openjdk/libexec/openjdk.jdk" /Library/Java/JavaVirtualMachines/openjdk.jdk'
  warm_echo "如果使用 jenv 管理 Java，推荐执行："
  warm_echo '  jenv add "$(brew --prefix)/opt/openjdk/libexec/openjdk.jdk/Contents/Home"'
}
# 封装 jobs_update_source_nvm_if_needed 对应的独立处理逻辑。
jobs_update_source_nvm_if_needed() {
  if jobs_update_has nvm; then
    return 0
  fi

  local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
  if [[ -s "$nvm_dir/nvm.sh" ]]; then
    source "$nvm_dir/nvm.sh"
  fi
}
# 解析并返回后续流程需要的目标信息。
get_node_major_version() {
  if ! jobs_update_has node; then
    echo "0"
    return 0
  fi

  local version=""
  version="$(node --version 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
  [[ -n "$version" ]] && echo "$version" || echo "0"
}
# 检查当前运行条件是否满足后续流程要求。
ensure_node_for_opencli() {
  local major=""
  major="$(get_node_major_version)"

  if (( major >= 21 )); then
    success_echo "Node.js 版本满足 OpenCLI 要求：$(node --version)"
    return 0
  fi

  warn_echo "OpenCLI 需要 Node.js >= 21，当前版本：$(node --version 2>/dev/null || echo '未安装')"
  warn_echo "【MacOS】update.command 不会静默安装 Node，请先通过 Homebrew / nvm 升级 Node 后重试。"
  return 1
}
# 封装 jobs_update_find_external_command 对应的独立处理逻辑。
jobs_update_find_external_command() {
  local command_name="$1"
  local path_dir=""
  local candidate=""
  local candidate_real=""
  local script_real=""

  if [[ -n "${SCRIPT_PATH:-}" && -e "$SCRIPT_PATH" ]]; then
    script_real="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd -P)/$(basename "$SCRIPT_PATH")"
  fi

  for path_dir in ${(s.:.)PATH}; do
    [[ -n "$path_dir" ]] || continue
    candidate="$path_dir/$command_name"
    [[ -x "$candidate" ]] || continue

    candidate_real="$(cd "$(dirname "$candidate")" 2>/dev/null && pwd -P)/$(basename "$candidate")"
    [[ -n "$script_real" && "$candidate_real" == "$script_real" ]] && continue

    print -r -- "$candidate"
    return 0
  done

  return 1
}
# 从 doctor 的实际 SDK 位置解析目标，不把引导工具自己的 SDK 当作 Flutter SDK。
jobs_update_android_sdk_root() {
  local doctor_output="$1" sdk_root=''
  sdk_root="$(/usr/bin/sed -n 's/^[[:space:]•]*Android SDK at //p' "$doctor_output" | /usr/bin/head -n 1)"
  [[ -n "$sdk_root" ]] || sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
  if [[ "$sdk_root" != /* || "$sdk_root" == / || ! -d "$sdk_root" ]]; then
    warn_echo "无法确认 Flutter 实际 Android SDK 目录：$sdk_root。"
    return 1
  fi
  REPLY="${sdk_root:A}"
}
# 优先复用 Flutter 正在使用的 JDK；只在当前维护作用域内传给 SDK 工具。
jobs_update_android_java_home() {
  local doctor_output="$1" java_binary='' java_home='' brew_bin='' brew_prefix=''
  local -a candidates=()
  java_binary="$(/usr/bin/sed -n 's/^[[:space:]•]*Java binary at: //p' "$doctor_output" | /usr/bin/head -n 1)"
  [[ "$java_binary" != /* ]] || candidates+=("${java_binary:h:h}")
  candidates+=("${JAVA_HOME:-}" '/Applications/Android Studio.app/Contents/jbr/Contents/Home')
  for java_home in "${candidates[@]}"; do
    if [[ -n "$java_home" && -x "$java_home/bin/java" ]] && "$java_home/bin/java" -version >/dev/null 2>&1; then
      REPLY="${java_home:A}"
      return 0
    fi
  done
  candidates=()
  if [[ -x /usr/libexec/java_home ]]; then
    candidates+=("$(/usr/libexec/java_home 2>/dev/null || true)")
  fi
  if brew_bin="$(find_brew_bin 2>/dev/null)"; then
    brew_prefix="$("$brew_bin" --prefix openjdk 2>/dev/null || true)"
    [[ -z "$brew_prefix" ]] || candidates+=("$brew_prefix/libexec/openjdk.jdk/Contents/Home")
  fi
  for java_home in "${candidates[@]}"; do
    if [[ -n "$java_home" && -x "$java_home/bin/java" ]] && "$java_home/bin/java" -version >/dev/null 2>&1; then
      REPLY="${java_home:A}"
      return 0
    fi
  done
  warn_echo '未找到可用 JDK，无法准备 Android SDK 工具；请先修复 Android Studio JDK 或 Homebrew openjdk。'
  return 1
}
# 本地候选须符合 Flutter 的 latest / 数字开头版本目录；其它健康目录只作引导。
jobs_update_android_find_sdkmanager() {
  local sdk_root="$1" candidate='' probe_output='' version_directory='' search_scope="${2:-local}"
  local -a candidates=("$sdk_root/cmdline-tools/latest/bin/sdkmanager" "$sdk_root"/cmdline-tools/*/bin/sdkmanager(NOn))
  if [[ "$search_scope" == external ]]; then
    candidates+=("$(jobs_update_find_external_command sdkmanager 2>/dev/null || true)")
  fi
  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    if [[ "$search_scope" == local ]]; then
      version_directory="${${candidate:h}:h:t}"
      [[ "$version_directory" == latest || "$version_directory" == [0-9]* ]] || continue
    fi
    if probe_output="$("$candidate" --version 2>&1)" &&
       print -r -- "$probe_output" | /usr/bin/grep -Eq '^[0-9]+([.][0-9]+)*[[:space:]]*$'; then
      REPLY="$candidate"
      return 0
    fi
    warn_echo "sdkmanager 健康检查失败：$candidate。"
    [[ -z "$probe_output" ]] || print -r -- "$probe_output" | jobs_update_log_stream
  done
  return 1
}
# 只补 Flutter 所用 SDK 缺失的命令行工具；引导安装和目标修复各最多一次。
jobs_update_android_prepare_sdkmanager() {
  local sdk_root="$1" manager='' brew_bin='' brew_prefix='' action=install
  if jobs_update_android_find_sdkmanager "$sdk_root"; then
    return 0
  fi
  [[ -w "$sdk_root" ]] || { warn_echo "Android SDK 目录不可写：$sdk_root；未修改目录权限。"; return 1; }
  if jobs_update_android_find_sdkmanager "$sdk_root" external; then
    manager="$REPLY"
  else
    brew_bin="$(find_brew_bin 2>/dev/null)" || {
      warn_echo '缺少可用 sdkmanager 和 Homebrew，无法补齐 Android Command-line Tools。'
      return 1
    }
    brew_prefix="$("$brew_bin" --prefix 2>/dev/null)" || return 1
    if jobs_update_android_find_sdkmanager "$brew_prefix/share/android-commandlinetools" bootstrap; then
      manager="$REPLY"
    else
      jobs_update_run_brew_update "$brew_bin" || return $?
      "$brew_bin" list --cask --versions android-commandlinetools >/dev/null 2>&1 && action=reinstall
      highlight_echo '来源｜Android Command-line Tools 引导工具'
      info_echo '软件源：Homebrew 官方 cask android-commandlinetools；上游 https://developer.android.com/studio（下载地址由 Homebrew 解析）。'
      info_echo "目标位置：$brew_prefix/share/android-commandlinetools；Flutter SDK：$sdk_root。"
      jobs_update_run_brew_adaptive_cmd '补齐 Android Command-line Tools 引导工具' plain \
        "$brew_bin" "$action" --cask android-commandlinetools || return $?
      if ! jobs_update_android_find_sdkmanager "$brew_prefix/share/android-commandlinetools" bootstrap; then
        warn_echo '引导工具安装后 sdkmanager 仍不可用，停止 Android 修复。'
        return 1
      fi
      manager="$REPLY"
    fi
  fi
  highlight_echo '来源｜补齐 Flutter SDK 的 Android Command-line Tools'
  info_echo "软件源：Google Android SDK 稳定频道 cmdline-tools;latest；目标位置：$sdk_root/cmdline-tools/latest。"
  jobs_update_run_flutter_android_licenses '补齐 Android SDK Command-line Tools' \
    "$manager" "--sdk_root=$sdk_root" --install 'cmdline-tools;latest' || return $?
  if ! jobs_update_android_find_sdkmanager "$sdk_root"; then
    warn_echo "Android Command-line Tools 安装后复检失败：$sdk_root。"
    return 1
  fi
}
# 为 Android 安装和许可设置总时限，仅回收本次启动的工具进程树。
jobs_update_android_run_bounded() (
  local timeout_seconds="${JOBS_ANDROID_SDK_TIMEOUT:-600}" worker_pid='' timer_pid='' timeout_file='' command_result=0
  if [[ "$timeout_seconds" != <-> ]] || (( timeout_seconds < 1 || timeout_seconds > 1800 )); then
    warn_echo 'JOBS_ANDROID_SDK_TIMEOUT 必须是 1～1800 秒的整数。'
    return 1
  fi
  timeout_file="$(mktemp -t jobs_update_android_timeout.XXXXXX)" || return 1
  /bin/rm -f -- "$timeout_file"
  trap 'exit 130' INT
  trap 'exit 143' TERM
  {
    "$@" <&0 &
    worker_pid=$!
    (
      local timer_sleep_pid=''
      trap '[[ -z "$timer_sleep_pid" ]] || kill -TERM "$timer_sleep_pid" 2>/dev/null || true; exit 0' TERM INT
      /bin/sleep "$timeout_seconds" &
      timer_sleep_pid=$!
      : > "${timeout_file}.ready"
      wait "$timer_sleep_pid" 2>/dev/null || exit 0
      timer_sleep_pid=''
      : > "$timeout_file"
      jobs_update_specs_terminate_tree "$worker_pid"
    ) &
    timer_pid=$!
    wait "$worker_pid" 2>/dev/null || command_result=$?
    worker_pid=''
    while [[ ! -e "${timeout_file}.ready" ]] && kill -0 "$timer_pid" 2>/dev/null; do
      /bin/sleep 0.01
    done
    kill -TERM "$timer_pid" 2>/dev/null || true
    wait "$timer_pid" 2>/dev/null || true
    timer_pid=''
    if [[ -e "$timeout_file" ]]; then
      warn_echo "Android 工具执行超过 ${timeout_seconds}s，已终止本次进程；未完成该操作。"
      command_result=124
    fi
  } always {
    if [[ -n "$timer_pid" ]]; then
      while [[ ! -e "${timeout_file}.ready" ]] && kill -0 "$timer_pid" 2>/dev/null; do
        /bin/sleep 0.01
      done
      kill -TERM "$timer_pid" 2>/dev/null || true
      wait "$timer_pid" 2>/dev/null || true
    fi
    [[ -z "$worker_pid" ]] || jobs_update_specs_terminate_tree "$worker_pid"
    /bin/rm -f -- "$timeout_file" "${timeout_file}.ready"
  }
  return "$command_result"
)
# 执行 Android SDK licenses 接受流程，托管模式下自动输入 y。
jobs_update_run_flutter_android_licenses() {
  local desc="$1"
  shift

  local -a license_cmd=("$@")
  if (( ${#license_cmd[@]} == 0 )); then
    warn_echo "未提供 Android SDK licenses 命令。"
    return 1
  fi

  if (( JOBS_UPDATE_TRUST_MODE == 1 )); then
    local license_output_file=''
    license_output_file="$(mktemp -t jobs_update_android_licenses.XXXXXX)" || return 1
    note_echo "$desc"
    debug_echo "执行命令：yes | ${license_cmd[*]}"
    yes | jobs_update_android_run_bounded "${license_cmd[@]}" 2>&1 | jobs_update_log_stream "$license_output_file"
    local -a license_stage_codes=("${pipestatus[@]}")
    local exit_code=${license_stage_codes[2]}
    (( license_stage_codes[3] == 0 )) || exit_code=1
    if (( exit_code == 0 )) && { jobs_update_output_has_failure "$license_output_file" ||
       /usr/bin/grep -Eq 'Android sdkmanager not found|licenses not accepted|Failed to install' "$license_output_file"; }; then
      exit_code=1
    fi
    /bin/rm -f -- "$license_output_file"

    if (( exit_code == 0 )); then
      success_echo "$desc：完成"
    else
      warn_echo "$desc：失败（exit code: ${exit_code}）"
    fi

    return $exit_code
  fi

  if [[ ! -t 0 ]]; then
    jobs_update_record_skip "当前不是交互式终端，无法接受许可：$desc"
    return 0
  fi

  jobs_update_run_cmd "$desc" jobs_update_android_run_bounded "${license_cmd[@]}"
}
# 执行 doctor；工具与许可缺失可自愈，健康告警和真正的执行 / 下载失败分别统计。
jobs_update_run_flutter_doctor_and_android_licenses() {
  local label="$1"
  local repair_result=0 warning_count=0 diagnostic_error=0 other_diagnostic=0
  shift

  local -a flutter_base_cmd=("$@")
  if (( ${#flutter_base_cmd[@]} == 0 )); then
    warn_echo "未提供 Flutter 命令，无法执行 Flutter doctor。"
    return 1
  fi

  local doctor_output_file=""
  doctor_output_file="$(mktemp -t jobs_update_flutter_doctor.XXXXXX)" || return 1
  local -a doctor_cmd=("${flutter_base_cmd[@]}" doctor -v)
  local -a license_cmd=("${flutter_base_cmd[@]}" doctor --android-licenses)

  note_echo "${label} doctor -v"
  debug_echo "执行命令：${doctor_cmd[*]}"
  "${doctor_cmd[@]}" 2>&1 | jobs_update_log_stream "$doctor_output_file"
  local -a doctor_stage_codes=("${pipestatus[@]}")
  local doctor_exit_code=${doctor_stage_codes[1]}
  (( doctor_stage_codes[2] == 0 )) || doctor_exit_code=1

  if (( doctor_exit_code == 0 )) && jobs_update_output_has_failure "$doctor_output_file"; then
    doctor_exit_code=1
  fi
  if grep -Eq 'Android license status unknown|flutter doctor --android-licenses|cmdline-tools component is missing|Android sdkmanager not found' "$doctor_output_file"; then
    if (( doctor_stage_codes[1] <= 1 && doctor_stage_codes[2] == 0 )) && ! jobs_update_output_has_failure "$doctor_output_file"; then
      local REPLY='' sdk_root='' java_home=''
      jobs_update_android_sdk_root "$doctor_output_file" && sdk_root="$REPLY" || repair_result=1
      jobs_update_android_java_home "$doctor_output_file" && java_home="$REPLY" || repair_result=1
      if (( repair_result == 0 )); then
        local -x JAVA_HOME="$java_home" ANDROID_HOME="$sdk_root" ANDROID_SDK_ROOT="$sdk_root"
        info_echo "Android 维护使用 SDK：$sdk_root；JDK：$JAVA_HOME（仅本次进程）。"
        jobs_update_android_prepare_sdkmanager "$sdk_root" || repair_result=$?
      fi
      if (( repair_result == 0 )); then
        info_echo "接受许可命令：${license_cmd[*]}"
        jobs_update_run_flutter_android_licenses '接受 Android SDK licenses' "${license_cmd[@]}" || repair_result=$?
      fi
      if (( repair_result == 0 )); then
        note_echo "${label} doctor -v（Android 修复后复检）"
        : > "$doctor_output_file" || { /bin/rm -f -- "$doctor_output_file"; return 1; }
        "${doctor_cmd[@]}" 2>&1 | jobs_update_log_stream "$doctor_output_file"
        doctor_stage_codes=("${pipestatus[@]}")
        doctor_exit_code=${doctor_stage_codes[1]}
        (( doctor_stage_codes[2] == 0 )) || doctor_exit_code=1
      else
        doctor_exit_code="$repair_result"
      fi
    else
      warn_echo 'doctor 存在命令或资源下载错误，未执行 Android 工具修复；请先修复当前 Flutter 运行环境。'
    fi
  fi
  if jobs_update_output_has_failure "$doctor_output_file" ||
     /usr/bin/grep -Eq 'Android license status unknown|flutter doctor --android-licenses|cmdline-tools component is missing|Android sdkmanager not found|Unhandled [Ee]xception|The doctor check crashed|^\[☠\]|command not found|segmentation fault' "$doctor_output_file"; then
    diagnostic_error=1
    doctor_exit_code=1
  fi
  warning_count="$(/usr/bin/grep -Ec '^\[!\]|^\[✗\]|^[[:space:]]*! Error: Browsing on the local area network' "$doctor_output_file")" || warning_count=0
  other_diagnostic="$(/usr/bin/awk '
    (/^\[!\]/ || /^\[✗\]/) && !/^\[(!|✗)\] (Network resources|Connected device)([[:space:](]|$)/ { found = 1 }
    END { print found + 0 }
  ' "$doctor_output_file")"
  if (( repair_result == 0 && diagnostic_error == 0 && doctor_stage_codes[2] == 0 &&
        doctor_stage_codes[1] <= 1 && warning_count > 0 &&
        (doctor_exit_code == 0 || other_diagnostic == 0) )); then
    doctor_exit_code=0
    JOBS_UPDATE_HEALTH_WARNING_COUNT=$(( ${JOBS_UPDATE_HEALTH_WARNING_COUNT:-0} + warning_count ))
    warn_echo "${label} doctor：检查完成，发现 ${warning_count} 项环境健康警告；已保留完整诊断，未计为升级失败。"
  fi
  if (( doctor_exit_code == 0 && warning_count == 0 )); then
    if /usr/bin/grep -Eq 'Doctor found issues in' "$doctor_output_file"; then
      warn_echo "${label} doctor 已执行；仍有上述环境健康警告，请按具体诊断处理。"
    else
      success_echo "${label} doctor -v：完成"
    fi
  elif (( doctor_exit_code != 0 )); then
    warn_echo "${label} doctor -v：未完成（exit code: ${doctor_exit_code}），具体原因见上述诊断。"
  fi
  /bin/rm -f -- "$doctor_output_file"
  return "$doctor_exit_code"
}
# ---------- 内置自述 ----------
jobs_update_show_readme_and_wait() {
  note_echo '默认低打扰更新：自动维护全部适用工具，不等待逐项确认或收尾输入。'
  gray_echo '已知 y/n 确认自动处理；需要额外账号、路径或权限的项目报告未完成并继续。'
}
# ---------- 更新项：系统 / Xcode / Shell ----------
jobs_update_clt() {
  if ! xcode-select -p >/dev/null 2>&1; then
    jobs_update_record_skip "未检测到 Xcode Command Line Tools。【MacOS】update.command 不负责安装，请运行 【MacOS】install.command 补装。"
    return 0
  fi

  success_echo "Xcode Command Line Tools 已存在：$(xcode-select -p)"

  if jobs_update_has xcodebuild; then
    jobs_update_run_sudo_cmd "接受 Xcode License" xcodebuild -license accept || true
  else
    jobs_update_record_skip "未检测到 xcodebuild，跳过 Xcode License 接受步骤"
  fi

  warn_echo "softwareupdate --install --all 可能安装 macOS 可用系统更新，耗时较长。"
  jobs_update_run_sudo_cmd "安装 macOS 可用软件更新" softwareupdate --install --all || true
}
# 封装 jobs_update_xcode_ios_platform 对应的独立处理逻辑。
jobs_update_xcode_ios_platform() {
  if ! jobs_update_has xcodebuild; then
    jobs_update_record_skip "未检测到 xcodebuild，无法更新 Xcode iOS 平台组件。"
    return 0
  fi

  if xcodebuild -showsdks 2>/dev/null | grep -E "iphoneos|iphonesimulator" >/dev/null 2>&1; then
    success_echo "检测到 iOS SDK，开始刷新 iOS 平台组件。"
  else
    warn_echo "未检测到 iOS SDK，将尝试通过 xcodebuild 下载 iOS 平台组件。"
  fi

  jobs_update_run_sh "清理 Xcode 缓存" 'rm -rf ~/Library/Caches/com.apple.dt.Xcode' || true
  jobs_update_run_sh "清理 CoreSimulator 缓存" 'rm -rf ~/Library/Developer/CoreSimulator/Caches' || true
  jobs_update_run_cmd "下载 / 更新 iOS 模拟器平台" xcodebuild -downloadPlatform iOS -verbose || true
}
# 展示来源时隐藏 URL 凭据与查询参数，不修改真实业务地址。
jobs_update_redact_source() {
  print -r -- "$1" | /usr/bin/sed -E 's#(://)[^/@]*@#\1***@#; s#[?#].*$##'
}
# 独立核对远端当前分支，避免官方升级脚本吞掉 Git 失败后误报成功。
jobs_update_verify_git_current() {
  local repo_dir="$1" fallback_remote="${2:-}" branch='' remote='' remote_ref='' remote_output='' remote_commit=''
  branch="$(git -C "$repo_dir" symbolic-ref --quiet --short HEAD)" || {
    print -u2 -r -- 'ERROR: 更新后处于游离 HEAD，无法确认跟踪分支。'
    return 1
  }
  remote="$(git -C "$repo_dir" config --get "branch.${branch}.remote")" || remote="$fallback_remote"
  remote_ref="$(git -C "$repo_dir" config --get "branch.${branch}.merge")" || remote_ref="refs/heads/${branch}"
  if [[ -z "$remote" || "$remote" == . || "$remote_ref" != refs/heads/* ]]; then
    print -u2 -r -- 'ERROR: 无法确认网络远端与跟踪分支，不能认定已更新。'
    return 1
  fi
  remote_output="$(GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/usr/bin/false GCM_INTERACTIVE=never git -C "$repo_dir" ls-remote --exit-code "$remote" "$remote_ref")" || {
    print -u2 -r -- 'ERROR: 更新后无法读取远端分支，本次更新结果未能验证。'
    return 1
  }
  remote_commit="$(print -r -- "$remote_output" | /usr/bin/awk -v ref="$remote_ref" '$2 == ref && $1 ~ /^[0-9a-f]+$/ && (length($1) == 40 || length($1) == 64) { count++; sha=$1 } END { if (count == 1) print sha }')"
  if [[ -z "$remote_commit" ]] || ! git -C "$repo_dir" merge-base --is-ancestor "$remote_commit" HEAD; then
    print -u2 -r -- 'ERROR: 本地 HEAD 尚未包含已核验的远端最新提交，更新未完成。'
    return 1
  fi
  print -r -- "已核验远端 ${remote}/${remote_ref#refs/heads/}：${remote_commit}，当前 HEAD 已包含该提交。"
}
# 保留官方升级流程并验证远端；整个过程只在验证完成后报告成功。
jobs_update_upgrade_oh_my_zsh() {
  local zsh_dir="$1"
  GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/usr/bin/false GCM_INTERACTIVE=never ZSH="$zsh_dir" /bin/zsh "$zsh_dir/tools/upgrade.sh" || return $?
  jobs_update_verify_git_current "$zsh_dir" origin
}
# 更新既有 Oh My Zsh，缺少目录或官方入口时明确跳过。
jobs_update_oh_my_zsh() {
  local zsh_dir="${ZSH:-${HOME}/.oh-my-zsh}" source_url=''
  if [[ ! -d "$zsh_dir" ]]; then
    jobs_update_record_skip "未检测到 Oh My Zsh：${zsh_dir}；请运行 【MacOS】install.command 补装。"
    return 0
  fi

  info_echo "Oh My Zsh 已存在：${zsh_dir}"

  if [[ -f "$zsh_dir/tools/upgrade.sh" ]]; then
    source_url="$(git -C "$zsh_dir" remote get-url origin 2>/dev/null)" || source_url='无法读取 origin 地址'
    info_echo "来源｜Oh My Zsh：$(jobs_update_redact_source "$source_url") → ${zsh_dir}"
    jobs_update_run_cmd "更新并核验 Oh My Zsh" jobs_update_upgrade_oh_my_zsh "$zsh_dir"
  else
    jobs_update_record_skip "未找到 Oh My Zsh 官方入口：${zsh_dir}/tools/upgrade.sh"
  fi
}
# 封装 jobs_update_rosetta 对应的独立处理逻辑。
jobs_update_rosetta() {
  if [[ "$(uname -m)" != "arm64" ]]; then
    info_echo "当前不是 Apple Silicon，Rosetta 2 不适用。"
    return 0
  fi

  if /usr/sbin/pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
    success_echo "Rosetta 2 已安装。Rosetta 2 通常通过 macOS 系统更新维护，无独立 upgrade 命令。"
  else
    warn_echo "未检测到 Rosetta 2。【MacOS】update.command 不负责安装，请运行 【MacOS】install.command 补装。"
  fi
}
# 仅把 doctor 已输出的健康诊断归为警告；执行错误、异常退出和日志失败仍须失败。
jobs_update_run_brew_doctor() {
  local desc='brew doctor（检查 Homebrew 健康状态）' output_file='' doctor_exit_code=0 log_exit_code=0 warning_count=0 diagnostic_error=0
  local -a stage_codes

  note_echo "$desc"
  debug_echo '执行命令：brew doctor'
  output_file="$(mktemp "${TMPDIR:-/tmp}/jobs-update-command.XXXXXXXX")" || {
    jobs_update_record_failure "$desc（无法创建输出记录）" 1
    return 1
  }
  JOBS_UPDATE_COMMAND_OUTPUT_FILES+=("$output_file")
  brew doctor 2>&1 | jobs_update_log_stream "$output_file"
  stage_codes=("${pipestatus[@]}")
  doctor_exit_code="${stage_codes[1]}"
  log_exit_code="${stage_codes[2]}"
  warning_count="$(/usr/bin/grep -Ec '^[[:space:]]*Warning:' "$output_file")" || warning_count=0

  if jobs_update_output_has_failure "$output_file" ||
     /usr/bin/grep -Eq 'Traceback \(most recent call last\)|(^|[[:space:](])(RuntimeError|NameError|NoMethodError|LoadError|SyntaxError|SystemExit|[[:alnum:]_]+Exception)([):[:space:]]|$)|command not found|segmentation fault|[Kk]illed:|[Aa]borted:' "$output_file"; then
    diagnostic_error=1
    (( doctor_exit_code != 0 )) || doctor_exit_code=1
  fi
  if (( log_exit_code == 0 && doctor_exit_code <= 1 && warning_count > 0 && diagnostic_error == 0 )); then
    (( JOBS_UPDATE_COMMAND_COUNT += 1 ))
    JOBS_UPDATE_HEALTH_WARNING_COUNT=$(( ${JOBS_UPDATE_HEALTH_WARNING_COUNT:-0} + warning_count ))
    /bin/rm -f -- "$output_file"
    warn_echo "brew doctor：检查完成，发现 ${warning_count} 项健康警告；已保留完整诊断，未计为升级失败。"
    return 0
  fi

  jobs_update_finish_command "$desc" "$doctor_exit_code" "$output_file" "$log_exit_code"
}
# ---------- 更新项：Homebrew ----------
jobs_update_homebrew() {
  if ! require_brew_or_skip; then
    return 0
  fi

  local result=0
  jobs_update_trust_configured_brew_taps || result=1
  if ! jobs_update_run_brew_update; then
    warn_echo "Homebrew 本体或索引未更新，停止本组升级并保留下载缓存。"
    return 1
  fi
  jobs_update_run_brew_upgrade || result=1
  jobs_update_run_brew_cask_upgrade || result=1
  if (( result == 0 )); then
    jobs_update_run_cmd "brew cleanup（清理旧版本缓存）" brew cleanup || result=1
  else
    warn_echo "部分升级未完成，跳过 brew cleanup，保留已安装版本及下载缓存供重试。"
  fi
  jobs_update_run_brew_doctor || result=1
  jobs_update_run_cmd "brew -v（输出 Homebrew 版本）" brew -v || result=1
  return "$result"
}
# 封装 brew_formula_install_arg 对应的独立处理逻辑。
brew_formula_install_arg() {
  local formula_name="$1"

  case "$formula_name" in
    go-task) echo "homebrew/core/go-task" ;;
    *) echo "$formula_name" ;;
  esac
}
# 封装 brew_formula_tap_name 对应的独立处理逻辑。
brew_formula_tap_name() {
  local formula_name="$1"

  case "$formula_name" in
    fvm) echo "leoafarias/fvm" ;;
    *) echo "" ;;
  esac
}
# 按当前 Homebrew 信任策略确认第三方 tap，避免已开启 tap trust 时直接拒绝加载。
brew_trust_tap_if_required() {
  local tap_name="$1"

  [[ -n "$tap_name" ]] || return 0

  if ! brew help trust >/dev/null 2>&1; then
    return 0
  fi

  if brew trust --json=v1 2>/dev/null | grep -Fq "\"${tap_name:l}\""; then
    success_echo "Homebrew Tap 已信任：${tap_name}"
    return 0
  fi

  jobs_update_run_cmd "信任 Homebrew Tap：${tap_name}" brew trust "$tap_name"
}
# 在全局 brew upgrade 前信任脚本维护的第三方 tap，避免扫描阶段先跳过第三方 formula/cask。
jobs_update_trust_configured_brew_taps() {
  local pkg=""
  local tap_name=""
  local trusted_taps=() result=0

  for pkg in "${BREW_FORMULAE[@]}"; do
    tap_name="$(brew_formula_tap_name "$pkg")"
    [[ -n "$tap_name" ]] || continue
    (( ${trusted_taps[(Ie)$tap_name]} > 0 )) && continue
    trusted_taps+=("$tap_name")
    brew_trust_tap_if_required "$tap_name" || result=1
  done

  for pkg in "${BREW_CASKS[@]}"; do
    tap_name="$(brew_cask_tap_name "$pkg")"
    [[ -n "$tap_name" ]] || continue
    (( ${trusted_taps[(Ie)$tap_name]} > 0 )) && continue
    trusted_taps+=("$tap_name")
    brew_trust_tap_if_required "$tap_name" || result=1
  done
  return "$result"
}
# 封装 brew_formula_after_update 对应的独立处理逻辑。
brew_formula_after_update() {
  local formula_name="$1"

  case "$formula_name" in
    rbenv) ensure_rbenv_init ;;
    jenv) ensure_jenv_init ;;
    openjdk|openjdk@17) post_openjdk_hint ;;
    fzf) setup_fzf_shellenv ;;
    *) return 0 ;;
  esac
}
# 封装 brew_cask_tap_name 对应的独立处理逻辑。
brew_cask_tap_name() {
  local cask_name="$1"

  case "$cask_name" in
    github-store) echo "OpenHub-Store/tap" ;;
    *) echo "" ;;
  esac
}
# 封装 brew_cask_install_hint 对应的独立处理逻辑。
brew_cask_install_hint() {
  local cask_name="$1"

  case "$cask_name" in
    github-store)
      warm_echo "补装命令：brew tap OpenHub-Store/tap"
      warm_echo "补装命令：brew install --cask github-store"
      ;;
    *) return 0 ;;
  esac
}
# 封装 jobs_update_github_store_after_update 对应的独立处理逻辑。
jobs_update_github_store_after_update() {
  local app_path="/Applications/GitHub-Store.app"

  if [[ -d "$app_path" ]]; then
    jobs_update_run_cmd "解除 GitHub-Store.app quarantine 标记" xattr -dr com.apple.quarantine "$app_path" || true
  else
    warn_echo "未找到 ${app_path}，跳过 quarantine 标记清理。"
  fi
}
# 仅在 Dart 通过 Flutter 官方签名校验后，解除 Homebrew Cask 传播到 Flutter SDK 的隔离标记。
jobs_update_flutter_release_verified_quarantine() {
  local flutter_command="${1:-}"
  local flutter_root=""
  local dart_binary=""
  local signature_info=""
  local remaining_quarantine=""
  local cleanup_failed=0 quarantined_link=''
  local -a quarantined_links=()

  [[ -n "$flutter_command" ]] || flutter_command="$(jobs_update_find_global_flutter 2>/dev/null || true)"
  if [[ -z "$flutter_command" ]]; then
    jobs_update_record_skip '未找到明确 Flutter 命令，无法检查该 SDK 的 quarantine 标记。'
    return 0
  fi

  flutter_command="${flutter_command:A}"
  if [[ ! -f "$flutter_command" ]]; then
    warn_echo "Flutter 命令路径无效，无法检查 SDK 隔离标记：$flutter_command。"
    return 1
  fi

  flutter_root="$(cd "$(dirname "$flutter_command")/.." 2>/dev/null && pwd -P || true)"
  dart_binary="${flutter_root}/bin/cache/dart-sdk/bin/dart"
  if [[ ! -x "$dart_binary" ]]; then
    jobs_update_record_skip "未找到 Flutter SDK 内的 Dart 二进制文件，跳过 quarantine 标记清理。"
    return 0
  fi

  if ! /usr/bin/codesign --verify --strict "$dart_binary" >/dev/null 2>&1; then
    warn_echo "Dart 代码签名校验失败，为避免降低系统安全性，保留 Flutter SDK 的 quarantine 标记。"
    return 1
  fi

  signature_info="$(/usr/bin/codesign -dv --verbose=4 "$dart_binary" 2>&1 || true)"
  if ! print -r -- "$signature_info" | grep -Fq 'Authority=Developer ID Application: FLUTTER.IO LLC (S8QB4VV633)'; then
    warn_echo "Dart 签名方不是预期的 FLUTTER.IO LLC，保留 Flutter SDK 的 quarantine 标记。"
    return 1
  fi

  if ! remaining_quarantine="$(find "$flutter_root" -xattrname com.apple.quarantine -print -quit 2>/dev/null)"; then
    warn_echo "Flutter SDK quarantine 查询失败，无法确认当前隔离状态：$flutter_root。"
    return 1
  fi
  if [[ -z "$remaining_quarantine" ]]; then
    success_echo "Flutter SDK 无 quarantine 标记，无需处理。"
    return 0
  fi

  /usr/bin/xattr -dr com.apple.quarantine "$flutter_root" 2>/dev/null || cleanup_failed=1
  if ! quarantined_links=("${(@0)$(find "$flutter_root" -type l -xattrname com.apple.quarantine -print0 2>/dev/null)}"); then
    warn_echo 'Flutter SDK 隔离标记链接查询失败，无法完成清理复检。'
    return 1
  fi
  for quarantined_link in "${quarantined_links[@]}"; do
    [[ -n "$quarantined_link" ]] || continue
    /usr/bin/xattr -d -s com.apple.quarantine "$quarantined_link" 2>/dev/null || cleanup_failed=1
  done
  if ! remaining_quarantine="$(find "$flutter_root" -xattrname com.apple.quarantine -print -quit 2>/dev/null)"; then
    warn_echo 'Flutter SDK 清理后查询失败，无法确认隔离标记已解除。'
    return 1
  fi
  if [[ -n "$remaining_quarantine" ]]; then
    warn_echo "Flutter SDK 仍存在 quarantine 标记：${remaining_quarantine}"
    return 1
  fi
  if (( cleanup_failed != 0 )); then
    info_echo 'xattr 清理曾返回非零，最终遍历复检已确认隔离标记全部解除。'
  fi

  success_echo "已验证 FLUTTER.IO LLC 官方签名，并解除 Flutter SDK quarantine 标记。"
}
# 封装 brew_cask_after_update 对应的独立处理逻辑。
brew_cask_after_update() {
  local cask_name="$1"

  case "$cask_name" in
    flutter) jobs_update_flutter_release_verified_quarantine ;;
    github-store) jobs_update_github_store_after_update ;;
    *) return 0 ;;
  esac
}
# 封装 brew_cask_local_app_path 对应的独立处理逻辑。
brew_cask_local_app_path() {
  local cask_name="$1"

  case "$cask_name" in
    vlc) echo "/Applications/VLC.app" ;;
    *) echo "" ;;
  esac
}
# 封装 brew_cask_local_app_exists 对应的独立处理逻辑。
brew_cask_local_app_exists() {
  local cask_name="$1"
  local app_path=""

  app_path="$(brew_cask_local_app_path "$cask_name")"
  [[ -n "$app_path" && -d "$app_path" ]]
}
# 手动 App 只核验简单稳定版本；含独立构建号或不完整元数据时保留跳过。
brew_cask_local_app_current_version() {
  local cask_name="$1" app_path='' short_version='' build_version='' metadata='' ruby_bin=''
  app_path="$(brew_cask_local_app_path "$cask_name")"
  [[ -n "$app_path" && -d "$app_path" ]] || return 1
  short_version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$app_path/Contents/Info.plist" 2>/dev/null)" || return 1
  build_version="$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$app_path/Contents/Info.plist" 2>/dev/null)" || build_version=''
  metadata="$(HOMEBREW_NO_AUTO_UPDATE=1 brew info --cask --json=v2 "$cask_name" 2>/dev/null)" || return 1
  ruby_bin="$(jobs_gemext_find_ruby 2>/dev/null)" || return 1
  print -r -- "$metadata" | env -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_BIN_PATH \
    "$ruby_bin" --disable-gems -rjson -e '
      begin
        data = JSON.parse(STDIN.read)
        casks = data.fetch("casks")
        exit 1 unless casks.is_a?(Array) && casks.length == 1
        cask = casks.first
        token, short_version, build_version, app_name = ARGV
        version = cask.fetch("version")
        exit 1 unless cask["token"] == token && version.is_a?(String) && version.match?(/\A[0-9]+(?:\.[0-9]+)*\z/)
        exit 1 unless short_version == version
        exit 1 unless build_version.empty? || build_version == version
        %w[bundle_version bundle_short_version].each do |key|
          value = cask[key]
          exit 1 unless value.nil? || value == version
        end
        exit 1 if cask["bundle_version"] && build_version.empty?
        artifacts = cask.fetch("artifacts")
        exit 1 unless artifacts.is_a?(Array) && artifacts.any? { |entry| entry.is_a?(Hash) && entry["app"] == [app_name] }
        puts version
      rescue JSON::ParserError, KeyError, TypeError, NoMethodError
        exit 1
      end
    ' "$cask_name" "$short_version" "$build_version" "${app_path:t}"
}
# 封装 jobs_update_brew_formula_one 对应的独立处理逻辑。
jobs_update_brew_formula_one() {
  local formula_name="$1"
  local install_arg=""
  local tap_name=""

  if ! require_brew_or_skip; then
    return 0
  fi
  jobs_update_run_brew_update || return $?

  install_arg="$(brew_formula_install_arg "$formula_name")"
  tap_name="$(brew_formula_tap_name "$formula_name")"

  if ! brew list --formula --versions "$formula_name" >/dev/null 2>&1; then
    jobs_update_record_skip "未安装 brew formula：${formula_name}，跳过升级。请运行 【MacOS】install.command 补装。"
    return 0
  fi

  if [[ -n "$tap_name" ]]; then
    brew_trust_tap_if_required "$tap_name" || return $?
    jobs_update_run_cmd "确认 Homebrew Tap：${tap_name}" brew tap "$tap_name" || return $?
  fi

  jobs_update_run_brew_adaptive_cmd "升级 brew formula：${formula_name}" plain brew upgrade --formula "$install_arg" || return $?
  [[ "$formula_name" != cocoapods ]] || JOBS_UPDATE_COCOAPODS_BREW_UPDATED=1
  brew_formula_after_update "$formula_name"
}
# 封装 jobs_update_brew_formulae 对应的独立处理逻辑。
jobs_update_brew_formulae() {
  local pkg result=0
  require_brew_or_skip || return 0
  jobs_update_run_brew_update || return $?
  for pkg in "${BREW_FORMULAE[@]}"; do
    echo ""
    highlight_echo "brew formula：${pkg}"
    jobs_update_brew_formula_one "$pkg" || result=1
  done
  return "$result"
}
# 保留原Brew双栈尝试与统计；仅Flutter SDK获取的网络失败进入下一轮。
jobs_update_flutter_cask_sdk() {
  setopt localtraps
  local adapter="$JOBS_FLUTTER_NETWORK_RESOURCE_ROOT/【MacOS】FlutterSDK命令适配.sh/【MacOS】FlutterSDK命令适配.sh"
  local network="$JOBS_FLUTTER_NETWORK_RESOURCE_ROOT/【MacOS】FlutterSDK网络选路.zsh/【MacOS】FlutterSDK网络选路.zsh"
  local result=0 delay=2 interrupted=0 sleep_pid=''
  local JOBS_UPDATE_DEFER_BREW_FAILURE=1
  [[ -f "$adapter" && -f "$network" ]] || return 1
  if [[ -z "${JOBS_FLUTTER_NETWORK_TASK_CACHE:-}" ]]; then
    local created_cache=""
    created_cache="$(/bin/zsh "$network" --cache-dir)" || return $?
    typeset -g JOBS_FLUTTER_NETWORK_TASK_CACHE="$created_cache"
  fi
  trap 'interrupted=130; [[ -z "$sleep_pid" ]] || kill "$sleep_pid" 2>/dev/null' INT
  trap 'interrupted=143; [[ -z "$sleep_pid" ]] || kill "$sleep_pid" 2>/dev/null' TERM
  trap 'interrupted=129; [[ -z "$sleep_pid" ]] || kill "$sleep_pid" 2>/dev/null' HUP
  while true; do
    result=0
    jobs_update_run_brew_adaptive_cmd '升级 Flutter cask SDK' plain env \
      JOBS_FLUTTER_ROUTE_CACHE_DIR="$JOBS_FLUTTER_NETWORK_TASK_CACHE" \
      JOBS_FLUTTER_ROUTE_LOG="$JOBS_FLUTTER_NETWORK_TASK_CACHE/brew-sdk.log" \
      /bin/sh "$adapter" --brew-cask-once "$(command -v brew)" upgrade || result=$?
    (( interrupted == 0 )) || return "$interrupted"
    (( result != 0 )) || return 0
    case "$result" in 126|127|129|130|131|137|143) return "$result" ;; esac
    if ! jobs_update_brew_failure_is_network_related; then
      jobs_update_record_failure '升级 Flutter cask SDK' "$result"
      return "$result"
    fi
    warn_echo "Flutter SDK下载未完成，${delay}秒后保留Brew原始URL重新测路并重试；Ctrl+C取消。"
    /bin/sleep "$delay" &
    sleep_pid=$!
    wait "$sleep_pid" || result=$?
    sleep_pid=''
    (( interrupted == 0 )) || return "$interrupted"
    (( result < 128 )) || return "$result"
    (( delay >= 30 )) || delay=$((delay * 2))
    (( delay <= 30 )) || delay=30
  done
}
# 封装 jobs_update_brew_cask_one 对应的独立处理逻辑。
jobs_update_brew_cask_one() {
  local cask_name="$1"
  local tap_name=""

  if ! require_brew_or_skip; then
    return 0
  fi
  jobs_update_run_brew_update || return $?

  tap_name="$(brew_cask_tap_name "$cask_name")"
  if [[ -n "$tap_name" ]]; then
    brew_trust_tap_if_required "$tap_name" || return $?
    jobs_update_run_cmd "确认 Homebrew Tap：${tap_name}" brew tap "$tap_name" || return $?
  fi

  if ! brew list --cask --versions "$cask_name" >/dev/null 2>&1; then
    if brew_cask_local_app_exists "$cask_name"; then
      local app_path="" verified_version=""
      app_path="$(brew_cask_local_app_path "$cask_name")"
      success_echo "已检测到本机 App：${app_path}"
      if verified_version="$(brew_cask_local_app_current_version "$cask_name")"; then
        success_echo "${cask_name} 本机 App 版本 ${verified_version} 已与 Homebrew 当前稳定版本核对一致，本体无需升级；保留手动安装归属。"
        return 0
      fi
      jobs_update_record_skip "Homebrew 未登记 brew cask：${cask_name}，但本机已有 App，跳过升级。"
      return 0
    fi

    jobs_update_record_skip "未安装 brew cask：${cask_name}，跳过升级。请运行 【MacOS】install.command 补装。"
    brew_cask_install_hint "$cask_name"
    return 0
  fi

  if [[ "$cask_name" == flutter ]]; then
    jobs_update_flutter_cask_sdk || return $?
  else
    jobs_update_run_brew_adaptive_cmd "升级 brew cask：${cask_name}" plain brew upgrade --cask "$cask_name" || return $?
  fi
  brew_cask_after_update "$cask_name"
}
# 封装 jobs_update_brew_casks 对应的独立处理逻辑。
jobs_update_brew_casks() {
  local pkg result=0
  require_brew_or_skip || return 0
  jobs_update_run_brew_update || return $?
  for pkg in "${BREW_CASKS[@]}"; do
    echo ""
    highlight_echo "brew cask：${pkg}"
    jobs_update_brew_cask_one "$pkg" || result=1
  done
  return "$result"
}
# FVM 数字版本和频道缓存都可能被项目共用，不能原地升级。
jobs_update_flutter_is_pinned_fvm_sdk() {
  local flutter_path="$1" sdk_root="${${1:A}:h:h}" cache_root=''
  local -a cache_roots=("${FVM_CACHE_PATH:-}" "${FVM_HOME:-}" "$HOME/fvm" "$HOME/.fvm")
  [[ "$flutter_path" != */.fvm/* && "$sdk_root" != */.fvm/* ]] || return 0
  for cache_root in "${cache_roots[@]}"; do
    [[ -n "$cache_root" ]] || continue
    if [[ "$sdk_root" == "${cache_root:A}" || "$sdk_root" == "${cache_root:A}/"* ||
          "${flutter_path:a}" == "${cache_root:a}/"* ]]; then
      return 0
    fi
  done
  [[ "$sdk_root" == */fvm/versions/* || "$flutter_path" == */fvm/default/bin/flutter ]]
}
# 只接受完整 SDK 的实际入口，未知 shim 不执行；工程内 SDK 也不属于全局环境。
jobs_update_flutter_is_global_sdk() {
  local candidate="$1" sdk_root="${${1:A}:h:h}" parent_dir=''
  [[ -x "$candidate" && "${${candidate:A}:t}" == flutter ]] || return 1
  jobs_update_flutter_is_pinned_fvm_sdk "$candidate" && return 1
  [[ -f "$sdk_root/bin/internal/shared.sh" && -f "$sdk_root/bin/internal/engine.version" &&
     -f "$sdk_root/packages/flutter_tools/pubspec.yaml" ]] || return 1
  for parent_dir in "${candidate:a:h:h}" "$sdk_root"; do
    while [[ "$parent_dir" != / && -n "$parent_dir" ]]; do
      if [[ -f "$parent_dir/.fvmrc" || ( -f "$parent_dir/pubspec.yaml" && -d "$parent_dir/lib" ) ]]; then
        return 1
      fi
      parent_dir="${parent_dir:h}"
    done
  done
  return 0
}
# 项目 FVM 或包装命令排在 PATH 前面时，继续寻找已配置的独立全局 SDK。
jobs_update_find_global_flutter() {
  local path_dir='' candidate='' brew_prefix=''
  local -a candidates=()
  for path_dir in "${path[@]}"; do
    [[ -n "$path_dir" && "$path_dir" == /* ]] || continue
    candidates+=("$path_dir/flutter")
  done
  [[ -z "${FLUTTER_ROOT:-}" ]] || candidates+=("$FLUTTER_ROOT/bin/flutter")
  [[ -z "${FLUTTER_HOME:-}" ]] || candidates+=("$FLUTTER_HOME/bin/flutter")
  for candidate in "${candidates[@]}"; do
    jobs_update_flutter_is_global_sdk "$candidate" || continue
    print -r -- "${candidate:A}"
    return 0
  done
  if jobs_update_has brew; then
    brew_prefix="$(brew --prefix 2>/dev/null)" || return 1
    candidate="$brew_prefix/share/flutter/bin/flutter"
    if [[ "$brew_prefix" == /* ]] && jobs_update_flutter_is_global_sdk "$candidate"; then
      print -r -- "${candidate:A}"
      return 0
    fi
  fi
  return 1
}
# 只维护已有 FVM 工具和独立全局 SDK；不安装全局环境、不改项目 SDK。
jobs_update_upgrade_global_flutter() (
  # Flutter upgrade 会处理当前工程依赖，切到 SDK 自身以保护调用方工程。
  builtin cd "${1:h:h}" || return 1
  jobs_flutter_sdk_command "$1" upgrade
)
# 更新工具及全局环境，逐项保留失败结果。
jobs_update_fvm_flutter() {
  local external_flutter="" result=0 upgrade_result=0

  if jobs_update_has brew && brew list --formula fvm >/dev/null 2>&1; then
    jobs_update_brew_formula_one fvm || result=1
  elif jobs_update_has fvm && jobs_update_has dart; then
    jobs_update_run_cmd "升级 FVM（Dart pub global）" jobs_flutter_sdk_command dart pub global activate fvm || result=1
  else
    jobs_update_record_skip "未检测到已安装的 FVM 及其更新运行时，跳过 FVM 更新；不自动安装。"
  fi

  if external_flutter="$(jobs_update_find_global_flutter)"; then
    info_echo "全局 Flutter：${external_flutter:h:h}；沿用当前频道获取最新版本，项目 FVM 缓存保持不变。"
    jobs_update_run_cmd "Flutter upgrade" jobs_update_upgrade_global_flutter "$external_flutter" || upgrade_result=$?
    if (( upgrade_result != 0 )); then
      warn_echo 'Flutter upgrade 未完成或已取消，跳过 SDK 隔离标记处理和 doctor；具体原因保留在本轮日志。'
      return "$upgrade_result"
    fi
    jobs_update_flutter_release_verified_quarantine "$external_flutter" || result=1
    jobs_update_run_flutter_doctor_and_android_licenses "Flutter" "$external_flutter" || result=1
  else
    jobs_update_record_skip '未检测到已配置的独立全局 Flutter SDK，跳过升级且不安装；项目 FVM SDK（含频道缓存）保持不变。'
  fi
  return "$result"
}
# 封装 jobs_update_node_base 对应的独立处理逻辑。
jobs_update_node_base() {
  jobs_update_source_nvm_if_needed

  if jobs_update_has nvm; then
    jobs_update_run_cmd "nvm 安装 / 更新 LTS" nvm install --lts --reinstall-packages-from=current || true
    jobs_update_run_cmd "nvm 设置 default=LTS" nvm alias default 'lts/*' || true
    jobs_update_run_cmd "nvm use default" nvm use default || true
  elif jobs_update_has node; then
    success_echo "检测到 Node：$(node --version 2>/dev/null || true)"
    warn_echo "未检测到 nvm；Node 版本升级已由 Homebrew formula：node 更新项负责。"
  else
    jobs_update_record_skip "未检测到 node / nvm，跳过 Node 基础维护"
  fi

  if jobs_update_has corepack; then
    jobs_update_run_cmd "启用 corepack" corepack enable || true
  fi

  if jobs_update_has npm; then
    jobs_update_run_cmd "升级 npm 自身" npm install -g npm@latest || true
    jobs_update_run_cmd "输出 npm 版本" npm -v || true
  fi
}
# 封装 jobs_update_npm_quicktype 对应的独立处理逻辑。
jobs_update_npm_quicktype() {
  if ! jobs_update_has npm; then
    jobs_update_record_skip "npm 不存在，无法更新 quicktype。请先运行 【MacOS】install.command 安装 node。"
    return 0
  fi

  if npm list -g quicktype --depth=0 >/dev/null 2>&1; then
    jobs_update_run_npm_global_cmd "更新 npm 全局包 quicktype" "quicktype" update -g quicktype || true
  else
    jobs_update_record_skip "未检测到 npm 全局包 quicktype，跳过升级。请运行 【MacOS】install.command 补装。"
  fi
}
# 封装 jobs_update_npm_opencli 对应的独立处理逻辑。
jobs_update_npm_opencli() {
  if ! jobs_update_has npm; then
    jobs_update_record_skip "npm 不存在，无法更新 OpenCLI。请先运行 【MacOS】install.command 安装 node。"
    return 0
  fi

  if ! ensure_node_for_opencli; then
    return 1
  fi

  if npm list -g @jackwener/opencli --depth=0 >/dev/null 2>&1; then
    jobs_update_run_npm_global_cmd "更新 npm 全局包 OpenCLI" "@jackwener/opencli" install -g @jackwener/opencli@latest || true
  else
    jobs_update_record_skip "未检测到 npm 全局包 OpenCLI，跳过升级。请运行 【MacOS】install.command 补装。"
  fi

  if jobs_update_has opencli; then
    jobs_update_run_cmd "输出 OpenCLI 版本" opencli --version || true
    warm_echo "OpenCLI 浏览器自动化还需要手动维护 Browser Bridge 扩展，可执行：opencli doctor"
  else
    warn_echo "当前 PATH 仍找不到 opencli，建议重新打开终端或检查 npm global bin。"
  fi
}
# 封装 jobs_update_npm_codegraph 对应的独立处理逻辑。
jobs_update_npm_codegraph() {
  if ! jobs_update_has npm; then
    jobs_update_record_skip "npm 不存在，无法更新 CodeGraph。请先运行 【MacOS】install.command 安装 node。"
    return 0
  fi

  if npm list -g @colbymchenry/codegraph --depth=0 >/dev/null 2>&1; then
    success_echo "检测到 npm 全局包 CodeGraph，开始升级到 npm latest。"
  elif jobs_update_has codegraph; then
    warn_echo "检测到 codegraph 命令，但未检测到 npm 全局包 @colbymchenry/codegraph。"
    warm_echo "将尝试用 npm 接管并升级 CodeGraph；如果你想保留非 npm 安装方式，可跳过本项。"
  else
    jobs_update_record_skip "未检测到 npm 全局包 CodeGraph，跳过升级。请运行 【MacOS】install.command 补装。"
    return 0
  fi

  if ! jobs_update_run_cmd "更新 npm 全局包 CodeGraph" npm install -g @colbymchenry/codegraph@latest; then
    warn_echo "CodeGraph npm 升级失败。若日志里是 EACCES 权限问题，请优先修复 npm 全局目录权限，或手动执行：sudo npm install -g @colbymchenry/codegraph@latest"
    return 0
  fi

  if jobs_update_has codegraph; then
    jobs_update_run_cmd "输出 CodeGraph 版本" codegraph --version || true
    jobs_update_run_cmd "刷新 CodeGraph Agent 配置" codegraph install --yes || true
    warm_echo "提示：已存在项目的 .codegraph/codegraph.db 不会在这里强制重建；进入具体项目后可按需执行 codegraph index --force。"
  else
    warn_echo "CodeGraph 已尝试升级，但当前 PATH 仍找不到 codegraph。建议重新打开终端或检查 npm global bin。"
  fi
}
# >>> Jobs Gem extension repair >>>
# 定位 CocoaPods 所用 Ruby；无法解析时复用当前 Ruby 和现有 Homebrew Ruby。
jobs_gemext_find_ruby() {
  local pod_bin='' entry='' interpreter='' candidate=''
  local -a candidates=()
  [[ -z "${JOBS_GEMEXT_RUBY:-}" ]] || candidates+=("$JOBS_GEMEXT_RUBY")
  pod_bin="$(whence -p pod 2>/dev/null)" || pod_bin=''
  if [[ -n "$pod_bin" ]]; then
    pod_bin="${pod_bin:A}"
    for entry in "$pod_bin" "${pod_bin:h:h}/libexec/bin/pod"; do
      [[ -f "$entry" ]] || continue
      interpreter="$(/usr/bin/sed -n '1s/^#!//p' "$entry")"
      [[ "$interpreter" == /*/ruby && -x "$interpreter" ]] && candidates+=("$interpreter")
    done
  fi
  candidates+=("$(whence -p ruby 2>/dev/null)" /opt/homebrew/opt/ruby/bin/ruby /usr/local/opt/ruby/bin/ruby)
  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    if env -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_BIN_PATH \
      "$candidate" --disable-gems -rrbconfig -e 'exit(RUBY_ENGINE == "ruby" ? 0 : 1)' >/dev/null 2>&1; then
      print -r -- "$candidate"
      return 0
    fi
  done
  print -u2 -r -- '✖ 没有找到可用的 Ruby，停止原生扩展检查。'
  return 1
}
# 清理仅影响本次 worker 的 Bundler 注入，原调用终端环境保持不变。
jobs_gemext_process() {
  local repair_mode="${1:-check}" ruby_bin=''
  ruby_bin="$(jobs_gemext_find_ruby)" || return 1
  env -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_BIN_PATH \
    "$ruby_bin" --disable-gems - "$repair_mode" "${JOBS_GEMEXT_BACKUP_ROOT:-$HOME/.JobsMacEnv/backups/gem-native-extensions}" <<'JOBS_GEMEXT_RUBY'
# >>> Jobs Gem extension Ruby >>>
require 'rubygems'
require 'rbconfig'
require 'fileutils'
require 'tmpdir'
require 'open3'
require 'rubygems/ext'

# 仅重建实际缺失的本平台扩展；保留已安装版本和原 Gem 安装记录。
class JobsGemExtensionRepair
  FEATURES = {
    'io-console' => ['io/console'],
    'erb' => ['erb', 'erb/escape'],
    'prism' => ['prism'],
    'json' => ['json']
  }.freeze
  PRIORITY = %w[bigdecimal io-console json prism psych erb nkf rbs].freeze
  CLEAN_ENV = %w[RUBYOPT RUBYLIB RUBYGEMS_GEMDEPS BUNDLE_GEMFILE BUNDLE_BIN_PATH].freeze

  class << self
    # 按当前 Ruby 的实际 Gem 搜索目录读取完整 spec，健康 / 默认 Gem 不进入修复。
    def missing_specs
      Gem.path.flat_map do |root|
        Dir.glob(File.join(root, 'specifications', '*.gemspec')).map do |path|
          spec = Gem::Specification.load(path)
          next unless spec && !spec.default_gem? && !spec.extensions.empty? && spec.missing_extensions?

          spec
        end.compact
      end.uniq { |spec| File.realpath(spec.loaded_from) }.sort_by do |spec|
        [PRIORITY.index(spec.name) || PRIORITY.length, spec.name, spec.version]
      end
    end

    # 只有确实有待修目标时，才检查本机编译工具链。
    def preflight!
      %w[rubyhdrdir rubyarchhdrdir].each do |key|
        file = key == 'rubyhdrdir' ? 'ruby.h' : 'ruby/config.h'
        raise "当前 Ruby 缺少头文件：#{key}" unless File.file?(File.join(RbConfig::CONFIG.fetch(key), file))
      end
      raise 'make 不可用' unless system('make', '--version', out: File::NULL, err: File::NULL)
      if RUBY_PLATFORM.include?('darwin')
        raise 'Xcode / Command Line Tools 的 clang 不可用' unless system('/usr/bin/xcrun', '--find', 'clang', out: File::NULL, err: File::NULL)
      end
    end

    # 完整备份会被构建器覆盖的 Gem 源目录和当前平台目录，旧平台扩展保持原状。
    def snapshot(spec, backup_root)
      source = spec.full_gem_path
      extension = spec.extension_dir
      raise "Gem 目录不存在或为链接：#{source}" unless File.directory?(source) && !File.symlink?(source)
      raise "Gem 目录不可写：#{source}" unless File.writable?(source) && File.writable?(File.dirname(source))
      ancestor = File.dirname(extension)
      ancestor = File.dirname(ancestor) until File.exist?(ancestor) || ancestor == File.dirname(ancestor)
      raise "扩展目录不可写：#{ancestor}" unless File.writable?(ancestor)
      raise '扩展目标不允许符号链接' if File.symlink?(extension)
      raise '仅支持本机已有的 extconf.rb 扩展源码' unless spec.extensions.all? { |entry| entry.end_with?('extconf.rb') && File.file?(File.join(source, entry)) }

      directory = Dir.mktmpdir("#{spec.full_name.gsub(/[^A-Za-z0-9_.-]/, '_')}-", backup_root)
      saved = {
        :directory => directory,
        :source => source,
        :extension => extension,
        :extension_existed => File.exist?(extension),
        :spec_path => spec.loaded_from,
        :spec_bytes => File.binread(spec.loaded_from)
      }
      FileUtils.cp_r(source, File.join(directory, 'gem'), preserve: true)
      FileUtils.cp_r(extension, File.join(directory, 'extension'), preserve: true) if saved[:extension_existed]
      FileUtils.cp(spec.loaded_from, File.join(directory, 'original.gemspec'), preserve: true)
      File.write(File.join(directory, 'manifest.txt'), saved.reject { |key, _| key == :spec_bytes }.map { |key, value| "#{key}=#{value.inspect}" }.join("\n") + "\n")
      saved
    end

    # 使用 RubyGems 原生构建接口；不经过 Gem 安装器、插件或远程下载。
    def build_spec(spec)
      spec.build_extensions
    end

    # 新 Ruby 进程精确激活原版本，并确认该版本的原生二进制真正载入。
    def verify_spec(spec)
      environment = CLEAN_ENV.each_with_object({}) { |key, result| result[key] = nil }
      environment['GEM_HOME'] = spec.base_dir
      environment['GEM_PATH'] = ([spec.base_dir] + Gem.path).uniq.join(File::PATH_SEPARATOR)
      features = FEATURES.fetch(spec.name, [spec.name.tr('-', '_')])
      code = <<~'VERIFY'
        require 'rubygems'
        name, version, source, extension, *features = ARGV
        gem name, "= #{version}"
        spec = Gem.loaded_specs.fetch(name)
        abort '激活了其它目录的同名 Gem' unless File.realpath(spec.full_gem_path) == File.realpath(source)
        features.each { |feature| require feature }
        binaries = $LOADED_FEATURES.select do |path|
          path.match?(/\.(bundle|so)\z/) &&
            [source, extension].any? { |root| File.expand_path(path).start_with?(File.expand_path(root) + File::SEPARATOR) }
        end
        expected = Dir.glob(File.join(extension, '**', '*.{bundle,so}')).map { |path| File.basename(path) }.uniq
        loaded = binaries.map { |path| File.basename(path) }.uniq
        abort '原生扩展未实际加载完整，或回退到了纯 Ruby 实现' if expected.empty? || !(expected - loaded).empty?
      VERIFY
      output, status = Open3.capture2e(environment, RbConfig.ruby, '--disable-gems', '-e', code,
                                      spec.name, spec.version.to_s, spec.full_gem_path, spec.extension_dir, *features)
      raise "原生扩展加载验证失败：#{output}" unless status.success?
      true
    end

    # 将失败构建留在备份旁，恢复本目标的原目录；不回滚其它已成功目标。
    def restore_snapshot(saved)
      directory = saved.fetch(:directory)
      source = saved.fetch(:source)
      extension = saved.fetch(:extension)
      FileUtils.mv(source, File.join(directory, 'failed-gem')) if File.exist?(source)
      FileUtils.cp_r(File.join(directory, 'gem'), source, preserve: true)
      FileUtils.mv(extension, File.join(directory, 'failed-extension')) if File.exist?(extension)
      if saved[:extension_existed]
        FileUtils.mkdir_p(File.dirname(extension))
        FileUtils.cp_r(File.join(directory, 'extension'), extension, preserve: true)
      end
      if !File.file?(saved[:spec_path]) || File.binread(saved[:spec_path]) != saved[:spec_bytes]
        FileUtils.cp(File.join(directory, 'original.gemspec'), saved[:spec_path], preserve: true)
      end
    end

    # 每个目标先备份，构建或验证失败则恢复并明确保留排查材料。
    def repair_spec(spec, backup_root)
      saved = snapshot(spec, backup_root)
      puts "➤ 重建 #{spec.full_name}；备份：#{saved[:directory]}"
      build_spec(spec)
      raise '构建结束后仍缺少当前平台完成标记' unless File.file?(spec.gem_build_complete_path)
      raise 'Gem 安装记录被意外改写' unless File.binread(spec.loaded_from) == saved[:spec_bytes]
      verify_spec(spec)
      File.write(File.join(saved[:directory], 'result.txt'), "success\n")
      puts "✔ #{spec.full_name}：当前平台扩展已构建并实际加载。"
      true
    rescue StandardError => error
      warn "✖ #{spec.full_name}：#{error.class}: #{error.message}"
      if saved
        File.write(File.join(saved[:directory], 'result.txt'), "failed\n#{error.class}: #{error.message}\n")
        begin
          restore_snapshot(saved)
          warn "⚠ 已恢复该 Gem 原目录；排查材料：#{saved[:directory]}"
        rescue StandardError => restore_error
          warn "✖ 自动恢复失败：#{restore_error.message}；完整备份：#{saved[:directory]}"
          raise
        end
      end
      false
    end

    # 持有修复锁后重新检测；健康设备不写备份、不重复编译。
    def run(mode:, backup_root:, runtime_label: nil)
      raise '未知执行模式' unless %w[check repair].include?(mode)
      puts "ℹ Ruby #{RUBY_VERSION}；平台 #{Gem::Platform.local}；运行时 #{runtime_label || RbConfig.ruby}"
      targets = missing_specs
      puts "ℹ 当前平台缺失原生扩展：#{targets.length} 个已安装版本。"
      targets.each { |spec| puts "  - #{spec.full_name}" }
      return 0 if targets.empty? || mode == 'check'

      preflight!
      FileUtils.mkdir_p(backup_root)
      File.open(File.join(backup_root, '.repair.lock'), File::RDWR | File::CREAT, 0o600) do |lock|
        raise '另一个 Gem 扩展修复正在运行' unless lock.flock(File::LOCK_EX | File::LOCK_NB)

        targets = missing_specs
        failed = targets.reject { |spec| repair_spec(spec, backup_root) }
        remaining = missing_specs
        puts "ℹ 修复成功 #{targets.length - failed.length}；失败 #{failed.length}；仍缺失 #{remaining.length}。"
        return failed.empty? && remaining.empty? ? 0 : 1
      end
    rescue StandardError => error
      warn "✖ 扩展修复停止：#{error.class}: #{error.message}"
      1
    end

    # 单文件 Shell 通过 stdin 执行；加载测试中的类定义不会启动修复。
    def run_cli
      $stdout.sync = true
      $stderr.sync = true
      exit run(mode: ARGV.fetch(0), backup_root: File.expand_path(ARGV.fetch(1)))
    end
  end
end

JobsGemExtensionRepair.run_cli if $PROGRAM_NAME == '-'
# <<< Jobs Gem extension Ruby <<<
JOBS_GEMEXT_RUBY
}
# <<< Jobs Gem extension repair <<<
# 将原生扩展诊断同步写入 update 日志，并传播 worker 退出码。
jobs_update_repair_gem_extensions() {
  if [[ "${JOBS_UPDATE_COMMAND_LOG_ACTIVE:-0}" == 1 ]]; then
    jobs_gemext_process repair 2>&1
    return $?
  fi
  jobs_gemext_process repair 2>&1 | jobs_update_log_stream
  local -a stage_codes=("${pipestatus[@]}")
  (( stage_codes[1] == 0 )) || return "${stage_codes[1]}"
  return "${stage_codes[2]}"
}
# 用原生扩展检查所选的同一 Ruby 启动 RubyGems，避开 PATH 中旧 gem 的固定解释器。
jobs_update_gem() {
  local ruby_bin="${JOBS_UPDATE_GEM_CURRENT_RUBY:-}"
  [[ -n "$ruby_bin" ]] || ruby_bin="$(jobs_gemext_find_ruby)" || return 1
  env -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_BIN_PATH \
    "$ruby_bin" --disable-gems -rrubygems/gem_runner -e 'Gem::GemRunner.new.run(ARGV)' -- "$@"
}
# 读取所选 Ruby 的 Gem 环境，并核对返回的解释器确实属于本次运行时。
jobs_update_gem_read_environment() {
  local gem_environment='' selected_ruby='' gem_home='' gem_bin='' reported_ruby=''
  selected_ruby="$(jobs_gemext_find_ruby)" || return 1
  typeset -g JOBS_UPDATE_GEM_CURRENT_RUBY="$selected_ruby"
  gem_environment="$(LC_ALL=C jobs_update_gem env 2>/dev/null)" || {
    warn_echo "无法读取所选 Ruby 的 RubyGems 环境：$selected_ruby；停止该 Gem 更新。"
    return 1
  }
  gem_home="$(print -r -- "$gem_environment" | /usr/bin/sed -n 's/^[[:space:]]*- INSTALLATION DIRECTORY: //p')"
  gem_bin="$(print -r -- "$gem_environment" | /usr/bin/sed -n 's/^[[:space:]]*- EXECUTABLE DIRECTORY: //p')"
  reported_ruby="$(print -r -- "$gem_environment" | /usr/bin/sed -n 's/^[[:space:]]*- RUBY EXECUTABLE: //p')"
  if [[ "$gem_home" != /* || "$gem_bin" != /* || "$reported_ruby" != /* ]]; then
    warn_echo '无法从 gem env 确认安装目录、可执行目录和 Ruby，停止该 Gem 更新。'
    return 1
  fi
  if [[ "${reported_ruby:A}" != "${selected_ruby:A}" ]]; then
    warn_echo "RubyGems 返回了其它 Ruby：$reported_ruby；本次选择：$selected_ruby；停止更新。"
    return 1
  fi
  typeset -g JOBS_UPDATE_GEM_CURRENT_HOME="$gem_home"
  typeset -g JOBS_UPDATE_GEM_CURRENT_BIN="$gem_bin"
  typeset -g JOBS_UPDATE_GEM_CURRENT_RUBY="$reported_ruby"
  info_echo "RubyGems 运行时：$JOBS_UPDATE_GEM_CURRENT_RUBY。"
}
# 检查已有目标及缺失目标的最近父目录，不创建测试文件或修改权限。
jobs_update_gem_path_writable() {
  local target="$1" ancestor="$1" target_kind="${2:-directory}"
  if [[ -e "$target" && "$target_kind" == directory && ! -d "$target" ]]; then
    warn_echo "RubyGems 目录被普通文件占用：$target。"
    return 1
  fi
  while [[ ! -e "$ancestor" && ! -L "$ancestor" && "$ancestor" != / ]]; do
    ancestor="${ancestor:h}"
  done
  if [[ ! -w "$ancestor" || ( -d "$ancestor" && ! -x "$ancestor" ) ]]; then
    warn_echo "RubyGems 写入目标不可写：$target（现有路径：$ancestor）。"
    return 1
  fi
  [[ ! -L "$ancestor" || -e "$ancestor" ]]
}
# gem home 可写仍可能留下只读插件；提前覆盖安装器会写入的目录和插件文件。
jobs_update_gem_write_targets_writable() {
  local gem_home="$1" gem_bin="$2" boundary="${3:-}" target=''
  for target in "$gem_home" "$gem_home/cache" "$gem_home/doc" "$gem_home/extensions" \
    "$gem_home/gems" "$gem_home/specifications" "$gem_home/build_info" "$gem_home/plugins" "$gem_bin" \
    "$gem_home"/plugins/*(N); do
    if [[ -n "$boundary" && "${target:A}" != "${boundary:A}" && "${target:A}" != "${boundary:A}/"* ]]; then
      warn_echo "用户 Gem 写入目标通过链接指向用户安装范围之外：$target。"
      return 1
    fi
    if [[ "$target" == "$gem_home/plugins/"* && "$target" != "$gem_home/plugins" ]]; then
      jobs_update_gem_path_writable "$target" file || return 1
    else
      jobs_update_gem_path_writable "$target" || return 1
    fi
  done
}
# 更新不生成本地帮助文档；共享目录权限不完整时只回退当前 Ruby 可加载的用户目录。
jobs_update_gem_packages() {
  local description="$1" gem_user_home='' gem_paths='' gem_path='' user_path_visible=0
  shift
  jobs_update_gem_read_environment || return 1
  if jobs_update_gem_write_targets_writable "$JOBS_UPDATE_GEM_CURRENT_HOME" "$JOBS_UPDATE_GEM_CURRENT_BIN"; then
    info_echo "Gem 更新范围：$JOBS_UPDATE_GEM_CURRENT_HOME；可执行目录：$JOBS_UPDATE_GEM_CURRENT_BIN。"
    jobs_update_run_cmd "$description" jobs_update_gem update "$@" --no-user-install --install-dir "$JOBS_UPDATE_GEM_CURRENT_HOME" --bindir "$JOBS_UPDATE_GEM_CURRENT_BIN" --no-document
    return $?
  fi
  gem_user_home="$(jobs_update_gem env user_gemhome 2>/dev/null)" || return 1
  gem_paths="$(jobs_update_gem env path 2>/dev/null)" || return 1
  if [[ "$gem_user_home" != /* || "${gem_user_home:A}" != "${HOME:A}/"* ]]; then
    warn_echo 'RubyGems 用户安装目录未能确认位于当前用户 HOME 内，停止更新。'
    return 1
  fi
  for gem_path in "${(@s.:.)gem_paths}"; do
    [[ "${gem_path:A}" != "${gem_user_home:A}" ]] || user_path_visible=1
  done
  if (( user_path_visible == 0 )); then
    warn_echo "当前 Ruby 的 GEM_PATH 不包含用户 Gem 目录：$gem_user_home；请先修复该 Ruby 的搜索路径。"
    return 1
  fi
  jobs_update_gem_write_targets_writable "$gem_user_home" "$gem_user_home/bin" "$gem_user_home" || return 1
  info_echo "Gem 更新回退到当前用户目录：$gem_user_home；可执行目录：$gem_user_home/bin。"
  jobs_update_run_cmd "$description（用户目录）" jobs_update_gem update "$@" --user-install --bindir "$gem_user_home/bin" --no-document || return $?
  gem_paths="$(jobs_update_gem env path 2>/dev/null)" || return 1
  user_path_visible=0
  for gem_path in "${(@s.:.)gem_paths}"; do
    [[ "${gem_path:A}" != "${gem_user_home:A}" ]] || user_path_visible=1
  done
  if (( user_path_visible == 0 )); then
    warn_echo "Gem 更新后当前 Ruby 无法搜索用户目录：$gem_user_home。"
    return 1
  fi
  case ":$PATH:" in
    *":$gem_user_home/bin:"*) ;;
    *) export PATH="$PATH:$gem_user_home/bin" ;;
  esac
  rehash
  info_echo '已复检当前 Ruby 用户 Gem 搜索路径，并将用户 bin 加入本次进程 PATH；已有命令保持原来源优先。'
}
# RubyGems 本体随系统 / Homebrew Ruby 管理；用户自管 Ruby 才在确认实际目标可写后更新。
jobs_update_rubygems_system() {
  local ruby_path='' site_directory=''
  jobs_update_gem_read_environment || return 1
  ruby_path="${JOBS_UPDATE_GEM_CURRENT_RUBY:A}"
  case "$ruby_path" in
    /usr/bin/ruby|/System/*|*/Cellar/ruby/*|*/Cellar/ruby@*/*)
      info_echo "跳过 gem update --system：RubyGems 本体由该 Ruby 的系统 / Homebrew 安装管理（$ruby_path）。"
      return 0
      ;;
  esac
  site_directory="$("$ruby_path" --disable-gems -rrbconfig -e 'puts RbConfig::CONFIG.fetch("sitelibdir")' 2>/dev/null)" || return 1
  [[ "$site_directory" == /* ]] || return 1
  jobs_update_gem_path_writable "$site_directory" || return 1
  jobs_update_gem_path_writable "$ruby_path" file || return 1
  jobs_update_gem_write_targets_writable "$JOBS_UPDATE_GEM_CURRENT_HOME" "$JOBS_UPDATE_GEM_CURRENT_BIN" || return 1
  jobs_update_run_cmd 'gem update --system' jobs_update_gem update --system --no-document
}
# 更新 RubyGems 和 Gem，并保留每个子步骤的失败状态。
jobs_update_ruby_base() {
  local result=0
  if jobs_update_has rbenv; then
    ensure_rbenv_init || result=1
    jobs_update_run_cmd "rbenv rehash" rbenv rehash || result=1
  fi

  jobs_update_run_cmd '修复当前 CocoaPods / Ruby 缺失的原生 Gem 扩展' jobs_update_repair_gem_extensions || result=1
  if jobs_update_has gem || jobs_update_has ruby; then
    jobs_update_rubygems_system || result=1
    jobs_update_gem_packages 'gem update' || result=1
  else
    jobs_update_record_skip "未检测到 gem，跳过 RubyGems 更新"
  fi
  jobs_update_run_cmd '复检更新后的原生 Gem 扩展' jobs_update_repair_gem_extensions || result=1
  return "$result"
}
# 记录选源诊断，不将可能包含凭据的 curl/git 原始错误写入日志。
jobs_update_specs_log() {
  print -r -- "$1" >&2
  print -r -- "$1" >> "$LOG_FILE"
}
# 校验环境变量中的整数时限，避免无效参数关闭超时保护。
jobs_update_specs_timeout() {
  local value="$1" maximum="$2"
  if [[ "$value" != <-> || ${#value} -gt 3 ]]; then
    jobs_update_specs_log "⚠ CocoaPods 时限必须是 1..${maximum} 的整数：$value"
    return 1
  fi
  REPLY=$(( 10#$value ))
  if (( REPLY < 1 || REPLY > maximum )); then
    jobs_update_specs_log "⚠ CocoaPods 时限超出 1..${maximum}：$value"
    return 1
  fi
  return 0
}
# 终止本次启动的进程树，覆盖 Git HTTP 传输与 CocoaPods 子进程。
jobs_update_specs_terminate_tree() {
  local process_id="$1" child_id child_list
  [[ "$process_id" == <-> && "$process_id" -gt 1 ]] || return 0
  child_list="$(/bin/ps -axo pid=,ppid= | /usr/bin/awk -v parent="$process_id" '$2 == parent {print $1}')"
  for child_id in "${(@f)child_list}"; do
    [[ -n "$child_id" ]] && jobs_update_specs_terminate_tree "$child_id"
  done
  kill -KILL "$process_id" 2>/dev/null || true
}
# 只回收当前子流程自己的进程和专属临时目录。
jobs_update_specs_cleanup() {
  local process_id
  for process_id in "${specs_pids[@]}"; do
    jobs_update_specs_terminate_tree "$process_id"
    wait "$process_id" 2>/dev/null || true
  done
  if [[ -d "$specs_work_dir" && "${specs_work_dir:t}" == jobs-update-specs.* ]]; then
    /bin/rm -r -- "$specs_work_dir"
  fi
}
# 校验完整 podspec JSON，拒绝门户 HTML、空响应和普通 JSON 假阳性。
jobs_update_specs_validate_payload() {
  local payload="$1" payload_name payload_version
  [[ -s "$payload" ]] || return 1
  /usr/bin/plutil -convert xml1 -o /dev/null -- "$payload" >/dev/null 2>&1 || return 1
  payload_name="$(/usr/bin/plutil -extract name raw -o - -- "$payload" 2>/dev/null)" || return 1
  payload_version="$(/usr/bin/plutil -extract version raw -o - -- "$payload" 2>/dev/null)" || return 1
  [[ "$payload_name" == AFNetworking && "$payload_version" == 4.0.1 ]]
}
# 对同一样本发送 GET；Git 候选同时核验真正刷新所需的 Git 与 GitHub API。
jobs_update_specs_probe() {
  local candidate="$1" sample_url duration api_sha='' api_status='' command_result=0
  local sample_path='Specs/a/7/5/AFNetworking/4.0.1/AFNetworking.podspec.json'
  sample_url="https://cdn.cocoapods.org/${sample_path}"
  [[ "$candidate" == git ]] && sample_url="https://raw.githubusercontent.com/CocoaPods/Specs/master/${sample_path}"
  curl -q --silent --show-error --fail --location \
    --connect-timeout "$specs_connect_timeout" --max-time "$specs_probe_timeout" \
    --output "$specs_work_dir/$candidate.json" --write-out '%{time_total}' \
    "$sample_url" > "$specs_work_dir/$candidate.time" 2> "$specs_work_dir/$candidate.error" || command_result=$?
  if (( command_result != 0 )); then
    print -r -- "podspec GET 失败，curl 退出码：$command_result。" > "$specs_work_dir/$candidate.reason"
    return 1
  fi
  if ! jobs_update_specs_validate_payload "$specs_work_dir/$candidate.json"; then
    print -r -- '不是完整有效的 AFNetworking 4.0.1 podspec。' > "$specs_work_dir/$candidate.reason"
    return 1
  fi
  duration="$(< "$specs_work_dir/$candidate.time")"
  [[ ${#duration} -le 20 && "$duration" =~ '^[0-9]+([.][0-9]+)?$' ]] || return 1
  if [[ "$candidate" == git ]]; then
    GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/usr/bin/false GCM_INTERACTIVE=never \
      git -c credential.interactive=false ls-remote --exit-code https://github.com/CocoaPods/Specs.git HEAD \
      > "$specs_work_dir/git.head" 2> "$specs_work_dir/git.error" || command_result=$?
    if (( command_result != 0 )) || ! /usr/bin/grep -Eq '^[0-9a-fA-F]{40,64}[[:space:]]+HEAD$' "$specs_work_dir/git.head"; then
      print -r -- "Git ls-remote 未通过，退出码：$command_result。" > "$specs_work_dir/git.reason"
      return 1
    fi
    curl -q --silent --show-error --fail --location \
      --connect-timeout "$specs_connect_timeout" --max-time "$specs_probe_timeout" \
      --header 'Accept: application/vnd.github.v3.sha' --header 'User-Agent: CocoaPods' \
      --output "$specs_work_dir/git.api" --write-out '%{http_code}' \
      https://api.github.com/repos/CocoaPods/Specs/commits/master \
      > "$specs_work_dir/git.api.status" 2> "$specs_work_dir/git.api.error" || command_result=$?
    if (( command_result == 0 )); then
      api_sha="$(< "$specs_work_dir/git.api")"
      api_status="$(< "$specs_work_dir/git.api.status")"
    fi
    if (( command_result != 0 )) || [[ "$api_status" != 200 || ! "$api_sha" =~ '^([0-9a-fA-F]{40}|[0-9a-fA-F]{64})$' ]]; then
      print -r -- "GitHub API 提交校验未通过，curl 退出码：$command_result。" > "$specs_work_dir/git.reason"
      return 1
    fi
  fi
  print -r -- "$duration" > "$specs_work_dir/$candidate.result"
}
# 为一个候选的 HTTP 和 Git 全过程设置墙钟时限，并回收看门狗。
jobs_update_specs_run_candidate() (
  trap - EXIT INT TERM
  local candidate="$1" worker_pid timer_pid candidate_result=0
  jobs_update_specs_probe "$candidate" &
  worker_pid=$!
  (
    /bin/sleep "$specs_probe_timeout" || exit 0
    print -r -- '候选整体超时，已终止传输进程。' > "$specs_work_dir/$candidate.timeout"
    jobs_update_specs_terminate_tree "$worker_pid"
  ) &
  timer_pid=$!
  wait "$worker_pid" 2>/dev/null || candidate_result=$?
  jobs_update_specs_terminate_tree "$timer_pid"
  wait "$timer_pid" 2>/dev/null || true
  if [[ -f "$specs_work_dir/$candidate.timeout" ]]; then
    /bin/mv -- "$specs_work_dir/$candidate.timeout" "$specs_work_dir/$candidate.reason"
    /bin/rm -f -- "$specs_work_dir/$candidate.result"
    return 1
  fi
  return "$candidate_result"
)
# 移植 Swift 挂载脚本的同样本实测策略；双源失败时保留缓存并拒绝联网刷新。
jobs_update_specs_select_source() (
  local specs_mode="${JOBS_SPECS_SOURCE:-auto}" REPLY
  local git_registered="${1:-1}"
  local specs_probe_timeout specs_connect_timeout specs_work_dir candidate process_id reason selected
  local -a specs_pids=()
  case "$specs_mode" in
    auto|cdn|git) ;;
    *) jobs_update_specs_log '⚠ JOBS_SPECS_SOURCE 仅支持 auto、cdn、git。'; return 1 ;;
  esac
  jobs_update_specs_timeout "${JOBS_SPECS_PROBE_TIMEOUT:-8}" 30 || return 1
  specs_probe_timeout="$REPLY"
  jobs_update_specs_timeout "${JOBS_SPECS_CONNECT_TIMEOUT:-2}" 30 || return 1
  specs_connect_timeout="$REPLY"
  (( specs_connect_timeout > specs_probe_timeout )) && specs_connect_timeout="$specs_probe_timeout"
  jobs_update_has curl || { jobs_update_specs_log '⚠ curl 不可用，保留 Specs 缓存。'; return 1; }
  specs_work_dir="$(/usr/bin/mktemp -d "${jobs_specs_repo_dir:-${TMPDIR:-/tmp}}/jobs-update-specs.XXXXXXXX")" || return 1
  trap jobs_update_specs_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  jobs_update_specs_log "ℹ CocoaPods 同样本网络探测：模式 ${specs_mode}，两源并发，每源整体限时 ${specs_probe_timeout}s。"
  for candidate in cdn git; do
    jobs_update_specs_run_candidate "$candidate" &
    specs_pids+=("$!")
  done
  for process_id in "${specs_pids[@]}"; do
    wait "$process_id" 2>/dev/null || true
  done
  specs_pids=()
  for candidate in cdn git; do
    if [[ -f "$specs_work_dir/$candidate.result" ]]; then
      jobs_update_specs_log "✔ $candidate 可用，相同 podspec GET 耗时：$(< "$specs_work_dir/$candidate.result")s。"
    else
      reason='没有有效结果。'
      [[ -s "$specs_work_dir/$candidate.reason" ]] && reason="$(< "$specs_work_dir/$candidate.reason")"
      jobs_update_specs_log "⚠ $candidate 不可用：$reason"
    fi
  done
  if [[ "$specs_mode" != auto ]]; then
    selected="$specs_mode"
  elif [[ -f "$specs_work_dir/cdn.result" && -f "$specs_work_dir/git.result" ]]; then
    selected=cdn
    if (( $(< "$specs_work_dir/git.result") < $(< "$specs_work_dir/cdn.result") * 0.85 )); then
      selected=git
    fi
  elif [[ -f "$specs_work_dir/cdn.result" ]]; then
    selected=cdn
  else
    selected=git
  fi
  if [[ "$specs_mode" == auto && "$selected" == git && "$git_registered" == 0 && -f "$specs_work_dir/cdn.result" ]]; then
    selected=cdn
    jobs_update_specs_log 'ℹ Git 小文件更快但尚无本地 Git Specs；改用已通过探测的 CDN，避免冷克隆。'
  fi
  if [[ ! -f "$specs_work_dir/$selected.result" ]]; then
    jobs_update_specs_log '⚠ 本次没有通过探测的所选源；保留现有缓存，跳过 Specs 刷新。网络尚未恢复。'
    return 1
  fi
  if [[ "$specs_mode" == auto ]]; then
    jobs_update_specs_log "✔ 本次优先刷新 $selected 公共源；真实刷新出现网络错误时才重测并尝试已登记的另一公共源。此探测不保证完整刷新成功。"
  else
    jobs_update_specs_log "✔ 本次只刷新 $selected 公共源；此探测不保证大仓库克隆或具体 Pod 源码下载成功。"
  fi
  print -r -- "$selected"
)
# 只将明确的传输失败列为可恢复，权限、证书、运行时及取消不得换源掩盖。
jobs_update_specs_failure_is_network_related() {
  local output_file="$1" exit_code="$2"
  case "$exit_code" in 0|129|130|131|137|143) return 1 ;; 124) return 0 ;; esac
  [[ -s "$output_file" ]] || return 1
  if /usr/bin/grep -Eqi 'Permission denied|Authentication failed|Bad credentials|SSL certificate problem|SSL peer certificate|certificate.*(verify|trust|authenticat)|returned error: (401|403)|HTTP(/[0-9.]+)? (401|403)|Response:.*(401|403)|401 Unauthorized|403 Forbidden|Repository not found|Traceback \(most recent call last\)|(^|[[:space:](])(LoadError|SyntaxError|NameError|NoMethodError|ArgumentError|RuntimeError|TypeError|EncodingError)([):[:space:]]|$)' "$output_file"; then
    return 1
  fi
  /usr/bin/grep -Eqi 'Failed to connect to GitHub to update the CocoaPods/Specs specs repo|curl: \((5|6|7|18|28|35|52|55|56|92)\)|Could not resolve host|Failed to connect|Couldn.t connect|Connection (timed out|reset)|Operation timed out|Timeout was reached|Operation too slow|Recv failure|Send failure|HTTP/[0-9.]+ stream|Error in the HTTP2 framing layer|CDN:.*(URL couldn.t be downloaded|download.*failed)|unable to access.*(timed out|Could not resolve|Failed to connect)' "$output_file"
}
# 只写当前 repo 流程创建的私有结果文件，内容仅含退出码与分类。
jobs_update_specs_record_outcome() {
  local outcome_file="${JOBS_UPDATE_SPECS_OUTCOME_FILE:-}"
  [[ -n "$outcome_file" ]] || return 0
  [[ -f "$outcome_file" && ! -L "$outcome_file" && -O "$outcome_file" && "${outcome_file:t}" == jobs-update-specs-outcome.* ]] || return 1
  print -r -- "$1|$2" > "$outcome_file"
}
# 仅接受同一次命令的分类，避免上一轮或全局日志中的网络错误触发换源。
jobs_update_specs_outcome_is_network_related() {
  local exit_code="$1" outcome=''
  case "$exit_code" in 129|130|131|137|143) return 1 ;; 124) return 0 ;; esac
  [[ -r "${JOBS_UPDATE_SPECS_OUTCOME_FILE:-}" ]] || return 1
  IFS= read -r outcome < "$JOBS_UPDATE_SPECS_OUTCOME_FILE" || return 1
  [[ "$outcome" == "${exit_code}|network" ]]
}
# 给真实源刷新设置独立总时限，私有捕获只供本次分类，实时输出仍只记录一次。
jobs_update_specs_run_cmd() (
  local desc="$1" REPLY specs_update_timeout specs_work_dir worker_pid timer_pid command_result=0
  local -a specs_pids=()
  shift
  jobs_update_specs_record_outcome 1 other || return 1
  jobs_update_specs_timeout "${JOBS_SPECS_UPDATE_TIMEOUT:-120}" 900 || return 1
  specs_update_timeout="$REPLY"
  specs_work_dir="$(/usr/bin/mktemp -d "${jobs_specs_repo_dir:-${TMPDIR:-/tmp}}/jobs-update-specs.XXXXXXXX")" || return 1
  local cdn_concurrency="${COCOAPODS_CDN_MAX_CONCURRENCY-8}"
  trap jobs_update_specs_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  (
    jobs_update_run_cmd "$desc（总时限 ${specs_update_timeout}s）" env \
      COCOAPODS_CDN_MAX_CONCURRENCY="$cdn_concurrency" \
      GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/usr/bin/false GCM_INTERACTIVE=never \
      GIT_HTTP_LOW_SPEED_LIMIT=1024 GIT_HTTP_LOW_SPEED_TIME=30 "$@" 2>&1 | /usr/bin/tee "$specs_work_dir/command.output"
    local -a command_stages=("${pipestatus[@]}")
    print -r -- "${command_stages[1]}|${command_stages[2]}" > "$specs_work_dir/command.status"
    (( command_stages[2] == 0 )) || return 1
    return "${command_stages[1]}"
  ) &
  worker_pid=$!
  specs_pids+=("$worker_pid")
  (
    /bin/sleep "$specs_update_timeout" || exit 0
    : > "$specs_work_dir/refresh.timeout"
    jobs_update_specs_terminate_tree "$worker_pid"
  ) &
  timer_pid=$!
  specs_pids+=("$timer_pid")
  wait "$worker_pid" 2>/dev/null || command_result=$?
  jobs_update_specs_terminate_tree "$timer_pid"
  wait "$timer_pid" 2>/dev/null || true
  specs_pids=()
  if [[ -f "$specs_work_dir/refresh.timeout" ]]; then
    warn_echo "Specs 刷新超过 ${specs_update_timeout}s，已停止本次进程；保留现有源与缓存，未完成刷新。"
    jobs_update_specs_record_outcome 124 network || return 1
    return 124
  fi
  local command_status='' failure_kind=other
  [[ ! -r "$specs_work_dir/command.status" ]] || IFS= read -r command_status < "$specs_work_dir/command.status"
  if [[ "$command_status" == "${command_result}|0" ]] && jobs_update_specs_failure_is_network_related "$specs_work_dir/command.output" "$command_result"; then
    failure_kind=network
  fi
  jobs_update_specs_record_outcome "$command_result" "$failure_kind" || return 1
  return "$command_result"
)
# 在独立 Ruby 中复用工程网络模块，只输出状态及私有 NUL 环境载荷。
jobs_update_pod_network_payload() {
  local payload_path="$1" ruby_bin
  ruby_bin="$(jobs_gemext_find_ruby)" || return 1
  env -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_BIN_PATH \
    "$ruby_bin" - "$payload_path" "$PWD" 2>/dev/null <<'JOBS_UPDATE_POD_NETWORK_RUBY'
# >>> Jobs CocoaPods network module >>>
# frozen_string_literal: true

require 'uri'

# 仅为本次依赖安装复用真实可用的 Git 链路，不改系统或全局 Git 配置。
module JobsCocoaPodsNetwork
  PROBE_URL = 'https://github.com/andreamazz/AMPopTip.git'.freeze
  PROBE_REF = 'refs/tags/4.12.0'.freeze
  DEFAULT_PROBE_TIMEOUT = 6
  OUTPUT_LIMIT = 4096
  PROXY_KEYS = %w[https_proxy HTTPS_PROXY http_proxy HTTP_PROXY all_proxy ALL_PROXY].freeze
  GIT_PROXY_KEY = 'http.https://github.com/.proxy'.freeze

  module_function

  # Podfile 在 Specs 选择前调用；查询命令与重复解析都不额外联网。
  def apply!(project_root:, probe: nil)
    return :skipped if ENV['JOBS_POD_NETWORK_ADAPT'] == '0' || probe == false || (probe.nil? && !dependency_command?)

    project_root = File.expand_path(project_root)
    @results ||= {}
    return @results[project_root] if @results.key?(project_root)

    timeout = probe_timeout
    runner = probe.respond_to?(:call) ? probe : method(:git_route_usable?)
    explicit = ENV['JOBS_POD_PROXY_URL'].to_s.strip
    if !explicit.empty? && valid_proxy_url?(explicit)
      route = proxy_route(:explicit, explicit)
      return remember_route(project_root, route) if route && usable?(runner, route, project_root, timeout)

      log('显式 JOBS_POD_PROXY_URL 未通过 Git tag 探测，继续检查当前链路。')
    elsif !explicit.empty?
      log('JOBS_POD_PROXY_URL 格式无效，继续检查当前链路；未输出代理内容。')
    end

    inherited = { kind: :inherited, environment: {} }
    return remember_route(project_root, inherited) if usable?(runner, inherited, project_root, timeout)

    routes = system_proxy_routes(timeout).reject { |route| route[:proxy] == explicit }
    results = routes.map do |route|
      Thread.new { [route, usable?(runner, route, project_root, timeout)] }
    end.map(&:value)
    selected = results.find { |_route, successful| successful }
    return remember_route(project_root, selected.first) if selected

    log('当前链路和已配置代理均未通过 Git tag 探测；继续交给源码归档回退及 CocoaPods，不代表安装成功。')
    @results[project_root] = :unavailable
  rescue StandardError
    log('网络适配未完成，保留现有环境继续安装；未输出可能含凭据的错误内容。')
    :unavailable
  end

  # 只接受真正的 CocoaPods 安装或升级，ipc/spec 等查询不触发网络。
  def dependency_command?
    command = ARGV.find { |argument| !argument.start_with?('-') }
    File.basename($PROGRAM_NAME) == 'pod' && %w[install update].include?(command)
  end

  # 对每个独立进程组设置短上限，系统候选并发，共享同一轮等待时间。
  def probe_timeout
    value = ENV['JOBS_POD_NETWORK_PROBE_TIMEOUT'] || ENV['JOB_POD_NETWORK_PROBE_TIMEOUT']
    value.to_s.match?(/\A\d+\z/) && (1..30).cover?(value.to_i) ? value.to_i : DEFAULT_PROBE_TIMEOUT
  end

  # 显式环境 URL 可以包含凭据，但控制字符、无效端口与未知协议被拒绝。
  def valid_proxy_url?(value)
    return false if value.match?(/[\x00-\x20\x7f]/)

    uri = URI.parse(value)
    %w[http https socks5 socks5h].include?(uri.scheme) &&
      uri.host && !uri.host.empty? && (1..65_535).cover?(uri.port.to_i) &&
      ['', '/'].include?(uri.path.to_s) && !uri.query && !uri.fragment
  rescue URI::Error, ArgumentError
    false
  end

  # 仅读取 macOS 已开启的手工代理，不执行 PAC、不猜端口。
  def system_proxy_routes(timeout)
    return [] unless File.executable?('/usr/sbin/scutil')

    output, successful, = run_bounded({}, ['/usr/sbin/scutil', '--proxy'], nil, [timeout, 1].min)
    return [] unless successful

    parse_system_proxies(output).each_with_object([]) do |(kind, proxy), routes|
      route = proxy_route(kind, proxy)
      routes << route if route
    end
  end

  # scutil 的 HTTPSProxy 表示 HTTP CONNECT；SOCKS 使用远端 DNS。
  def parse_system_proxies(output)
    values = {}
    depth = 0
    output.each_line do |line|
      match = line.match(/\A\s*(HTTPSEnable|HTTPSProxy|HTTPSPort|HTTPEnable|HTTPProxy|HTTPPort|SOCKSEnable|SOCKSProxy|SOCKSPort)\s*:\s*(.*?)\s*\z/) if depth <= 1
      values[match[1]] = match[2] if match
      depth += line.count('{') - line.count('}')
    end
    routes = []
    %w[HTTPS HTTP SOCKS].each do |kind|
      next unless values["#{kind}Enable"] == '1'

      host = values["#{kind}Proxy"].to_s
      port = values["#{kind}Port"].to_s
      next unless host.match?(/\A[A-Za-z0-9._:\[\]-]+\z/) && port.match?(/\A\d+\z/)

      host = "[#{host}]" if host.include?(':') && !host.start_with?('[')
      proxy = "#{kind == 'SOCKS' ? 'socks5h' : 'http'}://#{host}:#{port}"
      routes << ["system_#{kind.downcase}".to_sym, proxy] if valid_proxy_url?(proxy)
    end
    routes.uniq { |_kind, proxy| proxy }
  end

  # 追加 GitHub 范围的临时配置，既有私有域配置与 NO_PROXY 均保留。
  def proxy_route(kind, proxy)
    count = ENV.fetch('GIT_CONFIG_COUNT', '0')
    return nil unless count.match?(/\A\d+\z/)

    index = count.to_i
    environment = PROXY_KEYS.each_with_object({}) { |key, result| result[key] = proxy }
    environment['GIT_CONFIG_COUNT'] = (index + 1).to_s
    environment["GIT_CONFIG_KEY_#{index}"] = GIT_PROXY_KEY
    environment["GIT_CONFIG_VALUE_#{index}"] = proxy
    { kind: kind, proxy: proxy, environment: environment }
  end

  # 探测失败只返回状态，原始 stderr 与代理 URL 不进入日志。
  def usable?(runner, route, project_root, timeout)
    runner.call(environment: route[:environment].dup, project_root: project_root, timeout: timeout) == true
  rescue StandardError
    false
  end

  # Git 协议必须返回指定 tag 的对象 ID，HTTP 首页成功不能代替此检查。
  def git_route_usable?(environment:, project_root:, timeout:)
    environment = environment.merge(
      'GIT_TERMINAL_PROMPT' => '0', 'GCM_INTERACTIVE' => 'never',
      'GIT_ASKPASS' => '/usr/bin/false', 'SSH_ASKPASS' => '/usr/bin/false'
    )
    output, successful, = run_bounded(
      environment, ['git', '-c', 'credential.interactive=false', 'ls-remote', '--exit-code', PROBE_URL, PROBE_REF], project_root, timeout
    )
    successful && output.lines.any? do |line|
      line.match?(/\A[0-9a-fA-F]{40}(?:[0-9a-fA-F]{24})?\s+#{Regexp.escape(PROBE_REF)}\s*\z/)
    end
  end

  # 当前 pod 进程及其子进程继承代理；退出时恢复原环境，不写磁盘配置。
  def remember_route(project_root, route)
    unless route[:kind] == :inherited
      @original_environment ||= {}
      route[:environment].each do |key, value|
        @original_environment[key] = ENV[key] unless @original_environment.key?(key)
        ENV[key] = value
      end
      unless @restore_registered
        at_exit { restore! }
        @restore_registered = true
      end
    end
    message = case route[:kind]
              when :inherited then '已复用当前 Git 下载链路。'
              when :explicit then '已验证显式 JOBS_POD_PROXY_URL，仅本次 pod 进程使用。'
              else '已验证并临时继承 macOS 已开启的系统代理，仅本次 pod 进程使用。'
              end
    log(message)
    @results[project_root] = route[:kind] == :inherited ? :inherited : :proxy
  end

  # 隔离测试及进程退出共用恢复入口，只还原本模块实际覆盖的环境项。
  def restore!
    (@original_environment || {}).each { |key, value| ENV[key] = value }
    @original_environment = {}
    @results = {}
    nil
  end

  # 输出有上限且 stderr 丢弃；退出上限包含继承输出管道的子进程。
  def run_bounded(environment, command, project_root, timeout)
    reader, writer = IO.pipe
    options = { in: File::NULL, out: writer, err: File::NULL, pgroup: true }
    options[:chdir] = project_root if project_root
    pid = Process.spawn(environment, *command, options)
    writer.close
    waiter = Process.detach(pid)
    capture = { text: ''.dup, overflow: false }
    output_reader = Thread.new { capture_stdout(reader, capture) }
    deadline = monotonic_time + timeout
    timed_out = false
    while waiter.alive? || output_reader.alive?
      if monotonic_time >= deadline
        timed_out = true
        signal_group('TERM', pid)
        (output_reader.alive? ? output_reader : waiter).join(0.1)
        signal_group('KILL', pid)
        break
      end
      (waiter.alive? ? waiter : output_reader).join([deadline - monotonic_time, 0.02].min.clamp(0, 0.02))
    end
    waiter.join(0.2)
    reader.close unless reader.closed?
    output_reader.join(0.2)
    successful = !timed_out && !capture[:overflow] && !waiter.alive? && waiter.value.success?
    [capture[:text], successful, timed_out]
  rescue StandardError
    ['', false, false]
  ensure
    [reader, writer].compact.each { |stream| stream.close unless stream.closed? }
    if pid && (waiter.nil? || waiter.alive? || (output_reader && output_reader.alive?))
      signal_group('KILL', pid)
    end
    output_reader.join(0.2) if output_reader
  end

  # 始终读完有界缓冲，避免子进程因 stdout 写满而卡住。
  def capture_stdout(stream, capture)
    loop do
      chunk = stream.readpartial(1024)
      remaining = OUTPUT_LIMIT - capture[:text].bytesize
      capture[:text] << chunk.byteslice(0, remaining) if remaining.positive?
      capture[:overflow] = true if chunk.bytesize > remaining
    end
  rescue EOFError, IOError
    nil
  end

  # 独立进程组连同 Git helper 一起退出，已结束的进程属于正常竞态。
  def signal_group(signal, pid)
    Process.kill(signal, -pid)
  rescue Errno::ESRCH, Errno::EPERM
    nil
  end

  # 单调时钟避免系统校时改变探测时限。
  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # 日志只陈述链路状态，不泄露代理地址、凭据或原始子进程错误。
  def log(message)
    $stderr.puts("[Jobs Pod 网络] #{message}")
  end
end
# <<< Jobs CocoaPods network module <<<

# 只服务 update 的选路策略；避免 Git wrapper 的单次代理被误当成 pod 已继承的环境。
require 'json'

module JobsUpdatePodNetwork
  CDN_SAMPLE_URL = 'https://cdn.cocoapods.org/Specs/a/7/5/AFNetworking/4.0.1/AFNetworking.podspec.json'.freeze
  SPECS_URL = 'https://github.com/CocoaPods/Specs.git'.freeze

  module_function

  # 固定使用真实 Git 探测；测试可替换本方法，运行时不经 PATH 自动选路入口。
  def git_executable
    '/usr/bin/git'
  end

  # 显式 URL 代理（包括空值）优先；配置查询超时也不擅自覆盖未知配置。
  def configured_git_proxy?(project_root, timeout)
    _output, successful, timed_out = JobsCocoaPodsNetwork.run_bounded(
      {}, [git_executable, 'config', '--get-urlmatch', 'http.proxy', SPECS_URL],
      project_root, timeout
    )
    successful || timed_out
  end

  # 真正 CDN 的完整 JSON 或 Specs Git 任一路可用即可交接环境，最终源由后续实测决定。
  def route_usable?(environment:, project_root:, timeout:)
    payload, http_successful, = JobsCocoaPodsNetwork.run_bounded(
      environment, ['curl', '-q', '--silent', '--show-error', '--fail', '--location',
                    '--connect-timeout', [timeout, 2].min.to_s, '--max-time', timeout.to_s, CDN_SAMPLE_URL],
      project_root, timeout
    )
    if http_successful
      begin
        spec = JSON.parse(payload)
        return true if spec.is_a?(Hash) && spec['name'] == 'AFNetworking' && spec['version'] == '4.0.1'
      rescue JSON::ParserError
        nil
      end
    end
    environment = environment.merge(
      'GIT_TERMINAL_PROMPT' => '0', 'GCM_INTERACTIVE' => 'never',
      'GIT_ASKPASS' => '/usr/bin/false', 'SSH_ASKPASS' => '/usr/bin/false'
    )
    output, successful, = JobsCocoaPodsNetwork.run_bounded(
      environment, [git_executable, '-c', 'credential.interactive=false', 'ls-remote', '--quiet', '--exit-code', SPECS_URL, 'HEAD'],
      project_root, timeout
    )
    successful && output.lines.any? do |line|
      line.match?(/\A[0-9a-fA-F]{40}(?:[0-9a-fA-F]{24})?\s+HEAD\s*\z/)
    end
  end

  # Ruby 交接进程只写自己的环境；载荷写出后进程退出，无需依赖共用模块缓存。
  def use_route(route)
    return :inherited if route[:kind] == :inherited

    route[:environment].each { |key, value| ENV[key] = value }
    :proxy
  end

  # 已有明确代理不改写；自动模式先验证系统代理并将它真正交给后续 HTTP/Git。
  def apply!(project_root:)
    return :skipped if ENV['JOBS_POD_NETWORK_ADAPT'] == '0'

    network = JobsCocoaPodsNetwork
    timeout = network.probe_timeout
    inherited = { kind: :inherited, environment: {} }
    runner = method(:route_usable?)
    if ENV.key?('JOBS_POD_PROXY_URL') && !ENV['JOBS_POD_PROXY_URL'].empty?
      explicit = ENV['JOBS_POD_PROXY_URL']
      route = network.proxy_route(:explicit, explicit) if network.valid_proxy_url?(explicit)
      return use_route(route) if route && network.usable?(runner, route, project_root, timeout)

      return :unavailable
    end
    protected_environment = ENV.key?('JOBS_POD_PROXY_URL') || network::PROXY_KEYS.any? { |key| ENV.key?(key) }
    protected_environment ||= configured_git_proxy?(project_root, timeout)
    unless protected_environment
      results = network.system_proxy_routes(timeout).map do |route|
        Thread.new { [route, network.usable?(runner, route, project_root, timeout)] }
      end.map(&:value)
      selected = results.find { |_route, usable| usable }
      return use_route(selected.first) if selected
    end
    return use_route(inherited) if network.usable?(runner, inherited, project_root, timeout)

    :unavailable
  rescue StandardError
    :unavailable
  end
end

# >>> Jobs update Pod network handoff >>>
begin
  original_environment = ENV.to_h
  result = JobsUpdatePodNetwork.apply!(project_root: ARGV.fetch(1))
  raise 'unknown network result' unless %i[skipped inherited proxy unavailable].include?(result)

  changes = if result == :proxy
              ENV.select do |key, value|
                (JobsCocoaPodsNetwork::PROXY_KEYS.include?(key) || key.match?(/\AGIT_CONFIG_(?:COUNT|KEY_\d+|VALUE_\d+)\z/)) &&
                  original_environment[key] != value
              end
            else
              {}
            end
  File.open(ARGV.fetch(0), 'wb', 0o600) do |file|
    changes.each { |key, value| file.write("#{key}\0#{value}\0") }
  end
  puts result
rescue StandardError
  exit 1
end
# <<< Jobs update Pod network handoff <<<
JOBS_UPDATE_POD_NETWORK_RUBY
}
# 先完整校验受控键值，再导出；NUL 载荷不会作为 Shell 代码执行。
jobs_update_pod_network_apply_payload() {
  local payload_path="$1" route_key='' route_value='' index
  local -a route_keys=() route_values=()
  while true; do
    route_key=''
    IFS= read -r -d '' route_key || { [[ -z "$route_key" ]] && break; return 1; }
    IFS= read -r -d '' route_value || return 1
    case "$route_key" in
      https_proxy|HTTPS_PROXY|http_proxy|HTTP_PROXY|all_proxy|ALL_PROXY|GIT_CONFIG_COUNT|GIT_CONFIG_KEY_<->|GIT_CONFIG_VALUE_<->) ;;
      *) return 1 ;;
    esac
    route_keys+=("$route_key")
    route_values+=("$route_value")
  done < "$payload_path"
  for (( index=1; index<=${#route_keys}; index++ )); do
    export "${route_keys[$index]}=${route_values[$index]}"
  done
}
# 子流程退出时删除可能含认证值的私有载荷，不影响其它临时文件。
jobs_update_pod_network_cleanup() {
  if [[ -n "$jobs_pod_route_payload" && "${jobs_pod_route_payload:t}" == jobs-update-pod-route.* ]]; then
    /bin/rm -f -- "$jobs_pod_route_payload"
  fi
}
# 在本次 Specs 作用域内准备已有代理，失败时保留原环境继续真实选源。
jobs_update_pod_network_prepare() {
  local route_result=''
  jobs_pod_route_payload="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/jobs-update-pod-route.XXXXXXXX")" || {
    jobs_update_specs_log '⚠ 无法创建私有网络载荷，沿用当前环境继续 Specs 实测。'
    return 0
  }
  route_result="$(jobs_update_pod_network_payload "$jobs_pod_route_payload")" || route_result=failed
  case "$route_result" in
    proxy)
      if jobs_update_pod_network_apply_payload "$jobs_pod_route_payload"; then
        jobs_update_specs_log '✔ 已验证已有代理，本次 Specs 探测与 repo 命令继承相同环境。'
      else
        jobs_update_specs_log '⚠ 网络载荷校验失败，沿用原环境继续 Specs 实测；未认定代理可用。'
      fi
      ;;
    inherited) jobs_update_specs_log 'ℹ 已验证并复用当前 CocoaPods 链路，继续 Specs 实测；显式代理配置（含空值）保持原样。' ;;
    skipped) jobs_update_specs_log 'ℹ 已关闭 CocoaPods 代理适配，沿用当前环境进行 Specs 实测。' ;;
    unavailable) jobs_update_specs_log '⚠ 当前 CocoaPods 链路和已配置代理未通过验证，沿用原环境继续 Specs 实测；网络尚未恢复。' ;;
    *) jobs_update_specs_log '⚠ CocoaPods 网络适配未完成，沿用原环境继续 Specs 实测；未认定代理可用。' ;;
  esac
  jobs_update_pod_network_cleanup
  jobs_pod_route_payload=''
}
# 清理本次 repo 流程的私有交接载荷和退出状态，不触碰源与缓存。
jobs_update_specs_repo_cleanup() {
  jobs_update_pod_network_cleanup
  local outcome_file="${JOBS_UPDATE_SPECS_OUTCOME_FILE:-}"
  if [[ -n "$outcome_file" && ! -L "$outcome_file" && "${outcome_file:t}" == jobs-update-specs-outcome.* ]]; then
    /bin/rm -f -- "$outcome_file"
  fi
  if [[ -d "${jobs_specs_repo_dir:-}" && ! -L "$jobs_specs_repo_dir" && "${jobs_specs_repo_dir:t}" == jobs-update-specs-repo.* ]]; then
    /bin/rm -r -- "$jobs_specs_repo_dir"
  fi
}
# 同一子 Shell 内准备代理、选择公共源并刷新；返回后父环境完全不变。
jobs_update_cocoapods_repos() (
  local selected source_list source_name='' source_url='' row repo_name='' cdn_repo='' git_repo=''
  local fallback='' fallback_repo='' verified_fallback=''
  local JOBS_UPDATE_SPECS_OUTCOME_FILE=''
  local jobs_specs_repo_dir=''
  local git_registered=0 result=0 jobs_pod_route_payload=''
  trap jobs_update_specs_repo_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  jobs_specs_repo_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-update-specs-repo.XXXXXXXX")" || return 1
  JOBS_UPDATE_SPECS_OUTCOME_FILE="$(/usr/bin/mktemp "$jobs_specs_repo_dir/jobs-update-specs-outcome.XXXXXXXX")" || return 1
  jobs_update_pod_network_prepare
  source_list="$(pod repo list --no-ansi 2>/dev/null)" || { warn_echo '无法读取 CocoaPods 源清单，停止 Specs 刷新。'; return 1; }
  for row in "${(@f)source_list}"; do
    if [[ "$row" == '- URL:'* ]]; then
      source_url="${row#'- URL:'}"
      source_url="${source_url#"${source_url%%[![:space:]]*}"}"
      source_url="${source_url:l}"
      while [[ "$source_url" == */ ]]; do
        source_url="${source_url%/}"
      done
      if [[ -n "$source_name" && "$source_name" != -* && "$source_name" != *$'\t'* ]]; then
        case "$source_url" in
          https://cdn.cocoapods.org) [[ -n "$cdn_repo" ]] || cdn_repo="$source_name" ;;
          https://github.com/cocoapods/specs.git|https://github.com/cocoapods/specs)
            [[ -n "$git_repo" ]] || git_repo="$source_name"
            ;;
        esac
      fi
    elif [[ -n "$row" && "$row" != '- '* && "$row" != [[:space:]]* ]]; then
      source_name="$row"
    fi
  done
  [[ -n "$git_repo" ]] && git_registered=1
  selected="$(jobs_update_specs_select_source "$git_registered")" || return 1
  case "$selected" in
    cdn) repo_name="$cdn_repo" ;;
    git) repo_name="$git_repo" ;;
    *) return 1 ;;
  esac
  if [[ -z "$repo_name" ]]; then
    if [[ "$selected" == git ]]; then
      warn_echo '所选 GitHub Specs 尚无本地源；升级入口不冷克隆巨大 Specs 仓库，本次未刷新。'
      return 1
    fi
    repo_name='jobs-public-cdn'
    while print -r -- "$source_list" | /usr/bin/grep -Fxq -- "$repo_name"; do
      repo_name="${repo_name}-cdn"
    done
    jobs_update_specs_run_cmd '登记官方 CDN（保留已有源）' pod repo add-cdn "$repo_name" https://cdn.cocoapods.org/ || return $?
  fi
  jobs_update_specs_run_cmd "刷新 CocoaPods 公共源：$repo_name" pod repo update "$repo_name" --verbose || result=$?
  if (( result != 0 )) && [[ "${JOBS_SPECS_SOURCE:-auto}" == auto ]] && jobs_update_specs_outcome_is_network_related "$result"; then
    case "$selected" in
      cdn) fallback=git; fallback_repo="$git_repo" ;;
      git) fallback=cdn; fallback_repo="$cdn_repo" ;;
    esac
    [[ -n "$fallback_repo" ]] || return "$result"
    warn_echo "所选公共源刷新发生网络错误（exit ${result}）；重新实测已登记的 ${fallback} 源，健康时额外刷新一次，保留原缓存。"
    verified_fallback="$(JOBS_SPECS_SOURCE="$fallback" jobs_update_specs_select_source "$git_registered")" || return "$result"
    [[ "$verified_fallback" == "$fallback" ]] || return "$result"
    jobs_update_specs_run_cmd "刷新 CocoaPods 备用公共源：$fallback_repo" pod repo update "$fallback_repo" --verbose
    return $?
  fi
  return "$result"
)
# 按已安装的包管理器更新 CocoaPods，再独立按网络实测刷新公共规格源。
jobs_update_gem_cocoapods() {
  local brew_bin='' brew_prefix='' pod_bin='' result=0 brew_managed=0 gem_installed=0
  pod_bin="$(whence -p pod 2>/dev/null)" || pod_bin=''
  if { jobs_update_has gem || jobs_update_has ruby; } && jobs_update_gem_read_environment && jobs_update_gem list -i '^cocoapods$' >/dev/null 2>&1; then
    gem_installed=1
  fi
  brew_bin="$(find_brew_bin)" || brew_bin=''
  if [[ -n "$brew_bin" ]] && "$brew_bin" list --formula --versions cocoapods >/dev/null 2>&1; then
    brew_prefix="$("$brew_bin" --prefix cocoapods 2>/dev/null)" || brew_prefix=''
    if [[ -z "$pod_bin" || ( -n "$brew_prefix" && "${pod_bin:A}" == "${brew_prefix:A}/"* ) ]]; then
      brew_managed=1
    elif (( gem_installed == 0 )); then
      warn_echo 'Homebrew 已安装 CocoaPods，但当前 pod 不属于该 formula；无法确认工具归属，跳过本体升级。'
      result=1
    fi
  fi
  if (( brew_managed == 1 )); then
    if (( JOBS_UPDATE_COCOAPODS_BREW_UPDATED == 1 )); then
      info_echo 'CocoaPods 已在本轮 Homebrew formula 阶段升级，继续维护规格源。'
    elif ! jobs_update_run_brew_update "$brew_bin"; then
      warn_echo 'Homebrew 索引尚未成功更新，跳过 CocoaPods 本体升级，继续检查独立 Specs 源。'
      result=1
    elif jobs_update_run_brew_adaptive_cmd '升级 Homebrew CocoaPods' plain "$brew_bin" upgrade cocoapods; then
      JOBS_UPDATE_COCOAPODS_BREW_UPDATED=1
    else
      result=1
    fi
  fi
  if (( brew_managed == 0 && gem_installed == 1 )); then
    jobs_update_gem_packages '更新 gem 包 cocoapods' cocoapods || result=1
  elif (( brew_managed == 0 && result == 0 )); then
    warn_echo '当前 Homebrew / RubyGems 未登记 CocoaPods，跳过工具升级；已有 pod 命令仍可维护规格源。'
  fi
  if jobs_update_has pod; then
    if jobs_update_run_cmd '复检 CocoaPods 所用 Ruby 的原生扩展' jobs_update_repair_gem_extensions; then
      jobs_update_cocoapods_repos || result=1
    else
      warn_echo '原生扩展修复未完成，跳过本次规格源刷新。'
      result=1
    fi
  else
    warn_echo '当前 PATH 找不到 pod，无法刷新规格源；请先检查 CocoaPods 安装与 PATH。'
    result=1
  fi
  return "$result"
}
# 封装 jobs_update_python_base 对应的独立处理逻辑。
jobs_update_python_base() {
  if (( JOBS_UPDATE_TRUST_MODE == 1 )); then
    jobs_envupdate_python_preflight unattended || return 1
  else
    jobs_envupdate_python_preflight confirmed || return 1
  fi
  if jobs_update_has pyenv; then
    if pyenv commands | grep -qx update; then
      jobs_update_run_cmd "pyenv update" pyenv update || true
    else
      jobs_update_record_skip "pyenv-update 插件不存在，跳过 pyenv update"
    fi
    jobs_update_run_cmd "pyenv rehash" pyenv rehash || true
  fi

  if jobs_update_has pipx; then
    jobs_update_run_cmd "pipx upgrade-all" pipx upgrade-all || true
  fi

  local managed_marker=''
  managed_marker="$("$JOBS_PYTHON_BIN" -c 'import pathlib, sys, sysconfig; marker = pathlib.Path(sysconfig.get_path("stdlib")) / "EXTERNALLY-MANAGED"; print(str(marker) if sys.prefix == sys.base_prefix and marker.is_file() else "")')" || return 1
  if [[ -n "$managed_marker" ]]; then
    info_echo '该 Python 的 pip 由 Homebrew 管理，随 Homebrew Python 公式升级；本项校验其可用版本。'
    jobs_update_run_cmd "检查 Homebrew Python pip 版本" "$JOBS_PYTHON_BIN" -m pip --version
  else
    jobs_update_run_cmd "Python pip 自升级" "$JOBS_PYTHON_BIN" -m pip install --upgrade pip
  fi
}
# 封装 jobs_update_pub_cache 对应的独立处理逻辑。
jobs_update_pub_cache() {
  if jobs_update_has dart; then
    local repair_help='' result=0
    jobs_update_run_cmd "Dart pub global list" dart pub global list || result=1
    if ! repair_help="$(dart pub cache repair --help 2>&1)"; then
      print -r -- "$repair_help" | jobs_update_log_stream
      jobs_update_record_failure '读取 Dart pub cache repair 参数' 1
      warn_echo '无法读取 Dart 缓存修复参数，停止本次修复。'
      return 1
    fi
    if print -r -- "$repair_help" | /usr/bin/grep -Eq -- '(^|[[:space:]])--all([[:space:]=,]|$)'; then
      jobs_update_run_cmd "Dart pub cache repair --all" dart pub cache repair --all || result=1
    else
      jobs_update_run_cmd "Dart pub cache repair" dart pub cache repair || result=1
    fi
    return "$result"
  else
    jobs_update_record_skip "未检测到 dart，无法修复 Dart pub 缓存"
  fi
}
# ---------- 更新项：Git LFS / 手动下载页 ----------
jobs_update_git_lfs_init() {
  if ! jobs_update_has git; then
    jobs_update_record_skip "git 不存在，无法刷新 Git LFS。请先安装 Xcode Command Line Tools 或 git。"
    return 0
  fi

  if ! git lfs version >/dev/null 2>&1; then
    jobs_update_record_skip "git-lfs 不存在，无法初始化。请先运行 【MacOS】install.command 安装 brew formula：git-lfs。"
    return 0
  fi

  jobs_update_run_cmd "初始化 / 刷新 Git LFS" git lfs install || true
  jobs_update_run_cmd "配置 Git core.compression=0" git config --global core.compression 0 || true
  jobs_update_run_cmd "配置 Git http.postBuffer=524288000" git config --global http.postBuffer 524288000 || true
}
# 封装 open_download_page 对应的独立处理逻辑。
open_download_page() {
  local name="$1"
  local url="$2"

  if ! jobs_update_has open; then
    jobs_update_record_skip "open 命令不存在，无法打开：${name}"
    return 0
  fi

  jobs_update_run_cmd "打开 ${name} 下载 / 更新页" open "$url" || true
}
# 封装 jobs_update_manual_download_pages 对应的独立处理逻辑。
jobs_update_manual_download_pages() {
  if (( JOBS_UPDATE_TRUST_MODE == 1 )); then
    info_echo '无人值守模式不打开手动下载网页；网页不是自动升级入口，工具升级以对应包管理器结果为准。'
    return 0
  fi
  open_download_page "Visual Studio Code" "https://code.visualstudio.com/"
  open_download_page "Android Studio" "https://developer.android.com/studio?hl=zh-cn"
  open_download_page "Python" "https://www.python.org/downloads/"
}
# ---------- 命令实现 ----------
update() {
  local ran_count=0
  JOBS_UPDATE_COCOAPODS_BREW_UPDATED=0
  JOBS_UPDATE_FAILURE_COUNT=0
  JOBS_UPDATE_HEALTH_WARNING_COUNT=0
  JOBS_UPDATE_SKIP_COUNT=0
  JOBS_UPDATE_COMMAND_COUNT=0
  JOBS_UPDATE_FAILED_STEPS=0
  JOBS_UPDATE_PARTIAL_STEPS=0
  JOBS_UPDATE_SKIPPED_STEPS=0
  JOBS_UPDATE_SUCCEEDED_STEPS=0
  JOBS_UPDATE_FAILED_DESCRIPTIONS=()
  JOBS_UPDATE_BREW_UPDATE_RESULTS=()
  JOBS_UPDATE_RETRY_TITLES=()
  JOBS_UPDATE_RETRY_CALLBACKS=()
  JOBS_UPDATE_RETRY_SKIP_COUNT=0
  JOBS_UPDATE_RETRY_HEALTH_WARNING_COUNT=0

  if jobs_update_prompt_run "是否更新 Xcode Command Line Tools / macOS softwareupdate？" "对应 【MacOS】install.command：Xcode Command Line Tools。"; then
    jobs_update_run_selected_step "Xcode Command Line Tools / softwareupdate 更新" jobs_update_clt
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 Xcode iOS 平台组件？" "对应 【MacOS】install.command：Xcode iOS 平台组件。"; then
    jobs_update_run_selected_step "Xcode iOS 平台组件更新" jobs_update_xcode_ios_platform
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 Oh My Zsh？" "对应 【MacOS】install.command：Oh My Zsh。"; then
    jobs_update_run_selected_step "Oh My Zsh 更新" jobs_update_oh_my_zsh
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 Homebrew？" "执行 brew update / upgrade / cask upgrade / cleanup / doctor。"; then
    jobs_update_run_selected_step "Homebrew 更新" jobs_update_homebrew
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否逐项升级 【MacOS】install.command 中的 brew cask？" "覆盖 BREW_CASKS 内所有 cask；github-store 会确认 OpenHub-Store/tap 并解除 quarantine 标记。"; then
    jobs_update_run_selected_step "brew cask 批量升级" jobs_update_brew_casks
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否逐项升级 【MacOS】install.command 中的 brew formula？" "覆盖 BREW_FORMULAE 内所有 formula。"; then
    jobs_update_run_selected_step "brew formula 批量升级" jobs_update_brew_formulae
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否检查 Rosetta 2？" "Rosetta 2 无独立升级命令，只检查状态并说明维护方式。"; then
    jobs_update_run_selected_step "Rosetta 2 状态检查" jobs_update_rosetta
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 FVM / 全局 Flutter？" "只更新已安装的 FVM 工具和独立全局 Flutter SDK；未安装则跳过，不改项目 FVM SDK。"; then
    jobs_update_run_selected_step "FVM / Flutter 更新" jobs_update_fvm_flutter
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否维护 Node / corepack / npm？" "覆盖 【MacOS】install.command 中的 brew formula：node / pnpm，并兼容 nvm。"; then
    jobs_update_run_selected_step "Node / corepack / npm 维护" jobs_update_node_base
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 npm 全局包 quicktype？" "对应 【MacOS】install.command：npm 全局包 quicktype。"; then
    jobs_update_run_selected_step "npm quicktype 更新" jobs_update_npm_quicktype
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 npm 全局包 OpenCLI？" "对应 【MacOS】install.command：npm 全局包 OpenCLI。"; then
    jobs_update_run_selected_step "npm OpenCLI 更新" jobs_update_npm_opencli
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 npm 全局包 CodeGraph？" "对应 【MacOS】install.command：npm 全局包 CodeGraph；执行 npm install -g @colbymchenry/codegraph@latest，并刷新 Agent 配置。"; then
    jobs_update_run_selected_step "npm CodeGraph 更新" jobs_update_npm_codegraph
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 Ruby / RubyGems？" "维护 ruby / rbenv；前后检查 CocoaPods 所用 Ruby 的原生扩展，缺失时备份重建。"; then
    jobs_update_run_selected_step "Ruby / RubyGems 更新" jobs_update_ruby_base
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 CocoaPods？" "识别 Homebrew / gem 安装；实测 CDN / GitHub 后仅刷新所选公共源，失败保留缓存。"; then
    jobs_update_run_selected_step "CocoaPods 更新" jobs_update_gem_cocoapods
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 Python / pip？" "覆盖 【MacOS】install.command 中的 brew formula：python / python3 / uv 的后续维护。"; then
    jobs_update_run_selected_step "Python / pip 更新" jobs_update_python_base
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否修复 Dart pub 缓存？" "覆盖 Flutter / FVM / Dart 生态的缓存维护。"; then
    jobs_update_run_selected_step "Dart pub 缓存修复" jobs_update_pub_cache
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否刷新 Git LFS 初始化与大文件参数？" "对应 【MacOS】install.command：Git LFS 初始化。"; then
    jobs_update_run_selected_step "Git LFS 初始化刷新" jobs_update_git_lfs_init
    (( ran_count++ ))
  fi

  if (( JOBS_UPDATE_TRUST_MODE != 1 )) && jobs_update_prompt_run "是否打开手动下载 / 更新页面？" "对应 【MacOS】install.command：VS Code、Android Studio、Python 手动下载页。"; then
    jobs_update_run_selected_step "手动下载 / 更新页面" jobs_update_manual_download_pages
    (( ran_count++ ))
  elif (( JOBS_UPDATE_TRUST_MODE == 1 )); then
    info_echo '无人值守模式不计入手动网页项；打开下载页不代表升级完成。'
  fi

  jobs_update_print_summary "$ran_count"
  jobs_update_retry_unfinished "$ran_count"
}
# 输出当前最新结果；重试不增加原始选择数量，历史尝试保留在日志中。
jobs_update_print_summary() {
  local ran_count="$1"
  echo ""
  print_divider
  if (( ran_count == 0 )); then
    warn_echo "没有执行任何更新项"
  elif (( JOBS_UPDATE_FAILURE_COUNT > 0 )); then
    warn_echo "update 执行结束：选择 ${ran_count} 项，完成 ${JOBS_UPDATE_SUCCEEDED_STEPS} 项，失败 ${JOBS_UPDATE_FAILED_STEPS} 项，部分执行 ${JOBS_UPDATE_PARTIAL_STEPS} 项，跳过 ${JOBS_UPDATE_SKIPPED_STEPS} 项。"
    local failed_desc=''
    for failed_desc in "${JOBS_UPDATE_FAILED_DESCRIPTIONS[@]}"; do
      warn_echo "未完成：${failed_desc}"
    done
  elif (( JOBS_UPDATE_SKIP_COUNT > 0 )); then
    warn_echo "update 执行结束：选择 ${ran_count} 项，完成 ${JOBS_UPDATE_SUCCEEDED_STEPS} 项，部分执行 ${JOBS_UPDATE_PARTIAL_STEPS} 项，跳过 ${JOBS_UPDATE_SKIPPED_STEPS} 项。"
  else
    success_echo "update 执行完成，共完成 ${ran_count} 个更新项"
  fi
  info_echo "日志文件位置：${LOG_FILE}"
  if (( JOBS_UPDATE_HEALTH_WARNING_COUNT > 0 )); then
    warn_echo "健康检查告警：${JOBS_UPDATE_HEALTH_WARNING_COUNT} 项（详见日志，升级结果单独统计）。"
  fi
  print_divider
  (( JOBS_UPDATE_FAILURE_COUNT == 0 && JOBS_UPDATE_SKIP_COUNT == 0 ))
}
# ---------- 主流程统一收口 ----------
# 中断独立入口时只终止该脚本自己的子进程，随后回收本轮临时配置。
jobs_update_abort_run() {
  local interrupted_exit_code="${1:-130}" child_list='' child_id=''
  [[ "${JOBS_MAC_ENV_SOURCE_MODE:-}" != 1 ]] || return "$interrupted_exit_code"
  trap '' INT TERM
  child_list="$(/bin/ps -axo pid=,ppid= | /usr/bin/awk -v parent="$$" '$2 == parent {print $1}')"
  for child_id in "${(@f)child_list}"; do
    [[ "$child_id" == <-> && "$child_id" -gt 1 && "$child_id" != "$$" ]] || continue
    jobs_update_specs_terminate_tree "$child_id"
    wait "$child_id" 2>/dev/null || true
  done
  jobs_update_cleanup_runtime
  exit "$interrupted_exit_code"
}
# 回收本轮管理员保活、命令记录与临时下载配置。
jobs_update_cleanup_runtime() {
  jobs_update_stop_sudo_keepalive
  jobs_update_cleanup_network_strategy
}
# 安排独立入口的中断回收，并保留被调用环境原有的选项与信号处理。
jobs_update_main() {
  setopt LOCAL_OPTIONS LOCAL_TRAPS TRAPS_ASYNC
  local -x NONINTERACTIVE=1 GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/usr/bin/false GCM_INTERACTIVE=never SUDO_ASKPASS=/usr/bin/false
  if [[ "${JOBS_MAC_ENV_SOURCE_MODE:-}" != 1 ]]; then
    trap 'jobs_update_cleanup_runtime' EXIT
    trap 'jobs_update_abort_run 130' INT
    trap 'jobs_update_abort_run 143' TERM
  fi
  # 展示默认执行策略，不等待输入。
  jobs_update_show_readme_and_wait
  jobs_update_prepare_unattended_mode
  # 授权后关闭业务输入，未知子工具只能报告未完成。
  update "$@" </dev/null
  local exit_code=$?
  # 清理临时下载策略，并恢复用户原有的 Homebrew curl 环境。
  jobs_update_cleanup_runtime
  return $exit_code
}
# 只读解析参数并展示默认自动执行策略；帮助和错误不进入业务。
show_script_intro_and_wait() {
  JOBS_UPDATE_LOG_READY=0
  JOBS_UPDATE_ENTRY_READY=0
  JOBS_UPDATE_ENTRY_EXIT_CODE=0
  JOBS_UPDATE_TRUST_MODE=1
  jobs_update_parse_args "$@"
  local parse_exit_code=$?
  if (( parse_exit_code == 2 )); then
    return 0
  elif (( parse_exit_code != 0 )); then
    JOBS_UPDATE_ENTRY_EXIT_CODE=$parse_exit_code
    return 0
  fi
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：【MacOS】update.command' | jobs_intro_style title
  print -r -- '核心用途：自动维护 macOS 开发工具、语言运行时和已安装依赖。' | jobs_intro_style body
  print -r -- '运行策略：终端 update 与右键 update 均默认低打扰，不需要附加参数或逐项确认。' | jobs_intro_style body
  print -r -- '管理员权限：启动时可能输入一次系统密码，本轮保活，后续使用 sudo -n；不保存密码。' | jobs_intro_style body
  print -r -- 'Python 环境：自动维护 Homebrew 运行时和必要依赖，不替换系统 Python。' | jobs_intro_style body
  print -r -- 'Flutter：已配置的独立全局 SDK 升至当前频道最新版本；没有则跳过且不安装，项目 FVM SDK 保持不变。' | jobs_intro_style body
  print -r -- '未完成项：记录具体原因并继续，收尾汇总后退出；需要重试时直接再运行 update。' | jobs_intro_style body
  print -r -- '影响范围：系统更新、已安装工具、用户 Shell 配置、SDK 和包缓存；不自动打开下载页面。' | jobs_intro_style body
  print -r -- "日志位置：${LOG_FILE}（开始执行后记录）。" | jobs_intro_style body
  print -r -- '取消方式：按 Ctrl+C 终止；已完成的更新不会自动回滚。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  JOBS_UPDATE_ENTRY_READY=1
}
# 参数有效后初始化本轮日志；帮助和错误入口均不写文件。
jobs_update_prepare_confirmed_run() {
  (( JOBS_UPDATE_ENTRY_READY == 1 )) || return 0
  if ! : > "$LOG_FILE"; then
    print -u2 -r -- "无法初始化日志：$LOG_FILE；未执行更新。"
    JOBS_UPDATE_ENTRY_READY=0
    JOBS_UPDATE_ENTRY_EXIT_CODE=1
    return 0
  fi
  JOBS_UPDATE_LOG_READY=1
}
# 按参数解析结果执行更新并保留实际退出码。
jobs_update_run_confirmed_flow() {
  (( JOBS_UPDATE_ENTRY_READY == 1 )) || return "$JOBS_UPDATE_ENTRY_EXIT_CODE"
  jobs_update_main "$@"
}
# 编排只读自述、有效入口初始化和默认更新流程。
main() {
  show_script_intro_and_wait "$@" || return $? # 只读解析参数并展示内置自述。
  jobs_update_prepare_confirmed_run # 有效入口初始化日志及低打扰策略。
  jobs_update_run_confirmed_flow "$@" # 自动执行更新并传播最终退出码。
}
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_module() {
  set -u
  set -o pipefail
  setopt NO_NOMATCH
  if [[ "${JOBS_MAC_ENV_SOURCE_MODE:-}" != "1" ]]; then
    main "$@"
  fi
}
# 加载模块时统一执行必要的初始化和入口分派。
initialize_script_module "$@"
