#!/bin/zsh
# 脚本自述：独立拉取所选 Flutter 目标的原生依赖 / 平台资源，复用一键配置内核。
# 确认后可能准备 SDK、执行工程构建脚本并写正常缓存；不启动 App、不升级依赖或修改全局环境。

typeset FD_PROJECT="" FD_KIND="" FD_PLATFORM="" FD_CHECK=0
# 在首次执行确认前说明资源预缓存与组合构建的区别，避免把名字相近的操作混用。
fd_describe_dependency_kind() {
    case "$FD_KIND" in
        precache)
            print -r -- ''
            print -r -- '本项说明：下载Flutter平台资源'
            print -r -- '  1、调用命令'
            print -r -- '    flutter precache --<所选平台>'
            print -r -- '  2、下载内容：当前 Flutter SDK 为所选构建目标提供的引擎和工具。'
            print -r -- '    Android 示例：引擎二进制制品、gen_snapshot 等构建工具。'
            print -r -- '    iOS 示例：Flutter.xcframework 等引擎制品，仅在 Mac 处理。'
            print -r -- '    Web 示例：Web SDK、CanvasKit / Wasm 等渲染资源。'
            print -r -- '    具体内容随 SDK 版本、宿主与所选目标变化，以实际输出为准。'
            print -r -- '  3、下载边界'
            print -r -- '    不执行 flutter pub get 或 pod install。'
            print -r -- '    Android 预缓存可能包含 Flutter 自身的 Maven 制品。'
            print -r -- '    这不等于解析工程全部 Maven / 第三方依赖。'
            print -r -- '    不代替完整 Android SDK / NDK 或 Xcode 的安装。'
            print -r -- '  4、影响范围：写入当前 SDK 缓存，复用已有内容。'
            print -r -- '    仅准备所选目标，不自动下载所有平台。'
            ;;
        native)
            print -r -- ''
            print -r -- '本项说明：准备原生库与构建依赖（组合操作）'
            print -r -- '  1、包含前置准备：检查所选 SDK，并解析 Pub 依赖。'
            print -r -- '    按目标检查或准备必要的平台工具链。'
            print -r -- '  2、包含所选目标的依赖拉取，与对应单项菜单有重叠。'
            print -r -- '    Android：固定 Gradle / 构建插件及工程 Maven 原生库。'
            print -r -- '    iOS / macOS：CocoaPods 与 Swift Package 依赖。'
            print -r -- '    OpenHarmony：OHPM 包与 Hvigor 构建插件。'
            print -r -- '    Web：有 package.json 声明时安装锁定的 JS 依赖。'
            print -r -- '  3、实际执行：使用所选 SDK 与启动配置运行 flutter build。'
            print -r -- '    通过真实构建触发 FFI Hooks、CMake 等延迟制品下载或编译。'
            print -r -- '  4、影响范围：会执行工程构建脚本，写入正常缓存与构建产物。'
            print -r -- '    不安装或启动 App，不修改工程签名配置。'
            print -r -- '  5、完成边界：只针对所选目标和配置。'
            print -r -- '    不代表其它平台、flavor 或 CPU 架构已全部准备好。'
            ;;
    esac
}
# 先说明单项操作与工程脚本执行影响，确认前只解析参数，不创建日志。
fd_intro_and_wait() {
    local answer=""
    print -r -- '━━━━━━━━━━ Flutter 项目分层依赖准备 ━━━━━━━━━━'
    print -r -- '1、入口范围：仅处理本次选择的工程和操作。'
    print -r -- '  按操作复用健康环境，缺失时提示准备并复检。'
    print -r -- '2、版本策略：沿用项目锁定版本和已有私库认证。'
    print -r -- '  不升级依赖，不修改全局 SDK、仓库或代理。'
    print -r -- '3、日志位置：系统临时目录 JobsFlutterEnvironment.*。'
    print -r -- '4、交互方式：fzf 单选；← 返回上一层。'
    print -r -- '  Esc / Ctrl+C 取消；--check 全程只读。'
    while (( $# )); do
        case "$1" in
            --project) (( $# >= 2 )) && [[ -z "$FD_PROJECT" ]] || return 2; FD_PROJECT="$2"; shift 2 ;;
            --kind) (( $# >= 2 )) && [[ -z "$FD_KIND" ]] || return 2; FD_KIND="$2"; shift 2 ;;
            --platform) (( $# >= 2 )) && [[ -z "$FD_PLATFORM" ]] || return 2; FD_PLATFORM="$2"; shift 2 ;;
            --check) FD_CHECK=1; shift ;;
            *) return 2 ;;
        esac
    done
    case "$FD_KIND" in android|pods|spm|ohos|native|precache|web) ;; *) return 2 ;; esac
    case "$FD_PLATFORM" in ''|android|ios|macos|web|ohos) ;; *) return 2 ;; esac
    fd_describe_dependency_kind
    (( ! FD_CHECK )) || return 0
    [[ -t 0 && -t 1 ]] || return 2
    IFS= read -r 'answer?👉 已了解影响，回车继续；其它输入取消：' || return 130
    [[ -z "$answer" ]] || return 130
}
# 加载定义并先验证目标；只读检查不探测工具健康、不安装或执行工程代码。
fd_initialize() {
    source "${${(%):-%x}:A:h}/SetupFlutterProject.zsh" || return $?
    source "${${(%):-%x}:A:h}/ProjectDependencies.zsh" || return $?
    source "${${(%):-%x}:A:h}/ProjectEnvironment.zsh" || return $?
    pe_validate_project "$FD_PROJECT" || return $?
    SF_PROJECT="$PE_PROJECT" SF_CHECK="$FD_CHECK"
    if (( FD_CHECK )); then
        pe_log "➤ 只读计划：$FD_KIND；目标：${FD_PLATFORM:-由当前项目已有平台选择}；未联网、安装、写日志或调用 SDK。"
        return 0
    fi
    sf_initialize || return $?
}
# 优先复用显式本机环境记录或项目 FVM；缺失 / 损坏时准备一次并重新验证。
fd_prepare_flutter() {
    pe_read_environment || return $?
    if [[ -n "$PE_CONFIG_FLUTTER" ]]; then
        sf_probe_flutter "$PE_CONFIG_FLUTTER" || { pe_log '✖ 已记录的 Flutter 失效，请重新一键配置，未擅自切换 SDK。'; return 3; }
    elif [[ ! -f "$SF_PROJECT/.fvmrc" && ! -f "$SF_PROJECT/.fvm/fvm_config.json" ]] || ! sf_probe_flutter "$SF_PROJECT/.fvm/flutter_sdk/bin/flutter"; then
        if [[ "$SR_TARGET" == ohos ]]; then
            /bin/zsh "$PE_TOOLS_DIR/ManageHarmonyFlutterVersion.zsh" --project "$SF_PROJECT" || return $?
        else
            JOBS_FLUTTER_VERSION_CHAINED=1 /bin/zsh "$PE_TOOLS_DIR/ManageFlutterVersion.zsh" --project "$SF_PROJECT" || return $?
        fi
        sf_probe_flutter "$SF_PROJECT/.fvm/flutter_sdk/bin/flutter" || return $?
    fi
}
# Android 复用完整工具链、固定 Wrapper 和构建插件下载；其它目标无需安装 Android。
fd_prepare_android() {
    DG_PROJECT="$SF_PROJECT" PJ_PROJECT="$SF_PROJECT" DG_JAVA_HOME="$PE_CONFIG_JAVA"
    dg_read_wrapper && pj_check_gradle_criteria && dg_resolve_java && dg_check_java_compatibility || return $?
    SF_JAVA_HOME="$DG_JAVA_HOME"
    source "$PE_TOOLS_DIR/SetupFlutterPlatform.zsh" || return $?
    sf_platform_android "$SF_PROJECT" "$SF_FLUTTER" "$SF_JAVA_HOME" && dg_download_distribution && dg_extract_distribution && dg_warm_plugins
}
# 不自动扩大所选依赖种类；前置失败即停止，取消保留真实状态。
fd_run() {
    fd_initialize || return $?
    (( ! FD_CHECK )) || return 0
    pd_choose_platform "$FD_KIND" "$FD_PLATFORM" || return $?
    [[ "$FD_KIND" != web ]] || { pd_web_dependencies; return $?; }
    fd_prepare_flutter || return $?
    [[ "$FD_KIND" != precache ]] || { sr_precache_target; return $?; }
    sf_fetch_dependencies || return $?
    case "$SR_TARGET" in
        android) fd_prepare_android || return $? ;;
        ios|macos) sr_prepare_apple_platform || return $? ;;
    esac
    case "$FD_KIND" in
        android) pd_step android 'Android Maven 依赖' pd_android_dependencies ;;
        pods) pd_step pods 'CocoaPods 依赖' pd_pods_dependencies ;;
        spm) pd_step spm 'Swift Package 依赖' pd_spm_dependencies ;;
        ohos) pd_step ohos 'OHPM / Hvigor 依赖' pd_ohos_dependencies ;;
        native) pd_run_target_dependencies ;;
    esac
}
# 确认失败直接终止独立入口，不进入业务或创建日志。
fd_show_intro_and_confirm() {
    local result=0
    fd_intro_and_wait "$@" || result=$?
    (( result == 0 )) || exit "$result"
}
# 编排自述、确认和当前依赖类别，最终失败码直接返回到 Finder 终端。
main() {
    fd_show_intro_and_confirm "$@" # 展示本项影响并等待确认，取消直接终止。
    fd_run # 按所选类别复用环境准备依赖，保留真实失败码。
}

main "$@"
