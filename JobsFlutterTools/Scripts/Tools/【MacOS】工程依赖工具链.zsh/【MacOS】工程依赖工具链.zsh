#!/bin/zsh
# 脚本自述：仅供 source；为 Flutter Web / 鸿蒙依赖发现、准备和复检配套工具，并桥接 Apple SPM 构建缓存。
# 仅修改本进程环境、项目缓存或经明确确认的用户工具目录；不改系统代理、全局 npm、Shell 配置或工程版本声明。

# JOBS_INPUT_CHOICE_STYLE_BEGIN
# 只展示提示选项；不读取答案、不改变默认值、返回码或业务环境。
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

typeset -g PT_NODE="" PT_PACKAGE_MANAGER="" PT_OHPM="" PT_HVIGOR="" PT_NODE_PIN="" PT_NODE_RANGE="" PT_MANAGER_PIN=""
# 独立单项入口也可获取运行时；加载重试定义本身不安装或写配置。
pt_load_sdk_retry() {
    (( ${+functions[jobs_sdk_retry]} )) && return 0
    source "${${(%):-%x}:A:h:h}/【MacOS】SDK获取重试.zsh/【MacOS】SDK获取重试.zsh"
}
# 写入目录逐级检查，避免通过已有父级链接写到另一棵目录。
pt_check_directory_chain() {
    local directory="$1"
    [[ "$directory" == /* ]] || return 2
    while [[ "$directory" != / ]]; do
        [[ ! -L "$directory" && ( ! -e "$directory" || -d "$directory" ) ]] || return 2
        directory="${directory:h}"
    done
}
# 精确补丁使用官方归档及 SHA256，不把 Homebrew 主版本最新补丁冒充项目所锁版本。
pt_install_node_exact() {
    local version="$1" architecture="$(/usr/bin/uname -m)" folder="" cache="" archive="" checksum="" expected="" actual="" stage="" backup=""
    [[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || return 2
    case "$architecture" in arm64) ;; x86_64) architecture=x64 ;; *) pe_log '✖ 当前宿主架构没有对应 Node 官方 macOS 归档。'; return 3 ;; esac
    folder="node-v$version-darwin-$architecture"
    cache="$HOME/Library/Caches/JobsFlutterTools/node/v$version/$architecture"
    pt_check_directory_chain "$cache" || { pe_log '✖ Node 用户缓存目录含链接或非目录。'; return 2; }
    if pt_probe_node "$cache/$folder/bin/node"; then return 0; fi
    /bin/mkdir -p "$cache" || return $?
    archive="$cache/$folder.tar.gz" checksum="$cache/SHASUMS256.txt"
    [[ ! -L "$archive" && ! -L "$checksum" ]] || return 2
    pt_load_sdk_retry || return $?
    pe_log "📥 来源：https://nodejs.org/dist/v$version/SHASUMS256.txt；目标：$checksum。"
    JOBS_SDK_LOG_REPLACED=1 jobs_sdk_retry 'Node官方SHA256清单' "$PE_RUN_DIR/node-shasums.log" sf_run_diagnostic node-shasums /usr/bin/curl --fail --location --connect-timeout 30 --speed-limit 1 --speed-time 60 --output "$checksum" "https://nodejs.org/dist/v$version/SHASUMS256.txt" || return $?
    expected="$(/usr/bin/awk -v name="$folder.tar.gz" '$2 == name && $1 ~ /^[0-9a-f]+$/ && length($1)==64 {print $1}' "$checksum")"
    [[ ${#expected} == 64 && "$expected" != *$'\n'* ]] || { pe_log '✖ 官方校验清单没有唯一匹配的 Node 归档，未下载或执行。'; return 3; }
    if [[ -f "$archive" ]]; then actual="$(/usr/bin/shasum -a 256 "$archive")"; actual="${actual%% *}"; fi
    if [[ "$actual" != "$expected" ]]; then
        pe_log "📥 来源：https://nodejs.org/dist/v$version/$folder.tar.gz；目标：$archive；复用可续传内容。"
        JOBS_SDK_LOG_REPLACED=1 jobs_sdk_retry "Node $version $architecture" "$PE_RUN_DIR/node-download.log" sf_run_diagnostic node-download /usr/bin/curl --fail --location --connect-timeout 30 --speed-limit 1 --speed-time 60 --continue-at - --output "$archive" "https://nodejs.org/dist/v$version/$folder.tar.gz" || return $?
        actual="$(/usr/bin/shasum -a 256 "$archive")"; actual="${actual%% *}"
    fi
    [[ "$actual" == "$expected" ]] || { pe_log '✖ Node 归档 SHA256 不匹配，已保留现场并停止，未执行归档内容。'; return 3; }
    /usr/bin/tar -tzf "$archive" | /usr/bin/awk -v root="$folder" '($0 !~ "^" root "/" || $0 ~ /(^|\/)\.\.(\/|$)/ || $0 ~ /^\//) {bad=1} END {exit bad}' || return 3
    stage="$(/usr/bin/mktemp -d "$cache/.extract.XXXXXX")" || return 1
    /usr/bin/tar -xzf "$archive" -C "$stage" || return $?
    [[ -x "$stage/$folder/bin/node" && -x "$stage/$folder/bin/npm" ]] || return 3
    if [[ -e "$cache/$folder" || -L "$cache/$folder" ]]; then
        [[ ! -L "$cache/$folder" && -d "$cache/$folder" ]] || return 2
        backup="$cache/$folder.before-jobs-$(/bin/date +%Y%m%d-%H%M%S)-$$"
        [[ ! -e "$backup" ]] || return 2
        /bin/mv "$cache/$folder" "$backup" || return $?
        pe_log "➤ 原 Node 目录已保留：$backup。"
    fi
    /bin/mv "$stage/$folder" "$cache/$folder" || return $?
    /bin/rmdir "$stage" || return $?
    pt_probe_node "$cache/$folder/bin/node"
}
# 普通工具安装先明确选择；默认停止，取消不落盘。
pt_confirm_install() {
    pe_log "➤ $1"
    pe_select '准备依赖工具' $'stop\t取消，保留现有环境\ninstall\t安装上述工具并在当前流程重新验证' || return $?
    [[ "$PE_SELECTION" == install ]] || return 130
}
# 只读取数据；Node 版本文件与 packageManager 不作为 Shell 语句执行。
pt_read_node_requirements() {
    local directory="$1" rows="" key="" value="" file=""
    PT_NODE_PIN="" PT_NODE_RANGE="" PT_MANAGER_PIN=""
    rows="$(/usr/bin/perl -MJSON::PP -e '
        local $/; open my $f,"<",$ARGV[0] or exit 2; my $p=decode_json(<$f>); ref($p) eq "HASH" or exit 2;
        for my $entry (["range",ref($p->{engines}) eq "HASH" ? $p->{engines}{node} : undef],["manager",$p->{packageManager}]) {
            next unless defined $entry->[1]; ref($entry->[1]) and exit 2; $entry->[1] =~ /[\x00-\x1f\x7f]/ and exit 2;
            print "$entry->[0]\t$entry->[1]\n";
        }' "$directory/package.json")" || { pe_log '✖ package.json 版本声明无法解析。'; return 2; }
    while IFS=$'\t' read -r key value; do
        case "$key" in range) PT_NODE_RANGE="$value" ;; manager) PT_MANAGER_PIN="$value" ;; esac
    done <<< "$rows"
    for file in "$directory/.nvmrc" "$directory/.node-version" "$SF_PROJECT/.nvmrc" "$SF_PROJECT/.node-version"; do
        [[ -f "$file" && ! -L "$file" ]] || continue
        value="$(/usr/bin/tr -d ' \t\r\n' < "$file")"
        if [[ "$value" =~ '^v?[0-9]+(\.[0-9]+){0,2}$' ]]; then PT_NODE_PIN="${value#v}";
        elif [[ "$value" != node && "$value" != stable && "$value" != lts/\* ]]; then
            pe_log "✖ 无法静态确认 Node 版本声明：$file；请使用明确版本或项目支持的 engines.node。"; return 3
        fi
        break
    done
}
# npm 自带的 semver 负责完整 engines 范围，不用自行近似判断 ^、~、|| 等表达式。
pt_probe_node() {
    local candidate="$1" directory="${2:-$SF_PROJECT}" npm="${1:h}/npm"
    [[ -x "$candidate" && -x "$npm" ]] || return 1
    SF_COMMAND_TIMEOUT=30 sf_run_diagnostic toolchain-node "$candidate" --version || return $?
    SF_COMMAND_TIMEOUT=30 sf_run_diagnostic toolchain-npm "$npm" --version || return $?
    SF_COMMAND_TIMEOUT=30 sf_run_diagnostic toolchain-node-constraints "$candidate" -e '
const fs = require("fs"), Module = require("module");
const [npm, pin, range] = process.argv.slice(1);
let semver;
try { semver = Module.createRequire(fs.realpathSync(npm))("semver"); }
catch (error) { if (pin || range) { console.error("npm 的 semver 不可用，不能验证 Node 约束。"); process.exit(3); } }
if (pin && !semver.satisfies(process.version, pin)) { console.error(`Node ${process.version} 不满足版本文件 ${pin}`); process.exit(3); }
if (range && (!semver.validRange(range) || !semver.satisfies(process.version, range))) { console.error(`Node ${process.version} 不满足 engines.node ${range}`); process.exit(3); }
console.log(`Node ${process.version} / npm 与工程版本约束已通过`);
' "$npm" "$PT_NODE_PIN" "$PT_NODE_RANGE" || return $?
    PT_NODE="${candidate:A}"
    export PATH="${candidate:h}:$PATH"
    rehash
}
# 复用健康的 PATH、用户版本管理器和 Homebrew Node；不通过 nvm shell 函数改全局版本。
pt_prepare_node() {
    setopt localoptions NO_NOMATCH
    local directory="$1" candidate="" requested="" prefix="" formula=node choice="" attempted=0
    local -a candidates=("$(command -v node 2>/dev/null)" "${NODE_HOME:-/nonexistent}/bin/node" \
        "$HOME"/.nvm/versions/node/*/bin/node(N) "$HOME"/.volta/tools/image/node/*/bin/node(N) \
        "$HOME"/.local/share/fnm/node-versions/*/installation/bin/node(N) \
        "$HOME/Library/Caches/JobsFlutterTools/node"/v*/*/node-v*/bin/node(N) \
        /opt/homebrew/opt/node*/bin/node(N) /usr/local/opt/node*/bin/node(N))
    for candidate in "${candidates[@]}"; do
        [[ -n "$candidate" ]] || continue
        pt_probe_node "$candidate" "$directory" && return 0
    done
    while true; do
        pe_log "➤ 需要 Node ${PT_NODE_PIN:-${PT_NODE_RANGE:-工程支持版本}} 与同套 npm；仅对本次进程生效。"
        pe_select 'Node.js 工具链' $'stop\t取消本次依赖准备\nmanual\t选择已有 Node 可执行文件\ninstall\t通过 Homebrew 安装兼容版本并复检' || return $?
        choice="$PE_SELECTION"
        case "$choice" in
            stop) return 3 ;;
            manual)
                IFS= read -r "candidate?$(jobs_prompt_render 'Node 可执行文件绝对路径（空输入取消）：')" || return 130
                [[ -n "$candidate" ]] || return 130
                [[ "$candidate" == /* ]] || return 2
                pt_probe_node "$candidate" "$directory" && return 0 ;;
            install)
                (( ! attempted )) || { pe_log '✖ 本轮安装后仍不满足约束，请选择已有精确版本；未改工程声明。'; return 3; }
                attempted=1
                if [[ "$PT_NODE_PIN" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
                    pt_install_node_exact "$PT_NODE_PIN" || return $?
                    return 0
                fi
                requested="$(print -r -- "${PT_NODE_PIN:-$PT_NODE_RANGE}" | /usr/bin/perl -ne 'print $1 if /(?:^|[>=~^ ]+)(\d+)/')"
                [[ -z "$requested" ]] || formula="node@$requested"
                pe_log "来源：https://formulae.brew.sh/formula/$formula；自动准备必需Node与npm，精确补丁仍以复检为准，Ctrl+C结束。"
                if ! pj_find_brew; then
                    source "$(jobs_layout_file "$PE_TOOLS_DIR/SetupHomebrew.zsh")" || return $?
                    pe_prepare_homebrew || return $?
                fi
                pt_load_sdk_retry || return $?
                SF_COMMAND_TIMEOUT=1800 JOBS_SDK_LOG_REPLACED=1 jobs_sdk_retry 'Node.js runtime' "$PE_RUN_DIR/toolchain-node-install.log" sf_run_diagnostic toolchain-node-install /usr/bin/env HOMEBREW_NO_AUTO_UPDATE=1 "$PJ_BREW" install "$formula" || return $?
                prefix="$(HOMEBREW_NO_AUTO_UPDATE=1 "$PJ_BREW" --prefix "$formula")" || return 1
                pt_probe_node "$prefix/bin/node" "$directory" && return 0 ;;
            *) return 2 ;;
        esac
    done
}
# packageManager 指定的精确版本优先；没有精确声明时只复用健康现有工具，不擅自安装最新版。
pt_prepare_web_toolchain() {
    local directory="$1" lock="$2" manager="" required="" version="" candidate="" prefix="" npm="" package=""
    local SF_COMMAND_DIRECTORY="$directory"
    pt_read_node_requirements "$directory" && pt_prepare_node "$directory" || return $?
    case "$lock" in package-lock.json|npm-shrinkwrap.json) manager=npm ;; pnpm-lock.yaml) manager=pnpm ;; yarn.lock) manager=yarn ;; *) return 2 ;; esac
    if [[ -n "$PT_MANAGER_PIN" ]]; then
        [[ "$PT_MANAGER_PIN" =~ '^(npm|pnpm|yarn)@([0-9]+\.[0-9]+\.[0-9]+)(\+sha[0-9]+\.[A-Za-z0-9+/=]+)?$' ]] || { pe_log '✖ packageManager 必须明确声明受支持包管理器的精确版本。'; return 3; }
        [[ "${match[1]}" == "$manager" ]] || { pe_log '✖ packageManager 与锁文件不一致，未安装。'; return 3; }
        required="${match[2]}"
    fi
    candidate="$(command -v "$manager" 2>/dev/null)"
    if [[ -x "$candidate" ]] && SF_COMMAND_TIMEOUT=30 sf_run_diagnostic "toolchain-$manager" "$candidate" --version; then
        version="$(pe_semantic_version "$PE_RUN_DIR/toolchain-$manager.log")"
        if [[ -n "$version" && ( -z "$required" || "$version" == "$required" ) ]]; then PT_PACKAGE_MANAGER="$candidate"; return 0; fi
    fi
    [[ -n "$required" ]] || { pe_log "✖ 没有健康 $manager 且工程未锁定其版本；请在 package.json 的 packageManager 声明确切版本后重试。"; return 3; }
    prefix="$HOME/Library/Application Support/JobsFlutterTools/package-managers/$manager/$required"
    pt_check_directory_chain "$prefix" && pt_check_directory_chain "$prefix/node_modules/.bin" || return 2
    candidate="$prefix/node_modules/.bin/$manager"
    if [[ -x "$candidate" ]] && SF_COMMAND_TIMEOUT=30 sf_run_diagnostic "toolchain-$manager" "$candidate" --version &&
       [[ "$(pe_semantic_version "$PE_RUN_DIR/toolchain-$manager.log")" == "$required" ]]; then
        PT_PACKAGE_MANAGER="$candidate"; export PATH="${candidate:h}:$PATH"; rehash; return 0
    fi
    package="$manager"
    if [[ "$manager" == yarn && "${required%%.*}" -ge 2 ]]; then package='@yarnpkg/cli-dist'; fi
    pe_log "来源：https://registry.npmjs.org/$package；版本：$required；自动准备到$prefix（用户独立版本目录，不改全局npm）；Ctrl+C结束。"
    [[ "$PT_MANAGER_PIN" != *+sha* ]] || pe_log '➤ 本流程核对包管理器精确版本；声明中的 Corepack hash 由 Corepack 管理，npm 安装使用 registry integrity，不声称已验证该 Corepack hash。'
    npm="$(command -v npm)"
    pt_load_sdk_retry || return $?
    SF_COMMAND_TIMEOUT=1800 JOBS_SDK_LOG_REPLACED=1 jobs_sdk_retry "固定版本${manager}工具" "$PE_RUN_DIR/toolchain-$manager-install.log" sf_run_diagnostic "toolchain-$manager-install" "$npm" install --prefix "$prefix" --no-save --package-lock=false --registry=https://registry.npmjs.org "$package@$required" || return $?
    SF_COMMAND_TIMEOUT=30 sf_run_diagnostic "toolchain-$manager" "$candidate" --version || return $?
    [[ "$(pe_semantic_version "$PE_RUN_DIR/toolchain-$manager.log")" == "$required" ]] || { pe_log '✖ 包管理器安装后版本不匹配，已停止。'; return 3; }
    PT_PACKAGE_MANAGER="$candidate"
    export PATH="${candidate:h}:$PATH"
    rehash
}
# 发现 Studio / 官方 CLT 解压目录；多个候选明确选择，不依赖 Finder 继承交互 Shell PATH。
pt_find_ohos_root() {
    setopt localoptions NO_NOMATCH
    local candidate="${DEVECO_STUDIO_HOME:-${TOOL_HOME:-}}" rows="" location=""
    if [[ -n "$candidate" ]]; then
        [[ ! -d "$candidate/Contents" ]] || candidate="$candidate/Contents"
        [[ -d "$candidate" && ! -L "$candidate" ]] || return 3
        PT_OHOS_ROOT="${candidate:A}"; return 0
    fi
    for location in /Applications/DevEco*.app/Contents(N/) "$HOME"/Applications/DevEco*.app/Contents(N/) \
        "$HOME/Library/Application Support/JobsHarmonySimulator"/clt-*(N/); do
        [[ -d "$location/sdk" ]] || continue
        [[ -z "$rows" ]] || rows+=$'\n'
        rows+="$location"$'\t'"$location"
    done
    [[ -n "$rows" ]] || return 3
    if [[ "$rows" == *$'\n'* ]]; then pe_select 'DevEco / CLT 工具链' "$rows" || return $?; PT_OHOS_ROOT="$PE_SELECTION";
    else PT_OHOS_ROOT="${rows%%$'\t'*}"; fi
}
# 只激活所选目录；Harmony SDK 根与独立 OpenHarmony SDK 根分别校验，不互相冒充。
pt_activate_ohos_root() {
    local root="$PT_OHOS_ROOT" sdk="${DEVECO_SDK_HOME:-${HOS_SDK_HOME:-$PT_OHOS_ROOT/sdk}}" ohos="${OHOS_SDK_HOME:-}" item="" candidate=""
    [[ -d "$sdk" ]] || { pe_log "✖ Harmony SDK 目录不可用：$sdk"; return 3; }
    [[ -n "$ohos" ]] || ohos="$sdk/default/openharmony"
    for item in ets native toolchains; do
        [[ -d "$ohos/$item" ]] || { pe_log "✖ OpenHarmony SDK 缺少 $item：$ohos；请在 DevEco SDK Manager 安装当前工程要求的 SDK。"; return 3; }
    done
    export TOOL_HOME="$root" DEVECO_SDK_HOME="$sdk" OHOS_SDK_HOME="$ohos"
    for item in "$root/node/bin" "$root/node" "$root/tools/node/bin" "$root/tools/node" "$root/tool/node/bin" \
        "$root/ohpm/bin" "$root/tools/ohpm/bin" "$root/hvigor/bin" "$root/tools/hvigor/bin" "$ohos/toolchains"; do
        [[ ! -d "$item" || ":$PATH:" == *":$item:"* ]] || export PATH="$item:$PATH"
    done
    if [[ -z "${SF_JAVA_HOME:-${JAVA_HOME:-}}" ]]; then
        for candidate in "$root/jbr/Contents/Home" "$root/jbr"; do
            [[ -x "$candidate/bin/java" ]] || continue
            SF_JAVA_HOME="$candidate"; export JAVA_HOME="$candidate" PATH="$candidate/bin:$PATH"; break
        done
    fi
    rehash
    PT_OHPM="$(command -v ohpm 2>/dev/null)" PT_HVIGOR="$SF_PROJECT/ohos/hvigorw"
    [[ -f "$PT_HVIGOR" && ! -L "$PT_HVIGOR" ]] || PT_HVIGOR="$(command -v hvigorw 2>/dev/null)"
    local node="$(command -v node 2>/dev/null)" hdc="$(command -v hdc 2>/dev/null)" java="${SF_JAVA_HOME:-${JAVA_HOME:-}}/bin/java"
    [[ -x "$node" && -x "$PT_OHPM" && -f "$PT_HVIGOR" && -x "$hdc" && -x "$java" ]] || { pe_log '✖ 所选 DevEco / CLT 缺少 Node、OHPM、Hvigor、HDC 或 Java；可重新选择完整工具目录。'; return 3; }
    SF_COMMAND_TIMEOUT=30 sf_run_diagnostic ohos-node "$node" --version &&
        SF_COMMAND_TIMEOUT=30 sf_run_diagnostic ohpm-version "$PT_OHPM" --version &&
        SF_COMMAND_TIMEOUT=60 SF_COMMAND_DIRECTORY="$SF_PROJECT/ohos" sf_run_diagnostic hvigor-version /bin/sh "$PT_HVIGOR" --version &&
        SF_COMMAND_TIMEOUT=30 sf_run_diagnostic hdc-version "$hdc" -v &&
        SF_COMMAND_TIMEOUT=30 sf_run_diagnostic ohos-java "$java" -version || return $?
    SF_COMMAND_TIMEOUT=60 sf_run_diagnostic ohos-sdk "$SF_FLUTTER" build hap --help || { pe_log '✖ 当前 Flutter 不具备 Harmony HAP 构建能力，未改用官方 Flutter 冒充。'; return 3; }
    pe_log "✔ DevEco / OpenHarmony 工具链已激活并复检：$root；SDK：$ohos。"
}
# 失败选择不污染下一次工具链发现；用户显式 SDK 与已有 Java 原值一并恢复。
pt_try_ohos_root() {
    local name="" result=0
    local -A values presence
    for name in PATH TOOL_HOME DEVECO_SDK_HOME OHOS_SDK_HOME JAVA_HOME SF_JAVA_HOME; do
        presence[$name]="${+parameters[$name]}"
        values[$name]="${(P)name}"
    done
    pt_activate_ohos_root || result=$?
    (( result != 0 )) || return 0
    for name in PATH TOOL_HOME DEVECO_SDK_HOME OHOS_SDK_HOME JAVA_HOME SF_JAVA_HOME; do
        if [[ "${presence[$name]}" == 1 ]]; then export "$name=${values[$name]}"; else unset "$name"; fi
    done
    rehash
    pe_log "⚠ 当前鸿蒙工具链未通过（退出码 $result），已恢复本次选择前环境。"
    return "$result"
}
# 专有 SDK 的安装与许可保留官方界面；完成后在原流程重新选择目录并复检，无需重启终端。
pt_prepare_ohos_toolchain() {
    local result=0 candidate="" choice=""
    PT_OHOS_ROOT=""
    pt_find_ohos_root && pt_try_ohos_root && return 0
    while true; do
        pe_select '鸿蒙工具链准备' $'stop\t取消本次准备\nmanual\t选择已有 DevEco / 官方 CLT 完整目录并复检\nofficial\t打开华为官方下载 / SDK Manager，完成安装后复检' || return $?
        choice="$PE_SELECTION"
        case "$choice" in
            stop) return 3 ;;
            official)
                pe_log '📥 来源：https://developer.huawei.com/consumer/cn/download/；请本人安装 DevEco / CLT 并在 SDK Manager 完成工程要求组件与许可。'
                /usr/bin/open 'https://developer.huawei.com/consumer/cn/download/' || return $?
                IFS= read -r "candidate?$(jobs_prompt_render '安装与许可完成后按回车复检；Ctrl+C 取消：')" || return 130
                pt_find_ohos_root && pt_try_ohos_root && return 0 ;;
            manual)
                IFS= read -r "candidate?$(jobs_prompt_render 'DevEco.app 或 CLT 目录绝对路径（空输入取消）：')" || return 130
                [[ -n "$candidate" ]] || return 130
                [[ "$candidate" == /* && -d "$candidate" && ! -L "$candidate" ]] || { pe_log '✖ 目录不存在或不是普通绝对路径。'; continue; }
                [[ ! -d "$candidate/Contents" ]] || candidate="$candidate/Contents"
                PT_OHOS_ROOT="${candidate:A}"
                pt_try_ohos_root && return 0 ;;
            *) return 2 ;;
        esac
    done
}
# 已有缓存先逐项核对后只补缺失文件；冲突时整批停止，不覆盖来源或目标。
pt_merge_spm_cache() {
    /usr/bin/perl -MFile::Find -MFile::Copy -MFile::Path=make_path -MFile::Spec -MFile::Basename=dirname -MDigest::SHA -MCwd=abs_path -MFcntl=:DEFAULT -e '
        use strict; use warnings;
        my($src,$dst)=@ARGV; my @entries; my %parents;
        sub identity { my @s=lstat($_[0]); return @s ? join(":",@s[0,1,2,7,9]) : "absent"; }
        sub digest { open my $f,"<",$_[0] or die $!; binmode $f; return Digest::SHA->new(256)->addfile($f)->hexdigest; }
        sub check_parents {
            my $path=shift;
            while($path ne "/") {
                die "SPM linked/non-directory parent: $path\n" if -l $path || (-e $path && !-d $path);
                if(-d $path) {
                    my @s=lstat($path); my $id=join(":",@s[0,1,2]);
                    die "SPM changed parent: $path\n" if exists($parents{$path}) && $parents{$path} ne $id;
                    $parents{$path}=$id;
                }
                $path=dirname($path);
            }
        }
        check_parents($src); check_parents($dst);
        find({no_chdir=>1,wanted=>sub {
            return if $File::Find::name eq $src;
            my $p=$File::Find::name; my $r=substr($p,length($src)+1); my $t="$dst/$r";
            check_parents(dirname($p)); check_parents(dirname($t));
            my $hash=""; my $link="";
            if(-l $p) {
                $link=readlink($p);
                die "SPM absolute link: $r\n" if File::Spec->file_name_is_absolute($link);
                my $resolved=abs_path($p);
                die "SPM link escapes cache: $r\n" unless defined($resolved) && ($resolved eq $src || index($resolved,"$src/")==0);
                die "SPM link conflict: $r\n" if (-e $t || -l $t) && (!-l $t || readlink($t) ne $link);
            } elsif(-d $p) {
                die "SPM directory conflict: $r\n" if -l $t || (-e $t && !-d $t);
            } elsif(-f $p) {
                $hash=digest($p);
                die "SPM file conflict: $r\n" if -l $t || (-e $t && (!-f $t || digest($t) ne $hash));
            } else { die "SPM special file: $r\n"; }
            push @entries,[$p,$t,identity($p),identity($t),$hash,$link];
        }},$src);
        for my $e (@entries) {
            my($p,$t,$before,$target_before,$hash,$link)=@$e;
            check_parents(dirname($p)); check_parents(dirname($t));
            die "SPM source changed: $p\n" unless identity($p) eq $before;
            die "SPM target changed: $t\n" unless identity($t) eq $target_before;
            die "SPM source content changed: $p\n" if length($hash) && digest($p) ne $hash;
        }
        for my $e (@entries) {
            my($p,$t,$before,$target_before,$hash,$link)=@$e;
            check_parents(dirname($p)); check_parents(dirname($t));
            die "SPM source changed: $p\n" unless identity($p) eq $before;
            next if $target_before ne "absent";
            die "SPM target appeared: $t\n" if -e $t || -l $t;
            make_path(dirname($t)); check_parents(dirname($t));
            if(length($link)) { symlink($link,$t) or die $!; }
            elsif(-d $p) { make_path($t); }
            else {
                sysopen my $out,$t,O_WRONLY|O_CREAT|O_EXCL,0600 or die $!;
                binmode $out; copy($p,$out) or die $!; close $out or die $!;
                chmod((stat($p))[2]&0777,$t) or die $!;
                die "SPM copy verification failed: $t\n" unless digest($t) eq $hash;
            }
            check_parents(dirname($t));
        }
    ' "$1" "$2"
}
# Flutter 新版明确指定 build/<platform>/SourcePackages；旧版通过当前 Xcode 构建设置定位 DerivedData。
pt_spm_cache_path() {
    local sdk="${SF_FLUTTER_ROOT:-${SF_FLUTTER:A:h:h}}" source="" build_dir=build value="" option=-project scheme="" index=0 arg=""
    source="$sdk/packages/flutter_tools/lib/src/ios/xcodeproj.dart"
    if [[ -f "$source" ]] && /usr/bin/grep -q 'clonedSourcePackagesDirPath' "$source" && /usr/bin/grep -q 'kSwiftPackageCacheDirectoryName' "$source"; then
        SF_COMMAND_TIMEOUT=60 sf_run_diagnostic spm-flutter-config "$SF_FLUTTER" config --machine || return $?
        /usr/bin/plutil -convert xml1 -o /dev/null "$PE_RUN_DIR/spm-flutter-config.log" >/dev/null 2>&1 || { pe_log '✖ 无法读取当前 Flutter build-dir，未猜测缓存位置。'; return 3; }
        value="$(/usr/bin/plutil -extract build-dir raw -o - "$PE_RUN_DIR/spm-flutter-config.log" 2>/dev/null)"
        [[ -z "$value" ]] || build_dir="$value"
        [[ "$build_dir" != /* && "$build_dir" != *$'\n'* && "$build_dir" != *$'\r'* && "$build_dir" != *'..'* ]] || return 2
        PD_SPM_BUILD_CACHE="$SF_PROJECT/$build_dir/$SR_TARGET/SourcePackages"
    else
        [[ "$PD_XCODE_CONTAINER" != *.xcworkspace ]] || option=-workspace
        for (( index=1; index<=${#SR_ARGS}; index++ )); do
            arg="${SR_ARGS[index]}"
            [[ "$arg" != --flavor ]] || { (( index++ )); scheme="${SR_ARGS[index]}"; }
            [[ "$arg" != --flavor=* ]] || scheme="${arg#*=}"
        done
        local -a args=(-showBuildSettings "$option" "$PD_XCODE_CONTAINER")
        [[ -z "$scheme" ]] || args+=(-scheme "$scheme")
        SF_COMMAND_TIMEOUT=120 sf_run_diagnostic spm-xcode-build-settings /usr/bin/xcodebuild "${args[@]}" || return $?
        value="$(/usr/bin/sed -nE 's/^[[:space:]]*OBJROOT = (.*)\/Build\/Intermediates.noindex$/\1/p' "$PE_RUN_DIR/spm-xcode-build-settings.log" | /usr/bin/sort -u)"
        [[ "$value" == /* && "$value" != *$'\n'* ]] || { pe_log '✖ 旧版 Flutter 的 Xcode 缓存路径不能唯一确认，未冒用新版目录；请核对 workspace / scheme 的 DerivedData 设置。'; return 3; }
        PD_SPM_BUILD_CACHE="$value/SourcePackages"
        pe_log "➤ 旧版 Flutter 使用所选 Xcode 工程的实际 DerivedData 缓存：$PD_SPM_BUILD_CACHE。"
    fi
}
# 将实际构建缓存连接到普通项目快照目录；已有缓存融合后保留原目录备份。
pt_prepare_spm_build_cache() {
    local canonical="$SF_PROJECT/.jobs/dependencies/spm" parent="" relative="" backup=""
    pt_spm_cache_path || return $?
    [[ "$PD_SPM_BUILD_CACHE" != "$canonical" && "$PD_SPM_BUILD_CACHE" != "$canonical/"* && "$canonical" != "$PD_SPM_BUILD_CACHE/"* ]] || return 2
    for parent in "$SF_PROJECT/.jobs" "$SF_PROJECT/.jobs/dependencies" "$canonical"; do
        [[ ! -L "$parent" && ( ! -e "$parent" || -d "$parent" ) ]] || { pe_log "✖ SPM 项目缓存路径身份异常：$parent"; return 2; }
    done
    parent="${PD_SPM_BUILD_CACHE:h}"
    while [[ "$parent" != / ]]; do
        [[ ! -L "$parent" && ( ! -e "$parent" || -d "$parent" ) ]] || { pe_log '✖ 实际 SPM 缓存父目录含链接或非目录，未修改。'; return 2; }
        parent="${parent:h}"
    done
    /bin/mkdir -p "$canonical" "${PD_SPM_BUILD_CACHE:h}" || return $?
    if [[ -L "$PD_SPM_BUILD_CACHE" ]]; then
        [[ "${PD_SPM_BUILD_CACHE:A}" == "${canonical:A}" ]] || { pe_log '✖ 实际 SPM 缓存链接指向其它来源，未改动。'; return 2; }
        return 0
    fi
    if [[ -e "$PD_SPM_BUILD_CACHE" ]]; then
        [[ -d "$PD_SPM_BUILD_CACHE" ]] || return 2
        pt_merge_spm_cache "$canonical" "$PD_SPM_BUILD_CACHE" && pt_merge_spm_cache "$PD_SPM_BUILD_CACHE" "$canonical" || { pe_log '✖ SPM 缓存有冲突，保留两份原内容。'; return 3; }
        backup="${PD_SPM_BUILD_CACHE}.before-jobs-$(/bin/date +%Y%m%d-%H%M%S)-$$"
        [[ ! -e "$backup" && ! -L "$backup" ]] || return 2
        /bin/mv "$PD_SPM_BUILD_CACHE" "$backup" || return $?
        pe_log "➤ 原 SPM 构建缓存已保留：$backup。"
    fi
    relative="$(/usr/bin/perl -MFile::Spec -e 'print File::Spec->abs2rel($ARGV[0],$ARGV[1])' "$canonical" "${PD_SPM_BUILD_CACHE:h}")" || return 1
    /bin/ln -s "$relative" "$PD_SPM_BUILD_CACHE" || { [[ -z "$backup" ]] || /bin/mv "$backup" "$PD_SPM_BUILD_CACHE"; return 1; }
    pe_log "✔ SPM 实际构建缓存已连接项目快照目录：$PD_SPM_BUILD_CACHE → $canonical。"
}
