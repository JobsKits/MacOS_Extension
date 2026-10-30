#!/bin/zsh
# 脚本自述：
# - 脚本名称：DownloadProjectGradle.zsh。
# - 核心用途：按项目固定 Wrapper 版本及所选 Java 校验、下载 Gradle 并预热构建插件。
# - 影响范围：用户 Gradle 缓存、普通构建配置缓存与项目脚本执行；不改 Wrapper、AGP 或系统代理。
# - 运行提示：自述回车后 fzf 选官方 / 镜像，Ctrl+C / Esc 取消；--check 只读不联网；source 只定义函数。

typeset -g DG_PROJECT="" DG_JAVA_HOME="" DG_CHECK=0 DG_DISTRIBUTION_ONLY=0 DG_MIRROR=official
typeset -g DG_VERSION="" DG_TYPE="" DG_URL="" DG_SHA="" DG_CURL="" DG_GRADLE="" DG_CACHE="" DG_LOCK=""
typeset -g DG_WRAPPER_STAMP="" DG_TIMEOUT=900 DG_DOWNLOAD_TIMEOUT=300 DG_JAVA_MAJOR=""
# 静态读取工程中直接声明的AGP版本，动态变量不猜测、不执行Gradle配置。
dg_detect_agp_version() {
    setopt localoptions NO_NOMATCH
    local file="" versions=""
    local -a files
    for file in "$DG_PROJECT"/android/{settings,build}.gradle{,.kts}(N); do
        [[ -f "$file" && ! -L "$file" && "$(/usr/bin/stat -f %z "$file")" -le 1048576 ]] && files+=("$file")
    done
    (( ${#files} )) || return 0
    /usr/bin/perl -0777 -ne 's{/\*.*?\*/}{}gs; s{^\s*//.*$}{}mg; while (/\bid\s*(?:\(\s*)?["\x27]com\.android\.(?:application|library)["\x27]\s*\)?\s*version\s*["\x27]([0-9]+(?:\.[0-9]+)+(?:[-+][0-9A-Za-z.-]+)?)["\x27]/g) { $seen{$1}=1; } while (/com\.android\.tools\.build:gradle:([0-9]+(?:\.[0-9]+)+(?:[-+][0-9A-Za-z.-]+)?)/g) { $seen{$1}=1; } END { print join(" / ",sort keys %seen); }' "${files[@]}"
}
# 将已校验的固定分发版本发送给可见节点，不把配置版本当作AGP检测结果。
dg_report_distribution_version() {
    pe_event gradle.distribution gradle '下载并验证Gradle分发' succeeded '已验证ZIP SHA256' "Gradle $DG_VERSION"
}
# 第一屏自述同时解释插件解析会执行项目构建脚本。
dg_intro_and_wait() {
    local answer=""
    print -r -- '━━━━━━━━━━ DownloadProjectGradle.zsh｜下载 Gradle 插件 ━━━━━━━━━━'
    print -r -- '1、读取项目 Wrapper 固定版本与环境配置，按实际 Java 做兼容检查；不会自动升级 Gradle / AGP。'
    print -r -- '2、下载包先校验 SHA256；官方备用线路、有界重试和断点续传；可选镜像仅限本次进程。'
    print -r -- '3、在 android 执行 Gradle help 解析 AGP / Kotlin 等构建插件，会执行该项目构建脚本并写正常缓存；不编译 App。'
    print -r -- '4、日志与快照位于系统临时目录 JobsFlutterEnvironment.*；分发缓存位于用户 Library/Caches/JobsFlutterTools。'
    print -r -- '5、--check 只读不联网；常规运行回车继续，Ctrl+C / Esc 取消，不修改系统代理或全局仓库。'
    dg_parse "$@" || { print -u2 '用法：DownloadProjectGradle.zsh --project <绝对路径> [--java-home <JDK>] [--check] [--distribution-only]'; exit 2; }
    (( DG_CHECK )) && return 0
    [[ -t 0 && -t 1 ]] || { print -u2 '✖ 需要可交互终端。'; exit 2; }
    IFS= read -r 'answer?👉 已了解用途与影响，按回车继续；其它输入取消：' || exit 130
    [[ -z "$answer" ]] || exit 130
}
# 参数严格限定为数据，不接受额外 Gradle 命令。
dg_parse() {
    DG_PROJECT="" DG_JAVA_HOME="" DG_CHECK=0 DG_DISTRIBUTION_ONLY=0
    while (( $# )); do
        case "$1" in
            --project) (( $# >= 2 )) && [[ -z "$DG_PROJECT" ]] || return 2; DG_PROJECT="$2"; shift 2 ;;
            --java-home) (( $# >= 2 )) && [[ -z "$DG_JAVA_HOME" ]] || return 2; DG_JAVA_HOME="$2"; shift 2 ;;
            --check) DG_CHECK=1; shift ;;
            --distribution-only) DG_DISTRIBUTION_ONLY=1; shift ;;
            *) return 2 ;;
        esac
    done
    [[ "$DG_PROJECT" == /* && -d "$DG_PROJECT" && ! -L "${DG_PROJECT%/}" ]]
}
# 加载无入口的共享定义，检查和 source 模式均不创建日志。
dg_initialize() {
    source "${${(%):-%x}:A:h}/ProjectEnvironment.zsh" || return $?
    source "$PE_TOOLS_DIR/ManageProjectJava.zsh" || return $?
    source "$PE_TOOLS_DIR/WrapperDistributionCache.zsh" || return $?
    pe_validate_project "$DG_PROJECT" || { pe_log '✖ 请选择普通 Flutter 项目根目录。'; return 2; }
    DG_PROJECT="$PE_PROJECT"
    DG_TIMEOUT="${JOBS_GRADLE_TASK_TIMEOUT:-900}"
    DG_DOWNLOAD_TIMEOUT="${JOBS_GRADLE_DOWNLOAD_TIMEOUT:-300}"
    [[ "$DG_TIMEOUT" == <-> && "$DG_TIMEOUT" -ge 30 && "$DG_TIMEOUT" -le 7200 && "$DG_DOWNLOAD_TIMEOUT" == <-> && "$DG_DOWNLOAD_TIMEOUT" -ge 10 && "$DG_DOWNLOAD_TIMEOUT" -le 1800 ]] || { pe_log '✖ Gradle超时配置无效：任务30–7200秒，单次下载10–1800秒。'; return 2; }
}
# 只读解析标准固定发行版属性，拒绝未知格式、重复键和动态版本。
dg_read_wrapper() {
    local wrapper="$DG_PROJECT/android/gradle/wrapper/gradle-wrapper.properties" rows="" file_name=""
    [[ -d "$DG_PROJECT/android" && ! -L "$DG_PROJECT/android" && ! -L "$DG_PROJECT/android/gradle" && ! -L "$DG_PROJECT/android/gradle/wrapper" && -f "$wrapper" && ! -L "$wrapper" ]] || { pe_log '✖ 缺少普通 Android Gradle Wrapper 项目；不生成或升级平台文件。'; return 1; }
    [[ "$(/usr/bin/stat -f %z "$wrapper")" -le 65536 ]] || return 1
    rows="$(/usr/bin/perl -ne 's/\r?\n$//; next if /^\s*[#!]/; if (/^\s*(distributionUrl|distributionSha256Sum)\s*[=:]\s*(.*?)\s*$/) { $k=$1; $v=$2; die "duplicate key\n" if $seen{$k}++; $v =~ s/\\:/:/g; print "$k\t$v\n"; }' "$wrapper")" || return 1
    DG_URL="$(print -r -- "$rows" | /usr/bin/awk -F '\t' '$1=="distributionUrl" {print $2}')"
    DG_SHA="$(print -r -- "$rows" | /usr/bin/awk -F '\t' '$1=="distributionSha256Sum" {print tolower($2)}')"
    [[ "$DG_URL" =~ '^https://[A-Za-z0-9.-]+(:[0-9]+)?/[A-Za-z0-9._~/%+-]+$' ]] || { pe_log '✖ Wrapper URL须为无凭据/查询参数的HTTPS固定发行包。'; return 1; }
    file_name="${DG_URL:t}"
    [[ "$file_name" =~ '^gradle-([0-9]+\.[0-9]+(\.[0-9]+)?)-(bin|all)\.zip$' ]] || { pe_log '✖ 只支持固定正式 Gradle x.y[.z]-bin/all.zip；动态或预览版本请人工核实。'; return 1; }
    DG_VERSION="$match[1]" DG_TYPE="$match[3]"
    [[ -z "$DG_SHA" || "$DG_SHA" =~ '^[0-9a-f]{64}$' ]] || { pe_log '✖ distributionSha256Sum无效。'; return 1; }
    DG_WRAPPER_STAMP="$(/usr/bin/shasum -a 256 "$wrapper")" || return 1
}
# 项目环境配置优先，其次 .java-version，最后当前系统 JDK；显式参数优先于全部。
dg_resolve_java() {
    local candidate="" configured=""
    PJ_PROJECT="$DG_PROJECT"
    pj_check_gradle_criteria || return $?
    if [[ -z "$DG_JAVA_HOME" ]]; then
        pe_read_environment || return $?
        if [[ -n "$PE_CONFIG_JAVA" ]]; then
            DG_JAVA_HOME="$PE_CONFIG_JAVA"
        elif [[ -e "$DG_PROJECT/.java-version" || -L "$DG_PROJECT/.java-version" ]]; then
            pj_read_config && pj_discover_jdks && pj_resolve_config || { pe_log '✖ 项目Java声明不可用，请先安装/切换或一键配置。'; return 1; }
            DG_JAVA_HOME="$PJ_JAVA_HOME"
        else
            candidate="${JAVA_HOME:-}"
            [[ -n "$candidate" ]] || candidate="$(/usr/libexec/java_home 2>/dev/null)"
            DG_JAVA_HOME="$candidate"
        fi
    fi
    pj_probe_jdk "$DG_JAVA_HOME" || { pe_log '✖ 选定JDK失效，必须同时有可用java和javac；请重新配置。'; return 1; }
    DG_JAVA_HOME="$PJ_JAVA_HOME" DG_JAVA_MAJOR="$PJ_JAVA_MAJOR"
    [[ "$DG_JAVA_HOME" != *[\"\\\$\`]* ]] && ! print -rn -- "$DG_JAVA_HOME" | /usr/bin/grep -q '[[:cntrl:]]' || { pe_log '✖ JDK路径含Gradle启动器无法安全处理的字符，请使用常规安装路径。'; return 1; }
    pe_log "➤ 实际JDK：Java $DG_JAVA_MAJOR · $DG_JAVA_HOME；固定Gradle：$DG_VERSION"
}
# 比较纯数字版本，不依赖本机包管理器或执行项目脚本。
dg_version_at_least() {
    local -a actual required
    local index=0
    actual=("${(@s:.:)1}") required=("${(@s:.:)2}")
    for index in 1 2 3; do
        (( ${actual[index]:-0} > ${required[index]:-0} )) && return 0
        (( ${actual[index]:-0} < ${required[index]:-0} )) && return 1
    done
    return 0
}
# 依据Gradle官方Java Runtime矩阵校验，不以编译toolchain版本代替运行版本。
dg_check_java_compatibility() {
    local minimum=""
    case "$DG_JAVA_MAJOR" in
        8) minimum=2.0 ;; 9) minimum=4.3 ;; 10) minimum=4.7 ;; 11) minimum=5.0 ;;
        12) minimum=5.4 ;; 13) minimum=6.0 ;; 14) minimum=6.3 ;; 15) minimum=6.7 ;;
        16) minimum=7.0 ;; 17) minimum=7.3 ;; 18) minimum=7.5 ;; 19) minimum=7.6 ;;
        20) minimum=8.3 ;; 21) minimum=8.5 ;; 22) minimum=8.8 ;; 23) minimum=8.10 ;;
        24) minimum=8.14 ;; 25) minimum=9.1 ;; 26) minimum=9.4 ;; 27) minimum=9.8 ;;
        *) pe_log '✖ 此Java运行版本不在已核实兼容矩阵内，请人工核对。'; return 1 ;;
    esac
    if ! dg_version_at_least "$DG_VERSION" "$minimum" || { (( DG_JAVA_MAJOR < 17 )) && dg_version_at_least "$DG_VERSION" 9.0; }; then
        pe_log "✖ Java $DG_JAVA_MAJOR 与 Gradle $DG_VERSION 不兼容；该Java最低Gradle $minimum，Gradle9+须Java17+。请重新选择Java，脚本不升级工程。"
        return 1
    fi
}
# 下载单次有界，只有同一来源的临时片段可续传，失败保留供后次重试。
dg_curl_download() {
    local url="$1" target="$2" seconds="$3" result=0 attempt=0
    local -a resume
    for attempt in 1 2; do
        resume=()
        [[ ! -s "$target" ]] || resume=(--continue-at -)
        pe_log "📥 来源：$url；目标：$target；尝试$attempt/2，连接10秒、单次${seconds}秒、低速30秒停止。"
        result=0
        pe_run_logged "$DG_CURL" --fail --location --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time "$seconds" --speed-time 30 --speed-limit 1024 "${resume[@]}" --output "$target" "$url" || result=$?
        (( result == 0 )) && return 0
        # 416/不支持Range时只丢弃本次受管片段，第二次从头下载。
        if (( result == 22 || result == 33 )); then /bin/rm -f -- "$target"; fi
    done
    return "$result"
}
# 采用Wrapper固定摘要，缺省仅从Gradle官方校验端点取摘要，镜像不能提供信任根。
dg_fetch_checksum() {
    local url="" output="$PE_RUN_DIR/gradle.sha256" value=""
    [[ -z "$DG_SHA" ]] || return 0
    for url in "https://services.gradle.org/distributions/gradle-$DG_VERSION-$DG_TYPE.zip.sha256" "https://downloads.gradle.org/distributions/gradle-$DG_VERSION-$DG_TYPE.zip.sha256"; do
        /bin/rm -f -- "$output"
        if dg_curl_download "$url" "$output" 30; then
            value="$(/usr/bin/tr -d '\r\n' < "$output")"
            if [[ "$value" =~ '^[0-9a-fA-F]{64}$' ]]; then DG_SHA="${value:l}"; return 0; fi
        fi
    done
    pe_log '✖ 无法取得Gradle官方SHA256；没有可信摘要不会解压或执行下载包。'
    return 1
}
# 对照SHA256验证普通ZIP，拒绝符号或硬链接缓存。
dg_verify_zip() {
    local archive="$1" value=""
    [[ -f "$archive" && ! -L "$archive" && "$(/usr/bin/stat -f %l "$archive")" == 1 ]] || return 1
    value="$(/usr/bin/shasum -a 256 "$archive")" || return 1
    [[ "${value%% *}" == "$DG_SHA" ]]
}
# 从项目源与官方备用源下载，选镜像时加入腾讯分发镜像；各源片段隔离。
dg_download_distribution() {
    local archive="" url="" key="" partial=""
    local -a urls
    DG_CURL="$(command -v curl 2>/dev/null)"
    [[ -x "$DG_CURL" ]] && "$DG_CURL" --version >/dev/null 2>&1 || { pe_log '✖ 缺少可用curl。'; return 1; }
    dg_fetch_checksum || return $?
    DG_CACHE="$HOME/Library/Caches/JobsFlutterTools/gradle/$DG_SHA"
    [[ ! -L "$HOME/Library/Caches/JobsFlutterTools" && ! -L "${DG_CACHE:h}" && ! -L "$DG_CACHE" ]] || { pe_log '✖ Gradle缓存目录是链接，请人工核实。'; return 1; }
    /bin/mkdir -p -- "$DG_CACHE" || return 1
    archive="$DG_CACHE/gradle-$DG_VERSION-$DG_TYPE.zip"
    if dg_verify_zip "$archive"; then pe_log "✔ 复用已校验分发包：$archive"; dg_report_distribution_version; return 0; fi
    [[ ! -e "$archive" && ! -L "$archive" ]] || { pe_log '✖ 已有缓存包摘要不匹配/身份异常，保留现场，请核实后移走再重试。'; return 1; }
    urls=("$DG_URL" "https://downloads.gradle.org/distributions/gradle-$DG_VERSION-$DG_TYPE.zip" "https://services.gradle.org/distributions/gradle-$DG_VERSION-$DG_TYPE.zip")
    [[ "$DG_MIRROR" != aliyun ]] || urls=("https://mirrors.cloud.tencent.com/gradle/gradle-$DG_VERSION-$DG_TYPE.zip" "${urls[@]}")
    for url in "${(@u)urls}"; do
        key="$(print -rn -- "$url" | /usr/bin/shasum -a 256)"; key="${key%% *}"
        partial="$DG_CACHE/${key[1,16]}.part"
        [[ ! -L "$partial" ]] || return 1
        if dg_curl_download "$url" "$partial" "$DG_DOWNLOAD_TIMEOUT"; then
            if dg_verify_zip "$partial"; then
                /bin/mv -n -- "$partial" "$archive" || return 1
                dg_verify_zip "$archive" || return 1
                pe_log "✔ SHA256通过，最终分发来源：$url"
                dg_report_distribution_version
                return 0
            fi
            pe_log "⚠ 来源包SHA256不匹配，未执行，保留片段供排查：$partial"
        fi
    done
    pe_log '✖ 所有分发源失败；保留同源下载片段，下次运行可继续。'
    return 1
}
# 解压前检查归档目录和链接类型，每次运行只执行本次已校验ZIP解出的分发。
dg_extract_distribution() {
    local archive="$DG_CACHE/gradle-$DG_VERSION-$DG_TYPE.zip" entries="" item="" root="gradle-$DG_VERSION"
    entries="$(/usr/bin/unzip -Z1 "$archive")" || return 1
    [[ -n "$entries" ]] || return 1
    while IFS= read -r item; do
        [[ "$item" == "$root/"* && "$item" != *\\* && "$item" != *'/../'* && "$item" != *'/./'* ]] || { pe_log '✖ ZIP目录结构异常，未解压。'; return 1; }
    done <<< "$entries"
    /usr/bin/unzip -Z -l "$archive" | /usr/bin/awk '$1 ~ /^l/ {bad=1} END {exit bad}' || { pe_log '✖ ZIP含符号链接，未解压。'; return 1; }
    /bin/mkdir "$PE_RUN_DIR/distribution" || return 1
    /usr/bin/ditto -x -k "$archive" "$PE_RUN_DIR/distribution" || return 1
    DG_GRADLE="$PE_RUN_DIR/distribution/$root/bin/gradle"
    [[ -x "$DG_GRADLE" && ! -L "$DG_GRADLE" ]] || return 1
    wd_prepare_zip "$DG_PROJECT" "$DG_URL" "$DG_SHA" "$archive" "$DG_JAVA_HOME" || return $?
    dg_verify_wrapper
}
# 所选Java有界启动项目实际Wrapper，确认固定版本能从本地缓存启动。
dg_verify_wrapper() {
    local task_pid=0 timer_pid=0 result=0 actual=""
    local -a launch
    if [[ -f "$DG_PROJECT/android/gradlew" && ! -L "$DG_PROJECT/android/gradlew" ]]; then
        launch=(/bin/sh "$DG_PROJECT/android/gradlew")
    else
        launch=("$DG_JAVA_HOME/bin/java" -classpath "$DG_PROJECT/android/gradle/wrapper/gradle-wrapper.jar" org.gradle.wrapper.GradleWrapperMain)
    fi
    (
        cd -- "$DG_PROJECT/android" || exit 1
        JAVA_HOME="$DG_JAVA_HOME" PATH="$DG_JAVA_HOME/bin:$PATH" "${launch[@]}" "-Dorg.gradle.java.home=$DG_JAVA_HOME" --no-daemon --console plain --version 2>&1 | /usr/bin/tee "$PE_RUN_DIR/wrapper-version.log" >(pe_filter_log >> "$PE_LOG_FILE")
        exit ${pipestatus[1]}
    ) &
    task_pid=$!
    (
        trap 'exit 0' TERM INT HUP
        /bin/sleep 60 || exit 0
        print timeout > "$PE_RUN_DIR/wrapper-version.timeout"
        dg_stop_timed_out_tree "$task_pid"
    ) &
    timer_pid=$!
    trap 'dg_terminate_tree "$task_pid"; dg_terminate_tree "$timer_pid"; exit 130' INT TERM HUP
    wait "$task_pid" || result=$?
    dg_terminate_tree "$timer_pid"
    wait "$timer_pid" 2>/dev/null || true
    trap - INT TERM HUP
    [[ ! -f "$PE_RUN_DIR/wrapper-version.timeout" ]] || { pe_log '✖ 项目Wrapper启动超过60秒，缓存复用未验证。'; return 124; }
    (( result == 0 )) || { pe_log "✖ 项目Wrapper版本验证失败（$result），未进入Pub或插件预热。"; return "$result"; }
    if /usr/bin/grep -Eqi '^Downloading https?://' "$PE_RUN_DIR/wrapper-version.log"; then
        pe_log '✖ 项目Wrapper仍触发网络分发下载，缓存复用验证未通过，请检查Wrapper自定义实现或缓存参数。'
        return 1
    fi
    actual="$(/usr/bin/perl -ne 'if (/^Gradle ([0-9]+\.[0-9]+(?:\.[0-9]+)?)\s*$/) { print $1; exit }' "$PE_RUN_DIR/wrapper-version.log")"
    [[ "$actual" == "$DG_VERSION" ]] || { pe_log "✖ 实际Wrapper版本${actual:-未知}与固定${DG_VERSION}不同。"; return 1; }
    pe_log "✔ 项目Wrapper以所选Java从本地缓存启动Gradle $actual；未发生额外分发下载。"
    pe_event gradle.wrapper gradle '验证项目Wrapper缓存复用' succeeded '实际Wrapper已启动且无额外分发下载' "Gradle $actual"
    pe_event gradle '' 'Gradle分发' succeeded '' "Gradle $actual"
}
# 镜像只写临时init脚本，保留官方后备，不改工程或用户仓库配置。
dg_write_mirror_init() {
    [[ "$DG_MIRROR" == aliyun ]] || return 0
    dg_version_at_least "$DG_VERSION" 6.0 || { pe_log '✖ 此旧Gradle不能使用当前临时镜像钩子，请选官方模式。'; return 1; }
    /bin/cat > "$PE_RUN_DIR/repositories.init.gradle" <<'GROOVY'
gradle.beforeSettings { s ->
    s.pluginManagement.repositories {
        maven { url 'https://maven.aliyun.com/repository/google' }
        maven { url 'https://maven.aliyun.com/repository/gradle-plugin' }
        maven { url 'https://maven.aliyun.com/repository/public' }
        google(); mavenCentral(); gradlePluginPortal()
    }
}
gradle.settingsEvaluated { s ->
    if (s.metaClass.hasProperty(s, 'dependencyResolutionManagement')) {
        s.dependencyResolutionManagement.repositories {
            maven { url 'https://maven.aliyun.com/repository/google' }
            maven { url 'https://maven.aliyun.com/repository/public' }
        }
    }
}
gradle.beforeProject { p ->
    p.buildscript.repositories {
        maven { url 'https://maven.aliyun.com/repository/google' }
        maven { url 'https://maven.aliyun.com/repository/public' }
    }
}
GROOVY
    pe_log '➤ 本次构建插件备用源：https://maven.aliyun.com/repository/{google,gradle-plugin,public}；腾讯Gradle镜像。退出后撤回临时源，不修改系统代理。'
}
# 有界等待任务，超时时递归终止本次子进程，不触碰其它Gradle或Java会话。
dg_terminate_tree() {
    local pid="$1" child=""
    for child in "${(@f)$(/usr/bin/pgrep -P "$pid" 2>/dev/null)}"; do
        [[ "$child" == <-> ]] || continue
        dg_terminate_tree "$child"
    done
    /bin/kill -TERM "$pid" 2>/dev/null || true
}
# 超时升级为KILL，先收集本次子树再发送信号，避免TERM无效导致永久等待。
dg_stop_timed_out_tree() {
    local root_pid="$1" item="" child="" index=1
    local -a targets
    targets=("$root_pid")
    while (( index <= ${#targets} )); do
        for child in "${(@f)$(/usr/bin/pgrep -P "${targets[index]}" 2>/dev/null)}"; do
            [[ "$child" == <-> ]] && targets+=("$child")
        done
        (( index++ ))
    done
    for item in "${targets[@]}"; do /bin/kill -TERM "$item" 2>/dev/null || true; done
    /bin/sleep 2
    for item in "${targets[@]}"; do /bin/kill -KILL "$item" 2>/dev/null || true; done
}
# 执行单次help并保留超时标记，标准日志在前台流式显示。
dg_run_help_once() {
    local task_pid=0 timer_pid=0 result=0
    local -a options
    options=(--no-daemon --console plain "-Dorg.gradle.java.home=$DG_JAVA_HOME" -Dorg.gradle.internal.http.connectionTimeout=15000 -Dorg.gradle.internal.http.socketTimeout=30000)
    [[ "$DG_MIRROR" != aliyun ]] || options+=(--init-script "$PE_RUN_DIR/repositories.init.gradle")
    (
        cd -- "$DG_PROJECT/android" || exit 1
        JAVA_HOME="$DG_JAVA_HOME" PATH="$DG_JAVA_HOME/bin:$PATH" "$DG_GRADLE" "${options[@]}" help 2>&1 | /usr/bin/tee "$PE_RUN_DIR/gradle-current.log" >(pe_filter_log >> "$PE_LOG_FILE")
        exit ${pipestatus[1]}
    ) &
    task_pid=$!
    (
        trap 'exit 0' TERM INT HUP
        /bin/sleep "$DG_TIMEOUT" || exit 0
        print -r -- timeout > "$PE_RUN_DIR/gradle-timeout"
        dg_stop_timed_out_tree "$task_pid"
    ) &
    timer_pid=$!
    trap 'dg_terminate_tree "$task_pid"; dg_terminate_tree "$timer_pid"; exit 130' INT TERM HUP
    wait "$task_pid" || result=$?
    dg_terminate_tree "$timer_pid"
    wait "$timer_pid" 2>/dev/null || true
    trap - INT TERM HUP
    [[ ! -f "$PE_RUN_DIR/gradle-timeout" ]] || { pe_log "✖ Gradle任务超过${DG_TIMEOUT}秒，已停止本次进程。"; return 124; }
    return "$result"
}
# 插件预热最多两次，只在明确网络错误时重试，不重放配置/语法/权限失败。
dg_warm_plugins() {
    local result=0 attempt=0 current_stamp=""
    current_stamp="$(/usr/bin/shasum -a 256 "$DG_PROJECT/android/gradle/wrapper/gradle-wrapper.properties")" || return 1
    [[ "$current_stamp" == "$DG_WRAPPER_STAMP" ]] || { pe_log '✖ Wrapper配置在下载期间变化，请重跑。'; return 1; }
    dg_write_mirror_init || return $?
    for attempt in 1 2; do
        pe_log "➤ Gradle $DG_VERSION help · Java $DG_JAVA_MAJOR · 构建插件预热 $attempt/2"
        result=0
        dg_run_help_once || result=$?
        if (( result == 0 )); then
            pe_log '✔ Gradle help通过，AGP / Kotlin等当前配置阶段构建插件已解析；不代表所有App依赖或编译通过。'
            local agp_version="$(dg_detect_agp_version)"
            pe_event gradle.plugins gradle '解析AGP与构建插件' succeeded '动态声明的AGP版本不猜测' "Gradle $DG_VERSION${agp_version:+ · AGP $agp_version}"
            return 0
        fi
        (( result != 124 )) || return "$result"
        /usr/bin/grep -Eqi '401|403|Unauthorized|Forbidden|PKIX|certificate|authentication|permission denied' "$PE_RUN_DIR/gradle-current.log" && break
        /usr/bin/grep -Eqi 'timed out|Connection reset|UnknownHostException|Could not (GET|HEAD)|Network is unreachable|Temporary failure|Connection refused|Remote host terminated' "$PE_RUN_DIR/gradle-current.log" || break
    done
    pe_log "✖ Gradle插件预热失败（$result）；检查SDK、local.properties、私有仓库权限、AGP兼容及网络。没有把下载分发包当成插件完成。"
    return "$result"
}
# 编排独立模式的只读检查、网络选择、分发包准备与插件预热。
dg_run_requested() {
    local result=0
    dg_initialize && dg_read_wrapper && dg_resolve_java && dg_check_java_compatibility || return $?
    (( ! DG_CHECK )) || { pe_log '✔ 只读配置与Java/Gradle运行版本检查通过；未联网、未解析AGP、未执行构建。'; return 0; }
    pe_initialize_runtime && pe_ensure_fzf || return $?
    pe_select '下载线路' $'official\t项目/官方来源（默认）\naliyun\t腾讯Gradle镜像 + 阿里云Maven备用源（本次进程）' || { result=$?; (( result == 10 )) && result=130; return "$result"; }
    DG_MIRROR="$PE_SELECTION"
    dg_download_distribution && dg_extract_distribution || return $?
    (( ! DG_DISTRIBUTION_ONLY )) || { pe_log '✔ 分发包准备完成；尚未解析构建插件。'; return 0; }
    dg_warm_plugins
}
# 入口按自述、实际业务两步收口，source不执行。
main() {
    dg_intro_and_wait "$@" # 说明用途、缓存和项目脚本执行影响后确认。
    dg_run_requested # 按模式验证配置、准备分发并预热构建插件。
}

if [[ "$ZSH_EVAL_CONTEXT" == toplevel ]]; then
    main "$@"
fi
