#!/bin/zsh
# Created by Jobs on 2026年11月10日，星期二.
# 供当前运行器 source：原地承接鸿蒙 SDK、工具链、平台与依赖准备，不启动 App。
# 项目绑定与新增平台有备份；已有平台、业务源码与第三方插件不重写。

typeset -g JOBS_HARMONY_PREPARE_PACKAGE="${${(%):-%x}:A:h}"
typeset -g JOBS_HARMONY_PREPARE_RUN=""
typeset -g JOBS_HARMONY_PREPARE_OHPM="" JOBS_HARMONY_PREPARE_HVIGOR=""

jobs_hpr_command() {
    local name="$1" seconds="$2"
    shift 2
    RUN_BOUNDED_STREAM=1 run_bounded "$seconds" "$LOG_FILE.harmony-prepare.$name" "$@"
}

jobs_hpr_command_in_ohos() (
    cd -- "$PROJECT_PATH/ohos" || return 1
    jobs_hpr_command "$@"
)

jobs_hpr_command_in_project() (
    cd -- "$PROJECT_PATH" || return 1
    jobs_hpr_command "$@"
)

jobs_hpr_backup_project() {
    local item="" target=""
    JOBS_HARMONY_PREPARE_RUN="$(umask 077; /usr/bin/mktemp -d "${${TMPDIR:-/tmp}%/}/JobsHarmonyRun.XXXXXX")" || return 1
    /bin/mkdir "$JOBS_HARMONY_PREPARE_RUN/before" || return 1
    for item in pubspec.yaml pubspec.lock pubspec_overrides.yaml .metadata .fvmrc .fvm/fvm_config.json .dart_tool/package_config.json .flutter-plugins-dependencies; do
        [[ ! -L "$PROJECT_PATH/$item" ]] || { log "✖ 配置不是普通文件，保留并停止：$item"; return 1; }
        [[ -f "$PROJECT_PATH/$item" ]] || continue
        target="$JOBS_HARMONY_PREPARE_RUN/before/$item"
        /bin/mkdir -p "${target:h}" && /bin/cp -p "$PROJECT_PATH/$item" "$target" || return 1
    done
    log "➤ 原配置备份：$JOBS_HARMONY_PREPARE_RUN/before；SDK 绑定事务另由随包管理器保存并恢复。"
}

jobs_hpr_prepare_sdk() {
    local result=0 needs_prepare=0 manager="$JOBS_HARMONY_PREPARE_PACKAGE/Resources/Tools/ManageHarmonyFlutterVersion.zsh"
    [[ -s "$manager" && ! -L "$manager" ]] || { log '✖ 随包鸿蒙 SDK 管理器缺失，已停止当前准备。'; return 1; }
    jobs_hpr_command sdk-capabilities 60 "$FLUTTER_BIN" build -h || result=$?
    if (( result != 0 )) || ! /usr/bin/grep -Eq '^[[:space:]]*hap[[:space:]]' "$LOG_FILE.harmony-prepare.sdk-capabilities"; then
        needs_prepare=1
    else
        result=0
        /bin/zsh "$manager" --project "$PROJECT_PATH" --verify-sdk "${FLUTTER_BIN:A:h:h}" || result=$?
        case "$result" in
            0) ;;
            65) needs_prepare=1 ;;
            *) log '✖ 当前 SDK 版本或工程约束无法可靠核验，保留原绑定，未猜测版本继续。'; return "$result" ;;
        esac
    fi
    if (( needs_prepare )); then
        log '▶ 当前 SDK 不满足 HAP 或项目版本约束，直接在本轮运行中准备正式鸿蒙 SDK 与项目级绑定。'
        /bin/zsh "$manager" --project "$PROJECT_PATH" --prepare-for-run || return $?
        [[ -x "$PROJECT_PATH/.fvm/flutter_sdk/bin/flutter" ]] || { log '✖ 鸿蒙 SDK 准备后项目绑定仍不可用。'; return 1; }
        FLUTTER_BIN="${PROJECT_PATH}/.fvm/flutter_sdk/bin/flutter"
        FLUTTER_BIN="${FLUTTER_BIN:A}"
        jobs_hpr_command sdk-capabilities 60 "$FLUTTER_BIN" build -h || return $?
        /usr/bin/grep -Eq '^[[:space:]]*hap[[:space:]]' "$LOG_FILE.harmony-prepare.sdk-capabilities" || { log '✖ 准备后的 SDK 仍不提供 HAP 构建能力。'; return 1; }
    fi
}

# 在私有暂存工程生成，仅原子发布全新的 ohos/，不让 create 改写已有工程文件。
jobs_hpr_prepare_platform() {
    local file="" name="" stage="$JOBS_HARMONY_PREPARE_RUN/platform" result=0
    if [[ -e "$PROJECT_PATH/ohos" || -L "$PROJECT_PATH/ohos" ]]; then
        [[ -d "$PROJECT_PATH/ohos" && ! -L "$PROJECT_PATH/ohos" ]] || { log '✖ 已有 ohos 不是普通目录，保留并停止。'; return 1; }
        for file in build-profile.json5 oh-package.json5 AppScope/app.json5; do
            [[ -f "$PROJECT_PATH/ohos/$file" && ! -L "$PROJECT_PATH/ohos/$file" ]] || { log "✖ 已有 ohos/ 缺少 $file，保留原文件，不重新生成覆盖。"; return 1; }
        done
        return 0
    fi
    name="$(/usr/bin/awk '/^name:[[:space:]]*/ { sub(/^name:[[:space:]]*/, ""); sub(/[[:space:]]+#.*/, ""); print; exit }' "$PROJECT_PATH/pubspec.yaml")"
    name="${(Q)name}"
    [[ "$name" =~ '^[a-z][a-z0-9_]*$' ]] || { log '✖ 无法可靠读取工程包名，未生成鸿蒙平台。'; return 1; }
    /bin/mkdir "$stage" && /bin/cp -p "$PROJECT_PATH/pubspec.yaml" "$stage/pubspec.yaml" || return 1
    log "▶ 缺少 ohos/，在备份旁的私有工程生成鸿蒙平台：$stage；只发布新增目录，不改写现有 lib、Pub 配置或其它平台。"
    (
        cd -- "$stage" || return 1
        jobs_hpr_command create-platform 300 "$FLUTTER_BIN" create --platforms ohos --no-pub --project-name "$name" .
    ) || return $?
    for file in build-profile.json5 oh-package.json5 AppScope/app.json5; do
        [[ -f "$stage/ohos/$file" && ! -L "$stage/ohos/$file" ]] || { log '✖ 生成结果缺少鸿蒙工程清单，未发布目录。'; return 1; }
    done
    /usr/bin/osascript -l JavaScript - "$stage/ohos" "$PROJECT_PATH/ohos" <<'JXA' || return $?
ObjC.import('Foundation');
function run(a) {
    if (!$.NSFileManager.defaultManager.moveItemAtPathToPathError(a[0], a[1], null)) {
        throw Error('ohos 目标已出现或无法原子发布，保留原工程与生成现场。');
    }
}
JXA
    log '✓ 已发布新的 ohos/；现有源码与配置保持原样，签名和业务插件继续按实际能力复核。'
}

jobs_hpr_java17_ok() {
    local directory="$1"
    [[ -x "$directory/bin/java" && -x "$directory/bin/javac" ]] || return 1
    jobs_hpr_command java-version 30 "$directory/bin/java" -version &&
        jobs_hpr_command javac-version 30 "$directory/bin/javac" -version || return $?
    /usr/bin/grep -Eq 'version "17([.\"]|$)' "$LOG_FILE.harmony-prepare.java-version" &&
        /usr/bin/grep -Eq '^javac 17([.[:space:]]|$)' "$LOG_FILE.harmony-prepare.javac-version"
}

jobs_hpr_system_java17() {
    /usr/libexec/java_home -v 17 2>/dev/null
}

jobs_hpr_prepare_java17() {
    local root="$1" candidate="" brew="" prefix=""
    for candidate in "${JAVA_HOME:-}" "$root/jbr/Contents/Home" "$root/jbr" "$root/jre/Contents/Home" "$(jobs_hpr_system_java17)"; do
        [[ -n "$candidate" ]] || continue
        jobs_hpr_java17_ok "$candidate" || continue
        export JAVA_HOME="$candidate" PATH="$candidate/bin:$PATH"
        return 0
    done
    for candidate in "${commands[brew]:-}" /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [[ -x "$candidate" ]] || continue
        brew="$candidate"
        break
    done
    [[ -n "$brew" ]] || { log '✖ 未找到本机 Homebrew，当前流程无法获取所需 JDK 17；保留准备现场，未继续构建。'; return 1; }
    if jobs_hpr_command java-prefix 30 "$brew" --prefix openjdk@17; then
        prefix="$(/bin/cat "$LOG_FILE.harmony-prepare.java-prefix")"
        candidate="$prefix/libexec/openjdk.jdk/Contents/Home"
        if jobs_hpr_java17_ok "$candidate"; then
            export JAVA_HOME="$candidate" PATH="$candidate/bin:$PATH"
            return 0
        fi
    fi
    log '📥 鸿蒙运行需要健康 JDK 17；来源：https://formulae.brew.sh/formula/openjdk@17；目标：当前 Homebrew 的 openjdk@17，不修改全局 Java。'
    if (( ${+functions[jobs_sdk_retry]} )); then
        JOBS_SDK_LOG_REPLACED=1 jobs_sdk_retry '鸿蒙运行 JDK 17' "$LOG_FILE.harmony-prepare.java-install" jobs_hpr_command java-install 1800 /usr/bin/env HOMEBREW_NO_AUTO_UPDATE=1 "$brew" install openjdk@17 || return $?
    else
        jobs_hpr_command java-install 1800 /usr/bin/env HOMEBREW_NO_AUTO_UPDATE=1 "$brew" install openjdk@17 || return $?
    fi
    jobs_hpr_command java-prefix 30 "$brew" --prefix openjdk@17 || return $?
    prefix="$(/bin/cat "$LOG_FILE.harmony-prepare.java-prefix")"
    candidate="$prefix/libexec/openjdk.jdk/Contents/Home"
    jobs_hpr_java17_ok "$candidate" || { log '✖ JDK 安装后编译器或运行时仍未通过 17 版本复检。'; return 1; }
    export JAVA_HOME="$candidate" PATH="$candidate/bin:$PATH"
}

jobs_hpr_prepare_tools() {
    local creator="$JOBS_HARMONY_PREPARE_PACKAGE/Resources/Tools/CreateHarmonySimulator.zsh"
    local receipt="$JOBS_HARMONY_PREPARE_RUN/toolchain-root" root="" directory="" tool="" candidate="" node="" java=""
    [[ -s "$creator" && ! -L "$creator" ]] || { log '✖ 随包鸿蒙工具获取器缺失。'; return 1; }
    : > "$receipt" || return 1
    JOBS_HARMONY_RUN_PREPARE=1 JOBS_HARMONY_TOOLS_RECEIPT="$receipt" /bin/zsh "$creator" --tools-only || return $?
    IFS= read -r root < "$receipt" || return 1
    [[ "$root" == /* && "$root" != *[[:cntrl:]]* && -d "$root" && ! -L "$root" ]] || { log '✖ 工具获取器没有返回可用的本机目录，已停止。'; return 1; }
    export DEVECO_STUDIO_HOME="$root" TOOL_HOME="$root"
    export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-$root/sdk}"
    export OHOS_SDK_HOME="${OHOS_SDK_HOME:-$DEVECO_SDK_HOME/default/openharmony}"
    for directory in ets native toolchains; do
        [[ -d "$OHOS_SDK_HOME/$directory" ]] || { log "✖ 配套 SDK 缺少 $directory：$OHOS_SDK_HOME"; return 1; }
    done
    for directory in "$root/node/bin" "$root/node" "$root/tools/node/bin" "$root/tools/node" "$root/tool/node/bin" \
        "$root/ohpm/bin" "$root/tools/ohpm/bin" "$root/hvigor/bin" "$root/tools/hvigor/bin" "$OHOS_SDK_HOME/toolchains"; do
        [[ ! -d "$directory" || ":$PATH:" == *":$directory:"* ]] || export PATH="$directory:$PATH"
    done
    jobs_hpr_prepare_java17 "$root" || return $?
    rehash
    node="${commands[node]:-}"
    java="${JAVA_HOME:+$JAVA_HOME/bin/java}"
    [[ -n "$java" ]] || java="${commands[java]:-}"
    JOBS_HARMONY_PREPARE_OHPM="${commands[ohpm]:-}"
    JOBS_HARMONY_PREPARE_HVIGOR="$PROJECT_PATH/ohos/hvigorw"
    [[ -f "$JOBS_HARMONY_PREPARE_HVIGOR" && ! -L "$JOBS_HARMONY_PREPARE_HVIGOR" ]] || JOBS_HARMONY_PREPARE_HVIGOR="${commands[hvigorw]:-}"
    [[ -x "$node" && -x "$java" && -x "$JOBS_HARMONY_PREPARE_OHPM" && -f "$JOBS_HARMONY_PREPARE_HVIGOR" && -x "$OHOS_SDK_HOME/toolchains/hdc" ]] || { log '✖ 工具包缺少 Node、Java、OHPM、Hvigor 或 HDC，保留现场。'; return 1; }
    jobs_hpr_command node-version 30 "$node" --version &&
        jobs_hpr_command java-version 30 "$java" -version &&
        jobs_hpr_command ohpm-version 30 "$JOBS_HARMONY_PREPARE_OHPM" --version &&
        jobs_hpr_command hdc-version 30 "$OHOS_SDK_HOME/toolchains/hdc" -v
}

jobs_hpr_prepare_dependencies() {
    local verifier="$JOBS_HARMONY_PREPARE_PACKAGE/Resources/Flutter运行前体检.jxa" result=0
    jobs_hpr_command_in_project pub-get 900 "$FLUTTER_BIN" pub get || return $?
    [[ -s "$verifier" && ! -L "$verifier" ]] || { log '✖ 随包鸿蒙插件核验器缺失。'; return 1; }
    jobs_hpr_command plugins 30 /usr/bin/osascript -l JavaScript "$verifier" ohos "$PROJECT_PATH" "${FLUTTER_BIN:A:h:h}" || result=$?
    if (( result != 0 )); then
        log '✖ 工具与工程已准备；现有原生插件的鸿蒙支持未通过，保留供应商源码，不跳过能力继续运行。'
        return "$result"
    fi
    jobs_hpr_command_in_ohos ohpm-install 1800 "$JOBS_HARMONY_PREPARE_OHPM" install &&
        jobs_hpr_command_in_ohos hvigor-sync 1800 /bin/sh "$JOBS_HARMONY_PREPARE_HVIGOR" --sync
}

jobs_flutter_prepare_harmony_for_run() {
    local diagnostic_key="${1:-}"
    [[ -n "$diagnostic_key" && "$diagnostic_key" != *[[:cntrl:]]* ]] || return 2
    [[ -d "$PROJECT_PATH" && ! -L "$PROJECT_PATH" && -f "$PROJECT_PATH/pubspec.yaml" && ! -L "$PROJECT_PATH/pubspec.yaml" ]] || { log '✖ 当前项目身份无效，未准备环境。'; return 1; }
    log '▶ 当前鸿蒙运行：直接准备缺失 SDK、工具、平台与依赖，完成后由本轮运行器复检并继续；Ctrl+C 取消。'
    jobs_hpr_backup_project || return $?
    jobs_hpr_prepare_sdk || return $?
    jobs_hpr_prepare_platform || return $?
    jobs_hpr_prepare_tools || return $?
    jobs_hpr_prepare_dependencies || return $?
    REPLY="$diagnostic_key"
    log '✓ 本轮鸿蒙环境准备完成，继续复检工具链、设备授权与运行条件。'
}
