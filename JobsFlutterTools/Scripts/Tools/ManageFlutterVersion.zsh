#!/bin/zsh
# 脚本自述：
# - 脚本名称：ManageFlutterVersion.zsh。
# - 核心用途：只对指定 Flutter 项目，通过 fzf 选择历史或最新版本，再由 FVM 安装 / 切换。
# - 影响范围：经确认后准备缺失工具、FVM 缓存、目标 .fvmrc / .fvm 及 FVM 管理的 IDE / 忽略配置。
# - 运行提示：先阅读自述并回车；依赖安装另行确认，最终回车执行版本安装 / 切换，非空输入取消；Ctrl+C 随时取消。

typeset FM_PROJECT=""
typeset SCRIPT_DIR=""
typeset SCRIPT_PATH=""
typeset SCRIPT_BASENAME="ManageFlutterVersion"
typeset LOG_FILE=""
typeset FM_RUN_DIR=""
typeset FM_BREW=""
typeset FM_BREW_PREFIX=""
typeset FM_FVM=""
typeset FM_FZF=""
typeset FM_GIT=""
typeset FM_CURL=""
typeset FM_CONTEXT_URL=""
typeset FM_CACHE_PATH=""
typeset FM_ORIGINAL_CONFIG=""
typeset FM_ORIGINAL_CONFIG_DIGEST=""
typeset FM_CURRENT="未配置"
typeset FM_SELECTED=""
typeset FM_SELECTED_ROW=""
typeset FM_CHANNEL="stable"
typeset FM_ONLINE=0
typeset FM_MUTATION_STARTED=0
typeset FM_LINK_BEFORE=""
typeset FM_RETURN_FROM_HARMONY=0
typeset FM_NATIVE_CACHE_ROOT=""
typeset FM_RELEASE_URL="https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json"
typeset FM_RELEASE_SOURCE=""
typeset FM_STORAGE_BASE=""
# 官方域名被解析到 127.0.0.1 或代理不可用时，按顺序改用可直连的清单源；第二列是配套 Flutter 资源源。
typeset -a FM_RELEASE_MIRRORS
FM_RELEASE_MIRRORS=(
    'https://storage.flutter-io.cn/flutter_infra_release/releases/releases_macos.json|https://storage.flutter-io.cn'
)

# 只负责展示配色；日志始终使用纯文本。
fm_intro_line() {
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
# 使用系统 JavaScript for Automation 解析 JSON 和有限的常见 pubspec 写法，不增加 Python / jq 依赖。
fm_data() {
    /usr/bin/osascript -l JavaScript - "$@" <<'JXA'
ObjC.import('Foundation');
function run(args) {
    function read(path) {
        var data = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
        if (!data) throw Error('无法读取文件：' + path);
        return ObjC.unwrap(data);
    }
    function json(path) { return JSON.parse(read(path)); }
    function clean(value) {
        if (typeof value !== 'string' || /[\x00-\x1f\x7f]/.test(value)) throw Error('字段包含控制字符或类型错误');
        return value;
    }
    function version(value) { return typeof value === 'string' && /^v?\d+\.\d+\.\d+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?(?:\+[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$/.test(value); }
    function managedHarmony(config) {
        var home = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey('HOME'));
        return /^custom_jobs_ohos_[0-9a-f]{40}$/.test(config.flutter || '') &&
            config.flutterUrl === 'https://gitcode.com/CPF-Flutter/flutter_flutter.git' &&
            config.cachePath === home + '/Library/Caches/JobsFlutter/fvm/harmony';
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
    if (args[0] === 'directory-kind') {
        var url = $.NSURL.fileURLWithPath(args[1]);
        var properties = ObjC.deepUnwrap(url.resourceValuesForKeysError($([$.NSURLIsDirectoryKey, $.NSURLIsPackageKey, $.NSURLIsAliasFileKey, $.NSURLIsSymbolicLinkKey]), null));
        if (!properties || properties.NSURLIsDirectoryKey !== true || properties.NSURLIsPackageKey !== false ||
            properties.NSURLIsAliasFileKey !== false || properties.NSURLIsSymbolicLinkKey !== false) throw Error('目标不是普通目录，或是 package / Alias / 符号链接');
        return 'directory';
    }
    if (args[0] === 'pubspec') {
        var lines = read(args[1]).replace(/^\uFEFF/, '').split(/\r?\n/), start = -1, end = lines.length, count = 0, rootValue = '';
        lines = lines.map(uncomment);
        lines.forEach(function (line, i) {
            if (/^[ \t]*\t/.test(line)) throw Error('pubspec 缩进含 Tab，无法安全识别');
            if (/^\s*(?:---|\.\.\.)(?:\s|$)/.test(line)) throw Error('不支持 YAML 文档分隔标记');
            var match = /^(?:dependencies|"dependencies"|'dependencies')\s*:(?:\s+(.*)|\s*)$/.exec(line);
            if (match) { count++; start = i; rootValue = match[1] || ''; }
        });
        if (count !== 1) throw Error('必须有唯一根级 dependencies');
        if (rootValue) {
            var dependency = flow(rootValue).flutter;
            if (!dependency || typeof dependency !== 'object' || dependency.sdk !== 'flutter') throw Error('dependencies.flutter.sdk 不是 flutter');
            return 'flutter';
        }
        for (var i = start + 1; i < lines.length; i++) if (lines[i] && !/^ /.test(lines[i])) { end = i; break; }
        var depIndent = null, flutterStart = -1, flutterCount = 0, flutterValue = '';
        for (var i = start + 1; i < end; i++) {
            if (!lines[i]) continue;
            var match = /^( +)([^:]+):(?:\s+(.*)|\s*)$/.exec(lines[i]);
            if (!match) throw Error('无法安全识别 dependencies block');
            if (depIndent === null) depIndent = match[1].length;
            if (match[1].length === depIndent && scalar(match[2]) === 'flutter') {
                flutterStart = i; flutterCount++; flutterValue = match[3] || '';
            }
        }
        if (flutterCount !== 1) throw Error('缺少唯一直接依赖 flutter');
        if (flutterValue) {
            if (flow(flutterValue).sdk !== 'flutter') throw Error('flutter.sdk 不是 flutter');
            return 'flutter';
        }
        var sdkIndent = null, sdkValue = null;
        for (var i = flutterStart + 1; i < end; i++) {
            if (!lines[i]) continue;
            var indent = /^ */.exec(lines[i])[0].length;
            if (indent <= depIndent) break;
            var match = /^( +)([^:]+):\s*(.*)$/.exec(lines[i]);
            if (!match) throw Error('无法安全识别 flutter dependency');
            if (sdkIndent === null) sdkIndent = indent;
            if (indent === sdkIndent && scalar(match[2]) === 'sdk') {
                if (sdkValue !== null) throw Error('重复 sdk key');
                sdkValue = scalar(match[3]);
            }
        }
        if (sdkValue !== 'flutter') throw Error('dependencies.flutter.sdk 不是 flutter');
        return 'flutter';
    }
    if (args[0] === 'current' || args[0] === 'source-kind') {
        var config = json(args[1]);
        if (!config || Array.isArray(config) || typeof config !== 'object') throw Error('FVM 配置不是对象');
        if (config.flutterUrl && config.flutterUrl !== 'https://github.com/flutter/flutter.git' && !managedHarmony(config)) throw Error('自定义 flutterUrl 与官方版本列表不兼容；只支持本菜单管理的 CPF 鸿蒙配置切回官方');
        if (config.cachePath && (!clean(config.cachePath).startsWith('/'))) throw Error('cachePath 必须是绝对路径');
        if (args[0] === 'source-kind') return managedHarmony(config) ? 'managed-harmony' : 'native';
        return clean(config.flutter || config.flutterSdkVersion || '未配置');
    }
    if (args[0] === 'native-inspection') {
        var inspection = json(args[1]);
        if (!inspection || Array.isArray(inspection) || typeof inspection !== 'object' || !managedHarmony(inspection)) throw Error('不是可转换的受管 CPF 鸿蒙配置');
        inspection.flutterUrl = 'https://github.com/flutter/flutter.git';
        delete inspection.cachePath; delete inspection.flutter; delete inspection.flutterSdkVersion;
        return JSON.stringify(inspection, null, 2);
    }
    if (args[0] === 'native-merge') {
        var native = json(args[1]), root = clean(args[3]);
        if (!native || Array.isArray(native) || typeof native !== 'object' || !managedHarmony(native) || !version(args[2]) || !root.startsWith('/')) throw Error('受管鸿蒙到官方的配置转换无效');
        native.flutter = args[2]; delete native.flutterSdkVersion;
        native.flutterUrl = 'https://github.com/flutter/flutter.git'; native.cachePath = root;
        native.updateMelosSettings = false;
        return JSON.stringify(native, null, 2);
    }
    if (args[0] === 'context') {
        var context = json(args[1]).context;
        if (!context) throw Error('缺少 FVM context');
        var url = clean(context.flutterUrl), path = clean(context.versionsCachePath);
        if (url !== 'https://github.com/flutter/flutter.git') throw Error('有效 flutterUrl 是自定义仓库，与官方版本列表不兼容：' + url.replace(/\/\/[^/]*@/, '//[redacted]@').split(/[?#]/)[0]);
        if (!path.startsWith('/')) throw Error('FVM 缓存不是绝对路径');
        return url + '\t' + path;
    }
    if (args[0] === 'render') {
        var cached = json(args[2]);
        if (!cached || !Array.isArray(cached.versions)) throw Error('缓存 API 缺少 versions 数组');
        var cache = Object.create(null);
        cached.versions.forEach(function (entry) {
            if (!version(entry.name) || entry.isSetup !== true) return;
            var directory = clean(entry.directory);
            if (!directory.startsWith('/')) throw Error('缓存目录不是绝对路径');
            if ($.NSFileManager.defaultManager.isExecutableFileAtPath(directory + '/bin/flutter') &&
                $.NSFileManager.defaultManager.isExecutableFileAtPath(directory + '/bin/cache/dart-sdk/bin/dart')) cache[entry.name] = true;
        });
        var current = args[3], channel = args[4], arch = args[5], online = args[1] !== '-', rows = [], seen = Object.create(null);
        if (online) {
            var releases = json(args[1]);
            if (!releases || !Array.isArray(releases.releases) || !releases.current_release || !/^[a-f0-9]{40}$/.test(releases.current_release.stable || '')) throw Error('官方版本清单结构无效');
            var stableSeen = false;
            releases.releases.forEach(function (entry) {
                if (!version(entry.version) || !/^(stable|beta|dev)$/.test(entry.channel) || !/^\d{4}-\d\d-\d\dT/.test(entry.release_date || '') || !/^[a-f0-9]{40}$/.test(entry.hash || '')) return;
                if (entry.hash === releases.current_release.stable && entry.channel === 'stable') stableSeen = true;
                if (channel !== 'all' && channel !== entry.channel) return;
                var entryArch = entry.dart_sdk_arch || 'x64';
                if (entryArch !== arch) return;
                var key = entry.version + ':' + entry.channel;
                if (seen[key] && (entryArch !== arch || seen[key].arch === arch)) return;
                var row = { name:entry.version, date:entry.release_date.slice(0, 10), channel:entry.channel, arch:entryArch, latest:entry.hash === releases.current_release.stable && entry.channel === 'stable' };
                seen[key] = row;
            });
            if (!stableSeen) throw Error('清单缺少 current_release 对应 stable，不能确认最新版本');
            Object.keys(seen).forEach(function (key) { rows.push(seen[key]); });
        } else {
            Object.keys(cache).forEach(function (name) { rows.push({name:name, date:'未知日期', channel:'本机缓存', arch:'待SDK核验', latest:false}); });
        }
        rows.sort(function (a,b) { return b.date.localeCompare(a.date) || b.name.localeCompare(a.name, undefined, {numeric:true}); });
        return rows.map(function (row) {
            var flags = []; if (cache[row.name]) flags.push('已缓存'); if (row.name === current) flags.push('当前'); if (row.latest) flags.push('最新 stable');
            if (!online) flags.push('缓存清单/最新未知');
            return [row.name, row.date, row.channel, row.arch, flags.join(' · ') || '未缓存'].join('\t');
        }).join('\n');
    }
    if (args[0] === 'normalize-fvm-releases') {
        // FVM 自带接口能走通网络时，把它返回的清单补成官方清单结构，供后续统一渲染。
        var payload = json(args[1]);
        if (!payload || !Array.isArray(payload.versions)) throw Error('FVM releases 缺少 versions 数组');
        var releases = [], activeStable = '', latestStableDate = '';
        payload.versions.forEach(function (entry) {
            if (!version(entry.version) || !/^(stable|beta|dev)$/.test(entry.channel)) return;
            if (!/^\d{4}-\d\d-\d\dT/.test(entry.release_date || '') || !/^[a-f0-9]{40}$/.test(entry.hash || '')) return;
            var arch = entry.dart_sdk_arch === 'arm64' ? 'arm64' : 'x64';
            if (entry.channel === 'stable') {
                if (entry.active_channel === true) activeStable = entry.hash;
                if (entry.release_date > latestStableDate) latestStableDate = entry.release_date;
            }
            releases.push({ version:entry.version, channel:entry.channel, release_date:entry.release_date, hash:entry.hash, dart_sdk_arch:arch });
        });
        if (!activeStable) {
            // 缺少 active 标记时退回按日期取最晚的 stable，仍不猜测版本内容。
            releases.forEach(function (row) { if (row.channel === 'stable' && row.release_date === latestStableDate) activeStable = row.hash; });
        }
        if (!activeStable) throw Error('FVM releases 未提供可确认的最新 stable');
        return JSON.stringify({ releases:releases, current_release:{ stable:activeStable } });
    }
    if (args[0] === 'merge') {
        var object = args[1] === '-' ? {} : json(args[1]);
        if (!object || Array.isArray(object) || typeof object !== 'object' || !version(args[2])) throw Error('不能合并无效配置');
        object.flutter = args[2]; delete object.flutterSdkVersion;
        object.updateMelosSettings = false;
        return JSON.stringify(object, null, 2);
    }
    if (args[0] === 'preserve') {
        var planned = json(args[1]), produced = json(args[2]), restored = false;
        if (!planned || Array.isArray(planned) || typeof planned !== 'object' ||
            !produced || Array.isArray(produced) || typeof produced !== 'object' || !version(planned.flutter) || !version(produced.flutter)) throw Error('FVM 结果配置缺少真实精确 flutter 版本');
        if (produced.flutter !== planned.flutter) throw Error('FVM 真实版本与确认配置不匹配，不补写原字段');
        Object.keys(planned).forEach(function (key) {
            if (!Object.prototype.hasOwnProperty.call(produced, key)) {
                Object.defineProperty(produced, key, { value:planned[key], enumerable:true, writable:true, configurable:true });
                restored = true;
            }
        });
        return restored ? JSON.stringify(produced, null, 2) : '';
    }
    if (args[0] === 'machine') {
        var machine = json(args[1]);
        if (!version(machine.frameworkVersion)) throw Error('Flutter 版本输出无效');
        return machine.frameworkVersion;
    }
    if (args[0] === 'release-tag') {
        var tag = json(args[1]).tag_name;
        if (!/^\d+\.\d+\.\d+$/.test(tag || '')) throw Error('Homebrew 最新稳定 tag 无效');
        return tag;
    }
    if (args[0] === 'cached-directory') {
        var entries = json(args[1]).versions;
        if (!Array.isArray(entries)) throw Error('缓存缺少 versions');
        var entry = entries.filter(function (entry) { return entry.name === args[2] && entry.isSetup === true; })[0];
        if (!entry) throw Error('选择的缓存不完整');
        return clean(entry.directory);
    }
    if (args[0] === 'redact') return clean(args[1]).replace(/\/\/[^/]*@/, '//[redacted]@').split(/[?#]/)[0];
    throw Error('未知数据操作');
}
JXA
}
# 只读检查精确目标，拒绝把父目录、注释、纯 Dart 或 flutter_test 当成 Flutter 项目。
fm_validate_invocation() {
    local original="" size=""
    [[ "$#" == 2 && "$1" == --project && -n "$2" && -d "$2" ]] || {
        print -u2 -r -- '✖ 用法：/bin/zsh ManageFlutterVersion.zsh --project <Flutter项目目录>'
        exit 1
    }
    original="$2"
    while [[ "$original" == */ && "$original" != / ]]; do original="${original%/}"; done
    [[ -n "$original" && "$original" != / && ! -L "$original" ]] || { print -u2 -r -- '✖ 目标必须是普通文件夹，不能是符号链接或文件系统根目录。'; exit 1; }
    fm_data directory-kind "$original" >/dev/null || { print -u2 -r -- '✖ 目标不是可确认的普通文件夹；请避开 package / Alias / 符号链接。'; exit 1; }
    case "${original:e:l}" in app|appex|framework|bundle|xcodeproj|xcworkspace|playground|photoslibrary|workflow) print -u2 -r -- '✖ 不处理应用或工程 package，请选择包含 pubspec.yaml 的普通项目文件夹。'; exit 1 ;; esac
    FM_PROJECT="${original:A}"
    [[ -f "$FM_PROJECT/pubspec.yaml" && ! -L "$FM_PROJECT/pubspec.yaml" ]] || {
        print -u2 -r -- '✖ 目标同层缺少普通 pubspec.yaml，不搜索父目录或子目录。'
        exit 1
    }
    size="$(/usr/bin/stat -f %z "$FM_PROJECT/pubspec.yaml" 2>/dev/null)"
    [[ "$size" == <-> && "$size" -le 1048576 ]] || { print -u2 -r -- '✖ pubspec.yaml 超过 1 MiB 或无法读取，已停止。'; exit 1; }
    fm_data pubspec "$FM_PROJECT/pubspec.yaml" >/dev/null || {
        print -u2 -r -- '✖ 无法确认 dependencies.flutter.sdk: flutter；未安装工具或改动项目。YAML 锚点 / 多行 flow 等复杂写法请先人工确认并改成普通 block。'
        exit 1
    }
}
# 第一屏先解释用途；精确项目只读校验之后等待回车，再准备运行环境。
show_script_intro_and_wait() {
    local answer=""
    fm_intro_line title '━━━━━━━━━━ Flutter SDK 安装 / 切换（FVM）━━━━━━━━━━'
    fm_intro_line body '1、仅处理指定目录自身的 Flutter 项目，通过 fzf 单选历史版本 / 当前最新 stable。'
    fm_intro_line body '2、先体检 Git / curl / CLT、Homebrew、fzf、FVM 及实际运行依赖；健康工具复用，缺失或损坏组件另行确认后只修复一次。'
    fm_intro_line body '3、最终确认后可能修改目标 .fvmrc、.fvm、.gitignore、VSCode 配置及 FVM 缓存；跳过 pub get，不修改全局 SDK / Shell 配置 / 网络代理。'
    fm_intro_line body '4、版本清单优先查 Google 官方源，不可达时依次改用国内镜像、FVM 内置接口；镜像来源仅在本次进程内传给 SDK 下载。'
    fm_intro_line body '5、日志和配置快照保留在系统临时目录 JobsFlutterVersionMgr.*；Ctrl+C 取消，fzf 按 Esc 退出。'
    fm_validate_invocation "$@"
    fm_intro_line body "目标目录：$FM_PROJECT"
    [[ -t 0 && -t 1 ]] || { print -u2 -r -- '✖ 需要可交互 Terminal；没有 TTY，已停止。'; exit 1; }
    IFS= read -r 'answer?👉 已了解用途与影响，按回车继续；Ctrl+C 取消：' || exit 1
}
# 确认后才建立私有日志，所有 PATH 变化仅限本进程和子进程。
fm_initialize_runtime() {
    setopt NO_NOMATCH
    umask 077
    SCRIPT_PATH="${(%):-%x}"
    SCRIPT_PATH="${SCRIPT_PATH:A}"
    SCRIPT_DIR="${SCRIPT_PATH:h}"
    FM_RUN_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/JobsFlutterVersionMgr.XXXXXX")" || exit 1
    LOG_FILE="$FM_RUN_DIR/${SCRIPT_BASENAME}.log"
    : > "$LOG_FILE" || exit 1
    export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ANALYTICS=1
    export DART_SUPPRESS_ANALYTICS=true FLUTTER_SUPPRESS_ANALYTICS=true NO_COLOR=1
    trap 'fm_handle_signal INT 130' INT
    trap 'fm_handle_signal TERM 143' TERM
    cd -P -- "$FM_PROJECT" || fm_stop '无法进入目标目录'
    fm_log "ℹ 目标：$FM_PROJECT"
    fm_log "ℹ 日志：$LOG_FILE"
}
# 同步写入终端与纯文本日志，不在日志中注入 ANSI。
fm_log() {
    print -r -- "$*" | /usr/bin/tee -a "$LOG_FILE"
}
# 给出准确失败层级；写入阶段失败先按项目真实状态对齐配置，再退出。
fm_stop() {
    fm_log "✖ $1；日志：$LOG_FILE"
    if (( FM_MUTATION_STARTED )); then
        if fm_align_project_state; then
            fm_log "ℹ .fvmrc 已对齐项目当前真实状态；FVM 可能已写过 .gitignore / .vscode 等其它文件，配置快照：$FM_RUN_DIR/before"
        else
            fm_log "⚠ 项目或 SDK 缓存可能已经部分变更，无法安全对齐 .fvmrc；配置快照：$FM_RUN_DIR/before。请先查看差异，未自动覆盖 FVM 之后的其它改动。"
        fi
    fi
    exit "${2:-1}"
}
# 失败后让 .fvmrc 回到项目真实状态：链接未变就还原运行前配置，已变则对齐到链接版本。
fm_align_project_state() {
    local linked="" pinned="" current=""
    [[ -n "$FM_PROJECT" && -d "$FM_PROJECT" && -d "$FM_RUN_DIR/before" ]] || return 1
    [[ -f "$FM_PROJECT/.fvmrc" && ! -L "$FM_PROJECT/.fvmrc" ]] || return 1
    if [[ -L "$FM_PROJECT/.fvm/flutter_sdk" ]]; then
        linked="${FM_PROJECT}/.fvm/flutter_sdk"
        linked="${linked:A}"
        pinned="${linked:t}"
    fi
    current="$(fm_data current "$FM_PROJECT/.fvmrc" 2>> "$LOG_FILE")" || return 1
    # 配置已经等于链接版本时无需改动，只说明状态。
    if [[ -n "$pinned" && "$current" == "$pinned" ]]; then
        fm_log "✔ .fvmrc 与 SDK 链接已一致：$pinned，未改写配置"
        return 0
    fi
    [[ -f "$FM_RUN_DIR/next-fvmrc.json" ]] || return 1
    # 只在 .fvmrc 仍是本次写入内容时动手，避免覆盖等待期间的并发修改。
    /usr/bin/cmp -s -- "$FM_RUN_DIR/next-fvmrc.json" "$FM_PROJECT/.fvmrc" || return 1
    if [[ "$linked" == "$FM_LINK_BEFORE" ]]; then
        if [[ -f "$FM_RUN_DIR/before/.fvmrc" ]]; then
            /bin/cp -p -- "$FM_RUN_DIR/before/.fvmrc" "$FM_PROJECT/.fvmrc" || return 1
            fm_log "✔ 已把 .fvmrc 还原为运行前的 $FM_CURRENT；FVM 未改动 SDK 链接"
        else
            /bin/rm -f -- "$FM_PROJECT/.fvmrc" || return 1
            fm_log '✔ 已删除本次新建的 .fvmrc；运行前本项目没有该文件，FVM 也未改动 SDK 链接'
        fi
        return 0
    fi
    [[ "$pinned" =~ '^v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?(\+[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$' ]] || return 1
    fm_data merge "$FM_PROJECT/.fvmrc" "$pinned" > "$FM_RUN_DIR/aligned-fvmrc.json" 2>> "$LOG_FILE" || return 1
    /bin/cp -- "$FM_RUN_DIR/aligned-fvmrc.json" "$FM_PROJECT/.fvmrc" || return 1
    fm_log "✔ 已把 .fvmrc 对齐到链接的真实版本：$pinned；FVM 已改写 .fvm/flutter_sdk，不回退链接"
}
# 中断时保留日志与配置快照，避免宣称外部 FVM 操作已经回滚。
fm_handle_signal() {
    fm_stop "已收到 $1，操作中断" "$2"
}
# 保留管道首项退出码，不让 tee 掩盖安装失败。
fm_run_logged() {
    local -a results
    fm_log "▶ 执行：${(j: :)${(q)@}}"
    "$@" 2>&1 | /usr/bin/tee -a "$LOG_FILE"
    results=( "${pipestatus[@]}" )
    (( results[1] == 0 )) || return "${results[1]}"
    (( results[2] == 0 )) || return "${results[2]}"
}
# 独立菜单取消保持成功退出；依赖拉取串接时显式传递取消，阻止下游业务。
fm_cancel() {
    fm_log "$1"
    if [[ "${JOBS_FLUTTER_VERSION_CHAINED:-0}" == 1 ]]; then
        exit 130
    fi
    exit 0
}
# 必需依赖采用现有终端承接规则：回车确认准备，任意内容取消整个流程。
fm_confirm_dependency() {
    local answer=""
    fm_log "⚠ $1"
    IFS= read -r 'answer?👉 按回车确认安装 / 修复该必需组件；输入任意内容后回车取消：' || exit 1
    if [[ -n "$answer" ]]; then
        fm_cancel 'ℹ 已取消依赖准备，未安装 / 切换 Flutter 版本。'
    fi
}
# 拒绝 FVM 将直接写入的配置链接；SDK 链接本身属于正常 FVM 结构。
fm_check_project_boundaries() {
    local item="" config_source="" source_kind=""
    for item in .fvmrc .fvm .gitignore .vscode .vscode/settings.json .fvm/fvm_config.json .fvm/version .fvm/release .fvm/versions; do
        [[ ! -L "$FM_PROJECT/$item" ]] || fm_stop "项目配置是符号链接，停止以免写到其它位置：$item"
    done
    for item in "$FM_PROJECT"/*.code-workspace(N); do
        [[ ! -L "$item" ]] || fm_stop "workspace 配置是符号链接：$item"
    done
    [[ ! -e "$FM_PROJECT/.fvm" || -d "$FM_PROJECT/.fvm" ]] || fm_stop '.fvm 已存在但不是目录'
    if [[ -e "$FM_PROJECT/.fvmrc" ]]; then
        config_source="$FM_PROJECT/.fvmrc"
        FM_CURRENT="$(fm_data current "$FM_PROJECT/.fvmrc" 2>> "$LOG_FILE")" || fm_stop '无法读取 .fvmrc，或自定义 Flutter 仓库 / cachePath 与本入口不兼容'
    elif [[ -e "$FM_PROJECT/.fvm/fvm_config.json" ]]; then
        config_source="$FM_PROJECT/.fvm/fvm_config.json"
        FM_CURRENT="$(fm_data current "$FM_PROJECT/.fvm/fvm_config.json" 2>> "$LOG_FILE")" || fm_stop '无法读取旧版 FVM 配置'
    fi
    if [[ -n "$config_source" ]]; then
        source_kind="$(fm_data source-kind "$config_source" 2>> "$LOG_FILE")" || fm_stop '无法核对 Flutter SDK 来源类型'
        if [[ "$source_kind" == managed-harmony ]]; then
            FM_RETURN_FROM_HARMONY=1
            fm_log 'ℹ 已识别本菜单管理的 CPF 鸿蒙 SDK；本次可选择官方 Flutter 版本切回原生 iOS / Android SDK，确认前不改项目。'
        fi
    fi
    fm_log "ℹ 当前项目配置：$FM_CURRENT"
}
# 私有影子配置模拟精确目标的自身配置，防止只读 API 继承父项目 cachePath / flutterUrl。
fm_prepare_inspection_config() {
    local digest=""
    /bin/mkdir -p "$FM_RUN_DIR/inspection" || fm_stop '无法准备 FVM 只读体检目录'
    if [[ -f "$FM_PROJECT/.fvmrc" ]]; then FM_ORIGINAL_CONFIG="$FM_PROJECT/.fvmrc";
    elif [[ -f "$FM_PROJECT/.fvm/fvm_config.json" ]]; then FM_ORIGINAL_CONFIG="$FM_PROJECT/.fvm/fvm_config.json"; fi
    if [[ -n "$FM_ORIGINAL_CONFIG" ]]; then
        if (( FM_RETURN_FROM_HARMONY )); then
            fm_data native-inspection "$FM_ORIGINAL_CONFIG" > "$FM_RUN_DIR/inspection/.fvmrc" 2>> "$LOG_FILE" || fm_stop '无法建立受管鸿蒙切回官方的影子配置'
        else
            /bin/cp -- "$FM_ORIGINAL_CONFIG" "$FM_RUN_DIR/inspection/.fvmrc" || fm_stop '无法复制目标配置供只读体检'
        fi
        digest="$(/usr/bin/shasum -a 256 -- "$FM_ORIGINAL_CONFIG")" || fm_stop '无法计算目标配置的并发修改校验值'
        FM_ORIGINAL_CONFIG_DIGEST="${digest%% *}"
    else
        print -r -- '{}' > "$FM_RUN_DIR/inspection/.fvmrc" || fm_stop '无法建立私有体检配置'
    fi
}
# 从私有影子项目读取 API，原项目与父项目均不作为当前命令的 FVM 项目。
fm_inspect_api() {
    (cd -P -- "$FM_RUN_DIR/inspection" && "$FM_FVM" api "$@")
}
# osascript 的空字符串可能自带换行，必须检查有效内容而不是仅检查文件字节数。
fm_list_has_rows() {
    [[ -f "$1" ]] && /usr/bin/grep -q '[^[:space:]]' "$1"
}
# 验证必要系统引导工具；CLT 安装是系统异步任务，发起后停止下游操作。
fm_check_system_tools() {
    local candidate="" developer="" clang=""
    [[ "$(/usr/bin/uname -s)" == Darwin ]] || fm_stop '本脚本只适用于 macOS'
    [[ -x /bin/bash ]] && /bin/bash --version >> "$LOG_FILE" 2>&1 || fm_stop '系统 bash 不可用'
    for candidate in "$(command -v curl 2>/dev/null)" /usr/bin/curl; do
        if [[ -x "$candidate" ]] && "$candidate" --version >> "$LOG_FILE" 2>&1; then FM_CURL="$candidate"; break; fi
    done
    [[ -n "$FM_CURL" ]] || fm_stop 'curl 无健康候选；请先修复系统 curl，未开始安装下游工具'
    developer="$(/usr/bin/xcode-select -p 2>> "$LOG_FILE")"
    clang="$(/usr/bin/xcrun --find clang 2>> "$LOG_FILE")"
    if [[ ! -d "$developer" || ! -x "$clang" ]] || ! "$clang" --version >> "$LOG_FILE" 2>&1; then
        fm_confirm_dependency 'Apple Command Line Tools 缺失 / 损坏。来源：Apple 系统安装界面；请求安装后本次停止，请完成安装再重新运行。'
        fm_run_logged /usr/bin/xcode-select --install || fm_stop '无法启动 CLT 安装；可能已在安装中，请检查系统安装界面或 xcode-select 路径'
        fm_stop '已请求 CLT 安装；尚未就绪，未继续下游安装'
    fi
    for candidate in "$(command -v git 2>/dev/null)" /usr/bin/git; do
        if [[ -x "$candidate" ]] && "$candidate" --version >> "$LOG_FILE" 2>&1; then FM_GIT="$candidate"; break; fi
    done
    [[ -n "$FM_GIT" ]] || fm_stop 'CLT 已选择但 Git 不可用，请修复 Command Line Tools / Xcode 选择路径'
    fm_log "✔ bash / curl / CLT / Git 通过实际执行检查；Git：$FM_GIT"
}
# 已安装的 brew 必须能运行且返回真实绝对前缀。
fm_brew_candidate_ok() {
    local candidate="$1" prefix=""
    [[ -n "$candidate" && -x "$candidate" ]] || return 1
    "$candidate" --version >> "$LOG_FILE" 2>&1 || return 1
    prefix="$("$candidate" --prefix 2>> "$LOG_FILE")" || return 1
    [[ "$prefix" == /* && -d "$prefix" ]] || return 1
    "$candidate" config >> "$LOG_FILE" 2>&1 || return 1
    FM_BREW="$candidate"
    FM_BREW_PREFIX="$prefix"
}
# 依次发现当前 PATH、Apple Silicon、Intel 和既有用户前缀，健康安装复用。
fm_find_brew() {
    local candidate=""
    for candidate in "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew "${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}/bin/brew" "$HOME/.homebrew/bin/brew"; do
        fm_brew_candidate_ok "$candidate" && return 0
    done
    return 1
}
# 仅刷新当前进程 PATH，不写 shellenv 到用户配置，也不 eval 包管理器返回的代码。
fm_activate_brew() {
    export PATH="$FM_BREW_PREFIX/bin:$FM_BREW_PREFIX/sbin:$PATH"
    rehash
    fm_brew_candidate_ok "$FM_BREW" || fm_stop 'Homebrew 当前进程环境刷新后复检失败'
}
# 系统目录由官方安装器验证权限；用户目录安装官方稳定 tag，拒绝覆盖非空安装。
fm_install_brew() {
    local answer="" prefix="${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}" installer="" tag="" stage="" system_prefix="/usr/local"
    [[ "$(/usr/bin/uname -m)" != arm64 ]] || system_prefix="/opt/homebrew"
    fm_confirm_dependency '未找到健康 Homebrew。将准备官方 Homebrew；没有健康包管理器就不安装 FVM / fzf。'
    fm_log '━━━━━━━━━━ 来源｜Homebrew ━━━━━━━━━━'
    fm_log '📥 系统安装器：https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh'
    fm_log '📥 用户目录来源：https://github.com/Homebrew/brew.git；稳定 tag 由 https://api.github.com/repos/Homebrew/brew/releases/latest 查询'
    fm_log "1、精确输入 YES：系统标准目录 $system_prefix；官方安装器可能要求管理员密码。"
    fm_log "2、其它输入或直接回车：用户目录 $prefix，不使用 sudo；非标准前缀可能需要源码构建、耗时较长。"
    fm_log '路径失败即停止；不自动切换。Ctrl+C 取消。'
    IFS= read -r 'answer?➤ 安装路径选择：' || exit 1
    if [[ "$answer" == YES ]]; then
        installer="$FM_RUN_DIR/homebrew-install.sh"
        fm_log "📂 目标位置：$system_prefix"
        "$FM_CURL" --fail --location --proto '=https' --connect-timeout 10 --max-time 120 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer" 2>> "$LOG_FILE" || fm_stop '获取官方 Homebrew 安装器失败'
        fm_run_logged /bin/bash "$installer" || fm_stop '系统 Homebrew 安装失败，未切换安装路径'
        fm_brew_candidate_ok "$system_prefix/bin/brew" || fm_stop '官方安装器结束后 Homebrew 复检失败'
    else
        [[ "$prefix" == "$HOME/"* && "$prefix" != *[[:space:]:]* && ! -L "$prefix" ]] || fm_stop 'Homebrew 用户前缀必须位于当前 HOME 下且不含空白 / 冒号 / 符号链接'
        [[ ! -e "$prefix" ]] || fm_stop "用户前缀已经存在，保留原内容，不覆盖损坏安装：$prefix。请人工修复后重试"
        fm_log "📂 目标位置：$prefix"
        "$FM_CURL" --fail --location --proto '=https' --connect-timeout 10 --max-time 60 https://api.github.com/repos/Homebrew/brew/releases/latest -o "$FM_RUN_DIR/homebrew-release.json" 2>> "$LOG_FILE" || fm_stop '无法查询 Homebrew 官方稳定版本'
        tag="$(fm_data release-tag "$FM_RUN_DIR/homebrew-release.json" 2>> "$LOG_FILE")" || fm_stop 'Homebrew 官方稳定版本响应无效'
        /bin/mkdir -p -- "${prefix:h}" || fm_stop '无法准备 Homebrew 用户目录的父目录'
        stage="$(/usr/bin/mktemp -d "${prefix:h}/.jobs-homebrew.XXXXXX")" || fm_stop '无法建立用户 Homebrew 下载临时目录'
        fm_log "📦 官方 Homebrew 稳定版本：$tag；临时位置：$stage"
        fm_run_logged "$FM_GIT" -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 clone --depth 1 --branch "$tag" --single-branch https://github.com/Homebrew/brew.git "$stage/brew" || fm_stop "用户 Homebrew 克隆失败；保留诊断目录：$stage"
        fm_run_logged "$FM_GIT" -C "$stage/brew" checkout -b stable || fm_stop "用户 Homebrew stable 分支准备失败：$stage"
        fm_run_logged "$FM_GIT" -C "$stage/brew" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' || fm_stop '用户 Homebrew fetch 配置失败'
        /bin/mkdir -p "$stage/brew/Cellar" "$stage/brew/Caskroom" "$stage/brew/etc" "$stage/brew/var" || fm_stop '用户 Homebrew 目录准备失败'
        /bin/mv -- "$stage/brew" "$prefix" || fm_stop "无法部署 Homebrew，保留临时目录：$stage"
        /bin/rmdir -- "$stage" || fm_log "⚠ 临时目录保留：$stage"
        export HOMEBREW_NO_SUDO=1
        fm_brew_candidate_ok "$prefix/bin/brew" || fm_stop '用户 Homebrew 安装后复检失败；不重试覆盖'
    fi
}
# 既有 Homebrew 不做 update / upgrade / cleanup，仅按真实执行链判断可用性。
fm_ensure_brew() {
    fm_find_brew || fm_install_brew
    fm_activate_brew
    fm_log "✔ 复用健康 Homebrew：$FM_BREW；前缀：$FM_BREW_PREFIX"
}
# 发现能够实际运行的 fzf；不修改其键位或 Shell 启动配置。
fm_find_fzf() {
    local candidate=""
    for candidate in "$(command -v fzf 2>/dev/null)" "$FM_BREW_PREFIX/bin/fzf"; do
        if [[ -x "$candidate" ]] && "$candidate" --version >> "$LOG_FILE" 2>&1; then FM_FZF="$candidate"; return 0; fi
    done
    return 1
}
# 只修复缺失 / 损坏的 fzf 一次，安装后重新发现并复检。
fm_ensure_fzf() {
    local operation=install
    if fm_find_fzf; then fm_log "✔ 复用健康 fzf：$FM_FZF"; return 0; fi
    "$FM_BREW" list --versions fzf >> "$LOG_FILE" 2>&1 && operation=reinstall
    fm_log '━━━━━━━━━━ 来源｜fzf ━━━━━━━━━━'
    fm_log "📥 Homebrew core 公式：https://formulae.brew.sh/formula/fzf；目标前缀：$FM_BREW_PREFIX；动作：$operation；包 URL 由 Homebrew 解析"
    fm_confirm_dependency "fzf 不可用，需要 brew $operation fzf。"
    fm_run_logged "$FM_BREW" "$operation" fzf || fm_stop 'Homebrew fzf 安装 / 修复失败'
    fm_activate_brew
    fm_find_fzf || fm_stop 'fzf 安装后仍不可执行，停止且不重复修复'
}
# 版本、JSON API 与项目切换接口都能运行才接受 FVM；这同时验证了其实际 Dart / AOT 运行链。
fm_fvm_candidate_ok() {
    local candidate="$1" help=""
    [[ -x "$candidate" ]] || return 1
    "$candidate" --version >> "$LOG_FILE" 2>&1 || return 1
    "$candidate" api context --help >> "$LOG_FILE" 2>&1 || return 1
    "$candidate" api list --help >> "$LOG_FILE" 2>&1 || return 1
    help="$("$candidate" use --help 2>> "$LOG_FILE")" || return 1
    [[ "$help" == *--skip-pub-get* ]] || return 1
    FM_FVM="$candidate"
}
# 发现 PATH、Homebrew 和常用用户安装；已有健康 Dart Pub / 独立 FVM 无须迁移。
fm_find_fvm() {
    local candidate=""
    for candidate in "$(command -v fvm 2>/dev/null)" "$FM_BREW_PREFIX/bin/fvm" "$HOME/.pub-cache/bin/fvm" "$HOME/fvm/bin/fvm" "$HOME/.local/bin/fvm"; do
        fm_fvm_candidate_ok "$candidate" && return 0
    done
    return 1
}
# Homebrew core FVM 使用 dartaotruntime；损坏的实际运行时先修一次，再判断是否还需要重装 FVM。
fm_repair_aot_runtime() {
    local prefix="" operation=install
    prefix="$("$FM_BREW" --prefix dartaotruntime 2>> "$LOG_FILE")"
    if [[ "$prefix" == /* && -x "$prefix/bin/dartaotruntime" ]] && "$prefix/bin/dartaotruntime" --version >> "$LOG_FILE" 2>&1; then return 0; fi
    "$FM_BREW" list --versions dartaotruntime >> "$LOG_FILE" 2>&1 && operation=reinstall
    fm_log '━━━━━━━━━━ 来源｜FVM 实际 Dart AOT 运行时 ━━━━━━━━━━'
    fm_log "📥 Homebrew core：https://formulae.brew.sh/formula/dartaotruntime；动作：$operation；包 URL 由 Homebrew 解析"
    fm_confirm_dependency "现有 Homebrew core FVM 的 dartaotruntime 不健康，需要 brew $operation dartaotruntime。"
    fm_run_logged "$FM_BREW" "$operation" dartaotruntime || fm_stop 'Dart AOT 运行时安装 / 修复失败'
    fm_activate_brew
    prefix="$("$FM_BREW" --prefix dartaotruntime 2>> "$LOG_FILE")" || fm_stop '无法定位修复后的 Dart AOT 运行时'
    [[ "$prefix" == /* && -x "$prefix/bin/dartaotruntime" ]] && "$prefix/bin/dartaotruntime" --version >> "$LOG_FILE" 2>&1 || fm_stop 'Dart AOT 运行时修复后复检失败，停止下游 FVM'
}
# 根据已安装 formula 的实际归属修复，避免旧 tap / 版本化 FVM 与新同名公式冲突。
fm_ensure_fvm() {
    local formula="" operation=install item="" listing="" dependencies=""
    local -a owners=()
    if fm_find_fvm; then fm_log "✔ 复用健康 FVM 及实际运行链：$FM_FVM"; return 0; fi
    listing="$("$FM_BREW" list --formula --full-name -1 2>> "$LOG_FILE")" || fm_stop '无法读取 Homebrew 已安装公式归属'
    for item in "${(@f)listing}"; do
        [[ "${item:t}" == fvm || "${item:t}" == fvm@* ]] && owners+=( "$item" )
    done
    (( ${#owners} <= 1 )) || fm_stop "发现多个 FVM formula，无法安全选择修复对象：${(j:, :)owners}"
    if (( ${#owners} == 1 )); then
        formula="${owners[1]}"
        operation=reinstall
        if [[ "$formula" == fvm || "$formula" == homebrew/core/fvm ]]; then
            dependencies="$("$FM_BREW" deps --installed --direct "$formula" 2>> "$LOG_FILE")"
            if [[ $'\n'"$dependencies"$'\n' == *$'\n'dartaotruntime$'\n'* ]]; then
                fm_repair_aot_runtime
                if fm_find_fvm; then fm_log '✔ 修复 Dart AOT 运行时后既有 FVM 已恢复，无须重装 FVM。'; return 0; fi
            fi
        fi
    else
        formula=fvm
    fi
    fm_log '━━━━━━━━━━ 来源｜FVM ━━━━━━━━━━'
    if [[ "$formula" == fvm ]]; then
        fm_log '📥 Homebrew core：https://formulae.brew.sh/formula/fvm；上游：https://github.com/leoafarias/fvm'
    else
        fm_log "📥 保留既有 Homebrew formula 归属：$formula；实际下载 URL 由 Homebrew 解析"
    fi
    fm_log "📂 目标前缀：$FM_BREW_PREFIX；动作：$operation $formula；不自动卸载或迁移其它来源"
    fm_confirm_dependency "FVM 不可用，需要 brew $operation $formula（连同公式声明的运行依赖）。"
    fm_run_logged "$FM_BREW" "$operation" "$formula" || fm_stop 'FVM 安装 / 修复失败；请核对日志内原 formula / tap 和实际运行时'
    fm_activate_brew
    fm_find_fvm || fm_stop 'FVM 或其 Dart / AOT 运行链修复后仍失败，停止且不重复安装'
}
# 读取 FVM 实际有效源和缓存；自定义 Flutter fork 不能混用官方发布清单。
fm_read_effective_context() {
    local context="" effective="" resolved=""
    if [[ "${1:-}" == project ]]; then
        "$FM_FVM" api context --compress > "$FM_RUN_DIR/context.json" 2>> "$LOG_FILE" || fm_stop 'FVM context API 不可用'
    else
        fm_inspect_api context --compress > "$FM_RUN_DIR/context.json" 2>> "$LOG_FILE" || fm_stop 'FVM context API 不可用'
    fi
    effective="$(fm_data context "$FM_RUN_DIR/context.json" 2>> "$LOG_FILE")" || fm_stop '有效 FVM Flutter 来源 / 缓存无法安全核对；自定义 flutterUrl 请使用原项目流程'
    FM_CONTEXT_URL="${effective%%$'\t'*}"
    context="${effective#*$'\t'}"
    if [[ -n "$FM_CACHE_PATH" && "$FM_CACHE_PATH" != "$context" ]]; then fm_stop "最终目标配置生效后缓存路径发生变化：$FM_CACHE_PATH → $context。已停止，请重新运行核对本机缓存"; fi
    FM_CACHE_PATH="$context"
    if (( FM_RETURN_FROM_HARMONY )); then
        [[ "$FM_CACHE_PATH" != "$HOME/Library/Caches/JobsFlutter/fvm/harmony" && "$FM_CACHE_PATH" != "$HOME/Library/Caches/JobsFlutter/fvm/harmony/"* ]] || fm_stop '官方影子配置仍继承了鸿蒙专属缓存；请检查本进程 FVM_CACHE_PATH，未改动项目'
        [[ "$FM_CACHE_PATH" == */versions ]] || fm_stop '无法从 FVM versionsCachePath 确认官方缓存根目录，未改动项目'
        FM_NATIVE_CACHE_ROOT="${FM_CACHE_PATH%/versions}"
    fi
    resolved="$("$FM_GIT" ls-remote --get-url "$FM_CONTEXT_URL" 2>> "$LOG_FILE")" || fm_stop '无法解析 Git 已配置的 Flutter 仓库 URL'
    resolved="$(fm_data redact "$resolved" 2>> "$LOG_FILE")" || fm_stop 'Git 来源含无法安全展示的字段'
    fm_log "ℹ FVM 有效 Flutter 仓库：$FM_CONTEXT_URL"
    fm_log "ℹ Git 配置展开后的仓库地址：$resolved（未以此验证重定向终点 / 网络连通）"
    fm_log "ℹ FVM 有效 SDK 缓存：$FM_CACHE_PATH"
    if [[ -n "${FLUTTER_STORAGE_BASE_URL:-}" ]]; then
        fm_log "ℹ 当前进程已有 Flutter 资源源：$(fm_data redact "$FLUTTER_STORAGE_BASE_URL")；由 FVM / Flutter 使用，官方历史清单仍单独直查 Google 来源。"
    else
        fm_log 'ℹ Flutter 资源默认源：https://storage.googleapis.com；具体 SDK 下载由 FVM / Flutter 日志给出。'
    fi
}
# 下载清单并就地校验；只有能按当前架构渲染出条目才算可用，避免半截响应进入列表。
fm_try_release_source() {
    local url="$1" mode="${2:-proxy}" mirror_base="${3:-}" target="$FM_RUN_DIR/releases.json"
    local -a options
    options=(--fail --location --proto '=https' --connect-timeout 10 --max-time 45)
    [[ "$mode" == direct ]] && options+=(--noproxy '*')
    "$FM_CURL" "${options[@]}" "$url" -o "$target" 2>> "$LOG_FILE" || return 1
    fm_data render "$target" "$FM_RUN_DIR/cache.json" "$FM_CURRENT" all "$(fm_sdk_arch)" > "$FM_RUN_DIR/all.tsv" 2>> "$LOG_FILE" || return 1
    fm_list_has_rows "$FM_RUN_DIR/all.tsv" || return 1
    FM_RELEASE_SOURCE="$url"
    FM_STORAGE_BASE="$mirror_base"
}
# 清单来自镜像时，只在本次进程内把镜像资源源交给 FVM / Flutter，不写 Shell 配置也不覆盖用户已有的源。
fm_apply_storage_base() {
    [[ -n "$FM_STORAGE_BASE" ]] || return 0
    if [[ -n "${FLUTTER_STORAGE_BASE_URL:-}" && "${FLUTTER_STORAGE_BASE_URL}" != "$FM_STORAGE_BASE" ]]; then
        fm_log "ℹ 保留现有 Flutter 资源源：$(fm_data redact "$FLUTTER_STORAGE_BASE_URL")；未覆盖为镜像。"
        return 0
    fi
    export FLUTTER_STORAGE_BASE_URL="$FM_STORAGE_BASE"
    fm_log "ℹ 本次进程使用镜像资源源：$FM_STORAGE_BASE；SDK 初始化下载走镜像，不写 Shell 配置。"
}
# 只读取得本机缓存和全量历史；官方清单不可达时依次改用镜像和 FVM 自带接口，全部失败才降级本机缓存。
fm_fetch_versions() {
    local entry="" mirror_url="" mirror_base=""
    fm_inspect_api list --compress > "$FM_RUN_DIR/cache.json" 2>> "$LOG_FILE" || fm_stop '读取 FVM 本机缓存 API 失败'
    fm_data render - "$FM_RUN_DIR/cache.json" "$FM_CURRENT" cached x64 > "$FM_RUN_DIR/cached.tsv" 2>> "$LOG_FILE" || fm_stop 'FVM 缓存 JSON 格式错误，未猜测本机版本'
    fm_log '━━━━━━━━━━ 来源｜Flutter 历史与最新版本 ━━━━━━━━━━'
    fm_log "📥 Google 官方 macOS 发布清单：$FM_RELEASE_URL"
    fm_log "📂 本次临时清单：$FM_RUN_DIR/releases.json"
    if ! fm_try_release_source "$FM_RELEASE_URL"; then
        fm_log '⚠ 官方清单不可达。常见原因：该域名被解析到 127.0.0.1，或当前终端 HTTP(S)_PROXY 不可用；改试可直连来源。'
        for entry in "${FM_RELEASE_MIRRORS[@]}"; do
            mirror_url="${entry%%|*}"
            mirror_base="${entry#*|}"
            FM_RELEASE_SOURCE=""
            FM_STORAGE_BASE=""
            fm_log "📥 备用清单源：$mirror_url"
            fm_try_release_source "$mirror_url" direct "$mirror_base" && break
        done
    fi
    if [[ -z "$FM_RELEASE_SOURCE" ]]; then
        # 最后一层：FVM 自己的网络栈能取到清单时，补成官方结构继续用。
        FM_STORAGE_BASE=""
        fm_log '📥 备用清单源：FVM 内置发布接口（fvm api releases）'
        if fm_inspect_api releases --compress > "$FM_RUN_DIR/fvm-releases.json" 2>> "$LOG_FILE" &&
           fm_data normalize-fvm-releases "$FM_RUN_DIR/fvm-releases.json" > "$FM_RUN_DIR/releases.json" 2>> "$LOG_FILE" &&
           fm_data render "$FM_RUN_DIR/releases.json" "$FM_RUN_DIR/cache.json" "$FM_CURRENT" all "$(fm_sdk_arch)" > "$FM_RUN_DIR/all.tsv" 2>> "$LOG_FILE" &&
           fm_list_has_rows "$FM_RUN_DIR/all.tsv"; then
            FM_RELEASE_SOURCE='FVM 内置发布接口（fvm api releases）'
        fi
    fi
    if [[ -n "$FM_RELEASE_SOURCE" ]]; then
        FM_ONLINE=1
        fm_log "✔ 已取得本次历史清单；来源：$FM_RELEASE_SOURCE；查询时间：$(/bin/date '+%Y-%m-%d %H:%M:%S %Z')。列表标记 current_release 对应的最新 stable。"
        fm_apply_storage_base
    else
        FM_ONLINE=0
        fm_log '⚠ 官方版本查询失败 / 响应无效；无法确认最新版本，仅允许选择可读的本机缓存。已有工具安装不会因 Esc 撤销。'
        fm_list_has_rows "$FM_RUN_DIR/cached.tsv" || fm_stop '没有可供离线选择的精确版本缓存；请排查网络后重试'
    fi
}
# 保持本进程架构一致；列表仅展示当前 CPU 架构，避免隐式要求 Rosetta。
fm_sdk_arch() {
    if [[ "$(/usr/bin/uname -m)" == arm64 ]]; then print -r -- arm64; else print -r -- x64; fi
}
# fzf 固定单选并清除继承的默认动作，Esc / 输入流结束都不进入项目写操作。
fm_select_version() {
    local selection="" result=0 channel="" channel_label="" rows="$FM_RUN_DIR/selected-channel.tsv"
    if (( FM_ONLINE )); then
        channel="$(printf 'stable\t稳定版（默认）\nbeta\t预发布\ndev\t历史开发版\nall\t全部渠道\ncached\t仅本机缓存\n' |
            FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE=/dev/null "$FM_FZF" --no-multi --height=12 --layout=reverse --delimiter=$'\t' --prompt='渠道 > ' --header='Enter 选择渠道；Esc 取消；stable 排首位')" || result=$?
        if (( result == 1 || result == 130 )); then fm_cancel 'ℹ 已取消选择，未安装 / 切换 Flutter SDK。'; fi
        (( result == 0 )) || fm_stop "fzf 渠道选择失败（$result）"
        channel="${channel%%$'\t'*}"
        case "$channel" in stable|beta|dev|all|cached) FM_CHANNEL="$channel" ;; *) fm_stop 'fzf 返回未登记渠道' ;; esac
    else
        FM_CHANNEL=cached
    fi
    if [[ "$FM_CHANNEL" == cached ]]; then
        /bin/cp -- "$FM_RUN_DIR/cached.tsv" "$rows" || fm_stop '无法准备缓存选择列表'
        channel_label='本机缓存；不能据此确认最新版本'
    else
        fm_data render "$FM_RUN_DIR/releases.json" "$FM_RUN_DIR/cache.json" "$FM_CURRENT" "$FM_CHANNEL" "$(fm_sdk_arch)" > "$rows" 2>> "$LOG_FILE" || fm_stop '无法生成渠道列表'
        channel_label="官方 $FM_CHANNEL 历史版本；最新 stable 以清单标记为准"
    fi
    fm_list_has_rows "$rows" || fm_stop '当前渠道没有匹配版本，请重新运行选择其它渠道'
    selection="$(FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE=/dev/null "$FM_FZF" --no-multi --height=80% --layout=reverse --delimiter=$'\t' --prompt='Flutter > ' --header="$channel_label | 版本 / 日期 / 渠道 / 架构 / 状态；Esc 取消" < "$rows")" || result=$?
    if (( result == 1 || result == 130 )); then fm_cancel 'ℹ 已取消选择，未安装 / 切换 Flutter SDK。'; fi
    (( result == 0 )) || fm_stop "fzf 版本选择失败（$result）"
    /usr/bin/grep -Fqx -- "$selection" "$rows" || fm_stop '选择结果不是已展示清单中的完整条目'
    FM_SELECTED_ROW="$selection"
    FM_SELECTED="${selection%%$'\t'*}"
    [[ "$FM_SELECTED" =~ '^v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?(\+[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$' ]] || fm_stop '版本格式无效，未传入 FVM'
    fm_verify_cached_selection
}
# 缓存单选后实际运行其中的 Dart；损坏 / 不兼容缓存不进入项目配置写入。
fm_verify_cached_selection() {
    local directory=""
    [[ "$FM_CHANNEL" == cached ]] || return 0
    directory="$(fm_data cached-directory "$FM_RUN_DIR/cache.json" "$FM_SELECTED" 2>> "$LOG_FILE")" || fm_stop '无法定位选中缓存'
    [[ "$directory" == /* && -d "$directory" ]] || fm_stop '选中缓存目录已经失效'
    fm_run_logged "$directory/bin/cache/dart-sdk/bin/dart" --version || fm_stop '选中缓存的实际 Dart runtime 不可运行；请检查完整性和 CPU 架构，未修改项目'
}
# 提前说明本次切换是否需要下载 SDK；下载失败有失败对齐兜底，不留半套配置。
fm_report_cache_state() {
    [[ -f "$FM_RUN_DIR/cache.json" ]] || return 0
    if fm_data cached-directory "$FM_RUN_DIR/cache.json" "$FM_SELECTED" >/dev/null 2>> "$LOG_FILE"; then
        fm_log 'ℹ 目标版本已在本机缓存，切换不会触发 SDK 下载。'
    else
        fm_log 'ℹ 目标版本未在本机缓存：FVM 会先下载并初始化 SDK；下载或初始化失败时，脚本会把 .fvmrc 对齐回项目真实状态。'
    fi
}
# 展示具体改动再确认；回车执行安装 / 切换，任意非空输入取消。
fm_confirm_project_change() {
    local answer=""
    fm_log '━━━━━━━━━━ 即将安装 / 切换 ━━━━━━━━━━'
    fm_log "📂 项目：$FM_PROJECT"
    fm_log "📦 当前 → 目标：$FM_CURRENT → $FM_SELECTED"
    fm_log "ℹ 选择条目：$FM_SELECTED_ROW"
    fm_log "📥 版本依据：$([[ "$FM_CHANNEL" == cached ]] && print -r -- '本机 FVM 缓存（最新未知）' || print -r -- "$FM_RELEASE_SOURCE")"
    fm_report_cache_state
    fm_log "📥 SDK 源：FVM 有效仓库 $FM_CONTEXT_URL；缓存：$FM_CACHE_PATH；详细传输地址由 FVM 解析并输出。"
    if (( FM_RETURN_FROM_HARMONY )); then
        fm_log '📥 来源转换：CPF-Flutter 鸿蒙适配 SDK → https://github.com/flutter/flutter.git 官方原生 SDK。'
        fm_log "📝 确认后将 flutterUrl 写为官方源、cachePath 写为原生缓存 $FM_NATIVE_CACHE_ROOT；保留其它字段和鸿蒙旧缓存。"
    fi
    fm_log '📝 文件影响：合并目标 .fvmrc 并固定精确版本、设置 updateMelosSettings:false；FVM 更新 .fvm / SDK 链接和项目登记，按项目设置可能修改 .gitignore / .vscode/settings.json / *.code-workspace。'
    fm_log "📝 先备份已有相关配置到：$FM_RUN_DIR/before；不会自动覆盖恢复失败后的项目。"
    if [[ "$FM_CHANNEL" == cached ]]; then
        fm_log 'ℹ 选择已初始化且 Dart 可运行的缓存，使用 fvm use <精确版本> --skip-pub-get --skip-setup；Flutter 自身运行检查仍可能请求缺失资源。'
    else
        fm_log 'ℹ 使用 fvm use <精确版本> --skip-pub-get；SDK 初始化仍可能下载 Dart / 引擎。'
    fi
    fm_log 'ℹ 切换完成后需另行执行 fvm flutter pub get 检查依赖兼容。'
    IFS= read -r 'answer?👉 直接回车执行安装 / 切换；输入任意内容后回车取消：' || exit 1
    if [[ -n "$answer" ]]; then
        fm_cancel 'ℹ 已取消，项目版本配置未变更。'
    fi
}
# 保存可检查的原配置，再合并精确目标自身配置，防止 FVM 向上选中父项目。
fm_prepare_project_config() {
    local item="" config_source=- digest="" current_config=""
    fm_check_project_boundaries
    fm_data pubspec "$FM_PROJECT/pubspec.yaml" >/dev/null 2>> "$LOG_FILE" || fm_stop '等待交互期间项目身份发生变化，已停止'
    if [[ -f "$FM_PROJECT/.fvmrc" ]]; then current_config="$FM_PROJECT/.fvmrc";
    elif [[ -f "$FM_PROJECT/.fvm/fvm_config.json" ]]; then current_config="$FM_PROJECT/.fvm/fvm_config.json"; fi
    [[ "$current_config" == "$FM_ORIGINAL_CONFIG" ]] || fm_stop '等待交互期间 FVM 配置文件出现 / 消失 / 迁移，请重新运行审阅'
    if [[ -n "$current_config" ]]; then
        digest="$(/usr/bin/shasum -a 256 -- "$current_config")" || fm_stop '最终配置校验失败'
        [[ "${digest%% *}" == "$FM_ORIGINAL_CONFIG_DIGEST" ]] || fm_stop '等待交互期间 FVM 配置已被修改，请重新运行审阅'
    fi
    /bin/mkdir -p "$FM_RUN_DIR/before/.fvm" "$FM_RUN_DIR/before/.vscode" || fm_stop '无法创建配置快照目录'
    for item in .fvmrc .fvm/fvm_config.json .fvm/version .fvm/release .gitignore .vscode/settings.json; do
        if [[ -f "$FM_PROJECT/$item" ]]; then /bin/cp -p -- "$FM_PROJECT/$item" "$FM_RUN_DIR/before/$item" || fm_stop "配置快照失败：$item"; fi
    done
    for item in "$FM_PROJECT"/*.code-workspace(N); do
        [[ ! -f "$item" ]] || /bin/cp -p -- "$item" "$FM_RUN_DIR/before/${item:t}" || fm_stop "workspace 快照失败：$item"
    done
    if [[ -f "$FM_PROJECT/.fvmrc" ]]; then config_source="$FM_PROJECT/.fvmrc";
    elif [[ -f "$FM_PROJECT/.fvm/fvm_config.json" ]]; then config_source="$FM_PROJECT/.fvm/fvm_config.json"; fi
    # 记录写入前的链接指向，失败时据此判断该还原配置还是对齐链接。
    if [[ -L "$FM_PROJECT/.fvm/flutter_sdk" ]]; then
        FM_LINK_BEFORE="${FM_PROJECT}/.fvm/flutter_sdk"
        FM_LINK_BEFORE="${FM_LINK_BEFORE:A}"
    fi
    if (( FM_RETURN_FROM_HARMONY )); then
        [[ -n "$FM_NATIVE_CACHE_ROOT" ]] || fm_stop '缺少已核对的原生 Flutter 缓存根目录'
        fm_data native-merge "$config_source" "$FM_SELECTED" "$FM_NATIVE_CACHE_ROOT" > "$FM_RUN_DIR/next-fvmrc.json" 2>> "$LOG_FILE" || fm_stop '无法保留原字段并转换受管鸿蒙配置为官方原生配置'
    else
        fm_data merge "$config_source" "$FM_SELECTED" > "$FM_RUN_DIR/next-fvmrc.json" 2>> "$LOG_FILE" || fm_stop '无法保留原字段并合并目标 FVM 配置'
    fi
    FM_MUTATION_STARTED=1
    /bin/cp -- "$FM_RUN_DIR/next-fvmrc.json" "$FM_PROJECT/.fvmrc" || fm_stop '目标 .fvmrc 写入失败'
    fm_read_effective_context project
}
# FVM 执行前复核已确认的配置，拒绝前置配置缺失、链接替换或并发修改。
fm_validate_ready_config() {
    [[ -f "$FM_RUN_DIR/next-fvmrc.json" && ! -L "$FM_RUN_DIR/next-fvmrc.json" ]] || fm_stop '缺少本次已确认的目标配置，未执行 FVM'
    [[ -f "$FM_PROJECT/.fvmrc" && ! -L "$FM_PROJECT/.fvmrc" && ! -L "$FM_PROJECT/.fvm" ]] || fm_stop 'FVM 执行前配置变为符号链接或失效，未继续'
    /usr/bin/cmp -s -- "$FM_RUN_DIR/next-fvmrc.json" "$FM_PROJECT/.fvmrc" || fm_stop 'FVM 执行前配置已被修改，请重新运行审阅'
}
# 只补回 FVM 序列化省略的原字段，保留 FVM 实际输出值；原配置和结果快照用于并发核验。
fm_preserve_original_config_fields() {
    local produced="$FM_RUN_DIR/fvm-produced-fvmrc.json" merged="$FM_RUN_DIR/fvm-preserved-fvmrc.json" temporary=""
    [[ -f "$FM_PROJECT/.fvmrc" && ! -L "$FM_PROJECT/.fvmrc" ]] || fm_stop 'FVM 返回后配置变为符号链接或失效，未尝试恢复字段'
    /bin/cp -p -- "$FM_PROJECT/.fvmrc" "$produced" || fm_stop '无法保存 FVM 实际生成的配置'
    [[ ! -L "$FM_PROJECT/.fvmrc" ]] && /usr/bin/cmp -s -- "$produced" "$FM_PROJECT/.fvmrc" || fm_stop '读取 FVM 结果期间配置已被修改，保留现场'
    fm_data preserve "$FM_RUN_DIR/next-fvmrc.json" "$produced" > "$merged" 2>> "$LOG_FILE" || fm_stop '无法在保留 FVM 真实结果的前提下恢复原字段'
    if ! fm_list_has_rows "$merged"; then
        return 0
    fi
    [[ -f "$FM_PROJECT/.fvmrc" && ! -L "$FM_PROJECT/.fvmrc" && "${FM_PROJECT:A}" == "$FM_PROJECT" ]] &&
        /usr/bin/cmp -s -- "$produced" "$FM_PROJECT/.fvmrc" || fm_stop '恢复字段前配置或目标目录已经变化，未覆盖并发改动'
    temporary="$(/usr/bin/mktemp "$FM_PROJECT/.jobs-fvmrc-preserve.XXXXXX")" || fm_stop '无法建立目标同目录的配置临时文件'
    /bin/cp -p -- "$produced" "$temporary" && /bin/cat -- "$merged" > "$temporary" || fm_stop "无法准备字段恢复配置；保留临时文件：$temporary"
    [[ -f "$FM_PROJECT/.fvmrc" && ! -L "$FM_PROJECT/.fvmrc" && "${FM_PROJECT:A}" == "$FM_PROJECT" ]] &&
        /usr/bin/cmp -s -- "$produced" "$FM_PROJECT/.fvmrc" || fm_stop "恢复字段落盘前发现并发改动，未覆盖；保留临时文件：$temporary"
    /bin/mv -f -- "$temporary" "$FM_PROJECT/.fvmrc" || fm_stop "字段恢复配置写入失败；保留临时文件：$temporary"
    [[ -f "$FM_PROJECT/.fvmrc" && ! -L "$FM_PROJECT/.fvmrc" ]] &&
        /usr/bin/cmp -s -- "$merged" "$FM_PROJECT/.fvmrc" || fm_stop '恢复字段后的配置核验失败，保留现场'
    fm_log "✔ 已保留 FVM 序列化省略的原配置字段；FVM 实际输出：$produced"
}
# 调用精确版本并核验配置、实际 SDK 与链接身份；FVM 失败保留现场。
fm_apply_and_verify() {
    local result=0 actual="" pinned="" linked="" cached=""
    fm_validate_ready_config
    if [[ "$FM_CHANNEL" == cached ]]; then
        fm_run_logged "$FM_FVM" use "$FM_SELECTED" --skip-pub-get --skip-setup || result=$?
    else
        fm_run_logged "$FM_FVM" use "$FM_SELECTED" --skip-pub-get || result=$?
    fi
    (( result == 0 )) || fm_stop "fvm use 失败（退出码 $result）；请检查 SDK 下载、项目约束或架构依赖" "$result"
    [[ -f "$FM_PROJECT/.fvmrc" && ! -L "$FM_PROJECT/.fvmrc" ]] || fm_stop 'FVM 返回后 .fvmrc 失效或变为符号链接'
    pinned="$(fm_data current "$FM_PROJECT/.fvmrc" 2>> "$LOG_FILE")" || fm_stop '切换后 .fvmrc 无法读取'
    [[ "$pinned" == "$FM_SELECTED" ]] || fm_stop "配置版本核对失败：$pinned"
    fm_preserve_original_config_fields
    pinned="$(fm_data current "$FM_PROJECT/.fvmrc" 2>> "$LOG_FILE")" || fm_stop '保留原字段后 .fvmrc 无法读取'
    [[ "$pinned" == "$FM_SELECTED" ]] || fm_stop "保留原字段后配置版本核对失败：$pinned"
    [[ -L "$FM_PROJECT/.fvm/flutter_sdk" && -d "$FM_PROJECT/.fvm/flutter_sdk" ]] || fm_stop 'FVM SDK 链接缺失 / 失效'
    linked="${FM_PROJECT}/.fvm/flutter_sdk"
    linked="${linked:A}"
    cached="$FM_CACHE_PATH/$FM_SELECTED"
    [[ -d "$cached" && "$linked" == "${cached:A}" ]] || fm_stop "SDK 链接不指向本次有效缓存的精确版本：$linked"
    "$FM_FVM" flutter --version --machine > "$FM_RUN_DIR/flutter-machine.json" 2>> "$LOG_FILE" || fm_stop '项目 Flutter 实际运行失败；旧 x64 SDK 请核对 Rosetta，其他情况查看 SDK 初始化日志'
    actual="$(fm_data machine "$FM_RUN_DIR/flutter-machine.json" 2>> "$LOG_FILE")" || fm_stop 'Flutter 机器可读版本输出无效'
    [[ "${actual#v}" == "${FM_SELECTED#v}" ]] || fm_stop "实际 SDK 版本不匹配：$actual"
    fm_run_logged "$FM_FVM" dart --version || fm_stop '切换后项目实际 Dart runtime 不可用'
    fm_log "✔ 项目 Flutter 已核验：$FM_CURRENT → $FM_SELECTED；SDK：$linked"
    fm_log "ℹ 日志：$LOG_FILE；原配置快照：$FM_RUN_DIR/before"
    fm_log 'ℹ 终端日常使用 fvm flutter / fvm dart；需要解析项目依赖时执行 fvm flutter pub get。'
}
# 编排自述、只读体检、交互选择和最终项目变更。
main() {
    show_script_intro_and_wait "$@" # 首屏展示用途，确认精确 Flutter 目录后等待回车。
    fm_initialize_runtime # 用户确认后才创建日志并调整当前子进程环境。
    fm_check_project_boundaries # 在依赖准备前核对配置归属和写入边界。
    fm_prepare_inspection_config # 影子配置模拟目标自身设置，避免只读查询继承父项目。
    fm_check_system_tools # 验证必要系统工具和 CLT 的实际运行情况。
    fm_ensure_brew # 复用健康 Homebrew，缺失时经确认选择安装路径。
    fm_ensure_fzf # 复用健康 fzf，只修复不可用组件一次。
    fm_ensure_fvm # 检查 FVM 与真实 Dart / AOT 运行依赖。
    fm_read_effective_context # 显示实际仓库与缓存，不把官方清单冒充下载地址。
    fm_fetch_versions # 查询官方历史和最新版本，断网时仅提供本机缓存。
    fm_select_version # fzf 单选渠道与精确版本，取消不写项目。
    fm_confirm_project_change # 展示当前到目标和文件影响，回车执行，非空输入取消。
    fm_prepare_project_config # 保存配置快照并固定精确目标，避免父级回退。
    fm_apply_and_verify # 安装或切换后验证 .fvmrc、SDK 链接及实际 Flutter / Dart。
}

main "$@"
