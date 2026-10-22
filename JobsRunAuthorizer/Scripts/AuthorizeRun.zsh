#!/bin/zsh
# 脚本自述：
# - 脚本名称：AuthorizeRun.zsh
# - 核心用途：给 Finder 选中的一个普通文件增加执行权限。
# - 影响范围：只执行 chmod +x；保持当前 umask，不修改文件内容，不运行目标。
# - 运行提示：先阅读内置自述，直接回车继续；任意非空输入取消，EOF 停止。
# shell: zsh

typeset TARGET_FILE='' RUN_MODE='' LOG_FILE='' RUN_DIRECTORY='' SELECTED_IDENTITY=''

# 按终端能力显示颜色，纯文本日志不包含 ANSI 转义。
display_message() {
    local role="$1" message="$2" style='0;34'
    case "$role" in
        title) style='1;31' ;;
        success) style='1;32' ;;
        error) style='1;31' ;;
        warning) style='1;33' ;;
    esac
    if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" ]]; then
        printf '\033[%sm%s\033[0m\n' "$style" "$message"
    else
        print -r -- "$message"
    fi
}
# 同步保存和显示本次会话的业务结果。
log_message() {
    local role="$1" message="$2"
    print -r -- "$message" >> "$LOG_FILE" || {
        print -u2 -r -- "✖ 日志写入失败：${(q)LOG_FILE}"
        exit 1
    }
    display_message "$role" "$message"
}
# 列出严格的单文件调用方式，帮助入口不创建日志。
show_usage() {
    print -r -- '用法：'
    print -r -- '  /bin/zsh AuthorizeRun.zsh --file <绝对路径>'
    print -r -- '  /bin/zsh AuthorizeRun.zsh --check --file <绝对路径>'
    print -r -- '  /bin/zsh AuthorizeRun.zsh --help'
    print -r -- '仅接受一个普通文件；目录、文件包、符号链接和多文件参数均拒绝。'
}
# 只接受明确的单文件或只读参数组合，不解析目标中的 Shell 文本。
parse_arguments() {
    if (( $# == 1 )) && [[ "$1" == --help ]]; then
        show_usage
        exit 0
    elif (( $# == 2 )) && [[ "$1" == --file ]]; then
        RUN_MODE=authorize
        TARGET_FILE="$2"
    elif (( $# == 3 )) && [[ "$1" == --check && "$2" == --file ]]; then
        RUN_MODE=check
        TARGET_FILE="$3"
    else
        print -u2 -r -- '✖ 参数无效：必须明确指定一个 --file <绝对路径>。'
        show_usage
        exit 64
    fi
}
# 校验当前对象并记录身份，确认期间被替换的目标不得继续授权。
validate_selected_file() {
    local identity=''
    if [[ "$TARGET_FILE" != /* || -L "$TARGET_FILE" || ! -f "$TARGET_FILE" ]]; then
        print -u2 -r -- "✖ 只支持一个普通文件的绝对路径：${(q)TARGET_FILE}"
        exit 65
    fi
    identity="$(/usr/bin/stat -f '%d:%i' "$TARGET_FILE" 2>/dev/null)" || {
        print -u2 -r -- "✖ 无法读取目标文件状态：${(q)TARGET_FILE}"
        exit 1
    }
    if [[ -n "$SELECTED_IDENTITY" && "$identity" != "$SELECTED_IDENTITY" ]]; then
        print -u2 -r -- '✖ 目标文件在确认期间已被替换，请重新选择后再试。'
        exit 1
    fi
    SELECTED_IDENTITY="$identity"
}
# 展示用途后分流只读入口，普通入口只在终端中接受空行确认。
show_script_intro_and_wait() {
    local answer=''
    display_message title 'JobsRunAuthorizer｜运行授权'
    display_message body '1、只给选中的一个普通文件增加执行权限（chmod +x），保持当前 umask。'
    display_message body '2、不修改文件内容，不执行目标文件。'
    display_message body '3、直接回车继续；任意非空输入或 Ctrl+C 取消，输入结束时停止。'
    display_message body '4、确认后才在 $TMPDIR（未设置时 /tmp）创建独立私有日志。'
    parse_arguments "$@"
    validate_selected_file
    display_message body "目标文件：${(q)TARGET_FILE}"
    if [[ "$RUN_MODE" == check ]]; then
        display_message body "✔ 只读检查通过；当前权限：$(/usr/bin/stat -f '%Lp' "$TARGET_FILE")；umask：$(umask)"
        exit 0
    fi
    if [[ ! -t 0 ]]; then
        print -u2 -r -- '✖ 请在可交互终端中运行；没有确认，不进行授权。'
        exit 1
    fi
    print -n -r -- '已了解用途，直接回车继续；任意字符取消：'
    if ! IFS= read -r answer; then
        print -r -- ''
        print -r -- '⚠ 输入已结束，停止授权。'
        exit 1
    fi
    if [[ -n "$answer" ]]; then
        print -r -- '⚠ 已取消授权。'
        exit 0
    fi
}
# 确认后建立每次独立的私有日志，创建时的 umask 只作用于子 Shell。
initialize_script_runtime() {
    local temporary_root="${TMPDIR:-/tmp}"
    setopt NO_NOMATCH PIPE_FAIL
    validate_selected_file
    [[ -d "$temporary_root" ]] || {
        print -u2 -r -- "✖ 临时目录不存在：${(q)temporary_root}"
        exit 1
    }
    RUN_DIRECTORY="$(/usr/bin/mktemp -d "${temporary_root%/}/JobsRunAuthorizer.XXXXXXXX")" || {
        print -u2 -r -- '✖ 无法建立本次私有日志目录，停止授权。'
        exit 1
    }
    LOG_FILE="$RUN_DIRECTORY/run.log"
    (umask 077; : > "$LOG_FILE") || {
        print -u2 -r -- "✖ 无法创建日志：${(q)LOG_FILE}"
        /bin/rmdir "$RUN_DIRECTORY" 2>/dev/null
        exit 1
    }
    log_message body "ℹ 日志：${(q)LOG_FILE}"
    log_message body "ℹ 目标：${(q)TARGET_FILE}"
}
# 保留原工具的 chmod +x 语义，并把真实失败状态返回给启动方。
authorize_selected_file() {
    local before_mode='' after_mode='' command_output='' command_result=0
    validate_selected_file
    before_mode="$(/usr/bin/stat -f '%Lp' "$TARGET_FILE")" || exit 1
    command_output="$(/bin/chmod +x "$TARGET_FILE" 2>&1)"
    command_result=$?
    if (( command_result != 0 )); then
        log_message error "✖ chmod +x 失败（退出码 $command_result）：${(q)TARGET_FILE}"
        [[ -z "$command_output" ]] || log_message error "$command_output"
        exit "$command_result"
    fi
    after_mode="$(/usr/bin/stat -f '%Lp' "$TARGET_FILE")" || {
        log_message error '✖ chmod +x 已返回成功，但无法读取授权后的文件状态。'
        exit 1
    }
    log_message success "✔ chmod +x 成功；文件权限：$before_mode → $after_mode"
}
# 编排自述确认、私有日志和单文件授权。
main() {
    show_script_intro_and_wait "$@" # 先展示内置自述，只读分流并完成空行确认。
    initialize_script_runtime # 确认目标身份后创建本次独立私有日志。
    authorize_selected_file # 仅修改目标文件执行位并保留失败退出码。
}

main "$@"
