#!/bin/zsh
# 脚本自述：
# - 脚本名称：ManageExtension.zsh（App 内部后台管理器）
# - 核心用途：一个入口管理本功能的安装 / 更新、卸载与构建产物清理。
# - 影响范围：当前用户 Finder 菜单、对应构建产物与专用功能配置；保留源码和业务数据。
# - 运行提示：直接打开 GUI，在面板选择安装 / 更新或卸载；底部实时日志允许复制。
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

MANAGER_ACTION=""
MANAGER_STOP_REQUEST_FILE="${JOBS_FINDER_STOP_REQUEST_FILE:-}"
MANAGER_NON_INTERACTIVE=0
MANAGER_SKIP_RESTART=0
MANAGER_REQUESTED_FEATURES=""
MANAGER_ENTRY_DIR=""
MANAGER_GUI_SESSION=0
MANAGER_GUI_LEAF_FEATURES=""
MANAGER_UI_SCOPE="android-simulator-create"
# 支持上级面板在完成确认后调用；显式参数不会改变本目录的功能边界。
manager_parse_options() {
  local install_location="${JOBS_FINDER_INSTALL_LOCATION:-build}" cleanup_build_products="${JOBS_FINDER_CLEANUP_BUILD_PRODUCTS:-0}"
  MANAGER_ENTRY_DIR="${ZSH_ARGZERO:A:h:h}"
  while (( $# > 0 )); do
    case "$1" in
      --action) (( $# >= 2 )) || return 2; MANAGER_ACTION="$2"; shift ;;
      --action=*) MANAGER_ACTION="${1#--action=}" ;;
      --install-location) (( $# >= 2 )) || return 2; install_location="$2"; shift ;;
      --install-location=*) install_location="${1#--install-location=}" ;;
      --cleanup-build-products) cleanup_build_products=1 ;;
      --stop-request-file) (( $# >= 2 )) && [[ "$2" == /* ]] || return 2; MANAGER_STOP_REQUEST_FILE="$2"; shift ;;
      --stop-request-file=*) MANAGER_STOP_REQUEST_FILE="${1#--stop-request-file=}"; [[ "$MANAGER_STOP_REQUEST_FILE" == /* ]] || return 2 ;;
      --non-interactive) MANAGER_NON_INTERACTIVE=1 ;;
      --gui-session) MANAGER_GUI_SESSION=1 ;;
      --skip-finder-restart) MANAGER_SKIP_RESTART=1 ;;
      --scope|--features) (( $# >= 2 )) || return 2; MANAGER_REQUESTED_FEATURES="$2"; shift ;;
      --features=*) MANAGER_REQUESTED_FEATURES="${1#--features=}" ;;
      --help|-h) print '用法：双击管理，或 --action install|uninstall|cleanup --non-interactive [--features 功能ID,...] [--skip-finder-restart] [--install-location build|applications] [--cleanup-build-products] [--stop-request-file PATH]'; return 10 ;;
      *) print -u2 -r -- "✖ 未知参数：$1"; return 2 ;;
    esac
    shift
  done
  [[ "$install_location" == build || "$install_location" == applications ]] || { print -u2 "✖ 安装位置必须是 build 或 applications。"; return 2; }
  [[ "$cleanup_build_products" == 0 || "$cleanup_build_products" == 1 ]] || { print -u2 '✖ 构建产物清理开关必须是 0 或 1。'; return 2; }
  if [[ "$cleanup_build_products" == 1 && ( "$install_location" != applications || "${MANAGER_ACTION:-install}" != install ) ]]; then
    print -u2 '✖ 仅安装到应用程序目录时允许清除此轮构建产物。'
    return 2
  fi
  [[ "$MANAGER_ACTION" != cleanup || "$install_location" == applications ]] || { print -u2 '✖ 独立清理仅允许应用程序目录模式。'; return 2; }
  [[ -z "$MANAGER_STOP_REQUEST_FILE" || "$MANAGER_STOP_REQUEST_FILE" == /* ]] || { print -u2 '✖ 停止请求文件必须使用绝对路径。'; return 2; }
  export JOBS_FINDER_STOP_REQUEST_FILE="$MANAGER_STOP_REQUEST_FILE"
  export JOBS_FINDER_CLEANUP_BUILD_PRODUCTS="$cleanup_build_products"
  export JOBS_FINDER_INSTALL_LOCATION="$install_location"
  manager_prepare_gui_features || return $?
  [[ -z "$MANAGER_ACTION" || "$MANAGER_ACTION" == install || "$MANAGER_ACTION" == uninstall || "$MANAGER_ACTION" == cleanup ]] || return 2
  (( ! MANAGER_NON_INTERACTIVE )) || [[ -n "$MANAGER_ACTION" ]] || { print -u2 '✖ 非交互调用必须明确 --action。'; return 2; }
}
# 不支持颜色时保留纯文本自述，确认前不创建日志或修改系统。
manager_intro_line() {
  local role="$1" message="$2" code='0;34'
  [[ "$role" != title ]] || code='1;31'
  if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" ]]; then
    /usr/bin/printf '\033[%sm%s\033[0m\n' "$code" "$message"
  else
    print -r -- "$message"
  fi
}
# 上级批量操作只刷新一次 Finder。
manager_restart_finder() {
  (( MANAGER_SKIP_RESTART )) && return 0
  /usr/bin/killall Finder "$@"
}
# 按原有功能白名单把 GUI 叶标识转换为包内动作，事件仍使用原 GUI 标识。
manager_prepare_gui_features() {
  local feature="" mapped="" prepared=() allowed=("${(@s:,:)MANAGER_UI_SCOPE}")
  MANAGER_GUI_LEAF_FEATURES="$MANAGER_REQUESTED_FEATURES"
  [[ -n "$MANAGER_REQUESTED_FEATURES" ]] || { MANAGER_GUI_LEAF_FEATURES="$MANAGER_UI_SCOPE"; return 0; }
  [[ "$MANAGER_REQUESTED_FEATURES" != ,* && "$MANAGER_REQUESTED_FEATURES" != *, && "$MANAGER_REQUESTED_FEATURES" != *,,* ]] || return 2
  for feature in ${(s:,:)MANAGER_REQUESTED_FEATURES}; do
    mapped="$feature"
    case "${MANAGER_ENTRY_DIR:t}" in
      JobsFlutter*)
        if (( ${allowed[(Ie)$feature]} )); then
          mapped="${feature#flutter-}"
        fi
        ;;
      JobsTerminalOpener)
        case "$feature" in
          terminal_open) mapped=open ;;
          file_content) mapped=file-content ;;
          file_merge) mapped=file-merge ;;
          file_split) mapped=file-split ;;
          clean_build_artifacts) mapped=clean-build-artifacts ;;
          codegraph_bootstrap) mapped=codegraph-bootstrap ;;
        esac
        ;;
      JobsIOSTools) [[ "$feature" != pod_install ]] || mapped=ios-pod-install ;;
    esac
    if [[ "$MANAGER_ACTION" == cleanup ]]; then
      local cleanup_identifier="$(manager_gui_identifier "$mapped")"
      (( ${allowed[(Ie)$cleanup_identifier]} )) || { print -u2 -r -- "✖ 功能不属于本入口：$feature"; return 2; }
    fi
    prepared+=("$mapped")
  done
  MANAGER_REQUESTED_FEATURES="${(j:,:)prepared}"
}
# 兼容命令行包内动作，同时把 GUI 范围和状态统一为选择器叶 ID。
manager_gui_identifier() {
  local identifier="$1"
  case "${MANAGER_ENTRY_DIR:t}" in
    JobsFlutter*) [[ "$identifier" == flutter-* ]] || identifier="flutter-$identifier" ;;
    JobsTerminalOpener)
      case "$identifier" in
        open) identifier=terminal_open ;;
        file-content) identifier=file_content ;;
        file-merge) identifier=file_merge ;;
        file-split) identifier=file_split ;;
        clean-build-artifacts) identifier=clean_build_artifacts ;;
        codegraph-bootstrap) identifier=codegraph_bootstrap ;;
      esac
      ;;
    JobsIOSTools) [[ "$identifier" != ios-pod-install ]] || identifier=pod_install ;;
  esac
  print -nr -- "$identifier"
}
# 完整仓转交总管理器的受限范围，独立包使用随包源码且仍能整体复制。
manager_open_gui() {
  local -x JOBS_FINDER_STOP_REQUEST_FILE=""
  local entry="${MANAGER_ENTRY_DIR:h}/Scripts/ManageFinderExtensions.zsh" helper="$MANAGER_ENTRY_DIR/Scripts/FinderManagerGUI.zsh"
  local scope="$MANAGER_UI_SCOPE" identifier="" feature="" selected=() allowed=("${(@s:,:)MANAGER_UI_SCOPE}")
  if [[ -n "$MANAGER_REQUESTED_FEATURES" ]]; then
    for feature in ${(s:,:)MANAGER_REQUESTED_FEATURES}; do
      identifier="$(manager_gui_identifier "$feature")"
      (( ${allowed[(Ie)$identifier]} )) || { print -u2 -r -- "✖ 功能不属于本入口：$feature"; return 2; }
      selected+=("$identifier")
    done
    scope="${(j:,:)selected}"
  fi
  if [[ -f "$entry" ]]; then
    local arguments=(--scope "$scope" --action "${MANAGER_ACTION:-install}" --install-location "$JOBS_FINDER_INSTALL_LOCATION")
    [[ "${JOBS_FINDER_CLEANUP_BUILD_PRODUCTS:-0}" != 1 ]] || arguments+=(--cleanup-build-products)
    (( ! MANAGER_GUI_SESSION )) || arguments+=(--gui-session)
    exec /bin/zsh "$entry" "${arguments[@]}"
  fi
  if [[ ! -f "$helper" ]]; then
    /usr/bin/osascript -e 'display alert "缺少管理面板" message "请保留包含统一功能包的完整 MacOS@Extension 目录。" as critical'
    return 1
  fi
  source "$helper" || return 1
  jobs_launch_finder_manager_gui "${ZSH_ARGZERO:A}" "$scope" "${MANAGER_ACTION:-install}" "$MANAGER_GUI_SESSION"
}
# 后台操作的用途和副作用进入面板日志，不再读取终端输入。
manager_choose_action() {
  manager_intro_line title "━━━━━━━━━━ ${ZSH_ARGZERO:t} ━━━━━━━━━━"
  manager_intro_line body "来源：${MANAGER_ENTRY_DIR}；仅管理当前范围内的 Finder 功能。"
  manager_intro_line body '安装构建并启用菜单；卸载保留未选菜单；清理只删除已安装 App 对应构建产物。'
  return 0
}
# 逐叶回传真实运行状态；不使用无法核实的百分比。
manager_emit_progress() {
  local state="$1" feature="" message="" identifier=""
  case "$state" in
    running)
      case "$MANAGER_ACTION" in
        uninstall) message='正在卸载' ;;
        cleanup) message='正在清理构建产物' ;;
        *) message='正在安装 / 更新' ;;
      esac
      ;;
    succeeded) message='成功' ;;
    failed) message='失败，请查看下方日志' ;;
  esac
  for feature in ${(s:,:)MANAGER_GUI_LEAF_FEATURES}; do
    identifier="$feature"
    case "${MANAGER_ENTRY_DIR:t}" in
      JobsFlutter*) [[ "$identifier" == flutter-* ]] || identifier="flutter-$identifier" ;;
      JobsTerminalOpener)
        case "$identifier" in
          open) identifier=terminal_open ;;
          file-content) identifier=file_content ;;
          file-merge) identifier=file_merge ;;
          file-split) identifier=file_split ;;
          clean-build-artifacts) identifier=clean_build_artifacts ;;
          codegraph-bootstrap) identifier=codegraph_bootstrap ;;
        esac
        ;;
      JobsIOSTools) [[ "$identifier" != ios-pod-install ]] || identifier=pod_install ;;
    esac
    /usr/bin/printf '\nJOBS_MANAGER_EVENT\t%s\t%s\t%s\n' "$identifier" "$state" "$message"
  done
}
# 操作选择即最终确认，分支直接执行对应业务。
manager_main() {
  local manager_status=0
  setopt NO_NOMATCH
  manager_parse_options "$@" || { manager_status=$?; (( manager_status == 10 )) && return 0; return "$manager_status"; }
  if (( ! MANAGER_NON_INTERACTIVE )); then
    manager_open_gui
    return $?
  fi
  manager_choose_action || return $?
  manager_emit_progress running
  manager_execute_operation
  manager_status=$?
  if (( manager_status == 0 )); then
    manager_emit_progress succeeded
  else
    manager_emit_progress failed
  fi
  return "$manager_status"
}
# 校验与业务复用原分支；任何失败保留真实退出码。
manager_execute_operation() {
  if [[ "$MANAGER_ACTION" == cleanup ]]; then
    run_cleanup_operation
    return $?
  fi
  if [[ "$MANAGER_ACTION" == install ]]; then
    run_install_operation
  else
    run_uninstall_operation
  fi
}

# 只把本目录白名单中的叶功能交给统一包，保留其它已安装菜单。
run_feature_operation() {
  local operation="$1" manager="${MANAGER_ENTRY_DIR:h}/JobsDesktopTools/Scripts/ManageDesktopTools.zsh" feature=""
  local allowed=(android-simulator-create) requested=() extra=()
  [[ -f "$manager" ]] || { print -u2 '✖ 请保留包含 JobsDesktopTools 的完整 MacOS@Extension 目录。'; return 1; }
  if [[ -n "$MANAGER_REQUESTED_FEATURES" ]]; then
    requested=("${(@s:,:)MANAGER_REQUESTED_FEATURES}")
    for feature in "${requested[@]}"; do
      (( ${allowed[(Ie)$feature]} )) || { print -u2 -r -- "✖ 功能不属于本入口：$feature"; return 2; }
    done
  else
    requested=("${allowed[@]}")
  fi
  extra+=(--non-interactive)
  (( ! MANAGER_SKIP_RESTART )) || extra+=(--skip-finder-restart)
  [[ "${JOBS_FINDER_CLEANUP_BUILD_PRODUCTS:-0}" != 1 ]] || extra+=(--cleanup-build-products)
  [[ -z "$MANAGER_STOP_REQUEST_FILE" ]] || extra+=(--stop-request-file "$MANAGER_STOP_REQUEST_FILE")
  JOBS_SKIP_FINDER_RESTART="$MANAGER_SKIP_RESTART" /bin/zsh "$manager" "$operation" "${requested[@]}" "${extra[@]}"
}
run_install_operation() {
  run_feature_operation install
}
# 独立清理沿用所属宿主和功能白名单，不运行安装或卸载。
run_cleanup_operation() {
  run_feature_operation cleanup
}
run_uninstall_operation() {
  run_feature_operation uninstall
}

manager_main "$@"
