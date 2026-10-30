#!/bin/zsh
# 脚本自述：只供 source；按目标处理 Maven、Pods、SPM、OHPM、Web 锁定包及原生构建依赖。
# 使用调用者选择的 Flutter / Java 和日志；不修改全局仓库、不升级依赖、不启动 App。

typeset -g PD_PLATFORM="" PD_KIND="" PD_XCODE_CONTAINER=""
# 只展示当前宿主能处理且项目实际存在的平台，不生成缺失平台目录。
pd_choose_platform() {
    local kind="$1" requested="${2:-}" target="" rows="" allowed=""
    case "$kind" in
        android) allowed='android' ;;
        pods|spm) allowed='ios macos' ;;
        ohos) allowed='ohos' ;;
        web) allowed='web' ;;
        native|precache) allowed='android ios macos web ohos' ;;
        *) return 2 ;;
    esac
    for target in ${=allowed}; do
        [[ -d "$SF_PROJECT/$target" && ! -L "$SF_PROJECT/$target" ]] || continue
        [[ -z "$requested" || "$requested" == "$target" ]] || continue
        [[ -z "$rows" ]] || rows+=$'\n'
        rows+="$target"$'\t'"准备 $target 的依赖"
    done
    [[ -n "$rows" ]] || { pe_log "✖ 当前项目没有适用的 $kind 平台；Windows / Linux 原生目标须在对应宿主处理。"; return 3; }
    if [[ "$rows" != *$'\n'* ]]; then PD_PLATFORM="${rows%%$'\t'*}";
    else pe_select '依赖目标平台' "$rows" || return $?; PD_PLATFORM="$PE_SELECTION"; fi
    SR_TARGET="$PD_PLATFORM"
}
# 每个阶段使用独立事件和有界原始日志，失败不发布成功事件。
pd_step() {
    local id="$1" title="$2" result=0 state=failed
    shift 2
    pe_event "pub.$id" pub "$title" running
    "$@" || result=$?
    if (( result == 0 )); then pe_event "pub.$id" pub "$title" succeeded;
    else
        (( result != 3 && result != 10 && result != 130 )) || state=attention
        pe_event "pub.$id" pub "$title" "$state" "退出码 $result；后续依赖准备已停止"
    fi
    return "$result"
}
# 在各子项目自身任务中严格解析所有可解析配置；失败不使用 lenient 吞掉缺包。
pd_android_dependencies() {
    local init="$PE_RUN_DIR/project-dependencies.init.gradle" seconds="${JOBS_GRADLE_TASK_TIMEOUT:-1800}"
    [[ "$seconds" == <-> && "$seconds" -ge 30 && "$seconds" -le 7200 ]] || return 2
    [[ -d "$SF_PROJECT/android" && -n "$DG_GRADLE" && -n "$DG_JAVA_HOME" ]] || return 2
    /bin/cat > "$init" <<'GRADLE'
gradle.beforeProject { p ->
    p.tasks.register('jobsResolveProjectDependencies') {
        doLast {
            def resolved = 0
            (p.configurations.findAll { it.canBeResolved } + p.buildscript.configurations.findAll { it.canBeResolved }).each { cfg ->
                println("Jobs resolving ${p.path}:${cfg.name}")
                cfg.resolve().each { artifact -> println("Jobs artifact ${artifact.name}") }
                resolved++
            }
            println("Jobs resolved ${p.path}: ${resolved} configurations")
        }
    }
}
gradle.projectsEvaluated {
    gradle.rootProject.tasks.register('jobsResolveAllProjectDependencies') {
        dependsOn gradle.rootProject.allprojects.collect { it.tasks.named('jobsResolveProjectDependencies') }
        doLast { println('JOBS_PROJECT_DEPENDENCIES_RESOLVED') }
    }
}
GRADLE
    pe_log '📥 来源：工程和插件声明的 Maven / Google / 私有仓库；地址由 Gradle 原样输出。目标：实际 Gradle 用户缓存。'
    pe_log '➤ 逐子项目解析所有 canBeResolved 配置，包含各 variant 的 Maven AAR / JAR；工程内自定义任务、included builds 的延迟下载仍由原生构建验证。'
    (
        cd -- "$SF_PROJECT/android" || return 1
        SF_COMMAND_DIRECTORY="$SF_PROJECT/android" SF_COMMAND_TIMEOUT="$seconds" sf_run_diagnostic android-dependencies /usr/bin/env \
            "JAVA_HOME=$DG_JAVA_HOME" "PATH=$DG_JAVA_HOME/bin:$PATH" "$DG_GRADLE" \
            --no-daemon --no-configuration-cache --console plain "-Dorg.gradle.java.home=$DG_JAVA_HOME" \
            --init-script "$init" jobsResolveAllProjectDependencies
    ) || return $?
    /usr/bin/grep -Fxq 'JOBS_PROJECT_DEPENDENCIES_RESOLVED' "$PE_RUN_DIR/android-dependencies.log" || { pe_log '✖ Gradle 未返回完整依赖解析完成标记。'; return 1; }
}
# Pods 始终使用 install 和已有锁策略，沿用平台 Gemfile / Bundler 及健康检查。
pd_pods_dependencies() {
    [[ -f "$SF_PROJECT/$SR_TARGET/Podfile" && ! -L "$SF_PROJECT/$SR_TARGET/Podfile" ]] || { pe_log '➤ 无 Podfile，当前目标不使用 CocoaPods。'; return 0; }
    (( ${#SR_POD_COMMAND} )) || sr_prepare_cocoapods || return $?
    pe_log '📥 来源：Podfile / podspec 声明的 Specs、Git 与二进制源；目标：平台 Pods 及正常 CocoaPods 缓存。'
    sr_install_native_dependencies
}
# 配置生成只按工程当前 Flutter 策略运行；不为拉取依赖切换全局 SPM 开关。
pd_apple_configuration() {
    local help_file="$PE_RUN_DIR/apple-build-help.log"
    SF_COMMAND_TIMEOUT=60 sf_run_diagnostic apple-build-help "$SF_FLUTTER" build "$SR_TARGET" --help || return $?
    if /usr/bin/grep -q -- '--config-only' "$help_file"; then
        local -a args=(build "$SR_TARGET" --config-only --debug)
        [[ "$SR_TARGET" != ios ]] || args+=(--no-codesign)
        SF_COMMAND_TIMEOUT=1800 sf_run_diagnostic apple-configuration "$SF_FLUTTER" "${args[@]}"
    else
        pe_log '➤ 当前 Flutter 无 config-only，使用现有 Xcode 工程解析；尚未生成的 Flutter 插件包需先运行原生构建依赖入口。'
    fi
}
# 只选平台顶层工程，优先 workspace，多个容器明确选择，避免误选 Pods 工程。
pd_choose_xcode_container() {
    setopt localoptions NO_NOMATCH
    local item="" rows=""
    local -a candidates=("$SF_PROJECT/$SR_TARGET"/*.xcworkspace(N/))
    (( ${#candidates} )) || candidates=("$SF_PROJECT/$SR_TARGET"/*.xcodeproj(N/))
    for item in "${candidates[@]}"; do
        [[ ! -L "$item" && "${item:t}" != Pods.xcodeproj ]] || continue
        [[ -z "$rows" ]] || rows+=$'\n'
        rows+="$item"$'\t'"${item:t}"
    done
    [[ -n "$rows" ]] || { pe_log '✖ 目标缺少可解析的 Xcode 工程。'; return 1; }
    if [[ "$rows" == *$'\n'* ]]; then pe_select 'Xcode 工程' "$rows" || return $?; PD_XCODE_CONTAINER="$PE_SELECTION";
    else PD_XCODE_CONTAINER="${rows%%$'\t'*}"; fi
}
# SPM 解析 Xcode 工程引用的全部包，已有 Package.resolved 时要求沿用锁定版本。
pd_spm_dependencies() {
    local option=-project locked=""
    pd_apple_configuration && pd_choose_xcode_container || return $?
    [[ "$PD_XCODE_CONTAINER" != *.xcworkspace ]] || option=-workspace
    local source_packages="$SF_PROJECT/.jobs/dependencies/spm" parent=""
    for parent in "$SF_PROJECT/.jobs" "$SF_PROJECT/.jobs/dependencies" "$source_packages"; do
        [[ ! -L "$parent" && ( ! -e "$parent" || -d "$parent" ) ]] || { pe_log '✖ 项目 SPM 缓存目录身份异常。'; return 2; }
    done
    local -a args=(-resolvePackageDependencies "$option" "$PD_XCODE_CONTAINER" -clonedSourcePackagesDirPath "$source_packages")
    setopt localoptions NO_NOMATCH
    for locked in "$PD_XCODE_CONTAINER/xcshareddata/swiftpm/Package.resolved" \
        "$PD_XCODE_CONTAINER/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" \
        "$SF_PROJECT/$SR_TARGET"/*.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved(N); do
        if [[ -f "$locked" && ! -L "$locked" ]]; then args+=(-onlyUsePackageVersionsFromResolvedFile); break; fi
    done
    pe_log "📥 来源：Xcode 工程 / Package.swift 声明的 Swift 包与二进制制品；目标：$source_packages。"
    SF_COMMAND_TIMEOUT=1800 sf_run_diagnostic spm-dependencies /usr/bin/xcodebuild "${args[@]}"
}
# OHPM 包与 Hvigor 插件分开同步，使用项目 wrapper，不安装全局最新版构建器。
pd_ohos_dependencies() {
    local ohpm="$(command -v ohpm 2>/dev/null)" hvigor="$SF_PROJECT/ohos/hvigorw"
    [[ -f "$SF_PROJECT/ohos/oh-package.json5" && ! -L "$SF_PROJECT/ohos/oh-package.json5" ]] || return 2
    [[ -x "$ohpm" ]] || { pe_log '✖ 缺少 OHPM；请先配置 DevEco / OpenHarmony 工具链并在当前终端激活。'; return 3; }
    if [[ ! -f "$hvigor" || -L "$hvigor" ]]; then
        hvigor="$(command -v hvigorw 2>/dev/null)"
        [[ -n "$hvigor" && -f "$hvigor" ]] || { pe_log '✖ 缺少项目 / DevEco 配套 hvigorw；请先激活工程所需的 Hvigor 工具链。'; return 3; }
    fi
    SF_COMMAND_TIMEOUT=30 sf_run_diagnostic ohpm-version "$ohpm" --version || return $?
    pe_log '📥 来源：oh-package.json5、锁文件与 hvigor-config.json5 声明的源；目标：oh_modules、Hvigor 正常缓存。'
    (
        cd -- "$SF_PROJECT/ohos" || return 1
        SF_COMMAND_DIRECTORY="$SF_PROJECT/ohos" SF_COMMAND_TIMEOUT=1800 sf_run_diagnostic ohpm-dependencies "$ohpm" install &&
            SF_COMMAND_DIRECTORY="$SF_PROJECT/ohos" SF_COMMAND_TIMEOUT=1800 sf_run_diagnostic hvigor-dependencies /bin/sh "$hvigor" --sync
    )
}
# Web 额外 JS 工程仅按已有唯一锁文件安装，缺锁 / 多锁不猜测包管理器或升级版本。
pd_web_dependencies() {
    local directory="" file="" selected="" count=0 tool=""
    for directory in "$SF_PROJECT/web" "$SF_PROJECT"; do
        [[ -f "$directory/package.json" && ! -L "$directory/package.json" ]] || continue
        selected="" count=0
        for file in package-lock.json npm-shrinkwrap.json pnpm-lock.yaml yarn.lock; do
            if [[ -f "$directory/$file" && ! -L "$directory/$file" ]]; then selected="$file"; (( count++ )); fi
        done
        (( count == 1 )) || { pe_log "✖ $directory 缺少唯一 JS 锁文件，请先确认依赖版本与包管理器。"; return 3; }
        local -a args
        case "$selected" in
            package-lock.json|npm-shrinkwrap.json) tool="$(command -v npm)"; args=(ci) ;;
            pnpm-lock.yaml) tool="$(command -v pnpm)"; args=(install --frozen-lockfile) ;;
            yarn.lock)
                tool="$(command -v yarn)"
                [[ -x "$tool" ]] || { pe_log '✖ 缺少项目所需 yarn。'; return 3; }
                SF_COMMAND_TIMEOUT=30 sf_run_diagnostic yarn-version "$tool" --version || return $?
                if /usr/bin/grep -Eq '^1\.' "$PE_RUN_DIR/yarn-version.log"; then args=(install --frozen-lockfile); else args=(install --immutable); fi ;;
        esac
        [[ -x "$tool" ]] || { pe_log "✖ 缺少 $selected 对应的包管理器，请先准备工程要求的 Node.js 与包管理器。"; return 3; }
        pe_log "📥 来源：$directory/package.json 与 $selected 的仓库；目标：工程 node_modules。锁文件安装会执行工程生命周期脚本，npm ci 会重建 node_modules。"
        ( cd -- "$directory" && SF_COMMAND_DIRECTORY="$directory" SF_COMMAND_TIMEOUT=1800 sf_run_diagnostic web-dependencies "$tool" "${args[@]}" ) || return $?
    done
    pe_log '✔ 已处理存在的 JS 工程；没有 package.json 时不引入 npm 依赖。'
}
# 真实目标构建触发 CMake / FFI Hooks / 延迟二进制下载，不把分析或依赖树当下载成功。
pd_native_dependencies() {
    local command="$SR_TARGET" seconds="${JOBS_NATIVE_DEPENDENCY_TIMEOUT:-3600}"
    [[ "$seconds" == <-> && "$seconds" -ge 30 && "$seconds" -le 14400 ]] || return 2
    (( ${#SR_ARGS} )) || sr_choose_configuration || return $?
    sr_validate_arguments || return $?
    case "$SR_TARGET" in android) command=apk ;; ios|macos|web) ;; ohos) command=hap ;; *) return 2 ;; esac
    local -a args=(build "$command" "${SR_ARGS[@]}")
    [[ "$SR_TARGET" != ios ]] || args+=(--no-codesign)
    pe_log '📥 来源：所选目标的插件构建脚本 / FFI Hooks / CMake 声明。将实际编译以准备原生库及延迟依赖，写正常 build 缓存；不安装或启动 App，不改签名。'
    if [[ ( "$SR_TARGET" == android || "$SR_TARGET" == ohos ) && -n "$SF_JAVA_HOME" ]]; then
        SF_COMMAND_TIMEOUT="$seconds" sf_run_diagnostic native-dependencies /usr/bin/env \
            "JAVA_HOME=$SF_JAVA_HOME" "PATH=$SF_JAVA_HOME/bin:$PATH" \
            "GRADLE_OPTS=${GRADLE_OPTS:+$GRADLE_OPTS }-Dorg.gradle.java.home=\"$SF_JAVA_HOME\"" \
            "$SF_FLUTTER" "${args[@]}"
    else
        SF_COMMAND_TIMEOUT="$seconds" sf_run_diagnostic native-dependencies "$SF_FLUTTER" "${args[@]}"
    fi
}
# one-click 复用独立菜单相同内核；Pub 已先完成，仅处理当前已选择目标。
pd_run_target_dependencies() {
    case "$SR_TARGET" in
        android) pd_step android 'Android Maven 原生依赖' pd_android_dependencies || return $? ;;
        ios|macos)
            pd_step pods 'CocoaPods 依赖' pd_pods_dependencies && pd_step spm 'Swift Package 依赖' pd_spm_dependencies || return $? ;;
        ohos) pd_step ohos 'OpenHarmony OHPM / Hvigor 依赖' pd_ohos_dependencies || return $? ;;
        web) pd_step web 'Web JS 工程依赖' pd_web_dependencies || return $? ;;
        *) return 2 ;;
    esac
    pd_step native '原生库与目标构建依赖' pd_native_dependencies
}
