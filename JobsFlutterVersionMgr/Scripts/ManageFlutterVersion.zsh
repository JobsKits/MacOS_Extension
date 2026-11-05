#!/bin/zsh
# 脚本自述：
# - 脚本名称：ManageFlutterVersion.zsh。
# - 核心用途：只对指定 Flutter 项目，通过 fzf 选择历史或最新版本，再由 FVM 安装 / 切换。
# - 影响范围：经确认后准备缺失工具、FVM 缓存、目标 .fvmrc / .fvm 及 FVM 管理的 IDE / 忽略配置。
# - 运行提示：先阅读自述并回车；依赖安装另行确认，最终回车执行版本安装 / 切换，非空输入取消；Ctrl+C 随时取消。

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
    if (args[0] === 'current') {
        var config = json(args[1]);
        if (!config || Array.isArray(config) || typeof config !== 'object') throw Error('FVM 配置不是对象');
        if (config.flutterUrl && config.flutterUrl !== 'https://github.com/flutter/flutter.git') throw Error('自定义 flutterUrl 与官方版本列表不兼容');
        if (config.cachePath && (!clean(config.cachePath).startsWith('/'))) throw Error('cachePath 必须是绝对路径');
        return clean(config.flutter || config.flutterSdkVersion || '未配置');
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
# 机器输出单独保存供解析，终端同时显示首次 SDK 初始化与下载进度。
fm_capture_flutter_version() {
    local -a results
    "$FM_FVM" flutter --version --machine 2> >(/usr/bin/tee -a "$LOG_FILE" >&2) | /usr/bin/tee "$FM_RUN_DIR/flutter-machine.json"
    results=("${pipestatus[@]}")
    (( results[1] == 0 )) || return "${results[1]}"
    return "${results[2]}"
}
# 必需依赖采用现有终端承接规则：回车确认准备，任意内容取消整个流程。
fm_confirm_dependency() {
    local answer=""
    fm_log "⚠ $1"
    IFS= read -r 'answer?👉 按回车确认安装 / 修复该必需组件；输入任意内容后回车取消：' || exit 1
    if [[ -n "$answer" ]]; then
        fm_log 'ℹ 已取消依赖准备，未安装 / 切换 Flutter 版本。'
        exit 0
    fi
}
# 拒绝 FVM 将直接写入的配置链接；SDK 链接本身属于正常 FVM 结构。
fm_check_project_boundaries() {
    local item=""
    for item in .fvmrc .fvm .gitignore .vscode .vscode/settings.json .fvm/fvm_config.json .fvm/version .fvm/release .fvm/versions; do
        [[ ! -L "$FM_PROJECT/$item" ]] || fm_stop "项目配置是符号链接，停止以免写到其它位置：$item"
    done
    for item in "$FM_PROJECT"/*.code-workspace(N); do
        [[ ! -L "$item" ]] || fm_stop "workspace 配置是符号链接：$item"
    done
    [[ ! -e "$FM_PROJECT/.fvm" || -d "$FM_PROJECT/.fvm" ]] || fm_stop '.fvm 已存在但不是目录'
    if [[ -e "$FM_PROJECT/.fvmrc" ]]; then
        FM_CURRENT="$(fm_data current "$FM_PROJECT/.fvmrc" 2>> "$LOG_FILE")" || fm_stop '无法读取 .fvmrc，或自定义 Flutter 仓库 / cachePath 与本入口不兼容'
    elif [[ -e "$FM_PROJECT/.fvm/fvm_config.json" ]]; then
        FM_CURRENT="$(fm_data current "$FM_PROJECT/.fvm/fvm_config.json" 2>> "$LOG_FILE")" || fm_stop '无法读取旧版 FVM 配置'
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
        /bin/cp -- "$FM_ORIGINAL_CONFIG" "$FM_RUN_DIR/inspection/.fvmrc" || fm_stop '无法复制目标配置供只读体检'
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
# 验证必要系统工具；CLT由Apple安装器处理，持续复检后再进入下游。
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
        fm_log '➤ 自动打开Apple官方CLT安装界面；安装许可由本人处理。脚本等待工具就绪后自动继续，Ctrl+C结束。'
        fm_run_logged /usr/bin/xcode-select --install || fm_log '⚠ 未启动新安装，请检查已有安装窗口或完整Xcode首次配置；仍继续等待工具就绪。'
        fm_log 'ℹ Apple安装器的网络请求由系统管理；若其下载失败请在系统界面重试。本脚本不代签许可、不修改softwareupdate设置或升级系统。'
        while true; do
            developer="$(/usr/bin/xcode-select -p 2>> "$LOG_FILE")"
            clang="$(/usr/bin/xcrun --find clang 2>> "$LOG_FILE")"
            [[ -d "$developer" && -x "$clang" ]] && "$clang" --version >> "$LOG_FILE" 2>&1 && break
            fm_log '➤ Apple CLT尚未就绪，10秒后自动复检；完成安装后无需重开本脚本。'
            /bin/sleep 10 || return 130
        done
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
        fm_run_logged "$FM_CURL" --fail --location --proto '=https' --connect-timeout 10 --max-time 120 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer" || fm_stop '获取官方 Homebrew 安装器失败'
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
        fm_run_logged "$FM_GIT" -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 clone --progress --depth 1 --branch "$tag" --single-branch https://github.com/Homebrew/brew.git "$stage/brew" || fm_stop "用户 Homebrew 克隆失败；保留诊断目录：$stage"
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
    jobs_flutter_fvm_runtime "FVM所需Dart运行时" "$LOG_FILE" "$candidate" || return $?
    "$candidate" --version >> "$LOG_FILE" 2>&1 || return 1
    "$candidate" api context --help >> "$LOG_FILE" 2>&1 || return 1
    "$candidate" api list --help >> "$LOG_FILE" 2>&1 || return 1
    help="$("$candidate" use --help 2>> "$LOG_FILE")" || return 1
    [[ "$help" == *--skip-pub-get* ]] || return 1
    FM_FVM="$candidate"
}
# 发现 PATH、Homebrew 和常用用户安装；已有健康 Dart Pub / 独立 FVM 无须迁移。
fm_find_fvm() {
    local candidate="" result=0
    for candidate in "$(command -v fvm 2>/dev/null)" "$FM_BREW_PREFIX/bin/fvm" "$HOME/.pub-cache/bin/fvm" "$HOME/fvm/bin/fvm" "$HOME/.local/bin/fvm"; do
        result=0; fm_fvm_candidate_ok "$candidate" || result=$?
        (( result!=0 )) || return 0
        case "$result" in 129|130|137|143) return "$result" ;; esac
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
    fm_log "➤ 自动准备现有 FVM 必需的 Dart AOT runtime：brew $operation dartaotruntime；Ctrl+C 结束。"
    jobs_sdk_retry 'Dart AOT runtime' "$LOG_FILE" fm_run_logged "$FM_BREW" "$operation" dartaotruntime || fm_stop 'Dart AOT 运行时安装 / 修复失败' "$?"
    fm_activate_brew
    prefix="$("$FM_BREW" --prefix dartaotruntime 2>> "$LOG_FILE")" || fm_stop '无法定位修复后的 Dart AOT 运行时'
    [[ "$prefix" == /* && -x "$prefix/bin/dartaotruntime" ]] && "$prefix/bin/dartaotruntime" --version >> "$LOG_FILE" 2>&1 || fm_stop 'Dart AOT 运行时修复后复检失败，停止下游 FVM'
}
# 根据已安装 formula 的实际归属修复，避免旧 tap / 版本化 FVM 与新同名公式冲突。
fm_ensure_fvm() {
    local formula="" operation=install item="" listing="" dependencies="" result=0
    local -a owners=()
    if fm_find_fvm; then fm_log "✔ 复用健康 FVM 及实际运行链：$FM_FVM"; return 0; else result=$?; case "$result" in 129|130|137|143) fm_stop "FVM运行时准备已取消" "$result" ;; esac; fi
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
    fm_log "➤ 自动准备必需 FVM：brew $operation $formula（连同公式声明的运行依赖）；Ctrl+C 结束。"
    jobs_sdk_retry 'FVM及其运行时' "$LOG_FILE" fm_run_logged "$FM_BREW" "$operation" "$formula" || fm_stop 'FVM 安装 / 修复失败；请核对日志内原 formula / tap 和实际运行时' "$?"
    fm_activate_brew
    fm_find_fvm || fm_stop 'FVM 或其 Dart / AOT 运行链修复后仍失败，停止且不重复安装' "$?"
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
    fm_log "ℹ 版本清单来源仅作元数据；SDK真实制品下载前独立检测路线，显式源（含空值）保留。"
}
# 只读取得本机缓存和全量历史；官方清单不可达时依次改用镜像和 FVM 自带接口，全部失败才降级本机缓存。
fm_fetch_versions_once() {
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
        fm_list_has_rows "$FM_RUN_DIR/cached.tsv" || return 1
    fi
}
# 有健康缓存可直接离线选择；无缓存时持续获取远程版本清单，不要求重开流程。
fm_fetch_versions() {
    local attempt=1 delay=2 result=0
    while true; do
        result=0
        fm_fetch_versions_once || result=$?
        (( result == 0 )) && return 0
        case "$result" in 129|130|131|137|143) return "$result" ;; esac
        fm_log "⚠ SDK版本清单第${attempt}轮未取得可用结果；${delay}秒后自动继续，Ctrl+C结束。"
        /bin/sleep "$delay" || return 130
        (( attempt++ ))
        (( delay >= 30 )) || delay=$(( delay * 2 ))
        (( delay <= 30 )) || delay=30
    done
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
        if (( result == 1 || result == 130 )); then fm_log 'ℹ 已取消选择，未安装 / 切换 Flutter SDK。'; exit 0; fi
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
    if (( result == 1 || result == 130 )); then fm_log 'ℹ 已取消选择，未安装 / 切换 Flutter SDK。'; exit 0; fi
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
        fm_log 'ℹ 已取消，项目版本配置未变更。'
        exit 0
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
    fm_data merge "$config_source" "$FM_SELECTED" > "$FM_RUN_DIR/next-fvmrc.json" 2>> "$LOG_FILE" || fm_stop '无法保留原字段并合并目标 FVM 配置'
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
# SDK下载返回0不等于完整安装，实际Flutter入口就绪才允许绑定。
fm_install_sdk_once() {
    fm_run_logged "$FM_FVM" install "$FM_SELECTED" || return $?
    [[ -x "$FM_CACHE_PATH/$FM_SELECTED/bin/flutter" ]] || { fm_log '⚠ FVM下载尚未形成完整Flutter入口，继续获取。'; return 1; }
}
# 调用精确版本并核验配置、实际 SDK 与链接身份；FVM 失败保留现场。
fm_apply_and_verify() {
    local result=0 actual="" pinned="" linked="" cached="" use_help=""
    local -a use_options=(--skip-pub-get)
    fm_validate_ready_config
    use_help="$("$FM_FVM" use --help 2>> "$LOG_FILE")" || fm_stop '无法读取FVM切换参数'
    if [[ "$use_help" == *--skip-setup* ]]; then
        use_options+=(--skip-setup)
    else
        fm_log '➤ 此FVM不支持--skip-setup；已先安装SDK，绑定期间的首次补齐仍自动重试。'
    fi
    if [[ "$FM_CHANNEL" != cached ]]; then
        jobs_flutter_fvm_install "安装Flutter $FM_SELECTED" "$LOG_FILE" "$FM_FVM" "$FM_SELECTED" || result=$?
        (( result == 0 )) || fm_stop 'Flutter SDK 获取失败或已取消' "$result"
        fm_validate_ready_config
    fi
    jobs_flutter_sdk_once "FVM Flutter $FM_SELECTED" "$LOG_FILE" "$FM_CACHE_PATH/$FM_SELECTED" "$FM_SELECTED" fm_run_logged "$FM_FVM" use "$FM_SELECTED" "${use_options[@]}" || result=$?
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
    fm_log '▶ 核验项目 Flutter；首次启动补齐的 SDK 资源进度将在下方显示。'
    jobs_flutter_sdk_retry 'Flutter / Dart首次补齐' "$LOG_FILE" "$linked" "$FM_SELECTED" fm_capture_flutter_version || fm_stop '项目 Flutter 实际运行失败；旧 x64 SDK 请核对 Rosetta，其他情况查看 SDK 初始化日志' "$?"
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
    fm_fetch_versions || return $? # 查询官方历史和最新版本，断网时仅提供本机缓存。
    fm_select_version # fzf 单选渠道与精确版本，取消不写项目。
    fm_confirm_project_change # 展示当前到目标和文件影响，回车执行，非空输入取消。
    fm_prepare_project_config # 保存配置快照并固定精确目标，避免父级回退。
    fm_apply_and_verify # 安装或切换后验证 .fvmrc、SDK 链接及实际 Flutter / Dart。
}

main "$@"
