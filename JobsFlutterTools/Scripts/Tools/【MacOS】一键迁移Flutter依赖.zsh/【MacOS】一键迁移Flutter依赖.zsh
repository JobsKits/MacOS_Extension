#!/bin/zsh
# 脚本自述：
# - 脚本名称：一键提取 / 导入 Flutter 依赖。
# - 核心用途：默认聚合提取私库，或按内容识别迁移包、改名的 Pub / Gradle 原始缓存。
# - 影响范围：提取只读源；导入先预检，冲突可选择导入源或本机数据，经备份选择和 YES 后合并，不安装 SDK 或联网。
# - 运行提示：回车默认私库、默认 ZIP、默认保留原产物；非空输入采用提示中的另一选项。
# - 等待反馈：导入扫描与实际合并分别显示已耗时；等待输入时停止计时。

# JOBS_INPUT_CHOICE_STYLE_BEGIN
# 只展示提示选项；不读取答案、不改变默认值、返回码或业务环境。
jobs_prompt_color_ready() {
  [ -z "${NO_COLOR+x}" ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
    [ "${PLAIN_OUTPUT:-0}" != 1 ] && [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]
}
# 原生 awk 分段着色；任意/非空输入优先，括号内外沿用同一个选项。
jobs_prompt_format() {
  /usr/bin/awk -v color="${1:-0}" -v lines="${2:-0}" -v keep="${3:-0}" '
    function typedEnter(value, start, prefix) {
      prefix = substr(value, 1, start - 1)
      gsub(/[“”‘’「」『』"]/, "", prefix)
      gsub(sprintf("%c", 39), "", prefix)
      if (prefix ~ /(空格|[Ss][Pp][Aa][Cc][Ee])[[:space:]]*(后|再|并|[Tt][Hh][Ee][Nn])?[[:space:]]*$/) return 1
      return prefix ~ /(输入|键入|填写|[Tt]ype)[^；;|]*[[:alnum:]_+-]+[[:space:]]*(后|再|并)?[[:space:]]*$/
    }
    function greenPosition(value, token, start) {
      if (match(value, /(直接|仅|只需|只|按下|按)?[[:space:]]*(回车|回車)/)) {
        start = RSTART
        return typedEnter(value, start) ? 0 : start
      }
      if (!match(value, /(^|[^[:alnum:]_])([Ee][Nn][Tt][Ee][Rr]|[Rr][Ee][Tt][Uu][Rr][Nn])([^[:alnum:]_]|$)/)) return 0
      start = RSTART
      token = substr(value, RSTART, RLENGTH)
      match(token, /[Ee][Nn][Tt][Ee][Rr]|[Rr][Ee][Tt][Uu][Rr][Nn]/)
      start += RSTART - 1
      return typedEnter(value, start) ? 0 : start
    }
    function segment(value, inherited, start, kind, prefix, body, red, green, connector, left, right, splitAt) {
      if (value == "") return value
      kind = inherited
      start = 1
      if (!kind) {
        if (match(value, /(输入)?(任意|任何)(非空)?(字符|内容|输入|键)|非空(字符|内容|输入)?|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key/)) {
          red = RSTART
        }
        green = greenPosition(value)
        if (red && green && green < red) {
          left = substr(value, 1, red - 1)
          right = substr(value, red)
          connector = ""
          if (match(left, /(或者|或)[[:space:]]*$/)) {
            connector = substr(left, RSTART)
            left = substr(left, 1, RSTART - 1)
          }
          return segment(left, 0) connector segment(right, 31)
        }
        if (red && green && red < green && match(value, /或[[:space:]]*(直接|仅|只需|只|按下|按)?(回车|回車)/)) {
          splitAt = RSTART
          return segment(substr(value, 1, splitAt - 1), 31) "或" segment(substr(value, splitAt + length("或")), 0)
        }
        if (red) {
          kind = 31
          start = red
        } else if (green) {
          kind = 32
          start = green
        }
      }
      if (!kind || !color) return value
      prefix = substr(value, 1, start - 1)
      body = substr(value, start)
      return prefix esc "[1;" kind "m" body esc "[0m"
    }
    function render(value, output, part, boundary, inherited, kind, consumed, depth, original) {
      original = value
      gsub(esc "\\[[0-9;]*m", "", value)
      if (color && keep && !greenPosition(value) && value !~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) return original
      output = ""
      inherited = 0
      depth = 0
      while (match(value, /[；;\/|，,、？?：:=＝（）()\[\]【】]/)) {
        part = substr(value, 1, RSTART - 1)
        boundary = substr(value, RSTART, RLENGTH)
        consumed = RSTART + RLENGTH
        output = output segment(part, inherited) boundary
        if (boundary ~ /[（(\[【]/) {
          depth++
          if (part ~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) inherited = 31
          else if (greenPosition(part)) inherited = 32
        } else if (boundary ~ /[）)\]】]/) {
          if (depth) depth--
        } else if (boundary ~ /[：:=＝]/) {
          if (!inherited) {
            if (part ~ /(任意|任何|非空|其它输入|其他输入)/) inherited = 31
            else if (greenPosition(part)) inherited = 32
          }
        } else if (!depth) inherited = 0
        value = substr(value, consumed)
      }
      return output segment(value, inherited)
    }
    BEGIN { esc = sprintf("%c", 27); first = 1 }
    {
      if (lines == 2) {
        if (!first) printf "%s\n", render(pending)
        pending = $0
        first = 0
        next
      }
      if (!lines && !first) printf "\n"
      printf "%s", render($0)
      if (lines) printf "\n"
      first = 0
    }
    END {
      if (lines == 2 && !first) {
        sub(sprintf("%c", 1) "$", "", pending)
        printf "%s", render(pending)
      }
    }
  '
}
# read 的命令替换会使 stdout 成为管道，按输入与提示所在 stderr 判断终端。
jobs_prompt_render() {
  local jobs_prompt_color=0
  if [ -t 0 ] && [ -t 2 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  printf "%s" "$1" | jobs_prompt_format "$jobs_prompt_color" 0
}
# 仅放在显示链末端；tee 在此函数之前接收纯文本，不把 ANSI 写入日志。
jobs_prompt_stream() {
  local jobs_prompt_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  jobs_prompt_format "$jobs_prompt_color" 1 1
}
# 显示管道保留原末尾换行；只删除本轮追加的最后一个结束标记。
jobs_prompt_filter() {
  local jobs_prompt_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  { /bin/cat; printf '\001'; } | jobs_prompt_format "$jobs_prompt_color" 2 1
}
# 仅包装原 printf/echo/print 展示，原参数、尾换行与显示命令退出码保持不变。
jobs_prompt_output() {
  local jobs_prompt_status=0 jobs_prompt_stderr=0 jobs_prompt_arg="" jobs_prompt_previous=""
  if [ "${1:-}" = print ]; then
    for jobs_prompt_arg in "$@"; do
      case "$jobs_prompt_arg" in -?*u2*|-u2) jobs_prompt_stderr=1 ;; esac
      if [ "$jobs_prompt_previous" = -u ] && [ "$jobs_prompt_arg" = 2 ]; then jobs_prompt_stderr=1; fi
      jobs_prompt_previous="$jobs_prompt_arg"
      [ "$jobs_prompt_arg" != -- ] || break
    done
  fi
  if [ -n "${ZSH_VERSION:-}" ]; then
    if [ "$jobs_prompt_stderr" = 1 ]; then
      "$@" 2>&1 | jobs_prompt_filter >&2
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    else
      "$@" | jobs_prompt_filter
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    fi
  elif [ -n "${BASH_VERSION:-}" ]; then
    "$@" | jobs_prompt_filter
    jobs_prompt_status=$(( ${PIPESTATUS[0]} != 0 ? ${PIPESTATUS[0]} : ${PIPESTATUS[1]} ))
  else
    "$@" | jobs_prompt_filter
    jobs_prompt_status=$?
  fi
  return "$jobs_prompt_status"
}
# 仅替换日志 primitive 的 tee：磁盘同步追加纯文，终端保留非选项原色。
jobs_prompt_tee() {
  local jobs_prompt_log="$1" jobs_prompt_line="" jobs_prompt_newline=0
  while :; do
    jobs_prompt_line=""
    if IFS= read -r jobs_prompt_line; then jobs_prompt_newline=1; else jobs_prompt_newline=0; [ -n "$jobs_prompt_line" ] || break; fi
    if [ "$jobs_prompt_newline" = 1 ]; then
      { printf '%s\n' "$jobs_prompt_line"; printf '\001'; } | jobs_prompt_format 0 2 >> "$jobs_prompt_log" || return $?
      printf '%s\n' "$jobs_prompt_line" | jobs_prompt_filter || return $?
    else
      { printf '%s' "$jobs_prompt_line"; printf '\001'; } | jobs_prompt_format 0 2 >> "$jobs_prompt_log" || return $?
      printf '%s' "$jobs_prompt_line" | jobs_prompt_filter || return $?
    fi
  done
}
# JOBS_INPUT_CHOICE_STYLE_END

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
FM_PLAN=""
FM_CONFLICTS=0
FM_CONFLICT_POLICY=""
FM_BACKUP_DIRECTORY=""
FM_NO_BACKUP=0

# 首屏内容维护在脚本内；所有日志同时保留纯文本，颜色仅用于交互展示。
fm_intro() {
    local message='一键提取 / 导入 Flutter 依赖｜私库优先'
    if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" ]]; then
        printf '\033[1;31m%s\033[0m\n' "$message"
    else
        print -r -- "$message"
    fi
    print -r -- '提取：默认只迁移 Git、path、自建源等私库候选及可确认的原生私库；未知来源会单独报告。'
    jobs_prompt_output print -r -- '全提取：必须输入任意非空字符确认，包含公共依赖；不会打包账户凭据或安装 SDK。'
    print -r -- '导入：支持完整迁移目录、改名的 .gradle / .pub-cache，或包含这些缓存的父目录。'
    jobs_prompt_output print -r -- '导入冲突用 fzf 选择：导入源（推荐）或保留本机；使用导入源时回车默认备份，非空输入不备份，备份父目录默认系统桌面。'
    print -r -- '先显示计划，精确 YES 后才合并；备份校验失败不覆盖，目录类型冲突仍停止；ZIP 请先解压后选择目录。'
    print -r -- '导入扫描与实际合并分别显示已耗时；等待输入时停止计时，耗时不代表完成百分比。'
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
    print -r -- "$*" | jobs_prompt_tee "${FM_LOG:-/dev/null}"
}
# 格式化实际经过的秒数，小时不按天数归零。
fm_duration() {
    local elapsed="$1"
    printf '%02d:%02d:%02d' "$((elapsed / 3600))" "$((elapsed / 60 % 60))" "$((elapsed % 60))"
}
# 仅停止本次等待包装器创建的子树，不影响其它 Dart 或导入会话。
fm_stop_tree() {
    local root="$1" child=""
    for child in $(/usr/bin/pgrep -P "$root" 2>/dev/null); do
        fm_stop_tree "$child"
    done
    kill -TERM "$root" 2>/dev/null || true
    kill -KILL "$root" 2>/dev/null || true
}
# 原生输出先清除临时计时行；协议回执与日志只保存完整的纯文本行。
fm_timed_stream() {
    local receipt="$1" live="$2" line=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        if (( live )); then printf '\r\033[2K%s\n' "$line"; else print -r -- "$line"; fi
        print -r -- "$line" >> "${FM_LOG:-/dev/null}" || return 1
        [[ -z "$receipt" ]] || print -r -- "$line" >> "$receipt" || return 1
    done
}
# 交互终端每秒刷新单行；纯文本及落盘日志每十秒保留一条等待记录。
fm_ticker() {
    local title="$1" started="$2" live="$3" elapsed=0 logged=0 duration=""
    while true; do
        /bin/sleep 1
        elapsed=$((SECONDS - started))
        duration="$(fm_duration "$elapsed")"
        if (( live )); then printf '\r\033[2K⏳ %s｜已耗时 %s（Ctrl+C 取消）' "$title" "$duration"; fi
        if (( elapsed - logged >= 10 )); then
            logged="$elapsed"
            (( live )) || print -r -- "⏳ $title｜已耗时 $duration（Ctrl+C 取消）"
            print -r -- "⏳ $title｜已耗时 $duration（Ctrl+C 取消）" >> "${FM_LOG:-/dev/null}"
        fi
    done
}
# 在独立作用域中等待内核并收回计时器，成功、失败和中断均保留真实退出状态。
fm_run_timed() {
    setopt LOCAL_OPTIONS LOCAL_TRAPS PIPE_FAIL
    local title="$1" receipt="$2" task_pid="" ticker_pid="" result=0 interrupted=0 live=0 started=$SECONDS
    shift 2
    [[ ! -t 1 || -z "${TERM:-}" || "$TERM" == dumb || -n "${NO_COLOR+x}" || "${PLAIN_OUTPUT:-0}" == 1 ]] || live=1
    trap 'interrupted=130; [[ -z "$task_pid" ]] || fm_stop_tree "$task_pid"' INT
    trap 'interrupted=143; [[ -z "$task_pid" ]] || fm_stop_tree "$task_pid"' TERM
    trap 'interrupted=129; [[ -z "$task_pid" ]] || fm_stop_tree "$task_pid"' HUP
    trap '[[ -z "$ticker_pid" ]] || { fm_stop_tree "$ticker_pid"; wait "$ticker_pid" 2>/dev/null; }; [[ -z "$task_pid" ]] || { fm_stop_tree "$task_pid"; wait "$task_pid" 2>/dev/null; }' EXIT
    fm_log "⏳ $title｜已耗时 00:00:00（Ctrl+C 取消）"
    ( "$@" 2>&1 | fm_timed_stream "$receipt" "$live" ) <&0 &
    task_pid=$!
    fm_ticker "$title" "$started" "$live" &
    ticker_pid=$!
    wait "$task_pid" || result=$?
    task_pid=""
    fm_stop_tree "$ticker_pid"
    wait "$ticker_pid" 2>/dev/null
    ticker_pid=""
    (( live == 0 )) || printf '\r\033[2K'
    (( interrupted == 0 )) || result="$interrupted"
    local duration="$(fm_duration "$((SECONDS - started))")"
    if (( result == 0 )); then
        fm_log "✔ $title 完成｜总用时 $duration"
    elif (( interrupted != 0 || result == 129 || result == 130 || result == 143 )); then
        fm_log "⚠ $title 已中断｜总用时 $duration"
    else
        fm_log "✖ $title 失败（退出码 $result）｜总用时 $duration"
    fi
    return "$result"
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
    IFS= read -r "answer?$(jobs_prompt_render '直接回车 = 只提取私库；输入任意字符再回车 = 全提取：')" || return 130
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
            IFS= read -r "value?$(jobs_prompt_render "输入或拖入输出父目录（直接回车：$desktop）：")" || return 130
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
    IFS= read -r "answer?$(jobs_prompt_render '是否打包为 ZIP？直接回车 = 打包；任意字符再回车 = 不打包：')" || return 130
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
    if ! IFS= read -r "answer?$(jobs_prompt_render '是否删除原始提取目录？直接回车 = 不删除；任意字符再回车 = 删除：')"; then
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
# 只读计划单独解析协议，文件详情与进度继续实时显示并落盘。
fm_preview_import() {
    local result=0 receipt="" line="" markers=0 conflict_markers=0
    FM_PLAN=""
    FM_CONFLICTS=0
    receipt="$(/usr/bin/mktemp "${TMPDIR:-/tmp/}JobsFlutterMigrationPlan.XXXXXX")" || return 1
    fm_run_timed '扫描并校验导入计划' "$receipt" "$FM_DART" "$@"
    result=$?
    if (( result != 0 )); then /bin/rm -f -- "$receipt"; return "$result"; fi
    while IFS= read -r line; do
        if [[ "$line" == JOBS_MIGRATION_PLAN=* ]]; then
            FM_PLAN="${line#JOBS_MIGRATION_PLAN=}"
            markers=$((markers + 1))
        elif [[ "$line" == JOBS_MIGRATION_CONFLICTS=* ]]; then
            FM_CONFLICTS="${line#JOBS_MIGRATION_CONFLICTS=}"
            conflict_markers=$((conflict_markers + 1))
        fi
    done < "$receipt"
    /bin/rm -f -- "$receipt"
    [[ "$markers" == 1 && "$FM_PLAN" =~ '^[0-9a-f]{64}$' ]] || { fm_log '✖ 未取得唯一且有效的预检指纹，未执行导入。'; return 1; }
    [[ "$conflict_markers" == 1 && "$FM_CONFLICTS" == <-> ]] || { fm_log '✖ 冲突数量响应缺失或无效，未执行导入。'; return 1; }
}
# 终端优先 fzf；没有可用选择器时使用明确的编号菜单，取消不选中默认项。
fm_choose_conflict_policy() {
    local fzf_bin="${FM_FZF_BIN:-}" candidate="" answer="" result=0
    FM_CONFLICT_POLICY=""
    if [[ "${JOBS_FLUTTER_MIGRATION_FZF:-}" != 0 ]] && { [[ -t 0 && -t 1 ]] || [[ "${JOBS_FLUTTER_MIGRATION_FZF:-}" == always ]]; }; then
        for candidate in "$fzf_bin" "$(whence -p fzf 2>/dev/null)" /opt/homebrew/bin/fzf /usr/local/bin/fzf; do
            [[ -n "$candidate" && -x "$candidate" ]] || continue
            fzf_bin="$candidate"
            break
        done
        if [[ -n "$fzf_bin" && -x "$fzf_bin" ]]; then
            answer="$(printf '%s\n' $'source\t使用导入源的数据（推荐，覆盖冲突文件）' $'existing\t保留当前环境的数据（跳过冲突文件）' |
                /usr/bin/env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_OPTS_FILE "$fzf_bin" --no-multi --layout=reverse --height=50% --delimiter=$'\t' --with-nth=2.. --prompt='冲突处理 › ' --header='↑/↓ 选择，回车确认，Esc / Ctrl+C 取消；只影响列出的冲突文件。')" || result=$?
            case "$result" in
                0) FM_CONFLICT_POLICY="${answer%%$'\t'*}" ;;
                1|130) fm_log '已取消，未写入工程或环境。'; return 130 ;;
                *) fm_log "⚠ fzf 选择失败（$result），回退编号选择。" ;;
            esac
            if (( result == 0 )); then
                [[ "$FM_CONFLICT_POLICY" == source || "$FM_CONFLICT_POLICY" == existing ]] || { fm_log '✖ 选择器返回无效策略，未执行导入。'; return 1; }
                return 0
            fi
        fi
    fi
    fm_log '冲突处理：1、使用导入源的数据（推荐，覆盖冲突文件）；2、保留当前环境的数据（跳过冲突文件）。'
    while true; do
        IFS= read -r "answer?$(jobs_prompt_render '选择 1 / 2（回车默认 1；q 取消）：')" || return 130
        case "$answer" in
            ''|1) FM_CONFLICT_POLICY=source; return 0 ;;
            2) FM_CONFLICT_POLICY=existing; return 0 ;;
            [qQ]|$'\e') return 130 ;;
            *) fm_log '⚠ 请输入 1 或 2；q / Ctrl+C 取消。' ;;
        esac
    done
}
# 备份选项分别用绿、红强调；纯文本终端和日志不带颜色码。
fm_show_backup_prompt() {
    local question='是否备份将被覆盖的当前文件？' backup='回车 = 备份' overwrite='任意字符再回车 = 不备份直接覆盖：'
    if [[ -t 0 && -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" && "${PLAIN_OUTPUT:-0}" != 1 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]]; then
        printf '%s \033[1;32m%s\033[0m；\033[1;31m%s\033[0m' "$question" "$backup" "$overwrite"
    else
        printf '%s %s；%s' "$question" "$backup" "$overwrite"
    fi
    [[ -z "${FM_LOG:-}" ]] || print -r -- "$question $backup；$overwrite" >> "$FM_LOG"
}
# 使用导入源时二次确认备份；空路径取系统桌面，输入只按路径解析。
fm_choose_conflict_backup() {
    local answer="" directory="" desktop=""
    FM_NO_BACKUP=0
    FM_BACKUP_DIRECTORY=""
    fm_show_backup_prompt || return $?
    IFS= read -r answer || return 130
    if [[ -n "$answer" ]]; then
        FM_NO_BACKUP=1
        fm_log '➤ 已选择不保留备份；最终确认后覆盖冲突文件。'
        return 0
    fi
    desktop="$(/usr/bin/osascript -e 'POSIX path of (path to desktop folder)' 2>/dev/null)" || desktop=""
    [[ -n "$desktop" ]] || desktop="$HOME/Desktop"
    IFS= read -r "directory?$(jobs_prompt_render "输入或拖入备份父目录（回车默认：$desktop）：")" || return 130
    [[ -n "$directory" ]] || directory="$desktop"
    REPLY=""
    fm_normalize "$directory" || { fm_log '✖ 请输入一个备份目录的绝对路径。'; return 2; }
    FM_BACKUP_DIRECTORY="$REPLY"
    fm_log "📂 将备份到「$FM_BACKUP_DIRECTORY」内的新文件夹，校验通过后再覆盖。"
}
# 按冲突选择生成最终计划；YES 后内核再次验证并按备份策略执行。
fm_import() {
    local answer=""
    local -a args=("$FM_TOOLS/FlutterDependencyMigration.dart" import --project "$FM_PROJECT" --source "$FM_DIRECTORY")
    fm_log "📥 来源目录：$FM_DIRECTORY；目标：当前工程及本账户对应缓存（按计划逐项展示）。"
    fm_preview_import "${args[@]}" || return $?
    if (( FM_CONFLICTS > 0 )); then
        fm_log "⚠ 发现 $FM_CONFLICTS 个文件内容冲突，请选择本轮使用的数据。"
        fm_choose_conflict_policy || return $?
        args+=(--conflict-policy "$FM_CONFLICT_POLICY")
        if [[ "$FM_CONFLICT_POLICY" == source ]]; then
            fm_log '➤ 已选择使用导入源的数据，最终确认后替换列出的冲突文件。'
            fm_choose_conflict_backup || return $?
            if (( FM_NO_BACKUP )); then args+=(--no-backup); else args+=(--backup-directory "$FM_BACKUP_DIRECTORY"); fi
        else
            fm_log '➤ 已选择保留当前环境的数据，跳过冲突文件并补齐其它缺失项。'
        fi
        fm_preview_import "${args[@]}" || return $?
    fi
    while true; do
        IFS= read -r "answer?$(jobs_prompt_render '输入精确大写 YES 执行以上合并；直接回车重新询问，其它非空输入取消：')" || return 130
        [[ -z "$answer" ]] || break
        fm_log '尚未输入确认内容，请重新确认；未写入工程或环境。'
    done
    [[ "$answer" == YES ]] || { fm_log '已取消，未写入工程或环境。'; return 0; }
    fm_run_timed '校验、备份并导入依赖' '' "$FM_DART" "${args[@]}" --apply --expected-plan "$FM_PLAN"
}
# 首屏自述和确认先于日志、路径读取与文件迁移。
main() {
    local answer="" result=0
    fm_intro
    fm_parse "$@" || return $?
    if (( ! FM_CONFIRMED )); then
        IFS= read -r "answer?$(jobs_prompt_render '已了解用途与影响，直接回车继续；非空取消：')" || return 0
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
