#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】🐦Flutter项目体检.command
# - 核心用途：默认检查 Flutter 开发环境，也可显式选择 pub-get 或 clean-get。
# - 影响范围：doctor 只请求诊断（SDK 自身可能准备缓存）；pub-get 写入依赖；clean-get 还会清理缓存。
# - 运行提示：终端回车确认；Sourcetree 连续执行；--help / --check 只读且无等待。
# shell: zsh

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

readonly SCRIPT_SOURCE="$0"
SCRIPT_PATH=""
SCRIPT_DIR=""
SCRIPT_BASENAME=""
LOG_FILE=""
LOG_READY=0
IS_SOURCETREE_RUNTIME=0
PLAIN_OUTPUT=0
READ_ONLY_MODE=""
PARSE_ERROR=""
FLUTTER_ROOT=""
ACTION="doctor"
typeset -a POSITIONAL_ARGS=() FLUTTER_CMD=() DART_CMD=()

# Sourcetree 的参数环境和父进程可证明入口身份，非 TTY 本身不构成身份。
is_sourcetree_runtime() {
  env | grep -Eqi '^(SOURCETREE|SOURCE_TREE)' && return 0
  local parent_pid="$PPID" command_name="" guard=0
  while [[ -n "$parent_pid" && "$parent_pid" != 0 && "$guard" -lt 8 ]]; do
    command_name="$(ps -o comm= -p "$parent_pid" 2>/dev/null)"
    [[ "$command_name" == *SourceTree* || "$command_name" == *Sourcetree* ]] && return 0
    parent_pid="$(ps -o ppid= -p "$parent_pid" 2>/dev/null | tr -d ' ')"
    guard=$((guard + 1))
  done
  return 1
}
# 使用真实源码位置；兼容 Sourcetree 只给脚本文件名的入口。
resolve_script_path() {
  local candidate="" script_name="${SCRIPT_SOURCE:t}"
  for candidate in "$SCRIPT_SOURCE" "$PWD/$SCRIPT_SOURCE" \
    "$HOME/SourceTree.command/$script_name/$script_name" \
    "$HOME/Documents/Github/JobsGenesis/SourceTree.command/$script_name/$script_name"; do
    if [[ -f "$candidate" ]]; then
      print -r -- "${candidate:A}"
      return 0
    fi
  done
  print -r -- "$PWD/$script_name"
}
# 第一屏自述前设置纯文本上下文，外部命令也复用同一过滤器。
prepare_plain_output_context() {
  if [[ "$IS_SOURCETREE_RUNTIME" == 1 || ! -t 1 || -z "${TERM:-}" || "${TERM:-}" == dumb || -n "${NO_COLOR+x}" || "${JOBS_PLAIN_OUTPUT:-0}" == 1 ]]; then
    PLAIN_OUTPUT=1
    export NO_COLOR=1 FORCE_COLOR=0 CLICOLOR=0 ANSI_COLORS_DISABLED=1 npm_config_color=false
  fi
}
# 过滤脚本与外部工具的 ANSI 控制码。
strip_ansi_text() {
  /usr/bin/perl -e '
    $| = 1; my $pending = "";
    while (my $size = sysread(STDIN, my $chunk, 65536)) {
      $pending .= $chunk;
      $pending =~ s/\e\[[0-9;?]*[ -\/]*[@-~]//g;
      $pending =~ s/\e\][^\a]*?(?:\a|\e\\)//g;
      my $tail = "";
      $tail = $1 if $pending =~ s/(\e(?:\[[0-9;?]*[ -\/]*|\](?:(?!\a|\e\\).)*|))\z//s;
      print $pending;
      $pending = $tail;
    }
    print $pending;
  '
}
# 按字面文字同步输出终端和确认后的日志。
log() {
  if [[ "$LOG_READY" == 1 ]]; then
    printf '%s\n' "$1" | strip_ansi_text | tee -a "$LOG_FILE"
  else
    printf '%s\n' "$1" | strip_ansi_text
  fi
}
# 输出当前步骤或环境信息。
info_echo() { log "ℹ $1"; }
# 输出已验证完成的步骤。
success_echo() { log "✔ $1"; }
# 输出需要用户注意的条件。
warn_echo() { log "⚠ $1"; }
# 输出失败原因。
error_echo() { log "✖ $1"; }
# 输出路径和计划等次要信息。
gray_echo() { log "$1"; }
# 自述采用红色粗体标题和蓝色常规正文，受限输出降级纯文本。
intro_line() {
  local role="$1" message="$2" color='\033[0;34m'
  [[ "$role" == title ]] && color='\033[1;31m'
  if [[ "$PLAIN_OUTPUT" == 1 ]]; then
    print -r -- "$message"
  else
    printf '%b%s%b\n' "$color" "$message" '\033[0m'
  fi
}
# 只读选项可位于路径前后；其余参数仍按原入口顺序解释。
parse_script_arguments() {
  local argument="" literal=0
  for argument in "$@"; do
    if [[ "$literal" == 1 ]]; then
      POSITIONAL_ARGS+=("$argument")
      continue
    fi
    case "$argument" in
      --) literal=1 ;;
      --help|-h) READ_ONLY_MODE=help ;;
      --check) [[ "$READ_ONLY_MODE" == help ]] || READ_ONLY_MODE=check ;;
      -*) PARSE_ERROR="未知参数：$argument" ;;
      *) POSITIONAL_ARGS+=("$argument") ;;
    esac
  done
}
# 确认前只解析参数与展示说明，不创建日志、不调用 SDK。
show_script_intro_and_wait() {
  setopt NO_NOMATCH PIPE_FAIL
  SCRIPT_PATH="$(resolve_script_path)"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
  LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.log"
  is_sourcetree_runtime && IS_SOURCETREE_RUNTIME=1
  prepare_plain_output_context
  parse_script_arguments "$@"
  intro_line title "================ 脚本内置自述 ================"
  intro_line title "脚本名称：${SCRIPT_BASENAME}.command"
  intro_line body "1、用途：默认检查 Flutter 开发环境，也可显式选择 pub-get 或 clean-get。"
  intro_line body "2、影响：doctor 只请求诊断（SDK 自身可能准备缓存）；pub-get 写入依赖；clean-get 还会清理缓存。"
  intro_line body "3、策略：Sourcetree 连续执行；独立终端回车确认；Ctrl+C 取消。"
  intro_line body "4、只读：--help 查看参数；--check 检查路径、SDK 和计划，不调用 SDK、不写日志。"
  intro_line body "日志位置：$LOG_FILE"
  intro_line title "=============================================="
  if [[ -n "$READ_ONLY_MODE" ]]; then
    return 0
  fi
  [[ -z "$PARSE_ERROR" ]] || return 0
  if [[ "$IS_SOURCETREE_RUNTIME" == 1 ]]; then
    gray_echo '已识别为 Sourcetree 动作，无交互连续执行。'
  elif [[ ! -t 0 ]]; then
    error_echo '当前不是 Sourcetree 且没有可交互输入；请在终端运行，或使用 --check。'
    exit 1
  else
    IFS= read -r '?已了解用途与影响，按回车继续；Ctrl+C 取消：' _ || exit 1
  fi
}
# 保留用户 PATH 的选路优先级，仅在当前进程补齐常用工具目录。
initialize_script_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  export PATH="${PATH:-}:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.pub-cache/bin:$HOME/.fvm/bin:/opt/homebrew/bin:/usr/local/bin"
  prepare_plain_output_context
  if [[ -z "$READ_ONLY_MODE" && -z "$PARSE_ERROR" ]]; then
    : > "$LOG_FILE" || { print -r -- "日志不可写：$LOG_FILE" >&2; exit 1; }
    LOG_READY=1
  fi
}
# 先保留真实存在的路径，避免破坏文件名内合法引号和反斜杠。
normalize_flutter_input() {
  local input_value="$1"
  if [[ -e "$input_value" ]]; then
    print -r -- "$input_value"
    return 0
  fi
  input_value="${input_value%$'\r'}"
  input_value="${input_value%$'\n'}"
  if [[ "$input_value" == \"*\" || "$input_value" == \'*\' ]]; then
    input_value="${input_value[2,-2]}"
  fi
  [[ "$input_value" == '~/'* ]] && input_value="$HOME/${input_value#\~/}"
  [[ -e "$input_value" ]] || input_value="${(Q)input_value}"
  print -r -- "$input_value"
}
# 保守解析常用块映射和单行 flow 映射，不执行 YAML 标签、锚点或外部代码。
pubspec_query() {
  /usr/bin/perl - "$FLUTTER_ROOT/pubspec.yaml" "$1" "${2:-}" <<'PERL'
use strict;
use warnings;
my ($file, $mode, $wanted) = @ARGV;
open my $fh, '<:raw', $file or exit 2;
local $/; my $text = <$fh>; close $fh;
exit 2 if length($text) > 1048576 || $text =~ /\0/;
$text =~ s/^\xEF\xBB\xBF//;
$text =~ s/\r\n/\n/g;
sub trim { my $s = shift; $s =~ s/^\s+|\s+$//g; return $s; }
# 只接受引号和 flow 容器外的分隔符。
sub delimiter {
  my ($source, $wanted, $comments) = @_;
  my ($quote, $depth, $escaped) = ('', 0, 0);
  for (my $i = 0; $i < length($source); $i++) {
    my $c = substr($source, $i, 1);
    if ($quote ne '') {
      if ($quote eq '"' && $c eq '\\' && !$escaped) { $escaped = 1; next; }
      if ($c eq $quote && !$escaped) {
        if ($quote eq "'" && substr($source, $i + 1, 1) eq "'") { $i++; next; }
        $quote = '';
      }
      $escaped = 0;
    } elsif ($c eq '"' || $c eq "'") { $quote = $c; }
    elsif ($c eq $wanted && $depth == 0) {
      return $i if !$comments || !$i || substr($source, $i - 1, 1) =~ /\s/;
    } elsif ($c eq '{' || $c eq '[') { $depth++; }
    elsif ($c eq '}' || $c eq ']') { $depth--; }
  }
  return -1;
}
sub yaml_scalar {
  my $s = trim(shift);
  return undef unless length $s;
  if ($s =~ /^'((?:[^']|'')*)'$/s) { $s = $1; $s =~ s/''/'/g; return $s; }
  if ($s =~ /^"([^"\\]*)"$/s) { return $1; }
  return undef if $s =~ /[{}\[\],:#&*!|>"']/;
  return $s;
}
sub pair {
  my $s = shift;
  my $hash = delimiter($s, '#', 1);
  $s = substr($s, 0, $hash) if $hash >= 0;
  my $colon = delimiter($s, ':', 0);
  return () if $colon < 0;
  my $key = yaml_scalar(substr($s, 0, $colon));
  return () unless defined($key) && length($key);
  return ($key, trim(substr($s, $colon + 1)));
}
sub flow {
  my $s = trim(shift);
  die "unsupported flow" unless $s =~ /^\{(.*)\}$/s;
  my $rest = trim($1); my %result;
  while (length $rest) {
    my $comma = delimiter($rest, ',', 0);
    my $part = $comma >= 0 ? substr($rest, 0, $comma) : $rest;
    my ($key, $value) = pair($part);
    die "invalid flow" unless defined($key) && length($value) && !exists($result{$key});
    $result{$key} = $value =~ /^\{/ ? flow($value) : yaml_scalar($value);
    $rest = $comma >= 0 ? trim(substr($rest, $comma + 1)) : '';
  }
  return \%result;
}
my @entries;
for my $line (split /\n/, $text) {
  next if $line =~ /^\s*(?:#.*)?$/;
  exit 2 if $line =~ /^\s*(?:---|\.\.\.)\s*$/ || $line =~ /^ *\t/;
  my ($spaces) = $line =~ /^( *)/;
  my ($key, $value) = pair(substr($line, length($spaces)));
  push @entries, [length($spaces), $key, $value];
}
sub block {
  my ($index, $depth) = @_;
  my %result;
  while ($$index < @entries && $entries[$$index][0] == $depth) {
    my ($indent, $key, $value) = @{$entries[$$index]};
    $$index++;
    my $node;
    if (defined($key)) {
      die "duplicate mapping" if exists($result{$key});
      if (!length($value) && $$index < @entries && $entries[$$index][0] > $depth) {
        $node = block($index, $entries[$$index][0]);
      } elsif ($value =~ /^\{/) { $node = flow($value); }
      else { $node = yaml_scalar($value); }
      $result{$key} = $node;
    }
    # description 块字符串或其它不支持正文中的伪键不能抬升到根层。
    $$index++ while $$index < @entries && $entries[$$index][0] > $depth;
  }
  return \%result;
}
my ($root, $index) = (undef, 0);
eval { die "no root mapping" unless @entries && $entries[0][0] == 0; $root = block(\$index, 0); };
exit 2 if $@ || $index != @entries;
sub mapping { return ref($_[0]) eq 'HASH'; }
my $ok = 0;
if ($mode eq 'flutter') {
  my $deps = $root->{dependencies};
  $ok = mapping($deps) && mapping($deps->{flutter}) && defined($deps->{flutter}{sdk}) && !ref($deps->{flutter}{sdk}) && $deps->{flutter}{sdk} eq 'flutter';
} elsif ($mode eq 'dependency') {
  for my $section ('dependencies', 'dev_dependencies') {
    my $deps = $root->{$section};
    $ok = 1 if mapping($deps) && exists($deps->{$wanted});
  }
} elsif ($mode eq 'config') {
  $ok = mapping($root->{$wanted});
} elsif ($mode eq 'generate') {
  $ok = mapping($root->{flutter}) && defined($root->{flutter}{generate}) && !ref($root->{flutter}{generate}) && $root->{flutter}{generate} eq 'true';
}
exit($ok ? 0 : 1);
PERL
}
# 只查询依赖分区的直属包声明。
pubspec_has_dependency() {
  pubspec_query dependency "$1"
}
# Flutter 工程需声明 flutter 依赖，避免误选普通 Dart 包。
is_flutter_project() {
  local previous_root="$FLUTTER_ROOT" result=1
  FLUTTER_ROOT="$1"
  if [[ -f "$1/pubspec.yaml"  ]] && pubspec_query flutter; then
    result=0
  fi
  FLUTTER_ROOT="$previous_root"
  return "$result"
}
# 就近向上查找；向下扫描只接受唯一工程，跳过依赖、供应商和缓存。
resolve_flutter_project() {
  local base="$(normalize_flutter_input "${1:-${PROJECT_DIR:-${REPO:-$PWD}}}")"
  local current="" candidate="" found_specs=""
  local -a candidates=()
  [[ -f "$base" ]] && base="${base:h}"
  [[ -d "$base" ]] || { error_echo "工程路径不存在：$base"; return 1; }
  base="${base:A}"
  [[ "$base" != / && "$base" != "${HOME:A}" ]] || { error_echo '请指定工程目录，不扫描根目录或整个用户目录。'; return 1; }
  current="$base"
  while [[ "$current" != / ]]; do
    if is_flutter_project "$current"; then
      FLUTTER_ROOT="$current"
      return 0
    fi
    current="${current:h}"
  done
  found_specs="$(find "$base" \( -type d \( -name .git -o -name node_modules -o -name Pods -o -name PodsManual -o -name 'ManualBy*Pods*' -o -name .dart_tool -o -name .fvm -o -name build -o -name DerivedData -o -name .import_backup -o -name vendor -o -name third_party -o -name ThirdParty \) -prune \) -o \( -type f -name pubspec.yaml -print0 \))" || { error_echo "扫描工程失败：$base"; return 1; }
  for candidate in "${(@0)found_specs}"; do
    [[ -n "$candidate" ]] || continue
    is_flutter_project "${candidate:h}" && candidates+=("${candidate:h}")
  done
  if (( ${#candidates[@]} != 1 )); then
    error_echo "需要唯一 Flutter 工程，当前候选数量：${#candidates[@]}；pubspec 应声明 dependencies.flutter.sdk: flutter（支持常见块 / 单行 flow 映射）。"
    for candidate in "${candidates[@]}"; do
      gray_echo "候选：$candidate"
    done
    return 1
  fi
  FLUTTER_ROOT="${candidates[1]}"
}
# 固定版本工程缺少 SDK 时停止，避免隐式安装或悄悄切换全局版本。
choose_project_flutter() {
  local flutter_executable=""
  cd "$FLUTTER_ROOT" || return 1
  if [[ -x "$FLUTTER_ROOT/.fvm/flutter_sdk/bin/flutter" ]]; then
    flutter_executable="$FLUTTER_ROOT/.fvm/flutter_sdk/bin/flutter"
  elif [[ -f .fvmrc || -f .fvm/fvm_config.json || -e .fvm/flutter_sdk || -L .fvm/flutter_sdk ]]; then
    error_echo '工程固定的 FVM SDK 不可用；请先在工程中完成 fvm install / fvm use，再重试。'
    return 1
  elif command -v flutter >/dev/null 2>&1; then
    flutter_executable="${commands[flutter]:A}"
  else
    error_echo '没有可用 Flutter SDK；请检查当前 PATH 或项目 FVM 配置。'
    return 1
  fi
  FLUTTER_CMD=("$flutter_executable")
  DART_CMD=("${flutter_executable:h}/dart")
  info_echo "工程目录：$FLUTTER_ROOT"
  info_echo "Flutter 命令：${(q)FLUTTER_CMD[1]}"
}
# 在原始命令和日志管道之间保留退出码；命令失败优先返回其原码。
run_flutter_step() {
  local title="$1" result=0 code=0
  local -a step_codes=()
  shift
  info_echo "开始：$title"
  "$@" 2>&1 | strip_ansi_text | tee -a "$LOG_FILE"
  step_codes=("${pipestatus[@]}")
  for code in "${step_codes[@]}"; do
    if (( code != 0 )); then
      result="$code"
      break
    fi
  done
  if (( result != 0 )); then
    error_echo "$title 失败，退出码：$result；后续步骤已停止。"
    return "$result"
  fi
  success_echo "完成：$title"
}
# 高风险选项只在真实终端承接，并要求精确 YES；无交互入口不能绕过。
confirm_risky_options() {
  local message="$1" answer=""
  warn_echo "$message"
  if [[ "$IS_SOURCETREE_RUNTIME" == 1 || ! -t 0 || ! -t 1 ]]; then
    error_echo '该选项需要可交互终端和精确 YES 确认；请在终端独立运行。'
    return 1
  fi
  IFS= read -r '?输入精确大写 YES 继续，其它输入取消：' answer || return 1
  [[ "$answer" == YES ]] || { error_echo '已取消危险选项。'; return 1; }
}
# 说明参数、默认行为及只读入口。
show_usage() {
  print -r -- '用法：脚本 [--check|--help] [Flutter 工程路径] [doctor|pub-get|clean-get]'
  print -r -- '默认 doctor：flutter doctor -v，诊断有警告或错误时返回非零。'
  print -r -- 'pub-get：显式拉取依赖；clean-get：终端精确 YES 后清理并拉取依赖。'
  print -r -- '--check：只显示工程、SDK 和命令计划；--help：显示参数。'
}
# Flutter doctor 可能在发现环境问题时返回 0，需同时检查诊断结论。
run_flutter_doctor() {
  run_flutter_step 'flutter doctor -v' "${FLUTTER_CMD[@]}" doctor -v || return $?
  if grep -Eq '^[[:space:]]*\[(!|✗|✘|x|X)\]|Doctor found issues in|Doctor summary.*issues' "$LOG_FILE"; then
    warn_echo 'Flutter doctor 报告环境警告或错误；诊断未通过，请按上方输出处理。'
    return 1
  fi
  success_echo 'Flutter doctor 未报告环境警告或错误。'
}
# 定位工程并顺序执行显式选择的业务。
run_original_logic() {
  (( $# <= 2 )) || { show_usage; return 2; }
  ACTION="${2:-doctor}"
  case "$ACTION" in
    doctor|pub-get|clean-get) ;;
    *) error_echo "未知动作：$ACTION"; show_usage; return 2 ;;
  esac
  resolve_flutter_project "${1:-}" || return $?
  choose_project_flutter || return $?
  case "$ACTION" in
    doctor) gray_echo '计划：flutter doctor -v' ;;
    pub-get) gray_echo '计划：flutter pub get' ;;
    clean-get) gray_echo '计划：flutter clean → flutter pub get（终端 YES 确认）' ;;
  esac
  [[ "$READ_ONLY_MODE" == check ]] && return 0
  jobs_flutter_sdk_retry 'Flutter / Dart首次补齐' "$LOG_FILE" "" "" run_flutter_step '检查并补齐SDK' "${FLUTTER_CMD[@]}" --version || return $?
  case "$ACTION" in
    doctor) run_flutter_doctor || return $? ;;
    pub-get) run_flutter_step 'flutter pub get' "${FLUTTER_CMD[@]}" pub get || return $? ;;
    clean-get)
      confirm_risky_options 'flutter clean 会清理当前工程构建和工具生成目录。' || return $?
      run_flutter_step 'flutter clean' "${FLUTTER_CMD[@]}" clean || return $?
      run_flutter_step 'flutter pub get' "${FLUTTER_CMD[@]}" pub get || return $?
      ;;
  esac
}
# 只读入口与真实业务在同一解析路径上运行，保留最终失败状态。
run_checked_business() {
  local result=0
  [[ -z "$PARSE_ERROR" ]] || { error_echo "$PARSE_ERROR"; exit 2; }
  if [[ "$READ_ONLY_MODE" == help ]]; then
    show_usage
    return 0
  fi
  if run_original_logic "${POSITIONAL_ARGS[@]}"; then
    if [[ "$READ_ONLY_MODE" == check ]]; then
      success_echo '只读检查完成；未调用 SDK、写日志或执行工程命令。'
    else
      success_echo "脚本执行结束。日志：$LOG_FILE"
    fi
  else
    result=$?
    error_echo "脚本执行失败，退出码：$result。"
    [[ "$LOG_READY" == 1 ]] && gray_echo "日志：$LOG_FILE"
    exit "$result"
  fi
}
# 按自述、初始化、业务顺序编排入口。
main() {
  show_script_intro_and_wait "$@" # 第一屏自述及终端防误触确认。
  initialize_script_runtime # 初始化当前进程和确认后日志。
  run_checked_business # 统一分派只读检查和真实业务。
}

main "$@"
