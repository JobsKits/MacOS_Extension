#!/bin/zsh
# 脚本自述：
# - 脚本名称：SetupFlutterProject.zsh。
# - 核心用途：fzf选择FVM/系统Flutter、jEnv/系统JDK，准备固定Gradle、拉取Pub依赖并预热构建插件。
# - 影响范围：确认后安装缺失工具、项目SDK配置、.jobs环境记录、Android本机配置及正常缓存；不设置全局SDK或代理。
# - 运行提示：先自述回车；Enter选择、←返回、Esc取消；已完成阶段不自动撤销，原配置快照留在临时目录。

typeset -g SF_PROJECT="" SF_CHECK=0 SF_SDK_ONLY=0 SF_FLUTTER_MODE="" SF_JAVA_MODE="" SF_FLUTTER="" SF_FLUTTER_ROOT="" SF_JAVA_HOME=""
typeset -g SF_MIRROR=official SF_ENV_STAMP="" SF_LOCAL_STAMP="" SF_FVM_ACTION="" SF_SYSTEM_ACTION="" SF_HAS_ANDROID=1 SF_NEEDS_GRADLE=1
typeset -g SF_FLUTTER_VERSION="" SF_DART_VERSION="" SF_FVM_VERSION="" SF_JENV_VERSION=""
# 第一屏展示各阶段真实影响，参数检查和只读模式不会写日志。
sf_intro_and_wait() {
    local answer=""
    print -r -- '━━━━━━━━━━ SetupFlutterProject.zsh｜一键配置 Flutter 项目 ━━━━━━━━━━'
    print -r -- '1、先用fzf选择Flutter来源（默认FVM）和Java来源（默认jEnv），系统模式复用/选择本机SDK。'
    print -r -- '2、按选择安装或切换SDK；缺少工具会提示安装。系统Flutter可通过Homebrew安装；系统Java可复用或通过Homebrew安装指定版本。'
    print -r -- '3、按目标准备固定Gradle与平台资源，pub get后解析Maven、Pods/SPM、OHPM/Hvigor或Web锁定包，再实际构建准备FFI/CMake等延迟依赖。'
    print -r -- '4、保存.jobs/flutter-environment.json与android/local.properties的flutter.sdk；原文件先备份。FVM/jEnv模式保留其项目绑定。'
    print -r -- '5、系统模式仅让本流程和后续下载入口使用选定SDK，不删除原FVM/.java-version，不改全局PATH或系统代理。'
    print -r -- '6、插件解析会执行项目Gradle脚本；Pub按锁文件正常解析，不运行pub upgrade。已完成的安装/阶段不会因后续取消自动撤销。'
    print -r -- '7、日志和原配置快照在系统临时目录JobsFlutterEnvironment.*；Enter选择，←返回上一层，Esc/Ctrl+C取消。--check只读盘点。'
    print -r -- '8、默认完整流程还会按目标准备Android或Xcode/Pods、选择设备/启动配置，可实际构建安装验证。许可、首次组件、账号和签名由本人完成；--sdk-only仅执行SDK/依赖子流程。'
    print -r -- '9、外部工具日志原样展示并保留在私有运行目录，审计日志另行脱敏；分享原始日志前请自行检查凭据和业务信息。'
    while (( $# )); do
        case "$1" in
            --project) (( $# >= 2 )) && [[ -z "$SF_PROJECT" ]] || exit 2; SF_PROJECT="$2"; shift 2 ;;
            --check) SF_CHECK=1; shift ;;
            --sdk-only) SF_SDK_ONLY=1; shift ;;
            *) print -u2 '用法：SetupFlutterProject.zsh --project <Flutter项目绝对路径> [--check]'; exit 2 ;;
        esac
    done
    [[ "$SF_PROJECT" == /* && -d "$SF_PROJECT" && ! -L "${SF_PROJECT%/}" ]] || exit 2
    (( SF_CHECK )) && return 0
    [[ -t 0 && -t 1 ]] || { print -u2 '✖ 请在可交互终端中运行。'; exit 2; }
    IFS= read -r 'answer?👉 已了解用途与影响，按回车继续；其它输入取消：' || exit 130
    [[ -z "$answer" ]] || exit 130
}
# 自述之后加载定义；本脚本调用共享函数时不重复进入独立脚本入口。
sf_initialize() {
    source "${${(%):-%x}:A:h}/ProjectEnvironment.zsh" || return $?
    source "$PE_TOOLS_DIR/ManageProjectJava.zsh" || return $?
    source "$PE_TOOLS_DIR/DownloadProjectGradle.zsh" || return $?
    source "$PE_TOOLS_DIR/WrapperDistributionCache.zsh" || return $?
    source "$PE_TOOLS_DIR/SetupFlutterRun.zsh" || return $?
    source "$PE_TOOLS_DIR/SetupHomebrew.zsh" || return $?
    source "$PE_TOOLS_DIR/ProjectDependencies.zsh" || return $?
    pe_validate_project "$SF_PROJECT" || { pe_log '✖ 目标不是普通Flutter项目根目录。'; return 2; }
    SF_PROJECT="$PE_PROJECT" DG_PROJECT="$PE_PROJECT"
    PJ_PROJECT="$PE_PROJECT"
    if [[ ! -e "$SF_PROJECT/android" && ! -L "$SF_PROJECT/android" ]]; then
        SF_HAS_ANDROID=0
        DG_VERSION='不适用（无Android平台）'
    fi
    if (( SF_SDK_ONLY && SF_HAS_ANDROID )); then dg_read_wrapper && pj_check_gradle_criteria || return $?; fi
    SF_ENV_STAMP="$(sf_file_stamp "$SF_PROJECT/.jobs/flutter-environment.json")" || return 1
    SF_LOCAL_STAMP="$(sf_file_stamp "$SF_PROJECT/android/local.properties")" || return 1
    (( ! SF_CHECK )) || { pe_log "➤ 只读盘点：Flutter项目 $SF_PROJECT；固定Gradle $DG_VERSION；未安装、联网、写配置或验证SDK运行健康。"; return 0; }
    pe_initialize_runtime && pe_ensure_fzf
}
# 对配置内容与身份建立并发核验，不覆盖链接、特殊文件或硬链接。
sf_file_stamp() {
    local item="$1"
    [[ ! -L "${item:h}" && ! -L "$item" ]] || return 1
    [[ -e "$item" ]] || { print absent; return 0; }
    [[ -f "$item" && "$(/usr/bin/stat -f %l "$item")" == 1 && "$(/usr/bin/stat -f %z "$item")" -le 65536 ]] || return 1
    /usr/bin/stat -f '%d:%i:%l:%m:%c:%z' "$item" || return 1
    /usr/bin/shasum -a 256 "$item"
}
# 按真实上层导航选择来源和网络，任何取消都不运行SDK变更。
sf_choose_modes() {
    local step=1 result=0
    while true; do
        result=0
        case "$step" in
            1)
                pe_select Flutter $'fvm\tFVM项目SDK（推荐）\nsystem\t系统Flutter / 指定本机SDK（不使用FVM）' || result=$?
                (( result != 10 )) || return 130
                (( result == 0 )) || return "$result"
                SF_FLUTTER_MODE="$PE_SELECTION"; step=2 ;;
            2)
                pe_select Java $'jenv\tjEnv项目JDK（推荐）\nsystem\t系统Java / 指定本机JDK（不使用jEnv）' || result=$?
                if (( result == 10 )); then step=1; continue; fi
                (( result == 0 )) || return "$result"
                SF_JAVA_MODE="$PE_SELECTION"; step=3 ;;
            3)
                pe_select '下载线路' $'official\t项目/官方来源（默认）\naliyun\t腾讯Gradle镜像 + 阿里云Maven备用源（本次进程）' || result=$?
                if (( result == 10 )); then step=2; continue; fi
                (( result == 0 )) || return "$result"
                SF_MIRROR="$PE_SELECTION"; return 0 ;;
        esac
    done
}
# 健康检查所选Flutter与同套Dart，不能把只有PATH命令视为完整SDK。
sf_probe_flutter() {
    local binary="$1" version="" dart_version=""
    [[ "$binary" == /* && -x "$binary" ]] || return 1
    SF_FLUTTER="${binary:A}" SF_FLUTTER_ROOT="${${binary:A}:h:h}"
    [[ -x "$SF_FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" ]] || { pe_log '✖ Flutter缺少同套Dart runtime。'; return 1; }
    SF_COMMAND_TIMEOUT=60 sf_run_diagnostic flutter-version "$SF_FLUTTER" --version --machine || return $?
    version="$(/usr/bin/plutil -extract frameworkVersion raw -o - "$PE_RUN_DIR/flutter-version.log" 2>/dev/null)" || return 1
    [[ -n "$version" ]] || return 1
    SF_COMMAND_TIMEOUT=30 sf_run_diagnostic dart-version "$SF_FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" --version || return $?
    dart_version="$(/usr/bin/plutil -extract dartSdkVersion raw -o - "$PE_RUN_DIR/flutter-version.log" 2>/dev/null)"
    [[ -n "$dart_version" ]] || dart_version="$(pe_semantic_version "$PE_RUN_DIR/dart-version.log" dart)"
    SF_FLUTTER_VERSION="$version" SF_DART_VERSION="$dart_version"
    pe_event flutter.sdk flutter 'Flutter与Dart SDK' succeeded "$SF_FLUTTER" "Flutter $version${dart_version:+ · Dart $dart_version}"
    pe_event flutter '' 'Flutter SDK' running "$SF_FLUTTER" "Flutter $version${dart_version:+ · Dart $dart_version}"
    pe_log "✔ 实际Flutter：$version · $SF_FLUTTER"
}
# 系统Flutter从PATH、用户指定路径或已确认Homebrew安装取得，不运行全局切换命令。
sf_prepare_system_flutter() {
    local rows=$'path\t复用PATH中的Flutter\nmanual\t选择已有Flutter SDK绝对路径\ninstall\t通过Homebrew安装Flutter' result=0 target="" brew=""
    while true; do
        result=0; pe_select '系统Flutter' "$rows" || result=$?
        (( result == 0 )) || return "$result"
        case "$PE_SELECTION" in
            path) target="$(whence -p flutter 2>/dev/null)" ;;
            manual)
                IFS= read -r 'target?Flutter SDK根目录（绝对路径；空输入取消）：' || return 130
                [[ -n "$target" ]] || return 130
                target="$target/bin/flutter" ;;
            install)
                pj_find_brew || return $?
                brew="$PJ_BREW"
                pe_log '📥 来源：https://formulae.brew.sh/cask/flutter；目标：本机Homebrew Cask安装目录。'
                IFS= read -r 'target?输入任意字符安装Flutter；回车取消：' || return 130
                [[ -n "$target" ]] || return 130
                pe_run_logged /usr/bin/env HOMEBREW_NO_AUTO_UPDATE=1 "$brew" install --cask flutter || return $?
                target="$PJ_BREW_PREFIX/bin/flutter" ;;
        esac
        [[ -n "$target" && "${target:A}" != "$SF_PROJECT/.fvm/"* ]] || { pe_log '✖ PATH未提供独立系统Flutter，请选择已有SDK路径或安装。'; continue; }
        sf_probe_flutter "$target" && return 0
        pe_log '✖ 此Flutter不可用，请重新选择；已完成安装不会自动撤销。'
    done
}
# FVM优先复用项目SDK，也提供现有完整安装/切换工具。
sf_prepare_flutter() {
    local result=0 rows=""
    if [[ "$SF_FLUTTER_MODE" == system ]]; then sf_prepare_system_flutter; return $?; fi
    rows=$'configure\t安装/切换FVM项目Flutter SDK'
    [[ ! -x "$SF_PROJECT/.fvm/flutter_sdk/bin/flutter" ]] || rows=$'reuse\t复用当前FVM项目SDK\n'"$rows"
    pe_select 'FVM SDK' "$rows" || return $?
    if [[ "$PE_SELECTION" == configure ]]; then
        if [[ "$SR_TARGET" == ohos ]]; then
            /bin/zsh "$PE_TOOLS_DIR/ManageHarmonyFlutterVersion.zsh" --project "$SF_PROJECT" || return $?
        else
            JOBS_FLUTTER_VERSION_CHAINED=1 /bin/zsh "$PE_TOOLS_DIR/ManageFlutterVersion.zsh" --project "$SF_PROJECT" || return $?
        fi
    fi
    sf_probe_flutter "$SF_PROJECT/.fvm/flutter_sdk/bin/flutter" || { pe_log '✖ FVM项目SDK检查失败，停止后续步骤。'; return 1; }
    sf_report_fvm_version
}
# FVM模式只报告实际可执行管理器版本；健康缓存不要求凭空推定FVM版本。
sf_report_fvm_version() {
    local candidate=""
    for candidate in "${JOBS_FVM_BIN:-}" "$(command -v fvm 2>/dev/null)" "$HOME/.pub-cache/bin/fvm" "$HOME/.local/bin/fvm" /opt/homebrew/bin/fvm /usr/local/bin/fvm; do
        [[ -n "$candidate" && -x "$candidate" ]] || continue
        if SF_COMMAND_TIMEOUT=60 sf_run_diagnostic fvm-version "$candidate" --version; then
            SF_FVM_VERSION="$(pe_semantic_version "$PE_RUN_DIR/fvm-version.log" fvm)"
            if [[ -n "$SF_FVM_VERSION" ]]; then
                pe_event flutter.fvm flutter 'FVM版本管理' succeeded "$candidate" "FVM $SF_FVM_VERSION"
                return 0
            fi
        fi
    done
    pe_event flutter.fvm flutter 'FVM版本管理' attention '项目SDK缓存可用，未读取到可执行FVM的实际版本'
}
# 用fzf选择健康本机JDK或指定主版本；列表仅来自实际java/javac双校验。
sf_choose_java() {
    local rows="" index=0 requested="" candidate="" result=0
    (( ! SF_NEEDS_GRADLE )) || pj_check_gradle_criteria || return $?
    if [[ "$SF_JAVA_MODE" == jenv ]]; then pj_read_config || return $?; else PJ_CONFIG=""; fi
    pj_discover_jdks || return $?
    if [[ "$SF_JAVA_MODE" == system ]]; then
        candidate="${JAVA_HOME:-}"
        [[ -n "$candidate" ]] || candidate="$(/usr/libexec/java_home 2>/dev/null)"
        if pj_probe_jdk "$candidate"; then rows=$'current\t复用当前系统JDK · '"$PJ_JAVA_VERSION · $PJ_JAVA_HOME"; fi
    elif pj_resolve_config; then
        rows=$'current\t复用当前项目Java · '"$PJ_JAVA_VERSION · $PJ_JAVA_HOME"
    fi
    for (( index=1; index<=${#PJ_HOMES}; index++ )); do
        [[ -z "$rows" ]] || rows+=$'\n'
        rows+="${index}"$'\t'"Java ${PJ_VERSIONS[index]} · ${PJ_HOMES[index]}"
    done
    [[ -z "$rows" ]] || rows+=$'\n'
    rows+=$'install\t安装/复用指定Java主版本（Homebrew）\nmanual\t使用已有JDK绝对路径'
    pe_select JDK "$rows" || return $?
    case "$PE_SELECTION" in
        current)
            if [[ "$SF_JAVA_MODE" == jenv ]]; then pj_resolve_config || return 1;
            else pj_probe_jdk "$candidate" || return 1; fi
            PJ_SELECTED_HOME="$PJ_JAVA_HOME" PJ_SELECTED_MAJOR="$PJ_JAVA_MAJOR" ;;
        manual)
            IFS= read -r 'candidate?JDK根目录（绝对路径；空输入取消）：' || return 130
            [[ -n "$candidate" ]] || return 130
            pj_probe_jdk "$candidate" || { pe_log '✖ 此目录不是可用JDK。'; return 1; }
            PJ_SELECTED_HOME="$PJ_JAVA_HOME" PJ_SELECTED_MAJOR="$PJ_JAVA_MAJOR" ;;
        install)
            IFS= read -r "requested?Java主版本（回车$(pj_default_major)；q取消）：" || return 130
            [[ "$requested" != [qQ] ]] || return 130
            [[ -n "$requested" ]] || requested="$(pj_default_major)"
            [[ "$requested" == <-> && ${#requested} -le 2 && "$requested" -ge 8 && "$requested" -le 99 ]] || return 2
            PJ_SELECTED_HOME="" PJ_SELECTED_MAJOR="$requested"
            for candidate in "${PJ_HOMES[@]}"; do
                pj_probe_jdk "$candidate" || continue
                if [[ "$PJ_JAVA_MAJOR" == "$requested" ]]; then PJ_SELECTED_HOME="$PJ_JAVA_HOME"; break; fi
            done ;;
        *)
            [[ "$PE_SELECTION" == <-> && "$PE_SELECTION" -ge 1 && "$PE_SELECTION" -le ${#PJ_HOMES} ]] || return 2
            PJ_SELECTED_HOME="${PJ_HOMES[$PE_SELECTION]}"
            pj_probe_jdk "$PJ_SELECTED_HOME" || return 1
            PJ_SELECTED_MAJOR="$PJ_JAVA_MAJOR" ;;
    esac
}
# 确认后才安装/注册/绑定JDK；系统模式保留已有.java-version不写jEnv。
sf_apply_java() {
    local answer="" prefix="" result=0 binding_scope=gradle
    pe_log "➤ 选择Java $PJ_SELECTED_MAJOR · ${PJ_SELECTED_HOME:-待安装}；管理方式：$SF_JAVA_MODE"
    DG_JAVA_MAJOR="$PJ_SELECTED_MAJOR"
    (( ! SF_NEEDS_GRADLE )) || dg_check_java_compatibility || return $?
    IFS= read -r 'answer?按回车应用此Java选择；其它输入取消：' || return 130
    [[ -z "$answer" ]] || return 130
    PJ_RUN_DIR="$PE_RUN_DIR/java" PJ_LOG_FILE="$PE_LOG_FILE"
    /bin/mkdir "$PJ_RUN_DIR" || return 1
    if [[ "$SF_JAVA_MODE" == jenv ]]; then
        (( SF_NEEDS_GRADLE )) || binding_scope=sdk-only
        pj_ensure_dependencies && pj_register_jdk && pj_write_project_config "$binding_scope" || result=$?
        pj_cleanup_transaction
        (( result == 0 )) || return "$result"
    elif [[ -z "$PJ_SELECTED_HOME" ]]; then
        pj_find_brew && pj_brew_install "openjdk@$PJ_SELECTED_MAJOR" || return $?
        prefix="$(HOMEBREW_NO_AUTO_UPDATE=1 "$PJ_BREW" --prefix "openjdk@$PJ_SELECTED_MAJOR")" || return 1
        PJ_SELECTED_HOME="$prefix/libexec/openjdk.jdk/Contents/Home"
    fi
    pj_probe_jdk "$PJ_SELECTED_HOME" || return 1
    [[ "$PJ_JAVA_MAJOR" == "$PJ_SELECTED_MAJOR" ]] || return 1
    SF_JAVA_HOME="$PJ_JAVA_HOME" DG_JAVA_HOME="$PJ_JAVA_HOME" DG_JAVA_MAJOR="$PJ_JAVA_MAJOR"
    export JAVA_HOME="$SF_JAVA_HOME"
    export PATH="$SF_JAVA_HOME/bin:$PATH"
    pe_log "✔ 实际Java：$PJ_JAVA_VERSION · $SF_JAVA_HOME"
    pe_event java.jdk java 'Java SDK' succeeded "$SF_JAVA_HOME" "Java $PJ_JAVA_VERSION"
    if [[ "$SF_JAVA_MODE" == jenv && -x "$PJ_JENV" ]] && SF_COMMAND_TIMEOUT=30 sf_run_diagnostic jenv-version "$PJ_JENV" --version; then
        SF_JENV_VERSION="$(pe_semantic_version "$PE_RUN_DIR/jenv-version.log" jenv)"
        pe_event java.jenv java 'jEnv版本管理' succeeded "$PJ_JENV" "${SF_JENV_VERSION:+jEnv $SF_JENV_VERSION}"
    fi
    pe_event java '' 'Java SDK' running "$SF_JAVA_HOME" "Java $PJ_JAVA_VERSION${SF_JENV_VERSION:+ · jEnv $SF_JENV_VERSION}"
}
# 将模式记录和Flutter本机路径写到各自项目文件，先保存快照并复核并发。
sf_write_configuration() {
    local config="$SF_PROJECT/.jobs/flutter-environment.json" local_file="$SF_PROJECT/android/local.properties" staging=""
    [[ "$(sf_file_stamp "$config")" == "$SF_ENV_STAMP" && "$(sf_file_stamp "$local_file")" == "$SF_LOCAL_STAMP" ]] || { pe_log '✖ 配置在选择期间发生变化，请重跑，保留现有内容。'; return 1; }
    [[ ! -L "$SF_PROJECT/.jobs" ]] || return 1
    /bin/mkdir -p "$SF_PROJECT/.jobs" "$PE_RUN_DIR/before" || return 1
    [[ ! -f "$config" ]] || /bin/cp -p "$config" "$PE_RUN_DIR/before/flutter-environment.json" || return 1
    [[ ! -f "$local_file" ]] || /bin/cp -p "$local_file" "$PE_RUN_DIR/before/local.properties" || return 1
    staging="$(/usr/bin/mktemp "$SF_PROJECT/.jobs/environment.XXXXXX")" || return 1
    /usr/bin/osascript -l JavaScript - "$SF_FLUTTER_MODE" "$SF_FLUTTER" "$SF_JAVA_MODE" "$SF_JAVA_HOME" > "$staging" <<'JXA'
function run(argv) { return JSON.stringify({Platform:'MacOS', FlutterMode:argv[0], FlutterPath:argv[1], JavaMode:argv[2], JavaHome:argv[3]}, null, 2); }
JXA
    [[ $? == 0 ]] && /usr/bin/plutil -convert xml1 -o /dev/null "$staging" >/dev/null || return 1
    [[ "$(sf_file_stamp "$config")" == "$SF_ENV_STAMP" ]] || return 1
    /bin/mv -f "$staging" "$config" || return 1
    (( SF_HAS_ANDROID )) || { pe_log '✔ 已保存项目环境记录；此工程无Android平台，Gradle阶段不适用。'; return 0; }
    staging="$(/usr/bin/mktemp "$SF_PROJECT/android/.local.properties.XXXXXX")" || return 1
    if [[ -f "$local_file" ]]; then
        SF_SDK_ROOT="$SF_FLUTTER_ROOT" /usr/bin/perl -0777 -e 'local $/; $_=<>; s/^\s*flutter\.sdk\s*[=:].*(?:\r?\n|$)//mg; print; print "\n" if length && !/\n\z/; $v=$ENV{SF_SDK_ROOT}; $v =~ s/([\\:=#!])/\\$1/g; $v =~ s/ /\\ /g; print "flutter.sdk=$v\n";' "$local_file" > "$staging" || return 1
    else
        SF_SDK_ROOT="$SF_FLUTTER_ROOT" /usr/bin/perl -e '$v=$ENV{SF_SDK_ROOT}; $v =~ s/([\\:=#!])/\\$1/g; $v =~ s/ /\\ /g; print "flutter.sdk=$v\n";' > "$staging" || return 1
    fi
    [[ "$(sf_file_stamp "$local_file")" == "$SF_LOCAL_STAMP" ]] || return 1
    /bin/mv -f "$staging" "$local_file" || return 1
    pe_log '✔ 已保存项目环境记录与android/local.properties；后续Gradle下载复用此JDK。'
}
# 用户确认的SDK作用于直接Flutter进程；不走其它动作的FVM专用门禁。
sf_fetch_dependencies() {
    local attempt=0 result=0 seconds="${JOBS_PUB_GET_TIMEOUT:-900}"
    [[ "$seconds" == <-> && "$seconds" -ge 30 && "$seconds" -le 7200 ]] || { pe_log '✖ JOBS_PUB_GET_TIMEOUT须为30–7200秒。'; return 2; }
    pe_log "📥 Pub来源：项目pubspec.yaml/pubspec.lock与现有PUB_HOSTED_URL；Flutter：$SF_FLUTTER"
    for attempt in 1 2; do
        result=0
        SF_COMMAND_TIMEOUT="$seconds" sf_run_diagnostic pub "$SF_FLUTTER" pub get || result=$?
        if (( result == 0 )); then pe_log '✔ Flutter第三方依赖解析完成。'; return 0; fi
        (( result != 124 )) || return "$result"
        /usr/bin/grep -Eqi '401|403|Unauthorized|Forbidden|PKIX|certificate|authentication|permission denied|could not read Username' "$PE_RUN_DIR/pub.log" && break
        /usr/bin/grep -Eqi 'timed out|Connection reset|SocketException|UnknownHost|Network is unreachable|Temporary failure|Connection refused|Remote host terminated' "$PE_RUN_DIR/pub.log" || break
        pe_log '⚠ Pub网络异常，将使用原源重试一次，已完成的下载由Pub缓存复用。'
    done
    pe_log "✖ Pub依赖拉取失败（$result），已停止下游Gradle插件解析。"
    return "$result"
}
# 有界执行诊断，失败/超时保留日志且只停止本次诊断子树。
sf_run_diagnostic() {
    local name="$1" task_pid=0 timer_pid=0 result=0 seconds="${SF_COMMAND_TIMEOUT:-120}" raw_archive=""
    shift
    [[ "$name" =~ '^[A-Za-z0-9_.-]+$' && -d "$PE_RUN_DIR" && ! -L "$PE_RUN_DIR" ]] || return 2
    /bin/rm -f -- "$PE_RUN_DIR/$name.timeout" || return 1
    raw_archive="$(/usr/bin/mktemp "$PE_RUN_DIR/$name.raw.XXXXXX")" || return 1
    (
        cd -- "${SF_COMMAND_DIRECTORY:-$SF_PROJECT}" || exit 1
        "$@" 2>&1 | /usr/bin/tee "$PE_RUN_DIR/$name.log" "$raw_archive" >(pe_filter_log >> "$PE_LOG_FILE")
        exit ${pipestatus[1]}
    ) &
    task_pid=$!
    (
        trap 'exit 0' TERM INT HUP
        /bin/sleep "$seconds" || exit 0
        print timeout > "$PE_RUN_DIR/$name.timeout"
        dg_stop_timed_out_tree "$task_pid"
    ) &
    timer_pid=$!
    trap 'dg_terminate_tree "$task_pid"; dg_terminate_tree "$timer_pid"; exit 130' INT TERM HUP
    wait "$task_pid" || result=$?
    dg_terminate_tree "$timer_pid"
    wait "$timer_pid" 2>/dev/null || true
    trap - INT TERM HUP
    [[ ! -f "$PE_RUN_DIR/$name.timeout" ]] || { pe_log "✖ ${name}超过${seconds}秒，已停止本次进程。"; return 124; }
    return "$result"
}
# 汇总doctor和设备结果，区分环境准备与实际可运行，不接受许可证或启动应用。
sf_report_readiness() {
    local doctor_result=0 devices_result=0 detected_java="" issues=0 devices_count=""
    pe_log '➤ 收尾诊断：flutter doctor -v / devices --machine，各120秒；不自动接受Android许可，不构建或运行App。'
    sf_run_diagnostic doctor "$SF_FLUTTER" doctor -v || doctor_result=$?
    sf_run_diagnostic devices "$SF_FLUTTER" devices --machine || devices_result=$?
    if (( doctor_result != 0 )) || /usr/bin/grep -Eq '\[!\]|\[✗\]' "$PE_RUN_DIR/doctor.log"; then
        pe_log "⚠ Flutter doctor存在缺项或检查失败（退出码$doctor_result），请按上方诊断处理Android SDK/许可、Xcode/Pods等平台工具链。"
        issues=1
    fi
    detected_java="$(/usr/bin/perl -ne 'if (/Java binary at:\s*(.*?)\s*$/) { print $1; exit; }' "$PE_RUN_DIR/doctor.log")"
    if [[ -n "$detected_java" && "${detected_java:A}" != "${SF_JAVA_HOME:A}/bin/java" ]]; then
        pe_log "⚠ Flutter自身实际Java为$detected_java，与所选$SF_JAVA_HOME/bin/java不同；本脚本Gradle help已显式绑定所选JDK，IDE/后续flutter build请核对Gradle JVM。"
        issues=1
    fi
    if (( devices_result != 0 )); then
        pe_log "⚠ 设备诊断失败（$devices_result），设备运行尚未验证。"; issues=1
    else
        devices_count="$(/usr/bin/plutil -extract 0.id raw -o - "$PE_RUN_DIR/devices.log" 2>/dev/null)"
        if [[ -z "$devices_count" ]]; then pe_log '⚠ 未发现可运行设备；请启动模拟器/连接设备并检查授权。'; issues=1; fi
    fi
    pe_log '➤ 环境准备已完成；实际运行还需要匹配项目支持的平台、flavor/入口、私有仓库权限、iOS签名与设备。未执行flutter run，不能据此确认App已经可运行。'
    pe_log '➤ 系统模式的选择作用于本流程及“下载Gradle插件”入口；其它原有运行/打包菜单仍遵循其FVM/jEnv规则，原终端与IDE环境未切换。'
    pe_log "➤ 在当前项目终端使用所选SDK：JAVA_HOME=${(q)SF_JAVA_HOME} PATH=${(q)SF_JAVA_HOME}/bin:\$PATH ${(q)SF_FLUTTER} run（先按项目要求补充flavor/入口/设备参数）。"
    if (( issues )); then pe_log "⚠ 收尾检查未完全通过；日志：$PE_RUN_DIR；保留已完成配置，解决缺项后重试。"; return 3; fi
    pe_log '✔ doctor和设备检查通过；尚未实际构建/启动App。'
}
# 阶段封装为GUI里程碑，失败保留真实退出码且标明等待本人处理或失败。
sf_step() {
    local identifier="$1" parent="$2" title="$3" result=0 event_state=failed
    shift 3
    pe_event "$identifier" "$parent" "$title" running
    "$@" || result=$?
    if (( result == 0 )); then pe_event "$identifier" "$parent" "$title" succeeded;
    else
        (( result != 3 && result != 10 && result != 130 )) || event_state=attention
        sr_note_failure "$result"
        pe_event "$identifier" "$parent" "$title" "$event_state" "退出码$result；详见下方原始日志"
    fi
    return "$result"
}
# 非Android只验证所选JDK健康，不让同仓Android daemon criteria干扰其它平台。
sf_resolve_selected_java() {
    if (( SF_NEEDS_GRADLE )); then dg_resolve_java; return $?; fi
    pj_probe_jdk "$SF_JAVA_HOME" || return $?
    DG_JAVA_HOME="$PJ_JAVA_HOME" DG_JAVA_MAJOR="$PJ_JAVA_MAJOR"
}
# 目标先于SDK选择确定，非Android目标不受同仓Android Wrapper故障阻断。
sf_plan_target() {
    if (( SF_SDK_ONLY )); then
        SF_NEEDS_GRADLE="$SF_HAS_ANDROID"
        SR_TARGET='sdk-only'
    else
        sr_choose_target || return $?
        SF_NEEDS_GRADLE=0
        if [[ "$SR_TARGET" == android ]]; then SF_NEEDS_GRADLE=1; dg_read_wrapper && pj_check_gradle_criteria || return $?;
        else DG_VERSION='不适用（目标非Android）'; fi
    fi
}
# 按目标复用平台模块；所有安装/许可提示继续由原终端交互承接。
sf_prepare_platform() {
    (( ! SF_SDK_ONLY )) || return 0
    case "$SR_TARGET" in
        android)
            source "$PE_TOOLS_DIR/SetupFlutterPlatform.zsh" || return $?
            sf_platform_android "$SF_PROJECT" "$SF_FLUTTER" "$SF_JAVA_HOME" || return $? ;;
        ios|macos) sr_prepare_apple_platform || return $? ;;
        web) sr_prepare_web || return $? ;;
        ohos)
            SF_COMMAND_TIMEOUT=60 sf_run_diagnostic ohos-sdk "$SF_FLUTTER" build hap --help || return $?
            command -v ohpm >/dev/null && command -v hdc >/dev/null || { pe_log '✖ 请先准备 DevEco / OpenHarmony SDK、OHPM 与 HDC；官方 Flutter 不支持鸿蒙目标，不能改用官方 SDK 冒充。'; return 3; }
            ;;
    esac
    sr_precache_target
}
# 按选择顺序执行，每阶段失败立即停止，成功边界包括最终插件预热。
sf_run_requested() {
    local result=0 readiness_result=0
    sf_initialize || return $?
    (( ! SF_CHECK )) || return 0
    sf_plan_target || return $?
    sf_choose_modes || return $?
    while true; do
        result=0; sf_step flutter '' 'Flutter SDK' sf_prepare_flutter || result=$?
        if (( result == 10 )); then sf_choose_modes || return $?; continue; fi
        (( result == 0 )) || return "$result"
        result=0; sf_step java.discovery java '选择Java SDK' sf_choose_java || result=$?
        if (( result == 10 )); then continue; fi
        (( result == 0 )) || return "$result"
        break
    done
    sf_step java '' 'Java SDK' sf_apply_java && sf_resolve_selected_java && sf_step flutter.configuration flutter '保存项目环境' sf_write_configuration || return $?
    sf_step platforms '' '平台工具链' sf_prepare_platform || return $?
    DG_MIRROR="$SF_MIRROR"
    DG_TIMEOUT="${JOBS_GRADLE_TASK_TIMEOUT:-900}" DG_DOWNLOAD_TIMEOUT="${JOBS_GRADLE_DOWNLOAD_TIMEOUT:-300}"
    [[ "$DG_TIMEOUT" == <-> && "$DG_TIMEOUT" -ge 30 && "$DG_TIMEOUT" -le 7200 && "$DG_DOWNLOAD_TIMEOUT" == <-> && "$DG_DOWNLOAD_TIMEOUT" -ge 10 && "$DG_DOWNLOAD_TIMEOUT" -le 1800 ]] || { pe_log '✖ Gradle超时配置无效。'; return 2; }
    if (( SF_NEEDS_GRADLE )); then
        sf_step gradle.distribution gradle '下载并验证Gradle分发' dg_download_distribution && sf_step gradle.wrapper gradle '验证项目Wrapper缓存复用' dg_extract_distribution || return $?
    else pe_event gradle '' 'Gradle' succeeded '目标不适用，已跳过Gradle准备'; fi
    if (( SF_NEEDS_GRADLE )); then pe_event gradle '' 'Gradle分发' succeeded '分发包和实际Wrapper缓存复用验证通过'; fi
    sf_step pub.flutter pub 'Flutter第三方依赖' sf_fetch_dependencies || return $?
    (( ! SF_NEEDS_GRADLE )) || sf_step gradle.plugins gradle '解析AGP与构建插件' dg_warm_plugins || return $?
    (( SF_SDK_ONLY )) || sf_step "platforms.$SR_TARGET.native-dependencies" "platforms.$SR_TARGET" '目标平台依赖与原生库' pd_run_target_dependencies || return $?
    pe_event pub '' '依赖与插件' succeeded 'Pub、目标原生依赖和所需构建插件均已完成'
    pe_log "✔ SDK和目标所需依赖准备完成：$SF_FLUTTER_MODE Flutter、$SF_JAVA_MODE Java；Gradle：$DG_VERSION；不适用阶段已明确跳过。"
    sf_step readiness.doctor readiness '收尾诊断' sf_report_readiness || readiness_result=$?
    if (( SF_SDK_ONLY )); then return "$readiness_result"; fi
    sf_step readiness '' '运行验证' sr_offer_run
}
# 入口只编排自述与实际流程，source时保持无副作用。
main() {
    sf_intro_and_wait "$@" # 先展示完整影响与取消方式，再确认继续。
    sf_run_requested # 选择SDK来源、准备环境、下载依赖并验证插件解析。
}

if [[ "$ZSH_EVAL_CONTEXT" == toplevel ]]; then
    main "$@"
fi
