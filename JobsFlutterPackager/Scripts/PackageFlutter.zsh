#!/bin/zsh
# 脚本自述：
# - 脚本名称：PackageFlutter.zsh（Flutter打包）。
# - 核心用途：精确 Flutter 项目目录中用 fzf 选择 iOS、Android 或鸿蒙 HAP / APP。
# - 影响范围：解析依赖、调用工程构建与既有签名；生成项目 build 产物及私有日志。
# - 运行提示：自述后回车继续；Esc / Ctrl+C 取消；不安装升级工具、不修改系统配置。

fp_data() {
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
        if (read(args[1]).indexOf(String.fromCharCode(0)) !== -1) throw Error('清单含 NUL');
        var manifestEntries = loadEntries(args[1]);
        var dependencies = uniqueRoot(manifestEntries, 'dependencies');
        if (!dependencies) throw Error('必须有唯一根级 dependencies');
        if (assertFlutterSDKDependency(manifestEntries, dependencies)) return 'flutter';
        throw Error('未识别到 Flutter SDK 依赖');
    }
    throw Error('未知数据操作');
}
JXA
}

typeset FP_PROJECT="" FP_LOG_FILE="" FP_FZF="" FP_PLATFORM="" FP_ANDROID_TARGET=""
typeset FP_MODE="release" FP_FLAVOR="" FP_OUTPUT_DIR=""
typeset FP_BUILD_MARKER=""
typeset FP_OHOS_TARGET="" FP_OHOS_FLUTTER_SDK=""
typeset -a FP_FLUTTER=()

# 只给展示文字着色，日志保留纯文本。
fp_intro_line() {
    local role="$1" message="$2"
    if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" ]]; then
        if [[ "$role" == title ]]; then
            printf '\033[1;31m%s\033[0m\n' "$message"
        else
            printf '\033[0;34m%s\033[0m\n' "$message"
        fi
    else
        print -r -- "$message"
    fi
}

fp_show_intro() {
    [[ "${1:-}" != --help && "${1:-}" != --check ]] || return 0
    fp_intro_line title '━━━━━━━━━━ Flutter打包 ━━━━━━━━━━'
    fp_intro_line body '1、只处理指定文件夹自身的 Flutter 项目；Finder 子菜单指定 iOS、Android 或鸿蒙；直接运行未指定平台时用 fzf 选择。'
    fp_intro_line body '2、Android 支持 APK / AAB；iOS 构建 IPA；鸿蒙支持 HAP / APP，要求已适配的 ohos 工程与鸿蒙 Flutter SDK。'
    fp_intro_line body '3、将联网执行 flutter pub get、构建并写入项目 build 产物；不清理工程、不安装升级工具、不提交代码。'
    fp_intro_line body '4、优先使用项目已配置的 FVM SDK；模式默认 release，可使用 --mode / --flavor 指定。'
    fp_intro_line body '5、自述后回车继续；fzf 中 Esc、Ctrl+C 取消。日志保存在系统临时目录 JobsFlutterPackager.* 中。'
}

fp_help() {
    print -r -- 'Flutter打包：/bin/zsh PackageFlutter.zsh --project <Flutter根目录> [--platform ios|android|ohos] [--mode release|debug|profile] [--flavor NAME] [--target apk|appbundle|all] [--ohos-target hap|app|all] [--flutter-sdk 鸿蒙SDK根目录]'
    print -r -- '--check --project <目录>：只校验项目与参数，不等待、不创建日志、不调用 Flutter。'
    print -r -- '--help：显示帮助。--platform 指定后不再选择平台；省略时兼容 fzf 选择。--target 预设 Android 产物类型。'
    print -r -- '鸿蒙可用 OHOS_BUILD_TARGET、FLUTTER_OHOS_SDK；需要 DEVECO_SDK_HOME 和 Node/npm/ohpm/Hvigor/Java，不接受 --flavor。'
    print -r -- '也可使用 BUILD_MODE、FLAVOR、BUILD_TARGET、OPEN_AFTER_BUILD=0。缺 fzf 时请先执行 brew install fzf。'
}

fp_error() {
    local message="✖ $1"
    print -u2 -r -- "$message"
    [[ -z "$FP_LOG_FILE" ]] || print -r -- "$message" >> "$FP_LOG_FILE"
    return 1
}

fp_log() {
    print -r -- "$*" | /usr/bin/tee -a "$FP_LOG_FILE"
}

# 参数以数组交给子进程，路径和 flavor 都不经过 eval。
fp_parse() {
    FP_MODE="${BUILD_MODE:-release}"
    FP_FLAVOR="${FLAVOR:-}"
    FP_ANDROID_TARGET="${BUILD_TARGET:-}"
    FP_OHOS_TARGET="${OHOS_BUILD_TARGET:-}"
    FP_OHOS_FLUTTER_SDK="${FLUTTER_OHOS_SDK:-}"
    while (( $# > 0 )); do
        case "$1" in
            --project|--platform|--mode|--flavor|--target|--ohos-target|--flutter-sdk)
                (( $# >= 2 )) && [[ -n "$2" && "$2" != --* ]] || { fp_error "$1 缺少值"; return 2; }
                case "$1" in
                    --project)
                        [[ -z "$FP_PROJECT" ]] || { fp_error '只能传入一个项目目录'; return 2; }
                        FP_PROJECT="$2"
                        ;;
                    --platform)
                        [[ -z "$FP_PLATFORM" ]] || { fp_error '只能传入一个打包平台'; return 2; }
                        FP_PLATFORM="$2"
                        ;;
                    --mode) FP_MODE="$2" ;;
                    --flavor) FP_FLAVOR="$2" ;;
                    --target) FP_ANDROID_TARGET="$2" ;;
                    --ohos-target) FP_OHOS_TARGET="$2" ;;
                    --flutter-sdk) FP_OHOS_FLUTTER_SDK="$2" ;;
                esac
                shift 2
                ;;
            *) fp_error "未知参数：$1"; return 2 ;;
        esac
    done
    case "$FP_PLATFORM" in ''|ios|android|ohos) ;; *) fp_error "无效打包平台：$FP_PLATFORM"; return 2 ;; esac
    case "$FP_MODE" in release|debug|profile) ;; *) fp_error "无效模式：$FP_MODE"; return 2 ;; esac
    case "$FP_ANDROID_TARGET" in ''|apk|appbundle|all) ;; *) fp_error "无效 Android 产物：$FP_ANDROID_TARGET"; return 2 ;; esac
    case "$FP_OHOS_TARGET" in ''|hap|app|all) ;; *) fp_error "无效鸿蒙产物：$FP_OHOS_TARGET"; return 2 ;; esac
    [[ "$FP_OHOS_FLUTTER_SDK" != *[[:cntrl:]]* ]] || { fp_error '鸿蒙 SDK 路径不能包含控制字符'; return 2; }
    [[ "$FP_FLAVOR" != *[[:cntrl:]]* ]] || { fp_error 'flavor 不能包含控制字符'; return 2; }
}

# 与 Finder 过滤一样只认当前层真实清单，不向上或向下猜项目。
fp_validate_project() {
    local original="$FP_PROJECT" size=""
    while [[ "$original" == */ && "$original" != / ]]; do
        original="${original%/}"
    done
    [[ -n "$original" && "$original" != / && -d "$original" && ! -L "$original" && "$original" != *[[:cntrl:]]* ]] || {
        fp_error '请指定一个普通 Flutter 根目录，不接受链接或控制字符'
        return 1
    }
    fp_data directory-kind "$original" >/dev/null || { fp_error '目标不是普通文件夹'; return 1; }
    FP_PROJECT="${original:A}"
    [[ -f "$FP_PROJECT/pubspec.yaml" && ! -L "$FP_PROJECT/pubspec.yaml" ]] || { fp_error '当前层缺少普通 pubspec.yaml'; return 1; }
    size="$(/usr/bin/stat -f %z "$FP_PROJECT/pubspec.yaml")" || return 1
    [[ "$size" == <-> && "$size" -le 1048576 ]] || { fp_error 'pubspec.yaml 超过 1 MiB'; return 1; }
    fp_data pubspec "$FP_PROJECT/pubspec.yaml" >/dev/null || { fp_error '未确认 dependencies.flutter.sdk: flutter，已停止'; return 1; }
}

# 确认前不创建日志或执行项目命令。
fp_confirm() {
    local answer=""
    fp_intro_line body "项目：$FP_PROJECT"
    [[ -t 0 && -t 1 ]] || { fp_error '请在可交互终端运行'; return 1; }
    IFS= read -r 'answer?👉 已了解用途与影响，按回车继续；Ctrl+C 取消：'
}

fp_initialize() {
    setopt NO_NOMATCH PIPE_FAIL
    umask 077
    local run_dir=""
    run_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/JobsFlutterPackager.XXXXXX")" || return 1
    FP_LOG_FILE="$run_dir/PackageFlutter.log"
    : > "$FP_LOG_FILE" || return 1
    export PATH="${PATH:-/usr/bin:/bin}:/opt/homebrew/bin:/usr/local/bin:$HOME/.pub-cache/bin:$HOME/.fvm/bin"
    export DART_SUPPRESS_ANALYTICS=true FLUTTER_SUPPRESS_ANALYTICS=true
    trap 'fp_log "⚠ 已中断；日志：$FP_LOG_FILE"; exit 130' INT
    trap 'fp_log "⚠ 已停止；日志：$FP_LOG_FILE"; exit 143' TERM
    fp_log "ℹ 项目：$FP_PROJECT"
    fp_log "ℹ 日志：$FP_LOG_FILE"
    cd -P -- "$FP_PROJECT"
}

# 隔离用户 fzf 默认参数，避免 --filter 或自定义绑定改变确认行为。
fp_select() {
    local prompt="$1"
    shift
    FP_FZF="$(command -v fzf)"
    [[ -n "$FP_FZF" && -x "$FP_FZF" ]] && "$FP_FZF" --version >/dev/null 2>&1 || {
        fp_error 'fzf 不可用；请先在终端执行 brew install fzf，再重新右键。未运行依赖解析或构建。'
        return 2
    }
    print -rl -- "$@" | /usr/bin/env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_OPTS_FILE -u FZF_DEFAULT_COMMAND \
        "$FP_FZF" --no-multi --layout=reverse --height=10 --border --prompt="$prompt > " --header='回车选择；Esc / Ctrl+C 取消'
}

fp_select_platform() {
    local selection="" selection_ec=0
    if [[ -z "$FP_PLATFORM" ]]; then
        selection="$(fp_select '打包平台' 'Android' 'iOS' 'OpenHarmony')" || selection_ec=$?
        (( selection_ec == 0 )) || return "$selection_ec"
        case "$selection" in Android) FP_PLATFORM=android ;; iOS) FP_PLATFORM=ios ;; 'OpenHarmony') FP_PLATFORM=ohos ;; *) fp_error 'fzf 返回了无效平台'; return 2 ;; esac
    fi
    if [[ "$FP_PLATFORM" == android && -z "$FP_ANDROID_TARGET" ]]; then
        selection="$(fp_select 'Android 产物' 'APK' 'AAB' 'APK + AAB')" || return $?
        case "$selection" in APK) FP_ANDROID_TARGET=apk ;; AAB) FP_ANDROID_TARGET=appbundle ;; 'APK + AAB') FP_ANDROID_TARGET=all ;; *) fp_error 'fzf 返回了无效产物'; return 2 ;; esac
    fi
    if [[ "$FP_PLATFORM" == ohos ]]; then
        [[ -z "$FP_FLAVOR" ]] || { fp_error '鸿蒙入口使用工程默认 product / target，不接受 --flavor，避免适配 SDK 静默退回 default。'; return 2; }
        if [[ -z "$FP_OHOS_TARGET" ]]; then
            selection="$(fp_select '鸿蒙产物' 'HAP' 'APP' 'HAP + APP')" || return $?
            case "$selection" in HAP) FP_OHOS_TARGET=hap ;; APP) FP_OHOS_TARGET=app ;; 'HAP + APP') FP_OHOS_TARGET=all ;; *) fp_error 'fzf 返回了无效鸿蒙产物'; return 2 ;; esac
        fi
    fi
    fp_log "ℹ 平台：$FP_PLATFORM；模式：$FP_MODE；flavor：${FP_FLAVOR:-（默认）}"
}

# 固定 FVM 不默默降级；鸿蒙分支拒绝触发缺失 SDK 的自动下载。
fp_resolve_flutter() {
    if [[ "$FP_PLATFORM" == ohos && -n "$FP_OHOS_FLUTTER_SDK" ]]; then
        [[ -x "$FP_OHOS_FLUTTER_SDK/bin/flutter" ]] || { fp_error "指定鸿蒙 SDK 中没有 bin/flutter：$FP_OHOS_FLUTTER_SDK"; return 1; }
        FP_FLUTTER=("${FP_OHOS_FLUTTER_SDK:A}/bin/flutter")
    elif [[ -x "$FP_PROJECT/.fvm/flutter_sdk/bin/flutter" ]]; then
        FP_FLUTTER=("$FP_PROJECT/.fvm/flutter_sdk/bin/flutter")
    elif [[ -e "$FP_PROJECT/.fvmrc" || -e "$FP_PROJECT/.fvm/fvm_config.json" || -L "$FP_PROJECT/.fvm/flutter_sdk" ]]; then
        [[ "$FP_PLATFORM" != ohos ]] || { fp_error '鸿蒙项目固定了 FVM，但本地 SDK 不可用；请先恢复对应 SDK，或用 --flutter-sdk 显式指定，不自动下载 SDK。'; return 1; }
        command -v fvm >/dev/null 2>&1 || { fp_error '项目固定了 FVM，但项目 SDK / fvm 不可用，请先恢复对应版本'; return 1; }
        FP_FLUTTER=("$(command -v fvm)" flutter)
    elif command -v flutter >/dev/null 2>&1; then
        FP_FLUTTER=("$(command -v flutter)")
    else
        fp_error '找不到 Flutter SDK，请检查项目 FVM 或终端 PATH'
        return 1
    fi
    fp_log "ℹ Flutter 命令：${(j: :)FP_FLUTTER}"
}

fp_check_java17() {
    local candidate="${JAVA_HOME:-}" version=""
    if [[ -x "$candidate/bin/java" ]]; then
        version="$("$candidate/bin/java" -version 2>&1)" || version=""
    fi
    if ! print -r -- "$version" | /usr/bin/grep -Eq 'version "17([."]|$)'; then
        candidate="$(/usr/libexec/java_home -v 17 2>/dev/null)" || candidate=""
        if [[ -z "$candidate" ]]; then
            for candidate in /opt/homebrew/opt/openjdk@17 /usr/local/opt/openjdk@17; do
                [[ -x "$candidate/bin/java" ]] && break
                candidate=""
            done
        fi
        [[ -n "$candidate" && -x "$candidate/bin/java" ]] || { fp_error 'Android 打包需要可用 JDK 17，请先配置 JAVA_HOME'; return 1; }
        version="$("$candidate/bin/java" -version 2>&1)" || return 1
    fi
    print -r -- "$version" | /usr/bin/grep -Eq 'version "17([."]|$)' || { fp_error '当前 Java 不是 17'; return 1; }
    export JAVA_HOME="$candidate" PATH="$candidate/bin:$PATH"
    fp_log "ℹ JAVA_HOME：$JAVA_HOME"
}

# 原生构建日志实时保留；PIPE_FAIL 让 Flutter 或 tee 任一失败立即停止。
fp_run_step() {
    local title="$1" result=0
    shift
    fp_log "▶ $title"
    "$@" 2>&1 | /usr/bin/tee -a "$FP_LOG_FILE" || result=$?
    (( result == 0 )) || { fp_error "$title 失败，退出码 $result；日志：$FP_LOG_FILE"; return "$result"; }
    fp_log "✔ $title 完成"
}

# 复用 DevEco 工具链，仅影响本进程，不替换独立 OpenHarmony SDK 变量。
fp_prepare_harmony_environment() {
    local requested="${DEVECO_STUDIO_HOME:-${TOOL_HOME:-}}" contents="" candidate=""
    local -a candidates=()
    [[ -f "$FP_PROJECT/ohos/build-profile.json5" && -f "$FP_PROJECT/ohos/oh-package.json5" ]] || {
        fp_error '项目缺少 ohos/build-profile.json5 或 ohos/oh-package.json5，请先完成鸿蒙适配。'
        return 1
    }
    if [[ -z "${DEVECO_SDK_HOME:-}" && -n "${HOS_SDK_HOME:-}" ]]; then
        export DEVECO_SDK_HOME="$HOS_SDK_HOME"
    fi
    if [[ -n "$requested" ]]; then
        [[ ! -d "$requested/Contents" ]] || requested="$requested/Contents"
        [[ -d "$requested" ]] || { fp_error "DevEco 路径不存在：$requested"; return 1; }
        contents="$requested"
    elif [[ -z "${DEVECO_SDK_HOME:-}" ]]; then
        for candidate in /Applications/DevEco*.app/Contents(N) "$HOME"/Applications/DevEco*.app/Contents(N); do
            [[ ! -d "$candidate/sdk" ]] || candidates+=("$candidate")
        done
        if (( ${#candidates[@]} > 1 )); then
            fp_error '发现多个 DevEco Studio，请用 DEVECO_STUDIO_HOME 明确选择。'
            return 1
        fi
        (( ${#candidates[@]} == 0 )) || contents="${candidates[1]}"
    fi
    if [[ -n "$contents" ]]; then
        export TOOL_HOME="$contents"
        [[ -n "${DEVECO_SDK_HOME:-}" ]] || export DEVECO_SDK_HOME="$contents/sdk"
        export PATH="$contents/tools/node/bin:$contents/tools/ohpm/bin:$contents/tools/hvigor/bin:$contents/tool/node/bin:$contents/ohpm/bin:$contents/hvigor/bin:$PATH"
        if [[ -z "${JAVA_HOME:-}" && -x "$contents/jbr/Contents/Home/bin/java" ]]; then
            export JAVA_HOME="$contents/jbr/Contents/Home"
        fi
    fi
    [[ -n "${DEVECO_SDK_HOME:-}" && -d "$DEVECO_SDK_HOME" ]] || {
        fp_error '没有有效 DEVECO_SDK_HOME，请先准备 HarmonyOS SDK；OHOS_SDK_HOME 不能直接当作同义路径。'
        return 1
    }
    if [[ -n "${JAVA_HOME:-}" ]]; then
        [[ -x "$JAVA_HOME/bin/java" ]] || { fp_error "JAVA_HOME 中缺少 bin/java：$JAVA_HOME"; return 1; }
        export PATH="$JAVA_HOME/bin:$PATH"
    fi
    if [[ -n "${NODE_HOME:-}" ]]; then
        [[ -x "$NODE_HOME/bin/node" ]] || { fp_error "NODE_HOME 中缺少 bin/node：$NODE_HOME"; return 1; }
        export PATH="$NODE_HOME/bin:$PATH"
    fi
    rehash
    fp_log "ℹ HarmonyOS SDK：$DEVECO_SDK_HOME"
}
# 在 pub get 前检查全部依赖和所选包型能力，普通 Flutter SDK 会被拒绝。
fp_check_harmony_toolchain() {
    fp_prepare_harmony_environment || return $?
    local tool="" target="" help_text=""
    local -a targets=("${FP_OHOS_TARGET:-hap}")
    [[ "$FP_OHOS_TARGET" != all ]] || targets=(hap app)
    for tool in node npm ohpm hvigorw java; do
        command -v "$tool" >/dev/null 2>&1 || { fp_error "缺少 $tool，请检查 DevEco 工具目录与 PATH。"; return 1; }
        if [[ "$tool" == java ]]; then
            fp_run_step "检查 $tool" "$tool" -version || return $?
        else
            fp_run_step "检查 $tool" "$tool" --version || return $?
        fi
    done
    fp_run_step '检查鸿蒙 Flutter' "${FP_FLUTTER[@]}" --version || return $?
    for target in "${targets[@]}"; do
        if ! help_text="$("${FP_FLUTTER[@]}" build "$target" --help 2>&1)"; then
            fp_log "$help_text"
            fp_error "当前 SDK 不支持 flutter build $target，请选择匹配工程的鸿蒙适配版 SDK。"
            return 1
        fi
        print -r -- "$help_text" | /usr/bin/grep -Fq "flutter build $target" || {
            fp_error "未确认 flutter build $target 能力；普通 Android / iOS Flutter SDK 不能替代。"
            return 1
        }
    done
}

# 按所选平台检查前置条件，不改动平台工程与签名配置。
fp_check_toolchain() {
    [[ "$(/usr/bin/uname -s)" == Darwin ]] || { fp_error '本脚本需要 macOS'; return 1; }
    if [[ "$FP_PLATFORM" == android ]]; then
        [[ -d "$FP_PROJECT/android" && -f "$FP_PROJECT/android/gradlew" ]] || { fp_error '项目缺少 android / gradlew'; return 1; }
        fp_check_java17 || return $?
    elif [[ "$FP_PLATFORM" == ohos ]]; then
        fp_check_harmony_toolchain || return $?
    else
        [[ -d "$FP_PROJECT/ios" ]] || { fp_error '项目缺少 ios 平台目录'; return 1; }
        command -v xcodebuild >/dev/null 2>&1 || { fp_error '缺少 Xcode / xcodebuild'; return 1; }
        if [[ -f "$FP_PROJECT/ios/Podfile" ]]; then
            command -v pod >/dev/null 2>&1 || { fp_error '项目含 Podfile，但 CocoaPods 不可用'; return 1; }
        fi
        fp_run_step '检查 Xcode' xcodebuild -version || return $?
    fi
}

# 兼容适配 SDK 汇总目录与 DevEco 底层输出，只报告非空最终包文件。
fp_report_harmony_outputs() {
    local target="$1" output_root="" file="" found=0
    local -a roots=("$FP_PROJECT/build/ohos" "$FP_PROJECT/ohos/build")
    roots+=("$FP_PROJECT"/ohos/*/build(N/))
    FP_OUTPUT_DIR=""
    for output_root in "${roots[@]}"; do
        [[ -d "$output_root" ]] || continue
        while IFS= read -r -d '' file; do
            [[ -s "$file" ]] || continue
            if [[ -n "$FP_BUILD_MARKER" && ! "$file" -nt "$FP_BUILD_MARKER" ]]; then
                fp_log "ℹ 构建命令成功，复用现存产物，请核对模式与签名：$file"
            fi
            if [[ "${file:t}" == *-unsigned.* ]]; then
                fp_log "⚠ 未签名产物：$file；安装或上架前须完成相应签名。"
            else
                fp_log "✔ 产物：$file"
            fi
            [[ -n "$FP_OUTPUT_DIR" ]] || FP_OUTPUT_DIR="${file:h}"
            found=$((found + 1))
        done < <(/usr/bin/find "$output_root" \( -type d \( -name node_modules -o -name intermediates \) -prune \) -o \( -type f -name "*.$target" \( -path '*/outputs/*' -o -path '*/build/ohos/*' \) -print0 \))
    done
    (( found > 0 )) || { fp_error "构建已返回，但未发现非空 .$target 鸿蒙产物。"; return 1; }
    if [[ "${OPEN_AFTER_BUILD:-1}" == 1 ]]; then
        /usr/bin/open "$FP_OUTPUT_DIR" || fp_log "⚠ 无法打开产物目录：$FP_OUTPUT_DIR"
    fi
    return 0
}

fp_report_outputs() {
    local target="$1" file="" pattern="" found=0
    if [[ "$target" == hap || "$target" == app ]]; then
        fp_report_harmony_outputs "$target"
        return $?
    fi
    if [[ "$target" == ipa ]]; then
        FP_OUTPUT_DIR="$FP_PROJECT/build/ios/ipa"
        pattern='*.ipa'
    elif [[ "$target" == apk ]]; then
        FP_OUTPUT_DIR="$FP_PROJECT/build/app/outputs/flutter-apk"
        pattern="*-${FP_MODE}.apk"
    else
        FP_OUTPUT_DIR="$FP_PROJECT/build/app/outputs/bundle"
        pattern="*-${FP_MODE}.aab"
    fi
    [[ -d "$FP_OUTPUT_DIR" ]] || { fp_error "构建已返回，但没有产物目录：$FP_OUTPUT_DIR；iOS 请检查签名与导出配置"; return 1; }
    while IFS= read -r -d '' file; do
        [[ -s "$file" ]] || continue
        if [[ "$target" == ipa && -n "$FP_BUILD_MARKER" && ! "$file" -nt "$FP_BUILD_MARKER" ]]; then
            fp_log "ℹ 保留旧 IPA，未计入本轮导出：$file"
            continue
        fi
        if [[ "$target" != ipa ]]; then
            local extension="${target/appbundle/aab}" expected=""
            expected="app-${FP_MODE}.${extension}"
            [[ -z "$FP_FLAVOR" ]] || expected="app-${FP_FLAVOR:l}-${FP_MODE}.${extension}"
            # split-per-abi 产物也属于当前 flavor，但其它 flavor 不计入。
            if [[ "${file:t}" != "$expected" ]]; then
                [[ "$target" == apk && "${file:t}" == app-* && -z "$FP_FLAVOR" && "${file:t}" == app-(armeabi-v7a|arm64-v8a|x86_64)-${FP_MODE}.apk ]] || continue
            fi
            if [[ -n "$FP_BUILD_MARKER" && ! "$file" -nt "$FP_BUILD_MARKER" ]]; then
                fp_log "ℹ 构建命令成功，复用现存产物，请核对模式与签名：$file"
            fi
        fi
        fp_log "✔ 产物：$file"
        found=$(( found + 1 ))
    done < <(/usr/bin/find "$FP_OUTPUT_DIR" -type f -name "$pattern" -print0)
    (( found > 0 )) || { fp_error "没有发现 $target 产物：$FP_OUTPUT_DIR"; return 1; }
    if [[ "${OPEN_AFTER_BUILD:-1}" == 1 ]]; then
        /usr/bin/open "$FP_OUTPUT_DIR" || fp_log "⚠ 无法打开产物目录：$FP_OUTPUT_DIR"
    fi
    return 0
}

fp_build() {
    local target=""
    local -a targets=() args=()
    fp_run_step 'flutter pub get' "${FP_FLUTTER[@]}" pub get || return $?
    if [[ "$FP_PLATFORM" == ios ]]; then
        targets=(ipa)
    elif [[ "$FP_PLATFORM" == ohos ]]; then
        targets=("${FP_OHOS_TARGET:-hap}")
        [[ "$FP_OHOS_TARGET" != all ]] || targets=(hap app)
    elif [[ "$FP_ANDROID_TARGET" == all ]]; then
        targets=(apk appbundle)
    else
        targets=("$FP_ANDROID_TARGET")
    fi
    for target in "${targets[@]}"; do
        args=(build "$target" "--$FP_MODE")
        [[ -z "$FP_FLAVOR" ]] || args+=(--flavor "$FP_FLAVOR")
        FP_BUILD_MARKER="$(/usr/bin/mktemp "${FP_LOG_FILE:h}/build-start.XXXXXX")" || return 1
        fp_run_step "flutter build $target" "${FP_FLUTTER[@]}" "${args[@]}" || return $?
        fp_report_outputs "$target" || return $?
    done
    fp_log "✔ Flutter打包完成；日志：$FP_LOG_FILE"
}

# 保留只读检查入口，并集中处理平台选择、取消与失败传播。
fp_dispatch() {
    if [[ "${1:-}" == --help ]]; then
        fp_help
        return 0
    fi
    if [[ "${1:-}" == --check ]]; then
        shift
        fp_parse "$@" || return $?
        fp_validate_project || return $?
        print -r -- "✔ Flutter 项目：$FP_PROJECT；模式：$FP_MODE；未执行构建。"
        return 0
    fi
    fp_parse "$@" || return $? # 参数有误时在项目操作前停止。
    fp_validate_project || return $? # 只接受当前层真实 Flutter 清单。
    fp_confirm || return $? # 确认前不创建日志或执行项目命令。
    fp_initialize || return $? # 建立私有日志，仅修改当前进程环境。
    local selection_ec=0
    fp_select_platform || selection_ec=$? # 已指定平台时只选择尚未指定的包型；iOS 无需 fzf。
    if (( selection_ec == 1 || selection_ec == 130 )); then
        fp_log 'ℹ 已取消平台 / 产物选择，未执行依赖解析或构建。'
        return 0
    fi
    (( selection_ec == 0 )) || return "$selection_ec"
    fp_resolve_flutter || return $? # 使用项目固定 SDK 或既有系统 SDK。
    fp_check_toolchain || return $? # 先检查相应平台工具链。
    fp_build # 逐步构建，失败保留退出码并停止。
}

# 唯一入口先展示自述，再执行请求；帮助与只读检查保持无交互。
main() {
    fp_show_intro "$@" # 说明用途与影响，帮助和只读检查跳过运行提示。
    fp_dispatch "$@" # 校验项目并选择平台，按顺序检查与构建。
}

main "$@"
