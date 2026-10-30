#!/bin/zsh
# 脚本自述：
# - 只供 source：复用 CocoaPods 独立脚本的 Homebrew 检测、系统/用户安装及复检流程。
# - 缺失时由本人选择安装路径：精确YES为系统目录，其它输入为用户目录；不写任何Shell启动文件。
# - CLT或Apple许可由本人处理；安装失败不自动改用另一位置，不继续下游。

typeset -g HB_SETUP_BREW="" HB_SETUP_PREFIX="" HB_SETUP_MODE=""
# 检查真实可执行性及安装前缀，存在坏shim按不可用处理。
hb_setup_probe() {
    local candidate="$1" prefix=""
    [[ -n "$candidate" && -x "$candidate" ]] || return 1
    HOMEBREW_NO_AUTO_UPDATE=1 "$candidate" --version >/dev/null 2>&1 || return 1
    prefix="$(HOMEBREW_NO_AUTO_UPDATE=1 "$candidate" --prefix 2>/dev/null)" || return 1
    [[ "$prefix" == /* && -d "$prefix" ]] || return 1
    HB_SETUP_BREW="${candidate:A}" HB_SETUP_PREFIX="$prefix"
}
# 复用已经安装的健康前缀，兼容独立脚本的用户目录安装方式。
hb_setup_find() {
    local candidate=""
    for candidate in "${JOBS_HOMEBREW_BIN:-}" "${PJ_BREW:-}" "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew "${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}/bin/brew" "$HOME/.homebrew/bin/brew"; do
        hb_setup_probe "$candidate" && return 0
    done
    return 1
}
# 新安装前核对CLT/Git，系统异步安装不伪报已经完成。
hb_setup_prerequisites() {
    local developer="" answer=""
    [[ -x /bin/bash && -x /usr/bin/curl && -x /usr/bin/git ]] || return 1
    developer="$(/usr/bin/xcode-select -p 2>/dev/null)"
    if [[ -n "$developer" && -d "$developer" ]] && /usr/bin/git --version >/dev/null 2>&1 && /usr/bin/xcrun clang --version >/dev/null 2>&1; then return 0; fi
    pe_event flutter.bootstrap.clt flutter.bootstrap 'Command Line Tools' attention '需要本人完成Apple工具安装/许可'
    pe_log '⚠ Homebrew安装需要Apple Command Line Tools。回车打开官方安装界面；安装与许可由本人处理，完成后重新运行。'
    IFS= read -r 'answer?回车打开CLT安装；其它输入取消：' || return 130
    [[ -z "$answer" ]] || return 130
    /usr/bin/xcode-select --install || { pe_log '➤ 系统未启动新安装，请检查已有安装窗口或在完整Xcode中完成首次配置。'; return 3; }
    return 3
}
# 精确YES选择系统目录，其他输入保留用户目录默认，不探测管理员密码。
hb_setup_choose_mode() {
    local answer="" system_prefix=/usr/local
    [[ "$(/usr/bin/uname -m)" != arm64 ]] || system_prefix=/opt/homebrew
    pe_log "⚠ Homebrew缺失。精确输入YES安装到系统标准目录$system_prefix，官方安装器可能要求管理员授权。"
    pe_log "➤ 其它输入或直接回车安装到用户目录${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}；失败不切换位置。Ctrl+C取消。"
    IFS= read -r 'answer?Homebrew安装位置：' || return 130
    if [[ "$answer" == YES ]]; then HB_SETUP_MODE=system; else HB_SETUP_MODE=user; fi
}
# 系统路线仅执行Homebrew官方安装器，由官方处理权限和交互。
hb_setup_install_system() {
    local installer="$PE_RUN_DIR/homebrew-install.sh" prefix=/usr/local
    [[ "$(/usr/bin/uname -m)" != arm64 ]] || prefix=/opt/homebrew
    pe_log "📥 来源：https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh；目标：$prefix。"
    pe_run_logged /usr/bin/curl --fail --location --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 120 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh --output "$installer" || return $?
    pe_run_logged /bin/bash "$installer" || return $?
    hb_setup_probe "$prefix/bin/brew"
}
# 用户路线固定官方稳定tag，先完整下载再发布，不覆盖已有非空安装。
hb_setup_install_user() {
    local prefix="${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}" stage="" tag="" result=0
    [[ "$prefix" == /* && "$prefix" != / && "$prefix" != *[[:space:]:]* && ! -L "$prefix" ]] || { pe_log '✖ 用户Homebrew前缀须为不含空白/冒号的普通绝对目录。'; return 1; }
    if [[ -e "$prefix" && ( ! -d "$prefix" || -n "$(/bin/ls -A "$prefix" 2>/dev/null)" ) ]]; then pe_log '✖ 用户Homebrew目标已有内容，未覆盖。'; return 1; fi
    [[ ! -L "${prefix:h}" ]] || return 1
    /bin/mkdir -p "${prefix:h}" || return 1
    stage="$(/usr/bin/mktemp -d "${prefix:h}/.jobs-homebrew.XXXXXX")" || return 1
    pe_log "📥 来源：https://api.github.com/repos/Homebrew/brew/releases/latest → https://github.com/Homebrew/brew.git；目标：$prefix。"
    pe_run_logged /usr/bin/curl --fail --location --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 60 https://api.github.com/repos/Homebrew/brew/releases/latest --output "$stage/release.json" || return $?
    tag="$(/usr/bin/plutil -extract tag_name raw -o - "$stage/release.json" 2>/dev/null)" || return 1
    [[ "$tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { pe_log '✖ 官方稳定版本元数据无效；保留下载现场。'; return 1; }
    pe_log "➤ Homebrew官方固定tag：$tag；用户路径安装可能需要本机编译依赖。"
    pe_run_logged /usr/bin/env GIT_TERMINAL_PROMPT=0 /usr/bin/git -c http.lowSpeedLimit=1024 -c http.lowSpeedTime=60 clone --depth 1 --branch "$tag" --single-branch https://github.com/Homebrew/brew.git "$stage/brew" || return $?
    pe_run_logged /usr/bin/git -C "$stage/brew" checkout -b stable || return $?
    pe_run_logged /usr/bin/git -C "$stage/brew" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' || return $?
    /bin/mkdir -p "$stage/brew/Cellar" "$stage/brew/Caskroom" "$stage/brew/etc" "$stage/brew/var" || return 1
    [[ ! -e "$prefix" ]] || /bin/rmdir "$prefix" || return 1
    /bin/mv -n "$stage/brew" "$prefix" || return 1
    /bin/rmdir "$stage" 2>/dev/null || true
    export HOMEBREW_NO_SUDO=1
    if [[ -z "${HOMEBREW_CASK_OPTS:-}" ]]; then export HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications"; fi
    hb_setup_probe "$prefix/bin/brew"
}
# 只把健康安装注入当前进程，不eval配置、不写.zprofile或系统PATH。
hb_setup_activate() {
    hb_setup_probe "$HB_SETUP_BREW" || return 1
    export PATH="$HB_SETUP_PREFIX/bin:$HB_SETUP_PREFIX/sbin:$PATH"
    rehash
    HOMEBREW_NO_AUTO_UPDATE=1 "$HB_SETUP_BREW" config >/dev/null 2>&1 || { pe_log '✖ Homebrew命令层复检失败。'; return 1; }
    typeset -g PJ_BREW="$HB_SETUP_BREW" PJ_BREW_PREFIX="$HB_SETUP_PREFIX"
    export JOBS_HOMEBREW_BIN="$HB_SETUP_BREW"
    pe_log "✔ Homebrew已就绪：$PJ_BREW；仅本流程PATH生效。"
}
# 新电脑依赖链入口：健康复用，缺失只修复一次并二次验证。
pe_prepare_homebrew() {
    local result=0 actual_version=""
    pe_event flutter.bootstrap flutter 'Homebrew基础工具' running '检测现有健康安装'
    if ! hb_setup_find; then
        [[ -t 0 && -t 1 && -n "$PE_RUN_DIR" ]] || { pe_log '✖ 缺少Homebrew，需要在交互终端选择安装位置。'; return 1; }
        hb_setup_prerequisites && hb_setup_choose_mode || return $?
        if [[ "$HB_SETUP_MODE" == system ]]; then hb_setup_install_system || result=$?;
        else hb_setup_install_user || result=$?; fi
        if (( result != 0 )); then pe_event flutter.bootstrap flutter 'Homebrew基础工具' failed "安装失败（$result），未改走其他位置"; return "$result"; fi
    fi
    hb_setup_activate || return $?
    actual_version="$(HOMEBREW_NO_AUTO_UPDATE=1 "$PJ_BREW" --version 2>/dev/null | /usr/bin/head -1)"
    pe_event flutter.bootstrap flutter 'Homebrew基础工具' succeeded "$PJ_BREW" "${actual_version:-版本未读取}"
}
