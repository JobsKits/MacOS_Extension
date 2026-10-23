#!/bin/zsh
# 脚本自述：
# - 脚本名称：ManageHarmonyFlutterVersion.zsh，Created by Jobs。
# - 核心用途：查询 CPF-Flutter 的鸿蒙适配 tag，安装或切换指定项目的 FVM SDK。
# - 影响范围：确认后准备缺失 FVM、隔离 SDK 缓存和项目绑定；保留 IDE / ignore 配置。
# - 运行提示：先读自述并回车，再选择版本；最终输入 YES 才执行，--check 仅本地只读检查。

typeset FH_REPO='https://gitcode.com/CPF-Flutter/flutter_flutter.git'
typeset FH_PROJECT='' FH_CACHE='' FH_RUN='' FH_LOG='' FH_GIT='' FH_FVM=''
typeset FH_TAG='' FH_COMMIT='' FH_VERSION='' FH_MODE='' FH_CHECK=0 FH_HELP=0
typeset FH_PROJECT_LOCK='' FH_CACHE_LOCK='' FH_MUTATED=0 FH_SUCCESS=0
typeset FH_TOOLS='' FH_REMOTE_PID='' FH_BASELINE='' FH_EXPECTED_CONFIG='' FH_EXPECTED_FVM=''
typeset FH_INITIAL_CONFIG='' FH_INITIAL_FVM=''
typeset -a FH_ROWS FH_CHANGED

# 同步输出状态与纯文本日志。
fh_log() {
    local message="$*"
    print -r -- "$message"
    [[ -z "$FH_LOG" ]] || print -r -- "$message" >> "$FH_LOG"
    return 0
}
# 返回明确的失败状态。
fh_error() {
    fh_log "✖ $*" >&2
    return 1
}
# 首屏标题与正文分色，非终端不输出控制码。
fh_intro_line() {
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
# EOF 与非确认输入均不会触发默认执行。
fh_read() {
    print -u2 -n -r -- "$1"
    IFS= read -r REPLY || { fh_error '输入结束，已取消。'; return 130; }
}
# 在任何传输之前说明对象、来源与目标。
fh_source() {
    fh_log '━━━━━━━━━━ 来源 ━━━━━━━━━━'
    fh_log "对象：$1"
    fh_log "来源地址：$2"
    fh_log "目标位置：$3"
}
# 保留外部命令的真实失败码。
fh_run() {
    local -a result
    "$@" 2>&1 | /usr/bin/tee -a "$FH_LOG"
    result=("${pipestatus[@]}")
    (( result[1] == 0 )) || return "${result[1]}"
    return "${result[2]}"
}
# 只解析数据，不将项目路径、远端 tag 或 JSON 字段拼进可执行源码。
fh_data() {
    /usr/bin/osascript -l JavaScript - "$@" <<'JXA'
ObjC.import('Foundation');
function run(args) {
    var fm = $.NSFileManager.defaultManager;
    function read(path) {
        var text = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
        if (!text) throw Error('无法读取：' + path);
        return ObjC.unwrap(text);
    }
    function object(path) {
        var value = JSON.parse(read(path));
        if (!value || Array.isArray(value) || typeof value !== 'object') throw Error('配置不是 JSON 对象');
        return value;
    }
    function safe(value) {
        if (typeof value !== 'string' || /[\x00-\x1f\x7f]/.test(value)) throw Error('字段含控制字符');
        return value;
    }
    function tag(value) { return /^v?\d+\.\d+\.\d+[+-]ohos(?:[-+._][0-9A-Za-z]+)*$/.test(value); }
    function sha(value) { return /^[0-9a-f]{40}$/.test(value); }
    function configuration() { return args[1] === '-' ? {} : object(args[1]); }
    if (args[0] === 'directory') {
        var p = args[1], props = ObjC.deepUnwrap($.NSURL.fileURLWithPath(p).resourceValuesForKeysError($([$.NSURLIsDirectoryKey, $.NSURLIsPackageKey, $.NSURLIsAliasFileKey, $.NSURLIsSymbolicLinkKey]), null));
        if (!props || props.NSURLIsDirectoryKey !== true || props.NSURLIsPackageKey !== false || props.NSURLIsAliasFileKey !== false || props.NSURLIsSymbolicLinkKey !== false) throw Error('目标必须是普通目录');
        return 'directory';
    }
    if (args[0] === 'fingerprint') {
        function inspect(path) {
            var attributes = ObjC.deepUnwrap(fm.attributesOfItemAtPathError(path, null));
            if (!attributes) return null;
            var type = attributes.NSFileType, result = {type:type,identity:attributes.NSFileSystemFileNumber,device:attributes.NSFileSystemNumber,permissions:attributes.NSFilePosixPermissions};
            if (type === 'NSFileTypeSymbolicLink') result.link = ObjC.unwrap(fm.destinationOfSymbolicLinkAtPathError(path,null));
            else if (type === 'NSFileTypeDirectory') {
                var names = ObjC.deepUnwrap(fm.contentsOfDirectoryAtPathError(path,null)) || [];
                result.children = names.sort().map(function(name) { return [name,inspect(path+'/'+name)]; });
            } else if (type === 'NSFileTypeRegular') {
                if (Number(attributes.NSFileSize) > 1048576) throw Error('FVM 元数据超过 1 MiB');
                result.content = read(path);
            } else throw Error('FVM 配置包含不支持的文件类型');
            return result;
        }
        return JSON.stringify(inspect(args[1]));
    }
    if (args[0] === 'move') {
        if (!fm.moveItemAtPathToPathError(args[1],args[2],null)) throw Error('无法移动或目标已存在：'+args[2]);
        return 'moved';
    }
    if (args[0] === 'current') {
        var c = configuration();
        return safe(c.flutter || c.flutterSdkVersion || '未配置');
    }
    if (args[0] === 'config') {
        var c = configuration();
        c.flutter = safe(args[2]); delete c.flutterSdkVersion;
        c.cachePath = safe(args[3]); c.flutterUrl = safe(args[4]); c.useGitCache = false;
        if (args[5] === 'temporary') {
            c.updateVscodeSettings = false; c.updateGitIgnore = false;
            c.updateMelosSettings = false; c.runPubGetOnSdkChanges = false;
        }
        return JSON.stringify(c, null, 2);
    }
    if (args[0] === 'rows') {
        var versions = {}, rows = [], remote = args[1] === '-' ? '' : read(args[1]);
        remote.split(/\r?\n/).forEach(function(line) {
            var m = /^([0-9a-f]{40})\trefs\/tags\/(.+?)(\^\{\})?$/.exec(line);
            if (!m || !tag(m[2])) return;
            if (!versions[m[2]] || m[3]) versions[m[2]] = {tag:m[2], sha:m[1], mode:'remote'};
        });
        var root = args[2] + '/versions', names = ObjC.deepUnwrap(fm.contentsOfDirectoryAtPathError(root, null)) || [];
        names.forEach(function(name) {
            if (!/^custom_jobs_ohos_[0-9a-f]{40}$/.test(name)) return;
            try {
                var record = object(root + '/' + name + '/.jobs-harmony-source.json');
                if (tag(record.tag) && sha(record.commit) && record.repo === args[3] && name === 'custom_jobs_ohos_' + record.commit && !versions[record.tag]) versions[record.tag] = {tag:record.tag, sha:record.commit, mode:'local'};
            } catch (_) {}
        });
        rows = Object.keys(versions).map(function(key) { return versions[key]; });
        rows.sort(function(a,b) {
            var ap = /beta|alpha|canary|pre|dev|rc/i.test(a.tag), bp = /beta|alpha|canary|pre|dev|rc/i.test(b.tag);
            if (ap !== bp) return ap ? 1 : -1;
            var an = a.tag.match(/\d+/g).map(Number), bn = b.tag.match(/\d+/g).map(Number);
            for (var i=0; i<Math.max(an.length,bn.length); i++) if ((an[i]||0) !== (bn[i]||0)) return (bn[i]||0)-(an[i]||0);
            return b.tag.localeCompare(a.tag);
        });
        return rows.map(function(r) { return [r.tag,r.sha,r.mode].join('\t'); }).join('\n');
    }
    if (args[0] === 'manifest') return JSON.stringify({tag:safe(args[1]),commit:safe(args[2]),repo:safe(args[3])},null,2);
    throw Error('未知数据操作');
}
JXA
}
# 与菜单复用同一已验证的 Flutter 项目识别器，并保护配置实体边界。
fh_validate() {
    [[ -d "$FH_PROJECT" && ! -L "$FH_PROJECT" && "$FH_PROJECT" != / && "$FH_PROJECT" != "$HOME" ]] || { fh_error '请指定普通 Flutter 项目目录。'; return 1; }
    [[ -f "$FH_PROJECT/pubspec.yaml" && ! -L "$FH_PROJECT/pubspec.yaml" ]] || { fh_error '同层须有普通 pubspec.yaml。'; return 1; }
    fh_data directory "$FH_PROJECT" >/dev/null || return 1
    local kind=''
    kind="$(/bin/zsh "$FH_TOOLS/CleanBuildArtifacts.zsh" "$FH_PROJECT" --detect)" || return 1
    [[ "$kind" == Flutter ]] || { fh_error '目标未通过菜单共用的 Flutter 项目识别。'; return 1; }
    local component child
    for component in .fvmrc .fvm .vscode .vscode/settings.json .gitignore; do
        [[ ! -L "$FH_PROJECT/$component" ]] || { fh_error "配置不可为符号链接：$component"; return 1; }
    done
    [[ ! -e "$FH_PROJECT/.fvm" || -d "$FH_PROJECT/.fvm" ]] || { fh_error '.fvm 不是普通目录。'; return 1; }
    [[ ! -e "$FH_PROJECT/.fvmrc" || -f "$FH_PROJECT/.fvmrc" ]] || { fh_error '.fvmrc 不是普通文件。'; return 1; }
    [[ ! -e "$FH_PROJECT/.fvm/flutter_sdk" || -L "$FH_PROJECT/.fvm/flutter_sdk" ]] || { fh_error '.fvm/flutter_sdk 是真实目录，保留并停止，避免搬动 SDK。'; return 1; }
    if [[ -d "$FH_PROJECT/.fvm" ]]; then
        for child in "$FH_PROJECT/.fvm"/*(DN); do
            [[ ! -d "$child" || -L "$child" || "${child:t}" == versions ]] || { fh_error "未知 FVM 子目录，保留并停止：$child"; return 1; }
        done
        if [[ -e "$FH_PROJECT/.fvm/versions" || -L "$FH_PROJECT/.fvm/versions" ]]; then
            [[ -d "$FH_PROJECT/.fvm/versions" && ! -L "$FH_PROJECT/.fvm/versions" ]] || { fh_error '.fvm/versions 须是普通链接容器目录。'; return 1; }
            for child in "$FH_PROJECT/.fvm/versions"/*(DN); do
                [[ -L "$child" ]] || { fh_error "FVM versions 内有真实文件或目录，保留并停止：$child"; return 1; }
            done
        fi
    fi
    fh_data current "$(fh_original_config)" >/dev/null || return 1
}
# 没有工程级配置时从空对象建立绑定，不继承父工程。
fh_original_config() {
    if [[ -f "$FH_PROJECT/.fvmrc" ]]; then print -r -- "$FH_PROJECT/.fvmrc"; else print -r -- '-'; fi
}
# 安装动作的首屏授权；只读模式跳过阻塞。
show_script_intro_and_wait() {
    (( FH_HELP )) && return 0
    fh_intro_line title '━━━━━━━━━━ 安装/切换 Flutter@OpenHarmony SDK ━━━━━━━━━━'
    fh_intro_line body '1、从 CPF-Flutter 官方适配仓库的鸿蒙 tag 中选择，稳定 tag 按版本倒序优先；编号回车采用首项，fzf 可搜索。'
    fh_intro_line body '2、先选择并最终输入 YES，再安装缺失 FVM 和 SDK；只绑定当前项目，不切换全局 Flutter，不改 Shell / 代理。'
    fh_intro_line body '3、会保存 .fvmrc / FVM 链接快照，失败或中断自动恢复；保留 IDE 与 ignore，不执行 pub get。'
    fh_intro_line body '4、Ctrl+C 或非确认输入可取消；--check 不安装、不联网、不写文件。日志位于临时目录 JobsHarmonyFlutter.*。'
    fh_intro_line body "目标项目：$FH_PROJECT"
    (( FH_CHECK )) && return 0
    fh_read '阅读完毕，按回车继续；任意非空输入取消：' || return $?
    [[ -z "$REPLY" ]] || return 130
}
# 仅盘点本地绑定和带来源记录的缓存。
fh_check() {
    fh_log "当前绑定：$(fh_data current "$(fh_original_config)")" || return 1
    fh_log "鸿蒙来源：$FH_REPO"
    fh_log "隔离缓存：$FH_CACHE"
    local rows
    rows="$(fh_data rows - "$FH_CACHE" "$FH_REPO")" || return 1
    if [[ -n "$rows" ]]; then fh_log "$rows"; else fh_log '本机没有带来源记录的鸿蒙 SDK 缓存。'; fi
    fh_log '✔ 本地只读盘点完成；未运行 SDK / FVM，未验证真实构建。'
}
# 查询设置45秒总上限，退出时会回收仍在运行的子进程。
fh_remote() {
    local elapsed=0 result=0
    GIT_TERMINAL_PROMPT=0 "$FH_GIT" -c http.lowSpeedLimit=1024 -c http.lowSpeedTime=30 ls-remote --tags "$FH_REPO" > "$FH_RUN/tags" 2>> "$FH_LOG" &
    FH_REMOTE_PID="$!"
    while kill -0 "$FH_REMOTE_PID" 2>/dev/null; do
        if (( elapsed >= 45 )); then
            kill -TERM "$FH_REMOTE_PID" 2>/dev/null
            /bin/sleep 1
            kill -KILL "$FH_REMOTE_PID" 2>/dev/null
            wait "$FH_REMOTE_PID" 2>/dev/null
            FH_REMOTE_PID=''
            fh_log '⚠ 远端 tag 查询超过45秒，已终止。'
            return 124
        fi
        /bin/sleep 1
        (( elapsed += 1 ))
    done
    wait "$FH_REMOTE_PID" || result=$?
    FH_REMOTE_PID=''
    return "$result"
}
# 只读取 CPF 远端标签；断网回退明确的本机缓存。
fh_versions() {
    FH_GIT="$(command -v git 2>/dev/null)"
    [[ -n "$FH_GIT" ]] || { fh_error '缺少 Git / Apple Command Line Tools，请安装后重试。'; return 1; }
    fh_source 'Flutter@OpenHarmony tag 清单' "$FH_REPO" '仅查询，不下载 SDK'
    local listing='-' rows=''
    if fh_remote; then
        listing="$FH_RUN/tags"
    else
        fh_log '⚠ 无法查询远端，只提供带来源记录的本机缓存；不声称已获取最新版本。'
    fi
    rows="$(fh_data rows "$listing" "$FH_CACHE" "$FH_REPO")" || return 1
    [[ -n "$rows" ]] || { fh_error '没有可用鸿蒙版本，请检查网络后重新加载此动作。'; return 1; }
    FH_ROWS=("${(@f)rows}")
}
# fzf 和编号均只接受本次可信清单内的精确标签。
fh_choose() {
    local row='' answer='' index=0 fzf_bin=''
    fzf_bin="$(command -v fzf 2>/dev/null)"
    if [[ -t 0 && -t 1 && -n "$fzf_bin" ]]; then
        row="$(printf '%s\n' "${FH_ROWS[@]}" | "$fzf_bin" --no-multi --delimiter=$'\t' --with-nth=1,3 --prompt='鸿蒙 SDK > ' --header='稳定 tag 在前；Enter 选择，Esc 取消')" || return 130
    else
        for row in "${FH_ROWS[@]}"; do
            (( index += 1 ))
            fh_log "$index、${row%%$'\t'*}  [${row##*$'\t'}]"
        done
        fh_read '输入版本编号（回车=1；Q 取消）：' || return $?
        answer="${REPLY:-1}"
        [[ "$answer" == <-> && "$answer" -ge 1 && "$answer" -le "${#FH_ROWS}" ]] || return 130
        row="${FH_ROWS[$answer]}"
    fi
    (( ${FH_ROWS[(Ie)$row]} > 0 )) || { fh_error '选择结果不在本次可信清单内。'; return 1; }
    IFS=$'\t' read -r FH_TAG FH_COMMIT FH_MODE <<< "$row"
    FH_VERSION="custom_jobs_ohos_$FH_COMMIT"
    FH_INITIAL_CONFIG="$(fh_data fingerprint "$FH_PROJECT/.fvmrc")" || return 1
    FH_INITIAL_FVM="$(fh_data fingerprint "$FH_PROJECT/.fvm")" || return 1
    FH_BASELINE="$FH_INITIAL_CONFIG|$FH_INITIAL_FVM"
    fh_log "当前：$(fh_data current "$(fh_original_config)")"
    fh_source "Flutter OH $FH_TAG / $FH_COMMIT" "$FH_REPO" "$FH_CACHE/versions/$FH_VERSION"
    fh_read '输入 YES 确认安装 / 切换本项目；其它输入取消：' || return $?
    [[ "$REPLY" == YES ]] || return 130
}
# 最终授权后才准备FVM；已安装的健康组件直接复用。
fh_ensure_fvm() {
    FH_FVM="$(command -v fvm 2>/dev/null)"
    if [[ -z "$FH_FVM" ]]; then
        local brew_bin='' prefix=''
        brew_bin="$(command -v brew 2>/dev/null)"
        [[ -n "$brew_bin" || ! -x /opt/homebrew/bin/brew ]] || brew_bin=/opt/homebrew/bin/brew
        [[ -n "$brew_bin" || ! -x /usr/local/bin/brew ]] || brew_bin=/usr/local/bin/brew
        [[ -n "$brew_bin" ]] || { fh_error '缺少 FVM 和 Homebrew，请先安装 Homebrew 后重试：https://brew.sh/'; return 1; }
        prefix="$("$brew_bin" --prefix)" || return 1
        [[ "$prefix" == /* && -d "$prefix" ]] || { fh_error 'Homebrew 前缀无效。'; return 1; }
        fh_source 'FVM（官方文档 btwld/fvm tap）' 'https://github.com/btwld/homebrew-fvm' "$prefix"
        fh_run env HOMEBREW_NO_AUTO_UPDATE=1 "$brew_bin" install btwld/fvm/fvm || return $?
        rehash
        FH_FVM="$(command -v fvm 2>/dev/null)"
        [[ -n "$FH_FVM" || ! -x "$prefix/bin/fvm" ]] || FH_FVM="$prefix/bin/fvm"
    fi
    [[ -n "$FH_FVM" ]] || { fh_error '安装后仍找不到 FVM。'; return 1; }
    fh_run "$FH_FVM" --version || return $?
    local help_text
    help_text="$("$FH_FVM" use --help)" || return 1
    [[ "$help_text" == *--skip-pub-get* && "$help_text" == *--skip-setup* ]] || { fh_error 'FVM 版本过旧，须支持 --skip-setup / --skip-pub-get。'; return 1; }
}
# 缓存路径各级必须为当前用户的真实目录，不沿软链接写入。
fh_cache_boundaries() {
    local component current="$HOME"
    [[ -d "$HOME" && ! -L "$HOME" ]] || { fh_error 'HOME 不是普通目录。'; return 1; }
    for component in Library Caches JobsFlutter fvm harmony versions .locks; do
        case "$component" in
            .locks) current="$FH_CACHE/.locks" ;;
            *) current="$current/$component" ;;
        esac
        [[ ! -L "$current" && ( ! -e "$current" || -d "$current" ) ]] || { fh_error "缓存路径不是普通目录：$current"; return 1; }
    done
}
# 独立缓存沿用已有鸿蒙配置脚本的 custom_<name> 注册方式，不写全局 fork 别名。
fh_sdk() {
    local target="$FH_CACHE/versions/$FH_VERSION" stage='' actual='' origin='' dirty='' help_text=''
    fh_cache_boundaries || return 1
    /bin/mkdir -p "$FH_CACHE/versions" "$FH_CACHE/.locks" || return 1
    /bin/mkdir "$FH_CACHE/.locks/$FH_VERSION" 2>/dev/null || { fh_error '同一鸿蒙 SDK 正被其它进程处理，请稍后重试。'; return 1; }
    FH_CACHE_LOCK="$FH_CACHE/.locks/$FH_VERSION"
    if [[ -e "$target" || -L "$target" ]]; then
        [[ -d "$target/.git" && ! -L "$target" && ! -L "$target/.git" ]] || { fh_error "缓存不是独立 Git SDK，保留并停止：$target"; return 1; }
    else
        [[ "$FH_MODE" == remote ]] || { fh_error '本机缓存已消失，请重新加载版本列表。'; return 1; }
        fh_source "下载 Flutter OH $FH_TAG / $FH_COMMIT" "$FH_REPO" "$target"
        stage="$(/usr/bin/mktemp -d "$FH_CACHE/versions/.jobs-download.XXXXXX")" || return 1
        fh_log "临时下载目录：$stage；中断时保留供诊断。"
        fh_run env GIT_TERMINAL_PROMPT=0 "$FH_GIT" clone --no-checkout "$FH_REPO" "$stage/sdk" || return $?
        fh_run "$FH_GIT" -C "$stage/sdk" checkout --detach "$FH_COMMIT" || return $?
        [[ -x "$stage/sdk/bin/flutter" && ! -e "$target" && ! -L "$target" ]] || { fh_error 'SDK 不完整或缓存目标已被其它进程创建。'; return 1; }
        fh_data move "$stage/sdk" "$target" >/dev/null || return 1
        [[ ! -d "$stage/sdk" ]] || { fh_error '缓存未原子发布，保留下载目录。'; return 1; }
        /bin/rmdir "$stage" || return 1
    fi
    actual="$("$FH_GIT" -C "$target" rev-parse HEAD)" || return 1
    origin="$("$FH_GIT" -C "$target" remote get-url origin)" || return 1
    dirty="$("$FH_GIT" -C "$target" status --porcelain --untracked-files=no)" || return 1
    [[ "$actual" == "$FH_COMMIT" && "$origin" == "$FH_REPO" && -z "$dirty" && -x "$target/bin/flutter" && ! -L "$target/bin" && ! -L "$target/bin/flutter" ]] || { fh_error '缓存来源 / commit / 源码状态不符，保留并停止。'; return 1; }
    fh_run "$target/bin/flutter" --version || return $?
    help_text="$("$target/bin/flutter" build -h)" || return 1
    [[ "$help_text" == *hap* ]] || { fh_error 'SDK 未提供 build hap，未切换项目。'; return 1; }
    [[ ! -L "$target/.jobs-harmony-source.json" && ( ! -e "$target/.jobs-harmony-source.json" || -f "$target/.jobs-harmony-source.json" ) ]] || { fh_error 'SDK 来源记录不是普通文件，保留并停止。'; return 1; }
    fh_data manifest "$FH_TAG" "$FH_COMMIT" "$FH_REPO" > "$target/.jobs-harmony-source.json" || return 1
}
# 两个指纹分别检查退出码，不能让后一个成功掩盖前一个读取失败。
fh_binding_state() {
    local config='' metadata=''
    config="$(fh_data fingerprint "$FH_PROJECT/.fvmrc")" || return 1
    metadata="$(fh_data fingerprint "$FH_PROJECT/.fvm")" || return 1
    print -r -- "$config|$metadata"
}
# 保存绑定副本，原件在发布时单独搬到 displaced，便于原身份恢复。
fh_save() {
    local entry
    /bin/mkdir "$FH_RUN/before" "$FH_RUN/displaced" "$FH_RUN/work" "$FH_RUN/produced" || return 1
    for entry in .fvmrc .fvm; do
        if [[ -e "$FH_PROJECT/$entry" || -L "$FH_PROJECT/$entry" ]]; then
            /bin/cp -RpP "$FH_PROJECT/$entry" "$FH_RUN/before/$entry" || return 1
        fi
    done
}
# 将工作副本的所有SDK链接固定为绝对路径，避免移动后相对目标失效。
fh_absolute_links() {
    local root="$1" reference="$2" link relative destination
    for link in "$root/.fvm"/*(DN) "$root/.fvm/versions"/*(DN); do
        [[ -L "$link" ]] || continue
        relative="${link#$root/}"
        destination="$reference/$relative"
        destination="${destination:A}"
        /bin/ln -sfn "$destination" "$link" || return 1
    done
}
# FVM只接触影子工程，不允许它改写真实项目的IDE、ignore或其它配置。
fh_prepare_binding() {
    local original='-' target="$FH_CACHE/versions/$FH_VERSION" current='' linked=''
    fh_save || return 1
    [[ ! -f "$FH_RUN/before/.fvmrc" ]] || original="$FH_RUN/before/.fvmrc"
    /bin/cp "$FH_PROJECT/pubspec.yaml" "$FH_RUN/work/pubspec.yaml" || return 1
    if [[ -d "$FH_RUN/before/.fvm" ]]; then
        /bin/cp -RpP "$FH_RUN/before/.fvm" "$FH_RUN/work/.fvm" || return 1
        fh_absolute_links "$FH_RUN/work" "$FH_PROJECT" || return 1
    fi
    fh_data config "$original" "$FH_VERSION" "$FH_CACHE" "$FH_REPO" temporary > "$FH_RUN/work/.fvmrc" || return 1
    (
        cd -- "$FH_RUN/work" || exit 1
        export FVM_CACHE_PATH="$FH_CACHE" FVM_FLUTTER_URL="$FH_REPO" FVM_USE_GIT_CACHE=false
        fh_run "$FH_FVM" use "$FH_VERSION" --skip-setup --skip-pub-get
    ) || return $?
    [[ -L "$FH_RUN/work/.fvm/flutter_sdk" ]] || { fh_error 'FVM 未生成 SDK 链接。'; return 1; }
    linked="$FH_RUN/work/.fvm/flutter_sdk"
    [[ "${linked:A}" == "${target:A}" ]] || { fh_error 'FVM SDK 链接没有指向选定的隔离缓存。'; return 1; }
    current="$(fh_data current "$FH_RUN/work/.fvmrc")" || return 1
    [[ "$current" == "$FH_VERSION" ]] || { fh_error 'FVM 回读版本不匹配。'; return 1; }
    fh_absolute_links "$FH_RUN/work" "$FH_RUN/work" || return 1
    fh_data config "$original" "$FH_VERSION" "$FH_CACHE" "$FH_REPO" final > "$FH_RUN/work/.fvmrc" || return 1
}
# 替换前再次核对绑定指纹，使用不覆盖目标的移动保存原件与发布候选。
fh_publish_entry() {
    local entry="$1" expected='' current='' original=''
    if [[ "$entry" == .fvmrc ]]; then original="$FH_INITIAL_CONFIG"; else original="$FH_INITIAL_FVM"; fi
    current="$(fh_data fingerprint "$FH_PROJECT/$entry")" || return 1
    [[ "$current" == "$original" ]] || { fh_error "发布前发现并发修改，保留新状态：$entry"; return 1; }
    FH_CHANGED+=("$entry")
    if [[ "$entry" == .fvmrc ]]; then FH_EXPECTED_CONFIG='null'; else FH_EXPECTED_FVM='null'; fi
    if [[ -e "$FH_PROJECT/$entry" || -L "$FH_PROJECT/$entry" ]]; then
        fh_data move "$FH_PROJECT/$entry" "$FH_RUN/displaced/$entry" >/dev/null || return 1
    fi
    fh_data move "$FH_RUN/work/$entry" "$FH_PROJECT/$entry" >/dev/null || return 1
    expected="$(fh_data fingerprint "$FH_PROJECT/$entry")" || return 1
    if [[ "$entry" == .fvmrc ]]; then FH_EXPECTED_CONFIG="$expected"; else FH_EXPECTED_FVM="$expected"; fi
}
# 只在内容和文件身份仍等于本次写入时恢复，保留外部的新修改。
fh_restore_entry() {
    local entry="$1" current='' expected=''
    if [[ "$entry" == .fvmrc ]]; then expected="$FH_EXPECTED_CONFIG"; else expected="$FH_EXPECTED_FVM"; fi
    current="$(fh_data fingerprint "$FH_PROJECT/$entry")" || return 1
    [[ "$current" == "$expected" ]] || { fh_error "恢复发现并发修改，保留新状态与快照：$entry；$FH_RUN/before"; return 1; }
    if [[ -e "$FH_PROJECT/$entry" || -L "$FH_PROJECT/$entry" ]]; then
        fh_data move "$FH_PROJECT/$entry" "$FH_RUN/produced/$entry" >/dev/null || return 1
    fi
    if [[ -e "$FH_RUN/displaced/$entry" || -L "$FH_RUN/displaced/$entry" ]]; then
        fh_data move "$FH_RUN/displaced/$entry" "$FH_PROJECT/$entry" >/dev/null || return 1
    fi
}
# 发布后回读真实项目路径，成功前任何失败都交给受保护的恢复流程。
fh_bind() {
    local actual='' target="$FH_CACHE/versions/$FH_VERSION" linked=''
    fh_validate || return 1
    actual="$(fh_binding_state)" || return 1
    [[ "$actual" == "$FH_BASELINE" ]] || { fh_error '确认后项目绑定已被修改，保留外部状态，请重新运行。'; return 1; }
    fh_prepare_binding || return $?
    actual="$(fh_binding_state)" || return 1
    [[ "$actual" == "$FH_BASELINE" ]] || { fh_error '准备期间项目绑定已被修改，保留外部状态，请重新运行。'; return 1; }
    FH_MUTATED=1
    fh_publish_entry .fvmrc || return 1
    fh_publish_entry .fvm || return 1
    linked="$FH_PROJECT/.fvm/flutter_sdk"
    [[ -L "$linked" && "${linked:A}" == "${target:A}" ]] || { fh_error '发布后 SDK 链接核验失败。'; return 1; }
    FH_SUCCESS=1
    fh_log "✔ 项目已绑定 Flutter OH $FH_TAG / $FH_COMMIT"
    fh_log "SDK：$target"
    fh_log "备份与日志：$FH_RUN"
    fh_log '后续使用 fvm flutter / fvm dart；依赖解析、鸿蒙签名和真实构建需按项目单独执行。'
}
# 回收本任务锁；恢复冲突时保留外部文件和全部快照。
fh_finish() {
    local result="$1" entry failed=0
    trap - EXIT INT TERM HUP
    if [[ -n "$FH_REMOTE_PID" ]]; then
        kill -TERM "$FH_REMOTE_PID" 2>/dev/null
        wait "$FH_REMOTE_PID" 2>/dev/null
    fi
    if (( FH_MUTATED && ! FH_SUCCESS )); then
        fh_log '⚠ SDK 切换未完成，正在恢复本次操作前的项目绑定。'
        for entry in "${FH_CHANGED[@]}"; do
            fh_restore_entry "$entry" || failed=1
        done
        if (( failed )); then
            fh_log "✖ 自动恢复未完整完成，请按快照人工恢复：$FH_RUN/before" >&2
            result=1
        else
            fh_log "✔ 原项目绑定已恢复；失败产物与快照保留：$FH_RUN"
        fi
    fi
    [[ -z "$FH_CACHE_LOCK" ]] || /bin/rmdir "$FH_CACHE_LOCK" 2>/dev/null || result=1
    [[ -z "$FH_PROJECT_LOCK" ]] || /bin/rmdir "$FH_PROJECT_LOCK" 2>/dev/null || result=1
    exit "$result"
}
# 只解析入口参数与动态路径，不创建目录或运行工具。
fh_parse() {
    local supplied='' arg
    while (( $# )); do
        arg="$1"; shift
        case "$arg" in
            --project) (( $# )) || return 1; supplied="$1"; shift ;;
            --check) FH_CHECK=1 ;;
            --help|-h) FH_HELP=1; print -r -- '用法：ManageHarmonyFlutterVersion.zsh --project <Flutter项目目录> [--check]'; return 0 ;;
            *) fh_error "未知参数：$arg"; return 1 ;;
        esac
    done
    [[ -n "$supplied" && "$supplied" != *[[:cntrl:]]* ]] || { fh_error '缺少项目目录，或路径含控制字符。'; return 1; }
    [[ ! -L "${supplied%/}" ]] || { fh_error '项目目录不能是符号链接。'; return 1; }
    FH_PROJECT="${supplied:A}"
    FH_CACHE="$HOME/Library/Caches/JobsFlutter/fvm/harmony"
    FH_TOOLS="${${(%):-%x}:A:h}"
}
# 用户首屏授权后才创建日志。
fh_start() {
    FH_RUN="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/JobsHarmonyFlutter.XXXXXX")" || return 1
    FH_LOG="$FH_RUN/action.log"
    : > "$FH_LOG"
}
# 原子项目锁覆盖工具准备、缓存准备和最终发布全过程。
fh_lock_project() {
    /bin/mkdir "$FH_PROJECT/.jobs-harmony-fvm.lock" 2>/dev/null || { fh_error '此项目已有鸿蒙 SDK 操作锁，请待原操作结束后重试。'; return 1; }
    FH_PROJECT_LOCK="$FH_PROJECT/.jobs-harmony-fvm.lock"
}
# 初始化解释器选项与入口参数。
fh_initialize() {
    setopt NO_NOMATCH
    fh_parse "$@"
}
# 只读模式直接返回；安装模式依次查询、确认、隔离生成和发布。
fh_execute() {
    (( FH_HELP )) && return 0
    fh_validate || return 1
    if (( FH_CHECK )); then fh_check; return $?; fi
    fh_start || return 1 # 初始化本次日志与信号恢复。
    trap 'fh_finish $?' EXIT # 此编排函数结束时，业务已完成或明确失败。
    trap 'exit 130' INT TERM HUP
    fh_versions || return $? # 查询官方适配tag，失败才列本机缓存。
    fh_choose || return $? # 选择精确版本并最终YES确认。
    fh_lock_project || return 1 # 获取项目并发锁。
    fh_validate || return 1 # 安装前复检项目边界。
    fh_ensure_fvm || return $? # 确认后准备缺失FVM。
    fh_sdk || return $? # 准备并验证隔离SDK缓存。
    fh_bind # 影子项目生成绑定，再安全发布并回读。
}
# 主入口只负责高层编排。
main() {
    fh_initialize "$@" || return $? # 解析项目、帮助和只读模式。
    show_script_intro_and_wait || return $? # 先展示固定自述并取得首屏授权。
    fh_execute # 执行只读盘点或经最终确认的项目级安装 / 切换。
}

main "$@"
