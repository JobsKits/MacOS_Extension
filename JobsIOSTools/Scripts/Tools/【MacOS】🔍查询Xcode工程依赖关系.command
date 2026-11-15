#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】🔍查询Xcode工程依赖关系.command
# - 核心用途：执行“🔍查询Xcode工程依赖关系”对应的移动端项目自动化任务。
# - 影响范围：可能修改项目依赖、生成文件、构建产物或开发工具配置。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。

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


# ✅ 日志输出函数
# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
# >>> Jobs Homebrew install choice >>>
# 输出安装诊断，避免混入返回的命令路径。
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

jobs_brew_note() {
  print -u2 -r -- "ℹ $*"
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
  local answer="" system_prefix="$(jobs_brew_system_prefix)"
  if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]]; then
    jobs_brew_note "缺少 Homebrew，需要人工选择安装路径；请在可交互终端重新运行，未执行安装。"
    return 1
  fi
  print -u2 -r -- "⚠ Homebrew 尚未就绪，必须先选择安装路径："
  print -u2 -r -- "1、输入精确大写 YES：选择系统标准目录 $system_prefix（Apple Silicon：/opt/homebrew；Intel：/usr/local）。"
  print -u2 -r -- "   这表示你准备向系统目录安装；官方安装器可能随后要求管理员密码，并自行验证权限。"
  jobs_prompt_output print -u2 -r -- "2、其它输入或直接回车：选择用户目录 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}，不使用 sudo；有管理员权限也可选此路径。"
  print -u2 -r -- "本步骤只选择路径，不收集或验证密码；选定路径失败就停止，不自动切换。按 Ctrl+C 取消整个任务。"
  print -u2 -n -r -- "➤ 安装路径选择："
  if ! IFS= read -r answer; then
    jobs_brew_note "输入已取消或结束，停止安装。"
    return 1
  fi
  if [[ "$answer" == YES ]]; then
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=system
  else
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=user
  fi
}
# 将官方系统安装器下载到临时文件后执行，失败不自动改装到用户目录。
jobs_brew_install_system() {
  local installer system_prefix="$(jobs_brew_system_prefix)" installer_result=0
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方安装器。"; return 1; }
  installer="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-install.XXXXXX")" || return 1
  if curl -fsSL --connect-timeout 10 --max-time 120 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"; then
    /bin/bash "$installer" || installer_result=$?
  else
    installer_result=1
  fi
  rm -- "$installer"
  if (( installer_result != 0 )); then
    jobs_brew_note "系统目录安装失败（退出码 $installer_result）；停止，不自动切换安装路径。"
    return 1
  fi
  typeset -g JOBS_HOMEBREW_BIN="$system_prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "官方安装器结束后未找到健康 Homebrew：$JOBS_HOMEBREW_BIN"; return 1; }
}
# 克隆官方稳定版本到用户目录；不覆盖非空目录，不调用 sudo。
jobs_brew_install_user() {
  local prefix="${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}" stage release_tag git_bin
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
  if ! curl -fsSL --connect-timeout 10 --max-time 60 https://api.github.com/repos/Homebrew/brew/releases/latest -o "$stage/release.json"; then
    rm -r -- "$stage"
    jobs_brew_note "获取官方稳定版本失败，停止安装。"
    return 1
  fi
  release_tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$stage/release.json" | head -n 1)"
  if [[ ! "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] ||
     ! GIT_TERMINAL_PROMPT=0 "$git_bin" -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 clone --depth 1 --branch "$release_tag" --single-branch https://github.com/Homebrew/brew.git "$stage/brew" ||
     ! "$git_bin" -C "$stage/brew" checkout -b stable ||
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
      system) jobs_brew_install_system || exit 1 ;;
      user) jobs_brew_install_user || exit 1 ;;
      *) jobs_brew_note "安装路径选择无效，停止。"; exit 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || exit 1
}
# <<< Jobs Homebrew install choice <<<
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
SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')   # 当前脚本名（去掉扩展名）
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"                  # 设置对应的日志文件路径
# 按当前输出级别记录终端信息，并同步写入脚本日志。
log()            { echo -e "$1" | jobs_prompt_tee "$LOG_FILE"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
color_echo()     { log "\033[1;32m$1\033[0m"; }         # ✅ 正常绿色输出
# 按当前输出级别记录终端信息，并同步写入脚本日志。
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }       # ℹ 信息
# 按当前输出级别记录终端信息，并同步写入脚本日志。
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }       # ✔ 成功
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }       # ⚠ 警告
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warm_echo()      { log "\033[1;33m$1\033[0m"; }         # 🟡 温馨提示（无图标）
# 按当前输出级别记录终端信息，并同步写入脚本日志。
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }       # ➤ 说明
# 按当前输出级别记录终端信息，并同步写入脚本日志。
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }       # ✖ 错误
# 按当前输出级别记录终端信息，并同步写入脚本日志。
err_echo()       { log "\033[1;31m$1\033[0m"; }         # 🔴 错误纯文本
# 按当前输出级别记录终端信息，并同步写入脚本日志。
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }      # 🐞 调试
# 按当前输出级别记录终端信息，并同步写入脚本日志。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }      # 🔹 高亮
# 按当前输出级别记录终端信息，并同步写入脚本日志。
gray_echo()      { log "\033[0;90m$1\033[0m"; }         # ⚫ 次要信息
# 按当前输出级别记录终端信息，并同步写入脚本日志。
bold_echo()      { log "\033[1m$1\033[0m"; }            # 📝 加粗
# 按当前输出级别记录终端信息，并同步写入脚本日志。
underline_echo() { log "\033[4m$1\033[0m"; }            # 🔗 下划线
# ✅ 自述信息
print_banner() {
  highlight_echo "═════════════════════════════════════════════════════════════════════" | jobs_intro_style title
  highlight_echo "🔍 Podspec 依赖分析器 - 查询 Xcode / CocoaPods 工程依赖关系" | jobs_intro_style title
  highlight_echo "═════════════════════════════════════════════════════════════════════" | jobs_intro_style title
}
# ✅ 打印脚本说明
# wait：显示自述后等待用户回车
# skip：显示自述后不等待，适合已自动识别工程目录
print_readme() {
  local wait_mode="${1:-wait}"

  note_echo "功能说明：" | jobs_intro_style title
  color_echo "1. 优先检测脚本所在目录和上一层目录；若包含 Podfile，则直接作为分析目录。" | jobs_intro_style body
  color_echo "2. 若自动检测不到，再让你拖入一个包含 Podfile 的目录。支持普通文件夹、Unix symlink、Finder 替身。" | jobs_intro_style body
  color_echo "3. 递归查找所有 *.podspec，并生成 Markdown 依赖报告，包含总览、0 上游依赖 Pod、外部依赖引用关系、双向明细和 Mermaid 图。" | jobs_intro_style body
  color_echo "4. 生成可搜索、可缩放、可拖拽的动态 HTML 依赖图，并内置 2D / 3D 视图切换。" | jobs_intro_style body
  color_echo "5. 会先自检 Homebrew；未安装时按芯片架构安装，再安装 Graphviz；已安装 Graphviz 时可选择是否升级，并尝试生成 PNG 图。" | jobs_intro_style body
  warm_echo "" | jobs_intro_style body
  warm_echo "输出目录会创建在工程目录下：PodspecDependencyReport，新报告会覆盖旧数据。" | jobs_intro_style body
  info_echo "日志文件：$LOG_FILE" | jobs_intro_style body
  warm_echo "" | jobs_intro_style body

  if [[ "$wait_mode" == "wait" ]]; then
    bold_echo "准备好后按 Enter 继续..." | jobs_intro_style body | jobs_prompt_filter
    IFS= read -r _
  else
    success_echo "已自动识别工程目录，跳过回车确认，直接执行。" | jobs_intro_style body | jobs_prompt_filter
  fi
}
# ✅ 处理终端拖入路径
normalize_drag_path() {
  RAW_FOR_RUBY="$1" /usr/bin/ruby <<'RUBY'
require 'shellwords'

s = ENV.fetch('RAW_FOR_RUBY', '').strip

begin
  parts = Shellwords.split(s)
  s = parts.join(' ') unless parts.empty?
rescue ArgumentError
  s = s.gsub(/\\(.)/, '\1')
  if (s.start_with?('"') && s.end_with?('"')) || (s.start_with?("'") && s.end_with?("'"))
    s = s[1...-1]
  end
end

puts File.expand_path(s)
RUBY
}
# ✅ 解析真实路径：支持普通目录、普通 symlink、Finder「替身」
resolve_real_path() {
  local input_path="$1"
  local real_path=""
  local alias_resolved=""

  real_path="$(REAL_PATH_FOR_RUBY="$input_path" /usr/bin/ruby <<'RUBY'
path = ENV.fetch('REAL_PATH_FOR_RUBY', '').strip
begin
  puts File.realpath(path)
rescue
  puts File.expand_path(path)
end
RUBY
)"

  if [[ -d "$real_path" ]]; then
    echo "$real_path"
    return 0
  fi

  alias_resolved="$(/usr/bin/osascript - "$input_path" <<'APPLESCRIPT' 2>/dev/null || true
on run argv
  set inputPath to item 1 of argv

  tell application "Finder"
    try
      set aliasFile to (POSIX file inputPath) as alias
      set originalItem to original item of aliasFile
      return POSIX path of (originalItem as alias)
    on error
      return ""
    end try
  end tell
end run
APPLESCRIPT
)"

  alias_resolved="$(printf "%s" "$alias_resolved" | sed '/^[[:space:]]*$/d' | tail -n 1)"

  if [[ -n "${alias_resolved//[[:space:]]/}" ]]; then
    REAL_PATH_FOR_RUBY="$alias_resolved" /usr/bin/ruby <<'RUBY'
path = ENV.fetch('REAL_PATH_FOR_RUBY', '').strip
begin
  puts File.realpath(path)
rescue
  puts File.expand_path(path)
end
RUBY
    return 0
  fi

  echo "$real_path"
}
# ✅ 判断目录是否可用：必须是目录，并且当前目录下直接包含 Podfile
is_valid_project_dir() {
  local dir="$1"
  [[ -d "$dir" && -f "$dir/Podfile" ]]
}
# ✅ 获取脚本所在目录
get_script_dir() {
  local script_path="${0:A}"
  dirname "$script_path"
}
# ✅ 最高优先级：自动检测脚本所在目录，以及脚本所在目录的上一层目录
detect_target_dir_from_script_location() {
  local script_dir=""
  local parent_dir=""

  SELECTED_TARGET_DIR=""

  script_dir="$(get_script_dir)"
  parent_dir="$(dirname "$script_dir")"

  info_echo "优先检测脚本所在目录是否包含 Podfile：$script_dir"
  if is_valid_project_dir "$script_dir"; then
    SELECTED_TARGET_DIR="$script_dir"
    success_echo "已自动识别工程目录：$SELECTED_TARGET_DIR"
    return 0
  fi

  info_echo "继续检测脚本所在目录的上一层是否包含 Podfile：$parent_dir"
  if is_valid_project_dir "$parent_dir"; then
    SELECTED_TARGET_DIR="$parent_dir"
    success_echo "已自动识别工程目录：$SELECTED_TARGET_DIR"
    return 0
  fi

  warn_echo "脚本所在目录及上一层目录均未发现 Podfile，需要手动拖入包含 Podfile 的目录。"
  return 1
}
# ✅ 手动拖入目录
prompt_target_dir() {
  if [[ -n "${JOBS_IOS_PROJECT_DIR:-}" && -d "$JOBS_IOS_PROJECT_DIR" ]]; then
    SELECTED_TARGET_DIR="$JOBS_IOS_PROJECT_DIR"
    return 0
  fi
  local raw_path=""
  local input_path=""
  local target_dir=""

  SELECTED_TARGET_DIR=""

  while true; do
    warm_echo ""
    jobs_prompt_output bold_echo "请把要分析的工程文件夹拖到这里，然后按 Enter（该目录下必须包含 Podfile）："
    IFS= read -r raw_path

    if [[ -z "${raw_path//[[:space:]]/}" ]]; then
      warn_echo "输入为空，请重新拖入文件夹。"
      continue
    fi

    input_path="$(normalize_drag_path "$raw_path")"
    target_dir="$(resolve_real_path "$input_path")"

    if is_valid_project_dir "$target_dir"; then
      SELECTED_TARGET_DIR="$target_dir"
      success_echo "已识别有效工程目录：$SELECTED_TARGET_DIR"
      return 0
    fi

    if [[ -d "$target_dir" ]]; then
      error_echo "目录存在，但当前目录下没有 Podfile：$target_dir"
    else
      error_echo "不是有效文件夹：$target_dir"
    fi
  done
}
# ✅ 获取当前 CPU 架构
get_cpu_arch() {
  /usr/bin/uname -m
}
# ✅ 根据架构推导 Homebrew 默认安装路径
get_brew_bin_by_arch() {
  local arch="$1"

  if [[ "$arch" == "arm64" ]]; then
    echo "/opt/homebrew/bin/brew"
  else
    echo "/usr/local/bin/brew"
  fi
}
# ✅ 根据当前 shell 推导 profile 文件
get_shell_profile_file() {
  local shell_path="${SHELL##*/}"

  case "$shell_path" in
    zsh)  echo "$HOME/.zprofile" ;;
    bash) echo "$HOME/.bash_profile" ;;
    *)    echo "$HOME/.profile" ;;
  esac
}
# ✅ 写入 Homebrew shellenv 到对应配置文件，并让当前终端立即生效
# ✅ Homebrew 自检
install_homebrew() {
  local jobs_existing_brew=""
  if jobs_existing_brew="$(jobs_brew_find)"; then
    JOBS_HOMEBREW_BIN="$jobs_existing_brew"
    jobs_brew_activate || exit 1
  fi
  local arch="$(get_cpu_arch)"
  local shell_path="${SHELL##*/}"
  local profile_file="$(get_shell_profile_file)"
  local brew_bin="$(get_brew_bin_by_arch "$arch")"
  local shellenv_cmd=""
  local confirm=""

  warm_echo ""
  info_echo "开始 Homebrew 自检..."
  info_echo "当前架构：$arch；当前 Shell：$shell_path"

  if ! jobs_brew_find >/dev/null && [[ -x "$brew_bin" ]]; then
    shellenv_cmd="eval \"\$(${brew_bin} shellenv)\""
    info_echo "检测到 Homebrew 已安装但未进入 PATH，开始注入环境变量..."
    inject_shellenv_block "$profile_file" "$shellenv_cmd" || return 1
  fi

  if ! jobs_brew_find >/dev/null; then
    warn_echo "未检测到 Homebrew，正在安装中...（架构：$arch）"

    if [[ "$arch" == "arm64" ]]; then
      jobs_brew_install_or_exit > >(tee -a "$LOG_FILE")
      local install_exit_code=${pipestatus[1]}
      if [[ $install_exit_code -ne 0 ]]; then
        error_echo "Homebrew 安装失败（arm64），状态码：$install_exit_code"
        return 1
      fi
      brew_bin="${JOBS_HOMEBREW_BIN:-$(jobs_brew_find 2>/dev/null || true)}"
    else
      jobs_brew_install_or_exit > >(tee -a "$LOG_FILE")
      local install_exit_code=${pipestatus[1]}
      if [[ $install_exit_code -ne 0 ]]; then
        error_echo "Homebrew 安装失败（x86_64），状态码：$install_exit_code"
        return 1
      fi
      brew_bin="${JOBS_HOMEBREW_BIN:-$(jobs_brew_find 2>/dev/null || true)}"
    fi

    success_echo "Homebrew 安装成功"

    shellenv_cmd="eval \"\$(${brew_bin} shellenv)\""
    inject_shellenv_block "$profile_file" "$shellenv_cmd" || return 1
  else
    brew_bin="$(command -v brew)"
    success_echo "Homebrew 已安装：$brew_bin"

    info_echo "是否执行 Homebrew 更新与自检？"
    jobs_prompt_output warm_echo "直接按 Enter：跳过 Homebrew 更新，只执行 brew -v 轻量检查"
    jobs_prompt_output warm_echo "输入任意字符后回车：执行 brew update && brew upgrade && brew cleanup && brew doctor && brew -v"
    IFS= read -r confirm

    if [[ -z "$confirm" ]]; then
      note_echo "已选择跳过 Homebrew 更新"
      info_echo "执行轻量自检：brew -v"
      brew -v 2>&1 | tee -a "$LOG_FILE" || warn_echo "打印 brew 版本失败，可忽略。"
    else
      info_echo "正在执行 brew update..."
      brew update 2>&1 | tee -a "$LOG_FILE"
      local update_exit_code=${pipestatus[1]}
      [[ $update_exit_code -eq 0 ]] || { error_echo "brew update 失败，状态码：$update_exit_code"; return 1; }

      info_echo "正在执行 brew upgrade..."
      brew upgrade 2>&1 | tee -a "$LOG_FILE"
      local upgrade_exit_code=${pipestatus[1]}
      [[ $upgrade_exit_code -eq 0 ]] || { error_echo "brew upgrade 失败，状态码：$upgrade_exit_code"; return 1; }

      info_echo "正在执行 brew cleanup..."
      brew cleanup 2>&1 | tee -a "$LOG_FILE"
      local cleanup_exit_code=${pipestatus[1]}
      [[ $cleanup_exit_code -eq 0 ]] || { error_echo "brew cleanup 失败，状态码：$cleanup_exit_code"; return 1; }

      info_echo "正在执行 brew doctor..."
      brew doctor 2>&1 | tee -a "$LOG_FILE"
      local doctor_exit_code=${pipestatus[1]}
      [[ $doctor_exit_code -eq 0 ]] || warn_echo "brew doctor 有警告/错误，请按提示处理。"

      brew -v 2>&1 | tee -a "$LOG_FILE" || warn_echo "打印 brew 版本失败，可忽略。"
      success_echo "Homebrew 更新与自检完成"
    fi
  fi
}
# ✅ 检查 Graphviz
ensure_graphviz() {
  warm_echo ""
  info_echo "检查 Graphviz..."

  install_homebrew || {
    warn_echo "Homebrew 自检或安装失败。动态 HTML 图仍会生成；PNG 图可能无法生成。"
    return 0
  }

  if command -v brew >/dev/null 2>&1; then
    if brew list --versions graphviz >/dev/null 2>&1; then
      jobs_prompt_output info_echo "检测到 Graphviz 已通过 Homebrew 安装，是否开始升级？回车跳过，任意输入开始升级"
      IFS= read -r graphviz_upgrade_input

      if [[ -n "$graphviz_upgrade_input" ]]; then
        note_echo "开始升级 Graphviz..."
        HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade graphviz 2>&1 | tee -a "$LOG_FILE" || true
      else
        note_echo "已跳过 Graphviz 升级"
      fi
    else
      info_echo "未检测到 Homebrew 版 Graphviz，开始安装..."
      HOMEBREW_NO_AUTO_UPDATE=1 brew install graphviz 2>&1 | tee -a "$LOG_FILE" || true
    fi
  fi

  if command -v dot >/dev/null 2>&1; then
    success_echo "Graphviz 可用：$(command -v dot)"
  else
    warn_echo "未检测到 dot 命令。动态 HTML 图仍会生成；PNG 图不会生成。"
  fi
}
# ✅ 创建报告输出目录：固定使用 PodspecDependencyReport，新的报告会覆盖旧数据
prepare_report_dir() {
  local target_dir="$1"
  local report_dir="$target_dir/PodspecDependencyReport"

  if [[ -e "$report_dir" ]]; then
    warn_echo "检测到旧报告目录，将删除并重新生成：$report_dir" >&2
    rm -rf "$report_dir"
  fi

  mkdir -p "$report_dir"
  echo "$report_dir"
}
# ✅ 写入 Ruby 解析器
write_generator_script() {
  local generator="$1"

  cat > "$generator" <<'RUBY'
require 'find'
require 'set'
require 'digest'
require 'pathname'
require 'json'

root = File.expand_path(ARGV[0])
out_dir = File.expand_path(ARGV[1])

def strip_comment(line)
  result = +''
  quote = nil
  escaped = false

  line.each_char do |ch|
    if escaped
      result << ch
      escaped = false
      next
    end

    if quote
      if ch == '\\'
        result << ch
        escaped = true
      elsif ch == quote
        quote = nil
        result << ch
      else
        result << ch
      end
    else
      if ch == "'" || ch == '"'
        quote = ch
        result << ch
      elsif ch == '#'
        break
      else
        result << ch
      end
    end
  end

  result
end

def md_escape(value)
  value.to_s.gsub('\\', '\\\\').gsub('|', '\|').gsub("\n", ' ')
end

def md_link_text_escape(value)
  md_escape(value).gsub('[', '\[').gsub(']', '\]')
end

def html_attr_escape(value)
  value.to_s.gsub('&', '&amp;').gsub('"', '&quot;').gsub('<', '&lt;').gsub('>', '&gt;')
end

def html_escape(value)
  value.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
end

def rel_path(path, root)
  Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
rescue
  path
end

def detail_anchor(pod_name)
  pod_owner_name(pod_name)
end

def pod_owner_name(value)
  value.to_s.split('/').first.strip
end

# ✅ Pod 级依赖图只关心 Pod 与 Pod 之间的依赖。
# 同一个 Pod 内部的 subspec 依赖，例如：
#   MJRefreshExtra/Core -> MJRefreshExtra/Support
# 不应被归一化成：
#   MJRefreshExtra -> MJRefreshExtra
# 否则会污染“循环依赖”判断。
def same_pod_internal_dependency?(pod_name, dep_name)
  pod_owner_name(pod_name) == pod_owner_name(dep_name)
end

def normalized_pod_key(value)
  pod_owner_name(value).downcase.gsub(/[^a-z0-9]/, '')
end

def fuzzy_contains_match(name, candidates)
  key = normalized_pod_key(name)
  return nil if key.length < 4

  exact = candidates.find { |candidate| normalized_pod_key(candidate) == key }
  return exact if exact

  matches = candidates.select do |candidate|
    candidate_key = normalized_pod_key(candidate)
    next false if candidate_key.length < 4

    candidate_key.include?(key) || key.include?(candidate_key)
  end

  matches.min_by { |candidate| [(normalized_pod_key(candidate).length - key.length).abs, candidate.to_s.length, candidate.to_s] }
end

# ✅ 判断依赖目标是否为本次扫描到的仓库内 Pod。
# 循环依赖分析必须严谨，不能用包含关系做模糊匹配。
# 例如外部 Pod `MJRefresh` 不能被误判成本地 Pod `MJRefreshExtra`。
def local_pod_target(dep_name, pod_names)
  base = pod_owner_name(dep_name)
  return base if pod_names.include?(base)

  nil
end

def report_pod_name(label, pod_names = nil)
  base = pod_owner_name(label)
  return base unless pod_names

  local_pod_target(base, pod_names) || base
end

def pod_detail_link(label, pod_names, bold: false)
  display_name = report_pod_name(label, pod_names)
  target = local_pod_target(display_name, pod_names)
  escaped = md_link_text_escape(display_name)
  escaped = "**#{escaped}**" if bold

  return escaped unless target

  "[#{escaped}](##{detail_anchor(target)})"
end

def extract_first_source_url(line)
  github_match = line.match(%r{https?://github\.com/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)?})
  return github_match[0].sub(/\.git\z/, '') if github_match

  generic_match = line.match(%r{https?://[^\s'"<>)，,]+})
  return nil unless generic_match

  generic_match[0].sub(/[。；;，,、]+$/, '')
end

def collect_pod_source_urls(root)
  urls = {}
  podfile_paths = []

  Find.find(root) do |path|
    next unless File.file?(path)
    next if path.include?('/PodspecDependencyReport/')

    basename = File.basename(path)
    next unless basename == 'Podfile' ||
                basename.start_with?('Podfile.') ||
                basename.downcase.end_with?('.podfile')

    podfile_paths << path
  end

  podfile_paths.sort.each do |path|
    File.read(path, mode: 'r:BOM|UTF-8', invalid: :replace, undef: :replace, replace: '').each_line do |line|
      pod_line = line.sub(/\A\s*#\s*/, '')
      next unless pod_line =~ /\bpod\s*\(?\s*['"]([^'"]+)['"]/

      pod_name = pod_owner_name(Regexp.last_match(1).strip)
      source_url = extract_first_source_url(line)
      next if source_url.nil? || source_url.empty?

      urls[pod_name] ||= source_url
    end
  rescue => e
    warn "读取 Podfile 来源注释失败：#{path} #{e.message}"
  end

  [urls, podfile_paths]
end

def find_source_url_for_dependency(dep_name, source_urls)
  base = pod_owner_name(dep_name)

  return [base, source_urls[base]] if source_urls[base]

  matched_key = fuzzy_contains_match(base, source_urls.keys)
  return [matched_key, source_urls[matched_key]] if matched_key && source_urls[matched_key]

  [nil, nil]
end

def dependency_link(dep_name, pod_names, source_urls, bold: false)
  display_name = report_pod_name(dep_name, pod_names)
  target = local_pod_target(display_name, pod_names)
  return pod_detail_link(display_name, pod_names, bold: bold) if target

  escaped = md_link_text_escape(display_name)
  escaped = "**#{escaped}**" if bold

  _source_key, source_url = find_source_url_for_dependency(display_name, source_urls)
  return "[#{escaped}](#{source_url})" if source_url && !source_url.empty?

  escaped
end

def source_owner_name(edge)
  pod_owner_name(edge[:from])
end

def target_owner_name(dep_name, pod_names)
  local_pod_target(dep_name, pod_names) || pod_owner_name(dep_name)
end

def edge_targets_pod?(edge, pod_name, pod_names)
  target = report_pod_name(pod_name, pod_names)
  target_owner_name(edge[:to], pod_names) == target
end

def incoming_edges_for(pod_name, edges, pod_names, exclude_self: true)
  pod_base = pod_owner_name(pod_name)

  edges.select do |edge|
    next false unless edge_targets_pod?(edge, pod_name, pod_names)
    next false if exclude_self && source_owner_name(edge) == pod_base

    true
  end.uniq { |edge| [edge[:from], edge[:declared_in], edge[:to], edge[:line], edge[:file]] }
end

def external_dependency_key(dep_name, source_urls)
  source_key, _source_url = find_source_url_for_dependency(dep_name, source_urls)
  source_key || pod_owner_name(dep_name)
end

def external_dependency_groups(edges, pod_names, source_urls)
  groups = Hash.new { |hash, key| hash[key] = [] }

  edges.each do |edge|
    next if local_pod_target(edge[:to], pod_names)

    groups[external_dependency_key(edge[:to], source_urls)] << edge
  end

  groups
end

def external_dependency_link(name, source_urls)
  display_name = pod_owner_name(name)
  source_url = source_urls[display_name]

  unless source_url
    _source_key, source_url = find_source_url_for_dependency(display_name, source_urls)
  end

  return "[#{md_link_text_escape(display_name)}](#{source_url})" if source_url && !source_url.empty?

  md_escape(display_name)
end

def mermaid_id(label)
  'N' + Digest::MD5.hexdigest(label.to_s)[0, 12]
end

def mermaid_label(label)
  label.to_s.gsub('"', "'")
end

def dot_escape(label)
  label.to_s.gsub('\\', '\\\\').gsub('"', '\"')
end

def make_mermaid(edges, nodes = [])
  lines = ['flowchart LR']
  node_labels = nodes.to_set

  edges.each do |edge|
    node_labels << edge[:from]
    node_labels << edge[:to]
  end

  if edges.empty?
    if node_labels.empty?
      lines << '  EMPTY["未发现依赖关系"]'
    else
      node_labels.to_a.sort.each do |label|
        lines << %(  #{mermaid_id(label)}["#{mermaid_label(label)}"])
      end
    end
  else
    edges.map { |e| [e[:from], e[:to]] }.uniq.sort.each do |from, to|
      lines << %(  #{mermaid_id(from)}["#{mermaid_label(from)}"] --> #{mermaid_id(to)}["#{mermaid_label(to)}"])
    end
  end

  lines.join("\n")
end

def make_dot(edges, nodes = [])
  lines = []
  lines << 'digraph PodspecDependencies {'
  lines << '  rankdir=LR;'
  lines << '  node [shape=box, fontname="Helvetica"];'

  node_labels = nodes.to_set
  edges.each do |edge|
    node_labels << edge[:from]
    node_labels << edge[:to]
  end

  node_labels.to_a.sort.each do |label|
    lines << %(  "#{dot_escape(label)}";)
  end

  edges.map { |e| [e[:from], e[:to]] }.uniq.sort.each do |from, to|
    lines << %(  "#{dot_escape(from)}" -> "#{dot_escape(to)}";)
  end

  lines << '}'
  lines.join("\n")
end

def canonical_cycle_key(cycle)
  nodes = cycle.dup
  nodes.pop if nodes.length > 1 && nodes.first == nodes.last
  return '' if nodes.empty?

  forward = (0...nodes.length).map { |i| nodes.rotate(i) }
  reversed = nodes.reverse
  backward = (0...reversed.length).map { |i| reversed.rotate(i) }
  (forward + backward).map { |candidate| candidate.join("\u0000") }.min
end

def find_internal_cycles(edges)
  graph = Hash.new { |hash, key| hash[key] = Set.new }
  nodes = Set.new

  edges.each do |edge|
    from = edge[:from].to_s
    to = edge[:to].to_s
    next if from.empty? || to.empty? || from == to

    graph[from] << to
    nodes << from
    nodes << to
  end

  cycles = {}

  nodes.to_a.sort.each do |start|
    dfs = lambda do |current, path, seen|
      graph[current].to_a.sort.each do |nxt|
        if nxt == start && path.length > 1
          cycle = path + [start]
          cycles[canonical_cycle_key(cycle)] ||= cycle
        elsif !seen.include?(nxt)
          dfs.call(nxt, path + [nxt], seen + [nxt].to_set)
        end
      end
    end

    dfs.call(start, [start], [start].to_set)
  end

  cycles.values.sort_by { |cycle| [cycle.length, cycle.join(' -> ')] }
end

# ✅ 静态解析兜底：当某些 podspec 在 DSL 执行模式下因为读取缺失文件等原因失败时使用。
def parse_podspec_static(path)
  text = File.read(path, mode: 'r:BOM|UTF-8', invalid: :replace, undef: :replace, replace: '')
  lines = text.lines
  basename = File.basename(path, '.podspec')

  pod_name = nil
  root_vars = Set.new

  lines.each do |line|
    cleaned = strip_comment(line)

    if cleaned =~ /Pod::(?:Specification|Spec)\.new\s+do\s+\|(\w+)\|/
      root_vars << Regexp.last_match(1)
    end

    if pod_name.nil? && cleaned =~ /(?:^|[^\w])(?:\w+\.)?name\s*=\s*['"]([^'"]+)['"]/
      pod_name = Regexp.last_match(1).strip
    end
  end

  pod_name ||= basename
  pod_name = pod_owner_name(pod_name)

  deps = []
  ignored_internal_subspec_deps = []
  depth = 0
  contexts = {}
  stack = []

  lines.each_with_index do |line, index|
    cleaned = strip_comment(line).strip
    next if cleaned.empty?

    if cleaned =~ /(?:^|[^\w])(\w+)\.subspec\s+['"]([^'"]+)['"]\s+do\s+\|(\w+)\|/
      parent_var = Regexp.last_match(1)
      sub_name = Regexp.last_match(2)
      sub_var = Regexp.last_match(3)

      parent_name = contexts[parent_var]&.first || pod_name
      full_name = "#{parent_name}/#{sub_name}"

      contexts[sub_var] = [full_name, depth + 1]
      stack << [sub_var, depth + 1]
    end

    cleaned.scan(/(?:(\w+(?:\.\w+)*)\.)?\bdependency\b\s*\(?\s*['"]([^'"]+)['"]([^#]*)/) do |receiver, dep_name, rest|
      receiver_var = receiver&.split('.')&.first

      declared_in = nil
      declared_in = contexts[receiver_var]&.first if receiver_var
      declared_in ||= contexts[stack.last&.first]&.first if receiver.nil? && stack.any?
      declared_in ||= pod_name

      requirement = rest.to_s.strip
      requirement = requirement.sub(/\A\s*,\s*/, '').strip
      requirement = requirement.sub(/\)\s*\z/, '').strip
      requirement = '' if requirement == ','

      raw_dep_name = dep_name.strip
      dep_owner = pod_owner_name(raw_dep_name)
      declared_owner = pod_owner_name(declared_in)

      next if dep_owner.empty?

      if same_pod_internal_dependency?(pod_name, raw_dep_name)
        ignored_internal_subspec_deps << {
          dep: dep_owner,
          raw_dep: raw_dep_name,
          requirement: requirement,
          line: index + 1,
          declared_in: declared_owner,
          raw_declared_in: declared_in
        }
        next
      end

      deps << {
        dep: dep_owner,
        raw_dep: raw_dep_name,
        requirement: requirement,
        line: index + 1,
        declared_in: declared_owner,
        raw_declared_in: declared_in
      }
    end

    opens = cleaned.scan(/\bdo\b/).length + cleaned.count('{')
    closes = cleaned.scan(/\bend\b/).length + cleaned.count('}')
    depth += opens - closes

    while stack.any? && stack.last[1] > depth
      var, = stack.pop
      contexts.delete(var)
    end
  end

  deps.uniq! { |d| d[:dep] }
  ignored_internal_subspec_deps.uniq! { |d| [d[:raw_declared_in], d[:raw_dep], d[:line]] }

  {
    name: pod_name,
    path: path,
    deps: deps,
    ignored_internal_subspec_deps: ignored_internal_subspec_deps,
    parse_mode: 'static_fallback'
  }
end

# ✅ DSL 执行式解析器：不再只靠正则扫 `xx.dependency 'Pod'` 字面量。
# 这样可以识别下面这类常见写法：
#   deps = ['A', ['B', '~> 1.0']]
#   add_deps = lambda { |ss| deps.each { |dep| ss.dependency dep } }
#   spec.subspec 'Core' { |ss| add_deps.call(ss) }
# JobsByOCPods 这次漏掉上游依赖，根因就是依赖被放进数组 + lambda 里，旧正则扫不到。
class PodspecDependencyFakeValue
  def initialize(value = nil)
    @value = value
    @children = {}
  end

  def method_missing(method_name, *args, &block)
    key = method_name.to_s

    if key.end_with?('=')
      @children[key[0...-1]] = args.first
      return args.first
    end

    child = (@children[key] ||= PodspecDependencyFakeValue.new)
    block.call(child) if block
    child
  end

  def respond_to_missing?(_method_name, _include_private = false)
    true
  end

  def [](key)
    @children[key.to_s] ||= PodspecDependencyFakeValue.new
  end

  def []= (key, value)
    @children[key.to_s] = value
  end

  def to_s
    @value.to_s
  end

  def to_str
    to_s
  end

  def to_a
    []
  end

  def to_h
    {}
  end

  def nil?
    false
  end
end

module Pod
  class Spec
    @last_created = nil

    class << self
      attr_accessor :last_created

      def new(*_args, &block)
        object = allocate
        object.__send__(:initialize, nil, nil)
        self.last_created = object
        block.call(object) if block
        object
      end
    end

    attr_reader :dependencies, :subspecs, :parent

    def initialize(subspec_name = nil, parent = nil)
      @subspec_name = subspec_name
      @parent = parent
      @name_value = nil
      @attributes = {}
      @dependencies = []
      @subspecs = []
    end

    def name=(value)
      @name_value = value.to_s
      @attributes['name'] = @name_value
    end

    def name
      @name_value || @attributes['name'] || PodspecDependencyFakeValue.new
    end

    def full_name
      if @parent
        parent_name = @parent.full_name.to_s
        return @subspec_name.to_s if parent_name.empty?
        "#{parent_name}/#{@subspec_name}"
      else
        @name_value.to_s
      end
    end

    def subspec(name, &block)
      child = self.class.allocate
      child.__send__(:initialize, name.to_s, self)
      @subspecs << child
      block.call(child) if block
      child
    end

    def dependency(name, *requirements)
      location = caller_locations(1, 1).first

      if name.is_a?(Array)
        expanded = name.compact
        raw_name = expanded.shift.to_s.strip
        requirements = expanded + requirements
      else
        raw_name = name.to_s.strip
      end

      return self if raw_name.empty?

      @dependencies << {
        raw_dep: raw_name,
        requirement: normalize_dependency_requirement(requirements),
        line: location&.lineno || 0,
        raw_declared_in: full_name
      }

      self
    end

    def all_dependencies
      @dependencies + @subspecs.flat_map(&:all_dependencies)
    end

    def method_missing(method_name, *args, &block)
      key = method_name.to_s

      if key.end_with?('=')
        @attributes[key[0...-1]] = args.first
        return args.first
      end

      value = (@attributes[key] ||= PodspecDependencyFakeValue.new)
      block.call(value) if block
      value
    end

    def respond_to_missing?(_method_name, _include_private = false)
      true
    end

    private

    def normalize_dependency_requirement(requirements)
      requirements.flatten.compact.map do |item|
        case item
        when Hash
          item.map { |key, value| "#{key}: #{value}" }.join(', ')
        else
          item.to_s
        end
      end.reject(&:empty?).join(', ')
    end
  end

  Specification = Spec unless const_defined?(:Specification)
end

def parse_podspec_dynamic(path)
  Pod::Spec.last_created = nil

  old_pwd = Dir.pwd
  Dir.chdir(File.dirname(path)) do
    load path
  end
ensure
  Dir.chdir(old_pwd) if old_pwd && Dir.pwd != old_pwd
end

def build_report_from_dynamic_spec(path)
  spec = Pod::Spec.last_created
  raise 'Pod::Spec.new 没有返回 spec 对象' unless spec

  basename = File.basename(path, '.podspec')
  pod_name = spec.name.to_s.strip
  pod_name = basename if pod_name.empty?
  pod_name = pod_owner_name(pod_name)

  deps = []
  ignored_internal_subspec_deps = []

  spec.all_dependencies.each do |raw|
    raw_dep_name = raw[:raw_dep].to_s.strip
    dep_owner = pod_owner_name(raw_dep_name)
    next if dep_owner.empty?

    raw_declared_in = raw[:raw_declared_in].to_s.strip
    raw_declared_in = pod_name if raw_declared_in.empty?
    declared_owner = pod_owner_name(raw_declared_in)

    item = {
      dep: dep_owner,
      raw_dep: raw_dep_name,
      requirement: raw[:requirement].to_s,
      line: raw[:line].to_i,
      declared_in: declared_owner,
      raw_declared_in: raw_declared_in
    }

    if same_pod_internal_dependency?(pod_name, raw_dep_name)
      ignored_internal_subspec_deps << item
    else
      deps << item
    end
  end

  deps.uniq! { |d| d[:dep] }
  ignored_internal_subspec_deps.uniq! { |d| [d[:raw_declared_in], d[:raw_dep], d[:line]] }

  {
    name: pod_name,
    path: path,
    deps: deps,
    ignored_internal_subspec_deps: ignored_internal_subspec_deps,
    parse_mode: 'dsl'
  }
end

def parse_podspec(path)
  begin
    parse_podspec_dynamic(path)
    build_report_from_dynamic_spec(path)
  rescue Exception => e
    report = parse_podspec_static(path)
    report[:parse_error] = e.message
    report
  end
end

def make_interactive_html(data_json)
  <<~HTML
  <!doctype html>
  <html lang="zh-CN">
  <head>
    <meta charset="utf-8">
    <title>Podspec 依赖动态图</title>
    <style>
      :root {
        --bg: #f6f7f9;
        --ink: #222;
        --muted: #6b7280;
        --panel: #ffffff;
        --border: #ddd;
        --nav: #111827;
        --blue: #2563eb;
        --blue-soft: rgba(37, 99, 235, .12);
        --green: #059669;
        --orange: #d97706;
        --purple: #7c3aed;
      }

      * { box-sizing: border-box; }

      # 封装 body 对应的独立处理逻辑。
      body {
        margin: 0;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        background: var(--bg);
        color: var(--ink);
      }

      # 封装 header 对应的独立处理逻辑。
      header { padding: 14px 18px; background: var(--nav); color: white; }
      header h1 { margin: 0 0 8px; font-size: 20px; }
      header .meta { opacity: .8; font-size: 13px; }

      .toolbar {
        display: flex;
        gap: 10px;
        align-items: center;
        flex-wrap: wrap;
        padding: 12px 18px;
        background: white;
        border-bottom: 1px solid var(--border);
      }

      input, select, button { height: 32px; font-size: 14px; }
      # 封装 input 对应的独立处理逻辑。
      input { width: 260px; padding: 0 10px; }
      # 封装 button 对应的独立处理逻辑。
      button { padding: 0 12px; cursor: pointer; }

      .view-switch {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        padding: 2px;
        border: 1px solid #d1d5db;
        border-radius: 999px;
        background: #f3f4f6;
      }

      .view-switch button {
        height: 28px;
        border: 0;
        border-radius: 999px;
        background: transparent;
        color: #374151;
        font-weight: 700;
      }

      .view-switch button.active {
        color: white;
        background: #2563eb;
        box-shadow: 0 4px 14px rgba(37, 99, 235, .28);
      }

      .layout { display: grid; grid-template-columns: 1fr 320px; height: calc(100vh - 112px); }

      #stage {
        position: relative;
        overflow: hidden;
        background: linear-gradient(45deg, #fafafa, #f0f3f7);
        cursor: grab;
      }

      #stage:active { cursor: grabbing; }

      #canvas { position: absolute; left: 0; top: 0; transform-origin: 0 0; }
      svg { overflow: visible; }

      .node { cursor: pointer; }
      .node rect { fill: white; stroke: #5b6b84; stroke-width: 1.4; rx: 8; }
      .node text { font-size: 12px; pointer-events: none; }
      .node.focus rect { stroke-width: 3; stroke: #2563eb; filter: drop-shadow(0 0 8px rgba(37, 99, 235, .24)); }
      .edge { stroke: #718096; stroke-width: 1.2; marker-end: url(#arrow); }

      #stage3d {
        position: absolute;
        inset: 0;
        display: none;
        overflow: hidden;
        background:
          radial-gradient(circle at 25% 20%, rgba(37, 99, 235, .24), transparent 28%),
          radial-gradient(circle at 78% 68%, rgba(124, 58, 237, .18), transparent 32%),
          radial-gradient(circle at 50% 50%, rgba(5, 150, 105, .10), transparent 36%),
          #07111f;
      }

      #canvas3d {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
      }

      .three-hint {
        position: absolute;
        left: 14px;
        bottom: 14px;
        max-width: 520px;
        padding: 10px 12px;
        border: 1px solid rgba(148, 163, 184, .28);
        border-radius: 14px;
        color: rgba(226, 232, 240, .86);
        background: rgba(15, 23, 42, .62);
        backdrop-filter: blur(12px);
        font-size: 12px;
        line-height: 1.7;
        pointer-events: none;
      }

      .three-stats {
        position: absolute;
        right: 14px;
        top: 14px;
        padding: 8px 10px;
        border: 1px solid rgba(148, 163, 184, .28);
        border-radius: 999px;
        color: rgba(226, 232, 240, .88);
        background: rgba(15, 23, 42, .62);
        backdrop-filter: blur(12px);
        font-size: 12px;
        pointer-events: none;
      }

      # 封装 aside 对应的独立处理逻辑。
      aside { overflow: auto; background: white; border-left: 1px solid var(--border); padding: 14px; }
      aside h2 { font-size: 16px; margin: 0 0 10px; }
      aside h3 { font-size: 14px; margin: 18px 0 8px; }
      aside ul { padding-left: 18px; }
      .muted { color: var(--muted); font-size: 13px; }
      .badge { display: inline-block; padding: 2px 8px; background: #edf2f7; border-radius: 999px; margin-right: 6px; font-size: 12px; }

      .direction-sections > li { margin-bottom: 12px; }

      @media (max-width: 900px) {
        .layout { grid-template-columns: 1fr; height: calc(100vh - 160px); }
        # 封装 aside 对应的独立处理逻辑。
        aside { height: 280px; border-left: 0; border-top: 1px solid var(--border); }
        # 封装 input 对应的独立处理逻辑。
        input { width: min(260px, 100%); }
      }
    </style>
  </head>
  <body>
    <header>
      <h1>Podspec 依赖动态图</h1>
      <div class="meta" id="meta"></div>
    </header>

    <div class="toolbar">
      <div class="view-switch" aria-label="视图切换">
        <button id="view2d" class="active" type="button">2D 关系图</button>
        <button id="view3d" type="button">3D 空间图</button>
      </div>
      <input id="search" placeholder="搜索 Pod / 依赖">
      <select id="mode">
        <option value="internal">只看仓库内 Pod 关联</option>
        <option value="all">全部依赖</option>
      </select>
      <select id="depth">
        <option value="1">点击节点后显示 1 层邻居</option>
        <option value="2">点击节点后显示 2 层邻居</option>
        <option value="3">点击节点后显示 3 层邻居</option>
      </select>
      <button id="fit">适配视图</button>
      <button id="reset">重置</button>
    </div>

    <div class="layout">
      <div id="stage">
        <div id="canvas">
          <svg id="svg" width="2000" height="1400">
            <defs>
              <marker id="arrow" markerWidth="10" markerHeight="10" refX="9" refY="3" orient="auto">
                <path d="M0,0 L0,6 L9,3 z" fill="#718096"></path>
              </marker>
            </defs>
            <g id="edges"></g>
            <g id="nodes"></g>
          </svg>
        </div>
        <div id="stage3d">
          <canvas id="canvas3d"></canvas>
          <div class="three-stats" id="threeStats"></div>
          <div class="three-hint">3D 模式：拖动旋转，滚轮缩放，点击节点查看上下游；默认保留原 2D 图，方便你对照查看。</div>
        </div>
      </div>
      <aside id="detail"></aside>
    </div>

    <script>
      const data = #{data_json};
      const state = {
        view: '2d',
        mode: 'internal',
        search: '',
        focus: null,
        depth: 1,
        scale: 1,
        tx: 20,
        ty: 20,
        nodes: [],
        edges: [],
        rotateX: -0.46,
        rotateY: 0.78,
        zoom3d: 1,
        nodes3d: [],
        hit3d: []
      };

      const stage = document.getElementById('stage');
      const canvas = document.getElementById('canvas');
      const svg = document.getElementById('svg');
      const edgesGroup = document.getElementById('edges');
      const nodesGroup = document.getElementById('nodes');
      const stage3d = document.getElementById('stage3d');
      const canvas3d = document.getElementById('canvas3d');
      const ctx3d = canvas3d.getContext('2d');
      const threeStats = document.getElementById('threeStats');
      const view2dButton = document.getElementById('view2d');
      const view3dButton = document.getElementById('view3d');

      document.getElementById('meta').textContent =
        `分析目录：${data.root} ｜ 生成时间：${data.generatedAt} ｜ Pod 数：${data.pods.length}`;

      # 封装 allEdges 对应的独立处理逻辑。
      function allEdges() {
        return state.mode === 'internal' ? data.internalEdges : data.allEdges;
      }

      # 封装 localPodNames 对应的独立处理逻辑。
      function localPodNames() {
        return new Set(data.pods.map(p => p.name));
      }

      # 封装 nodeNames 对应的独立处理逻辑。
      function nodeNames() {
        const names = new Set(data.pods.map(p => p.name));
        allEdges().forEach(e => {
          names.add(e.from);
          names.add(e.to);
        });
        return [...names].sort();
      }

      # 封装 collectVisibleNames 对应的独立处理逻辑。
      function collectVisibleNames() {
        let names = new Set(nodeNames());
        const q = state.search.trim().toLowerCase();

        if (q) {
          names = new Set([...names].filter(n => n.toLowerCase().includes(q)));
          allEdges().forEach(e => {
            if (e.from.toLowerCase().includes(q) || e.to.toLowerCase().includes(q)) {
              names.add(e.from);
              names.add(e.to);
            }
          });
        }

        if (state.focus) {
          const visible = new Set([state.focus]);
          let frontier = new Set([state.focus]);

          for (let i = 0; i < state.depth; i++) {
            const next = new Set();
            allEdges().forEach(e => {
              if (frontier.has(e.from)) {
                next.add(e.to);
                visible.add(e.to);
              }
              if (frontier.has(e.to)) {
                next.add(e.from);
                visible.add(e.from);
              }
            });
            frontier = next;
          }

          names = visible;
        }

        return names;
      }

      function layout(names) {
        const arr = [...names].sort();
        const cols = Math.max(1, Math.ceil(Math.sqrt(arr.length)));
        const w = 210;
        const h = 90;

        return arr.map((name, i) => ({
          name,
          x: (i % cols) * w + 60,
          y: Math.floor(i / cols) * h + 60,
          width: 160,
          height: 38
        }));
      }

      # 封装 applyTransform 对应的独立处理逻辑。
      function applyTransform() {
        canvas.style.transform = `translate(${state.tx}px, ${state.ty}px) scale(${state.scale})`;
      }

      # 封装 render 对应的独立处理逻辑。
      function render() {
        updateViewVisibility();

        if (state.view === '3d') {
          render3d();
        } else {
          render2d();
        }

        updateDetail();
      }

      # 封装 render2d 对应的独立处理逻辑。
      function render2d() {
        const visibleNames = collectVisibleNames();
        state.nodes = layout(visibleNames);
        const nodeMap = new Map(state.nodes.map(n => [n.name, n]));

        state.edges = allEdges().filter(e => nodeMap.has(e.from) && nodeMap.has(e.to));

        edgesGroup.innerHTML = '';
        state.edges.forEach(e => {
          const a = nodeMap.get(e.from);
          const b = nodeMap.get(e.to);
          const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
          line.setAttribute('class', 'edge');
          line.setAttribute('x1', a.x + a.width);
          line.setAttribute('y1', a.y + a.height / 2);
          line.setAttribute('x2', b.x);
          line.setAttribute('y2', b.y + b.height / 2);
          edgesGroup.appendChild(line);
        });

        nodesGroup.innerHTML = '';
        state.nodes.forEach(n => {
          const g = document.createElementNS('http://www.w3.org/2000/svg', 'g');
          g.setAttribute('class', 'node' + (state.focus === n.name ? ' focus' : ''));
          g.setAttribute('transform', `translate(${n.x}, ${n.y})`);

          const rect = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
          rect.setAttribute('width', n.width);
          rect.setAttribute('height', n.height);

          const text = document.createElementNS('http://www.w3.org/2000/svg', 'text');
          text.setAttribute('x', 10);
          text.setAttribute('y', 24);
          text.textContent = n.name.length > 22 ? n.name.slice(0, 21) + '…' : n.name;

          g.appendChild(rect);
          g.appendChild(text);

          g.addEventListener('click', event => {
            event.stopPropagation();
            state.focus = state.focus === n.name ? null : n.name;
            render();
          });

          nodesGroup.appendChild(g);
        });
      }

      # 封装 resize3dCanvas 对应的独立处理逻辑。
      function resize3dCanvas() {
        const rect = stage3d.getBoundingClientRect();
        const dpr = window.devicePixelRatio || 1;
        const width = Math.max(1, Math.floor(rect.width * dpr));
        const height = Math.max(1, Math.floor(rect.height * dpr));

        if (canvas3d.width !== width || canvas3d.height !== height) {
          canvas3d.width = width;
          canvas3d.height = height;
          canvas3d.style.width = `${rect.width}px`;
          canvas3d.style.height = `${rect.height}px`;
        }

        ctx3d.setTransform(dpr, 0, 0, dpr, 0, 0);
        return rect;
      }

      function layout3d(names) {
        const arr = [...names].sort();
        const degrees = new Map();

        allEdges().forEach(edge => {
          degrees.set(edge.from, (degrees.get(edge.from) || 0) + 1);
          degrees.set(edge.to, (degrees.get(edge.to) || 0) + 1);
        });

        const count = Math.max(1, arr.length);
        const radius = Math.min(520, Math.max(190, 90 + Math.sqrt(count) * 42));
        const golden = Math.PI * (3 - Math.sqrt(5));

        return arr.map((name, index) => {
          const y = count === 1 ? 0 : 1 - (index / (count - 1)) * 2;
          const r = Math.sqrt(Math.max(0, 1 - y * y));
          const theta = index * golden;
          const degree = degrees.get(name) || 0;

          # 封装 return 对应的独立处理逻辑。
          return {
            name,
            x: Math.cos(theta) * r * radius,
            y: y * radius * 0.88,
            z: Math.sin(theta) * r * radius,
            weight: degree,
            radius: Math.min(18, 7 + Math.sqrt(degree + 1) * 2.4)
          };
        });
      }

      function rotatePoint(point) {
        const cosY = Math.cos(state.rotateY);
        const sinY = Math.sin(state.rotateY);
        const cosX = Math.cos(state.rotateX);
        const sinX = Math.sin(state.rotateX);

        const x1 = point.x * cosY - point.z * sinY;
        const z1 = point.x * sinY + point.z * cosY;
        const y1 = point.y * cosX - z1 * sinX;
        const z2 = point.y * sinX + z1 * cosX;

        # 封装 return 对应的独立处理逻辑。
        return { x: x1, y: y1, z: z2 };
      }

      function projectPoint(point, rect) {
        const rotated = rotatePoint(point);
        const camera = 820;
        const depth = camera + rotated.z;
        const perspective = camera / Math.max(120, depth);
        const scale = perspective * state.zoom3d;

        # 封装 return 对应的独立处理逻辑。
        return {
          name: point.name,
          x: rect.width / 2 + rotated.x * scale,
          y: rect.height / 2 + rotated.y * scale,
          z: rotated.z,
          radius: point.radius * Math.max(.55, Math.min(1.7, scale)),
          weight: point.weight,
          source: point
        };
      }

      function nodeColor(name, alpha = 1) {
        const localNames = localPodNames();
        const isLocal = localNames.has(name);
        const isFocused = state.focus === name;
        const users = allEdges().filter(edge => edgeTargetsName(edge, name) && sourceOwner(edge) !== name).length;
        const deps = allEdges().filter(edge => edge.from === name).length;

        if (isFocused) return `rgba(250, 204, 21, ${alpha})`;
        if (!isLocal) return `rgba(249, 115, 22, ${alpha})`;
        if (users > deps) return `rgba(59, 130, 246, ${alpha})`;
        if (deps > users) return `rgba(16, 185, 129, ${alpha})`;
        return `rgba(168, 85, 247, ${alpha})`;
      }

      function drawGrid3d(rect) {
        ctx3d.save();
        ctx3d.strokeStyle = 'rgba(148, 163, 184, .12)';
        ctx3d.lineWidth = 1;

        for (let i = -6; i <= 6; i++) {
          const a = projectPoint({ x: -420, y: 220, z: i * 70, name: '' }, rect);
          const b = projectPoint({ x: 420, y: 220, z: i * 70, name: '' }, rect);
          const c = projectPoint({ x: i * 70, y: 220, z: -420, name: '' }, rect);
          const d = projectPoint({ x: i * 70, y: 220, z: 420, name: '' }, rect);

          ctx3d.beginPath();
          ctx3d.moveTo(a.x, a.y);
          ctx3d.lineTo(b.x, b.y);
          ctx3d.stroke();

          ctx3d.beginPath();
          ctx3d.moveTo(c.x, c.y);
          ctx3d.lineTo(d.x, d.y);
          ctx3d.stroke();
        }

        ctx3d.restore();
      }

      # 封装 render3d 对应的独立处理逻辑。
      function render3d() {
        const rect = resize3dCanvas();
        ctx3d.clearRect(0, 0, rect.width, rect.height);

        const visibleNames = collectVisibleNames();
        state.nodes3d = layout3d(visibleNames);
        const rawMap = new Map(state.nodes3d.map(n => [n.name, n]));
        const projected = new Map(state.nodes3d.map(n => [n.name, projectPoint(n, rect)]));
        const edges = allEdges().filter(e => rawMap.has(e.from) && rawMap.has(e.to));

        state.hit3d = [];
        threeStats.textContent = `3D 节点 ${state.nodes3d.length} ｜ 边 ${edges.length}`;

        drawGrid3d(rect);

        edges
          .map(edge => ({ edge, a: projected.get(edge.from), b: projected.get(edge.to) }))
          .sort((one, two) => ((one.a.z + one.b.z) - (two.a.z + two.b.z)))
          .forEach(item => {
            # 封装 const 对应的独立处理逻辑。
            const { edge, a, b } = item;
            const related = !state.focus || edge.from === state.focus || edgeTargetsName(edge, state.focus);
            const alpha = related ? .58 : .16;
            const grad = ctx3d.createLinearGradient(a.x, a.y, b.x, b.y);
            grad.addColorStop(0, nodeColor(edge.from, alpha));
            grad.addColorStop(1, nodeColor(edge.to, alpha * .72));

            ctx3d.save();
            ctx3d.strokeStyle = grad;
            ctx3d.lineWidth = related ? 1.55 : .85;
            ctx3d.beginPath();
            ctx3d.moveTo(a.x, a.y);
            ctx3d.lineTo(b.x, b.y);
            ctx3d.stroke();

            const angle = Math.atan2(b.y - a.y, b.x - a.x);
            const arrowSize = 7;
            ctx3d.fillStyle = nodeColor(edge.to, alpha);
            ctx3d.beginPath();
            ctx3d.moveTo(b.x, b.y);
            ctx3d.lineTo(b.x - Math.cos(angle - .45) * arrowSize, b.y - Math.sin(angle - .45) * arrowSize);
            ctx3d.lineTo(b.x - Math.cos(angle + .45) * arrowSize, b.y - Math.sin(angle + .45) * arrowSize);
            ctx3d.closePath();
            ctx3d.fill();
            ctx3d.restore();
          });

        const projectedNodes = [...projected.values()].sort((a, b) => a.z - b.z);

        projectedNodes.forEach(point => {
          const related = !state.focus || point.name === state.focus ||
            allEdges().some(edge =>
              (edge.from === state.focus && edgeTargetsName(edge, point.name)) ||
              (edgeTargetsName(edge, state.focus) && edge.from === point.name)
            );
          const glow = point.name === state.focus ? 26 : 12;
          const radius = point.radius;

          ctx3d.save();
          ctx3d.globalAlpha = related ? 1 : .38;
          ctx3d.shadowColor = nodeColor(point.name, .72);
          ctx3d.shadowBlur = glow;
          ctx3d.fillStyle = nodeColor(point.name, .92);
          ctx3d.beginPath();
          ctx3d.arc(point.x, point.y, radius, 0, Math.PI * 2);
          ctx3d.fill();

          ctx3d.shadowBlur = 0;
          ctx3d.lineWidth = point.name === state.focus ? 3 : 1;
          ctx3d.strokeStyle = point.name === state.focus ? 'rgba(254, 240, 138, .95)' : 'rgba(226, 232, 240, .72)';
          ctx3d.stroke();

          if (radius > 9 || point.name === state.focus || state.nodes3d.length < 60) {
            ctx3d.font = `${point.name === state.focus ? 700 : 600} 12px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif`;
            ctx3d.textBaseline = 'middle';
            ctx3d.fillStyle = 'rgba(241, 245, 249, .94)';
            ctx3d.shadowColor = 'rgba(0,0,0,.9)';
            ctx3d.shadowBlur = 4;
            const label = point.name.length > 22 ? point.name.slice(0, 21) + '…' : point.name;
            ctx3d.fillText(label, point.x + radius + 7, point.y);
          }

          state.hit3d.push({
            name: point.name,
            x: point.x,
            y: point.y,
            radius: Math.max(12, radius + 7)
          });

          ctx3d.restore();
        });
      }

      # 执行对应的环境配置或同步处理。
      function updateViewVisibility() {
        const is3d = state.view === '3d';

        canvas.style.display = is3d ? 'none' : 'block';
        stage3d.style.display = is3d ? 'block' : 'none';
        view2dButton.classList.toggle('active', !is3d);
        view3dButton.classList.toggle('active', is3d);
      }

      function edgeTargetsName(edge, name) {
        return edge.to === name || edge.to_base === name || edge.to_pod === name || edge.to_external === name;
      }

      function sourceOwner(edge) {
        return edge.from || '';
      }

      # 执行对应的环境配置或同步处理。
      function updateDetail() {
        const box = document.getElementById('detail');

        if (!state.focus) {
          const zero = data.pods.filter(p => !p.deps || p.deps.length === 0).map(p => p.name).sort();
          box.innerHTML = `
            <h2>总览</h2>
            <p><span class="badge">Pod ${data.pods.length}</span><span class="badge">边 ${allEdges().length}</span><span class="badge">${state.view === '3d' ? '3D 空间图' : '2D 关系图'}</span></p>
            <p class="muted">点击节点查看上下游依赖。3D 模式下可以拖动旋转、滚轮缩放。</p>
            <h3>0 上游依赖 Pod</h3>
            <ul>${zero.map(n => `<li>${n}</li>`).join('')}</ul>
          `;
          return;
        }

        const deps = [...new Set(allEdges().filter(e => e.from === state.focus).map(e => e.to))].sort();
        const users = [...new Set(allEdges()
          .filter(e => edgeTargetsName(e, state.focus) && sourceOwner(e) !== state.focus)
          .map(e => e.from))].sort();

        box.innerHTML = `
          <h2>${state.focus}</h2>
          <ul class="direction-sections">
            <li>
              <strong>上游依赖</strong>
              <ul>${deps.length ? deps.map(n => `<li>${n}</li>`).join('') : '<li class="muted">无</li>'}</ul>
            </li>
            <li>
              <strong>下游依赖</strong>
              <ul>${users.length ? users.map(n => `<li>${n}</li>`).join('') : '<li class="muted">无</li>'}</ul>
            </li>
          </ul>
        `;
      }

      # 封装 fitView 对应的独立处理逻辑。
      function fitView() {
        if (state.view === '3d') {
          state.rotateX = -0.46;
          state.rotateY = 0.78;
          state.zoom3d = 1;
          render3d();
          return;
        }

        state.scale = 1;
        state.tx = 20;
        state.ty = 20;
        applyTransform();
      }

      # 执行对应的清理操作，并保留必要的安全检查。
      function resetAll() {
        state.search = '';
        state.focus = null;
        state.depth = 1;
        state.rotateX = -0.46;
        state.rotateY = 0.78;
        state.zoom3d = 1;
        state.scale = 1;
        state.tx = 20;
        state.ty = 20;
        document.getElementById('search').value = '';
        document.getElementById('depth').value = '1';
        render();
        fitView();
      }

      function switchView(view) {
        state.view = view;
        render();
        fitView();
      }

      view2dButton.addEventListener('click', () => switchView('2d'));
      view3dButton.addEventListener('click', () => switchView('3d'));

      document.getElementById('mode').addEventListener('change', e => {
        state.mode = e.target.value;
        state.focus = null;
        render();
        fitView();
      });

      document.getElementById('search').addEventListener('input', e => {
        state.search = e.target.value;
        state.focus = null;
        render();
        fitView();
      });

      document.getElementById('depth').addEventListener('change', e => {
        state.depth = Number(e.target.value);
        render();
      });

      document.getElementById('fit').addEventListener('click', fitView);
      document.getElementById('reset').addEventListener('click', resetAll);

      let dragging = false;
      let moved = false;
      let lastX = 0;
      let lastY = 0;

      stage.addEventListener('mousedown', e => {
        dragging = true;
        moved = false;
        lastX = e.clientX;
        lastY = e.clientY;
      });

      window.addEventListener('mousemove', e => {
        if (!dragging) return;

        const dx = e.clientX - lastX;
        const dy = e.clientY - lastY;

        if (Math.abs(dx) + Math.abs(dy) > 2) {
          moved = true;
        }

        if (state.view === '3d') {
          state.rotateY += dx * 0.008;
          state.rotateX += dy * 0.008;
          state.rotateX = Math.max(-1.35, Math.min(1.35, state.rotateX));
          render3d();
        } else {
          state.tx += dx;
          state.ty += dy;
          applyTransform();
        }

        lastX = e.clientX;
        lastY = e.clientY;
      });

      window.addEventListener('mouseup', () => dragging = false);

      stage.addEventListener('click', e => {
        if (state.view !== '3d' || moved) return;

        const rect = canvas3d.getBoundingClientRect();
        const x = e.clientX - rect.left;
        const y = e.clientY - rect.top;
        const hit = [...state.hit3d].reverse().find(item => {
          const dx = item.x - x;
          const dy = item.y - y;
          return Math.sqrt(dx * dx + dy * dy) <= item.radius;
        });

        if (hit) {
          state.focus = state.focus === hit.name ? null : hit.name;
          render();
        }
      });

      stage.addEventListener('wheel', e => {
        e.preventDefault();

        if (state.view === '3d') {
          state.zoom3d *= e.deltaY > 0 ? .92 : 1.08;
          state.zoom3d = Math.max(.35, Math.min(2.8, state.zoom3d));
          render3d();
          return;
        }

        const delta = e.deltaY > 0 ? 0.9 : 1.1;
        state.scale = Math.max(0.2, Math.min(3, state.scale * delta));
        applyTransform();
      }, { passive: false });

      window.addEventListener('resize', () => {
        if (state.view === '3d') {
          render3d();
        }
      });

      render();
      fitView();
    </script>
  </body>
  </html>
  HTML
end

podspec_paths = []

Find.find(root) do |path|
  next unless File.file?(path)
  next if path.include?('/PodspecDependencyReport/')
  next if path.include?('/__MACOSX/')
  next if File.basename(path).start_with?('._')
  podspec_paths << path if path.end_with?('.podspec')
end

podspec_paths.sort!

reports = []
errors = []

podspec_paths.each do |path|
  begin
    reports << parse_podspec(path)
  rescue => e
    errors << [path, e.message]
  end
end

pod_names = reports.map { |r| r[:name] }.to_set
source_urls, source_podfile_paths = collect_pod_source_urls(root)
all_edges = []
internal_edges = []

reports.each do |report|
  report[:deps].each do |dep|
    dep_name = report_pod_name(dep[:dep], pod_names)
    from_name = report_pod_name(report[:name], pod_names)
    next if dep_name == from_name

    local_target = local_pod_target(dep_name, pod_names)
    external_target = local_target ? nil : external_dependency_key(dep_name, source_urls)

    edge = {
      from: from_name,
      to: local_target || external_target || dep_name,
      to_base: dep_name,
      to_pod: local_target,
      to_external: external_target,
      requirement: dep[:requirement],
      declared_in: report_pod_name(dep[:declared_in], pod_names),
      line: dep[:line],
      file: rel_path(report[:path], root)
    }

    all_edges << edge
    internal_edges << edge if local_target
  end
end

all_edges.uniq! { |edge| [edge[:from], edge[:to]] }
internal_edges.uniq! { |edge| [edge[:from], edge[:to]] }

all_nodes = reports.map { |r| report_pod_name(r[:name], pod_names) }.uniq
zero_dependency_reports = reports.select { |r| r[:deps].empty? }.sort_by { |r| r[:name] }
ignored_internal_subspec_deps = reports.flat_map do |report|
  report.fetch(:ignored_internal_subspec_deps, []).map do |dep|
    dep.merge(pod: report[:name], file: report[:path])
  end
end
external_groups = external_dependency_groups(all_edges, pod_names, source_urls)
parse_mode_counts = reports.group_by { |r| r[:parse_mode] || 'unknown' }.transform_values(&:length)
fallback_reports = reports.select { |r| r[:parse_mode] == 'static_fallback' }
internal_cycles = find_internal_cycles(internal_edges)

md_path = File.join(out_dir, 'PodspecDependencies.md')
html_path = File.join(out_dir, 'PodspecDependencies_interactive.html')
all_mmd_path = File.join(out_dir, 'PodspecDependencies_all.mmd')
internal_mmd_path = File.join(out_dir, 'PodspecDependencies_internal.mmd')
all_dot_path = File.join(out_dir, 'PodspecDependencies_all.dot')
internal_dot_path = File.join(out_dir, 'PodspecDependencies_internal.dot')

all_mermaid = make_mermaid(all_edges, all_nodes)
internal_mermaid = make_mermaid(internal_edges, all_nodes)

File.write(all_mmd_path, all_mermaid)
File.write(internal_mmd_path, internal_mermaid)
File.write(all_dot_path, make_dot(all_edges, all_nodes))
File.write(internal_dot_path, make_dot(internal_edges, all_nodes))

html_data = {
  root: root,
  generatedAt: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
  pods: reports.sort_by { |r| r[:name] }.map do |r|
    {
      name: report_pod_name(r[:name], pod_names),
      file: rel_path(r[:path], root),
      deps: r[:deps]
    }
  end,
  allEdges: all_edges,
  internalEdges: internal_edges,
  internalCycles: internal_cycles,
  ignoredInternalSubspecDeps: ignored_internal_subspec_deps
}

File.write(html_path, make_interactive_html(JSON.generate(html_data)))

File.open(md_path, 'w') do |md|
  top_link = '<a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>'

  md.puts '# Podspec 依赖分析报告'
  md.puts '![Jobs出品，必属精品](https://picsum.photos/1500/400)'
  md.puts '[toc]'
  md.puts
  md.puts "## 🔥 <font id=前言>前言</font> #{top_link}"
  md.puts
  md.puts "- 此文件由脚本自动运行分析得出"
  md.puts "- 分析目录：`#{root}`"
  md.puts "- 生成时间：`#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}`"
  md.puts "- Podspec 数量：`#{reports.length}`"
  md.puts "- 0 下游依赖 Pod 数量：`#{zero_dependency_reports.length}`"
  md.puts "- 全部依赖边数量：`#{all_edges.map { |e| [e[:from], e[:to]] }.uniq.length}`"
  md.puts "- 仓库内 Pod 依赖边数量：`#{internal_edges.map { |e| [e[:from], e[:to]] }.uniq.length}`"
  md.puts "- Pod 间循环依赖数量：`#{internal_cycles.length}`"
  md.puts "- 已过滤同 Pod 内部 subspec 依赖数量：`#{ignored_internal_subspec_deps.length}`"
  md.puts "- 外部依赖来源注释文件数量：`#{source_podfile_paths.length}`"
  md.puts "- 已识别外部依赖来源链接数量：`#{source_urls.length}`"
  md.puts "- DSL 执行式解析 Podspec 数量：`#{parse_mode_counts.fetch('dsl', 0)}`"
  md.puts "- 静态兜底解析 Podspec 数量：`#{parse_mode_counts.fetch('static_fallback', 0)}`"
  md.puts
  md.puts "> 更易读的动态关系图见：`PodspecDependencies_interactive.html`，其中默认保留 2D 关系图，并新增可拖动旋转的 3D 空间图。"
  md.puts

  if podspec_paths.empty?
    md.puts '> 没有找到任何 `.podspec` 文件。'
    md.puts
    md.puts '<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>'
    next
  end

  unless errors.empty?
    md.puts '#### 解析失败的文件'
    md.puts
    md.puts '| Podspec | 错误 |'
    md.puts '|---|---|'
    errors.each do |path, message|
      rel = rel_path(path, root)
      md.puts "| **`#{md_escape(rel)}`** | #{md_escape(message)} |"
    end
    md.puts
  end

  unless fallback_reports.empty?
    md.puts '#### 使用静态兜底解析的文件'
    md.puts
    md.puts '这些文件无法通过 DSL 执行式解析完整展开，已自动回退到正则静态解析；若其中使用数组、lambda、helper 方法声明依赖，仍可能需要人工确认。'
    md.puts
    md.puts '| Pod | Podspec | DSL 解析失败原因 |'
    md.puts '|---|---|---|'
    fallback_reports.sort_by { |r| r[:name] }.each do |report|
      rel = rel_path(report[:path], root)
      md.puts "| #{pod_detail_link(report[:name], pod_names, bold: true)} | `#{md_escape(rel)}` | #{md_escape(report[:parse_error])} |"
    end
    md.puts
  end

  md.puts "## 一、总览 #{top_link}"
  md.puts
  md.puts '| Pod | Podspec | 下游依赖数量 | 下游依赖 | 上游依赖数量 | 上游依赖方 |'
  md.puts '|---|---|---:|---|---:|---|'

  reports.sort_by { |r| r[:name] }.each do |report|
    rel = rel_path(report[:path], root)
    deps = report[:deps].map { |d| d[:dep] }.uniq.sort
    dep_links = deps.map { |dep_name| dependency_link(dep_name, pod_names, source_urls) }.join(', ')
    incoming = incoming_edges_for(report[:name], all_edges, pod_names)
    incoming_names = incoming.map { |edge| source_owner_name(edge) }.uniq.sort
    incoming_links = incoming_names.map { |name| pod_detail_link(name, pod_names, bold: true) }.join(', ')
    md.puts "| #{pod_detail_link(report[:name], pod_names, bold: true)} | `#{md_escape(rel)}` | #{deps.length} | #{dep_links} | #{incoming_names.length} | #{incoming_links} |"
  end

  md.puts
  md.puts "## 二、0 下游依赖 Pod #{top_link}"
  md.puts

  if zero_dependency_reports.empty?
    md.puts '没有 0 下游依赖 Pod。'
  else
    md.puts '| Pod | Podspec |'
    md.puts '|---|---|'
    zero_dependency_reports.each do |report|
      rel = rel_path(report[:path], root)
      md.puts "| #{pod_detail_link(report[:name], pod_names, bold: true)} | `#{md_escape(rel)}` |"
    end
  end

  md.puts
  md.puts "## 三、已过滤的同 Pod 内部 subspec 依赖 #{top_link}"
  md.puts
  md.puts '这些依赖只表达同一个 Pod 内部 subspec 的包含关系，不参与 Pod 与 Pod 之间的循环依赖判断。'
  md.puts

  if ignored_internal_subspec_deps.empty?
    md.puts '> 未发现同 Pod 内部 subspec 依赖。'
  else
    md.puts '| Pod | 声明位置 | 内部依赖 | 行号 |'
    md.puts '|---|---|---|---:|'
    ignored_internal_subspec_deps.sort_by { |d| [d[:pod], d[:raw_declared_in], d[:raw_dep], d[:line]] }.each do |dep|
      md.puts "| #{pod_detail_link(dep[:pod], pod_names, bold: true)} | `#{md_escape(dep[:raw_declared_in])}` | `#{md_escape(dep[:raw_dep])}` | `#{dep[:line]}` |"
    end
  end

  md.puts
  md.puts "## 四、Pod 间循环依赖检测 #{top_link}"
  md.puts
  if internal_cycles.empty?
    md.puts '> 未发现仓库内 Pod 间循环依赖。'
  else
    md.puts '| 序号 | 循环链路 |'
    md.puts '|---:|---|'
    internal_cycles.each_with_index do |cycle, index|
      links = cycle.map { |name| pod_detail_link(name, pod_names, bold: true) }.join(' → ')
      md.puts "| #{index + 1} | #{links} |"
    end
  end

  md.puts
  md.puts "## 五、仓库内 Pod 相互依赖图 Mermaid #{top_link}"
  md.puts
  md.puts '只展示依赖目标也在本次扫描到的 `.podspec` 里存在的关系；同 Pod 内部 subspec 依赖已过滤，不计入 Pod 级依赖/循环分析；跨 Pod subspec 依赖显示为主 Pod 名；仓库内 Pod 匹配只采用精确名称，避免把 MJRefresh 误判为 MJRefreshExtra。'
  md.puts
  md.puts '```mermaid'
  md.puts internal_mermaid
  md.puts '```'
  md.puts

  md.puts "## 六、全部依赖图 Mermaid #{top_link}"
  md.puts
  md.puts '```mermaid'
  md.puts all_mermaid
  md.puts '```'
  md.puts

  md.puts "## 七、外部依赖引用关系 #{top_link}"
  md.puts
  md.puts '这里统计本次扫描到的 `.podspec` 对外部 Pod 的引用；同 Pod 内部 subspec 依赖已过滤；跨 Pod subspec 依赖显示为主 Pod 名；仓库内 Pod 匹配只采用精确名称，避免把 MJRefresh 误判为 MJRefreshExtra。外部来源链接匹配规则已放宽为：完全匹配 → base 名匹配 → 字符串包含匹配。'
  md.puts

  if external_groups.empty?
    md.puts '未发现外部依赖。'
  else
    md.puts '| 外部依赖 | 被引用数量 | 引用方 | 引用声明 |'
    md.puts '|---|---:|---|---|'

    external_groups.keys.sort.each do |dep_name|
      edges = external_groups[dep_name]
      callers = edges.map { |edge| source_owner_name(edge) }.uniq.sort
      caller_links = callers.map { |name| pod_detail_link(name, pod_names, bold: true) }.join(', ')
      declarations = edges.map { |edge| dependency_link(edge[:to], pod_names, source_urls) }.uniq.sort.join(', ')
      md.puts "| #{external_dependency_link(dep_name, source_urls)} | #{callers.length} | #{caller_links} | #{declarations} |"
    end
  end

  md.puts
  md.puts "## 八、明细 #{top_link}"

  reports.sort_by { |r| r[:name] }.each_with_index do |report, index|
    rel = rel_path(report[:path], root)

    md.puts
    md.puts %(### #{index + 1}、<font id="#{html_attr_escape(detail_anchor(report[:name]))}">#{md_escape(report[:name])}</font> #{top_link})
    md.puts
    md.puts "Podspec：`#{rel}`"
    md.puts

    incoming = incoming_edges_for(report[:name], all_edges, pod_names)

    unless incoming.empty?
      md.puts '- **上游依赖**'
      md.puts

      incoming_names = incoming.map { |edge| source_owner_name(edge) }.uniq.sort
      incoming_names.each do |name|
        md.puts "  - #{pod_detail_link(name, pod_names, bold: true)}"
      end

      md.puts
    end

    unless report[:deps].empty?
      md.puts '- **下游依赖**'
      md.puts

      downstream_names = report[:deps].map { |d| d[:dep] }.uniq.sort
      downstream_names.each do |dep_name|
        md.puts "  - #{dependency_link(dep_name, pod_names, source_urls, bold: true)}"
      end

      md.puts
    end
  end

  md.puts
  md.puts "## 九、生成的文件 #{top_link}"
  md.puts
  md.puts '- `PodspecDependencies_interactive.html`：可搜索、可拖拽、可缩放动态图，内置 `2D 关系图` / `3D 空间图` 切换'
  md.puts '- `PodspecDependencies.md`：本报告'
  md.puts '- `PodspecDependencies_all.mmd`：全部依赖 Mermaid 图源码'
  md.puts '- `PodspecDependencies_internal.mmd`：仓库内 Pod 相互依赖 Mermaid 图源码'
  md.puts '- `PodspecDependencies_all.dot`：全部依赖 Graphviz DOT 源码'
  md.puts '- `PodspecDependencies_internal.dot`：仓库内 Pod 相互依赖 Graphviz DOT 源码'
  md.puts
  md.puts '<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>'
end

puts md_path
puts html_path
RUBY
}
# ✅ 执行 Ruby 解析器
run_generator() {
  local generator="$1"
  local target_dir="$2"
  local report_dir="$3"
  local generator_exit_code=0

  info_echo "开始扫描并生成依赖报告..."

  /usr/bin/ruby "$generator" "$target_dir" "$report_dir" 2>&1 | tee -a "$LOG_FILE"
  generator_exit_code=${pipestatus[1]}

  rm -f "$generator"

  if [[ $generator_exit_code -ne 0 ]]; then
    error_echo "生成失败，状态码：$generator_exit_code"
    exit $generator_exit_code
  fi

  success_echo "依赖报告生成完成。"
}
# ✅ 如果系统可用 dot，则额外生成 Graphviz PNG 图片
generate_graphviz_png() {
  local report_dir="$1"
  local dot_all="$report_dir/PodspecDependencies_all.dot"
  local dot_internal="$report_dir/PodspecDependencies_internal.dot"
  local png_all="$report_dir/PodspecDependencies_all.png"
  local png_internal="$report_dir/PodspecDependencies_internal.png"

  if command -v dot >/dev/null 2>&1; then
    info_echo "开始生成 Graphviz PNG 图片..."
    dot -Tpng "$dot_all" -o "$png_all" 2>&1 | tee -a "$LOG_FILE" || true
    dot -Tpng "$dot_internal" -o "$png_internal" 2>&1 | tee -a "$LOG_FILE" || true

    warm_echo ""
    success_echo "已生成 Graphviz PNG："
    [[ -f "$png_all" ]] && color_echo "$png_all"
    [[ -f "$png_internal" ]] && color_echo "$png_internal"
  else
    warn_echo "未检测到 dot 命令，跳过 PNG 生成。"
  fi
}
# ✅ 打开主要产物
open_outputs() {
  local report_dir="$1"
  local md_file="$report_dir/PodspecDependencies.md"
  local html_file="$report_dir/PodspecDependencies_interactive.html"
  local png_internal="$report_dir/PodspecDependencies_internal.png"

  [[ -f "$html_file" ]] && open "$html_file"
  [[ -f "$md_file" ]] && open "$md_file"
  [[ -f "$png_internal" ]] && open "$png_internal"

  warm_echo ""
  success_echo "报告已生成：$report_dir"
  warm_echo ""
  note_echo "推荐先看动态 HTML：$html_file（已内置 2D / 3D 视图切换）"
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：【MacOS】🔍查询Xcode工程依赖关系.command' | jobs_intro_style title
  print -r -- '核心用途：执行“🔍查询Xcode工程依赖关系”对应的移动端项目自动化任务。' | jobs_intro_style body
  print -r -- '影响范围：可能修改项目依赖、生成文件、构建产物或开发工具配置。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '当前没有可交互输入，请在终端中重新运行。'
    return 1
  fi
  read -r "?$(jobs_prompt_render "👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：")" _
}
# 执行入口下沉后的完整业务流程和控制逻辑。
run_main_business_flow() {
  # 执行当前流程中的独立业务步骤：处理当前语句。
  : > "$LOG_FILE"

  # 初始化当前流程后续步骤需要使用的变量。
  local target_dir=""
  # 初始化当前流程后续步骤需要使用的变量。
  local report_dir=""
  # 初始化当前流程后续步骤需要使用的变量。
  local generator=""

  # 执行当前流程中的独立业务步骤：print_banner。
  print_banner

  # 1. 最高优先级：先检测脚本所在目录和上一层目录是否包含 Podfile。
  # 2. 自动检测成功时，不等待“准备好后按 Enter”，直接继续执行。
  # 3. 自动检测失败时，显示自述并等待回车，然后进入手动拖入目录流程。
  if detect_target_dir_from_script_location; then
    # 执行当前流程中的独立业务步骤：print_readme。
    print_readme "skip"
  else
    # 执行当前流程中的独立业务步骤：print_readme。
    print_readme "wait"
    # 执行当前流程中的独立业务步骤：prompt_target_dir。
    prompt_target_dir
  fi

  # 初始化当前流程后续步骤需要使用的变量。
  target_dir="$SELECTED_TARGET_DIR"

  # 检查当前步骤所需的环境、路径或输入条件。
  ensure_graphviz

  # 初始化当前流程后续步骤需要使用的变量。
  report_dir="$(prepare_report_dir "$target_dir")"
  # 初始化当前流程后续步骤需要使用的变量。
  generator="$report_dir/.generate_podspec_dependency_report.rb"

  # 执行当前流程中的独立业务步骤：write_generator_script。
  write_generator_script "$generator"
  # 执行当前流程中的独立业务步骤：run_generator。
  run_generator "$generator" "$target_dir" "$report_dir"
  # 执行当前流程中的独立业务步骤：generate_graphviz_png。
  generate_graphviz_png "$report_dir"
  # 执行当前流程中的独立业务步骤：open_outputs。
  open_outputs "$report_dir"
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
# 将 Homebrew shellenv 写入用户配置并在当前终端生效。
inject_shellenv_block() {
  local profile_file="$1"
  local shellenv="$2"
  local header="# >>> homebrew_env 环境变量 >>>"
  local footer="# <<< homebrew_env 环境变量 <<<"
  local tmp_file=""
  if [[ -z "$profile_file" || -z "$shellenv" ]]; then
    error_echo "缺少参数：inject_shellenv_block <profile_file> <shellenv>"
    return 1
  fi
  mkdir -p "$(dirname "$profile_file")"
  touch "$profile_file"
  if grep -Fq "$shellenv" "$profile_file"; then
    info_echo "Homebrew shellenv 已存在：$profile_file"
  else
    if grep -Fq "$header" "$profile_file"; then
      warn_echo "检测到旧 Homebrew 环境变量块，将替换：$profile_file"
      tmp_file="$(mktemp)"
      /usr/bin/awk -v header="$header" -v footer="$footer" '
        $0 == header { skip = 1; next }
        $0 == footer { skip = 0; next }
        skip != 1 { print }
      ' "$profile_file" > "$tmp_file" && mv "$tmp_file" "$profile_file"
    fi

    {
      echo ""
      echo "$header"
      echo "$shellenv"
      echo "$footer"
    } >> "$profile_file"

    success_echo "已写入 Homebrew 环境变量：$profile_file"
  fi
  eval "$shellenv"
  success_echo "Homebrew shellenv 已在当前终端生效"
}
# 初始化脚本运行环境和后续流程所需状态。
initialize_script_runtime() {
  set -u
}
# 编排脚本的高层业务流程。
main() {
  # 展示脚本内置自述，并按运行入口完成防误触确认。
  show_script_intro_and_wait
  # 初始化 Shell 选项、日志、依赖和入口运行状态。
  initialize_script_runtime
  # 执行入口下沉后的完整业务流程。
  run_main_business_flow "$@"
}

main "$@"
