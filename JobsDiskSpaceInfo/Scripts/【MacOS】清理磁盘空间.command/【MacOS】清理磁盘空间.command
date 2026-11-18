#!/bin/zsh
# shell: zsh
# 右键独立实现；与终端 clean.command 对称维护，运行时不引用其它脚本。
# 脚本自述：
# - 脚本名称：【MacOS】清理磁盘空间.command
# - 核心用途：先选择 Xcode 六组，再清理 zsh 历史、用户缓存、Homebrew 缓存及失效开发 App 图标和登记。
# - 影响范围：会删除用户缓存、将开发构建 App 移入废纸篓、备份并注销实体缺失的模拟器、清空终端历史，并短暂重启 Spotlight 与 Dock。
# - 运行提示：Xcode 先回车进入或输入跳过，选择后回车执行、非空输入跳过并继续常规阶段；常规阶段回车确认、非空取消，缓存首行全选、次行跳过，失败后回车仅重试失败步骤。
# - 失败诊断：具体系统错误同步打印到终端并写入日志，保留原失败与取消状态。

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
  print -u2 -n -r -- '按回车继续；← 返回功能菜单；Esc / Ctrl+C 取消：'
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



# ---------- 基础路径 ----------
# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
# 输出当前脚本内的 Homebrew 健康诊断。
# JOBS_INPUT_CHOICE_STYLE_BEGIN
# 仅显式询问渲染青色粗体题干；选项沿用绿／红，不读取答案或改变业务。
jobs_prompt_color_ready() {
  env | LC_ALL=C /usr/bin/grep -qiE '^(SOURCETREE|SOURCE_TREE)' && return 1
  [ -z "${NO_COLOR+x}" ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
    [ "${PLAIN_OUTPUT:-0}" != 1 ] && [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]
}
# 原生 awk 分段着色；题干模式仅由read提示启用，普通日志不追加青色。
jobs_prompt_format() {
  # 中文字符类按UTF-8字符处理，仅约束此awk进程，保留调用者locale。
  LC_ALL=en_US.UTF-8 /usr/bin/awk -v color="${1:-0}" -v lines="${2:-0}" -v keep="${3:-0}" -v question="${4:-0}" '
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
      gsub(esc "\\[[0-9;]*m", "", value)
      if (color && keep && !greenPosition(value) && value !~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) return original
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
      return output segment(value, inherited, question_body) (question && color ? esc "[0m" : "")
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
  print -u2 -r -- "ℹ $*"
}
# 验证 Homebrew 命令和真实前缀均可用。
jobs_brew_candidate_ok() {
  local candidate="$1" prefix
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  HOMEBREW_NO_AUTO_UPDATE=1 "$candidate" --version >/dev/null 2>&1 || return 1
  prefix="$("$candidate" --prefix 2>/dev/null)" || return 1
  [[ "$prefix" == /* && -d "$prefix" ]]
}
# 在当前脚本内发现健康 Homebrew，不触发安装或升级。
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
SCRIPT_DIR=""
SCRIPT_PATH=""
LOG_FILE=""
LAUNCH_SERVICES_REGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
JOBS_CLEAN_APPLICATION_INDEX_CHANGED=0
JOBS_CLEAN_CONFIRMED=0
JOBS_CLEAN_MOVED_BUILD_PRODUCTS=0
JOBS_DISK_CLEAN_LOCK=""
JOBS_DISK_CLEAN_LOCK_ID=""
JOBS_DISK_CLEAN_HOME_ID=""
# ---------- 彩色日志 ----------
# 在当前 Shell 执行命令，诊断同时显示并落盘；不让管道丢失状态或原退出码。
jobs_clean_run_with_diagnostics() {
  emulate -L zsh
  setopt PIPE_FAIL
  local jobs_clean_output_mode="$1"
  shift
  local jobs_clean_output_file="" jobs_clean_command_code=0 jobs_clean_output_code=0
  jobs_clean_output_file="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/JobsCleanCommand.XXXXXXXX")" || return 1
  if [[ "$jobs_clean_output_mode" == stderr ]]; then
    "$@" 2> "$jobs_clean_output_file" || jobs_clean_command_code=$?
    if [[ /dev/fd/2 -ef "$LOG_FILE" ]]; then
      { /bin/cat "$jobs_clean_output_file" && printf '\001'; } | jobs_prompt_format 0 2 >&2 || jobs_clean_output_code=$?
    else
      /bin/cat "$jobs_clean_output_file" | jobs_prompt_tee "$LOG_FILE" >&2 || jobs_clean_output_code=$?
    fi
  else
    "$@" > "$jobs_clean_output_file" 2>&1 || jobs_clean_command_code=$?
    if [[ /dev/fd/1 -ef "$LOG_FILE" ]]; then
      { /bin/cat "$jobs_clean_output_file" && printf '\001'; } | jobs_prompt_format 0 2 || jobs_clean_output_code=$?
    else
      /bin/cat "$jobs_clean_output_file" | jobs_prompt_tee "$LOG_FILE" || jobs_clean_output_code=$?
    fi
  fi
  /bin/rm -f -- "$jobs_clean_output_file"
  (( jobs_clean_command_code == 0 )) || return "$jobs_clean_command_code"
  return "$jobs_clean_output_code"
}
# 普通命令的输出与错误均进入终端和日志。
jobs_clean_run_logged() {
  jobs_clean_run_with_diagnostics all "$@"
}
# 机器输出保持原样，仅将错误显示到 stderr 并写日志。
jobs_clean_run_stderr_logged() {
  jobs_clean_run_with_diagnostics stderr "$@"
}

# 同步记录终端输出和脚本日志。
log() {
  if [[ /dev/fd/1 -ef "$LOG_FILE" ]]; then
    # Xcode 动作已重定向到同一日志，避免追加后又经 stdout 重复写入。
    { echo -e "$1"; printf '\001'; } | jobs_prompt_format 0 2
  else
    echo -e "$1" | jobs_prompt_tee "$LOG_FILE"
  fi
}
# 按当前输出级别记录终端信息，并同步写入脚本日志。
color_echo()     { log "[1;32m$1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
info_echo()      { log "[1;34mℹ $1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
success_echo()   { log "[1;32m✔ $1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warn_echo()      { log "[1;33m⚠ $1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warm_echo()      { log "[1;33m$1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
note_echo()      { log "[1;35m➤ $1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
error_echo()     { log "[1;31m✖ $1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
err_echo()       { log "[1;31m$1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
debug_echo()     { log "[1;35m🐞 $1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
highlight_echo() { log "[1;36m🔹 $1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
gray_echo()      { log "[0;90m$1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
bold_echo()      { log "[1m$1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
underline_echo() { log "[4m$1[0m"; }
# ---------- 内置自述 ----------
# 两个独立入口携带相同完整自述；这里只展示范围，不扫描或执行清理。
jobs_clean_show_intro() {
  cat <<EOFREADME | jobs_intro_style auto | jobs_prompt_filter
============================================================
clean - 磁盘空间清理
============================================================

功能：
  - 清空 zsh 历史和 zsh_sessions 残留。
  - 完整枚举用户缓存候选，明确勾选并核对最终范围后才处理；未选项目保留。
  - 将 Spotlight 收录且无法在 macOS 打开的 Apple 平台构建 App 移入废纸篓。
  - 定向注销非 macOS 构建产物与模拟器 App 的 LaunchServices 记录。
  - 实体已缺失的模拟器登记归前置 Simulators 组选择；未选或跳过的受管设备保持不动。
  - 检测到 Homebrew 时执行 brew cleanup。

说明：
  - 位于 Library/Caches 不代表可直接删除；开发依赖／源码标记、只读内容、链接、异盘或无法完整检查的候选保留。
  - 保护规则按实际结构与权限判断，不依赖本机用户名、工程路径或特定开发环境目录名。
  - 选中的普通缓存直接删除，不经过废纸篓；应用后续可能重新生成缓存。
  - 常规清理失败后列出未完成步骤；回车仅重试失败步骤，任意非空输入停止，EOF / Ctrl+C 取消。
  - fzf 中 Enter 勾选，Space 确认；未勾选时取当前行，已有选择不增加光标项，默认跳过与最终确认保留。
  - Xcode 最终范围回车确认，任意非空输入跳过；Xcode 失败仍进入常规清理，最终保留未完成状态。
  - 重试仍执行原有安全检查，不自动提权或修改权限；每轮结果追加到同一日志。
  - 删除、移动、备份或查询失败的具体系统错误同时打印到终端并写入日志。
  - 只移动用户目录中 Build/Products 或 build/*-iphone 等开发输出下的 .app。
  - 不移动 Applications 里的正常 App，不移动正常 CoreSimulator 设备容器中的 App 实体。
  - 模拟器目录或 device.plist 已缺失才注销；仅 data 缺失或 Runtime 不可用的设备保留。
  - 只关闭待注销的损坏设备；实体目录完全缺失时，关闭失败或卡在 Shutting Down 仍尝试按 UUID 注销。
  - 仍有残留目录时，须确认已关闭并完成备份；正常设备与共享 Runtime 保留。
  - 构建 App 保留在废纸篓的 JobsClean-DevelopmentApps-* 目录中，可恢复或重新构建。
  - 会短暂重启 Spotlight、corespotlightd、sharedfilelistd 和 Dock，界面可能闪烁一次。
  - 日志路径：${LOG_FILE:-确认后在系统临时目录建立独立日志}
============================================================
EOFREADME
}
# 展示完整范围；仅空回车授权常规阶段，输入结束与非空输入取消。
show_script_intro_and_wait() {
  emulate -L zsh
  jobs_clean_show_intro
  print -r -- '常规清理按回车确认；任意非空输入、EOF 或 Ctrl+C 均取消。' | jobs_intro_style body
  [[ -t 0 && -t 1 ]] || { print -u2 '无交互终端，已取消；未执行常规清理。'; return 130; }
  local answer=""
  IFS= builtin read -r "?$(jobs_prompt_render '⚠️ 确认执行上述常规清理？[回车确认 / 任意字符后回车取消]：')" answer || return 130
  [[ -z "$answer" ]] || { print -r -- '已取消；未执行常规清理。'; return 130; }
  JOBS_CLEAN_CONFIRMED=1
}
# ---------- 命令实现 ----------
# 初始化清理流程需要的 zsh 选项和日志文件。
jobs_clean_prepare_runtime() {
  (( JOBS_CLEAN_CONFIRMED == 1 )) || return 1
  setopt NO_NOMATCH PIPE_FAIL
  [[ -n "${HOME:-}" && "$HOME" == /* && -d "$HOME" && ! -L "$HOME" && "${HOME:A}" != / ]] || { print -u2 '用户目录不可靠，停止清理。'; return 1; }
  JOBS_DISK_CLEAN_HOME_ID="$(/usr/bin/stat -f '%d:%i' "$HOME")" || return 1
  if ! LOG_FILE="$(umask 077; /usr/bin/mktemp "${TMPDIR:-/tmp}/JobsDiskSpaceCleanup.XXXXXXXX")"; then
    LOG_FILE=""
    print -u2 -r -- "无法在临时目录创建本轮日志，未执行常规清理：${TMPDIR:-/tmp}"
    return 1
  fi
  JOBS_DISK_CLEAN_LOCK="${TMPDIR:-/tmp}/JobsDiskSpaceCleanup-${UID}.lock"
  /bin/mkdir -m 700 "$JOBS_DISK_CLEAN_LOCK" 2>/dev/null || { print -u2 '已有清理任务或遗留锁，未执行清理。确认旧任务已结束后再处理日志所示锁。'; print -u2 -r -- "$JOBS_DISK_CLEAN_LOCK"; JOBS_DISK_CLEAN_LOCK=""; return 1; }
  JOBS_DISK_CLEAN_LOCK_ID="$(/usr/bin/stat -f '%d:%i' "$JOBS_DISK_CLEAN_LOCK")" || return 1
  print -r -- "$$" > "$JOBS_DISK_CLEAN_LOCK/pid" || return 1
  trap 'jobs_disk_clean_release_lock' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  print -r -- "日志：$LOG_FILE"
}
# 只回收当前进程创建且身份未变化的锁，不接管或删除其它任务。
jobs_disk_clean_release_lock() {
  [[ -n "$JOBS_DISK_CLEAN_LOCK" && -d "$JOBS_DISK_CLEAN_LOCK" && ! -L "$JOBS_DISK_CLEAN_LOCK" &&
     "$(/usr/bin/stat -f '%d:%i' "$JOBS_DISK_CLEAN_LOCK" 2>/dev/null)" == "$JOBS_DISK_CLEAN_LOCK_ID" &&
     -f "$JOBS_DISK_CLEAN_LOCK/pid" && "$(<"$JOBS_DISK_CLEAN_LOCK/pid")" == "$$" ]] || return 0
  /bin/rm -f -- "$JOBS_DISK_CLEAN_LOCK/pid"
  /bin/rmdir -- "$JOBS_DISK_CLEAN_LOCK"
}
# 所有写入候选必须位于原用户目录，逐层拒绝链接；HOME 被并发替换时停止。
jobs_disk_clean_reliable_path() {
  emulate -L zsh
  local target="$1" current="$HOME" part="" relative="${1#$HOME/}"
  [[ -n "$HOME" && "$HOME" == /* && "${HOME:A}" == "$HOME" && "$target" == "$HOME/"* && ! -L "$HOME" ]] || return 1
  [[ -z "$JOBS_DISK_CLEAN_HOME_ID" || "$(/usr/bin/stat -f '%d:%i' "$HOME" 2>/dev/null)" == "$JOBS_DISK_CLEAN_HOME_ID" ]] || return 1
  for part in "${(@s:/:)relative}"; do
    [[ -n "$part" && "$part" != . && "$part" != .. ]] || return 1
    current+="/$part"
    [[ -e "$current" && ! -L "$current" ]] || return 1
  done
  [[ -O "$target" ]]
}
# 历史仅限当前用户的标准文件；不信任外部 HISTFILE 或符号链接。
# 交给诊断包装器执行重定向，让历史文件写入错误也能同时显示和落盘。
jobs_clean_truncate_history() {
  : >| "$1"
}
jobs_disk_clean_history() {
  emulate -L zsh
  (( JOBS_CLEAN_CONFIRMED == 1 )) || return 1
  local item="" result=0 sessions_id="" id=""
  local -a files=("$HOME/.zsh_history")
  typeset -A identities=()
  if jobs_disk_clean_reliable_path "$HOME/.zsh_sessions" && [[ -d "$HOME/.zsh_sessions" ]]; then
    sessions_id="$(/usr/bin/stat -f '%d:%i' "$HOME/.zsh_sessions")" || return 1
    files+=("$HOME/.zsh_sessions"/*.history(N) "$HOME/.zsh_sessions"/*.historynew(N))
  elif [[ -e "$HOME/.zsh_sessions" || -L "$HOME/.zsh_sessions" ]]; then
    warn_echo '会话历史入口不可靠，已保留。'
    result=1
  fi
  for item in "${files[@]}"; do
    if jobs_disk_clean_reliable_path "$item" && [[ -f "$item" ]]; then
      identities[$item]="$(/usr/bin/stat -f '%d:%i' "$item")"
    fi
  done
  for item in "${files[@]}"; do
    [[ -e "$item" || -L "$item" ]] || continue
    if [[ -n "${identities[$item]:-}" ]] && jobs_disk_clean_reliable_path "$item" &&
       [[ -f "$item" && "$(/usr/bin/stat -f '%d:%i' "$item")" == "${identities[$item]}" ]] &&
       { [[ "${item:h}" != "$HOME/.zsh_sessions" ]] || [[ "$(/usr/bin/stat -f '%d:%i' "$HOME/.zsh_sessions")" == "$sessions_id" ]]; }; then
      jobs_clean_run_logged jobs_clean_truncate_history "$item" || { warn_echo "历史清理失败：$item"; result=1; }
    else
      warn_echo "历史路径已变化或不可靠，已保留：$item"
      result=1
    fi
  done
  return "$result"
}
# 清空当前用户缓存内容，保留目录本身且不跟随缓存入口的符号链接。
# 以有界流式遍历核对整棵候选树；不完整检查不能成为删除授权。
jobs_clean_cache_snapshot() (
  emulate -L zsh
  setopt NO_NOMATCH PIPE_FAIL
  local target="$1" expected_device="$2" output="$3" work="" scan_pid="" scan_fd="" entry="" metadata="" relative=""
  local -a fields=()
  local -i count=0 deadline=$((SECONDS + 5)) scan_code=0 read_code=0
  work="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/JobsCacheScan.XXXXXXXX")" || return 1
  # 只管理本次find；收尾轮询有界，系统I/O本身不承诺硬超时。
  jobs_clean_cache_scan_cleanup() {
    local -i rounds=0
    [[ -z "$scan_fd" ]] || exec {scan_fd}<&-
    if [[ -n "$scan_pid" ]]; then
      /bin/kill -TERM "$scan_pid" 2>/dev/null
      zmodload zsh/zselect
      while /bin/kill -0 "$scan_pid" 2>/dev/null && (( rounds < 10 )); do
        zselect -t 5
        (( rounds += 1 ))
      done
      /bin/kill -0 "$scan_pid" 2>/dev/null && /bin/kill -KILL "$scan_pid" 2>/dev/null
      /bin/kill -0 "$scan_pid" 2>/dev/null || wait "$scan_pid" 2>/dev/null
    fi
    /bin/rm -f -- "$work/items" "$work/error"
    /bin/rmdir "$work" 2>/dev/null
  }
  trap 'jobs_clean_cache_scan_cleanup' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  /usr/bin/mkfifo "$work/items" || return 1
  : > "$output" || return 1
  /usr/bin/find -P -x "$target" -print0 > "$work/items" 2> "$work/error" &
  scan_pid=$!
  exec {scan_fd}< "$work/items" || return 1
  while :; do
    (( SECONDS < deadline && count < 10000 )) || { print -u2 -r -- '检查超过5秒或10000项预算，整项保留。'; return 2; }
    entry=""
    read_code=0
    IFS= read -r -d '' -t 1 entry <&$scan_fd || read_code=$?
    if (( read_code != 0 )); then
      if /bin/kill -0 "$scan_pid" 2>/dev/null; then
        print -u2 -r -- '候选枚举未能及时完整返回，整项保留。'
        return 2
      fi
      [[ -z "$entry" ]] || { print -u2 -r -- '候选枚举返回不完整路径，整项保留。'; return 2; }
      break
    fi
    (( count += 1 ))
    [[ "$entry" == "$target" || "$entry" == "$target/"* ]] || return 2
    relative="${entry#$target}"
    (( ${#${(s:/:)relative}} <= 64 )) || { print -u2 -r -- '候选超过64层检查深度，整项保留。'; return 2; }
    [[ ! -L "$entry" ]] || { print -u2 -r -- "包含符号链接，整项保留：${(q)entry}"; return 2; }
    [[ -O "$entry" && -r "$entry" && -w "$entry" ]] || { print -u2 -r -- "存在非本人所有或不可读写内容，整项保留：${(q)entry}"; return 2; }
    if [[ -d "$entry" ]]; then
      [[ -x "$entry" ]] || { print -u2 -r -- "目录不可遍历，整项保留：${(q)entry}"; return 2; }
    elif [[ ! -f "$entry" ]]; then
      print -u2 -r -- "存在特殊文件，整项保留：${(q)entry}"
      return 2
    fi
    case "${entry:t}" in
      .git|.hg|.svn|go.mod|go.sum|Cargo.toml|Cargo.lock|package.json|package-lock.json|pnpm-lock.yaml|yarn.lock|pyvenv.cfg|.venv|venv|conda-meta|pyproject.toml|requirements.txt|Pipfile|SDKSettings.plist|go.work|Go.work|site-packages|node_modules|Podfile|Package.swift|pubspec.yaml|package.xml|source.properties|CMakeLists.txt)
        print -u2 -r -- "识别到源码、依赖或SDK标记，交由所属工具管理：${(q)entry}"
        return 2
        ;;
    esac
    metadata="$(/usr/bin/stat -f '%d|%i|%Lp|%u|%f|%HT|%z|%Fm|%Fc' "$entry" 2>/dev/null)" || { print -u2 -r -- "元数据无法完整读取，整项保留：${(q)entry}"; return 2; }
    fields=("${(@s:|:)metadata}")
    [[ ${#fields} == 9 && "${fields[1]}" == "$expected_device" && "${fields[5]}" == <-> ]] || { print -u2 -r -- "存在异盘或带文件系统保护标记的内容，整项保留：${(q)entry}"; return 2; }
    # 只排除不可变或仅追加标记；hidden/nodump/compressed 不等于禁止删除。
    (( (fields[5] & 0x60006) == 0 )) || { print -u2 -r -- "存在不可变或仅追加保护，整项保留：${(q)entry}"; return 2; }
    # 部分删除会改变父目录时间；目录只冻结身份，文件同时冻结大小和修改时间。
    if [[ -d "$entry" ]]; then
      metadata="${(j:|:)fields[1,6]}"
    fi
    printf '%s\0%s\0' "$entry" "$metadata" >> "$output" || return 1
  done
  wait "$scan_pid" || scan_code=$?
  scan_pid=""
  if (( scan_code != 0 )); then
    /bin/cat "$work/error" >&2
    print -u2 -r -- '候选无法完整枚举，整项保留。'
    return 2
  fi
  (( count > 0 )) || return 2
  return 0
)
# 全选只展开本轮冻结候选；未勾选时确认当前行，默认行仍是跳过。
jobs_clean_cache_select_candidates() {
  emulate -L zsh
  local rows="$1" picker="" picked="" line="" key="" code=0 all_selected=0 skip_selected=0
  local -a selected=()
  [[ -t 0 && -t 2 ]] || { print -u2 -r -- '用户缓存选择需要交互终端，未删除。'; return 130; }
  picker="$(command -v fzf 2>/dev/null)" || { print -u2 -r -- '缺少健康的fzf，用户缓存未删除。'; return 1; }
  "$picker" --version >/dev/null 2>&1 || return 1
  picked="$(FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE='' "$picker" --multi --no-sort --reverse --delimiter=$'\t' --with-nth=2.. \
    --bind='load:pos(2),up:up,down:down,tab:down,shift-tab:up,enter:toggle,space:accept-non-empty,esc:abort,left:abort' \
    --header='用户缓存：首行全选、次行跳过（默认）；↑↓/Tab移动；Enter勾选/取消；Space确认，未勾选则取当前行；Esc/←取消' \
    --prompt='用户缓存 > ' < "$rows")" || code=$?
  (( code == 0 )) || return "$code"
  [[ -n "$picked" && "$picked" != __EMPTY__ && "$picked" != __EMPTY__$'\n'* ]] || return 0
  while IFS= read -r line; do
    key="${line%%$'\t'*}"
    case "$key" in
      ALL) all_selected=1 ;;
      SKIP) skip_selected=1 ;;
      <->) selected+=("$key") ;;
      *) return 1 ;;
    esac
  done <<< "$picked"
  (( skip_selected == 0 )) || return 0
  if (( all_selected )); then
    while IFS=$'\t' read -r key line; do
      [[ "$key" == <-> ]] && print -r -- "$key"
    done < "$rows"
  elif (( ${#selected} )); then
    print -rl -- "${selected[@]}"
  fi
  return 0
}
# 明确列出通过检查的准确范围；非空输入跳过，输入结束传播取消。
jobs_clean_cache_confirm_selected() {
  emulate -L zsh
  local answer=""
  [[ -t 0 ]] || return 130
  IFS= builtin read -r "?$(jobs_prompt_render '确认仅删除以上已选用户缓存？[回车确认 / 任意字符后回车跳过用户缓存]：')" answer || return 130
  [[ -z "$answer" ]] || return 2
  return 0
}
# 检查当前树是首次授权树的子集，重试不能接纳新建或被替换的成员。
jobs_clean_cache_matches_original() {
  local snapshot="$1" entry="" metadata=""
  while IFS= read -r -d '' entry && IFS= read -r -d '' metadata; do
    [[ -n "${JOBS_CLEAN_CACHE_ORIGINAL[$entry]:-}" && "${JOBS_CLEAN_CACHE_ORIGINAL[$entry]}" == "$metadata" ]] || return 1
  done < "$snapshot"
  return 0
}
# 仅删除授权快照中的原成员；目录仅rmdir，新生成内容不会被递归删除。
jobs_clean_cache_remove_snapshot() {
  emulate -L zsh
  local target="$1" snapshot="$2" entry="" expected="" metadata="" current=""
  local -a entries=() identities=() fields=()
  local -i position=0 result=0 code=0
  while IFS= read -r -d '' entry && IFS= read -r -d '' expected; do
    entries+=("$entry")
    identities+=("$expected")
  done < "$snapshot"
  for (( position=${#entries}; position >= 1; position-- )); do
    entry="${entries[$position]}"
    [[ "$entry" == "$target" || "$entry" == "$target/"* ]] || return 1
    [[ -e "$entry" || -L "$entry" ]] || continue
    if ! jobs_disk_clean_reliable_path "$entry" ||
       [[ "$(/usr/bin/stat -f '%d:%i' "$target" 2>/dev/null)" != "${JOBS_CLEAN_CACHE_PENDING[$target]}" ]]; then
      print -u2 -r -- "删除前路径身份变化，保留未完成成员：${(q)entry}"
      return 1
    fi
    metadata="$(/usr/bin/stat -f '%d|%i|%Lp|%u|%f|%HT|%z|%Fm|%Fc' "$entry" 2>/dev/null)" || return 1
    fields=("${(@s:|:)metadata}")
    [[ ! -d "$entry" ]] || metadata="${(j:|:)fields[1,6]}"
    [[ "$metadata" == "${identities[$position]}" ]] || { print -u2 -r -- "删除前成员已被替换或修改，保留：${(q)entry}"; return 1; }
    if [[ -d "$entry" ]]; then
      code=0; /bin/rmdir -- "$entry" || code=$?
    elif [[ -f "$entry" && ! -L "$entry" ]]; then
      code=0; /bin/rm -f -- "$entry" || code=$?
    else
      print -u2 -r -- "删除前成员类型变化，保留：${(q)entry}"
      return 1
    fi
    case "$code" in
      129|130|143) return "$code" ;;
      0) ;;
      *) result=1 ;;
    esac
  done
  return "$result"
}
# 先选择再检查并确认缓存；只重试已授权树中尚未完成的原候选。
jobs_clean_user_caches() {
  emulate -L zsh
  setopt PIPE_FAIL
  (( JOBS_CLEAN_CONFIRMED == 1 )) || return 1
  local cache_dir="$HOME/Library/Caches" item="" plan="" cache_id="" work="" selected="" index="" entry="" metadata=""
  local -i removed=0 failed=0 protected=0 count=0 code=0 first_plan=0
  local -A candidates=() eligible=()
  if (( ! ${+JOBS_CLEAN_CACHE_PLAN_READY} )); then
    local -i JOBS_CLEAN_CACHE_PLAN_READY=0
    local JOBS_CLEAN_CACHE_ROOT_ID=""
    local -A JOBS_CLEAN_CACHE_PENDING=() JOBS_CLEAN_CACHE_ORIGINAL=()
  fi
  (( JOBS_CLEAN_CACHE_PLAN_READY >= 0 )) || { warn_echo '首次缓存计划未完成，未扩大候选；请排障后重新运行 clean。'; return 1; }
  [[ -e "$cache_dir" || -L "$cache_dir" ]] || { info_echo '用户缓存目录不存在，跳过。'; return 0; }
  jobs_disk_clean_reliable_path "$cache_dir" && [[ -d "$cache_dir" ]] || { warn_echo '用户缓存入口不可靠，保留。'; return 1; }
  cache_id="$(/usr/bin/stat -f '%d:%i' "$cache_dir")" || return 1
  work="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/JobsDiskSpaceCachePlan.XXXXXXXX")" || return 1
  {
    if (( JOBS_CLEAN_CACHE_PLAN_READY == 0 )); then
      first_plan=1
      JOBS_CLEAN_CACHE_PLAN_READY=-1
      plan="$work/items"
      if ! jobs_clean_run_stderr_logged /usr/bin/find "$cache_dir" -mindepth 1 -maxdepth 1 -print0 > "$plan"; then
        error_echo '缓存完整枚举失败，未删除缓存。'
        return 1
      fi
      printf 'ALL\t全选用户缓存（选择后检查）\nSKIP\t跳过用户缓存清理（默认）\n' > "$work/rows" || return 1
      while IFS= read -r -d '' item; do
        (( count += 1 ))
        candidates[$count]="$item"
        JOBS_CLEAN_CACHE_PENDING[$item]="$(/usr/bin/stat -f '%d:%i' "$item" 2>/dev/null)"
        print -r -- "$count"$'\t'"${(q)${item:t}}（选择后检查）" >> "$work/rows" || return 1
      done < "$plan"
      JOBS_CLEAN_CACHE_ROOT_ID="$cache_id"
      JOBS_CLEAN_CACHE_PLAN_READY=1
      (( count )) || { info_echo '用户缓存无候选，已跳过。'; return 0; }
      jobs_clean_cache_select_candidates "$work/rows" > "$work/selected" || code=$?
      if (( code != 0 )); then
        JOBS_CLEAN_CACHE_PENDING=()
        JOBS_CLEAN_CACHE_PLAN_READY=-1
        return "$code"
      fi
      while IFS= read -r index; do
        [[ "$index" == <-> && -n "${candidates[$index]:-}" ]] || { JOBS_CLEAN_CACHE_PENDING=(); JOBS_CLEAN_CACHE_PLAN_READY=-1; return 1; }
        eligible[${candidates[$index]}]=1
      done < "$work/selected"
      for item in "${(@k)JOBS_CLEAN_CACHE_PENDING}"; do
        [[ -n "${eligible[$item]:-}" ]] || unset "JOBS_CLEAN_CACHE_PENDING[$item]"
      done
      (( ${#JOBS_CLEAN_CACHE_PENDING} )) || { info_echo '用户缓存未勾选或已跳过，未删除。'; return 0; }
    fi
    [[ "$cache_id" == "$JOBS_CLEAN_CACHE_ROOT_ID" ]] || { warn_echo '缓存根目录已变化，保留原失败清单，不采纳新目录。'; return 1; }
    for item in "${(@k)JOBS_CLEAN_CACHE_PENDING}"; do
      if ! jobs_disk_clean_reliable_path "$cache_dir" ||
         [[ "$(/usr/bin/stat -f '%d:%i' "$cache_dir" 2>/dev/null)" != "$JOBS_CLEAN_CACHE_ROOT_ID" || "${item:h}" != "$cache_dir" ]]; then
        warn_echo "缓存入口或候选已变化，停止当前缓存清理：$item"
        ((failed += 1))
        break
      fi
      if [[ ! -e "$item" && ! -L "$item" ]]; then
        unset "JOBS_CLEAN_CACHE_PENDING[$item]"
        continue
      fi
      if [[ -z "${JOBS_CLEAN_CACHE_PENDING[$item]:-}" ||
            "$(/usr/bin/stat -f '%d:%i' "$item" 2>/dev/null)" != "${JOBS_CLEAN_CACHE_PENDING[$item]}" ]]; then
        warn_echo "缓存候选已变化，保留且不采纳重建项：$item"
        ((failed += 1))
        continue
      fi
      code=0
      jobs_clean_run_logged jobs_clean_cache_snapshot "$item" "${cache_id%%:*}" "$work/snapshot" || code=$?
      case "$code" in
        129|130|143) return "$code" ;;
        0) ;;
        *) warn_echo "保护缓存候选，未进入删除或重试：${(q)item}"; unset "JOBS_CLEAN_CACHE_PENDING[$item]"; ((protected += 1)); continue ;;
      esac
      if (( first_plan )); then
        while IFS= read -r -d '' entry && IFS= read -r -d '' metadata; do
          JOBS_CLEAN_CACHE_ORIGINAL[$entry]="$metadata"
        done < "$work/snapshot"
      elif ! jobs_clean_cache_matches_original "$work/snapshot"; then
        warn_echo "候选出现未授权的新建、替换或修改内容，整项保留：${(q)item}"
        unset "JOBS_CLEAN_CACHE_PENDING[$item]"
        ((protected += 1))
      fi
    done
    if (( first_plan && ${#JOBS_CLEAN_CACHE_PENDING} )); then
      note_echo '以下是本次已选且通过检查的准确范围；删除后不可从废纸篓恢复：'
      for item in "${(@ok)JOBS_CLEAN_CACHE_PENDING}"; do
        note_echo "${(q)item}"
      done
      code=0
      jobs_clean_cache_confirm_selected || code=$?
      if (( code != 0 )); then
        JOBS_CLEAN_CACHE_PENDING=()
        case "$code" in
          129|130|143) return "$code" ;;
          2) info_echo '已跳过用户缓存清理，未删除。'; return 0 ;;
          *) JOBS_CLEAN_CACHE_PLAN_READY=-1; return "$code" ;;
        esac
      fi
    fi
    for item in "${(@k)JOBS_CLEAN_CACHE_PENDING}"; do
      code=0
      jobs_clean_run_logged jobs_clean_cache_snapshot "$item" "${cache_id%%:*}" "$work/snapshot" || code=$?
      case "$code" in
        129|130|143) return "$code" ;;
        0) ;;
        *) warn_echo "删除前检查未通过，整项保留：${(q)item}"; unset "JOBS_CLEAN_CACHE_PENDING[$item]"; ((protected += 1)); continue ;;
      esac
      if ! jobs_disk_clean_reliable_path "$cache_dir" ||
         [[ "$(/usr/bin/stat -f '%d:%i' "$cache_dir" 2>/dev/null)" != "$JOBS_CLEAN_CACHE_ROOT_ID" ||
            "$(/usr/bin/stat -f '%d:%i' "$item" 2>/dev/null)" != "${JOBS_CLEAN_CACHE_PENDING[$item]}" ]] ||
         ! jobs_clean_cache_matches_original "$work/snapshot"; then
        warn_echo "确认后候选已变化，整项保留：${(q)item}"
        unset "JOBS_CLEAN_CACHE_PENDING[$item]"
        ((protected += 1))
        continue
      fi
      code=0
      jobs_clean_run_logged jobs_clean_cache_remove_snapshot "$item" "$work/snapshot" || code=$?
      case "$code" in
        129|130|143) return "$code" ;;
        0) ((removed += 1)); unset "JOBS_CLEAN_CACHE_PENDING[$item]" ;;
        *) warn_echo "缓存删除失败，继续其它项目：$item"; ((failed += 1)) ;;
      esac
    done
    info_echo "用户缓存清理：已删除 $removed 项，保护保留 $protected 项，失败 $failed 项；未选项及Caches目录保留。"
    (( failed == 0 ))
  } always {
    /bin/rm -f -- "$work/items" "$work/rows" "$work/selected" "$work/snapshot"
    /bin/rmdir -- "$work" 2>/dev/null
  }
}
# 限时调用当前 Xcode 的 simctl，固定设备集，取消或超时只结束本次客户端。
jobs_clean_simctl() (
  local devices_dir="$1" simctl_bin="" task_pid="" result=0 deadline=$((SECONDS + 30))
  shift
  simctl_bin="$(/usr/bin/xcrun --find simctl 2>/dev/null)" || return 127
  trap '[[ -z "$task_pid" ]] || /bin/kill -KILL "$task_pid" 2>/dev/null' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  "$simctl_bin" --set "$devices_dir" "$@" &
  task_pid=$!
  while /bin/kill -0 "$task_pid" 2>/dev/null; do
    if (( SECONDS >= deadline )); then
      /bin/kill -KILL "$task_pid" 2>/dev/null || true
      wait "$task_pid" 2>/dev/null || true
      task_pid=""
      print -u2 -r -- 'simctl 操作超过 30 秒，已停止本次客户端。'
      return 124
    fi
    /bin/sleep 0.1
  done
  wait "$task_pid" || result=$?
  task_pid=""
  return "$result"
)
# 完整校验 JSON 后才输出 iOS UUID 与状态，避免错误输出或外部路径成为删除参数。
jobs_clean_simulator_rows() {
  /usr/bin/osascript -l JavaScript - "$1" "$2" <<'JOBS_SIMULATOR_JSON'
ObjC.import('Foundation');
function run(argv) {
  const raw = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null);
  const payload = JSON.parse(ObjC.unwrap(raw));
  if (!payload || !payload.devices || typeof payload.devices !== 'object' || Array.isArray(payload.devices)) {
    throw new Error('缺少 devices 对象');
  }
  const rows = [], seen = {};
  Object.keys(payload.devices).forEach(function(runtime) {
    if (!Array.isArray(payload.devices[runtime])) throw new Error('设备清单不是数组');
    if (!/^com\.apple\.CoreSimulator\.SimRuntime\.iOS-/.test(runtime)) return;
    payload.devices[runtime].forEach(function(device) {
      if (!device || typeof device.udid !== 'string' ||
          !/^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/i.test(device.udid) ||
          typeof device.state !== 'string' || !device.state || /[\x00-\x1f\x7f]/.test(device.state) ||
          device.dataPath !== argv[1] + '/' + device.udid + '/data' || seen[device.udid.toUpperCase()]) {
        throw new Error('设备 UUID、状态或 dataPath 不可靠');
      }
      seen[device.udid.toUpperCase()] = true;
      rows.push(device.udid + '\t' + device.state);
    });
  });
  return rows.join('\n');
}
JOBS_SIMULATOR_JSON
}
# 0 表示目录或定义确实缺失；1 保留现有定义；2 表示权限、链接或路径不可靠。
jobs_clean_simulator_missing() {
  emulate -L zsh
  local devices_dir="$1" uuid="$2" current="${HOME:A}" component="" entry=""
  [[ -n "$HOME" && "$HOME" == /* && "$current" != / && -d "$current" && -r "$current" && -x "$current" ]] || return 2
  [[ "$devices_dir" == "$current/Library/Developer/CoreSimulator/Devices" ]] || return 2
  [[ "$uuid" =~ '^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$' ]] || return 2
  for component in Library Developer CoreSimulator Devices "$uuid"; do
    current+="/$component"
    [[ ! -L "$current" ]] || return 2
    [[ -e "$current" ]] || return 0
    [[ -d "$current" && -r "$current" && -x "$current" ]] || return 2
  done
  for entry in "$current/device.plist" "$current/data"; do
    [[ ! -L "$entry" ]] || return 2
  done
  if [[ -e "$current/device.plist" ]]; then
    [[ -f "$current/device.plist" && -r "$current/device.plist" ]] || return 2
    # 保留仍有定义的设备，data 可由系统初始化或重新生成。
    [[ ! -e "$current/data" || ( -d "$current/data" && -r "$current/data" && -x "$current/data" ) ]] || return 2
    return 1
  fi
  [[ ! -e "$current/data" || ( -d "$current/data" && -r "$current/data" && -x "$current/data" ) ]] || return 2
  return 0
}
# 写操作前重新查询同一 UUID；恢复、状态变化或已消失均保留，不沿用旧快照。
jobs_clean_simulator_recheck() {
  local devices_dir="$1" uuid="$2" expected_state="$3" snapshot="$4" check_result=0
  jobs_clean_run_stderr_logged jobs_clean_simctl "$devices_dir" list devices --json > "$snapshot" || { local query_code=$?; case "$query_code" in 129|130|143) return "$query_code" ;; esac; return 2; }
  jobs_clean_run_stderr_logged jobs_clean_simulator_rows "$snapshot" "$devices_dir" > "$snapshot.rows" || return 2
  jobs_clean_simulator_missing "$devices_dir" "$uuid" || check_result=$?
  (( check_result == 0 )) || return "$check_result"
  # 整台目录已不存在时没有可备份的活数据，允许系统直接注销关闭卡住的同一设备。
  if [[ "$expected_state" == missing-directory ]]; then
    [[ ! -e "$devices_dir/$uuid" && ! -L "$devices_dir/$uuid" ]] || return 1
    /usr/bin/grep -Fxq -- "$uuid"$'\tShutdown' "$snapshot.rows" && return 0
    /usr/bin/grep -Fxq -- "$uuid"$'\tBooted' "$snapshot.rows" && return 0
    /usr/bin/grep -Fxq -- "$uuid"$'\tShutting Down' "$snapshot.rows" && return 0
    /usr/bin/grep -q -- "^$uuid"$'\t' "$snapshot.rows" && return 2
    return 1
  fi
  /usr/bin/grep -Fxq -- "$uuid"$'\t'"$expected_state" "$snapshot.rows" && return 0
  # 关闭命令假成功时不能把仍在运行的损坏设备当作清理完成。
  if [[ "$expected_state" == Shutdown ]]; then
    /usr/bin/grep -Fxq -- "$uuid"$'\tBooted' "$snapshot.rows" && return 2
    /usr/bin/grep -Fxq -- "$uuid"$'\tShutting Down' "$snapshot.rows" && return 2
  fi
  return 1
}
# 仅注销定义或目录已丢失的 iOS 设备；残留数据备份验证成功后才交给 simctl 删除。
jobs_clean_orphaned_simulators() {
  emulate -L zsh
  (( JOBS_CLEAN_CONFIRMED == 1 )) || return 1
  local devices_dir="${HOME:A}/Library/Developer/CoreSimulator/Devices" scan_dir="" backup_dir=""
  local uuid="" device_state="" recheck_state="" entry="" result=0 query_result=0 shutdown_result=0
  local -i candidates=0 removed=0 failed=0 skipped=0
  if jobs_xcode_managed_path "$devices_dir" &&
     { [[ ! "${JOBS_XCODE_ORPHAN_UUID:-}" =~ '^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$' ]] || (( ${+functions[jobs_xcode_legacy_device_rows]} != 1 )); }; then
    info_echo '失效模拟器登记请在先行 Simulators 组选择；旧清理保留未选设备。'
    return 0
  fi
  scan_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/JobsClean-SimulatorScan.XXXXXXXX")" || return 1
  jobs_clean_run_stderr_logged jobs_clean_simctl "$devices_dir" list devices --json > "$scan_dir/before.json" || query_result=$?
  case "$query_result" in 129|130|143) return "$query_result" ;; esac
  if (( query_result == 127 )); then
    info_echo '未安装可用的 Xcode simctl，跳过模拟器登记清理。'
    return 0
  fi
  if (( query_result != 0 )) || ! jobs_clean_run_stderr_logged jobs_clean_simulator_rows "$scan_dir/before.json" "$devices_dir" > "$scan_dir/before.rows"; then
    warn_echo "模拟器清单读取失败，未注销设备；诊断：$scan_dir"
    return 1
  fi
  info_echo '正在检查 CoreSimulator 中实体已缺失的 iOS 模拟器登记…'
  while IFS=$'\t' read -r uuid device_state; do
    [[ -n "$uuid" ]] || continue
    result=0
    jobs_clean_simulator_missing "$devices_dir" "$uuid" || result=$?
    (( result != 1 )) || continue
    if (( result == 2 )) || [[ "$device_state" != Shutdown && "$device_state" != Booted && "$device_state" != 'Shutting Down' ]]; then
      ((skipped += 1))
      (( result != 2 )) || ((failed += 1))
      warn_echo "设备路径不可靠或正在转换状态，保留：$uuid ($device_state)"
      continue
    fi
    entry="$devices_dir/$uuid"
    recheck_state="$device_state"
    if [[ ! -e "$entry" && ! -L "$entry" ]]; then
      recheck_state=missing-directory
    elif [[ "$device_state" == 'Shutting Down' ]]; then
      ((skipped += 1))
      ((failed += 1))
      warn_echo "设备仍在关闭且有残留目录，保留数据；关闭完成后可重试：$uuid"
      continue
    fi
    ((candidates += 1))
    result=0
    jobs_clean_simulator_recheck "$devices_dir" "$uuid" "$recheck_state" "$scan_dir/$uuid.precheck.json" || result=$?
    case "$result" in 129|130|143) return "$result" ;; esac
    if (( result != 0 )); then
      ((skipped += 1))
      (( result != 2 )) || ((failed += 1))
      warn_echo "设备已变化或无法复检，保留：$uuid"
      continue
    fi
    if [[ -z "$backup_dir" ]]; then
      if [[ -L "$HOME/.Trash" || ! -d "$HOME/.Trash" || ! -w "$HOME/.Trash" ]] ||
         ! backup_dir="$(/usr/bin/mktemp -d "$HOME/.Trash/JobsClean-SimulatorOrphans-XXXXXXXX")" ||
         ! /bin/cp "$scan_dir/before.json" "$backup_dir/inventory-before.json"; then
        error_echo '模拟器清理备份不可用，已停止注销。'
        return 1
      fi
      note_echo "模拟器清理备份：$backup_dir"
    fi
    if [[ "$device_state" == Booted ]]; then
      shutdown_result=0
      jobs_clean_run_logged jobs_clean_simctl "$devices_dir" shutdown "$uuid" || shutdown_result=$?
      case "$shutdown_result" in
        129|130|143) return "$shutdown_result" ;;
      esac
      if (( shutdown_result != 0 )) && [[ "$recheck_state" != missing-directory ]]; then
        ((failed += 1))
        warn_echo "损坏设备关闭失败，保留：$uuid"
        continue
      fi
      if (( shutdown_result != 0 )); then
        warn_echo "设备关闭未完成（退出码 $shutdown_result）；复检实体目录仍缺失后尝试精确注销：$uuid"
      fi
      [[ "$recheck_state" == missing-directory ]] || recheck_state=Shutdown
    fi
    result=0
    jobs_clean_simulator_recheck "$devices_dir" "$uuid" "$recheck_state" "$scan_dir/$uuid.shutdown.json" || result=$?
    case "$result" in 129|130|143) return "$result" ;; esac
    if (( result != 0 )); then
      ((skipped += 1))
      (( result != 2 )) || ((failed += 1))
      warn_echo "关闭后设备已变化或无法复检，保留：$uuid"
      continue
    fi
    if [[ -d "$entry" ]]; then
      if ! jobs_clean_run_logged /usr/bin/ditto "$entry" "$backup_dir/$uuid" ||
         ! jobs_clean_run_logged /usr/bin/diff -qr "$entry" "$backup_dir/$uuid"; then
        ((failed += 1))
        warn_echo "残留数据备份校验失败，保留：$uuid"
        continue
      fi
    fi
    result=0
    jobs_clean_simulator_recheck "$devices_dir" "$uuid" "$recheck_state" "$scan_dir/$uuid.delete.json" || result=$?
    case "$result" in 129|130|143) return "$result" ;; esac
    if (( result != 0 )) || { [[ -d "$entry" ]] && ! jobs_clean_run_logged /usr/bin/diff -qr "$entry" "$backup_dir/$uuid"; }; then
      ((skipped += 1))
      (( result != 2 )) || ((failed += 1))
      warn_echo "删除前设备或数据已变化，保留：$uuid"
      continue
    fi
result=0
jobs_clean_run_logged jobs_clean_simctl "$devices_dir" delete "$uuid" || result=$?
case "$result" in 129|130|143) return "$result" ;; esac
if (( result == 0 )); then
  jobs_clean_run_stderr_logged jobs_clean_simctl "$devices_dir" list devices --json > "$scan_dir/$uuid.after.json" || result=$?
  case "$result" in 129|130|143) return "$result" ;; esac
fi
if (( result != 0 )) || ! jobs_clean_run_stderr_logged jobs_clean_simulator_rows "$scan_dir/$uuid.after.json" "$devices_dir" > "$scan_dir/$uuid.after.rows" || /usr/bin/grep -q -- "^$uuid"$'\t' "$scan_dir/$uuid.after.rows"; then
  ((failed += 1))
  warn_echo "设备注销失败或登记仍存在：$uuid；详情：$scan_dir"
  continue
fi
    ((removed += 1))
    gray_echo "已注销实体缺失的模拟器：$uuid"
  done < "$scan_dir/before.rows"
  info_echo "模拟器登记检查：候选 $candidates，已注销 $removed，保留 $skipped，失败 $failed；诊断：$scan_dir"
  (( failed == 0 ))
}
# 顺手清理 Homebrew 旧版本包和缓存；Homebrew 不存在或清理失败都不阻断 clean。
jobs_clean_homebrew_cleanup() {
  emulate -L zsh
  setopt PIPE_FAIL

  local brew_bin=""
  brew_bin="$(jobs_brew_find)" || return 0

  (( JOBS_CLEAN_CONFIRMED == 1 )) || return 1

  print -P "%F{blue}ℹ 正在执行 brew cleanup...%f"
if HOMEBREW_NO_AUTO_UPDATE=1 "$brew_bin" cleanup 2>&1 | jobs_prompt_tee "$LOG_FILE"; then
  success_echo 'Homebrew 缓存清理完成。'
else
  warn_echo 'Homebrew cleanup 失败；保留失败状态，继续其它清理。'
  return 1
fi
}
# 判断路径是否属于可重新生成的非 macOS Apple 平台构建 App。
jobs_clean_is_non_macos_build_product_app_path() {
  emulate -L zsh

  local app_path="$1"
  case "$app_path" in
    */[Bb]uild/Products/*-iphone*/*.app|*/[Bb]uild/Products/*-appletv*/*.app|*/[Bb]uild/Products/*-watch*/*.app|*/[Bb]uild/Products/*-xr*/*.app)
      return 0
      ;;
    */[Bb]uild/*-iphone*/*.app|*/[Bb]uild/*-appletv*/*.app|*/[Bb]uild/*-watch*/*.app|*/[Bb]uild/*-xr*/*.app)
      return 0
      ;;
  esac
  return 1
}
# 判断 LaunchServices 路径是否属于无法在 macOS 直接打开的 Apple 开发 App。
jobs_clean_is_non_macos_development_app_path() {
  emulate -L zsh

  local app_path="$1"
  case "$app_path" in
    "$HOME/Library/Developer/CoreSimulator/Devices/"*/data/Containers/Bundle/Application/*/*.app)
      return 0
      ;;
  esac
  jobs_clean_is_non_macos_build_product_app_path "$app_path"
}
# 将 Spotlight 直接收录的非 macOS 构建 App 移入废纸篓，从文件源头清除图标。
jobs_clean_move_indexed_build_apps_to_trash() {
  emulate -L zsh
  setopt NO_NOMATCH

  command -v mdfind >/dev/null 2>&1 || {
    warn_echo "Spotlight 查询工具不可用，已跳过构建 App 废纸篓清理。"
    return 0
  }
  [[ -d "$HOME/.Trash" ]] || {
    warn_echo "废纸篓目录不可用，已跳过构建 App 文件清理：$HOME/.Trash"
    return 0
  }

  local app_path="" app_id="" spotlight_snapshot=""
  local relative_path=""
  local destination=""
  local destination_parent=""
  local trash_root=""
  local -i candidate_count=0
  local -i moved_count=0
  local -i failed_count=0
  local -i skipped_count=0
  typeset -A seen_paths=()

  (( JOBS_CLEAN_CONFIRMED == 1 )) || return 1
  spotlight_snapshot="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/JobsDiskSpaceSpotlight.XXXXXXXX")" || return 1
  jobs_clean_run_stderr_logged mdfind -0 -onlyin "$HOME" 'kMDItemContentType == "com.apple.application-bundle"' > "$spotlight_snapshot" || { /bin/rm -f -- "$spotlight_snapshot"; return 1; }
  info_echo "正在检查 Spotlight 直接收录的非 macOS 构建 App..."
  while IFS= read -r -d '' app_path; do
    jobs_clean_is_non_macos_build_product_app_path "$app_path" || continue
    jobs_xcode_managed_path "$app_path" && continue
    [[ "$app_path" == "$HOME/"* ]] || {
      ((skipped_count++))
      warn_echo "已跳过用户目录以外的构建 App：$app_path"
      continue
    }
    [[ "$app_path" != "$HOME/.Trash/"* ]] || continue
    jobs_disk_clean_reliable_path "$app_path" && [[ -d "$app_path" ]] || { warn_echo "构建 App 路径不可靠，保留：$app_path"; continue; }
    app_id="$(/usr/bin/stat -f '%d:%i' "$app_path")" || continue
    [[ -z "${seen_paths[$app_path]:-}" ]] || continue
    seen_paths[$app_path]=1
    ((candidate_count++))

    if [[ -z "$trash_root" ]]; then
      jobs_disk_clean_reliable_path "$HOME/.Trash" || return 1
      if ! trash_root="$(/usr/bin/mktemp -d "$HOME/.Trash/JobsDiskSpaceCleanup-DevelopmentApps.XXXXXXXX")"; then
        error_echo "无法创建可恢复清理目录：$trash_root"
        return 1
      fi
    fi

    relative_path="${app_path#/}"
    destination="$trash_root/$relative_path"
    destination_parent="${destination:h}"
    if ! jobs_clean_run_logged mkdir -p "$destination_parent"; then
      ((failed_count++))
      warn_echo "无法创建废纸篓目标目录：$destination_parent"
      continue
    fi
    if [[ -x "$LAUNCH_SERVICES_REGISTER" ]]; then
      jobs_clean_run_logged "$LAUNCH_SERVICES_REGISTER" -u "$app_path" || true
    fi
    jobs_disk_clean_reliable_path "$app_path" && [[ "$(/usr/bin/stat -f '%d:%i' "$app_path")" == "$app_id" && ! -e "$destination" && ! -L "$destination" ]] || { failed_count+=1; continue; }
    if jobs_clean_run_logged /bin/mv -n "$app_path" "$destination" && [[ ! -e "$app_path" && -d "$destination" ]]; then
      ((moved_count++))
      JOBS_CLEAN_MOVED_BUILD_PRODUCTS=1
      JOBS_CLEAN_APPLICATION_INDEX_CHANGED=1
      gray_echo "已移入废纸篓：$app_path"
    else
      ((failed_count++))
      warn_echo "移入废纸篓失败：$app_path"
    fi
  done < "$spotlight_snapshot"
  /bin/rm -f -- "$spotlight_snapshot"

  if (( candidate_count == 0 )); then
    info_echo "Spotlight 中未发现需要移走的非 macOS 构建 App。"
    return 0
  fi
  success_echo "Spotlight 构建 App 清理完成：发现 ${candidate_count} 项，已移入废纸篓 ${moved_count} 项。"
  [[ -z "$trash_root" ]] || note_echo "可恢复目录：$trash_root"
  (( skipped_count == 0 )) || warn_echo "为保护外部路径，已跳过 ${skipped_count} 项。"
  (( failed_count == 0 )) || { warn_echo "其中 ${failed_count} 项移动失败，详情见：$LOG_FILE"; return 1; }
}
# 定向注销非 macOS 构建产物与模拟器 App；模拟器容器中的实体文件保持不动。
jobs_clean_unregister_non_macos_development_apps() {
  emulate -L zsh
  setopt NO_NOMATCH

  [[ -x "$LAUNCH_SERVICES_REGISTER" ]] || {
    warn_echo "LaunchServices 注册工具不可用，已跳过失效 App 图标清理：$LAUNCH_SERVICES_REGISTER"
    return 0
  }

  local line="" registry_snapshot=""
  local app_path=""
  local -i candidate_count=0
  local -i unregistered_count=0
  local -i stale_count=0
  local -i failed_count=0
  typeset -A seen_paths=()

  (( JOBS_CLEAN_CONFIRMED == 1 )) || return 1
  registry_snapshot="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/JobsDiskSpaceRegistry.XXXXXXXX")" || return 1
  jobs_clean_run_stderr_logged "$LAUNCH_SERVICES_REGISTER" -dump > "$registry_snapshot" || { /bin/rm -f -- "$registry_snapshot"; return 1; }
  info_echo "正在检查 LaunchServices 中的非 macOS 构建产物与模拟器 App..."
  while IFS= read -r line; do
    [[ "$line" =~ '^path:[[:space:]]+(.+)[[:space:]]+\(0x[[:xdigit:]]+\)$' ]] || continue
    app_path="${match[1]}"
    jobs_clean_is_non_macos_development_app_path "$app_path" || continue
    jobs_xcode_managed_path "$app_path" && continue
    [[ "$app_path" == "$HOME/"* ]] || continue
    if [[ -e "$app_path" || -L "$app_path" ]]; then jobs_disk_clean_reliable_path "$app_path" || { failed_count+=1; continue; }; fi
    [[ -z "${seen_paths[$app_path]:-}" ]] || continue
    seen_paths[$app_path]=1
    ((candidate_count++))

    if [[ ! -e "$app_path" && ! -L "$app_path" ]]; then
      ((stale_count++))
      continue
    fi
    if jobs_clean_run_logged "$LAUNCH_SERVICES_REGISTER" -u "$app_path"; then
      ((unregistered_count++))
      gray_echo "已注销：$app_path"
    else
      ((failed_count++))
      warn_echo "注销失败：$app_path"
    fi
  done < "$registry_snapshot"
  /bin/rm -f -- "$registry_snapshot"

  if jobs_clean_run_logged "$LAUNCH_SERVICES_REGISTER" -gc; then
    JOBS_CLEAN_APPLICATION_INDEX_CHANGED=1
  else
    warn_echo "LaunchServices 垃圾回收执行失败，已继续后续清理。"
    failed_count+=1
  fi

  if (( candidate_count == 0 )); then
    info_echo "未发现需要注销的非 macOS 开发 App 记录。"
    return 0
  fi
  success_echo "LaunchServices 清理完成：发现 ${candidate_count} 项，已注销 ${unregistered_count} 项，已回收 ${stale_count} 项失效路径。"
  (( failed_count == 0 )) || { warn_echo "其中 ${failed_count} 项注销失败，详情见：$LOG_FILE"; return 1; }
}
# 重启应用列表相关的用户级进程，让失效图标立即从 Spotlight 消失。
jobs_clean_refresh_application_lists() {
  emulate -L zsh

  (( JOBS_CLEAN_APPLICATION_INDEX_CHANGED == 1 )) || return 0
  killall Spotlight >/dev/null 2>&1 || true
  killall corespotlightd >/dev/null 2>&1 || true
  killall sharedfilelistd >/dev/null 2>&1 || true
  killall Dock >/dev/null 2>&1 || true
  JOBS_CLEAN_APPLICATION_INDEX_CHANGED=0
  success_echo "已刷新 Spotlight 和 Dock 应用列表"
}
# 用可读名称展示失败队列，保留函数名供日志定位。
jobs_clean_step_label() {
  case "$1" in
    jobs_disk_clean_history) print -r -- '终端历史／会话' ;;
    jobs_clean_move_indexed_build_apps_to_trash) print -r -- '开发构建 App 移入废纸篓' ;;
    jobs_clean_orphaned_simulators) print -r -- '失效模拟器登记' ;;
    jobs_clean_unregister_non_macos_development_apps) print -r -- '开发 App 登记注销' ;;
    jobs_clean_refresh_application_lists) print -r -- 'Spotlight／Dock 应用列表刷新' ;;
    jobs_clean_homebrew_cleanup) print -r -- 'Homebrew 缓存' ;;
    jobs_clean_user_caches) print -r -- '用户缓存' ;;
    *) print -r -- "$1" ;;
  esac
}
# 只把实际读到的空行视为继续；EOF、无终端和非空输入均保留失败状态。
jobs_clean_confirm_retry() {
  emulate -L zsh
  local answer=""
  [[ -t 0 && -t 1 ]] || { warn_echo '当前无交互终端，未重试失败步骤。'; return 130; }
  note_echo '是否继续清理以上失败步骤？回车继续；输入任意字符后回车结束。'
  IFS= builtin read -r "?$(jobs_prompt_render '是否继续清理失败步骤？[回车继续 / 任意非空输入后回车结束]：')" answer || { warn_echo '输入结束，未重试失败步骤。'; return 130; }
  [[ -z "$answer" ]] || { note_echo '已结束，保留失败步骤与日志。'; return 1; }
}
# 六类功能逐项执行；每轮只保留失败步骤，重试不重跑已成功步骤或前置 Xcode 阶段。
clean() {
  emulate -L zsh
  setopt NO_NOMATCH NULL_GLOB PIPE_FAIL
  (( JOBS_CLEAN_CONFIRMED == 1 )) || return 1
  local result=0 step="" code=0 label=""
  local -i attempt=1
  local -a pending_steps=(jobs_disk_clean_history jobs_clean_move_indexed_build_apps_to_trash jobs_clean_orphaned_simulators jobs_clean_unregister_non_macos_development_apps jobs_clean_refresh_application_lists jobs_clean_homebrew_cleanup jobs_clean_user_caches)
  local -a failed_steps=()
  local -i JOBS_CLEAN_CACHE_PLAN_READY=0
  local JOBS_CLEAN_CACHE_ROOT_ID=""
  local -A JOBS_CLEAN_CACHE_PENDING=() JOBS_CLEAN_CACHE_ORIGINAL=()
  while (( ${#pending_steps} )); do
    failed_steps=()
    info_echo "第 ${attempt} 轮常规清理：${#pending_steps} 个步骤。"
    for step in "${pending_steps[@]}"; do
      code=0
      "$step" || code=$?
      case "$code" in
        129|130|143) return "$code" ;;
        0) ;;
        *)
          failed_steps+=("$step")
          label="$(jobs_clean_step_label "$step")"
          warn_echo "步骤未全部完成：$label（$step，退出码 $code）"
          ;;
      esac
    done
    # 重试移动／注销开发 App 后仍需更新展示结果，不重复已成功的清理步骤。
    if (( JOBS_CLEAN_APPLICATION_INDEX_CHANGED == 1 && ${pending_steps[(Ie)jobs_clean_refresh_application_lists]} == 0 )); then
      code=0
      jobs_clean_refresh_application_lists || code=$?
      case "$code" in
        129|130|143) return "$code" ;;
        0) ;;
        *) failed_steps+=(jobs_clean_refresh_application_lists); warn_echo "应用列表刷新失败（退出码 $code）" ;;
      esac
    fi
    (( ${#failed_steps} )) || break
    warn_echo "清理未全部完成，详情：$LOG_FILE"
    for step in "${failed_steps[@]}"; do
      note_echo "未完成：$(jobs_clean_step_label "$step")"
    done
    code=0
    jobs_clean_confirm_retry || code=$?
    case "$code" in
      129|130|143) return "$code" ;;
      0) ;;
      *) result=1; break ;;
    esac
    pending_steps=("${failed_steps[@]}")
    (( attempt += 1 ))
    note_echo '继续清理失败步骤，日志追加到同一文件。'
  done
  note_echo "清理结束。退出码：$result；日志：$LOG_FILE"
  note_echo '关闭当前右键菜单并重新右键，可读取最新磁盘总余量。'
  return "$result"
}
# BEGIN JOBS_XCODE_CLEANUP_PHASE
# 仅回放本次失败操作追加的诊断，不重复写入日志或显示历史错误。
jobs_xcode_show_log_delta() {
  emulate -L zsh
  setopt PIPE_FAIL
  local jobs_xcode_delta_file="$1" jobs_xcode_delta_start="$2" jobs_xcode_delta_end=""
  [[ -f "$jobs_xcode_delta_file" && "$jobs_xcode_delta_start" == <-> ]] || return 1
  jobs_xcode_delta_end="$(/usr/bin/stat -f '%z' "$jobs_xcode_delta_file")" || return 1
  (( jobs_xcode_delta_end >= jobs_xcode_delta_start )) || return 1
  (( jobs_xcode_delta_end > jobs_xcode_delta_start )) || return 0
  if (( ${+functions[jobs_prompt_filter]} )); then
    /usr/bin/tail -c "+$((jobs_xcode_delta_start + 1))" "$jobs_xcode_delta_file" | jobs_prompt_filter >&2
  else
    /usr/bin/tail -c "+$((jobs_xcode_delta_start + 1))" "$jobs_xcode_delta_file" >&2
  fi
}
# 六组路径按 Cleaner for Xcode 的公开功能核对；此实现独立编写，不依赖该应用。
jobs_xcode_interactive() {
  [[ -t 0 && -t 1 ]]
}
# 仅渲染Xcode询问提示，原始输入、IFS和read退出状态保持。
jobs_xcode_read() {
  local prompt="$1"
  IFS= builtin read -r "?$(jobs_prompt_render "$prompt")" REPLY
}
# 只接受当前用户目录内的真实路径；逐层拒绝符号链接，不能用规范化掩盖越界。
jobs_xcode_safe_path() {
  emulate -L zsh
  local candidate="$1" current="${HOME:A}" part=""
  [[ -n "$HOME" && "$HOME" == /* && -d "$HOME" && ! -L "$HOME" && "$current" != / && "$candidate" == "$current/"* && "$candidate" != *[[:cntrl:]]* ]] || return 1
  local relative="${candidate#"$current/"}"
  for part in "${(@s:/:)relative}"; do
    [[ -n "$part" && "$part" != . && "$part" != .. ]] || return 1
    current+="/$part"
    [[ ! -L "$current" && -e "$current" ]] || return 1
  done
  [[ "${candidate:A}" == "$candidate" && -O "$candidate" ]]
}
# 这些目录只由前置六组的显式选择管理，后续宽范围开发 App 清理不能越过选择。
jobs_xcode_managed_path() {
  local candidate="$1" developer="${HOME:A}/Library/Developer" root=""
  for root in "$developer/Xcode/"{iOS,watchOS,tvOS,macOS}' DeviceSupport' \
      "$developer/CoreSimulator/Devices" "$developer/Xcode/UserData/Previews/Simulator Devices" \
      "$developer/Xcode/DerivedData" "$developer/Xcode/Archives" "$developer/CoreSimulator/Caches/dyld"; do
    [[ "$candidate" == "$root" || "$candidate" == "$root/"* ]] && return 0
  done
  return 1
}
jobs_xcode_identity() {
  /usr/bin/stat -f '%d:%i:%m:%c:%z' "$1"
}
# 元数据清单使用纳秒时间与 inode；不跟随子树链接，异盘挂载与读取失败均保留。
jobs_xcode_manifest() {
  local target="$1" output="$2" device="" raw="$2.raw"
  device="$(/usr/bin/stat -f '%d' "$target")" || return 1
  (builtin cd -P -- "$target" && /usr/bin/find -P . -xdev -exec /usr/bin/stat -f '%d:%i:%.9Fm:%.9Fc:%z:%p:%u:%g:%N' {} +) > "$raw" || return 1
  # 原位改名只改变根目录时间；子树的纳秒时间、大小、权限、属主和 inode 必须不变。
  /usr/bin/awk -F ':' -v OFS=':' -v device="$device" '$1 != device { bad=1 } $NF == "." {$3=0; $4=0} {print} END { exit bad }' "$raw" | LC_ALL=C /usr/bin/sort > "$output" || return 1
  /bin/rm -f -- "$raw"
}
jobs_xcode_add() {
  local group="$1" kind="$2" target="$3" reference="${4:-}" label="${5:-}" identity="" size=""
  jobs_xcode_safe_path "$target" || { print -u2 -r -- "保留链接、越界或不可读路径：$target"; return 0; }
  [[ -d "$target" && -r "$target" && -x "$target" && "${target:t}" != .JobsXcodeClean.* ]] || return 0
  identity="$(jobs_xcode_identity "$target")" || return 1
  print -r -- "正在扫描 $group：${target#"${HOME:A}/"}"
  size="$(/usr/bin/du -sk "$target" 2>/dev/null)" || { print -u2 -r -- "无法完整统计，保留：$target"; return 0; }
  size="${size%%$'\t'*}"
  [[ "$size" == <-> ]] || return 1
  (( xcounter += 1 ))
  jobs_xcode_manifest "$target" "$xwork/manifest-$xcounter" || return 1
  xpaths[$xcounter]="$target"
  xids[$xcounter]="$identity"
  xgroups[$xcounter]="$group"
  xkinds[$xcounter]="$kind"
  xrefs[$xcounter]="$reference"
  xsizes[$xcounter]="$size"
  xlabels[$xcounter]="${label:-${target#"${HOME:A}/"}}"
}
# simctl 每次只操作显式设备集与精确 UUID；不执行 delete all / unavailable / runtime。
jobs_xcode_simctl() (
  local set_path="$1" pid="" result=0 deadline=$((SECONDS + 30))
  shift
  [[ -n "$xsimctl" && -x "$xsimctl" ]] || return 127
  trap '[[ -z "$pid" ]] || /bin/kill -KILL "$pid" 2>/dev/null' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  "$xsimctl" --set "$set_path" "$@" &
  pid=$!
  while /bin/kill -0 "$pid" 2>/dev/null; do
    if (( SECONDS >= deadline )); then
      /bin/kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      pid=""
      return 124
    fi
    /bin/sleep 0.1
  done
  wait "$pid" || result=$?
  pid=""
  return "$result"
)
jobs_xcode_device_rows() {
  /usr/bin/osascript -l JavaScript - "$1" "$2" <<'JOBS_XCODE_JSON'
ObjC.import('Foundation');
function run(argv) {
  const source = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null);
  const payload = JSON.parse(ObjC.unwrap(source));
  if (!payload || !payload.devices || Array.isArray(payload.devices) || typeof payload.devices !== 'object') throw new Error('设备清单无效');
  const rows = [], seen = {};
  Object.keys(payload.devices).forEach(function(runtime) {
    if (!Array.isArray(payload.devices[runtime])) throw new Error('设备分组无效');
    payload.devices[runtime].forEach(function(device) {
      if (!device || typeof device.udid !== 'string' || !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(device.udid) || seen[device.udid] ||
          typeof device.name !== 'string' || /[\x00-\x1f\x7f]/.test(device.name) ||
          !['Shutdown','Booted','Shutting Down'].includes(device.state) ||
          (device.dataPath !== undefined && device.dataPath !== argv[1] + '/' + device.udid + '/data')) throw new Error('设备身份或路径不可靠');
      seen[device.udid] = true;
      rows.push([device.udid, device.state, device.name].join('\t'));
    });
  });
  return rows.join('\n');
}
JOBS_XCODE_JSON
}
jobs_xcode_add_missing_device() {
  local group="$1" set_path="$2" uuid="$3" label="$4" target="$2/$3"
  jobs_xcode_safe_path "$set_path" || return 1
  [[ ! -e "$target" && ! -L "$target" ]] || return 1
  (( xcounter += 1 ))
  xpaths[$xcounter]="$target"
  xids[$xcounter]=missing
  xgroups[$xcounter]="$group"
  xkinds[$xcounter]=orphan
  xrefs[$xcounter]="$uuid"
  xsizes[$xcounter]=0
  xlabels[$xcounter]="$label / $uuid [实体缺失的残留登记]"
}
jobs_xcode_scan_devices() {
  local group="$1" set_path="$2" uuid="" state="" name="" code=0 predicate=0 kind=""
  [[ -d "$set_path" ]] || return 0
  jobs_xcode_safe_path "$set_path" || return 1
  [[ -n "$xsimctl" ]] || { print -r -- "$group：simctl 不可用，保留此组。"; return 0; }
  jobs_xcode_simctl "$set_path" list devices --json > "$xwork/devices.json" 2>> "$xwork/scan.log" || code=$?
  (( code == 0 )) || return "$code"
  jobs_xcode_device_rows "$xwork/devices.json" "$set_path" > "$xwork/devices.rows" || return 1
  while IFS=$'\t' read -r uuid state name; do
    [[ -n "$uuid" ]] || continue
    kind=simulator
    if [[ "$group" == Simulators ]]; then
      predicate=0
      jobs_clean_simulator_missing "$set_path" "$uuid" || predicate=$?
      case "$predicate" in
        0)
          if [[ ! -e "$set_path/$uuid" && ! -L "$set_path/$uuid" ]]; then
            jobs_xcode_add_missing_device "$group" "$set_path" "$uuid" "$name" || return $?
            continue
          fi
          kind=orphan
          name+=" [缺少 device.plist 的残留登记]"
          ;;
        1) ;;
        *) print -u2 -r -- "设备路径不可靠，保留：$uuid"; continue ;;
      esac
    fi
    jobs_xcode_add "$group" "$kind" "$set_path/$uuid" "$uuid" "$name / $uuid [$state]" || return $?
  done < "$xwork/devices.rows"
}
jobs_xcode_scan() {
  local developer="${HOME:A}/Library/Developer" root="" child="" date_dir="" parent=""
  for root in "$developer/Xcode/"{iOS,watchOS,tvOS,macOS}' DeviceSupport'; do
    [[ -e "$root" ]] || continue
    jobs_xcode_safe_path "$root" || return 1
    for child in "$root"/*(ND); do
      jobs_xcode_add 'Device Support' directory "$child" || return $?
    done
  done
  jobs_xcode_scan_devices Simulators "$developer/CoreSimulator/Devices" || return $?
  jobs_xcode_scan_devices 'SwiftUI Previews' "$developer/Xcode/UserData/Previews/Simulator Devices" || return $?
  root="$developer/Xcode/DerivedData"
  if [[ -e "$root" ]]; then
    jobs_xcode_safe_path "$root" || return 1
    for child in "$root"/*(ND); do
      jobs_xcode_add DerivedData directory "$child" || return $?
    done
  fi
  root="$developer/Xcode/Archives"
  if [[ -e "$root" ]]; then
    jobs_xcode_safe_path "$root" || return 1
    for date_dir in "$root"/*(N/); do
      jobs_xcode_safe_path "$date_dir" || return 1
      for child in "$date_dir"/*.xcarchive(N/); do
        jobs_xcode_add Archives archive "$child" || return $?
      done
    done
  fi
  root="$developer/CoreSimulator/Caches/dyld"
  if [[ -e "$root" ]]; then
    jobs_xcode_safe_path "$root" || return 1
    for parent in "$root"/*(N/); do
      jobs_xcode_safe_path "$parent" || return 1
      for child in "$parent"/*(N/); do
        jobs_xcode_add Caches directory "$child" || return $?
      done
    done
  fi
}
jobs_xcode_pick_group() {
  local group="$1" index="" picked="" line="" key="" found=0
  local -a indices=()
  for index in ${(on)${(k)xpaths}}; do
    [[ "${xgroups[$index]}" == "$group" ]] && indices+=("$index")
  done
  (( ${#indices} )) || { print -r -- "$group：无可清理项目，已跳过。"; return 0; }
  {
    print -r -- $'ALL\tALL — 当前组全部项目'
    for index in "${indices[@]}"; do
      print -r -- "$index"$'\t'"${xsizes[$index]} KiB"$'\t'"${xlabels[$index]}"
    done
    print -r -- $'SKIP\t跳过当前组'
  } > "$xwork/picker.rows" || return 1
  picked="$(FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE='' "$xfzf" --multi --no-sort --reverse --delimiter=$'\t' --with-nth=2.. \
    --bind='up:up,down:down,tab:down,shift-tab:up,enter:toggle,space:accept-non-empty,esc:abort,left:abort' \
    --header="$group：首行 ALL 默认高亮；↑↓/Tab移动；Enter勾选；Space确认，未勾选则取当前行；Esc/←取消整个阶段" \
    --prompt="$group > " < "$xwork/picker.rows")" || return 130
  [[ -n "$picked" ]] || return 130
  [[ "$picked" != SKIP$'\t'* && "$picked" != *$'\n'SKIP$'\t'* ]] || return 0
  while IFS= read -r line; do
    key="${line%%$'\t'*}"
    if [[ "$key" == ALL ]]; then
      for index in "${indices[@]}"; do xselected[$index]=1; done
      return 0
    fi
    [[ "$key" == <-> && -n "${xpaths[$key]:-}" && "${xgroups[$key]}" == "$group" ]] || return 1
    xselected[$key]=1
  done <<< "$picked"
}
# 普通目录先原位改名隔离，再复检身份；归档保留在私有废纸篓，其它项明确不可逆。
jobs_xcode_execute_path() {
  local index="$1" target="${xpaths[$1]}" identity="" staged="" staging="" parent="" trash=""
  jobs_xcode_safe_path "$target" || return 1
  identity="$(jobs_xcode_identity "$target")" || return 1
  [[ "$identity" == "${xids[$index]}" ]] || { print -u2 -r -- "候选已变化，保留：$target"; return 1; }
  jobs_xcode_manifest "$target" "$xwork/recheck-$index" || return 1
  /usr/bin/cmp -s "$xwork/manifest-$index" "$xwork/recheck-$index" || { print -u2 -r -- "内容已变化，保留：$target"; return 1; }
  parent="${target:h}"
  staging="$(/usr/bin/mktemp -d "$parent/.JobsXcodeClean.XXXXXXXX")" || return 1
  staged="$staging/payload"
  jobs_xcode_safe_path "$target" && [[ "$(jobs_xcode_identity "$target")" == "$identity" ]] || { /bin/rmdir "$staging"; return 1; }
  /bin/mv -n -- "$target" "$staged" || return 1
  [[ ! -e "$target" && ! -L "$target" && -d "$staged" && ! -L "$staged" && "$(/usr/bin/stat -f '%d:%i' "$staged")" == "${identity%%:*}:${${identity#*:}%%:*}" ]] || { print -u2 -r -- "隔离后身份异常，保留：$staging"; return 1; }
  if ! jobs_xcode_manifest "$staged" "$xwork/staged-$index" || ! /usr/bin/cmp -s "$xwork/manifest-$index" "$xwork/staged-$index"; then
    [[ -e "$target" || -L "$target" ]] || /bin/mv -n -- "$staged" "$target"
    /bin/rmdir -- "$staging" 2>/dev/null || true
    print -u2 -r -- "隔离后内容已变化，已保留原路径或隔离目录：$staging"
    return 1
  fi
  if [[ "${xkinds[$index]}" == archive ]]; then
    trash="${HOME:A}/.Trash"
    if ! jobs_xcode_safe_path "$trash" || [[ ! -d "$trash" || ! -w "$trash" ]]; then
      [[ -e "$target" || -L "$target" ]] || /bin/mv -n -- "$staged" "$target"
      /bin/rmdir "$staging" 2>/dev/null || true
      return 1
    fi
    [[ -n "$xrecovery" ]] || xrecovery="$(/usr/bin/mktemp -d "$trash/JobsXcodeClean-Archives.XXXXXXXX")" || return 1
    jobs_xcode_safe_path "$xrecovery" || return 1
    /bin/mv -n -- "$staged" "$xrecovery/$index-${target:t}" || return 1
    print -r -- "归档可恢复（尚未释放容量）：$xrecovery/$index-${target:t}"
  else
    /bin/rm -rf -- "$staged" || return 1
    print -r -- "已删除：$target"
  fi
  /bin/rmdir -- "$staging"
}
# 孤儿登记沿用本脚本原有完整保全流程；通用平台解析器先校验全部 JSON，再仅输出选中的 UUID。
jobs_xcode_execute_orphan() (
  emulate -L zsh
  setopt PIPE_FAIL
  local index="$1" target="${xpaths[$1]}" set_path="${xpaths[$1]:h}"
  local JOBS_XCODE_ORPHAN_UUID="${xrefs[$1]}" JOBS_XCODE_ORPHAN_CANCEL=0 JOBS_CLEAN_CONFIRMED=1 LOG_FILE="$xwork/action.log" result=0
  [[ "$JOBS_XCODE_ORPHAN_UUID" =~ '^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$' ]] || return 1
  if [[ "${xids[$index]}" == missing ]]; then
    jobs_xcode_safe_path "$set_path" || return 1
    [[ ! -e "$target" && ! -L "$target" ]] || return 1
  else
    jobs_xcode_safe_path "$target" || return 1
    [[ "$(jobs_xcode_identity "$target")" == "${xids[$index]}" ]] || return 1
    jobs_xcode_manifest "$target" "$xwork/orphan-check-$index" || return 1
    /usr/bin/cmp -s "$xwork/manifest-$index" "$xwork/orphan-check-$index" || return 1
  fi
  jobs_clean_simulator_missing "$set_path" "$JOBS_XCODE_ORPHAN_UUID" || return 1
  (( ${+functions[jobs_clean_simulator_rows]} && ${+functions[jobs_clean_simctl]} && ${+functions[jobs_clean_orphaned_simulators]} )) || return 1
  functions[jobs_xcode_legacy_device_rows]="${functions[jobs_xcode_device_rows]}"
  functions[jobs_xcode_legacy_simctl]="${functions[jobs_clean_simctl]}"
  jobs_clean_simulator_rows() {
    emulate -L zsh
    setopt PIPE_FAIL
    jobs_xcode_legacy_device_rows "$@" | /usr/bin/awk -F '\t' -v uuid="$JOBS_XCODE_ORPHAN_UUID" '$1 == uuid'
  }
  jobs_clean_simctl() {
    local code=0
    jobs_xcode_legacy_simctl "$@" || code=$?
    case "$code" in 129|130|143) JOBS_XCODE_ORPHAN_CANCEL="$code" ;; esac
    return "$code"
  }
  jobs_clean_orphaned_simulators || result=$?
  (( JOBS_XCODE_ORPHAN_CANCEL == 0 )) || return "$JOBS_XCODE_ORPHAN_CANCEL"
  return "$result"
)
jobs_xcode_execute_simulator() {
  local index="$1" target="${xpaths[$1]}" uuid="${xrefs[$1]}" set_path="${xpaths[$1]:h}" code=0 state=""
  jobs_xcode_safe_path "$target" || return 1
  [[ "$(jobs_xcode_identity "$target")" == "${xids[$index]}" ]] || return 1
  jobs_xcode_simctl "$set_path" list devices --json > "$xwork/check.json" 2>> "$xwork/action.log" || return $?
  jobs_xcode_device_rows "$xwork/check.json" "$set_path" > "$xwork/check.rows" || return 1
  state="$(/usr/bin/awk -F '\t' -v uuid="$uuid" '$1 == uuid {print $2}' "$xwork/check.rows")"
  [[ "$state" == Shutdown || "$state" == Booted ]] || { print -u2 -r -- "设备已变化或仍在过渡状态，保留：$uuid"; return 1; }
  if [[ "$state" == Booted ]]; then
    jobs_xcode_simctl "$set_path" shutdown "$uuid" >> "$xwork/action.log" 2>&1 || return $?
  fi
  # 关闭后再从系统完整清单核对状态；只注销选中的同一个 UUID。
  jobs_xcode_simctl "$set_path" list devices --json > "$xwork/check.json" 2>> "$xwork/action.log" || return $?
  jobs_xcode_device_rows "$xwork/check.json" "$set_path" > "$xwork/check.rows" || return 1
  /usr/bin/grep -Fq -- "$uuid"$'\tShutdown\t' "$xwork/check.rows" || return 1
  jobs_xcode_safe_path "$target" || return 1
  [[ "$(/usr/bin/stat -f '%d:%i' "$target")" == "${xids[$index]%%:*}:${${xids[$index]#*:}%%:*}" ]] || return 1
  jobs_xcode_simctl "$set_path" delete "$uuid" >> "$xwork/action.log" 2>&1 || return $?
  jobs_xcode_simctl "$set_path" list devices --json > "$xwork/check.json" 2>> "$xwork/action.log" || return $?
  jobs_xcode_device_rows "$xwork/check.json" "$set_path" > "$xwork/check.rows" || return 1
  ! /usr/bin/grep -q -- "^$uuid"$'\t' "$xwork/check.rows" || return 1
  print -r -- "已注销设备（数据不可恢复）：$uuid"
}
jobs_clean_xcode_stage() (
  emulate -L zsh
  setopt NO_NOMATCH PIPE_FAIL
  local REPLY="" xwork="" xsimctl="" xfzf="" index="" group="" code=0 result=0 xrecovery="" lock="" lockid=""
  local -i xcounter=0 action_log_start=0
  local -A xpaths=() xids=() xgroups=() xkinds=() xrefs=() xsizes=() xlabels=() xselected=()
  print -r -- 'Xcode 六组清理：Device Support / Simulators / SwiftUI Previews / DerivedData / Archives / Caches。'
  print -r -- '回车只进入扫描和选择；输入任意字符后回车跳过本阶段。EOF / Ctrl+C 取消。'
  print -r -- '最终范围回车确认清理，任意非空输入跳过本阶段；失败仍进入常规清理，最终汇总未完成状态。'
  jobs_xcode_interactive || { print -u2 '无交互终端，未扫描或清理。'; return 130; }
  jobs_xcode_read '是否进入 Xcode 清理？[回车继续 / 其它输入跳过]：' || return 130
  [[ -z "$REPLY" ]] || { print -r -- '已跳过 Xcode 阶段；未扫描。'; return 0; }
  [[ -n "$HOME" && "$HOME" == /* && -d "$HOME" && ! -L "$HOME" && "${HOME:A}" != / ]] || return 1
  xfzf="$(command -v fzf 2>/dev/null)" || { print -u2 '需要健康的 fzf，请先安装后重试；未扫描或删除。'; return 1; }
  "$xfzf" --version >/dev/null 2>&1 || return 1
  xwork="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/JobsXcodeCleanup.XXXXXXXX")" || return 1
  lock="${TMPDIR:-/tmp}/JobsXcodeCleanup-${UID}.lock"
  /bin/mkdir -m 700 "$lock" 2>/dev/null || { print -u2 '已有 Xcode 清理任务或遗留锁，停止本次扫描。'; return 1; }
  lockid="$(/usr/bin/stat -f '%d:%i' "$lock")" || return 1
  trap '[[ ! -L "$lock" && "$(/usr/bin/stat -f "%d:%i" "$lock" 2>/dev/null)" == "$lockid" ]] && /bin/rmdir "$lock" 2>/dev/null; true' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  print -r -- "Xcode 本次日志／清单：$xwork"
  xsimctl="$(/usr/bin/xcrun --find simctl 2>/dev/null)" || xsimctl=""
  jobs_xcode_scan || return $?
  for group in 'Device Support' Simulators 'SwiftUI Previews' DerivedData Archives Caches; do
    jobs_xcode_pick_group "$group" || return $?
  done
  (( ${#xselected} )) || { print -r -- '六组均无选中项目，未清理。'; return 0; }
  print -r -- '最终范围如下；除 Archives 进入废纸篓可恢复外，所选目录与模拟器数据会永久删除。'
  print -r -- '删除 Device Support 后调试需重新准备；DerivedData/缓存需重建；模拟器已安装App与数据不可恢复，Runtime保留。'
  for index in ${(on)${(k)xselected}}; do
    print -r -- "${xgroups[$index]} | ${xsizes[$index]} KiB | ${xpaths[$index]}"
  done | /usr/bin/tee "$xwork/selected.txt"
  jobs_xcode_read '确认仅执行以上 Xcode 范围？[回车确认清理 / 任意字符后回车跳过并继续常规清理]：' || return 130
  [[ -z "$REPLY" ]] || { print -r -- '已取消本次 Xcode 清理，继续常规清理；未删除所选项目。'; return 0; }
  if /usr/bin/pgrep -x Xcode >/dev/null || /usr/bin/pgrep -x xcodebuild >/dev/null; then
    print -u2 'Xcode 或 xcodebuild 仍在运行；请结束构建并退出 Xcode 后重试，未删除。'
    return 1
  fi
  for index in ${(on)${(k)xselected}}; do
    code=0
    action_log_start=0
    if [[ -f "$xwork/action.log" ]]; then
      action_log_start="$(/usr/bin/stat -f '%z' "$xwork/action.log")" || return 1
    fi
    if [[ "${xkinds[$index]}" == orphan ]]; then
      jobs_xcode_execute_orphan "$index" >> "$xwork/action.log" 2>&1 || code=$?
    elif [[ "${xkinds[$index]}" == simulator ]]; then
      jobs_xcode_execute_simulator "$index" >> "$xwork/action.log" 2>&1 || code=$?
    else
      jobs_xcode_execute_path "$index" >> "$xwork/action.log" 2>&1 || code=$?
    fi
    if (( code != 0 )); then
      jobs_xcode_show_log_delta "$xwork/action.log" "$action_log_start" ||
        print -u2 -r -- "无法显示本次详细诊断，请查看：$xwork/action.log"
    fi
    case "$code" in
      129|130|143) return "$code" ;;
      0) print -r -- "✓ ${xgroups[$index]}：${xlabels[$index]}" ;;
      *) result=1; print -u2 -r -- "✗ 保留或未完成：${xpaths[$index]}（退出码 $code）；详情：$xwork/action.log" ;;
    esac
  done
  print -r -- "Xcode 阶段退出码：$result；日志：$xwork/action.log"
  [[ -z "$xrecovery" ]] || print -r -- "Archives 恢复目录：$xrecovery（未清空废纸篓，不算立即释放空间）"
  return "$result"
)
# END JOBS_XCODE_CLEANUP_PHASE
# 区分开发阶段普通失败与用户中止，普通失败留待最终汇总。
jobs_clean_run_xcode_stage() {
  JOBS_CLEAN_XCODE_RESULT=0
  jobs_clean_xcode_stage || JOBS_CLEAN_XCODE_RESULT=$?
  case "$JOBS_CLEAN_XCODE_RESULT" in
    129|130|143) return "$JOBS_CLEAN_XCODE_RESULT" ;;
    0) ;;
    *) print -u2 -r -- "Xcode 阶段未全部完成（退出码 $JOBS_CLEAN_XCODE_RESULT），继续进入常规清理；最终保留失败状态。" ;;
  esac
  return 0
}
# 执行常规清理并汇总两个独立阶段，不能以常规成功覆盖开发失败。
jobs_clean_run_regular_stage() {
  local regular_code=0
  if (( JOBS_CLEAN_XCODE_RESULT != 0 )); then
    warn_echo "Xcode 阶段未全部完成（退出码 $JOBS_CLEAN_XCODE_RESULT）；所选未完成项目保留，常规清理单独执行。"
  fi
  clean "$@" || regular_code=$?
  case "$regular_code" in
    129|130|143) return "$regular_code" ;;
  esac
  if (( JOBS_CLEAN_XCODE_RESULT != 0 || regular_code != 0 )); then
    warn_echo "清理结果：Xcode 阶段退出码 $JOBS_CLEAN_XCODE_RESULT；常规阶段退出码 $regular_code。"
  fi
  (( regular_code == 0 )) || return "$regular_code"
  return "$JOBS_CLEAN_XCODE_RESULT"
}
# 复用完整清理顺序，常规授权与初始化失败均停止后续动作。
jobs_clean_run_stages() {
  local JOBS_CLEAN_XCODE_RESULT=0
  JOBS_CLEAN_CONFIRMED=0
  jobs_clean_run_xcode_stage || return $? # 先执行可选开发阶段；普通失败不阻断常规阶段。
  show_script_intro_and_wait || return $? # 单独取得常规清理授权，取消后不初始化或清理。
  jobs_clean_prepare_runtime || return $? # 确认成功后才准备日志和安全上下文。
  jobs_clean_run_regular_stage "$@" # 执行常规清理并保留两个阶段的最终结果。
}
# 旧六类只有回车确认成功后才初始化日志、互斥锁并执行；Xcode 阶段独立先行。
jobs_disk_clean_dispatch() {
  if (( $# > 0 )); then
    [[ $# == 1 && ( "$1" == --help || "$1" == -h ) ]] || { print -u2 '不接受目标路径或后台清理参数。'; return 2; }
    print -r -- '右键磁盘清理：先回车进入或输入跳过 Xcode 六组；最终范围回车执行、非空跳过，失败仍进入常规阶段，再回车确认执行旧六类；用户缓存首行全选、次行跳过。无参数使用；--help 只读。'
    return 0
  fi
  jobs_clean_run_stages "$@" # 按阶段独立取得授权、执行并汇总未完成状态。
}
# 统一收口参数分派与完整清理流程。
main() {
  jobs_disk_clean_dispatch "$@" # 保留只读帮助与参数校验，再进入清理流程。
}
main "$@"
