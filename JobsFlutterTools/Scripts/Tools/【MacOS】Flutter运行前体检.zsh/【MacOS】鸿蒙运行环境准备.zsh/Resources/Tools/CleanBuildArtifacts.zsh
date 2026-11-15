#!/bin/zsh
# 清理构建产物：只识别传入目录，不向上寻找工程；先列出范围，再确认删除。
# Flutter 优先；其次为 OpenHarmony、Android、iOS/Xcode；菜单识别逻辑见 DependencyProjectValidator.swift。
# 不执行工程脚本，不清理共享缓存、Pods、锁文件、签名或自定义输出目录。
# 用法：zsh CleanBuildArtifacts.zsh <工程目录> [--detect|--dry-run|--yes] [--android-openharmony]

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

jobs_clean_file() { [[ -f "$1" && ! -L "$1" ]]; }
jobs_clean_dir() { [[ -d "$1" && ! -L "$1" ]]; }
jobs_clean_gradle() {
  jobs_clean_file "$1/build.gradle" || jobs_clean_file "$1/build.gradle.kts"
}
jobs_clean_settings() {
  jobs_clean_file "$1/settings.gradle" || jobs_clean_file "$1/settings.gradle.kts"
}
# 仅解析 dependencies.flutter.sdk；支持常见块映射和单行 flow，不执行 YAML 或工程代码。
jobs_clean_flutter() {
  jobs_clean_file "$1/pubspec.yaml" || return 1
  /usr/bin/perl - "$1/pubspec.yaml" <<'PERL'
use strict;
use warnings;
use Encode qw(decode FB_CROAK);
use JSON::PP ();

# 去掉字段两侧空白，不改写带引号字符串中的内容。
sub trim {
  my ($source) = @_;
  $source =~ s/^\s+|\s+$//g;
  return $source;
}
# 只寻找引号和 flow 容器之外的分隔符；# 还必须位于空白之后。
sub delimiter {
  my ($source, $wanted, $comments) = @_;
  my @characters = split //, $source;
  my ($quote, $depth, $escaped) = ('', 0, 0);
  for (my $index = 0; $index < @characters; $index++) {
    my $current = $characters[$index];
    if (length $quote) {
      if ($quote eq '"' && $current eq '\\' && !$escaped) {
        $escaped = 1;
        next;
      }
      if ($current eq $quote && !$escaped) {
        if ($quote eq "'" && $index + 1 < @characters && $characters[$index + 1] eq "'") {
          $index++;
          next;
        }
        $quote = '';
      }
      $escaped = 0;
    } elsif ($current eq '"' || $current eq "'") {
      $quote = $current;
    } elsif ($current eq $wanted && $depth == 0) {
      return $index if !$comments || $index == 0 || $characters[$index - 1] =~ /\s/;
    } elsif ($current eq '{' || $current eq '[') {
      $depth++;
    } elsif ($current eq '}' || $current eq ']') {
      $depth--;
    }
  }
  return undef;
}
# 解码普通值和单双引号标量；不支持 YAML 标签、锚点或执行型扩展。
sub scalar_value {
  my $source = trim($_[0]);
  return undef if !length $source;
  if (substr($source, 0, 1) eq '"') {
    my $value = eval { JSON::PP->new->allow_nonref->decode($source) };
    return undef if $@ || !defined($value) || ref($value);
    return $value;
  }
  if (substr($source, 0, 1) eq "'") {
    return undef if length($source) < 2 || substr($source, -1) ne "'";
    my $body = substr($source, 1, length($source) - 2);
    my $unpaired = $body;
    $unpaired =~ s/''//g;
    return undef if $unpaired =~ /'/;
    $body =~ s/''/'/g;
    return $body;
  }
  return undef if $source =~ /[{}\[\],:#&*!|>"']/;
  return $source;
}
# 解析一行或一个 flow 成员的键值，忽略引号外的尾注释。
sub mapping_pair {
  my ($source) = @_;
  my $hash = delimiter($source, '#', 1);
  $source = trim(substr($source, 0, $hash)) if defined $hash;
  my $colon = delimiter($source, ':', 0);
  return undef if !defined $colon;
  my $key = scalar_value(substr($source, 0, $colon));
  return undef if !defined($key) || !length($key);
  return [$key, trim(substr($source, $colon + 1))];
}
# 解析单行花括号映射，重复键或缺值一律拒绝。
sub flow_mapping {
  my $source = trim($_[0]);
  return undef if substr($source, 0, 1) ne '{' || substr($source, -1) ne '}';
  my $remaining = trim(substr($source, 1, length($source) - 2));
  my %result;
  while (length $remaining) {
    my $comma = delimiter($remaining, ',', 0);
    my $part = defined($comma) ? substr($remaining, 0, $comma) : $remaining;
    my $pair = mapping_pair($part);
    return undef if !defined($pair) || exists($result{$pair->[0]}) || !length($pair->[1]);
    $result{$pair->[0]} = $pair->[1];
    last if !defined $comma;
    $remaining = trim(substr($remaining, $comma + 1));
  }
  return \%result;
}
# 按缩进定位唯一 dependencies → flutter → sdk，与菜单的保守识别规则一致。
sub declares_flutter_sdk {
  my ($text) = @_;
  return 0 if index($text, "\0") >= 0;
  $text =~ s/\r\n/\n/g;
  my @entries;
  for my $line (split /\n/, $text, -1) {
    $line =~ s/^\x{FEFF}//;
    my ($spaces) = $line =~ /^( *)/;
    my $indent = length($spaces);
    my $trimmed = trim($line);
    next if !length($trimmed) || substr($trimmed, 0, 1) eq '#';
    my ($prefix) = $line =~ /^(\s*)/;
    return 0 if $trimmed eq '---' || $trimmed eq '...' || $prefix =~ /\t/;
    my $pair = mapping_pair(substr($line, $indent));
    push @entries, [$indent, defined($pair) ? @$pair : ('', '')];
  }
  my @roots = grep { $entries[$_][0] == 0 && $entries[$_][1] eq 'dependencies' } 0 .. $#entries;
  return 0 if @roots != 1;
  my $root = $roots[0];
  if (length $entries[$root][2]) {
    my $dependencies = flow_mapping($entries[$root][2]);
    return 0 if !defined($dependencies) || !exists($dependencies->{flutter});
    my $flutter = flow_mapping($dependencies->{flutter});
    return 0 if !defined($flutter) || !exists($flutter->{sdk});
    return (scalar_value($flutter->{sdk}) // '') eq 'flutter';
  }
  my $end = $root + 1;
  $end++ while $end < @entries && $entries[$end][0] != 0;
  return 0 if $end == $root + 1;
  my @children = @entries[$root + 1 .. $end - 1];
  my $dependency_indent = $children[0][0];
  for my $entry (@children) {
    $dependency_indent = $entry->[0] if $entry->[0] < $dependency_indent;
  }
  return 0 if $dependency_indent <= 0;
  my @flutter_positions = grep { $children[$_][0] == $dependency_indent && $children[$_][1] eq 'flutter' } 0 .. $#children;
  return 0 if @flutter_positions != 1;
  my $flutter_index = $flutter_positions[0];
  if (length $children[$flutter_index][2]) {
    my $flutter = flow_mapping($children[$flutter_index][2]);
    return 0 if !defined($flutter) || !exists($flutter->{sdk});
    return (scalar_value($flutter->{sdk}) // '') eq 'flutter';
  }
  my $flutter_end = $flutter_index + 1;
  $flutter_end++ while $flutter_end < @children && $children[$flutter_end][0] > $dependency_indent;
  return 0 if $flutter_end == $flutter_index + 1;
  my @fields = @children[$flutter_index + 1 .. $flutter_end - 1];
  my $sdk_indent = $fields[0][0];
  for my $entry (@fields) {
    $sdk_indent = $entry->[0] if $entry->[0] < $sdk_indent;
  }
  return 0 if $sdk_indent <= $dependency_indent;
  my @sdk = grep { $_->[0] == $sdk_indent && $_->[1] eq 'sdk' } @fields;
  return @sdk == 1 && (scalar_value($sdk[0][2]) // '') eq 'flutter';
}

exit 1 if !defined($ARGV[0]) || !-f $ARGV[0] || -s $ARGV[0] > 1_048_576;
open my $manifest, '<:raw', $ARGV[0] or exit 1;
my $bytes = do { local $/; <$manifest> };
close $manifest;
my $text = eval { decode('UTF-8', $bytes, FB_CROAK) };
exit 1 if $@ || !defined $text;
exit(declares_flutter_sdk($text) ? 0 : 1);
PERL
}

# Hvigor 工程/模块的明确标记；不能只凭文件夹名 ohos 或普通 build 目录判断。
jobs_clean_harmony_project() {
  jobs_clean_dir "$1" &&
    { jobs_clean_file "$1/hvigorfile.ts" || jobs_clean_file "$1/hvigorfile.js"; } &&
    jobs_clean_file "$1/build-profile.json5" && jobs_clean_file "$1/oh-package.json5" &&
    { jobs_clean_file "$1/AppScope/app.json5" || jobs_clean_file "$1/src/main/module.json5"; }
}

jobs_clean_scan_harmony() {
  local directory="$1" child
  if jobs_clean_file "$directory/build-profile.json5" && jobs_clean_file "$directory/src/main/module.json5"; then
    harmony_dirs+=("$directory")
  fi
  for child in "$directory"/*(N/); do
    [[ -L "$child" ]] && continue
    case "${child:t}" in
      build|node_modules|oh_modules|Pods|vendor|third_party|DerivedData|*.xcodeproj|*.xcworkspace) continue ;;
    esac
    [[ -e "$child/.git" || -e "$child/pubspec.yaml" || -e "$child/AppScope/app.json5" ]] && continue
    jobs_clean_settings "$child" && continue
    jobs_clean_scan_harmony "$child" || return 1
  done
  return 0
}

jobs_clean_add_harmony() {
  local directory="$1" module
  harmony_dirs=()
  jobs_clean_scan_harmony "$directory" || return 1
  candidates+=("$directory/build" "$directory/.hvigor")
  for module in "${harmony_dirs[@]}"; do
    candidates+=("$module/build" "$module/.hvigor")
  done
}

# 只扫描当前 Gradle 构建内部；链接、缓存、依赖和嵌套的独立工程不进入。
jobs_clean_scan_gradle() {
  local directory="$1" child script
  if jobs_clean_gradle "$directory"; then
    gradle_dirs+=("$directory")
    if jobs_clean_file "$directory/src/main/AndroidManifest.xml"; then android_found=1; fi
    for script in "$directory/build.gradle" "$directory/build.gradle.kts"; do
      if jobs_clean_file "$script" && /usr/bin/perl -0777 -pe 's{/\*.*?\*/}{}gs; s{//[^\n]*}{}g' "$script" | /usr/bin/grep -Eq 'com\.android\.(application|library|test|dynamic-feature|asset-pack)' ; then
        android_found=1
      fi
    done
  fi
  for child in "$directory"/*(N/); do
    [[ -L "$child" ]] && continue
    case "${child:t}" in
      build|node_modules|oh_modules|Pods|vendor|third_party|DerivedData) continue ;;
      *.xcodeproj|*.xcworkspace) continue ;;
    esac
    [[ -e "$child/.git" || -e "$child/pubspec.yaml" ]] && continue
    jobs_clean_settings "$child" && continue
    jobs_clean_harmony_project "$child" && continue
    jobs_clean_scan_gradle "$child" || return 1
  done
  return 0
}

jobs_clean_android() {
  local directory="$1"
  jobs_clean_dir "$directory" || return 1
  jobs_clean_gradle "$directory" || jobs_clean_settings "$directory" || return 1
  gradle_dirs=()
  android_found=0
  jobs_clean_scan_gradle "$directory" || return 1
  [[ "$android_found" == 1 ]]
}

jobs_clean_ios() {
  local project
  jobs_clean_dir "$1" || return 1
  for project in "$1"/*.xcodeproj(N/); do
    [[ -L "$project" ]] && continue
    if jobs_clean_file "$project/project.pbxproj" &&
       /usr/bin/grep -Eq '(SDKROOT[[:blank:]]*=[[:blank:]]*"?iphone(os|simulator)|IPHONEOS_DEPLOYMENT_TARGET[[:blank:]]*=|SUPPORTED_PLATFORMS[[:blank:]]*=.*iphone)' "$project/project.pbxproj"; then
      return 0
    fi
  done
  return 1
}

jobs_clean_add_android() {
  local directory="$1" module
  candidates+=("$directory/build" "$directory/.gradle" "$directory/.kotlin")
  for module in "${gradle_dirs[@]}"; do
    candidates+=("$module/build" "$module/.cxx" "$module/.externalNativeBuild")
  done
}

# Xcode 默认产物在用户 DerivedData 下；仅接受 info.plist 精确归属当前工程的 Build。
jobs_clean_owned_derived_data() {
  local directory="$1" workspace project_root
  [[ "$derived_data" == "${derived_data:A}" ]] || return 1
  jobs_clean_dir "$derived_data" && jobs_clean_dir "$directory" && jobs_clean_file "$directory/info.plist" || return 1
  [[ "${directory:h}" == "$derived_data" ]] || return 1
  workspace="$(/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' "$directory/info.plist" 2>/dev/null)" || return 1
  jobs_clean_dir "$workspace" || return 1
  [[ "$workspace" == "${workspace:A}" ]] || return 1
  case "$workspace" in *.xcodeproj|*.xcworkspace) ;; *) return 1 ;; esac
  for project_root in "${ios_roots[@]}"; do
    [[ "${workspace:h}" == "$project_root" ]] && jobs_clean_ios "$project_root" && return 0
  done
  return 1
}

# 对白名单路径逐层验证，拒绝指向工程外的链接；产物内部的链接只由 rm 删除链接本身。
jobs_clean_validate() {
  local target="$1" current="$1"
  jobs_clean_dir "$root" && [[ "$root" == "${root:A}" ]] || return 1
  if [[ "$target" != "$root/"* ]]; then
    [[ "${target:t}" == Build ]] && jobs_clean_owned_derived_data "${target:h}" || return 1
    [[ ! -L "$target" && ( ! -e "$target" || -d "$target" ) ]]
    return $?
  fi
  while [[ "$current" != "$root" ]]; do
    if [[ -L "$current" ]]; then
      print -u2 -r -- "拒绝清理链接路径：$current"
      return 1
    fi
    current="${current:h}"
  done
  [[ ! -e "$target" || -d "$target" ]] || { print -u2 -r -- "产物路径不是目录：$target"; return 1; }
}

jobs_clean_main() {
  emulate -L zsh
  setopt localoptions pipefail
  local input="${1:-}" mode='' scope='' argument root kind='' target reply android_found=0 derived_data
  local -a gradle_dirs harmony_dirs candidates existing ios_roots
  local -U candidates
  [[ $# -ge 1 && $# -le 3 ]] || {
    print -u2 -- '用法：CleanBuildArtifacts.zsh <工程目录> [--detect|--dry-run|--yes] [--android-openharmony]'; return 1
  }
  for argument in "${@:2}"; do
    case "$argument" in
      --detect|--dry-run|--yes)
        [[ -z "$mode" ]] || { print -u2 -- '执行模式不能重复指定。'; return 1; }
        mode="$argument"
        ;;
      --android-openharmony)
        [[ -z "$scope" ]] || { print -u2 -- '清理范围不能重复指定。'; return 1; }
        scope=android-openharmony
        ;;
      *) print -u2 -r -- "未知选项：$argument"; return 1 ;;
    esac
  done
  jobs_clean_dir "$input" || { print -u2 -- '目标必须是实际文件夹，不能是文件或符号链接。'; return 1; }
  root="${input:A}"
  derived_data="${HOME:A}/Library/Developer/Xcode/DerivedData"
  [[ "$root" != / && "$root" != "${HOME:A}" ]] || { print -u2 -- '不能清理磁盘或用户主目录。'; return 1; }
  if jobs_clean_flutter "$root"; then
    kind=Flutter
    if [[ "$scope" == android-openharmony ]]; then
      # 两平台入口不删除共享 build/、.dart_tool/，避免连带清理 iOS 和桌面产物。
      if jobs_clean_android "$root/android"; then
        jobs_clean_add_android "$root/android"
        candidates+=("$root/build/app")
      fi
      if jobs_clean_harmony_project "$root/ohos"; then
        jobs_clean_add_harmony "$root/ohos" || return 1
        candidates+=("$root/build/ohos")
      fi
    else
      candidates+=("$root/build" "$root/.dart_tool")
      if jobs_clean_android "$root/android"; then jobs_clean_add_android "$root/android"; fi
      if jobs_clean_ios "$root/ios"; then
        ios_roots+=("$root/ios")
        candidates+=("$root/ios/build" "$root/ios/DerivedData" "$root/ios/Flutter/ephemeral")
      fi
      for target in windows linux macos; do
        jobs_clean_dir "$root/$target" && candidates+=("$root/$target/flutter/ephemeral" "${root}/${target}/Flutter/ephemeral")
      done
      if jobs_clean_harmony_project "$root/ohos"; then jobs_clean_add_harmony "$root/ohos" || return 1; fi
    fi
  elif jobs_clean_harmony_project "$root"; then
    kind=OpenHarmony
    jobs_clean_add_harmony "$root" || return 1
  elif jobs_clean_android "$root"; then
    kind=Android
    candidates=()
    jobs_clean_add_android "$root"
  elif jobs_clean_ios "$root"; then
    [[ "$scope" != android-openharmony ]] || { print -u2 -- '此入口只清理 Flutter、Android 或 OpenHarmony 工程的 Android / OpenHarmony 产物。'; return 1; }
    kind=iOS/Xcode
    ios_roots+=("$root")
    candidates=("$root/build" "$root/DerivedData")
  else
    print -u2 -- '未识别为当前层的 iOS/Xcode、Android、Flutter 或 OpenHarmony 工程，未删除任何文件。'
    return 1
  fi
  # 只读接口供识别一致性测试及未来调用方使用；不询问、不删除。
  if [[ "$mode" == --detect ]]; then print -r -- "$kind"; return 0; fi
  if (( ${#ios_roots} > 0 )) && jobs_clean_dir "$derived_data"; then
    for target in "$derived_data"/*(N/); do
      jobs_clean_owned_derived_data "$target" && candidates+=("$target/Build")
    done
  fi
  print -r -- "工程类型：$kind"
  print -r -- "工程目录：$root"
  [[ "$scope" == android-openharmony ]] && print -- '清理范围：Android / OpenHarmony；保留 iOS、桌面平台与 Flutter 共享缓存。'
  # 整份计划先验证，防止后面的危险路径导致只清理一半才报错。
  for target in "${candidates[@]}"; do
    jobs_clean_validate "$target" || return 1
    [[ -d "$target" ]] && existing+=("$target")
  done
  if (( ${#existing} == 0 )); then print -- '没有可清理的构建产物。'; return 0; fi
  print -- '将删除以下属于此工程的构建产物（请先停止正在进行的构建）：'
  printf '  %s\n' "${existing[@]}"
  [[ "$mode" == --dry-run ]] && return 0
  if [[ "$mode" != --yes ]]; then
    read -r "reply?输入 CLEAN 确认清理，其它输入取消：" || return 1
    [[ "$reply" == CLEAN ]] || { print -- '已取消，未删除任何文件。'; return 0; }
  fi
  case "$kind" in
    Flutter) jobs_clean_flutter "$root" || return 1 ;;
    Android) jobs_clean_android "$root" || return 1 ;;
    OpenHarmony) jobs_clean_harmony_project "$root" || return 1 ;;
    iOS/Xcode) jobs_clean_ios "$root" || return 1 ;;
  esac
  for target in "${existing[@]}"; do jobs_clean_validate "$target" || return 1; done
  for target in "${existing[@]}"; do
    jobs_clean_validate "$target" || return 1
    /bin/rm -rf -- "$target" || { print -u2 -r -- "清理失败：$target"; return 1; }
  done
  print -- '构建产物清理完成。源码、锁文件、依赖与全局缓存保留。'
}

jobs_clean_main "$@"
