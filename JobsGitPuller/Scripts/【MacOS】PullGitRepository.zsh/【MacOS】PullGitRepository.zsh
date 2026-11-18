#!/bin/zsh
# 脚本自述：
# - 脚本名称：PullGitRepository.zsh
# - 核心用途：拉取当前工作树分支的上游，冲突时提供还原、放弃改动或提交后重试。
# - 影响范围：仅当前 Git 工作树；不递归更新子模块，不推送，恢复快照保存在 Git 元数据中。
# - 运行提示：先阅读内置自述并回车；未提交内容再次回车确认，丢弃必须输入 YES。

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

typeset REPO='' PULL_GIT_DIR='' BRANCH='' REMOTE='' MERGE_REF='' ORIGINAL_HEAD=''
typeset SESSION='' REF_BASE='' SNAPSHOT='' INITIAL_SNAPSHOT='' ATTEMPT_HEAD='' TARGET='' LOG_FILE='' LOCK_DIR='' CONFIRMED_TOKEN=''
typeset LOCK_OWNED=0 TRANSACTION_ACTIVE=0 APPLY_ATTEMPTED=0
typeset -a UNTRACKED_PATHS=()

# 将可能含凭据的命令输出脱敏，日志与终端使用同一展示副本。
redact_stream() {
    /usr/bin/perl -pe 's{([a-zA-Z][a-zA-Z0-9+.-]*://)[^/\s]*\@}{$1***\@}g; s{([a-zA-Z][a-zA-Z0-9+.-]*://[^\s?#]+)[?#][^\s]*}{$1?[redacted]}g; s/\e\[[0-9;]*[A-Za-z]//g'
}
# 同步显示并保存纯文本业务日志。
log() {
    if [[ -n "$LOG_FILE" ]]; then
        print -r -- "$*" | redact_stream | jobs_prompt_tee "$LOG_FILE"
    else
        print -r -- "$*" | redact_stream
    fi
}
# 执行 Git 并保留真实退出码，禁用隐式递归与自动 stash。
run_git() {
    local result
    LC_ALL=C git -C "$REPO" -c submodule.recurse=false -c merge.autoStash=false "$@" 2>&1 | redact_stream | /usr/bin/tee "$SESSION/last-git-output" | /usr/bin/tee -a "$LOG_FILE"
    result=${pipestatus[1]}
    return "$result"
}
# 读取一行；空格不是空输入，EOF 不构成确认。
read_answer() {
    jobs_prompt_output print -n -r -- "$1"
    IFS= read -r REPLY
}
# 先只读判断 Git 归属，非 Git 目录静默退出且不创建日志。
show_script_intro_and_wait() {
    local selected="${1:-$PWD}" answer=''
    [[ -d "$selected" ]] || exit 0
    if [[ -n "${GIT_DIR+x}${GIT_WORK_TREE+x}${GIT_INDEX_FILE+x}${GIT_COMMON_DIR+x}${GIT_NAMESPACE+x}" ]]; then
        print -u2 '✖ 检测到改变仓库或索引归属的 GIT_* 环境变量，请在普通终端中运行。'
        exit 1
    fi
    command -v git >/dev/null 2>&1 || { print -u2 '✖ 未找到 Git，请先安装命令行工具。'; exit 1; }
    [[ "$(git -C "$selected" rev-parse --is-inside-work-tree 2>/dev/null)" == true ]] || exit 0
    REPO="$(git -C "$selected" rev-parse --show-toplevel)" || exit 1
    local title='JobsGitPuller｜拉取 Git 到最新'
    if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" ]]; then
        print -r -- $'\033[1;31m'"$title"$'\033[0m'
        print -r -- $'\033[0;34m1、拉取当前分支上游；保护未提交内容，冲突时三选一。\033[0m'
    else
        print -r -- "$title"
        print -r -- '1、拉取当前分支上游；保护未提交内容，冲突时三选一。'
    fi
    print -r -- "2、作用目录：$REPO"
    print -r -- '3、不递归子模块、不推送；放弃改动需要 YES。请先停止其它 Git 操作和文件编辑。'
    print -r -- '4、日志与恢复锚点保存在当前工作树 Git 元数据的 jobs-git-pull/ 中。Ctrl+C 取消；事务中断保留现场。'
    [[ -t 0 ]] || { print -u2 '✖ 请在可交互终端中运行。'; exit 1; }
    read_answer '已了解用途，直接回车继续；任意字符取消：' || exit 0
    [[ -z "$REPLY" ]] || exit 0
}
# 初始化本工作树互斥锁、私有日志和中断清理。
initialize_runtime() {
    setopt NO_NOMATCH PIPE_FAIL
    umask 077
    PULL_GIT_DIR="$(git -C "$REPO" rev-parse --absolute-git-dir)" || exit 1
    local common_dir="$(git -C "$REPO" rev-parse --git-common-dir)"
    [[ "$common_dir" == /* ]] || common_dir="$REPO/$common_dir"
    LOCK_DIR="${common_dir:A}/jobs-git-pull.lock"
    /bin/mkdir "$LOCK_DIR" 2>/dev/null || { print -u2 "✖ 已有拉取会话或遗留锁：$LOCK_DIR；确认旧进程结束后再处理。"; exit 1; }
    LOCK_OWNED=1
    SESSION="$PULL_GIT_DIR/jobs-git-pull/$(/bin/date +%Y%m%d-%H%M%S)-$$-$RANDOM"
    /bin/mkdir -p "$SESSION" || exit 1
    LOG_FILE="$SESSION/run.log"
    : > "$LOG_FILE" || exit 1
    REF_BASE="refs/jobs-git-pull/${SESSION:t}"
    log "ℹ 日志：$LOG_FILE"
}
# 退出时仅清理本会话锁，不自动 reset 现场；终端载体由外层负责清理。
finish_runtime() {
    if (( TRANSACTION_ACTIVE )); then
        log "⚠ 尚未完成，原 HEAD：$REF_BASE/head；原改动：${SNAPSHOT:-无}"
        log "⚠ 恢复说明：$SESSION/recovery.txt；请勿删除快照。"
    fi
    if (( LOCK_OWNED )); then
        /bin/rmdir "$LOCK_DIR" 2>/dev/null
    fi
}
# 命名退出陷阱保持脚本级生命周期，避免在初始化函数返回时提前释放锁。
TRAPEXIT() {
    local result=$?
    finish_runtime
    return "$result"
}
# 中断只保留现场，不自动重置可能已由外部编辑的文件。
TRAPINT() {
    log '⚠ 已中断，保留当前现场与恢复锚点。'
    exit 130
}
# 终端关闭沿用中断保护，保留可识别的退出码。
TRAPHUP() {
    exit 129
}
# 外部终止沿用脚本级退出清理。
TRAPTERM() {
    exit 143
}
# 拒绝既存事务、稀疏或特殊索引，避免脚本无法完整还原的状态。
validate_repository() {
    local marker entry folder top state_all state_without flags
    for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply sequencer BISECT_START; do
        [[ ! -e "$PULL_GIT_DIR/$marker" ]] || { log "✖ 已有 Git 操作进行中：$marker，请先完成或中止。"; exit 1; }
    done
    BRANCH="$(git -C "$REPO" symbolic-ref --quiet --short HEAD)" || { log '✖ 游离 HEAD 不拉取。'; exit 1; }
    ORIGINAL_HEAD="$(git -C "$REPO" rev-parse --verify HEAD)" || { log '✖ 当前分支尚无提交。'; exit 1; }
    ATTEMPT_HEAD="$ORIGINAL_HEAD"
    [[ "$(git -C "$REPO" config --bool core.sparseCheckout)" != true ]] || { log '✖ 稀疏检出请在 Git 客户端手动处理。'; exit 1; }
    while IFS= read -r -d '' entry; do
        flags="${entry[1]}"
        [[ "$flags" == H ]] || { log '✖ 存在 skip-worktree、assume-unchanged 或冲突索引，请先恢复普通索引。'; exit 1; }
    done < <(git -C "$REPO" ls-files -v -z)
    state_all="$(git -C "$REPO" status --porcelain=v1 --ignore-submodules=none --untracked-files=all)" || exit 1
    state_without="$(git -C "$REPO" status --porcelain=v1 --ignore-submodules=all --untracked-files=all)" || exit 1
    [[ "$state_all" == "$state_without" ]] || { log '✖ 子模块有未提交内容或检出变化，请先单独处理子模块。'; exit 1; }
    while IFS= read -r -d '' entry; do
        folder="$REPO/${entry%/}"
        [[ -d "$folder" && ! -L "$folder" ]] || continue
        top="$(git -C "$folder" rev-parse --show-toplevel 2>/dev/null)"
        [[ -z "$top" || "$top" == "$REPO" ]] || { log "✖ 未跟踪目录包含独立 Git 仓库：$entry，请先移出或忽略。"; exit 1; }
    done < <(git -C "$REPO" ls-files --others --exclude-standard --directory -z)
    REMOTE="$(git -C "$REPO" config --get "branch.$BRANCH.remote")" || { log '✖ 当前分支未配置 upstream。'; exit 1; }
    MERGE_REF="$(git -C "$REPO" config --get-all "branch.$BRANCH.merge")" || exit 1
    [[ "$REMOTE" != . && "$REMOTE" != -* && "$MERGE_REF" == refs/heads/* && "$MERGE_REF" != *$'\n'* ]] || { log '✖ 只支持一个明确的远端 upstream 分支。'; exit 1; }
    git check-ref-format "$MERGE_REF" || exit 1
    if [[ -n "$state_all" ]]; then
        log '⚠ 当前有未提交内容（含暂存、未暂存及未跟踪文件）：'
        log "$state_all"
        read_answer '直接回车确认保护这些内容后继续；任意字符取消：' || exit 0
        [[ -z "$REPLY" ]] || exit 0
    fi
    CONFIRMED_TOKEN="$(worktree_token)" || exit 1
}
# 展示实际生效来源并只获取明确的上游分支，失败时工作区尚未移动。
fetch_upstream() {
    local configured actual
    configured="$(git -C "$REPO" config --get "remote.$REMOTE.url")" || exit 1
    actual="$(git -C "$REPO" remote get-url "$REMOTE")" || exit 1
    log '━━━━━━━━━━ 来源｜Git 拉取 ━━━━━━━━━━'
    log "📦 工作树：$REPO"
    log "🌐 远端：$REMOTE ｜ 分支：$MERGE_REF"
    log "📥 配置地址：$configured"
    log "📥 拉取地址（本地规则展开）：$actual"
    log '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
    run_git fetch --no-tags --no-recurse-submodules -- "$REMOTE" "+$MERGE_REF:$REF_BASE/upstream" || { log '✖ 获取上游失败，工作区未修改。'; exit 1; }
    TARGET="$(git -C "$REPO" rev-parse "$REF_BASE/upstream^{commit}")" || exit 1
    [[ "$(git -C "$REPO" rev-parse HEAD)" == "$ORIGINAL_HEAD" ]] || { log '✖ 获取期间 HEAD 已改变，停止。'; exit 1; }
    assert_branch || exit 1
    assert_worktree_token "$CONFIRMED_TOKEN" || exit 1
}
# 防止其它 Git 客户端切换分支后，后续命令作用到错误分支。
assert_branch() {
    [[ "$(git -C "$REPO" symbolic-ref --quiet --short HEAD)" == "$BRANCH" ]] || { log '✖ 当前分支已被其它进程切换，停止并保留快照。'; return 1; }
}
# 只有成功计算且一致的状态摘要才能继续，探测失败同样停止。
assert_worktree_token() {
    local current
    current="$(worktree_token)" || { log '✖ 无法读取完整工作区状态，停止并保留现场。'; return 1; }
    [[ "$current" == "$1" ]] || { log '✖ 工作区、索引或分支已被其它进程改动，停止并保留现场。'; return 1; }
}
# 建立持久恢复锚点，将未提交内容移入本会话 stash。
snapshot_worktree() {
    local before after entry
    assert_branch || exit 1
    verify_protected_state || exit 1
    run_git update-ref "$REF_BASE/head" "$ORIGINAL_HEAD" || exit 1
    print -r -- "仓库：$REPO
原 HEAD：$REF_BASE/head
上游：$REF_BASE/upstream
本次 stash 若存在位于 $REF_BASE/snapshot（包含 index 和非忽略的 untracked）。
中断后先检查 git status。已有 merge 用 git merge --abort；再按 head 锚点恢复。
reset --hard 会丢弃中断后编辑，必须人工确认；未跟踪文件先另存，不要直接 clean。
恢复原 HEAD 且工作区干净后：git stash apply --index $REF_BASE/snapshot
快照与日志保留，不自动删除任何既存 stash。" > "$SESSION/recovery.txt"
    if [[ -n "$(git -C "$REPO" status --porcelain=v1 --untracked-files=all)" ]]; then
        before="$(git -C "$REPO" rev-parse -q --verify refs/stash 2>/dev/null)"
        TRANSACTION_ACTIVE=1
        run_git stash push --include-untracked --message "JobsGitPuller ${SESSION:t}" || { log '✖ 快照失败，保留当前状态，请按日志检查。'; exit 1; }
        after="$(git -C "$REPO" rev-parse -q --verify refs/stash)" || exit 1
        [[ "$after" != "$before" ]] || { log '✖ 未得到新的快照，停止。'; exit 1; }
        [[ "$(git -C "$REPO" rev-parse "$after^1")" == "$ORIGINAL_HEAD" && "$(git -C "$REPO" show -s --format=%s "$after")" == *"JobsGitPuller ${SESSION:t}"* ]] || { log '✖ stash 被其它进程改变，无法确认本会话快照，停止并保留现场。'; exit 1; }
        SNAPSHOT="$after"
        INITIAL_SNAPSHOT="$after"
        run_git update-ref "$REF_BASE/snapshot" "$SNAPSHOT" || exit 1
        if git -C "$REPO" rev-parse --verify "$SNAPSHOT^3" >/dev/null 2>&1; then
            while IFS= read -r -d '' entry; do
                UNTRACKED_PATHS+=("$entry")
            done < <(git -C "$REPO" ls-tree -r --name-only -z "$SNAPSHOT^3")
        fi
    fi
    [[ -z "$(git -C "$REPO" status --porcelain=v1 --ignore-submodules=all --untracked-files=all)" ]] || { log '✖ 快照后工作区仍非干净，停止并保留快照。'; exit 1; }
    TRANSACTION_ACTIVE=1
    log "ℹ 恢复锚点：$REF_BASE/head；改动快照：${SNAPSHOT:-无}"
}
# 快照前再次检查隐藏索引和子模块，防止获取远端期间的状态变化被漏掉。
verify_protected_state() {
    local entry state_all state_without marker
    for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply sequencer BISECT_START; do
        [[ ! -e "$PULL_GIT_DIR/$marker" ]] || { log "✖ 新出现的 Git 操作：$marker，停止。"; return 1; }
    done
    git -C "$REPO" ls-files -v -z > "$SESSION/index-flags" || return 1
    while IFS= read -r -d '' entry; do
        [[ "${entry[1]}" == H ]] || { log '✖ 索引出现隐藏或冲突条目，停止。'; return 1; }
    done < "$SESSION/index-flags"
    state_all="$(git -C "$REPO" status --porcelain=v1 --ignore-submodules=none --untracked-files=all)" || return 1
    state_without="$(git -C "$REPO" status --porcelain=v1 --ignore-submodules=all --untracked-files=all)" || return 1
    [[ "$state_all" == "$state_without" ]] || { log '✖ 子模块状态已变化，停止。'; return 1; }
}
# 从本次合并现场恢复指定检查点，清理仅限本会话恢复过的未跟踪路径。
restore_checkpoint() {
    local checkpoint_head="$1" checkpoint_snapshot="$2" entry
    assert_branch || return 1
    if [[ -f "$PULL_GIT_DIR/MERGE_HEAD" ]]; then
        run_git merge --abort || return 1
    fi
    run_git -c core.hooksPath=/dev/null reset --hard "$checkpoint_head" || return 1
    if (( APPLY_ATTEMPTED )); then
        for entry in "${UNTRACKED_PATHS[@]}"; do
            verify_untracked_before_cleanup "$entry" || return 1
            run_git --literal-pathspecs clean -f -- "$entry" || return 1
        done
    fi
    if [[ -n "$checkpoint_snapshot" ]]; then
        run_git stash apply --index "$checkpoint_snapshot" || { log '✖ 快照恢复失败；保留现场与快照，停止。'; return 1; }
    fi
    APPLY_ATTEMPTED=0
    return 0
}
# 只允许清理快照原样恢复的未跟踪文件，外部编辑或类型变化必须停止。
verify_untracked_before_cleanup() {
    local entry="$1" expected actual
    [[ -e "$REPO/$entry" || -L "$REPO/$entry" ]] || return 0
    git -C "$REPO" --literal-pathspecs ls-files --error-unmatch -- "$entry" >/dev/null 2>&1 && return 0
    expected="$(git -C "$REPO" rev-parse "$INITIAL_SNAPSHOT^3:$entry")" || return 1
    if [[ -L "$REPO/$entry" ]]; then
        actual="$(/usr/bin/readlink "$REPO/$entry" | /usr/bin/perl -pe 'chomp if eof' | git -C "$REPO" hash-object --stdin)" || return 1
    elif [[ -f "$REPO/$entry" ]]; then
        actual="$(git -C "$REPO" hash-object --path="$entry" -- "$REPO/$entry")" || return 1
    else
        log "✖ 快照路径类型已变化，保留并停止：$entry"
        return 1
    fi
    [[ "$actual" == "$expected" ]] || { log "✖ 未跟踪文件已被外部修改，保留并停止：$entry"; return 1; }
}
# 仅明确确认后舍弃快照内容，保留原有本地提交并重新合并上游。
discard_original() {
    local token answer read_result
    token="$(worktree_token)" || return 1
    read_answer '⚠ 将放弃拉取前全部未提交内容（不含 ignored / 子仓），输入 YES 确认：'
    read_result=$?
    answer="$REPLY"
    assert_worktree_token "$token" || return 1
    (( read_result == 0 )) && [[ "$answer" == YES ]] || return 2
    restore_checkpoint "$ATTEMPT_HEAD" "$SNAPSHOT" || return 1
    if [[ -n "$SNAPSHOT" ]]; then
        run_git stash push --include-untracked --message "JobsGitPuller discarded ${SESSION:t}" || return 1
    fi
    SNAPSHOT=''
    APPLY_ATTEMPTED=0
    return 0
}
# 提交最初的改动，空行作为合法空提交信息，保留既有本地提交。
commit_original() {
    local message token
    if [[ "$ATTEMPT_HEAD" != "$ORIGINAL_HEAD" ]]; then
        restore_checkpoint "$ATTEMPT_HEAD" '' || return 1
        log '⚠ 本轮改动已经提交；已提交历史间的冲突需要手动解决，提交已保留。'
        return 1
    fi
    restore_checkpoint "$ATTEMPT_HEAD" "$SNAPSHOT" || return 1
    if [[ -z "$(git -C "$REPO" status --porcelain=v1 --ignore-submodules=all --untracked-files=all)" ]]; then
        log '⚠ 原始状态没有可提交改动；已还原。请手动解决已提交历史间的冲突。'
        return 1
    fi
    token="$(worktree_token)" || return 1
    read_answer '输入 commit 信息（直接回车也立即提交，允许空信息）：' || return 1
    message="$REPLY"
    assert_worktree_token "$token" || return 1
    run_git add --all || return 1
    if ! run_git commit --allow-empty-message --message "$message"; then
        log '✖ 提交失败（身份、签名或 hook 等），保留原 HEAD、工作区和快照；不继续拉取。'
        return 1
    fi
    ATTEMPT_HEAD="$(git -C "$REPO" rev-parse HEAD)" || return 1
    run_git update-ref "$REF_BASE/committed" "$ATTEMPT_HEAD" || return 1
    SNAPSHOT=''
    APPLY_ATTEMPTED=0
    return 0
}
# 汇总 HEAD、分支、索引、工作区及未跟踪内容，识别等待输入期间的外部改动。
worktree_token() {
    local directory token result
    directory="$(/usr/bin/mktemp -d "$SESSION/token.XXXXXX")" || return 1
    write_worktree_token "$directory"
    result=$?
    if (( result == 0 )); then
        token="$(git -C "$REPO" hash-object --no-filters -- "$directory/input")"
        result=$?
    fi
    /bin/rm -f -- "$directory/input" "$directory/paths"
    /bin/rmdir "$directory" 2>/dev/null
    (( result == 0 )) || return 1
    print -r -- "$token"
}
# 逐项读取状态并检查退出码，不能把失败的 Git 探测当作空工作区。
write_worktree_token() {
    local directory="$1" entry
    git -C "$REPO" rev-parse HEAD > "$directory/input" || return 1
    git -C "$REPO" symbolic-ref --quiet HEAD >> "$directory/input" || return 1
    git -C "$REPO" status --porcelain=v1 -z --untracked-files=all >> "$directory/input" || return 1
    git -C "$REPO" ls-files -v -z >> "$directory/input" || return 1
    git -C "$REPO" diff --binary --no-ext-diff >> "$directory/input" || return 1
    git -C "$REPO" diff --cached --binary --no-ext-diff >> "$directory/input" || return 1
    git -C "$REPO" ls-files --others --exclude-standard -z > "$directory/paths" || return 1
    while IFS= read -r -d '' entry; do
        print -rn -- "$entry"$'\0' >> "$directory/input" || return 1
        if [[ -L "$REPO/$entry" ]]; then
            /usr/bin/readlink "$REPO/$entry" >> "$directory/input" || return 1
        elif [[ -f "$REPO/$entry" ]]; then
            /bin/cat -- "$REPO/$entry" >> "$directory/input" || return 1
        else
            return 1
        fi
    done < "$directory/paths"
}
# 冲突菜单只接受三个明确选项，EOF 按还原处理。
resolve_conflict() {
    local token choice_result
    log '⚠ 合并或恢复本地改动发生冲突：'
    log '1、回滚到当前这轮拉取之前（HEAD、暂存区和工作区；已确认的新提交保留）。'
    log '2、放弃拉取前未提交内容，再拉取最新（保留本地已提交历史）。'
    log '3、先恢复并提交拉取前的改动，再拉取最新。'
    while true; do
        token="$(worktree_token)" || return 1
        if ! read_answer '输入 1 / 2 / 3（回车默认 1）：'; then
            REPLY=1
        fi
        assert_worktree_token "$token" || return 1
        case "$REPLY" in
            ''|1)
                restore_checkpoint "$ATTEMPT_HEAD" "$SNAPSHOT" || exit 1
                TRANSACTION_ACTIVE=0
                log '✔ 已回滚到拉取前状态，恢复快照保留。'
                return 2
                ;;
            2)
                discard_original
                choice_result=$?
                if (( choice_result == 2 )); then
                    restore_checkpoint "$ATTEMPT_HEAD" "$SNAPSHOT" || return 1
                    TRANSACTION_ACTIVE=0
                    return 1
                fi
                (( choice_result == 0 )) || return 1
                return 0
                ;;
            3)
                commit_original || return 1
                return 0
                ;;
            *) log '⚠ 只支持 1 / 2 / 3。' ;;
        esac
    done
}
# 合并固定的本次远端提交，再还原本地改动；失败时严格区分冲突和其它错误。
merge_and_restore() {
    local merge_result conflict_result apply_output
    while true; do
        assert_branch || return 1
        run_git -c rerere.enabled=false merge --commit --no-squash --no-edit --no-autostash --no-overwrite-ignore "$TARGET"
        merge_result=$?
        if (( merge_result == 0 )); then
            if [[ -f "$PULL_GIT_DIR/MERGE_HEAD" ]] || ! git -C "$REPO" merge-base --is-ancestor "$TARGET" HEAD; then
                log '✖ 合并命令结束但远端历史尚未整合，保留现场与快照。'
                return 1
            fi
            if [[ -n "$SNAPSHOT" ]]; then
                APPLY_ATTEMPTED=1
                if ! run_git stash apply --index "$SNAPSHOT"; then
                    apply_output="$(/bin/cat "$SESSION/last-git-output")"
                    if [[ -z "$(git -C "$REPO" ls-files --unmerged)" && "$apply_output" != *'patch failed'* && "$apply_output" != *'already exists'* && "$apply_output" != *'CONFLICT'* && "$apply_output" != *'conflicts in index'* ]]; then
                        log '✖ 恢复快照失败但未确认文件冲突，保留现场和快照，请人工检查。'
                        return 1
                    fi
                    resolve_conflict
                    conflict_result=$?
                    (( conflict_result == 2 )) && return 0
                    (( conflict_result == 0 )) || return 1
                    refresh_upstream_for_retry || return 1
                    continue
                fi
            fi
            TRANSACTION_ACTIVE=0
            log "✔ 已整合上游 $REMOTE/$MERGE_REF（$TARGET），未提交内容已保留。"
            log "ℹ 当前 HEAD：$(git -C "$REPO" rev-parse HEAD)；来源：$(git -C "$REPO" remote get-url "$REMOTE")"
            return 0
        fi
        if [[ -n "$(git -C "$REPO" ls-files --unmerged)" ]]; then
            resolve_conflict
            conflict_result=$?
            (( conflict_result == 2 )) && return 0
            (( conflict_result == 0 )) || return 1
            refresh_upstream_for_retry || return 1
            continue
        fi
        log '✖ 合并失败但没有文件冲突；正在还原，不进入冲突选项。'
        restore_checkpoint "$ATTEMPT_HEAD" "$SNAPSHOT" || exit 1
        TRANSACTION_ACTIVE=0
        return 1
    done
}
# 提交或放弃后重新获取最新上游，避免用户输入期间远端推进导致使用旧目标。
refresh_upstream_for_retry() {
    local token
    assert_branch || return 1
    [[ "$(git -C "$REPO" config --get "branch.$BRANCH.remote")" == "$REMOTE" && "$(git -C "$REPO" config --get-all "branch.$BRANCH.merge")" == "$MERGE_REF" ]] || { log '✖ upstream 配置已变化，保留当前基线并停止。'; return 1; }
    token="$(worktree_token)" || return 1
    log "ℹ 已确认的新基线：$ATTEMPT_HEAD；重新获取 $REMOTE/$MERGE_REF。"
    log "📥 拉取地址：$(git -C "$REPO" remote get-url "$REMOTE")"
    if ! run_git fetch --no-tags --no-recurse-submodules -- "$REMOTE" "+$MERGE_REF:$REF_BASE/upstream"; then
        TRANSACTION_ACTIVE=0
        log '✖ 再次获取失败，已确认的提交或放弃结果保留；未开始新一轮合并。'
        return 1
    fi
    assert_worktree_token "$token" || return 1
    TARGET="$(git -C "$REPO" rev-parse "$REF_BASE/upstream^{commit}")" || return 1
}
# 编排只读门禁、确认、远端获取、快照与合并。
main() {
    show_script_intro_and_wait "$@" # 非 Git 静默退出，展示影响范围并等待确认。
    initialize_runtime # 为本工作树建立独立锁、日志和退出清理。
    validate_repository # 检查上游和仓库状态，未提交内容再次确认。
    fetch_upstream # 工作区未移动前先获取准确上游提交。
    snapshot_worktree # 为 HEAD、暂存区与工作区建立可恢复锚点。
    merge_and_restore # 合并上游并处理冲突三选项。
}

main "$@"
