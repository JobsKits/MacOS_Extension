#!/bin/zsh
# 脚本自述：
# - 脚本名称：InspectFlutterSdkVersion.zsh。
# - 核心用途：查询指定 Flutter 项目当前实际使用的 Flutter SDK 版本与来源；FVM 管理的项目显示 FVM 版本，其它项目显示系统 SDK 版本。
# - 影响范围：只读读取项目配置、SDK 版本和当前进程环境；不安装工具、不下载 SDK、不修改任何项目文件。
# - 运行提示：由 Finder 右键在 Terminal 中打开；首屏自述后按回车开始，Ctrl+C 取消，全程日志直接输出在终端。

typeset FSI_PROJECT=""
typeset FSI_LOG_FILE=""
typeset FSI_RUN_DIR=""
typeset FSI_MACHINE_FILE=""
typeset FSI_FLUTTER=""
typeset FSI_SDK_ROOT=""
typeset FSI_SDK_SOURCE=""
typeset FSI_FVM_CONFIG=""
typeset FSI_FVM_PINNED=""
typeset FSI_FVM_LINK_VERSION=""
typeset FSI_FRAMEWORK=""
typeset FSI_DART=""
typeset FSI_CHANNEL=""
typeset FSI_FRAMEWORK_REVISION=""
typeset FSI_FRAMEWORK_DATE=""
typeset FSI_ENGINE_REVISION=""
typeset FSI_ENV_SDK=""
typeset FSI_ENV_FLUTTER=""
# Flutter 首次执行 --version --machine 时会生成 Dart kernel snapshot，冷启动明显慢于常规查询。
typeset FSI_PROBE_TIMEOUT=180
typeset FSI_HEALTH_TIMEOUT=25

# 标题红字、正文蓝字；日志始终写入纯文本。
fsi_intro_line() {
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
# 使用系统 JavaScript for Automation 解析 YAML / JSON，不引入 Python / Node 依赖。
fsi_data() {
    /usr/bin/osascript -l JavaScript - "$@" <<'JXA'
ObjC.import('Foundation');
function run(args) {
    function read(path) {
        var data = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
        if (!data) throw Error('无法读取文件：' + path);
        return ObjC.unwrap(data);
    }
    function clean(value) {
        if (typeof value !== 'string' || /[\x00-\x1f\x7f]/.test(value)) throw Error('字段包含控制字符或类型错误');
        return value;
    }
    function scalar(value) {
        value = value.trim();
        if (/^'[^']*'$/.test(value) || /^"[^"\\]*"$/.test(value)) return value.slice(1, -1);
        return value;
    }
    function uncomment(line) {
        var quote = '', result = '';
        for (var i = 0; i < line.length; i++) {
            var c = line[i];
            if (quote) {
                result += c;
                if (c === '\\' && quote === '"') { result += line[++i] || ''; continue; }
                if (c === quote) {
                    if (quote === "'" && line[i + 1] === "'") { result += line[++i]; continue; }
                    quote = '';
                }
            } else if (c === '#' && (i === 0 || /\s/.test(line[i - 1]))) break;
            else { result += c; if (c === "'" || c === '"') quote = c; }
        }
        return result.replace(/\s+$/, '');
    }
    function flow(text) {
        var pos = 0;
        function space() { while (/\s/.test(text[pos] || '') && pos < text.length) pos++; }
        function token() {
            space(); var start = pos, quote = text[pos];
            if (quote === '"' || quote === "'") {
                pos++; while (pos < text.length && text[pos] !== quote) { if (text[pos] === '\\') throw Error('不支持转义 flow scalar'); pos++; }
                if (text[pos++] !== quote) throw Error('引号未闭合');
                return text.slice(start + 1, pos - 1);
            }
            while (pos < text.length && !/[,:{}\[\]]/.test(text[pos])) pos++;
            var result = text.slice(start, pos).trim();
            if (!result || /[&*!|>]/.test(result)) throw Error('不支持该 YAML flow 写法');
            return result;
        }
        function map() {
            space(); if (text[pos++] !== '{') throw Error('要求 flow map');
            var result = Object.create(null); space();
            while (text[pos] !== '}') {
                var key = token(); space(); if (text[pos++] !== ':') throw Error('缺少冒号'); space();
                if (Object.prototype.hasOwnProperty.call(result, key)) throw Error('重复 YAML key：' + key);
                result[key] = text[pos] === '{' ? map() : token(); space();
                if (text[pos] === ',') { pos++; space(); } else if (text[pos] !== '}') throw Error('flow map 格式无效');
            }
            pos++; return result;
        }
        var result = map(); space(); if (pos !== text.length) throw Error('flow map 末尾有额外内容');
        return result;
    }
    // 读全部可读的 key: value 行；Tab 缩进与多文档标记直接拒绝，避免猜错层级。
    function loadEntries(path) {
        var lines = read(path).replace(/^\uFEFF/, '').split(/\r?\n/), entries = [];
        lines.forEach(function (line, i) {
            var cleanLine = uncomment(line);
            if (!cleanLine) return;
            if (/^[ \t]*\t/.test(cleanLine)) throw Error('缩进含 Tab，无法安全识别');
            if (/^\s*(?:---|\.\.\.)(?:\s|$)/.test(cleanLine)) throw Error('不支持 YAML 文档分隔标记');
            var indent = cleanLine.length - cleanLine.replace(/^ +/, '').length;
            var match = /^([^:]+):(?:\s+(.*)|\s*)$/.exec(cleanLine.slice(indent));
            if (!match) return;
            entries.push({ index: i, indent: indent, key: scalar(match[1]), value: (match[2] || '').trim() });
        });
        return entries;
    }
    // 取某节点的直接子节点：大于父缩进且取最小缩进，遇到回缩即截断。
    function childrenOf(entries, parent) {
        var result = [];
        if (!parent) {
            return entries.filter(function (entry) { return entry.indent === 0; });
        }
        for (var i = 0; i < entries.length; i++) {
            if (entries[i].index <= parent.index) continue;
            if (entries[i].indent <= parent.indent) break;
            result.push(entries[i]);
        }
        if (result.length === 0) return [];
        var minimum = Math.min.apply(null, result.map(function (entry) { return entry.indent; }));
        return result.filter(function (entry) { return entry.indent === minimum; });
    }
    // 根级 key 必须唯一，否则不参与后续判定。
    function uniqueRoot(entries, key) {
        var roots = childrenOf(entries, null).filter(function (entry) { return entry.key === key; });
        return roots.length === 1 ? roots[0] : null;
    }
    // 逐层确认 dependencies.flutter.sdk 是 flutter，支持 block 与单行 flow 两种常见写法。
    function assertFlutterSDKDependency(entries, dependencies) {
        if (dependencies.value) {
            var flattened = flow(dependencies.value);
            if (!flattened.flutter) throw Error('缺少 dependencies.flutter');
            // 嵌套 flow map 已被解析成对象，只有仍是字符串的单行写法才需要二次解析。
            var nested = typeof flattened.flutter === 'string' ? flow(flattened.flutter) : flattened.flutter;
            if (!nested || nested.sdk !== 'flutter') throw Error('dependencies.flutter.sdk 不是 flutter');
            return true;
        }
        var declarations = childrenOf(entries, dependencies).filter(function (entry) { return entry.key === 'flutter'; });
        if (declarations.length !== 1) throw Error('缺少唯一直接依赖 flutter');
        var declaration = declarations[0];
        if (declaration.value) {
            if (flow(declaration.value).sdk !== 'flutter') throw Error('dependencies.flutter.sdk 不是 flutter');
            return true;
        }
        var fields = childrenOf(entries, declaration).filter(function (entry) { return entry.key === 'sdk'; });
        if (fields.length !== 1) throw Error('缺少唯一 sdk 声明');
        if (scalar(fields[0].value) !== 'flutter') throw Error('dependencies.flutter.sdk 不是 flutter');
        return true;
    }
    if (args[0] === 'directory-kind') {
        var url = $.NSURL.fileURLWithPath(args[1]);
        var properties = ObjC.deepUnwrap(url.resourceValuesForKeysError($([$.NSURLIsDirectoryKey, $.NSURLIsPackageKey, $.NSURLIsAliasFileKey, $.NSURLIsSymbolicLinkKey]), null));
        if (!properties || properties.NSURLIsDirectoryKey !== true || properties.NSURLIsPackageKey !== false ||
            properties.NSURLIsAliasFileKey !== false || properties.NSURLIsSymbolicLinkKey !== false) throw Error('目标不是普通目录，或是 package / Alias / 符号链接');
        return 'directory';
    }
    if (args[0] === 'pubspec') {
        var manifestEntries = loadEntries(args[1]);
        var dependencies = uniqueRoot(manifestEntries, 'dependencies');
        if (!dependencies) throw Error('必须有唯一根级 dependencies');
        if (assertFlutterSDKDependency(manifestEntries, dependencies)) return 'flutter';
        throw Error('未识别到 Flutter SDK 依赖');
    }
    if (args[0] === 'environment') {
        var environment = uniqueRoot(loadEntries(args[1]), 'environment');
        if (!environment) return '';
        if (environment.value) {
            var inline = flow(environment.value);
            return (inline.sdk || '') + '\t' + (inline.flutter || '');
        }
        var constraints = { sdk: '', flutter: '' };
        childrenOf(loadEntries(args[1]), environment).forEach(function (entry) {
            if (entry.key === 'sdk') constraints.sdk = scalar(entry.value);
            if (entry.key === 'flutter') constraints.flutter = scalar(entry.value);
        });
        return constraints.sdk + '\t' + constraints.flutter;
    }
    if (args[0] === 'fvm-config') {
        var config = JSON.parse(read(args[1]));
        if (!config || Array.isArray(config) || typeof config !== 'object') throw Error('FVM 配置不是 JSON 对象');
        return clean(config.flutter || config.flutterSdkVersion || '');
    }
    if (args[0] === 'machine') {
        var machine = JSON.parse(read(args[1]));
        if (!machine || typeof machine !== 'object') throw Error('Flutter --version --machine 输出不是 JSON 对象');
        var pieces = [
            clean(machine.frameworkVersion || ''),
            clean(machine.dartSdkVersion || ''),
            clean(machine.channel || ''),
            clean(machine.frameworkRevision || ''),
            clean(machine.frameworkCommitDate || ''),
            clean(machine.engineRevision || ''),
            clean(machine.flutterRoot || '')
        ];
        if (!/^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/.test(pieces[0])) throw Error('Flutter Framework 版本格式无效');
        return pieces.join('\t');
    }
    throw Error('未知数据操作');
}
JXA
}
# 只读检查精确目标，拒绝把父目录、注释、纯 Dart 或 flutter_test 当成 Flutter 项目。
fsi_validate_invocation() {
    local original="" size=""
    [[ "$#" == 2 && "$1" == --project && -n "$2" && -d "$2" ]] || {
        print -u2 -r -- '✖ 用法：/bin/zsh InspectFlutterSdkVersion.zsh --project <Flutter项目目录>'
        exit 1
    }
    original="$2"
    while [[ "$original" == */ && "$original" != / ]]; do original="${original%/}"; done
    [[ -n "$original" && "$original" != / && ! -L "$original" ]] || { print -u2 -r -- '✖ 目标必须是普通文件夹，不能是符号链接或文件系统根目录。'; exit 1; }
    fsi_data directory-kind "$original" >/dev/null || { print -u2 -r -- '✖ 目标不是可确认的普通文件夹；请避开 package / Alias / 符号链接。'; exit 1; }
    case "${original:e:l}" in app|appex|framework|bundle|xcodeproj|xcworkspace|playground|photoslibrary|workflow) print -u2 -r -- '✖ 不处理应用或工程 package，请选择包含 pubspec.yaml 的普通项目文件夹。'; exit 1 ;; esac
    FSI_PROJECT="${original:A}"
    [[ -f "$FSI_PROJECT/pubspec.yaml" && ! -L "$FSI_PROJECT/pubspec.yaml" ]] || {
        print -u2 -r -- '✖ 目标同层缺少普通 pubspec.yaml，不搜索父目录或子目录。'
        exit 1
    }
    size="$(/usr/bin/stat -f %z "$FSI_PROJECT/pubspec.yaml" 2>/dev/null)"
    [[ "$size" == <-> && "$size" -le 1048576 ]] || { print -u2 -r -- '✖ pubspec.yaml 超过 1 MiB 或无法读取，已停止。'; exit 1; }
    fsi_data pubspec "$FSI_PROJECT/pubspec.yaml" >/dev/null || {
        print -u2 -r -- '✖ 无法确认 dependencies.flutter.sdk: flutter；YAML 锚点 / 多行 flow 等复杂写法请先人工确认并改成普通 block。'
        exit 1
    }
}
# 第一屏说明用途与只读边界；精确项目只读校验通过后才等待回车。
show_script_intro_and_wait() {
    local answer=""
    fsi_intro_line title '━━━━━━━━━━ 查看当前 Flutter SDK 版本 ━━━━━━━━━━'
    fsi_intro_line body '1、只读取指定目录自身的 Flutter 项目配置与 SDK 版本，不安装工具、不下载 SDK、不修改任何文件。'
    fsi_intro_line body '2、项目由 FVM 管理且已链接 SDK 时显示 FVM 版本；没有 FVM 或 SDK 未链接时显示系统 Flutter SDK 环境。'
    fsi_intro_line body '3、版本结论以该 SDK 实际执行 flutter --version --machine 的输出为准，并与 .fvmrc 配置和 pubspec environment 约束核对。'
    fsi_intro_line body '4、PATH 与环境变量只在本脚本及其子进程内生效，不写入 Shell 配置。Ctrl+C 随时取消。'
    fsi_validate_invocation "$@"
    fsi_intro_line body "目标目录：$FSI_PROJECT"
    [[ -t 0 && -t 1 ]] || { print -u2 -r -- '✖ 需要可交互 Terminal；没有 TTY，已停止。'; exit 1; }
    IFS= read -r 'answer?👉 已了解用途与影响，按回车继续；Ctrl+C 取消：' || exit 1
}
# 确认后才建立私有日志，并把抑制遥测的环境变量限定在当前进程与子进程。
fsi_initialize_runtime() {
    setopt NO_NOMATCH
    umask 077
    FSI_RUN_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/JobsFlutterSdkInspector.XXXXXX")" || exit 1
    FSI_LOG_FILE="$FSI_RUN_DIR/InspectFlutterSdkVersion.log"
    FSI_MACHINE_FILE="$FSI_RUN_DIR/machine.json"
    : > "$FSI_LOG_FILE" || exit 1
    export DART_SUPPRESS_ANALYTICS=true FLUTTER_SUPPRESS_ANALYTICS=true NO_COLOR=1
    trap 'fsi_handle_signal INT 130' INT
    trap 'fsi_handle_signal TERM 143' TERM
    cd -P -- "$FSI_PROJECT" || { print -u2 -r -- '✖ 无法进入目标目录'; exit 1; }
    fsi_log "ℹ 目标：$FSI_PROJECT"
    fsi_log "ℹ 日志：$FSI_LOG_FILE"
}
# 同步写入终端与纯文本日志，不在日志中注入 ANSI。
fsi_log() {
    print -r -- "$*" | /usr/bin/tee -a "$FSI_LOG_FILE"
}
# 给出准确失败层级后退出，并始终保留本次日志路径。
fsi_fail() {
    print -r -- "✖ $1；日志：${FSI_LOG_FILE:-（未创建）}" | /usr/bin/tee -a "${FSI_LOG_FILE:-/dev/null}"
    exit "${2:-1}"
}
# 中断时保留日志，便于人工查看已完成的只读结果。
fsi_handle_signal() {
    fsi_fail "已收到 $1，查询中断" "$2"
}
# 只依赖 macOS 自带工具：zsh / osascript / uname 均来自系统。
fsi_check_system() {
    [[ "$(/usr/bin/uname -s)" == Darwin ]] || fsi_fail '本脚本只适用于 macOS'
    [[ -x /bin/zsh && -x /usr/bin/osascript ]] || fsi_fail '系统 zsh 或 osascript 不可用'
    fsi_log "✔ 系统 $(/usr/bin/sw_vers -productVersion 2>/dev/null || print -r -- 未知)；架构：$(/usr/bin/uname -m)"
}
# 按原顺序去重并解析真实路径，避免重复体检同一个 SDK。
fsi_dedup_candidates() {
    local candidate=""
    local -a unique=()
    for candidate in "$@"; do
        [[ -n "$candidate" ]] || continue
        candidate="${candidate:A}"
        [[ -x "$candidate" ]] || continue
        (( ${unique[(Ie)$candidate]} )) || unique+=( "$candidate" )
    done
    print -r -- "${(j:|:)unique}"
}
# 读取 FVM 配置：新版 .fvmrc 优先，兼容旧版 .fvm/fvm_config.json。
fsi_read_fvm_config() {
    if [[ -f "$FSI_PROJECT/.fvmrc" && ! -L "$FSI_PROJECT/.fvmrc" ]]; then
        FSI_FVM_CONFIG="$FSI_PROJECT/.fvmrc"
    elif [[ -f "$FSI_PROJECT/.fvm/fvm_config.json" && ! -L "$FSI_PROJECT/.fvm/fvm_config.json" ]]; then
        FSI_FVM_CONFIG="$FSI_PROJECT/.fvm/fvm_config.json"
    else
        return 1
    fi
    FSI_FVM_PINNED="$(fsi_data fvm-config "$FSI_FVM_CONFIG" 2>> "$FSI_LOG_FILE")" || fsi_fail '无法读取 FVM 配置；请确认文件内容为普通 JSON 对象'
    fsi_log "ℹ FVM 配置文件：$FSI_FVM_CONFIG"
    return 0
}
# 项目 .fvm/flutter_sdk 是 FVM 的实际生效点：存在且自带 flutter 才算 FVM 项目 SDK。
fsi_resolve_project_fvm_sdk() {
    local link_path="$FSI_PROJECT/.fvm/flutter_sdk" linked=""
    [[ -L "$link_path" ]] || return 1
    [[ -x "$link_path/bin/flutter" ]] || return 1
    linked="${link_path:A}"
    FSI_FLUTTER="${link_path:A}/bin/flutter"
    FSI_SDK_ROOT="$linked"
    FSI_FVM_LINK_VERSION="${linked:t}"
    FSI_SDK_SOURCE='FVM 项目 SDK（.fvm/flutter_sdk）'
    fsi_log "✔ FVM 链接已生效：flutter_sdk → $linked"
    return 0
}
# 没有可用 FVM 链接时寻找系统 Flutter SDK；被 FVM 接管的 PATH 入口也按系统层处理。
fsi_resolve_system_sdk() {
    fsi_log '✖ 项目 FVM SDK 缺失或未正确链接；不会读取系统 Flutter。'
    return 1
}

# 先记录 FVM 声明版本，再判断它是否已经通过 .fvm/flutter_sdk 真正生效。
fsi_resolve_sdk_source() {
    fsi_read_fvm_config || true
    if fsi_resolve_project_fvm_sdk; then
        return 0
    fi
    if [[ -n "$FSI_FVM_CONFIG" ]]; then
        if [[ -n "$FSI_FVM_PINNED" ]]; then
            fsi_log "⚠ .fvmrc 已指定 $FSI_FVM_PINNED，但项目 .fvm/flutter_sdk 尚未链接或不可用；本次显示的是系统 Flutter SDK。请在终端执行 fvm use <版本> 后再查询。"
        else
            fsi_log '⚠ 存在 FVM 配置但没有指定具体版本，也没有可用的 .fvm/flutter_sdk；本次显示的是系统 Flutter SDK。'
        fi
    else
        fsi_log 'ℹ 项目不由 FVM 管理（缺少 .fvmrc / .fvm/fvm_config.json）；本次显示的是系统 Flutter SDK。'
    fi
    fsi_resolve_system_sdk || fsi_fail '未找到可执行的 Flutter SDK。请先安装 Flutter 或用 FVM 安装版本；本脚本不自动安装 SDK'
}
# 用轮询代替 GNU timeout；Flutter 冷启动会生成 kernel snapshot，需要较长等待窗口。
fsi_probe_with_timeout() {
    local executable="$1" seconds="$2" pid="" waited=0 result=0
    ( exec "$executable" --version --machine ) > "$FSI_MACHINE_FILE.raw" 2>> "$FSI_LOG_FILE" &
    pid=$!
    while (( waited < seconds )); do
        if ! /bin/kill -0 "$pid" 2>/dev/null; then
            wait "$pid" 2>> "$FSI_LOG_FILE"
            result=$?
            return "$result"
        fi
        /bin/sleep 1
        waited=$(( waited + 1 ))
    done
    /bin/kill -TERM "$pid" 2>/dev/null || true
    /bin/sleep 1
    /bin/kill -KILL "$pid" 2>/dev/null || true
    wait "$pid" 2>> "$FSI_LOG_FILE" || true
    fsi_log "⚠ SDK 版本查询超时（${seconds}s），已停止候选：$executable"
    return 124
}
# 实际执行该 SDK 并解析机器可读输出；这是唯一被采信的版本来源。
fsi_read_sdk_version() {
    local pieces="" remaining=""
    fsi_log "▶ 执行：Flutter --version --machine；SDK：$FSI_FLUTTER"
    fsi_probe_with_timeout "$FSI_FLUTTER" "$FSI_PROBE_TIMEOUT" || fsi_fail "Flutter SDK 实际执行失败（详情见日志）：$FSI_FLUTTER"
    [[ -f "$FSI_MACHINE_FILE.raw" ]] && /usr/bin/grep -q '[^[:space:]]' "$FSI_MACHINE_FILE.raw" || fsi_fail 'Flutter --version --machine 没有返回有效输出'
    /bin/mv -- "$FSI_MACHINE_FILE.raw" "$FSI_MACHINE_FILE" || fsi_fail '无法保存本次版本输出'
    pieces="$(fsi_data machine "$FSI_MACHINE_FILE" 2>> "$FSI_LOG_FILE")" || fsi_fail 'Flutter 机器可读版本输出无法解析'
    FSI_FRAMEWORK="${pieces%%$'\t'*}"
    remaining="${pieces#*$'\t'}"
    FSI_DART="${remaining%%$'\t'*}"
    remaining="${remaining#*$'\t'}"
    FSI_CHANNEL="${remaining%%$'\t'*}"
    remaining="${remaining#*$'\t'}"
    FSI_FRAMEWORK_REVISION="${remaining%%$'\t'*}"
    remaining="${remaining#*$'\t'}"
    FSI_FRAMEWORK_DATE="${remaining%%$'\t'*}"
    remaining="${remaining#*$'\t'}"
    FSI_ENGINE_REVISION="${remaining%%$'\t'*}"
    remaining="${remaining#*$'\t'}"
    [[ -n "$remaining" ]] && FSI_SDK_ROOT="$remaining"
}
# 读取 pubspec.yaml 的 environment 约束，用于核对项目要求与实际 SDK 是否匹配。
fsi_read_environment_constraints() {
    local constraints=""
    constraints="$(fsi_data environment "$FSI_PROJECT/pubspec.yaml" 2>> "$FSI_LOG_FILE")" || constraints=""
    [[ -n "$constraints" ]] || return 0
    FSI_ENV_SDK="${constraints%%$'\t'*}"
    FSI_ENV_FLUTTER="${constraints#*$'\t'}"
    [[ -n "$FSI_ENV_SDK" ]] && fsi_log "ℹ 项目 environment.sdk：$FSI_ENV_SDK"
    [[ -n "$FSI_ENV_FLUTTER" ]] && fsi_log "ℹ 项目 environment.flutter：$FSI_ENV_FLUTTER"
    return 0
}
# 只判定常见约束写法；任何无法可靠判定的形式都明确输出未判定，不假装满足。
fsi_check_constraint() {
    local name="$1" constraint="$2" actual="$3" bound="" major=""
    local -a parts=()
    autoload -U is-at-least
    [[ -n "$constraint" && "$constraint" != any && "$constraint" != '*' ]] || { fsi_log "ℹ ${name}：无约束"; return 0; }
    [[ -n "$actual" ]] || { fsi_log "⚠ ${name}：实际版本未知，跳过核对。"; return 0; }
    if [[ "$constraint" == *-* || "$constraint" == *+* ]]; then
        fsi_log "⚠ ${name}：约束包含预发布 / build 后缀（$constraint），未做区间判定，请人工核对。"
        return 0
    fi
    parts=( ${=constraint} )
    for part in "${parts[@]}"; do
        if [[ "$part" == \^* ]]; then
            bound="${part#\^}"
            if ! is-at-least "$bound" "$actual"; then
                fsi_log "✖ ${name}：不满足 ^$bound（实际 $actual 低于下限）。"
                return 1
            fi
            major="${bound%%.*}"
            if [[ "$major" == <-> ]] && (( major > 0 )) && is-at-least "$(( major + 1 )).0.0" "$actual"; then
                fsi_log "✖ ${name}：不满足 ^$bound（实际 $actual 已跨过 $major.x 主版本）。"
                return 1
            fi
        elif [[ "$part" == \>=* ]]; then
            bound="${part#>=}"
            is-at-least "$bound" "$actual" || { fsi_log "✖ ${name}：不满足 >=$bound（实际 $actual）。"; return 1; }
        elif [[ "$part" == \<=* ]]; then
            bound="${part#<=}"
            is-at-least "$actual" "$bound" || { fsi_log "✖ ${name}：不满足 <=$bound（实际 $actual）。"; return 1; }
        elif [[ "$part" == \<* ]]; then
            bound="${part#<}"
            if is-at-least "$bound" "$actual"; then
                fsi_log "✖ ${name}：不满足 <$bound（实际 $actual 不低于上限）。"
                return 1
            fi
        elif [[ "$part" == \>* ]]; then
            bound="${part#>}"
            if is-at-least "$actual" "$bound"; then
                fsi_log "✖ ${name}：不满足 >$bound（实际 $actual 不高于下限）。"
                return 1
            fi
        else
            fsi_log "⚠ ${name}：约束写法 $part 超过本脚本判定范围，请人工核对。"
            return 0
        fi
    done
    fsi_log "✔ ${name}：实际 $actual 满足 $constraint。"
    return 0
}
# 汇总展示来源、实际版本与一致性结论，全部内容同时进入日志。
fsi_render_report() {
    local note=""
    fsi_log '━━━━━━━━━━ 查询结果 ━━━━━━━━━━'
    fsi_log "📂 项目：$FSI_PROJECT"
    fsi_log "🔎 来源：$FSI_SDK_SOURCE"
    fsi_log "📦 Flutter 版本：$FSI_FRAMEWORK"
    fsi_log "🎯 Dart 版本：$FSI_DART"
    [[ -n "$FSI_CHANNEL" ]] && fsi_log "🚦 发布渠道：$FSI_CHANNEL"
    fsi_log "📁 SDK 路径：$FSI_SDK_ROOT"
    fsi_log "🛠 SDK 可执行文件：$FSI_FLUTTER"
    [[ -n "$FSI_FRAMEWORK_REVISION" ]] && fsi_log "🔧 Framework revision：$FSI_FRAMEWORK_REVISION"
    [[ -n "$FSI_FRAMEWORK_DATE" ]] && fsi_log "🕒 Framework 提交时间：$FSI_FRAMEWORK_DATE"
    [[ -n "$FSI_ENGINE_REVISION" ]] && fsi_log "⚙ Engine revision：$FSI_ENGINE_REVISION"
    if [[ -n "$FSI_FVM_PINNED" ]]; then
        note="🧩 FVM 配置版本：$FSI_FVM_PINNED"
        if [[ -n "$FSI_FVM_LINK_VERSION" && "$FSI_FVM_LINK_VERSION" == "$FSI_FRAMEWORK" ]]; then
            note="$note；链接目录与实际版本一致"
        elif [[ -n "$FSI_FVM_LINK_VERSION" ]]; then
            note="$note；⚠ 链接目录 $FSI_FVM_LINK_VERSION 与实际版本 $FSI_FRAMEWORK 不一致"
        else
            note="$note；⚠ 项目未链接 .fvm/flutter_sdk，当前结论来自系统 SDK"
        fi
        fsi_log "$note"
    fi
    [[ -n "$FSI_ENV_SDK" ]] && fsi_check_constraint 'environment.sdk（Dart）' "$FSI_ENV_SDK" "$FSI_DART"
    [[ -n "$FSI_ENV_FLUTTER" ]] && fsi_check_constraint 'environment.flutter' "$FSI_ENV_FLUTTER" "$FSI_FRAMEWORK"
    fsi_log "✔ 查询完成，未修改任何项目文件；日志：$FSI_LOG_FILE"
    return 0
}
# 编排首屏自述、环境检查、SDK 定位、版本读取与结果展示。
main() {
    show_script_intro_and_wait "$@" # 首屏展示只读边界，确认精确 Flutter 目录后等待回车。
    fsi_initialize_runtime # 用户确认后才建立私有日志并抑制遥测。
    fsi_check_system # 校验 macOS 自带工具链可用。
    fsi_read_environment_constraints # 先记录项目声明约束，供最后核对。
    fsi_resolve_sdk_source # 判定本次应采信的 SDK：FVM 项目 SDK 或系统 SDK。
    fsi_read_sdk_version # 实际执行该 SDK 取得机器可读版本。
    fsi_render_report # 汇总来源、版本、路径与约束核对结论。
}

main "$@"
