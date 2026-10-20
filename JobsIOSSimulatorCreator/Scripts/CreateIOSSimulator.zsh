#!/bin/zsh
# 脚本自述：
# - 脚本名称：CreateIOSSimulator.zsh。
# - 核心用途：交互选择本机已安装的 iOS Runtime 和兼容 iPhone / iPad，创建并启动新模拟器。
# - 影响范围：只新增一个模拟器并打开 Simulator，不关闭、删除或重置已有设备，不安装工具或 Runtime。
# - 运行提示：先阅读自述并回车；选择时可取消，最终回车才创建；--help / --check 为只读入口。

typeset SCRIPT_DIR=""
typeset SCRIPT_PATH=""
typeset SCRIPT_BASENAME="CreateIOSSimulator"
typeset LOG_FILE=""
typeset SIM_MODE="interactive"
typeset SIM_RUN_DIR=""
typeset SIM_ACTIVE_PID=""
typeset SIM_DEVELOPER_DIR=""
typeset SIM_APP=""
typeset SIM_APP_KIND=""
typeset SIM_FZF=""
typeset SIM_SELECTED_ROW=""
typeset SIM_RUNTIME_ID=""
typeset SIM_RUNTIME_NAME=""
typeset SIM_DEVICE_ID=""
typeset SIM_DEVICE_NAME=""
typeset SIM_NAME=""
typeset SIM_UDID=""
typeset SIM_LOG_READY=0
typeset SIM_CANCELLED=0
typeset -a SIM_ROWS

# 仅设置进程内选项、路径及纯文本 / 彩色展示条件。
sim_prepare_context() {
    setopt NO_NOMATCH PIPE_FAIL
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
    SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
    LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.$$.log"
}
# 同步显示与日志；磁盘日志始终保持纯文本。
sim_log() {
    print -r -- "$1"
    if [[ "$SIM_LOG_READY" == 1 ]]; then
        print -r -- "$1" >> "$LOG_FILE"
    fi
}
# 按 Jobs 标准显示自述，非完整终端自动降级为纯文本。
sim_intro_line() {
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
# 首屏只说明行为并确认，确认前不探测 Xcode 或写日志。
show_script_intro_and_wait() {
    sim_prepare_context
    sim_intro_line title '━━━━━━━━━━ 新建 iOS 模拟器 ━━━━━━━━━━'
    sim_intro_line body '1、选择本机已安装的 iOS 系统与兼容 iPhone / iPad，新增并启动一个模拟器。'
    sim_intro_line body '2、保留现有设备与调试会话；不安装工具 / Runtime，不更改 Xcode、Shell 或网络配置。'
    sim_intro_line body '3、Ctrl+C 随时停止；选择时按 Esc / 输入 q 取消；创建前会再次确认。'
    sim_intro_line body "日志位置：${LOG_FILE}（确认后创建；只读入口不写日志）"
    case "$#:${1:-}" in
        0:) SIM_MODE=interactive ;;
        1:--help|1:-h) SIM_MODE=help; return 0 ;;
        1:--check) SIM_MODE=check; return 0 ;;
        *) sim_log '✖ 参数无效。使用 --help 查看说明。'; exit 64 ;;
    esac
    if [[ ! -t 0 || ! -t 1 ]]; then
        sim_log '✖ 当前没有可交互终端，请通过 Finder 入口或 Terminal 运行；不会创建模拟器。'
        exit 1
    fi
    local answer=""
    IFS= read -r "?已了解影响，直接回车继续；输入任意字符取消：" answer || exit 130
    if [[ -n "$answer" ]]; then
        sim_log '➤ 已取消，未创建模拟器。'
        exit 0
    fi
}
# 清理本次私有临时文件，不触碰 CoreSimulator 或其它会话。
sim_cleanup() {
    if [[ -n "$SIM_ACTIVE_PID" ]]; then
        kill -TERM "$SIM_ACTIVE_PID" 2>/dev/null
        /bin/sleep 0.2
        kill -KILL "$SIM_ACTIVE_PID" 2>/dev/null
        wait "$SIM_ACTIVE_PID" 2>/dev/null
        SIM_ACTIVE_PID=""
    fi
    if [[ -n "$SIM_RUN_DIR" && -d "$SIM_RUN_DIR" ]]; then
        /bin/rm -f -- "$SIM_RUN_DIR"/runtimes.json "$SIM_RUN_DIR"/devicetypes.json "$SIM_RUN_DIR"/devices.json "$SIM_RUN_DIR"/command.out
        /bin/rmdir -- "$SIM_RUN_DIR" 2>/dev/null
    fi
}
# 中断只停止当前命令，已创建的设备保留，并显示可追踪的 UDID。
sim_handle_signal() {
    sim_log '⚠ 已停止当前操作。'
    if [[ -n "$SIM_UDID" ]]; then
        sim_log "➤ 新设备已保留：${SIM_NAME}（${SIM_UDID}）。可在 Simulator 中继续启动。"
    fi
    exit 130
}
# zsh 在脚本退出时清理；顶层特殊函数避免函数内部 EXIT trap 提前清理目录。
TRAPEXIT() {
    sim_cleanup
}
# 将终端中断转为有提示的安全停止。
TRAPINT() {
    sim_handle_signal
}
# 关闭终端时保留已创建的设备并停止当前命令。
TRAPHUP() {
    sim_handle_signal
}
# 外部终止遵循相同的保留设备策略。
TRAPTERM() {
    sim_handle_signal
}
# 确认后准备私有临时目录；只读体检仅使用临时快照，不保留日志。
sim_initialize_runtime() {
    local old_umask="$(umask)"
    umask 077
    SIM_RUN_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.XXXXXX")" || exit 1
    if [[ "$SIM_MODE" == interactive ]]; then
        if ! (setopt NO_CLOBBER; : > "$LOG_FILE") 2>/dev/null; then
            sim_log "✖ 无法安全创建日志：${LOG_FILE}"
            /bin/rmdir -- "$SIM_RUN_DIR"
            exit 1
        fi
        SIM_LOG_READY=1
    fi
    umask "$old_umask"
    if [[ "$SIM_MODE" == interactive ]]; then
        sim_log "➤ 操作：只新增模拟器；保留现有设备。日志：${LOG_FILE}"
    else
        sim_log '➤ 操作：只读检查，临时快照退出时清理，不创建日志。'
    fi
}
# 以有限等待运行指定命令，超时停止本次进程，保留输出供错误定位。
sim_run_to_file() {
    local output="$1" limit="$2"
    shift 2
    local ticks=0 result=0
    "$@" > "$output" 2>&1 &
    SIM_ACTIVE_PID=$!
    while kill -0 "$SIM_ACTIVE_PID" 2>/dev/null; do
        if (( ticks >= limit * 10 )); then
            kill -TERM "$SIM_ACTIVE_PID" 2>/dev/null
            /bin/sleep 0.2
            kill -KILL "$SIM_ACTIVE_PID" 2>/dev/null
            wait "$SIM_ACTIVE_PID" 2>/dev/null
            SIM_ACTIVE_PID=""
            sim_log "✖ 命令等待超过 ${limit} 秒：$*"
            return 124
        fi
        /bin/sleep 0.1
        (( ticks += 1 ))
    done
    wait "$SIM_ACTIVE_PID" || result=$?
    SIM_ACTIVE_PID=""
    return "$result"
}
# 使用系统 JXA 解析 simctl JSON，避免依赖 Homebrew、Python 或 jq。
sim_data() {
    /usr/bin/osascript -l JavaScript - "$@" <<'JXA'
ObjC.import('Foundation');
function run(args) {
    function json(path) {
        var data = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
        if (!data) throw Error('无法读取模拟器快照：' + path);
        return JSON.parse(ObjC.unwrap(data));
    }
    function text(value) {
        if (typeof value !== 'string' || !value || /[\x00-\x1f\x7f]/.test(value)) throw Error('模拟器字段无效或包含控制字符');
        return value;
    }
    function id(value, prefix) {
        if (!text(value).startsWith(prefix) || !/^[A-Za-z0-9._-]+$/.test(value)) throw Error('模拟器标识格式无效');
        return value;
    }
    function version(value) {
        if (typeof value !== 'string' || !/^\d+(?:\.\d+){0,2}$/.test(value)) throw Error('系统版本格式无效');
        var parts = value.split('.').map(Number);
        while (parts.length < 3) parts.push(0);
        return parts[0] * 65536 + parts[1] * 256 + parts[2];
    }
    function runtimeList(path) {
        var value = json(path);
        if (!value || !Array.isArray(value.runtimes)) throw Error('Runtime JSON 缺少 runtimes 数组');
        return value.runtimes;
    }
    function deviceList(path) {
        var value = json(path);
        if (!value || !Array.isArray(value.devicetypes)) throw Error('设备 JSON 缺少 devicetypes 数组');
        return value.devicetypes;
    }
    if (args[0] === 'health') return 'jxa-ready';
    if (args[0] === 'app') {
        var appPath = text(args[1]), bundle = $.NSBundle.bundleWithPath(appPath);
        var bundleID = ObjC.unwrap(bundle.bundleIdentifier);
        if (bundleID !== 'com.apple.iphonesimulator' && bundleID !== 'com.apple.dt.Devices') throw Error('模拟器应用 Bundle ID 无效');
        var executable = ObjC.unwrap(bundle.executablePath);
        if (!executable || !$.NSFileManager.defaultManager.isExecutableFileAtPath(executable)) throw Error('模拟器应用可执行文件缺失');
        return bundleID;
    }
    if (args[0] === 'runtimes') {
        var seen = Object.create(null), seenIDs = Object.create(null), rows = [], arch = args[2];
        runtimeList(args[1]).forEach(function (entry) {
            if (entry.isAvailable !== true || !/^com\.apple\.CoreSimulator\.SimRuntime\.iOS-/.test(entry.identifier || '')) return;
            if (Array.isArray(entry.supportedArchitectures) && entry.supportedArchitectures.indexOf(arch) < 0) return;
            var name = text(entry.name), identifier = id(entry.identifier, 'com.apple.CoreSimulator.SimRuntime.iOS-');
            var value = version(entry.version);
            if (seen[name] || seenIDs[identifier]) return;
            seen[name] = true;
            seenIDs[identifier] = true;
            rows.push({name:name, id:identifier, value:value});
        });
        rows.sort(function (a,b) { return b.value - a.value || a.name.localeCompare(b.name); });
        return rows.map(function (row) { return row.name + '\t' + row.id; }).join('\n');
    }
    if (args[0] === 'devices') {
        var matches = runtimeList(args[1]).filter(function (runtime) { return runtime.identifier === args[3] && runtime.isAvailable === true; });
        if (!matches.length) throw Error('选定 Runtime 不再可用，请重新运行');
        var runtime = matches[0], allowed = null, seen = Object.create(null);
        if (Array.isArray(runtime.supportedDeviceTypes)) {
            allowed = Object.create(null);
            runtime.supportedDeviceTypes.forEach(function (device) { allowed[id(device.identifier, 'com.apple.CoreSimulator.SimDeviceType.')] = true; });
        }
        var runtimeVersion = version(runtime.version), rows = [];
        deviceList(args[2]).forEach(function (device) {
            if (device.productFamily ? (device.productFamily !== 'iPhone' && device.productFamily !== 'iPad') : !/^iPhone |^iPad /.test(device.name || '')) return;
            var identifier = id(device.identifier, 'com.apple.CoreSimulator.SimDeviceType.'), name = text(device.name);
            if (seen[identifier]) return;
            if (allowed !== null && !allowed[identifier]) return;
            if (allowed === null) {
                var minimum = typeof device.minRuntimeVersion === 'number' ? device.minRuntimeVersion : (device.minRuntimeVersionString ? version(device.minRuntimeVersionString) : null);
                var maximum = typeof device.maxRuntimeVersion === 'number' ? device.maxRuntimeVersion : (device.maxRuntimeVersionString ? version(device.maxRuntimeVersionString) : null);
                if (minimum !== null && runtimeVersion < minimum) return;
                if (maximum !== null && runtimeVersion > maximum) return;
            }
            seen[identifier] = true;
            rows.push(name + '\t' + identifier);
        });
        return rows.join('\n');
    }
    if (args[0] === 'unique-name') {
        var payload = json(args[1]), names = Object.create(null), base = text(args[2]);
        if (!payload || !payload.devices || Array.isArray(payload.devices) || typeof payload.devices !== 'object') throw Error('已有设备 JSON 缺少 devices 对象');
        Object.keys(payload.devices).forEach(function (runtime) {
            if (!Array.isArray(payload.devices[runtime])) throw Error('已有设备 JSON 格式无效');
            payload.devices[runtime].forEach(function (device) { names[text(device.name)] = true; });
        });
        var name = base, suffix = 2;
        while (names[name]) name = base + ' (' + suffix++ + ')';
        return name;
    }
    throw Error('未知数据操作');
}
JXA
}
# 体检当前 Xcode 工具链及系统解析器，不变更 xcode-select 或安装任何依赖。
sim_check_environment() {
    local output="$SIM_RUN_DIR/command.out" simctl_path="" jxa_health="" candidate="" app_kind=""
    if [[ "$(/usr/bin/uname -s)" != Darwin ]]; then
        sim_log '✖ 此脚本仅适用于 macOS。'
        return 1
    fi
    if ! sim_run_to_file "$output" 20 /usr/bin/xcrun --find simctl; then
        sim_log '✖ xcrun 无法定位 simctl。请安装完整 Xcode，完成首次启动与组件安装。'
        sim_log "$(<"$output")"
        return 1
    fi
    simctl_path="$(<"$output")"
    if [[ ! -x "$simctl_path" || "$simctl_path" != */usr/bin/simctl ]]; then
        sim_log "✖ simctl 路径不可执行：${simctl_path}"
        return 1
    fi
    SIM_DEVELOPER_DIR="${simctl_path%/usr/bin/simctl}"
    if ! jxa_health="$(sim_data health 2>&1)" || [[ "$jxa_health" != jxa-ready ]]; then
        sim_log "✖ 系统 JavaScript for Automation 不可用：${jxa_health}"
        return 1
    fi
    SIM_APP=""
    SIM_APP_KIND=""
    for candidate in "$SIM_DEVELOPER_DIR/Applications/Simulator.app" "${SIM_DEVELOPER_DIR:h}/Applications/Simulator.app" "${SIM_DEVELOPER_DIR:h}/Applications/DeviceHub.app"; do
        [[ -d "$candidate" ]] || continue
        if app_kind="$(sim_data app "$candidate" 2>&1)"; then
            SIM_APP="$candidate"
            SIM_APP_KIND="$app_kind"
            break
        fi
    done
    if [[ -z "$SIM_APP" ]]; then
        sim_log "✖ 当前 Xcode 缺少健康的 Simulator / Device Hub：${SIM_DEVELOPER_DIR}"
        return 1
    fi
    SIM_FZF="$(command -v fzf 2>/dev/null)"
    if [[ -n "$SIM_FZF" ]]; then
        if ! sim_run_to_file "$output" 5 "$SIM_FZF" --version; then
            SIM_FZF=""
        fi
    fi
    sim_log "✔ 当前 Xcode 工具链：${SIM_DEVELOPER_DIR}"
    if [[ -n "$SIM_FZF" ]]; then
        sim_log '➤ 选择方式：本机健康 fzf（Esc 取消）。'
    else
        sim_log '➤ 选择方式：原生编号列表（输入 q 取消），无需安装额外工具。'
    fi
}
# 获取结构化清单，任一命令失败都停止，不把错误文本当作设备数据。
sim_load_catalog() {
    local kind="" file=""
    for kind in runtimes devicetypes devices; do
        file="$SIM_RUN_DIR/${kind}.json"
        if ! sim_run_to_file "$file" 30 /usr/bin/xcrun simctl list "$kind" --json; then
            sim_log "✖ 读取模拟器清单失败：xcrun simctl list ${kind} --json"
            sim_log "$(<"$file")"
            return 1
        fi
    done
}
# 选择指定列表，空输入、EOF、Esc 和 q 均不会回退到默认设备。
sim_choose_row() {
    local title="$1" content="$2" answer="" index=0 result=0
    SIM_SELECTED_ROW=""
    SIM_ROWS=("${(@f)content}")
    if [[ -z "$content" || ${#SIM_ROWS} == 0 ]]; then
        return 2
    fi
    sim_log "➤ ${title}"
    if [[ -n "$SIM_FZF" ]]; then
        SIM_SELECTED_ROW="$(print -rl -- "${SIM_ROWS[@]}" | "$SIM_FZF" --delimiter=$'\t' --with-nth=1 --height=60% --reverse --prompt="${title} > ")" || result=$?
        if (( result != 0 )) || [[ -z "$SIM_SELECTED_ROW" ]]; then
            SIM_CANCELLED=1
            return 130
        fi
        if (( ${SIM_ROWS[(Ie)$SIM_SELECTED_ROW]} == 0 )); then
            sim_log '✖ 选择结果不属于当前清单，已停止。'
            return 1
        fi
    else
        for (( index=1; index<=${#SIM_ROWS}; index++ )); do
            sim_log "${index}、${SIM_ROWS[index]%%$'\t'*}"
        done
        while true; do
            if ! IFS= read -r "?输入编号（q 取消）：" answer || [[ -z "$answer" || "$answer" == [qQ] || "$answer" == $'\e' ]]; then
                SIM_CANCELLED=1
                return 130
            fi
            if [[ "$answer" == <-> && ${#answer} -le 6 ]]; then
                index=$(( 10#$answer ))
                if (( index >= 1 && index <= ${#SIM_ROWS} )); then
                    SIM_SELECTED_ROW="${SIM_ROWS[index]}"
                    break
                fi
            fi
            sim_log '⚠ 请输入列表内的编号，或输入 q 取消。'
        done
    fi
}
# 先选择已安装系统，再筛选其兼容设备，旧版清单缺兼容元数据时由 create 最终校验。
sim_select_combination() {
    local rows="" result=0
    if ! rows="$(sim_data runtimes "$SIM_RUN_DIR/runtimes.json" "$(/usr/bin/uname -m)" 2>&1)"; then
        sim_log "✖ 无法解析 Runtime：${rows}"
        return 1
    fi
    if [[ -z "$rows" ]]; then
        sim_log '✖ 没有本机可用的 iOS Runtime。请在 Xcode → Settings → Components 安装后重试。'
        return 1
    fi
    sim_choose_row '选择 iOS 系统版本' "$rows" || return $?
    SIM_RUNTIME_NAME="${SIM_SELECTED_ROW%%$'\t'*}"
    SIM_RUNTIME_ID="${SIM_SELECTED_ROW#*$'\t'}"
    if ! rows="$(sim_data devices "$SIM_RUN_DIR/runtimes.json" "$SIM_RUN_DIR/devicetypes.json" "$SIM_RUNTIME_ID" 2>&1)"; then
        sim_log "✖ 无法解析兼容设备：${rows}"
        return 1
    fi
    if [[ -z "$rows" ]]; then
        sim_log "⚠ ${SIM_RUNTIME_NAME} 没有兼容的 iPhone / iPad，请选择其它系统版本。"
        return 2
    fi
    sim_choose_row '选择兼容 iPhone / iPad' "$rows" || return $?
    SIM_DEVICE_NAME="${SIM_SELECTED_ROW%%$'\t'*}"
    SIM_DEVICE_ID="${SIM_SELECTED_ROW#*$'\t'}"
}
# 创建前刷新已有名称，避开同秒操作或遗留同名设备。
sim_prepare_unique_name() {
    local base="${SIM_DEVICE_NAME}@$(/bin/date '+%Y.%m.%d %H:%M:%S')-${$}" output=""
    if ! sim_run_to_file "$SIM_RUN_DIR/devices.json" 30 /usr/bin/xcrun simctl list devices --json; then
        sim_log '✖ 刷新已有设备失败，已停止创建。'
        sim_log "$(<"$SIM_RUN_DIR/devices.json")"
        return 1
    fi
    if ! output="$(sim_data unique-name "$SIM_RUN_DIR/devices.json" "$base" 2>&1)"; then
        sim_log "✖ 无法确认唯一设备名：${output}"
        return 1
    fi
    SIM_NAME="$output"
}
# 明确展示即将创建的组合；任意非空输入都取消。
sim_confirm_creation() {
    local answer=""
    sim_log "➤ 设备：${SIM_DEVICE_NAME}"
    sim_log "➤ 系统：${SIM_RUNTIME_NAME}"
    sim_log "➤ 新名称：${SIM_NAME}"
    if ! IFS= read -r "?直接回车创建并启动；输入任意字符取消：" answer || [[ -n "$answer" ]]; then
        SIM_CANCELLED=1
        return 130
    fi
}
# 只新增并启动选定设备；创建结果不明确时停止，避免重试产生重复设备。
sim_create_and_boot() {
    local output="$SIM_RUN_DIR/command.out" result=0 value=""
    sim_log "➤ 正在创建：${SIM_NAME}"
    sim_run_to_file "$output" 30 /usr/bin/xcrun simctl create "$SIM_NAME" "$SIM_DEVICE_ID" "$SIM_RUNTIME_ID" || result=$?
    value="$(<"$output")"
    if (( result != 0 )); then
        if (( result != 124 )) && [[ "$value" == *'Unable to create a device for device type'* || "$value" == *'Incompatible device'* ]]; then
            sim_log "⚠ 当前设备 / 系统组合不受支持，可重新选择：${value}"
            return 2
        fi
        sim_log "✖ 创建未成功确认（退出码 ${result}）：${value}"
        sim_log '➤ 已停止，未自动重试。若命令曾超时，请先检查 Simulator 设备列表。'
        return 1
    fi
    if [[ ! "$value" =~ '^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$' ]]; then
        sim_log "✖ 创建命令返回的 UDID 无效：${value}"
        sim_log '➤ 已停止，未自动重试；请检查 Simulator 设备列表。'
        return 1
    fi
    SIM_UDID="$value"
    sim_log "✔ 模拟器已创建：${SIM_NAME}（${SIM_UDID}）"
    if ! sim_run_to_file "$output" 30 /usr/bin/xcrun simctl boot "$SIM_UDID"; then
        sim_log "✖ 启动失败：$(<"$output")"
        sim_log "➤ 新设备已保留。可稍后运行：xcrun simctl boot ${SIM_UDID}"
        return 1
    fi
    if ! sim_run_to_file "$output" 15 /usr/bin/open -a "$SIM_APP"; then
        sim_log "✖ 无法打开模拟器界面：$(<"$output")"
        sim_log "➤ 已保留设备：${SIM_UDID}"
        return 1
    fi
    if ! sim_run_to_file "$output" 120 /usr/bin/xcrun simctl bootstatus "$SIM_UDID"; then
        sim_log "⚠ 设备已创建并发起启动，但尚未确认完成：$(<"$output")"
        sim_log "➤ 请在 Simulator 查看 ${SIM_NAME}（${SIM_UDID}）。"
        return 1
    fi
    sim_log "✔ 新模拟器已完成启动：${SIM_NAME}"
    if [[ "$SIM_APP_KIND" == com.apple.dt.Devices ]]; then
        sim_log "➤ 已打开 Device Hub；可按设备名选中 ${SIM_NAME}（${SIM_UDID}）。"
    fi
}
# 交互取消正常返回；仅明确不兼容时回到选择，不重复创建已确认的设备。
sim_interactive_loop() {
    local result=0
    while true; do
        result=0
        sim_select_combination || result=$?
        if (( result == 130 )); then
            sim_log '➤ 已取消，未创建模拟器。'
            return 0
        elif (( result == 2 )); then
            continue
        elif (( result != 0 )); then
            return "$result"
        fi
        sim_prepare_unique_name || return $?
        if ! sim_confirm_creation; then
            sim_log '➤ 已取消，未创建模拟器。'
            return 0
        fi
        result=0
        sim_create_and_boot || result=$?
        if (( result == 2 )); then
            continue
        fi
        return "$result"
    done
}
# 显示独立运行接口，不加载或修改模拟器环境。
sim_show_help() {
    sim_log '用法：/bin/zsh CreateIOSSimulator.zsh [--help | --check]'
    sim_log '  无参数   在可交互终端中选择并新建一个模拟器。'
    sim_log '  --help   显示帮助；不读取 Xcode 或创建日志。'
    sim_log '  --check  只读体检 Xcode / simctl，并列出可用 iOS 系统及兼容设备数量。'
    sim_log '来源：JobsCommand@iOS/其他/【MacOS】📱双击初始化iOS模拟器.command。'
}
# 体检同时验证真实 JSON 数据；没有可用系统或兼容设备时返回失败。
sim_report_catalog() {
    local rows="" devices="" row="" count=0 total=0
    local -a device_rows
    if ! rows="$(sim_data runtimes "$SIM_RUN_DIR/runtimes.json" "$(/usr/bin/uname -m)" 2>&1)"; then
        sim_log "✖ Runtime 数据无效：${rows}"
        return 1
    fi
    if [[ -z "$rows" ]]; then
        sim_log '✖ 没有本机可用的 iOS Runtime；本次未创建或下载。'
        return 1
    fi
    for row in "${(@f)rows}"; do
        if ! devices="$(sim_data devices "$SIM_RUN_DIR/runtimes.json" "$SIM_RUN_DIR/devicetypes.json" "${row#*$'\t'}" 2>&1)"; then
            sim_log "✖ 兼容设备数据无效：${devices}"
            return 1
        fi
        count=0
        if [[ -n "$devices" ]]; then
            device_rows=("${(@f)devices}")
            count=${#device_rows}
        fi
        (( total += count ))
        sim_log "✔ ${row%%$'\t'*}：${count} 个兼容 iPhone / iPad"
    done
    if (( total == 0 )); then
        sim_log '✖ 可用系统没有兼容的 iPhone / iPad。'
        return 1
    fi
    sim_log '✔ 只读体检完成；未创建、启动、关闭或删除模拟器。'
}
# 将帮助、只读体检与交互创建路由到各自流程，并传播失败状态。
sim_run_requested_action() {
    if [[ "$SIM_MODE" == help ]]; then
        sim_show_help
        return 0
    fi
    sim_initialize_runtime
    sim_check_environment || return $?
    sim_load_catalog || return $?
    if [[ "$SIM_MODE" == check ]]; then
        sim_report_catalog
    else
        sim_interactive_loop
    fi
}
# 编排自述确认与本次请求，所有真实动作都在确认或只读路由后执行。
main() {
    show_script_intro_and_wait "$@" # 首先展示内置自述并校验交互确认或只读入口。
    sim_run_requested_action # 体检工具链与 JSON，再执行本次创建或只读检查。
}

main "$@"
