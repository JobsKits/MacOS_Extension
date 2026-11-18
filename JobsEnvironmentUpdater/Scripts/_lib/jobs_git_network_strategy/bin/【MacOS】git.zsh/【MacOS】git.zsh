#!/bin/zsh
# 脚本自述：
# - 脚本名称：Jobs Git 网络策略入口。
# - 核心用途：HTTP(S) 网络命令按可配置优先级短探测直连与当前系统代理。
# - 影响范围：代理只传给本次 Git 子进程；不写 Git / 系统代理配置，原始命令不重放。
# - 运行提示：普通 Git 调用无额外交互；VPN 关闭时自动使用可达的直连，Ctrl+C 取消。
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
    jobs_style_applied_rows=''
    jobs_style_changed=0
    jobs_style_applied_complete=0
    jobs_style_query_active=0
    jobs_style_recovery=''
    jobs_style_exit_status=0
    jobs_style_esc=$(printf '\033')
    jobs_style_bel=$(printf '\007')
    # 只接受本次请求对应的 RGB 响应；非协议输入使本次探测失败。
    jobs_terminal_style_query() {
        jobs_style_query_key=$1
        printf '\033]%s;?\007' "$jobs_style_query_key" > /dev/tty || return 1
        jobs_style_reply=''
        for jobs_style_attempt in 1 2 3; do
            jobs_style_piece=$(dd bs=256 count=1 2>/dev/null < /dev/tty)
            jobs_style_reply=$jobs_style_reply$jobs_style_piece
            case $jobs_style_reply in
                *"$jobs_style_bel"|*"$jobs_style_esc\\") break ;;
                '') ;;
                "$jobs_style_esc"*) ;;
                *) break ;;
            esac
        done
        case $jobs_style_reply in
            "$jobs_style_esc]$jobs_style_query_key;rgb:"*"$jobs_style_bel")
                jobs_style_rgb=${jobs_style_reply#"$jobs_style_esc]$jobs_style_query_key;rgb:"}
                jobs_style_rgb=${jobs_style_rgb%"$jobs_style_bel"}
                ;;
            "$jobs_style_esc]$jobs_style_query_key;rgb:"*"$jobs_style_esc\\")
                jobs_style_rgb=${jobs_style_reply#"$jobs_style_esc]$jobs_style_query_key;rgb:"}
                jobs_style_rgb=${jobs_style_rgb%"$jobs_style_esc\\"}
                ;;
            *) return 1 ;;
        esac
        jobs_style_normalized=$(printf '%s\n' "$jobs_style_rgb" | LC_ALL=C awk -F/ '
            NF != 3 { exit 1 }
            {
                for (i = 1; i <= 3; i++) {
                    h = tolower($i)
                    if (length(h) < 1 || length(h) > 4 || h ~ /[^0-9a-f]/) exit 1
                    n = 0
                    for (j = 1; j <= length(h); j++) n = n * 16 + index("0123456789abcdef", substr(h, j, 1)) - 1
                    value[i] = int(n * 65535 / (16 ^ length(h) - 1) + 0.5)
                }
                printf "%d/%d/%d", value[1], value[2], value[3]
            }
        ') || return 1
        [ -n "$jobs_style_normalized" ]
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
            jobs_style_conflicts=''
            jobs_style_restore_safe=''
            if [ "$jobs_style_applied_complete" = 1 ]; then
                jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_style_stty=''
                if [ -n "$jobs_style_stty" ] && stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
                    jobs_style_query_active=1
                    jobs_style_cleanup_ok=1
                    while IFS='|' read -r jobs_style_key jobs_style_expected jobs_style_original; do
                        [ -n "$jobs_style_key" ] || continue
                        if ! jobs_terminal_style_query "$jobs_style_key"; then
                            jobs_style_cleanup_ok=0
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
                    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || jobs_style_cleanup_ok=0
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
                printf '终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh "%s"\n' "$jobs_style_recovery" >&2
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
    trap 'jobs_style_exit_status=129; exit 129' HUP
    trap 'jobs_style_exit_status=130; exit 130' INT
    trap 'jobs_style_exit_status=143; exit 143' TERM
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
        trap 'jobs_style_exit_status=129; exit 129' HUP
        trap 'jobs_style_exit_status=130; exit 130' INT
        trap 'jobs_style_exit_status=143; exit 143' TERM
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

typeset -ga ORIGINAL_ARGS GLOBAL_ARGS PUSH_ARGS COMMAND_ARGS PROXY_URLS PROXY_HOSTS PROXY_PORTS
typeset -g AUDIT_FILE='' TARGET_URL='' TARGET_ROOT=''
typeset -g TARGET_HOST='-' TARGET_PORT='-' TARGET_REMOTE=''
typeset -g NETWORK_COMMAND='' NETWORK_REPOSITORY='' NETWORK_SKIP_REASON='' CLONE_REMOTE='origin'
typeset -g CONNECT_TIMEOUT=2 PROBE_TIMEOUT=4
typeset -g DEFAULT_ROUTE_PRIORITY='system' ROUTE_PRIORITY='system' SELECTED_PROXY=''

# 始终使用系统 Git，避免入口经 PATH 再次调用自己。
real_git() {
    /usr/bin/git "$@"
}
# 无需自动选路时替换当前进程，保持 Git 输出和退出语义。
exec_real_git() {
    exec /usr/bin/git "$@"
    exit $?
}
# clone 不读取所在父仓的 local 配置；查询保留 system / global 与显式命令行配置。
metadata_git() {
    if [[ "$NETWORK_COMMAND" != clone ]]; then
        real_git "${GLOBAL_ARGS[@]}" "$@"
        return $?
    fi
    local -a remaining=( "${GLOBAL_ARGS[@]}" ) query_args=()
    local argument=''
    while (( ${#remaining} )); do
        argument="${remaining[1]}"
        case "$argument" in
            -C|--git-dir|--work-tree|--namespace|--super-prefix)
                shift 2 remaining
                ;;
            -C?*|--git-dir=*|--work-tree=*|--namespace=*|--super-prefix=*|--bare)
                shift remaining
                ;;
            -c|--config-env)
                query_args+=( "${remaining[1]}" "${remaining[2]}" )
                shift 2 remaining
                ;;
            *)
                query_args+=( "$argument" )
                shift remaining
                ;;
        esac
    done
    (
        builtin cd / || return 1
        real_git "${query_args[@]}" "$@"
    )
}
# 识别 Git 全局参数和支持的网络命令；未知形式保留原生语义。
parse_network_invocation() {
    ORIGINAL_ARGS=( "$@" )
    GLOBAL_ARGS=()
    PUSH_ARGS=()
    COMMAND_ARGS=()
    NETWORK_COMMAND=''
    NETWORK_SKIP_REASON=''
    local -a remaining=( "$@" )
    local option=''
    while (( ${#remaining} )); do
        option="${remaining[1]}"
        case "$option" in
            -c|-C|--git-dir|--work-tree|--namespace|--config-env|--super-prefix)
                (( ${#remaining} >= 2 )) || return 1
                GLOBAL_ARGS+=( "${remaining[1]}" "${remaining[2]}" )
                shift 2 remaining
                ;;
            -c?*|-C?*|--git-dir=*|--work-tree=*|--namespace=*|--config-env=*|--super-prefix=*|--exec-path=*)
                GLOBAL_ARGS+=( "$option" )
                shift remaining
                ;;
            -p|-P|--paginate|--no-pager|--bare|--no-replace-objects|--literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs|--no-optional-locks|--no-lazy-fetch|--no-advice)
                GLOBAL_ARGS+=( "$option" )
                shift remaining
                ;;
            -*)
                return 1
                ;;
            clone|fetch|pull|ls-remote|push)
                NETWORK_COMMAND="$option"
                shift remaining
                COMMAND_ARGS=( "${remaining[@]}" )
                PUSH_ARGS=( "${remaining[@]}" )
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    done
    return 1
}
# 先确认单一 HTTP(S) 目标，再显示不阻塞普通 Git 调用的内置自述。
show_network_intro_and_route() {
    if ! parse_network_invocation "$@"; then
        exec_real_git "$@"
    fi
    if ! resolve_single_http_network_target; then
        [[ -z "$NETWORK_SKIP_REASON" ]] || print -u2 -r -- "[Jobs Git] ${NETWORK_SKIP_REASON}；本次原生透传，不自动选路。"
        exec_real_git "$@"
    fi
    configure_route_priority
    if [[ "$ROUTE_PRIORITY" == system ]]; then
        print -u2 -r -- '[Jobs Git] 系统代理优先；当前代理均不可达时短探测直连，原始命令只执行一次。'
    else
        print -u2 -r -- '[Jobs Git] 直连优先；连接失败后短探测当前系统代理，原始命令只执行一次。'
    fi
    print -u2 -r -- "[Jobs Git] 代理仅影响本次 Git 及子进程；流量经过选定代理，退出即撤回，Ctrl+C 取消。审计：${HOME}/Library/Logs/JobsGitNetworkStrategy/push.log"
}
# 建立最小权限审计位置；无法写日志时仍保留原生 Git 可用性。
prepare_audit() {
    local audit_directory="${HOME}/Library/Logs/JobsGitNetworkStrategy"
    AUDIT_FILE=''
    if [[ -L "$audit_directory" || -L "${audit_directory}/push.log" ]]; then
        print -u2 -r -- '[Jobs Git] 审计路径为符号链接，本次跳过审计。'
        return 0
    fi
    if ! /bin/mkdir -p "$audit_directory" 2>/dev/null; then
        print -u2 -r -- '[Jobs Git] 无法创建审计目录，本次跳过审计。'
        return 0
    fi
    if ! /bin/chmod 700 "$audit_directory" 2>/dev/null; then
        return 0
    fi
    if ! { : >> "${audit_directory}/push.log"; } 2>/dev/null; then
        return 0
    fi
    /bin/chmod 600 "${audit_directory}/push.log" 2>/dev/null || return 0
    AUDIT_FILE="${audit_directory}/push.log"
}
# 日志只记录模式、经过校验的主机/端口和退出码，不记录命令或原始诊断。
audit_result() {
    [[ -n "$AUDIT_FILE" ]] || return 0
    local mode="$1" host="$2" port="$3" result="$4"
    [[ "$mode" =~ '^[a-z-]+$' ]] || return 0
    is_safe_proxy_host "$host" || host='-'
    [[ "$port" =~ '^([0-9]+|-)$' ]] || port='-'
    [[ "$result" =~ '^[0-9]+$' ]] || result=1
    printf '%s mode=%s host=%s port=%s exit=%s\n' \
        "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')" "$mode" "$host" "$port" "$result" >> "$AUDIT_FILE" 2>/dev/null
    return 0
}
# 中断时立即终止选路，不进入后续代理探测或 Git 业务。
TRAPINT() {
    exit 130
}
# 收到终止信号后不再探测或启动子进程。
TRAPTERM() {
    exit 143
}
# 解析 push 的目标参数；不明确的选项保守交回原生 Git。
push_repository_argument() {
    local -a remaining=( "${PUSH_ARGS[@]}" )
    local repository='' argument=''
    while (( ${#remaining} )); do
        argument="${remaining[1]}"
        case "$argument" in
            --repo)
                (( ${#remaining} >= 2 )) || return 1
                [[ -z "$repository" ]] || return 1
                repository="${remaining[2]}"
                shift 2 remaining
                ;;
            --repo=*)
                [[ -z "$repository" ]] || return 1
                repository="${argument#--repo=}"
                shift remaining
                ;;
            --receive-pack|--exec|--push-option|-o)
                (( ${#remaining} >= 2 )) || return 1
                shift 2 remaining
                ;;
            --receive-pack=*|--exec=*|--push-option=*|-o?*|--force-with-lease=*|--signed=*|--recurse-submodules=*)
                shift remaining
                ;;
            -u|--set-upstream|-v|--verbose|-q|--quiet|--all|--branches|--prune|--mirror|-d|--delete|--tags|-n|--dry-run|--porcelain|-f|--force|--force-with-lease|--force-if-includes|--no-force-if-includes|--no-verify|--verify|--atomic|--no-atomic|--follow-tags|--no-follow-tags|--signed|--no-signed|--thin|--no-thin|--progress|--no-progress|-4|--ipv4|-6|--ipv6)
                shift remaining
                ;;
            --)
                shift remaining
                if (( ${#remaining} )); then
                    [[ -z "$repository" ]] || return 1
                    repository="${remaining[1]}"
                fi
                break
                ;;
            -*)
                return 1
                ;;
            *)
                if [[ -z "$repository" ]]; then
                    repository="$argument"
                fi
                shift remaining
                ;;
        esac
    done
    print -r -- "$repository"
}
# 按 Git 的默认 push remote 优先级选择一个目标，不改变仓库配置。
default_push_remote() {
    local branch='' selected='' remotes=''
    branch="$(real_git "${GLOBAL_ARGS[@]}" symbolic-ref --quiet --short HEAD 2>/dev/null)"
    if [[ -n "$branch" ]]; then
        selected="$(real_git "${GLOBAL_ARGS[@]}" config --get "branch.${branch}.pushRemote" 2>/dev/null)"
        if [[ -n "$selected" ]]; then
            print -r -- "$selected"
            return 0
        fi
    fi
    selected="$(real_git "${GLOBAL_ARGS[@]}" config --get remote.pushDefault 2>/dev/null)"
    if [[ -n "$selected" ]]; then
        print -r -- "$selected"
        return 0
    fi
    if [[ -n "$branch" ]]; then
        selected="$(real_git "${GLOBAL_ARGS[@]}" config --get "branch.${branch}.remote" 2>/dev/null)"
        if [[ -n "$selected" ]]; then
            print -r -- "$selected"
            return 0
        fi
    fi
    remotes="$(real_git "${GLOBAL_ARGS[@]}" remote 2>/dev/null)"
    local -a names=( "${(@f)remotes}" )
    if (( ${#names} == 1 )) && [[ -n "${names[1]}" ]]; then
        print -r -- "${names[1]}"
        return 0
    fi
    if (( ${names[(Ie)origin]} )); then
        print -r -- origin
        return 0
    fi
    return 1
}
# 拆出不含凭据、路径和查询参数的 HTTP 站点，只用于只读连通性探测。
parse_http_target() {
    local url="$1" scheme='' authority='' host='' port=''
    [[ "$url" != *$'\n'* && "$url" != *$'\r'* ]] || return 1
    if [[ "$url" == https://* ]]; then
        scheme=https
        port=443
    elif [[ "$url" == http://* ]]; then
        scheme=http
        port=80
    else
        return 1
    fi
    authority="${url#*://}"
    authority="${authority%%[/?#]*}"
    authority="${authority##*@}"
    if [[ "$authority" =~ '^\[([0-9A-Fa-f:]+)\](:([0-9]+))?$' ]]; then
        host="[${match[1]}]"
        [[ -n "${match[3]}" ]] && port="${match[3]}"
    elif [[ "$authority" =~ '^([A-Za-z0-9_.-]+)(:([0-9]+))?$' ]]; then
        host="${match[1]}"
        [[ -n "${match[3]}" ]] && port="${match[3]}"
    else
        return 1
    fi
    (( ${#port} <= 5 )) || return 1
    (( 10#$port >= 1 && 10#$port <= 65535 )) || return 1
    TARGET_URL="$url"
    TARGET_HOST="$host"
    TARGET_PORT="$port"
    TARGET_ROOT="${scheme}://${authority}/"
    return 0
}
# 展开真实 push URL；多个地址或 SSH / 本地目标不进入自动选路。
resolve_single_http_push_target() {
    local repository='' urls=''
    if ! repository="$(push_repository_argument)"; then
        NETWORK_SKIP_REASON='push 参数无法安全确定单一目标'
        return 1
    fi
    [[ -n "$repository" ]] || repository="$(default_push_remote)" || return 1
    TARGET_REMOTE=''
    if [[ "$repository" =~ '^[A-Za-z0-9_][A-Za-z0-9._/-]*$' ]]; then
        urls="$(real_git "${GLOBAL_ARGS[@]}" remote get-url --push --all "$repository" 2>/dev/null)"
        if [[ $? == 0 && -n "$urls" ]]; then
            TARGET_REMOTE="$repository"
        else
            urls=''
        fi
    fi
    if [[ -z "$urls" ]]; then
        urls="$(expand_push_repository_url "$repository")" || return 1
    fi
    local -a expanded_urls=( "${(@f)urls}" )
    if (( ${#expanded_urls} != 1 )); then
        NETWORK_SKIP_REASON='push 配置含多个目标地址'
        return 1
    fi
    parse_http_target "${expanded_urls[1]}"
}
# 显式 push 地址先按最长 pushInsteadOf 前缀展开，否则复用 Git 的只读 insteadOf 解析。
expand_push_repository_url() {
    local repository="$1" records='' record='' key='' prefix='' base=''
    local best_prefix='' best_base=''
    records="$(metadata_git config --null --get-regexp '^url\..*\.pushinsteadof$' 2>/dev/null)"
    for record in "${(@0)records}"; do
        [[ "$record" == *$'\n'* ]] || continue
        key="${record%%$'\n'*}"
        prefix="${record#*$'\n'}"
        [[ -n "$prefix" && "$repository" == "$prefix"* ]] || continue
        if (( ${#prefix} > ${#best_prefix} )); then
            best_prefix="$prefix"
            base="${key#url.}"
            best_base="${base%.pushinsteadof}"
        fi
    done
    if [[ -n "$best_prefix" ]]; then
        print -r -- "${best_base}${repository#"$best_prefix"}"
        return 0
    fi
    metadata_git ls-remote --get-url "$repository"
}
# 提取 clone 的仓库与可选目标目录；命令内配置和递归形式交回原生 Git。
parse_clone_repository() {
    local -a remaining=( "${COMMAND_ARGS[@]}" ) positional=()
    local argument=''
    CLONE_REMOTE=origin
    while (( ${#remaining} )); do
        argument="${remaining[1]}"
        case "$argument" in
            --)
                shift remaining
                positional+=( "${remaining[@]}" )
                break
                ;;
            --origin|-o)
                (( ${#remaining} >= 2 )) || return 1
                CLONE_REMOTE="${remaining[2]}"
                shift 2 remaining
                ;;
            --origin=*|-o?*)
                [[ "$argument" == --origin=* ]] && CLONE_REMOTE="${argument#*=}" || CLONE_REMOTE="${argument#-o}"
                shift remaining
                ;;
            --template|--branch|-b|--upload-pack|-u|--reference|--reference-if-able|--separate-git-dir|--depth|--shallow-since|--shallow-exclude|--filter|--jobs|-j|--server-option|--revision)
                (( ${#remaining} >= 2 )) || return 1
                shift 2 remaining
                ;;
            --template=*|--branch=*|-b?*|--upload-pack=*|-u?*|--reference=*|--reference-if-able=*|--separate-git-dir=*|--depth=*|--shallow-since=*|--shallow-exclude=*|--filter=*|--jobs=*|-j?*|--server-option=*|--revision=*)
                shift remaining
                ;;
            --config|-c|--config=*|-c?*)
                NETWORK_SKIP_REASON='clone 含命令内配置，保留其原有作用域'
                return 1
                ;;
            --recursive|--recursive=*|--recurse-submodules|--recurse-submodules=*|--bundle-uri|--bundle-uri=*)
                NETWORK_SKIP_REASON='递归子模块或 bundle 可能连接多个目标'
                return 1
                ;;
            -l|--local|--no-local|--no-hardlinks|-s|--shared|-q|--quiet|-v|--verbose|--progress|-n|--no-checkout|--bare|--mirror|--dissociate|--single-branch|--no-single-branch|--tags|--no-tags|--shallow-submodules|--no-shallow-submodules|--sparse|--reject-shallow|--no-reject-shallow|--remote-submodules|--no-remote-submodules|--also-filter-submodules|--no-also-filter-submodules|--no-recurse-submodules)
                shift remaining
                ;;
            -*)
                NETWORK_SKIP_REASON='clone 参数无法安全确定单一目标'
                return 1
                ;;
            *)
                positional+=( "$argument" )
                shift remaining
                ;;
        esac
    done
    (( ${#positional} >= 1 && ${#positional} <= 2 )) || return 1
    [[ "$CLONE_REMOTE" =~ '^[A-Za-z0-9_][A-Za-z0-9._/-]*$' ]] || return 1
    NETWORK_REPOSITORY="${positional[1]}"
    return 0
}
# 解析 fetch / pull / ls-remote 的单一仓库参数，后续 refspec / pattern 原样保留。
parse_read_repository() {
    local -a remaining=( "${COMMAND_ARGS[@]}" )
    local argument=''
    NETWORK_REPOSITORY=''
    while (( ${#remaining} )); do
        argument="${remaining[1]}"
        case "$argument" in
            --)
                shift remaining
                [[ -n "$NETWORK_REPOSITORY" || ${#remaining} == 0 ]] || NETWORK_REPOSITORY="${remaining[1]}"
                break
                ;;
            --all|--multiple|--recurse-submodules|--recurse-submodules=*|--recurse-submodules-default=*)
                NETWORK_SKIP_REASON='多仓库或递归子模块形式可能连接多个目标'
                return 1
                ;;
            --upload-pack|--depth|--deepen|--shallow-since|--shallow-exclude|--negotiation-tip|--filter|--server-option|--jobs|-j|--refmap|--sort|--strategy|-s|--strategy-option|-X|--cleanup)
                (( ${#remaining} >= 2 )) || return 1
                shift 2 remaining
                ;;
            --upload-pack=*|--depth=*|--deepen=*|--shallow-since=*|--shallow-exclude=*|--negotiation-tip=*|--filter=*|--server-option=*|--jobs=*|-j?*|--refmap=*|--sort=*|--strategy=*|-s?*|--strategy-option=*|-X?*|--cleanup=*|--rebase=*|--log=*|--gpg-sign=*|--show-forced-updates=*)
                shift remaining
                ;;
            -q|--quiet|-v|--verbose|--progress|--no-progress|-f|--force|-k|--keep|-u|--update-head-ok|--update-shallow|--unshallow|--append|-a|--atomic|--no-atomic|--dry-run|-n|--no-tags|-t|--tags|--no-recurse-submodules|-p|--prune|--no-prune|--prune-tags|--no-prune-tags|--no-write-fetch-head|--write-fetch-head|--keep-auto|--no-auto-maintenance|--auto-maintenance|--no-auto-gc|--auto-gc|--no-write-commit-graph|--write-commit-graph|--negotiate-only|--show-forced-updates|--no-show-forced-updates|-4|--ipv4|-6|--ipv6|--exit-code|--symref|-h|--heads|--branches|--refs|-r|--rebase|--no-rebase|--ff-only|--ff|--no-ff|--commit|--no-commit|--edit|--no-edit|--squash|--no-squash|--verify|--no-verify|--signoff|--no-signoff|--allow-unrelated-histories|--autostash|--no-autostash|--stat|--no-stat|--log|--no-log|--gpg-sign|--no-gpg-sign|--no-verify-signatures|--verify-signatures|--no-overwrite-ignore|--overwrite-ignore|--compact-summary|--no-compact-summary)
                shift remaining
                ;;
            -*)
                NETWORK_SKIP_REASON="${NETWORK_COMMAND} 参数无法安全确定单一目标"
                return 1
                ;;
            *)
                [[ -n "$NETWORK_REPOSITORY" ]] || NETWORK_REPOSITORY="$argument"
                shift remaining
                ;;
        esac
    done
    return 0
}
# fetch / pull / ls-remote 沿用当前分支的 remote，否则由 origin 交给 Git 校验。
default_read_remote() {
    local branch='' selected=''
    branch="$(real_git "${GLOBAL_ARGS[@]}" symbolic-ref --quiet --short HEAD 2>/dev/null)"
    if [[ -n "$branch" ]]; then
        selected="$(real_git "${GLOBAL_ARGS[@]}" config --get "branch.${branch}.remote" 2>/dev/null)"
        if [[ -n "$selected" ]]; then
            print -r -- "$selected"
            return 0
        fi
    fi
    print -r -- origin
}
# 用 Git 自身展开 URL 重写规则；帮助、本地、SSH 与不明确的多目标保持透明。
resolve_single_http_network_target() {
    local argument='' urls=''
    local -a expanded_urls=()
    NETWORK_REPOSITORY=''
    TARGET_REMOTE=''
    for argument in "${COMMAND_ARGS[@]}"; do
        case "$argument" in
            --help)
                return 1
                ;;
            -h)
                [[ "$NETWORK_COMMAND" == ls-remote && ${#COMMAND_ARGS} -gt 1 ]] || return 1
                ;;
            --get-url)
                [[ "$NETWORK_COMMAND" == ls-remote ]] && return 1
                ;;
        esac
    done
    if [[ "$NETWORK_COMMAND" == push ]]; then
        for argument in "${COMMAND_ARGS[@]}"; do
            case "$argument" in
                --recurse-submodules|--recurse-submodules=*)
                    NETWORK_SKIP_REASON='递归子模块可能连接多个目标'
                    return 1
                    ;;
            esac
        done
        if ! resolve_single_http_push_target; then
            return 1
        fi
        if has_recursive_network_config; then
            NETWORK_SKIP_REASON='配置启用了递归子模块，可能连接多个目标'
            return 1
        fi
        return 0
    elif [[ "$NETWORK_COMMAND" == clone ]]; then
        parse_clone_repository || return 1
    else
        parse_read_repository || return 1
        if [[ -z "$NETWORK_REPOSITORY" && "$NETWORK_COMMAND" != ls-remote ]] && has_fetch_all_config; then
            NETWORK_SKIP_REASON='fetch.all 配置可能连接多个仓库'
            return 1
        fi
        [[ -n "$NETWORK_REPOSITORY" ]] || NETWORK_REPOSITORY="$(default_read_remote)" || return 1
        if [[ "$NETWORK_REPOSITORY" =~ '^[A-Za-z0-9_][A-Za-z0-9._/-]*$' ]]; then
            urls="$(real_git "${GLOBAL_ARGS[@]}" remote get-url --all "$NETWORK_REPOSITORY" 2>/dev/null)"
            if [[ $? == 0 && -n "$urls" ]]; then
                TARGET_REMOTE="$NETWORK_REPOSITORY"
            else
                urls=''
            fi
        fi
    fi
    if [[ -z "$urls" ]]; then
        urls="$(metadata_git ls-remote --get-url "$NETWORK_REPOSITORY" 2>/dev/null)" || return 1
    fi
    expanded_urls=( "${(@f)urls}" )
    if (( ${#expanded_urls} != 1 )); then
        NETWORK_SKIP_REASON='仓库配置含多个目标地址'
        return 1
    fi
    parse_http_target "${expanded_urls[1]}" || return 1
    [[ "$NETWORK_COMMAND" != clone ]] || TARGET_REMOTE="$CLONE_REMOTE"
    if has_recursive_network_config; then
        NETWORK_SKIP_REASON='配置启用了递归子模块，可能连接多个目标'
        return 1
    fi
    return 0
}
# 无显式目标时 fetch.all 可能扩展到不同站点，保留原生多仓库语义。
has_fetch_all_config() {
    local value=''
    value="$(metadata_git config --get fetch.all 2>/dev/null)" || return 1
    case "${value:l}" in
        false|no|off|0)
            return 1
            ;;
    esac
    return 0
}
# 明确递归配置与含 gitlink 的默认按需 fetch 都可能访问其它站点。
has_recursive_network_config() {
    local value='' key=''
    local -a keys=()
    case "$NETWORK_COMMAND" in
        clone|ls-remote)
            return 1
            ;;
    esac
    for value in "${COMMAND_ARGS[@]}"; do
        [[ "$value" != --no-recurse-submodules ]] || return 1
    done
    case "$NETWORK_COMMAND" in
        fetch|pull)
            keys=( fetch.recurseSubmodules submodule.recurse )
            ;;
        push)
            keys=( push.recurseSubmodules submodule.recurse )
            ;;
    esac
    for key in "${keys[@]}"; do
        value="$(metadata_git config --get "$key" 2>/dev/null)" || continue
        case "${value:l}" in
            false|no|off|0)
                return 1
                ;;
            *)
                return 0
                ;;
        esac
    done
    if [[ "$NETWORK_COMMAND" == fetch || "$NETWORK_COMMAND" == pull ]]; then
        metadata_git ls-files --stage 2>/dev/null | /usr/bin/grep -q '^160000 ' && return 0
    fi
    return 1
}
# 用户已有显式代理或显式空代理时保留其选择，不替换配置作用域。
has_explicit_proxy() {
    local variable=''
    for variable in http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY; do
        (( ${+parameters[$variable]} )) && return 0
    done
    metadata_git config --get-urlmatch http.proxy "$TARGET_URL" >/dev/null 2>&1 && return 0
    if [[ -n "$TARGET_REMOTE" ]]; then
        metadata_git config --get "remote.${TARGET_REMOTE}.proxy" >/dev/null 2>&1 && return 0
    fi
    return 1
}
# 在失败发生后读取当前系统代理，避免固定某个本机端口。
system_proxy_snapshot() {
    /usr/sbin/scutil --proxy
}
# 只接受普通主机名或 IPv6 字面量，拒绝凭据、空白和 URL 片段。
is_safe_proxy_host() {
    [[ "$1" =~ '^([A-Za-z0-9_.-]+|[0-9A-Fa-f:]+|\[[0-9A-Fa-f:]+\])$' ]]
}
# 匹配主机/通配域名和 IPv4 CIDR；IPv6 CIDR 无法精确判断时保守保留旁路。
proxy_rules_bypass_target() {
    local rules="$1" exclude_simple="${2:-0}"
    print -r -- "$rules" | /usr/bin/awk -v host="${TARGET_HOST:l}" -v simple="$exclude_simple" '
        function ipv4(value, octets, count, i, result) {
            count=split(value,octets,"."); if (count<1 || count>4) return -1
            result=0
            for (i=1;i<=4;i++) {
                if (i<=count && (octets[i]!~/^[0-9]+$/ || octets[i]>255)) return -1
                result=result*256+(i<=count ? octets[i] : 0)
            }
            return result
        }
        function matches(rule, pair, prefix, divisor, left, right, regex, i, character) {
            if (rule=="<local>") return host !~ /[.:]/
            if (index(rule,"/")) {
                split(rule,pair,"/")
                if (index(pair[1],":") && index(host,":")) return 1
                if (host !~ /^[0-9.]+$/ || pair[2]!~/^[0-9]+$/ || pair[2]>32) return 0
                left=ipv4(host); right=ipv4(pair[1]); divisor=2^(32-pair[2])
                return left>=0 && right>=0 && int(left/divisor)==int(right/divisor)
            }
            if (rule==host) return 1
            if (substr(rule,1,1)==".") rule=substr(rule,2)
            if (host==rule || (length(host)>length(rule) && substr(host,length(host)-length(rule))=="." rule)) return 1
            regex="^"
            for (i=1;i<=length(rule);i++) {
                character=substr(rule,i,1)
                if (character=="*") regex=regex ".*"
                else if (character=="?") regex=regex "."
                else if (character ~ /[A-Za-z0-9_-]/) regex=regex character
                else regex=regex "\\" character
            }
            return host ~ (regex "$")
        }
        BEGIN {
            sub(/^\[/,"",host); sub(/\]$/,"",host)
            if (simple=="1" && host !~ /[.:]/) matched=1
        }
        { rule=tolower($0); gsub(/^[[:space:]]+|[[:space:]]+$/,"",rule); if (length(rule) && matches(rule)) matched=1 }
        END { exit matched ? 0 : 1 }
    '
}
# 保留系统代理例外与现有 NO_PROXY；不把被排除的主机导向回退代理。
target_bypasses_proxy() {
    local snapshot="$1" rules='' exclude_simple=0
    rules="$(print -r -- "$snapshot" | /usr/bin/awk '
        /ExceptionsList[[:space:]]*:[[:space:]]*<array>/ { in_exceptions=1; next }
        in_exceptions && /^[[:space:]]*}/ { in_exceptions=0 }
        in_exceptions && /^[[:space:]]*[0-9]+[[:space:]]*:/ { sub(/^[^:]*:[[:space:]]*/, ""); print }
    ')"
    print -r -- "$snapshot" | /usr/bin/grep -Eq '^[[:space:]]*ExcludeSimpleHostnames[[:space:]]*:[[:space:]]*1[[:space:]]*$' && exclude_simple=1
    proxy_rules_bypass_target "$rules" "$exclude_simple" && return 0
    local variable=''
    for variable in no_proxy NO_PROXY; do
        rules="${(P)variable}"
        rules="${rules//,/$'\n'}"
        proxy_rules_bypass_target "$rules" 0 && return 0
    done
    return 1
}
# 优先 HTTPS、其次 HTTP、最后 SOCKS；仅接受已启用、合法且不含凭据的地址。
discover_system_proxies() {
    PROXY_URLS=()
    PROXY_HOSTS=()
    PROXY_PORTS=()
    local snapshot='' rows='' kind='' host='' port='' proxy='' scheme=''
    snapshot="$(system_proxy_snapshot 2>/dev/null)" || return 1
    target_bypasses_proxy "$snapshot" && return 2
    rows="$(print -r -- "$snapshot" | /usr/bin/awk '
        /^[[:space:]]*(HTTPSEnable|HTTPSProxy|HTTPSPort|HTTPEnable|HTTPProxy|HTTPPort|SOCKSEnable|SOCKSProxy|SOCKSPort)[[:space:]]*:/ {
            key=$1; value=$0; sub(/^[^:]*:[[:space:]]*/, "", value); sub(/[[:space:]]*$/, "", value); values[key]=value
        }
        END {
            split("HTTPS HTTP SOCKS", kinds, " ")
            for (i=1;i<=3;i++) {
                kind=kinds[i]
                if (values[kind "Enable"]=="1") printf "%s\t%s\t%s\n", kind, values[kind "Proxy"], values[kind "Port"]
            }
        }')"
    while IFS=$'\t' read -r kind host port; do
        [[ -n "$kind" && "$port" =~ '^[0-9]+$' ]] || continue
        is_safe_proxy_host "$host" || continue
        (( ${#port} <= 5 )) || continue
        (( 10#$port >= 1 && 10#$port <= 65535 )) || continue
        [[ "$host" == *:* && "$host" != \[*\] ]] && host="[${host}]"
        scheme=http
        [[ "$kind" == SOCKS ]] && scheme=socks5h
        proxy="${scheme}://${host}:${port}"
        (( ${PROXY_URLS[(Ie)$proxy]} )) && continue
        PROXY_URLS+=( "$proxy" )
        PROXY_HOSTS+=( "$host" )
        PROXY_PORTS+=( "$port" )
    done <<< "$rows"
    (( ${#PROXY_URLS} > 0 ))
}
# 允许按本机网络选择系统代理或直连优先，不改变任何持久代理值。
configure_route_priority() {
    ROUTE_PRIORITY="${JOBS_GIT_ROUTE_PRIORITY:-$DEFAULT_ROUTE_PRIORITY}"
    case "$ROUTE_PRIORITY" in
        system|direct)
            return 0
            ;;
    esac
    print -u2 -r -- "[Jobs Git] JOBS_GIT_ROUTE_PRIORITY 无效，使用 ${DEFAULT_ROUTE_PRIORITY} 优先级。"
    ROUTE_PRIORITY="$DEFAULT_ROUTE_PRIORITY"
}
# 校验可配置短超时，避免错误环境值变成无限等待。
configure_probe_timeouts() {
    CONNECT_TIMEOUT="${JOBS_GIT_CONNECT_TIMEOUT:-2}"
    PROBE_TIMEOUT="${JOBS_GIT_PROBE_TIMEOUT:-4}"
    if [[ ! "$CONNECT_TIMEOUT" =~ '^[0-9]{1,2}$' ]] || (( 10#$CONNECT_TIMEOUT < 1 || 10#$CONNECT_TIMEOUT > 60 )); then
        print -u2 -r -- '[Jobs Git] JOBS_GIT_CONNECT_TIMEOUT 无效，使用 2 秒连接探测。'
        CONNECT_TIMEOUT=2
    fi
    if [[ ! "$PROBE_TIMEOUT" =~ '^[0-9]{1,3}$' ]] || (( 10#$PROBE_TIMEOUT < 1 || 10#$PROBE_TIMEOUT > 120 )); then
        print -u2 -r -- '[Jobs Git] JOBS_GIT_PROBE_TIMEOUT 无效，使用 4 秒总探测。'
        PROBE_TIMEOUT=4
    fi
}
# curl 只探测脱敏站点根地址；空代理强制直连，HTTP 错误状态仍说明连接已建立。
curl_head_status() {
    local -a route_args=( --proxy "$1" )
    [[ -n "$1" ]] || route_args+=( --noproxy '*' )
    /usr/bin/curl --disable --silent --head --output /dev/null --write-out '%{http_code}' \
        --connect-timeout "$CONNECT_TIMEOUT" --max-time "$PROBE_TIMEOUT" --proto '=http,https' \
        "${route_args[@]}" "$TARGET_ROOT" 2>/dev/null
}
# 只有 DNS、初始连接或未收到 HTTP 响应的超时允许自动改走代理。
is_initial_connection_probe_failure() {
    case "$1" in
        6|7|28)
            return 0
            ;;
    esac
    return 1
}
# TLS / 证书故障不通过换代理掩盖，也不关闭证书验证。
is_tls_probe_failure() {
    case "$1" in
        35|51|58|59|60|64|66|77|80|82|83|90|91)
            return 0
            ;;
    esac
    return 1
}
# 选路后仅运行一次原始 Git；代理参数只存在于这个子进程。
execute_selected_command() {
    local mode="$1" proxy="${2:-}" command_result=0
    local -a proxy_args=()
    if [[ -n "$proxy" ]]; then
        proxy_args=( -c "http.${TARGET_ROOT}.proxy=${proxy}" )
        real_git "${GLOBAL_ARGS[@]}" "${proxy_args[@]}" "$NETWORK_COMMAND" "${COMMAND_ARGS[@]}"
    else
        real_git "${ORIGINAL_ARGS[@]}"
    fi
    command_result=$?
    audit_result "$mode" "$TARGET_HOST" "$TARGET_PORT" "$command_result"
    return "$command_result"
}
# 只选择首个可用系统代理；返回失败时仍未启动任何 Git 网络业务。
probe_first_reachable_proxy() {
    local index=0 http_status='' probe_result=0
    SELECTED_PROXY=''
    for (( index = 1; index <= ${#PROXY_URLS}; index++ )); do
        http_status="$(curl_head_status "${PROXY_URLS[index]}")"
        probe_result=$?
        audit_result proxy-probe "${PROXY_HOSTS[index]}" "${PROXY_PORTS[index]}" "$probe_result"
        if [[ "$http_status" =~ '^[1-5][0-9][0-9]$' && "$http_status" != 407 ]]; then
            print -u2 -r -- "[Jobs Git] 已选择系统代理 ${PROXY_HOSTS[index]}:${PROXY_PORTS[index]}，执行本次 ${NETWORK_COMMAND}。"
            SELECTED_PROXY="${PROXY_URLS[index]}"
            return 0
        fi
        if is_tls_probe_failure "$probe_result"; then
            print -u2 -r -- '[Jobs Git] 系统代理探测遇到 TLS / 证书差异，不继续换路；使用该代理交给原生 Git 校验其 CA / 客户端证书。'
            SELECTED_PROXY="${PROXY_URLS[index]}"
            return 0
        fi
    done
    return 1
}
# 两路短探测均失败时快速返回，不创建 clone 目录或执行未知远端写入。
report_network_unavailable() {
    print -u2 -r -- "[Jobs Git] ${TARGET_HOST}:${TARGET_PORT} 的直连与当前系统代理均不可达；请检查网络或 VPN，未执行 Git 网络命令。"
    audit_result network-unavailable "$TARGET_HOST" "$TARGET_PORT" 128
    return 128
}
# 直连已经失败后只探测一次代理候选，业务执行失败时不重新选择线路。
execute_with_first_reachable_proxy() {
    if probe_first_reachable_proxy; then
        execute_selected_command proxy "$SELECTED_PROXY"
        return $?
    fi
    report_network_unavailable
}
# 先探测直连，仅明确初始连接故障才动态读取系统代理。
execute_direct_first_policy() {
    local http_status='' probe_result=0 discovery_result=0
    http_status="$(curl_head_status '')"
    probe_result=$?
    audit_result direct-probe "$TARGET_HOST" "$TARGET_PORT" "$probe_result"
    if [[ "$http_status" =~ '^[1-5][0-9][0-9]$' ]]; then
        execute_selected_command direct
        return $?
    fi
    if ! is_initial_connection_probe_failure "$probe_result"; then
        print -u2 -r -- '[Jobs Git] 直连探测未显示可安全换路的初始连接故障，交给原生 Git 校验，保留其 TLS 与认证配置。'
        execute_selected_command skip-probe-error
        return $?
    fi
    discover_system_proxies
    discovery_result=$?
    if (( discovery_result != 0 )); then
        if (( discovery_result == 2 )); then
            print -u2 -r -- '[Jobs Git] 直连不可达且目标命中系统或 NO_PROXY 旁路规则，不自动代理；未执行 Git 网络命令。'
            audit_result skip-bypass "$TARGET_HOST" "$TARGET_PORT" 128
        else
            print -u2 -r -- "[Jobs Git] ${TARGET_HOST}:${TARGET_PORT} 直连不可达，且当前没有启用的系统代理；请检查网络或开启 VPN，未执行 Git 网络命令。"
            audit_result no-system-proxy "$TARGET_HOST" "$TARGET_PORT" 128
        fi
        return 128
    fi
    execute_with_first_reachable_proxy
}
# 优先探测当前系统代理；所有候选均不可用后只回退探测直连一次。
execute_system_first_policy() {
    local discovery_result=0 http_status='' probe_result=0
    discover_system_proxies
    discovery_result=$?
    if (( discovery_result == 0 )) && probe_first_reachable_proxy; then
        execute_selected_command proxy "$SELECTED_PROXY"
        return $?
    fi
    http_status="$(curl_head_status '')"
    probe_result=$?
    audit_result direct-probe "$TARGET_HOST" "$TARGET_PORT" "$probe_result"
    if [[ "$http_status" =~ '^[1-5][0-9][0-9]$' ]]; then
        execute_selected_command direct
        return $?
    fi
    if ! is_initial_connection_probe_failure "$probe_result"; then
        print -u2 -r -- '[Jobs Git] 直连探测未显示可安全换路的初始连接故障，交给原生 Git 校验，保留其 TLS 与认证配置。'
        execute_selected_command skip-probe-error
        return $?
    fi
    if (( discovery_result == 2 )); then
        print -u2 -r -- '[Jobs Git] 直连不可达且目标命中系统或 NO_PROXY 旁路规则，不自动代理；未执行 Git 网络命令。'
        audit_result skip-bypass "$TARGET_HOST" "$TARGET_PORT" 128
        return 128
    fi
    if (( discovery_result != 0 )); then
        print -u2 -r -- "[Jobs Git] ${TARGET_HOST}:${TARGET_PORT} 直连不可达，且当前没有启用的系统代理；请检查网络或开启 VPN，未执行 Git 网络命令。"
        audit_result no-system-proxy "$TARGET_HOST" "$TARGET_PORT" 128
        return 128
    fi
    report_network_unavailable
}
# 先尊重显式代理，再按已确认优先级短探测，原始业务最多执行一次。
execute_network_policy() {
    setopt NO_NOMATCH
    prepare_audit
    if has_explicit_proxy; then
        print -u2 -r -- '[Jobs Git] 已有显式代理或显式空代理，保留原配置，不自动选路。'
        execute_selected_command skip-explicit-proxy
        return $?
    fi
    configure_probe_timeouts
    if [[ "$ROUTE_PRIORITY" == system ]]; then
        execute_system_first_policy
    else
        execute_direct_first_policy
    fi
}
# 编排透明入口与运行前选路，业务 Git 命令最多执行一次。
main() {
    show_network_intro_and_route "$@" # 本地与未知形式原生透传，明确 HTTP(S) 目标展示运行策略。
    execute_network_policy # 短探测直连与当前系统代理，选定后仅执行一次原始命令。
}

main "$@"
