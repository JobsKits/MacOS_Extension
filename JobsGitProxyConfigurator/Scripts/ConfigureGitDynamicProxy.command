#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】🌐双击配置Git动态代理.command。
# - 核心用途：从本文件内嵌源码安装可回退的用户级 Git 动态代理入口。
# - 影响范围：只管理专用运行文件、用户 .zshrc 末尾受控 PATH 块及 Sourcetree 两个 Git 选择键。
# - 运行提示：双击后回车安装；检查或恢复可在菜单选择。--install 已表示无交互安装授权。
# shell: zsh

typeset -g SCRIPT_PATH='' STATE_ROOT='' INSTALLER_STATE='' SNAPSHOT_ROOT='' ACTIVE_FILE=''
typeset -g RUNTIME_FILE='' OWNER_FILE='' SHELL_FILE='' SHELL_TARGET='' LOG_FILE='' MODE='install'
typeset -g STAGE_DIR='' LOCK_DIR='' CURRENT_SNAPSHOT='' EFFECTIVE_SNAPSHOT='' TRANSACTION_ACTIVE=0
typeset -g OWNER_VALUE='jobs-git-network-strategy-installer-v1'
typeset -g PREF_DOMAIN='com.torusknot.SourceTreeNotMAS'
typeset -g INTERACTIVE_RUN=0

# 只计算用户路径，不创建目录，也不读取其它应用的无关配置。
initialize_paths() {
    SCRIPT_PATH="${${(%):-%x}:A}"
    STATE_ROOT="$HOME/Library/Application Support/JobsGitNetworkStrategy"
    INSTALLER_STATE="$STATE_ROOT/installer"
    SNAPSHOT_ROOT="$INSTALLER_STATE/snapshots"
    ACTIVE_FILE="$INSTALLER_STATE/active"
    RUNTIME_FILE="$STATE_ROOT/runtime/bin/git"
    OWNER_FILE="$STATE_ROOT/runtime/.jobs-git-network-strategy-owner"
    SHELL_FILE="$HOME/.zshrc"
    SHELL_TARGET="${SHELL_FILE:A}"
    LOG_FILE="$INSTALLER_STATE/install.log"
}
# 适配双击终端和纯文本输出；首屏说明具体作用域与恢复入口。
show_script_intro_and_wait() {
    initialize_paths
    INTERACTIVE_RUN=0
    [[ $# != 0 ]] || INTERACTIVE_RUN=1
    local title='' body='' reset='' answer=''
    if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" ]]; then
        title=$'\033[1;31m'
        body=$'\033[0;34m'
        reset=$'\033[0m'
    fi
    printf '%sJobs Git 动态代理｜双击安装与精确恢复%s\n' "$title" "$reset"
    printf '%s1、默认优先使用已启用且可达的系统代理；代理不可用时探测直连。Git 业务最多执行一次。%s\n' "$body" "$reset"
    printf '%s2、只修改用户 .zshrc 末尾 PATH 块、专用运行文件和已安装 Sourcetree 的两个 Git 选择键。%s\n' "$body" "$reset"
    printf '%s3、代理仅传给当次 Git 子进程，流量经过选定代理；退出即撤回。不改 .gitconfig、系统代理、VPN 或项目远端。%s\n' "$body" "$reset"
    printf '%s4、安装与恢复保留精确快照；后续冲突时停止。--restore 可恢复安装前或上一版本，Ctrl+C 取消。%s\n' "$body" "$reset"
    printf '%s5、来源：%s（本文件内嵌 Git 入口）。%s\n' "$body" "$SCRIPT_PATH" "$reset"
    printf '%s6、目标：%s。%s\n' "$body" "$RUNTIME_FILE" "$reset"
    printf '%s7、日志：%s。%s\n' "$body" "$LOG_FILE" "$reset"
    case "${1:-}" in
        --install)
            [[ $# == 1 ]] || return 2
            MODE=install
            return 0
            ;;
        --check)
            [[ $# == 1 ]] || return 2
            MODE=check
            return 0
            ;;
        --restore)
            [[ $# == 1 ]] || return 2
            MODE=restore
            ;;
        '')
            MODE=install
            ;;
        *)
            print -u2 -r -- '用法：双击运行，或使用 --install / --check / --restore。'
            return 2
            ;;
    esac
    if [[ ! -t 0 ]]; then
        print -u2 -r -- '当前没有可交互终端，未修改配置；请双击运行，或明确使用 --install。'
        return 2
    fi
    if [[ "$MODE" == restore ]]; then
        read -r "?按回车确认精确恢复；Ctrl+C 取消：" answer || return 2
        [[ -z "$answer" ]] || return 2
    else
        print -r -- '菜单：直接回车安装；输入 C 检查；输入 R 恢复；其它输入取消。'
        read -r '?请选择：' answer || return 2
        case "${answer:l}" in
            '') MODE=install ;;
            c) MODE=check ;;
            r)
                MODE=restore
                read -r '?按回车确认精确恢复；Ctrl+C 取消：' answer || return 2
                [[ -z "$answer" ]] || return 2
                ;;
            *) return 2 ;;
        esac
    fi
}
# 用于双击失败退出后显示结果，不阻塞明确的命令行参数模式。
finish_interactive_run() {
    local result="$1"
    if [[ -t 0 && "$INTERACTIVE_RUN" == 1 ]]; then
        read -r '?处理结束，按回车关闭：' _
    fi
    return "$result"
}
# 检查系统现有工具，不调用安装器、包管理器或提权命令。
check_dependencies() {
    setopt NO_NOMATCH
    local executable=''
    for executable in /bin/zsh /usr/bin/perl /usr/bin/git /usr/bin/cmp /usr/bin/defaults /usr/bin/mktemp; do
        [[ -x "$executable" ]] || { print -u2 -r -- "缺少系统工具：$executable；停止，未修改配置。"; return 1; }
    done
    /usr/bin/git --version >/dev/null 2>&1 || { print -u2 -r -- '系统 Git 不可用；请先准备 Command Line Tools。'; return 1; }
    embedded_wrapper | /bin/zsh -n || { print -u2 -r -- '内嵌 Git 入口语法检查失败，停止。'; return 1; }
    embedded_wrapper | /usr/bin/grep -Fq 'Jobs Git 网络策略入口' || { print -u2 -r -- '内嵌 Git 源码缺失，停止。'; return 1; }
}
# SourceTree 检测和偏好访问独立封装，隔离测试可以替换这些外部边界。
sourcetree_installed() {
    [[ -d /Applications/Sourcetree.app || -d /Applications/SourceTree.app || -d "$HOME/Applications/Sourcetree.app" || -d "$HOME/Applications/SourceTree.app" ]]
}
# 只报告在途应用，不结束进程或自动重启。
sourcetree_running() {
    /usr/bin/pgrep -x Sourcetree >/dev/null 2>&1 || /usr/bin/pgrep -x SourceTree >/dev/null 2>&1
}
# 读取单个已知偏好键，缺失与空字符串通过退出码区分。
preference_read() {
    /usr/bin/defaults read "$PREF_DOMAIN" "$1" 2>/dev/null
}
# 读取原偏好类型，避免恢复时把整数和字符串混用。
preference_type() {
    /usr/bin/defaults read-type "$PREF_DOMAIN" "$1" 2>/dev/null | /usr/bin/sed 's/^Type is //'
}
# 只写本安装器管理的键，第三个参数保留快照中的原类型。
preference_write() {
    local key="$1" value="$2" kind="${3:-string}"
    case "$kind" in
        integer) /usr/bin/defaults write "$PREF_DOMAIN" "$key" -int "$value" ;;
        boolean) /usr/bin/defaults write "$PREF_DOMAIN" "$key" -bool "$value" ;;
        float) /usr/bin/defaults write "$PREF_DOMAIN" "$key" -float "$value" ;;
        string) /usr/bin/defaults write "$PREF_DOMAIN" "$key" -string "$value" ;;
        *) print -u2 -r -- '遇到不支持的偏好类型，停止。'; return 1 ;;
    esac
}
# 原本未设置的键通过删除精确恢复，不清空整个偏好域。
preference_delete() {
    /usr/bin/defaults delete "$PREF_DOMAIN" "$1" 2>/dev/null
}
# 固定的 PATH 块使用 HOME 动态定位，保留旧 JobsMacEnv 和既有 git 函数。
embedded_mount() {
    /bin/cat <<'JOBS_GIT_DYNAMIC_PROXY_MOUNT_EOF'

# JOBS_GIT_DYNAMIC_PROXY_BEGIN
# Jobs Git 动态代理：优先使用用户专用入口，保留其它 PATH 项。
jobs_git_dynamic_proxy_mount() {
    local strategy_bin="$HOME/Library/Application Support/JobsGitNetworkStrategy/runtime/bin"
    if [[ -x "$strategy_bin/git" ]]; then
        path=("$strategy_bin" "${(@)path:#$strategy_bin}")
        export PATH
        rehash
    fi
}
jobs_git_dynamic_proxy_mount
unfunction jobs_git_dynamic_proxy_mount
# JOBS_GIT_DYNAMIC_PROXY_END
JOBS_GIT_DYNAMIC_PROXY_MOUNT_EOF
}
# 快照编号只允许目录名，不允许路径跳出私有状态目录。
snapshot_from_id() {
    [[ "$1" =~ '^[A-Za-z0-9._-]+$' && "$1" != . && "$1" != .. ]] || return 1
    [[ -d "$SNAPSHOT_ROOT/$1" && ! -L "$SNAPSHOT_ROOT/$1" ]] || return 1
    print -r -- "$SNAPSHOT_ROOT/$1"
}
# 任何恢复前先确认快照完整，缺失状态不能被误判为原本不存在。
validate_snapshot_manifest() {
    local snapshot="$1" field='' prefix='' value='' key=''
    local -a fields=( status previous-active shell.path wrapper.after mount.before mount.after preferences.managed )
    for prefix in wrapper.before owner.before shell.before; do
        fields+=( "$prefix.exists" "$prefix.data" "$prefix.mode" )
    done
    for field in "${fields[@]}"; do
        [[ -f "$snapshot/$field" && ! -L "$snapshot/$field" && -r "$snapshot/$field" ]] || return 1
    done
    case "$(< "$snapshot/status")" in prepared|applied|restoring|restored) ;; *) return 1 ;; esac
    for prefix in wrapper.before owner.before shell.before; do
        case "$(< "$snapshot/$prefix.exists")" in 0|1) ;; *) return 1 ;; esac
        [[ "$(< "$snapshot/$prefix.mode")" =~ '^[0-7]{3,4}$' ]] || return 1
    done
    value="$(< "$snapshot/shell.path")"
    [[ "$value" == /* && "$value" != *$'\n'* && "$value" != *$'\r'* ]] || return 1
    case "$(< "$snapshot/preferences.managed")" in
        0) return 0 ;;
        1)
            for key in gitCustomPath gitWhichOne; do
                for field in exists value type; do
                    [[ -f "$snapshot/$key.before.$field" && ! -L "$snapshot/$key.before.$field" ]] || return 1
                done
                case "$(< "$snapshot/$key.before.exists")" in 0|1) ;; *) return 1 ;; esac
                case "$(< "$snapshot/$key.before.type")" in string|integer|boolean|float) ;; *) return 1 ;; esac
            done
            ;;
        *) return 1 ;;
    esac
}
# 已恢复的快照保留 active 指向以保证重复恢复幂等；安装时查找实际当前版本。
resolve_effective_snapshot() {
    EFFECTIVE_SNAPSHOT=''
    [[ -e "$ACTIVE_FILE" || -L "$ACTIVE_FILE" ]] || return 0
    [[ -f "$ACTIVE_FILE" && ! -L "$ACTIVE_FILE" ]] || return 1
    local identifier="$(< "$ACTIVE_FILE")" snapshot='' guard=0
    while [[ -n "$identifier" ]]; do
        snapshot="$(snapshot_from_id "$identifier")" || return 1
        validate_snapshot_manifest "$snapshot" || return 1
        if [[ "$(< "$snapshot/status")" != restored ]]; then
            EFFECTIVE_SNAPSHOT="$snapshot"
            return 0
        fi
        identifier="$(< "$snapshot/previous-active")"
        (( guard++ < 100 )) || return 1
    done
}
# 仅创建专用用户目录，拒绝状态路径的符号链接。
ensure_private_layout() {
    umask 077
    local directory=''
    for directory in "$STATE_ROOT" "$INSTALLER_STATE" "$SNAPSHOT_ROOT" "$STATE_ROOT/runtime" "$STATE_ROOT/runtime/bin"; do
        [[ ! -L "$directory" && ( ! -e "$directory" || -d "$directory" ) ]] || { print -u2 -r -- "状态路径不是普通目录：$directory"; return 1; }
        /bin/mkdir -p "$directory" && /bin/chmod 700 "$directory" || return 1
    done
    [[ ! -L "$LOG_FILE" && ! -L "$ACTIVE_FILE" ]] || return 1
}
# 安装和恢复互斥；遗留锁不自动删除，以免覆盖另一运行中的实例。
acquire_lock() {
    LOCK_DIR="$INSTALLER_STATE/lock"
    /bin/mkdir "$LOCK_DIR" 2>/dev/null || { LOCK_DIR=''; print -u2 -r -- '另一安装/恢复实例尚未结束，或存在遗留锁；停止。'; return 1; }
    print -r -- "$$" > "$LOCK_DIR/pid"
}
# 日志只保存动作与结果，不保存完整偏好、代理认证或环境信息。
record_audit() {
    printf '%s action=%s result=%s\n' "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" "$2" >> "$LOG_FILE"
    /bin/chmod 600 "$LOG_FILE"
}
# 清理仅由本实例创建的临时文件与锁；不递归删除任何目录。
cleanup_temporary_state() {
    if [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]]; then
        /bin/rm -f "$STAGE_DIR/wrapper" "$STAGE_DIR/mount" "$STAGE_DIR/empty" "$STAGE_DIR/active" "$STAGE_DIR/owner"
        /bin/rmdir "$STAGE_DIR" 2>/dev/null
        STAGE_DIR=''
    fi
    if [[ -n "$LOCK_DIR" && -d "$LOCK_DIR" ]]; then
        /bin/rm -f "$LOCK_DIR/pid"
        /bin/rmdir "$LOCK_DIR" 2>/dev/null
        LOCK_DIR=''
    fi
}
# 原子写入单个普通文件，保存指定权限；不会替换符号链接。
atomic_copy() {
    /usr/bin/perl - "$1" "$2" "$3" <<'JOBS_ATOMIC_COPY_EOF'
use strict; use warnings; use Fcntl qw(O_WRONLY O_CREAT O_EXCL);
my ($source,$target,$mode)=@ARGV;
die "拒绝覆盖符号链接\n" if -l $target;
open my $in,'<:raw',$source or die "读取快照失败\n"; local $/; my $data=<$in>;
my $tmp="$target.jobs-git-install.$$";
sysopen my $out,$tmp,O_WRONLY|O_CREAT|O_EXCL,0600 or die "创建临时文件失败\n";
binmode $out; print {$out} $data or die "写入失败\n"; close $out or die "保存失败\n";
chmod(oct($mode),$tmp) or die "设置权限失败\n";
rename $tmp,$target or die "原子替换失败\n";
JOBS_ATOMIC_COPY_EOF
}
# 按精确块检查或替换 shell 配置，原文其它字节和当前权限原样保留。
process_shell_block() {
    /usr/bin/perl - "$SHELL_TARGET" "$1" "$2" "$3" <<'JOBS_SHELL_BLOCK_EOF'
use strict; use warnings; use Fcntl qw(O_WRONLY O_CREAT O_EXCL);
my ($file,$expected_file,$replacement_file,$mode)=@ARGV;
sub read_all { my($p)=@_; open my $h,'<:raw',$p or die "读取块快照失败\n"; local $/; return <$h>; }
my $content=-e $file ? read_all($file) : '';
my $expected=read_all($expected_file); my $replacement=read_all($replacement_file);
if(length $expected) {
  my $count=()=$content=~/\Q$expected\E/g; die "shell 挂载块已被修改或重复，停止\n" unless $count==1;
  my $without=$content; $without=~s/\Q$expected\E//;
  die "发现其它同名挂载块，停止\n" if $without=~/JOBS_GIT_DYNAMIC_PROXY_(?:BEGIN|END)/;
  $content=~s/\Q$expected\E/$replacement/;
} else {
  die "存在未受本安装器管理的同名挂载块，停止\n" if $content=~/JOBS_GIT_DYNAMIC_PROXY_(?:BEGIN|END)/;
  $content.=$replacement;
}
exit 0 if $mode eq 'check';
die "shell 目标成为符号链接，停止\n" if -l $file;
my $permissions=-e $file ? ((stat($file))[2]&07777) : 0600;
my $tmp="$file.jobs-git-install.$$";
sysopen my $out,$tmp,O_WRONLY|O_CREAT|O_EXCL,0600 or die "创建 shell 临时文件失败\n";
binmode $out; print {$out} $content or die "写入 shell 失败\n"; close $out or die "保存 shell 失败\n";
chmod $permissions,$tmp or die "恢复 shell 权限失败\n";
rename $tmp,$file or die "保存 shell 配置失败\n";
JOBS_SHELL_BLOCK_EOF
}
# 保存普通文件的存在状态、精确内容和权限，拒绝未知符号链接。
snapshot_file() {
    local source="$1" prefix="$2"
    [[ ! -L "$source" && ( ! -e "$source" || -f "$source" ) ]] || return 1
    if [[ -f "$source" ]]; then
        print -r -- 1 > "$prefix.exists"
        /bin/cp -p "$source" "$prefix.data" || return 1
        /bin/chmod 600 "$prefix.data" || return 1
        /usr/bin/stat -f '%Lp' "$source" > "$prefix.mode"
    else
        print -r -- 0 > "$prefix.exists"
        : > "$prefix.data"
        print -r -- 600 > "$prefix.mode"
    fi
}
# 比较文件与某个存在状态快照，不读取或打印文件内容。
matches_file_snapshot() {
    local target="$1" prefix="$2"
    [[ ! -L "$target" ]] || return 1
    if [[ "$(< "$prefix.exists")" == 1 ]]; then
        [[ -f "$target" ]] && /usr/bin/cmp -s "$target" "$prefix.data"
    else
        [[ ! -e "$target" ]]
    fi
}
# 恢复本次管理的单个普通文件；原本不存在时只删除该文件。
restore_file_snapshot() {
    local target="$1" prefix="$2"
    if [[ "$(< "$prefix.exists")" == 1 ]]; then
        atomic_copy "$prefix.data" "$target" "$(< "$prefix.mode")"
    else
        /bin/rm -f "$target"
    fi
}
# 保存两项偏好的存在状态、值与类型；未知类型在任何写入前停止。
snapshot_preferences() {
    local snapshot="$1" key='' kind='' value=''
    print -r -- 0 > "$snapshot/preferences.managed"
    sourcetree_installed || return 0
    print -r -- 1 > "$snapshot/preferences.managed"
    for key in gitCustomPath gitWhichOne; do
        if preference_read "$key" > "$snapshot/$key.before.value"; then
            print -r -- 1 > "$snapshot/$key.before.exists"
            kind="$(preference_type "$key")"
            value="$(< "$snapshot/$key.before.value")"
            [[ -n "$kind" ]] || { [[ "$key" == gitWhichOne && "$value" =~ '^-?[0-9]+$' ]] && kind=integer || kind=string; }
            case "$kind" in string|integer|boolean|float) ;; *) print -u2 -r -- 'Sourcetree 偏好类型不受支持，未修改配置。'; return 1 ;; esac
            print -r -- "$kind" > "$snapshot/$key.before.type"
        else
            print -r -- 0 > "$snapshot/$key.before.exists"
            : > "$snapshot/$key.before.value"
            print -r -- string > "$snapshot/$key.before.type"
        fi
    done
}
# 对比单个偏好与本次写入值或原快照，不打印敏感值。
matches_preference_before() {
    local snapshot="$1" key="$2" value='' kind='' result=0
    value="$(preference_read "$key")"
    result=$?
    if [[ "$(< "$snapshot/$key.before.exists")" == 1 ]]; then
        (( result == 0 )) || return 1
        kind="$(preference_type "$key")" || return 1
        [[ "$value" == "$(< "$snapshot/$key.before.value")" && "$kind" == "$(< "$snapshot/$key.before.type")" ]]
    else
        (( result != 0 ))
    fi
}
# 当前安装后的两项偏好必须仍与本次目标一致，恢复才可写回。
matches_preference_after() {
    local key="$1" value='' kind='' expected="$RUNTIME_FILE" expected_type=string
    if [[ "$key" == gitWhichOne ]]; then
        expected=1
        expected_type=integer
    fi
    value="$(preference_read "$key")" || return 1
    kind="$(preference_type "$key")" || return 1
    [[ "$value" == "$expected" && "$kind" == "$expected_type" ]]
}
# 从 active 加载最新一次快照；状态文件从不作为代码执行。
load_current_snapshot() {
    CURRENT_SNAPSHOT=''
    [[ -f "$ACTIVE_FILE" && ! -L "$ACTIVE_FILE" ]] || return 1
    CURRENT_SNAPSHOT="$(snapshot_from_id "$(< "$ACTIVE_FILE")")" || return 1
    validate_snapshot_manifest "$CURRENT_SNAPSHOT"
}
# 未知同名运行文件和被改动的已知版本都不覆盖。
validate_managed_runtime() {
    resolve_effective_snapshot || return 1
    [[ ! -L "$RUNTIME_FILE" && ! -L "$OWNER_FILE" ]] || return 1
    if [[ -e "$RUNTIME_FILE" ]]; then
        [[ -f "$RUNTIME_FILE" ]] || return 1
        if [[ -n "$EFFECTIVE_SNAPSHOT" ]]; then
            /usr/bin/cmp -s "$RUNTIME_FILE" "$EFFECTIVE_SNAPSHOT/wrapper.after" || return 1
        else
            embedded_wrapper | /usr/bin/cmp -s - "$RUNTIME_FILE" || return 1
        fi
    fi
    if [[ -e "$OWNER_FILE" ]]; then
        [[ -f "$OWNER_FILE" && "$(< "$OWNER_FILE")" == "$OWNER_VALUE" ]] || return 1
    fi
}
# 生成私有临时目标文件；检查模式不调用该函数。
prepare_install_stage() {
    STAGE_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-git-installer.XXXXXXXX")" || return 1
    /bin/chmod 700 "$STAGE_DIR" || return 1
    embedded_wrapper > "$STAGE_DIR/wrapper"
    embedded_mount > "$STAGE_DIR/mount"
    : > "$STAGE_DIR/empty"
    print -r -- "$OWNER_VALUE" > "$STAGE_DIR/owner"
}
# 只对确实要修改的项建立快照，升级记录当前有效版本作为恢复目标。
create_install_snapshot() {
    CURRENT_SNAPSHOT="$(/usr/bin/mktemp -d "$SNAPSHOT_ROOT/$(/bin/date -u '+%Y%m%dT%H%M%SZ').XXXXXXXX")" || return 1
    /bin/chmod 700 "$CURRENT_SNAPSHOT" || return 1
    print -r -- prepared > "$CURRENT_SNAPSHOT/status"
    print -r -- "${EFFECTIVE_SNAPSHOT:t}" > "$CURRENT_SNAPSHOT/previous-active"
    print -r -- "$SHELL_TARGET" > "$CURRENT_SNAPSHOT/shell.path"
    snapshot_file "$RUNTIME_FILE" "$CURRENT_SNAPSHOT/wrapper.before" || return 1
    snapshot_file "$OWNER_FILE" "$CURRENT_SNAPSHOT/owner.before" || return 1
    snapshot_file "$SHELL_TARGET" "$CURRENT_SNAPSHOT/shell.before" || return 1
    /bin/cp "$STAGE_DIR/wrapper" "$CURRENT_SNAPSHOT/wrapper.after" || return 1
    /bin/cp "$STAGE_DIR/mount" "$CURRENT_SNAPSHOT/mount.after" || return 1
    if [[ -n "$EFFECTIVE_SNAPSHOT" ]]; then
        /bin/cp "$EFFECTIVE_SNAPSHOT/mount.after" "$CURRENT_SNAPSHOT/mount.before" || return 1
    else
        : > "$CURRENT_SNAPSHOT/mount.before"
    fi
    snapshot_preferences "$CURRENT_SNAPSHOT" || return 1
    /bin/chmod 600 "$CURRENT_SNAPSHOT"/* || return 1
}
# 判断是否已完整安装当前源码和挂载；重复安装不会建立新快照。
installation_is_current() {
    [[ -n "$EFFECTIVE_SNAPSHOT" && "$(< "$EFFECTIVE_SNAPSHOT/status")" == applied ]] || return 1
    [[ -f "$OWNER_FILE" && "$(< "$OWNER_FILE")" == "$OWNER_VALUE" && -x "$RUNTIME_FILE" ]] || return 1
    /usr/bin/cmp -s "$RUNTIME_FILE" "$STAGE_DIR/wrapper" || return 1
    /usr/bin/cmp -s "$EFFECTIVE_SNAPSHOT/mount.after" "$STAGE_DIR/mount" || return 1
    process_shell_block "$STAGE_DIR/mount" "$STAGE_DIR/mount" check || return 1
    if sourcetree_installed; then
        matches_preference_after gitCustomPath && matches_preference_after gitWhichOne || return 1
    fi
    return 0
}
# 写入快照指向后再修改业务项，受控失败可由同一恢复入口撤回。
apply_install_snapshot() {
    local snapshot="$CURRENT_SNAPSHOT" key=''
    matches_file_snapshot "$RUNTIME_FILE" "$snapshot/wrapper.before" || return 1
    matches_file_snapshot "$OWNER_FILE" "$snapshot/owner.before" || return 1
    process_shell_block "$snapshot/mount.before" "$snapshot/mount.after" check || return 1
    if [[ "$(< "$snapshot/preferences.managed")" == 1 ]]; then
        for key in gitCustomPath gitWhichOne; do
            matches_preference_before "$snapshot" "$key" || { print -u2 -r -- 'Sourcetree 偏好发生并发修改，未写入配置。'; return 1; }
        done
    fi
    print -r -- "${snapshot:t}" > "$STAGE_DIR/active" || return 1
    atomic_copy "$STAGE_DIR/active" "$ACTIVE_FILE" 600 || return 1
    TRANSACTION_ACTIVE=1
    atomic_copy "$snapshot/wrapper.after" "$RUNTIME_FILE" 755 || return 1
    atomic_copy "$STAGE_DIR/owner" "$OWNER_FILE" 600 || return 1
    process_shell_block "$snapshot/mount.before" "$snapshot/mount.after" apply || return 1
    if [[ "$(< "$snapshot/preferences.managed")" == 1 ]]; then
        for key in gitCustomPath gitWhichOne; do
            matches_preference_before "$snapshot" "$key" || { print -u2 -r -- 'Sourcetree 偏好发生并发修改，停止。'; return 1; }
        done
        preference_write gitCustomPath "$RUNTIME_FILE" string || return 1
        preference_write gitWhichOne 1 integer || return 1
        matches_preference_after gitCustomPath && matches_preference_after gitWhichOne || return 1
    fi
    print -r -- applied > "$snapshot/status" || return 1
    TRANSACTION_ACTIVE=0
}
# 检查恢复涉及的全部项；任意并发修改都在实际写回前停止。
validate_restore_snapshot() {
    local snapshot="$1" prepared=0 key=''
    validate_snapshot_manifest "$snapshot" || return 1
    case "$(< "$snapshot/status")" in prepared|restoring) prepared=1 ;; esac
    [[ "${SHELL_FILE:A}" == "$(< "$snapshot/shell.path")" ]] || return 1
    SHELL_TARGET="$(< "$snapshot/shell.path")"
    if ! { [[ -f "$RUNTIME_FILE" && ! -L "$RUNTIME_FILE" ]] && /usr/bin/cmp -s "$RUNTIME_FILE" "$snapshot/wrapper.after"; }; then
        (( prepared )) && matches_file_snapshot "$RUNTIME_FILE" "$snapshot/wrapper.before" || return 1
    fi
    if [[ ! -f "$OWNER_FILE" || -L "$OWNER_FILE" || "$(< "$OWNER_FILE")" != "$OWNER_VALUE" ]]; then
        (( prepared )) && matches_file_snapshot "$OWNER_FILE" "$snapshot/owner.before" || return 1
    fi
    if ! process_shell_block "$snapshot/mount.after" "$snapshot/mount.after" check 2>/dev/null; then
        (( prepared )) && process_shell_block "$snapshot/mount.before" "$snapshot/mount.before" check || return 1
    fi
    if [[ "$(< "$snapshot/preferences.managed")" == 1 ]]; then
        for key in gitCustomPath gitWhichOne; do
            if ! matches_preference_after "$key"; then
                (( prepared )) && matches_preference_before "$snapshot" "$key" || return 1
            fi
        done
    fi
}
# 按快照恢复文件、精确 shell 块与两项偏好，不覆盖用户后续无关修改。
apply_restore_snapshot() {
    local snapshot="$1" key='' value=''
    print -r -- restoring > "$snapshot/status" || return 1
    if process_shell_block "$snapshot/mount.after" "$snapshot/mount.after" check 2>/dev/null; then
        process_shell_block "$snapshot/mount.after" "$snapshot/mount.before" apply || return 1
    fi
    if [[ "$(< "$snapshot/shell.before.exists")" == 0 && -f "$SHELL_TARGET" && ! -s "$SHELL_TARGET" ]]; then
        /bin/rm -f "$SHELL_TARGET" || return 1
    fi
    restore_file_snapshot "$RUNTIME_FILE" "$snapshot/wrapper.before" || return 1
    restore_file_snapshot "$OWNER_FILE" "$snapshot/owner.before" || return 1
    if [[ "$(< "$snapshot/preferences.managed")" == 1 ]]; then
        for key in gitCustomPath gitWhichOne; do
            if [[ "$(< "$snapshot/$key.before.exists")" == 1 ]]; then
                value="$(< "$snapshot/$key.before.value")"
                preference_write "$key" "$value" "$(< "$snapshot/$key.before.type")" || return 1
            elif preference_read "$key" >/dev/null; then
                preference_delete "$key" || return 1
            fi
        done
    fi
    print -r -- restored > "$snapshot/status"
}
# 只读核对当前管理状态，不创建临时文件、快照、日志或目录。
check_configuration() {
    check_dependencies || return 1
    validate_managed_runtime || { print -u2 -r -- '存在未知或已修改的运行入口/快照，检查失败；未修改任何配置。'; return 1; }
    if [[ -z "$EFFECTIVE_SNAPSHOT" ]]; then
        print -r -- '当前没有本安装器生效中的配置；未修改任何文件。'
        return 0
    fi
    [[ -x "$RUNTIME_FILE" ]] || { print -u2 -r -- '已管理的 Git 运行入口不可执行，检查失败；未修改任何配置。'; return 1; }
    [[ "$(< "$EFFECTIVE_SNAPSHOT/status")" == applied ]] || { print -u2 -r -- '上次操作未完成；请使用恢复入口。'; return 1; }
    validate_restore_snapshot "$EFFECTIVE_SNAPSHOT" || { print -u2 -r -- '运行入口、挂载块或 Sourcetree 偏好已变化，检查失败；未修改任何配置。'; return 1; }
    print -r -- '运行入口、PATH 挂载与受管理的 Sourcetree 偏好一致。'
    if ! embedded_wrapper | /usr/bin/cmp -s - "$RUNTIME_FILE"; then
        print -r -- '当前为已知旧版本；重新安装可升级，并保留回到该版本的快照。'
    fi
}
# 安装只更新受控项；失败时尝试精确撤回，冲突时保留快照并显式报错。
perform_installation() {
    check_dependencies || return 1
    validate_managed_runtime || { print -u2 -r -- '发现未知或被修改的同名运行文件/快照，停止覆盖。'; return 1; }
    prepare_install_stage || return 1
    if installation_is_current; then
        print -r -- '当前已经是同一版本和配置，无需重复安装；未建立新快照。'
        return 0
    fi
    ensure_private_layout && acquire_lock || return 1
    validate_managed_runtime || return 1
    create_install_snapshot || return 1
    process_shell_block "$CURRENT_SNAPSHOT/mount.before" "$CURRENT_SNAPSHOT/mount.after" check || return 1
    if ! apply_install_snapshot; then
        TRANSACTION_ACTIVE=0
        if validate_restore_snapshot "$CURRENT_SNAPSHOT" && apply_restore_snapshot "$CURRENT_SNAPSHOT"; then
            record_audit install failed-restored
            print -u2 -r -- '安装失败，本次修改已按快照撤回。'
        else
            record_audit install failed-conflict
            print -u2 -r -- "安装失败且存在后续冲突，未强制覆盖；保留恢复快照：$CURRENT_SNAPSHOT"
        fi
        return 1
    fi
    record_audit install applied
    print -r -- "安装完成。运行入口：$RUNTIME_FILE"
    print -r -- "精确快照：$CURRENT_SNAPSHOT"
    print -r -- '重新打开终端，或在现有终端执行 source "$HOME/.zshrc"。普通 git 命令自动使用动态入口。'
    if sourcetree_installed; then
        print -r -- 'Sourcetree 已选择动态 Git 入口；请保存工作后自行退出并重新打开应用。'
        sourcetree_running && print -r -- '检测到 Sourcetree 正在运行；未结束或重启应用，在途任务可继续。'
    fi
    return 0
}
# 恢复最新一次操作后保留 restored 标记，重复调用不会继续卸载上一版本。
perform_restoration() {
    [[ -e "$ACTIVE_FILE" || -L "$ACTIVE_FILE" ]] || { print -r -- '没有需要恢复的安装快照。'; return 0; }
    load_current_snapshot || { print -u2 -r -- '快照指向无效，停止恢复。'; return 1; }
    [[ "$(< "$CURRENT_SNAPSHOT/status")" != restored ]] || { print -r -- '本次安装已经恢复，无需重复操作。'; return 0; }
    validate_restore_snapshot "$CURRENT_SNAPSHOT" || { print -u2 -r -- '运行入口、挂载块或偏好发生后续修改；恢复停止，未覆盖任何配置。'; return 1; }
    ensure_private_layout && acquire_lock || return 1
    validate_restore_snapshot "$CURRENT_SNAPSHOT" || return 1
    apply_restore_snapshot "$CURRENT_SNAPSHOT" || { record_audit restore failed; print -u2 -r -- '恢复未完成，快照已保留；请检查后重试。'; return 1; }
    record_audit restore restored
    print -r -- '已按精确快照恢复安装前或上一版本；保留后续无关 shell 配置。请重新打开终端。'
    sourcetree_running && print -r -- 'Sourcetree 正在运行；未中断任务，请保存后自行重启以加载恢复设置。'
    return 0
}
# 对外安装接口无论成功或失败都释放本实例临时文件，便于重复调用与测试。
install_configuration() {
    local result=0
    perform_installation
    result=$?
    cleanup_temporary_state
    return "$result"
}
# 对外恢复接口同样释放锁，恢复后的重复调用保持当前版本。
restore_configuration() {
    local result=0
    perform_restoration
    result=$?
    cleanup_temporary_state
    return "$result"
}
# 中断安装时按 prepared 快照回溯，失败时保留恢复依据。
handle_interruption() {
    local result="$1"
    if (( TRANSACTION_ACTIVE )); then
        TRANSACTION_ACTIVE=0
        validate_restore_snapshot "$CURRENT_SNAPSHOT" && apply_restore_snapshot "$CURRENT_SNAPSHOT"
        print -u2 -r -- '操作已中断；已尝试撤回本次修改，恢复快照仍保留。'
    fi
    exit "$result"
}
# 退出只清理本实例临时文件与锁。
TRAPEXIT() {
    cleanup_temporary_state
}
# Ctrl+C 不再继续安装或启动应用。
TRAPINT() {
    handle_interruption 130
}
# 外部终止时同样保留精确恢复依据。
TRAPTERM() {
    handle_interruption 143
}
# 根据已确认的模式调用安装、只读检查或精确恢复。
dispatch_configuration() {
    case "$MODE" in
        install) install_configuration ;;
        check) check_configuration ;;
        restore) restore_configuration ;;
    esac
}
# 说明或参数校验失败时不执行业务，并统一显示最终退出状态。
execute_confirmed_configuration() {
    local result=0
    (( $1 == 0 )) || return "$1"
    dispatch_configuration
    result=$?
    finish_interactive_run "$result"
}
# 本文件自带完整入口源码，携走单个 .command 即可安装，不依赖原仓库路径。
embedded_wrapper() {
    /bin/cat <<'JOBS_GIT_DYNAMIC_PROXY_PAYLOAD_V1_EOF'
#!/bin/zsh
# 脚本自述：
# - 脚本名称：Jobs Git 网络策略入口。
# - 核心用途：HTTP(S) 网络命令按可配置优先级短探测直连与当前系统代理。
# - 影响范围：代理只传给本次 Git 子进程；不写 Git / 系统代理配置，原始命令不重放。
# - 运行提示：普通 Git 调用无额外交互；VPN 关闭时自动使用可达的直连，Ctrl+C 取消。
# shell: zsh

typeset -ga ORIGINAL_ARGS GLOBAL_ARGS PUSH_ARGS COMMAND_ARGS PROXY_URLS PROXY_HOSTS PROXY_PORTS
typeset -g AUDIT_FILE='' TARGET_URL='' TARGET_ROOT=''
typeset -g TARGET_HOST='-' TARGET_PORT='-' TARGET_REMOTE=''
typeset -g NETWORK_COMMAND='' NETWORK_REPOSITORY='' NETWORK_SKIP_REASON='' CLONE_REMOTE='origin'
typeset -g CONNECT_TIMEOUT=2 PROBE_TIMEOUT=4
typeset -g DEFAULT_ROUTE_PRIORITY='system' ROUTE_PRIORITY='system' SELECTED_PROXY=''

# 始终使用系统 Git，避免入口经 PATH 再次调用自己。
real_git() {
    /usr/bin/git "$@"
}
# 无需自动选路时替换当前进程，保持 Git 输出和退出语义。
exec_real_git() {
    exec /usr/bin/git "$@"
    exit $?
}
# clone 不读取所在父仓的 local 配置；查询保留 system / global 与显式命令行配置。
metadata_git() {
    if [[ "$NETWORK_COMMAND" != clone ]]; then
        real_git "${GLOBAL_ARGS[@]}" "$@"
        return $?
    fi
    local -a remaining=( "${GLOBAL_ARGS[@]}" ) query_args=()
    local argument=''
    while (( ${#remaining} )); do
        argument="${remaining[1]}"
        case "$argument" in
            -C|--git-dir|--work-tree|--namespace|--super-prefix)
                shift 2 remaining
                ;;
            -C?*|--git-dir=*|--work-tree=*|--namespace=*|--super-prefix=*|--bare)
                shift remaining
                ;;
            -c|--config-env)
                query_args+=( "${remaining[1]}" "${remaining[2]}" )
                shift 2 remaining
                ;;
            *)
                query_args+=( "$argument" )
                shift remaining
                ;;
        esac
    done
    (
        builtin cd / || return 1
        real_git "${query_args[@]}" "$@"
    )
}
# 识别 Git 全局参数和支持的网络命令；未知形式保留原生语义。
parse_network_invocation() {
    ORIGINAL_ARGS=( "$@" )
    GLOBAL_ARGS=()
    PUSH_ARGS=()
    COMMAND_ARGS=()
    NETWORK_COMMAND=''
    NETWORK_SKIP_REASON=''
    local -a remaining=( "$@" )
    local option=''
    while (( ${#remaining} )); do
        option="${remaining[1]}"
        case "$option" in
            -c|-C|--git-dir|--work-tree|--namespace|--config-env|--super-prefix)
                (( ${#remaining} >= 2 )) || return 1
                GLOBAL_ARGS+=( "${remaining[1]}" "${remaining[2]}" )
                shift 2 remaining
                ;;
            -c?*|-C?*|--git-dir=*|--work-tree=*|--namespace=*|--config-env=*|--super-prefix=*|--exec-path=*)
                GLOBAL_ARGS+=( "$option" )
                shift remaining
                ;;
            -p|-P|--paginate|--no-pager|--bare|--no-replace-objects|--literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs|--no-optional-locks|--no-lazy-fetch|--no-advice)
                GLOBAL_ARGS+=( "$option" )
                shift remaining
                ;;
            -*)
                return 1
                ;;
            clone|fetch|pull|ls-remote|push)
                NETWORK_COMMAND="$option"
                shift remaining
                COMMAND_ARGS=( "${remaining[@]}" )
                PUSH_ARGS=( "${remaining[@]}" )
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    done
    return 1
}
# 先确认单一 HTTP(S) 目标，再显示不阻塞普通 Git 调用的内置自述。
show_network_intro_and_route() {
    if ! parse_network_invocation "$@"; then
        exec_real_git "$@"
    fi
    if ! resolve_single_http_network_target; then
        [[ -z "$NETWORK_SKIP_REASON" ]] || print -u2 -r -- "[Jobs Git] ${NETWORK_SKIP_REASON}；本次原生透传，不自动选路。"
        exec_real_git "$@"
    fi
    configure_route_priority
    if [[ "$ROUTE_PRIORITY" == system ]]; then
        print -u2 -r -- '[Jobs Git] 系统代理优先；当前代理均不可达时短探测直连，原始命令只执行一次。'
    else
        print -u2 -r -- '[Jobs Git] 直连优先；连接失败后短探测当前系统代理，原始命令只执行一次。'
    fi
    print -u2 -r -- "[Jobs Git] 代理仅影响本次 Git 及子进程；流量经过选定代理，退出即撤回，Ctrl+C 取消。审计：${HOME}/Library/Logs/JobsGitNetworkStrategy/push.log"
}
# 建立最小权限审计位置；无法写日志时仍保留原生 Git 可用性。
prepare_audit() {
    local audit_directory="${HOME}/Library/Logs/JobsGitNetworkStrategy"
    AUDIT_FILE=''
    if [[ -L "$audit_directory" || -L "${audit_directory}/push.log" ]]; then
        print -u2 -r -- '[Jobs Git] 审计路径为符号链接，本次跳过审计。'
        return 0
    fi
    if ! /bin/mkdir -p "$audit_directory" 2>/dev/null; then
        print -u2 -r -- '[Jobs Git] 无法创建审计目录，本次跳过审计。'
        return 0
    fi
    if ! /bin/chmod 700 "$audit_directory" 2>/dev/null; then
        return 0
    fi
    if ! { : >> "${audit_directory}/push.log"; } 2>/dev/null; then
        return 0
    fi
    /bin/chmod 600 "${audit_directory}/push.log" 2>/dev/null || return 0
    AUDIT_FILE="${audit_directory}/push.log"
}
# 日志只记录模式、经过校验的主机/端口和退出码，不记录命令或原始诊断。
audit_result() {
    [[ -n "$AUDIT_FILE" ]] || return 0
    local mode="$1" host="$2" port="$3" result="$4"
    [[ "$mode" =~ '^[a-z-]+$' ]] || return 0
    is_safe_proxy_host "$host" || host='-'
    [[ "$port" =~ '^([0-9]+|-)$' ]] || port='-'
    [[ "$result" =~ '^[0-9]+$' ]] || result=1
    printf '%s mode=%s host=%s port=%s exit=%s\n' \
        "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')" "$mode" "$host" "$port" "$result" >> "$AUDIT_FILE" 2>/dev/null
    return 0
}
# 中断时立即终止选路，不进入后续代理探测或 Git 业务。
TRAPINT() {
    exit 130
}
# 收到终止信号后不再探测或启动子进程。
TRAPTERM() {
    exit 143
}
# 解析 push 的目标参数；不明确的选项保守交回原生 Git。
push_repository_argument() {
    local -a remaining=( "${PUSH_ARGS[@]}" )
    local repository='' argument=''
    while (( ${#remaining} )); do
        argument="${remaining[1]}"
        case "$argument" in
            --repo)
                (( ${#remaining} >= 2 )) || return 1
                [[ -z "$repository" ]] || return 1
                repository="${remaining[2]}"
                shift 2 remaining
                ;;
            --repo=*)
                [[ -z "$repository" ]] || return 1
                repository="${argument#--repo=}"
                shift remaining
                ;;
            --receive-pack|--exec|--push-option|-o)
                (( ${#remaining} >= 2 )) || return 1
                shift 2 remaining
                ;;
            --receive-pack=*|--exec=*|--push-option=*|-o?*|--force-with-lease=*|--signed=*|--recurse-submodules=*)
                shift remaining
                ;;
            -u|--set-upstream|-v|--verbose|-q|--quiet|--all|--branches|--prune|--mirror|-d|--delete|--tags|-n|--dry-run|--porcelain|-f|--force|--force-with-lease|--force-if-includes|--no-force-if-includes|--no-verify|--verify|--atomic|--no-atomic|--follow-tags|--no-follow-tags|--signed|--no-signed|--thin|--no-thin|--progress|--no-progress|-4|--ipv4|-6|--ipv6)
                shift remaining
                ;;
            --)
                shift remaining
                if (( ${#remaining} )); then
                    [[ -z "$repository" ]] || return 1
                    repository="${remaining[1]}"
                fi
                break
                ;;
            -*)
                return 1
                ;;
            *)
                if [[ -z "$repository" ]]; then
                    repository="$argument"
                fi
                shift remaining
                ;;
        esac
    done
    print -r -- "$repository"
}
# 按 Git 的默认 push remote 优先级选择一个目标，不改变仓库配置。
default_push_remote() {
    local branch='' selected='' remotes=''
    branch="$(real_git "${GLOBAL_ARGS[@]}" symbolic-ref --quiet --short HEAD 2>/dev/null)"
    if [[ -n "$branch" ]]; then
        selected="$(real_git "${GLOBAL_ARGS[@]}" config --get "branch.${branch}.pushRemote" 2>/dev/null)"
        if [[ -n "$selected" ]]; then
            print -r -- "$selected"
            return 0
        fi
    fi
    selected="$(real_git "${GLOBAL_ARGS[@]}" config --get remote.pushDefault 2>/dev/null)"
    if [[ -n "$selected" ]]; then
        print -r -- "$selected"
        return 0
    fi
    if [[ -n "$branch" ]]; then
        selected="$(real_git "${GLOBAL_ARGS[@]}" config --get "branch.${branch}.remote" 2>/dev/null)"
        if [[ -n "$selected" ]]; then
            print -r -- "$selected"
            return 0
        fi
    fi
    remotes="$(real_git "${GLOBAL_ARGS[@]}" remote 2>/dev/null)"
    local -a names=( "${(@f)remotes}" )
    if (( ${#names} == 1 )) && [[ -n "${names[1]}" ]]; then
        print -r -- "${names[1]}"
        return 0
    fi
    if (( ${names[(Ie)origin]} )); then
        print -r -- origin
        return 0
    fi
    return 1
}
# 拆出不含凭据、路径和查询参数的 HTTP 站点，只用于只读连通性探测。
parse_http_target() {
    local url="$1" scheme='' authority='' host='' port=''
    [[ "$url" != *$'\n'* && "$url" != *$'\r'* ]] || return 1
    if [[ "$url" == https://* ]]; then
        scheme=https
        port=443
    elif [[ "$url" == http://* ]]; then
        scheme=http
        port=80
    else
        return 1
    fi
    authority="${url#*://}"
    authority="${authority%%[/?#]*}"
    authority="${authority##*@}"
    if [[ "$authority" =~ '^\[([0-9A-Fa-f:]+)\](:([0-9]+))?$' ]]; then
        host="[${match[1]}]"
        [[ -n "${match[3]}" ]] && port="${match[3]}"
    elif [[ "$authority" =~ '^([A-Za-z0-9_.-]+)(:([0-9]+))?$' ]]; then
        host="${match[1]}"
        [[ -n "${match[3]}" ]] && port="${match[3]}"
    else
        return 1
    fi
    (( ${#port} <= 5 )) || return 1
    (( 10#$port >= 1 && 10#$port <= 65535 )) || return 1
    TARGET_URL="$url"
    TARGET_HOST="$host"
    TARGET_PORT="$port"
    TARGET_ROOT="${scheme}://${authority}/"
    return 0
}
# 展开真实 push URL；多个地址或 SSH / 本地目标不进入自动选路。
resolve_single_http_push_target() {
    local repository='' urls=''
    if ! repository="$(push_repository_argument)"; then
        NETWORK_SKIP_REASON='push 参数无法安全确定单一目标'
        return 1
    fi
    [[ -n "$repository" ]] || repository="$(default_push_remote)" || return 1
    TARGET_REMOTE=''
    if [[ "$repository" =~ '^[A-Za-z0-9_][A-Za-z0-9._/-]*$' ]]; then
        urls="$(real_git "${GLOBAL_ARGS[@]}" remote get-url --push --all "$repository" 2>/dev/null)"
        if [[ $? == 0 && -n "$urls" ]]; then
            TARGET_REMOTE="$repository"
        else
            urls=''
        fi
    fi
    if [[ -z "$urls" ]]; then
        urls="$(expand_push_repository_url "$repository")" || return 1
    fi
    local -a expanded_urls=( "${(@f)urls}" )
    if (( ${#expanded_urls} != 1 )); then
        NETWORK_SKIP_REASON='push 配置含多个目标地址'
        return 1
    fi
    parse_http_target "${expanded_urls[1]}"
}
# 显式 push 地址先按最长 pushInsteadOf 前缀展开，否则复用 Git 的只读 insteadOf 解析。
expand_push_repository_url() {
    local repository="$1" records='' record='' key='' prefix='' base=''
    local best_prefix='' best_base=''
    records="$(metadata_git config --null --get-regexp '^url\..*\.pushinsteadof$' 2>/dev/null)"
    for record in "${(@0)records}"; do
        [[ "$record" == *$'\n'* ]] || continue
        key="${record%%$'\n'*}"
        prefix="${record#*$'\n'}"
        [[ -n "$prefix" && "$repository" == "$prefix"* ]] || continue
        if (( ${#prefix} > ${#best_prefix} )); then
            best_prefix="$prefix"
            base="${key#url.}"
            best_base="${base%.pushinsteadof}"
        fi
    done
    if [[ -n "$best_prefix" ]]; then
        print -r -- "${best_base}${repository#"$best_prefix"}"
        return 0
    fi
    metadata_git ls-remote --get-url "$repository"
}
# 提取 clone 的仓库与可选目标目录；命令内配置和递归形式交回原生 Git。
parse_clone_repository() {
    local -a remaining=( "${COMMAND_ARGS[@]}" ) positional=()
    local argument=''
    CLONE_REMOTE=origin
    while (( ${#remaining} )); do
        argument="${remaining[1]}"
        case "$argument" in
            --)
                shift remaining
                positional+=( "${remaining[@]}" )
                break
                ;;
            --origin|-o)
                (( ${#remaining} >= 2 )) || return 1
                CLONE_REMOTE="${remaining[2]}"
                shift 2 remaining
                ;;
            --origin=*|-o?*)
                [[ "$argument" == --origin=* ]] && CLONE_REMOTE="${argument#*=}" || CLONE_REMOTE="${argument#-o}"
                shift remaining
                ;;
            --template|--branch|-b|--upload-pack|-u|--reference|--reference-if-able|--separate-git-dir|--depth|--shallow-since|--shallow-exclude|--filter|--jobs|-j|--server-option|--revision)
                (( ${#remaining} >= 2 )) || return 1
                shift 2 remaining
                ;;
            --template=*|--branch=*|-b?*|--upload-pack=*|-u?*|--reference=*|--reference-if-able=*|--separate-git-dir=*|--depth=*|--shallow-since=*|--shallow-exclude=*|--filter=*|--jobs=*|-j?*|--server-option=*|--revision=*)
                shift remaining
                ;;
            --config|-c|--config=*|-c?*)
                NETWORK_SKIP_REASON='clone 含命令内配置，保留其原有作用域'
                return 1
                ;;
            --recursive|--recursive=*|--recurse-submodules|--recurse-submodules=*|--bundle-uri|--bundle-uri=*)
                NETWORK_SKIP_REASON='递归子模块或 bundle 可能连接多个目标'
                return 1
                ;;
            -l|--local|--no-local|--no-hardlinks|-s|--shared|-q|--quiet|-v|--verbose|--progress|-n|--no-checkout|--bare|--mirror|--dissociate|--single-branch|--no-single-branch|--tags|--no-tags|--shallow-submodules|--no-shallow-submodules|--sparse|--reject-shallow|--no-reject-shallow|--remote-submodules|--no-remote-submodules|--also-filter-submodules|--no-also-filter-submodules|--no-recurse-submodules)
                shift remaining
                ;;
            -*)
                NETWORK_SKIP_REASON='clone 参数无法安全确定单一目标'
                return 1
                ;;
            *)
                positional+=( "$argument" )
                shift remaining
                ;;
        esac
    done
    (( ${#positional} >= 1 && ${#positional} <= 2 )) || return 1
    [[ "$CLONE_REMOTE" =~ '^[A-Za-z0-9_][A-Za-z0-9._/-]*$' ]] || return 1
    NETWORK_REPOSITORY="${positional[1]}"
    return 0
}
# 解析 fetch / pull / ls-remote 的单一仓库参数，后续 refspec / pattern 原样保留。
parse_read_repository() {
    local -a remaining=( "${COMMAND_ARGS[@]}" )
    local argument=''
    NETWORK_REPOSITORY=''
    while (( ${#remaining} )); do
        argument="${remaining[1]}"
        case "$argument" in
            --)
                shift remaining
                [[ -n "$NETWORK_REPOSITORY" || ${#remaining} == 0 ]] || NETWORK_REPOSITORY="${remaining[1]}"
                break
                ;;
            --all|--multiple|--recurse-submodules|--recurse-submodules=*|--recurse-submodules-default=*)
                NETWORK_SKIP_REASON='多仓库或递归子模块形式可能连接多个目标'
                return 1
                ;;
            --upload-pack|--depth|--deepen|--shallow-since|--shallow-exclude|--negotiation-tip|--filter|--server-option|--jobs|-j|--refmap|--sort|--strategy|-s|--strategy-option|-X|--cleanup)
                (( ${#remaining} >= 2 )) || return 1
                shift 2 remaining
                ;;
            --upload-pack=*|--depth=*|--deepen=*|--shallow-since=*|--shallow-exclude=*|--negotiation-tip=*|--filter=*|--server-option=*|--jobs=*|-j?*|--refmap=*|--sort=*|--strategy=*|-s?*|--strategy-option=*|-X?*|--cleanup=*|--rebase=*|--log=*|--gpg-sign=*|--show-forced-updates=*)
                shift remaining
                ;;
            -q|--quiet|-v|--verbose|--progress|--no-progress|-f|--force|-k|--keep|-u|--update-head-ok|--update-shallow|--unshallow|--append|-a|--atomic|--no-atomic|--dry-run|-n|--no-tags|-t|--tags|--no-recurse-submodules|-p|--prune|--no-prune|--prune-tags|--no-prune-tags|--no-write-fetch-head|--write-fetch-head|--keep-auto|--no-auto-maintenance|--auto-maintenance|--no-auto-gc|--auto-gc|--no-write-commit-graph|--write-commit-graph|--negotiate-only|--show-forced-updates|--no-show-forced-updates|-4|--ipv4|-6|--ipv6|--exit-code|--symref|-h|--heads|--branches|--refs|-r|--rebase|--no-rebase|--ff-only|--ff|--no-ff|--commit|--no-commit|--edit|--no-edit|--squash|--no-squash|--verify|--no-verify|--signoff|--no-signoff|--allow-unrelated-histories|--autostash|--no-autostash|--stat|--no-stat|--log|--no-log|--gpg-sign|--no-gpg-sign|--no-verify-signatures|--verify-signatures|--no-overwrite-ignore|--overwrite-ignore|--compact-summary|--no-compact-summary)
                shift remaining
                ;;
            -*)
                NETWORK_SKIP_REASON="${NETWORK_COMMAND} 参数无法安全确定单一目标"
                return 1
                ;;
            *)
                [[ -n "$NETWORK_REPOSITORY" ]] || NETWORK_REPOSITORY="$argument"
                shift remaining
                ;;
        esac
    done
    return 0
}
# fetch / pull / ls-remote 沿用当前分支的 remote，否则由 origin 交给 Git 校验。
default_read_remote() {
    local branch='' selected=''
    branch="$(real_git "${GLOBAL_ARGS[@]}" symbolic-ref --quiet --short HEAD 2>/dev/null)"
    if [[ -n "$branch" ]]; then
        selected="$(real_git "${GLOBAL_ARGS[@]}" config --get "branch.${branch}.remote" 2>/dev/null)"
        if [[ -n "$selected" ]]; then
            print -r -- "$selected"
            return 0
        fi
    fi
    print -r -- origin
}
# 用 Git 自身展开 URL 重写规则；帮助、本地、SSH 与不明确的多目标保持透明。
resolve_single_http_network_target() {
    local argument='' urls=''
    local -a expanded_urls=()
    NETWORK_REPOSITORY=''
    TARGET_REMOTE=''
    for argument in "${COMMAND_ARGS[@]}"; do
        case "$argument" in
            --help)
                return 1
                ;;
            -h)
                [[ "$NETWORK_COMMAND" == ls-remote && ${#COMMAND_ARGS} -gt 1 ]] || return 1
                ;;
            --get-url)
                [[ "$NETWORK_COMMAND" == ls-remote ]] && return 1
                ;;
        esac
    done
    if [[ "$NETWORK_COMMAND" == push ]]; then
        for argument in "${COMMAND_ARGS[@]}"; do
            case "$argument" in
                --recurse-submodules|--recurse-submodules=*)
                    NETWORK_SKIP_REASON='递归子模块可能连接多个目标'
                    return 1
                    ;;
            esac
        done
        if ! resolve_single_http_push_target; then
            return 1
        fi
        if has_recursive_network_config; then
            NETWORK_SKIP_REASON='配置启用了递归子模块，可能连接多个目标'
            return 1
        fi
        return 0
    elif [[ "$NETWORK_COMMAND" == clone ]]; then
        parse_clone_repository || return 1
    else
        parse_read_repository || return 1
        if [[ -z "$NETWORK_REPOSITORY" && "$NETWORK_COMMAND" != ls-remote ]] && has_fetch_all_config; then
            NETWORK_SKIP_REASON='fetch.all 配置可能连接多个仓库'
            return 1
        fi
        [[ -n "$NETWORK_REPOSITORY" ]] || NETWORK_REPOSITORY="$(default_read_remote)" || return 1
        if [[ "$NETWORK_REPOSITORY" =~ '^[A-Za-z0-9_][A-Za-z0-9._/-]*$' ]]; then
            urls="$(real_git "${GLOBAL_ARGS[@]}" remote get-url --all "$NETWORK_REPOSITORY" 2>/dev/null)"
            if [[ $? == 0 && -n "$urls" ]]; then
                TARGET_REMOTE="$NETWORK_REPOSITORY"
            else
                urls=''
            fi
        fi
    fi
    if [[ -z "$urls" ]]; then
        urls="$(metadata_git ls-remote --get-url "$NETWORK_REPOSITORY" 2>/dev/null)" || return 1
    fi
    expanded_urls=( "${(@f)urls}" )
    if (( ${#expanded_urls} != 1 )); then
        NETWORK_SKIP_REASON='仓库配置含多个目标地址'
        return 1
    fi
    parse_http_target "${expanded_urls[1]}" || return 1
    [[ "$NETWORK_COMMAND" != clone ]] || TARGET_REMOTE="$CLONE_REMOTE"
    if has_recursive_network_config; then
        NETWORK_SKIP_REASON='配置启用了递归子模块，可能连接多个目标'
        return 1
    fi
    return 0
}
# 无显式目标时 fetch.all 可能扩展到不同站点，保留原生多仓库语义。
has_fetch_all_config() {
    local value=''
    value="$(metadata_git config --get fetch.all 2>/dev/null)" || return 1
    case "${value:l}" in
        false|no|off|0)
            return 1
            ;;
    esac
    return 0
}
# 明确递归配置与含 gitlink 的默认按需 fetch 都可能访问其它站点。
has_recursive_network_config() {
    local value='' key=''
    local -a keys=()
    case "$NETWORK_COMMAND" in
        clone|ls-remote)
            return 1
            ;;
    esac
    for value in "${COMMAND_ARGS[@]}"; do
        [[ "$value" != --no-recurse-submodules ]] || return 1
    done
    case "$NETWORK_COMMAND" in
        fetch|pull)
            keys=( fetch.recurseSubmodules submodule.recurse )
            ;;
        push)
            keys=( push.recurseSubmodules submodule.recurse )
            ;;
    esac
    for key in "${keys[@]}"; do
        value="$(metadata_git config --get "$key" 2>/dev/null)" || continue
        case "${value:l}" in
            false|no|off|0)
                return 1
                ;;
            *)
                return 0
                ;;
        esac
    done
    if [[ "$NETWORK_COMMAND" == fetch || "$NETWORK_COMMAND" == pull ]]; then
        metadata_git ls-files --stage 2>/dev/null | /usr/bin/grep -q '^160000 ' && return 0
    fi
    return 1
}
# 用户已有显式代理或显式空代理时保留其选择，不替换配置作用域。
has_explicit_proxy() {
    local variable=''
    for variable in http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY; do
        (( ${+parameters[$variable]} )) && return 0
    done
    metadata_git config --get-urlmatch http.proxy "$TARGET_URL" >/dev/null 2>&1 && return 0
    if [[ -n "$TARGET_REMOTE" ]]; then
        metadata_git config --get "remote.${TARGET_REMOTE}.proxy" >/dev/null 2>&1 && return 0
    fi
    return 1
}
# 在失败发生后读取当前系统代理，避免固定某个本机端口。
system_proxy_snapshot() {
    /usr/sbin/scutil --proxy
}
# 只接受普通主机名或 IPv6 字面量，拒绝凭据、空白和 URL 片段。
is_safe_proxy_host() {
    [[ "$1" =~ '^([A-Za-z0-9_.-]+|[0-9A-Fa-f:]+|\[[0-9A-Fa-f:]+\])$' ]]
}
# 匹配主机/通配域名和 IPv4 CIDR；IPv6 CIDR 无法精确判断时保守保留旁路。
proxy_rules_bypass_target() {
    local rules="$1" exclude_simple="${2:-0}"
    print -r -- "$rules" | /usr/bin/awk -v host="${TARGET_HOST:l}" -v simple="$exclude_simple" '
        function ipv4(value, octets, count, i, result) {
            count=split(value,octets,"."); if (count<1 || count>4) return -1
            result=0
            for (i=1;i<=4;i++) {
                if (i<=count && (octets[i]!~/^[0-9]+$/ || octets[i]>255)) return -1
                result=result*256+(i<=count ? octets[i] : 0)
            }
            return result
        }
        function matches(rule, pair, prefix, divisor, left, right, regex, i, character) {
            if (rule=="<local>") return host !~ /[.:]/
            if (index(rule,"/")) {
                split(rule,pair,"/")
                if (index(pair[1],":") && index(host,":")) return 1
                if (host !~ /^[0-9.]+$/ || pair[2]!~/^[0-9]+$/ || pair[2]>32) return 0
                left=ipv4(host); right=ipv4(pair[1]); divisor=2^(32-pair[2])
                return left>=0 && right>=0 && int(left/divisor)==int(right/divisor)
            }
            if (rule==host) return 1
            if (substr(rule,1,1)==".") rule=substr(rule,2)
            if (host==rule || (length(host)>length(rule) && substr(host,length(host)-length(rule))=="." rule)) return 1
            regex="^"
            for (i=1;i<=length(rule);i++) {
                character=substr(rule,i,1)
                if (character=="*") regex=regex ".*"
                else if (character=="?") regex=regex "."
                else if (character ~ /[A-Za-z0-9_-]/) regex=regex character
                else regex=regex "\\" character
            }
            return host ~ (regex "$")
        }
        BEGIN {
            sub(/^\[/,"",host); sub(/\]$/,"",host)
            if (simple=="1" && host !~ /[.:]/) matched=1
        }
        { rule=tolower($0); gsub(/^[[:space:]]+|[[:space:]]+$/,"",rule); if (length(rule) && matches(rule)) matched=1 }
        END { exit matched ? 0 : 1 }
    '
}
# 保留系统代理例外与现有 NO_PROXY；不把被排除的主机导向回退代理。
target_bypasses_proxy() {
    local snapshot="$1" rules='' exclude_simple=0
    rules="$(print -r -- "$snapshot" | /usr/bin/awk '
        /ExceptionsList[[:space:]]*:[[:space:]]*<array>/ { in_exceptions=1; next }
        in_exceptions && /^[[:space:]]*}/ { in_exceptions=0 }
        in_exceptions && /^[[:space:]]*[0-9]+[[:space:]]*:/ { sub(/^[^:]*:[[:space:]]*/, ""); print }
    ')"
    print -r -- "$snapshot" | /usr/bin/grep -Eq '^[[:space:]]*ExcludeSimpleHostnames[[:space:]]*:[[:space:]]*1[[:space:]]*$' && exclude_simple=1
    proxy_rules_bypass_target "$rules" "$exclude_simple" && return 0
    local variable=''
    for variable in no_proxy NO_PROXY; do
        rules="${(P)variable}"
        rules="${rules//,/$'\n'}"
        proxy_rules_bypass_target "$rules" 0 && return 0
    done
    return 1
}
# 优先 HTTPS、其次 HTTP、最后 SOCKS；仅接受已启用、合法且不含凭据的地址。
discover_system_proxies() {
    PROXY_URLS=()
    PROXY_HOSTS=()
    PROXY_PORTS=()
    local snapshot='' rows='' kind='' host='' port='' proxy='' scheme=''
    snapshot="$(system_proxy_snapshot 2>/dev/null)" || return 1
    target_bypasses_proxy "$snapshot" && return 2
    rows="$(print -r -- "$snapshot" | /usr/bin/awk '
        /^[[:space:]]*(HTTPSEnable|HTTPSProxy|HTTPSPort|HTTPEnable|HTTPProxy|HTTPPort|SOCKSEnable|SOCKSProxy|SOCKSPort)[[:space:]]*:/ {
            key=$1; value=$0; sub(/^[^:]*:[[:space:]]*/, "", value); sub(/[[:space:]]*$/, "", value); values[key]=value
        }
        END {
            split("HTTPS HTTP SOCKS", kinds, " ")
            for (i=1;i<=3;i++) {
                kind=kinds[i]
                if (values[kind "Enable"]=="1") printf "%s\t%s\t%s\n", kind, values[kind "Proxy"], values[kind "Port"]
            }
        }')"
    while IFS=$'\t' read -r kind host port; do
        [[ -n "$kind" && "$port" =~ '^[0-9]+$' ]] || continue
        is_safe_proxy_host "$host" || continue
        (( ${#port} <= 5 )) || continue
        (( 10#$port >= 1 && 10#$port <= 65535 )) || continue
        [[ "$host" == *:* && "$host" != \[*\] ]] && host="[${host}]"
        scheme=http
        [[ "$kind" == SOCKS ]] && scheme=socks5h
        proxy="${scheme}://${host}:${port}"
        (( ${PROXY_URLS[(Ie)$proxy]} )) && continue
        PROXY_URLS+=( "$proxy" )
        PROXY_HOSTS+=( "$host" )
        PROXY_PORTS+=( "$port" )
    done <<< "$rows"
    (( ${#PROXY_URLS} > 0 ))
}
# 允许按本机网络选择系统代理或直连优先，不改变任何持久代理值。
configure_route_priority() {
    ROUTE_PRIORITY="${JOBS_GIT_ROUTE_PRIORITY:-$DEFAULT_ROUTE_PRIORITY}"
    case "$ROUTE_PRIORITY" in
        system|direct)
            return 0
            ;;
    esac
    print -u2 -r -- "[Jobs Git] JOBS_GIT_ROUTE_PRIORITY 无效，使用 ${DEFAULT_ROUTE_PRIORITY} 优先级。"
    ROUTE_PRIORITY="$DEFAULT_ROUTE_PRIORITY"
}
# 校验可配置短超时，避免错误环境值变成无限等待。
configure_probe_timeouts() {
    CONNECT_TIMEOUT="${JOBS_GIT_CONNECT_TIMEOUT:-2}"
    PROBE_TIMEOUT="${JOBS_GIT_PROBE_TIMEOUT:-4}"
    if [[ ! "$CONNECT_TIMEOUT" =~ '^[0-9]{1,2}$' ]] || (( 10#$CONNECT_TIMEOUT < 1 || 10#$CONNECT_TIMEOUT > 60 )); then
        print -u2 -r -- '[Jobs Git] JOBS_GIT_CONNECT_TIMEOUT 无效，使用 2 秒连接探测。'
        CONNECT_TIMEOUT=2
    fi
    if [[ ! "$PROBE_TIMEOUT" =~ '^[0-9]{1,3}$' ]] || (( 10#$PROBE_TIMEOUT < 1 || 10#$PROBE_TIMEOUT > 120 )); then
        print -u2 -r -- '[Jobs Git] JOBS_GIT_PROBE_TIMEOUT 无效，使用 4 秒总探测。'
        PROBE_TIMEOUT=4
    fi
}
# curl 只探测脱敏站点根地址；空代理强制直连，HTTP 错误状态仍说明连接已建立。
curl_head_status() {
    local -a route_args=( --proxy "$1" )
    [[ -n "$1" ]] || route_args+=( --noproxy '*' )
    /usr/bin/curl --disable --silent --head --output /dev/null --write-out '%{http_code}' \
        --connect-timeout "$CONNECT_TIMEOUT" --max-time "$PROBE_TIMEOUT" --proto '=http,https' \
        "${route_args[@]}" "$TARGET_ROOT" 2>/dev/null
}
# 只有 DNS、初始连接或未收到 HTTP 响应的超时允许自动改走代理。
is_initial_connection_probe_failure() {
    case "$1" in
        6|7|28)
            return 0
            ;;
    esac
    return 1
}
# TLS / 证书故障不通过换代理掩盖，也不关闭证书验证。
is_tls_probe_failure() {
    case "$1" in
        35|51|58|59|60|64|66|77|80|82|83|90|91)
            return 0
            ;;
    esac
    return 1
}
# 选路后仅运行一次原始 Git；代理参数只存在于这个子进程。
execute_selected_command() {
    local mode="$1" proxy="${2:-}" command_result=0
    local -a proxy_args=()
    if [[ -n "$proxy" ]]; then
        proxy_args=( -c "http.${TARGET_ROOT}.proxy=${proxy}" )
        real_git "${GLOBAL_ARGS[@]}" "${proxy_args[@]}" "$NETWORK_COMMAND" "${COMMAND_ARGS[@]}"
    else
        real_git "${ORIGINAL_ARGS[@]}"
    fi
    command_result=$?
    audit_result "$mode" "$TARGET_HOST" "$TARGET_PORT" "$command_result"
    return "$command_result"
}
# 只选择首个可用系统代理；返回失败时仍未启动任何 Git 网络业务。
probe_first_reachable_proxy() {
    local index=0 http_status='' probe_result=0
    SELECTED_PROXY=''
    for (( index = 1; index <= ${#PROXY_URLS}; index++ )); do
        http_status="$(curl_head_status "${PROXY_URLS[index]}")"
        probe_result=$?
        audit_result proxy-probe "${PROXY_HOSTS[index]}" "${PROXY_PORTS[index]}" "$probe_result"
        if [[ "$http_status" =~ '^[1-5][0-9][0-9]$' && "$http_status" != 407 ]]; then
            print -u2 -r -- "[Jobs Git] 已选择系统代理 ${PROXY_HOSTS[index]}:${PROXY_PORTS[index]}，执行本次 ${NETWORK_COMMAND}。"
            SELECTED_PROXY="${PROXY_URLS[index]}"
            return 0
        fi
        if is_tls_probe_failure "$probe_result"; then
            print -u2 -r -- '[Jobs Git] 系统代理探测遇到 TLS / 证书差异，不继续换路；使用该代理交给原生 Git 校验其 CA / 客户端证书。'
            SELECTED_PROXY="${PROXY_URLS[index]}"
            return 0
        fi
    done
    return 1
}
# 两路短探测均失败时快速返回，不创建 clone 目录或执行未知远端写入。
report_network_unavailable() {
    print -u2 -r -- "[Jobs Git] ${TARGET_HOST}:${TARGET_PORT} 的直连与当前系统代理均不可达；请检查网络或 VPN，未执行 Git 网络命令。"
    audit_result network-unavailable "$TARGET_HOST" "$TARGET_PORT" 128
    return 128
}
# 直连已经失败后只探测一次代理候选，业务执行失败时不重新选择线路。
execute_with_first_reachable_proxy() {
    if probe_first_reachable_proxy; then
        execute_selected_command proxy "$SELECTED_PROXY"
        return $?
    fi
    report_network_unavailable
}
# 先探测直连，仅明确初始连接故障才动态读取系统代理。
execute_direct_first_policy() {
    local http_status='' probe_result=0 discovery_result=0
    http_status="$(curl_head_status '')"
    probe_result=$?
    audit_result direct-probe "$TARGET_HOST" "$TARGET_PORT" "$probe_result"
    if [[ "$http_status" =~ '^[1-5][0-9][0-9]$' ]]; then
        execute_selected_command direct
        return $?
    fi
    if ! is_initial_connection_probe_failure "$probe_result"; then
        print -u2 -r -- '[Jobs Git] 直连探测未显示可安全换路的初始连接故障，交给原生 Git 校验，保留其 TLS 与认证配置。'
        execute_selected_command skip-probe-error
        return $?
    fi
    discover_system_proxies
    discovery_result=$?
    if (( discovery_result != 0 )); then
        if (( discovery_result == 2 )); then
            print -u2 -r -- '[Jobs Git] 直连不可达且目标命中系统或 NO_PROXY 旁路规则，不自动代理；未执行 Git 网络命令。'
            audit_result skip-bypass "$TARGET_HOST" "$TARGET_PORT" 128
        else
            print -u2 -r -- "[Jobs Git] ${TARGET_HOST}:${TARGET_PORT} 直连不可达，且当前没有启用的系统代理；请检查网络或开启 VPN，未执行 Git 网络命令。"
            audit_result no-system-proxy "$TARGET_HOST" "$TARGET_PORT" 128
        fi
        return 128
    fi
    execute_with_first_reachable_proxy
}
# 优先探测当前系统代理；所有候选均不可用后只回退探测直连一次。
execute_system_first_policy() {
    local discovery_result=0 http_status='' probe_result=0
    discover_system_proxies
    discovery_result=$?
    if (( discovery_result == 0 )) && probe_first_reachable_proxy; then
        execute_selected_command proxy "$SELECTED_PROXY"
        return $?
    fi
    http_status="$(curl_head_status '')"
    probe_result=$?
    audit_result direct-probe "$TARGET_HOST" "$TARGET_PORT" "$probe_result"
    if [[ "$http_status" =~ '^[1-5][0-9][0-9]$' ]]; then
        execute_selected_command direct
        return $?
    fi
    if ! is_initial_connection_probe_failure "$probe_result"; then
        print -u2 -r -- '[Jobs Git] 直连探测未显示可安全换路的初始连接故障，交给原生 Git 校验，保留其 TLS 与认证配置。'
        execute_selected_command skip-probe-error
        return $?
    fi
    if (( discovery_result == 2 )); then
        print -u2 -r -- '[Jobs Git] 直连不可达且目标命中系统或 NO_PROXY 旁路规则，不自动代理；未执行 Git 网络命令。'
        audit_result skip-bypass "$TARGET_HOST" "$TARGET_PORT" 128
        return 128
    fi
    if (( discovery_result != 0 )); then
        print -u2 -r -- "[Jobs Git] ${TARGET_HOST}:${TARGET_PORT} 直连不可达，且当前没有启用的系统代理；请检查网络或开启 VPN，未执行 Git 网络命令。"
        audit_result no-system-proxy "$TARGET_HOST" "$TARGET_PORT" 128
        return 128
    fi
    report_network_unavailable
}
# 先尊重显式代理，再按已确认优先级短探测，原始业务最多执行一次。
execute_network_policy() {
    setopt NO_NOMATCH
    prepare_audit
    if has_explicit_proxy; then
        print -u2 -r -- '[Jobs Git] 已有显式代理或显式空代理，保留原配置，不自动选路。'
        execute_selected_command skip-explicit-proxy
        return $?
    fi
    configure_probe_timeouts
    if [[ "$ROUTE_PRIORITY" == system ]]; then
        execute_system_first_policy
    else
        execute_direct_first_policy
    fi
}
# 编排透明入口与运行前选路，业务 Git 命令最多执行一次。
main() {
    show_network_intro_and_route "$@" # 本地与未知形式原生透传，明确 HTTP(S) 目标展示运行策略。
    execute_network_policy # 短探测直连与当前系统代理，选定后仅执行一次原始命令。
}

main "$@"
JOBS_GIT_DYNAMIC_PROXY_PAYLOAD_V1_EOF
}
# 唯一入口先显示脚本自述，再执行用户已经选择的作用域。
main() {
    show_script_intro_and_wait "$@" # 首先说明范围，双击时回车确认，检查模式保持只读。
    execute_confirmed_configuration "$?" # 入口确认成功后执行业务，并保留失败退出码。
}

main "$@"
