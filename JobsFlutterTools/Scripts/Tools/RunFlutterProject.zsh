#!/bin/zsh
# 脚本自述：
# - 脚本名称：从终端运行 Flutter 项目。
# - 核心用途：终端选择设备，独立后台运行 Flutter，并查看日志及控制热重载。
# - 影响范围：Flutter 构建可更新项目依赖和构建目录；按需创建、启动所选 iOS 模拟器。
# - 运行提示：先回车确认；关闭终端只离开日志，输入 s 才停止后台任务。
# - 选择方式：终端内优先用 fzf 上下键 + 输入筛选选择；fzf 不可用或非终端时自动回退编号输入。

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

SCRIPT_DIR=""
SCRIPT_PATH=""
SCRIPT_SOURCE="${(%):-%x}"
LOG_FILE=""
PROJECT_PATH=""
FLUTTER_BIN=""
SDK_VERSION_LABEL="版本未解析"
HELPER=""
STATE_ROOT=""
SESSION_DIR=""
JOB_LABEL=""
DEVICE_ID=""
TAIL_PID=""
START_LOCK=""
LOCK_FD=""
QUERY_PID=""
QUERY_PROGRESS_FD=""
REPLY=""
FZF_BIN=""
typeset -a ROWS=() SDK_ARCHIVE_WRITERS=()

intro_line() {
  local role="$1" message="$2" code="0;34"
  [[ "$role" == title ]] && code="1;31"
  if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" ]]; then
    printf '\033[%sm%s\033[0m\n' "$code" "$message"
  else
    print -r -- "$message"
  fi
}

show_script_intro_and_wait() {
  intro_line title '从终端运行 Flutter 项目'
  intro_line body '1、选择设备后构建、运行当前 Flutter 项目；沿用项目 FVM SDK 或终端 Flutter。'
  intro_line body '2、Flutter 由当前登录会话的 launchd 托管，关闭 Terminal 不影响运行。'
  intro_line body '3、iOS 可选择已有模拟器；没有时内置选择型号、系统版本、创建及启动流程。'
  intro_line body '4、可能下载项目依赖、生成构建文件；项目声明的 FVM SDK 缺失时自动下载，失败持续重试直至成功或 Ctrl+C，不安装或升级全局 Flutter / Xcode。'
  intro_line body '5、日志与会话保存在用户资源库 Application Support/JobsFlutterRunner/sessions。'
  intro_line body '6、回车继续，非空或 Ctrl+C 取消；运行后 d 离开日志，s 停止后台任务。'
  intro_line body '7、设备、模拟器型号与系统版本用上下键选择，可直接输入关键字筛选；未装 fzf 时回退编号输入。'
  local answer=""
  IFS= read -r 'answer?已了解用途与范围，按回车继续；非空取消：' || exit 0
  [[ -z "$answer" ]] || exit 0
}

initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  umask 077
  SCRIPT_PATH="${SCRIPT_SOURCE:A}"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  HELPER="$SCRIPT_DIR/FlutterRunner.jxa"
  STATE_ROOT="$HOME/Library/Application Support/JobsFlutterRunner/sessions"
  LOG_FILE="$(/usr/bin/mktemp "${TMPDIR:-/tmp/}JobsFlutterRunner.XXXXXX")" || exit 1
  [[ -f "$HELPER" ]] || die '缺少 FlutterRunner.jxa，请保留完整脚本包。'
  log "操作日志：$LOG_FILE"
}

log() {
  print -r -- "$*" | /usr/bin/tee -a "$LOG_FILE"
}

die() {
  log "✖ $*"
  exit 1
}

json_helper() {
  /usr/bin/osascript -l JavaScript "$HELPER" "$@"
}

leave_terminal() {
  if [[ -n "$QUERY_PID" ]]; then
    jfs_route_stop_tree "$QUERY_PID"
    wait "$QUERY_PID" 2>/dev/null || true
    QUERY_PID=""
  fi
  close_query_progress
  if [[ -n "$TAIL_PID" ]]; then
    kill "$TAIL_PID" 2>/dev/null
    wait "$TAIL_PID" 2>/dev/null
    TAIL_PID=""
  fi
  if [[ -n "$LOCK_FD" ]]; then
    zsystem flock -u "$LOCK_FD" 2>/dev/null
    LOCK_FD=""
  fi
}

# 从原始日志增量读取字节，保留下载工具的回车进度，不改变命令 PID 或退出码。
show_query_progress() {
  local chunk=""
  [[ -n "$QUERY_PROGRESS_FD" ]] || return 0
  while sysread -i "$QUERY_PROGRESS_FD" -s 16384 chunk 2>/dev/null; do
    print -rn -- "$chunk"
  done
}

close_query_progress() {
  if [[ -n "$QUERY_PROGRESS_FD" ]]; then
    exec {QUERY_PROGRESS_FD}<&-
    QUERY_PROGRESS_FD=""
  fi
}

# 有界等待仅用于发现和启动设备，不给持续运行的 Flutter 设置超时。
run_bounded() {
  local seconds="$1" output="$2" task_pid="" elapsed=0 result=0
  shift 2
  if [[ "${RUN_BOUNDED_STREAM:-0}" == 1 ]]; then
    zmodload zsh/system || return 1
    : > "$output" || return 1
    exec {QUERY_PROGRESS_FD}< "$output" || return 1
  fi
  "$@" > "$output" 2>&1 &
  task_pid=$!
  QUERY_PID="$task_pid"
  while kill -0 "$task_pid" 2>/dev/null; do
    if (( elapsed >= seconds )); then
      jfs_route_stop_tree "$task_pid"
      /bin/sleep 1
      wait "$task_pid" 2>/dev/null
      QUERY_PID=""
      show_query_progress
      close_query_progress
      log "⚠ 命令超时（${seconds} 秒）：${1:t}；详情：$output"
      return 124
    fi
    show_query_progress
    /bin/sleep 1
    (( elapsed++ ))
  done
  wait "$task_pid" || result=$?
  QUERY_PID=""
  show_query_progress
  close_query_progress
  return "$result"
}

normalize_path_input() {
  local raw="${1%$'\r'}"
  local -a words=()
  if [[ -d "$raw" ]]; then
    REPLY="$raw"
    return
  fi
  words=("${(@z)raw}")
  (( ${#words} == 1 )) || die '请只输入或拖入一个项目目录。'
  REPLY="${(Q)words[1]}"
  [[ "$REPLY" == '~/'* ]] && REPLY="$HOME/${REPLY#\~/}"
}

read_project() {
  local input="" valid=""
  if (( $# == 2 )) && [[ "$1" == --project ]]; then
    PROJECT_PATH="$2"
  elif (( $# == 0 )); then
    IFS= read -r 'input?输入或拖入 Flutter 项目根目录：' || exit 0
    normalize_path_input "$input"
    PROJECT_PATH="$REPLY"
  else
    die '用法：RunFlutterProject.zsh --project <Flutter 项目根目录>'
  fi
  [[ -d "$PROJECT_PATH" && ! -L "$PROJECT_PATH" ]] || die '项目必须是存在的普通目录。'
  valid="$(json_helper validate "$PROJECT_PATH")" || die '无法解析 pubspec.yaml。'
  [[ "$valid" == true ]] || die '所选目录同层没有真实的 dependencies.flutter.sdk: flutter。'
  PROJECT_PATH="${PROJECT_PATH:A}"
  cd "$PROJECT_PATH" || die '不能进入项目目录。'
  log "项目：$PROJECT_PATH"
}

project_fvm_config() {
  if [[ -f "$PROJECT_PATH/.fvmrc" ]]; then
    REPLY="$PROJECT_PATH/.fvmrc"
    return 0
  fi
  if [[ -f "$PROJECT_PATH/.fvm/fvm_config.json" ]]; then
    REPLY="$PROJECT_PATH/.fvm/fvm_config.json"
    return 0
  fi
  return 1
}

# Dart压缩包名与Flutter的Darwin下载器一致，按物理ARM能力选择。
sdk_dart_download_arch() {
  local physical_arm=""
  physical_arm="$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null)" || physical_arm=""
  case "$physical_arm" in
    1) REPLY=arm64 ;;
    0) REPLY=x64 ;;
    *) REPLY="$(/usr/bin/uname -m)"; [[ "$REPLY" != x86_64 ]] || REPLY=x64 ;;
  esac
}
# 仅检查这个SDK压缩包的写句柄；只读句柄不阻止启动，也不操作已有写入者。
sdk_archive_writers() {
  local archive="$1" result=0 current_pid="" record="" saw_process=0
  SDK_ARCHIVE_WRITERS=()
  [[ -e "$archive" ]] || return 0
  [[ -x /usr/sbin/lsof ]] || return 2
  run_bounded 5 "$LOG_FILE.sdk-writers" /usr/sbin/lsof -n -P -F pfa -- "$archive" || result=$?
  case "$result" in 0|1) ;; *) return "$result" ;; esac
  while IFS= read -r record; do
    case "$record" in
      p<->) current_pid="${record#p}"; saw_process=1 ;;
      aw|au) [[ -z "$current_pid" || "$current_pid" == "$$" ]] || SDK_ARCHIVE_WRITERS+=("$current_pid") ;;
    esac
  done < "$LOG_FILE.sdk-writers"
  SDK_ARCHIVE_WRITERS=("${(@u)SDK_ARCHIVE_WRITERS}")
  # 非空诊断却没有进程记录，不能把查询失败当成“无人写入”。
  (( saw_process )) || [[ ! -s "$LOG_FILE.sdk-writers" ]] || return 2
  return 0
}
# 等待旧下载释放同一缓存，避免新入口与超时遗留进程同时写zip。
wait_for_sdk_download_writers() {
  setopt LOCAL_OPTIONS LOCAL_TRAPS
  local sdk="${${FLUTTER_BIN:A}:h:h}" archive="" result=0 sdk_wait_cancel=0
  sdk_dart_download_arch
  archive="$sdk/bin/cache/dart-sdk-darwin-$REPLY.zip"
  trap 'sdk_wait_cancel=130; leave_terminal' INT
  trap 'sdk_wait_cancel=143; leave_terminal' TERM
  trap 'sdk_wait_cancel=129; leave_terminal' HUP
  while true; do
    result=0
    sdk_archive_writers "$archive" || result=$?
    (( sdk_wait_cancel == 0 )) || return "$sdk_wait_cancel"
    case "$result" in 129|130|131|137|143) return "$result" ;; esac
    if (( result == 0 && ${#SDK_ARCHIVE_WRITERS} == 0 )); then return 0; fi
    if (( result == 0 )); then
      log "⚠ 等待同一SDK已有下载释放缓存；写入PID：${(j:, :)SDK_ARCHIVE_WRITERS}；缓存：$archive"
    else
      log "⚠ 暂不能核对SDK缓存写入者（$result）；继续等待：$archive"
    fi
    log '➤ 2秒后自动复检；Ctrl+C结束当前等待入口。'
    /bin/sleep 2 &
    QUERY_PID=$!
    wait "$QUERY_PID" || result=$?
    QUERY_PID=""
    (( sdk_wait_cancel == 0 )) || return "$sdk_wait_cancel"
  done
}

# 下载开始前标明声明、已解析的SDK与目标组件，不执行Flutter/Dart进行探测。
show_sdk_download_context() {
  local line="" executable="$1" target="${2:-}" declared="" config="" sdk="${${1:A}:h:h}" git_tag="" git_revision="" physical_arm="" arch="" context=""
  if project_fvm_config; then
    config="$REPLY"
    declared="$(json_helper fvm-version "$config" 2>/dev/null)" || declared=""
  fi
  if [[ -e "$sdk/.git" ]] && /usr/bin/xcode-select -p >/dev/null 2>&1; then
    if run_bounded 5 "$LOG_FILE.sdk-git-tag" /usr/bin/env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_COMMON_DIR GIT_NO_LAZY_FETCH=1 GIT_TERMINAL_PROMPT=0 /usr/bin/git --no-optional-locks -c core.fsmonitor=false -C "$sdk" describe --tags --exact-match HEAD; then
      git_tag="$(<"$LOG_FILE.sdk-git-tag")"
    fi
    if run_bounded 5 "$LOG_FILE.sdk-git-head" /usr/bin/env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_COMMON_DIR GIT_NO_LAZY_FETCH=1 GIT_TERMINAL_PROMPT=0 /usr/bin/git --no-optional-locks -c core.fsmonitor=false -C "$sdk" rev-parse HEAD; then
      git_revision="$(<"$LOG_FILE.sdk-git-head")"
    fi
  fi
  sdk_dart_download_arch
  arch="$REPLY"
  context="$(json_helper sdk-download-context "$sdk" "$declared" "$git_tag" "$git_revision" "Darwin $arch" "${FLUTTER_PREBUILT_ENGINE_VERSION:-}" "$target")" || {
    log "⚠ 无法解析SDK下载上下文；SDK：$sdk；项目声明：${declared:-未解析}；Darwin $arch。"
    return 0
  }
  while IFS= read -r line; do log "$line"; done <<< "$context"
  SDK_VERSION_LABEL="项目声明 ${declared:-未解析}"
  [[ "$git_tag" =~ '^v?[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z._+-]+)?$' ]] && SDK_VERSION_LABEL="$git_tag"
  return 0
}

resolve_fvm_cli() {
  local candidate=""
  for candidate in "${JOBS_FVM_BIN:-}" "${commands[fvm]:-}" /opt/homebrew/bin/fvm /usr/local/bin/fvm \
    "$HOME/.pub-cache/bin/fvm" "$HOME/.local/bin/fvm"; do
    if [[ -n "$candidate" && -x "$candidate" && ! -d "$candidate" ]]; then
      REPLY="${candidate:A}"
      return 0
    fi
  done
  return 1
}

# SDK安装器返回0仍需确认实际Flutter入口存在；残缺获取继续重试。
install_project_fvm_sdk_once() {
  run_bounded 1800 "$LOG_FILE.fvminstall" "$fvm_bin" install "$version" || return $?
  [[ -x "$cached" ]] || { log "⚠ FVM安装返回成功但Flutter入口仍缺失：$cached"; return 1; }
}
# 项目 FVM SDK 就绪就直接返回；断链或缺失时补齐：本机缓存已有只重建链接，没有才下载。
prepare_project_fvm_sdk() {
  local link="$PROJECT_PATH/.fvm/flutter_sdk" config="" version="" fvm_bin="" answer="" cached="" bind_result=0
  if [[ -x "$link/bin/flutter" ]]; then
    REPLY="${link:A}/bin/flutter"
    return 0
  fi
  project_fvm_config || { log '⚠ 项目声明了 FVM，但既没有可用的 .fvm/flutter_sdk，也读不到版本声明。'; return 1; }
  config="$REPLY"
  version="$(json_helper fvm-version "$config")" || { log "⚠ 无法解析 FVM 版本声明：$config"; return 1; }
  resolve_fvm_cli || { log '⚠ 未找到 fvm；请先安装（brew install fvm）或设置 JOBS_FVM_BIN，再重新运行。'; return 1; }
  fvm_bin="$REPLY"
  jobs_flutter_fvm_runtime "FVM所需Dart运行时" "$LOG_FILE.fvm-runtime" "$fvm_bin" || return $?
  log "ℹ 项目声明 Flutter $version，但 .fvm/flutter_sdk 未就绪。"
  cached="$HOME/fvm/versions/$version/bin/flutter"
  if [[ -x "$cached" ]]; then
    log '➤ 本机 FVM 缓存已有该版本，将重建项目链接；不下载。'
  else
    log "➤ 本机 FVM 缓存没有该版本，将下载并初始化 Flutter $version（需要联网，可能几分钟）。"
  fi
  log '➤ 必需 SDK 自动补齐；下载失败持续重试，Ctrl+C 结束。'
  if [[ ! -x "$cached" ]]; then
    show_sdk_download_context "$cached" '项目声明SDK安装 / 初始化'
    log "▶ 下载并初始化 Flutter $version；FVM：$fvm_bin"
    log "完整下载日志：$LOG_FILE.fvminstall（下方实时显示工具原始进度）"
    RUN_BOUNDED_STREAM=1 JOBS_SDK_LOG_REPLACED=1 jobs_flutter_fvm_install "Flutter $version" "$LOG_FILE.fvminstall" "$fvm_bin" "$version" || {
      bind_result=$?
      log "✖ fvm install $version 失败或已取消，详情：$LOG_FILE.fvminstall"
      return "$bind_result"
    }
  fi
  # 只移除已失效的链接本身，避免FVM下载成功却反复碰到旧机器的断链。
  if [[ -L "$link" && ! -e "$link" ]]; then
    /bin/rm -f -- "$link" || return 1
  fi
  log "▶ 绑定项目 Flutter $version；完整日志：$LOG_FILE.fvmuse"
  RUN_BOUNDED_STREAM=1 JOBS_SDK_LOG_REPLACED=1 jobs_flutter_sdk_once "FVM绑定 Flutter $version" "$LOG_FILE.fvmuse" "${cached:h:h}" "$version" run_bounded 1800 "$LOG_FILE.fvmuse" "$fvm_bin" use "$version" --skip-pub-get --skip-setup \
    || bind_result=$?
  case "$bind_result" in 129|130|131|137|143) return "$bind_result" ;; esac
  (( bind_result == 0 )) || log "⚠ fvm use $version 未成功确认，详情：$LOG_FILE.fvmuse"
  # fvm 在声明版本已一致时可能只写配置、不重建链接，这里按本机缓存兜底。
  if [[ ! -x "$link/bin/flutter" && -x "$cached" ]]; then
    # 只清理失效的符号链接本身，不动真实 SDK 目录。
    if [[ -L "$link" ]] && ! /bin/rm -f -- "$link"; then
      log '⚠ 无法清理失效的 .fvm/flutter_sdk 链接。'
      return 1
    fi
    /bin/ln -s "${cached:h:h}" "$link" || { log '⚠ 无法重建 .fvm/flutter_sdk 链接。'; return 1; }
    log '➤ 已按本机 FVM 缓存重建 .fvm/flutter_sdk 链接。'
  fi
  [[ -x "$link/bin/flutter" ]] || { log "✖ fvm 执行后 .fvm/flutter_sdk 仍不可用：$link"; return 1; }
  REPLY="${link:A}/bin/flutter"
  log "✔ FVM SDK 已就绪：Flutter $version → $REPLY"
}

# 每次获取的原始输出追加归档；下一轮覆盖当前进度文件前保留已结束尝试。
acquire_device_discovery_sdk_once() {
  local output="$LOG_FILE.discovery-sdk" result=0
  run_bounded 1800 "$output" "$FLUTTER_BIN" precache --universal || result=$?
  print -r -- "━━ universal：$(/bin/date '+%Y-%m-%d %H:%M:%S')，退出码 $result ━━" >> "$output.attempts.log"
  [[ ! -f "$output" ]] || /bin/cat "$output" >> "$output.attempts.log"
  return "$result"
}

# devices 也会隐式下载公共制品，先以可见进度完成，避免被设备查询的短超时反复中止。
prepare_device_discovery_sdk() {
  local output="$LOG_FILE.discovery-sdk" sdk="${FLUTTER_BIN:A:h:h}"
  if [[ "$(json_helper universal-ready "$sdk" 2>/dev/null)" == true ]]; then
    log '✓ Flutter 设备发现所需公共SDK缓存已就绪，复用本地组件。'
    return 0
  fi
  if (( ${+functions[show_sdk_download_context]} )); then
    show_sdk_download_context "$FLUTTER_BIN" '设备发现公共组件（universal）'
  fi
  log "▶ 补齐 Flutter 设备发现公共SDK组件；实时显示进度，失败自动重试，Ctrl+C结束；完整日志：$output"
  RUN_BOUNDED_STREAM=1 JOBS_SDK_LOG_REPLACED=1 JOBS_FLUTTER_ROUTE_MODE=platform jobs_flutter_sdk_retry \
    'Flutter 设备发现公共SDK' "$output" "$sdk" "" acquire_device_discovery_sdk_once
}

find_flutter() {
  local candidate="" output="$LOG_FILE.version" result=0
  if [[ -e "$PROJECT_PATH/.fvmrc" || -e "$PROJECT_PATH/.fvm/fvm_config.json" || -L "$PROJECT_PATH/.fvm/flutter_sdk" ]]; then
    prepare_project_fvm_sdk || {
      result=$?
      case "$result" in 129|130|131|137|143) return "$result" ;; esac
      die '项目 FVM SDK 未就绪且未自动补齐，详见日志；可手动运行 fvm use 后重试。'
    }
    candidate="$REPLY"
  else
    die '项目未绑定 FVM；不会回退全局 Flutter。'
  fi
  [[ -n "$candidate" && -x "$candidate" ]] || die '未找到 Flutter；先配置终端 PATH 或项目 FVM SDK。'
  FLUTTER_BIN="${candidate:A}"
  show_sdk_download_context "$FLUTTER_BIN"
  wait_for_sdk_download_writers || return $?
  log "▶ 检查 Flutter SDK（首次执行可能下载组件）；完整日志：$output"
  RUN_BOUNDED_STREAM=1 JOBS_SDK_LOG_REPLACED=1 jobs_flutter_sdk_retry "Flutter $SDK_VERSION_LABEL / Dart首次补齐" "$output" "${FLUTTER_BIN:A:h:h}" "" run_bounded 1800 "$output" "$FLUTTER_BIN" --version || {
    result=$?
    case "$result" in 129|130|131|137|143) return "$result" ;; esac
    die "Flutter 体检失败：$output"
  }
  prepare_device_discovery_sdk || return $?
  log "Flutter：$FLUTTER_BIN"
}

# fzf 只用于终端交互；找不到就保持编号输入，不阻断运行。
resolve_fzf() {
  local candidate=""
  for candidate in "${commands[fzf]:-}" /opt/homebrew/bin/fzf /usr/local/bin/fzf "$HOME/.fzf/bin/fzf"; do
    if [[ -n "$candidate" && -x "$candidate" && ! -d "$candidate" ]]; then
      FZF_BIN="${candidate:A}"
      return 0
    fi
  done
  FZF_BIN=""
  return 1
}

# JOBS_FLUTTER_RUNNER_FZF：0 关闭；always 忽略终端检测（供测试注入）。
fzf_ready() {
  local mode="${JOBS_FLUTTER_RUNNER_FZF:-auto}"
  [[ "$mode" != 0 ]] || return 1
  if [[ "$mode" != always ]]; then
    [[ -t 0 && -t 1 ]] || return 1
  fi
  if [[ -z "$FZF_BIN" ]]; then
    resolve_fzf || return 1
  fi
  [[ -n "$FZF_BIN" ]] || return 1
}

# 每行是 "id\tdisplay"：只展示 display，输出整行以便回取原始 id。
fzf_pick_row() {
  local heading="$1" row="" answer="" pick_status=0
  local -a lines=()
  for row in "${ROWS[@]}"; do
    if [[ "$row" == *$'\t'* ]]; then
      lines+=("$row")
    else
      lines+=("$row"$'\t'"$row")
    fi
  done
  # 清空个人选项；使用备用屏幕，避免内嵌 height 模式在终端重绘后留下两份菜单。
  answer="$(printf '%s\n' "${lines[@]}" | /usr/bin/env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_OPTS_FILE \
    "$FZF_BIN" --no-multi --cycle --layout=reverse \
    --no-height --border \
    --delimiter=$'\t' --with-nth=2.. \
    --prompt="${heading}› " \
    --header='↑/↓ 选择；输入即筛选；Esc 取消' 2>> "$LOG_FILE")"
  pick_status=$?
  # 退出码 2 是参数不兼容等运行错误，去掉装饰类参数再试一次；130 是用户取消，不再重试。
  if (( pick_status == 2 )); then
    answer="$(printf '%s\n' "${lines[@]}" | /usr/bin/env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_OPTS_FILE \
      "$FZF_BIN" --no-multi --layout=reverse --no-height \
      --delimiter=$'\t' --with-nth=2.. --prompt="${heading}› " 2>> "$LOG_FILE")"
    pick_status=$?
  fi
  (( pick_status == 0 )) || return 1
  [[ -n "$answer" ]] || return 1
  REPLY="${answer%%$'\t'*}"
  return 0
}

select_row() {
  local heading="$1" answer="" row="" index=1
  (( ${#ROWS} > 0 )) || return 1
  if fzf_ready; then
    log "$heading"
    fzf_pick_row "$heading" || return 1
    return 0
  fi
  log "$heading"
  for row in "${ROWS[@]}"; do
    log "  ${index}、${row#*$'\t'}"
    (( index++ ))
  done
  while true; do
    IFS= read -r 'answer?输入编号，直接回车取消：' || return 1
    [[ -n "$answer" ]] || return 1
    if [[ "$answer" == <-> ]] && (( answer >= 1 && answer <= ${#ROWS} )); then
      REPLY="${ROWS[$answer]%%$'\t'*}"
      return 0
    fi
    log '⚠ 编号无效，请重新输入。'
  done
}

# 设备枚举使用短超时；公共SDK下载已在选择设备前独立完成。
refresh_devices() {
  local seconds="${1:-30}" output="$LOG_FILE.devices.json" table=""
  log 'ℹ 正在读取 Flutter 设备列表…'
  if run_bounded "$seconds" "$output" "$FLUTTER_BIN" devices --machine --device-timeout 10; then
    table="$(json_helper devices "$output" "$PROJECT_PATH")" || { log "⚠ 无法解析设备响应：$output"; ROWS=(); return 1; }
    ROWS=("${(@f)table}")
    [[ -n "$table" ]] || ROWS=()
  else
    ROWS=()
    log "⚠ 设备查询失败，可重新加载或选择 iOS 模拟器；详情：$output"
    if [[ -s "$output" ]]; then
      log '➤ 最近输出：'
      /usr/bin/tail -n 5 "$output" | while IFS= read -r line; do log "  $line"; done
    fi
    return 1
  fi
}

read_simulator_inventory() {
  /usr/bin/xcode-select -p >/dev/null 2>&1 || die '未选择 Xcode 开发目录，请先完成 Xcode 安装与配置。'
  run_bounded 30 "$LOG_FILE.simulators.json" /usr/bin/xcrun simctl list --json || die 'simctl 不可用，请确认当前开发目录是完整 Xcode，且已接受许可。'
}

# 只在明确不兼容且用户精确输入 r 后才重选，一路回车不会再反复弹出型号 / 系统列表。
confirm_simulator_reselection() {
  local answer=""
  if IFS= read -r 'answer?输入 r 重新选择型号和系统；直接回车或其它输入停止：' && [[ "$answer" == [rR] ]]; then
    return 0
  fi
  log '➤ 已停止，未重复选择或再次创建模拟器。'
  return 1
}

# 与独立初始化脚本同款命名：型号名@时间-进程号；创建前刷新已有设备，撞名追加“ (2)”。
simulator_name_for() {
  local type_name="$1" base="" name="" output="$LOG_FILE.devices.json"
  [[ -n "$type_name" ]] || return 1
  base="${type_name}@$(/bin/date '+%Y.%m.%d %H:%M:%S')-$$"
  run_bounded 30 "$output" /usr/bin/xcrun simctl list devices --json || return 1
  name="$(json_helper unique-name "$output" "$base")" || return 1
  [[ -n "$name" ]] || return 1
  REPLY="$name"
}

# 型号与系统分别列出：先按“有无可搭配系统”推荐型号，再只列匹配该型号的系统。
create_simulator() {
  local table="" type_id="" runtime_id="" type_name="" runtime_name="" simulator_name=""
  local simulator_id="" answer="" row="" output="$LOG_FILE.create" create_status=0
  while true; do
    table="$(json_helper preferred-types "$LOG_FILE.simulators.json" "$(/usr/bin/uname -m)")" || die '无法解析模拟器型号。'
    ROWS=("${(@f)table}")
    [[ -n "$table" ]] || die 'Xcode 没有可用 iPhone 型号。'
    select_row '选择模拟器设备型号：' || return 1
    type_id="$REPLY"
    type_name=""
    for row in "${ROWS[@]}"; do
      if [[ "${row%%$'\t'*}" == "$type_id" ]]; then
        # 展示列的“（本机无可搭配系统）”标注只用于选择，不进入设备名。
        type_name="${row#*$'\t'}"
        type_name="${type_name%%'（本机无可搭配系统）'}"
        break
      fi
    done
    [[ -n "$type_name" ]] || type_name="$type_id"
    table="$(json_helper runtimes "$LOG_FILE.simulators.json")" || die '无法解析 iOS Runtime。'
    [[ -n "$table" ]] || die '没有可用的 iOS Runtime，请在 Xcode → Settings → Components（旧版 Platforms）安装 iOS，再重新运行。'
    table="$(json_helper compatible-runtimes "$LOG_FILE.simulators.json" "$(/usr/bin/uname -m)" "$type_id")" || die '无法匹配所选型号的 iOS 系统。'
    ROWS=("${(@f)table}")
    if [[ -z "$table" ]]; then
      log '✖ 所选型号没有可搭配的已安装 iOS 系统；请在 Xcode 安装对应 Runtime，或重新选择型号。'
      confirm_simulator_reselection || return 1
      continue
    fi
    select_row '选择 iOS 系统版本（已按所选型号匹配排序）：' || return 1
    runtime_id="$REPLY"
    runtime_name=""
    for row in "${ROWS[@]}"; do
      if [[ "${row%%$'\t'*}" == "$runtime_id" ]]; then
        runtime_name="${row#*$'\t'}"
        break
      fi
    done
    simulator_name_for "$type_name" || die '无法确认唯一的模拟器名称。'
    simulator_name="$REPLY"
    log "将创建模拟器：$type_name / $runtime_name"
    log "➤ 新名称：$simulator_name"
    IFS= read -r 'answer?回车创建并启动；非空取消：' || return 1
    [[ -z "$answer" ]] || return 1
    create_status=0
    run_bounded 45 "$output" /usr/bin/xcrun simctl create "$simulator_name" "$type_id" "$runtime_id" || create_status=$?
    simulator_id="$(/bin/cat "$output" 2>/dev/null)"
    if (( create_status == 0 )); then
      if [[ ! "$simulator_id" =~ '^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$' ]]; then
        log "✖ simctl 没有返回有效 UDID：$output"
        log '➤ 已停止，未自动重试；请检查 Simulator 设备列表。'
        return 1
      fi
      REPLY="$simulator_id"
      return 0
    fi
    # 只有 Xcode 明确写出 Incompatible device 才算组合不受支持；
    # 泛化的 Unable to create a device for device type 可能来自权限或状态问题，不自动重选。
    if (( create_status != 124 )) && [[ "$simulator_id" == *'Incompatible device'* ]]; then
      log "⚠ 当前型号 / 系统组合不受支持：$simulator_id"
      log '➤ 未删除任何既有模拟器，设备列表保持不变。'
      confirm_simulator_reselection || return 1
      continue
    fi
    log "✖ 创建失败（退出码 ${create_status}），未自动重试，未删除任何既有模拟器：$output"
    return 1
  done
}

# Xcode 27 起模拟器界面改名为 DeviceHub.app 并移到 Xcode.app/Contents/Applications；
# 旧版为 Xcode.app/Contents/Developer/Applications/Simulator.app，两种布局都要认。
simulator_interface_path() {
  local developer="$1" candidate=""
  for candidate in "$developer/Applications/Simulator.app" "${developer:h}/Applications/Simulator.app" \
    "${developer:h}/Applications/DeviceHub.app"; do
    [[ -d "$candidate" ]] || continue
    REPLY="$candidate"
    return 0
  done
  return 1
}

simulator_interface_app() {
  local simctl_path=""
  simctl_path="$(/usr/bin/xcrun --find simctl 2>/dev/null)" || return 1
  [[ "$simctl_path" == */usr/bin/simctl ]] || return 1
  simulator_interface_path "${simctl_path%/usr/bin/simctl}"
}

# 设备已启动，界面打不开只提示，不终止本次运行。
reveal_simulator_interface() {
  local simulator_id="$1" app=""
  if ! simulator_interface_app; then
    log '⚠ 当前 Xcode 没有 Simulator / Device Hub，跳过打开界面；设备已启动，可在 Xcode → Devices and Simulators 查看。'
    return 1
  fi
  app="$REPLY"
  if [[ "${app:t}" == 'Simulator.app' ]]; then
    /usr/bin/open -a "$app" --args -CurrentDeviceUDID "$simulator_id" || {
      log "⚠ 无法打开模拟器界面：$app"
      return 1
    }
    log "➤ 已打开模拟器界面：$app"
    return 0
  fi
  /usr/bin/open -a "$app" || {
    log "⚠ 无法打开模拟器界面：$app"
    return 1
  }
  log "➤ 已打开 Device Hub：$app"
  log "➤ 请在 Device Hub 按设备名选中该模拟器（$simulator_id）。"
}

select_ios_simulator() {
  local table="" simulator_id="" row="" attempt=0
  read_simulator_inventory
  table="$(json_helper simulators "$LOG_FILE.simulators.json")" || die '无法解析模拟器列表。'
  ROWS=("${(@f)table}")
  [[ -n "$table" ]] || ROWS=()
  if (( ${#ROWS} > 0 )); then
    ROWS+=($'create\t创建新的 iOS 模拟器')
    select_row '选择 iOS 模拟器：' || return 1
    simulator_id="$REPLY"
  else
    log 'ℹ 尚无可用 iOS 模拟器，进入内置初始化流程。'
    simulator_id=create
  fi
  if [[ "$simulator_id" == create ]]; then
    create_simulator || return 1
    simulator_id="$REPLY"
  fi
  /usr/bin/xcrun simctl boot "$simulator_id" > "$LOG_FILE.boot" 2>&1 || {
    /usr/bin/xcrun simctl list devices booted | /usr/bin/grep -Fq "$simulator_id" || die "模拟器启动失败：$LOG_FILE.boot"
  }
  log "ℹ 等待所选模拟器就绪：$simulator_id"
  run_bounded 180 "$LOG_FILE.bootstatus" /usr/bin/xcrun simctl bootstatus "$simulator_id" -b || die "模拟器未在 180 秒内启动完成：$LOG_FILE.bootstatus"
  reveal_simulator_interface "$simulator_id" || log 'ℹ 界面未打开不影响运行；Flutter 仍会使用已启动的模拟器。'
  # 模拟器启动后等待Flutter设备发现刷新；公共制品已在前置流程准备。
  wait_for_simulator_recognition "$simulator_id"
}

# 新建模拟器后等设备出现在 Flutter 列表：首次 120 秒、第二次 60 秒、之后 30 秒，共 4 次。
wait_for_simulator_recognition() {
  local simulator_id="$1" attempt=0 timeout=30
  for attempt in 1 2 3 4; do
    if (( attempt == 1 )); then
      timeout=120
    elif (( attempt == 2 )); then
      timeout=60
    else
      timeout=30
    fi
    refresh_devices "$timeout" || { log "ℹ 第 ${attempt} 次读取设备列表失败，将继续重试。"; /bin/sleep 2; continue; }
    for row in "${ROWS[@]}"; do
      if [[ "${(L)${row%%$'\t'*}}" == "${(L)simulator_id}" ]]; then
        DEVICE_ID="${row%%$'\t'*}"
        return 0
      fi
    done
    log 'ℹ Flutter 尚未发现所选模拟器，正在重新加载…'
    /bin/sleep 3
  done
  die '模拟器已启动，但 Flutter 尚未识别；保留模拟器，请检查 flutter doctor 后重试。'
}

# Android SDK 原生命令列出 AVD；单独 launchd 作业防止模拟器跟随终端断连。
start_android_emulator() {
  local emulator="" candidate="" output="$LOG_FILE.avds" avd="" digest="" avd_session="" avd_label=""
  local -a candidates=("${ANDROID_HOME:-}/emulator/emulator" "${ANDROID_SDK_ROOT:-}/emulator/emulator"
    "$HOME/Library/Android/sdk/emulator/emulator" "${commands[emulator]:-}")
  for candidate in "${candidates[@]}"; do
    if [[ -n "$candidate" && -x "$candidate" && ! -d "$candidate" ]]; then
      emulator="${candidate:A}"
      break
    fi
  done
  [[ -n "$emulator" ]] || { log '⚠ 未找到 Android SDK emulator；设置 ANDROID_HOME / ANDROID_SDK_ROOT，或先从 Android Studio 启动模拟器。'; return 1; }
  run_bounded 30 "$output" "$emulator" -list-avds || { log "⚠ 无法读取 Android AVD：$output"; return 1; }
  ROWS=()
  while IFS= read -r avd; do
    avd="${avd%$'\r'}"
    [[ "$avd" =~ '^[A-Za-z0-9_.-]+$' ]] && ROWS+=("${avd}"$'\t'"${avd}")
  done < "$output"
  (( ${#ROWS} > 0 )) || { log 'ℹ 尚无 Android AVD，请先在 Android Studio Device Manager 创建，然后重新加载。'; return 1; }
  select_row '选择已配置的 Android AVD：' || return 1
  avd="$REPLY"
  digest="$(printf '%s\0%s' "$emulator" "$avd" | /usr/bin/shasum -a 256)"
  digest="${digest%% *}"
  avd_label="com.jobs.flutterrunner.avd.$digest"
  avd_session="$STATE_ROOT/android-$digest"
  [[ ! -L "$STATE_ROOT" && ! -L "$avd_session" ]] || die '模拟器会话目录不能是符号链接。'
  /bin/mkdir -p "$avd_session" || die '无法创建模拟器会话目录。'
  if /bin/launchctl print "gui/$UID/$avd_label" 2>/dev/null | /usr/bin/grep -Fq 'state = running'; then
    log 'ℹ 该 AVD 已由后台启动，请在设备列表选择对应设备。'
    return
  fi
  /bin/launchctl bootout "gui/$UID/$avd_label" >/dev/null 2>&1
  json_helper emulator-plist "$avd_session" "$avd_label" "$emulator" "$avd" >/dev/null || die '无法生成 Android 模拟器后台配置。'
  /bin/launchctl bootstrap "gui/$UID" "$avd_session/job.plist" >> "$LOG_FILE" 2>&1 || { log "⚠ AVD 启动失败，详情：$LOG_FILE"; return 1; }
  log "✔ 已请求后台启动 AVD：$avd；就绪后在设备列表选择，尚未出现可重新加载。"
  log "模拟器日志：$avd_session/emulator.log"
}

choose_device() {
  while true; do
    refresh_devices
    (( ${#ROWS} > 0 )) || log 'ℹ 暂无当前项目可运行的设备；连接手机、启动模拟器后可重新加载。'
    [[ ! -d "$PROJECT_PATH/ios" ]] || ROWS+=($'ios\tiOS 模拟器（启动已有 / 缺失时初始化）')
    [[ ! -d "$PROJECT_PATH/android" ]] || ROWS+=($'android-avd\t启动已有 Android 模拟器')
    ROWS+=($'refresh\t重新加载设备列表')
    select_row '选择 Flutter 运行设备：' || exit 0
    case "$REPLY" in
      refresh) continue ;;
      ios) select_ios_simulator && return ;;
      android-avd) start_android_emulator ;;
      *) DEVICE_ID="$REPLY"; return ;;
    esac
  done
}

# 构建前补齐目标引擎，失败只重试资源获取，不反复构建或启动App。
prepare_target_sdk_resources() {
  local platform="" result=0 output="$LOG_FILE.precache"
  platform="$(json_helper precache-platform "$LOG_FILE.devices.json" "$DEVICE_ID")" || return $?
  [[ -n "$platform" ]] || { log '➤ 自定义设备未声明可识别的Flutter平台，无法选择对应预缓存目标。'; return 0; }
  if [[ "$platform" == ohos ]]; then
    RUN_BOUNDED_STREAM=1 run_bounded 120 "$LOG_FILE.precache-help" "$FLUTTER_BIN" precache --help || return $?
    /usr/bin/grep -Fq -- --ohos "$LOG_FILE.precache-help" || { log '✖ 当前鸿蒙Flutter没有precache --ohos，无法可靠准备目标资源，请使用支持此命令的适配SDK。'; return 1; }
  fi
  show_sdk_download_context "$FLUTTER_BIN" "$platform 平台资源预缓存"
  log "▶ 准备Flutter $platform 平台SDK资源；失败自动重试，Ctrl+C结束。"
  RUN_BOUNDED_STREAM=1 JOBS_SDK_LOG_REPLACED=1 JOBS_FLUTTER_ROUTE_MODE=platform jobs_flutter_sdk_retry "Flutter $platform 平台资源" "$output" "${FLUTTER_BIN:A:h:h}" "" run_bounded 1800 "$output" "$FLUTTER_BIN" precache "--$platform"
}

session_live() {
  [[ ! -f "$SESSION_DIR/exitcode" ]] || return 1
  /bin/launchctl print "gui/$UID/$JOB_LABEL" 2>/dev/null | /usr/bin/grep -Eq '^[[:space:]]*pid = [1-9][0-9]*'
}

prepare_session() {
  local digest="" tick=0
  digest="$(printf '%s\0%s' "$PROJECT_PATH" "$DEVICE_ID" | /usr/bin/shasum -a 256)"
  digest="${digest%% *}"
  JOB_LABEL="com.jobs.flutterrunner.$digest"
  SESSION_DIR="$STATE_ROOT/$digest"
  [[ ! -L "$STATE_ROOT" && ! -L "$SESSION_DIR" ]] || die '后台会话目录不能是符号链接。'
  /bin/mkdir -p "$SESSION_DIR" || die '无法创建后台会话目录。'
  if session_live; then
    log 'ℹ 当前项目 / 设备已经在运行，连接已有日志。'
    return
  fi
  START_LOCK="$SESSION_DIR/start.lock"
  [[ ! -L "$START_LOCK" ]] || die '任务锁不能是符号链接。'
  : >> "$START_LOCK"
  zmodload zsh/system || die '系统 zsh 缺少文件锁模块。'
  zsystem flock -t 0 -f LOCK_FD "$START_LOCK" || die '另一个终端正在启动该任务；稍后重新右键。'
  if session_live; then
    zsystem flock -u "$LOCK_FD"
    LOCK_FD=""
    return
  fi
  /bin/launchctl bootout "gui/$UID/$JOB_LABEL" >/dev/null 2>&1
  # 上一次运行保留为独立日志，重启不会擦掉失败现场。
  if [[ -e "$SESSION_DIR/run.log" ]]; then
    /bin/mv "$SESSION_DIR/run.log" "$SESSION_DIR/run.$(/bin/date '+%Y%m%d-%H%M%S').$$.log" || die '无法归档已有日志。'
  fi
  /bin/rm -f "$SESSION_DIR/exitcode" "$SESSION_DIR/control.fifo"
  /bin/cp "$SCRIPT_PATH" "$SESSION_DIR/RunFlutterProject.zsh" || die '无法保存独立后台脚本。'
  /bin/cp "$HELPER" "$SESSION_DIR/FlutterRunner.jxa" || die '无法保存后台解析脚本。'
  /usr/bin/mkfifo "$SESSION_DIR/control.fifo" || die '无法创建后台控制通道。'
  : > "$SESSION_DIR/run.log"
  json_helper plist "$SESSION_DIR" "$JOB_LABEL" "$SESSION_DIR/RunFlutterProject.zsh" "$PROJECT_PATH" "$FLUTTER_BIN" "$DEVICE_ID" >/dev/null || die '无法生成 launchd 会话配置。'
  /usr/bin/plutil -lint "$SESSION_DIR/job.plist" >> "$LOG_FILE" 2>&1 || die '后台任务配置无效。'
  /bin/launchctl bootstrap "gui/$UID" "$SESSION_DIR/job.plist" >> "$LOG_FILE" 2>&1 || die 'launchd 无法托管任务，请在当前桌面登录会话重新运行，详见操作日志。'
  for tick in 1 2 3 4 5 6 7 8 9 10; do
    session_live && break
    [[ ! -f "$SESSION_DIR/exitcode" ]] || break
    /bin/sleep 0.2
  done
  zsystem flock -u "$LOCK_FD"
  LOCK_FD=""
  if ! session_live && [[ ! -f "$SESSION_DIR/exitcode" ]]; then
    die "后台任务未成功启动，请检查会话日志：$SESSION_DIR/run.log"
  fi
  log '✔ 后台任务已提交；构建或启动结果请查看下方日志。'
}

send_control() {
  local mode="$1" message=""
  session_live || { log '⚠ 后台任务已结束。'; return 1; }
  message="$(json_helper command "$SESSION_DIR/run.log" "$mode" 2>> "$LOG_FILE")" || { log '⚠ Flutter 尚未提供 appId，稍后重试；构建期间可用 s 停止。'; return 1; }
  # 读写模式打开 FIFO 不会因任务恰好退出而永久等待读端。
  [[ -p "$SESSION_DIR/control.fifo" ]] || return 1
  ( exec 8<>"$SESSION_DIR/control.fifo"; print -r -- "$message" >&8 )
}

stop_session() {
  local tick=0
  send_control stop
  for tick in 1 2 3 4 5; do
    session_live || break
    /bin/sleep 1
  done
  if /bin/launchctl print "gui/$UID/$JOB_LABEL" >/dev/null 2>&1; then
    /bin/launchctl bootout "gui/$UID/$JOB_LABEL" >> "$LOG_FILE" 2>&1 || { log '✖ 无法停止 launchd 任务，请检查操作日志。'; return 1; }
  fi
  log '✔ 已停止该项目 / 设备的后台运行。'
}

watch_session() {
  local answer=""
  log ''
  log '━━━━━━━━━━ Flutter 构建与运行 ━━━━━━━━━━'
  log "完整原始日志：$SESSION_DIR/run.log"
  log '控制：输入 r 热重载 / R 热重启 / s 停止 / d 离开，再按回车。'
  log '关闭终端或 Ctrl+C 只离开；[警告] 不等于失败，以 [成功] / [错误] 为准。'
  log '──────────────────────────────────────'
  /usr/bin/osascript -l JavaScript "$HELPER" watch-log "$SESSION_DIR/run.log" "$SESSION_DIR/exitcode" &
  TAIL_PID=$!
  while true; do
    # 不输出悬挂的输入提示符，避免异步日志接在“运行控制 >”后面。
    IFS= read -r answer || return 0
    case "$answer" in
      r) send_control reload ;;
      R) send_control restart ;;
      s) stop_session && return ;;
      d) log '后台任务继续运行；再次右键并选择同一设备可重看日志及停止。'; return ;;
      *)
        if session_live; then
          log 'ℹ 后台任务仍在运行。'
        else
          log "ℹ 后台任务已结束，退出码：$(/bin/cat "$SESSION_DIR/exitcode" 2>/dev/null || print unknown)"
          return
        fi
        ;;
    esac
  done
}

# 由 launchd 启动的独立入口；stdin 留在 FIFO，不继承终端的 EOF / HUP。
run_worker() {
  local session="$1" project="$2" flutter="$3" device="$4" result=0 child_pid=""
  setopt NO_NOMATCH PIPE_FAIL
  umask 077
  [[ -d "$session" && ! -L "$session" ]] || return 64
  [[ -p "$session/control.fifo" && -x "$flutter" ]] || { print 64 > "$session/exitcode"; return 64; }
  SCRIPT_DIR="${session:A}"
  HELPER="$SCRIPT_DIR/FlutterRunner.jxa"
  [[ "$(json_helper validate "$project")" == true ]] || { print '项目身份已变化，停止运行。'; print 65 > "$session/exitcode"; return 65; }
  cd "$project" || { print 66 > "$session/exitcode"; return 66; }
  exec 9<>"$session/control.fifo"
  trap '[[ -z "$child_pid" ]] || kill -TERM "$child_pid" 2>/dev/null; print 143 > "$session/exitcode"; exit 143' TERM INT
  print -r -- "Flutter 后台运行：$project / $device"
  # fd 9 只负责保持 FIFO 打开；Dart 的异步 stdin 必须另用只读描述符。
  # macOS 下直接继承 O_RDWR FIFO 会让 stdin.listen 收不到热重载 / 停止请求。
  "$flutter" run --machine -d "$device" < "$session/control.fifo" &
  child_pid=$!
  wait "$child_pid" || result=$?
  print -r -- "Flutter 已退出：$result"
  print -r -- "$result" > "$session/exitcode"
  return "$result"
}

main() {
  if [[ "${1:-}" == --worker ]]; then
    (( $# == 5 )) || return 64
    run_worker "$2" "$3" "$4" "$5"
    return $?
  fi
  show_script_intro_and_wait
  initialize_runtime
  trap 'leave_terminal' EXIT
  trap 'exit 0' HUP INT TERM
  read_project "$@"
  find_flutter || return $?
  choose_device
  prepare_target_sdk_resources || return $?
  prepare_session
  watch_session
}

main "$@"
