#!/bin/zsh
# 来源：JobsCommand@Flutter Android SDK / platforms 修复工具；复用已验证的官方工具引导。
# 限定当前项目，使用 FVM；不写 flutter config、Shell 配置或自动同意许可证。
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

setopt NO_NOMATCH PIPE_FAIL
REPAIR_PROJECT="${1:A}"
REPAIR_TOOLS="${0:A:h}"
[[ $# == 1 && -f "$REPAIR_PROJECT/pubspec.yaml" && -d "$REPAIR_PROJECT/android" && -x "$REPAIR_PROJECT/.fvm/flutter_sdk/bin/flutter" ]] || {
  print -u2 '请选择已绑定 FVM 且包含 android/ 的 Flutter 项目。'; exit 1
}
print -r -- '━━━━━━━━━━ 修复 Android SDK / platforms 缺失 ━━━━━━━━━━'
print -r -- "项目：$REPAIR_PROJECT"
jobs_prompt_output print -r -- '回车授权补齐所需 Java、官方命令行工具及 Android 构建组件；许可仍由本人阅读接受。'
print -r -- '只为此项目更新 android/local.properties（先备份），不安装 Flutter、不改全局配置。'
[[ -t 0 ]] || { print -u2 '请在交互终端运行。'; exit 1; }
IFS= read -r "answer?$(jobs_prompt_render '回车继续，任意非空输入取消：')" || exit 130
[[ -z "$answer" ]] || exit 0
source "$REPAIR_TOOLS/AndroidSdkSupport.zsh"
android_prepare_context
ANDROID_SIM_MODE=prepare
android_initialize_runtime || exit $?
# Honor the project's existing SDK location, including escaped spaces, before considering defaults.
config="$REPAIR_PROJECT/android/local.properties"
[[ ! -L "$config" ]] || { android_log '✖ local.properties 是链接，未修改。'; exit 1; }
if [[ -f "$config" ]]; then
  project_sdk="$(/usr/bin/perl -ne 'if (/^\s*sdk\.dir\s*=\s*(.*)$/) { my $v=$1; $v =~ s/\\([\\:=#! ])/$1/g; print $v; exit }' "$config")"
  if [[ -n "$project_sdk" ]]; then
    [[ "$project_sdk" == /* ]] || { android_log '✖ 项目 sdk.dir 不是绝对路径，请先修正。'; exit 1; }
    export ANDROID_HOME="$project_sdk"
  fi
fi
android_configure_network && android_detect_architecture && android_ensure_sdk && android_ensure_java && android_ensure_command_tools || exit $?

REPAIR_FILES=("$REPAIR_PROJECT"/android/app/build.gradle{,.kts}(N))
REPAIR_API=""
if (( ${#REPAIR_FILES} )); then
REPAIR_API="$(/usr/bin/perl -0777 -ne 'if (/compileSdk(?:Version)?\s*(?:=\s*)?(\d+)/) { print $1; exit }' "${REPAIR_FILES[@]}")"
fi
if [[ -z "$REPAIR_API" ]]; then
  REPAIR_FILES=("$REPAIR_PROJECT"/.fvm/flutter_sdk/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt(N) "$REPAIR_PROJECT"/.fvm/flutter_sdk/packages/flutter_tools/gradle/src/main/groovy/flutter.groovy(N))
  if (( ${#REPAIR_FILES} )); then
  REPAIR_API="$(/usr/bin/perl -0777 -ne 'if (/compileSdkVersion\s*=\s*(\d+)/) { print $1; exit }' "${REPAIR_FILES[@]}")"
  fi
fi
catalog="$(jobs_sdk_retry 'Android SDK组件清单' "$LOG_FILE" android_remote_images_once)" || exit $?
if [[ -z "$REPAIR_API" ]]; then
  REPAIR_API="$(print -r -- "$catalog" | /usr/bin/sed -nE 's/^[[:space:]]*platforms;android-([0-9]+)[[:space:]]*\|.*/\1/p' | /usr/bin/sort -nu | /usr/bin/tail -1)"
fi
[[ "$REPAIR_API" == <-> ]] || { android_log '✖ 无法确定项目 compileSdk；未安装猜测的版本。'; exit 1; }
REPAIR_BUILD_TOOLS="$(print -r -- "$catalog" | /usr/bin/sed -nE 's/^[[:space:]]*build-tools;([0-9]+\.[0-9]+\.[0-9]+)[[:space:]]*\|.*/\1/p' | /usr/bin/sort -t. -k1,1n -k2,2n -k3,3n | /usr/bin/tail -1)"
REPAIR_FILES=("$REPAIR_PROJECT"/android/app/build.gradle{,.kts}(N))
if (( ${#REPAIR_FILES} )); then
  pinned_build="$(/usr/bin/perl -0777 -ne 'if (/buildToolsVersion\s*(?:=\s*)?["\x27](\d+\.\d+\.\d+)/) { print $1; exit }' "${REPAIR_FILES[@]}")"
  [[ -z "$pinned_build" ]] || REPAIR_BUILD_TOOLS="$pinned_build"
fi
[[ -n "$REPAIR_BUILD_TOOLS" ]] || { android_log '✖ 未找到稳定版 build-tools。'; exit 1; }
android_log "计划：platform-tools；platforms;android-$REPAIR_API；build-tools;$REPAIR_BUILD_TOOLS"
[[ -x "$ANDROID_SIM_SDK/platform-tools/adb" ]] || android_install_package platform-tools || exit $?
[[ -f "$ANDROID_SIM_SDK/platforms/android-$REPAIR_API/android.jar" ]] || android_install_package "platforms;android-$REPAIR_API" || exit $?
[[ -x "$ANDROID_SIM_SDK/build-tools/$REPAIR_BUILD_TOOLS/aapt2" ]] || android_install_package "build-tools;$REPAIR_BUILD_TOOLS" || exit $?
[[ -f "$ANDROID_SIM_SDK/platforms/android-$REPAIR_API/android.jar" && -x "$ANDROID_SIM_SDK/platform-tools/adb" && -x "$ANDROID_SIM_SDK/build-tools/$REPAIR_BUILD_TOOLS/aapt2" ]] || { android_log '✖ 组件复检失败，保留已安装内容。'; exit 1; }
config="$REPAIR_PROJECT/android/local.properties"
[[ ! -L "$config" && ( ! -e "$config" || -f "$config" ) ]] || { android_log '✖ local.properties 不是普通文件，未改写。'; exit 1; }
backup="$(/usr/bin/mktemp -d "$REPAIR_PROJECT/android/.jobs-sdk-backup.XXXXXX")" || exit 1
if [[ -f "$config" ]]; then /bin/cp -p "$config" "$backup/local.properties" || exit 1; fi
REPAIR_SDK_VALUE="$ANDROID_SIM_SDK" /usr/bin/perl -e '
  use strict; use warnings;
  my $path=shift; my $text="";
  if (-e $path) { open my $in,"<",$path or die $!; local $/; $text=<$in>; close $in; }
  $text =~ s/^sdk\.dir\s*=.*(?:\r?\n|$)//mg;
  my $sdk=$ENV{REPAIR_SDK_VALUE}; $sdk =~ s/([\\:=#! ])/\\$1/g;
  print $text; print "\n" if length($text) && $text !~ /\n$/; print "sdk.dir=$sdk\n";
' "$config" > "$backup/next.properties" || exit 1
/bin/mv "$backup/next.properties" "$config" || exit 1
android_log "✔ Android SDK 与构建组件已验证；项目 sdk.dir 已更新。备份：$backup"
android_log "Flutter 使用项目 FVM：$REPAIR_PROJECT/.fvm/flutter_sdk；可继续运行原生Flutter项目体检。"
