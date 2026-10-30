#!/bin/zsh
# 脚本自述：
# - 只供 source：组合现有 AndroidSdkSupport 内核，补齐当前项目需要的 Android SDK、组件和本机路径。
# - 影响范围：所选 SDK 缓存与 android/local.properties；许可证保持真实终端交互，不自动同意。
# - Java：SDK Manager 可以临时使用其要求的工具 JDK，Gradle 仍使用一键流程明确选择的项目 JDK。

typeset -g AP_PROJECT="" AP_FLUTTER="" AP_SELECTED_JAVA="" AP_API="" AP_BUILD="" AP_NDK="" AP_CMAKE=""
typeset -g AP_ACTIVE_ID="" AP_ACTIVE_TITLE=""
typeset -g AP_DYNAMIC_NDK=0 AP_DYNAMIC_CMAKE=0
# 向面板发布分类子节点，未通过 GUI 启动时仍保留终端提示。
ap_event() {
    local id="$1" title="$2" state="$3" message="${4:-}" version="${5:-}"
    if [[ "$state" == running || "$state" == attention ]]; then AP_ACTIVE_ID="$id" AP_ACTIVE_TITLE="$title"; fi
    if [[ "$state" == succeeded && "$AP_ACTIVE_ID" == "$id" ]]; then AP_ACTIVE_ID="" AP_ACTIVE_TITLE=""; fi
    pe_event "platforms.android.$id" platforms.android "$title" "$state" "$message" "$version"
}
# 从官方组件小型元数据读取实际版本，不把目录名或请求版本冒充检测结果。
ap_package_value() {
    local file="$1" key="$2"
    [[ -f "$file" && ! -L "$file" && "$(/usr/bin/stat -f %z "$file")" -le 65536 ]] || return 1
    /usr/bin/perl -e 'my($f,$key)=@ARGV; open my $in,"<",$f or exit 1; while(<$in>) { s/\r?\n$//; if (/^\s*\Q$key\E\s*=\s*([0-9]+(?:\.[0-9]+)*)\s*$/) { print $1; exit 0; } } exit 1;' "$file" "$key"
}
# 只接受普通目录及配置文件，拒绝链接和硬链接的本机配置。
ap_check_project() {
    local item="$AP_PROJECT/android/local.properties"
    [[ "$AP_PROJECT" == /* && -d "$AP_PROJECT/android" && ! -L "$AP_PROJECT/android" && ! -L "$item" ]] || return 1
    [[ ! -e "$item" || ( -f "$item" && "$(/usr/bin/stat -f %l "$item")" == 1 && "$(/usr/bin/stat -f %z "$item")" -le 65536 ) ]] || return 1
}
# 静态提取显式版本或 Flutter 官方扩展默认值，不运行 Gradle 配置来猜版本。
ap_read_requirements() {
    setopt localoptions NO_NOMATCH
    local files=("$AP_PROJECT"/android/app/build.gradle{,.kts}(N)) sdk_root="${AP_FLUTTER:A:h:h}" rows="" key="" value=""
    AP_API="" AP_BUILD="" AP_NDK="" AP_CMAKE=""
    AP_DYNAMIC_NDK=0 AP_DYNAMIC_CMAKE=0
    (( ${#files} > 0 )) || { pe_log '✖ 未找到当前Android应用的build.gradle或build.gradle.kts。'; return 1; }
    rows="$(/usr/bin/perl -0777 -ne '
        s{/\*.*?\*/}{}gs; s{^\s*//.*$}{}mg;
        print "api\t$1\n" if /\bcompileSdk(?:Version)?\s*(?:=\s*|\(\s*)?(\d+)/;
        print "build\t$1\n" if /\bbuildToolsVersion\s*(?:=\s*|\(\s*)?["\x27](\d+\.\d+\.\d+)["\x27]/;
        print "ndk\t$1\n" if /\bndkVersion\s*(?:=\s*|\(\s*)?["\x27]([\d.]+)["\x27]/;
        print "cmake\t$1\n" if /\bcmake\s*\{[^}]*?\bversion\s*(?:=\s*|\(\s*)?["\x27]([\d.]+)["\x27]/s;
        print "flutter-api\tyes\n" if /\bcompileSdk(?:Version)?\s*(?:=\s*|\(\s*)?flutter\.compileSdkVersion/;
        print "flutter-ndk\tyes\n" if /\bndkVersion\s*(?:=\s*|\(\s*)?flutter\.ndkVersion/;
        print "has-ndk\tyes\n" if /\bndkVersion\b/;
        print "has-cmake-version\tyes\n" if /\bcmake\s*\{[^}]*?\bversion\b/s;
    ' "${files[@]}")" || return 1
    while IFS=$'\t' read -r key value; do
        case "$key" in
            api) AP_API="$value" ;; build) AP_BUILD="$value" ;; ndk) AP_NDK="$value" ;; cmake) AP_CMAKE="$value" ;;
        esac
    done <<< "$rows"
    files=("$sdk_root"/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt(N) "$sdk_root"/packages/flutter_tools/gradle/src/main/groovy/flutter.groovy(N))
    if [[ -z "$AP_API" && "$rows" == *$'flutter-api\tyes'* && ${#files} -gt 0 ]]; then
        AP_API="$(/usr/bin/perl -0777 -ne 'if (/\bcompileSdkVersion(?:\s*:\s*Int)?\s*=\s*(\d+)/) { print $1; exit; }' "${files[@]}")"
    fi
    if [[ -z "$AP_NDK" && "$rows" == *$'flutter-ndk\tyes'* ]]; then
        if (( ${#files} > 0 )); then
            AP_NDK="$(/usr/bin/perl -0777 -ne 'if (/\bndkVersion(?:\s*:\s*String)?\s*=\s*["\x27]([\d.]+)["\x27]/) { print $1; exit; }' "${files[@]}")"
        fi
        [[ -n "$AP_NDK" ]] || { pe_log '✖ 当前工程引用flutter.ndkVersion，但所选SDK中无法解析此版本；请核对工程声明。'; return 1; }
    fi
    [[ -z "$AP_API" || "$AP_API" == <-> ]] || return 1
    if [[ -z "$AP_NDK" && "$rows" == *$'has-ndk\tyes'* ]]; then AP_DYNAMIC_NDK=1; fi
    if [[ -z "$AP_CMAKE" && "$rows" == *$'has-cmake-version\tyes'* ]]; then AP_DYNAMIC_CMAKE=1; fi
    [[ -z "$AP_NDK" || "$AP_NDK" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || return 1
    [[ -z "$AP_CMAKE" || "$AP_CMAKE" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || return 1
}
# 复用项目sdk.dir，避免忽略用户自定义的Android SDK位置。
ap_reuse_sdk_location() {
    local config="$AP_PROJECT/android/local.properties" candidate=""
    if [[ -f "$config" ]]; then
        candidate="$(/usr/bin/perl -ne 'if (/^\s*sdk\.dir\s*[=:]\s*(.*)$/) { my $v=$1; $v =~ s/\\([\\:=#! ])/$1/g; print $v; exit; }' "$config")"
        if [[ -n "$candidate" ]]; then
            [[ "$candidate" == /* && ! -L "${candidate%/}" ]] || { pe_log '✖ 项目sdk.dir不是普通绝对目录；请检查原配置。'; return 1; }
            export ANDROID_HOME="$candidate"
        fi
    fi
}
# 复用原内核的SDK与官方CLT引导，限定为子进程，不切换项目Java配置。
ap_prepare_tools() {
    ap_event sdk 'SDK位置' running '检查项目sdk.dir和已有安装'
    android_prepare_context
    ANDROID_SIM_MODE=prepare
    LOG_FILE="$PE_RUN_DIR/android-tools.log"
    ANDROID_SIM_LOG_READY=1
    : > "$LOG_FILE"
    export JAVA_HOME="$AP_SELECTED_JAVA"
    ap_reuse_sdk_location && android_configure_network && android_detect_architecture && android_ensure_sdk || { ap_event sdk 'SDK位置' failed 'SDK定位或网络配置失败'; return 1; }
    ap_event sdk 'SDK位置' succeeded "$ANDROID_SIM_SDK"
    ap_event command-tools 'Command-line Tools' running '复用官方工具引导并二次验证Java兼容'
    android_ensure_java && android_ensure_command_tools || { ap_event command-tools 'Command-line Tools' failed '官方下载或工具复检失败'; return 1; }
    local clt_version="$(ap_package_value "${ANDROID_SIM_SDKMANAGER:A:h:h}/source.properties" Pkg.Revision)"
    ap_event command-tools 'Command-line Tools' succeeded "$ANDROID_SIM_SDKMANAGER" "CLT ${clt_version:-版本未读取}"
    pe_log "➤ SDK Manager工具Java：${JAVA_HOME:-未知}；Gradle项目Java仍为$AP_SELECTED_JAVA。"
}
# 从官方清单选择无法静态解析的API；返回/取消不启动组件安装。
ap_resolve_packages() {
    local catalog="" rows="" result=0
    ap_event platforms 'platform / build-tools' running '读取官方稳定组件清单和工程要求'
    catalog="$(android_timed 120 "$ANDROID_SIM_SDKMANAGER" --sdk_root="$ANDROID_SIM_SDK" --list --channel=0 "${ANDROID_SIM_SDK_PROXY[@]}" 2> >(pe_filter_log >&2))" || return $?
    if [[ -z "$AP_API" ]]; then
        rows="$(print -r -- "$catalog" | /usr/bin/sed -nE 's/^[[:space:]]*platforms;android-([0-9]+)[[:space:]]*\|.*/\1/p' | /usr/bin/sort -nu | /usr/bin/awk '{ print $0 "\tAndroid API " $0 }')"
        [[ -n "$rows" ]] || { pe_log '✖ 没有可选稳定Android平台；请检查SDK官方清单。'; return 1; }
        pe_log '➤ 工程compileSdk使用动态表达式，无法静态确定；请按项目要求选择API，不会自动改源码。'
        pe_select '项目compileSdk' "$rows" || { result=$?; (( result != 10 )) || result=130; return "$result"; }
        AP_API="$PE_SELECTION"
    fi
    if [[ -z "$AP_BUILD" ]]; then
        AP_BUILD="$(print -r -- "$catalog" | /usr/bin/sed -nE 's/^[[:space:]]*build-tools;([0-9]+\.[0-9]+\.[0-9]+)[[:space:]]*\|.*/\1/p' | /usr/bin/sort -t. -k1,1n -k2,2n -k3,3n | /usr/bin/tail -1)"
    fi
    [[ "$AP_API" == <-> && "$AP_BUILD" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { pe_log '✖ 无法确定稳定Android构建组件版本。'; return 1; }
    if (( AP_DYNAMIC_NDK )); then
        rows="$(print -r -- "$catalog" | /usr/bin/sed -nE 's/^[[:space:]]*ndk;([0-9]+\.[0-9]+\.[0-9]+)[[:space:]]*\|.*/\1/p' | /usr/bin/sort -u | /usr/bin/awk '{print $0 "\tNDK " $0}')"
        [[ -n "$rows" ]] || { pe_log '✖ 工程NDK版本为动态表达式，官方清单中无可选版本。'; return 1; }
        pe_select '工程动态NDK版本，请按项目要求选择' "$rows" || return $?
        AP_NDK="$PE_SELECTION"
    fi
    if (( AP_DYNAMIC_CMAKE )); then
        rows="$(print -r -- "$catalog" | /usr/bin/sed -nE 's/^[[:space:]]*cmake;([0-9]+\.[0-9]+\.[0-9]+)[[:space:]]*\|.*/\1/p' | /usr/bin/sort -u | /usr/bin/awk '{print $0 "\tCMake " $0}')"
        [[ -n "$rows" ]] || { pe_log '✖ 工程CMake版本为动态表达式，官方清单中无可选版本。'; return 1; }
        pe_select '工程动态CMake版本，请按项目要求选择' "$rows" || return $?
        AP_CMAKE="$PE_SELECTION"
    fi
    pe_log "➤ 当前工程组件计划：platform-tools、platforms;android-$AP_API、build-tools;$AP_BUILD、NDK ${AP_NDK:-未声明}、CMake ${AP_CMAKE:-未声明}。"
}
# 保留官方许可逐项阅读与选择，不通过yes管道代替用户接受。
ap_review_licenses() {
    local result=0
    ap_event licenses 'Android许可证' attention '请在下方终端阅读并选择，拒绝则停止需要许可的安装'
    pe_log '➤ 接下来由官方sdkmanager展示许可证，请本人阅读后回答；脚本不替你接受。'
    "$ANDROID_SIM_SDKMANAGER" --sdk_root="$ANDROID_SIM_SDK" --licenses "${ANDROID_SIM_SDK_PROXY[@]}" 2>&1 | /usr/bin/tee "$PE_RUN_DIR/android-licenses.log" | /usr/bin/tee -a "$LOG_FILE"
    result=${pipestatus[1]}
    (( result == 0 )) || { ap_event licenses 'Android许可证' attention "许可流程未完成（$result）"; return "$result"; }
    if ! /usr/bin/grep -Eq 'All SDK package licenses accepted\.' "$PE_RUN_DIR/android-licenses.log"; then
        ap_event licenses 'Android许可证' attention '没有收到官方全部许可接受结果，尚需本人处理'
        pe_log '⚠ 官方许可命令结束，但许可状态尚未确认；不把退出码0当成已接受。'
        return 3
    fi
    ap_event licenses 'Android许可证' succeeded '官方许可步骤完成，组件安装仍会复核许可'
}
# 安装并复检精确需要的基本组件，健康组件直接复用。
ap_install_packages() {
    local actual_api="" actual_build="" actual_tools="" actual_ndk="" actual_cmake="" native_version=""
    ap_event platforms 'platform / build-tools' running "API $AP_API / build-tools $AP_BUILD"
    [[ -x "$ANDROID_SIM_SDK/platform-tools/adb" ]] || android_install_package platform-tools || return $?
    [[ -f "$ANDROID_SIM_SDK/platforms/android-$AP_API/android.jar" ]] || android_install_package "platforms;android-$AP_API" || return $?
    [[ -x "$ANDROID_SIM_SDK/build-tools/$AP_BUILD/aapt2" ]] || android_install_package "build-tools;$AP_BUILD" || return $?
    [[ -x "$ANDROID_SIM_SDK/platform-tools/adb" && -f "$ANDROID_SIM_SDK/platforms/android-$AP_API/android.jar" && -x "$ANDROID_SIM_SDK/build-tools/$AP_BUILD/aapt2" ]] || return 1
    pe_run_logged "$ANDROID_SIM_SDK/platform-tools/adb" version || return $?
    actual_api="$(ap_package_value "$ANDROID_SIM_SDK/platforms/android-$AP_API/source.properties" AndroidVersion.ApiLevel)"
    actual_build="$(ap_package_value "$ANDROID_SIM_SDK/build-tools/$AP_BUILD/source.properties" Pkg.Revision)"
    actual_tools="$(ap_package_value "$ANDROID_SIM_SDK/platform-tools/source.properties" Pkg.Revision)"
    ap_event platforms 'platform / build-tools' succeeded "要求API $AP_API / build-tools $AP_BUILD；本机组件已检查" "API ${actual_api:-未读取} · Build-tools ${actual_build:-未读取} · Platform-tools ${actual_tools:-未读取}"
    ap_event native 'NDK / CMake' running '按工程声明补齐原生插件构建组件'
    if [[ -n "$AP_NDK" ]]; then
        [[ -f "$ANDROID_SIM_SDK/ndk/$AP_NDK/source.properties" ]] || android_install_package "ndk;$AP_NDK" || return $?
        [[ -f "$ANDROID_SIM_SDK/ndk/$AP_NDK/source.properties" ]] || return 1
        actual_ndk="$(ap_package_value "$ANDROID_SIM_SDK/ndk/$AP_NDK/source.properties" Pkg.Revision)"
        if [[ -n "$actual_ndk" && "$actual_ndk" != "$AP_NDK" ]]; then pe_log '✖ NDK元数据版本与工程声明不一致。'; return 1; fi
    fi
    if [[ -n "$AP_CMAKE" ]]; then
        [[ -x "$ANDROID_SIM_SDK/cmake/$AP_CMAKE/bin/cmake" ]] || android_install_package "cmake;$AP_CMAKE" || return $?
        [[ -x "$ANDROID_SIM_SDK/cmake/$AP_CMAKE/bin/cmake" ]] || return 1
        pe_run_logged "$ANDROID_SIM_SDK/cmake/$AP_CMAKE/bin/cmake" --version || return $?
        actual_cmake="$(ap_package_value "$ANDROID_SIM_SDK/cmake/$AP_CMAKE/source.properties" Pkg.Revision)"
    fi
    [[ -z "$AP_NDK" ]] || native_version="NDK ${actual_ndk:-版本未读取}"
    [[ -z "$AP_CMAKE" ]] || native_version="${native_version:+$native_version · }CMake ${actual_cmake:-版本未读取}"
    ap_event native 'NDK / CMake' succeeded "工程要求NDK ${AP_NDK:-未声明} / CMake ${AP_CMAKE:-未声明}" "${native_version:-工程未声明}"
}
# 原子合并sdk.dir，保留其他键，并检查选择期间的并发编辑。
ap_write_sdk_config() {
    local config="$AP_PROJECT/android/local.properties" before="" after="" staging=""
    ap_event config '项目SDK路径' running '备份并更新本机sdk.dir'
    ap_check_project || return 1
    before="$(sf_file_stamp "$config")" || return 1
    /bin/mkdir -p "$PE_RUN_DIR/before" || return 1
    if [[ -f "$config" ]]; then /bin/cp -p "$config" "$PE_RUN_DIR/before/android-local.properties" || return 1; fi
    staging="$(/usr/bin/mktemp "$AP_PROJECT/android/.jobs-sdk.XXXXXX")" || return 1
    AP_SDK_VALUE="$ANDROID_SIM_SDK" /usr/bin/perl -e '
        use strict; use warnings; my $file=shift; my $text="";
        if(-f $file) { open my $in,"<",$file or die $!; local $/; $text=<$in>; }
        $text =~ s/^\s*sdk\.dir\s*[=:].*(?:\r?\n|$)//mg;
        my $sdk=$ENV{AP_SDK_VALUE}; $sdk =~ s/([\\:=#! ])/\\$1/g;
        print $text; print "\n" if length($text) && $text !~ /\n$/; print "sdk.dir=$sdk\n";
    ' "$config" > "$staging" || return 1
    after="$(sf_file_stamp "$config")" || return 1
    [[ "$before" == "$after" ]] || { /bin/rm -f -- "$staging"; pe_log '✖ local.properties有并发修改，未覆盖。'; return 1; }
    /bin/mv -f -- "$staging" "$config" || return 1
    print -r -- "$ANDROID_SIM_SDK" > "$PE_RUN_DIR/android-sdk-root" || return 1
    ap_event config '项目SDK路径' succeeded 'sdk.dir已合并，原文快照保留'
}
# 在隔离子Shell中组合现有工具内核，失败保留真实节点与原始日志。
ap_prepare_android() {
    local result=0
    AP_PROJECT="$1" AP_FLUTTER="$2" AP_SELECTED_JAVA="$3"
    source "$PE_TOOLS_DIR/AndroidSdkSupport.zsh" || return $?
    pe_event platforms.android platforms 'Android工具链' running '复用现有SDK引导和组件安装内核'
    ap_check_project && ap_read_requirements && ap_prepare_tools && ap_resolve_packages && ap_review_licenses && ap_install_packages && ap_write_sdk_config || result=$?
    if (( result != 0 )); then
        local state=failed
        (( result != 3 && result != 130 )) || state=attention
        [[ -z "$AP_ACTIVE_ID" ]] || ap_event "$AP_ACTIVE_ID" "$AP_ACTIVE_TITLE" "$state" "当前步骤未完成（$result）"
        pe_event platforms.android platforms 'Android工具链' "$state" "未完成，退出码$result；保留已安装组件与日志"
        return "$result"
    fi
    pe_event platforms.android platforms 'Android工具链' succeeded 'SDK、许可证、构建组件与本机路径已准备' "Android API $AP_API"
}
# 成功后仅把SDK路径带回父流程，Gradle继续使用已选项目JDK。
sf_platform_android() {
    local result=0 sdk=""
    (ap_prepare_android "$@") || result=$?
    (( result == 0 )) || return "$result"
    sdk="$(<"$PE_RUN_DIR/android-sdk-root")"
    [[ "$sdk" == /* && -d "$sdk" ]] || return 1
    export ANDROID_HOME="$sdk" ANDROID_SDK_ROOT="$sdk"
    export PATH="$sdk/platform-tools:$PATH"
}
