#!/bin/zsh
# 脚本自述：
# - 脚本名称：Android 模拟器启动与新建工具。
# - 核心用途：启动已有 AVD，或按本机架构选择设备和系统映像后新建、启动 AVD。
# - 影响范围：首屏回车授权本次自动补齐必要工具链与选中映像，新增 AVD；不删除、覆盖现有设备，不修改 Shell / 系统代理。
# - 运行提示：--create 直接新建；--prepare 仅补齐工具链；--check / --help 只读；SDK 许可证仍由本人选择。
# shell: zsh

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

# >>> Jobs Android simulator core >>>
# JOBS_SDK_RETRY_BEGIN
# 只处理本轮子树，避免超时或取消后残留下载进程占用 SDK 锁。
# 仅格式化展示中的URL；地址原文和已有正文样式保持不变。
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
# 样式只送往当前交互输出；日志和重定向输出始终为纯文本。
jobs_url_stream() {
  local url_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then url_color=1; fi
  jobs_url_format "$url_color" "${1:-1}"
}

# JOBS_INPUT_CHOICE_STYLE_BEGIN
# 只展示提示选项；不读取答案、不改变默认值、返回码或业务环境。
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

jobs_sdk_stop_tree() {
    local root="$1" child=""
    for child in $(/usr/bin/pgrep -P "$root" 2>/dev/null); do
        jobs_sdk_stop_tree "$child"
    done
    /bin/kill -TERM "$root" 2>/dev/null || true
    /bin/kill -KILL "$root" 2>/dev/null || true
}
# 状态写标准错误，机器可读的标准输出不混入重试提示。
jobs_sdk_retry_note() {
    print -r -- "$2" | jobs_url_stream >&2
    [[ -z "$1" ]] || print -r -- "$2" >> "$1"
}
# 本地确定错误应明确失败；下载超时、断流和未知获取失败则继续，无次数/总时长上限。
jobs_sdk_retry() {
    setopt LOCAL_OPTIONS LOCAL_TRAPS
    local title="$1" acquisition_log="$2" attempt=1 result=0 delay="${JOBS_SDK_RETRY_DELAY:-2}" maximum="${JOBS_SDK_RETRY_MAX_DELAY:-30}"
    local task_pid="" offset=0 failure="" interrupted=0 history="${2}.attempts.log"
    shift 2
    [[ "$delay" == <-> && "$maximum" == <-> && "$maximum" -gt 0 && "$delay" -le "$maximum" ]] || return 2
    trap 'interrupted=130; [[ -z "$task_pid" ]] || jobs_sdk_stop_tree "$task_pid"' INT
    trap 'interrupted=143; [[ -z "$task_pid" ]] || jobs_sdk_stop_tree "$task_pid"' TERM
    trap 'interrupted=129; [[ -z "$task_pid" ]] || jobs_sdk_stop_tree "$task_pid"' HUP
    while true; do
        jobs_sdk_retry_note "$acquisition_log" "▶ SDK 获取：$title；第 $attempt 次（失败自动重试，Ctrl+C 结束）"
        offset=0
        [[ ! -f "$acquisition_log" ]] || offset="$(/usr/bin/wc -c < "$acquisition_log")"
        [[ "${JOBS_SDK_LOG_REPLACED:-0}" != 1 ]] || offset=0
        # 显式继承 stdin；后台调用仍能进行工具自身的许可/认证交互。
        "$@" <&0 &
        task_pid=$!
        result=0
        wait "$task_pid" || result=$?
        task_pid=""
        (( interrupted == 0 )) || return "$interrupted"
        if [[ -f "$acquisition_log" ]]; then
            (( $(/usr/bin/wc -c < "$acquisition_log") >= offset )) || offset=0
            print -r -- "━━ $title：第 $attempt 次，退出码 $result ━━" >> "$history"
            /usr/bin/tail -c +$((offset + 1)) "$acquisition_log" >> "$history"
        fi
        failure=""
        if [[ -f "$acquisition_log" ]]; then
            failure="$(/usr/bin/tail -c +$((offset + 1)) "$acquisition_log" | /usr/bin/tail -c 65536)"
        fi
        # 部分获取器下载失败仍返回0，明确失败详情不能冒充SDK就绪。
        if (( result == 0 )) && print -r -- "$failure" | /usr/bin/grep -Eqi 'Failed to download|Error downloading|Unable to download|Could not download|Download failed'; then
            result=1
        fi
        (( result != 0 )) || return 0
        # 超时的调用方应返回124；外部中断状态不能被重试循环吞掉。
        case "$result" in 129|130|131|137|143) return "$result" ;; 126|127) return "$result" ;; esac
        failure=""
        if [[ -f "$acquisition_log" ]]; then
            # 兼容调用方每次重建机器输出文件：缩短后从文件开头读取。
            (( $(/usr/bin/wc -c < "$acquisition_log") >= offset )) || offset=0
            failure="$(/usr/bin/tail -c +$((offset + 1)) "$acquisition_log" | /usr/bin/tail -c 65536)"
        fi
        if print -r -- "$failure" | /usr/bin/grep -Eqi 'File exists|Permission denied|Operation not permitted|No space left on device|Read-only file system|Bad CPU type|Exec format error|unknown option|unrecognized option|invalid argument|version .* (does not exist|not found)|license[^[:cntrl:]]*(not accepted|rejected)|licenses?[^[:cntrl:]]*not accepted|HTTP[^[:cntrl:]]*(401|403|404)|returned error: (401|403|404)|Authentication failed|could not read Username'; then
            jobs_sdk_retry_note "$acquisition_log" "✖ $title 遇到权限、许可、版本或本地环境错误（$result），已停止；请按原始日志处理。"
            return "$result"
        fi
        jobs_sdk_retry_note "$acquisition_log" "⚠ $title 获取未完成（退出码 $result）；${delay} 秒后自动重试，保留已有缓存。"
        /bin/sleep "$delay" &
        task_pid=$!
        wait "$task_pid" || { (( interrupted == 0 )) || return "$interrupted"; return 130; }
        task_pid=""
        (( interrupted == 0 )) || return "$interrupted"
        (( attempt++ ))
        (( delay < maximum )) && delay=$(( delay * 2 ))
        (( delay <= maximum )) || delay="$maximum"
    done
}
# JOBS_SDK_RETRY_END

# 准备展示所需路径；在确认前只计算变量，不创建文件。
android_prepare_context() {
    local source_path="${(%):-%x}"
    SCRIPT_PATH="${source_path:A}"
    SCRIPT_DIR="${SCRIPT_PATH:h}"
    SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
    local temporary_root="${TMPDIR:-/tmp}"
    LOG_FILE="${temporary_root%/}/${SCRIPT_BASENAME}.$$.log"
    ANDROID_SIM_MODE=menu
    ANDROID_SIM_LOG_READY=0
    ANDROID_SIM_FZF=""
    ANDROID_SIM_SELECTED=""
    ANDROID_SIM_SDK=""
    ANDROID_SIM_EMULATOR=""
    ANDROID_SIM_SDKMANAGER=""
    ANDROID_SIM_AVDMANAGER=""
    ANDROID_SIM_JAVA=""
    ANDROID_SIM_DEVICES=""
    ANDROID_SIM_AVDS=""
    ANDROID_SIM_IMAGES=""
    ANDROID_SIM_NEW_AVD=""
    ANDROID_SIM_BOOTSTRAP_STAGE=""
    ANDROID_SIM_JAVA_INCOMPATIBLE=0
    typeset -ga ANDROID_SIM_CURL_PROXY=() ANDROID_SIM_SDK_PROXY=()
    ANDROID_SIM_STAGE='初始化'
    ANDROID_SIM_COLOR=0
    if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" && "${PLAIN_OUTPUT:-0}" != 1 ]]; then
        ANDROID_SIM_COLOR=1
    fi
}
# 输出纯文本日志；交互终端按级别着色，文件始终不含 ANSI。
android_log() {
    local message="$1" color="${2:-0;34}"
    [[ "$message" != (━━|✖|❌)* ]] || color='1;31'
    if (( ANDROID_SIM_COLOR )); then
        print -r -- $'\e['"${color}m${message}"$'\e[0m' | jobs_url_stream
    else
        print -r -- "$message" | jobs_url_stream
    fi
    if (( ANDROID_SIM_LOG_READY )); then
        print -r -- "$message" | jobs_url_format 0 >> "$LOG_FILE"
    fi
}
# 输出简明帮助，参数只选择入口模式，不接受无确认的安装或覆盖。
android_help() {
    android_log '用法：/bin/zsh 当前脚本 [--create | --prepare | --check | --help]'
    android_log '无参数：已有模拟器可启动或新建；没有已有设备时进入新建。'
    android_log '--create：仅进入新建流程，仍逐步选择并最终确认。'
    jobs_prompt_output android_log '--prepare：首屏回车后自动补齐、复检必要工具链，完成即退出；不查询系统映像、不创建设备。'
    android_log '--check：只读检查 SDK / Java / 工具 / 已装映像和已有 AVD；不联网、不安装、不新建设备、不写脚本日志。'
    android_log '网络：优先使用 ANDROID_SIM_PROXY 或 HTTPS_PROXY / ALL_PROXY，其次读取 macOS 静态代理；仅影响本次下载。'
    android_log '示例：ANDROID_SIM_PROXY=http://127.0.0.1:7890；也支持 socks5://主机:端口，direct 表示本次直连。PAC / 认证代理请使用已配置网络的 Android Studio SDK Manager。'
}
# 首屏写死用途、影响和取消方法，再按入口区分只读请求与交互确认。
show_script_intro_and_wait() {
    android_prepare_context
    android_log '━━━━━━━━━━ Android 模拟器：新建 / 启动 ━━━━━━━━━━' '1;31'
    android_log "当前脚本：${SCRIPT_PATH}"
    android_log '1、双击可启动已有 AVD，也可新建；桌面右键使用 --create 直接新建。'
    android_log '2、新建时先选完整设备清单，再选匹配 Apple Silicon / Intel 的手机或平板系统映像。'
    jobs_prompt_output android_log '3、首屏回车即授权本次自动体检、补齐或修复必要 SDK / Java / 命令行工具 / emulator；健康组件不升级。工具下载约数百 MB，选中映像可能数 GB，不再逐层询问安装。'
    android_log '4、不覆盖或清理任何现有 AVD，不安装 Homebrew，不改 Shell 配置或系统代理。'
    android_log '➤ SDK / Java 下载、清单和组件获取失败自动持续重试，无次数或总时长上限；Ctrl+C 主动结束。'
    jobs_prompt_output android_log '5、无映像时自动读取官方清单，选中后直接安装；SDK 许可证仍须本人阅读接受。列表回车选首项，q / Esc / Ctrl+C 取消；最后回车才创建。'
    android_log "日志位置：${LOG_FILE}（确认后创建；--check / --help 不写日志）"
    if (( $# > 1 )); then
        android_log '✖ 参数过多。' '1;31'
        exit 2
    fi
    case "${1:-}" in
        '') ANDROID_SIM_MODE=menu ;;
        --create) ANDROID_SIM_MODE=create ;;
        --prepare) ANDROID_SIM_MODE=prepare ;;
        --check) ANDROID_SIM_MODE=check; return 0 ;;
        --help|-h) android_help; exit 0 ;;
        *) android_log "✖ 不支持的参数：$1" '1;31'; android_help; exit 2 ;;
    esac
    if [[ ! -t 0 ]]; then
        android_log '✖ 请在可交互终端或双击 .command 执行；无交互检查请用 --check。' '1;31'
        exit 1
    fi
    local answer=""
    if ! IFS= read -r "?$(jobs_prompt_render "已了解用途，按回车继续，非空输入取消：")" answer || [[ -n "$answer" ]]; then
        android_log '➤ 已取消，未执行后续操作。'
        exit 0
    fi
}
# 确认后初始化选项与独立日志；只读入口没有文件写入。
android_initialize_runtime() {
    setopt NO_NOMATCH
    if [[ "$ANDROID_SIM_MODE" != check ]]; then
        if ! (umask 077; setopt NO_CLOBBER; : > "$LOG_FILE") 2>/dev/null; then
            android_log "✖ 无法安全创建日志：${LOG_FILE}" '1;31'
            return 1
        fi
        ANDROID_SIM_LOG_READY=1
        trap 'android_handle_interrupt' INT TERM HUP
    fi
}
# 为只读探测设置有限等待，只终止本函数启动的进程。
android_timed() {
    local limit="$1" child_pid watchdog_pid result=0 started=$SECONDS
    shift
    "$@" &
    child_pid=$!
    (
        /bin/sleep "$limit"
        kill -TERM "$child_pid" 2>/dev/null
        /bin/sleep 1
        kill -KILL "$child_pid" 2>/dev/null
    ) >/dev/null 2>&1 &
    watchdog_pid=$!
    wait "$child_pid" 2>/dev/null || result=$?
    kill -TERM "$watchdog_pid" 2>/dev/null
    wait "$watchdog_pid" 2>/dev/null
    if (( result >= 128 )); then
        print -u2 -r -- "命令超时或被终止（${limit} 秒）：${1:t}"
        (( result == 130 || SECONDS - started < limit )) || result=124
    fi
    return "$result"
}
# 解析宿主真实硬件架构，兼容 Apple Silicon 的 Rosetta 终端。
android_detect_architecture() {
    local machine="$(/usr/bin/uname -m)" arm_hardware=""
    arm_hardware="$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null)"
    if [[ "$machine" == arm64 || "$arm_hardware" == 1 ]]; then
        ANDROID_SIM_ABI=arm64-v8a
    elif [[ "$machine" == x86_64 ]]; then
        ANDROID_SIM_ABI=x86_64
    else
        android_log "✖ 不支持的 Mac 架构：${machine}" '1;31'
        return 1
    fi
    android_log "➤ 系统映像架构：${ANDROID_SIM_ABI}"
}
# SDK 显式环境优先；只读入口报告缺失，授权流程自动建立不存在的目录。
android_find_sdk() {
    ANDROID_SIM_SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
    if [[ "$ANDROID_SIM_SDK" != /* || ! -d "$ANDROID_SIM_SDK" ]]; then
        android_log "⚠ SDK 根目录未就绪：${ANDROID_SIM_SDK}" '1;33'
        return 1
    fi
    ANDROID_SIM_SDK="${ANDROID_SIM_SDK:A}"
    if [[ -n "${ANDROID_HOME:-}" && -n "${ANDROID_SDK_ROOT:-}" && "${ANDROID_HOME:A}" != "${ANDROID_SDK_ROOT:A}" ]]; then
        android_log '⚠ ANDROID_HOME 与 ANDROID_SDK_ROOT 不一致，本次进程统一使用 ANDROID_HOME。' '1;33'
    fi
    export ANDROID_HOME="$ANDROID_SIM_SDK" ANDROID_SDK_ROOT="$ANDROID_SIM_SDK"
    android_log "✔ SDK：${ANDROID_SIM_SDK}" '1;32'
}
# 首屏授权后自动补充 SDK 根目录，已有内容与显式路径保留。
android_ensure_sdk() {
    android_find_sdk && return 0
    [[ "$ANDROID_SIM_MODE" != check ]] || return 1
    if [[ "$ANDROID_SIM_SDK" != /* || -L "$ANDROID_SIM_SDK" || ( -e "$ANDROID_SIM_SDK" && ! -d "$ANDROID_SIM_SDK" ) ]]; then
        android_log "✖ SDK 路径不是可补齐的普通绝对目录，未覆盖现有内容：${ANDROID_SIM_SDK}" '1;31'
        return 1
    fi
    android_log "➤ 自动补齐 SDK 根目录：${ANDROID_SIM_SDK}"
    /bin/mkdir -p "$ANDROID_SIM_SDK" || return 1
    android_find_sdk
}
# 依次验证已配置 Java、Android Studio 内置 JBR、用户安装与系统 Java，不修改持久配置。
android_find_java() {
    local candidate version="" resolved="" major="" minimum="${1:-17}"
    local -a candidates
    resolved="$(/usr/libexec/java_home 2>/dev/null)"
    candidates=("${JAVA_HOME:-}/bin/java" '/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java' "$HOME/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java" "${resolved}/bin/java" "$(command -v java 2>/dev/null)")
    candidates+=("$HOME/Library/Java/JavaVirtualMachines"/*/Contents/Home/bin/java(N))
    for candidate in "${candidates[@]}"; do
        [[ -n "$candidate" && -x "$candidate" ]] || continue
        if version="$(android_timed 12 "$candidate" -version 2>&1)"; then
            major="$(print -r -- "$version" | /usr/bin/awk '/version/ { for(i=1;i<NF;i++) if($i == "version") { value=$(i+1); gsub(/"/, "", value); split(value,p,"."); print (p[1] == 1 ? p[2] : p[1]); exit } }')"
            [[ "$major" == <-> && "$major" -ge "$minimum" ]] || continue
            ANDROID_SIM_JAVA="$candidate"
            export JAVA_HOME="${candidate:A:h:h}"
            android_log "✔ Java：${candidate}；${version%%$'\n'*}" '1;32'
            return 0
        fi
    done
    android_log "⚠ 未找到健康的 Java ${minimum}+。" '1;33'
    return 1
}
# 仅允许 Adoptium 官方 API、Temurin 官方发布仓及 GitHub 官方资产主机。
android_temurin_url_allowed() {
    [[ "$1" != *[[:space:]]* && "$1" != *'#'* ]] || return 1
    case "$1" in
        https://api.adoptium.net/v3/assets/latest/21/hotspot\?*) return 0 ;;
        https://github.com/adoptium/temurin21-binaries/releases/download/*) return 0 ;;
        https://release-assets.githubusercontent.com/*|https://objects.githubusercontent.com/*) return 0 ;;
    esac
    return 1
}
# 逐跳核对官方 HTTPS 下载主机，不加载 curlrc，也不把签名查询串写入日志。
android_download_temurin_once() {
    local url="$1" target="$2" limit="$3" curl_bin="$(command -v curl 2>/dev/null)" http_code="" next_url="" hop=0 request_target=""
    local -a resume=()
    while (( hop < 5 )); do
        request_target="$target"
        resume=()
        if [[ "$target" == *.tar.gz ]]; then
            if [[ "$url" == https://github.com/* ]]; then
                request_target="${target}.redirect"
            else
                resume=(--continue-at -)
            fi
        fi
        android_temurin_url_allowed "$url" || { android_log '✖ invalid argument：Java 下载跳转到未授权来源，停止。' '1;31'; return 1; }
        if ! http_code="$("$curl_bin" --disable "${ANDROID_SIM_CURL_PROXY[@]}" "${resume[@]}" --fail --show-error --progress-bar --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time "$limit" --max-redirs 0 --dump-header "${target}.headers" --output "$request_target" --write-out '%{http_code}' "$url" 2> >(/usr/bin/tee -a "$LOG_FILE" >&2))"; then
            if [[ "$http_code" == 416 && "$target" == *.tar.gz && -f "$target" ]]; then
                return 0
            fi
            android_log "✖ Temurin 官方下载失败（HTTP ${http_code:-未知}），未发布 Java。" '1;31'
            return 1
        fi
        if [[ "$http_code" == 200 || "$http_code" == 206 || "$http_code" == 416 ]]; then
            [[ "$request_target" == "$target" ]] || /bin/mv -f -- "$request_target" "$target" || return 1
            android_log "➤ Java 下载来源主机：${${url#https://}%%/*}"
            return 0
        fi
        case "$http_code" in
            301|302|303|307|308)
                next_url="$(/usr/bin/awk 'tolower($0) ~ /^location:/ { sub(/^[^:]*:[[:space:]]*/, ""); sub(/\r$/, ""); value=$0 } END { print value }' "${target}.headers")"
                [[ -n "$next_url" ]] || return 1
                url="$next_url"
                ;;
            *) android_log "✖ Temurin 官方下载返回 HTTP ${http_code}，停止。" '1;31'; return 1 ;;
        esac
        (( hop += 1 ))
    done
    android_log '✖ invalid argument：Java 下载跳转次数超限，停止。' '1;31'
    return 1
}
# SDK 获取重试只包围传输，不重放解压、发布或项目操作。
android_download_temurin() {
    jobs_sdk_retry 'Temurin 官方 SDK 下载' "$LOG_FILE" android_download_temurin_once "$@"
}
# 使用系统 JSON 解析器核对 Temurin 21、宿主架构、官方归档 URL 与 SHA256。
android_read_java_asset() {
    /usr/bin/osascript -l JavaScript - "$1" "$2" <<'JXA'
ObjC.import('Foundation');
function run(args) {
    var data = $.NSString.stringWithContentsOfFileEncodingError(args[0], $.NSUTF8StringEncoding, null);
    if (!data) throw Error('无法读取 Temurin 官方元数据');
    var entries = JSON.parse(ObjC.unwrap(data));
    if (!Array.isArray(entries)) throw Error('Temurin 元数据必须为数组');
    for (var i=0; i<entries.length; i++) {
        var item=entries[i], binary=item.binary || {}, pkg=binary.package || {}, version=item.version || {};
        if (item.vendor !== 'eclipse' || version.major !== 21 || binary.os !== 'mac' || binary.architecture !== args[1] || binary.image_type !== 'jdk' || binary.jvm_impl !== 'hotspot') continue;
        if (!/^https:\/\/github\.com\/adoptium\/temurin21-binaries\/releases\/download\/[A-Za-z0-9_%+.-]+\/OpenJDK21U-jdk_[A-Za-z0-9_.-]+\.tar\.gz$/.test(pkg.link || '') || !/^[a-fA-F0-9]{64}$/.test(pkg.checksum || '') || !Number.isSafeInteger(pkg.size) || pkg.size < 1 || pkg.size > 2147483648 || !/^jdk-21(?:\.[0-9]+)*\+[0-9]+$/.test(item.release_name || '')) throw Error('Temurin 官方包字段不符合安全约束');
        return [pkg.link, pkg.checksum, String(pkg.size), item.release_name].join('\n');
    }
    throw Error('官方元数据没有匹配的 Temurin 21 macOS JDK');
}
JXA
}
# 下载校验后在用户目录同卷展开 JDK，检查路径及链接边界，再排他发布。
android_perform_java_bootstrap() {
    local stage="$ANDROID_SIM_BOOTSTRAP_STAGE" arch=x64 api="" metadata="" digest="" size="" listing="" root_name="" root="" link="" resolved="" destination=""
    local -a fields
    [[ "$ANDROID_SIM_ABI" != arm64-v8a ]] || arch=aarch64
    api="https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=${arch}&image_type=jdk&os=mac&vendor=eclipse"
    android_log "📥 官方 Java 元数据：${api}"
    android_download_temurin "$api" "$stage/assets.json" 60 || return 1
    metadata="$(android_read_java_asset "$stage/assets.json" "$arch")" || return 1
    fields=("${(@f)metadata}")
    (( ${#fields} == 4 )) || return 1
    android_log "📦 对象：Eclipse Temurin 21 ${fields[4]}；${arch}；${fields[3]} 字节。"
    android_log "📥 官方归档：${fields[1]}"
    android_log "📂 目标：${HOME}/Library/Java/JavaVirtualMachines/（仅当前用户，不改 Shell 配置）"
    android_download_temurin "${fields[1]}" "$stage/java.tar.gz" 600 || return 1
    size="$(/usr/bin/stat -f %z "$stage/java.tar.gz")" || return 1
    digest="$(/usr/bin/shasum -a 256 "$stage/java.tar.gz" | /usr/bin/awk '{print $1}')" || return 1
    if [[ "$size" != "${fields[3]}" || "${digest:l}" != "${fields[2]:l}" ]]; then
        android_log '✖ Java 归档长度或 SHA256 与官方元数据不符，停止解压。' '1;31'
        return 1
    fi
    listing="$(/usr/bin/tar -tzf "$stage/java.tar.gz")" || return 1
    if ! print -r -- "$listing" | /usr/bin/awk '!/^jdk-21[0-9.+-]*(\.jdk)?\// || /(^|\/)\.\.?(\/|$)/ || /\\/ || /\/\// || /[^A-Za-z0-9_.\/+@-]/ { bad=1 } END { exit bad }'; then
        android_log '✖ Java 归档含非预期路径，停止解压。' '1;31'
        return 1
    fi
    root_name="$(print -r -- "$listing" | /usr/bin/cut -d / -f1 | /usr/bin/sort -u)"
    [[ "$root_name" =~ '^jdk-21([.][0-9]+)*[+][0-9]+([.]jdk)?$' ]] || return 1
    /bin/mkdir "$stage/extract" || return 1
    /usr/bin/tar --no-same-owner --no-same-permissions -xzf "$stage/java.tar.gz" -C "$stage/extract" || return 1
    root="$stage/extract/$root_name"
    [[ ! -L "$root" && -x "$root/Contents/Home/bin/java" ]] || return 1
    root="${root:A}"
    while IFS= read -r -d '' link; do
        if [[ ! -e "$link" || "$(/usr/bin/readlink "$link")" == /* ]]; then
            android_log '✖ Java 归档包含悬空或绝对符号链接，未发布安装。' '1;31'
            return 1
        fi
        resolved="${link:A}"
        if [[ "$resolved" != "$root" && "$resolved" != "$root"/* ]]; then
            android_log '✖ Java 归档符号链接越过本次 JDK 根目录，未发布安装。' '1;31'
            return 1
        fi
    done < <(/usr/bin/find "$root" -type l -print0)
    destination="${stage:h}/temurin-21-${${stage:t}#.jobs-staging.}.jdk"
    android_publish_tools_directory "$root" "$destination" || return 1
    export JAVA_HOME="$destination/Contents/Home"
    android_log "✔ 已补齐官方 Temurin 21：${JAVA_HOME}；来源：${fields[1]}" '1;32'
}
# Java 沿健康候选复用，全部不可用才自动补装官方校验的用户级 Temurin 21 一次。
android_ensure_java() {
    local minimum="${1:-17}" result=0 directory="$HOME/Library/Java/JavaVirtualMachines" tool=""
    android_find_java "$minimum" && return 0
    [[ "$ANDROID_SIM_MODE" != check ]] || return 1
    android_log '➤ 自动补齐官方 Eclipse Temurin 21，下载约 200 MB；仅安装到当前用户目录。'
    for tool in /usr/bin/osascript /usr/bin/tar /usr/bin/shasum; do
        [[ -x "$tool" ]] || { android_log "✖ 缺少系统工具：${tool}" '1;31'; return 1; }
    done
    command -v curl >/dev/null 2>&1 || return 1
    if [[ -L "$directory" || ( -e "$directory" && ! -d "$directory" ) ]]; then
        android_log "✖ Java 用户目录不是普通目录，未覆盖：${directory}" '1;31'
        return 1
    fi
    /bin/mkdir -p "$directory" || return 1
    ANDROID_SIM_BOOTSTRAP_STAGE="$(umask 077; /usr/bin/mktemp -d "$directory/.jobs-staging.XXXXXX")" || return 1
    android_perform_java_bootstrap || result=$?
    android_cleanup_bootstrap
    (( result == 0 )) || return "$result"
    if ! android_find_java "$minimum"; then
        android_log '✖ 官方 Java 安装后复检仍失败，停止下游；保留新增版本供人工排查。' '1;31'
        return 1
    fi
}
# 新 sdkmanager 是 Android CLI 下载启动器，连 --version 都可能下载另一份程序。
# 本流程依赖传统包 ID / 清单 / 许可交互契约；只读探测绝不运行该启动器。
android_is_cli_launcher() {
    /usr/bin/grep -Eq 'ANDROID_CLI_BIN|run_android_cli' "$1"
}
# 只从选定 SDK 中发现成对的 sdkmanager / avdmanager，并实际验证二者可运行。
android_find_command_tools() {
    local bin_dir output="" last_error="" candidate
    local -a bins
    bins=("$ANDROID_SIM_SDK/cmdline-tools/latest/bin")
    ANDROID_SIM_JAVA_INCOMPATIBLE=0
    while IFS= read -r -d '' candidate; do
        bins+=("${candidate:h}")
    done < <(/usr/bin/find "$ANDROID_SIM_SDK/cmdline-tools" -type f -name sdkmanager -print0 2>/dev/null)
    bins+=("$ANDROID_SIM_SDK/tools/bin")
    bins=("${(@u)bins}")
    for bin_dir in "${bins[@]}"; do
        [[ -x "$bin_dir/sdkmanager" && -x "$bin_dir/avdmanager" ]] || continue
        if android_is_cli_launcher "$bin_dir/sdkmanager"; then
            android_log "➤ 跳过 Android CLI 下载启动器：${bin_dir}；保留已安装版本，使用可离线自检的兼容工具。"
            continue
        fi
        if ! output="$(android_timed 20 "$bin_dir/sdkmanager" --sdk_root="$ANDROID_SIM_SDK" --version 2>&1)"; then
            last_error="${bin_dir}/sdkmanager --version：${output}"
            [[ "$output" != *UnsupportedClassVersionError* && "$output" != *'class file version'* ]] || ANDROID_SIM_JAVA_INCOMPATIBLE=1
            continue
        fi
        if ! output="$(android_timed 20 "$bin_dir/avdmanager" list device 2>&1)"; then
            last_error="${bin_dir}/avdmanager list device：${output}"
            [[ "$output" != *UnsupportedClassVersionError* && "$output" != *'class file version'* ]] || ANDROID_SIM_JAVA_INCOMPATIBLE=1
            continue
        fi
        ANDROID_SIM_SDKMANAGER="$bin_dir/sdkmanager"
        ANDROID_SIM_AVDMANAGER="$bin_dir/avdmanager"
        ANDROID_SIM_DEVICES="$output"
        android_log "✔ SDK 命令行工具：${bin_dir}" '1;32'
        return 0
    done
    android_log '⚠ SDK Command-line Tools 缺失或无法运行。' '1;33'
    [[ -z "$last_error" ]] || android_log "➤ 失败命令：${last_error}"
    return 1
}
# curl 与 Java SDK Manager 使用相同的本次代理，不写系统设置或 Shell 配置。
android_configure_network() {
    local proxy="${ANDROID_SIM_PROXY:-${https_proxy:-${HTTPS_PROXY:-${all_proxy:-${ALL_PROXY:-}}}}}" settings="" host="" port="" scheme="" key="" excluded="" exclusions="${no_proxy:-${NO_PROXY:-}}"
    ANDROID_SIM_CURL_PROXY=()
    ANDROID_SIM_SDK_PROXY=()
    if [[ -z "$proxy" ]]; then
        settings="$(/usr/sbin/scutil --proxy 2>/dev/null)"
        for key in HTTPS HTTP SOCKS; do
            [[ "$(print -r -- "$settings" | /usr/bin/awk -v k="${key}Enable" '$1 == k {print $3; exit}')" == 1 ]] || continue
            host="$(print -r -- "$settings" | /usr/bin/awk -v k="${key}Proxy" '$1 == k {print $3; exit}')"
            port="$(print -r -- "$settings" | /usr/bin/awk -v k="${key}Port" '$1 == k {print $3; exit}')"
            scheme=http
            [[ "$key" != SOCKS ]] || scheme=socks5
            proxy="${scheme}://${host}:${port}"
            break
        done
        if [[ -z "$proxy" && "$(print -r -- "$settings" | /usr/bin/awk '$1 == "ProxyAutoConfigEnable" {print $3; exit}')" == 1 ]]; then
            android_log '⚠ 检测到 PAC 自动代理；命令行不解析 PAC，请通过 ANDROID_SIM_PROXY 指定本次代理，或在 Android Studio SDK Manager 准备依赖。' '1;33'
        fi
    fi
    if [[ -z "$proxy" ]]; then
        android_log '➤ 未发现可复用的静态代理；按当前网络访问 Google 官方源。'
        return 0
    fi
    if [[ "$proxy" == direct ]]; then
        ANDROID_SIM_CURL_PROXY=(--proxy '' --noproxy '*')
        android_log '➤ 本次下载使用直连。'
        return 0
    fi
    if [[ ! "$proxy" =~ '^(http|socks5|socks5h)://([A-Za-z0-9._-]+|\[[0-9A-Fa-f:]+\]):([0-9]{1,5})/?$' ]]; then
        android_log '✖ 本次代理格式不受支持：请指定不含账号密码的 http://主机:端口 或 socks5://主机:端口；未输出代理原文。' '1;31'
        return 1
    fi
    scheme="$match[1]" host="$match[2]" port="$match[3]"
    (( 10#$port >= 1 && 10#$port <= 65535 )) || { android_log '✖ 代理端口须为 1–65535。' '1;31'; return 1; }
    ANDROID_SIM_CURL_PROXY=(--proxy "$proxy")
    [[ "$scheme" == http ]] || scheme=socks
    ANDROID_SIM_SDK_PROXY=(--proxy="$scheme" --proxy_host="${${host#\[}%\]}" --proxy_port="$port")
    # Google SDK 仓库走 dl.google.com；保留已有 NO_PROXY 对此主机的直连约定。
    for excluded in "${(@s:,:)exclusions}"; do
        excluded="${${excluded//[[:space:]]/}:l}"
        excluded="${excluded%.}"
        excluded="${excluded#\*.}"
        excluded="${excluded#.}"
        if [[ "$excluded" == '*' || "$excluded" == dl.google.com || "$excluded" == google.com || "$excluded" == com ]]; then
            ANDROID_SIM_SDK_PROXY=()
            android_log '➤ NO_PROXY 将 dl.google.com 排除在代理之外，SDK Manager 对该仓库使用直连。'
            break
        fi
    done
    android_log "➤ 本次官方下载复用代理：${host}:${port}（${scheme}）；系统配置保持不变。"
}
android_network_failure_hint() {
    android_log '➤ 请检查本次代理能否访问 dl.google.com/android/repository/；浏览器能下载不代表 Java SDK Manager 使用了相同代理。'
    android_log '➤ 可用 ANDROID_SIM_PROXY=http://主机:端口 指定本次代理；或在 Android Studio SDK Manager 安装 Command-line Tools 21.0、Android Emulator 和所需映像后重试。'
}
# 下载固定官方 HTTPS 地址，不跟随重定向，失败时保留明确诊断。
android_download_official_once() {
    local url="$1" target="$2" limit="$3" http_code="" curl_bin="$(command -v curl 2>/dev/null)"
    [[ "$url" == https://dl.google.com/android/repository/* && -n "$curl_bin" ]] || return 1
    local -a resume=()
    [[ "$target" != *.zip ]] || resume=(--continue-at -)
    if ! http_code="$("$curl_bin" --disable "${ANDROID_SIM_CURL_PROXY[@]}" "${resume[@]}" --fail --show-error --progress-bar --proto '=https' --connect-timeout 10 --max-time "$limit" --max-redirs 0 --output "$target" --write-out '%{http_code}' "$url" 2> >(/usr/bin/tee -a "$LOG_FILE" >&2))" || [[ "$http_code" != 200 && "$http_code" != 206 && "$http_code" != 416 ]]; then
        if [[ "$http_code" == 416 && "$target" == *.zip && -f "$target" ]]; then
            return 0
        fi
        android_log "✖ Google 官方下载失败：${url}；HTTP ${http_code}" '1;31'
        android_network_failure_hint
        return 1
    fi
}
android_download_official() {
    [[ "$1" == https://dl.google.com/android/repository/* ]] || return 2
    command -v curl >/dev/null 2>&1 || return 127
    jobs_sdk_retry 'Google Android SDK 下载' "$LOG_FILE" android_download_official_once "$@"
}
# 固定已验证的传统 CLI 21.0 契约；从官方元数据取得归档与摘要，不追随 CLI 启动器版 latest。
android_read_tools_archive() {
    local xml="$1" package_path="" archive_path="" host_arch=x64 field=""
    [[ "$ANDROID_SIM_ABI" != arm64-v8a ]] || host_arch=aarch64
    package_path="(//*[local-name()='remotePackage' and @path='cmdline-tools;21.0'][*[local-name()='channelRef' and @ref='channel-0']][not(*[local-name()='revision']/*[local-name()='preview'])])[1]"
    archive_path="(${package_path}/*[local-name()='archives']/*[local-name()='archive'][*[local-name()='host-os' and .='macosx']][*[local-name()='host-arch' and .='${host_arch}'] or not(*[local-name()='host-arch'])]/*[local-name()='complete'])[1]"
    ANDROID_SIM_TOOLS_ARCHIVE="$(/usr/bin/xmllint --nonet --xpath "string(${archive_path}/*[local-name()='url'])" "$xml" 2>/dev/null)" || return 1
    ANDROID_SIM_TOOLS_SIZE="$(/usr/bin/xmllint --nonet --xpath "string(${archive_path}/*[local-name()='size'])" "$xml" 2>/dev/null)" || return 1
    ANDROID_SIM_TOOLS_CHECKSUM="$(/usr/bin/xmllint --nonet --xpath "string(${archive_path}/*[local-name()='checksum'])" "$xml" 2>/dev/null)" || return 1
    ANDROID_SIM_TOOLS_HASH_TYPE="$(/usr/bin/xmllint --nonet --xpath "string(${archive_path}/*[local-name()='checksum']/@type)" "$xml" 2>/dev/null)" || return 1
    ANDROID_SIM_TOOLS_VERSION="$(/usr/bin/xmllint --nonet --xpath "string(${package_path}/*[local-name()='revision']/*[local-name()='major'])" "$xml" 2>/dev/null)"
    field="$(/usr/bin/xmllint --nonet --xpath "string(${package_path}/*[local-name()='revision']/*[local-name()='minor'])" "$xml" 2>/dev/null)"
    [[ -z "$field" ]] || ANDROID_SIM_TOOLS_VERSION+=".${field}"
    [[ "$ANDROID_SIM_TOOLS_VERSION" == 21.0 ]] || { android_log '✖ 官方清单缺少兼容版 Command-line Tools 21.0；停止，不自动改用 Android CLI 下载启动器。' '1;31'; return 1; }
    if [[ ! "$ANDROID_SIM_TOOLS_ARCHIVE" =~ '^commandlinetools-mac(_arm64|_x86_64)?-[0-9]+_latest\.zip$' || ! "$ANDROID_SIM_TOOLS_SIZE" == <-> || ${#ANDROID_SIM_TOOLS_SIZE} -gt 10 || "$ANDROID_SIM_TOOLS_SIZE" -le 0 || "$ANDROID_SIM_TOOLS_SIZE" -gt 1073741824 || ! "$ANDROID_SIM_TOOLS_VERSION" =~ '^[0-9]+(\.[0-9]+)?$' ]]; then
        android_log '✖ 官方工具元数据格式或归档地址不符合预期，未下载工具归档。' '1;31'
        return 1
    fi
    case "$ANDROID_SIM_TOOLS_HASH_TYPE" in
        sha1) [[ "$ANDROID_SIM_TOOLS_CHECKSUM" =~ '^[0-9a-fA-F]{40}$' ]] || return 1 ;;
        sha256) [[ "$ANDROID_SIM_TOOLS_CHECKSUM" =~ '^[0-9a-fA-F]{64}$' ]] || return 1 ;;
        *) android_log '✖ 官方归档使用未知校验算法，已停止。' '1;31'; return 1 ;;
    esac
}
# 解压前校验长度、官方摘要与路径；禁止归档符号链接和目录穿越。
android_validate_tools_zip() {
    local zip="$1" size="" digest="" algorithm=1 listing=""
    size="$(/usr/bin/stat -f %z "$zip" 2>/dev/null)" || return 1
    [[ "$size" == "$ANDROID_SIM_TOOLS_SIZE" ]] || { android_log '✖ 工具归档长度与官方元数据不符。' '1;31'; return 1; }
    [[ "$ANDROID_SIM_TOOLS_HASH_TYPE" != sha256 ]] || algorithm=256
    digest="$(/usr/bin/shasum -a "$algorithm" "$zip" | /usr/bin/awk '{print $1}')" || return 1
    [[ "${digest:l}" == "${ANDROID_SIM_TOOLS_CHECKSUM:l}" ]] || { android_log '✖ 工具归档校验失败，未解压或写入 SDK。' '1;31'; return 1; }
    listing="$(/usr/bin/unzip -Z1 "$zip" 2>/dev/null)" || return 1
    if ! print -r -- "$listing" | /usr/bin/awk '
        !/^cmdline-tools\// || /(^|\/)\.\.?(\/|$)/ || /\\/ || /\/\// || /[^A-Za-z0-9_.\/+@ -]/ { bad=1 }
        END { exit bad }
    '; then
        android_log '✖ 工具归档包含不安全的路径，已停止解压。' '1;31'
        return 1
    fi
    if /usr/bin/unzip -Z -l "$zip" 2>/dev/null | /usr/bin/awk '$1 ~ /^l/ { found=1 } END { exit !found }'; then
        android_log '✖ 工具归档含符号链接，已停止解压。' '1;31'
        return 1
    fi
}
# 使用系统排他移动 API 发布目录；目标即使在预检后出现也不会嵌套或覆盖。
android_publish_tools_directory() {
    /usr/bin/osascript -l JavaScript - "$1" "$2" <<'JXA'
ObjC.import('Foundation');
function run(args) {
    var error = Ref();
    if (!$.NSFileManager.defaultManager.moveItemAtPathToPathError(args[0], args[1], error)) {
        throw Error('工具目录发布失败，目标已存在或文件系统返回错误；未覆盖目标。');
    }
}
JXA
}
# 临时下载与校验完成后只新增独立版本目录，不移动或覆盖任何现有工具版本。
android_perform_tools_bootstrap() {
    local stage="$ANDROID_SIM_BOOTSTRAP_STAGE" destination="" url=""
    android_download_official 'https://dl.google.com/android/repository/repository2-3.xml' "$stage/repository.xml" 60 || return 1
    android_read_tools_archive "$stage/repository.xml" || return 1
    url="https://dl.google.com/android/repository/${ANDROID_SIM_TOOLS_ARCHIVE}"
    destination="$ANDROID_SIM_SDK/cmdline-tools/jobs-${ANDROID_SIM_TOOLS_VERSION}-${${stage:t}#.jobs-staging.}"
    android_log "📦 对象：Android SDK Command-line Tools ${ANDROID_SIM_TOOLS_VERSION}（stable）"
    android_log "📥 官方归档：${url}"
    android_log "📂 新增目录：${destination}"
    android_log "➤ 官方校验：${ANDROID_SIM_TOOLS_HASH_TYPE} ${ANDROID_SIM_TOOLS_CHECKSUM}；${ANDROID_SIM_TOOLS_SIZE} 字节。"
    android_download_official "$url" "$stage/tools.zip" 600 || return 1
    android_validate_tools_zip "$stage/tools.zip" || return 1
    /bin/mkdir "$stage/extract" || return 1
    /usr/bin/unzip -q "$stage/tools.zip" -d "$stage/extract" || return 1
    if [[ ! -x "$stage/extract/cmdline-tools/bin/sdkmanager" || ! -x "$stage/extract/cmdline-tools/bin/avdmanager" || ! -d "$stage/extract/cmdline-tools/lib" || ! -f "$stage/extract/cmdline-tools/source.properties" ]]; then
        android_log '✖ 官方工具归档内容不完整，未写入 SDK。' '1;31'
        return 1
    fi
    if android_is_cli_launcher "$stage/extract/cmdline-tools/bin/sdkmanager"; then
        android_log '✖ 兼容归档意外包含 Android CLI 下载启动器，停止发布；请检查官方工具版本。' '1;31'
        return 1
    fi
    if [[ -L "$ANDROID_SIM_SDK/cmdline-tools" ]]; then
        android_log '✖ cmdline-tools 是符号链接，请在 SDK Manager 人工处理，未写入该路径。' '1;31'
        return 1
    fi
    /bin/mkdir -p "$ANDROID_SIM_SDK/cmdline-tools" || return 1
    [[ ! -e "$destination" && ! -L "$destination" ]] || return 1
    if ! android_publish_tools_directory "$stage/extract/cmdline-tools" "$destination"; then
        android_log '✖ 工具目录发布失败，未覆盖或嵌入既有目标目录。' '1;31'
        return 1
    fi
    if [[ -e "$stage/extract/cmdline-tools" || ! -x "$destination/bin/sdkmanager" || ! -x "$destination/bin/avdmanager" || ! -d "$destination/lib" || ! -f "$destination/source.properties" ]]; then
        android_log '✖ 工具目标目录发生冲突，未覆盖现有内容。' '1;31'
        return 1
    fi
    android_log "✔ 已新增官方命令行工具：${destination}；来源：${url}" '1;32'
}
# 仅移除本次创建的私有临时下载目录，永不清理 SDK 或 AVD。
android_cleanup_bootstrap() {
    if [[ -n "$ANDROID_SIM_BOOTSTRAP_STAGE" && -d "$ANDROID_SIM_BOOTSTRAP_STAGE" ]]; then
        /bin/rm -r -- "$ANDROID_SIM_BOOTSTRAP_STAGE"
        ANDROID_SIM_BOOTSTRAP_STAGE=""
    fi
}
# 中断时清理本次下载，保留所有已安装组件与已有 / 新增设备。
android_handle_interrupt() {
    android_cleanup_bootstrap
    android_log '➤ 操作已中断，SDK 与 AVD 保持现有内容。'
    exit 130
}
# 缺失工具自动补齐一次；Java 兼容错误先切换合适运行时，健康安装不联网或升级。
android_ensure_command_tools() {
    local result=0 tool="" java_retried=0
    android_find_command_tools && return 0
    [[ "$ANDROID_SIM_MODE" != check ]] || return 1
    if (( ANDROID_SIM_JAVA_INCOMPATIBLE )); then
        android_log '➤ 当前 SDK 与 Java 版本不兼容，自动选择或补齐 Java 21 后复检一次。'
        android_ensure_java 21 || return 1
        java_retried=1
        android_find_command_tools && return 0
        if (( ANDROID_SIM_JAVA_INCOMPATIBLE )); then
            android_log '✖ Java 运行时复检后仍不兼容，停止；请检查官方 SDK / JDK 版本要求：https://developer.android.com/build/jdks' '1;31'
            return 1
        fi
    fi
    android_log '━━━━━━━━━━ 来源｜补充 SDK Command-line Tools ━━━━━━━━━━' '1;36'
    android_log '📥 官方元数据：https://dl.google.com/android/repository/repository2-3.xml'
    android_log "📂 目标：${ANDROID_SIM_SDK}/cmdline-tools/ 下新建独立版本目录；不会覆盖 latest 或既有版本。"
    android_log '➤ 自动补齐官方稳定兼容版 Command-line Tools 21.0，下载约 150 MB；避免 Android CLI 首次联网下载，保留所有既有版本。SDK 许可证仍须本人接受。'
    for tool in curl; do
        command -v "$tool" >/dev/null 2>&1 || { android_log "✖ 缺少 ${tool}，请使用 Android Studio 的 SDK Manager。" '1;31'; return 1; }
    done
    for tool in /usr/bin/xmllint /usr/bin/unzip /usr/bin/shasum /usr/bin/osascript; do
        [[ -x "$tool" ]] || { android_log "✖ 缺少系统校验工具 ${tool}。" '1;31'; return 1; }
    done
    if [[ -L "$ANDROID_SIM_SDK/cmdline-tools" || ( -e "$ANDROID_SIM_SDK/cmdline-tools" && ! -d "$ANDROID_SIM_SDK/cmdline-tools" ) ]]; then
        android_log '✖ cmdline-tools 不是普通目录，请在 SDK Manager 人工处理，未写入该路径。' '1;31'
        return 1
    fi
    /bin/mkdir -p "$ANDROID_SIM_SDK/cmdline-tools" || return 1
    ANDROID_SIM_BOOTSTRAP_STAGE="$(umask 077; /usr/bin/mktemp -d "$ANDROID_SIM_SDK/cmdline-tools/.jobs-staging.XXXXXX")" || return 1
    android_perform_tools_bootstrap || result=$?
    android_cleanup_bootstrap
    (( result == 0 )) || return "$result"
    if ! android_find_command_tools; then
        if (( ANDROID_SIM_JAVA_INCOMPATIBLE && !java_retried )); then
            android_log '➤ 新命令行工具需要更高 Java，自动选择或补齐 Java 21 后复检一次。'
            android_ensure_java 21 || return 1
            android_find_command_tools && return 0
        fi
        android_log '✖ 命令行工具安装后复检失败，已停止；新增版本保留供 SDK Manager 人工排查。' '1;31'
        return 1
    fi
}
# 检查本 SDK 的 emulator 本体与 AVD 清单，存在文件不代表安装健康。
android_probe_emulator() {
    local output=""
    ANDROID_SIM_EMULATOR="$ANDROID_SIM_SDK/emulator/emulator"
    [[ -x "$ANDROID_SIM_EMULATOR" ]] || return 1
    if ! output="$(android_timed 15 "$ANDROID_SIM_EMULATOR" -version 2>&1)"; then
        android_log "⚠ emulator 版本体检失败：${ANDROID_SIM_EMULATOR}；${output}" '1;33'
        return 1
    fi
    if ! ANDROID_SIM_AVDS="$(android_timed 15 "$ANDROID_SIM_EMULATOR" -list-avds 2>&1)"; then
        android_log "⚠ emulator AVD 清单体检失败：${ANDROID_SIM_AVDS}" '1;33'
        return 1
    fi
    android_log "✔ emulator：${ANDROID_SIM_EMULATOR}；${output%%$'\n'*}" '1;32'
}
# 在每次真实安装前显示可追溯的软件源与目标，地址尚由工具解析时如实说明。
android_show_install_source() {
    android_log '━━━━━━━━━━ 来源｜SDK 组件安装 ━━━━━━━━━━' '1;36'
    android_log "📦 对象：$1（stable channel 0）"
    android_log '🌐 平台 / 软件源：Google 官方 Android SDK Repository'
    android_log '📥 来源地址：https://dl.google.com/android/repository/（具体归档地址由 sdkmanager 解析，尚未核实）'
    android_log "📂 目标位置：${ANDROID_SIM_SDK}"
    android_log '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' '1;36'
}
# 清除外部命令展示中的 ANSI，使终端和落盘日志保留可搜索的文本。
android_strip_ansi() {
    /usr/bin/awk 'BEGIN { esc=sprintf("%c",27) } { gsub(esc "\\[[0-9;?]*[ -/]*[@-~]", ""); print }'
}
# 安装精确组件并保留 SDK 官方许可证交互，不执行 yes 管道或全量更新。
android_install_package() {
    local package="$1" result=0
    android_show_install_source "$package"
    android_log "➤ 自动安装本次必要组件：${package}；SDK 许可证由你阅读并选择。"
    jobs_sdk_retry "Android SDK 组件 ${package}" "$LOG_FILE" android_install_package_once "$package" || result=$?
    if (( result != 0 )); then
        android_log "✖ 组件安装失败（退出码 ${result}）：${package}；来源：Google 官方 Android SDK Repository。" '1;31'
        android_network_failure_hint
        return "$result"
    fi
}
# 单次只安装选定组件；保留原生许可输入与实时输出。
android_install_package_once() {
    local result=0 directory="$ANDROID_SIM_SDK/${(j:/:)${(s:;:)1}}" offset=0 output=""
    [[ ! -f "$LOG_FILE" ]] || offset="$(/usr/bin/wc -c < "$LOG_FILE")"
    NO_COLOR=1 FORCE_COLOR=0 TERM=dumb "$ANDROID_SIM_SDKMANAGER" --sdk_root="$ANDROID_SIM_SDK" --install "$1" --channel=0 "${ANDROID_SIM_SDK_PROXY[@]}" 2>&1 | /usr/bin/tee -a "$LOG_FILE"
    result=${pipestatus[1]}
    output="$(/usr/bin/tail -c +$((offset + 1)) "$LOG_FILE")"
    if print -r -- "$output" | /usr/bin/grep -Eqi 'Failed to find package|Unknown package|Package .* not found'; then
        android_log '✖ invalid argument：选定 SDK 包或版本不存在，停止下游。' '1;31'
        return 2
    fi
    (( result == 0 )) || return "$result"
    case "$1" in
        emulator) [[ -x "$directory/emulator" ]] && return 0 ;;
        system-images\;*) [[ -f "$directory/system.img" && -f "$directory/source.properties" ]] && return 0 ;;
        platform-tools) [[ -x "$directory/adb" ]] && return 0 ;;
        platforms\;*) [[ -f "$directory/android.jar" ]] && return 0 ;;
        build-tools\;*) [[ -x "$directory/aapt2" ]] && return 0 ;;
        ndk\;*) [[ -x "$directory/ndk-build" ]] && return 0 ;;
        cmake\;*) [[ -x "$directory/bin/cmake" ]] && return 0 ;;
        *) [[ -f "$directory/source.properties" || -f "$directory/package.xml" ]] && return 0 ;;
    esac
    android_log "⚠ SDK 获取未就绪：${1}；安装器返回成功但所需文件缺失，将继续获取。" '1;33'
    return 1
}
# 缺失 emulator 自动补齐；损坏登记包仅重装 emulator 工具包，始终保留 AVD。
android_ensure_emulator() {
    android_probe_emulator && return 0
    android_log "⚠ emulator 缺失或健康检查失败：${ANDROID_SIM_SDK}/emulator/emulator" '1;33'
    [[ "$ANDROID_SIM_MODE" != check ]] || return 1
    if [[ -z "$ANDROID_SIM_SDKMANAGER" ]]; then
        android_ensure_java && android_ensure_command_tools || return 1
    fi
    if [[ -e "$ANDROID_SIM_SDK/emulator/emulator" || -e "$ANDROID_SIM_SDK/emulator/source.properties" || -e "$ANDROID_SIM_SDK/emulator/package.xml" ]]; then
        android_log '➤ emulator 已登记但损坏，自动通过官方 sdkmanager 卸载、重装一次，仅处理 emulator 工具包；保留已有 AVD 和系统映像。'
        NO_COLOR=1 FORCE_COLOR=0 TERM=dumb "$ANDROID_SIM_SDKMANAGER" --sdk_root="$ANDROID_SIM_SDK" --uninstall emulator "${ANDROID_SIM_SDK_PROXY[@]}" 2>&1 | /usr/bin/tee -a "$LOG_FILE"
        (( pipestatus[1] == 0 )) || { android_log '✖ 损坏 emulator 官方卸载失败，停止下游操作。' '1;31'; return 1; }
    fi
    android_install_package emulator || return 1
    if ! android_probe_emulator; then
        android_log '✖ emulator 安装后复检仍失败，已停止；请在 SDK Manager 修复 Android Emulator。' '1;31'
        return 1
    fi
}
# 只读模式仅验证；已确认交互流程按需补齐并复检 fzf。
# JOBS_FZF_REQUIRED_BEGIN
# Homebrew 条件准备，来源为本轮现行 Jobs 自维护实现。
jobs_brew_note() {
  jobs_prompt_output print -u2 -r -- "ℹ $*"
  if [[ "${_JOBS_ENV_LOG_READY:-0}" == 1 && -n "${LOG_FILE:-}" ]]; then
    print -r -- "ℹ $*" >> "$LOG_FILE"
  fi
  return 0
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
  print -u2 -n -r -- "$(jobs_prompt_render "➤ 安装路径选择：")"
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
# 持续获取临时网络失败；只尝试已声明官方地址，确定错误和取消立即停止。
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
# 校验官方安装脚本后仅执行一次，下载失败与安装失败分别报告。
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
# 只终止本次获取或等待创建的子进程树，不碰其它 SDK 写者。
jobs_brew_stop_acquisition_tree() {
  local root="$1" child=""
  for child in $(/usr/bin/pgrep -P "$root" 2>/dev/null); do
    jobs_brew_stop_acquisition_tree "$child"
  done
  /bin/kill -TERM "$root" 2>/dev/null || true
  /bin/kill -KILL "$root" 2>/dev/null || true
}
# 在本轮私有暂存目录持续获取固定官方 tag，复用已收对象；不重放安装。
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

# 获取固定官方稳定版本到用户目录；不覆盖非空目录，不调用 sudo。
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
  local git_health=1 locate_result=0 git_candidate="" selected_developer="" clt_result=0 clt_diagnostic=""
  git_bin="$(command -v git 2>/dev/null)"
  # /usr/bin/git 可能只是CLT占位器；先查询真实工具，避免健康检查自行弹出安装窗口。
  if [[ "$git_bin" == /usr/bin/git || -z "$git_bin" ]]; then
    git_bin="$(/usr/bin/xcrun --find git 2>/dev/null)" || locate_result=$?
    case "$locate_result" in 129|130|131|137|143) return "$locate_result" ;; esac
  fi
  if [[ -n "$git_bin" && -x "$git_bin" ]]; then
    git_health=0;"$git_bin" --version >/dev/null 2>&1 || git_health=$?
    case "$git_health" in 129|130|131|137|143) return "$git_health" ;; esac
  fi
  if (( git_health != 0 )); then
    [[ -z "${DEVELOPER_DIR:-}" ]] || { jobs_brew_note '显式DEVELOPER_DIR没有健康Git，保留用户开发目录，未自动改全局选择。'; return 1; }
    locate_result=0
    selected_developer="$(/usr/bin/xcode-select -p 2>/dev/null)" || locate_result=$?
    case "$locate_result" in 129|130|131|137|143) return "$locate_result" ;; esac
    if [[ -n "$selected_developer" && -d "$selected_developer" ]]; then
      jobs_brew_note "既有开发目录未提供健康Git：$selected_developer；可能是许可、版本或本地文件阻塞，未反复安装或改全局xcode-select。"
      return 1
    fi
    if [[ "${DRY_RUN:-0}" == 1 || "${CHECK_ONLY:-0}" == 1 || ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]] ||
       env | LC_ALL=C /usr/bin/grep -qiE '^(SOURCETREE|SOURCE_TREE)'; then
      jobs_brew_note '用户目录Homebrew需要健康Git；当前为只读或非交互入口，未打开CLT安装窗口或写安装目标。'
      return 1
    fi
    jobs_brew_note '当前已选用户目录Homebrew安装需要Apple Command Line Tools的Git；只打开一次原生安装窗口，许可由本人处理，当前流程持续复检，Ctrl+C停止。' || return $?
    clt_diagnostic="$(/usr/bin/xcode-select --install 2>&1)" || clt_result=$?
    jobs_brew_note "$clt_diagnostic" || return $?
    if (( clt_result != 0 )) && [[ "$clt_diagnostic" != *'already being installed'* && "$clt_diagnostic" != *'正在安装'* ]]; then return "$clt_result"; fi
    while true; do
      locate_result=0
      git_candidate="$(/usr/bin/xcrun --find git 2>/dev/null)" || locate_result=$?
      case "$locate_result" in 129|130|131|137|143) return "$locate_result" ;; esac
      if [[ -n "$git_candidate" && -x "$git_candidate" ]]; then
        git_health=0;"$git_candidate" --version >/dev/null 2>&1 || git_health=$?
        case "$git_health" in 129|130|131|137|143) return "$git_health" ;; esac
        if (( git_health == 0 )); then git_bin="$git_candidate";break;fi
      fi
      jobs_brew_note '等待Apple CLT提供健康Git；不会重复打开窗口，Ctrl+C停止。' || return $?
      /bin/sleep 3 || return $?
    done
  fi
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
    # 只刷新本次进程，不向用户 Shell 启动文件写入持久配置。
    :
  fi
}
# 用户取消保持信号退出码，其它安装失败沿用原入口失败状态。
jobs_brew_stop_failed_install() {
  case "$1" in
    129|130|143) exit "$1" ;;
    *) exit 1 ;;
  esac
}

# 编排既有健康复用和已选安装路径，失败保留原生取消状态。
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

# 将依赖诊断写到人类展示流，避免混入选择结果。
jobs_fzf_note() {
  if (( ${+functions[jobs_prompt_output]} )); then
    jobs_prompt_output print -u2 -r -- "$*"
  else
    print -u2 -r -- "$*"
  fi
  if [[ -n "${LOG_FILE:-}" ]]; then print -r -- "$*" >> "$LOG_FILE"; fi
}
# 只给健康探针设置单次上限；下载获取仍由持续重试流程负责。
jobs_fzf_bounded_probe() {
  local child=0 watchdog=0 result=0
  "$@" <&0 &
  child=$!
  ( /bin/sleep 10; jobs_brew_stop_acquisition_tree "$child" ) >/dev/null 2>&1 &
  watchdog=$!
  wait "$child" || result=$?
  jobs_brew_stop_acquisition_tree "$watchdog"
  wait "$watchdog" 2>/dev/null || :
  return "$result"
}
# 验证可执行路径、版本和本轮菜单实际使用的选项；不打开选择面板。
jobs_fzf_probe() {
  local candidate="$1" probe='__JOBS_FZF_HEALTH__' output="" result=0
  [[ -n "$candidate" && -x "$candidate" && ! -d "$candidate" ]] || return 1
  jobs_fzf_bounded_probe /usr/bin/env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_OPTS_FILE -u FZF_DEFAULT_COMMAND "$candidate" --version >/dev/null 2>&1 || return 1
  output="$(print -r -- "P"$'\t'"$probe" | jobs_fzf_bounded_probe /usr/bin/env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_OPTS_FILE -u FZF_DEFAULT_COMMAND \
    "$candidate" --filter="$probe" --delimiter=$'\t' --with-nth=2.. --no-multi --sync --print-query --layout=reverse --height=60% --border \
      --bind='up:up,down:down,tab:down,shift-tab:up' --expect=left --header='↑/↓ 选择；回车确认；← 返回上一层；Esc / Ctrl+C 取消')" || result=$?
  (( result == 0 )) && [[ "${output##*$'\n'}" == P$'\t'"$probe" ]]
}
# 从当前进程和常见安装位置复用真正健康的 fzf，不重复安装。
jobs_fzf_find() {
  local candidate=""
  local -a candidates=("${JOBS_FZF_BIN:-}" "${commands[fzf]:-}" /opt/homebrew/bin/fzf /usr/local/bin/fzf "$HOME/.local/bin/fzf")
  for candidate in "${candidates[@]}"; do
    if jobs_fzf_probe "$candidate"; then JOBS_FZF_BIN="${candidate:A}"; return 0; fi
  done
  return 1
}
# 只读检查不修复；已确认业务仅在缺失或损坏时补齐选择器并刷新当前进程。
jobs_fzf_ensure() {
  local mode="${1:-required}" brew="" action=install result=0 attempt=0 delay=1 output_log="" prefix="" offset=0 log_result=0
  local -a command_status
  if [[ "$mode" != check ]] && { [[ ! -t 0 || ! -t 2 ]] || [[ "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]]; }; then
    print -u2 -r -- '✖ 选择器需要可交互终端；未安装依赖或执行后续业务。'
    return 1
  fi
  if jobs_fzf_find; then
    if [[ "$mode" != check ]]; then export PATH="${JOBS_FZF_BIN:h}:$PATH"; rehash; fi
    return 0
  fi
  [[ "$mode" != check ]] || { print -u2 -r -- '✖ fzf 路径、版本或菜单选项检查失败；只读模式未安装或修复。'; return 1; }
  jobs_fzf_note '➤ 本次键盘选择需要健康 fzf；仅在缺失或损坏时通过 Homebrew 准备，Ctrl+C 可取消。' || return $?
  jobs_brew_install_or_exit >&2 || return $?
  brew="${JOBS_HOMEBREW_BIN:-}"
  [[ -n "$brew" ]] || { jobs_fzf_note '✖ Homebrew 准备未返回可执行路径。'; return 1; }
  prefix="$("$brew" --prefix)" || return $?
  export PATH="$prefix/bin:$prefix/sbin:$PATH"
  rehash
  output_log="${LOG_FILE:-${TMPDIR:-/tmp}/JobsFzf.$$.log}"
  HOMEBREW_NO_AUTO_UPDATE=1 "$brew" list --versions fzf >/dev/null 2>&1 && action=reinstall
  while true; do
    (( attempt += 1 ))
    jobs_fzf_note "➤ 必需依赖 fzf｜来源：https://formulae.brew.sh/formula/fzf｜目标：$prefix｜$action，第 $attempt 次；网络失败持续重试，Ctrl+C 结束。" || return $?
    offset=0
    [[ ! -f "$output_log" ]] || offset="$(/usr/bin/wc -c < "$output_log")"
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 "$brew" "$action" fzf 2>&1 | jobs_prompt_tee "$output_log" >&2
    command_status=("${pipestatus[@]}")
    result=${command_status[1]}
    log_result=${command_status[2]}
    if (( log_result != 0 )); then print -u2 -r -- "✖ fzf 输出记录失败，退出码 $log_result；未继续重试或报告就绪。"; return "$log_result"; fi
    if (( result == 0 )); then
      rehash
      if jobs_fzf_find; then jobs_fzf_note "✔ fzf 已通过版本与菜单选项复检：$JOBS_FZF_BIN"; return 0; fi
      jobs_fzf_note '✖ 安装器返回成功，但 fzf 仍未通过实际选项复检；保留日志并停止，未进入业务。'
      return 1
    fi
    case "$result" in 129|130|137|143) return "$result" ;; esac
    if /usr/bin/tail -c +$((offset + 1)) "$output_log" | /usr/bin/tail -c 65536 | /usr/bin/grep -Eqi 'Permission denied|Operation not permitted|No space left|No available formula|No formulae found|File exists|unsupported|not supported|license.*(not accepted|rejected)|authentication failed|certificate.*(invalid|verify failed)'; then
      jobs_fzf_note "✖ 必需依赖遇到确定的本地、版本、认证或许可阻塞，退出码 $result；日志：$output_log"
      return "$result"
    fi
    jobs_fzf_note "⚠ fzf 获取失败，退出码 $result；${delay} 秒后继续同一流程。日志：$output_log" || return $?
    /bin/sleep "$delay" || return $?
    (( delay < 30 )) && delay=$(( delay * 2 > 30 ? 30 : delay * 2 ))
  done
}
# 单选默认取消，操作行与业务数据分开；返回、取消和失败分别传播。
jobs_fzf_pick() {
  local title="$1" level="${2:-root}" selected="" result=0 record="" key="" choice="" index=0 header=""
  shift 2
  local -a choices=("$@") menu=($'C\t× 取消本轮')
  JOBS_FZF_SELECTED=""
  JOBS_FZF_QUERY="${JOBS_FZF_INITIAL_QUERY:-}"
  (( ${#choices[@]} )) || return 1
  for choice in "${choices[@]}"; do
    [[ "$choice" != *$'\n'* && "$choice" != *$'\r'* ]] || { jobs_fzf_note '✖ 候选包含换行，停止以避免错误映射。'; return 1; }
  done
  local force=0
  if [[ "$level" == confirm-* ]]; then force=1; level="${level#confirm-}"; JOBS_FZF_QUERY=""; fi
  if [[ "$level" == force-* ]]; then force=1; level="${level#force-}"; fi
  if (( ${#choices[@]} == 1 && ! force )); then JOBS_FZF_SELECTED="${choices[1]}"; return 0; fi
  jobs_fzf_ensure >&2 || return $?
  if [[ "$level" == root ]]; then
    header='↑/↓ 或 Tab 选择；回车确认；← / Esc / Ctrl+C 取消'
  else
    menu+=($'B\t← 返回上一层')
    header='↑/↓ 或 Tab 选择；回车确认；← 返回上一层；Esc / Ctrl+C 取消'
  fi
  for choice in "${choices[@]}"; do
    [[ "$choice" != *$'\n'* && "$choice" != *$'\r'* ]] || { jobs_fzf_note '✖ 候选包含换行，停止以避免错误映射。'; return 1; }
    (( index += 1 ))
    menu+=("D${index}"$'\t'"$choice")
  done
  selected="$(print -rl -- "${menu[@]}" | /usr/bin/env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_OPTS_FILE -u FZF_DEFAULT_COMMAND \
    "$JOBS_FZF_BIN" --no-multi --sync --print-query --query="$JOBS_FZF_QUERY" --layout=reverse --height=60% --border --delimiter=$'\t' --with-nth=2.. --prompt="$title > " \
      --bind='up:up,down:down,tab:down,shift-tab:up' --expect=left --header="$header")" || result=$?
  if [[ "$selected" == *$'\n'* ]]; then
    JOBS_FZF_QUERY="${selected%%$'\n'*}"
    selected="${selected#*$'\n'}"
    key="${selected%%$'\n'*}"
    record="${selected#*$'\n'}"
  fi
  if [[ "$key" == left ]]; then
    [[ "$level" == root ]] && return 130 || return 20
  fi
  (( result == 0 )) || { (( result == 1 || result == 130 )) && return 130; return "$result"; }
  key="${record%%$'\t'*}"
  [[ -n "$record" && "$key" != C ]] || return 130
  [[ "$key" != B ]] || return 20
  [[ "$key" == D<-> ]] || { jobs_fzf_note '✖ 选择器返回无效操作标记。'; return 1; }
  index="${key#D}"
  (( index >= 1 && index <= ${#choices[@]} )) && [[ "$record" == "D${index}"$'\t'"${choices[index]}" ]] || {
    jobs_fzf_note '✖ 选择器返回了不属于当前清单的数据。'; return 1
  }
  JOBS_FZF_SELECTED="${choices[index]}"
  return 0
}
# 按真实候选集记住本层查询；返回保留，候选改变后清空，确认菜单不复用查询。
jobs_fzf_menu() {
  local title="$1" level="${2:-root}" result=0 cache_key="" signature=""
  shift 2
  local -a choices=("$@")
  typeset -gA JOBS_FZF_SAVED_QUERIES JOBS_FZF_SAVED_ROWS
  cache_key="$level"$'\x1f'"$title"
  signature="${(F)choices}"
  local JOBS_FZF_INITIAL_QUERY=""
  if [[ "${JOBS_FZF_SAVED_ROWS[$cache_key]-}" == "$signature" ]]; then
    JOBS_FZF_INITIAL_QUERY="${JOBS_FZF_SAVED_QUERIES[$cache_key]-}"
  fi
  jobs_fzf_pick "$title" "force-$level" "${choices[@]}" || result=$?
  JOBS_FZF_SAVED_ROWS[$cache_key]="$signature"
  JOBS_FZF_SAVED_QUERIES[$cache_key]="$JOBS_FZF_QUERY"
  return "$result"
}
# 为单层旧调用保留纯数据 stdout；多层调用直接使用 pick 的结果和查询字段。
jobs_fzf_choose() {
  jobs_fzf_pick "$@" || return $?
  print -r -- "$JOBS_FZF_SELECTED"
}
# JOBS_FZF_REQUIRED_END

android_find_selector() {
    local mode="${1:-required}"
    [[ "${ANDROID_SIM_MODE:-}" != check ]] || mode=check
    jobs_fzf_ensure "$mode" || return $?
    ANDROID_SIM_FZF="$JOBS_FZF_BIN"
    android_log "✔ 选择器已通过版本与菜单选项复检：$ANDROID_SIM_FZF" '1;32'
}
# 选择清单首项为回车默认值，防止 fzf 配置注入并校验返回值属于当前清单。
android_choose() {
    local title="$1" content="$2" level="${3:-root}" result=0
    local -a rows=("${(@f)content}")
    ANDROID_SIM_SELECTED=""
    [[ -n "$content" && ${#rows} -gt 0 ]] || return 1
    jobs_fzf_menu "$title" "$level" "${rows[@]}" || result=$?
    (( result == 0 )) || return "$result"
    ANDROID_SIM_FZF="$JOBS_FZF_BIN"
    ANDROID_SIM_SELECTED="$JOBS_FZF_SELECTED"
}
# 根据 SDK 自带设备定义列出所有型号，Pixel 手机优先，其余硬件定义仍可选择。
android_device_rows() {
    print -r -- "$ANDROID_SIM_DEVICES" | /usr/bin/awk '
        /^[[:space:]]*id:/ { id=$0; if (id !~ /"/) { id=""; next }; sub(/^[^"]*"/, "", id); sub(/".*$/, "", id) }
        /^[[:space:]]*Name:/ && id != "" {
            name=$0; sub(/^[[:space:]]*Name:[[:space:]]*/, "", name)
            if (id !~ /^[A-Za-z0-9_.-]+$/ || name ~ /[\t\r]/) next
            if (tolower(id " " name) ~ /wear|watch|(^|[ _])tv|television|automotive|desktop/) next
            rank=(id ~ /^pixel_[0-9]+[a-z_]*$/ ? 0 : 1)
            print rank "\t" name "\t" id
        }
    ' | /usr/bin/sort -k1,1n -k2,2Vr | /usr/bin/cut -f2-
}
# 仅从完整的已装手机 / 平板映像发现候选，过滤预览及不匹配 ABI 的镜像。
android_installed_images() {
    local properties relative package image_dir
    local -a packages
    packages=()
    if [[ -d "$ANDROID_SIM_SDK/system-images" ]]; then
        while IFS= read -r -d '' properties; do
            image_dir="${properties:h}"
            relative="${image_dir#"$ANDROID_SIM_SDK/system-images/"}"
            package="system-images;${relative//\//;}"
            if [[ -f "$image_dir/system.img" ]] && print -r -- "$package" | /usr/bin/grep -Eq "^system-images;android-[0-9]+(\\.[0-9]+)?(-ext[0-9]+)?;(google_apis|google_apis_playstore|default);${ANDROID_SIM_ABI}$"; then
                packages+=("$package")
            fi
        done < <(/usr/bin/find "$ANDROID_SIM_SDK/system-images" -type f -name source.properties -print0 2>/dev/null)
    fi
    if (( ${#packages} )); then
        print -rl -- "${packages[@]}" | /usr/bin/sort -t ';' -k2,2Vr -k3,3 -u
    fi
}
# 将精确的包 ID 变为可读行，元数据始终保留完整包标识。
android_image_rows() {
    local package api variant
    while IFS= read -r package; do
        [[ -n "$package" ]] || continue
        api="${package#system-images;android-}"
        api="${api%%;*}"
        variant="${package#system-images;android-${api};}"
        variant="${variant%%;*}"
        print -r -- "API ${api} · ${variant} · ${ANDROID_SIM_ABI}"$'\t'"$package"
    done
}
# 缺少本地映像或主动选择其它映像时自动查询官方稳定、同架构手机 / 平板清单。
android_remote_images() {
    local output="" result=0
    android_log '➤ 将从 Google 官方 Android SDK Repository 查询稳定系统映像；不会修改系统代理。'
    if ! output="$(jobs_sdk_retry 'Google SDK 系统映像清单' "$LOG_FILE" android_remote_images_once)"; then
        android_log "✖ 读取 Google SDK 清单失败：${output}" '1;31'
        android_network_failure_hint
        return 1
    fi
    ANDROID_SIM_IMAGES="$(print -r -- "$output" | /usr/bin/awk -F '|' -v abi="$ANDROID_SIM_ABI" '
        { package=$1; gsub(/^[[:space:]]+|[[:space:]]+$/, "", package)
          if (package ~ ("^system-images;android-[0-9]+(\\.[0-9]+)?(-ext[0-9]+)?;(google_apis|google_apis_playstore|default);" abi "$")) print package }
    ' | /usr/bin/sort -t ';' -k2,2Vr -k3,3 -u)"
    if [[ -z "$ANDROID_SIM_IMAGES" ]]; then
        android_log "➤ SDK Manager 输出：${output}"
        android_log "✖ 官方清单没有可用的 ${ANDROID_SIM_ABI} 手机 / 平板映像。请在 SDK Manager 中检查。" '1;31'
        android_network_failure_hint
        return 1
    fi
}
# 获取清单独立重试；工具返回成功但报告网络失败时仍视为未完成。
android_remote_images_once() {
    local output="" result=0
    output="$(android_timed 60 "$ANDROID_SIM_SDKMANAGER" --sdk_root="$ANDROID_SIM_SDK" --list --channel=0 "${ANDROID_SIM_SDK_PROXY[@]}" 2>&1)" || result=$?
    print -r -- "$output" >> "$LOG_FILE"
    if (( result == 0 )) && print -r -- "$output" | /usr/bin/grep -Eqi 'Failed to download|Failed to fetch|IO exception.*(download|manifest)|Failed to.*(source lists|repository)|Could not download|network.*failed|Connection.*(reset|timed out)|UnknownHostException'; then
        result=1
    fi
    if (( result == 0 )); then
        print -r -- "$output"
    else
        print -u2 -r -- "$output"
    fi
    return "$result"
}
# 优先使用已装映像，允许显式另选下载；安装成功后确认映像文件实际存在。
android_select_image() {
    local installed="$(android_installed_images)" rows="" package image_path result=0
    while true; do
        if [[ -n "$installed" ]]; then
            rows="$(print -r -- "$installed" | android_image_rows)"
            rows+=$'
从 Google 官方源选择其它系统映像	__download__'
            android_choose '选择系统映像（优先已安装）' "$rows" child || return $?
            package="${ANDROID_SIM_SELECTED#*$'	'}"
        else
            package=__download__
        fi
        if [[ "$package" == __download__ ]]; then
            android_remote_images || return $?
            rows="$(print -r -- "$ANDROID_SIM_IMAGES" | android_image_rows)"
            result=0
            android_choose '选择要安装的系统映像' "$rows" child || result=$?
            if (( result == 20 )); then [[ -n "$installed" ]] && continue; return 20; fi
            (( result == 0 )) || return "$result"
            package="${ANDROID_SIM_SELECTED#*$'	'}"
            image_path="$ANDROID_SIM_SDK/${(j:/:)${(s:;:)package}}/system.img"
            [[ -f "$image_path" ]] || android_install_package "$package" || return $?
        fi
        break
    done
    image_path="$ANDROID_SIM_SDK/${(j:/:)${(s:;:)package}}/system.img"
    if [[ ! -f "$image_path" || ! -f "${image_path:h}/source.properties" ]]; then
        android_log "✖ 映像安装后复检失败：${image_path}；已停止创建设备。" '1;31'
        return 1
    fi
    ANDROID_SIM_IMAGE="$package"
}
# 检查 AVD 元数据和实际目录，禁止同名覆盖，包括未能列出的损坏设备。
android_name_exists() {
    local name="$1" avd_home="${ANDROID_AVD_HOME:-${ANDROID_USER_HOME:-${ANDROID_EMULATOR_HOME:-$HOME/.android}}/avd}"
    if [[ -e "$avd_home/$name.ini" || -L "$avd_home/$name.ini" || -e "$avd_home/$name.avd" || -L "$avd_home/$name.avd" ]]; then
        return 0
    fi
    print -r -- "$ANDROID_SIM_AVDS" | /usr/bin/grep -Fxq -- "$name"
}
# 提供可读默认名；名称仅允许 AVD 安全字符，冲突时要求重新选择。
android_choose_name() {
    local default_name="$1" answer=""
    while true; do
        if ! IFS= read -r "?$(jobs_prompt_render "新 AVD 名称（回车用 ${default_name}；q 取消）：")" answer || [[ "$answer" == [qQ] ]]; then
            return 130
        fi
        [[ -n "$answer" ]] || answer="$default_name"
        if [[ ! "$answer" =~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,79}$' ]]; then
            android_log '⚠ 名称须为 1–80 位字母、数字、下划线、点或连字符，首位须为字母 / 数字。' '1;33'
        elif android_name_exists "$answer"; then
            android_log "⚠ 已存在同名 AVD 或遗留目录：${answer}；请换名称，现有内容保持不动。" '1;33'
        else
            ANDROID_SIM_NEW_AVD="$answer"
            return 0
        fi
    done
}
# 分离后台模拟器与终端，短暂检查启动进程，不把进程存活误报为 Android 完成开机。
android_launch() {
    local name="$1" pid=0 launch_log="${LOG_FILE:r}.${1}.emulator.log"
    android_log "➤ 正在启动：${name}"
    /usr/bin/nohup "$ANDROID_SIM_EMULATOR" -avd "$name" > "$launch_log" 2>&1 < /dev/null &!
    pid=$!
    /bin/sleep 2
    if ! kill -0 "$pid" 2>/dev/null; then
        android_log "✖ 模拟器进程已退出，请检查日志：${launch_log}" '1;31'
        return 1
    fi
    android_log "✔ 模拟器启动进程已保持运行（PID ${pid}）；Android 开机仍需等待。关闭终端不会主动停止它。" '1;32'
    android_log "➤ emulator 日志：${launch_log}"
}
# 仅向父运行器预建的空普通文件交接精确设备标识，不创建路径或跟随符号链接。
android_publish_created_device() (
    local created_file="${JOBS_FLUTTER_CREATED_DEVICE_FILE:-}" created_fd="" result=0
    [[ -n "$created_file" ]] || return 0
    if [[ ! -f "$created_file" || -L "$created_file" || -s "$created_file" || ! -O "$created_file" ]]; then
        android_log "✖ 模拟器已创建，但设备交接文件无效；须为本用户预建的空普通文件：${created_file}"
        return 1
    fi
    # 系统 zsh 的 sysopen 不接受含中文的完整路径，父目录由原生 cd 处理。
    if ! cd -- "${created_file:h}" || ! zmodload zsh/system || ! sysopen -w -o nofollow,nonblock -u created_fd "${created_file:t}"; then
        android_log "✖ 模拟器已创建，但无法打开设备交接文件：${created_file}"
        return 1
    fi
    if [[ -f "/dev/fd/$created_fd" && ! -s "/dev/fd/$created_fd" && -O "/dev/fd/$created_fd" ]]; then
        print -r -- $'android\t'"$ANDROID_SIM_NEW_AVD" >&$created_fd || result=1
    else
        result=1
    fi
    exec {created_fd}>&-
    (( result == 0 )) || android_log "✖ 模拟器已创建，但设备交接失败；保留设备，请重新选择：${created_file}"
    return "$result"
)
# 按实际 SDK 型号、架构映像和无冲突名称新增 AVD，不使用 --force 或 wipe。
android_create() {
    local rows="" device_id api default_name answer="" result=0 level="${1:-root}"
    [[ -n "$ANDROID_SIM_SDKMANAGER" ]] || { android_ensure_java && android_ensure_command_tools || return 1; }
    rows="$(android_device_rows)"
    if [[ -z "$rows" ]]; then
        android_log '✖ SDK 中没有可解析的设备定义，请在 SDK Tools 修复命令行工具。' '1;31'
        return 1
    fi
    local select_model=1
    while true; do
        if (( select_model )); then
            android_choose '选择 Android 设备型号' "$rows" "$level" || return $?
            device_id="${ANDROID_SIM_SELECTED#*$'\t'}"
            select_model=0
        fi
        result=0
        android_select_image || result=$?
        if (( result == 20 )); then select_model=1; continue; fi
        (( result == 0 )) || return "$result"
        api="${ANDROID_SIM_IMAGE#system-images;android-}"
        api="${api%%;*}"
        default_name="${device_id}_API_${api}_${ANDROID_SIM_ABI//-/_}"
        android_choose_name "$default_name" || return $?
        android_log "➤ 即将新建：${ANDROID_SIM_NEW_AVD}；设备：${device_id}；系统：${ANDROID_SIM_IMAGE}"
        result=0
        jobs_fzf_pick '确认新建并启动（默认取消；← 返回系统映像）' confirm-child \
            "创建并启动 ${ANDROID_SIM_NEW_AVD}" || result=$?
        if (( result == 20 )); then continue; fi
        (( result == 0 )) || return "$result"
        break
    done
    if android_name_exists "$ANDROID_SIM_NEW_AVD"; then
        android_log '✖ 创建前发现同名设备，已停止以保留现有内容。' '1;31'
        return 1
    fi
    print -r -- no | "$ANDROID_SIM_AVDMANAGER" create avd -n "$ANDROID_SIM_NEW_AVD" -k "$ANDROID_SIM_IMAGE" --device "$device_id" 2>&1 | android_strip_ansi | /usr/bin/tee -a "$LOG_FILE"
    result=${pipestatus[2]}
    if (( result != 0 )); then
        android_log "✖ 创建失败（${result}）；未覆盖已有设备。若有本次同名半成品，请在 Device Manager 人工检查：${ANDROID_SIM_NEW_AVD}" '1;31'
        return "$result"
    fi
    ANDROID_SIM_AVDS="$(android_timed 15 "$ANDROID_SIM_EMULATOR" -list-avds 2>&1)" || return 1
    if ! print -r -- "$ANDROID_SIM_AVDS" | /usr/bin/grep -Fxq -- "$ANDROID_SIM_NEW_AVD"; then
        android_log "✖ 创建命令返回成功，但列表未检出 ${ANDROID_SIM_NEW_AVD}，已停止启动。" '1;31'
        return 1
    fi
    android_log "✔ 已新增 AVD：${ANDROID_SIM_NEW_AVD}" '1;32'
    android_launch "$ANDROID_SIM_NEW_AVD" || return $?
    android_publish_created_device
}
# 双击入口保留已有设备启动能力，同时显式提供新增入口。
android_menu() {
    local rows=$'新建 Android 模拟器\t__create__' name result=0
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        if [[ "$name" =~ '^[A-Za-z0-9][A-Za-z0-9_.-]*$' ]]; then
            rows+=$'\n'"启动 ${name}"$'\t'"$name"
        fi
    done <<< "$ANDROID_SIM_AVDS"
    if [[ -z "$ANDROID_SIM_AVDS" ]]; then
        android_log '➤ 当前没有 AVD，进入新建流程。'
        android_create
        return $?
    fi
    while true; do
        android_choose '选择操作' "$rows" || return $?
        name="${ANDROID_SIM_SELECTED#*$'\t'}"
        if [[ "$name" == __create__ ]]; then
            result=0
            android_create child || result=$?
            (( result != 20 )) || continue
            return "$result"
        fi
        android_launch "$name"
        return $?
    done
}
# 汇总完整依赖与本地状态，健康时不安装或升级，缺失层明确返回失败。
android_check() {
    local failures=0 installed="" count=0
    android_log '➤ 只读自检：不联网、不下载、不安装、不创建设备、不写脚本日志。'
    android_detect_architecture || return 1
    android_find_sdk || return 1
    android_find_java && android_find_command_tools || failures=$((failures + 1))
    android_ensure_emulator || failures=$((failures + 1))
    android_find_selector check || failures=$((failures + 1))
    installed="$(android_installed_images)"
    if [[ -n "$installed" ]]; then
        count="$(print -r -- "$installed" | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
        android_log "✔ 已装匹配架构的手机 / 平板系统映像：${count} 个" '1;32'
        jobs_prompt_output android_log "➤ 优先显示的已有系统映像：${installed%%$'\n'*}"
    else
        android_log "⚠ 尚无完整的 ${ANDROID_SIM_ABI} 手机 / 平板系统映像；交互新建时可选择官方下载安装。" '1;33'
        failures=$((failures + 1))
    fi
    android_log "➤ 已有 AVD：${ANDROID_SIM_AVDS:-无}"
    if (( failures )); then
        android_log "✖ 自检发现 ${failures} 处未就绪；未执行修复。" '1;31'
        return 1
    fi
    android_log '✔ 创建依赖已就绪。' '1;32'
}
# 完整工具链逐层体检与条件修复，供准备入口与正常业务共同使用。
android_prepare_toolchain() {
    ANDROID_SIM_STAGE='本次网络配置检查'
    android_configure_network || return $?
    ANDROID_SIM_STAGE='主机架构体检'
    android_detect_architecture || return $?
    ANDROID_SIM_STAGE='SDK 根目录补齐'
    android_ensure_sdk || return $?
    ANDROID_SIM_STAGE='Java 运行时体检与补齐'
    android_ensure_java || return $?
    ANDROID_SIM_STAGE='SDK 命令行工具体检与补齐'
    android_ensure_command_tools || return $?
    ANDROID_SIM_STAGE='emulator 体检与修复'
    android_ensure_emulator || return $?
    android_log '✔ 工具链体检与必要补齐已完成，继续执行本次操作。' '1;32'
}
# 执行选择模式并统一传播失败或取消状态，任何失败都显示阶段与日志位置。
android_run_requested_action() {
    local result=0
    android_initialize_runtime || return $?
    if [[ "$ANDROID_SIM_MODE" == check ]]; then
        android_check
        return $?
    fi
    if android_prepare_toolchain; then
        if [[ "$ANDROID_SIM_MODE" == prepare ]]; then
            android_log '✔ --prepare 已完成；未查询系统映像或创建设备。' '1;32'
        else
            android_find_selector || return $?
            ANDROID_SIM_STAGE='设备与系统映像选择 / 创建 / 启动'
            if [[ "$ANDROID_SIM_MODE" == create ]]; then
                android_create || result=$?
            else
                android_menu || result=$?
            fi
        fi
    else
        result=$?
    fi
    if (( result == 130 )); then
        android_log '➤ 已取消；未删除或覆盖现有 AVD。'
        result=0
    elif (( result != 0 )); then
        android_log "✖ 自动补齐或操作失败：${ANDROID_SIM_STAGE}；退出码 ${result}。请查看失败命令 / 官方来源输出。" '1;31'
    fi
    android_log "➤ 操作结束；日志：${LOG_FILE}"
    return "$result"
}
# <<< Jobs Android simulator core <<<
# 编排内置自述和独立环境自检、选择与新建 / 启动流程。
main() {
    show_script_intro_and_wait "$@" # 首屏说明影响，区分只读检查与终端确认。
    android_run_requested_action # 沿本次依赖链检查环境，执行所选模拟器操作。
}

main "$@"
