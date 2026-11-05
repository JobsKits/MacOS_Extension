#!/bin/zsh
# 脚本自述：
# - 脚本名称：SetupFlutterProject.zsh。
# - 核心用途：fzf选择FVM/系统Flutter、jEnv/系统JDK，准备固定Gradle、拉取Pub依赖并预热构建插件。
# - 影响范围：确认后安装缺失工具、项目SDK配置、.jobs环境记录、Android本机配置及正常缓存；不设置全局SDK或代理。
# - 运行提示：先自述回车；Enter选择、←返回、Esc取消；已完成阶段不自动撤销，原配置快照留在临时目录。

# JOBS_SDK_RETRY_BEGIN
# 只处理本轮子树，避免超时或取消后残留下载进程占用 SDK 锁。
jobs_sdk_stop_tree() {
    local root="$1" child=""
    for child in $(/usr/bin/pgrep -P "$root" 2>/dev/null); do
        jobs_sdk_stop_tree "$child"
    done
    /bin/kill -TERM "$root" 2>/dev/null || true
    /bin/kill -KILL "$root" 2>/dev/null || true
}
# 状态写标准错误，机器可读的标准输出不混入重试提示。
jobs_sdk_retry_note() {
    print -u2 -r -- "$2"
    [[ -z "$1" ]] || print -r -- "$2" >> "$1"
}
# 本地确定错误应明确失败；下载超时、断流和未知获取失败则继续，无次数/总时长上限。
jobs_sdk_retry() {
    setopt LOCAL_OPTIONS LOCAL_TRAPS
    local title="$1" acquisition_log="$2" attempt=1 result=0 delay="${JOBS_SDK_RETRY_DELAY:-2}" maximum="${JOBS_SDK_RETRY_MAX_DELAY:-30}"
    local task_pid="" offset=0 failure="" interrupted=0 history="${2}.attempts.log"
    shift 2
    [[ "$delay" == <-> && "$maximum" == <-> && "$maximum" -gt 0 && "$delay" -le "$maximum" ]] || return 2
    trap 'interrupted=130; [[ -z "$task_pid" ]] || jobs_sdk_stop_tree "$task_pid"' INT
    trap 'interrupted=143; [[ -z "$task_pid" ]] || jobs_sdk_stop_tree "$task_pid"' TERM
    trap 'interrupted=129; [[ -z "$task_pid" ]] || jobs_sdk_stop_tree "$task_pid"' HUP
    while true; do
        jobs_sdk_retry_note "$acquisition_log" "▶ SDK 获取：$title；第 $attempt 次（失败自动重试，Ctrl+C 结束）"
        offset=0
        [[ ! -f "$acquisition_log" ]] || offset="$(/usr/bin/wc -c < "$acquisition_log")"
        [[ "${JOBS_SDK_LOG_REPLACED:-0}" != 1 ]] || offset=0
        # 显式继承 stdin；后台调用仍能进行工具自身的许可/认证交互。
        "$@" <&0 &
        task_pid=$!
        result=0
        wait "$task_pid" || result=$?
        task_pid=""
        (( interrupted == 0 )) || return "$interrupted"
        if [[ -f "$acquisition_log" ]]; then
            (( $(/usr/bin/wc -c < "$acquisition_log") >= offset )) || offset=0
            print -r -- "━━ $title：第 $attempt 次，退出码 $result ━━" >> "$history"
            /usr/bin/tail -c +$((offset + 1)) "$acquisition_log" >> "$history"
        fi
        failure=""
        if [[ -f "$acquisition_log" ]]; then
            failure="$(/usr/bin/tail -c +$((offset + 1)) "$acquisition_log" | /usr/bin/tail -c 65536)"
        fi
        # 部分获取器下载失败仍返回0，明确失败详情不能冒充SDK就绪。
        if (( result == 0 )) && print -r -- "$failure" | /usr/bin/grep -Eqi 'Failed to download|Error downloading|Unable to download|Could not download|Download failed'; then
            result=1
        fi
        (( result != 0 )) || return 0
        # 超时的调用方应返回124；外部中断状态不能被重试循环吞掉。
        case "$result" in 129|130|131|137|143) return "$result" ;; 126|127) return "$result" ;; esac
        failure=""
        if [[ -f "$acquisition_log" ]]; then
            # 兼容调用方每次重建机器输出文件：缩短后从文件开头读取。
            (( $(/usr/bin/wc -c < "$acquisition_log") >= offset )) || offset=0
            failure="$(/usr/bin/tail -c +$((offset + 1)) "$acquisition_log" | /usr/bin/tail -c 65536)"
        fi
        if print -r -- "$failure" | /usr/bin/grep -Eqi 'No available formula|No formulae found|Failed to find package|File exists|Permission denied|Operation not permitted|No space left on device|Read-only file system|Bad CPU type|Exec format error|unknown option|unrecognized option|invalid argument|version .* (does not exist|not found)|license[^[:cntrl:]]*(not accepted|rejected)|licenses?[^[:cntrl:]]*not accepted|HTTP[^[:cntrl:]]*(401|403|404)|returned error: (401|403|404)|Authentication failed|could not read Username'; then
            jobs_sdk_retry_note "$acquisition_log" "✖ $title 遇到权限、许可、版本或本地环境错误（$result），已停止；请按原始日志处理。"
            return "$result"
        fi
        jobs_sdk_retry_note "$acquisition_log" "⚠ $title 获取未完成（退出码 $result）；${delay} 秒后自动重试，保留已有缓存。"
        /bin/sleep "$delay" &
        task_pid=$!
        wait "$task_pid" || { (( interrupted == 0 )) || return "$interrupted"; return 130; }
        task_pid=""
        (( interrupted == 0 )) || return "$interrupted"
        (( attempt++ ))
        (( delay < maximum )) && delay=$(( delay * 2 ))
        (( delay <= maximum )) || delay="$maximum"
    done
}
# JOBS_SDK_RETRY_END

# JOBS_FLUTTER_ROUTE_BEGIN
# 每个宿主Shell保留一个私有任务缓存，网络变量仅在wrapper的子进程中修改。
jfs_route_cache_init() {
    if [[ -n "${JFS_ROUTE_CACHE_DIR:-${JOBS_FLUTTER_ROUTE_CACHE_DIR:-}}" ]]; then
        JFS_ROUTE_CACHE_DIR="${JFS_ROUTE_CACHE_DIR:-$JOBS_FLUTTER_ROUTE_CACHE_DIR}"
        [[ -d "$JFS_ROUTE_CACHE_DIR" && ! -L "$JFS_ROUTE_CACHE_DIR" && -f "$JFS_ROUTE_CACHE_DIR/.jobs-sdk-route" && "$(/usr/bin/stat -f %u "$JFS_ROUTE_CACHE_DIR")" == "$UID" && "$(/usr/bin/stat -f %Lp "$JFS_ROUTE_CACHE_DIR")" == 700 ]] && return 0
    fi
    JFS_ROUTE_CACHE_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp/}JobsFlutterSdkRoute.XXXXXX")" || return 1
    /bin/chmod 700 "$JFS_ROUTE_CACHE_DIR"
    print -r -- v1 > "$JFS_ROUTE_CACHE_DIR/.jobs-sdk-route"
}
# 审计不回显URL凭据或查询串，stdout始终留给SDK自身及机器输出。
jfs_route_note() {
    local output=""
    output="$(print -r -- "$2" | /usr/bin/perl -pe 's{([a-z][a-z0-9+.-]*://)[^\s/@]+@}{$1***@}ig; s{(https?://[^\s?#]+)[?#][^\s]*}{$1?[已省略]}ig; s{\e\[[0-9;?]*[ -/]*[@-~]}{}g')"
    print -u2 -r -- "$output"
    [[ -z "$1" ]] || print -r -- "$output" >> "$1"
}
# 只回收本轮创建的子树，避免中断后留下SDK下载者。
jfs_route_stop_tree() {
    local child=""
    # Freeze the owned parent first: killed download children cannot trigger a retry fork.
    /bin/kill -STOP "$1" 2>/dev/null || return 0
    for child in $(/usr/bin/pgrep -P "$1" 2>/dev/null); do jfs_route_stop_tree "$child"; done
    # Stopped processes cannot run TERM traps; kill this tree, then the caller reaps its child.
    /bin/kill -KILL "$1" 2>/dev/null || true
}
# 参数仅作为数据交给系统JXA解析，不执行SDK或项目代码。
jfs_route_data() {
    /usr/bin/osascript -l JavaScript - "$@" <<'JXA'
ObjC.import('Foundation');
function run(a) {
    function text(p) { var v=$.NSString.stringWithContentsOfFileEncodingError(p,$.NSUTF8StringEncoding,null), value=v ? ObjC.unwrap(v) : ''; return typeof value==='string' ? value : ''; }
    function json(p) { return JSON.parse(text(p)); }
    function clean(v) { v=String(v===undefined?'':v); if(/[\x00-\x1f\x7f]/.test(v)) throw Error('字段含控制字符'); return v; }
    function sha(v) { return /^[0-9a-f]{40}$/i.test(v||'') ? v.toLowerCase() : ''; }
    function version(v) { return /^v?\d+\.\d+\.\d+(?:[-+][\w.+-]+)?$/.test(v||'') ? v : ''; }
    if(a[0]==='json-valid') { json(a[1]); return 'valid'; }
    if(a[0]==='identity') {
        var root=a[1], wanted=a[2], engine=sha(a[4]) || (!a[4] ? sha(text(root+'/bin/internal/engine.version').trim()) : '');
        var m={}; try {m=json(root+'/bin/cache/flutter.version.json');} catch(_) {}
        var cached=engine && sha(m.engineRevision)===engine ? version(m.frameworkVersion) : '';
        var v=wanted || cached;
        return [clean(v),engine].join('\t');
    }
    if(a[0]==='sdk-base') {
        var update=text(a[1]+'/bin/internal/update_dart_sdk.sh'), line=update.match(/^.*DART_SDK_BASE_URL=.*FLUTTER_STORAGE_BASE_URL.*$/m), match=line && line[0].match(/FLUTTER_STORAGE_BASE_URL:-([^}\s"']+)/);
        return match && /^https:\/\//.test(match[1]) ? clean(match[1]).replace(/\/+$/,'') : '';
    }
    if(a[0]==='realm') {
        var realm=text(a[1]+'/bin/cache/engine.realm').replace(/\s/g,'');
        if(realm && (!/^[A-Za-z0-9_.\/-]+$/.test(realm) || realm.split('/').some(function(v){return v==='..'||v==='.';}))) throw Error('realm路径无效');
        return realm.replace(/^\/+|\/+$/g,'');
    }
    if(a[0]==='manifest') {
        var m=json(a[1]),wanted=a[2],arch=a[3],channel=/^(stable|beta|dev)$/.test(wanted)?wanted:'';
        if(!Array.isArray(m.releases)) throw Error('发布清单无releases');
        var rows=m.releases.filter(function(r) {
            if(channel && (!m.current_release || r.hash!==m.current_release[channel])) return false;
            if(!channel && wanted && r.version.replace(/^v/,'')!==wanted.replace(/^v/,'')) return false;
            if(!/^[0-9a-f]{64}$/i.test(r.sha256||'') || !/^([\w.-]+\/)*flutter_macos_[\w.+-]+\.zip$/.test(r.archive||'')) return false;
            return arch==='arm64' ? (r.dart_sdk_arch==='arm64'||/_arm64_/.test(r.archive)) : (r.dart_sdk_arch==='x64'||!/_arm64_/.test(r.archive));
        });
        if(!rows.length) throw Error('清单无匹配版本和架构');
        var r=rows[0]; return [r.version,'flutter_infra_release/releases/'+r.archive,r.sha256,sha(r.engine_revision||r.engineRevision)].map(clean).join('\t');
    }
    if(a[0]==='metadata-url') { var path=a[1].split('/'); return 'https://www.googleapis.com/storage/v1/b/'+encodeURIComponent(path.shift())+'/o/'+encodeURIComponent(path.join('/'))+'?fields=name,size,md5Hash'; }
    if(a[0]==='metadata') {
        var m=json(a[1]), object=a[2].split('/').slice(1).join('/');
        if(m.name!==object || !/^[0-9]+$/.test(String(m.size)) || !/^[A-Za-z0-9+/]{22}==$/.test(m.md5Hash||'')) throw Error('官方对象身份/摘要无效');
        var alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/',bits=0,count=0,hex='';
        m.md5Hash.replace(/=/g,'').split('').forEach(function(c){bits=(bits<<6)|alphabet.indexOf(c);count+=6;if(count>=8){count-=8;hex+=('0'+((bits>>count)&255).toString(16)).slice(-2);}});
        return [m.size,hex].join('\t');
    }
    if(a[0]==='probe') {
        var headers=text(a[1]), metrics=text(a[3]).trim().split('\t'), body=$.NSData.dataWithContentsOfFile(a[2]);
        if(!body) throw Error('无样本');
        var size=Number(body.length),code=Number(metrics[0]),total=Number(a[4]),md5=a[5],kind=a[6];
        var ranges=headers.match(/content-range:\s*bytes\s+0-(\d+)\/(\d+)/ig)||[],range=ranges.length?/0-(\d+)\/(\d+)/.exec(ranges[ranges.length-1]):null;
        if(kind==='source') { if(code!==206 && !(code===200&&size<=262144)) throw Error('来源正文状态无效'); }
        else if(code!==206 || !range || Number(range[2])<=0 || Number(range[1])>=Number(range[2]) || (total&&Number(range[2])!==total)) throw Error('非匹配206/对象总长');
        if(!size || size>262144 || (kind!=='source'&&size<Math.min(4096,total||4096))) throw Error('样本长度无效');
        if(kind!=='source' && range && Number(a[8])===0 && size!==Number(range[1])+1) throw Error('完整样本与Range长度不一致');
        var etags=headers.match(/etag:\s*(?:W\/)?"?([a-f0-9]{32})"?/ig)||[],etag=etags.length?/([a-f0-9]{32})/i.exec(etags[etags.length-1])[1].toLowerCase():'';
        if(md5 && etag!==md5) throw Error('ETag与官方对象MD5不一致');
        var preview=ObjC.unwrap($.NSString.alloc.initWithDataEncoding(body,$.NSISOLatin1StringEncoding))||'';
        if(kind==='source') { if(/^\s*(?:<!doctype\s+html|<html|\{\s*"error")/i.test(preview)) throw Error('错误页面'); if(a[7] && preview.indexOf(a[7])<0) throw Error('原始来源正文未匹配预期'); }
        else if(preview.slice(0,2)!=='PK') throw Error('非ZIP制品');
        return [Number(metrics[2])||size/Math.max(0.001,Number(metrics[3])),Number(metrics[1])||0,size].join('\t');
    }
    if(a[0]==='cache-read') {
        var c=json(a[1]); if(c.key!==a[2] || Number(a[3])-c.at>300 || Number(a[3])<c.at) throw Error('缓存失效');
        return ['base','proxyMode','proxy','object','sha','size','md5','version'].map(function(k){return k+'\t'+clean(c[k]);}).join('\n');
    }
    if(a[0]==='cache-write') {
        var c={key:a[2],at:Number(a[3]),base:a[4],proxyMode:a[5],proxy:a[6],object:a[7],sha:a[8],size:a[9],md5:a[10],version:a[11]};
        if(!$(JSON.stringify(c)).writeToFileAtomicallyEncodingError(a[1],true,$.NSUTF8StringEncoding,null)) throw Error('缓存写入失败');
        return 'saved';
    }
    throw Error('未知路由数据操作');
}
JXA
}
# 当前已设置代理（含空值）优先；候选只来自当前启用的系统代理配置。
jfs_route_candidates() {
    local name="" configured=0 settings="" kind="" enabled="" host="" port="" scheme=""
    JFS_PROXY_MODES=() JFS_PROXY_URLS=()
    for name in HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy; do
        (( ${+parameters[$name]} )) && configured=1
    done
    JFS_CURL_CONFIG=0
    if [[ -f "${JOBS_FLUTTER_ROUTE_CURL_CONFIG:-}" || -f "${CURL_HOME:-$HOME}/.curlrc" || -f "${XDG_CONFIG_HOME:-$HOME/.config}/curlrc" ]]; then JFS_CURL_CONFIG=1; configured=1; fi
    if [[ "$JFS_MODE" == git && -n "$JFS_SOURCE_URL" ]]; then
        /usr/bin/git config --get-urlmatch http.proxy "$JFS_SOURCE_URL" >/dev/null 2>&1 && configured=1
    fi
    if (( configured )); then JFS_PROXY_MODES=(env); JFS_PROXY_URLS=(''); return 0; fi
    JFS_PROXY_MODES=(direct) JFS_PROXY_URLS=('')
    settings="$(/usr/sbin/scutil --proxy 2>/dev/null)"
    for kind in HTTP HTTPS SOCKS; do
        enabled="$(print -r -- "$settings" | /usr/bin/awk -v k="${kind}Enable" '$1==k&&$2==":"{print $3;exit}')"
        host="$(print -r -- "$settings" | /usr/bin/awk -v k="${kind}Proxy" '$1==k&&$2==":"{print $3;exit}')"
        port="$(print -r -- "$settings" | /usr/bin/awk -v k="${kind}Port" '$1==k&&$2==":"{print $3;exit}')"
        [[ "$enabled" == 1 && "$port" == <-> && "$port" -gt 0 && "$port" -le 65535 && "$host" =~ '^[A-Za-z0-9_.:-]+$' ]] || continue
        scheme=http; [[ "$kind" != SOCKS ]] || scheme=socks5h
        [[ "$host" != *:* || "$host" == \[*\] ]] || host="[$host]"
        JFS_PROXY_MODES+=(proxy) JFS_PROXY_URLS+=("$scheme://$host:$port")
    done
}
# 只在探测或真实SDK子进程内调用；原本有显式代理时mode=env不改任何key。
jfs_route_apply_proxy() {
    [[ "$1" != env ]] || return 0
    local value="$2"
    export HTTP_PROXY="$value" HTTPS_PROXY="$value" ALL_PROXY="$value" http_proxy="$value" https_proxy="$value" all_proxy="$value"
}
# Curl受时间、Range和文件大小双重约束；不使用完整SDK测速。
jfs_route_curl() {
    local mode="$1" proxy="$2"; shift 2
    local -a options=()
    (( JFS_CURL_CONFIG )) || options=(--disable)
    [[ ! -f "${JOBS_FLUTTER_ROUTE_CURL_CONFIG:-}" ]] || options+=(--config "$JOBS_FLUTTER_ROUTE_CURL_CONFIG")
    [[ "$mode" == env ]] || options+=(--proxy "$proxy")
    /usr/bin/env LC_ALL=C "${JOBS_FLUTTER_ROUTE_CURL:-/usr/bin/curl}" "${options[@]}" --fail --location --max-redirs 4 --proto '=https' --proto-redir '=https' --connect-timeout 2 --max-time 6 "$@"
}
# 小型官方JSON通过原有网络候选获取，最终还需按具体对象身份解析。
jfs_route_fetch_json() {
    local url="$1" output="$2" index=0 task="" result=1
    local -a tasks=()
    for (( index=1; index<=${#JFS_PROXY_MODES}; index++ )); do
        ( jfs_route_curl "$JFS_PROXY_MODES[index]" "$JFS_PROXY_URLS[index]" --max-filesize 2097152 --output "$output.$index" "$url" >/dev/null 2> "$output.$index.error" ) &
        tasks+=($!)
    done
    for task in "${tasks[@]}"; do wait "$task" 2>/dev/null || true; done
    for (( index=1; index<=${#JFS_PROXY_MODES}; index++ )); do
        if [[ -s "$output.$index" ]] && jfs_route_data json-valid "$output.$index" >/dev/null 2>&1; then /bin/cp "$output.$index" "$output"; return 0; fi
    done
    return "$result"
}
# 从SDK实际元数据取得realm与默认源；显式用户源优先，fork自有默认源不替换。
jfs_route_bases() {
    JFS_BASES=('')
    [[ "$JFS_MODE" != git && "$JFS_MODE" != source ]] || return 0
    JFS_SDK_DEFAULT_BASE="$(jfs_route_data sdk-base "$JFS_SDK_ROOT" 2>/dev/null)"
    if (( ${+FLUTTER_STORAGE_BASE_URL} )); then
        JFS_BASES=("${FLUTTER_STORAGE_BASE_URL:-https://storage.googleapis.com}")
    elif [[ -n "$JFS_SDK_DEFAULT_BASE" && "$JFS_SDK_DEFAULT_BASE" != https://storage.googleapis.com && "$JFS_SDK_DEFAULT_BASE" != https://storage.flutter-io.cn ]]; then
        JFS_BASES=("$JFS_SDK_DEFAULT_BASE")
    else
        JFS_BASES=(https://storage.googleapis.com https://storage.flutter-io.cn)
    fi
}
# 只有真实官方origin或公开元数据证明，才把未显式授权的对象发给公共镜像。
jfs_route_sdk_is_official() {
    local sdk="$1" origin=""
    [[ -d "$sdk/.git" || -f "$sdk/.git" ]] || return 1
    origin="$(jfs_fvm_timed /usr/bin/env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_COMMON_DIR GIT_NO_LAZY_FETCH=1 GIT_TERMINAL_PROMPT=0 /usr/bin/git --no-optional-locks -c core.fsmonitor=false -C "$sdk" config --get remote.origin.url 2>/dev/null)" || return 1
    case "${origin%/}" in https://github.com/flutter/flutter|https://github.com/flutter/flutter.git|git@github.com:flutter/flutter.git|ssh://git@github.com/flutter/flutter.git) return 0 ;; esac
    return 1
}
jfs_route_protect_private_namespace() {
    if (( ${#JFS_BASES}>1 )) && [[ -n "$JFS_REALM" || "${JFS_PUBLIC_EVIDENCE:-0}" != 1 ]]; then
        JFS_BASES=("${JFS_SDK_DEFAULT_BASE:-https://storage.googleapis.com}")
        JFS_TRUST_NOTE+=' 对象未能证明属于公开标准命名空间，仅检查原SDK源与既有网络路线，不发送到新增镜像。'
    fi
}

# 无制品身份时只检测实际Git来源；没有可解析来源便保留原命令，不猜公共stable。
jfs_route_unresolved_identity() {
    local origin="${JFS_SOURCE_URL:-}"
    if [[ -d "$JFS_SDK_ROOT/.git" || -f "$JFS_SDK_ROOT/.git" ]]; then
        origin="$(jfs_fvm_timed /usr/bin/env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_COMMON_DIR GIT_NO_LAZY_FETCH=1 GIT_TERMINAL_PROMPT=0 /usr/bin/git --no-optional-locks -c core.fsmonitor=false -C "$JFS_SDK_ROOT" remote get-url origin 2>/dev/null)" || origin="${JFS_SOURCE_URL:-}"
    fi
    if [[ -n "$origin" && "$origin" != *$'\n'* ]]; then
        JFS_SOURCE_URL="$origin" JFS_MODE=git JFS_BASES=('') JFS_TRUST_NOTE='制品身份尚未解析，仅预检实际Git来源；保留SDK来源与原命令，不猜公共stable或声明二进制已验证。'
    else
        JFS_IDENTITY_UNRESOLVED=1 JFS_WARM=1
    fi
    return 0
}

# 根据具体版本/架构或SDK engine确定对象，官方不可达时允许已获准可信来源继续验证。
jfs_route_target() {
    local identity="" arm="" manifest="" details="" metadata_url="" base="" manifest_source=""
    arm="$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null)"; JFS_ARCH=x64; [[ "$arm" != 1 ]] || JFS_ARCH=arm64
    identity="$(jfs_route_data identity "$JFS_SDK_ROOT" "$JFS_VERSION" "$JFS_ARCH" "${FLUTTER_PREBUILT_ENGINE_VERSION:-}")" || return 1
    JFS_VERSION="${identity%%$'\t'*}" JFS_ENGINE="${identity#*$'\t'}" JFS_WARM=0 JFS_IDENTITY_UNRESOLVED=0
    JFS_REALM="$(jfs_route_data realm "$JFS_SDK_ROOT" "${FLUTTER_REALM:-}" 2>/dev/null)" || return 2
    if [[ "$JFS_MODE" == dart && -n "$JFS_ENGINE" && -x "$JFS_SDK_ROOT/bin/cache/dart-sdk/bin/dart" && -f "$JFS_SDK_ROOT/bin/cache/engine-dart-sdk.stamp" && "$(<"$JFS_SDK_ROOT/bin/cache/engine-dart-sdk.stamp")" == "$JFS_ENGINE" ]]; then JFS_WARM=1; return 0; fi
    if [[ "$JFS_MODE" == git || "$JFS_MODE" == source ]]; then [[ -n "$JFS_SOURCE_URL" ]] || return 2; return 0; fi
    JFS_OBJECT="" JFS_SHA="" JFS_SIZE="" JFS_MD5="" JFS_TRUST_NOTE="" JFS_PUBLIC_EVIDENCE=0
    local private_target=0
    if (( ${#JFS_BASES}==1 )) && [[ "$JFS_BASES[1]" != https://storage.googleapis.com && "$JFS_BASES[1]" != https://storage.flutter-io.cn ]]; then private_target=1; fi
    [[ -z "$JFS_REALM" && -z "${FLUTTER_PREBUILT_ENGINE_VERSION:-}" ]] || private_target=1
    if [[ "$JFS_MODE" == archive && ( -d "$JFS_SDK_ROOT/.git" || -f "$JFS_SDK_ROOT/.git" ) ]] && ! jfs_route_sdk_is_official "$JFS_SDK_ROOT"; then private_target=1; fi
    if [[ "$JFS_MODE" == archive && -n "$JFS_SOURCE_URL" ]]; then
        case "${JFS_SOURCE_URL%/}" in https://github.com/flutter/flutter|https://github.com/flutter/flutter.git) ;; *) private_target=1 ;; esac
    fi
    if [[ "$JFS_MODE" == archive && "$private_target" == 1 ]]; then
        if [[ -n "$JFS_ENGINE" ]]; then JFS_MODE=platform
        else jfs_route_unresolved_identity; return $?; fi
    elif [[ ( "$JFS_MODE" != archive && -z "$JFS_ENGINE" ) || ( "$JFS_MODE" == archive && -z "$JFS_REQUESTED_VERSION" ) ]]; then
        jfs_route_unresolved_identity; return $?
    fi
    if [[ -n "$JFS_ENGINE" && "$JFS_MODE" != archive ]]; then
        if [[ -z "$JFS_REALM" && -z "${FLUTTER_PREBUILT_ENGINE_VERSION:-}" ]] && jfs_route_sdk_is_official "$JFS_SDK_ROOT"; then JFS_PUBLIC_EVIDENCE=1; fi
        JFS_OBJECT="flutter_infra_release/flutter/$JFS_ENGINE/dart-sdk-darwin-$JFS_ARCH.zip"
        [[ -z "$JFS_REALM" ]] || JFS_OBJECT="$JFS_REALM/$JFS_OBJECT"
    else
        manifest="$JFS_PROBE_DIR/releases.json"
        if jfs_route_fetch_json 'https://www.googleapis.com/storage/v1/b/flutter_infra_release/o/releases%2Freleases_macos.json?alt=media' "$manifest" &&
           details="$(jfs_route_data manifest "$manifest" "${JFS_VERSION:-stable}" "$JFS_ARCH" 2>/dev/null)"; then
            manifest_source='Google官方发布清单'
        else
            details=""
            for base in "${JFS_BASES[@]}"; do
                if jfs_route_fetch_json "${base%/}/flutter_infra_release/releases/releases_macos.json" "$manifest" &&
                   details="$(jfs_route_data manifest "$manifest" "${JFS_VERSION:-stable}" "$JFS_ARCH" 2>/dev/null)"; then
                    manifest_source="$base 发布清单"; break
                fi
            done
        fi
        [[ -n "$details" ]] || return 1
        IFS=$'\t' read -r JFS_VERSION JFS_OBJECT JFS_SHA JFS_ENGINE <<< "$details"
        JFS_TRUST_NOTE="发布SHA来源：$manifest_source；具体版本/宿主架构已匹配。"
        case "$manifest_source" in Google*|https://storage.googleapis.com*|https://storage.flutter-io.cn*) JFS_PUBLIC_EVIDENCE=1 ;; esac
    fi
    # 自定义显式源或fork源不向Google泄露其私有engine，也不宣称官方等价。
    if (( ${#JFS_BASES}==1 )) && [[ "$JFS_BASES[1]" != https://storage.googleapis.com && ( "$JFS_BASES[1]" != https://storage.flutter-io.cn || -n "$JFS_REALM" || -n "${FLUTTER_PREBUILT_ENGINE_VERSION:-}" ) ]]; then
        JFS_TRUST_NOTE+=" 自定义来源保持原URL，仅验证精确engine/版本/架构路径及Range/传输一致性，不声明与官方等价。"
        return 0
    fi
    metadata_url="$(jfs_route_data metadata-url "$JFS_OBJECT")" || return 1
    if jfs_route_fetch_json "$metadata_url" "$JFS_PROBE_DIR/object.json" &&
       details="$(jfs_route_data metadata "$JFS_PROBE_DIR/object.json" "$JFS_OBJECT" 2>/dev/null)"; then
        IFS=$'\t' read -r JFS_SIZE JFS_MD5 <<< "$details"
        JFS_TRUST_NOTE+=' 官方对象总长/MD5与候选ETag核验。'
        [[ -n "$JFS_REALM" ]] || JFS_PUBLIC_EVIDENCE=1
    else
        JFS_TRUST_NOTE+=' 官方摘要不可达，使用已获准可信来源的精确路径、Range总长/ETag及正文样本一致性；不冒称官方摘要核验。'
    fi
    jfs_route_protect_private_namespace
}

# 各候选并发探测；--max-filesize和子进程文件限额防止服务器忽略Range时下载整个SDK。
jfs_route_probe() (
    local id="$1" base="$2" mode="$3" proxy="$4" url="" result=0 ref="${JOBS_FLUTTER_ROUTE_GIT_REF:-}" started=0 elapsed=0 pid=""
    local prefix="$JFS_PROBE_DIR/probe.$id"
    ulimit -f 512
    if [[ "$JFS_MODE" == git ]]; then
        jfs_route_apply_proxy "$mode" "$proxy"
        [[ -n "$ref" ]] || { ref="refs/tags/$JFS_VERSION"; case "$JFS_VERSION" in stable|beta|main|master|dev) ref="refs/heads/$JFS_VERSION" ;; '') ref=HEAD ;; esac; }
        zmodload zsh/datetime
        started="$EPOCHREALTIME"
        /usr/bin/env GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0 GIT_NO_LAZY_FETCH=1 "${JOBS_FLUTTER_ROUTE_GIT:-/usr/bin/git}" -c protocol.version=2 ls-remote --exit-code "$JFS_SOURCE_URL" "$ref" > "$prefix.body" 2> "$prefix.error" &
        pid=$!
        while /bin/kill -0 "$pid" 2>/dev/null; do
            if (( EPOCHREALTIME-started>=6 )); then jfs_route_stop_tree "$pid"; wait "$pid" 2>/dev/null; return 124; fi
            /bin/sleep 0.1
        done
        wait "$pid" || return $?
        /usr/bin/awk -v ref="$ref" '$2==ref && $1 ~ /^[0-9a-f]+$/ && length($1)==40 {found=1} END {exit !found}' "$prefix.body" || return 1
        elapsed=$(( EPOCHREALTIME-started ))
        printf '1\t%.4f\t%s\n' "$elapsed" "$(/usr/bin/wc -c < "$prefix.body")" > "$prefix.valid"
        return 0
    fi
    url="$JFS_SOURCE_URL"
    [[ "$JFS_MODE" == source ]] || url="${base%/}/$JFS_OBJECT"
    jfs_route_curl "$mode" "$proxy" --range 0-262143 --max-filesize 262144 --header 'Accept-Encoding: identity' --dump-header "$prefix.headers" --output "$prefix.body" --write-out '%{http_code}\t%{time_starttransfer}\t%{speed_download}\t%{time_total}' "$url" > "$prefix.metrics" 2> "$prefix.error" || result=$?
    # 只要获得足够且身份正确的206样本，低速导致的当次超时仍可参与真实指标比较。
    (( result==0 || result==28 )) || return "$result"
    jfs_route_data probe "$prefix.headers" "$prefix.body" "$prefix.metrics" "$JFS_SIZE" "$JFS_MD5" "$JFS_MODE" "${JOBS_FLUTTER_ROUTE_EXPECTED_TEXT:-}" "$result" > "$prefix.valid" 2> "$prefix.invalid" || return 1
)
# 缓存只接受本次输入指纹；源码/版本/架构/显式空值变化都重新探测。
jfs_route_key() {
    setopt LOCAL_OPTIONS
    unsetopt NOUNSET
    local name="" cache_engine="$JFS_ENGINE"
    [[ "$JFS_MODE" != archive ]] || cache_engine=""
    { print -r -- "private-identity-v2|$JFS_SDK_ROOT|$JFS_REQUESTED_VERSION|$JFS_ARCH|$cache_engine|${JFS_MODE/(dart|platform)/artifact}|$JFS_REALM|$JFS_SDK_DEFAULT_BASE|$JFS_SOURCE_URL|${JOBS_FLUTTER_ROUTE_GIT_REF:-}|${JOBS_FLUTTER_ROUTE_EXPECTED_TEXT:-}"
      [[ ! -f "${JOBS_FLUTTER_ROUTE_CURL_CONFIG:-}" ]] || /usr/bin/shasum -a 256 "$JOBS_FLUTTER_ROUTE_CURL_CONFIG"
      for name in FLUTTER_STORAGE_BASE_URL PUB_HOSTED_URL FLUTTER_REALM HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy NO_PROXY no_proxy; do print -r -- "$name:${+parameters[$name]}:${(P)name}"; done
    } | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}
# 失败的AUTO路线短时冷却，避免小样本始终最快却实际下载永远失败。
jfs_route_fingerprint() {
    print -rn -- "$1|$2|$3" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}
jfs_route_is_cooling() {
    local route="$1" now="$2" failed_at=""
    [[ -f "$JFS_ROUTE_FAILED_FILE" ]] || return 1
    failed_at="$(/usr/bin/awk -v key="$route" '$2==key{stamp=$1} END{print stamp}' "$JFS_ROUTE_FAILED_FILE")"
    [[ "$failed_at" == <-> ]] && (( now-failed_at<60 && now>=failed_at ))
}
# 读取受控缓存字段，不eval任何下载结果。
jfs_route_apply_cache() {
    local data="$1" key="" value="" base="" mode="" proxy=""
    while IFS=$'\t' read -r key value; do
        case "$key" in base) base="$value" ;; proxyMode) mode="$value" ;; proxy) proxy="$value" ;; object) export JOBS_FLUTTER_ROUTE_OBJECT_PATH="$value" ;; sha) export JOBS_FLUTTER_ROUTE_EXPECTED_SHA256="$value" ;; version) export JOBS_FLUTTER_ROUTE_RESOLVED_VERSION="$value" ;; esac
    done <<< "$data"
    if [[ "$JFS_MODE" != git && "$JFS_MODE" != source && ${+FLUTTER_STORAGE_BASE_URL} == 0 ]]; then export FLUTTER_STORAGE_BASE_URL="$base"; fi
    jfs_route_apply_proxy "$mode" "$proxy"
    JFS_ROUTE_SELECTED_ROUTE="$(jfs_route_fingerprint "$base" "$mode" "$proxy")"
}
# 低层接口只供已经隔离作用域的调用者；普通入口使用下面的子进程wrapper。
jobs_flutter_route_prepare() {
    setopt LOCAL_OPTIONS
    unsetopt NOUNSET
    local sdk="$1" version="$2" log_file="$3" mode="${4:-${JOBS_FLUTTER_ROUTE_MODE:-dart}}" attempt=1 delay=2 now=0 key="" cache="" data="" base="" id=0 index=0 task="" best="" speed=0 ttfb=0 bytes=0 best_speed=-1 best_ttfb=999 result=0
    local -a bases=() tasks=() ids=() candidate_bases=() candidate_modes=() candidate_proxies=()
    JFS_SDK_ROOT="$sdk" JFS_REQUESTED_VERSION="$version" JFS_VERSION="$version" JFS_MODE="$mode" JFS_SOURCE_URL="${JOBS_FLUTTER_ROUTE_SOURCE_URL:-}" JFS_ENGINE="" JFS_ARCH="" JFS_OBJECT="" JFS_SHA="" JFS_SIZE="" JFS_MD5=""
    case "$mode" in dart|platform|archive|git|source) ;; *) return 2 ;; esac
    if [[ "$mode" == git || "$mode" == source ]]; then [[ -n "$JFS_SOURCE_URL" && "$JFS_SOURCE_URL" != *$'\n'* ]] || return 2; fi
    jfs_route_cache_init || return 1
    export JOBS_FLUTTER_ROUTE_CACHE_DIR="$JFS_ROUTE_CACHE_DIR"
    while true; do
        JFS_PROBE_DIR="$(/usr/bin/mktemp -d "$JFS_ROUTE_CACHE_DIR/probe.XXXXXX")" || return 1
        jfs_route_candidates
        jfs_route_bases
        JFS_REALM="$(jfs_route_data realm "$JFS_SDK_ROOT" "${FLUTTER_REALM:-}" 2>/dev/null)" || return 2
        JFS_ARCH=x64; [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null)" != 1 ]] || JFS_ARCH=arm64
        local local_identity=""
        local_identity="$(jfs_route_data identity "$JFS_SDK_ROOT" "$JFS_REQUESTED_VERSION" "$JFS_ARCH" "${FLUTTER_PREBUILT_ENGINE_VERSION:-}")" || return 2
        JFS_ENGINE="${local_identity#*$'\t'}"
        key="$(jfs_route_key)"; cache="$JFS_ROUTE_CACHE_DIR/$key.json"; JFS_ROUTE_SELECTED_CACHE="$cache"; JFS_ROUTE_FAILED_FILE="$JFS_ROUTE_CACHE_DIR/$key.failed"; JFS_ROUTE_LOG="$log_file"; now="$(/bin/date +%s)"
        local source_count=${#JFS_BASES}
        JFS_ROUTE_ROTATION_ALLOWED=0
        (( source_count*${#JFS_PROXY_MODES}>1 )) && JFS_ROUTE_ROTATION_ALLOWED=1
        if data="$(jfs_route_data cache-read "$cache" "$key" "$now" 2>/dev/null)"; then
            jfs_route_note "$log_file" "✓ 复用本任务300秒内同版本/架构/配置的SDK路线；无需重复联网测速。"
            jfs_route_apply_cache "$data"; return 0
        fi
        if [[ "$mode" != dart || -z "$JFS_ENGINE" || ! -x "$JFS_SDK_ROOT/bin/cache/dart-sdk/bin/dart" || ! -f "$JFS_SDK_ROOT/bin/cache/engine-dart-sdk.stamp" || "$(<"$JFS_SDK_ROOT/bin/cache/engine-dart-sdk.stamp")" != "$JFS_ENGINE" ]]; then
            jfs_route_note "$log_file" "▶ SDK网络准备第${attempt}轮：仅本轮进程使用原有源/代理候选，显式值及空值保留；系统/Git/Shell配置不变，退出目标进程即撤回。"
        fi
        if jfs_route_target; then
            if (( JFS_WARM )); then
                if [[ "${JFS_IDENTITY_UNRESOLVED:-0}" == 1 ]]; then
                    jfs_route_note "$log_file" 'ℹ SDK制品身份及原Git来源尚未解析；保留显式源、代理和原命令继续，不猜公共stable，不宣称二进制已通过网络验证。'
                else
                    jfs_route_note "$log_file" '✓ 本地SDK的目标Engine/Dart缓存已就绪，复用健康环境；无下载网络探测。'
                fi
                return 0
            fi
            # 目标重分类后不能把Git路线缓存当archive源读取并导出空storage。
            if [[ "$JFS_MODE" != "$mode" ]]; then
                key="$(jfs_route_key)"; cache="$JFS_ROUTE_CACHE_DIR/$key.json"; JFS_ROUTE_SELECTED_CACHE="$cache"; JFS_ROUTE_FAILED_FILE="$JFS_ROUTE_CACHE_DIR/$key.failed"
            fi
            bases=("${JFS_BASES[@]}")
            JFS_ROUTE_ROTATION_ALLOWED=0
            (( ${#bases}*${#JFS_PROXY_MODES}>1 )) && JFS_ROUTE_ROTATION_ALLOWED=1
            [[ -z "${JFS_TRUST_NOTE:-}" ]] || jfs_route_note "$log_file" "ℹ $JFS_TRUST_NOTE"
            jfs_route_note "$log_file" "▶ SDK网络检测：${JFS_VERSION:-未解析} / Darwin $JFS_ARCH；Engine：${JFS_ENGINE:-不适用}；原始源：${JFS_SOURCE_URL:-${(j:, :)bases}}；每候选连接2秒/总计6秒，小样本≤256KiB。"
            tasks=() ids=() candidate_bases=() candidate_modes=() candidate_proxies=(); id=0
            for base in "${bases[@]}"; do
                for (( index=1; index<=${#JFS_PROXY_MODES}; index++ )); do
                    (( id++ )); ids+=("$id"); candidate_bases+=("$base"); candidate_modes+=("$JFS_PROXY_MODES[index]"); candidate_proxies+=("$JFS_PROXY_URLS[index]")
                    jfs_route_probe "$id" "$base" "$JFS_PROXY_MODES[index]" "$JFS_PROXY_URLS[index]" & tasks+=($!)
                done
            done
            for task in "${tasks[@]}"; do wait "$task" 2>/dev/null || true; done
            best=""; best_speed=-1; best_ttfb=999
            local reference_prefix="" sample_prefix=""
            for id in "${ids[@]}"; do
                if [[ -s "$JFS_PROBE_DIR/probe.$id.valid" ]]; then
                    sample_prefix="$(/bin/dd if="$JFS_PROBE_DIR/probe.$id.body" bs=4096 count=1 2>/dev/null | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
                    if [[ -n "$reference_prefix" && "$sample_prefix" != "$reference_prefix" ]]; then
                        jfs_route_note "$log_file" "⚠ 候选$id与同一目标的其它有效样本前缀/引用不一致，拒绝。"
                        continue
                    fi
                    reference_prefix="$sample_prefix"
                    local route_id="$(jfs_route_fingerprint "$candidate_bases[id]" "$candidate_modes[id]" "$candidate_proxies[id]")"
                    if (( JFS_ROUTE_ROTATION_ALLOWED )) && jfs_route_is_cooling "$route_id" "$now"; then
                        jfs_route_note "$log_file" "➤ 候选$id小样本有效，但其真实获取刚失败，AUTO冷却60秒；优先尝试其它已验证路线。"
                        continue
                    fi
                    IFS=$'\t' read -r speed ttfb bytes < "$JFS_PROBE_DIR/probe.$id.valid"
                    if [[ "$mode" == git ]]; then speed=$(( 1.0/(ttfb+0.001) )); fi
                    if [[ "$mode" == git ]]; then
                        jfs_route_note "$log_file" "✓ 候选$id：$JFS_SOURCE_URL；网络：${candidate_modes[id]} ${candidate_proxies[id]}；Git目标ref查询=${ttfb}s；引用元数据=${bytes}B。"
                    else
                        jfs_route_note "$log_file" "✓ 候选$id：${candidate_bases[id]:-$JFS_SOURCE_URL}；网络：${candidate_modes[id]} ${candidate_proxies[id]}；首字节=${ttfb}s；样本=${bytes}B；吞吐=${speed}B/s。"
                    fi
                    if (( speed>best_speed || (speed==best_speed && ttfb<best_ttfb) )); then best="$id"; best_speed="$speed"; best_ttfb="$ttfb"; fi
                else
                    jfs_route_note "$log_file" "⚠ 候选$id未通过真实响应/目标对象校验：${candidate_bases[id]:-$JFS_SOURCE_URL}；网络：${candidate_modes[id]} ${candidate_proxies[id]}。"
                fi
            done
            if [[ -n "$best" ]]; then
                jfs_route_data cache-write "$cache" "$key" "$now" "$candidate_bases[best]" "$candidate_modes[best]" "$candidate_proxies[best]" "$JFS_OBJECT" "$JFS_SHA" "$JFS_SIZE" "$JFS_MD5" "$JFS_VERSION" >/dev/null || return 1
                data="$(jfs_route_data cache-read "$cache" "$key" "$now")" || return 1
                jfs_route_note "$log_file" "➤ 选用候选$best：身份校验通过，实测指标最高；仅本轮SDK进程及子进程生效，退出后按原入口启动即撤回。"
                jfs_route_apply_cache "$data"; return 0
            fi
        fi
        if [[ "${JOBS_FLUTTER_ROUTE_PREPARE_ONCE:-0}" == 1 ]]; then jfs_route_note "$log_file" "⚠ SDK网络不可达，本轮有界检测已结束；返回上层原有网络重试/双栈回退。"; return 75; fi
        jfs_route_note "$log_file" "⚠ SDK网络第${attempt}轮没有可验证可用路线；${delay}秒后自动重新检测，Ctrl+C结束；尚未进入SDK/业务。"
        /bin/sleep "$delay" || return 130
        (( attempt++ )); (( delay>=30 )) || delay=$((delay*2)); (( delay<=30 )) || delay=30
    done
}
# 下载失败只删除本模块自己的路线缓存，不清理SDK或用户下载片段。
jobs_flutter_route_invalidate() {
    if [[ "${JFS_ROUTE_ROTATION_ALLOWED:-0}" == 1 && -n "${JFS_ROUTE_SELECTED_ROUTE:-}" && "$JFS_ROUTE_FAILED_FILE" == "$JFS_ROUTE_CACHE_DIR/"*.failed ]]; then
        print -r -- "$(/bin/date +%s) $JFS_ROUTE_SELECTED_ROUTE" >> "$JFS_ROUTE_FAILED_FILE"
        /bin/chmod 600 "$JFS_ROUTE_FAILED_FILE"
        jfs_route_note "${JFS_ROUTE_LOG:-}" '➤ 本次实际获取失败，AUTO候选已短时冷却，下一轮优先其它已验证路线；显式配置不变。'
    fi
    [[ -z "${JFS_ROUTE_SELECTED_CACHE:-}" || "$JFS_ROUTE_SELECTED_CACHE" != "$JFS_ROUTE_CACHE_DIR/"*.json ]] || /bin/rm -f -- "$JFS_ROUTE_SELECTED_CACHE"
}
# 普通入口：独立子进程内选择路线和运行SDK，完整保留命令参数、stdin及stdout。
jobs_flutter_sdk_retry() {
    setopt LOCAL_OPTIONS LOCAL_TRAPS
    unsetopt NOUNSET
    local title="$1" log_file="$2" sdk="$3" version="$4" child="" result=0 cancelled=0 token=""; shift 4
    jfs_route_cache_init || return 1
    if [[ -z "$sdk" ]]; then
        for token in "$@"; do [[ "$token" == */bin/flutter ]] && sdk="${token:A:h:h}" && break; done
        [[ -n "$sdk" || ! -d "$PWD/.fvm/flutter_sdk" ]] || sdk="${PWD}/.fvm/flutter_sdk"
        [[ -n "$sdk" || -z "${commands[flutter]:-}" ]] || sdk="${commands[flutter]:A:h:h}"
    fi
    trap 'cancelled=130; [[ -z "$child" ]] || jfs_route_stop_tree "$child"' INT
    trap 'cancelled=143; [[ -z "$child" ]] || jfs_route_stop_tree "$child"' TERM
    trap 'cancelled=129; [[ -z "$child" ]] || jfs_route_stop_tree "$child"' HUP
    (
        local attempt=1 delay=2 code=0 name="" offset=0 detail="" route_mode=""
        local -A original_values original_set
        for name in FLUTTER_STORAGE_BASE_URL HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy NO_PROXY no_proxy; do original_set[$name]="${+parameters[$name]}"; original_values[$name]="${(P)name}"; done
        while true; do
            for name in ${(k)original_set}; do if [[ "$original_set[$name]" == 1 ]]; then export "$name=$original_values[$name]"; else unset "$name"; fi; done
            route_mode="${JOBS_FLUTTER_ROUTE_MODE:-dart}"
            if [[ "${JOBS_FLUTTER_ROUTE_LEGACY_FVM_AUTO:-0}" == 1 && -s "$sdk/bin/internal/engine.version" ]]; then
                route_mode=platform
                jfs_route_note "$log_file" 'ℹ 旧FVM源码已落地，按其当前engine代表制品检测；后续Git仍保持原源，不把当前engine冒称新版本。'
            fi
            jobs_flutter_route_prepare "$sdk" "$version" "$log_file" "$route_mode" || exit $?
            jfs_route_note "$log_file" "▶ $title；SDK获取第${attempt}次，失败自动重新测路并重试。"
            offset=0; [[ ! -f "$log_file" ]] || offset="$(/usr/bin/wc -c < "$log_file")"
            [[ "${JOBS_SDK_LOG_REPLACED:-0}" != 1 ]] || offset=0
            code=0
            if [[ "${JOBS_FLUTTER_ROUTE_CAPTURE_OUTPUT:-0}" == 1 ]]; then
                "$@" > >(/usr/bin/tee -a "$log_file") 2> >(/usr/bin/tee -a "$log_file" >&2) || code=$?
            else
                "$@" || code=$?
            fi
            if [[ "${JOBS_FLUTTER_ROUTE_ONCE:-0}" == 1 ]]; then exit "$code"; fi
            detail=""; [[ ! -f "$log_file" ]] || detail="$(/usr/bin/tail -c +$((offset+1)) "$log_file" | /usr/bin/tail -c 65536)"
            if (( code==0 )) && print -r -- "$detail" | /usr/bin/grep -Eqi 'Failed to download|Error downloading|Unable to download|Could not download|Download failed'; then code=1; fi
            (( code!=0 )) || exit 0
            case "$code" in 126|127|129|130|131|137|143) exit "$code" ;; esac
            if print -r -- "$detail" | /usr/bin/grep -Eqi 'Permission denied|Operation not permitted|No space left|Bad CPU type|No available formula|No formulae found|Failed to find package|unknown option|invalid argument|bad substitution|syntax error|read-only variable|Exec format error|license.*(not accepted|rejected)'; then exit "$code"; fi
            jobs_flutter_route_invalidate
            jfs_route_note "$log_file" "⚠ SDK获取未完成（$code），已使本轮路线缓存失效；${delay}秒后重测并重试。"
            /bin/sleep "$delay" || exit 130
            (( attempt++ )); (( delay>=30 )) || delay=$((delay*2)); (( delay<=30 )) || delay=30
        done
    ) <&0 &
    child=$!
    wait "$child" || result=$?
    (( cancelled==0 )) || return "$cancelled"
    return "$result"
}
# 业务只执行一次；调用方先单独使用--version准备SDK，不因业务失败重复构建/运行。
jobs_flutter_sdk_once() {
    JOBS_FLUTTER_ROUTE_ONCE=1 jobs_flutter_sdk_retry "$@"
}
# 仅静态确认文本FVM入口依赖PATH Dart时，准备其真正的Flutter Dart宿主。
# stdout保持空，避免污染 FVM_BIN=$(finder) 等机器输出。
jobs_flutter_fvm_runtime() {
    setopt LOCAL_OPTIONS
    unsetopt NOUNSET
    local title="$1" log_file="$2" manager="$3" kind="" body="" dart_bin="" sdk="" expected=""
    [[ -r "$manager" && -f "$manager" ]] || return 0
    manager="${manager:A}"
    kind="$(/usr/bin/file -b "$manager" 2>/dev/null)" || return 0
    case "$kind" in *Mach-O*|*ELF*) return 0 ;; *text*|*script*) ;; *) return 0 ;; esac
    body="$(/usr/bin/head -c 65536 "$manager")"
    # A local dart function/alias or changed PATH cannot prove an external dependency.
    print -r -- "$body" | /usr/bin/grep -Eq '^[[:space:]]*((function[[:space:]]+)?dart[[:space:]]*\(|alias[[:space:]]+dart=|export[[:space:]]+PATH=|PATH=)' && return 0
    print -r -- "$body" | /usr/bin/grep -Eq '^[[:space:]]*((exec|command|if)[[:space:]]+)?dart([[:space:];]|$)|^#![[:space:]]*/usr/bin/env([[:space:]]+-S)?[[:space:]]+dart([[:space:]]|$)' || return 0
    dart_bin="$(whence -p dart 2>/dev/null)" || return 0
    dart_bin="${dart_bin:A}"
    [[ "${dart_bin:t}" == dart && "${dart_bin:h:t}" == bin ]] || return 0
    sdk="${dart_bin:h:h}"
    [[ -x "$sdk/bin/flutter" && -f "$sdk/bin/internal/update_dart_sdk.sh" && -f "$sdk/bin/internal/shared.sh" ]] || return 0
    # Standalone/native Dart is already executable and must not trigger another SDK.
    kind="$(/usr/bin/file -b "$dart_bin" 2>/dev/null)" || return 0
    case "$kind" in *Mach-O*|*ELF*) return 0 ;; *text*|*script*) ;; *) return 0 ;; esac
    /usr/bin/grep -Eq 'shared\.sh|cache/dart-sdk' "$dart_bin" || return 0
    expected="${FLUTTER_PREBUILT_ENGINE_VERSION:-}"
    [[ -n "$expected" || ! -f "$sdk/bin/internal/engine.version" ]] || expected="$(<"$sdk/bin/internal/engine.version")"
    if [[ -n "$expected" && -x "$sdk/bin/cache/dart-sdk/bin/dart" && -f "$sdk/bin/cache/engine-dart-sdk.stamp" && "$(<"$sdk/bin/cache/engine-dart-sdk.stamp")" == "$expected" ]]; then return 0; fi
    jfs_route_note "$log_file" '▶ FVM文本入口依赖当前PATH的Flutter Dart shim；先准备该真实运行时，再查询FVM元数据。'
    JOBS_FLUTTER_ROUTE_MODE=dart JOBS_FLUTTER_ROUTE_CAPTURE_OUTPUT=1 \
        jobs_flutter_sdk_retry "$title" "$log_file" "$sdk" '' "$sdk/bin/flutter" --version >&2
}

# 小型只读命令必须有界；仅过滤后的上下文字段通过stdout，不落完整环境JSON。
jfs_fvm_timed() (
    local child_pid='' started=$SECONDS result=0
    trap '[[ -z "$child_pid" ]] || jfs_route_stop_tree "$child_pid"; exit 130' INT
    trap '[[ -z "$child_pid" ]] || jfs_route_stop_tree "$child_pid"; exit 143' TERM
    trap '[[ -z "$child_pid" ]] || jfs_route_stop_tree "$child_pid"; exit 129' HUP
    "$@" <&0 &
    child_pid=$!
    while /bin/kill -0 "$child_pid" 2>/dev/null; do
        if (( SECONDS-started>=10 )); then
            jfs_route_stop_tree "$child_pid"
            wait "$child_pid" 2>/dev/null
            return 124
        fi
        /bin/sleep 0.1
    done
    wait "$child_pid" || result=$?
    return "$result"
)
# FVM context包含完整环境，仅在内存管道筛选实际Git源和SDK缓存位置。
jfs_fvm_context_fields() {
    local fvm_bin="$1" requested="$2"
    "$fvm_bin" api context 2>/dev/null | /usr/bin/ruby -rjson -e '
      begin
        c=JSON.parse(STDIN.read).fetch("context")
        url=c["flutterUrl"]; cache=c["versionsCachePath"]; wanted=ARGV.fetch(0)
        if wanted.include?("/")
          fork=wanted.split("/",2).first; forks=(c["config"]||{})["forks"]
          entry=forks.is_a?(Hash) ? forks[fork] : nil
          url=entry if entry.is_a?(String)
          url=entry["url"] || entry["flutterUrl"] if entry.is_a?(Hash)
          raise "unresolved fork" if entry.nil?
        end
        raise "missing fields" unless url.is_a?(String) && !url.empty? && cache.is_a?(String) && cache.start_with?("/")
        raise "unsafe fields" if [url,cache].any?{|s|s.match?(/[\x00-\x1f\x7f]/)}
        STDOUT.write([url,cache].join("\t"))
      rescue StandardError
        exit 1
      end
    ' "$requested"
    local -a command_status=("${pipestatus[@]}")
    (( command_status[1]==0 && command_status[2]==0 ))
}
# 老FVM无context API时只读既有配置，不改用户源，不从版本目录猜fork仓库。
jfs_fvm_legacy_fields() {
    /usr/bin/ruby -rjson -e '
      begin
        wanted=ARGV.fetch(0); root=ENV.fetch("HOME")
        cfg={}; file=File.join(root,"Library/Application Support/fvm/.fvmrc")
        cfg=JSON.parse(File.read(file)) if File.file?(file)
        [File.join(Dir.pwd,".fvmrc"),File.join(Dir.pwd,".fvm/fvm_config.json")].each do |project_file|
          if File.file?(project_file)
            project=JSON.parse(File.read(project_file)); cfg=cfg.merge(project); break
          end
        end
        url=ENV.key?("FVM_FLUTTER_URL") ? ENV["FVM_FLUTTER_URL"] : cfg["flutterUrl"]
        url="https://github.com/flutter/flutter.git" if url.nil?
        cache=ENV["FVM_CACHE_PATH"] || ENV["FVM_HOME"] || cfg["cachePath"]
        cache=File.join(root,File.directory?(File.join(root,".fvm/versions")) ? ".fvm" : "fvm") if cache.nil? || cache.empty?
        cache=File.join(cache,"versions")
        if wanted.include?("/")
          forks=cfg["forks"]; entry=forks.is_a?(Hash) ? forks[wanted.split("/",2).first] : nil
          url=entry if entry.is_a?(String)
          url=entry["url"] || entry["flutterUrl"] if entry.is_a?(Hash)
          raise "unresolved fork" if entry.nil?
        end
        raise "unsafe fields" unless url.is_a?(String) && !url.empty? && cache.start_with?("/")
        raise "unsafe fields" if [url,cache].any?{|s|s.match?(/[\x00-\x1f\x7f]/)}
        STDOUT.write([url,cache].join("\t"))
      rescue StandardError
        exit 1
      end
    ' "$1"
}
# 把Git获取返回零但缺SDK入口的残缺安装继续留在获取阶段。
jfs_fvm_install_once() {
    local log_file="$1" sdk="$2" fvm_bin="$3" version="$4" code=0
    shift 4
    "$fvm_bin" install "$version" "$@" 2>&1 | /usr/bin/tee -a "$log_file"
    code=${pipestatus[1]}
    (( code==0 )) || return "$code"
    [[ -x "$sdk/bin/flutter" ]] || { jfs_route_note "$log_file" '⚠ FVM返回成功但Flutter入口缺失，将重新获取。'; return 1; }
}
# 旧组合通道先验证同一实际网络环境可读原Git，再执行安装，不能重写其来源。
jfs_fvm_combined_once() {
    local log_file="$1" sdk="$2" fvm_bin="$3" version="$4" url="$5" ref="$6" code=0
    shift 6
    jfs_fvm_timed /usr/bin/env GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0 "${JOBS_FLUTTER_ROUTE_GIT:-/usr/bin/git}" -c protocol.version=2 ls-remote --exit-code "$url" "$ref" >/dev/null 2>&1 || code=$?
    (( code==0 )) || { jfs_route_note "$log_file" "⚠ FVM组合通道的原Git源未通过有界检查（$code）。"; return "$code"; }
    jfs_fvm_install_once "$log_file" "$sdk" "$fvm_bin" "$version" "$@"
}
# 先读FVM生效上下文，优先分离Git和SDK自举；原生附加参数及用户fork保持。
jobs_flutter_fvm_install() {
    setopt LOCAL_OPTIONS
    unsetopt NOUNSET
    local title="$1" log_file="$2" fvm_bin="$3" version="$4" fields='' source_url='' versions='' sdk='' help_text='' code=0
    local no_setup=0 setup_flag='' ref='' token=''
    local -a install_args=()
    shift 4
    [[ -n "$version" && "$version" != -* && "$version" != /* && "$version" != *$'\n'* && "$version" != *$'\r'* && "/$version/" != */../* && "/$version/" != */./* ]] || { jfs_route_note "$log_file" '✖ FVM版本为空或路径无效。'; return 2; }
    jobs_flutter_fvm_runtime "${title}：FVM所需Dart运行时" "$log_file" "$fvm_bin" || return $?
    fields="$(jfs_fvm_timed jfs_fvm_context_fields "$fvm_bin" "$version")" || code=$?
    case "$code" in 129|130|137|143) return "$code" ;; esac
    if [[ -z "$fields" ]]; then fields="$(jfs_fvm_legacy_fields "$version")" || { jfs_route_note "$log_file" '✖ 无法可靠取得FVM源/缓存配置，保留原配置并停止。'; return 2; }; fi
    IFS=$'\t' read -r source_url versions <<< "$fields"
    sdk="${versions%/}/$version"
    # 已存在的fork缓存以其真实origin为准，不将自定义仓库改为官方。
    if [[ -d "$sdk/.git" || -f "$sdk/.git" ]]; then
        token="$(/usr/bin/env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_COMMON_DIR /usr/bin/git --no-optional-locks -c core.fsmonitor=false -C "$sdk" remote get-url origin 2>/dev/null)" && source_url="$token"
    fi
    help_text="$(jfs_fvm_timed "$fvm_bin" install --help 2>/dev/null)" || code=$?
    case "$code" in 129|130|137|143) return "$code" ;; esac
    if [[ "$help_text" == *'--[no-]setup'* || "$help_text" == *'--no-setup'* ]]; then setup_flag=--no-setup
    elif [[ "$help_text" == *'--skip-setup'* ]]; then setup_flag=--skip-setup
    fi
    for token in "$@"; do
        case "$token" in
            --no-setup|--skip-setup) no_setup=1 ;;
            --setup|-s) ;;
            *) install_args+=("$token") ;;
        esac
    done
    token="${version##*/}"
    ref="refs/tags/${token#v}"
    case "$token" in stable|beta|dev|main|master) ref="refs/heads/$token" ;; esac
    [[ "$token" =~ '^[0-9a-fA-F]{7,40}$' ]] && ref=HEAD
    if [[ -n "$setup_flag" ]]; then
        install_args+=("$setup_flag")
        JOBS_FLUTTER_ROUTE_MODE=git JOBS_FLUTTER_ROUTE_SOURCE_URL="$source_url" JOBS_FLUTTER_ROUTE_GIT_REF="$ref" \
            jobs_flutter_sdk_retry "${title}：原Git源获取" "$log_file" "$sdk" "$version" jfs_fvm_install_once "$log_file" "$sdk" "$fvm_bin" "$version" "${install_args[@]}" || return $?
    else
        # 老版没有关闭自举的能力时，制品路线先选定，再验证同环境原Git源可用。
        [[ "$no_setup" == 0 ]] || { jfs_route_note "$log_file" '✖ 当前FVM无法兑现显式仅安装、不自举的要求；未执行安装。'; return 2; }
        local legacy_mode=git legacy_auto=1
        case "${source_url%/}" in
            https://github.com/flutter/flutter|https://github.com/flutter/flutter.git)
                if [[ "$token" == stable || "$token" == beta || "$token" == dev || "$token" =~ '^v?[0-9]+\.[0-9]+\.[0-9]+([-+].*)?$' ]]; then legacy_mode=archive; legacy_auto=0; fi ;;
        esac
        if (( legacy_auto )); then
            jfs_route_note "$log_file" 'ℹ 旧FVM无法分离自举且目标无可信公开archive：先检测原Git来源；源码形成后再检测实际engine制品，不宣称首轮已验证未知二进制。'
        fi
        JOBS_FLUTTER_ROUTE_MODE="$legacy_mode" JOBS_FLUTTER_ROUTE_LEGACY_FVM_AUTO="$legacy_auto" \
        JOBS_FLUTTER_ROUTE_SOURCE_URL="$source_url" JOBS_FLUTTER_ROUTE_GIT_REF="$ref" \
            jobs_flutter_sdk_retry "${title}：Git与制品组合通道" "$log_file" "$sdk" "$version" jfs_fvm_combined_once "$log_file" "$sdk" "$fvm_bin" "$version" "$source_url" "$ref" "${install_args[@]}" || return $?
    fi
    (( no_setup==0 )) || return 0
    JOBS_FLUTTER_ROUTE_MODE=dart \
        JOBS_FLUTTER_ROUTE_CAPTURE_OUTPUT=1 jobs_flutter_sdk_retry "${title}：Dart/引擎自举" "$log_file" "$sdk" "$version" "$sdk/bin/flutter" --version
}

# 升级使用同一选中网络环境检查原跟踪Git，再执行原命令；Git失败也使候选降权。
jfs_flutter_upgrade_once() {
    local log_file="$1" sdk="$2" url="$3" ref="$4" code=0
    shift 4
    jfs_fvm_timed /usr/bin/env GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0 \
        "${JOBS_FLUTTER_ROUTE_GIT:-/usr/bin/git}" -c protocol.version=2 \
        ls-remote --exit-code "$url" "$ref" >/dev/null 2>&1 || code=$?
    (( code==0 )) || { jfs_route_note "$log_file" "⚠ SDK升级的原Git跟踪ref在同一网络环境中不可读（$code）；本轮未执行upgrade。"; return "$code"; }
    "$@" || return $?
    local engine_file="$sdk/bin/cache/engine.stamp"
    [[ -f "$engine_file" ]] || engine_file="$sdk/bin/internal/engine.version"
    [[ -x "$sdk/bin/cache/dart-sdk/bin/dart" && -f "$engine_file" && -f "$sdk/bin/cache/engine-dart-sdk.stamp" ]] && \
        /usr/bin/cmp -s "$engine_file" "$sdk/bin/cache/engine-dart-sdk.stamp" || {
        jfs_route_note "$log_file" '⚠ upgrade返回成功但目标SDK原生Dart/engine stamp仍未就绪，保留在SDK获取阶段。'
        return 1
    }
}
# sdk/channel都来自明确参数或真实本地SDK，不把目录名和公共stable当成用户的升级目标。
jobs_flutter_upgrade() {
    setopt LOCAL_OPTIONS
    unsetopt NOUNSET
    local title="$1" log_file="$2" sdk="$3" requested="$4" branch='' remote='' url='' ref='' target='' mode='' token=''
    shift 4
    (( $#>0 )) || return 2
    if [[ -z "$sdk" ]]; then
        for token in "$@"; do [[ "$token" == */bin/flutter ]] && sdk="${token:A:h:h}" && break; done
        [[ -n "$sdk" || ! -d "$PWD/.fvm/flutter_sdk" ]] || sdk="$PWD/.fvm/flutter_sdk"
        [[ -n "$sdk" || -z "${commands[flutter]:-}" ]] || sdk="${commands[flutter]:A:h:h}"
    fi
    [[ -d "$sdk/.git" || -f "$sdk/.git" ]] || { jfs_route_note "$log_file" '✖ 无法定位SDK原Git仓库，未猜测来源或执行升级。'; return 2; }
    # 只读当前SDK配置，忽略其它仓库遗留的Git目录环境变量。
    local -a local_git=(/usr/bin/env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_COMMON_DIR \
        "${JOBS_FLUTTER_ROUTE_GIT:-/usr/bin/git}" --no-optional-locks -c core.fsmonitor=false -C "$sdk")
    branch="$("${local_git[@]}" symbolic-ref --quiet --short HEAD 2>/dev/null)" || {
        jfs_route_note "$log_file" '✖ SDK不在可升级的跟踪分支，保留原版本；未猜测频道。'
        return 2
    }
    [[ -n "$branch" && "$branch" != *$'\n'* && "$branch" != *$'\r'* ]] || return 2
    remote="$("${local_git[@]}" config --get "branch.$branch.remote" 2>/dev/null)" || remote=origin
    [[ -n "$remote" && "$remote" != . ]] || { jfs_route_note "$log_file" '✖ SDK跟踪来源不是远端仓库，未执行网络升级。'; return 2; }
    url="$("${local_git[@]}" remote get-url "$remote" 2>/dev/null)" || return 2
    [[ -n "$url" && "$url" != *$'\n'* && "$url" != *$'\r'* ]] || return 2
    ref="$("${local_git[@]}" config --get "branch.$branch.merge" 2>/dev/null)" || ref="refs/heads/$branch"
    [[ "$ref" == refs/heads/* ]] && "${local_git[@]}" check-ref-format "$ref" >/dev/null 2>&1 || return 2
    target="${requested:-$branch}"
    case "$target" in
        stable|beta|dev)
            case "${url%/}" in
                https://github.com/flutter/flutter|https://github.com/flutter/flutter.git) mode=archive ;;
                *) mode=platform; jfs_route_note "$log_file" 'ℹ 自定义SDK跟踪源保持原样；只核验当前实际engine代表制品，不取公共channel归档冒充fork目标。' ;;
            esac
            ;;
        *)
            mode=platform
            jfs_route_note "$log_file" 'ℹ 当前为自定义/开发分支；按当前engine代表制品探测网络，不宣称验证了该分支的新版本制品，不切换到公共stable。'
            ;;
    esac
    JOBS_FLUTTER_ROUTE_MODE="$mode" jobs_flutter_sdk_retry "$title" "$log_file" "$sdk" "$target" \
        jfs_flutter_upgrade_once "$log_file" "$sdk" "$url" "$ref" "$@"
}

# 子进程CLI保留stdin，不需要eval环境，也不依赖固定仓库位置。
jfs_route_main() {
    case "${1:-}" in
        --flutter-upgrade) shift; (( $#>=5 )) || return 2; jobs_flutter_upgrade "$@" ;;
        --fvm-runtime) shift; (( $#==3 )) || return 2; jobs_flutter_fvm_runtime "$@" ;;
        --fvm-install) shift; (( $#>=4 )) || return 2; jobs_flutter_fvm_install "$@" ;;
        --cache-dir) jfs_route_cache_init || return $?; print -r -- "$JFS_ROUTE_CACHE_DIR" ;;
        --run) shift; (( $#>=5 )) || return 2; jobs_flutter_sdk_retry "$@" ;;
        --once) shift; (( $#>=5 )) || return 2; jobs_flutter_sdk_once "$@" ;;
        --) shift; (( $#>0 )) || return 2; local log_file="${JOBS_FLUTTER_ROUTE_LOG:-}"; [[ -n "$log_file" ]] || log_file="$(/usr/bin/mktemp "${TMPDIR:-/tmp/}JobsFlutterSdkRouteLog.XXXXXX")"; jobs_flutter_sdk_retry 'Flutter SDK' "$log_file" "${JOBS_FLUTTER_ROUTE_SDK_ROOT:-}" "${JOBS_FLUTTER_ROUTE_VERSION:-}" "$@" ;;
        *) print -u2 '内部SDK网络模块：--run 标题 日志 SDK根 版本 命令 参数…'; return 2 ;;
    esac
}
# JOBS_FLUTTER_ROUTE_END

typeset -g SF_PROJECT="" SF_CHECK=0 SF_SDK_ONLY=0 SF_FLUTTER_MODE="" SF_JAVA_MODE="" SF_FLUTTER="" SF_FLUTTER_ROOT="" SF_JAVA_HOME=""
typeset -g SF_MIRROR=official SF_ENV_STAMP="" SF_LOCAL_STAMP="" SF_FVM_ACTION="" SF_SYSTEM_ACTION="" SF_HAS_ANDROID=1 SF_NEEDS_GRADLE=1 SF_NEEDS_JAVA=1
typeset -g SF_FLUTTER_VERSION="" SF_DART_VERSION="" SF_FVM_VERSION="" SF_JENV_VERSION=""
# 第一屏展示各阶段真实影响，参数检查和只读模式不会写日志。
sf_intro_and_wait() {
    local answer=""
    print -r -- '━━━━━━━━━━ SetupFlutterProject.zsh｜一键配置 Flutter 项目 ━━━━━━━━━━'
    print -r -- '1、先用fzf选择Flutter来源（默认FVM）；Android/OpenHarmony再选择Java来源（默认jEnv），其它目标不要求JDK。'
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
                SF_FLUTTER_MODE="$PE_SELECTION"
                if (( SF_NEEDS_JAVA )); then step=2; else SF_JAVA_MODE=none; step=3; fi ;;
            2)
                pe_select Java $'jenv\tjEnv项目JDK（推荐）\nsystem\t系统Java / 指定本机JDK（不使用jEnv）' || result=$?
                if (( result == 10 )); then step=1; continue; fi
                (( result == 0 )) || return "$result"
                SF_JAVA_MODE="$PE_SELECTION"; step=3 ;;
            3)
                pe_select '下载线路' $'official\t项目/官方来源（默认）\naliyun\t腾讯Gradle镜像 + 阿里云Maven备用源（本次进程）' || result=$?
                if (( result == 10 )); then
                    if (( SF_NEEDS_JAVA )); then step=2; else step=1; fi
                    continue
                fi
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
    # 首次组件下载先完成，再单独读取机器结果，避免进度日志污染版本 JSON。
    SF_COMMAND_TIMEOUT=1800 JOBS_SDK_LOG_REPLACED=1 jobs_flutter_sdk_retry 'Flutter / Dart首次补齐' "$PE_RUN_DIR/flutter-bootstrap.log" "$SF_FLUTTER_ROOT" "" sf_run_diagnostic flutter-bootstrap "$SF_FLUTTER" --version || return $?
    SF_COMMAND_TIMEOUT=1800 JOBS_SDK_LOG_REPLACED=1 jobs_flutter_sdk_retry 'Flutter / Dart首次补齐' "$PE_RUN_DIR/flutter-version.log" "$SF_FLUTTER_ROOT" "" sf_run_diagnostic flutter-version "$SF_FLUTTER" --version --machine || return $?
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
                # Homebrew 在管道下会静默 curl；PTY 保留 SDK 原生下载进度，外层继续落日志。
                pe_run_logged /bin/sh "$PE_TOOLS_DIR/【MacOS】FlutterSDK命令适配.sh/【MacOS】FlutterSDK命令适配.sh" --brew-cask "$brew" install || return $?
                target="$PJ_BREW_PREFIX/bin/flutter" ;;
        esac
        [[ -n "$target" && "${target:A}" != "$SF_PROJECT/.fvm/"* ]] || { pe_log '✖ PATH未提供独立系统Flutter，请选择已有SDK路径或安装。'; continue; }
        result=0
        sf_probe_flutter "$target" || result=$?
        case "$result" in 129|130|131|137|143) return "$result" ;; esac
        (( result != 0 )) || return 0
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
    local candidate="" result=0
    for candidate in "${JOBS_FVM_BIN:-}" "$(command -v fvm 2>/dev/null)" "$HOME/.pub-cache/bin/fvm" "$HOME/.local/bin/fvm" /opt/homebrew/bin/fvm /usr/local/bin/fvm; do
        [[ -n "$candidate" && -x "$candidate" ]] || continue
        result=0; jobs_flutter_fvm_runtime "FVM所需Dart运行时" "$PE_LOG_FILE" "$candidate" || result=$?
        (( result==0 )) || return "$result"
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
    if (( SF_NEEDS_JAVA )) && [[ -n "$SF_JAVA_HOME" && -n "$detected_java" && "${detected_java:A}" != "${SF_JAVA_HOME:A}/bin/java" ]]; then
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
    if [[ -n "$SF_JAVA_HOME" ]]; then
        pe_log "➤ 在当前项目终端使用所选SDK：JAVA_HOME=${(q)SF_JAVA_HOME} PATH=${(q)SF_JAVA_HOME}/bin:\$PATH ${(q)SF_FLUTTER} run（先按项目要求补充flavor/入口/设备参数）。"
    else
        pe_log "➤ 在当前项目终端使用所选SDK：${(q)SF_FLUTTER} run（先按项目要求补充flavor/入口/设备参数）。"
    fi
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
        SF_NEEDS_JAVA="$SF_NEEDS_GRADLE"
        SR_TARGET='sdk-only'
    else
        sr_choose_target || return $?
        SF_NEEDS_GRADLE=0
        SF_NEEDS_JAVA=0
        [[ "$SR_TARGET" != android && "$SR_TARGET" != ohos ]] || SF_NEEDS_JAVA=1
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
            pd_load_toolchain_support && pt_prepare_ohos_toolchain || return $?
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
        (( SF_NEEDS_JAVA )) || break
        result=0; sf_step java.discovery java '选择Java SDK' sf_choose_java || result=$?
        if (( result == 10 )); then continue; fi
        (( result == 0 )) || return "$result"
        break
    done
    if (( SF_NEEDS_JAVA )); then
        sf_step java '' 'Java SDK' sf_apply_java && sf_resolve_selected_java || return $?
    else
        SF_JAVA_MODE=none SF_JAVA_HOME=""
        pe_event java '' 'Java SDK' succeeded '所选目标不依赖Java，已跳过JDK准备'
    fi
    sf_step flutter.configuration flutter '保存项目环境' sf_write_configuration || return $?
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
