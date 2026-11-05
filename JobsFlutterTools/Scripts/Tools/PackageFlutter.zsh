#!/bin/zsh
# 脚本自述：
# - 脚本名称：PackageFlutter.zsh（Flutter打包）。
# - 核心用途：精确 Flutter 项目目录中用 fzf 选择 iOS、Android 或鸿蒙 HAP / APP。
# - 影响范围：解析依赖、调用工程构建与既有签名；生成项目 build 产物及私有日志。
# - 运行提示：自述后回车继续；Esc / Ctrl+C 取消；不安装升级工具、不修改系统配置。

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
typeset -a FP_HARMONY_ARTIFACTS=()

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
    if [[ -n "$FP_OHOS_FLUTTER_SDK" ]]; then
        fp_error '此菜单仅使用项目 FVM SDK；请先用 FVM 绑定 Harmony 版本。'; return 1
    elif [[ -x "$FP_PROJECT/.fvm/flutter_sdk/bin/flutter" ]]; then
        FP_FLUTTER=("$FP_PROJECT/.fvm/flutter_sdk/bin/flutter")
    elif [[ -e "$FP_PROJECT/.fvmrc" || -e "$FP_PROJECT/.fvm/fvm_config.json" || -L "$FP_PROJECT/.fvm/flutter_sdk" ]]; then
        [[ "$FP_PLATFORM" != ohos ]] || { fp_error '鸿蒙项目固定了 FVM，但本地 SDK 不可用；请先恢复对应 SDK，不自动下载 SDK。'; return 1; }
        command -v fvm >/dev/null 2>&1 || { fp_error '项目固定了 FVM，但项目 SDK / fvm 不可用，请先恢复对应版本'; return 1; }
        FP_FLUTTER=("$(command -v fvm)" flutter)
    else
        fp_error '找不到 Flutter SDK，请检查项目 FVM 或终端 PATH'
        return 1
    fi
    fp_log "ℹ Flutter 命令：${(j: :)FP_FLUTTER}"
    jobs_flutter_sdk_retry 'Flutter / Dart首次补齐' "$FP_LOG_FILE" "" "" fp_run_step '检查并补齐SDK' "${FP_FLUTTER[@]}" --version || return $?
}

fp_check_java17() {
    local candidate="${JAVA_HOME:-}" version=""
    if [[ -e "$FP_PROJECT/.java-version" || -L "$FP_PROJECT/.java-version" ]]; then
        source "${${(%):-%x}:A:h}/ManageProjectJava.zsh" || return $?
        pj_bind_project_java "$FP_PROJECT" || return $?
        fp_log "ℹ 项目 Java：$PJ_CONFIG · $JAVA_HOME（Gradle JVM 已绑定）"
        return 0
    fi
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

# 构建前只重试所选平台的SDK制品获取；构建失败保持单次失败。
fp_prepare_target_sdk_resources() {
    local help_text=""
    if [[ "$FP_PLATFORM" == ohos ]]; then
        help_text="$("${FP_FLUTTER[@]}" precache --help 2>&1)" || return $?
        print -r -- "$help_text" | /usr/bin/grep -Fq -- --ohos || { fp_error '当前鸿蒙Flutter没有precache --ohos，无法可靠准备目标资源，请使用支持此命令的适配SDK。'; return 1; }
    fi
    JOBS_FLUTTER_ROUTE_MODE=platform jobs_flutter_sdk_retry "Flutter $FP_PLATFORM 平台资源" "$FP_LOG_FILE" "" "" fp_run_step '准备目标SDK资源' "${FP_FLUTTER[@]}" precache "--$FP_PLATFORM"
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
            FP_HARMONY_ARTIFACTS+=("$file")
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
    local target="" artifact=""
    local -a targets=() args=()
    FP_HARMONY_ARTIFACTS=()
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
    # APP 构建可能重建输出树，最后复核先前登记的 HAP 与 APP 仍然存在。
    for artifact in "${FP_HARMONY_ARTIFACTS[@]}"; do
        [[ -f "$artifact" && ! -L "$artifact" && -s "$artifact" ]] || {
            fp_error "最终产物复核失败，已生成的包被后续构建移除或清空：$artifact"
            return 1
        }
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
    fp_prepare_target_sdk_resources || return $? # 必需平台制品先获取成功。
    fp_build # 逐步构建，失败保留退出码并停止。
}

# 唯一入口先展示自述，再执行请求；帮助与只读检查保持无交互。
main() {
    fp_show_intro "$@" # 说明用途与影响，帮助和只读检查跳过运行提示。
    fp_dispatch "$@" # 校验项目并选择平台，按顺序检查与构建。
}

main "$@"
