#!/bin/zsh -f
# 脚本自述：
# - 脚本名称：【MacOS】自检具体的某个本地pod是否能编译通过.command
# - 核心用途：执行“自检具体的某个本地pod是否能编译通过”对应的移动端项目自动化任务。
# - 影响范围：可能修改项目依赖、生成文件、构建产物或开发工具配置。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。


# ==============================================================================
# 本地 Pod 编译自检工具
# - 独立 .command 文件，双击后直接运行完整流程
# - 内置 x.command 等待文案修复能力：按回车继续执行 x... -> 按回车继续执行 ...
# - 禁止使用 zsh 特殊变量名 path，避免破坏 PATH
# - 使用 zsh -f 启动，并在输入读取/变量清洗块内同时屏蔽 stdout/stderr trace，避免内部变量打印出来
# - 区分“源码编译失败”和“podspec lint 校验失败”，避免 BUILD SUCCEEDED 被误报为编译失败
# - 默认只把目标 Pod 真实依赖到的本地 podspec 传给 --include-podspecs，缺依赖时再自动全量重试
# - 记住上一次输入的本地 Pod 根目录，下次回车直接沿用
# - 单次自检结束后不关闭窗口，回车进入下一个 Pod 的自检流程
# - 开启 typeset_silent，避免 zsh 在重复 local 声明空变量时把 raw/input 等内部变量打印到终端
# ==============================================================================


# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
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
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
SCRIPT_BASENAME="$(basename -- "$0" | /usr/bin/sed 's/\.[^.]*$//')"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
CACHE_DIR="${HOME}/.jobscommand/cache"
WORKSPACE_ROOT_CACHE_FILE="${CACHE_DIR}/local_pod_lint_workspace_root.txt"
# 按当前输出级别记录终端信息，并同步写入脚本日志。
log()            { /usr/bin/printf "%b\n" "$1" | /usr/bin/tee -a "$LOG_FILE" >/dev/null; /usr/bin/printf "%b\n" "$1"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
color_echo()     { log "\033[1;32m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warm_echo()      { log "\033[1;33m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
gray_echo()      { log "\033[0;90m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
bold_echo()      { log "\033[1m$1\033[0m"; }
# 封装 close_trace_noise 对应的独立处理逻辑。
close_trace_noise() {
    # 防止 .zshenv、外层执行器或旧脚本残留 xtrace/verbose，导致内部变量泄漏到终端。
    # 注意：有些本机环境会把 xtrace 打到 stdout，而不是 stderr，所以这里必须同时吞掉 stdout/stderr。
    {
        set +x 2>/dev/null || true
        set +v 2>/dev/null || true
        unsetopt xtrace 2>/dev/null || true
        unsetopt verbose 2>/dev/null || true
        setopt typeset_silent 2>/dev/null || true
        unset XTRACEFD BASH_XTRACEFD 2>/dev/null || true
        trap - DEBUG 2>/dev/null || true
        unfunction TRAPDEBUG 2>/dev/null || true
        PS4=''
    } >/dev/null 2>&1
}
# 封装 silent_input_guard 对应的独立处理逻辑。
silent_input_guard() {
    # 任何读取用户输入、清洗路径、变量赋值的区域都用这个模式包住：
    #   { ... } >/dev/null 2>&1
    # 这样即便 xtrace 被系统环境重新打开，也不会把内部变量打到终端。
    close_trace_noise >/dev/null 2>&1
}
# 封装 print_divider 对应的独立处理逻辑。
print_divider() {
    gray_echo "------------------------------------------------------------------------"
}
# 封装 pause_for_enter 对应的独立处理逻辑。
pause_for_enter() {
    { close_trace_noise; } >/dev/null 2>&1
    local prompt_text="${1:-👉 请按回车继续，或按 Ctrl+C 取消...}"
    echo ""
    /usr/bin/printf "%s" "${prompt_text}"
    {
        local ignored_input
        IFS= read -r ignored_input
        silent_input_guard
    } >/dev/null 2>&1
    silent_input_guard
}
# 封装 trim_string 对应的独立处理逻辑。
trim_string() {
    local input_value="$1"
    input_value="${input_value#"${input_value%%[![:space:]]*}"}"
    input_value="${input_value%"${input_value##*[![:space:]]}"}"
    print -r -- "$input_value"
}
# 封装 normalize_input_dir 对应的独立处理逻辑。
normalize_input_dir() {
    local input_value="$1"
    local output_value
    output_value="$(trim_string "$input_value")"

    # 兼容 Finder 拖拽路径、外层引号、反斜杠转义
    output_value="${(Q)output_value}"

    if [[ "$output_value" == "~" ]]; then
        output_value="$HOME"
    elif [[ "$output_value" == "~/"* ]]; then
        output_value="${HOME}/${output_value#\~/}"
    fi

    print -r -- "$output_value"
}
# 封装 normalize_input_dir_to_global 对应的独立处理逻辑。
normalize_input_dir_to_global() {
    local input_value="$1"
    local output_value="$input_value"

    output_value="${output_value#"${output_value%%[![:space:]]*}"}"
    output_value="${output_value%"${output_value##*[![:space:]]}"}"

    # 兼容 Finder 拖拽路径、外层引号、反斜杠转义
    output_value="${(Q)output_value}"

    if [[ "$output_value" == "~" ]]; then
        output_value="$HOME"
    elif [[ "$output_value" == "~/"* ]]; then
        output_value="${HOME}/${output_value#\~/}"
    fi

    __NORMALIZED_INPUT_DIR="$output_value"
}
# 封装 trim_string_to_global 对应的独立处理逻辑。
trim_string_to_global() {
    local input_value="$1"
    input_value="${input_value#"${input_value%%[![:space:]]*}"}"
    input_value="${input_value%"${input_value##*[![:space:]]}"}"
    __TRIMMED_INPUT_VALUE="$input_value"
}
# 封装 load_workspace_root_cache 对应的独立处理逻辑。
load_workspace_root_cache() {
    [[ -f "$WORKSPACE_ROOT_CACHE_FILE" ]] || return 0

    local cached_value
    cached_value="$(/usr/bin/head -n 1 "$WORKSPACE_ROOT_CACHE_FILE" 2>/dev/null)"
    [[ -n "$cached_value" ]] || return 0

    local __NORMALIZED_INPUT_DIR
    normalize_input_dir_to_global "$cached_value"
    print -r -- "$__NORMALIZED_INPUT_DIR"
}
# 封装 save_workspace_root_cache 对应的独立处理逻辑。
save_workspace_root_cache() {
    local workspace_root_value="$1"
    [[ -n "$workspace_root_value" ]] || return 1

    /bin/mkdir -p "$CACHE_DIR" 2>/dev/null || return 1
    /usr/bin/printf "%s\n" "$workspace_root_value" > "$WORKSPACE_ROOT_CACHE_FILE"
}
# 执行已经拆分完成的独立业务步骤。
run_cmd_stream() {
    local desc="$1"
    shift

    note_echo "$desc"
    debug_echo "执行命令：$*"

    "$@" 2>&1 | /usr/bin/tee -a "$LOG_FILE"
    local exit_code=${pipestatus[1]}

    if [[ $exit_code -eq 0 ]]; then
        success_echo "${desc}：完成"
    else
        error_echo "${desc}：失败（exit code: ${exit_code}）"
    fi

    return $exit_code
}
# 执行已经拆分完成的独立业务步骤。
run_cmd_stream_to_file() {
    local desc="$1"
    local capture_file="$2"
    shift 2

    note_echo "$desc"
    debug_echo "执行命令：$*"
    : > "$capture_file"

    "$@" 2>&1 | /usr/bin/tee -a "$LOG_FILE" | /usr/bin/tee -a "$capture_file"
    local exit_code=${pipestatus[1]}

    if [[ $exit_code -eq 0 ]]; then
        success_echo "${desc}：完成"
    else
        error_echo "${desc}：失败（exit code: ${exit_code}）"
    fi

    return $exit_code
}
# 封装 lint_output_contains 对应的独立处理逻辑。
lint_output_contains() {
    local output_file="$1"
    local fixed_text="$2"
    /usr/bin/grep -Fq -- "$fixed_text" "$output_file" 2>/dev/null
}
# 封装 lint_output_matches 对应的独立处理逻辑。
lint_output_matches() {
    local output_file="$1"
    local regex_text="$2"
    /usr/bin/grep -Eq -- "$regex_text" "$output_file" 2>/dev/null
}
# 封装 print_lint_error_summary 对应的独立处理逻辑。
print_lint_error_summary() {
    local output_file="$1"
    local summary_text

    summary_text="$(/usr/bin/grep -E "^[[:space:]]*- ERROR[[:space:]]*\\||^\\[!\\]|[[:space:]]error:|fatal error:" "$output_file" 2>/dev/null | /usr/bin/sed -n '1,30p')"

    if [[ -n "$summary_text" ]]; then
        warn_echo "lint 关键错误摘要："
        while IFS= read -r summary_line; do
            [[ -n "$summary_line" ]] || continue
            warm_echo "• ${summary_line}"
        done <<< "$summary_text"
    else
        warn_echo "未提取到明确 ERROR 摘要，请查看完整日志：${LOG_FILE}"
    fi
}
# 封装 print_lint_failure_advice 对应的独立处理逻辑。
print_lint_failure_advice() {
    local output_file="$1"

    if lint_output_matches "$output_file" 'file patterns: The `[^`]+` pattern did not match any file'; then
        warn_echo "诊断：podspec 文件匹配规则有空匹配。"
        gray_echo "• 常见原因：source_files/public_header_files/resources 写了通用模板，但实际目录里没有对应文件。"
        gray_echo "• 处理方式：没有这类文件就删掉对应配置；有文件就修正 glob，让它能匹配到真实文件。"
    fi

    if lint_output_matches "$output_file" 'Unable to find a specification for|None of your spec sources contain a spec satisfying'; then
        warn_echo "诊断：依赖解析失败。"
        gray_echo "• 如果依赖是本地兄弟 Pod，请确认目标 podspec 里有明确的 s.dependency/ss.dependency。"
        gray_echo "• 如果依赖来自远端源，请确认 CocoaPods repo/source 可访问，或者在 podspec 中补齐 source。"
    fi

    if lint_output_matches "$output_file" 'Missing primary key for `source` attribute|There was a problem validating the URL'; then
        warn_echo "诊断：podspec 元信息不完整或 URL 不可校验。"
        gray_echo "• private lint 通常能容忍 warning，但如果你的环境把 warning 当失败，需要补齐 source/homepage/license 等字段。"
    fi
}
# 封装 glob_has_match 对应的独立处理逻辑。
glob_has_match() {
    local pattern_text="$1"

    if [[ "$pattern_text" == *'#{'* || "$pattern_text" == *'$'* ]]; then
        return 2
    fi

    if command -v ruby >/dev/null 2>&1; then
        ruby -e 'pattern = ARGV[0]; exit(Dir.glob(pattern).empty? ? 1 : 0)' "$pattern_text" >/dev/null 2>&1
        return $?
    fi

    local -a matched_files
    matched_files=( ${~pattern_text}(N) )
    (( ${#matched_files[@]} > 0 ))
}
# 封装 preflight_resource_patterns 对应的独立处理逻辑。
preflight_resource_patterns() {
    local spec_file="$1"
    local spec_dir
    spec_dir="$(dirname -- "$spec_file")"

    [[ -f "$spec_file" ]] || return 0

    local old_pwd="$PWD"
    local line_text
    local line_no=0
    local issue_count=0
    local -a checked_attrs
    checked_attrs=(source_files public_header_files private_header_files resources vendored_frameworks vendored_libraries)

    cd "$spec_dir" || return 0

    while IFS= read -r line_text; do
        ((line_no++))
        [[ "$line_text" == *"="* ]] || continue
        [[ "$line_text" =~ '^[[:space:]]*#' ]] && continue

        local attr_name
        local should_check=""
        for attr_name in "${checked_attrs[@]}"; do
            if [[ "$line_text" == *".${attr_name}"* ]]; then
                should_check="$attr_name"
                break
            fi
        done
        [[ -n "$should_check" ]] || continue

        # 覆盖最常见 podspec 写法：ss.resources = 'Core/**/*.{png,json,...}'
        # 多行数组、resource_bundles Hash 或复杂 Ruby 表达式仍交给 pod lib lint 原生输出判断。
        local patterns_text
        patterns_text="$(print -r -- "$line_text" | /usr/bin/awk -F"'" '{for (i=2; i<=NF; i+=2) print $i}')"
        [[ -n "$patterns_text" ]] || continue

        local pattern_text
        while IFS= read -r pattern_text; do
            [[ -n "$pattern_text" ]] || continue
            glob_has_match "$pattern_text"
            local match_code=$?
            [[ $match_code -eq 2 ]] && continue
            if [[ $match_code -ne 0 ]]; then
                if (( issue_count == 0 )); then
                    warn_echo "podspec 预检发现文件模式空匹配。"
                fi
                ((issue_count++))
                warm_echo "• $(relative_to_root "$WORKSPACE_ROOT" "$spec_file"):${line_no}（${should_check}）"
                gray_echo "  ${pattern_text}"
            fi
        done <<< "$patterns_text"
    done < "$spec_file"

    cd "$old_pwd" || true

    if (( issue_count > 0 )); then
        warm_echo "这类问题会让 pod lib lint 返回失败，但不等于源码编译失败。"
        gray_echo "没有对应文件时，建议删除这条配置；有对应文件时，修正 glob 让它能匹配到真实文件。"
        echo ""
    fi

    return 0
}
# 封装 relative_to_root 对应的独立处理逻辑。
relative_to_root() {
    local root_dir="$1"
    local item_file="$2"
    print -r -- "${item_file#$root_dir/}"
}
# 封装 unique_existing_files 对应的独立处理逻辑。
unique_existing_files() {
    local -a raw_files=("$@")
    local -a unique_files=()
    local candidate_file

    for candidate_file in "${raw_files[@]}"; do
        [[ -f "$candidate_file" ]] || continue
        if (( ${unique_files[(Ie)$candidate_file]} == 0 )); then
            unique_files+=("$candidate_file")
        fi
    done

    print -r -- "${(pj:\n:)unique_files}"
}
# 解析并返回后续流程需要的目标信息。
find_x_command_candidates() {
    # Finder 载体不维护其它脚本仓库。
    [[ -n "${JOBS_IOS_PROJECT_DIR:-}" ]] && return 0
    local -a candidate_files=()
    local cursor_dir="$SCRIPT_DIR"
    local index=0

    # 从当前脚本目录开始向上找 Scripts/x.command/x.command。
    while [[ -n "$cursor_dir" && "$cursor_dir" != "/" && $index -lt 8 ]]; do
        candidate_files+=("${cursor_dir}/Scripts/x.command/x.command")
        candidate_files+=("${cursor_dir}/x.command/x.command")
        candidate_files+=("${cursor_dir}/x.command")
        cursor_dir="$(dirname -- "$cursor_dir")"
        ((index++))
    done

    # 兼容你常见的 JobsCommand@iOS 工程结构。
    candidate_files+=("${SCRIPT_DIR}/../../Scripts/x.command/x.command")
    candidate_files+=("${SCRIPT_DIR}/../Scripts/x.command/x.command")

    unique_existing_files "${candidate_files[@]}"
}
# 封装 repair_one_x_command_file 对应的独立处理逻辑。
repair_one_x_command_file() {
    local target_file="$1"

    [[ -f "$target_file" ]] || return 1

    local temp_file
    temp_file="$(/usr/bin/mktemp "/tmp/x_command_patch.XXXXXX")" || return 1
    /bin/cp "$target_file" "$temp_file" || return 1

    /usr/bin/perl -0pi -e 's/按回车继续执行\s*x\.\.\./按回车继续执行 .../g; s/按回车继续执行\s*\$\{[^}]+\}\.\.\./按回车继续执行 .../g; s/按回车继续执行\s*\$[A-Za-z_][A-Za-z0-9_]*\.\.\./按回车继续执行 .../g' "$temp_file"

    if /usr/bin/cmp -s "$target_file" "$temp_file"; then
        /bin/rm -f "$temp_file"
        return 2
    fi

    local backup_file
    backup_file="${target_file}.bak.$(/bin/date +%Y%m%d%H%M%S)"
    /bin/cp "$target_file" "$backup_file" || {
        /bin/rm -f "$temp_file"
        return 1
    }

    /bin/cp "$temp_file" "$target_file" || {
        /bin/rm -f "$temp_file"
        return 1
    }

    /bin/rm -f "$temp_file"
    success_echo "已修复 x.command 等待文案：${target_file}"
    gray_echo "备份文件：${backup_file}"
    return 0
}
# 封装 repair_x_command_wait_prompt_if_possible 对应的独立处理逻辑。
repair_x_command_wait_prompt_if_possible() {
    local candidates_text
    candidates_text="$(find_x_command_candidates)"

    if [[ -z "$candidates_text" ]]; then
        info_echo "未发现 x.command 执行器，跳过等待文案修复。"
        return 0
    fi

    local changed_count=0
    local checked_count=0
    local candidate_file

    while IFS= read -r candidate_file; do
        [[ -n "$candidate_file" ]] || continue
        ((checked_count++))
        repair_one_x_command_file "$candidate_file"
        local repair_code=$?
        if [[ $repair_code -eq 0 ]]; then
            ((changed_count++))
        fi
    done <<< "$candidates_text"

    if (( changed_count == 0 )); then
        info_echo "已检查 x.command 等待文案，无需修复。"
    fi

    return 0
}
# 展示脚本用途和影响范围，并在执行前等待用户确认。
show_readme_and_block() {
    clear 2>/dev/null || true
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：【MacOS】自检具体的某个本地pod是否能编译通过.command' | jobs_intro_style title
  print -r -- '核心用途：执行“自检具体的某个本地pod是否能编译通过”对应的自动化任务。' | jobs_intro_style body
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title

    echo "" | jobs_intro_style body
    bold_echo "====================== 本地 Pod 编译自检工具 ======================" | jobs_intro_style title
    echo "" | jobs_intro_style body

    info_echo "用途：检查某个本地 CocoaPods Pod 是否能在自己的 podspec 环境下独立编译通过。" | jobs_intro_style body
    info_echo "执行方式：直接双击本 .command 文件运行；不需要额外输入 pd。" | jobs_intro_style body
    echo "" | jobs_intro_style body

    highlight_echo "本工具会执行以下流程：" | jobs_intro_style title
    gray_echo "1. 自动检查并修复 x.command 等待文案：按回车继续执行 ..." | jobs_intro_style body
    gray_echo "2. 打印本自述，并等待你按回车继续" | jobs_intro_style body
    gray_echo "3. 自检 pod 命令是否存在" | jobs_intro_style body
    gray_echo "4. 如果 pod 不存在，则执行：sudo gem install cocoapods" | jobs_intro_style body
    gray_echo "5. 如果 pod 已存在，则询问是否升级 CocoaPods：回车跳过，输入任意字符后回车执行升级" | jobs_intro_style body
    gray_echo "6. 询问本地 Pod 根目录（会记住上次输入；下次回车直接沿用）" | jobs_intro_style body
    gray_echo "7. 询问需要自检的目标 Pod 名" | jobs_intro_style body
    gray_echo "8. 智能分析目标 Pod 依赖，只收集真实依赖到的本地 podspec" | jobs_intro_style body
    gray_echo "9. 执行 pod lib lint，并区分源码编译结果与 podspec 校验结果" | jobs_intro_style body
    gray_echo "10. 如果智能依赖解析仍缺本地依赖，自动切换全量兼容模式重试一次" | jobs_intro_style body
    gray_echo "11. 单个 Pod 自检结束后不关闭窗口，可直接进入下一个 Pod 的自检流程" | jobs_intro_style body
    echo "" | jobs_intro_style body

    warn_echo "x.command 文案说明：" | jobs_intro_style title
    gray_echo "• 如果本工具是被旧 x.command 外层执行器启动的，外层已打印的旧文案本次无法撤回" | jobs_intro_style body
    gray_echo "• 本工具会在运行后自动修复能定位到的 x.command，下一次执行时生效" | jobs_intro_style body
    echo "" | jobs_intro_style body

    warn_echo "本地 Pod 根目录说明：" | jobs_intro_style title
    gray_echo "• 这个目录下面通常有多个兄弟文件夹" | jobs_intro_style body
    gray_echo "• 每个兄弟文件夹里面通常都有自己的 *.podspec" | jobs_intro_style body
    gray_echo "• 目标 Pod 会被 lint；真实依赖到的兄弟 podspec 会作为本地依赖参与解析" | jobs_intro_style body
    echo "" | jobs_intro_style body

    warn_echo "注意事项：" | jobs_intro_style title
    gray_echo "• 安装或升级 CocoaPods 时可能要求输入系统密码" | jobs_intro_style body
    gray_echo "• pod lib lint 会暴露 public_header_files、source_files、frameworks、resources、subspec 依赖等问题" | jobs_intro_style body
    gray_echo "• 如果日志中出现 BUILD SUCCEEDED，但随后出现 lint ERROR，本工具会明确标记为：编译通过，podspec 校验失败" | jobs_intro_style body
    gray_echo "• 默认不再把所有兄弟 podspec 全量塞给 --include-podspecs，避免无关 Pod 污染本次自检" | jobs_intro_style body
    gray_echo "• 本工具默认使用：--platforms=ios --private --verbose --no-clean --allow-warnings" | jobs_intro_style body
    gray_echo "• --no-clean 会保留 CocoaPods 临时目录，方便你排查编译错误" | jobs_intro_style body
    gray_echo "• 每次自检结束后：回车继续检查下一个 Pod；输入 r 可更换根目录；输入 q 退出" | jobs_intro_style body
    echo "" | jobs_intro_style body

    warm_echo "当前脚本：${SCRIPT_PATH}" | jobs_intro_style body
    warm_echo "日志文件：${LOG_FILE}" | jobs_intro_style body
    echo "" | jobs_intro_style body

    print_divider
    repair_x_command_wait_prompt_if_possible
    print_divider

    pause_for_enter "👉 请确认开始执行。按回车继续，或按 Ctrl+C 取消..."
}
# 解析并返回后续流程需要的目标信息。
find_gem_bin() {
    if command -v gem >/dev/null 2>&1; then
        command -v gem
        return 0
    fi

    local candidate_file
    for candidate_file in /opt/homebrew/opt/ruby/bin/gem /usr/local/opt/ruby/bin/gem /usr/bin/gem; do
        if [[ -x "$candidate_file" ]]; then
            print -r -- "$candidate_file"
            return 0
        fi
    done

    return 1
}
# 解析并返回后续流程需要的目标信息。
find_pod_bin() {
    if command -v pod >/dev/null 2>&1; then
        command -v pod
        return 0
    fi

    local candidate_file
    for candidate_file in /opt/homebrew/bin/pod /usr/local/bin/pod /usr/bin/pod; do
        if [[ -x "$candidate_file" ]]; then
            print -r -- "$candidate_file"
            return 0
        fi
    done

    return 1
}
# 执行对应的环境配置或同步处理。
install_cocoapods_by_gem() {
    local gem_bin
    if ! gem_bin="$(find_gem_bin)"; then
        error_echo "gem 不存在，无法按当前流程安装 CocoaPods。"
        warm_echo "请先安装 Ruby/gem 后重新运行本 .command。"
        return 1
    fi

    run_cmd_stream "安装 CocoaPods" sudo "$gem_bin" install cocoapods || return 1

    hash -r 2>/dev/null || true

    local pod_bin_after_install
    if pod_bin_after_install="$(find_pod_bin)"; then
        success_echo "CocoaPods 安装完成：${pod_bin_after_install}"
        run_cmd_stream "输出 CocoaPods 版本" "$pod_bin_after_install" --version
        return 0
    fi

    error_echo "CocoaPods 安装后仍未检测到 pod 命令。"
    warm_echo "可能是 gem 可执行目录未加入 PATH，请重新打开终端后再试。"
    return 1
}
# 检查当前运行条件是否满足后续流程要求。
ensure_pod_command() {
    print_divider
    highlight_echo "开始自检 CocoaPods"

    local pod_bin
    if ! pod_bin="$(find_pod_bin)"; then
        warn_echo "未检测到 pod 命令，进入 CocoaPods 安装流程。"
        install_cocoapods_by_gem || return 1
        return 0
    fi

    success_echo "已检测到 pod：${pod_bin}"
    run_cmd_stream "输出 CocoaPods 版本" "$pod_bin" --version

    echo ""
    warm_echo "是否升级 CocoaPods？"
    gray_echo "• 直接回车：跳过升级"
    gray_echo "• 输入任意字符后回车：执行 sudo gem install cocoapods"
    { close_trace_noise; } >/dev/null 2>&1
    /usr/bin/printf "👉 请选择："
    {
        local choice_text
        local __TRIMMED_INPUT_VALUE
        IFS= read -r choice_text
        silent_input_guard
        trim_string_to_global "$choice_text"
        choice_text="$__TRIMMED_INPUT_VALUE"
        silent_input_guard
    } >/dev/null 2>&1
    silent_input_guard

    if [[ -z "$choice_text" ]]; then
        info_echo "已选择跳过 CocoaPods 升级。"
        return 0
    fi

    install_cocoapods_by_gem || return 1
}

WORKSPACE_ROOT=""
TARGET_POD_NAME=""
TARGET_PODSPEC_PATH=""
CHOSEN_PODSPEC_PATH=""

typeset -ga ALL_PODSPEC_PATHS
ALL_PODSPEC_PATHS=()
typeset -gA PODSPEC_BY_NAME
PODSPEC_BY_NAME=()
typeset -gA PODSPEC_NAME_BY_PATH
PODSPEC_NAME_BY_PATH=()
typeset -ga PODSPEC_DUPLICATE_NAMES
PODSPEC_DUPLICATE_NAMES=()
# 封装 discover_podspecs_under_root 对应的独立处理逻辑。
discover_podspecs_under_root() {
    local root_dir="$1"
    local -a found_specs
    local -a filtered_specs
    local candidate_file

    found_specs=(
        "$root_dir"/*.podspec(ND.)
        "$root_dir"/*/*.podspec(ND.)
        "$root_dir"/*/*/*.podspec(ND.)
    )
    found_specs=("${(@u)found_specs}")
    filtered_specs=()

    for candidate_file in "${found_specs[@]}"; do
        [[ "$candidate_file" == */__MACOSX/* ]] && continue
        [[ "$(basename -- "$candidate_file")" == ._* ]] && continue
        filtered_specs+=("$candidate_file")
    done

    print -r -- "${(pj:\n:)filtered_specs}"
}
# 封装 extract_podspec_declared_name 对应的独立处理逻辑。
extract_podspec_declared_name() {
    local spec_file="$1"
    local declared_name

    declared_name="$(/usr/bin/sed -nE "s/^[[:space:]]*[^#]*\\.name[[:space:]]*=[[:space:]]*['\\\"]([^'\\\"]+)['\\\"].*/\\1/p" "$spec_file" 2>/dev/null | /usr/bin/sed -n '1p')"

    if [[ -n "$declared_name" ]]; then
        print -r -- "$declared_name"
        return 0
    fi

    basename -- "$spec_file" .podspec
}
# 封装 extract_dependency_names_from_podspec 对应的独立处理逻辑。
extract_dependency_names_from_podspec() {
    local spec_file="$1"
    local dependencies_text
    local dependency_name
    local -a dependency_names

    dependencies_text="$(/usr/bin/sed -nE "s/^[[:space:]]*[^#]*\\.dependency[[:space:]]+['\\\"]([^'\\\"]+)['\\\"].*/\\1/p" "$spec_file" 2>/dev/null)"
    dependency_names=()

    while IFS= read -r dependency_name; do
        [[ -n "$dependency_name" ]] || continue
        dependency_name="${dependency_name%%/*}"
        [[ -n "$dependency_name" ]] || continue
        if (( ${dependency_names[(Ie)$dependency_name]} == 0 )); then
            dependency_names+=("$dependency_name")
        fi
    done <<< "$dependencies_text"

    print -r -- "${(pj:\n:)dependency_names}"
}
# 封装 build_podspec_index 对应的独立处理逻辑。
build_podspec_index() {
    PODSPEC_BY_NAME=()
    PODSPEC_NAME_BY_PATH=()
    PODSPEC_DUPLICATE_NAMES=()

    local spec_file
    local declared_name
    for spec_file in "${ALL_PODSPEC_PATHS[@]}"; do
        declared_name="$(extract_podspec_declared_name "$spec_file")"
        [[ -n "$declared_name" ]] || continue
        PODSPEC_NAME_BY_PATH[$spec_file]="$declared_name"

        if [[ -n "${PODSPEC_BY_NAME[$declared_name]-}" ]]; then
            PODSPEC_DUPLICATE_NAMES+=("$declared_name")
            continue
        fi

        PODSPEC_BY_NAME[$declared_name]="$spec_file"
    done

    if (( ${#PODSPEC_DUPLICATE_NAMES[@]} > 0 )); then
        warn_echo "发现重复的 Pod 名，智能依赖模式会使用首次发现的 podspec。"
        local duplicate_name
        local -a printed_names
        printed_names=()
        for duplicate_name in "${PODSPEC_DUPLICATE_NAMES[@]}"; do
            (( ${printed_names[(Ie)$duplicate_name]} > 0 )) && continue
            printed_names+=("$duplicate_name")
            gray_echo "• ${duplicate_name}"
        done
    fi
}
# 封装 join_files_by_comma 对应的独立处理逻辑。
join_files_by_comma() {
    local -a files=("$@")
    print -r -- "${(j:,:)files}"
}
# 封装 collect_all_dependency_podspecs 对应的独立处理逻辑。
collect_all_dependency_podspecs() {
    local target_spec="$1"
    local -a dependency_specs
    local candidate_file

    dependency_specs=()
    for candidate_file in "${ALL_PODSPEC_PATHS[@]}"; do
        [[ "$candidate_file" == "$target_spec" ]] && continue
        dependency_specs+=("$candidate_file")
    done

    join_files_by_comma "${dependency_specs[@]}"
}
# 封装 collect_smart_dependency_podspecs 对应的独立处理逻辑。
collect_smart_dependency_podspecs() {
    local target_spec="$1"
    local -a queue
    local -a dependency_specs
    local dependency_name
    local dependency_spec
    local sub_dependency_name
    typeset -A visited_names

    queue=()
    dependency_specs=()
    visited_names=()

    while IFS= read -r dependency_name; do
        [[ -n "$dependency_name" ]] || continue
        queue+=("$dependency_name")
    done < <(extract_dependency_names_from_podspec "$target_spec")

    while (( ${#queue[@]} > 0 )); do
        dependency_name="${queue[1]}"
        queue[1]=()
        [[ -n "$dependency_name" ]] || continue

        if [[ -n "${visited_names[$dependency_name]-}" ]]; then
            continue
        fi
        visited_names[$dependency_name]=1

        dependency_spec="${PODSPEC_BY_NAME[$dependency_name]-}"
        [[ -n "$dependency_spec" ]] || continue
        [[ "$dependency_spec" == "$target_spec" ]] && continue

        if (( ${dependency_specs[(Ie)$dependency_spec]} == 0 )); then
            dependency_specs+=("$dependency_spec")
        fi

        while IFS= read -r sub_dependency_name; do
            [[ -n "$sub_dependency_name" ]] || continue
            queue+=("$sub_dependency_name")
        done < <(extract_dependency_names_from_podspec "$dependency_spec")
    done

    join_files_by_comma "${dependency_specs[@]}"
}
# 封装 count_comma_items 对应的独立处理逻辑。
count_comma_items() {
    local comma_text="$1"
    if [[ -z "$comma_text" ]]; then
        print -r -- "0"
        return 0
    fi

    local -a items
    items=( ${(s:,:)comma_text} )
    print -r -- "${#items[@]}"
}
# 封装 print_include_podspecs 对应的独立处理逻辑。
print_include_podspecs() {
    local include_podspecs="$1"
    local mode_name="$2"

    if [[ -z "$include_podspecs" ]]; then
        info_echo "${mode_name}：未发现目标 Pod 依赖的本地兄弟 podspec，本次只 lint 目标 Pod。"
        return 0
    fi

    info_echo "${mode_name}：已收集本地依赖 podspec（$(count_comma_items "$include_podspecs") 个）："
    local dependency_item
    for dependency_item in ${(s:,:)include_podspecs}; do
        gray_echo "• $(relative_to_root "$WORKSPACE_ROOT" "$dependency_item")"
    done
}
# 封装 lint_output_has_missing_spec 对应的独立处理逻辑。
lint_output_has_missing_spec() {
    local output_file="$1"
    lint_output_matches "$output_file" 'Unable to find a specification for|None of your spec sources contain a spec satisfying'
}
# 收集并校验用户输入，决定后续执行路径。
choose_from_candidates() {
    local root_dir="$1"
    shift
    local -a candidates=("$@")

    if [[ ${#candidates[@]} -eq 1 ]]; then
        CHOSEN_PODSPEC_PATH="${candidates[1]}"
        return 0
    fi

    warn_echo "找到多个匹配的 podspec，请选择一个："
    local index=1
    local candidate_file
    for candidate_file in "${candidates[@]}"; do
        gray_echo "${index}. $(relative_to_root "$root_dir" "$candidate_file")"
        ((index++))
    done

    while true; do
        { close_trace_noise; } >/dev/null 2>&1
        /usr/bin/printf "👉 请输入序号："
        {
            local selected_index
            local __TRIMMED_INPUT_VALUE
            IFS= read -r selected_index
            silent_input_guard
            trim_string_to_global "$selected_index"
            selected_index="$__TRIMMED_INPUT_VALUE"
            silent_input_guard
        } >/dev/null 2>&1
        silent_input_guard

        if [[ "$selected_index" != <-> ]]; then
            warn_echo "请输入数字序号。"
            continue
        fi

        if (( selected_index < 1 || selected_index > ${#candidates[@]} )); then
            warn_echo "序号超出范围。"
            continue
        fi

        CHOSEN_PODSPEC_PATH="${candidates[$selected_index]}"
        return 0
    done
}
# 收集并校验用户输入，决定后续执行路径。
ask_for_workspace_root() {
    if [[ -n "${JOBS_IOS_PROJECT_DIR:-}" && -d "$JOBS_IOS_PROJECT_DIR" ]]; then
        WORKSPACE_ROOT="${JOBS_IOS_PROJECT_DIR:h}"
        ALL_PODSPEC_PATHS=("${(@f)$(discover_podspecs_under_root "$WORKSPACE_ROOT")}")
        build_podspec_index
        return 0
    fi
    local cached_workspace_root=""
    local raw_workspace_root=""
    local input_dir=""
    local used_cached_workspace_root="0"
    local discovered_specs_text=""
    local discovered_spec=""
    local -a discovered_specs

    cached_workspace_root="$(load_workspace_root_cache)"

    while true; do
        echo ""
        highlight_echo "请输入本地 Pod 根目录地址"
        gray_echo "示例：/Users/jobs/Developer/Pods"
        gray_echo "也可以直接把 Finder 里的目录拖进终端窗口。"

        if [[ -n "$cached_workspace_root" ]]; then
            gray_echo "已记住：${cached_workspace_root}"
            gray_echo "直接回车：沿用历史目录"
            gray_echo "输入新路径后回车：更改并记住新目录"
        else
            gray_echo "首次使用时不能为空；请输入本地 Pod 根目录。"
        fi

        { close_trace_noise; } >/dev/null 2>&1
        /usr/bin/printf "👉 本地 Pod 根目录："

        {
            local __NORMALIZED_INPUT_DIR=""
            raw_workspace_root=""
            input_dir=""
            used_cached_workspace_root="0"
            IFS= read -r raw_workspace_root
            normalize_input_dir_to_global "$raw_workspace_root"
            input_dir="$__NORMALIZED_INPUT_DIR"
            silent_input_guard
        } >/dev/null 2>&1
        silent_input_guard

        if [[ -z "$input_dir" ]]; then
            if [[ -n "$cached_workspace_root" ]]; then
                input_dir="$cached_workspace_root"
                used_cached_workspace_root="1"
                info_echo "已沿用历史目录：${input_dir}"
            else
                warn_echo "目录不能为空。"
                continue
            fi
        fi

        if [[ ! -d "$input_dir" ]]; then
            if [[ "$used_cached_workspace_root" == "1" ]]; then
                error_echo "历史目录已不可用：${input_dir}"
                warm_echo "请重新输入新的本地 Pod 根目录。"
            else
                error_echo "目录不存在：${input_dir}"
            fi
            continue
        fi

        discovered_specs_text="$(discover_podspecs_under_root "$input_dir")"
        discovered_specs=()
        while IFS= read -r discovered_spec; do
            [[ -n "$discovered_spec" ]] || continue
            discovered_specs+=("$discovered_spec")
        done <<< "$discovered_specs_text"

        if [[ ${#discovered_specs[@]} -eq 0 ]]; then
            error_echo "该目录下没有找到 *.podspec：${input_dir}"
            warm_echo "请确认你输入的是多个 Pod 兄弟文件夹的上级目录。"
            continue
        fi

        success_echo "已找到 ${#discovered_specs[@]} 个 podspec。"

        if [[ "$input_dir" != "$cached_workspace_root" ]]; then
            if save_workspace_root_cache "$input_dir"; then
                success_echo "已记住本地 Pod 根目录：${input_dir}"
                cached_workspace_root="$input_dir"
            else
                warn_echo "写入历史目录失败：${WORKSPACE_ROOT_CACHE_FILE}"
            fi
        fi

        WORKSPACE_ROOT="$input_dir"
        ALL_PODSPEC_PATHS=("${discovered_specs[@]}")
        build_podspec_index
        return 0
    done
}
# 解析并返回后续流程需要的目标信息。
find_target_podspec() {
    local root_dir="$1"
    local pod_name="$2"

    local -a exact_specs=()
    local candidate_file
    for candidate_file in "${ALL_PODSPEC_PATHS[@]}"; do
        if [[ "$(basename -- "$candidate_file")" == "${pod_name}.podspec" ]]; then
            exact_specs+=("$candidate_file")
        fi
    done

    if [[ ${#exact_specs[@]} -gt 0 ]]; then
        choose_from_candidates "$root_dir" "${exact_specs[@]}" || return 1
        TARGET_PODSPEC_PATH="$CHOSEN_PODSPEC_PATH"
        return 0
    fi

    local -a declared_name_specs=()
    for candidate_file in "${ALL_PODSPEC_PATHS[@]}"; do
        if [[ "${PODSPEC_NAME_BY_PATH[$candidate_file]-}" == "$pod_name" ]]; then
            declared_name_specs+=("$candidate_file")
        fi
    done

    if [[ ${#declared_name_specs[@]} -gt 0 ]]; then
        choose_from_candidates "$root_dir" "${declared_name_specs[@]}" || return 1
        TARGET_PODSPEC_PATH="$CHOSEN_PODSPEC_PATH"
        return 0
    fi

    return 1
}
# 收集并校验用户输入，决定后续执行路径。
ask_for_target_pod_name() {
    if [[ -n "${JOBS_IOS_PROJECT_DIR:-}" ]]; then
        local -a finder_specs=("$JOBS_IOS_PROJECT_DIR"/*.podspec(ND.))
        (( ${#finder_specs[@]} > 0 )) || { error_echo '当前目录已无 podspec，停止。'; return 1; }
        choose_from_candidates "$JOBS_IOS_PROJECT_DIR" "${finder_specs[@]}" || return 1
        TARGET_PODSPEC_PATH="$CHOSEN_PODSPEC_PATH"
        TARGET_POD_NAME="$(extract_podspec_declared_name "$TARGET_PODSPEC_PATH")"
        return 0
    fi
    while true; do
        echo ""
        highlight_echo "请输入需要自检的 Pod 名"
        gray_echo "示例：JobsSuspend"
        { close_trace_noise; } >/dev/null 2>&1
        /usr/bin/printf "👉 Pod 名："

        {
            local input_name
            local pod_name
            local __TRIMMED_INPUT_VALUE
            IFS= read -r input_name
            silent_input_guard
            trim_string_to_global "$input_name"
            pod_name="$__TRIMMED_INPUT_VALUE"
            silent_input_guard
        } >/dev/null 2>&1
        silent_input_guard

        if [[ -z "$pod_name" ]]; then
            warn_echo "Pod 名不能为空。"
            continue
        fi

        if find_target_podspec "$WORKSPACE_ROOT" "$pod_name"; then
            TARGET_POD_NAME="$pod_name"
            success_echo "目标 podspec：$(relative_to_root "$WORKSPACE_ROOT" "$TARGET_PODSPEC_PATH")"
            return 0
        fi

        error_echo "没有找到目标 Pod 的 podspec：${pod_name}"
        warm_echo "请确认 Pod 名是否等于 podspec 文件名，或等于 spec.name。"
    done
}
# 执行已经拆分完成的独立业务步骤。
execute_pod_lint_once() {
    local pod_bin="$1"
    local include_podspecs="$2"
    local mode_name="$3"
    local lint_run_log="$4"

    local -a lint_cmd
    lint_cmd=(
        "$pod_bin" lib lint "$TARGET_PODSPEC_PATH"
        --platforms=ios
        --private
        --verbose
        --no-clean
        --allow-warnings
    )

    if [[ -n "$include_podspecs" ]]; then
        lint_cmd+=(--include-podspecs="$include_podspecs")
    fi

    print_include_podspecs "$include_podspecs" "$mode_name"
    echo ""
    run_cmd_stream_to_file "执行 pod lib lint（${mode_name}）" "$lint_run_log" "${lint_cmd[@]}"
}
# 封装 classify_lint_result 对应的独立处理逻辑。
classify_lint_result() {
    local lint_run_log="$1"
    local lint_exit_code="$2"

    print_divider
    if [[ $lint_exit_code -eq 0 ]]; then
        success_echo "编译结果：${TARGET_POD_NAME} 已通过 xcodebuild 编译。"
        success_echo "lint 结果：podspec 校验通过。"
        success_echo "${TARGET_POD_NAME} 自检通过。"
        return 0
    fi

    if lint_output_contains "$lint_run_log" "** BUILD FAILED **"; then
        error_echo "编译结果：${TARGET_POD_NAME} 源码编译失败。"
        print_lint_error_summary "$lint_run_log"
        print_lint_failure_advice "$lint_run_log"
        warm_echo "重点查看上方 xcodebuild 输出，以及日志文件：${LOG_FILE}"
        return $lint_exit_code
    fi

    if lint_output_contains "$lint_run_log" "** BUILD SUCCEEDED **"; then
        success_echo "编译结果：${TARGET_POD_NAME} 已通过 xcodebuild 编译。"
        error_echo "lint 结果：podspec 校验失败。"
        warm_echo "结论：这不是源码编译失败，而是 podspec 规则/文件匹配/元信息问题。"
        print_lint_error_summary "$lint_run_log"
        print_lint_failure_advice "$lint_run_log"
        warm_echo "重点查看上方 pod lib lint 输出，以及日志文件：${LOG_FILE}"
        return 2
    fi

    if lint_output_has_missing_spec "$lint_run_log"; then
        error_echo "依赖解析结果：失败。"
        warm_echo "结论：尚未进入明确源码编译阶段，优先处理 podspec 依赖解析。"
        print_lint_error_summary "$lint_run_log"
        print_lint_failure_advice "$lint_run_log"
        warm_echo "重点查看上方 pod lib lint 输出，以及日志文件：${LOG_FILE}"
        return 3
    fi

    if lint_output_matches "$lint_run_log" "CompileC|Ld |SwiftCompile|ProcessPCH"; then
        warn_echo "lint 未通过，且日志中出现过编译阶段输出，但未找到明确 BUILD SUCCEEDED / BUILD FAILED。"
    else
        warn_echo "lint 未通过，且尚未进入明确 xcodebuild 编译结论。"
    fi

    error_echo "${TARGET_POD_NAME} 自检未通过。"
    print_lint_error_summary "$lint_run_log"
    print_lint_failure_advice "$lint_run_log"
    warm_echo "重点查看上方 pod lib lint 输出，以及日志文件：${LOG_FILE}"
    return $lint_exit_code
}
# 执行已经拆分完成的独立业务步骤。
run_pod_lint() {
    print_divider
    highlight_echo "开始执行 pod lib lint"

    local pod_bin
    if ! pod_bin="$(find_pod_bin)"; then
        error_echo "未检测到 pod 命令，无法继续。"
        return 1
    fi

    echo ""
    warm_echo "目标 Pod：${TARGET_POD_NAME}"
    warm_echo "目标 podspec：${TARGET_PODSPEC_PATH}"
    warm_echo "日志文件：${LOG_FILE}"
    echo ""

    preflight_resource_patterns "$TARGET_PODSPEC_PATH"

    local target_dir
    target_dir="$(dirname -- "$TARGET_PODSPEC_PATH")"
    cd "$target_dir" || return 1

    local smart_include_podspecs
    smart_include_podspecs="$(collect_smart_dependency_podspecs "$TARGET_PODSPEC_PATH")"

    local lint_run_log
    lint_run_log="/tmp/${SCRIPT_BASENAME}.pod-lib-lint-current.log"
    execute_pod_lint_once "$pod_bin" "$smart_include_podspecs" "智能依赖模式" "$lint_run_log"
    local lint_exit_code=$?
    local final_lint_log="$lint_run_log"

    if [[ $lint_exit_code -ne 0 ]] && lint_output_has_missing_spec "$lint_run_log"; then
        local all_include_podspecs
        all_include_podspecs="$(collect_all_dependency_podspecs "$TARGET_PODSPEC_PATH")"

        if [[ -n "$all_include_podspecs" && "$all_include_podspecs" != "$smart_include_podspecs" ]]; then
            echo ""
            warn_echo "智能依赖模式仍有缺失依赖，自动切换全量兼容模式重试一次。"
            gray_echo "全量兼容模式只作为兜底，不作为默认路径，避免无关 podspec 污染结论。"
            echo ""

            local fallback_lint_log
            fallback_lint_log="/tmp/${SCRIPT_BASENAME}.pod-lib-lint-fallback-all.log"
            execute_pod_lint_once "$pod_bin" "$all_include_podspecs" "全量兼容模式" "$fallback_lint_log"
            lint_exit_code=$?
            final_lint_log="$fallback_lint_log"
        fi
    fi

    classify_lint_result "$final_lint_log" "$lint_exit_code"
}

ASK_NEXT_POD_ACTION=""
ASK_NEXT_POD_ANSWER=""
# 收集并校验用户输入，决定后续执行路径。
ask_next_pod_action() {
    ASK_NEXT_POD_ACTION=""
    ASK_NEXT_POD_ANSWER=""

    while true; do
        echo ""
        print_divider
        highlight_echo "本次 Pod 自检已结束"
        gray_echo "直接回车：继续检查同一根目录下的下一个 Pod"
        gray_echo "输入 r 后回车：重新选择本地 Pod 根目录"
        gray_echo "输入 q 后回车：退出工具"
        { close_trace_noise; } >/dev/null 2>&1
        /usr/bin/printf "👉 请选择："

        {
            ASK_NEXT_POD_ANSWER=""
            __TRIMMED_INPUT_VALUE=""
            IFS= read -r ASK_NEXT_POD_ANSWER
            silent_input_guard
            trim_string_to_global "$ASK_NEXT_POD_ANSWER"
            ASK_NEXT_POD_ANSWER="$__TRIMMED_INPUT_VALUE"
            silent_input_guard
        } >/dev/null 2>&1
        silent_input_guard

        case "$ASK_NEXT_POD_ANSWER" in
            "")
                ASK_NEXT_POD_ACTION="next"
                return 0
                ;;
            r|R|root|ROOT|change|CHANGE|更换|更改|换目录)
                ASK_NEXT_POD_ACTION="change_root"
                return 0
                ;;
            q|Q|quit|QUIT|exit|EXIT|退出|结束)
                ASK_NEXT_POD_ACTION="quit"
                return 0
                ;;
            *)
                warn_echo "无法识别：${ASK_NEXT_POD_ANSWER}"
                warm_echo "请直接回车继续，或输入 r / q。"
                ;;
        esac
    done
}
# 执行对应的清理操作，并保留必要的安全检查。
reset_target_pod_state() {
    TARGET_POD_NAME=""
    TARGET_PODSPEC_PATH=""
    CHOSEN_PODSPEC_PATH=""
}
# 执行入口下沉后的完整业务流程和控制逻辑。
run_main_business_flow() {
    # 检查当前步骤所需的环境、路径或输入条件。
    ensure_pod_command || exit 1
    # 执行当前流程中的独立业务步骤：ask_for_workspace_root。
    ask_for_workspace_root

    # 初始化当前流程后续步骤需要使用的变量。
    local final_exit_code=0
    # 初始化当前流程后续步骤需要使用的变量。
    local current_exit_code=0

    # 循环处理用户输入或当前批次中的全部目标。
    while true; do
        # 执行当前流程中的独立业务步骤：reset_target_pod_state。
        reset_target_pod_state
        # 执行当前流程中的独立业务步骤：ask_for_target_pod_name。
        ask_for_target_pod_name || exit 1
        # 执行当前流程中的独立业务步骤：run_pod_lint。
        run_pod_lint
        # 初始化当前流程后续步骤需要使用的变量。
        current_exit_code=$?
        final_exit_code=$current_exit_code

        # 执行当前流程中的独立业务步骤：ask_next_pod_action。
        ask_next_pod_action

        # 根据当前条件选择对应的执行分支。
        case "$ASK_NEXT_POD_ACTION" in
            # 执行当前流程中的独立业务步骤：next。
            next)
                # 输出当前步骤的提示或执行进度。
                echo ""
                # 执行当前流程中的独立业务步骤：highlight_echo。
                highlight_echo "进入下一个 Pod 自检流程"
                # 执行当前流程中的独立业务步骤：continue。
                continue
                ;;
            # 执行当前流程中的独立业务步骤：change_root。
            change_root)
                # 输出当前步骤的提示或执行进度。
                echo ""
                # 执行当前流程中的独立业务步骤：highlight_echo。
                highlight_echo "重新选择本地 Pod 根目录"
                # 执行当前流程中的独立业务步骤：ask_for_workspace_root。
                ask_for_workspace_root
                # 执行当前流程中的独立业务步骤：continue。
                continue
                ;;
            # 执行当前流程中的独立业务步骤：quit。
            quit)
                # 输出当前步骤的提示或执行进度。
                echo ""
                # 执行当前流程中的独立业务步骤：info_echo。
                info_echo "已退出本地 Pod 编译自检工具。"
                # 执行当前流程中的独立业务步骤：break。
                break
                ;;
        esac
    done

    # 执行当前流程中的独立业务步骤：exit。
    exit $final_exit_code
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  emulate -R zsh
  {
      set +x 2>/dev/null || true
      set +v 2>/dev/null || true
      unsetopt xtrace 2>/dev/null || true
      unsetopt verbose 2>/dev/null || true
      setopt typeset_silent 2>/dev/null || true
      unset XTRACEFD BASH_XTRACEFD 2>/dev/null || true
      trap - DEBUG 2>/dev/null || true
      unfunction TRAPDEBUG 2>/dev/null || true
      PS4=''
  } >/dev/null 2>&1
  {
      set +xv 2>/dev/null || true
      unsetopt xtrace 2>/dev/null || true
      unsetopt verbose 2>/dev/null || true
      setopt typeset_silent 2>/dev/null || true
      unset XTRACEFD BASH_XTRACEFD 2>/dev/null || true
      PS4=''
  } >/dev/null 2>&1
  set -u
  setopt null_glob
  setopt extended_glob
  setopt typeset_silent 2>/dev/null || true
  : > "$LOG_FILE"
}
# 编排脚本的高层业务流程。
main() {
  # 展示脚本内置自述，并按运行入口完成防误触确认。
  show_readme_and_block
  # 初始化 Shell 选项、日志、依赖和入口运行状态。
  initialize_script_runtime
  # 执行入口下沉后的完整业务流程。
  run_main_business_flow "$@"
}

main "$@"
