#!/bin/zsh
# 脚本自述：
# - 脚本名称：EnableFinderExtension.zsh
# - 核心用途：在 Xcode 构建后注册、启用并刷新 JobsXcodeOpener Finder Sync Extension。
# - 影响范围：只影响 com.jobs.JobsXcodeOpener.FinderSyncExtension 和 Finder 进程刷新。
# - 运行提示：由 Xcode Build Phase 自动调用，不需要手动运行。

# JOBS_SOURCE_LAYOUT_V1：源码同名包装与发布旧平铺目录分别解析，不改变运行时资源名。
# 保留实际文件路径；只有源码同名包装才向上还原原资源目录。
jobs_layout_directory() {
  local file="${1:A}" directory="${1:A:h}" levels="${2:-0}"
  [[ "${directory:t}" != "${file:t}" ]] || directory="${directory:h}"
  while (( levels > 0 )); do
    directory="${directory:h}"
    (( levels -= 1 ))
  done
  print -r -- "$directory"
}
# 优先兼容已发布的平铺文件，再尝试源码中的同名包装；不跟随链接文件。
jobs_layout_file() {
  local file="$1" directory="${1:h}" name="${1:t}" candidate="" prefixed=""
  if [[ -f "$file" && ! -L "$file" ]]; then
    print -r -- "$file"
    return 0
  fi
  case "$name" in
    EnableFinderExtension.zsh) prefixed="【MacOS@Xcode】$name" ;;
    *.zsh|*.command|*.sh) [[ "$name" == '【MacOS'* ]] && prefixed="$name" || prefixed="【MacOS】$name" ;;
    *.jxa) prefixed="$name" ;;
    *) print -r -- "$file"; return 0 ;;
  esac
  [[ "${directory:t}" != "$name" ]] || directory="${directory:h}"
  candidate="$directory/$prefixed/$prefixed"
  if [[ ! -L "$directory/$prefixed" && -f "$candidate" && ! -L "$candidate" ]]; then
    print -r -- "$candidate"
  else
    print -r -- "$file"
  fi
}

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

LOG_FILE="/tmp/JobsXcodeOpenerBuildPhase.log"
REFRESH_MARKER="/tmp/JobsXcodeOpenerNeedsFinderRestart"
EXTENSION_ID="com.jobs.JobsXcodeOpener.FinderSyncExtension"
APP_PROCESS_NAME="JobsXcodeOpener"
APP_PATH="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
EXTENSION_PATH="${APP_PATH}/Contents/PlugIns/JobsXcodeFinderSync.appex"

# 展示固定自述；Xcode 构建为已声明自动入口，手动运行仍需确认。
show_script_intro_and_wait() {
  print -r -- '━━━━━━━━━━ JobsXcodeOpener 构建后启用 Finder 扩展 ━━━━━━━━━━'
  print -r -- '用途：注册并启用当前 App 内置扩展；成功后重启 Finder 刷新菜单。'
  print -r -- "日志：${LOG_FILE}；外层安装器与隔离构建可用 JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1 跳过。"
  print -r -- '取消：手动运行时按 Ctrl+C；Xcode 构建中可停止构建。'
  if [[ "${JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE:-0}" == 1 ]]; then
    return 0
  fi
  if [[ -n "${TARGET_BUILD_DIR:-}" && -n "${WRAPPER_NAME:-}" ]]; then
    print -r -- '运行策略：Xcode Build Phase 自动执行已声明的注册流程。'
    return 0
  fi
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '错误：缺少 Xcode 构建上下文且无法交互；未修改扩展。'
    exit 1
  fi
  read -r "?$(jobs_prompt_render '手动运行仅支持已有 Xcode 构建上下文；按回车检查，Ctrl+C 取消：')" _ || exit 1
}
# 在跳过开关处理后初始化当前脚本，拒绝不完整的构建路径。
initialize_build_context() {
  setopt NO_NOMATCH
  set +e
  if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${WRAPPER_NAME:-}" || "${WRAPPER_NAME}" != 'JobsXcodeOpener.app' ]]; then
    print -u2 -r -- '错误：当前不是此 App 的 Xcode 构建上下文；未修改扩展。'
    exit 1
  fi
}
# 查询当前 Finder Sync 扩展注册状态。
status_line() {
  local lines=""
  local current_line=""
  lines="$(/usr/bin/pluginkit -m -p com.apple.FinderSync -A -v 2>/dev/null | /usr/bin/grep -F "${EXTENSION_ID}" || true)"
  current_line="$(print -r -- "${lines}" | /usr/bin/grep -F "${EXTENSION_PATH}" | /usr/bin/head -n 1 || true)"
  if [[ -n "${current_line}" ]]; then
    print -r -- "${current_line}"
    return 0
  fi

  print -r -- "${lines}" | /usr/bin/head -n 1
}
# 判断外层安装脚本是否已经接管扩展注册和启用。
should_skip_build_phase_enable() {
  [[ "${JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE:-0}" == "1" ]]
}
# 外层安装脚本接管时跳过 Build Phase 内的注册副作用。
skip_enable_when_requested() {
  if should_skip_build_phase_enable; then
    echo "skip build phase enable: outer installer will register and enable Finder Sync extension"
    exit 0
  fi
}
# 停止上一轮 Xcode 调试残留的宿主 App。
stop_stale_host_app() {
  /usr/bin/pkill -x "${APP_PROCESS_NAME}" 2>/dev/null || true
  echo "stop stale host app exit=$?"
}
# 注册当前构建产物里的 Finder Sync 扩展。
register_extension() {
  /usr/bin/pluginkit -a "${EXTENSION_PATH}"
  echo "pluginkit register exit=$?"
}
# 请求系统启用 Finder Sync 扩展。
enable_extension() {
  /usr/bin/pluginkit -e use -i "${EXTENSION_ID}"
  echo "pluginkit enable exit=$?"
}
# 等待 pluginkit 异步登记完成，并在扩展出现后再次启用到 + 状态。
wait_until_extension_enabled() {
  local attempt=""
  local line=""

  for attempt in {1..90}; do
    line="$(status_line)"
    echo "poll ${attempt}=${line}" >&2
    if [[ "${line}" == +* ]]; then
      print -r -- "${line}"
      return 0
    fi
    if [[ -n "${line}" ]]; then
      /usr/bin/pluginkit -e use -i "${EXTENSION_ID}"
      echo "pluginkit retry enable ${attempt} exit=$?" >&2
    fi
    if (( attempt % 10 == 0 )); then
      /usr/bin/pluginkit -a "${EXTENSION_PATH}"
      echo "pluginkit retry register ${attempt} exit=$?" >&2
    fi
    /bin/sleep 0.5
  done

  return 1
}
# 重启 Finder，让 Finder Sync 右键菜单缓存立刻刷新。
restart_finder() {
  echo "restart Finder for FinderSync cache"
  /usr/bin/killall Finder
  echo "killall Finder exit=$?"
}
# 完成一次构建后的扩展注册、启用和 Finder 刷新。
run_enable_flow() {
  echo "[$(/bin/date)] Enable Finder Extension"
  echo "APP_PATH=${APP_PATH}"
  echo "EXTENSION_PATH=${EXTENSION_PATH}"

  local before_line=""
  local after_line=""
  before_line="$(status_line)"
  echo "before=${before_line}"
  stop_stale_host_app

  if [[ ! -d "${EXTENSION_PATH}" ]]; then
    echo "missing extension path"
    /usr/bin/touch "${REFRESH_MARKER}"
    return 0
  fi

  register_extension
  enable_extension
  after_line="$(wait_until_extension_enabled)"
  echo "after=${after_line}"

  if [[ "${after_line}" == +* ]]; then
    restart_finder
    /bin/rm -f "${REFRESH_MARKER}"
    return 0
  fi

  echo "extension not enabled after polling, keep marker for App launch"
  /usr/bin/touch "${REFRESH_MARKER}"
}
# 保存注册诊断；扩展激活失败交给宿主重试，不阻断 App 构建。
enable_extension_with_logging() {
  run_enable_flow >> "${LOG_FILE}" 2>&1
  return 0
}
# 编排 Xcode Build Phase 自动启用扩展流程。
main() {
  show_script_intro_and_wait # 先说明自动注册范围、跳过方式和日志位置。
  skip_enable_when_requested # 外层安装脚本接管时，避免 Build Phase 重复注册并卡住构建。
  initialize_build_context # 初始化 zsh 并核验当前 App 构建上下文。
  enable_extension_with_logging # 注册并启用扩展，保存诊断并按需刷新 Finder。
}

main "$@"
