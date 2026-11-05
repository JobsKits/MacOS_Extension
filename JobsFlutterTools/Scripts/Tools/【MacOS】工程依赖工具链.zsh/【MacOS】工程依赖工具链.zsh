#!/bin/zsh
# 脚本自述：仅供 source；为 Flutter Web / 鸿蒙依赖发现、准备和复检配套工具，并桥接 Apple SPM 构建缓存。
# 仅修改本进程环境、项目缓存或经明确确认的用户工具目录；不改系统代理、全局 npm、Shell 配置或工程版本声明。

typeset -g PT_NODE="" PT_PACKAGE_MANAGER="" PT_OHPM="" PT_HVIGOR="" PT_NODE_PIN="" PT_NODE_RANGE="" PT_MANAGER_PIN=""
# 独立单项入口也可获取运行时；加载重试定义本身不安装或写配置。
pt_load_sdk_retry() {
    (( ${+functions[jobs_sdk_retry]} )) && return 0
    source "${${(%):-%x}:A:h:h}/【MacOS】SDK获取重试.zsh/【MacOS】SDK获取重试.zsh"
}
# 写入目录逐级检查，避免通过已有父级链接写到另一棵目录。
pt_check_directory_chain() {
    local directory="$1"
    [[ "$directory" == /* ]] || return 2
    while [[ "$directory" != / ]]; do
        [[ ! -L "$directory" && ( ! -e "$directory" || -d "$directory" ) ]] || return 2
        directory="${directory:h}"
    done
}
# 精确补丁使用官方归档及 SHA256，不把 Homebrew 主版本最新补丁冒充项目所锁版本。
pt_install_node_exact() {
    local version="$1" architecture="$(/usr/bin/uname -m)" folder="" cache="" archive="" checksum="" expected="" actual="" stage="" backup=""
    [[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || return 2
    case "$architecture" in arm64) ;; x86_64) architecture=x64 ;; *) pe_log '✖ 当前宿主架构没有对应 Node 官方 macOS 归档。'; return 3 ;; esac
    folder="node-v$version-darwin-$architecture"
    cache="$HOME/Library/Caches/JobsFlutterTools/node/v$version/$architecture"
    pt_check_directory_chain "$cache" || { pe_log '✖ Node 用户缓存目录含链接或非目录。'; return 2; }
    if pt_probe_node "$cache/$folder/bin/node"; then return 0; fi
    /bin/mkdir -p "$cache" || return $?
    archive="$cache/$folder.tar.gz" checksum="$cache/SHASUMS256.txt"
    [[ ! -L "$archive" && ! -L "$checksum" ]] || return 2
    pt_load_sdk_retry || return $?
    pe_log "📥 来源：https://nodejs.org/dist/v$version/SHASUMS256.txt；目标：$checksum。"
    JOBS_SDK_LOG_REPLACED=1 jobs_sdk_retry 'Node官方SHA256清单' "$PE_RUN_DIR/node-shasums.log" sf_run_diagnostic node-shasums /usr/bin/curl --fail --location --connect-timeout 30 --speed-limit 1 --speed-time 60 --output "$checksum" "https://nodejs.org/dist/v$version/SHASUMS256.txt" || return $?
    expected="$(/usr/bin/awk -v name="$folder.tar.gz" '$2 == name && $1 ~ /^[0-9a-f]+$/ && length($1)==64 {print $1}' "$checksum")"
    [[ ${#expected} == 64 && "$expected" != *$'\n'* ]] || { pe_log '✖ 官方校验清单没有唯一匹配的 Node 归档，未下载或执行。'; return 3; }
    if [[ -f "$archive" ]]; then actual="$(/usr/bin/shasum -a 256 "$archive")"; actual="${actual%% *}"; fi
    if [[ "$actual" != "$expected" ]]; then
        pe_log "📥 来源：https://nodejs.org/dist/v$version/$folder.tar.gz；目标：$archive；复用可续传内容。"
        JOBS_SDK_LOG_REPLACED=1 jobs_sdk_retry "Node $version $architecture" "$PE_RUN_DIR/node-download.log" sf_run_diagnostic node-download /usr/bin/curl --fail --location --connect-timeout 30 --speed-limit 1 --speed-time 60 --continue-at - --output "$archive" "https://nodejs.org/dist/v$version/$folder.tar.gz" || return $?
        actual="$(/usr/bin/shasum -a 256 "$archive")"; actual="${actual%% *}"
    fi
    [[ "$actual" == "$expected" ]] || { pe_log '✖ Node 归档 SHA256 不匹配，已保留现场并停止，未执行归档内容。'; return 3; }
    /usr/bin/tar -tzf "$archive" | /usr/bin/awk -v root="$folder" '($0 !~ "^" root "/" || $0 ~ /(^|\/)\.\.(\/|$)/ || $0 ~ /^\//) {bad=1} END {exit bad}' || return 3
    stage="$(/usr/bin/mktemp -d "$cache/.extract.XXXXXX")" || return 1
    /usr/bin/tar -xzf "$archive" -C "$stage" || return $?
    [[ -x "$stage/$folder/bin/node" && -x "$stage/$folder/bin/npm" ]] || return 3
    if [[ -e "$cache/$folder" || -L "$cache/$folder" ]]; then
        [[ ! -L "$cache/$folder" && -d "$cache/$folder" ]] || return 2
        backup="$cache/$folder.before-jobs-$(/bin/date +%Y%m%d-%H%M%S)-$$"
        [[ ! -e "$backup" ]] || return 2
        /bin/mv "$cache/$folder" "$backup" || return $?
        pe_log "➤ 原 Node 目录已保留：$backup。"
    fi
    /bin/mv "$stage/$folder" "$cache/$folder" || return $?
    /bin/rmdir "$stage" || return $?
    pt_probe_node "$cache/$folder/bin/node"
}
# 普通工具安装先明确选择；默认停止，取消不落盘。
pt_confirm_install() {
    pe_log "➤ $1"
    pe_select '准备依赖工具' $'stop\t取消，保留现有环境\ninstall\t安装上述工具并在当前流程重新验证' || return $?
    [[ "$PE_SELECTION" == install ]] || return 130
}
# 只读取数据；Node 版本文件与 packageManager 不作为 Shell 语句执行。
pt_read_node_requirements() {
    local directory="$1" rows="" key="" value="" file=""
    PT_NODE_PIN="" PT_NODE_RANGE="" PT_MANAGER_PIN=""
    rows="$(/usr/bin/perl -MJSON::PP -e '
        local $/; open my $f,"<",$ARGV[0] or exit 2; my $p=decode_json(<$f>); ref($p) eq "HASH" or exit 2;
        for my $entry (["range",ref($p->{engines}) eq "HASH" ? $p->{engines}{node} : undef],["manager",$p->{packageManager}]) {
            next unless defined $entry->[1]; ref($entry->[1]) and exit 2; $entry->[1] =~ /[\x00-\x1f\x7f]/ and exit 2;
            print "$entry->[0]\t$entry->[1]\n";
        }' "$directory/package.json")" || { pe_log '✖ package.json 版本声明无法解析。'; return 2; }
    while IFS=$'\t' read -r key value; do
        case "$key" in range) PT_NODE_RANGE="$value" ;; manager) PT_MANAGER_PIN="$value" ;; esac
    done <<< "$rows"
    for file in "$directory/.nvmrc" "$directory/.node-version" "$SF_PROJECT/.nvmrc" "$SF_PROJECT/.node-version"; do
        [[ -f "$file" && ! -L "$file" ]] || continue
        value="$(/usr/bin/tr -d ' \t\r\n' < "$file")"
        if [[ "$value" =~ '^v?[0-9]+(\.[0-9]+){0,2}$' ]]; then PT_NODE_PIN="${value#v}";
        elif [[ "$value" != node && "$value" != stable && "$value" != lts/\* ]]; then
            pe_log "✖ 无法静态确认 Node 版本声明：$file；请使用明确版本或项目支持的 engines.node。"; return 3
        fi
        break
    done
}
# npm 自带的 semver 负责完整 engines 范围，不用自行近似判断 ^、~、|| 等表达式。
pt_probe_node() {
    local candidate="$1" directory="${2:-$SF_PROJECT}" npm="${1:h}/npm"
    [[ -x "$candidate" && -x "$npm" ]] || return 1
    SF_COMMAND_TIMEOUT=30 sf_run_diagnostic toolchain-node "$candidate" --version || return $?
    SF_COMMAND_TIMEOUT=30 sf_run_diagnostic toolchain-npm "$npm" --version || return $?
    SF_COMMAND_TIMEOUT=30 sf_run_diagnostic toolchain-node-constraints "$candidate" -e '
const fs = require("fs"), Module = require("module");
const [npm, pin, range] = process.argv.slice(1);
let semver;
try { semver = Module.createRequire(fs.realpathSync(npm))("semver"); }
catch (error) { if (pin || range) { console.error("npm 的 semver 不可用，不能验证 Node 约束。"); process.exit(3); } }
if (pin && !semver.satisfies(process.version, pin)) { console.error(`Node ${process.version} 不满足版本文件 ${pin}`); process.exit(3); }
if (range && (!semver.validRange(range) || !semver.satisfies(process.version, range))) { console.error(`Node ${process.version} 不满足 engines.node ${range}`); process.exit(3); }
console.log(`Node ${process.version} / npm 与工程版本约束已通过`);
' "$npm" "$PT_NODE_PIN" "$PT_NODE_RANGE" || return $?
    PT_NODE="${candidate:A}"
    export PATH="${candidate:h}:$PATH"
    rehash
}
# 复用健康的 PATH、用户版本管理器和 Homebrew Node；不通过 nvm shell 函数改全局版本。
pt_prepare_node() {
    setopt localoptions NO_NOMATCH
    local directory="$1" candidate="" requested="" prefix="" formula=node choice="" attempted=0
    local -a candidates=("$(command -v node 2>/dev/null)" "${NODE_HOME:-/nonexistent}/bin/node" \
        "$HOME"/.nvm/versions/node/*/bin/node(N) "$HOME"/.volta/tools/image/node/*/bin/node(N) \
        "$HOME"/.local/share/fnm/node-versions/*/installation/bin/node(N) \
        "$HOME/Library/Caches/JobsFlutterTools/node"/v*/*/node-v*/bin/node(N) \
        /opt/homebrew/opt/node*/bin/node(N) /usr/local/opt/node*/bin/node(N))
    for candidate in "${candidates[@]}"; do
        [[ -n "$candidate" ]] || continue
        pt_probe_node "$candidate" "$directory" && return 0
    done
    while true; do
        pe_log "➤ 需要 Node ${PT_NODE_PIN:-${PT_NODE_RANGE:-工程支持版本}} 与同套 npm；仅对本次进程生效。"
        pe_select 'Node.js 工具链' $'stop\t取消本次依赖准备\nmanual\t选择已有 Node 可执行文件\ninstall\t通过 Homebrew 安装兼容版本并复检' || return $?
        choice="$PE_SELECTION"
        case "$choice" in
            stop) return 3 ;;
            manual)
                IFS= read -r 'candidate?Node 可执行文件绝对路径（空输入取消）：' || return 130
                [[ -n "$candidate" ]] || return 130
                [[ "$candidate" == /* ]] || return 2
                pt_probe_node "$candidate" "$directory" && return 0 ;;
            install)
                (( ! attempted )) || { pe_log '✖ 本轮安装后仍不满足约束，请选择已有精确版本；未改工程声明。'; return 3; }
                attempted=1
                if [[ "$PT_NODE_PIN" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
                    pt_install_node_exact "$PT_NODE_PIN" || return $?
                    return 0
                fi
                requested="$(print -r -- "${PT_NODE_PIN:-$PT_NODE_RANGE}" | /usr/bin/perl -ne 'print $1 if /(?:^|[>=~^ ]+)(\d+)/')"
                [[ -z "$requested" ]] || formula="node@$requested"
                pe_log "来源：https://formulae.brew.sh/formula/$formula；自动准备必需Node与npm，精确补丁仍以复检为准，Ctrl+C结束。"
                if ! pj_find_brew; then
                    source "$PE_TOOLS_DIR/SetupHomebrew.zsh" || return $?
                    pe_prepare_homebrew || return $?
                fi
                pt_load_sdk_retry || return $?
                SF_COMMAND_TIMEOUT=1800 JOBS_SDK_LOG_REPLACED=1 jobs_sdk_retry 'Node.js runtime' "$PE_RUN_DIR/toolchain-node-install.log" sf_run_diagnostic toolchain-node-install /usr/bin/env HOMEBREW_NO_AUTO_UPDATE=1 "$PJ_BREW" install "$formula" || return $?
                prefix="$(HOMEBREW_NO_AUTO_UPDATE=1 "$PJ_BREW" --prefix "$formula")" || return 1
                pt_probe_node "$prefix/bin/node" "$directory" && return 0 ;;
            *) return 2 ;;
        esac
    done
}
# packageManager 指定的精确版本优先；没有精确声明时只复用健康现有工具，不擅自安装最新版。
pt_prepare_web_toolchain() {
    local directory="$1" lock="$2" manager="" required="" version="" candidate="" prefix="" npm="" package=""
    local SF_COMMAND_DIRECTORY="$directory"
    pt_read_node_requirements "$directory" && pt_prepare_node "$directory" || return $?
    case "$lock" in package-lock.json|npm-shrinkwrap.json) manager=npm ;; pnpm-lock.yaml) manager=pnpm ;; yarn.lock) manager=yarn ;; *) return 2 ;; esac
    if [[ -n "$PT_MANAGER_PIN" ]]; then
        [[ "$PT_MANAGER_PIN" =~ '^(npm|pnpm|yarn)@([0-9]+\.[0-9]+\.[0-9]+)(\+sha[0-9]+\.[A-Za-z0-9+/=]+)?$' ]] || { pe_log '✖ packageManager 必须明确声明受支持包管理器的精确版本。'; return 3; }
        [[ "${match[1]}" == "$manager" ]] || { pe_log '✖ packageManager 与锁文件不一致，未安装。'; return 3; }
        required="${match[2]}"
    fi
    candidate="$(command -v "$manager" 2>/dev/null)"
    if [[ -x "$candidate" ]] && SF_COMMAND_TIMEOUT=30 sf_run_diagnostic "toolchain-$manager" "$candidate" --version; then
        version="$(pe_semantic_version "$PE_RUN_DIR/toolchain-$manager.log")"
        if [[ -n "$version" && ( -z "$required" || "$version" == "$required" ) ]]; then PT_PACKAGE_MANAGER="$candidate"; return 0; fi
    fi
    [[ -n "$required" ]] || { pe_log "✖ 没有健康 $manager 且工程未锁定其版本；请在 package.json 的 packageManager 声明确切版本后重试。"; return 3; }
    prefix="$HOME/Library/Application Support/JobsFlutterTools/package-managers/$manager/$required"
    pt_check_directory_chain "$prefix" && pt_check_directory_chain "$prefix/node_modules/.bin" || return 2
    candidate="$prefix/node_modules/.bin/$manager"
    if [[ -x "$candidate" ]] && SF_COMMAND_TIMEOUT=30 sf_run_diagnostic "toolchain-$manager" "$candidate" --version &&
       [[ "$(pe_semantic_version "$PE_RUN_DIR/toolchain-$manager.log")" == "$required" ]]; then
        PT_PACKAGE_MANAGER="$candidate"; export PATH="${candidate:h}:$PATH"; rehash; return 0
    fi
    package="$manager"
    if [[ "$manager" == yarn && "${required%%.*}" -ge 2 ]]; then package='@yarnpkg/cli-dist'; fi
    pe_log "来源：https://registry.npmjs.org/$package；版本：$required；自动准备到$prefix（用户独立版本目录，不改全局npm）；Ctrl+C结束。"
    [[ "$PT_MANAGER_PIN" != *+sha* ]] || pe_log '➤ 本流程核对包管理器精确版本；声明中的 Corepack hash 由 Corepack 管理，npm 安装使用 registry integrity，不声称已验证该 Corepack hash。'
    npm="$(command -v npm)"
    pt_load_sdk_retry || return $?
    SF_COMMAND_TIMEOUT=1800 JOBS_SDK_LOG_REPLACED=1 jobs_sdk_retry "固定版本${manager}工具" "$PE_RUN_DIR/toolchain-$manager-install.log" sf_run_diagnostic "toolchain-$manager-install" "$npm" install --prefix "$prefix" --no-save --package-lock=false --registry=https://registry.npmjs.org "$package@$required" || return $?
    SF_COMMAND_TIMEOUT=30 sf_run_diagnostic "toolchain-$manager" "$candidate" --version || return $?
    [[ "$(pe_semantic_version "$PE_RUN_DIR/toolchain-$manager.log")" == "$required" ]] || { pe_log '✖ 包管理器安装后版本不匹配，已停止。'; return 3; }
    PT_PACKAGE_MANAGER="$candidate"
    export PATH="${candidate:h}:$PATH"
    rehash
}
# 发现 Studio / 官方 CLT 解压目录；多个候选明确选择，不依赖 Finder 继承交互 Shell PATH。
pt_find_ohos_root() {
    setopt localoptions NO_NOMATCH
    local candidate="${DEVECO_STUDIO_HOME:-${TOOL_HOME:-}}" rows="" location=""
    if [[ -n "$candidate" ]]; then
        [[ ! -d "$candidate/Contents" ]] || candidate="$candidate/Contents"
        [[ -d "$candidate" && ! -L "$candidate" ]] || return 3
        PT_OHOS_ROOT="${candidate:A}"; return 0
    fi
    for location in /Applications/DevEco*.app/Contents(N/) "$HOME"/Applications/DevEco*.app/Contents(N/) \
        "$HOME/Library/Application Support/JobsHarmonySimulator"/clt-*(N/); do
        [[ -d "$location/sdk" ]] || continue
        [[ -z "$rows" ]] || rows+=$'\n'
        rows+="$location"$'\t'"$location"
    done
    [[ -n "$rows" ]] || return 3
    if [[ "$rows" == *$'\n'* ]]; then pe_select 'DevEco / CLT 工具链' "$rows" || return $?; PT_OHOS_ROOT="$PE_SELECTION";
    else PT_OHOS_ROOT="${rows%%$'\t'*}"; fi
}
# 只激活所选目录；Harmony SDK 根与独立 OpenHarmony SDK 根分别校验，不互相冒充。
pt_activate_ohos_root() {
    local root="$PT_OHOS_ROOT" sdk="${DEVECO_SDK_HOME:-${HOS_SDK_HOME:-$PT_OHOS_ROOT/sdk}}" ohos="${OHOS_SDK_HOME:-}" item="" candidate=""
    [[ -d "$sdk" ]] || { pe_log "✖ Harmony SDK 目录不可用：$sdk"; return 3; }
    [[ -n "$ohos" ]] || ohos="$sdk/default/openharmony"
    for item in ets native toolchains; do
        [[ -d "$ohos/$item" ]] || { pe_log "✖ OpenHarmony SDK 缺少 $item：$ohos；请在 DevEco SDK Manager 安装当前工程要求的 SDK。"; return 3; }
    done
    export TOOL_HOME="$root" DEVECO_SDK_HOME="$sdk" OHOS_SDK_HOME="$ohos"
    for item in "$root/node/bin" "$root/node" "$root/tools/node/bin" "$root/tools/node" "$root/tool/node/bin" \
        "$root/ohpm/bin" "$root/tools/ohpm/bin" "$root/hvigor/bin" "$root/tools/hvigor/bin" "$ohos/toolchains"; do
        [[ ! -d "$item" || ":$PATH:" == *":$item:"* ]] || export PATH="$item:$PATH"
    done
    if [[ -z "${SF_JAVA_HOME:-${JAVA_HOME:-}}" ]]; then
        for candidate in "$root/jbr/Contents/Home" "$root/jbr"; do
            [[ -x "$candidate/bin/java" ]] || continue
            SF_JAVA_HOME="$candidate"; export JAVA_HOME="$candidate" PATH="$candidate/bin:$PATH"; break
        done
    fi
    rehash
    PT_OHPM="$(command -v ohpm 2>/dev/null)" PT_HVIGOR="$SF_PROJECT/ohos/hvigorw"
    [[ -f "$PT_HVIGOR" && ! -L "$PT_HVIGOR" ]] || PT_HVIGOR="$(command -v hvigorw 2>/dev/null)"
    local node="$(command -v node 2>/dev/null)" hdc="$(command -v hdc 2>/dev/null)" java="${SF_JAVA_HOME:-${JAVA_HOME:-}}/bin/java"
    [[ -x "$node" && -x "$PT_OHPM" && -f "$PT_HVIGOR" && -x "$hdc" && -x "$java" ]] || { pe_log '✖ 所选 DevEco / CLT 缺少 Node、OHPM、Hvigor、HDC 或 Java；可重新选择完整工具目录。'; return 3; }
    SF_COMMAND_TIMEOUT=30 sf_run_diagnostic ohos-node "$node" --version &&
        SF_COMMAND_TIMEOUT=30 sf_run_diagnostic ohpm-version "$PT_OHPM" --version &&
        SF_COMMAND_TIMEOUT=60 SF_COMMAND_DIRECTORY="$SF_PROJECT/ohos" sf_run_diagnostic hvigor-version /bin/sh "$PT_HVIGOR" --version &&
        SF_COMMAND_TIMEOUT=30 sf_run_diagnostic hdc-version "$hdc" -v &&
        SF_COMMAND_TIMEOUT=30 sf_run_diagnostic ohos-java "$java" -version || return $?
    SF_COMMAND_TIMEOUT=60 sf_run_diagnostic ohos-sdk "$SF_FLUTTER" build hap --help || { pe_log '✖ 当前 Flutter 不具备 Harmony HAP 构建能力，未改用官方 Flutter 冒充。'; return 3; }
    pe_log "✔ DevEco / OpenHarmony 工具链已激活并复检：$root；SDK：$ohos。"
}
# 失败选择不污染下一次工具链发现；用户显式 SDK 与已有 Java 原值一并恢复。
pt_try_ohos_root() {
    local name="" result=0
    local -A values presence
    for name in PATH TOOL_HOME DEVECO_SDK_HOME OHOS_SDK_HOME JAVA_HOME SF_JAVA_HOME; do
        presence[$name]="${+parameters[$name]}"
        values[$name]="${(P)name}"
    done
    pt_activate_ohos_root || result=$?
    (( result != 0 )) || return 0
    for name in PATH TOOL_HOME DEVECO_SDK_HOME OHOS_SDK_HOME JAVA_HOME SF_JAVA_HOME; do
        if [[ "${presence[$name]}" == 1 ]]; then export "$name=${values[$name]}"; else unset "$name"; fi
    done
    rehash
    pe_log "⚠ 当前鸿蒙工具链未通过（退出码 $result），已恢复本次选择前环境。"
    return "$result"
}
# 专有 SDK 的安装与许可保留官方界面；完成后在原流程重新选择目录并复检，无需重启终端。
pt_prepare_ohos_toolchain() {
    local result=0 candidate="" choice=""
    PT_OHOS_ROOT=""
    pt_find_ohos_root && pt_try_ohos_root && return 0
    while true; do
        pe_select '鸿蒙工具链准备' $'stop\t取消本次准备\nmanual\t选择已有 DevEco / 官方 CLT 完整目录并复检\nofficial\t打开华为官方下载 / SDK Manager，完成安装后复检' || return $?
        choice="$PE_SELECTION"
        case "$choice" in
            stop) return 3 ;;
            official)
                pe_log '📥 来源：https://developer.huawei.com/consumer/cn/download/；请本人安装 DevEco / CLT 并在 SDK Manager 完成工程要求组件与许可。'
                /usr/bin/open 'https://developer.huawei.com/consumer/cn/download/' || return $?
                IFS= read -r 'candidate?安装与许可完成后按回车复检；Ctrl+C 取消：' || return 130
                pt_find_ohos_root && pt_try_ohos_root && return 0 ;;
            manual)
                IFS= read -r 'candidate?DevEco.app 或 CLT 目录绝对路径（空输入取消）：' || return 130
                [[ -n "$candidate" ]] || return 130
                [[ "$candidate" == /* && -d "$candidate" && ! -L "$candidate" ]] || { pe_log '✖ 目录不存在或不是普通绝对路径。'; continue; }
                [[ ! -d "$candidate/Contents" ]] || candidate="$candidate/Contents"
                PT_OHOS_ROOT="${candidate:A}"
                pt_try_ohos_root && return 0 ;;
            *) return 2 ;;
        esac
    done
}
# 已有缓存先逐项核对后只补缺失文件；冲突时整批停止，不覆盖来源或目标。
pt_merge_spm_cache() {
    /usr/bin/perl -MFile::Find -MFile::Copy -MFile::Path=make_path -MFile::Spec -MFile::Basename=dirname -MDigest::SHA -MCwd=abs_path -MFcntl=:DEFAULT -e '
        use strict; use warnings;
        my($src,$dst)=@ARGV; my @entries; my %parents;
        sub identity { my @s=lstat($_[0]); return @s ? join(":",@s[0,1,2,7,9]) : "absent"; }
        sub digest { open my $f,"<",$_[0] or die $!; binmode $f; return Digest::SHA->new(256)->addfile($f)->hexdigest; }
        sub check_parents {
            my $path=shift;
            while($path ne "/") {
                die "SPM linked/non-directory parent: $path\n" if -l $path || (-e $path && !-d $path);
                if(-d $path) {
                    my @s=lstat($path); my $id=join(":",@s[0,1,2]);
                    die "SPM changed parent: $path\n" if exists($parents{$path}) && $parents{$path} ne $id;
                    $parents{$path}=$id;
                }
                $path=dirname($path);
            }
        }
        check_parents($src); check_parents($dst);
        find({no_chdir=>1,wanted=>sub {
            return if $File::Find::name eq $src;
            my $p=$File::Find::name; my $r=substr($p,length($src)+1); my $t="$dst/$r";
            check_parents(dirname($p)); check_parents(dirname($t));
            my $hash=""; my $link="";
            if(-l $p) {
                $link=readlink($p);
                die "SPM absolute link: $r\n" if File::Spec->file_name_is_absolute($link);
                my $resolved=abs_path($p);
                die "SPM link escapes cache: $r\n" unless defined($resolved) && ($resolved eq $src || index($resolved,"$src/")==0);
                die "SPM link conflict: $r\n" if (-e $t || -l $t) && (!-l $t || readlink($t) ne $link);
            } elsif(-d $p) {
                die "SPM directory conflict: $r\n" if -l $t || (-e $t && !-d $t);
            } elsif(-f $p) {
                $hash=digest($p);
                die "SPM file conflict: $r\n" if -l $t || (-e $t && (!-f $t || digest($t) ne $hash));
            } else { die "SPM special file: $r\n"; }
            push @entries,[$p,$t,identity($p),identity($t),$hash,$link];
        }},$src);
        for my $e (@entries) {
            my($p,$t,$before,$target_before,$hash,$link)=@$e;
            check_parents(dirname($p)); check_parents(dirname($t));
            die "SPM source changed: $p\n" unless identity($p) eq $before;
            die "SPM target changed: $t\n" unless identity($t) eq $target_before;
            die "SPM source content changed: $p\n" if length($hash) && digest($p) ne $hash;
        }
        for my $e (@entries) {
            my($p,$t,$before,$target_before,$hash,$link)=@$e;
            check_parents(dirname($p)); check_parents(dirname($t));
            die "SPM source changed: $p\n" unless identity($p) eq $before;
            next if $target_before ne "absent";
            die "SPM target appeared: $t\n" if -e $t || -l $t;
            make_path(dirname($t)); check_parents(dirname($t));
            if(length($link)) { symlink($link,$t) or die $!; }
            elsif(-d $p) { make_path($t); }
            else {
                sysopen my $out,$t,O_WRONLY|O_CREAT|O_EXCL,0600 or die $!;
                binmode $out; copy($p,$out) or die $!; close $out or die $!;
                chmod((stat($p))[2]&0777,$t) or die $!;
                die "SPM copy verification failed: $t\n" unless digest($t) eq $hash;
            }
            check_parents(dirname($t));
        }
    ' "$1" "$2"
}
# Flutter 新版明确指定 build/<platform>/SourcePackages；旧版通过当前 Xcode 构建设置定位 DerivedData。
pt_spm_cache_path() {
    local sdk="${SF_FLUTTER_ROOT:-${SF_FLUTTER:A:h:h}}" source="" build_dir=build value="" option=-project scheme="" index=0 arg=""
    source="$sdk/packages/flutter_tools/lib/src/ios/xcodeproj.dart"
    if [[ -f "$source" ]] && /usr/bin/grep -q 'clonedSourcePackagesDirPath' "$source" && /usr/bin/grep -q 'kSwiftPackageCacheDirectoryName' "$source"; then
        SF_COMMAND_TIMEOUT=60 sf_run_diagnostic spm-flutter-config "$SF_FLUTTER" config --machine || return $?
        /usr/bin/plutil -convert xml1 -o /dev/null "$PE_RUN_DIR/spm-flutter-config.log" >/dev/null 2>&1 || { pe_log '✖ 无法读取当前 Flutter build-dir，未猜测缓存位置。'; return 3; }
        value="$(/usr/bin/plutil -extract build-dir raw -o - "$PE_RUN_DIR/spm-flutter-config.log" 2>/dev/null)"
        [[ -z "$value" ]] || build_dir="$value"
        [[ "$build_dir" != /* && "$build_dir" != *$'\n'* && "$build_dir" != *$'\r'* && "$build_dir" != *'..'* ]] || return 2
        PD_SPM_BUILD_CACHE="$SF_PROJECT/$build_dir/$SR_TARGET/SourcePackages"
    else
        [[ "$PD_XCODE_CONTAINER" != *.xcworkspace ]] || option=-workspace
        for (( index=1; index<=${#SR_ARGS}; index++ )); do
            arg="${SR_ARGS[index]}"
            [[ "$arg" != --flavor ]] || { (( index++ )); scheme="${SR_ARGS[index]}"; }
            [[ "$arg" != --flavor=* ]] || scheme="${arg#*=}"
        done
        local -a args=(-showBuildSettings "$option" "$PD_XCODE_CONTAINER")
        [[ -z "$scheme" ]] || args+=(-scheme "$scheme")
        SF_COMMAND_TIMEOUT=120 sf_run_diagnostic spm-xcode-build-settings /usr/bin/xcodebuild "${args[@]}" || return $?
        value="$(/usr/bin/sed -nE 's/^[[:space:]]*OBJROOT = (.*)\/Build\/Intermediates.noindex$/\1/p' "$PE_RUN_DIR/spm-xcode-build-settings.log" | /usr/bin/sort -u)"
        [[ "$value" == /* && "$value" != *$'\n'* ]] || { pe_log '✖ 旧版 Flutter 的 Xcode 缓存路径不能唯一确认，未冒用新版目录；请核对 workspace / scheme 的 DerivedData 设置。'; return 3; }
        PD_SPM_BUILD_CACHE="$value/SourcePackages"
        pe_log "➤ 旧版 Flutter 使用所选 Xcode 工程的实际 DerivedData 缓存：$PD_SPM_BUILD_CACHE。"
    fi
}
# 将实际构建缓存连接到普通项目快照目录；已有缓存融合后保留原目录备份。
pt_prepare_spm_build_cache() {
    local canonical="$SF_PROJECT/.jobs/dependencies/spm" parent="" relative="" backup=""
    pt_spm_cache_path || return $?
    [[ "$PD_SPM_BUILD_CACHE" != "$canonical" && "$PD_SPM_BUILD_CACHE" != "$canonical/"* && "$canonical" != "$PD_SPM_BUILD_CACHE/"* ]] || return 2
    for parent in "$SF_PROJECT/.jobs" "$SF_PROJECT/.jobs/dependencies" "$canonical"; do
        [[ ! -L "$parent" && ( ! -e "$parent" || -d "$parent" ) ]] || { pe_log "✖ SPM 项目缓存路径身份异常：$parent"; return 2; }
    done
    parent="${PD_SPM_BUILD_CACHE:h}"
    while [[ "$parent" != / ]]; do
        [[ ! -L "$parent" && ( ! -e "$parent" || -d "$parent" ) ]] || { pe_log '✖ 实际 SPM 缓存父目录含链接或非目录，未修改。'; return 2; }
        parent="${parent:h}"
    done
    /bin/mkdir -p "$canonical" "${PD_SPM_BUILD_CACHE:h}" || return $?
    if [[ -L "$PD_SPM_BUILD_CACHE" ]]; then
        [[ "${PD_SPM_BUILD_CACHE:A}" == "${canonical:A}" ]] || { pe_log '✖ 实际 SPM 缓存链接指向其它来源，未改动。'; return 2; }
        return 0
    fi
    if [[ -e "$PD_SPM_BUILD_CACHE" ]]; then
        [[ -d "$PD_SPM_BUILD_CACHE" ]] || return 2
        pt_merge_spm_cache "$canonical" "$PD_SPM_BUILD_CACHE" && pt_merge_spm_cache "$PD_SPM_BUILD_CACHE" "$canonical" || { pe_log '✖ SPM 缓存有冲突，保留两份原内容。'; return 3; }
        backup="${PD_SPM_BUILD_CACHE}.before-jobs-$(/bin/date +%Y%m%d-%H%M%S)-$$"
        [[ ! -e "$backup" && ! -L "$backup" ]] || return 2
        /bin/mv "$PD_SPM_BUILD_CACHE" "$backup" || return $?
        pe_log "➤ 原 SPM 构建缓存已保留：$backup。"
    fi
    relative="$(/usr/bin/perl -MFile::Spec -e 'print File::Spec->abs2rel($ARGV[0],$ARGV[1])' "$canonical" "${PD_SPM_BUILD_CACHE:h}")" || return 1
    /bin/ln -s "$relative" "$PD_SPM_BUILD_CACHE" || { [[ -z "$backup" ]] || /bin/mv "$backup" "$PD_SPM_BUILD_CACHE"; return 1; }
    pe_log "✔ SPM 实际构建缓存已连接项目快照目录：$PD_SPM_BUILD_CACHE → $canonical。"
}
