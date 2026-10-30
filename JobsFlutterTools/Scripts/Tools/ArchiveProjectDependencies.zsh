#!/bin/zsh
# 脚本自述：配对导出 / 导入 Gradle、Pods、SPM、OHPM、原生构建、Flutter artifacts 与 Web 包快照。
# 归档保留宿主、工具版本、工程锁指纹与文件校验；导入先预检再精确 YES，不覆盖冲突或执行归档脚本。

typeset -g AR_PROJECT="" AR_KIND="" AR_MODE="" AR_PLATFORM="" AR_CHECK=0 AR_ROOT="" AR_DIRECTORY=""
typeset -g AR_DART="" AR_VERSION="" AR_COMPONENT="" AR_NODE_ROOT=""
# 第一屏说明缓存边界；参数只作为数据解释，确认前不创建文件。
ar_intro_and_wait() {
    local answer=""
    print -r -- '━━━━━━━━━━ Flutter 分层依赖快照提取 / 导入 ━━━━━━━━━━'
    print -r -- '1、每次只处理所选类别。Pub 源码继续使用原提取 / 导入入口；本入口处理平台包与工具缓存。'
    print -r -- '2、快照记录宿主系统、工具版本、工程配置 / 锁文件指纹和逐文件校验，导入不自动联网或运行归档中的脚本。'
    print -r -- '3、Gradle modules-2、Flutter artifacts 是共享缓存，可能包含其它工程 / 平台的包；不提取全局配置、认证、daemon、SDK 源码或 Dart runtime。'
    print -r -- '4、native 是本机目标构建缓存，可能含业务产物；Web node_modules 可能含本机原生扩展。均不能当作任意系统可复用的源码包。'
    print -r -- '5、导入完整预检后输入精确 YES；同名不同内容拒绝覆盖。只恢复文件不保证完整离线构建，恢复后仍需对应拉取 / 构建入口验证。'
    print -r -- '6、日志在系统临时目录 JobsFlutterEnvironment.*；Ctrl+C / Esc 取消。--check 只显示静态计划，不调用 SDK 或写日志。'
    while (( $# )); do
        case "$1" in
            --project) (( $# >= 2 )) && [[ -z "$AR_PROJECT" ]] || return 2; AR_PROJECT="$2"; shift 2 ;;
            --kind) (( $# >= 2 )) && [[ -z "$AR_KIND" ]] || return 2; AR_KIND="$2"; shift 2 ;;
            --mode) (( $# >= 2 )) && [[ -z "$AR_MODE" ]] || return 2; AR_MODE="$2"; shift 2 ;;
            --platform) (( $# >= 2 )) && [[ -z "$AR_PLATFORM" ]] || return 2; AR_PLATFORM="$2"; shift 2 ;;
            --directory) (( $# >= 2 )) && [[ -z "$AR_DIRECTORY" ]] || return 2; AR_DIRECTORY="$2"; shift 2 ;;
            --check) AR_CHECK=1; shift ;;
            *) return 2 ;;
        esac
    done
    case "$AR_KIND" in gradle|pods|spm|ohos|native|precache|web) ;; *) return 2 ;; esac
    case "$AR_MODE" in export|import) ;; *) return 2 ;; esac
    case "$AR_PLATFORM" in ''|android|ios|macos|ohos|web) ;; *) return 2 ;; esac
    (( ! AR_CHECK )) || return 0
    [[ -t 0 && -t 1 ]] || return 2
    IFS= read -r 'answer?👉 已了解范围，回车继续；其它输入取消：' || return 130
    [[ -z "$answer" ]] || return 130
}
# 加载同包定义并验证项目；静态检查不读取或执行快照业务。
ar_initialize() {
    local tools="${${(%):-%x}:A:h}"
    source "$tools/SetupFlutterProject.zsh" || return $?
    source "$tools/ProjectEnvironment.zsh" || return $?
    source "$tools/ManageProjectJava.zsh" || return $?
    source "$tools/DownloadProjectGradle.zsh" || return $?
    source "$tools/SetupFlutterRun.zsh" || return $?
    source "$tools/ProjectDependencies.zsh" || return $?
    pe_validate_project "$AR_PROJECT" || return $?
    SF_PROJECT="$PE_PROJECT" DG_PROJECT="$PE_PROJECT"
    (( ! AR_CHECK )) || { pe_log "➤ 只读计划：$AR_MODE / $AR_KIND / ${AR_PLATFORM:-项目已有平台}；未复制、联网、调用 SDK 或写日志。"; return 0; }
    pe_initialize_runtime && pe_ensure_fzf
}
# 路径输入支持原路径和 Terminal 拖入转义，不对用户输入使用 eval。
ar_read_directory() {
    local prompt="$1" value="${2:-}"
    if [[ -z "$value" ]]; then
        IFS= read -r "value?$prompt：" || return 130
    fi
    [[ -n "$value" ]] || return 130
    if [[ ! -d "$value" ]]; then value="${(Q)value}"; fi
    [[ "$value" == /* && -d "$value" && ! -L "${value%/}" ]] || { pe_log '✖ 请输入实际存在的普通目录绝对路径。'; return 2; }
    AR_DIRECTORY="${value:A}"
}
# 使用已记录 SDK 或项目自身 FVM 的同套 Dart，不为了导出缓存安装其它 SDK。
ar_resolve_dart() {
    pe_read_environment || return $?
    local candidate="${PE_CONFIG_FLUTTER:-$SF_PROJECT/.fvm/flutter_sdk/bin/flutter}"
    sf_probe_flutter "$candidate" || { pe_log '✖ 需要当前项目可运行的 Flutter / Dart；请先通过 SDK 或一键配置入口准备。'; return 3; }
    AR_DART="$SF_FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart"
}
# 归档目标平台遵循宿主能力，快照平台在导入时必须与当前选择一致。
ar_choose_platform() {
    local kind="$AR_KIND"
    [[ "$kind" != gradle ]] || kind=android
    [[ "$kind" != precache ]] || kind=precache
    pd_choose_platform "$kind" "$AR_PLATFORM" || return $?
    AR_PLATFORM="$SR_TARGET"
}
# 当前工具和锁版本形成兼容键；绝对源路径只用于当前进程，不写入清单。
ar_resolve_root() {
    local file="" value="" tool="" help=""
    case "$AR_KIND" in
        gradle)
            dg_read_wrapper || return $?
            pe_select 'Gradle 快照组件' $'modules\tMaven 制品和元数据缓存（共享 modules-2）\nwrapper\t工程固定 Gradle Wrapper 分发' || return $?
            AR_COMPONENT="$PE_SELECTION"
            AR_VERSION="Gradle $DG_VERSION $AR_COMPONENT"
            if [[ "$AR_COMPONENT" == modules ]]; then AR_ROOT="${GRADLE_USER_HOME:-$HOME/.gradle}/caches/modules-2";
            else
                source "$PE_TOOLS_DIR/WrapperDistributionCache.zsh" || return $?
                wd_resolve_layout "$SF_PROJECT" "$DG_URL" || return $?
                AR_ROOT="${WD_ZIP_PATH:h}"
            fi
            ;;
        pods)
            file="$SF_PROJECT/$AR_PLATFORM/Podfile.lock"
            [[ -f "$file" && ! -L "$file" ]] || { pe_log '✖ 缺少平台 Podfile.lock，不能确认 CocoaPods 快照兼容性。'; return 3; }
            value="$(/usr/bin/perl -ne 'print $1 if /^COCOAPODS:\s*(\S+)/' "$file")"
            [[ -n "$value" ]] || return 3
            AR_VERSION="CocoaPods $value" AR_ROOT="$SF_PROJECT/$AR_PLATFORM/Pods"
            ;;
        spm)
            SF_COMMAND_TIMEOUT=60 sf_run_diagnostic archive-xcode /usr/bin/xcodebuild -version || return $?
            value="$(/usr/bin/tr '\n' ' ' < "$PE_RUN_DIR/archive-xcode.log")"
            [[ "$value" == *Xcode* ]] || return 3
            AR_VERSION="$value" AR_ROOT="$SF_PROJECT/.jobs/dependencies/spm"
            if [[ "$AR_MODE" == export && ! -d "$AR_ROOT" ]]; then
                pe_log '➤ 旧版 Xcode 缓存在工程外；请选择本工程实际使用的 SourcePackages 目录。导入目标仍为工程本地 SPM 缓存。'
                local previous_directory="$AR_DIRECTORY"
                ar_read_directory '实际 SourcePackages 目录' || return $?
                AR_ROOT="$AR_DIRECTORY" AR_DIRECTORY="$previous_directory"
                [[ -d "$AR_ROOT/checkouts" || -d "$AR_ROOT/artifacts" ]] || { pe_log '✖ 所选目录不是 SourcePackages 缓存。'; return 2; }
            fi
            ;;
        ohos)
            pe_select 'OpenHarmony 快照组件' $'ohpm\tOHPM 包（工程 oh_modules）\nhvigor\tHvigor 插件 / 包缓存（实际工具缓存目录）' || return $?
            AR_COMPONENT="$PE_SELECTION"
            if [[ "$AR_COMPONENT" == ohpm ]]; then
                tool="$(command -v ohpm 2>/dev/null)"
                [[ -x "$tool" ]] || { pe_log '✖ 需要当前工程对应的 OHPM 读取兼容版本。'; return 3; }
                SF_COMMAND_TIMEOUT=30 sf_run_diagnostic archive-ohpm "$tool" --version || return $?
                value="$(pe_semantic_version "$PE_RUN_DIR/archive-ohpm.log")"
                AR_VERSION="OHPM $value" AR_ROOT="$SF_PROJECT/ohos/oh_modules"
            else
                tool="$SF_PROJECT/ohos/hvigorw"
                [[ -f "$tool" && ! -L "$tool" ]] || tool="$(command -v hvigorw 2>/dev/null)"
                [[ -f "$tool" ]] || { pe_log '✖ 需要工程配套 Hvigor wrapper 读取兼容版本。'; return 3; }
                SF_COMMAND_DIRECTORY="$SF_PROJECT/ohos" SF_COMMAND_TIMEOUT=60 sf_run_diagnostic archive-hvigor /bin/sh "$tool" --version || return $?
                value="$(pe_semantic_version "$PE_RUN_DIR/archive-hvigor.log")"
                AR_VERSION="Hvigor $value"
                pe_log '➤ 不猜测 Hvigor 版本间的缓存布局；请指定本工具实际使用的依赖缓存目录（不选整个用户目录）。'
                local previous_directory="$AR_DIRECTORY"
                ar_read_directory '实际 Hvigor 缓存源 / 恢复目录' || return $?
                AR_ROOT="$AR_DIRECTORY" AR_DIRECTORY="$previous_directory"
                [[ "$AR_ROOT" != "${HOME:A}" && "$AR_ROOT" != / && "$AR_ROOT" != "$SF_PROJECT" && "$AR_ROOT" != "$SF_PROJECT/ohos" ]] || return 2
            fi
            [[ -n "$value" ]] || return 3
            ;;
        native)
            AR_VERSION="Flutter $SF_FLUTTER_VERSION arch $(/usr/bin/uname -m)"
            if [[ "$AR_PLATFORM" == android ]]; then AR_ROOT="$SF_PROJECT/build/app";
            else AR_ROOT="$SF_PROJECT/build/$AR_PLATFORM"; fi
            ;;
        precache)
            AR_VERSION="Flutter $SF_FLUTTER_VERSION artifacts arch $(/usr/bin/uname -m)" AR_ROOT="$SF_FLUTTER_ROOT/bin/cache/artifacts"
            ;;
        web)
            AR_NODE_ROOT=""
            local rows="" scope=""
            for file in "$SF_PROJECT/web" "$SF_PROJECT"; do
                if [[ -f "$file/package.json" && ! -L "$file/package.json" ]]; then
                    scope=root
                    [[ "$file" != "$SF_PROJECT/web" ]] || scope=web
                    [[ -z "$rows" ]] || rows+=$'\n'
                    rows+="$scope"$'\t'"$file/node_modules"
                fi
            done
            [[ -n "$rows" ]] || { pe_log '✖ 当前工程没有额外 JS package.json，无需迁移 node_modules。'; return 3; }
            if [[ "$rows" == *$'\n'* ]]; then pe_select 'JS 包快照范围' "$rows" || return $?; scope="$PE_SELECTION";
            else scope="${rows%%$'\t'*}"; fi
            if [[ "$scope" == web ]]; then AR_NODE_ROOT="$SF_PROJECT/web"; else AR_NODE_ROOT="$SF_PROJECT"; fi
            tool="$(command -v node 2>/dev/null)"
            [[ -x "$tool" ]] || { pe_log '✖ 缺少工程对应的 Node.js。'; return 3; }
            SF_COMMAND_TIMEOUT=30 sf_run_diagnostic archive-node "$tool" --version || return $?
            value="$(pe_semantic_version "$PE_RUN_DIR/archive-node.log")"
            [[ -n "$value" ]] || return 3
            SF_COMMAND_TIMEOUT=30 sf_run_diagnostic archive-node-arch "$tool" -p process.arch || return $?
            local architecture="$(/usr/bin/tr -d '\r\n' < "$PE_RUN_DIR/archive-node-arch.log")"
            [[ "$architecture" =~ '^[A-Za-z0-9_-]+$' ]] || return 3
            AR_VERSION="Node $value arch $architecture scope $scope" AR_ROOT="$AR_NODE_ROOT/node_modules"
            ;;
    esac
    [[ -n "$AR_ROOT" && -n "$AR_VERSION" && ! -L "$AR_ROOT" ]] || return 2
}
# 清单预检与真实导入使用同一个内核，确认后仍再次全量核验，不覆盖冲突。
ar_transfer() {
    local answer="" engine="$PE_TOOLS_DIR/NativeDependencyArchive.dart"
    local -a args=("$engine" "$AR_MODE" --project "$SF_PROJECT" --kind "$AR_KIND" --platform "$AR_PLATFORM" --tool-version "$AR_VERSION" --directory "$AR_DIRECTORY")
    [[ -f "$engine" ]] || { pe_log '✖ 缺少同包快照内核。'; return 1; }
    if [[ "$AR_MODE" == export ]]; then
        [[ -d "$AR_ROOT" && ! -L "$AR_ROOT" ]] || { pe_log "✖ 没有本地可提取内容：$AR_ROOT；先运行相应拉取/构建入口。"; return 3; }
        pe_log "📤 来源：$AR_KIND · $AR_ROOT；工具：$AR_VERSION；输出父目录：$AR_DIRECTORY"
        pe_run_logged "$AR_DART" "${args[@]}" --source-root "$AR_ROOT"
    else
        pe_log "📥 来源：$AR_DIRECTORY；目标：$AR_ROOT；工具：$AR_VERSION。先验证完整快照与冲突。"
        pe_run_logged "$AR_DART" "${args[@]}" --target-root "$AR_ROOT" --check || return $?
        IFS= read -r 'answer?输入精确大写 YES 导入；其它输入取消：' || return 130
        [[ "$answer" == YES ]] || return 130
        pe_run_logged "$AR_DART" "${args[@]}" --target-root "$AR_ROOT" --confirm YES
    fi
}
# 一项只处理一个类型和平台；完成后由原包管理器 / 构建步骤验证可使用性。
ar_run() {
    ar_initialize || return $?
    (( ! AR_CHECK )) || return 0
    ar_choose_platform && ar_resolve_dart && ar_resolve_root || return $?
    if [[ "$AR_MODE" == export ]]; then ar_read_directory '提取输出父目录（输入或拖入，空输入取消）' "$AR_DIRECTORY" || return $?;
    else ar_read_directory '完整快照目录（输入或拖入，空输入取消）' "$AR_DIRECTORY" || return $?; fi
    ar_transfer
}
# 自述确认失败即退出，不能将取消误当成导入完成。
ar_show_intro_and_confirm() {
    local result=0
    ar_intro_and_wait "$@" || result=$?
    (( result == 0 )) || exit "$result"
}
# 单项菜单入口；source 时只提供定义供隔离测试使用。
main() {
    ar_show_intro_and_confirm "$@" # 首屏说明缓存范围与确认方式，取消直接终止。
    ar_run # 校验版本、快照与冲突，再执行本项提取或导入。
}

if [[ "$ZSH_EVAL_CONTEXT" == toplevel ]]; then
    main "$@"
fi
