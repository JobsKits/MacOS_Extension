#!/bin/zsh
# shell: zsh
# 脚本自述：通用 iOS 开发 / Ad Hoc IPA 免编译重签工具。
# - 使用本机证书私钥与有效描述文件，分别重签主 App、Widget 和嵌套动态代码。
# - 不登录 Apple、不刷新描述文件、不编译；新包验证后替换原 IPA，回车确认后安装到已选设备。
# - 双击后先确认；过期、设备未授权、权限不匹配或缺少私钥时停止。

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

# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
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
typeset -g SCRIPT_DIR SCRIPT_PATH SCRIPT_BASENAME LOG_FILE WORK_ROOT REPLACEMENT_DIR IPA_PATH TARGET_UDID
typeset -g OTOOL_PATH FZF_PATH PROJECT_FOLDER IPA_BUNDLE_ID
typeset -g IPA_REPLACED=0 FINISH_WAIT=1
# 终端按语义着色；重定向、NO_COLOR 或简陋终端使用纯文本。
display_line() {
  local message="$1" style='' label
  if [[ ! -t 1 || "${TERM:-dumb}" == dumb || -n "${NO_COLOR+x}" ]]; then
    print -r -- "$message"
    return
  fi
  case "$message" in
    '✖'*) style='1;31' ;;
    '⚠'*) style='1;33' ;;
    *'UDID：'*|*'目标设备：'*) style='1;36' ;;
    '✔'*) style='1;32' ;;
    'ℹ'*) style='36' ;;
    '➤'*) style='1;35' ;;
    'Jobs ·'*|'── '*) style='1' ;;
  esac
  if [[ -n "$style" ]]; then
    printf '\033[%sm%s\033[0m\n' "$style" "$message"
  elif [[ "$message" == *：* ]]; then
    label="${message%%：*}"
    printf '\033[1m%s：\033[0m%s\n' "$label" "${message#*：}"
  else
    print -r -- "$message"
  fi
}
# 打印内置说明，确认前不写文件或修改环境。
show_script_intro_and_wait() {
  display_line 'Jobs · 通用 IPA 免编译重签' | jobs_intro_style title
  display_line '用途：对已有 IPA 重新签名；不重新编译源码。' | jobs_intro_style body
  display_line '需要：有效描述文件、对应证书私钥，以及描述文件已授权的设备。' | jobs_intro_style body
  display_line '免费 Personal Team 的描述文件通常只有 7 天；本工具不能续期。' | jobs_intro_style body
  display_line '支持：自有未加密 iOS IPA，保持原团队与 Bundle ID，主 App 和扩展分别签名。' | jobs_intro_style body
  display_line '不支持：App Store 加密包、跨团队迁移、Watch App、macOS / tvOS 包。' | jobs_intro_style body
  display_line '工程目录：回车从 IPA 向上寻找工程根目录并校验；也可手动拖入。再次回车会重新查找。' | jobs_intro_style body | jobs_prompt_filter
  display_line '材料不足时强提示打开 Xcode，人工刷新后在本窗口复检，最多复检三轮。' | jobs_intro_style body
  display_line '范围：在临时副本中重签，完整验证成功后替换原 IPA；失败保留原包，不生成桌面报告或结果目录。' | jobs_intro_style body
  display_line '安装：替换成功后，直接回车安装到已选设备；输入任意字符（包括空格）结束脚本。不自动卸载旧 App。' | jobs_intro_style body | jobs_prompt_filter
  display_line '日志：系统临时目录/IPA免编译重签.时间戳.进程号.log；结束时显示完整路径。' | jobs_intro_style body
  display_line '可选参数：第一个参数为 IPA 绝对路径，第二个参数为设备 UDID。' | jobs_intro_style body
  display_line '未指定 UDID 时自动检测：单台自动选中，多台使用 fzf 选择；无设备可重扫或手动输入。' | jobs_intro_style body
  display_line '遇到钥匙串授权提示，只授权本次 codesign 使用所选证书。Ctrl+C 可取消。' | jobs_intro_style body
  [[ -t 0 ]] || { print -u2 -- '请双击或在交互式终端运行。'; exit 2; }
  read -r "?$(jobs_prompt_render '按回车继续，Ctrl+C 取消：')" || exit 2
}
# 同步终端与纯文本日志。
log() {
  print -r -- "$*" >> "$LOG_FILE"
  display_line "$*"
}
# 输出明确错误并停止下游业务。
fail() {
  log "✖ $*"
  exit 1
}
# 回收本次临时副本，保留日志与成功结果。
finish() {
  local result=$?
  trap - EXIT
  if [[ -n "$REPLACEMENT_DIR" && "$REPLACEMENT_DIR" == "${IPA_PATH:h}/.jobs-ipa-replace."* && -d "$REPLACEMENT_DIR" ]]; then
    /bin/rm -f -- "$REPLACEMENT_DIR/replacement.ipa"
    /bin/rmdir -- "$REPLACEMENT_DIR"
  fi
  if [[ -n "$WORK_ROOT" && "$WORK_ROOT" == "${TMPDIR:-/tmp/}"jobs-ipa-resign.* && -d "$WORK_ROOT" ]]; then
    /bin/rm -rf -- "$WORK_ROOT"
  fi
  print -r -- "日志：$LOG_FILE"
  if (( result != 0 )); then
    if (( IPA_REPLACED )); then
      display_line "⚠ 后续流程未完成；已重签的 IPA 保留在：$IPA_PATH"
    else
      display_line '未生成可交付 IPA；原文件未修改。'
    fi
  fi
  if [[ -t 0 && "$FINISH_WAIT" == 1 ]]; then
    read -r "?$(jobs_prompt_render '按回车关闭：')"
  fi
  exit "$result"
}
# 在整个脚本结束时执行回收，避免 zsh 的函数级 EXIT trap 提前触发。
TRAPEXIT() {
  finish
}
# 初始化运行参数、私有临时目录和失败回收。
initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  umask 077
  SCRIPT_PATH="${0:A}"
  SCRIPT_DIR="$(jobs_layout_directory "$SCRIPT_PATH")"
  SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
  LOG_FILE="${TMPDIR:-/tmp/}IPA免编译重签.$(/bin/date +%Y%m%d-%H%M%S).$$.log"
  : > "$LOG_FILE" || exit 1
  trap 'exit 130' INT
  trap 'exit 143' TERM
  WORK_ROOT=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp/}jobs-ipa-resign.XXXXXX") || fail '无法创建临时目录。'
  IPA_PATH="${1:-}"
  TARGET_UDID="${2:-}"
}
# 解析 Finder 拖入的转义路径，不使用 eval 或执行用户输入。
normalize_file_path() {
  local raw="$1"
  local kind="${2:-file}"
  local -a parts
  raw="${raw%$'\r'}"
  [[ "$raw" == q ]] && exit 0
  if [[ "$kind" == directory && -d "$raw" || "$kind" == file && -f "$raw" ]]; then
    REPLY="${raw:A}"
    return
  fi
  parts=( ${(z)raw} )
  (( ${#parts} == 1 )) || { log '⚠ 每次只接受一个文件，请重新拖入。'; return 1; }
  REPLY="${(Q)parts[1]}"
  [[ "$kind" == directory && -d "$REPLY" || "$kind" == file && -f "$REPLY" ]] || { log "⚠ 路径不存在或类型不正确：$REPLY"; return 1; }
  REPLY="${REPLY:A}"
}
# 读取 IPA 主 App 标识，供工程归属校验使用，不执行包内代码。
read_ipa_identity() {
  local LC_ALL=C
  local entry
  local -a entries
  while IFS= read -r entry; do
    [[ "$entry" =~ '^Payload/[^/]+\.app/Info\.plist$' ]] && entries+=("$entry")
  done < <(/usr/bin/unzip -Z1 "$IPA_PATH")
  (( ${#entries} == 1 )) || fail '无法唯一确定 IPA 主 App 的 Info.plist。'
  /usr/bin/unzip -p "$IPA_PATH" "${entries[1]}" > "$WORK_ROOT/ipa-info.plist" || fail '无法读取 IPA 信息。'
  IPA_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$WORK_ROOT/ipa-info.plist") || fail 'IPA 缺少 Bundle ID。'
}
# 检查真实 iOS 应用 Target 与 IPA 标识，过滤只有同名目录的误匹配。
validate_ios_projects() {
  /usr/bin/osascript -l JavaScript - "$1" "$IPA_BUNDLE_ID" <<'IOSPROJECT'
ObjC.import('Foundation');
function run(args) {
  const text=ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(args[0],$.NSUTF8StringEncoding,null));
  const found=[];
  for(const path of text.trim().split('\n').filter(Boolean)) {
    try {
      const native=$.NSPropertyListSerialization.propertyListWithDataOptionsFormatError($.NSData.dataWithContentsOfFile(path),0,null,null);
      if(!native) continue;
      const p=ObjC.deepUnwrap(native), objects=p.objects, project=objects[p.rootObject];
      if(!project || project.isa!=='PBXProject') continue;
      const root=path.replace(/\/[^/]+\.xcodeproj\/project\.pbxproj$/,'');
      const defaults=((objects[project.buildConfigurationList]||{}).buildConfigurations||[]).map(id=>objects[id]);
      for(const id of project.targets||[]) {
        const t=objects[id];
        if(t.isa!=='PBXNativeTarget' || t.productType!=='com.apple.product-type.application') continue;
        for(const configID of (objects[t.buildConfigurationList]||{}).buildConfigurations||[]) {
          const c=objects[configID], base=defaults.find(b=>b.name===c.name);
          const s=Object.assign({},(base||{}).buildSettings||{},c.buildSettings||{},{SRCROOT:root,PROJECT_DIR:root,TARGET_NAME:t.name,CONFIGURATION:c.name});
          const expand=v=>{let value=String(v||'');for(let i=0;i<10;i++){const next=value.replace(/\$\(([^)]+)\)|\$\{([^}]+)\}/g,(all,a,b)=>typeof s[a||b]==='string'?s[a||b]:all);if(next===value)break;value=next;}return value;};
          const ios=/^iphoneos/.test(expand(s.SDKROOT)) || /\biphoneos\b/.test(expand(s.SUPPORTED_PLATFORMS));
          if(ios && expand(s.PRODUCT_BUNDLE_IDENTIFIER)===args[1]) {found.push(path);break;}
        }
      }
    } catch(e) { /* 无法解析的工程不作为匹配依据。 */ }
  }
  const unique=Array.from(new Set(found));
  if(unique.length!==1) throw Error('未找到唯一匹配 IPA Bundle ID 的 iOS 应用工程（或配置依赖未解析的 xcconfig）。');
  return unique[0];
}
IOSPROJECT
}
# 向上逐层检查工程，识别仓库根目录作为顶层边界，不扫描其它仓库。
discover_project_folder() {
  local cursor="${IPA_PATH:h}" boundary='' candidate project matched=''
  local -a projects
  boundary=$(/usr/bin/git -C "$cursor" rev-parse --show-toplevel 2>/dev/null) || boundary=''
  [[ -n "$boundary" ]] && boundary="${boundary:A}"
  : > "$WORK_ROOT/ancestor-projects.txt"
  while true; do
    projects=("$cursor/"*.xcodeproj/project.pbxproj(N))
    for project in "${projects[@]}"; do
      print -r -- "$project" >> "$WORK_ROOT/ancestor-projects.txt"
    done
    [[ "$cursor" == / || "$cursor" == "$boundary" ]] && break
    cursor="${cursor:h}"
  done
  matched=$(validate_ios_projects "$WORK_ROOT/ancestor-projects.txt" 2>> "$LOG_FILE") || return 1
  candidate="${matched:h:h}"
  [[ -n "$boundary" && "$candidate/" == "$boundary/"* ]] && candidate="$boundary"
  PROJECT_FOLDER="$candidate"
  print -r -- "$matched" > "$WORK_ROOT/projects.txt"
}
# 关联工程根目录；回车每次重新自动查找，失败后保持输入循环。
select_project_folder() {
  local input matched
  read_ipa_identity
  log '── 关联 IPA 对应工程 ──'
  while true; do
    read -r "input?$(jobs_prompt_render '拖入对应工程文件夹；直接回车从 IPA 向上查找（q 退出）：')" < /dev/tty || fail '输入已取消。'
    if [[ -z "${input//[[:space:]]/}" ]]; then
      log "ℹ 从 IPA 所在目录向上查找并验证：${IPA_PATH:h}"
      discover_project_folder || { log '✖ 未找到可验证的对应 iOS 工程根目录。请手动拖入；再次回车将重新查找。'; continue; }
    else
      normalize_file_path "$input" directory || continue
      PROJECT_FOLDER="$REPLY"
      /usr/bin/find "$PROJECT_FOLDER" \( -type d \( -name .git -o -name Pods -o -name node_modules -o -name build -o -name DerivedData -o -name .dart_tool \) -prune \) -o \( -type f -name project.pbxproj -print \) > "$WORK_ROOT/projects.txt"
      matched=$(validate_ios_projects "$WORK_ROOT/projects.txt" 2>> "$LOG_FILE") || { log '✖ 目录未通过对应 iOS 工程校验，请重新拖入；回车可重新自动查找。'; continue; }
      print -r -- "$matched" > "$WORK_ROOT/projects.txt"
    fi
    log "✔ 对应工程：$PROJECT_FOLDER"
    return 0
  done
}
# 静态读取工程配置，不调用构建；只有全部配置一致时才自动使用权限文件。
resolve_project_entitlements() {
  /usr/bin/osascript -l JavaScript - "$WORK_ROOT/projects.txt" "$1" <<'PROJECT'
ObjC.import('Foundation');
function run(args) {
  const read=p=>ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(p,$.NSUTF8StringEncoding,null));
  const matches=[];
  for (const path of read(args[0]).trim().split('\n')) {
    const data=$.NSData.dataWithContentsOfFile(path);
    const plist=$.NSPropertyListSerialization.propertyListWithDataOptionsFormatError(data,0,null,null);
    if (!plist) continue;
    const p=ObjC.deepUnwrap(plist), objects=p.objects, project=objects[p.rootObject];
    const root=path.replace(/\/[^/]+\.xcodeproj\/project\.pbxproj$/,'');
    const projectConfigs=(objects[project.buildConfigurationList]||{}).buildConfigurations||[];
    for (const targetID of project.targets||[]) {
      const target=objects[targetID];
      if (target.isa!=='PBXNativeTarget') continue;
      const configs=(objects[target.buildConfigurationList]||{}).buildConfigurations||[];
      const paths=[]; let hit=false, uncertain=false;
      for (const configID of configs) {
        const config=objects[configID], own=config.buildSettings||{};
        const inherited=projectConfigs.map(id=>objects[id]).find(c=>c.name===config.name);
        const settings=Object.assign({},(inherited||{}).buildSettings||{},own);
        Object.assign(settings,{SRCROOT:root,PROJECT_DIR:root,SOURCE_ROOT:root,TARGET_NAME:target.name,CONFIGURATION:config.name});
        const expand=value=>{
          let text=String(value||'');
          for(let i=0;i<10 && /\$[({]/.test(text);i++) {
            const next=text.replace(/\$\(([^)]+)\)|\$\{([^}]+)\}/g,(all,a,b)=> typeof settings[a||b]==='string'?settings[a||b]:all);
            if(next===text) break; text=next;
          }
          return text;
        };
        const id=expand(settings.PRODUCT_BUNDLE_IDENTIFIER);
        if(id===args[1]) hit=true;
        // 依赖 xcconfig、条件覆盖或不同配置的匹配无法静态确定时，保持人工兜底。
        if(id!==args[1] || !own.PRODUCT_BUNDLE_IDENTIFIER || !own.CODE_SIGN_ENTITLEMENTS || Object.keys(settings).some(k=>/^(PRODUCT_BUNDLE_IDENTIFIER|CODE_SIGN_ENTITLEMENTS)\[/.test(k))) {uncertain=true;continue;}
        const entitlement=expand(settings.CODE_SIGN_ENTITLEMENTS);
        if(!entitlement || /\$[({]/.test(entitlement)) {uncertain=true;continue;}
        const resolved=ObjC.unwrap($(entitlement.startsWith('/')?entitlement:root+'/'+entitlement).stringByStandardizingPath);
        if(!$.NSFileManager.defaultManager.fileExistsAtPath(resolved)) {uncertain=true;continue;}
        paths.push(resolved);
      }
      if(hit) matches.push({uncertain,paths:Array.from(new Set(paths))});
    }
  }
  if(matches.length!==1 || matches[0].uncertain || matches[0].paths.length!==1) throw Error('无法唯一确定该 Bundle ID 的权限配置，请手动提供对应 .entitlements / .xcent。');
  return matches[0].paths[0];
}
PROJECT
}
# 从终端读取文件，避免嵌套文件遍历占用标准输入。
read_file_path() {
  local input
  while true; do
    read -r "input?$(jobs_prompt_render "$1：")" < /dev/tty || fail '输入已取消。'
    if [[ -z "${input//[[:space:]]/}" ]]; then
      log 'ℹ 尚未输入文件，请拖入文件或输入路径；q 退出。'
      continue
    fi
    normalize_file_path "$input" && return 0
  done
}
# 接收 IPA 和实际目标设备，避免沿用固定项目或固定手机。
select_input() {
  log '── 选择 IPA 与目标设备 ──'
  if [[ -z "$IPA_PATH" ]]; then
    read_file_path '请拖入目标 IPA 或输入路径（q 退出）'
    IPA_PATH="$REPLY"
  fi
  [[ -f "$IPA_PATH" && "${IPA_PATH:e:l}" == ipa ]] || fail "不是有效 IPA 文件路径：$IPA_PATH"
  IPA_PATH="${IPA_PATH:A}"
  select_project_folder
  if [[ -z "$TARGET_UDID" ]]; then
    detect_target_device
  fi
  if [[ -z "$TARGET_UDID" ]]; then
    log 'ℹ 请从爱思设备信息复制 UDID；不要填写序列号、IMEI 或 devicectl 的内部 UUID。'
    read -r "TARGET_UDID?$(jobs_prompt_render '目标 iPhone / iPad 的 UDID（q 退出）：')" || fail '输入已取消。'
    [[ "$TARGET_UDID" == q ]] && exit 0
  fi
  [[ "$TARGET_UDID" =~ '^[A-Fa-f0-9-]{16,64}$' ]] || fail '设备 UDID 格式不正确。'
  log "ℹ 输入：$IPA_PATH"
  log "ℹ 目标设备：$TARGET_UDID"
}
# 从结构化设备数据提取硬件 UDID，排除离线记录和模拟器。
parse_connected_devices() {
  /usr/bin/osascript -l JavaScript - "$1" <<'DEVICES'
ObjC.import('Foundation');
function run(args) {
  const data=JSON.parse(ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(args[0],$.NSUTF8StringEncoding,null)));
  if (data.info && data.info.outcome !== 'success') throw Error('设备枚举失败');
  const seen=new Set();
  return ((data.result||{}).devices||[]).map(d=>{
    const p=d.properties||{}, h=p.hardware||d.hardwareProperties||{}, c=p.connection||d.connectionProperties||{}, s=p.state||d.deviceProperties||{};
    const state=c.state||c.tunnelState;
    if (!['connected','available'].includes(state) || !['iPhone','iPad'].includes(h.deviceType) || h.reality!=='physical') return '';
    const udid=h.udid;
    if (!/^(?:[A-Fa-f0-9]{8}-[A-Fa-f0-9]{16}|[A-Fa-f0-9]{40})$/.test(udid||'') || seen.has(udid.toUpperCase())) return '';
    seen.add(udid.toUpperCase());
    const label=[s.name||h.deviceType,h.marketingName||'',c.transportType||''].join(' · ').replace(/[\r\n\t]/g,' ');
    return udid+'\t'+label;
  }).filter(Boolean).join('\n');
}
DEVICES
}
# 检查 PATH 与两种 Homebrew 路径中的 fzf，并保存实际可用入口。
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

find_healthy_fzf() {
  jobs_fzf_find || return $?
  FZF_PATH="$JOBS_FZF_BIN"
}
# 缺失或损坏时提供一次安装修复机会，完成后重新发现并验证。
ensure_fzf() {
  jobs_fzf_ensure || return $?
  FZF_PATH="$JOBS_FZF_BIN"
}
# 使用 fzf 单选真实设备行，取消或异常时不自动选取首项。
select_device_with_fzf() {
  local result=0
  jobs_fzf_menu '目标设备（名称 · 型号 · 连接方式 | UDID）' root "$@" || result=$?
  if (( result == 130 )); then log 'ℹ 已取消设备选择。'; exit 0; fi
  (( result == 0 )) || return "$result"
  FZF_PATH="$JOBS_FZF_BIN"
  TARGET_UDID="${JOBS_FZF_SELECTED%%$'\t'*}"
  log "✔ 已选择：${JOBS_FZF_SELECTED#*$'\t'}，UDID：$TARGET_UDID"
}
# 单设备自动使用，多设备通过 fzf 选择，检测失败时保留手动输入兜底。
detect_target_device() {
  local answer row
  local -a devices
  while true; do
    log 'ℹ 正在检测已连接的 iPhone / iPad…'
    devices=()
    if /usr/bin/xcrun devicectl --timeout 15 list devices --json-output "$WORK_ROOT/devices.json" >> "$LOG_FILE" 2>&1; then
      if parse_connected_devices "$WORK_ROOT/devices.json" > "$WORK_ROOT/devices.tsv" 2>> "$LOG_FILE"; then
        while IFS= read -r row; do
          [[ -n "$row" ]] && devices+=("$row")
        done < "$WORK_ROOT/devices.tsv"
      fi
    fi
    if (( ${#devices} == 1 )); then
      TARGET_UDID="${devices[1]%%$'\t'*}"
      log "✔ 自动选中：${devices[1]#*$'\t'}，UDID：$TARGET_UDID"
      return 0
    fi
    if (( ${#devices} > 1 )); then
      select_device_with_fzf "${devices[@]}" || return $?
      return 0
    else
      log '⚠ 未检测到可用设备。请用数据线连接、解锁并信任此 Mac；检查 Xcode 工具链是否可用。'
      read -r "answer?$(jobs_prompt_render '连接后输入 r 重扫；回车或 m 手动输入；q 退出：')" < /dev/tty || fail '输入已取消。'
    fi
    case "$answer" in
      q|Q) exit 0 ;;
      m|M|'') return 0 ;;
      r|R) continue ;;
      *) log '⚠ 选项无效，请重新选择。' ;;
    esac
  done
}
# 强提示用户打开 Xcode；打开后仍须人工完成签名刷新。
wait_for_xcode() {
  local answer
  while ! /usr/bin/pgrep -x Xcode >/dev/null; do
    log '⚠⚠ 请打开 Xcode。当前未检测到 Xcode 运行，本步骤暂停。'
    read -r "answer?$(jobs_prompt_render '输入 o 打开 Xcode；手动打开后按回车复检；q 退出：')" || fail '输入已取消。'
    case "$answer" in
      q|Q) exit 0 ;;
      o|O) /usr/bin/open -b com.apple.dt.Xcode >> "$LOG_FILE" 2>&1 || log '⚠ 无法启动 Xcode，请先安装或手动打开。' ;;
    esac
  done
  log 'ℹ 已检测到 Xcode；这仅证明应用已打开，不代表签名材料已更新。'
}
# 验证完整原生依赖链，缺失时不自动安装工具。
check_environment() {
  local command_path
  for command_path in /usr/bin/codesign /usr/bin/security /usr/bin/plutil /usr/bin/osascript /usr/bin/ditto /usr/bin/unzip /usr/bin/shasum /usr/bin/base64 /usr/bin/find /usr/libexec/PlistBuddy /usr/bin/file; do
    [[ -x "$command_path" ]] || fail "缺少系统工具：$command_path"
  done
  /usr/bin/security find-identity -v -p codesigning > "$WORK_ROOT/identities.txt" 2>> "$LOG_FILE" || fail '钥匙串不可用。'
  /usr/bin/osascript -l JavaScript -e 'ObjC.import("Foundation"); "ok"' >> "$LOG_FILE" 2>&1 || fail '系统 JavaScript/Foundation 不可用。'
  /usr/bin/plutil -help > /dev/null || fail 'plutil 不可用。'
  if ! OTOOL_PATH=$(/usr/bin/xcrun --find otool 2>> "$LOG_FILE"); then
    wait_for_xcode
    fail 'otool 不可用；请完成 Xcode 首次启动组件安装，并在 Settings → Locations 配置 Command Line Tools 后重试。'
  fi
  "$OTOOL_PATH" -h /usr/bin/true >> "$LOG_FILE" 2>&1 || fail 'otool 无法工作，请检查 Xcode 工具链。'
}
# 解包并检查路径边界，仅接受一个主 App。
unpack_ipa() {
  /usr/bin/unzip -t "$IPA_PATH" >> "$LOG_FILE" 2>&1 || fail 'IPA 压缩数据损坏。'
  /usr/bin/unzip -Z1 "$IPA_PATH" > "$WORK_ROOT/entries.txt" || fail '无法读取 ZIP 目录。'
  local entry target
  while IFS= read -r entry; do
    [[ "$entry" != /* && "/$entry/" != */../* ]] || fail 'ZIP 包含越界路径。'
  done < "$WORK_ROOT/entries.txt"
  /usr/bin/ditto -x -k "$IPA_PATH" "$WORK_ROOT/unpacked" >> "$LOG_FILE" 2>&1 || fail '解压失败。'
  while IFS= read -r -d '' entry; do
    target="${entry:A}"
    [[ "$target" == "${WORK_ROOT:A}/unpacked/"* ]] || fail "符号链接越界：$entry"
  done < <(/usr/bin/find "$WORK_ROOT/unpacked" -type l -print0)
  local -a main_apps
  main_apps=("$WORK_ROOT/unpacked/Payload/"*.app(N/))
  (( ${#main_apps} == 1 )) || fail '只支持 Payload 下一个主 App 的 IPA。'
  /bin/mkdir -p "$WORK_ROOT/bundles" "$WORK_ROOT/profiles" || fail '无法建立检查目录。'
  local bundle index=0 bundle_id executable fallback
  while IFS= read -r -d '' bundle; do
    (( ++index ))
    [[ "$bundle" != *$'\n'* && "$bundle" != *$'\t'* ]] || fail '不支持路径中的换行或制表符。'
    /bin/mkdir "$WORK_ROOT/bundles/$index" || fail '无法建立 bundle 检查目录。'
    print -r -- "$bundle" > "$WORK_ROOT/bundles/$index/path.txt"
    /bin/cp "$bundle/Info.plist" "$WORK_ROOT/bundles/$index/info.plist" || fail '缺少 Info.plist。'
    bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Info.plist") || fail '缺少 Bundle ID。'
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$bundle/Info.plist" 2>/dev/null)" == iPhoneOS ]] || fail "仅支持 iOS App / 扩展：$bundle_id"
    if ! /usr/bin/security cms -D -i "$bundle/embedded.mobileprovision" > "$WORK_ROOT/bundles/$index/old.plist" 2>> "$LOG_FILE"; then
      log "⚠ $bundle_id 没有可用的原始描述文件。为保持团队与 App ID 前缀，请提供该 target 的原始描述文件。"
      read_file_path '拖入该 target 的 .mobileprovision（可过期，仅用于确认原身份；q 退出）'
      /usr/bin/security cms -D -i "$REPLY" > "$WORK_ROOT/bundles/$index/old.plist" 2>> "$LOG_FILE" || fail '描述文件不可解析。'
    fi
    /usr/bin/codesign -d --xml --entitlements - "$bundle" > "$WORK_ROOT/bundles/$index/requested.plist" 2>> "$LOG_FILE"
    if [[ ! -s "$WORK_ROOT/bundles/$index/requested.plist" ]]; then
      bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Info.plist")
      log "⚠ $bundle_id 的原签名没有权限数据，正在匹配工程 Target。"
      if fallback=$(resolve_project_entitlements "$bundle_id" 2>> "$LOG_FILE"); then
        log "✔ 自动定位权限文件：$fallback"
      else
        log '⚠ 工程配置无法唯一解析；请提供对应 target 的 .entitlements 或构建生成的 .xcent。'
        read_file_path '拖入对应权限文件（q 退出）'
        fallback="$REPLY"
      fi
      /bin/cp "$fallback" "$WORK_ROOT/bundles/$index/requested.plist" || fail '权限恢复失败。'
      log "⚠ $bundle_id 缺少签名权限，将根据项目 entitlements 和新描述文件恢复。"
    fi
    /usr/bin/plutil -lint "$WORK_ROOT/bundles/$index/requested.plist" >> "$LOG_FILE" 2>&1 || fail '权限文件不可解析。'
  done < <(/usr/bin/find "${main_apps[1]}" -depth -type d \( -name '*.app' -o -name '*.appex' \) -print0)
  (( index > 0 )) || fail '未找到可签名 App。'
}
# 检查加密负载和暂不支持的嵌套代码；不执行 IPA 中的程序。
inspect_payload() {
  local item format
  while IFS= read -r -d '' item; do
    [[ "$item" != *.xpc ]] || fail '暂不支持嵌套 XPC 服务。'
  done < <(/usr/bin/find "$WORK_ROOT/unpacked/Payload" -type d -name '*.xpc' -print0)
  while IFS= read -r -d '' item; do
    format=$(/usr/bin/file -b "$item") || fail '无法检测文件类型。'
    [[ "$format" == *Mach-O* ]] || continue
    "$OTOOL_PATH" -l "$item" > "$WORK_ROOT/load-commands.txt" 2>> "$LOG_FILE" || fail "无法检查 Mach-O：$item"
    if /usr/bin/awk '$1 == "cryptid" && $2 != "0" {found=1} END {exit !found}' "$WORK_ROOT/load-commands.txt"; then
      fail "检测到加密二进制，不能通过重新签名安装：$item"
    fi
  done < <(/usr/bin/find "$WORK_ROOT/unpacked/Payload" -type f -print0)
}
# 收集 Xcode 缓存中的描述文件及其允许的证书指纹。
collect_profiles() {
  local source decoded cert_index fingerprint index=0
  local -a roots
  /bin/rm -f -- "$WORK_ROOT/profiles/"*(N)
  /usr/bin/security find-identity -v -p codesigning > "$WORK_ROOT/identities.txt" 2>> "$LOG_FILE" || fail '钥匙串读取失败。'
  roots=("$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles" "$SCRIPT_DIR/描述文件")
  : > "$WORK_ROOT/certificates.tsv"
  for source in "${roots[@]}"; do
    [[ -d "$source" ]] || continue
    local profile
    while IFS= read -r -d '' profile; do
      (( ++index ))
      decoded="$WORK_ROOT/profiles/$index.plist"
      /usr/bin/security cms -D -i "$profile" > "$decoded" 2>> "$LOG_FILE" || { /bin/rm -f "$decoded"; log "⚠ 跳过无法解析的描述文件：${profile:t}"; continue; }
      /bin/cp "$profile" "$WORK_ROOT/profiles/$index.mobileprovision" || fail '无法暂存描述文件。'
      cert_index=0
      while /usr/bin/plutil -extract "DeveloperCertificates.$cert_index" raw -o "$WORK_ROOT/cert.base64" "$decoded" 2>/dev/null; do
        fingerprint=$(/usr/bin/base64 -D -i "$WORK_ROOT/cert.base64" | /usr/bin/shasum -a 1) || fail '证书指纹计算失败。'
        fingerprint="${fingerprint%% *}"
        printf '%s\t%s\n' "$index" "${(U)fingerprint}" >> "$WORK_ROOT/certificates.tsv"
        (( ++cert_index ))
      done
    done < <(/usr/bin/find "$source" -type f -name '*.mobileprovision' -print0)
  done
}
# 写入内嵌的原生 plist 匹配器；不依赖 Python、Node 或第三方包。
write_planner() {
  /bin/cat > "$WORK_ROOT/plan.js" <<'JXA'
ObjC.import('Foundation');
// 读取原生 plist，同时保留布尔、数组和日期类型。
function plist(p) {
  const data = $.NSData.dataWithContentsOfFile(p);
  if (!data) throw Error('无法读取 ' + p);
  return ObjC.deepUnwrap($.NSPropertyListSerialization.propertyListWithDataOptionsFormatError(data, 0, null, null));
}
// 读取文本清单。
function text(p) { return ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(p, $.NSUTF8StringEncoding, null)); }
// 安全落盘计划与 JSON 权限文件。
function write(p, s) { if (!$(s).writeToFileAtomicallyEncodingError(p, true, $.NSUTF8StringEncoding, null)) throw Error('写入失败 ' + p); }
// 列举当前目录，避免执行拼接的 shell 命令。
function names(p) { return ObjC.deepUnwrap($.NSFileManager.defaultManager.contentsOfDirectoryAtPathError(p, null)); }
// 描述文件只允许相等值或自身声明的通配范围。
function allowed(value, permit) {
  if (Array.isArray(value)) return Array.isArray(permit) && value.every(v => permit.some(p => allowed(v, p)));
  if (typeof value === 'string' && typeof permit === 'string') {
    const re = '^' + permit.split('*').map(s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('.*') + '$';
    return new RegExp(re).test(value);
  }
  if (value && typeof value === 'object') return permit && Object.keys(value).every(k => allowed(value[k], permit[k]));
  return value === permit;
}
// 为每个 bundle 保留请求的权限，仅补签名必需标识。
function entitlements(requested, profile, bundleID) {
  const permit = profile.Entitlements;
  const appID = profile.ApplicationIdentifierPrefix[0] + '.' + bundleID;
  // 仅展开标准 Xcode 标识变量，未知构建变量交给用户提供 .xcent。
  function expand(v) {
    if (Array.isArray(v)) return v.map(expand);
    if (v && typeof v==='object') { const o={}; Object.keys(v).forEach(k=>o[k]=expand(v[k])); return o; }
    if (typeof v!=='string') return v;
    const values={AppIdentifierPrefix:profile.ApplicationIdentifierPrefix[0]+'.',TeamIdentifierPrefix:profile.TeamIdentifier[0]+'.',CFBundleIdentifier:bundleID,PRODUCT_BUNDLE_IDENTIFIER:bundleID};
    const result=v.replace(/\$\(([^)]+)\)|\$\{([^}]+)\}/g,(_,a,b)=>{
      if (!Object.prototype.hasOwnProperty.call(values,a||b)) throw Error('未知构建变量，请提供 .xcent：'+(a||b));
      return values[a||b];
    });
    return result;
  }
  const ent = expand(requested);
  ent['application-identifier'] = appID;
  ent['com.apple.developer.team-identifier'] = profile.TeamIdentifier[0];
  ent['get-task-allow'] = permit['get-task-allow'];
  if (!ent['keychain-access-groups']) ent['keychain-access-groups'] = [appID];
  for (const key of Object.keys(ent)) {
    if (!allowed(ent[key], permit[key])) throw Error('描述文件未授权权限：' + key);
  }
  return ent;
}
// 从同团队、同前缀、同证书且包含目标设备的描述文件中选择最晚到期者。
function run(args) {
  const root = args[0], udid = args[1];
  const identities = text(root + '/identities.txt').match(/[A-F0-9]{40}/g) || [];
  const certs = {};
  text(root + '/certificates.tsv').trim().split('\n').filter(Boolean).forEach(l => {
    const v=l.split('\t'); (certs[v[0]] || (certs[v[0]]=[])).push(v[1]);
  });
  const profiles = names(root + '/profiles').filter(n => n.endsWith('.plist')).map(n => ({index:n.slice(0,-6), p:plist(root+'/profiles/'+n)}));
  const bundles = names(root + '/bundles').sort((a,b)=>Number(a)-Number(b)).map(n => {
    const dir=root+'/bundles/'+n;
    return {index:n, path:text(dir+'/path.txt').trimEnd(), info:plist(dir+'/info.plist'), old:plist(dir+'/old.plist'), requested:plist(dir+'/requested.plist')};
  });
  let report = ['IPA 重签预检', '目标 UDID：'+udid, '生成时间：'+new Date().toISOString()];
  const matches = bundles.map(b => {
    const id=b.info.CFBundleIdentifier;
    if (!b.old.TeamIdentifier || !b.old.ApplicationIdentifierPrefix || !b.old.Entitlements || !allowed(b.old.ApplicationIdentifierPrefix[0]+'.'+id,b.old.Entitlements['application-identifier'])) throw Error('提供的原始描述文件与 Bundle ID 不匹配：'+id);
    const compatible = profiles.filter(x => x.p.TeamIdentifier && x.p.ApplicationIdentifierPrefix && x.p.Entitlements && x.p.TeamIdentifier[0]===b.old.TeamIdentifier[0] && x.p.ApplicationIdentifierPrefix[0]===b.old.ApplicationIdentifierPrefix[0] && allowed(x.p.ApplicationIdentifierPrefix[0]+'.'+id,x.p.Entitlements['application-identifier']));
    const candidates=[];
    for (const x of compatible) {
      const p=x.p, reason=[];
      if (!(new Date(p.ExpirationDate).getTime()>Date.now())) reason.push('描述文件已过期 '+new Date(p.ExpirationDate).toISOString());
      if (!(p.ProvisionedDevices || []).some(d=>d.toUpperCase()===udid.toUpperCase())) reason.push('未授权目标设备（仅支持 Development / Ad Hoc）');
      if (typeof p.Entitlements['get-task-allow']!=='boolean') reason.push('缺少有效的 get-task-allow');
      if (!(certs[x.index]||[]).some(c=>identities.includes(c))) reason.push('缺少匹配的有效证书私钥');
      let ent;
      try { ent=entitlements(b.requested,p,id); } catch(e) { reason.push(e.message); }
      report.push(id+' / '+p.Name+' / '+(reason.length?reason.join('；'):'可用'));
      if (!reason.length) candidates.push({x,ent});
    }
    if (!compatible.length) report.push(id+'：未找到同团队、同 App ID 的描述文件');
    return {b,candidates};
  });
  let choice=null;
  for (const identity of identities) {
    const selected=matches.map(m=>m.candidates.filter(c=>(certs[c.x.index]||[]).includes(identity)).sort((a,b)=>new Date(b.x.p.ExpirationDate)-new Date(a.x.p.ExpirationDate))[0]);
    if (selected.every(Boolean)) { choice={identity,selected}; break; }
  }
  write(root+'/report.txt',report.join('\n')+'\n');
  if (!choice) throw Error('预检失败：没有可同时签署全部 App/扩展的有效材料。请在 Xcode 更新对应团队、全部 target 的描述文件及证书。');
  const plan=[];
  matches.forEach((m,i)=>{
    const c=choice.selected[i];
    write(root+'/bundles/'+m.b.index+'/entitlements.json',JSON.stringify(c.ent));
    plan.push([m.b.index,c.x.index,choice.identity].join('\t'));
    report.push('采用：'+m.b.info.CFBundleIdentifier+'；有效至 '+new Date(c.x.p.ExpirationDate).toISOString());
  });
  write(root+'/plan.tsv',plan.join('\n')+'\n');
  write(root+'/identity.txt',choice.identity);
  write(root+'/report.txt',report.join('\n')+'\n');
  return '主 App 与扩展的描述文件、设备、证书及权限均已匹配。';
}
JXA
}
# 在任何实际签名前完成全部 bundle 的检查。
prepare_signing_plan() {
  log '── 签名材料检查 ──'
  local attempt answer
  for attempt in 0 1 2 3; do
    collect_profiles
    /bin/rm -f "$WORK_ROOT/plan.tsv" "$WORK_ROOT/report.txt"
    if /usr/bin/osascript -l JavaScript "$WORK_ROOT/plan.js" "$WORK_ROOT" "$TARGET_UDID" > "$WORK_ROOT/planner.log" 2>&1; then
      /bin/cat "$WORK_ROOT/report.txt" | /usr/bin/tee -a "$LOG_FILE"
      log 'ℹ 本机材料已齐备，无需启动 Xcode 或编译。'
      return 0
    fi
    [[ -f "$WORK_ROOT/report.txt" ]] && /bin/cat "$WORK_ROOT/report.txt" | /usr/bin/tee -a "$LOG_FILE"
    /bin/cat "$WORK_ROOT/planner.log" | /usr/bin/tee -a "$LOG_FILE"
    (( attempt < 3 )) || fail '三轮复检仍未通过；已停止。请按报告解决签名材料问题后重新运行。'
    log '⚠⚠ 签名材料不齐，暂停重签。打开 Xcode 只是第一步。'
    wait_for_xcode
    log '➤ 打开目标 IPA 对应工程；Settings → Accounts 登录原团队账号。'
    log '➤ 主 App 和每个扩展的 Signing & Capabilities 选择原 Team；免费账号使用 Automatically manage signing。'
    log '➤ 连接目标设备，确认其 UDID 已授权；等待签名刷新，必要时 Try Again 或 Run 一次，无需 Clean。'
    log '➤ 也可把有效 .mobileprovision 放入本脚本旁的“描述文件”目录；私钥仍必须在钥匙串。'
    read -r "answer?$(jobs_prompt_render '完成刷新后输入 r 复检；直接回车或 q 退出：')" || fail '输入已取消。'
    [[ "$answer" == r || "$answer" == R ]] || exit 0
  done
}
# 将全部嵌套动态代码从内到外签名，再分别签署扩展和主 App。
sign_payload() {
  log '── 重签 App 与扩展 ──'
  local identity="$(<"$WORK_ROOT/identity.txt")" item bundle_index profile_index planned_identity bundle
  log 'ℹ 预检通过，开始签署临时副本。'
  while IFS= read -r -d '' item; do
    if [[ -f "$item" ]]; then
      [[ "$(/usr/bin/file -b "$item")" == *Mach-O* ]] || continue
    elif [[ "$item" == *.bundle ]]; then
      [[ -f "$item/Info.plist" ]] || continue
      /usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$item/Info.plist" >/dev/null 2>&1 || continue
    elif [[ "$item" != *.framework ]]; then
      continue
    fi
    /usr/bin/codesign --force --sign "$identity" --generate-entitlement-der "$item" >> "$LOG_FILE" 2>&1 || fail "嵌套代码签名失败：$item"
  done < <(/usr/bin/find "$WORK_ROOT/unpacked/Payload" -depth \( -type f -o -type d -name '*.framework' -o -type d -name '*.bundle' \) -print0)
  while IFS=$'\t' read -r bundle_index profile_index planned_identity; do
    bundle="$(<"$WORK_ROOT/bundles/$bundle_index/path.txt")"
    /usr/bin/plutil -convert xml1 -o "$WORK_ROOT/bundles/$bundle_index/entitlements.plist" "$WORK_ROOT/bundles/$bundle_index/entitlements.json" || fail '权限转换失败。'
    /bin/cp "$WORK_ROOT/profiles/$profile_index.mobileprovision" "$bundle/embedded.mobileprovision" || fail '无法替换副本描述文件。'
    /usr/bin/codesign --force --sign "$planned_identity" --entitlements "$WORK_ROOT/bundles/$bundle_index/entitlements.plist" --generate-entitlement-der "$bundle" >> "$LOG_FILE" 2>&1 || fail "App/扩展签名失败：$bundle"
    /usr/bin/codesign --verify --deep --strict "$bundle" >> "$LOG_FILE" 2>&1 || fail "签名完整性失败：$bundle"
    # codesign 的文件输出会追加；标准输出重定向覆盖，并按 Target 隔离回读文件。
    /usr/bin/codesign -d --xml --entitlements - "$bundle" > "$WORK_ROOT/bundles/$bundle_index/actual.plist" 2>> "$LOG_FILE" || fail '无法回读签名权限。'
    /usr/bin/plutil -convert json -o "$WORK_ROOT/bundles/$bundle_index/actual.json" "$WORK_ROOT/bundles/$bundle_index/actual.plist" || fail '回读的签名权限无效。'
    /usr/bin/osascript -l JavaScript -e 'ObjC.import("Foundation"); function run(a){function read(p){return JSON.parse(ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(p,$.NSUTF8StringEncoding,null)));} function norm(v){if(Array.isArray(v))return v.map(norm);if(v&&typeof v==="object"){let o={};Object.keys(v).sort().forEach(k=>o[k]=norm(v[k]));return o;}return v;}const actual=read(a[0]), expected=read(a[1]); const keys=Array.from(new Set(Object.keys(actual).concat(Object.keys(expected)))); const diff=keys.filter(k=>JSON.stringify(norm(actual[k]))!==JSON.stringify(norm(expected[k]))); if(diff.length)throw Error("签名权限差异键："+diff.join(", "));}' "$WORK_ROOT/bundles/$bundle_index/actual.json" "$WORK_ROOT/bundles/$bundle_index/entitlements.json" >> "$LOG_FILE" 2>&1 || fail "写入与回读的签名权限不一致：$bundle（差异键见日志）。"
    log "✔ 签名与权限回读一致：${bundle:t}"
  done < "$WORK_ROOT/plan.tsv"
}
# 同目录暂存并原子替换，复制或校验失败时不触碰原 IPA。
replace_verified_ipa() {
  REPLACEMENT_DIR=$(/usr/bin/mktemp -d "${IPA_PATH:h}/.jobs-ipa-replace.XXXXXX") || fail '原 IPA 目录不可写，无法替换。'
  /bin/cp "$1" "$REPLACEMENT_DIR/replacement.ipa" || fail '新 IPA 暂存失败，原包保留。'
  /usr/bin/cmp -s "$1" "$REPLACEMENT_DIR/replacement.ipa" || fail '新 IPA 复制校验失败，原包保留。'
  /bin/mv -f "$REPLACEMENT_DIR/replacement.ipa" "$IPA_PATH" || fail '原 IPA 替换失败。'
  IPA_REPLACED=1
  /bin/rmdir "$REPLACEMENT_DIR"
  REPLACEMENT_DIR=''
  log "✔ 已用重签后的 IPA 替换原文件：$IPA_PATH"
}
# 压缩后再次解包验证，成功后才替换原文件。
package_and_verify() {
  log '── 打包与最终验证 ──'
  /usr/bin/ditto -c -k --norsrc --keepParent "$WORK_ROOT/unpacked/Payload" "$WORK_ROOT/resigned.ipa" >> "$LOG_FILE" 2>&1 || fail '压缩 IPA 失败。'
  /usr/bin/unzip -t "$WORK_ROOT/resigned.ipa" >> "$LOG_FILE" 2>&1 || fail '最终 ZIP 校验失败。'
  /usr/bin/ditto -x -k "$WORK_ROOT/resigned.ipa" "$WORK_ROOT/verify" >> "$LOG_FILE" 2>&1 || fail '最终解包复验失败。'
  local app
  for app in "$WORK_ROOT/verify/Payload/"*.app(N/); do
    /usr/bin/codesign --verify --deep --strict "$app" >> "$LOG_FILE" 2>&1 || fail '最终 IPA 签名复验失败。'
  done
  replace_verified_ipa "$WORK_ROOT/resigned.ipa"
  log 'ℹ 本地签名与压缩校验已通过；尚未安装到手机，最终以 iOS 安装验证为准。'
  log 'ℹ 即将询问是否直接安装；开发签名在适用系统上需要开启开发者模式。'
}
# 调用 Xcode 设备安装工具，保留原始错误与结构化安装结果。
run_device_install() {
  /usr/bin/xcrun devicectl device install app --device "$TARGET_UDID" "$1" --timeout 180 --json-output "$WORK_ROOT/install-result.json"
}
# 回车才安装；任意字符均结束，不再追加关闭窗口确认。
confirm_and_install() {
  local answer app
  local -a apps
  log '── 安装到手机 ──'
  log "ℹ 安装目标设备：$TARGET_UDID"
  log "ℹ 已重签 IPA：$IPA_PATH"
  IFS= read -r "answer?$(jobs_prompt_render '直接回车确认安装；输入任意字符结束脚本：')" < /dev/tty || { FINISH_WAIT=0; exit 0; }
  if [[ -n "$answer" ]]; then
    log 'ℹ 已跳过安装，重签后的 IPA 已保留。'
    FINISH_WAIT=0
    exit 0
  fi
  apps=("$WORK_ROOT/verify/Payload/"*.app(N/))
  (( ${#apps} == 1 )) || fail '无法唯一定位最终 IPA 中已验证的 App。'
  app="${apps[1]}"
  log 'ℹ 开始安装，请保持手机连接并解锁；如果设备询问信任，请在设备上确认。'
  if ! run_device_install "$app" 2>&1 | /usr/bin/tee -a "$LOG_FILE"; then
    fail '设备安装未成功或超时，具体原因见上方工具输出；重签 IPA 保留，不自动卸载旧 App。'
  fi
  /usr/bin/osascript -l JavaScript -e 'ObjC.import("Foundation"); function run(a){const s=ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(a[0],$.NSUTF8StringEncoding,null));const result=JSON.parse(s);if(!result.info || result.info.outcome!=="success")throw Error("未获得明确的安装成功结果");}' "$WORK_ROOT/install-result.json" >> "$LOG_FILE" 2>&1 || fail '无法确认安装成功，请检查设备；重签 IPA 保留。'
  log "✔ 安装成功，目标设备：$TARGET_UDID"
}
# 编排交互、完整预检、重签与最终交付。
main() {
  show_script_intro_and_wait # 先展示范围并等待确认。
  initialize_runtime "$@" # 建立日志与临时副本上下文。
  select_input # 接收拖入的 IPA 与目标设备 UDID。
  check_environment # 检查系统工具和可用证书私钥。
  unpack_ipa # 解包并恢复每个 App 的权限请求。
  inspect_payload # 拦截加密包与不支持的嵌套代码。
  write_planner # 准备原生 plist 权限与授权检查器。
  prepare_signing_plan # 材料全部合格后才允许签名。
  sign_payload # 按嵌套顺序分别签名并回读验证。
  package_and_verify # 对最终 IPA 复验并替换原文件。
  confirm_and_install # 回车确认后安装到已选设备，任意字符结束。
}

main "$@"
