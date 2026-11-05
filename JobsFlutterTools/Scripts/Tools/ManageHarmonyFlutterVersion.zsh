#!/bin/zsh
# 脚本自述：
# - 脚本名称：ManageHarmonyFlutterVersion.zsh，Created by Jobs。
# - 核心用途：查询 CPF-Flutter 的鸿蒙适配 tag，安装或切换指定项目的 FVM SDK。
# - 影响范围：确认后准备缺失 FVM、隔离 SDK 缓存和项目绑定；保留 IDE / ignore 配置。
# - 运行提示：先读自述并回车，再选择版本；最终输入 YES 才执行，--check 仅本地只读检查。

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
fh_remote_once() {
    local elapsed=0 result=0
    GIT_TERMINAL_PROMPT=0 "$FH_GIT" -c http.lowSpeedLimit=1024 -c http.lowSpeedTime=30 ls-remote --tags "$FH_REPO" > "$FH_RUN/tags" 2>> "$FH_LOG" &
    FH_REMOTE_PID="$!"
    while kill -0 "$FH_REMOTE_PID" 2>/dev/null; do
        if (( elapsed >= 45 )); then
            jfs_route_stop_tree "$FH_REMOTE_PID"
            /bin/sleep 1
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
# 有来源可核对的本机SDK可离线选择；无缓存时远程清单持续获取。
fh_remote() {
    local cached=""
    cached="$(fh_data rows - "$FH_CACHE" "$FH_REPO")" || return $?
    if [[ -n "$cached" ]]; then fh_remote_once; return $?; fi
    JOBS_FLUTTER_ROUTE_MODE=git JOBS_FLUTTER_ROUTE_SOURCE_URL="$FH_REPO" JOBS_FLUTTER_ROUTE_GIT_REF='refs/tags/*' jobs_flutter_sdk_retry '鸿蒙Flutter远程版本清单' "$FH_LOG" "" "" fh_remote_once
}
# 只读取 CPF 远端标签；断网回退明确的本机缓存。
fh_versions() {
    FH_GIT="$(command -v git 2>/dev/null)"
    [[ -n "$FH_GIT" ]] || { fh_error '缺少 Git / Apple Command Line Tools，请安装后重试。'; return 1; }
    fh_source 'Flutter@OpenHarmony tag 清单' "$FH_REPO" '仅查询，不下载 SDK'
    local listing='-' rows='' result=0
    if fh_remote; then
        listing="$FH_RUN/tags"
    else
        result=$?
        case "$result" in 129|130|131|137|143) return "$result" ;; esac
        fh_log '⚠ 远程来源存在确定错误，仅提供带来源记录的本机缓存；不声称已获取最新版本。'
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
        jobs_sdk_retry 'FVM及其运行时' "$FH_LOG" fh_run env HOMEBREW_NO_AUTO_UPDATE=1 "$brew_bin" install btwld/fvm/fvm || return $?
        rehash
        FH_FVM="$(command -v fvm 2>/dev/null)"
        [[ -n "$FH_FVM" || ! -x "$prefix/bin/fvm" ]] || FH_FVM="$prefix/bin/fvm"
    fi
    [[ -n "$FH_FVM" ]] || { fh_error '安装后仍找不到 FVM。'; return 1; }
    jobs_flutter_fvm_runtime "FVM所需Dart运行时" "$FH_LOG" "$FH_FVM" || return $?
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
        fh_run "$FH_GIT" init "$stage/sdk" || return $?
        fh_run "$FH_GIT" -C "$stage/sdk" remote add origin "$FH_REPO" || return $?
        JOBS_FLUTTER_ROUTE_MODE=git JOBS_FLUTTER_ROUTE_SOURCE_URL="$FH_REPO" JOBS_FLUTTER_ROUTE_GIT_REF="refs/tags/$FH_TAG" jobs_flutter_sdk_retry "鸿蒙Flutter $FH_TAG" "$FH_LOG" "$target" "$FH_TAG" fh_run env GIT_TERMINAL_PROMPT=0 "$FH_GIT" -C "$stage/sdk" -c http.lowSpeedLimit=1 -c http.lowSpeedTime=120 fetch --progress --depth 1 origin "refs/tags/$FH_TAG" || return $?
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
    jobs_flutter_sdk_retry '鸿蒙Flutter / Dart首次补齐' "$FH_LOG" "$target" "$FH_TAG" fh_run "$target/bin/flutter" --version || return $?
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
