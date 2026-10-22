#!/bin/zsh
# 脚本自述：
# - 脚本名称：Android 模拟器启动与新建工具。
# - 核心用途：启动已有 AVD，或按本机架构选择设备和系统映像后新建、启动 AVD。
# - 影响范围：仅按确认安装选中的 SDK 组件和新增 AVD；不删除、覆盖现有设备，不修改 Shell / 系统代理。
# - 运行提示：双击先阅读自述并回车确认；--create 直接新建；--check / --help 只读且不等待确认。
# shell: zsh

# >>> Jobs Android simulator core >>>
# 准备展示所需路径；在确认前只计算变量，不创建文件。
android_prepare_context() {
    local source_path="${(%):-%x}"
    SCRIPT_PATH="${source_path:A}"
    SCRIPT_DIR="${SCRIPT_PATH:h}"
    SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
    LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.$$.log"
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
    ANDROID_SIM_COLOR=0
    if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" && "${PLAIN_OUTPUT:-0}" != 1 ]]; then
        ANDROID_SIM_COLOR=1
    fi
}
# 输出纯文本日志；交互终端按级别着色，文件始终不含 ANSI。
android_log() {
    local message="$1" color="${2:-0;34}"
    if (( ANDROID_SIM_COLOR )); then
        print -r -- $'\e['"${color}m${message}"$'\e[0m'
    else
        print -r -- "$message"
    fi
    if (( ANDROID_SIM_LOG_READY )); then
        print -r -- "$message" >> "$LOG_FILE"
    fi
}
# 输出简明帮助，参数只选择入口模式，不接受无确认的安装或覆盖。
android_help() {
    android_log '用法：/bin/zsh 当前脚本 [--create | --check | --help]'
    android_log '无参数：已有模拟器可启动或新建；没有已有设备时进入新建。'
    android_log '--create：仅进入新建流程，仍逐步选择并最终确认。'
    android_log '--check：只读检查 SDK / Java / 工具 / 已装映像和已有 AVD；不联网、不安装、不新建设备、不写脚本日志。'
}
# 首屏写死用途、影响和取消方法，再按入口区分只读请求与交互确认。
show_script_intro_and_wait() {
    android_prepare_context
    android_log '━━━━━━━━━━ Android 模拟器：新建 / 启动 ━━━━━━━━━━' '1;31'
    android_log "当前脚本：${SCRIPT_PATH}"
    android_log '1、双击可启动已有 AVD，也可新建；桌面右键使用 --create 直接新建。'
    android_log '2、新建时先选完整设备清单，再选匹配 Apple Silicon / Intel 的手机或平板系统映像。'
    android_log '3、只补充缺失组件；下载 / 安装回车跳过，输入任意字符执行。官方许可证需本人阅读接受。'
    android_log '4、不覆盖或清理任何现有 AVD，不安装 Homebrew，不改 Shell 配置或系统代理。'
    android_log '5、回车采用选择清单首项；q / Esc / Ctrl+C 取消；最后回车才创建。'
    android_log "日志位置：${LOG_FILE}（确认后创建；--check / --help 不写日志）"
    if (( $# > 1 )); then
        android_log '✖ 参数过多。' '1;31'
        exit 2
    fi
    case "${1:-}" in
        '') ANDROID_SIM_MODE=menu ;;
        --create) ANDROID_SIM_MODE=create ;;
        --check) ANDROID_SIM_MODE=check; return 0 ;;
        --help|-h) android_help; exit 0 ;;
        *) android_log "✖ 不支持的参数：$1" '1;31'; android_help; exit 2 ;;
    esac
    if [[ ! -t 0 ]]; then
        android_log '✖ 请在可交互终端或双击 .command 执行；无交互检查请用 --check。' '1;31'
        exit 1
    fi
    local answer=""
    if ! IFS= read -r "?已了解用途，按回车继续，非空输入取消：" answer || [[ -n "$answer" ]]; then
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
    local limit="$1" child_pid watchdog_pid result=0
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
# SDK 显式环境优先；保持用户配置目录，不向其它 SDK 悄悄安装。
android_find_sdk() {
    ANDROID_SIM_SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
    if [[ "$ANDROID_SIM_SDK" != /* || ! -d "$ANDROID_SIM_SDK" ]]; then
        android_log "✖ SDK 根目录不存在或不是绝对目录：${ANDROID_SIM_SDK}" '1;31'
        android_log '➤ 请在 Android Studio → SDK Manager 安装 SDK，再设置 ANDROID_HOME；官方说明：https://developer.android.com/studio/intro/update#sdk-manager'
        return 1
    fi
    ANDROID_SIM_SDK="${ANDROID_SIM_SDK:A}"
    if [[ -n "${ANDROID_HOME:-}" && -n "${ANDROID_SDK_ROOT:-}" && "${ANDROID_HOME:A}" != "${ANDROID_SDK_ROOT:A}" ]]; then
        android_log '⚠ ANDROID_HOME 与 ANDROID_SDK_ROOT 不一致，本次进程统一使用 ANDROID_HOME。' '1;33'
    fi
    export ANDROID_HOME="$ANDROID_SIM_SDK" ANDROID_SDK_ROOT="$ANDROID_SIM_SDK"
    android_log "✔ SDK：${ANDROID_SIM_SDK}" '1;32'
}
# 依次验证已配置 Java、Android Studio 内置 JBR 和系统 Java，不安装或改持久配置。
android_find_java() {
    local candidate version="" resolved="" major=""
    local -a candidates
    resolved="$(/usr/libexec/java_home 2>/dev/null)"
    candidates=("${JAVA_HOME:-}/bin/java" '/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java' "$HOME/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java" "${resolved}/bin/java" "$(command -v java 2>/dev/null)")
    for candidate in "${candidates[@]}"; do
        [[ -n "$candidate" && -x "$candidate" ]] || continue
        if version="$(android_timed 12 "$candidate" -version 2>&1)"; then
            major="$(print -r -- "$version" | /usr/bin/awk '/version/ { for(i=1;i<NF;i++) if($i == "version") { value=$(i+1); gsub(/"/, "", value); split(value,p,"."); print (p[1] == 1 ? p[2] : p[1]); exit } }')"
            [[ "$major" == <-> && "$major" -ge 17 ]] || continue
            ANDROID_SIM_JAVA="$candidate"
            export JAVA_HOME="${candidate:A:h:h}"
            android_log "✔ Java：${candidate}；${version%%$'\n'*}" '1;32'
            return 0
        fi
    done
    android_log '✖ 没有可执行的 Java。请安装 / 修复 Android Studio 的内置 JBR，或配置可用 JAVA_HOME。' '1;31'
    android_log '➤ 官方说明：https://developer.android.com/build/jdks'
    return 1
}
# 只从选定 SDK 中发现成对的 sdkmanager / avdmanager，并实际验证二者可运行。
android_find_command_tools() {
    local bin_dir output="" last_error="" candidate
    local -a bins
    bins=("$ANDROID_SIM_SDK/cmdline-tools/latest/bin")
    while IFS= read -r -d '' candidate; do
        bins+=("${candidate:h}")
    done < <(/usr/bin/find "$ANDROID_SIM_SDK/cmdline-tools" -type f -name sdkmanager -print0 2>/dev/null)
    bins+=("$ANDROID_SIM_SDK/tools/bin")
    for bin_dir in "${bins[@]}"; do
        [[ -x "$bin_dir/sdkmanager" && -x "$bin_dir/avdmanager" ]] || continue
        if ! output="$(android_timed 20 "$bin_dir/sdkmanager" --sdk_root="$ANDROID_SIM_SDK" --version 2>&1)"; then
            last_error="${bin_dir}/sdkmanager --version：${output}"
            continue
        fi
        if ! output="$(android_timed 20 "$bin_dir/avdmanager" list device 2>&1)"; then
            last_error="${bin_dir}/avdmanager list device：${output}"
            continue
        fi
        ANDROID_SIM_SDKMANAGER="$bin_dir/sdkmanager"
        ANDROID_SIM_AVDMANAGER="$bin_dir/avdmanager"
        ANDROID_SIM_DEVICES="$output"
        android_log "✔ SDK 命令行工具：${bin_dir}" '1;32'
        return 0
    done
    android_log '✖ SDK Command-line Tools 缺失或无法运行；尚未进行任何下载安装。' '1;31'
    [[ -z "$last_error" ]] || android_log "➤ 失败命令：${last_error}"
    android_log '➤ 请在 Android Studio → SDK Manager → SDK Tools 安装 / 修复 Android SDK Command-line Tools (latest)，并检查 Java 兼容性。'
    android_log '➤ 官方下载及目录布局：https://developer.android.com/tools/sdkmanager'
    return 1
}
# 下载固定官方 HTTPS 地址，不跟随重定向，失败时保留明确诊断。
android_download_official() {
    local url="$1" target="$2" limit="$3" http_code="" curl_bin="$(command -v curl 2>/dev/null)"
    [[ "$url" == https://dl.google.com/android/repository/* && -n "$curl_bin" ]] || return 1
    if ! http_code="$("$curl_bin" --disable --fail --show-error --silent --proto '=https' --connect-timeout 10 --max-time "$limit" --max-redirs 0 --output "$target" --write-out '%{http_code}' "$url" 2>&1)" || [[ "$http_code" != 200 ]]; then
        android_log "✖ Google 官方下载失败：${url}；${http_code}" '1;31'
        return 1
    fi
}
# 解析官方稳定版 macOS 归档，按真实硬件选择架构；旧通用归档仍兼容。
android_read_tools_archive() {
    local xml="$1" package_path="" archive_path="" host_arch=x64 field=""
    [[ "$ANDROID_SIM_ABI" != arm64-v8a ]] || host_arch=aarch64
    package_path="(//*[local-name()='remotePackage' and @path='cmdline-tools;latest'][*[local-name()='channelRef' and @ref='channel-0']])[1]"
    archive_path="(${package_path}/*[local-name()='archives']/*[local-name()='archive'][*[local-name()='host-os' and .='macosx']][*[local-name()='host-arch' and .='${host_arch}'] or not(*[local-name()='host-arch'])]/*[local-name()='complete'])[1]"
    ANDROID_SIM_TOOLS_ARCHIVE="$(/usr/bin/xmllint --nonet --xpath "string(${archive_path}/*[local-name()='url'])" "$xml" 2>/dev/null)" || return 1
    ANDROID_SIM_TOOLS_SIZE="$(/usr/bin/xmllint --nonet --xpath "string(${archive_path}/*[local-name()='size'])" "$xml" 2>/dev/null)" || return 1
    ANDROID_SIM_TOOLS_CHECKSUM="$(/usr/bin/xmllint --nonet --xpath "string(${archive_path}/*[local-name()='checksum'])" "$xml" 2>/dev/null)" || return 1
    ANDROID_SIM_TOOLS_HASH_TYPE="$(/usr/bin/xmllint --nonet --xpath "string(${archive_path}/*[local-name()='checksum']/@type)" "$xml" 2>/dev/null)" || return 1
    ANDROID_SIM_TOOLS_VERSION="$(/usr/bin/xmllint --nonet --xpath "string(${package_path}/*[local-name()='revision']/*[local-name()='major'])" "$xml" 2>/dev/null)"
    field="$(/usr/bin/xmllint --nonet --xpath "string(${package_path}/*[local-name()='revision']/*[local-name()='minor'])" "$xml" 2>/dev/null)"
    [[ -z "$field" ]] || ANDROID_SIM_TOOLS_VERSION+=".${field}"
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
# 缺失工具允许选择官方自助安装一次，健康安装不触发网络或更新。
android_ensure_command_tools() {
    local result=0 tool=""
    android_find_command_tools && return 0
    [[ "$ANDROID_SIM_MODE" != check ]] || return 1
    android_log '━━━━━━━━━━ 来源｜补充 SDK Command-line Tools ━━━━━━━━━━' '1;36'
    android_log '📥 官方元数据：https://dl.google.com/android/repository/repository2-3.xml'
    android_log "📂 目标：${ANDROID_SIM_SDK}/cmdline-tools/ 下新建独立版本目录；不会覆盖 latest 或既有版本。"
    android_ask_install '是否下载官方稳定命令行工具？归档约 150 MB；确认后联网、校验并新增工具目录；不会自动接受 SDK 许可证。' || return 1
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
        android_log '✖ 命令行工具安装后复检失败，已停止；新增版本保留供 SDK Manager 人工排查。' '1;31'
        return 1
    fi
}
# 检查本 SDK 的 emulator 本体与 AVD 清单，存在文件不代表安装健康。
android_probe_emulator() {
    local output=""
    ANDROID_SIM_EMULATOR="$ANDROID_SIM_SDK/emulator/emulator"
    [[ -x "$ANDROID_SIM_EMULATOR" ]] || return 1
    output="$(android_timed 15 "$ANDROID_SIM_EMULATOR" -version 2>&1)" || return 1
    ANDROID_SIM_AVDS="$(android_timed 15 "$ANDROID_SIM_EMULATOR" -list-avds 2>&1)" || return 1
    android_log "✔ emulator：${ANDROID_SIM_EMULATOR}；${output%%$'\n'*}" '1;32'
}
# 普通安装独立确认；直接回车或 EOF 不会写入 SDK。
android_ask_install() {
    local answer=""
    android_log "⚠ $1" '1;33'
    if ! IFS= read -r "?回车跳过；输入任意字符执行；Ctrl+C 取消：" answer; then
        return 1
    fi
    [[ -n "$answer" ]]
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
    android_ask_install "将下载 / 安装所选组件：${package}；可能占用数 GB，许可证由你阅读并选择。" || return 1
    NO_COLOR=1 FORCE_COLOR=0 TERM=dumb "$ANDROID_SIM_SDKMANAGER" --sdk_root="$ANDROID_SIM_SDK" --install "$package" --channel=0 2>&1 | /usr/bin/tee -a "$LOG_FILE"
    result=${pipestatus[1]}
    if (( result != 0 )); then
        android_log "✖ 组件安装失败（退出码 ${result}）：${package}；来源：Google 官方 Android SDK Repository。" '1;31'
        return "$result"
    fi
}
# 缺失 emulator 只补装一次；已登记或有本体却损坏时停止并给出官方修复入口。
android_ensure_emulator() {
    android_probe_emulator && return 0
    android_log "⚠ emulator 缺失或健康检查失败：${ANDROID_SIM_SDK}/emulator/emulator" '1;33'
    [[ "$ANDROID_SIM_MODE" != check ]] || return 1
    if [[ -e "$ANDROID_SIM_SDK/emulator/emulator" || -e "$ANDROID_SIM_SDK/emulator/source.properties" || -e "$ANDROID_SIM_SDK/emulator/package.xml" ]]; then
        android_log '✖ emulator 已存在或已被 SDK 登记，但无法运行；sdkmanager --install 可能跳过已登记包，因此本次停止，未声称完成修复。' '1;31'
        android_log '➤ 请在 Android Studio → SDK Manager → SDK Tools 中取消 Android Emulator 并 Apply，再重新勾选安装；只重装工具包，保留已有 AVD。'
        return 1
    fi
    if [[ -z "$ANDROID_SIM_SDKMANAGER" ]]; then
        android_find_java && android_ensure_command_tools || return 1
    fi
    android_install_package emulator || return 1
    if ! android_probe_emulator; then
        android_log '✖ emulator 安装后复检仍失败，已停止；请在 SDK Manager 修复 Android Emulator。' '1;31'
        return 1
    fi
}
# 可用 fzf 只是交互增强；缺失或损坏时直接使用编号，无安装依赖。
android_find_selector() {
    local candidate="$(command -v fzf 2>/dev/null)"
    if [[ -n "$candidate" && -x "$candidate" ]] && android_timed 8 "$candidate" --version >/dev/null 2>&1; then
        ANDROID_SIM_FZF="$candidate"
        android_log "✔ 选择器：${candidate}" '1;32'
    else
        ANDROID_SIM_FZF=""
        android_log '➤ fzf 缺失或不可用，使用编号选择；无需安装。'
    fi
}
# 选择清单首项为回车默认值，防止 fzf 配置注入并校验返回值属于当前清单。
android_choose() {
    local title="$1" content="$2" answer="" result=0 index=0
    local -a rows
    rows=("${(@f)content}")
    ANDROID_SIM_SELECTED=""
    [[ -n "$content" && ${#rows} -gt 0 ]] || return 1
    android_log "➤ ${title}"
    if [[ -n "$ANDROID_SIM_FZF" ]]; then
        ANDROID_SIM_SELECTED="$(print -rl -- "${rows[@]}" | /usr/bin/env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_OPTS_FILE "$ANDROID_SIM_FZF" --delimiter=$'\t' --with-nth=1 --height=60% --reverse --prompt="${title} > ")" || result=$?
        if (( result == 1 || result == 130 )) || [[ -z "$ANDROID_SIM_SELECTED" && $result == 0 ]]; then
            return 130
        fi
        if (( result == 0 )); then
            if (( ${rows[(Ie)$ANDROID_SIM_SELECTED]} == 0 )); then
                android_log '✖ 选择结果不属于当前清单，已停止。' '1;31'
                return 1
            fi
            return 0
        fi
        android_log "⚠ fzf 运行失败（${result}），改用编号选择。" '1;33'
        ANDROID_SIM_FZF=""
    fi
    for (( index=1; index<=${#rows}; index++ )); do
        android_log "${index}、${rows[index]%%$'\t'*}"
    done
    while true; do
        if ! IFS= read -r "?输入编号（回车选第 1 项，q 取消）：" answer || [[ "$answer" == [qQ] || "$answer" == $'\e' ]]; then
            return 130
        fi
        [[ -n "$answer" ]] || answer=1
        if [[ "$answer" == <-> && ${#answer} -le 6 ]]; then
            index=$(( 10#$answer ))
            if (( index >= 1 && index <= ${#rows} )); then
                ANDROID_SIM_SELECTED="${rows[index]}"
                return 0
            fi
        fi
        android_log '⚠ 请输入清单内的编号，或 q 取消。' '1;33'
    done
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
# 下载清单需用户先确认联网，再只列稳定、同架构手机 / 平板系统映像。
android_remote_images() {
    local output="" result=0
    android_log '➤ 将从 Google 官方 Android SDK Repository 查询稳定系统映像；不会修改系统代理。'
    android_ask_install '是否联网读取可下载的系统映像清单？' || return 130
    if ! output="$(android_timed 60 "$ANDROID_SIM_SDKMANAGER" --sdk_root="$ANDROID_SIM_SDK" --list --channel=0 2>&1)"; then
        android_log "✖ 读取 Google SDK 清单失败：${output}" '1;31'
        return 1
    fi
    ANDROID_SIM_IMAGES="$(print -r -- "$output" | /usr/bin/awk -F '|' -v abi="$ANDROID_SIM_ABI" '
        { package=$1; gsub(/^[[:space:]]+|[[:space:]]+$/, "", package)
          if (package ~ ("^system-images;android-[0-9]+(\\.[0-9]+)?(-ext[0-9]+)?;(google_apis|google_apis_playstore|default);" abi "$")) print package }
    ' | /usr/bin/sort -t ';' -k2,2Vr -k3,3 -u)"
    if [[ -z "$ANDROID_SIM_IMAGES" ]]; then
        android_log "✖ 官方清单没有可用的 ${ANDROID_SIM_ABI} 手机 / 平板映像。请在 SDK Manager 中检查。" '1;31'
        return 1
    fi
}
# 优先使用已装映像，允许显式另选下载；安装成功后确认映像文件实际存在。
android_select_image() {
    local installed="$(android_installed_images)" rows="" package image_path
    if [[ -n "$installed" ]]; then
        rows="$(print -r -- "$installed" | android_image_rows)"
        rows+=$'\n从 Google 官方源选择其它系统映像\t__download__'
        android_choose '选择系统映像（优先已安装）' "$rows" || return $?
        package="${ANDROID_SIM_SELECTED#*$'\t'}"
    else
        package=__download__
    fi
    if [[ "$package" == __download__ ]]; then
        android_remote_images || return $?
        rows="$(print -r -- "$ANDROID_SIM_IMAGES" | android_image_rows)"
        android_choose '选择要安装的系统映像' "$rows" || return $?
        package="${ANDROID_SIM_SELECTED#*$'\t'}"
        image_path="$ANDROID_SIM_SDK/${(j:/:)${(s:;:)package}}/system.img"
        if [[ ! -f "$image_path" ]]; then
            android_install_package "$package" || return $?
        fi
    fi
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
        if ! IFS= read -r "?新 AVD 名称（回车用 ${default_name}；q 取消）：" answer || [[ "$answer" == [qQ] ]]; then
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
# 按实际 SDK 型号、架构映像和无冲突名称新增 AVD，不使用 --force 或 wipe。
android_create() {
    local rows="" device_id api default_name answer="" result=0
    [[ -n "$ANDROID_SIM_SDKMANAGER" ]] || { android_find_java && android_ensure_command_tools || return 1; }
    rows="$(android_device_rows)"
    if [[ -z "$rows" ]]; then
        android_log '✖ SDK 中没有可解析的设备定义，请在 SDK Tools 修复命令行工具。' '1;31'
        return 1
    fi
    android_choose '选择 Android 设备型号' "$rows" || return $?
    device_id="${ANDROID_SIM_SELECTED#*$'\t'}"
    android_select_image || return $?
    api="${ANDROID_SIM_IMAGE#system-images;android-}"
    api="${api%%;*}"
    default_name="${device_id}_API_${api}_${ANDROID_SIM_ABI//-/_}"
    android_choose_name "$default_name" || return $?
    android_log "➤ 即将新建：${ANDROID_SIM_NEW_AVD}；设备：${device_id}；系统：${ANDROID_SIM_IMAGE}"
    if ! IFS= read -r "?按回车创建并启动，任意非空输入取消：" answer || [[ -n "$answer" ]]; then
        return 130
    fi
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
    android_launch "$ANDROID_SIM_NEW_AVD"
}
# 双击入口保留已有设备启动能力，同时显式提供新增入口。
android_menu() {
    local rows=$'新建 Android 模拟器\t__create__' name
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
    android_choose '选择操作' "$rows" || return $?
    name="${ANDROID_SIM_SELECTED#*$'\t'}"
    if [[ "$name" == __create__ ]]; then
        android_create
    else
        android_launch "$name"
    fi
}
# 汇总完整依赖与本地状态，健康时不安装或升级，缺失层明确返回失败。
android_check() {
    local failures=0 installed="" count=0
    android_log '➤ 只读自检：不联网、不下载、不安装、不创建设备、不写脚本日志。'
    android_detect_architecture || return 1
    android_find_sdk || return 1
    android_find_java && android_find_command_tools || failures=$((failures + 1))
    android_ensure_emulator || failures=$((failures + 1))
    android_find_selector
    installed="$(android_installed_images)"
    if [[ -n "$installed" ]]; then
        count="$(print -r -- "$installed" | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
        android_log "✔ 已装匹配架构的手机 / 平板系统映像：${count} 个" '1;32'
        android_log "➤ 回车首选系统映像：${installed%%$'\n'*}"
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
# 执行选择模式并统一传播失败或取消状态，不吞掉外部工具错误。
android_run_requested_action() {
    local result=0
    android_initialize_runtime || return $?
    if [[ "$ANDROID_SIM_MODE" == check ]]; then
        android_check
        return $?
    fi
    android_detect_architecture && android_find_sdk && android_ensure_emulator || return 1
    android_find_selector
    if [[ "$ANDROID_SIM_MODE" == create ]]; then
        android_create || result=$?
    else
        android_menu || result=$?
    fi
    if (( result == 130 )); then
        android_log '➤ 已取消；未删除或覆盖现有 AVD。'
        result=0
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
