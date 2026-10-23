#!/bin/zsh
# 脚本自述：
# - 脚本名称：ManageProjectJava.zsh。
# - 核心用途：以 jEnv 和 .java-version 安装 / 切换指定 Flutter 项目的 JDK。
# - 影响范围：确认后可用 Homebrew 安装缺失工具、向 jEnv 注册本机 JDK，并修改目标 .java-version；不改全局 Java、Shell 或 Flutter 配置。
# - 运行提示：先阅读自述并回车，选择版本后再次确认；Ctrl+C / q 取消。--check 全程只读且不联网；source 只提供函数。

typeset PJ_PROJECT="" PJ_MODE="manage" PJ_LOG_FILE="" PJ_RUN_DIR=""
typeset PJ_JENV="" PJ_BREW="" PJ_BREW_PREFIX="" PJ_JAVA_HOME="" PJ_JAVA_VERSION="" PJ_JAVA_MAJOR=""
typeset PJ_CONFIG="" PJ_CONFIG_STAMP="" PJ_ORIGINAL="" PJ_SELECTED_HOME="" PJ_SELECTED_MAJOR="" PJ_SELECTED_ALIAS=""
typeset PJ_EXPECTED="" PJ_LOCK="" PJ_TRANSACTION=0 PJ_CONFIG_EXISTED=0
typeset -a PJ_HOMES PJ_VERSIONS

# 展示自述专用配色，非终端保持纯文本。
pj_intro_line() {
    local role="$1" message="$2"
    if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" ]]; then
        if [[ "$role" == title ]]; then
            printf '\033[1;31m%s\033[0m\n' "$message"
        else
            printf '\033[0;34m%s\033[0m\n' "$message"
        fi
    else
        print -r -- "$message"
    fi
}
# 同步输出纯文本业务日志，source / --check 不创建日志。
pj_log() {
    print -r -- "$1"
    if [[ -n "$PJ_LOG_FILE" ]]; then
        print -r -- "$1" >> "$PJ_LOG_FILE"
    fi
}
# 清除第三方工具强制输出的 ANSI，保证非终端与日志仍可直接阅读。
pj_strip_ansi() {
    /usr/bin/perl -pe 's/\e\[[0-?]*[ -\/]*[@-~]//g; s/\e\][^\a]*(?:\a|\e\\)//g'
}
# 严格解析入口参数，目标自身必须是普通 Flutter 项目目录。
pj_parse_invocation() {
    PJ_MODE=manage
    PJ_PROJECT=""
    while (( $# )); do
        case "$1" in
            --project)
                [[ -z "$PJ_PROJECT" && $# -ge 2 ]] || return 2
                PJ_PROJECT="$2"
                shift 2
                ;;
            --check)
                [[ "$PJ_MODE" == manage ]] || return 2
                PJ_MODE=check
                shift
                ;;
            *) return 2 ;;
        esac
    done
    pj_validate_project "$PJ_PROJECT"
}
# 复用现有静态项目识别，不搜索父目录或执行任何工程代码。
pj_validate_project() {
    local target="$1" helper="${${(%):-%x}:A:h}/CleanBuildArtifacts.zsh" kind=""
    while [[ "$target" == */ && "$target" != / ]]; do target="${target%/}"; done
    [[ "$target" == /* && "$target" != / && -d "$target" && ! -L "$target" ]] || {
        pj_log '✖ 请选择实际 Flutter 项目根目录（绝对路径），不能选择符号链接。'
        return 2
    }
    [[ -f "$target/pubspec.yaml" && ! -L "$target/pubspec.yaml" && -f "$helper" ]] || return 2
    kind="$(/bin/zsh "$helper" "$target" --detect 2>/dev/null)" || return 2
    [[ "$kind" == Flutter ]] || { pj_log '✖ 目标自身不是可确认的 Flutter 项目。'; return 2; }
    PJ_PROJECT="${target:A}"
}
# 第一屏先说明用途和完整影响；只读检查模式不等待输入。
show_script_intro_and_wait() {
    local answer="" result=0
    pj_intro_line title '━━━━━━━━━━ 项目 Java 环境安装 / 切换（jEnv）━━━━━━━━━━'
    pj_intro_line body '1、仅管理指定 Flutter 根目录的 .java-version；可以复用本机 JDK，或安装指定 Java 主版本。'
    pj_intro_line body '2、确认后，缺少 jEnv / JDK 时会通过已安装的 Homebrew 自动补齐；下载源是 Homebrew 官方 Formulae，软件安装影响本机共享工具目录。'
    pj_intro_line body '3、向 jEnv 注册 JDK 并只执行项目 jenv local；不修改 jenv global、Shell 配置、全局 Flutter jdk-dir 或系统 Java 链接。'
    pj_intro_line body '4、菜单启动的 Android 构建绑定所选 JAVA_HOME 和 Gradle JVM；Flutter 自身仍可能采用 Android Studio JDK。现有 Gradle JVM criteria 冲突时停止。'
    pj_intro_line body '5、先回车进入选择，再回车确认具体版本；q / 非空最终确认 / Ctrl+C 取消。日志与原配置快照保留在系统临时目录 JobsProjectJava.*。'
    pj_intro_line body '6、--check 只读、不联网、不安装、不写日志；源码被 source 时不执行入口或修改环境。'
    pj_parse_invocation "$@" || result=$?
    if (( result )); then
        pj_log '✖ 用法：/bin/zsh ManageProjectJava.zsh --project <Flutter项目绝对路径> [--check]'
        exit "$result"
    fi
    pj_intro_line body "目标目录：$PJ_PROJECT"
    [[ "$PJ_MODE" == check ]] && return 0
    [[ -t 0 && -t 1 ]] || { pj_log '✖ 需要可交互 Terminal；请在终端重新运行。'; exit 2; }
    IFS= read -r 'answer?👉 已了解用途与影响，按回车继续；Ctrl+C 取消：' || exit 130
    [[ -z "$answer" ]] || exit 130
}
# 确认后才建立运行日志和中断保护，检查模式不创建任何文件。
pj_initialize_runtime() {
    setopt localoptions NO_NOMATCH PIPE_FAIL
    [[ "$PJ_MODE" == check ]] && return 0
    PJ_RUN_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/JobsProjectJava.XXXXXX")" || return 1
    PJ_LOG_FILE="$PJ_RUN_DIR/ManageProjectJava.log"
    : > "$PJ_LOG_FILE"
    trap 'pj_cleanup_transaction; exit 130' INT
    trap 'pj_cleanup_transaction; exit 143' TERM HUP
    pj_log "➤ 日志与快照：$PJ_RUN_DIR"
}
# 读取小型纯文本版本声明，拒绝链接、特殊文件、硬链接及可执行内容。
pj_read_config() {
    local config_file="$PJ_PROJECT/.java-version" value="" details=""
    PJ_CONFIG=""
    PJ_CONFIG_EXISTED=0
    PJ_CONFIG_STAMP=absent
    if [[ -e "$PJ_PROJECT/.jenv-version" || -L "$PJ_PROJECT/.jenv-version" ]]; then
        pj_log '✖ 检测到旧 .jenv-version；jenv local 可能迁移并删除它，请先人工确认并迁移到 .java-version 后重试。'
        return 1
    fi
    if [[ -L "$config_file" || ( -e "$config_file" && ! -f "$config_file" ) ]]; then
        pj_log '✖ .java-version 不是普通文件；为保护链接或特殊文件已停止。'
        return 1
    fi
    [[ -e "$config_file" ]] || return 0
    details="$(/usr/bin/stat -f '%l:%z' "$config_file" 2>/dev/null)" || return 1
    [[ "${details%%:*}" == 1 && "${details#*:}" == <-> && "${details#*:}" -le 1024 ]] || {
        pj_log '✖ .java-version 含硬链接、超过 1 KiB 或无法读取，已停止。'
        return 1
    }
    value="$(/usr/bin/perl -0777 -e 'local $/; $_=<>; s/\r?\n\z//; /\A[A-Za-z0-9][A-Za-z0-9._+\-]{0,127}\z/ && $_ ne "system" or exit 1; print;' "$config_file")" || {
        pj_log '✖ .java-version 只允许一个 jEnv 版本标识（例如 17 或 openjdk64-17.0.17）；不会执行配置。'
        return 1
    }
    PJ_CONFIG="$value"
    PJ_CONFIG_EXISTED=1
    PJ_CONFIG_STAMP="$(pj_config_stamp)" || return 1
}
# 将元数据和内容摘要一起用于写入前及失败恢复时的并发检查。
pj_config_stamp() {
    local config_file="$PJ_PROJECT/.java-version"
    [[ ! -L "$config_file" ]] || return 1
    if [[ ! -e "$config_file" ]]; then
        print -r -- absent
        return 0
    fi
    [[ -f "$config_file" ]] || return 1
    /usr/bin/stat -f '%d:%i:%l:%m:%c:%z' "$config_file" || return 1
    /usr/bin/shasum -a 256 "$config_file" || return 1
}
# 仅发现可执行 jEnv，不运行 init、不修改用户 Shell 配置。
pj_find_jenv() {
    local candidate="" item
    PJ_JENV=""
    candidate="$(command -v jenv 2>/dev/null)"
    for item in "$candidate" "$HOME/.jenv/bin/jenv" /opt/homebrew/bin/jenv /usr/local/bin/jenv; do
        if [[ -n "$item" && -x "$item" ]] && "$item" --version >/dev/null 2>&1; then
            PJ_JENV="$item"
            return 0
        fi
    done
    return 1
}
# 验证真实 JDK 的运行时和编译器主版本一致，不接受只有 JRE 的目录。
pj_probe_jdk() {
    local jdk_home="$1" runtime="" compiler="" version="" compiler_version="" major="" compiler_major=""
    [[ "$jdk_home" == /* && -d "$jdk_home" && -x "$jdk_home/bin/java" && -x "$jdk_home/bin/javac" ]] || return 1
    runtime="$("$jdk_home/bin/java" -version 2>&1)" || return 1
    compiler="$("$jdk_home/bin/javac" -version 2>&1)" || return 1
    version="$(print -r -- "$runtime" | /usr/bin/perl -ne 'if (/^(?:openjdk|java) version "([0-9]+(?:\.[0-9]+)*(?:[_+\-][0-9A-Za-z.\-]+)?)"/) {print $1; exit} elsif (/^(?:openjdk|java) ([0-9]+(?:\.[0-9]+)*(?:[_+\-][0-9A-Za-z.\-]+)?)(?:\s|$)/) {print $1; exit}')"
    compiler_version="$(print -r -- "$compiler" | /usr/bin/perl -ne 'if (/^javac ([0-9]+(?:\.[0-9]+)*(?:[_+\-][0-9A-Za-z.\-]+)?)(?:\s|$)/) {print $1; exit}')"
    [[ -n "$version" && -n "$compiler_version" ]] || return 1
    major="${version%%[._+-]*}"
    compiler_major="${compiler_version%%[._+-]*}"
    if [[ "$major" == 1 ]]; then major="${${version#1.}%%[._+-]*}"; fi
    if [[ "$compiler_major" == 1 ]]; then compiler_major="${${compiler_version#1.}%%[._+-]*}"; fi
    [[ "$major" == <-> && "$major" == "$compiler_major" ]] || return 1
    PJ_JAVA_HOME="${jdk_home:A}"
    PJ_JAVA_VERSION="$version"
    PJ_JAVA_MAJOR="$major"
}
# 将通过双健康检查的本机 JDK 去重加入菜单。
pj_add_candidate() {
    local jdk_home="$1"
    pj_probe_jdk "$jdk_home" || return 0
    (( ${PJ_HOMES[(Ie)$PJ_JAVA_HOME]} )) && return 0
    PJ_HOMES+=("$PJ_JAVA_HOME")
    PJ_VERSIONS+=("$PJ_JAVA_VERSION")
}
# 从 jEnv、本机 JDK、Android Studio 和常见 Homebrew 前缀只读发现环境。
pj_discover_jdks() {
    setopt localoptions NO_NOMATCH
    local alias_name="" candidate="" item
    PJ_HOMES=()
    PJ_VERSIONS=()
    pj_find_jenv || true
    if [[ -n "$PJ_JENV" ]]; then
        while IFS= read -r alias_name; do
            [[ "$alias_name" =~ '^[A-Za-z0-9][A-Za-z0-9._+\-]*$' && "$alias_name" != system ]] || continue
            candidate="$(/usr/bin/env JENV_VERSION="$alias_name" "$PJ_JENV" prefix 2>/dev/null)" || continue
            pj_add_candidate "$candidate"
        done < <("$PJ_JENV" versions --bare 2>/dev/null)
    fi
    if [[ -n "${JAVA_HOME:-}" ]]; then pj_add_candidate "$JAVA_HOME"; fi
    while IFS= read -r -d '' item; do
        pj_add_candidate "$item"
    done < <(pj_system_jdk_homes)
}
# 用 NUL 分隔候选目录，供发现流程及隔离测试复用。
pj_system_jdk_homes() {
    setopt localoptions NO_NOMATCH
    local item
    for item in /Library/Java/JavaVirtualMachines/*/Contents/Home(N) "$HOME"/Library/Java/JavaVirtualMachines/*/Contents/Home(N) /Applications/'Android Studio.app'/Contents/jbr/Contents/Home(N) /opt/homebrew/opt/openjdk*/libexec/openjdk.jdk/Contents/Home(N) /usr/local/opt/openjdk*/libexec/openjdk.jdk/Contents/Home(N); do
        printf '%s\0' "$item"
    done
}
# 优先用精确 jEnv 标识解析，纯数字声明还能复用已发现的同版本 JDK。
pj_resolve_config() {
    local candidate="" index=0
    [[ -n "$PJ_CONFIG" ]] || return 1
    if [[ -n "$PJ_JENV" ]]; then
        candidate="$(/usr/bin/env JENV_VERSION="$PJ_CONFIG" "$PJ_JENV" prefix 2>/dev/null)"
        if [[ -n "$candidate" ]] && pj_probe_jdk "$candidate"; then return 0; fi
    fi
    [[ "$PJ_CONFIG" =~ '^[0-9]+([._][0-9]+)*$' ]] || return 1
    for (( index=1; index<=${#PJ_HOMES}; index++ )); do
        pj_probe_jdk "${PJ_HOMES[index]}" || continue
        if [[ "$PJ_CONFIG" == "$PJ_JAVA_MAJOR" || "$PJ_CONFIG" == "$PJ_JAVA_VERSION" ]]; then return 0; fi
    done
    return 1
}
# 从声明推导安装菜单的默认主版本，未知标识回退 Android 常用 Java 17。
pj_default_major() {
    local value="${PJ_CONFIG:-17}" major=""
    major="$(print -r -- "$value" | /usr/bin/perl -ne 'if (/(?:^|[-])(?:1\.)?([0-9]+)(?:[._+\-][0-9A-Za-z.\-]*)?$/) {print $1}')"
    [[ "$major" == <-> && ${#major} -le 2 && "$major" -ge 8 ]] || major=17
    print -r -- "$major"
}
# 编号选择本机 JDK 或新增主版本，所有输入只作数据处理。
pj_choose_jdk() {
    local answer="" requested="" candidate="" index=0 default_major="$(pj_default_major)"
    pj_log "➤ 当前 .java-version：${PJ_CONFIG:-未配置}"
    for (( index=1; index<=${#PJ_HOMES}; index++ )); do
        pj_log "${index}、本机 Java ${PJ_VERSIONS[index]} · ${PJ_HOMES[index]}"
    done
    pj_log 'n、安装 / 复用指定 Java 主版本；q、取消'
    IFS= read -r "answer?选择编号（回车进入 Java ${default_major} 安装 / 复用；q 取消）：" || return 130
    [[ "$answer" != [qQ] ]] || return 130
    if [[ -z "$answer" || "$answer" == [nN] ]]; then
        IFS= read -r "requested?Java 主版本（回车 ${default_major}；q 取消）：" || return 130
        [[ "$requested" != [qQ] ]] || return 130
        [[ -n "$requested" ]] || requested="$default_major"
        [[ "$requested" == <-> && ${#requested} -le 2 && "$requested" -ge 8 && "$requested" -le 99 ]] || { pj_log '✖ 主版本须为 8–99 之间的整数。'; return 2; }
        PJ_SELECTED_MAJOR="$(( 10#$requested ))"
        PJ_SELECTED_HOME=""
        for candidate in "${PJ_HOMES[@]}"; do
            pj_probe_jdk "$candidate" || continue
            if [[ "$PJ_JAVA_MAJOR" == "$PJ_SELECTED_MAJOR" ]]; then PJ_SELECTED_HOME="$PJ_JAVA_HOME"; break; fi
        done
    elif [[ "$answer" == <-> && ${#answer} -le 5 ]] && (( 10#$answer >= 1 && 10#$answer <= ${#PJ_HOMES} )); then
        PJ_SELECTED_HOME="${PJ_HOMES[$(( 10#$answer ))]}"
        pj_probe_jdk "$PJ_SELECTED_HOME" || return 1
        PJ_SELECTED_MAJOR="$PJ_JAVA_MAJOR"
    else
        pj_log '✖ 请输入本机 JDK 编号或 n / q。'
        return 2
    fi
}
# 具体版本再次确认，安装和项目写入都排在此门禁之后。
pj_confirm_selection() {
    local answer=""
    pj_log "➤ 即将绑定 Java ${PJ_SELECTED_MAJOR}：${PJ_SELECTED_HOME:-将从 Homebrew 安装 openjdk@${PJ_SELECTED_MAJOR}}"
    pj_log "➤ 项目声明：$PJ_PROJECT/.java-version；缺少 jEnv 时安装 jenv。"
    if ! IFS= read -r 'answer?按回车安装 / 切换；任意非空输入取消：' || [[ -n "$answer" ]]; then return 130; fi
}
# 在已有 Homebrew 上验证真实前缀；缺失时停止，不自动安装包管理器。
pj_find_brew() {
    local candidate="$(command -v brew 2>/dev/null)" item prefix=""
    for item in "$candidate" /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [[ -n "$item" && -x "$item" ]] && "$item" --version >/dev/null 2>&1; then
            prefix="$(HOMEBREW_NO_AUTO_UPDATE=1 "$item" --prefix 2>/dev/null)" || continue
            [[ "$prefix" == /* && -d "$prefix" ]] || continue
            PJ_BREW="$item"
            PJ_BREW_PREFIX="$prefix"
            export PATH="$prefix/bin:$prefix/sbin:$PATH"
            return 0
        fi
    done
    pj_log '✖ 缺少可用 Homebrew。请先通过 https://brew.sh/ 安装 / 修复 Homebrew，再重新运行此菜单；本次已停止。'
    return 1
}
# 来源先于真实安装展示，完整保留 brew 的失败退出码。
pj_brew_install() {
    local formula="$1" result=0
    pj_log '━━━━━━━━━━ 来源｜安装 ━━━━━━━━━━'
    pj_log "📦 对象：${formula}"
    pj_log '🌐 软件源：Homebrew 官方 Formulae / homebrew/core；最终下载地址由 brew 解析并显示。'
    pj_log "📥 配方地址：https://formulae.brew.sh/formula/${formula}"
    pj_log "📂 目标：$PJ_BREW_PREFIX 的本机共享安装目录；不创建系统 Java 链接。"
    pj_log '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
    HOMEBREW_NO_AUTO_UPDATE=1 "$PJ_BREW" install --formula "$formula" 2>&1 | pj_strip_ansi | /usr/bin/tee -a "$PJ_LOG_FILE"
    result=${pipestatus[1]}
    if (( result )); then pj_log "✖ brew install --formula ${formula} 失败（${result}），已停止；请检查上方来源和 Homebrew 输出。"; fi
    return "$result"
}
# 只沿缺失依赖补齐一次，已健康的 jEnv / JDK 直接复用。
pj_ensure_dependencies() {
    local prefix="" result=0
    if ! pj_find_jenv; then
        pj_find_brew || return $?
        pj_brew_install jenv || return $?
        rehash
        pj_find_jenv || { pj_log '✖ jEnv 安装后仍不可用，请检查 brew info jenv。'; return 1; }
    fi
    if [[ -z "$PJ_SELECTED_HOME" ]]; then
        [[ -n "$PJ_BREW" ]] || pj_find_brew || return $?
        pj_brew_install "openjdk@${PJ_SELECTED_MAJOR}" || return $?
        prefix="$(HOMEBREW_NO_AUTO_UPDATE=1 "$PJ_BREW" --prefix "openjdk@${PJ_SELECTED_MAJOR}")" || return $?
        PJ_SELECTED_HOME="$prefix/libexec/openjdk.jdk/Contents/Home"
    fi
    pj_probe_jdk "$PJ_SELECTED_HOME" || { pj_log "✖ JDK 复检失败（必须同时具备可用 java / javac）：$PJ_SELECTED_HOME"; return 1; }
    [[ "$PJ_JAVA_MAJOR" == "$PJ_SELECTED_MAJOR" ]] || { pj_log '✖ 安装后的 JDK 主版本与选择不一致，已停止。'; return 1; }
    PJ_SELECTED_HOME="$PJ_JAVA_HOME"
}
# 注册真实 JDK，并选取能解析回该目录的精确 jEnv 标识。
pj_register_jdk() {
    local alias_name="" candidate="" result=0 digest=""
    pj_probe_jdk "$PJ_SELECTED_HOME" || return 1
    PJ_SELECTED_ALIAS=""
    for alias_name in "$PJ_JAVA_VERSION"; do
        candidate="$(/usr/bin/env JENV_VERSION="$alias_name" "$PJ_JENV" prefix 2>/dev/null)" || continue
        [[ "${candidate:A}" == "$PJ_SELECTED_HOME" ]] && PJ_SELECTED_ALIAS="$alias_name"
    done
    if [[ -z "$PJ_SELECTED_ALIAS" ]]; then
        while IFS= read -r alias_name; do
            [[ "$alias_name" =~ '^[A-Za-z0-9][A-Za-z0-9._+\-]*$' && "$alias_name" != system ]] || continue
            candidate="$(/usr/bin/env JENV_VERSION="$alias_name" "$PJ_JENV" prefix 2>/dev/null)" || continue
            if [[ "${candidate:A}" == "$PJ_SELECTED_HOME" ]]; then PJ_SELECTED_ALIAS="$alias_name"; break; fi
        done < <("$PJ_JENV" versions --bare)
    fi
    [[ -z "$PJ_SELECTED_ALIAS" ]] || return 0
    digest="$(print -rn -- "$PJ_SELECTED_HOME" | /usr/bin/shasum -a 256)"
    digest="${digest%% *}"
    alias_name="jobs-${PJ_JAVA_VERSION//_/.}-${digest[1,12]}"
    candidate="$(/usr/bin/env JENV_VERSION="$alias_name" "$PJ_JENV" prefix 2>/dev/null)"
    if [[ -n "$candidate" ]]; then
        pj_log "✖ 待注册标识 ${alias_name} 已指向其它环境，未覆盖它。"
        return 1
    fi
    pj_log "➤ 本机来源：$PJ_SELECTED_HOME → jEnv 独立标识 $alias_name（不覆盖已有别名）。"
    /usr/bin/env JENV_SKIP=true "$PJ_JENV" add "$alias_name" "$PJ_SELECTED_HOME" 2>&1 | pj_strip_ansi | /usr/bin/tee -a "$PJ_LOG_FILE"
    result=${pipestatus[1]}
    (( result == 0 )) || return "$result"
    candidate="$(/usr/bin/env JENV_VERSION="$alias_name" "$PJ_JENV" prefix 2>/dev/null)" || return 1
    [[ "${candidate:A}" == "$PJ_SELECTED_HOME" ]] || { pj_log '✖ jEnv 注册后的 JDK 路径不一致，未改动项目声明。'; return 1; }
    PJ_SELECTED_ALIAS="$alias_name"
}
# 检查会覆盖项目选择的 Gradle daemon JVM criteria，避免误报生效。
pj_check_gradle_criteria() {
    if [[ -e "$PJ_PROJECT/android/gradle/gradle-daemon-jvm.properties" || -L "$PJ_PROJECT/android/gradle/gradle-daemon-jvm.properties" ]]; then
        pj_log '✖ android/gradle/gradle-daemon-jvm.properties 的 JVM criteria 优先于项目 Java 选择；请先核对并调整该项目配置，再重新运行。'
        return 1
    fi
}
# 对目标 .java-version 做快照并在唯一项目目录执行 jenv local。
pj_write_project_config() {
    local current_stamp="" result=0 config_file="$PJ_PROJECT/.java-version" original_existed="$PJ_CONFIG_EXISTED"
    PJ_LOCK="$PJ_PROJECT/.java-version.jobs-lock"
    /bin/mkdir "$PJ_LOCK" 2>/dev/null || { PJ_LOCK=""; pj_log '✖ 已有 Java 切换锁或同名项目文件；请确认没有并发任务，保留现场后重试。'; return 1; }
    current_stamp="$(pj_config_stamp)" || return 1
    [[ "$current_stamp" == "$PJ_CONFIG_STAMP" ]] || { pj_log '✖ .java-version 在选择期间发生变化；已停止以保留新内容。'; return 1; }
    PJ_ORIGINAL="$PJ_RUN_DIR/original.java-version"
    PJ_EXPECTED="$PJ_RUN_DIR/expected.java-version"
    if (( PJ_CONFIG_EXISTED )); then /bin/cp -p "$config_file" "$PJ_ORIGINAL" || return 1; fi
    print -r -- "$PJ_SELECTED_ALIAS" > "$PJ_EXPECTED" || return 1
    PJ_TRANSACTION=1
    (cd -- "$PJ_PROJECT" && /usr/bin/env -u JENV_VERSION JENV_DIR="$PJ_PROJECT" "$PJ_JENV" local "$PJ_SELECTED_ALIAS") 2>&1 | pj_strip_ansi | /usr/bin/tee -a "$PJ_LOG_FILE"
    result=${pipestatus[1]}
    if (( result )); then pj_log "✖ jenv local 失败（${result}），将尝试恢复本次写入。"; return "$result"; fi
    if [[ -L "$config_file" || ! -f "$config_file" ]] || ! /usr/bin/cmp -s "$config_file" "$PJ_EXPECTED"; then
        pj_log '✖ jenv local 结果与确认的版本不一致；保留快照并停止。'
        return 1
    fi
    PJ_CONFIG="$PJ_SELECTED_ALIAS"
    pj_bind_project_java "$PJ_PROJECT" || result=$?
    PJ_CONFIG_EXISTED="$original_existed"
    (( result == 0 )) || return "$result"
    PJ_TRANSACTION=0
    pj_log "✔ 已绑定项目 Java：$PJ_CONFIG · $PJ_JAVA_HOME"
    pj_log '➤ 菜单后续启动的 Android 构建会绑定此 JDK；已有终端和 IDE 进程请重新启动并核对 Gradle JVM。'
}
# 失败 / 中断只恢复仍等于本次写入的配置，不覆盖并发编辑，保留快照用于人工恢复。
pj_cleanup_transaction() {
    local config_file="$PJ_PROJECT/.java-version" staging=""
    if (( PJ_TRANSACTION )); then
        if [[ ! -L "$config_file" && -f "$config_file" && -f "$PJ_EXPECTED" ]] && /usr/bin/cmp -s "$config_file" "$PJ_EXPECTED"; then
            if (( PJ_CONFIG_EXISTED )); then
                staging="$(/usr/bin/mktemp "$PJ_PROJECT/.java-version.restore.XXXXXX")"
                if [[ -n "$staging" ]] && /bin/cp -p "$PJ_ORIGINAL" "$staging" && /usr/bin/cmp -s "$config_file" "$PJ_EXPECTED" && /bin/mv -f "$staging" "$config_file"; then
                    pj_log '✔ 已恢复原 .java-version。'
                else
                    pj_log "✖ 自动恢复失败；原配置快照：$PJ_ORIGINAL；请核对当前文件后人工恢复。"
                    [[ -z "$staging" ]] || /bin/rm -f "$staging"
                fi
            else
                /bin/rm -f "$config_file" || pj_log '✖ 无法移除本次新增声明，请人工核对。'
            fi
        elif (( PJ_CONFIG_EXISTED )) && [[ ! -L "$config_file" && -f "$config_file" ]] && /usr/bin/cmp -s "$config_file" "$PJ_ORIGINAL"; then
            pj_log '➤ 原 .java-version 保持完整。'
        elif (( ! PJ_CONFIG_EXISTED )) && [[ ! -e "$config_file" && ! -L "$config_file" ]]; then
            pj_log '➤ 原项目没有 .java-version，本次也未保留声明。'
        else
            pj_log "⚠ 当前声明与本次写入不一致，可能存在并发编辑；未覆盖它。原配置快照：${PJ_ORIGINAL:-无原声明}"
        fi
    fi
    if [[ -n "$PJ_LOCK" && -d "$PJ_LOCK" && ! -L "$PJ_LOCK" ]]; then /bin/rmdir "$PJ_LOCK" 2>/dev/null || true; fi
    PJ_TRANSACTION=0
    PJ_LOCK=""
}
# 只读绑定接口：无项目声明时完全保持原环境，有声明时验证并注入当前进程。
pj_bind_project_java() {
    local project="$1" chosen_home="" escaped_home=""
    [[ -e "$project/.java-version" || -L "$project/.java-version" ]] || return 0
    pj_validate_project "$project" || return $?
    pj_read_config || return $?
    pj_check_gradle_criteria || return $?
    pj_discover_jdks
    pj_resolve_config || { pj_log "✖ 项目 Java 声明 ${PJ_CONFIG} 无法解析到可用 JDK；请先使用“安装/切换Java环境”菜单。"; return 1; }
    chosen_home="$PJ_JAVA_HOME"
    if [[ "$chosen_home" == *[\"\\\$\`]* ]] || ! print -rn -- "$chosen_home" | /usr/bin/perl -0777 -e 'local $/; $_=<>; exit /[\x00-\x1f\x7f]/ ? 1 : 0'; then
        pj_log '✖ JDK 真实路径含引号、反斜杠、美元符、反引号或控制字符，无法兼容各代 Gradle wrapper；请将 JDK 安装到常规目录后重新选择。项目目录仍可包含特殊字符。'
        return 1
    fi
    escaped_home="$chosen_home"
    export JAVA_HOME="$chosen_home"
    export PATH="$chosen_home/bin:$PATH"
    export JENV_VERSION="$PJ_CONFIG"
    export GRADLE_OPTS="${GRADLE_OPTS:+${GRADLE_OPTS} }-Dorg.gradle.java.home=\"${escaped_home}\""
    return 0
}
# 汇总只读自检结果，包含失效声明和 Gradle criteria 冲突。
pj_check_project() {
    pj_log '➤ 只读检查：不联网、不安装、不修改声明或日志。'
    pj_read_config || return $?
    pj_check_gradle_criteria || return $?
    pj_discover_jdks
    [[ -n "$PJ_CONFIG" ]] || { pj_log '✖ 尚无项目 .java-version，请使用安装 / 切换菜单选择 JDK。'; return 1; }
    pj_resolve_config || { pj_log "✖ 声明 ${PJ_CONFIG} 未匹配到可用 java / javac；请重新安装 / 切换。"; return 1; }
    pj_log "✔ 项目声明：$PJ_CONFIG；JDK：$PJ_JAVA_HOME；java / javac 主版本：$PJ_JAVA_MAJOR"
    [[ -n "$PJ_JENV" ]] || pj_log '➤ jEnv 尚未安装，当前数字声明可直接匹配本机 JDK；交互切换时再补齐 jEnv。'
}
# 执行检查或依赖补齐与事务写入，并保留真实失败码。
pj_run_requested_action() {
    local result=0
    pj_initialize_runtime || return $?
    if [[ "$PJ_MODE" == check ]]; then pj_check_project; return $?; fi
    pj_read_config && pj_check_gradle_criteria && pj_discover_jdks && pj_choose_jdk && pj_confirm_selection && pj_ensure_dependencies && pj_register_jdk && pj_write_project_config || result=$?
    if (( result == 130 )); then pj_log '➤ 已取消 Java 环境切换。'; fi
    if (( result != 0 && result != 130 )); then pj_log "✖ 操作失败（${result}）；日志与快照：$PJ_RUN_DIR"; fi
    pj_cleanup_transaction
    return "$result"
}
# 编排独立入口，source 此文件时只加载定义。
main() {
    show_script_intro_and_wait "$@" # 第一屏声明用途、范围及确认策略。
    pj_run_requested_action # 按模式执行只读检查或项目级 Java 切换。
}

if [[ "${ZSH_EVAL_CONTEXT}" == toplevel ]]; then
    main "$@"
fi
