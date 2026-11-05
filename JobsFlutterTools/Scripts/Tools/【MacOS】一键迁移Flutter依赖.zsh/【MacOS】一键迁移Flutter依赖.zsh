#!/bin/zsh
# 脚本自述：
# - 脚本名称：一键提取 / 导入 Flutter 依赖。
# - 核心用途：默认聚合提取私库，或按内容识别迁移包、改名的 Pub / Gradle 原始缓存。
# - 影响范围：提取只读源；导入先预检再经 YES 合并，保留已有内容，不安装 SDK 或联网。
# - 运行提示：回车默认私库、默认 ZIP、默认保留原产物；非空输入采用提示中的另一选项。

FM_PROJECT=""
FM_MODE=""
FM_TOOLS=""
FM_LOG=""
FM_DART=""
FM_DIRECTORY=""
FM_OUTPUT=""
FM_PRIVATE=1
FM_SCOPE_SELECTED=0
FM_CONFIRMED=0
FM_METADATA="migration.json"

# 首屏内容维护在脚本内；所有日志同时保留纯文本，颜色仅用于交互展示。
fm_intro() {
    local message='一键提取 / 导入 Flutter 依赖｜私库优先'
    if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" ]]; then
        printf '\033[1;31m%s\033[0m\n' "$message"
    else
        print -r -- "$message"
    fi
    print -r -- '提取：默认只迁移 Git、path、自建源等私库候选及可确认的原生私库；未知来源会单独报告。'
    print -r -- '全提取：必须输入任意非空字符确认，包含公共依赖；不会打包账户凭据或安装 SDK。'
    print -r -- '导入：支持完整迁移目录、改名的 .gradle / .pub-cache，或包含这些缓存的父目录。'
    print -r -- '先显示计划，精确 YES 后才合并；不会覆盖冲突文件；ZIP 请先解压后选择目录。'
    print -r -- 'Ctrl+C 或输入结束取消；日志确认后创建在系统临时目录。'
}
# 只解析当前入口参数，source 时不执行业务。
fm_parse() {
    while (( $# )); do
        case "$1" in
            --private-only) FM_PRIVATE=1; FM_SCOPE_SELECTED=1; shift ;;
            --confirmed) FM_CONFIRMED=1; shift ;;
            --project) (( $# >= 2 )) && [[ -z "$FM_PROJECT" ]] || return 2; FM_PROJECT="$2"; shift 2 ;;
            --mode) (( $# >= 2 )) && [[ -z "$FM_MODE" ]] || return 2; FM_MODE="$2"; shift 2 ;;
            --directory) (( $# >= 2 )) && [[ -z "$FM_DIRECTORY" ]] || return 2; FM_DIRECTORY="$2"; shift 2 ;;
            *) print -u2 -r -- '✖ 用法：脚本 --project Flutter目录 --mode export|import [--directory 目录]'; return 2 ;;
        esac
    done
    [[ "$FM_MODE" == export || "$FM_MODE" == import ]] || return 2
}
# 用户确认后建立本次日志，路径相对脚本自身定位，不依赖启动工作目录。
fm_initialize() {
    setopt NO_NOMATCH PIPE_FAIL
    umask 077
    FM_TOOLS="${${(%):-%x}:A:h:h}"
    FM_LOG="$(/usr/bin/mktemp "${TMPDIR:-/tmp/}JobsFlutterMigration.XXXXXX")" || return 1
    fm_log "日志：$FM_LOG"
    [[ -d "$FM_PROJECT" && ! -L "${FM_PROJECT%/}" && -f "$FM_PROJECT/pubspec.yaml" && ! -L "$FM_PROJECT/pubspec.yaml" ]] || { fm_log '✖ 请选择普通 Flutter 工程根目录。'; return 2; }
    FM_PROJECT="${FM_PROJECT:A}"
    [[ -f "$FM_TOOLS/FlutterDependencyMigration.dart" ]] || { fm_log '✖ 缺少同包迁移内核，请保留完整 Tools 目录。'; return 1; }
}
# 显示副本不含控制序列，保留引擎真实失败码。
fm_log() {
    print -r -- "$*" | /usr/bin/tee -a "${FM_LOG:-/dev/null}"
}
# 先保留真实存在的原路径，再兼容 Terminal 拖入转义和外侧粘贴空白，不执行输入。
fm_normalize() {
    local raw="${1%$'\r'}" variant="" candidate="" trimmed="$1"
    local -a words=() variants=("$raw")
    local whitespace=$' \t\r\n\u00a0\u202f'
    while [[ -n "$trimmed" && "$whitespace" == *"${trimmed[1]}"* ]]; do trimmed="${trimmed[2,-1]}"; done
    while [[ -n "$trimmed" && "$whitespace" == *"${trimmed[-1]}"* ]]; do
        [[ "$trimmed" == *\\[[:space:]] ]] && break
        trimmed="${trimmed[1,-2]}"
    done
    [[ "$trimmed" == "$raw" ]] || variants+=("$trimmed")
    for variant in "${variants[@]}"; do
        [[ -n "$variant" ]] || continue
        if [[ -e "$variant" ]]; then REPLY="$variant"; return 0; fi
        if [[ "$variant" == *\\* || "$variant" == \"* || "$variant" == \'* ]]; then
            words=("${(@z)variant}")
            (( ${#words} == 1 )) || continue
            candidate="${(Q)words[1]}"
        else
            candidate="$variant"
        fi
        [[ "$candidate" == '~' ]] && candidate="$HOME"
        [[ "$candidate" == '~/'* ]] && candidate="$HOME/${candidate#\~/}"
        [[ "$candidate" == /* && "$candidate" != *$'\n'* && "$candidate" != *$'\r'* ]] || continue
        REPLY="$candidate"
        [[ ! -e "$candidate" ]] || return 0
    done
    [[ -n "${REPLY:-}" ]]
}
# 迁移是文件操作，优先使用项目 Dart；已有原生 PATH Dart 仅作执行器，不切换项目 SDK。
fm_resolve_dart() {
    local candidate="" found="$(whence -p dart 2>/dev/null)" discovered_sdk=""
    [[ -z "$found" ]] || discovered_sdk="${found:A:h}/cache/dart-sdk/bin/dart"
    for candidate in "$FM_PROJECT/.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart" "$discovered_sdk" "$found"; do
        [[ -n "$candidate" && -x "$candidate" ]] || continue
        /usr/bin/file -b "${candidate:A}" | /usr/bin/grep -q 'Mach-O' || continue
        "$candidate" --version </dev/null >/dev/null 2>&1 || continue
        FM_DART="${candidate:A}"
        fm_log "✔ 本地原生 Dart 执行器：$FM_DART（只运行迁移内核，不切换工程 SDK）"
        return 0
    done
    fm_log '✖ 未找到健康的本地原生 Dart；请先准备项目 FVM 或已有 Dart。不会下载或执行 SDK shim。'
    return 3
}
# 默认私库；任何非空输入（包括空格）才授权公共依赖一并提取。
fm_choose_scope() {
    local answer=""
    fm_log '🔐 私库是本次迁移重点：默认仅提取私库候选；来源不能确认的项目会写入告警。'
    IFS= read -r 'answer?直接回车 = 只提取私库；输入任意字符再回车 = 全提取：' || return 130
    FM_PRIVATE=1
    [[ -z "$answer" ]] || FM_PRIVATE=0
    if (( FM_PRIVATE )); then fm_log '🔐 已选择：只提取私库。'; else fm_log '➤ 已明确选择：全提取（公共 + 私库）。'; fi
}
# 路径为空持续重问导入来源，EOF 退出；输出默认桌面，不把空格当空输入。
fm_read_directory() {
    local value="$FM_DIRECTORY" desktop=""
    if [[ "$FM_MODE" == export ]]; then
        desktop="$(/usr/bin/osascript -e 'POSIX path of (path to desktop folder)' 2>/dev/null)" || desktop=""
        [[ -n "$desktop" ]] || desktop="$HOME/Desktop"
        if [[ -z "$value" ]]; then
            IFS= read -r "value?输入或拖入输出父目录（直接回车：$desktop）：" || return 130
            [[ -n "$value" ]] || value="$desktop"
        fi
        REPLY=""
        fm_normalize "$value" || { fm_log '✖ 请输入一个目录的绝对路径。'; return 2; }
        FM_DIRECTORY="$REPLY"
    else
        while true; do
            if [[ -z "$value" ]]; then
                IFS= read -r 'value?输入或拖入迁移目录 / 原始缓存目录 / 包含缓存的父目录：' || return 130
            fi
            if [[ -z "$value" ]]; then fm_log '尚未输入依赖目录，请重新选择；Ctrl+C 取消。'; continue; fi
            REPLY=""
            if fm_normalize "$value" && [[ -d "$REPLY" && ! -L "${REPLY%/}" ]]; then
                FM_DIRECTORY="${REPLY:A}"
                return 0
            fi
            fm_log '✖ 请选择一个普通目录；ZIP 请先解压。'
            value=""
        done
    fi
}
# 协议行用于精确定位本次新产物；不通过文件夹扫描猜测旧导出。
fm_export() {
    local result=0 line="" receipt=""
    local -a args=("$FM_TOOLS/FlutterDependencyMigration.dart" export --project "$FM_PROJECT" --destination "$FM_DIRECTORY")
    (( FM_PRIVATE )) || args+=(--all)
    receipt="$(/usr/bin/mktemp "${TMPDIR:-/tmp/}JobsFlutterMigrationReceipt.XXXXXX")" || return 1
    fm_log "📤 来源工程：$FM_PROJECT；输出父目录：$FM_DIRECTORY"
    "$FM_DART" "${args[@]}" 2>&1 | /usr/bin/tee -a "$FM_LOG" "$receipt"
    result=$?
    if (( result != 0 )); then /bin/rm -f -- "$receipt"; return "$result"; fi
    while IFS= read -r line; do
        [[ "$line" != JOBS_MIGRATION_OUTPUT=* ]] || FM_OUTPUT="${line#JOBS_MIGRATION_OUTPUT=}"
    done < "$receipt"
    /bin/rm -f -- "$receipt"
    [[ -n "$FM_OUTPUT" && -d "$FM_OUTPUT" && ! -L "$FM_OUTPUT" && -f "$FM_OUTPUT/$FM_METADATA" && "${FM_OUTPUT:A:h}" == "${FM_DIRECTORY:A}" ]] || { fm_log '✖ 内核未返回可验证的本次导出目录，未压缩或删除任何目录。'; return 1; }
    fm_zip_offer
}
# ZIP 先写私有临时文件并检验完整性；成功后才询问是否删除本次新产物。
# 对照已解压的 ZIP 核对整个目录；新增链接、隐藏文件或内容变化均阻止删除。
fm_zip_source_matches() {
    local source="$1" verified="$2" unusual=""
    [[ -d "$source" && ! -L "$source" && -d "$verified" && ! -L "$verified" ]] || return 1
    unusual="$(/usr/bin/find "$source" ! -type f ! -type d -print -quit 2>> "$FM_LOG")" || return 1
    [[ -z "$unusual" ]] || return 1
    /usr/bin/diff -qr "$source" "$verified" >> "$FM_LOG" 2>&1
}
# ZIP 先写私有临时文件并解压核验完整目录；删除前再次比较，保留确认期间改动。
fm_zip_offer() {
    local answer="" archive="$FM_OUTPUT.zip" temporary="" verification="" verified="" fingerprint="" current=""
    IFS= read -r 'answer?是否打包为 ZIP？直接回车 = 打包；任意字符再回车 = 不打包：' || return 130
    if [[ -n "$answer" ]]; then fm_log "✔ 保留提取目录：$FM_OUTPUT"; return 0; fi
    [[ ! -e "$archive" && ! -L "$archive" ]] || { fm_log "✖ ZIP 已存在，未覆盖：$archive；提取目录保留。"; return 1; }
    fingerprint="$(/usr/bin/shasum -a 256 "$FM_OUTPUT/$FM_METADATA")" || return 1
    temporary="$(/usr/bin/mktemp "${archive}.partial.XXXXXX")" || return 1
    verification="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp/}JobsFlutterZipVerify.XXXXXX")" || { /bin/rm -f -- "$temporary"; return 1; }
    verified="$verification/${FM_OUTPUT:t}"
    if ! /usr/bin/ditto -c -k --keepParent "$FM_OUTPUT" "$temporary" >> "$FM_LOG" 2>&1 ||
       ! /usr/bin/unzip -tq "$temporary" >> "$FM_LOG" 2>&1 ||
       ! /usr/bin/ditto -x -k "$temporary" "$verification" >> "$FM_LOG" 2>&1 ||
       ! fm_zip_source_matches "$FM_OUTPUT" "$verified"; then
        /bin/rm -f -- "$temporary"
        /bin/rm -r -- "$verification"
        fm_log '✖ ZIP 生成、解压或完整目录核对失败，提取目录完整保留；详情见日志。'
        return 1
    fi
    current="$(/usr/bin/shasum -a 256 "$FM_OUTPUT/$FM_METADATA")" || current=""
    if [[ "$current" != "$fingerprint" ]]; then
        /bin/rm -f -- "$temporary"
        /bin/rm -r -- "$verification"
        fm_log '✖ 打包期间清单发生变化，原目录保留。'
        return 1
    fi
    if ! /bin/mv -n -- "$temporary" "$archive" || [[ -e "$temporary" ]]; then
        /bin/rm -f -- "$temporary"
        /bin/rm -r -- "$verification"
        fm_log '✖ ZIP 目标发生冲突，原目录保留。'
        return 1
    fi
    fm_log "✔ ZIP 已完成并校验：$archive"
    if ! IFS= read -r 'answer?是否删除原始提取目录？直接回车 = 不删除；任意字符再回车 = 删除：'; then
        /bin/rm -r -- "$verification"
        return 130
    fi
    if [[ -z "$answer" ]]; then
        /bin/rm -r -- "$verification"
        fm_log "✔ 保留提取目录：$FM_OUTPUT"
        return 0
    fi
    current="$(/usr/bin/shasum -a 256 "$FM_OUTPUT/$FM_METADATA")" || current=""
    if [[ -L "$FM_OUTPUT" || ! -d "$FM_OUTPUT" || "${FM_OUTPUT:A:h}" != "${FM_DIRECTORY:A}" || "$current" != "$fingerprint" ]] ||
       ! fm_zip_source_matches "$FM_OUTPUT" "$verified"; then
        /bin/rm -r -- "$verification"
        fm_log '✖ 提取目录或文件内容在打包后发生变化，未删除；原目录与已验证 ZIP 均保留。'
        return 1
    fi
    /bin/rm -r -- "$verification"
    /bin/rm -r -- "$FM_OUTPUT" || return 1
    fm_log '✔ 已按选择删除本次提取目录，ZIP 保留。'
}
# 完整预检通过后才请求一次精确 YES；实际执行仍由内核重新校验。
fm_import() {
    local answer="" result=0 receipt="" line="" expected="" markers=0
    local -a args=("$FM_TOOLS/FlutterDependencyMigration.dart" import --project "$FM_PROJECT" --source "$FM_DIRECTORY")
    fm_log "📥 来源目录：$FM_DIRECTORY；目标：当前工程及本账户对应缓存（按计划逐项展示）。"
    receipt="$(/usr/bin/mktemp "${TMPDIR:-/tmp/}JobsFlutterMigrationPlan.XXXXXX")" || return 1
    "$FM_DART" "${args[@]}" 2>&1 | /usr/bin/tee -a "$FM_LOG" "$receipt"
    result=$?
    if (( result != 0 )); then /bin/rm -f -- "$receipt"; return "$result"; fi
    while IFS= read -r line; do
        if [[ "$line" == JOBS_MIGRATION_PLAN=* ]]; then
            expected="${line#JOBS_MIGRATION_PLAN=}"
            markers=$((markers + 1))
        fi
    done < "$receipt"
    /bin/rm -f -- "$receipt"
    [[ "$markers" == 1 && "$expected" =~ '^[0-9a-f]{64}$' ]] || { fm_log '✖ 未取得唯一且有效的预检指纹，未执行导入。'; return 1; }
    IFS= read -r 'answer?输入精确大写 YES 执行以上合并；其它输入取消：' || return 130
    [[ "$answer" == YES ]] || { fm_log '已取消，未写入工程或环境。'; return 0; }
    "$FM_DART" "${args[@]}" --apply --expected-plan "$expected" 2>&1 | /usr/bin/tee -a "$FM_LOG"
}
# 首屏自述和确认先于日志、路径读取与文件迁移。
main() {
    local answer="" result=0
    fm_intro
    fm_parse "$@" || return $?
    if (( ! FM_CONFIRMED )); then
        IFS= read -r 'answer?已了解用途与影响，直接回车继续；非空取消：' || return 0
        [[ -z "$answer" ]] || return 0
    fi
    fm_initialize && fm_resolve_dart || return $?
    if [[ "$FM_MODE" == export && "$FM_SCOPE_SELECTED" == 0 ]]; then fm_choose_scope || return $?; fi
    fm_read_directory || return $?
    if [[ "$FM_MODE" == export ]]; then fm_export; else fm_import; fi
    result=$?
    (( result != 0 )) || fm_log "✔ 完成；日志：$FM_LOG"
    return "$result"
}

if [[ "$ZSH_EVAL_CONTEXT" == toplevel ]]; then
    main "$@"
fi
