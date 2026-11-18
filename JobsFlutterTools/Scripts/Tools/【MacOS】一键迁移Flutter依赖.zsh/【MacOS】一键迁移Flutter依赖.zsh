#!/bin/zsh
# 脚本自述：
# - 脚本名称：一键提取 / 导入 Flutter 依赖。
# - 核心用途：默认聚合提取私库，或按内容识别迁移包、改名的 Pub / Gradle 原始缓存。
# - 影响范围：提取只读源；导入先预检，冲突可选择导入源或本机数据，经备份选择和 YES 后合并，不安装 SDK 或联网。
# - 运行提示：回车默认私库、默认 ZIP、默认保留原产物；非空输入采用提示中的另一选项。
# - 等待反馈：导入扫描与实际合并分别显示已耗时；等待输入时停止计时。

# JOBS_INPUT_CHOICE_STYLE_BEGIN
# 只展示提示选项；不读取答案、不改变默认值、返回码或业务环境。
# URL仅供显示；纯文本日志传color=0。
jobs_url_format() {
  LC_ALL=en_US.UTF-8 /usr/bin/awk -v color="${1:-0}" -v lines="${2:-1}" '
    # URL 范围只在展示文本上识别；不会改写真实请求或输出数据。
    function urlInit() {
      urlPattern = "[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]<>\"" sprintf("%c", 39) esc "]+"
      urlPunctuationCount = split("，|。|；|：|！|？|、|（|）|【|】|《|》|「|」|『|』|“|”|‘|’", urlPunctuation, "\\|")
    }
    function urlCount(value, token, total, idx) {
      total = 0
      for (idx = 1; idx <= length(value); idx++) if (substr(value, idx, 1) == token) total++
      return total
    }
    function urlTrim(value, idx, at, last) {
      for (idx = 1; idx <= urlPunctuationCount; idx++) {
        at = index(value, urlPunctuation[idx])
        if (at) value = substr(value, 1, at - 1)
      }
      while (length(value)) {
        last = substr(value, length(value), 1)
        if (index(".,;:!?", last) > 0 || (last == ")" && urlCount(value, ")") > urlCount(value, "(")) ||
            (last == "]" && urlCount(value, "]") > urlCount(value, "[")) || (last == "}" && urlCount(value, "}") > urlCount(value, "{"))) {
          value = substr(value, 1, length(value) - 1)
        } else break
      }
      return value
    }
    function urlClean(value, preserve, output, token, start, size) {
      gsub(esc "\\][^" esc sprintf("%c", 7) "]*(" sprintf("%c", 7) "|" esc "\\\\)", "", value)
      output = ""
      while (match(value, esc "\\[[0-?]*[ -/]*[@-~]")) {
        start = RSTART; size = RLENGTH; token = substr(value, start, size)
        output = output substr(value, 1, start - 1)
        if (preserve && token ~ /m$/) output = output token
        value = substr(value, start + size)
      }
      return output value
    }
    # 题干分段前临时遮蔽地址，地址里的 Enter、/、?、= 不参与选项识别。
    function urlProtect(value, output, at, size, token, marker, number, original) {
      urlProtectedCount = 0; output = ""; original = value; number = 0
      while (match(value, urlPattern)) {
        at = RSTART; size = RLENGTH; token = urlTrim(substr(value, at, size))
        do { marker = sprintf("%c", 2) "U" ++number sprintf("%c", 3) } while (index(original, marker))
        urlProtected[++urlProtectedCount] = token; urlMarkers[urlProtectedCount] = marker
        output = output substr(value, 1, at - 1) marker
        value = substr(value, at + length(token))
      }
      return output value
    }
    function urlRestore(value, idx, token, at) {
      for (idx = urlProtectedCount; idx > 0; idx--) {
        token = urlMarkers[idx]
        while ((at = index(value, token))) value = substr(value, 1, at - 1) urlProtected[idx] substr(value, at + length(token))
      }
      return value
    }
    # 保存原 SGR 的有效序列；RGB 中的零值不能误认为整体复位。
    function urlTrack(tokens, token, code, idx, total, reset, fields) {
      while (match(tokens, esc "\\[[0-9;:]*m")) {
        token = substr(tokens, RSTART, RLENGTH)
        tokens = substr(tokens, RSTART + RLENGTH)
        code = substr(token, 3, length(token) - 3); reset = (code == "")
        total = split(code, fields, ";")
        for (idx = 1; idx <= total; idx++) {
          if (fields[idx] == "0") reset = 1
          if ((fields[idx] == "38" || fields[idx] == "48" || fields[idx] == "58") && idx < total) {
            if (fields[idx + 1] == "2") idx += 4
            else if (fields[idx + 1] == "5") idx += 2
          }
        }
        if (reset) urlActive = ""
        urlActive = urlActive token
      }
    }
    # 用可见字符位置映射原 SGR，URL 内已有样式也会重新覆为绿下划线。
    function urlRender(value, output, visible, rest, key, at, size, token, idx, offset, url, inURL) {
      value = urlClean(value, color)
      if (!color) return value
      for (key in urlStyles) delete urlStyles[key]
      for (key in urlStarts) delete urlStarts[key]
      for (key in urlEnds) delete urlEnds[key]
      visible = ""; rest = value
      while (match(rest, esc "\\[[0-9;:]*m")) {
        at = RSTART; size = RLENGTH; token = substr(rest, at, size)
        visible = visible substr(rest, 1, at - 1)
        urlStyles[length(visible) + 1] = urlStyles[length(visible) + 1] token
        rest = substr(rest, at + size)
      }
      visible = visible rest; rest = visible; offset = 0
      while (match(rest, urlPattern)) {
        at = RSTART; size = RLENGTH; url = urlTrim(substr(rest, at, size))
        urlStarts[offset + at] = 1; urlEnds[offset + at + length(url) - 1] = 1
        offset += at + length(url) - 1; rest = substr(visible, offset + 1)
      }
      output = ""; inURL = 0
      for (idx = 1; idx <= length(visible) + 1; idx++) {
        if (idx in urlStyles) {
          token = urlStyles[idx]; output = output token; urlTrack(token)
          if (inURL) output = output esc "[32;4m"
        }
        if (idx > length(visible)) break
        if (idx in urlStarts) { output = output esc "[32;4m"; inURL = 1 }
        output = output substr(visible, idx, 1)
        if (idx in urlEnds) { output = output esc "[0m" urlActive; inURL = 0 }
      }
      return output
    }
    BEGIN { esc = sprintf("%c", 27); first = 1; urlInit() }
    {
      if (lines == 2) {
        if (!first) printf "%s\n", urlRender(pending)
        pending = $0; first = 0
      } else {
        if (!lines && !first) printf "\n"
        printf "%s", urlRender($0)
        if (lines) printf "\n"
        first = 0
      }
    }
    END {
      if (lines == 2 && !first) {
        sub(sprintf("%c", 1) "$", "", pending)
        printf "%s", urlRender(pending)
      }
    }
  '
}
# URL仅供显示；纯文本日志传color=0。
jobs_url_stream() {
  local url_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then url_color=1; fi
  jobs_url_format "$url_color" "${1:-1}"
}
jobs_prompt_color_ready() {
  env | LC_ALL=C /usr/bin/grep -qiE '^(SOURCETREE|SOURCE_TREE)' && return 1
  [ -z "${NO_COLOR+x}" ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
    [ "${PLAIN_OUTPUT:-0}" != 1 ] && [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]
}
# 原生 awk 分段着色；任意/非空输入优先，括号内外沿用同一个选项。
jobs_prompt_format() {
  # 中文字符类按UTF-8字符处理，仅约束此awk进程，保留调用者locale。
  LC_ALL=en_US.UTF-8 /usr/bin/awk -v color="${1:-0}" -v lines="${2:-0}" -v keep="${3:-0}" -v question="${4:-0}" '
    # URL 范围只在展示文本上识别；不会改写真实请求或输出数据。
    function urlInit() {
      urlPattern = "[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]<>\"" sprintf("%c", 39) esc "]+"
      urlPunctuationCount = split("，|。|；|：|！|？|、|（|）|【|】|《|》|「|」|『|』|“|”|‘|’", urlPunctuation, "\\|")
    }
    function urlCount(value, token, total, idx) {
      total = 0
      for (idx = 1; idx <= length(value); idx++) if (substr(value, idx, 1) == token) total++
      return total
    }
    function urlTrim(value, idx, at, last) {
      for (idx = 1; idx <= urlPunctuationCount; idx++) {
        at = index(value, urlPunctuation[idx])
        if (at) value = substr(value, 1, at - 1)
      }
      while (length(value)) {
        last = substr(value, length(value), 1)
        if (index(".,;:!?", last) > 0 || (last == ")" && urlCount(value, ")") > urlCount(value, "(")) ||
            (last == "]" && urlCount(value, "]") > urlCount(value, "[")) || (last == "}" && urlCount(value, "}") > urlCount(value, "{"))) {
          value = substr(value, 1, length(value) - 1)
        } else break
      }
      return value
    }
    function urlClean(value, preserve, output, token, start, size) {
      gsub(esc "\\][^" esc sprintf("%c", 7) "]*(" sprintf("%c", 7) "|" esc "\\\\)", "", value)
      output = ""
      while (match(value, esc "\\[[0-?]*[ -/]*[@-~]")) {
        start = RSTART; size = RLENGTH; token = substr(value, start, size)
        output = output substr(value, 1, start - 1)
        if (preserve && token ~ /m$/) output = output token
        value = substr(value, start + size)
      }
      return output value
    }
    # 题干分段前临时遮蔽地址，地址里的 Enter、/、?、= 不参与选项识别。
    function urlProtect(value, output, at, size, token, marker, number, original) {
      urlProtectedCount = 0; output = ""; original = value; number = 0
      while (match(value, urlPattern)) {
        at = RSTART; size = RLENGTH; token = urlTrim(substr(value, at, size))
        do { marker = sprintf("%c", 2) "U" ++number sprintf("%c", 3) } while (index(original, marker))
        urlProtected[++urlProtectedCount] = token; urlMarkers[urlProtectedCount] = marker
        output = output substr(value, 1, at - 1) marker
        value = substr(value, at + length(token))
      }
      return output value
    }
    function urlRestore(value, idx, token, at) {
      for (idx = urlProtectedCount; idx > 0; idx--) {
        token = urlMarkers[idx]
        while ((at = index(value, token))) value = substr(value, 1, at - 1) urlProtected[idx] substr(value, at + length(token))
      }
      return value
    }
    # 保存原 SGR 的有效序列；RGB 中的零值不能误认为整体复位。
    function urlTrack(tokens, token, code, idx, total, reset, fields) {
      while (match(tokens, esc "\\[[0-9;:]*m")) {
        token = substr(tokens, RSTART, RLENGTH)
        tokens = substr(tokens, RSTART + RLENGTH)
        code = substr(token, 3, length(token) - 3); reset = (code == "")
        total = split(code, fields, ";")
        for (idx = 1; idx <= total; idx++) {
          if (fields[idx] == "0") reset = 1
          if ((fields[idx] == "38" || fields[idx] == "48" || fields[idx] == "58") && idx < total) {
            if (fields[idx + 1] == "2") idx += 4
            else if (fields[idx + 1] == "5") idx += 2
          }
        }
        if (reset) urlActive = ""
        urlActive = urlActive token
      }
    }
    # 用可见字符位置映射原 SGR，URL 内已有样式也会重新覆为绿下划线。
    function urlRender(value, output, visible, rest, key, at, size, token, idx, offset, url, inURL) {
      value = urlClean(value, color)
      if (!color) return value
      for (key in urlStyles) delete urlStyles[key]
      for (key in urlStarts) delete urlStarts[key]
      for (key in urlEnds) delete urlEnds[key]
      visible = ""; rest = value
      while (match(rest, esc "\\[[0-9;:]*m")) {
        at = RSTART; size = RLENGTH; token = substr(rest, at, size)
        visible = visible substr(rest, 1, at - 1)
        urlStyles[length(visible) + 1] = urlStyles[length(visible) + 1] token
        rest = substr(rest, at + size)
      }
      visible = visible rest; rest = visible; offset = 0
      while (match(rest, urlPattern)) {
        at = RSTART; size = RLENGTH; url = urlTrim(substr(rest, at, size))
        urlStarts[offset + at] = 1; urlEnds[offset + at + length(url) - 1] = 1
        offset += at + length(url) - 1; rest = substr(visible, offset + 1)
      }
      output = ""; inURL = 0
      for (idx = 1; idx <= length(visible) + 1; idx++) {
        if (idx in urlStyles) {
          token = urlStyles[idx]; output = output token; urlTrack(token)
          if (inURL) output = output esc "[32;4m"
        }
        if (idx > length(visible)) break
        if (idx in urlStarts) { output = output esc "[32;4m"; inURL = 1 }
        output = output substr(visible, idx, 1)
        if (idx in urlEnds) { output = output esc "[0m" urlActive; inURL = 0 }
      }
      return output
    }
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
    function segment(value, inherited, is_question, start, kind, prefix, body, red, green, connector, left, right, splitAt) {
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
          return segment(left, 0, is_question) connector segment(right, 31, 0)
        }
        if (red && green && red < green && match(value, /或[[:space:]]*(直接|仅|只需|只|按下|按)?(回车|回車)/)) {
          splitAt = RSTART
          return segment(substr(value, 1, splitAt - 1), 31, is_question) "或" segment(substr(value, splitAt + length("或")), 0, 0)
        }
        if (red) {
          kind = 31
          start = red
        } else if (green) {
          kind = 32
          start = green
        }
      }
      if (!color) return value
      if (!kind) return is_question && value !~ /^[[:space:]]*$/ ? esc "[1;36m" value esc "[0m" : value
      prefix = substr(value, 1, start - 1)
      body = substr(value, start)
      if (is_question && prefix !~ /^[[:space:]]*$/) prefix = esc "[1;36m" prefix esc "[0m"
      return prefix esc "[1;" kind "m" body esc "[0m"
    }
    function render(value, output, part, boundary, inherited, kind, consumed, depth, original, question_body) {
      original = value
      value = urlProtect(urlClean(value, 0))
      if (color && keep && !greenPosition(value) && value !~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) return urlRender(original)
      output = ""
      inherited = 0
      depth = 0
      question_body = question
      while (match(value, /[；;\/|，,、？?：:=＝（）()\[\]【】]/)) {
        part = substr(value, 1, RSTART - 1)
        boundary = substr(value, RSTART, RLENGTH)
        consumed = RSTART + RLENGTH
        output = output segment(part, inherited, question_body) boundary
        if (inherited || greenPosition(part) || part ~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) question_body = 0
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
      return urlRender(urlRestore(output segment(value, inherited, question_body) (question && color ? esc "[0m" : "")))
    }
    BEGIN { esc = sprintf("%c", 27); first = 1; urlInit() }
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
  printf "%s" "$1" | jobs_prompt_format "$jobs_prompt_color" 0 0 1
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
                IFS= read -r "value?$(jobs_prompt_render '输入或拖入迁移目录 / 原始缓存目录 / 包含缓存的父目录：')" || return 130
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
# 终端冲突菜单使用健康 fzf；缺失按已确认流程补齐，取消不写入。
# JOBS_FZF_REQUIRED_BEGIN
# Homebrew 条件准备，来源为本轮现行 Jobs 自维护实现。
jobs_brew_note() {
  jobs_prompt_output print -u2 -r -- "ℹ $*"
  if [[ "${_JOBS_ENV_LOG_READY:-0}" == 1 && -n "${LOG_FILE:-}" ]]; then
    print -r -- "ℹ $*" >> "$LOG_FILE"
  fi
  return 0
}
# 验证候选能够执行；共享安装只读不代表未安装。
jobs_brew_candidate_ok() {
  local candidate="$1" prefix
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  HOMEBREW_NO_AUTO_UPDATE=1 "$candidate" --version >/dev/null 2>&1 || return 1
  prefix="$("$candidate" --prefix 2>/dev/null)" || return 1
  [[ "$prefix" == /* && -d "$prefix" ]]
}
# 发现既有健康安装，不以目录可写性决定是否重新安装。
jobs_brew_find() {
  local candidate
  local -a candidates
  candidates=("${JOBS_HOMEBREW_BIN:-}" "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew
    "${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}/bin/brew" "$HOME/.homebrew/bin/brew")
  for candidate in "${candidates[@]}"; do
    if jobs_brew_candidate_ok "$candidate"; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}
# 计算官方系统目录；实际支持范围和授权交由官方安装器处理。
jobs_brew_system_prefix() {
  case "$(/usr/bin/uname -m)" in
    arm64) print -r -- /opt/homebrew ;;
    *) print -r -- /usr/local ;;
  esac
}
# 缺失时强提示选择安装路径；YES 只表示选择系统目录，不验证密码或权限。
jobs_brew_choose_installation() {
  local answer="" system_prefix="$(jobs_brew_system_prefix)"
  if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]]; then
    jobs_brew_note "缺少 Homebrew，需要人工选择安装路径；请在可交互终端重新运行，未执行安装。"
    return 1
  fi
  print -u2 -r -- "⚠ Homebrew 尚未就绪，必须先选择安装路径："
  print -u2 -r -- "1、输入精确大写 YES：选择系统标准目录 $system_prefix（Apple Silicon：/opt/homebrew；Intel：/usr/local）。"
  print -u2 -r -- "   这表示你准备向系统目录安装；官方安装器可能随后要求管理员密码，并自行验证权限。"
  jobs_prompt_output print -u2 -r -- "2、其它输入或直接回车：选择用户目录 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}，不使用 sudo；有管理员权限也可选此路径。"
  print -u2 -r -- "本步骤只选择路径，不收集或验证密码；选定路径失败就停止，不自动切换。按 Ctrl+C 取消整个任务。"
  print -u2 -n -r -- "$(jobs_prompt_render "➤ 安装路径选择：")"
  if ! IFS= read -r answer; then
    jobs_brew_note "输入已取消或结束，停止安装。"
    return 1
  fi
  if [[ "$answer" == YES ]]; then
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=system
  else
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=user
  fi
}
# 持续获取临时网络失败；只尝试已声明官方地址，确定错误和取消立即停止。
jobs_brew_download_file() {
  local destination="$1" description="$2" download_url attempt download_result=1 http_code
  local retry_round=0 retry_delay=1 round_has_retryable=0
  local -a request_headers download_urls
  local -A blocked_urls
  shift 2
  download_urls=("$@")
  (( ${#download_urls} > 0 )) || { jobs_brew_note '没有已声明的官方获取地址。'; return 2; }
  while true; do
    (( retry_round += 1 ))
    round_has_retryable=0
    for download_url in "${download_urls[@]}"; do
      [[ -z "${blocked_urls[$download_url]:-}" ]] || continue
      request_headers=()
      if [[ "$download_url" == https://api.github.com/repos/Homebrew/install/contents/install.sh\?ref=HEAD ]]; then
        request_headers=(-H 'Accept: application/vnd.github.raw+json')
      fi
      for attempt in 1 2 3; do
        jobs_brew_note "下载${description}（第 $retry_round 轮，第 $attempt 次）：$download_url"
        download_result=0
        http_code="$(curl -q -fsSL --proto '=https' --proto-redir '=https' \
          --connect-timeout 10 --max-time 30 "${request_headers[@]}" \
          --write-out '%{http_code}' "$download_url" -o "$destination" \
          2> >(tee -a "${LOG_FILE:-/dev/null}" >&2))" || download_result=$?
        if (( download_result == 0 )); then
          return 0
        fi
        rm -f -- "$destination" || return 1
        jobs_brew_note "${description}下载失败：curl 退出码 $download_result，HTTP ${http_code:-未知}。"
        case "$download_result" in
          129|130|143) return "$download_result" ;;
          5|6|7|18|28|35|52|55|56) ;;
          22)
            if [[ "$http_code" != 408 && "$http_code" != 429 && "$http_code" != 5[0-9][0-9] ]]; then
              blocked_urls[$download_url]=1
              break
            fi
            ;;
          *) blocked_urls[$download_url]=1; break ;;
        esac
        if (( attempt < 3 )); then
          jobs_brew_note '临时连接失败，1 秒后重试同一官方地址；Ctrl+C 可取消。'
          sleep 1 || return $?
        fi
      done
      if [[ -z "${blocked_urls[$download_url]:-}" ]]; then
        round_has_retryable=1
      fi
      jobs_brew_note '当前地址尚未取得可用响应；如有下一已声明官方地址，将按原顺序尝试，安装目录不变。'
    done
    if (( round_has_retryable == 0 )); then
      jobs_brew_note "获取${description}遇到确定错误，停止；未执行安装。日志：${LOG_FILE:-终端输出}。"
      return "$download_result"
    fi
    jobs_brew_note "官方来源暂时不可用，${retry_delay} 秒后继续下一轮；不设总次数或总时长上限，按 Ctrl+C 取消。"
    sleep "$retry_delay" || return $?
    if (( retry_delay < 30 )); then
      retry_delay=$(( retry_delay * 2 ))
      (( retry_delay <= 30 )) || retry_delay=30
    fi
  done
}
# 校验官方安装脚本后仅执行一次，下载失败与安装失败分别报告。
jobs_brew_install_system() {
  local installer system_prefix="$(jobs_brew_system_prefix)" installer_result=0
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方安装器。"; return 1; }
  installer="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-install.XXXXXX")" || return 1
  if jobs_brew_download_file "$installer" 'Homebrew 官方安装器' \
      https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh \
      'https://api.github.com/repos/Homebrew/install/contents/install.sh?ref=HEAD'; then
    if [[ ! -s "$installer" || "$(head -n 1 "$installer")" != '#!/bin/bash' ]] || ! /bin/bash -n "$installer"; then
      rm -f -- "$installer"
      jobs_brew_note '官方安装器响应为空或内容校验失败（可能是 HTML / JSON 错误页）；未执行安装。'
      return 1
    fi
  else
    installer_result=$?
    rm -f -- "$installer"
    jobs_brew_note "系统目录安装器下载失败（curl 退出码 $installer_result）；尚未执行安装，不自动切换安装路径。"
    return "$installer_result"
  fi
  /bin/bash "$installer" || installer_result=$?
  rm -- "$installer"
  if (( installer_result != 0 )); then
    jobs_brew_note "系统目录安装失败（退出码 $installer_result）；停止，不自动切换安装路径。"
    return "$installer_result"
  fi
  typeset -g JOBS_HOMEBREW_BIN="$system_prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "官方安装器结束后未找到健康 Homebrew：$JOBS_HOMEBREW_BIN"; return 1; }
}
# 只终止本次获取或等待创建的子进程树，不碰其它 SDK 写者。
jobs_brew_stop_acquisition_tree() {
  local root="$1" child=""
  for child in $(/usr/bin/pgrep -P "$root" 2>/dev/null); do
    jobs_brew_stop_acquisition_tree "$child"
  done
  /bin/kill -TERM "$root" 2>/dev/null || true
  /bin/kill -KILL "$root" 2>/dev/null || true
}
# 在本轮私有暂存目录持续获取固定官方 tag，复用已收对象；不重放安装。
jobs_brew_fetch_release() {
  setopt LOCAL_OPTIONS LOCAL_TRAPS NO_ERREXIT
  local git_bin="$1" release_tag="$2" stage="$3" target="${3}/brew"
  local attempt_log="${3}/git-fetch-attempt.log" history="${3}/git-fetch-history.log"
  local attempt=1 result=0 delay=1 task_pid="" interrupted=0 failure=""
  [[ "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' && "$stage" == /* &&
     "${stage:t}" == .jobs-homebrew.* && -d "$stage" && ! -L "$stage" && ! -e "$target" && ! -L "$target" ]] || {
    jobs_brew_note 'Homebrew 获取版本或私有暂存路径无效，未执行 Git 获取。'
    return 2
  }
  "$git_bin" init --quiet "$target" || { result=$?; jobs_brew_note "Homebrew 暂存仓初始化失败（$result）：$target"; return "$result"; }
  "$git_bin" -C "$target" remote add origin https://github.com/Homebrew/brew.git || return $?
  trap 'interrupted=130; [[ -z "$task_pid" ]] || jobs_brew_stop_acquisition_tree "$task_pid"' INT
  trap 'interrupted=143; [[ -z "$task_pid" ]] || jobs_brew_stop_acquisition_tree "$task_pid"' TERM
  trap 'interrupted=129; [[ -z "$task_pid" ]] || jobs_brew_stop_acquisition_tree "$task_pid"' HUP
  while true; do
    jobs_brew_note "获取 Homebrew 官方版本 $release_tag（第 $attempt 次）：https://github.com/Homebrew/brew.git → $target；失败自动重试，Ctrl+C 取消。"
    : > "$attempt_log" || return 1
    print -r -- "━━ Homebrew $release_tag：第 $attempt 次 ━━" >> "$history" || return 1
    (
      local -a acquisition_statuses
      LC_ALL=C GIT_TERMINAL_PROMPT=0 "$git_bin" -C "$target" -c color.ui=false \
        -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 fetch --progress --depth 1 origin "refs/tags/$release_tag" 2>&1 |
        jobs_prompt_tee "$history" | jobs_prompt_tee "${LOG_FILE:-/dev/null}" | jobs_prompt_tee "$attempt_log" >&2
      acquisition_statuses=("${pipestatus[@]}")
      (( acquisition_statuses[2] == 0 && acquisition_statuses[3] == 0 && acquisition_statuses[4] == 0 )) || exit 74
      exit "${acquisition_statuses[1]}"
    ) <&0 &
    task_pid=$!
    result=0
    wait "$task_pid" || result=$?
    task_pid=""
    (( interrupted == 0 )) || return "$interrupted"
    jobs_brew_note "Homebrew $release_tag 获取第 $attempt 次退出码：$result。"
    if (( result == 0 )); then
      "$git_bin" -C "$target" checkout --quiet --detach FETCH_HEAD || return $?
      return 0
    fi
    case "$result" in
      74) jobs_brew_note "Homebrew 获取日志写入失败，停止；请检查磁盘空间、路径和权限。"; return 74 ;;
      129|130|131|137|143|126|127) return "$result" ;;
    esac
    failure="$(/usr/bin/tail -c 65536 "$attempt_log")" || return 1
    if print -r -- "$failure" | /usr/bin/grep -Eqi \
      'Permission denied|Operation not permitted|No space left on device|Read-only file system|File exists|already exists and is not an empty directory|Bad CPU type|Exec format error|unknown option|unrecognized option|invalid argument|couldn.t find remote ref|Remote branch .* not found|repository .* not found|Authentication failed|could not read Username|terminal prompts disabled|HTTP[^[:cntrl:]]*(401|403|404)|returned error: (401|403|404)|SSL certificate problem|certificate verify failed|unable to get local issuer certificate'; then
      jobs_brew_note "Homebrew 官方版本获取遇到本地、认证、证书或版本确定错误（$result），已停止；请核对日志：${LOG_FILE:-$history}。"
      return "$result"
    fi
    jobs_brew_note "Homebrew 网络获取尚未完成，保留本轮已收对象，${delay} 秒后继续；不设总次数或总时长上限，Ctrl+C 取消。"
    sleep "$delay" &
    task_pid=$!
    wait "$task_pid" || { result=$?; (( interrupted == 0 )) || return "$interrupted"; return "$result"; }
    task_pid=""
    (( interrupted == 0 )) || return "$interrupted"
    (( attempt += 1 ))
    (( delay >= 30 )) || delay=$(( delay * 2 ))
    (( delay <= 30 )) || delay=30
  done
}

# 获取固定官方稳定版本到用户目录；不覆盖非空目录，不调用 sudo。
jobs_brew_install_user() {
  local prefix="${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}" stage release_tag git_bin release_result=0
  [[ "$prefix" == /* && "$prefix" != / && "$prefix" != *[[:space:]:]* ]] || {
    jobs_brew_note "Homebrew 用户前缀须为不含空白或冒号的绝对目录：$prefix"
    return 1
  }
  if [[ -L "$prefix" || ( -e "$prefix" && ! -d "$prefix" ) || ( -d "$prefix" && -n "$(ls -A "$prefix" 2>/dev/null)" ) ]]; then
    jobs_brew_note "用户安装目标非空或不是普通目录，不覆盖：$prefix"
    return 1
  fi
  local git_health=1 locate_result=0 git_candidate="" selected_developer="" clt_result=0 clt_diagnostic=""
  git_bin="$(command -v git 2>/dev/null)"
  # /usr/bin/git 可能只是CLT占位器；先查询真实工具，避免健康检查自行弹出安装窗口。
  if [[ "$git_bin" == /usr/bin/git || -z "$git_bin" ]]; then
    git_bin="$(/usr/bin/xcrun --find git 2>/dev/null)" || locate_result=$?
    case "$locate_result" in 129|130|131|137|143) return "$locate_result" ;; esac
  fi
  if [[ -n "$git_bin" && -x "$git_bin" ]]; then
    git_health=0;"$git_bin" --version >/dev/null 2>&1 || git_health=$?
    case "$git_health" in 129|130|131|137|143) return "$git_health" ;; esac
  fi
  if (( git_health != 0 )); then
    [[ -z "${DEVELOPER_DIR:-}" ]] || { jobs_brew_note '显式DEVELOPER_DIR没有健康Git，保留用户开发目录，未自动改全局选择。'; return 1; }
    locate_result=0
    selected_developer="$(/usr/bin/xcode-select -p 2>/dev/null)" || locate_result=$?
    case "$locate_result" in 129|130|131|137|143) return "$locate_result" ;; esac
    if [[ -n "$selected_developer" && -d "$selected_developer" ]]; then
      jobs_brew_note "既有开发目录未提供健康Git：$selected_developer；可能是许可、版本或本地文件阻塞，未反复安装或改全局xcode-select。"
      return 1
    fi
    if [[ "${DRY_RUN:-0}" == 1 || "${CHECK_ONLY:-0}" == 1 || ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]] ||
       env | LC_ALL=C /usr/bin/grep -qiE '^(SOURCETREE|SOURCE_TREE)'; then
      jobs_brew_note '用户目录Homebrew需要健康Git；当前为只读或非交互入口，未打开CLT安装窗口或写安装目标。'
      return 1
    fi
    jobs_brew_note '当前已选用户目录Homebrew安装需要Apple Command Line Tools的Git；只打开一次原生安装窗口，许可由本人处理，当前流程持续复检，Ctrl+C停止。' || return $?
    clt_diagnostic="$(/usr/bin/xcode-select --install 2>&1)" || clt_result=$?
    jobs_brew_note "$clt_diagnostic" || return $?
    if (( clt_result != 0 )) && [[ "$clt_diagnostic" != *'already being installed'* && "$clt_diagnostic" != *'正在安装'* ]]; then return "$clt_result"; fi
    while true; do
      locate_result=0
      git_candidate="$(/usr/bin/xcrun --find git 2>/dev/null)" || locate_result=$?
      case "$locate_result" in 129|130|131|137|143) return "$locate_result" ;; esac
      if [[ -n "$git_candidate" && -x "$git_candidate" ]]; then
        git_health=0;"$git_candidate" --version >/dev/null 2>&1 || git_health=$?
        case "$git_health" in 129|130|131|137|143) return "$git_health" ;; esac
        if (( git_health == 0 )); then git_bin="$git_candidate";break;fi
      fi
      jobs_brew_note '等待Apple CLT提供健康Git；不会重复打开窗口，Ctrl+C停止。' || return $?
      /bin/sleep 3 || return $?
    done
  fi
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方稳定版本。"; return 1; }
  export HOMEBREW_NO_SUDO=1
  mkdir -p "${prefix:h}" || return 1
  stage="$(mktemp -d "${prefix:h}/.jobs-homebrew.XXXXXX")" || return 1
  if jobs_brew_download_file "$stage/release.json" 'Homebrew 官方稳定版本' \
      https://api.github.com/repos/Homebrew/brew/releases/latest; then
    release_result=0
  else
    release_result=$?
    rm -r -- "$stage"
    jobs_brew_note "获取官方稳定版本已停止（退出码 $release_result），未执行安装。"
    return "$release_result"
  fi
  release_tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$stage/release.json" | head -n 1)"
  if [[ ! "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    rm -r -- "$stage"
    jobs_brew_note '官方版本响应无有效 tag，停止；不重试版本解析或执行安装。'
    return 1
  fi
  if jobs_brew_fetch_release "$git_bin" "$release_tag" "$stage"; then
    release_result=0
  else
    release_result=$?
    rm -r -- "$stage"
    jobs_brew_note "Homebrew 官方版本获取已停止（退出码 $release_result），未执行安装。"
    return "$release_result"
  fi
  if ! "$git_bin" -C "$stage/brew" checkout -b stable ||
     ! "$git_bin" -C "$stage/brew" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' ||
     ! mkdir -p "$stage/brew/Cellar" "$stage/brew/Caskroom" "$stage/brew/etc" "$stage/brew/var"; then
    rm -r -- "$stage"
    jobs_brew_note "Homebrew 用户目录初始化失败，停止安装。"
    return 1
  fi
  # 空目录也只在下载成功后移除，避免提前改动用户的目标目录。
  if [[ -d "$prefix" ]] && ! rmdir -- "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  if ! mv "$stage/brew" "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  rm -r -- "$stage"
  typeset -g JOBS_HOMEBREW_BIN="$prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "用户目录安装后复检失败：$prefix"; return 1; }
}
# 只更新本模块的 shellenv 配置块，并保留配置文件的符号链接和权限。
# 激活当前进程并验证 Ruby 命令层；只有新安装才持久化 shellenv。
jobs_brew_activate() {
  local brew_env
  brew_env="$("$JOBS_HOMEBREW_BIN" shellenv)" || return 1
  eval "$brew_env" || return 1
  typeset -g JOBS_HOMEBREW_PREFIX="$("$JOBS_HOMEBREW_BIN" --prefix)"
  export PATH="$JOBS_HOMEBREW_PREFIX/bin:$JOBS_HOMEBREW_PREFIX/sbin:$PATH"
  rehash
  HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" config >/dev/null || { jobs_brew_note "Homebrew 命令层复检失败，停止后续业务。"; return 1; }
  if [[ "${1:-}" == installed ]]; then
    if [[ "${JOBS_HOMEBREW_INSTALL_MODE:-}" == user && -z "${HOMEBREW_CASK_OPTS:-}" ]]; then
      export HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications"
    fi
    # 只刷新本次进程，不向用户 Shell 启动文件写入持久配置。
    :
  fi
}
# 用户取消保持信号退出码，其它安装失败沿用原入口失败状态。
jobs_brew_stop_failed_install() {
  case "$1" in
    129|130|143) exit "$1" ;;
    *) exit 1 ;;
  esac
}

# 编排既有健康复用和已选安装路径，失败保留原生取消状态。
jobs_brew_install_or_exit() {
  local installed=""
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    jobs_brew_note "演练：Homebrew 系统路径 $(jobs_brew_system_prefix)；用户路径 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}；未询问或执行安装。"
    return 0
  fi
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    jobs_brew_choose_installation || exit 1
    case "$JOBS_HOMEBREW_INSTALL_MODE" in
      system) jobs_brew_install_system || jobs_brew_stop_failed_install $? ;;
      user) jobs_brew_install_user || jobs_brew_stop_failed_install $? ;;
      *) jobs_brew_note "安装路径选择无效，停止。"; exit 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || exit 1
}

# 将依赖诊断写到人类展示流，避免混入选择结果。
jobs_fzf_note() {
  if (( ${+functions[jobs_prompt_output]} )); then
    jobs_prompt_output print -u2 -r -- "$*"
  else
    print -u2 -r -- "$*"
  fi
  if [[ -n "${LOG_FILE:-}" ]]; then print -r -- "$*" >> "$LOG_FILE"; fi
}
# 只给健康探针设置单次上限；下载获取仍由持续重试流程负责。
jobs_fzf_bounded_probe() {
  local child=0 watchdog=0 result=0
  "$@" <&0 &
  child=$!
  ( /bin/sleep 10; jobs_brew_stop_acquisition_tree "$child" ) >/dev/null 2>&1 &
  watchdog=$!
  wait "$child" || result=$?
  jobs_brew_stop_acquisition_tree "$watchdog"
  wait "$watchdog" 2>/dev/null || :
  return "$result"
}
# 验证可执行路径、版本和本轮菜单实际使用的选项；不打开选择面板。
jobs_fzf_probe() {
  local candidate="$1" probe='__JOBS_FZF_HEALTH__' output="" result=0
  [[ -n "$candidate" && -x "$candidate" && ! -d "$candidate" ]] || return 1
  jobs_fzf_bounded_probe /usr/bin/env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_OPTS_FILE -u FZF_DEFAULT_COMMAND "$candidate" --version >/dev/null 2>&1 || return 1
  output="$(print -r -- "P"$'\t'"$probe" | jobs_fzf_bounded_probe /usr/bin/env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_OPTS_FILE -u FZF_DEFAULT_COMMAND \
    "$candidate" --filter="$probe" --delimiter=$'\t' --with-nth=2.. --no-multi --sync --print-query --layout=reverse --height=60% --border \
      --bind='up:up,down:down,tab:down,shift-tab:up' --expect=left --header='↑/↓ 选择；回车确认；← 返回上一层；Esc / Ctrl+C 取消')" || result=$?
  (( result == 0 )) && [[ "${output##*$'\n'}" == P$'\t'"$probe" ]]
}
# 从当前进程和常见安装位置复用真正健康的 fzf，不重复安装。
jobs_fzf_find() {
  local candidate=""
  local -a candidates=("${JOBS_FZF_BIN:-}" "${commands[fzf]:-}" /opt/homebrew/bin/fzf /usr/local/bin/fzf "$HOME/.local/bin/fzf")
  for candidate in "${candidates[@]}"; do
    if jobs_fzf_probe "$candidate"; then JOBS_FZF_BIN="${candidate:A}"; return 0; fi
  done
  return 1
}
# 只读检查不修复；已确认业务仅在缺失或损坏时补齐选择器并刷新当前进程。
jobs_fzf_ensure() {
  local mode="${1:-required}" brew="" action=install result=0 attempt=0 delay=1 output_log="" prefix="" offset=0 log_result=0
  local -a command_status
  if [[ "$mode" != check ]] && { [[ ! -t 0 || ! -t 2 ]] || [[ "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]]; }; then
    print -u2 -r -- '✖ 选择器需要可交互终端；未安装依赖或执行后续业务。'
    return 1
  fi
  if jobs_fzf_find; then
    if [[ "$mode" != check ]]; then export PATH="${JOBS_FZF_BIN:h}:$PATH"; rehash; fi
    return 0
  fi
  [[ "$mode" != check ]] || { print -u2 -r -- '✖ fzf 路径、版本或菜单选项检查失败；只读模式未安装或修复。'; return 1; }
  jobs_fzf_note '➤ 本次键盘选择需要健康 fzf；仅在缺失或损坏时通过 Homebrew 准备，Ctrl+C 可取消。' || return $?
  jobs_brew_install_or_exit >&2 || return $?
  brew="${JOBS_HOMEBREW_BIN:-}"
  [[ -n "$brew" ]] || { jobs_fzf_note '✖ Homebrew 准备未返回可执行路径。'; return 1; }
  prefix="$("$brew" --prefix)" || return $?
  export PATH="$prefix/bin:$prefix/sbin:$PATH"
  rehash
  output_log="${LOG_FILE:-${TMPDIR:-/tmp}/JobsFzf.$$.log}"
  HOMEBREW_NO_AUTO_UPDATE=1 "$brew" list --versions fzf >/dev/null 2>&1 && action=reinstall
  while true; do
    (( attempt += 1 ))
    jobs_fzf_note "➤ 必需依赖 fzf｜来源：https://formulae.brew.sh/formula/fzf｜目标：$prefix｜$action，第 $attempt 次；网络失败持续重试，Ctrl+C 结束。" || return $?
    offset=0
    [[ ! -f "$output_log" ]] || offset="$(/usr/bin/wc -c < "$output_log")"
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 "$brew" "$action" fzf 2>&1 | jobs_prompt_tee "$output_log" >&2
    command_status=("${pipestatus[@]}")
    result=${command_status[1]}
    log_result=${command_status[2]}
    if (( log_result != 0 )); then print -u2 -r -- "✖ fzf 输出记录失败，退出码 $log_result；未继续重试或报告就绪。"; return "$log_result"; fi
    if (( result == 0 )); then
      rehash
      if jobs_fzf_find; then jobs_fzf_note "✔ fzf 已通过版本与菜单选项复检：$JOBS_FZF_BIN"; return 0; fi
      jobs_fzf_note '✖ 安装器返回成功，但 fzf 仍未通过实际选项复检；保留日志并停止，未进入业务。'
      return 1
    fi
    case "$result" in 129|130|137|143) return "$result" ;; esac
    if /usr/bin/tail -c +$((offset + 1)) "$output_log" | /usr/bin/tail -c 65536 | /usr/bin/grep -Eqi 'Permission denied|Operation not permitted|No space left|No available formula|No formulae found|File exists|unsupported|not supported|license.*(not accepted|rejected)|authentication failed|certificate.*(invalid|verify failed)'; then
      jobs_fzf_note "✖ 必需依赖遇到确定的本地、版本、认证或许可阻塞，退出码 $result；日志：$output_log"
      return "$result"
    fi
    jobs_fzf_note "⚠ fzf 获取失败，退出码 $result；${delay} 秒后继续同一流程。日志：$output_log" || return $?
    /bin/sleep "$delay" || return $?
    (( delay < 30 )) && delay=$(( delay * 2 > 30 ? 30 : delay * 2 ))
  done
}
# 单选默认取消，操作行与业务数据分开；返回、取消和失败分别传播。
jobs_fzf_pick() {
  local title="$1" level="${2:-root}" selected="" result=0 record="" key="" choice="" index=0 header=""
  shift 2
  local -a choices=("$@") menu=($'C\t× 取消本轮')
  JOBS_FZF_SELECTED=""
  JOBS_FZF_QUERY="${JOBS_FZF_INITIAL_QUERY:-}"
  (( ${#choices[@]} )) || return 1
  for choice in "${choices[@]}"; do
    [[ "$choice" != *$'\n'* && "$choice" != *$'\r'* ]] || { jobs_fzf_note '✖ 候选包含换行，停止以避免错误映射。'; return 1; }
  done
  local force=0
  if [[ "$level" == confirm-* ]]; then force=1; level="${level#confirm-}"; JOBS_FZF_QUERY=""; fi
  if [[ "$level" == force-* ]]; then force=1; level="${level#force-}"; fi
  if (( ${#choices[@]} == 1 && ! force )); then JOBS_FZF_SELECTED="${choices[1]}"; return 0; fi
  jobs_fzf_ensure >&2 || return $?
  if [[ "$level" == root ]]; then
    header='↑/↓ 或 Tab 选择；回车确认；← / Esc / Ctrl+C 取消'
  else
    menu+=($'B\t← 返回上一层')
    header='↑/↓ 或 Tab 选择；回车确认；← 返回上一层；Esc / Ctrl+C 取消'
  fi
  for choice in "${choices[@]}"; do
    [[ "$choice" != *$'\n'* && "$choice" != *$'\r'* ]] || { jobs_fzf_note '✖ 候选包含换行，停止以避免错误映射。'; return 1; }
    (( index += 1 ))
    menu+=("D${index}"$'\t'"$choice")
  done
  selected="$(print -rl -- "${menu[@]}" | /usr/bin/env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_OPTS_FILE -u FZF_DEFAULT_COMMAND \
    "$JOBS_FZF_BIN" --no-multi --sync --print-query --query="$JOBS_FZF_QUERY" --layout=reverse --height=60% --border --delimiter=$'\t' --with-nth=2.. --prompt="$title > " \
      --bind='up:up,down:down,tab:down,shift-tab:up' --expect=left --header="$header")" || result=$?
  if [[ "$selected" == *$'\n'* ]]; then
    JOBS_FZF_QUERY="${selected%%$'\n'*}"
    selected="${selected#*$'\n'}"
    key="${selected%%$'\n'*}"
    record="${selected#*$'\n'}"
  fi
  if [[ "$key" == left ]]; then
    [[ "$level" == root ]] && return 130 || return 20
  fi
  (( result == 0 )) || { (( result == 1 || result == 130 )) && return 130; return "$result"; }
  key="${record%%$'\t'*}"
  [[ -n "$record" && "$key" != C ]] || return 130
  [[ "$key" != B ]] || return 20
  [[ "$key" == D<-> ]] || { jobs_fzf_note '✖ 选择器返回无效操作标记。'; return 1; }
  index="${key#D}"
  (( index >= 1 && index <= ${#choices[@]} )) && [[ "$record" == "D${index}"$'\t'"${choices[index]}" ]] || {
    jobs_fzf_note '✖ 选择器返回了不属于当前清单的数据。'; return 1
  }
  JOBS_FZF_SELECTED="${choices[index]}"
  return 0
}
# 按真实候选集记住本层查询；返回保留，候选改变后清空，确认菜单不复用查询。
jobs_fzf_menu() {
  local title="$1" level="${2:-root}" result=0 cache_key="" signature=""
  shift 2
  local -a choices=("$@")
  typeset -gA JOBS_FZF_SAVED_QUERIES JOBS_FZF_SAVED_ROWS
  cache_key="$level"$'\x1f'"$title"
  signature="${(F)choices}"
  local JOBS_FZF_INITIAL_QUERY=""
  if [[ "${JOBS_FZF_SAVED_ROWS[$cache_key]-}" == "$signature" ]]; then
    JOBS_FZF_INITIAL_QUERY="${JOBS_FZF_SAVED_QUERIES[$cache_key]-}"
  fi
  jobs_fzf_pick "$title" "force-$level" "${choices[@]}" || result=$?
  JOBS_FZF_SAVED_ROWS[$cache_key]="$signature"
  JOBS_FZF_SAVED_QUERIES[$cache_key]="$JOBS_FZF_QUERY"
  return "$result"
}
# 为单层旧调用保留纯数据 stdout；多层调用直接使用 pick 的结果和查询字段。
jobs_fzf_choose() {
  jobs_fzf_pick "$@" || return $?
  print -r -- "$JOBS_FZF_SELECTED"
}
# JOBS_FZF_REQUIRED_END

fm_choose_conflict_policy() {
    local result=0
    FM_CONFLICT_POLICY=""
    [[ "${JOBS_FLUTTER_MIGRATION_FZF:-}" != 0 ]] || { fm_log '✖ 本次禁用了交互选择，未导入文件。'; return 1; }
    [[ -z "${FM_FZF_BIN:-}" ]] || JOBS_FZF_BIN="$FM_FZF_BIN"
    jobs_fzf_menu '冲突处理（仅影响已列出的文件）' root \
        $'source\t使用导入源的数据（推荐，覆盖冲突文件）' $'existing\t保留当前环境的数据（跳过冲突文件）' || result=$?
    (( result == 0 )) || return "$result"
    FM_CONFLICT_POLICY="${JOBS_FZF_SELECTED%%$'\t'*}"
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
FM_ENTRY_CONFIRMED=0
# 首屏自述和确认只解析展示参数，取消保持零写入。
show_script_intro_and_wait() {
    local answer=""
    FM_ENTRY_CONFIRMED=0
    fm_intro
    fm_parse "$@" || return $?
    if (( ! FM_CONFIRMED )); then
        IFS= read -r "answer?$(jobs_prompt_render '已了解用途与影响，直接回车继续；非空取消：')" || return 0
        [[ -z "$answer" ]] || return 0
    fi
    FM_ENTRY_CONFIRMED=1
}
# 首屏失败或取消不进入迁移，执行阶段完整保留原有结果传播。
fm_execute_requested_migration() {
    local intro_code="$1" result=0
    (( intro_code == 0 )) || return "$intro_code"
    (( FM_ENTRY_CONFIRMED )) || return 0
    fm_initialize && fm_resolve_dart || return $?
    if [[ "$FM_MODE" == export && "$FM_SCOPE_SELECTED" == 0 ]]; then fm_choose_scope || return $?; fi
    fm_read_directory || return $?
    if [[ "$FM_MODE" == export ]]; then fm_export; else fm_import; fi
    result=$?
    (( result != 0 )) || fm_log "✔ 完成；日志：$FM_LOG"
    return "$result"
}
# 先取得本轮入口确认，再运行已选导入或导出。
main() {
    show_script_intro_and_wait "$@" # 首屏说明范围，保留参数确认和非空取消语义。
    fm_execute_requested_migration "$?" # 仅已确认入口执行迁移，并保留真实失败状态。
}

if [[ "$ZSH_EVAL_CONTEXT" == toplevel ]]; then
    main "$@"
fi
