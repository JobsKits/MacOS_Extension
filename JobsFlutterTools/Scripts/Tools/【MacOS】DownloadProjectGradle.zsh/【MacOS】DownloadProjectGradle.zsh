#!/bin/zsh
# 脚本自述：
# - 脚本名称：DownloadProjectGradle.zsh。
# - 核心用途：按项目固定 Wrapper 版本及所选 Java 校验、下载 Gradle 并预热构建插件。
# - 影响范围：用户 Gradle 缓存、普通构建配置缓存与项目脚本执行；不改 Wrapper、AGP 或系统代理。
# - 运行提示：自述回车后 fzf 选官方 / 镜像，Ctrl+C / Esc 取消；--check 只读不联网；source 只定义函数。

# JOBS_SOURCE_LAYOUT_V1：源码同名包装与发布旧平铺目录分别解析，不改变运行时资源名。
# 保留实际文件路径；只有源码同名包装才向上还原原资源目录。
jobs_layout_directory() {
  local file="${1:A}" directory="${1:A:h}" levels="${2:-0}"
  [[ "${directory:t}" != "${file:t}" ]] || directory="${directory:h}"
  while (( levels > 0 )); do
    directory="${directory:h}"
    (( levels -= 1 ))
  done
  print -r -- "$directory"
}
# 优先兼容已发布的平铺文件，再尝试源码中的同名包装；不跟随链接文件。
jobs_layout_file() {
  local file="$1" directory="${1:h}" name="${1:t}" candidate="" prefixed=""
  if [[ -f "$file" && ! -L "$file" ]]; then
    print -r -- "$file"
    return 0
  fi
  case "$name" in
    EnableFinderExtension.zsh) prefixed="【MacOS@Xcode】$name" ;;
    *.zsh|*.command|*.sh) [[ "$name" == '【MacOS'* ]] && prefixed="$name" || prefixed="【MacOS】$name" ;;
    *.jxa) prefixed="$name" ;;
    *) print -r -- "$file"; return 0 ;;
  esac
  [[ "${directory:t}" != "$name" ]] || directory="${directory:h}"
  candidate="$directory/$prefixed/$prefixed"
  if [[ ! -L "$directory/$prefixed" && -f "$candidate" && ! -L "$candidate" ]]; then
    print -r -- "$candidate"
  else
    print -r -- "$file"
  fi
}

# JOBS_SDK_RETRY_BEGIN
# 只处理本轮子树，避免超时或取消后残留下载进程占用 SDK 锁。
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

jobs_sdk_stop_tree() {
    local root="$1" child=""
    for child in $(/usr/bin/pgrep -P "$root" 2>/dev/null); do
        jobs_sdk_stop_tree "$child"
    done
    /bin/kill -TERM "$root" 2>/dev/null || true
    /bin/kill -KILL "$root" 2>/dev/null || true
}
# 状态写标准错误，机器可读的标准输出不混入重试提示。
jobs_sdk_retry_note() {
    print -u2 -r -- "$2"
    [[ -z "$1" ]] || print -r -- "$2" >> "$1"
}
# 本地确定错误应明确失败；下载超时、断流和未知获取失败则继续，无次数/总时长上限。
jobs_sdk_retry() {
    setopt LOCAL_OPTIONS LOCAL_TRAPS
    local title="$1" acquisition_log="$2" attempt=1 result=0 delay="${JOBS_SDK_RETRY_DELAY:-2}" maximum="${JOBS_SDK_RETRY_MAX_DELAY:-30}"
    local task_pid="" offset=0 failure="" interrupted=0 history="${2}.attempts.log"
    shift 2
    [[ "$delay" == <-> && "$maximum" == <-> && "$maximum" -gt 0 && "$delay" -le "$maximum" ]] || return 2
    trap 'interrupted=130; [[ -z "$task_pid" ]] || jobs_sdk_stop_tree "$task_pid"' INT
    trap 'interrupted=143; [[ -z "$task_pid" ]] || jobs_sdk_stop_tree "$task_pid"' TERM
    trap 'interrupted=129; [[ -z "$task_pid" ]] || jobs_sdk_stop_tree "$task_pid"' HUP
    while true; do
        jobs_sdk_retry_note "$acquisition_log" "▶ SDK 获取：$title；第 $attempt 次（失败自动重试，Ctrl+C 结束）"
        offset=0
        [[ ! -f "$acquisition_log" ]] || offset="$(/usr/bin/wc -c < "$acquisition_log")"
        [[ "${JOBS_SDK_LOG_REPLACED:-0}" != 1 ]] || offset=0
        # 显式继承 stdin；后台调用仍能进行工具自身的许可/认证交互。
        "$@" <&0 &
        task_pid=$!
        result=0
        wait "$task_pid" || result=$?
        task_pid=""
        (( interrupted == 0 )) || return "$interrupted"
        if [[ -f "$acquisition_log" ]]; then
            (( $(/usr/bin/wc -c < "$acquisition_log") >= offset )) || offset=0
            print -r -- "━━ $title：第 $attempt 次，退出码 $result ━━" >> "$history"
            /usr/bin/tail -c +$((offset + 1)) "$acquisition_log" >> "$history"
        fi
        failure=""
        if [[ -f "$acquisition_log" ]]; then
            failure="$(/usr/bin/tail -c +$((offset + 1)) "$acquisition_log" | /usr/bin/tail -c 65536)"
        fi
        # 部分获取器下载失败仍返回0，明确失败详情不能冒充SDK就绪。
        if (( result == 0 )) && print -r -- "$failure" | /usr/bin/grep -Eqi 'Failed to download|Error downloading|Unable to download|Could not download|Download failed'; then
            result=1
        fi
        (( result != 0 )) || return 0
        # 超时的调用方应返回124；外部中断状态不能被重试循环吞掉。
        case "$result" in 129|130|131|137|143) return "$result" ;; 126|127) return "$result" ;; esac
        failure=""
        if [[ -f "$acquisition_log" ]]; then
            # 兼容调用方每次重建机器输出文件：缩短后从文件开头读取。
            (( $(/usr/bin/wc -c < "$acquisition_log") >= offset )) || offset=0
            failure="$(/usr/bin/tail -c +$((offset + 1)) "$acquisition_log" | /usr/bin/tail -c 65536)"
        fi
        if print -r -- "$failure" | /usr/bin/grep -Eqi 'No available formula|No formulae found|Failed to find package|File exists|Permission denied|Operation not permitted|No space left on device|Read-only file system|Bad CPU type|Exec format error|unknown option|unrecognized option|invalid argument|version .* (does not exist|not found)|license[^[:cntrl:]]*(not accepted|rejected)|licenses?[^[:cntrl:]]*not accepted|HTTP[^[:cntrl:]]*(401|403|404)|returned error: (401|403|404)|Authentication failed|could not read Username'; then
            jobs_sdk_retry_note "$acquisition_log" "✖ $title 遇到权限、许可、版本或本地环境错误（$result），已停止；请按原始日志处理。"
            return "$result"
        fi
        jobs_sdk_retry_note "$acquisition_log" "⚠ $title 获取未完成（退出码 $result）；${delay} 秒后自动重试，保留已有缓存。"
        /bin/sleep "$delay" &
        task_pid=$!
        wait "$task_pid" || { (( interrupted == 0 )) || return "$interrupted"; return 130; }
        task_pid=""
        (( interrupted == 0 )) || return "$interrupted"
        (( attempt++ ))
        (( delay < maximum )) && delay=$(( delay * 2 ))
        (( delay <= maximum )) || delay="$maximum"
    done
}
# JOBS_SDK_RETRY_END

typeset -g DG_PROJECT="" DG_JAVA_HOME="" DG_CHECK=0 DG_DISTRIBUTION_ONLY=0 DG_MIRROR=official
typeset -g DG_VERSION="" DG_TYPE="" DG_URL="" DG_SHA="" DG_CURL="" DG_GRADLE="" DG_CACHE="" DG_LOCK=""
typeset -g DG_WRAPPER_STAMP="" DG_TIMEOUT=900 DG_DOWNLOAD_TIMEOUT=300 DG_JAVA_MAJOR=""
# 静态读取工程中直接声明的AGP版本，动态变量不猜测、不执行Gradle配置。
dg_detect_agp_version() {
    setopt localoptions NO_NOMATCH
    local file="" versions=""
    local -a files
    for file in "$DG_PROJECT"/android/{settings,build}.gradle{,.kts}(N); do
        [[ -f "$file" && ! -L "$file" && "$(/usr/bin/stat -f %z "$file")" -le 1048576 ]] && files+=("$file")
    done
    (( ${#files} )) || return 0
    /usr/bin/perl -0777 -ne 's{/\*.*?\*/}{}gs; s{^\s*//.*$}{}mg; while (/\bid\s*(?:\(\s*)?["\x27]com\.android\.(?:application|library)["\x27]\s*\)?\s*version\s*["\x27]([0-9]+(?:\.[0-9]+)+(?:[-+][0-9A-Za-z.-]+)?)["\x27]/g) { $seen{$1}=1; } while (/com\.android\.tools\.build:gradle:([0-9]+(?:\.[0-9]+)+(?:[-+][0-9A-Za-z.-]+)?)/g) { $seen{$1}=1; } END { print join(" / ",sort keys %seen); }' "${files[@]}"
}
# 将已校验的固定分发版本发送给可见节点，不把配置版本当作AGP检测结果。
dg_report_distribution_version() {
    pe_event gradle.distribution gradle '下载并验证Gradle分发' succeeded '已验证ZIP SHA256' "Gradle $DG_VERSION"
}
# 第一屏自述同时解释插件解析会执行项目构建脚本。
dg_intro_and_wait() {
    local answer=""
    print -r -- '━━━━━━━━━━ DownloadProjectGradle.zsh｜下载 Gradle 插件 ━━━━━━━━━━'
    print -r -- '1、读取项目 Wrapper 固定版本与环境配置，按实际 Java 做兼容检查；不会自动升级 Gradle / AGP。'
    print -r -- '2、下载包先校验 SHA256；官方备用线路、有界重试和断点续传；可选镜像仅限本次进程。'
    print -r -- '3、在 android 执行 Gradle help 解析 AGP / Kotlin 等构建插件，会执行该项目构建脚本并写正常缓存；不编译 App。'
    print -r -- '4、日志与快照位于系统临时目录 JobsFlutterEnvironment.*；分发缓存位于用户 Library/Caches/JobsFlutterTools。'
    jobs_prompt_output print -r -- '5、--check 只读不联网；常规运行回车继续，Ctrl+C / Esc 取消，不修改系统代理或全局仓库。'
    dg_parse "$@" || { print -u2 '用法：DownloadProjectGradle.zsh --project <绝对路径> [--java-home <JDK>] [--check] [--distribution-only]'; exit 2; }
    (( DG_CHECK )) && return 0
    [[ -t 0 && -t 1 ]] || { print -u2 '✖ 需要可交互终端。'; exit 2; }
    IFS= read -r "answer?$(jobs_prompt_render '👉 已了解用途与影响，按回车继续；其它输入取消：')" || exit 130
    [[ -z "$answer" ]] || exit 130
}
# 参数严格限定为数据，不接受额外 Gradle 命令。
dg_parse() {
    DG_PROJECT="" DG_JAVA_HOME="" DG_CHECK=0 DG_DISTRIBUTION_ONLY=0
    while (( $# )); do
        case "$1" in
            --project) (( $# >= 2 )) && [[ -z "$DG_PROJECT" ]] || return 2; DG_PROJECT="$2"; shift 2 ;;
            --java-home) (( $# >= 2 )) && [[ -z "$DG_JAVA_HOME" ]] || return 2; DG_JAVA_HOME="$2"; shift 2 ;;
            --check) DG_CHECK=1; shift ;;
            --distribution-only) DG_DISTRIBUTION_ONLY=1; shift ;;
            *) return 2 ;;
        esac
    done
    [[ "$DG_PROJECT" == /* && -d "$DG_PROJECT" && ! -L "${DG_PROJECT%/}" ]]
}
# 加载无入口的共享定义，检查和 source 模式均不创建日志。
dg_initialize() {
    source "$(jobs_layout_file "$(jobs_layout_directory "${(%):-%x}")/ProjectEnvironment.zsh")" || return $?
    source "$(jobs_layout_file "$PE_TOOLS_DIR/ManageProjectJava.zsh")" || return $?
    source "$(jobs_layout_file "$PE_TOOLS_DIR/WrapperDistributionCache.zsh")" || return $?
    pe_validate_project "$DG_PROJECT" || { pe_log '✖ 请选择普通 Flutter 项目根目录。'; return 2; }
    DG_PROJECT="$PE_PROJECT"
    DG_TIMEOUT="${JOBS_GRADLE_TASK_TIMEOUT:-900}"
    DG_DOWNLOAD_TIMEOUT="${JOBS_GRADLE_DOWNLOAD_TIMEOUT:-300}"
    [[ "$DG_TIMEOUT" == <-> && "$DG_TIMEOUT" -ge 30 && "$DG_TIMEOUT" -le 7200 && "$DG_DOWNLOAD_TIMEOUT" == <-> && "$DG_DOWNLOAD_TIMEOUT" -ge 10 && "$DG_DOWNLOAD_TIMEOUT" -le 1800 ]] || { pe_log '✖ Gradle超时配置无效：任务30–7200秒，单次下载10–1800秒。'; return 2; }
}
# 只读解析标准固定发行版属性，拒绝未知格式、重复键和动态版本。
dg_read_wrapper() {
    local wrapper="$DG_PROJECT/android/gradle/wrapper/gradle-wrapper.properties" rows="" file_name=""
    [[ -d "$DG_PROJECT/android" && ! -L "$DG_PROJECT/android" && ! -L "$DG_PROJECT/android/gradle" && ! -L "$DG_PROJECT/android/gradle/wrapper" && -f "$wrapper" && ! -L "$wrapper" ]] || { pe_log '✖ 缺少普通 Android Gradle Wrapper 项目；不生成或升级平台文件。'; return 1; }
    [[ "$(/usr/bin/stat -f %z "$wrapper")" -le 65536 ]] || return 1
    rows="$(/usr/bin/perl -ne 's/\r?\n$//; next if /^\s*[#!]/; if (/^\s*(distributionUrl|distributionSha256Sum)\s*[=:]\s*(.*?)\s*$/) { $k=$1; $v=$2; die "duplicate key\n" if $seen{$k}++; $v =~ s/\\:/:/g; print "$k\t$v\n"; }' "$wrapper")" || return 1
    DG_URL="$(print -r -- "$rows" | /usr/bin/awk -F '\t' '$1=="distributionUrl" {print $2}')"
    DG_SHA="$(print -r -- "$rows" | /usr/bin/awk -F '\t' '$1=="distributionSha256Sum" {print tolower($2)}')"
    [[ "$DG_URL" =~ '^https://[A-Za-z0-9.-]+(:[0-9]+)?/[A-Za-z0-9._~/%+-]+$' ]] || { pe_log '✖ Wrapper URL须为无凭据/查询参数的HTTPS固定发行包。'; return 1; }
    file_name="${DG_URL:t}"
    [[ "$file_name" =~ '^gradle-([0-9]+\.[0-9]+(\.[0-9]+)?)-(bin|all)\.zip$' ]] || { pe_log '✖ 只支持固定正式 Gradle x.y[.z]-bin/all.zip；动态或预览版本请人工核实。'; return 1; }
    DG_VERSION="$match[1]" DG_TYPE="$match[3]"
    [[ -z "$DG_SHA" || "$DG_SHA" =~ '^[0-9a-f]{64}$' ]] || { pe_log '✖ distributionSha256Sum无效。'; return 1; }
    DG_WRAPPER_STAMP="$(/usr/bin/shasum -a 256 "$wrapper")" || return 1
}
# 项目环境配置优先，其次 .java-version，最后当前系统 JDK；显式参数优先于全部。
dg_resolve_java() {
    local candidate="" configured=""
    PJ_PROJECT="$DG_PROJECT"
    pj_check_gradle_criteria || return $?
    if [[ -z "$DG_JAVA_HOME" ]]; then
        pe_read_environment || return $?
        if [[ -n "$PE_CONFIG_JAVA" ]]; then
            DG_JAVA_HOME="$PE_CONFIG_JAVA"
        elif [[ -e "$DG_PROJECT/.java-version" || -L "$DG_PROJECT/.java-version" ]]; then
            pj_read_config && pj_discover_jdks && pj_resolve_config || { pe_log '✖ 项目Java声明不可用，请先安装/切换或一键配置。'; return 1; }
            DG_JAVA_HOME="$PJ_JAVA_HOME"
        else
            candidate="${JAVA_HOME:-}"
            [[ -n "$candidate" ]] || candidate="$(/usr/libexec/java_home 2>/dev/null)"
            DG_JAVA_HOME="$candidate"
        fi
    fi
    pj_probe_jdk "$DG_JAVA_HOME" || { pe_log '✖ 选定JDK失效，必须同时有可用java和javac；请重新配置。'; return 1; }
    DG_JAVA_HOME="$PJ_JAVA_HOME" DG_JAVA_MAJOR="$PJ_JAVA_MAJOR"
    [[ "$DG_JAVA_HOME" != *[\"\\\$\`]* ]] && ! print -rn -- "$DG_JAVA_HOME" | /usr/bin/grep -q '[[:cntrl:]]' || { pe_log '✖ JDK路径含Gradle启动器无法安全处理的字符，请使用常规安装路径。'; return 1; }
    pe_log "➤ 实际JDK：Java $DG_JAVA_MAJOR · $DG_JAVA_HOME；固定Gradle：$DG_VERSION"
}
# 比较纯数字版本，不依赖本机包管理器或执行项目脚本。
dg_version_at_least() {
    local -a actual required
    local index=0
    actual=("${(@s:.:)1}") required=("${(@s:.:)2}")
    for index in 1 2 3; do
        (( ${actual[index]:-0} > ${required[index]:-0} )) && return 0
        (( ${actual[index]:-0} < ${required[index]:-0} )) && return 1
    done
    return 0
}
# 依据Gradle官方Java Runtime矩阵校验，不以编译toolchain版本代替运行版本。
dg_check_java_compatibility() {
    local minimum=""
    case "$DG_JAVA_MAJOR" in
        8) minimum=2.0 ;; 9) minimum=4.3 ;; 10) minimum=4.7 ;; 11) minimum=5.0 ;;
        12) minimum=5.4 ;; 13) minimum=6.0 ;; 14) minimum=6.3 ;; 15) minimum=6.7 ;;
        16) minimum=7.0 ;; 17) minimum=7.3 ;; 18) minimum=7.5 ;; 19) minimum=7.6 ;;
        20) minimum=8.3 ;; 21) minimum=8.5 ;; 22) minimum=8.8 ;; 23) minimum=8.10 ;;
        24) minimum=8.14 ;; 25) minimum=9.1 ;; 26) minimum=9.4 ;; 27) minimum=9.8 ;;
        *) pe_log '✖ 此Java运行版本不在已核实兼容矩阵内，请人工核对。'; return 1 ;;
    esac
    if ! dg_version_at_least "$DG_VERSION" "$minimum" || { (( DG_JAVA_MAJOR < 17 )) && dg_version_at_least "$DG_VERSION" 9.0; }; then
        pe_log "✖ Java $DG_JAVA_MAJOR 与 Gradle $DG_VERSION 不兼容；该Java最低Gradle $minimum，Gradle9+须Java17+。请重新选择Java，脚本不升级工程。"
        return 1
    fi
}
# 下载单次有界，只有同一来源的临时片段可续传，失败保留供后次重试。
dg_curl_download_once() {
    local url="$1" target="$2" seconds="$3" result=0 attempt=0 rejected=""
    local -a resume
    for attempt in 1 2; do
        resume=()
        [[ ! -s "$target" ]] || resume=(--continue-at -)
        pe_log "📥 来源：$url；目标：$target；尝试$attempt/2，连接10秒、单次${seconds}秒、低速30秒停止。"
        result=0
        pe_run_logged "$DG_CURL" --fail --location --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time "$seconds" --speed-time 30 --speed-limit 1024 "${resume[@]}" --output "$target" "$url" || result=$?
        if (( result == 0 )); then
            if [[ -n "$DG_SHA" && "$url" == *.zip ]]; then
                if dg_verify_zip "$target"; then return 0; fi
                pe_log "⚠ 本次Gradle分发摘要不符，保留损坏片段并继续获取：$target"
                rejected="$(/usr/bin/mktemp "$target.rejected.XXXXXX")" || return 1
                /bin/mv -f -- "$target" "$rejected" || return 1
                [[ ! -e "$target" ]] || return 1
                result=65
            else
                return 0
            fi
        fi
        # 416/不支持Range时只丢弃本次受管片段，第二次从头下载。
        if (( result == 22 || result == 33 )); then /bin/rm -f -- "$target"; fi
    done
    return "$result"
}
# SDK分发获取失败继续重试；项目构建和插件执行不进入此循环。
dg_curl_download() {
    jobs_sdk_retry 'Gradle分发 / 官方摘要' "$PE_LOG_FILE" dg_curl_download_once "$@"
}
# 采用Wrapper固定摘要，缺省仅从Gradle官方校验端点取摘要，镜像不能提供信任根。
dg_fetch_checksum() {
    local url="" output="$PE_RUN_DIR/gradle.sha256" value=""
    [[ -z "$DG_SHA" ]] || return 0
    for url in "https://services.gradle.org/distributions/gradle-$DG_VERSION-$DG_TYPE.zip.sha256" "https://downloads.gradle.org/distributions/gradle-$DG_VERSION-$DG_TYPE.zip.sha256"; do
        /bin/rm -f -- "$output"
        if dg_curl_download "$url" "$output" 30; then
            value="$(/usr/bin/tr -d '\r\n' < "$output")"
            if [[ "$value" =~ '^[0-9a-fA-F]{64}$' ]]; then DG_SHA="${value:l}"; return 0; fi
        fi
    done
    pe_log '✖ 无法取得Gradle官方SHA256；没有可信摘要不会解压或执行下载包。'
    return 1
}
# 对照SHA256验证普通ZIP，拒绝符号或硬链接缓存。
dg_verify_zip() {
    local archive="$1" value=""
    [[ -f "$archive" && ! -L "$archive" && "$(/usr/bin/stat -f %l "$archive")" == 1 ]] || return 1
    value="$(/usr/bin/shasum -a 256 "$archive")" || return 1
    [[ "${value%% *}" == "$DG_SHA" ]]
}
# 从项目源与官方备用源下载，选镜像时加入腾讯分发镜像；各源片段隔离。
dg_download_distribution() {
    local archive="" url="" key="" partial=""
    local -a urls
    DG_CURL="$(command -v curl 2>/dev/null)"
    [[ -x "$DG_CURL" ]] && "$DG_CURL" --version >/dev/null 2>&1 || { pe_log '✖ 缺少可用curl。'; return 1; }
    dg_fetch_checksum || return $?
    DG_CACHE="$HOME/Library/Caches/JobsFlutterTools/gradle/$DG_SHA"
    [[ ! -L "$HOME/Library/Caches/JobsFlutterTools" && ! -L "${DG_CACHE:h}" && ! -L "$DG_CACHE" ]] || { pe_log '✖ Gradle缓存目录是链接，请人工核实。'; return 1; }
    /bin/mkdir -p -- "$DG_CACHE" || return 1
    archive="$DG_CACHE/gradle-$DG_VERSION-$DG_TYPE.zip"
    if dg_verify_zip "$archive"; then pe_log "✔ 复用已校验分发包：$archive"; dg_report_distribution_version; return 0; fi
    [[ ! -e "$archive" && ! -L "$archive" ]] || { pe_log '✖ 已有缓存包摘要不匹配/身份异常，保留现场，请核实后移走再重试。'; return 1; }
    urls=("$DG_URL" "https://downloads.gradle.org/distributions/gradle-$DG_VERSION-$DG_TYPE.zip" "https://services.gradle.org/distributions/gradle-$DG_VERSION-$DG_TYPE.zip")
    [[ "$DG_MIRROR" != aliyun ]] || urls=("https://mirrors.cloud.tencent.com/gradle/gradle-$DG_VERSION-$DG_TYPE.zip" "${urls[@]}")
    for url in "${(@u)urls}"; do
        key="$(print -rn -- "$url" | /usr/bin/shasum -a 256)"; key="${key%% *}"
        partial="$DG_CACHE/${key[1,16]}.part"
        [[ ! -L "$partial" ]] || return 1
        if dg_curl_download "$url" "$partial" "$DG_DOWNLOAD_TIMEOUT"; then
            if dg_verify_zip "$partial"; then
                /bin/mv -n -- "$partial" "$archive" || return 1
                dg_verify_zip "$archive" || return 1
                pe_log "✔ SHA256通过，最终分发来源：$url"
                dg_report_distribution_version
                return 0
            fi
            pe_log "⚠ 来源包SHA256不匹配，未执行，保留片段供排查：$partial"
        fi
    done
    pe_log '✖ 所有分发源失败；保留同源下载片段，下次运行可继续。'
    return 1
}
# 解压前检查归档目录和链接类型，每次运行只执行本次已校验ZIP解出的分发。
dg_extract_distribution() {
    local archive="$DG_CACHE/gradle-$DG_VERSION-$DG_TYPE.zip" entries="" item="" root="gradle-$DG_VERSION"
    entries="$(/usr/bin/unzip -Z1 "$archive")" || return 1
    [[ -n "$entries" ]] || return 1
    while IFS= read -r item; do
        [[ "$item" == "$root/"* && "$item" != *\\* && "$item" != *'/../'* && "$item" != *'/./'* ]] || { pe_log '✖ ZIP目录结构异常，未解压。'; return 1; }
    done <<< "$entries"
    /usr/bin/unzip -Z -l "$archive" | /usr/bin/awk '$1 ~ /^l/ {bad=1} END {exit bad}' || { pe_log '✖ ZIP含符号链接，未解压。'; return 1; }
    /bin/mkdir "$PE_RUN_DIR/distribution" || return 1
    /usr/bin/ditto -x -k "$archive" "$PE_RUN_DIR/distribution" || return 1
    DG_GRADLE="$PE_RUN_DIR/distribution/$root/bin/gradle"
    [[ -x "$DG_GRADLE" && ! -L "$DG_GRADLE" ]] || return 1
    wd_prepare_zip "$DG_PROJECT" "$DG_URL" "$DG_SHA" "$archive" "$DG_JAVA_HOME" || return $?
    dg_verify_wrapper
}
# 所选Java有界启动项目实际Wrapper，确认固定版本能从本地缓存启动。
dg_verify_wrapper() {
    local task_pid=0 timer_pid=0 result=0 actual=""
    local -a launch
    if [[ -f "$DG_PROJECT/android/gradlew" && ! -L "$DG_PROJECT/android/gradlew" ]]; then
        launch=(/bin/sh "$DG_PROJECT/android/gradlew")
    else
        launch=("$DG_JAVA_HOME/bin/java" -classpath "$DG_PROJECT/android/gradle/wrapper/gradle-wrapper.jar" org.gradle.wrapper.GradleWrapperMain)
    fi
    (
        cd -- "$DG_PROJECT/android" || exit 1
        JAVA_HOME="$DG_JAVA_HOME" PATH="$DG_JAVA_HOME/bin:$PATH" "${launch[@]}" "-Dorg.gradle.java.home=$DG_JAVA_HOME" --no-daemon --console plain --version 2>&1 | /usr/bin/tee "$PE_RUN_DIR/wrapper-version.log" >(pe_filter_log >> "$PE_LOG_FILE")
        exit ${pipestatus[1]}
    ) &
    task_pid=$!
    (
        trap 'exit 0' TERM INT HUP
        /bin/sleep 60 || exit 0
        print timeout > "$PE_RUN_DIR/wrapper-version.timeout"
        dg_stop_timed_out_tree "$task_pid"
    ) &
    timer_pid=$!
    trap 'dg_terminate_tree "$task_pid"; dg_terminate_tree "$timer_pid"; exit 130' INT TERM HUP
    wait "$task_pid" || result=$?
    dg_terminate_tree "$timer_pid"
    wait "$timer_pid" 2>/dev/null || true
    trap - INT TERM HUP
    [[ ! -f "$PE_RUN_DIR/wrapper-version.timeout" ]] || { pe_log '✖ 项目Wrapper启动超过60秒，缓存复用未验证。'; return 124; }
    (( result == 0 )) || { pe_log "✖ 项目Wrapper版本验证失败（$result），未进入Pub或插件预热。"; return "$result"; }
    if /usr/bin/grep -Eqi '^Downloading https?://' "$PE_RUN_DIR/wrapper-version.log"; then
        pe_log '✖ 项目Wrapper仍触发网络分发下载，缓存复用验证未通过，请检查Wrapper自定义实现或缓存参数。'
        return 1
    fi
    actual="$(/usr/bin/perl -ne 'if (/^Gradle ([0-9]+\.[0-9]+(?:\.[0-9]+)?)\s*$/) { print $1; exit }' "$PE_RUN_DIR/wrapper-version.log")"
    [[ "$actual" == "$DG_VERSION" ]] || { pe_log "✖ 实际Wrapper版本${actual:-未知}与固定${DG_VERSION}不同。"; return 1; }
    pe_log "✔ 项目Wrapper以所选Java从本地缓存启动Gradle $actual；未发生额外分发下载。"
    pe_event gradle.wrapper gradle '验证项目Wrapper缓存复用' succeeded '实际Wrapper已启动且无额外分发下载' "Gradle $actual"
    pe_event gradle '' 'Gradle分发' succeeded '' "Gradle $actual"
}
# 镜像只写临时init脚本，保留官方后备，不改工程或用户仓库配置。
dg_write_mirror_init() {
    [[ "$DG_MIRROR" == aliyun ]] || return 0
    dg_version_at_least "$DG_VERSION" 6.0 || { pe_log '✖ 此旧Gradle不能使用当前临时镜像钩子，请选官方模式。'; return 1; }
    /bin/cat > "$PE_RUN_DIR/repositories.init.gradle" <<'GROOVY'
gradle.beforeSettings { s ->
    s.pluginManagement.repositories {
        maven { url 'https://maven.aliyun.com/repository/google' }
        maven { url 'https://maven.aliyun.com/repository/gradle-plugin' }
        maven { url 'https://maven.aliyun.com/repository/public' }
        google(); mavenCentral(); gradlePluginPortal()
    }
}
gradle.settingsEvaluated { s ->
    if (s.metaClass.hasProperty(s, 'dependencyResolutionManagement')) {
        s.dependencyResolutionManagement.repositories {
            maven { url 'https://maven.aliyun.com/repository/google' }
            maven { url 'https://maven.aliyun.com/repository/public' }
        }
    }
}
gradle.beforeProject { p ->
    p.buildscript.repositories {
        maven { url 'https://maven.aliyun.com/repository/google' }
        maven { url 'https://maven.aliyun.com/repository/public' }
    }
}
GROOVY
    pe_log '➤ 本次构建插件备用源：https://maven.aliyun.com/repository/{google,gradle-plugin,public}；腾讯Gradle镜像。退出后撤回临时源，不修改系统代理。'
}
# 有界等待任务，超时时递归终止本次子进程，不触碰其它Gradle或Java会话。
dg_terminate_tree() {
    local pid="$1" child=""
    for child in "${(@f)$(/usr/bin/pgrep -P "$pid" 2>/dev/null)}"; do
        [[ "$child" == <-> ]] || continue
        dg_terminate_tree "$child"
    done
    /bin/kill -TERM "$pid" 2>/dev/null || true
}
# 超时升级为KILL，先收集本次子树再发送信号，避免TERM无效导致永久等待。
dg_stop_timed_out_tree() {
    local root_pid="$1" item="" child="" index=1
    local -a targets
    targets=("$root_pid")
    while (( index <= ${#targets} )); do
        for child in "${(@f)$(/usr/bin/pgrep -P "${targets[index]}" 2>/dev/null)}"; do
            [[ "$child" == <-> ]] && targets+=("$child")
        done
        (( index++ ))
    done
    for item in "${targets[@]}"; do /bin/kill -TERM "$item" 2>/dev/null || true; done
    /bin/sleep 2
    for item in "${targets[@]}"; do /bin/kill -KILL "$item" 2>/dev/null || true; done
}
# 执行单次help并保留超时标记，标准日志在前台流式显示。
dg_run_help_once() {
    local task_pid=0 timer_pid=0 result=0
    local -a options
    options=(--no-daemon --console plain "-Dorg.gradle.java.home=$DG_JAVA_HOME" -Dorg.gradle.internal.http.connectionTimeout=15000 -Dorg.gradle.internal.http.socketTimeout=30000)
    [[ "$DG_MIRROR" != aliyun ]] || options+=(--init-script "$PE_RUN_DIR/repositories.init.gradle")
    (
        cd -- "$DG_PROJECT/android" || exit 1
        JAVA_HOME="$DG_JAVA_HOME" PATH="$DG_JAVA_HOME/bin:$PATH" "$DG_GRADLE" "${options[@]}" help 2>&1 | /usr/bin/tee "$PE_RUN_DIR/gradle-current.log" >(pe_filter_log >> "$PE_LOG_FILE")
        exit ${pipestatus[1]}
    ) &
    task_pid=$!
    (
        trap 'exit 0' TERM INT HUP
        /bin/sleep "$DG_TIMEOUT" || exit 0
        print -r -- timeout > "$PE_RUN_DIR/gradle-timeout"
        dg_stop_timed_out_tree "$task_pid"
    ) &
    timer_pid=$!
    trap 'dg_terminate_tree "$task_pid"; dg_terminate_tree "$timer_pid"; exit 130' INT TERM HUP
    wait "$task_pid" || result=$?
    dg_terminate_tree "$timer_pid"
    wait "$timer_pid" 2>/dev/null || true
    trap - INT TERM HUP
    [[ ! -f "$PE_RUN_DIR/gradle-timeout" ]] || { pe_log "✖ Gradle任务超过${DG_TIMEOUT}秒，已停止本次进程。"; return 124; }
    return "$result"
}
# 插件预热最多两次，只在明确网络错误时重试，不重放配置/语法/权限失败。
dg_warm_plugins() {
    local result=0 attempt=0 current_stamp=""
    current_stamp="$(/usr/bin/shasum -a 256 "$DG_PROJECT/android/gradle/wrapper/gradle-wrapper.properties")" || return 1
    [[ "$current_stamp" == "$DG_WRAPPER_STAMP" ]] || { pe_log '✖ Wrapper配置在下载期间变化，请重跑。'; return 1; }
    dg_write_mirror_init || return $?
    for attempt in 1 2; do
        pe_log "➤ Gradle $DG_VERSION help · Java $DG_JAVA_MAJOR · 构建插件预热 $attempt/2"
        result=0
        dg_run_help_once || result=$?
        if (( result == 0 )); then
            pe_log '✔ Gradle help通过，AGP / Kotlin等当前配置阶段构建插件已解析；不代表所有App依赖或编译通过。'
            local agp_version="$(dg_detect_agp_version)"
            pe_event gradle.plugins gradle '解析AGP与构建插件' succeeded '动态声明的AGP版本不猜测' "Gradle $DG_VERSION${agp_version:+ · AGP $agp_version}"
            return 0
        fi
        (( result != 124 )) || return "$result"
        /usr/bin/grep -Eqi '401|403|Unauthorized|Forbidden|PKIX|certificate|authentication|permission denied' "$PE_RUN_DIR/gradle-current.log" && break
        /usr/bin/grep -Eqi 'timed out|Connection reset|UnknownHostException|Could not (GET|HEAD)|Network is unreachable|Temporary failure|Connection refused|Remote host terminated' "$PE_RUN_DIR/gradle-current.log" || break
    done
    pe_log "✖ Gradle插件预热失败（$result）；检查SDK、local.properties、私有仓库权限、AGP兼容及网络。没有把下载分发包当成插件完成。"
    return "$result"
}
# 编排独立模式的只读检查、网络选择、分发包准备与插件预热。
dg_run_requested() {
    local result=0
    dg_initialize && dg_read_wrapper && dg_resolve_java && dg_check_java_compatibility || return $?
    (( ! DG_CHECK )) || { pe_log '✔ 只读配置与Java/Gradle运行版本检查通过；未联网、未解析AGP、未执行构建。'; return 0; }
    pe_initialize_runtime && pe_ensure_fzf || return $?
    pe_select '下载线路' $'official\t项目/官方来源（默认）\naliyun\t腾讯Gradle镜像 + 阿里云Maven备用源（本次进程）' || { result=$?; (( result == 10 )) && result=130; return "$result"; }
    DG_MIRROR="$PE_SELECTION"
    dg_download_distribution && dg_extract_distribution || return $?
    (( ! DG_DISTRIBUTION_ONLY )) || { pe_log '✔ 分发包准备完成；尚未解析构建插件。'; return 0; }
    dg_warm_plugins
}
# 入口按自述、实际业务两步收口，source不执行。
main() {
    dg_intro_and_wait "$@" # 说明用途、缓存和项目脚本执行影响后确认。
    dg_run_requested # 按模式验证配置、准备分发并预热构建插件。
}

if [[ "$ZSH_EVAL_CONTEXT" == toplevel ]]; then
    main "$@"
fi
