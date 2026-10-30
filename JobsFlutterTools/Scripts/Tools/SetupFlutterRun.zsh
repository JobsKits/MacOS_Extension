#!/bin/zsh
# 脚本自述：
# - 只供source：组合平台工具链、原生依赖、设备、启动配置和实际Flutter启动验收。
# - 使用父流程已选择的SDK；不自动同意许可、不绕过签名、不执行配置中的Shell任务。

typeset -g SR_TARGET="" SR_POD="" SR_DEVICE="" SR_CONFIG="" SR_XCODE="" SR_GEMFILE="" SR_STARTED=0 SR_POD_VERSION="" SR_BUNDLER_VERSION=""
typeset -g SR_ACTIVE_EVENT="" SR_ACTIVE_PARENT="" SR_ACTIVE_TITLE=""
typeset -g SR_RUBY="" SR_GEM="" SR_RUBY_REQUIREMENT="" SR_BUNDLER_MIN_RUBY=2.6
typeset -ga SR_POD_COMMAND=() SR_ARGS=() SR_BUNDLE_COMMAND=()
# 向GUI显示平台子步骤，终端仍打印完整原生命令日志。
sr_event() {
    if [[ "$4" == running ]]; then
        SR_ACTIVE_EVENT="$1" SR_ACTIVE_PARENT="$2" SR_ACTIVE_TITLE="$3"
    elif [[ "$1" == "$SR_ACTIVE_EVENT" && ( "$4" == succeeded || "$4" == failed || "$4" == attention ) ]]; then
        SR_ACTIVE_EVENT="" SR_ACTIVE_PARENT="" SR_ACTIVE_TITLE=""
    fi
    pe_event "$1" "$2" "$3" "$4" "${5:-}" "${6:-}"
}
# 父阶段退出时同时结束尚在运行的叶子，不把失败留成永久转圈。
sr_note_failure() {
    local result="$1" state=failed
    [[ -n "$SR_ACTIVE_EVENT" ]] || return 0
    (( result != 3 && result != 10 && result != 130 )) || state=attention
    pe_event "$SR_ACTIVE_EVENT" "$SR_ACTIVE_PARENT" "$SR_ACTIVE_TITLE" "$state" "退出码$result；请查看原始日志"
    SR_ACTIVE_EVENT="" SR_ACTIVE_PARENT="" SR_ACTIVE_TITLE=""
}
# 从当前项目已有平台选择目标，不自动生成平台源码。
sr_choose_target() {
    local target="" rows="" result=0
    for target in android ios macos web ohos; do
        [[ -d "$SF_PROJECT/$target" && ! -L "$SF_PROJECT/$target" ]] || continue
        [[ -z "$rows" ]] || rows+=$'\n'
        rows+="${target}"$'\t'"配置并运行 $target"
    done
    [[ -n "$rows" ]] || { pe_log '✖ 项目没有可在macOS准备/运行的android、ios、macos、web或ohos平台目录。'; return 1; }
    pe_select '目标平台' "$rows" || return $?
    SR_TARGET="$PE_SELECTION"
    sr_event platforms '' '平台工具链' pending "目标平台：$SR_TARGET"
}
# 完整Xcode由本人安装与接受许可；选择开发目录只作用当前进程。
sr_prepare_xcode() {
    local developer="${DEVELOPER_DIR:-}" app="" rows="" answer="" result=0
    sr_event "platforms.$SR_TARGET.xcode" "platforms.$SR_TARGET" 'Xcode与CLT' running
    [[ -n "$developer" ]] || developer="$(/usr/bin/xcode-select -p 2>/dev/null)"
    if [[ "$developer" != *.app/Contents/Developer || ! -d "$developer" ]]; then
        for app in /Applications/Xcode*.app(N) "$HOME"/Applications/Xcode*.app(N); do
            [[ -d "$app/Contents/Developer" ]] || continue
            [[ -z "$rows" ]] || rows+=$'\n'
            rows+="${app}/Contents/Developer"$'\t'"使用 ${app:t}（仅本次进程）"
        done
        [[ -z "$rows" ]] || rows+=$'\n'
        rows+=$'manual\t选择其它完整Xcode.app路径\nstore\t打开Mac App Store安装Xcode（本人操作后重试）'
        pe_select Xcode "$rows" || return $?
        case "$PE_SELECTION" in
            store) /usr/bin/open 'macappstore://itunes.apple.com/app/id497799835'; sr_event "platforms.$SR_TARGET.xcode" "platforms.$SR_TARGET" 'Xcode与CLT' attention '请本人完成Xcode安装后重新运行'; return 3 ;;
            manual)
                IFS= read -r 'app?完整Xcode.app绝对路径（空输入取消）：' || return 130
                [[ "$app" == /* && -d "$app/Contents/Developer" ]] || return 2
                developer="$app/Contents/Developer" ;;
            *) developer="$PE_SELECTION" ;;
        esac
    fi
    [[ -x "$developer/usr/bin/xcodebuild" && -x "$developer/usr/bin/xcrun" || -x /usr/bin/xcrun ]] || return 1
    export DEVELOPER_DIR="$developer"
    SR_XCODE="${developer%/Contents/Developer}"
    pe_log "➤ 本次Xcode：$SR_XCODE；仅DEVELOPER_DIR生效，不修改系统xcode-select。"
    sf_run_diagnostic xcode /usr/bin/xcodebuild -version || return $?
    while ! /usr/bin/xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; do
        sr_event "platforms.$SR_TARGET.xcode" "platforms.$SR_TARGET" 'Xcode与CLT' attention '首次组件/许可需本人在Xcode完成'
        pe_log '⚠ Xcode首次组件或许可尚未完成；请本人阅读同意许可并安装组件，脚本不会代签接受。'
        pe_select Xcode $'open\t打开所选Xcode完成首次配置\nretry\t已完成，重新检查\nstop\t保留已完成环境，稍后继续' || return $?
        case "$PE_SELECTION" in open) /usr/bin/open -a "$SR_XCODE" ;; retry) ;; stop) return 3 ;; esac
    done
    sf_run_diagnostic clang /usr/bin/xcrun clang --version || return $?
    local xcode_version="$(/usr/bin/perl -ne 's/\r?\n$//; push @v,$_ if /^(?:Xcode|Build version)\s+/; END {print join(" · ",@v)}' "$PE_RUN_DIR/xcode.log")"
    sr_event "platforms.$SR_TARGET.xcode" "platforms.$SR_TARGET" 'Xcode与CLT' succeeded "$SR_XCODE" "$xcode_version"
}
# CocoaPods安装复用既有脚本的brew优先、Brew Ruby gem兜底和安装后二次验证。
sr_prepare_cocoapods() {
    local candidate="" prefix="" gem_home="" result=0 answer=""
    sr_event "platforms.$SR_TARGET.pods" "platforms.$SR_TARGET" 'CocoaPods环境' running
    for candidate in "$(command -v pod 2>/dev/null)" /opt/homebrew/bin/pod /usr/local/bin/pod; do
        if [[ -x "$candidate" ]] && SF_COMMAND_TIMEOUT=60 sf_run_diagnostic pod-version "$candidate" --version; then SR_POD="$candidate"; break; fi
    done
    if [[ -z "$SR_POD" ]]; then
        pj_find_brew || return $?
        pe_log '📥 来源：https://formulae.brew.sh/formula/cocoapods；缺少CocoaPods将安装到当前Homebrew前缀，健康工具不升级。'
        IFS= read -r 'answer?回车安装CocoaPods；其它输入取消：' || return 130
        [[ -z "$answer" ]] || return 130
        result=0
        SF_COMMAND_TIMEOUT=1800 sf_run_diagnostic cocoapods-install /usr/bin/env HOMEBREW_NO_AUTO_UPDATE=1 "$PJ_BREW" install cocoapods || result=$?
        if (( result )); then
            pe_log '⚠ Brew安装失败；改用Homebrew Ruby的用户级gem，不改全局gem源或Shell配置。'
            SF_COMMAND_TIMEOUT=1800 sf_run_diagnostic ruby-install /usr/bin/env HOMEBREW_NO_AUTO_UPDATE=1 "$PJ_BREW" install ruby || return $?
            prefix="$(HOMEBREW_NO_AUTO_UPDATE=1 "$PJ_BREW" --prefix ruby)" || return 1
            [[ -x "$prefix/bin/ruby" && -x "$prefix/bin/gem" ]] || return 1
            export PATH="$prefix/bin:$PATH"
            SF_COMMAND_TIMEOUT=1800 sf_run_diagnostic cocoapods-gem "$prefix/bin/gem" install cocoapods --no-document --user-install --clear-sources --source https://rubygems.org || return $?
            gem_home="$("$prefix/bin/ruby" -e 'puts Gem.user_dir')" || return 1
            [[ "$gem_home" == /* ]] || return 1
            export PATH="$gem_home/bin:$PATH"
            SR_POD="$gem_home/bin/pod"
        else
            SR_POD="$PJ_BREW_PREFIX/bin/pod"
        fi
        [[ -x "$SR_POD" ]] && SF_COMMAND_TIMEOUT=60 sf_run_diagnostic pod-version "$SR_POD" --version || { pe_log '✖ CocoaPods安装后复检失败。'; return 1; }
    fi
    SR_POD_COMMAND=("$SR_POD")
    for candidate in "$SF_PROJECT/$SR_TARGET/Gemfile" "$SF_PROJECT/Gemfile"; do
        if [[ -f "$candidate" && ! -L "$candidate" ]] && /usr/bin/grep -Eq "gem[[:space:]]+['\"]cocoapods['\"]" "$candidate"; then SR_GEMFILE="$candidate"; break; fi
    done
    if [[ -n "$SR_GEMFILE" ]]; then
        export BUNDLE_GEMFILE="$SR_GEMFILE"
        sr_ensure_bundler || return $?
        SF_COMMAND_TIMEOUT=1200 sf_run_diagnostic bundle-install "${SR_BUNDLE_COMMAND[@]}" install || return $?
        SR_POD_COMMAND=("${SR_BUNDLE_COMMAND[@]}" exec pod)
    fi
    SF_COMMAND_TIMEOUT=60 sf_run_diagnostic project-pod-version "${SR_POD_COMMAND[@]}" --version || return $?
    SR_POD_VERSION="$(pe_semantic_version "$PE_RUN_DIR/project-pod-version.log" pods)"
    sr_event "platforms.$SR_TARGET.pods" "platforms.$SR_TARGET" 'CocoaPods环境' succeeded '可用版本已验证；项目Gemfile存在时通过Bundler执行' "${SR_POD_VERSION:+CocoaPods $SR_POD_VERSION}"
}
# 依Gemfile.lock固定Bundler，缺失时通过健康Ruby用户级gem补齐并复检。
sr_ensure_bundler() {
    local version="" bundle="$(command -v bundle 2>/dev/null)" ruby="$(command -v ruby 2>/dev/null)" gem="$(command -v gem 2>/dev/null)" gem_home="" prefix=""
    local -a selector install_options
    if [[ -f "$SR_GEMFILE.lock" && ! -L "$SR_GEMFILE.lock" ]]; then
        version="$(/usr/bin/awk '/^BUNDLED WITH$/ {getline; gsub(/^[ \t]+|[ \t\r]+$/, ""); print; exit}' "$SR_GEMFILE.lock")"
        [[ -z "$version" || "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { pe_log '✖ Gemfile.lock的BUNDLED WITH无效。'; return 1; }
    fi
    selector=()
    [[ -z "$version" ]] || selector=("_${version}_")
    if [[ -x "$bundle" ]] && SF_COMMAND_TIMEOUT=60 sf_run_diagnostic bundler-version "$bundle" "${selector[@]}" --version; then
        SR_BUNDLE_COMMAND=("$bundle" "${selector[@]}")
        SR_BUNDLER_VERSION="$(pe_semantic_version "$PE_RUN_DIR/bundler-version.log" bundler)"
        sr_event "platforms.$SR_TARGET.bundler" "platforms.$SR_TARGET" 'Ruby与固定Bundler' succeeded "$bundle" "${SR_BUNDLER_VERSION:+Bundler $SR_BUNDLER_VERSION}"
        return 0
    fi
    sr_event "platforms.$SR_TARGET.bundler" "platforms.$SR_TARGET" 'Ruby与固定Bundler' running "Gemfile.lock要求：${version:-未锁定}"
    sr_select_compatible_ruby "$version" || return $?
    ruby="$SR_RUBY" gem="$SR_GEM"
    export PATH="${ruby:h}:$PATH"
    install_options=(install bundler --user-install --no-document --clear-sources --source https://rubygems.org)
    [[ -z "$version" ]] || install_options+=(--version "$version")
    pe_log "📥 来源：https://rubygems.org/gems/bundler；版本：${version:-RubyGems兼容版本}；用户级安装，不改gem源或全局Shell。"
    SF_COMMAND_TIMEOUT=1200 sf_run_diagnostic bundler-install "$gem" "${install_options[@]}" || return $?
    gem_home="$("$ruby" -e 'puts Gem.user_dir')" || return 1
    [[ "$gem_home" == /* ]] || return 1
    export PATH="$gem_home/bin:$PATH"
    bundle="$gem_home/bin/bundle"
    [[ -x "$bundle" ]] && SF_COMMAND_TIMEOUT=60 sf_run_diagnostic bundler-version "$bundle" "${selector[@]}" --version || { pe_log '✖ 固定Bundler安装后复检失败，请检查工程Ruby版本约束与上方日志。'; return 1; }
    SR_BUNDLE_COMMAND=("$bundle" "${selector[@]}")
    SR_BUNDLER_VERSION="$(pe_semantic_version "$PE_RUN_DIR/bundler-version.log" bundler)"
    sr_event "platforms.$SR_TARGET.bundler" "platforms.$SR_TARGET" 'Ruby与固定Bundler' succeeded "$bundle" "${SR_BUNDLER_VERSION:+Bundler $SR_BUNDLER_VERSION}"
}
# RubyGems已核实的Bundler运行下限，另保留工程Gemfile中的静态Ruby要求。
sr_ruby_compatible() {
    local ruby="$1" gem="$2"
    [[ -x "$ruby" && -x "$gem" ]] && "$gem" --version >/dev/null 2>&1 || return 1
    "$ruby" -rrubygems -e 'v=Gem::Version.new(RUBY_VERSION); exit 1 unless Gem::Requirement.new(">= " + ARGV[0]).satisfied_by?(v); r=ARGV[1]; exit 1 if !r.empty? && !Gem::Requirement.new(r).satisfied_by?(v)' "$SR_BUNDLER_MIN_RUBY" "$SR_RUBY_REQUIREMENT" >/dev/null 2>&1
}
# 复用兼容Ruby，系统Ruby过旧时改用已装Brew Ruby或精确主次版本公式，安装后再核对。
sr_select_compatible_ruby() {
    local bundler="$1" ruby="" gem="" prefix="" candidate="" formula=ruby requested=""
    local -a candidates
    SR_RUBY_REQUIREMENT="$(/usr/bin/perl -ne 'if (/^\s*ruby\s+["\x27]([^"\x27]+)["\x27]\s*(?:#.*)?$/) {print $1; exit}' "$SR_GEMFILE")" || return 1
    SR_BUNDLER_MIN_RUBY=2.6
    if [[ -z "$bundler" ]] || dg_version_at_least "$bundler" 4.0; then SR_BUNDLER_MIN_RUBY=3.2
    elif dg_version_at_least "$bundler" 2.6; then SR_BUNDLER_MIN_RUBY=3.1
    elif dg_version_at_least "$bundler" 2.5; then SR_BUNDLER_MIN_RUBY=3.0; fi
    candidates=("$(command -v ruby 2>/dev/null)" "${PJ_BREW_PREFIX:-$HOME/.local/homebrew}/opt/ruby/bin/ruby" /opt/homebrew/opt/ruby/bin/ruby /usr/local/opt/ruby/bin/ruby)
    for candidate in "${candidates[@]}"; do
        [[ -n "$candidate" ]] || continue
        gem="${candidate:h}/gem"
        if sr_ruby_compatible "$candidate" "$gem"; then SR_RUBY="$candidate" SR_GEM="$gem"; return 0; fi
    done
    pe_log "➤ 当前Ruby不满足Bundler ${bundler:-默认版本}（最低Ruby $SR_BUNDLER_MIN_RUBY）或Gemfile约束 ${SR_RUBY_REQUIREMENT:-无}；准备兼容Ruby。"
    if ! pj_find_brew; then
        source "$PE_TOOLS_DIR/SetupHomebrew.zsh" || return $?
        pe_prepare_homebrew || return $?
    fi
    # 静态主次版本要求可用Brew版本化公式；精确补丁不满足时停止，不篡改Gemfile。
    requested="$(print -r -- "$SR_RUBY_REQUIREMENT" | /usr/bin/perl -ne 'if (/(\d+)\.(\d+)/) {print "$1.$2"}')"
    [[ -z "$requested" ]] || formula="ruby@$requested"
    prefix="$(HOMEBREW_NO_AUTO_UPDATE=1 "$PJ_BREW" --prefix "$formula" 2>/dev/null)"
    if [[ "$prefix" == /* ]] && sr_ruby_compatible "$prefix/bin/ruby" "$prefix/bin/gem"; then SR_RUBY="$prefix/bin/ruby" SR_GEM="$prefix/bin/gem"; return 0; fi
    pe_log "📥 来源：https://formulae.brew.sh/formula/$formula；目标：当前Homebrew前缀；不改系统Ruby或Gemfile。"
    SF_COMMAND_TIMEOUT=1800 sf_run_diagnostic ruby-install /usr/bin/env HOMEBREW_NO_AUTO_UPDATE=1 "$PJ_BREW" install "$formula" || return $?
    prefix="$(HOMEBREW_NO_AUTO_UPDATE=1 "$PJ_BREW" --prefix "$formula")" || return 1
    sr_ruby_compatible "$prefix/bin/ruby" "$prefix/bin/gem" || { pe_log '✖ 安装后的Ruby仍不满足工程/Bundler约束，保留已装工具，请按工程精确Ruby版本重试；不改锁文件。'; return 3; }
    SR_RUBY="$prefix/bin/ruby" SR_GEM="$prefix/bin/gem"
}
# Web目标需要真实可执行的Chromium浏览器，缺失时提供安装/指定路径并复检。
sr_prepare_web() {
    local candidate="" answer="" result=0
    sr_event platforms.web platforms 'Web工具链' running
    sr_event platforms.web.browser platforms.web 'Chrome或Edge浏览器' running
    for candidate in "${CHROME_EXECUTABLE:-}" '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' "$HOME/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge'; do
        if [[ -n "$candidate" && -x "$candidate" ]] && SF_COMMAND_TIMEOUT=30 sf_run_diagnostic browser "$candidate" --version; then
            export CHROME_EXECUTABLE="${candidate:A}"
            sr_event platforms.web.browser platforms.web 'Chrome或Edge浏览器' succeeded "$CHROME_EXECUTABLE" "$(pe_semantic_version "$PE_RUN_DIR/browser.log" browser)"
            sr_event platforms.web platforms 'Web工具链' succeeded
            return 0
        fi
    done
    while true; do
        sr_event platforms.web.browser platforms.web 'Chrome或Edge浏览器' attention '未发现可用Chromium浏览器，可安装或选择本机路径'
        pe_select 浏览器 $'install\t通过Homebrew官方cask安装Google Chrome\nmanual\t选择已有Chrome/Edge可执行文件\nstop\t保留准备结果，稍后配置浏览器' || return $?
        case "$PE_SELECTION" in
            install)
                pj_find_brew || return $?
                pe_log '📥 来源：https://formulae.brew.sh/cask/google-chrome；安装到本机Homebrew应用目录。'
                IFS= read -r 'answer?按回车安装Chrome；其它输入取消：' || return 130
                [[ -z "$answer" ]] || return 130
                SF_COMMAND_TIMEOUT=1800 sf_run_diagnostic chrome-install /usr/bin/env HOMEBREW_NO_AUTO_UPDATE=1 "$PJ_BREW" install --cask google-chrome || return $?
                candidate='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
                [[ -x "$candidate" ]] || candidate="$HOME/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ;;
            manual) IFS= read -r 'candidate?浏览器可执行文件绝对路径（空输入取消）：' || return 130; [[ -n "$candidate" ]] || return 130 ;;
            stop) return 3 ;;
        esac
        if [[ "$candidate" == /* && -x "$candidate" ]] && SF_COMMAND_TIMEOUT=30 sf_run_diagnostic browser "$candidate" --version; then
            export CHROME_EXECUTABLE="${candidate:A}"
            sr_event platforms.web.browser platforms.web 'Chrome或Edge浏览器' succeeded "$CHROME_EXECUTABLE" "$(pe_semantic_version "$PE_RUN_DIR/browser.log" browser)"
            sr_event platforms.web platforms 'Web工具链' succeeded
            return 0
        fi
        pe_log '✖ 选定浏览器不可执行，请重选。'
    done
}
# Apple平台先准备完整Xcode，再补CocoaPods；SPM工程保持原项目选择。
sr_prepare_apple_platform() {
    sr_event "platforms.$SR_TARGET" platforms "${SR_TARGET}工具链" running
    sr_prepare_xcode || return $?
    if [[ -f "$SF_PROJECT/$SR_TARGET/Podfile" && ! -L "$SF_PROJECT/$SR_TARGET/Podfile" ]]; then sr_prepare_cocoapods || return $?;
    else sr_event "platforms.$SR_TARGET.pods" "platforms.$SR_TARGET" 'CocoaPods环境' succeeded '无Podfile，沿用工程SPM/无Pods配置'; fi
    sr_event "platforms.$SR_TARGET.signing" "platforms.$SR_TARGET" '签名与平台约束' attention '真机签名、Team、描述文件与供应商模拟器切片以实际启动结果为准，不自动改工程签名'
    sr_event "platforms.$SR_TARGET" platforms "${SR_TARGET}工具链" succeeded
}
# 平台依赖解析排在pub get之后，不自动执行pod update或接受签名条款。
sr_install_native_dependencies() {
    if [[ "$SR_TARGET" == ios || "$SR_TARGET" == macos ]] && [[ -f "$SF_PROJECT/$SR_TARGET/Podfile" ]]; then
        sr_event "platforms.$SR_TARGET.pod-install" "platforms.$SR_TARGET" '原生第三方依赖' running
        SF_COMMAND_TIMEOUT=1800 sf_run_diagnostic pod-install /usr/bin/env COCOAPODS_DISABLE_STATS=true "LANG=${LANG:-en_US.UTF-8}" "${SR_POD_COMMAND[@]}" install "--project-directory=$SF_PROJECT/$SR_TARGET" || return $?
        sr_event "platforms.$SR_TARGET.pod-install" "platforms.$SR_TARGET" '原生第三方依赖' succeeded 'pod install完成，保留Podfile.lock版本策略'
    fi
}
# 平台预缓存使用选定Flutter，失败停止而非等到构建时重复隐式下载。
sr_precache_target() {
    [[ "$SR_TARGET" != ohos ]] || { pe_log '➤ 鸿蒙适配 SDK 的平台资源以该 SDK 的 precache --ohos 实际结果为准。'; }
    sr_event "platforms.$SR_TARGET.flutter-cache" "platforms.$SR_TARGET" 'Flutter平台资源' running
    SF_COMMAND_TIMEOUT=1800 sf_run_diagnostic flutter-precache "$SF_FLUTTER" precache "--$SR_TARGET" || return $?
    sr_event "platforms.$SR_TARGET.flutter-cache" "platforms.$SR_TARGET" 'Flutter平台资源' succeeded '' "${SF_FLUTTER_VERSION:+Flutter $SF_FLUTTER_VERSION}${SF_DART_VERSION:+ · Dart $SF_DART_VERSION}"
}
# 设备发现只接受目标平台，空列表提供重载和现有完整模拟器入口。
sr_choose_device() {
    local rows="" result=0
    sr_event readiness.devices readiness '发现与选择设备' running
    while true; do
        result=0
        sf_run_diagnostic devices "$SF_FLUTTER" devices --machine --device-timeout 10 || result=$?
        rows=""
        if (( result == 0 )); then rows="$(/usr/bin/osascript -l JavaScript "$PE_TOOLS_DIR/SetupFlutterRun.jxa" devices "$PE_RUN_DIR/devices.log" "$SR_TARGET")" || rows=""; fi
        if [[ -z "$rows" ]]; then
            sr_event readiness.devices readiness '发现与选择设备' attention '暂无目标平台可运行设备；可重载或创建/启动模拟器'
            pe_log '⚠ 暂无目标平台可运行设备；连接并授权真机，或通过下面入口创建/启动模拟器后重新加载。'
        fi
        [[ -z "$rows" ]] || rows+=$'\n'
        rows+=$'refresh\t重新加载设备列表'
        [[ "$SR_TARGET" != ios ]] || rows+=$'\ncreate\t新建并启动iOS模拟器（完整型号/Runtime选择）'
        [[ "$SR_TARGET" != android ]] || rows+=$'\ncreate\t启动已有/创建Android模拟器（完整工具入口）'
        rows+=$'\nstop\t保留环境准备结果，稍后连接设备'
        result=0; pe_select 设备 "$rows" || result=$?
        (( result != 10 )) || return 10
        (( result == 0 )) || return "$result"
        case "$PE_SELECTION" in
            refresh) continue ;;
            stop) return 3 ;;
            create)
                if [[ "$SR_TARGET" == ios ]]; then /bin/zsh "$PE_TOOLS_DIR/SetupCreateIOSSimulator.zsh" || return $?;
                else /bin/zsh "$PE_TOOLS_DIR/SetupCreateAndroidSimulator.zsh" || return $?; fi
                continue ;;
            *) SR_DEVICE="$PE_SELECTION"; sr_event readiness.devices readiness '发现与选择设备' succeeded "$SR_DEVICE"; return 0 ;;
        esac
    done
}
# 从已存在配置选择启动参数；配置解析只产出白名单数据，不运行preLaunchTask。
sr_choose_configuration() {
    local rows="" arguments="" result=0
    sr_event readiness.configuration readiness '启动配置' running
    SR_CONFIG="$PE_RUN_DIR/launch-configurations.json"
    /usr/bin/osascript -l JavaScript "$PE_TOOLS_DIR/SetupFlutterRun.jxa" configs "$SF_PROJECT" > "$SR_CONFIG" 2> "$PE_RUN_DIR/launch-configurations.err" || { /bin/cat "$PE_RUN_DIR/launch-configurations.err" | pe_filter_log; return 1; }
    [[ ! -s "$PE_RUN_DIR/launch-configurations.err" ]] || /bin/cat "$PE_RUN_DIR/launch-configurations.err" | pe_filter_log
    rows="$(/usr/bin/osascript -l JavaScript "$PE_TOOLS_DIR/SetupFlutterRun.jxa" config-rows "$SR_CONFIG")" || return 1
    rows+=$'\nmanual\t手动输入入口、flavor、模式与dart-define'
    pe_select '启动配置' "$rows" || return $?
    if [[ "$PE_SELECTION" == manual ]]; then sr_manual_configuration || return $?;
    else
        arguments="$(/usr/bin/osascript -l JavaScript "$PE_TOOLS_DIR/SetupFlutterRun.jxa" args "$SR_CONFIG" "$PE_SELECTION")" || return 1
        SR_ARGS=("${(@f)arguments}")
    fi
    sr_validate_arguments || return $?
    sr_event readiness.configuration readiness '启动配置' succeeded '模式、flavor、入口和dart-define已选择；不执行配置任务'
}
# 自由文本全部作为单个参数加入数组，回车默认入口和debug，空define结束。
sr_manual_configuration() {
    local target="" flavor="" mode="" define=""
    IFS= read -r 'target?Dart入口（相对工程目录；回车lib/main.dart）：' || return 130
    [[ -n "$target" ]] || target=lib/main.dart
    IFS= read -r 'flavor?flavor（回车不指定）：' || return 130
    pe_select '运行模式' $'debug\tdebug（推荐）\nprofile\tprofile\nrelease\trelease' || return $?
    mode="$PE_SELECTION"
    SR_ARGS=("--$mode" --target "$target")
    [[ -z "$flavor" ]] || SR_ARGS+=(--flavor "$flavor")
    while true; do
        IFS= read -r 'define?dart-define，格式KEY=VALUE（一行一个，回车结束；不会写入项目文件）：' || return 130
        [[ -n "$define" ]] || break
        [[ "$define" =~ '^[A-Za-z_][A-Za-z0-9_]*=' ]] || { pe_log '✖ dart-define需要KEY=VALUE。'; return 2; }
        SR_ARGS+=(--dart-define "$define")
    done
}
# 入口和define文件必须为工程内普通文件，路径/参数都不经过Shell求值。
sr_validate_arguments() {
    local index=0 arg="" value="" target=lib/main.dart candidate="" kind=""
    for (( index=1; index<=${#SR_ARGS}; index++ )); do
        arg="${SR_ARGS[index]}" value="" kind=""
        if [[ "$arg" == --target || "$arg" == -t || "$arg" == --dart-define-from-file || "$arg" == --flavor ]]; then
            (( index++ )); value="${SR_ARGS[index]}"; kind="$arg"
        elif [[ "$arg" == --target=* || "$arg" == --dart-define-from-file=* || "$arg" == --flavor=* ]]; then
            value="${arg#*=}"; kind="${arg%%=*}"
        fi
        [[ "$kind" != --flavor ]] || { [[ "$value" =~ '^[A-Za-z0-9][A-Za-z0-9_.-]*$' ]] || return 2; }
        if [[ "$kind" == --target || "$kind" == -t || "$kind" == --dart-define-from-file ]]; then
            [[ -n "$value" && "$value" != /* ]] || { pe_log '✖ 入口/define文件须位于工程内并使用相对路径。'; return 2; }
            candidate="$SF_PROJECT/$value"
            [[ -f "$candidate" && ! -L "$candidate" && "${candidate:A}" == "$SF_PROJECT/"* ]] || { pe_log '✖ 入口或define文件缺失、越界或为链接。'; return 2; }
            [[ "$kind" != --target && "$kind" != -t ]] || target="$value"
        fi
    done
    candidate="$SF_PROJECT/$target"
    [[ -f "$candidate" && ! -L "$candidate" && "${candidate:A}" == "$SF_PROJECT/"* && "$candidate" == *.dart ]] || { pe_log '✖ 缺少合法Dart入口；请选择正确启动配置。'; return 1; }
}
# 原流旁路仅保留启动协议最小事件，普通超大日志行丢弃于旁路，完整raw日志不截断。
sr_machine_events() {
    /usr/bin/perl -MJSON::PP -e '
        $|=1; my $json=JSON::PP->new->utf8->canonical; my($buffer,$discard)=("",0);
        sub emit_line {
            my($line)=@_; return unless $line =~ /^\s*\[/;
            my $items=eval {$json->decode($line)}; return unless ref($items) eq "ARRAY";
            for my $event (@$items) {
                next unless ref($event) eq "HASH" && ($event->{event}//"") =~ /^app\.(?:start|started)$/;
                my $p=$event->{params}; next unless ref($p) eq "HASH" && defined($p->{appId}) && !ref($p->{appId}) && length($p->{appId}) && $p->{appId} !~ /[\x00-\x1f\x7f]/;
                my %params=(appId=>$p->{appId}); $params{deviceId}=$p->{deviceId} if defined($p->{deviceId}) && !ref($p->{deviceId});
                print $json->encode([{event=>$event->{event},params=>\%params}]),"\n";
            }
        }
        while (sysread(STDIN,my $chunk,65536)) {
            for my $part (split(/(\n)/,$chunk,-1)) {
                if ($part eq "\n") {emit_line($buffer) unless $discard; ($buffer,$discard)=("",0);}
                elsif (!$discard) {$buffer.=$part; if(length($buffer)>1048576) {($buffer,$discard)=("",1);}}
            }
        }
        emit_line($buffer) if length($buffer) && !$discard;
    '
}
# 真正运行Flutter并等待app.started，收到后发送detach使应用保留在设备上。
sr_verify_run() {
    local answer="" pid=0 timer=0 result=0 app="" seconds="${JOBS_FLUTTER_RUN_TIMEOUT:-1800}" fifo="$PE_RUN_DIR/flutter-run.fifo" tick=0
    [[ "$seconds" == <-> && "$seconds" -ge 30 && "$seconds" -le 7200 ]] || return 2
    pe_log "➤ 即将使用选定SDK在设备${SR_DEVICE}执行Flutter run；会构建、签名及安装到该设备，成功启动后detach保留App运行。"
    pe_log '➤ 真机安装可能覆盖相同包名已有App；不自动修改Team/Bundle ID，不绕过设备资格、描述文件或供应商架构限制。'
    IFS= read -r 'answer?按回车开始实际启动验证；其它输入取消：' || return 130
    [[ -z "$answer" ]] || return 130
    sr_validate_arguments || return $?
    pe_validate_project "$SF_PROJECT" || { pe_log '✖ 等待期间项目身份发生变化，未启动。'; return 1; }
    sr_event readiness.run readiness '实际构建、安装与启动' running "设备：$SR_DEVICE"
    /usr/bin/mkfifo "$fifo" || return 1
    exec {SR_CONTROL_FD}<>"$fifo" || return 1
    (
        cd -- "$SF_PROJECT" || exit 1
        JAVA_HOME="$SF_JAVA_HOME" PATH="$SF_JAVA_HOME/bin:$PATH" GRADLE_OPTS="${GRADLE_OPTS:+$GRADLE_OPTS }-Dorg.gradle.java.home=\"$SF_JAVA_HOME\"" "$SF_FLUTTER" run --machine -d "$SR_DEVICE" "${SR_ARGS[@]}" < "$fifo" 2>&1 | /usr/bin/tee "$PE_RUN_DIR/flutter-run.log" >(pe_filter_log >> "$PE_LOG_FILE") >(sr_machine_events > "$PE_RUN_DIR/flutter-run.events.jsonl")
        exit ${pipestatus[1]}
    ) &
    pid=$!
    (
        trap 'exit 0' TERM INT HUP
        /bin/sleep "$seconds" || exit 0
        print timeout > "$PE_RUN_DIR/flutter-run.timeout"
        dg_stop_timed_out_tree "$pid"
    ) &
    timer=$!
    trap 'dg_stop_timed_out_tree "$pid"; dg_terminate_tree "$timer"; exec {SR_CONTROL_FD}>&-; exit 130' INT TERM HUP
    while /bin/kill -0 "$pid" 2>/dev/null; do
        if /usr/bin/grep -q 'app.started' "$PE_RUN_DIR/flutter-run.events.jsonl" 2>/dev/null; then
            app="$(/usr/bin/osascript -l JavaScript "$PE_TOOLS_DIR/SetupFlutterRun.jxa" started "$PE_RUN_DIR/flutter-run.events.jsonl" "$SR_DEVICE" 2>/dev/null)"
            if [[ -n "$app" ]]; then
                /usr/bin/osascript -l JavaScript "$PE_TOOLS_DIR/SetupFlutterRun.jxa" detach "$app" >&$SR_CONTROL_FD || break
                SR_STARTED=1
                break
            fi
        fi
        /bin/sleep 1
    done
    if (( SR_STARTED )); then
        for tick in {1..20}; do /bin/kill -0 "$pid" 2>/dev/null || break; /bin/sleep 0.25; done
        if /bin/kill -0 "$pid" 2>/dev/null; then pe_log '⚠ App已启动但Flutter控制进程未及时detach，停止本次控制子树。'; dg_stop_timed_out_tree "$pid"; fi
    fi
    wait "$pid" || result=$?
    dg_terminate_tree "$timer"
    wait "$timer" 2>/dev/null || true
    exec {SR_CONTROL_FD}>&-
    trap - INT TERM HUP
    [[ ! -f "$PE_RUN_DIR/flutter-run.timeout" ]] || { sr_event readiness.run readiness '实际构建、安装与启动' failed '运行验证超时，保留日志'; return 124; }
    if (( ! SR_STARTED || result != 0 )); then
        sr_event readiness.run readiness '实际构建、安装与启动' attention '构建/签名/安装/启动未全部通过，请按原始日志处理；不宣称可运行'
        pe_log "✖ 实际运行验证未通过（$result）；日志：$PE_RUN_DIR/flutter-run.log。请核对签名、设备授权、flavor、原生SDK切片和业务依赖。"
        (( result != 0 )) && return "$result"
        return 3
    fi
    sr_event readiness.run readiness '实际构建、安装与启动' succeeded '已收到Flutter app.started，并正常detach；设备App保留运行'
    if [[ "$SR_TARGET" == ios || "$SR_TARGET" == macos ]]; then sr_event "platforms.$SR_TARGET.signing" "platforms.$SR_TARGET" '签名与平台约束' succeeded '所选设备本次构建/安装已通过，未更改项目签名策略'; fi
    sr_event readiness '' '运行验证' succeeded '实际构建安装启动通过，业务功能需本人验收'
    pe_log "✔ 实际启动验证通过：设备$SR_DEVICE；已收到app.started并detach，App保留运行；业务功能仍需本人验收。"
}
# 运行验证为明确选择，准备完成不自动冒充启动通过。
sr_offer_run() {
    local result=0
    while true; do
        result=0
        pe_select '收尾方式' $'run\t选择设备，实际安装并启动验证（推荐）\nprepare\t仅保留依赖和构建准备结果，不安装/启动App' || result=$?
        (( result == 0 )) || return "$result"
        if [[ "$PE_SELECTION" == prepare ]]; then sr_event readiness.run readiness '实际构建、安装与启动' attention '用户选择仅准备，尚未实际运行'; sr_event readiness '' '运行验证' attention '仅准备环境，尚未实际运行'; return 3; fi
        result=0; sr_choose_device || result=$?
        if (( result == 10 )); then continue; fi
        (( result == 0 )) || return "$result"
        result=0
        if (( ${#SR_ARGS} )); then sr_validate_arguments || result=$?;
        else sr_choose_configuration || result=$?; fi
        if (( result == 10 )); then continue; fi
        (( result == 0 )) || return "$result"
        sr_verify_run
        return $?
    done
}
