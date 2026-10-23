#!/bin/zsh
# 脚本自述：
# - 脚本名称：CreateHarmonySimulator.zsh
# - 核心用途：通过华为官方 Emulator CLI，补齐工具和选中的 Release 镜像，新建并按需启动 Harmony 模拟器。
# - 影响范围：写入 DevEco 默认模拟器实例目录；保留已有设备、镜像、代理和系统配置。
# - 运行提示：回车授权缺工具时从 SDL 镜像安装 CLT；缺镜像走官方下载，--check 只读，许可展示后本人回车同意。

HS_BIN=""
HS_LOG=""
HS_CHECK=0
HS_HELP=0
HS_PREPARE=0
HS_START=1
HS_NAME=""
HS_IMAGES=""
HS_INSTANCES=""
HS_TYPE=""
HS_VERSION=""
HS_OFFICIAL_URL="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-command-line"
HS_DOWNLOAD_URL="https://developer.huawei.com/consumer/cn/download/"
HS_CLT_VERSION="6.1.1.280"
HS_CLT_URL="https://libsdl.org/harmonyos-devtools/commandline-tools-mac-arm64-6.1.1.280.zip"
HS_CLT_SIZE=2025336267
# 固定 SDL 镜像快照摘要；不是华为官方公布的校验值。
HS_CLT_SHA256="47d0e558b8285e1452f4d3611863027ec0d1135642761bef23402434e22382d4"
HS_TOOLS_HOME="$HOME/Library/Application Support/JobsHarmonySimulator"
HS_INSTALL_STAGE=""
HS_CAN_BOOTSTRAP=0
HS_LICENSES_CONFIRMED=0
HS_PREFERRED_ROW=""
typeset -a HS_NAMES=()
typeset -a HS_ROWS=()

hs_intro_line() {
  local role="$1" message="$2"
  if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" ]]; then
    if [[ "$role" == title ]]; then
      printf '\033[1;31m%s\033[0m\n' "$message"
    else
      printf '\033[0;34m%s\033[0m\n' "$message"
    fi
  else
    print -r -- "$message"
  fi
}
# 任何运行入口先展示固定说明，帮助和只读检查由后续流程直接分流。
hs_show_intro() {
  hs_intro_line title '━━━━━━━━━━ 新建 Harmony 模拟器 ━━━━━━━━━━'
  hs_intro_line body '1、仅支持 Apple Silicon macOS 与具备 -create / -imageList 的官方 DevEco Emulator（6.1.0 Beta1+）。'
  hs_intro_line body '2、缺系统镜像时自动读取官方清单，回车选择最新稳定版手机镜像并下载；随后创建唯一实例并启动。'
  hs_intro_line body '3、下载或启动前展示工具随附的许可原文，回车表示本人同意；任意非空输入取消。不改代理或 Shell 配置。'
  hs_intro_line body '4、回车授权缺工具时从 SDL 第三方镜像免登录下载 Mac ARM64 CLT（约 2.03 GB），校验后新增独立目录；健康工具不升级。'
  hs_intro_line body '   华为官网下载工具需登录；SDL 替代工具包下载，系统镜像由官方 Emulator 下载（可能数 GB），保留已有设备与镜像。'
  hs_intro_line body '5、交互入口回车继续，q / Ctrl+C 取消；--prepare 仅准备，--check 只读查询，日志在系统临时目录 JobsHarmonySimulator.* 中。'
}

hs_help() {
  print -r -- '用法：CreateHarmonySimulator.zsh [--create | --prepare | --check] [--name 名称] [--no-start] [--help]'
  print -r -- '环境：HARMONY_EMULATOR_BIN 指定官方 Emulator；DEVECO_STUDIO_HOME / TOOL_HOME 指定 DevEco 或 CLT 根目录。'
  print -r -- 'HARMONY_CLT_ARCHIVE 可指定已下载的 SDL 同版本 ZIP；仍检查固定大小与 SHA-256，不接受任意工具包。'
  print -r -- '--check 仅查询 -help、-imageList -downloaded true、-list -details，不创建、启动或下载。'
  print -r -- '--prepare 补齐缺失工具和选中的 Release 系统镜像，复检完成即退出，不创建设备。'
  print -r -- "SDL 替代下载源：$HS_CLT_URL"
  print -r -- "官方说明：$HS_OFFICIAL_URL"
}

hs_error() {
  print -u2 -r -- "✖ $*"
  [[ -z "$HS_LOG" ]] || print -r -- "✖ $*" >> "$HS_LOG"
  return 1
}

hs_log() {
  print -r -- "$*"
  [[ -z "$HS_LOG" ]] || print -r -- "$*" >> "$HS_LOG"
  return 0
}

hs_parse() {
  while (( $# )); do
    case "$1" in
      --help|-h) HS_HELP=1 ;;
      --check) HS_CHECK=1 ;;
      --prepare) HS_PREPARE=1 ;;
      --create) ;;
      --no-start) HS_START=0 ;;
      --name)
        (( $# > 1 )) || { hs_error '--name 缺少名称。'; return 2; }
        HS_NAME="$2"
        shift
        ;;
      *) hs_error "未知参数：$1"; return 2 ;;
    esac
    shift
  done
  (( ! HS_CHECK || ! HS_PREPARE )) || { hs_error '--check 与 --prepare 不能同时使用。'; return 2; }
  [[ -z "$HS_NAME" ]] || hs_valid_name "$HS_NAME" || { hs_error '名称须以英文字母开头，仅含英文字母、数字、空格、下划线或加号；不能以空格结尾，最长 64 字符，不支持连字符 -。'; return 2; }
}

hs_valid_name() {
  local value="$1"
  # 官方 Emulator 拒绝连字符；额外限制首字符、尾空格和长度，使两端一致。
  [[ -n "$value" && ${#value} -le 64 && "$value" == [a-zA-Z]* && "$value" != *[^a-zA-Z0-9_+\ ]* && "$value" != *' ' ]]
}

# 常用 macOS 卷不区分大小写，预检按更保守的名称规则保护既有实例。
hs_name_exists() {
  local requested="$1" existing=""
  shift
  for existing in "$@"; do
    [[ "${existing:l}" != "${requested:l}" ]] || return 0
  done
  return 1
}

hs_check_host() {
  [[ "$(/usr/bin/uname -s)" == Darwin ]] || { hs_error '本入口只支持 macOS。'; return 1; }
  if [[ "$(/usr/bin/uname -m)" != arm64 ]]; then
    if [[ "$(/usr/sbin/sysctl -n sysctl.proc_translated 2>/dev/null)" == 1 ]]; then
      hs_error '当前 Terminal 在 Rosetta 下运行；请关闭“使用 Rosetta 打开”，从 Apple Silicon 原生终端重新运行。'
    else
      hs_error '华为Harmony 本地模拟器仅支持 Apple Silicon（arm64）；Intel Mac 不支持。'
    fi
    return 1
  fi
}

# 显式路径失败即停止，不能静默选到另一套 SDK 或 Android emulator。
hs_find_emulator() {
  HS_CAN_BOOTSTRAP=0
  local requested="${HARMONY_EMULATOR_BIN:-}" root="${DEVECO_STUDIO_HOME:-${TOOL_HOME:-}}" candidate="" directory=""
  local -a candidates=() compatible=()
  if [[ -n "$requested" ]]; then
    [[ -f "$requested" && -x "$requested" ]] || { hs_error "指定 Emulator 不可执行：$requested"; return 1; }
    HS_BIN="${requested:A}"
    hs_log "ℹ 指定工具：$HS_BIN"
    hs_check_capabilities
    return $?
  fi
  if [[ -n "$root" ]]; then
    [[ -d "$root" ]] || { hs_error "指定 DevEco / CLT 目录不存在：$root"; return 1; }
    for candidate in "$root/Contents/tools/emulator/Emulator" "$root/tools/emulator/Emulator" "$root/emulator/Emulator"; do
      [[ ! -f "$candidate" || ! -x "$candidate" ]] || candidates+=("${candidate:A}")
    done
  else
    # macOS 常见卷不区分大小写，PATH 的 Emulator 可能实际是 Android emulator。
    # 收集所有路径并逐个验证能力，不能让首个同名工具遮蔽真正的 DevEco。
    for candidate in /Applications/DevEco*.app/Contents/tools/emulator/Emulator(N) "$HOME"/Applications/DevEco*.app/Contents/tools/emulator/Emulator(N); do
      [[ ! -f "$candidate" || ! -x "$candidate" ]] || candidates+=("${candidate:A}")
    done
    for candidate in "$HS_TOOLS_HOME"/clt-*/emulator/Emulator(N); do
      [[ ! -f "$candidate" || ! -x "$candidate" ]] || candidates+=("${candidate:A}")
    done
    for directory in "${path[@]}"; do
      [[ -n "$directory" ]] || continue
      candidate="$directory/Emulator"
      [[ ! -f "$candidate" || ! -x "$candidate" ]] || candidates+=("${candidate:A}")
    done
  fi
  candidates=("${(@u)candidates}")
  for candidate in "${candidates[@]}"; do
    HS_BIN="$candidate"
    hs_log "ℹ 检查候选工具：$candidate"
    if hs_check_capabilities >/dev/null 2>&1; then
      compatible+=("$candidate")
    else
      hs_log "ℹ 已排除不兼容候选：$candidate"
    fi
  done
  HS_BIN=""
  if (( ${#compatible[@]} == 0 )); then
    [[ -n "$requested$root" ]] || HS_CAN_BOOTSTRAP=1
    hs_error '未找到支持新建 Harmony 模拟器的 DevEco Emulator；Android SDK 的 emulator 不能用于此入口。'
    hs_log '请安装 DevEco Studio 6.1.0 Beta1+，在 Tools → Device Manager → Local Emulator 准备工具与 Release 镜像后重试。'
    hs_log '若已安装到其它位置，可用 HARMONY_EMULATOR_BIN 指定官方 Emulator，或 DEVECO_STUDIO_HOME 指定安装目录。'
    hs_log "官方说明：$HS_OFFICIAL_URL"
    return 1
  fi
  if (( ${#compatible[@]} > 1 )); then
    hs_error "找到 ${#compatible[@]} 个兼容 DevEco Emulator；请用 HARMONY_EMULATOR_BIN 明确指定其中一个。"
    for candidate in "${compatible[@]}"; do hs_log "  $candidate"; done
    return 1
  fi
  HS_BIN="${compatible[1]}"
}

# SDL 包固定版本、大小和快照 SHA-256；先验证再解压，下载内容不会直接执行。
hs_validate_clt_archive() {
  local archive="$1" actual="" listing=""
  actual="$(/usr/bin/stat -f %z "$archive")" || return 1
  [[ "$actual" == "$HS_CLT_SIZE" ]] || { hs_error 'SDL 工具包大小不符，未解压。'; return 1; }
  actual="$(/usr/bin/shasum -a 256 "$archive")" || return 1
  [[ "${actual%% *}" == "$HS_CLT_SHA256" ]] || { hs_error 'SDL 工具包 SHA-256 不符，未解压；请核对下载版本。'; return 1; }
  listing="$(/usr/bin/unzip -Z1 "$archive")" || return 1
  print -r -- "$listing" | /usr/bin/awk '
    !/^(command-line-tools|__MACOSX)\// || /(^|\/)\.\.?(\/|$)/ || /\\/ || /\/\// || /[[:cntrl:]]/ { bad=1 }
    END { exit bad }
  ' || { hs_error 'SDL 工具包包含不安全路径，未解压。'; return 1; }
}

hs_download_clt_archive() {
  local destination="$1"
  /usr/bin/curl -q --fail --show-error --location --progress-bar --retry 3 --connect-timeout 20 \
    --max-time 3600 --speed-limit 1024 --speed-time 90 --max-filesize "$HS_CLT_SIZE" \
    --proto '=https' --proto-redir '=https' --output "$destination" "$HS_CLT_URL" || {
      hs_error "SDL 下载失败；可手动下载同一 ZIP 并用 HARMONY_CLT_ARCHIVE 指定：$HS_CLT_URL"
      return 1
    }
}

hs_publish_clt() {
  /usr/bin/osascript -l JavaScript - "$1" "$2" <<'JXA'
ObjC.import('Foundation');
function run(args) {
  var error = Ref();
  if (!$.NSFileManager.defaultManager.moveItemAtPathToPathError(args[0], args[1], error)) {
    throw Error('CLT 目录发布失败；不会覆盖或嵌入已有目录。');
  }
}
JXA
}

hs_cleanup_install() {
  if [[ -n "$HS_INSTALL_STAGE" && "$HS_INSTALL_STAGE" == "$HS_TOOLS_HOME"/.install.* && -d "$HS_INSTALL_STAGE" && ! -L "$HS_INSTALL_STAGE" ]]; then
    /bin/rm -rf -- "$HS_INSTALL_STAGE"
  fi
  HS_INSTALL_STAGE=""
}

hs_perform_clt_install() {
  local stage="$HS_INSTALL_STAGE" archive="${HARMONY_CLT_ARCHIVE:-}" root="" entry="" destination=""
  hs_log "📥 SDL 第三方免登录镜像：$HS_CLT_URL"
  hs_log "ℹ CLT $HS_CLT_VERSION；$HS_CLT_SIZE 字节；快照 SHA-256：$HS_CLT_SHA256"
  hs_log 'ℹ 该摘要固定 SDL 镜像内容，不代表已比对华为官方摘要；包内不含可启动的系统镜像。'
  if [[ -n "$archive" ]]; then
    [[ -f "$archive" ]] || { hs_error 'HARMONY_CLT_ARCHIVE 指定的文件不存在。'; return 1; }
    hs_log "ℹ 使用本地归档：$archive"
  else
    archive="$stage/tools.zip"
    hs_download_clt_archive "$archive" || return 1
  fi
  hs_validate_clt_archive "$archive" || return 1
  hs_log '✔ 工具包校验通过，正在解压依赖；这一步可能需要几分钟。'
  /bin/mkdir "$stage/extract" || return 1
  # macOS bsdtar 默认拒绝目录穿越及经符号链接写出解压根目录。
  /usr/bin/tar -xf "$archive" -C "$stage/extract" --no-same-owner --no-same-permissions || return 1
  root="$stage/extract/command-line-tools"
  [[ -d "$root" && ! -L "$root" && -x "$root/emulator/Emulator" && ! -L "$root/emulator/Emulator" && -f "$root/version.txt" ]] || {
    hs_error 'SDL 包缺少完整 Emulator 或版本文件，未安装。'; return 1
  }
  for entry in "$root"/**/*(ND@); do
    [[ "${entry:A}" == "${root:A}"/* ]] || { hs_error '工具包存在指向安装目录外的符号链接，未安装。'; return 1; }
  done
  HS_BIN="$root/emulator/Emulator"
  hs_check_capabilities || { HS_BIN=""; return 1; }
  destination="$HS_TOOLS_HOME/clt-$HS_CLT_VERSION-${${stage:t}#.install.}"
  hs_publish_clt "$root" "$destination" || { HS_BIN=""; return 1; }
  HS_BIN="$destination/emulator/Emulator"
  HARMONY_EMULATOR_BIN="$HS_BIN"
  hs_log "✔ SDL 工具依赖已安装并通过能力复检：$destination"
}

hs_install_clt() {
  setopt LOCAL_TRAPS
  local result=0
  trap 'hs_cleanup_install; return 130' INT TERM HUP
  [[ ! -L "$HS_TOOLS_HOME" && ( ! -e "$HS_TOOLS_HOME" || -d "$HS_TOOLS_HOME" ) ]] || { hs_error '工具安装根目录不是普通目录，停止。'; return 1; }
  /bin/mkdir -p "$HS_TOOLS_HOME" || return 1
  HS_INSTALL_STAGE="$(umask 077; /usr/bin/mktemp -d "$HS_TOOLS_HOME/.install.XXXXXX")" || return 1
  hs_perform_clt_install || result=$?
  hs_cleanup_install
  return "$result"
}

# 将用户选择保留在本次进程；路径只作为参数，不执行 shell 展开或命令。
hs_read_tool_location() {
  local location=""
  IFS= read -r 'location?粘贴 DevEco .app / CLT 目录或 Emulator 文件路径（回车返回）：' || return 130
  [[ -n "$location" ]] || return 0
  location="${(Q)location}"
  [[ "$location" != '~/'* ]] || location="$HOME/${location#\~/}"
  [[ "$location" == /* && "$location" != *[[:cntrl:]]* ]] || { hs_error '请输入现有的绝对路径；不会执行路径中的命令。'; return 1; }
  if [[ -d "$location" ]]; then
    HARMONY_EMULATOR_BIN=""
    DEVECO_STUDIO_HOME="$location"
    TOOL_HOME=""
  elif [[ -f "$location" && -x "$location" ]]; then
    HARMONY_EMULATOR_BIN="$location"
  else
    hs_error "路径不存在或不是可用工具：$location"
    return 1
  fi
}

# 显式工具路径有误时保留手动恢复入口；正常缺镜像直接走官方下载。
hs_preparation_prompt() {
  local answer="" result=0
  while true; do
    hs_log '━━━━━━━━━━ Harmony 环境准备 ━━━━━━━━━━'
    hs_log '尚未具备可用工具。SDL 可免登录下载 CLT；华为官方下载中心需要账号登录。'
    hs_log '1、从 SDL 镜像安装 Mac ARM64 CLT 6.1.1.280（约 2.03 GB）'
    hs_log '3、打开华为官方下载页（备选）'
    hs_log '2、指定已经安装 / 解压的 DevEco .app、CLT 目录或 Emulator 文件'
    hs_log '回车：准备完成，重新检查并继续；q：取消本次操作。'
    IFS= read -r 'answer?选择：' || return 130
    case "$answer" in
      '') return 0 ;;
      q|Q|$'\e') return 130 ;;
      1)
        hs_install_clt || return $?
        return 0
        ;;
      3)
        /usr/bin/open "$HS_DOWNLOAD_URL" || hs_log "⚠ 自动打开失败，请访问：$HS_DOWNLOAD_URL"
        hs_log 'ℹ 终端保留在此；完成准备后回车复检。'
        ;;
      2)
        result=0
        hs_read_tool_location || result=$?
        (( result != 130 )) || return 130
        (( result != 0 )) || return 0
        ;;
      *) hs_log '请输入对应编号，或回车复检；q 取消。' ;;
    esac
  done
}

hs_prepare_environment() {
  local result=0
  while true; do
    result=0
    hs_find_emulator || result=$?
    if (( result != 0 )); then
      (( ! HS_CHECK )) || return "$result"
      if (( HS_CAN_BOOTSTRAP )); then
        hs_install_clt || return $?
        continue
      fi
      hs_preparation_prompt tools || return $?
      continue
    fi
    hs_log "ℹ 已确认官方兼容工具能力：$HS_BIN"
    hs_query_state || return $?
    # --check 如实报告数量；只有交互创建 / 准备需要等待镜像就绪。
    (( ! HS_CHECK )) || return 0
    (( ${#HS_ROWS[@]} == 0 )) || return 0
    hs_install_image
    return $?
  done
}

# 已展示原文并取得本次明确同意后，才调用官方接受命令；不在首屏隐含接受协议。
hs_review_licenses() {
  (( ! HS_LICENSES_CONFIRMED )) || return 0
  local directory="${HS_BIN:h}/agreement" file="" answer=""
  local -a files=("$directory/HarmonyOS_SDK_Agreement.txt" "$directory/HarmonyOS_Software_Service_Agreement.txt")
  for file in "${files[@]}"; do
    [[ -s "$file" && -r "$file" ]] || { hs_error "找不到可供阅读的官方许可：$file；未接受许可。"; return 1; }
  done
  for file in "${files[@]}"; do
    hs_log "━━━━━━━━━━ 官方许可原文：$file ━━━━━━━━━━"
    /bin/cat "$file" || return $?
    print
  done
  IFS= read -r 'answer?阅读以上全部协议后，回车表示本人同意并继续；任意非空输入取消：' || return 130
  [[ -z "$answer" ]] || return 130
  hs_run_command -license accept || return $?
  HS_LICENSES_CONFIRMED=1
}

hs_install_image() {
  local catalog="" parsed="" selected="" type="" version="" answer="" row="" found=0 result=0
  local -a available=()
  hs_log 'ℹ 没有本地 Release 镜像，正在读取官方可下载清单（最长 60 秒）…'
  catalog="$(hs_query_output -imageList -downloaded false)" || return $?
  parsed="$(hs_json available "$catalog")" || { hs_error '官方可下载镜像清单解析失败，未下载或创建。'; return 1; }
  [[ -n "$parsed" ]] || { hs_error '官方没有返回可下载的 Release 镜像，请在 DevEco Device Manager 核对网络或账号要求。'; return 1; }
  available=("${(@f)parsed}")
  selected="$(hs_choose '下载系统镜像（默认最新稳定版手机；可能数 GB）' "${available[@]}")" || return $?
  (( ${available[(Ie)$selected]} )) || { hs_error '选择器返回了无效下载镜像。'; return 2; }
  type="${selected%%$'\t'*}"
  version="${${selected#*$'\t'}%%$'\t'*}"
  hs_log "📥 官方 Emulator 下载：$type / $version；目录沿用 DevEco 既有配置。"
  IFS= read -r 'answer?回车下载此镜像；任意非空输入取消：' || return 130
  [[ -z "$answer" ]] || return 130
  hs_review_licenses || return $?
  # 只在用户确认的新镜像安装中跳过重复确认；创建、启动均不使用 -force。
  hs_run_command -install -deviceType "$type" -osVersion "$version" -force || result=$?
  if (( result != 0 )); then
    hs_log '下载未完成。请查看上方官方网络、地区或账号错误；不会循环重试或修改地区配置。'
    return "$result"
  fi
  hs_query_state || return $?
  for row in "${HS_ROWS[@]}"; do
    if [[ "${row%%$'\t'*}" == "$type" && "${${row#*$'\t'}%%$'\t'*}" == "$version" ]]; then
      HS_PREFERRED_ROW="$row"
      found=1
      break
    fi
  done
  (( found )) || { hs_error '官方安装命令返回，但选中镜像仍未下载就绪；请查看上方许可、网络或账号提示。未创建，不循环复检。'; return 1; }
  hs_log "✔ 已验证下载镜像：$type / $version"
}

# 只对 -help 只读探测设限；创建和启动保留官方交互，不施加该超时。
hs_probe_help() {
  local child_pid watchdog_pid result=0
  "$HS_BIN" -help &
  child_pid=$!
  ( /bin/sleep 15; kill -TERM "$child_pid" 2>/dev/null; /bin/sleep 1; kill -KILL "$child_pid" 2>/dev/null ) >/dev/null 2>&1 &
  watchdog_pid=$!
  wait "$child_pid" 2>/dev/null || result=$?
  kill -TERM "$watchdog_pid" 2>/dev/null
  wait "$watchdog_pid" 2>/dev/null
  (( result < 128 )) || print -u2 -r -- 'Emulator -help 超时或被终止（15 秒）。'
  return "$result"
}

hs_check_capabilities() {
  local help_text="" result=0
  help_text="$(hs_probe_help 2>&1)" || result=$?
  (( result == 0 )) || { hs_error "Emulator -help 失败，退出码 $result：$help_text"; return "$result"; }
  print -r -- "$help_text" | /usr/bin/grep -Eqi -- '(^|[^[:alnum:]_-])-create([^[:alnum:]_-]|$)' &&
    print -r -- "$help_text" | /usr/bin/grep -Eqi -- '(^|[^[:alnum:]_-])-imageList([^[:alnum:]_-]|$)' || {
      hs_error '当前工具未同时提供 -create 与 -imageList；请准备 DevEco Studio 6.1.0 Beta1+，不能用 Android emulator 替代。'
      return 1
    }
}

# 只解析官方 JSON 字段，拒绝畸形、控制字符和混入的日志；输入从不作为代码执行。
hs_json() {
  (( ${#2} <= 100000 )) || { hs_error 'CLI JSON 超过 100 KB，请在 DevEco Device Manager 检查。'; return 1; }
  /usr/bin/osascript -l JavaScript - "$@" <<'JAVASCRIPT'
ObjC.import('Foundation');
function run(argv) {
  var mode = argv[0], records = JSON.parse(argv[1]);
  if (mode !== 'images' && mode !== 'available' && records && !Array.isArray(records) && typeof records === 'object' && typeof records.name === 'string') records = [records];
  if (!Array.isArray(records)) throw new Error('Expected official JSON array for ' + mode);
  function text(value, field) {
    if (typeof value !== 'string' || !value || /[\u0000-\u001f\u007f-\u009f]/.test(value)) throw new Error('Invalid ' + field);
    return value;
  }
  var output = [], seen = Object.create(null);
  records.forEach(function(item) {
    if (!item || typeof item !== 'object' || Array.isArray(item)) throw new Error('Invalid record');
    var line;
    if (mode === 'images' || mode === 'available') {
      var type = text(item.deviceType, 'deviceType'), os = text(item.osVersion, 'osVersion');
      if (os.charAt(0) === '-') throw new Error('Invalid osVersion option');
      var software = text(item.SoftWareVersion, 'SoftWareVersion'), release = text(item.releaseType, 'releaseType');
      if (item.downloaded !== true && item.downloaded !== false && item.downloaded !== 'true' && item.downloaded !== 'false') throw new Error('Invalid downloaded');
      if (String(item.downloaded) !== (mode === 'images' ? 'true' : 'false') || release.toLowerCase() !== 'release') return;
      if (!/^(?:[A-Za-z][A-Za-z0-9_-]*|2in1(?: Foldable)?)$/i.test(type)) throw new Error('Invalid deviceType');
      line = type + '\t' + os + '\t' + software;
    } else if (mode === 'names') {
      line = text(item.name, 'name');
    } else if (mode === 'instancePath') {
      if (text(item.name, 'name') !== argv[2]) return;
      line = text(item.instancePath, 'instancePath');
    } else if (mode === 'verify') {
      var name = text(item.name, 'name');
      if (name !== argv[2]) return;
      if (text(item.deviceType, 'deviceType').toLowerCase() !== argv[3].toLowerCase()) throw new Error('Created deviceType differs');
      var flatVersion = item['os.osVersion'], nestedVersion = item.os && item.os.osVersion;
      if (flatVersion !== undefined && nestedVersion !== undefined && flatVersion !== nestedVersion) throw new Error('Conflicting os.osVersion representations');
      if (text(flatVersion !== undefined ? flatVersion : nestedVersion, 'os.osVersion') !== argv[4]) throw new Error('Created osVersion differs');
      line = name;
    } else throw new Error('Unknown mode');
    if (seen[line] && mode !== 'images' && mode !== 'available') throw new Error('Duplicate instance name');
    if (!seen[line]) output.push(line);
    seen[line] = true;
  });
  if ((mode === 'verify' || mode === 'instancePath') && output.length !== 1) throw new Error('Created instance not uniquely listed');
  if (mode === 'images' || mode === 'available') output.sort(function(a, b) {
    var left = a.split('\t'), right = b.split('\t');
    var phone = Number(right[0].toLowerCase() === 'phone') - Number(left[0].toLowerCase() === 'phone');
    if (phone) return phone;
    if (left[0] !== right[0]) return left[0].localeCompare(right[0]);
    var av = left[1].match(/\d+/g) || [], bv = right[1].match(/\d+/g) || [];
    for (var i = 0; i < Math.max(av.length, bv.length); i++) {
      var delta = Number(bv[i] || 0) - Number(av[i] || 0);
      if (delta) return delta;
    }
    return a.localeCompare(b);
  });
  return output.join('\n');
}
JAVASCRIPT
}

hs_query_state() {
  local result=0 parsed=""
  HS_IMAGES="$(hs_query_output -imageList -downloaded true)" || result=$?
  (( result == 0 )) || { hs_error "Emulator -imageList 失败，退出码 $result。"; return "$result"; }
  parsed="$(hs_json images "$HS_IMAGES")" || { hs_error '镜像 JSON 无法按官方字段解析，未创建模拟器。'; return 1; }
  HS_ROWS=("${(@f)parsed}")
  [[ -n "$parsed" ]] || HS_ROWS=()
  result=0
  HS_INSTANCES="$(hs_query_output -list -details)" || result=$?
  (( result == 0 )) || { hs_error "Emulator -list -details 失败，退出码 $result。"; return "$result"; }
  parsed="$(hs_json names "$HS_INSTANCES")" || { hs_error '实例 JSON 无法按官方字段解析，停止以保护已有设备。'; return 1; }
  HS_NAMES=("${(@f)parsed}")
  [[ -n "$parsed" ]] || HS_NAMES=()
  hs_log "ℹ 已下载 Release 镜像：${#HS_ROWS[@]}；已有实例：${#HS_NAMES[@]}。"
}

# 6.1.1.200 实测空清单使用这两种非 JSON 响应；只接受退出码 0 与精确文案。
hs_query_output() {
  local output="" result=0
  output="$(hs_bounded_query "$@" 2>&1)" || result=$?
  if (( result != 0 )); then print -u2 -r -- "$output"; return "$result"; fi
  if [[ "$1" == '-imageList' && "$output" == 'No images matching the criteria were found.' ]]; then
    print -r -- '[]'
  elif [[ "$*" == '-list -details' && "$output" == '[Empty]' ]]; then
    print -r -- '[]'
  else
    print -r -- "$output"
  fi
}

hs_bounded_query() {
  local child_pid watchdog_pid result=0
  "$HS_BIN" "$@" &
  child_pid=$!
  ( /bin/sleep 60; kill -TERM "$child_pid" 2>/dev/null; /bin/sleep 1; kill -KILL "$child_pid" 2>/dev/null ) >/dev/null 2>&1 &
  watchdog_pid=$!
  wait "$child_pid" 2>/dev/null || result=$?
  kill -TERM "$watchdog_pid" 2>/dev/null
  wait "$watchdog_pid" 2>/dev/null
  (( result < 128 )) || print -u2 -r -- 'Emulator 查询超时或被终止（60 秒）。'
  return "$result"
}

hs_choose() {
  local prompt="$1" choice="" answer="" index=1 fzf=""
  shift
  local -a options=("$@")
  (( ${#options[@]} )) || return 1
  fzf="$(command -v fzf 2>/dev/null)" || fzf=""
  if [[ -n "$fzf" && -x "$fzf" ]] && "$fzf" --version >/dev/null 2>&1; then
    print -rl -- "${options[@]}" | /usr/bin/env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_OPTS_FILE -u FZF_DEFAULT_COMMAND \
      "$fzf" --no-multi --layout=reverse --height=14 --border --prompt="$prompt > " --header='回车选首项；Esc / Ctrl+C 取消'
    return $?
  fi
  print -u2 -r -- "$prompt（回车选 1；输入 q 取消）："
  for choice in "${options[@]}"; do
    print -u2 -r -- "$index、$choice"
    index=$((index + 1))
  done
  IFS= read -r answer || return 130
  [[ "$answer" != q && "$answer" != Q ]] || return 130
  [[ -n "$answer" ]] || answer=1
  [[ "$answer" == <-> ]] && (( answer >= 1 && answer <= ${#options[@]} )) || { hs_error '选择编号无效。'; return 2; }
  print -r -- "${options[$answer]}"
}

hs_select_image() {
  local row="" selected="" proposed="" answer="" name_type="" suffix=1
  local -a types=() versions=()
  (( ${#HS_ROWS[@]} )) || {
    hs_error '本地镜像复检为空，无法继续创建；请查看前面的下载诊断。'
    hs_log "官方说明：$HS_OFFICIAL_URL"
    return 1
  }
  if [[ -n "$HS_PREFERRED_ROW" ]]; then
    (( ${HS_ROWS[(Ie)$HS_PREFERRED_ROW]} )) || { hs_error '刚下载的镜像未通过本地复检。'; return 1; }
    HS_TYPE="${HS_PREFERRED_ROW%%$'\t'*}"
    selected="${HS_PREFERRED_ROW#*$'\t'}"
  else
    for row in "${HS_ROWS[@]}"; do types+=("${row%%$'\t'*}"); done
    types=("${(@u)types}")
    HS_TYPE="$(hs_choose '设备类型' "${types[@]}")" || return $?
    (( ${types[(Ie)$HS_TYPE]} )) || { hs_error '选择器返回了无效设备类型。'; return 2; }
    for row in "${HS_ROWS[@]}"; do
      [[ "${row%%$'\t'*}" != "$HS_TYPE" ]] || versions+=("${row#*$'\t'}")
    done
    selected="$(hs_choose '已下载 Release 镜像（系统版本 / 详细版本）' "${versions[@]}")" || return $?
    (( ${versions[(Ie)$selected]} )) || { hs_error '选择器返回了无效镜像。'; return 2; }
  fi
  HS_VERSION="${selected%%$'\t'*}"
  if [[ -z "$HS_NAME" ]]; then
    name_type="${HS_TYPE//[^a-zA-Z0-9]/_}"
    proposed="JobsHarmony_${name_type[1,24]}_$(/bin/date +%Y%m%d_%H%M%S)"
    HS_NAME="$proposed"
    while hs_name_exists "$HS_NAME" "${HS_NAMES[@]}"; do
      HS_NAME="${proposed}_${suffix}"
      suffix=$((suffix + 1))
    done
    print -r -- "ℹ 默认唯一名称：$HS_NAME"
    IFS= read -r 'answer?模拟器名称（回车使用默认）：' || return 130
    [[ -z "$answer" ]] || HS_NAME="$answer"
  fi
  hs_valid_name "$HS_NAME" || { hs_error '名称无效：须以英文字母开头，仅含英文字母、数字、空格、下划线或加号，不能以空格结尾，最长 64 字符，不支持连字符 -。未创建模拟器。'; return 2; }
  if hs_name_exists "$HS_NAME" "${HS_NAMES[@]}"; then
    hs_error "已有同名实例：$HS_NAME；不会覆盖。"
    return 1
  fi
}

hs_initialize_log() {
  local directory=""
  umask 077
  directory="$(/usr/bin/mktemp -d "${${TMPDIR:-/tmp}%/}/JobsHarmonySimulator.XXXXXX")" || return 1
  HS_LOG="$directory/CreateHarmonySimulator.log"
  : > "$HS_LOG" || return 1
  hs_log "ℹ 日志：$HS_LOG"
}

# 保留 stdin 和原始退出码；-force 仅用于本人确认后的镜像安装。
hs_run_command() {
  local result=0
  "$HS_BIN" "$@" 2>&1 | /usr/bin/tee -a "$HS_LOG" || result=$?
  (( result == 0 )) || { hs_error "Emulator $1 失败，退出码 $result；保留现场，不删除实例。"; return "$result"; }
}

# 独立 CLT 的 SDK 与 emulator 同级；官方默认推导沿用 Studio 的 tools/emulator 层级，
# 会少一层。只为本次已核验的新实例补 sdkPath；不改全局配置或既有实例。
hs_bind_created_sdk() {
  local sdk="${HS_BIN:h:h}/sdk" directory="" config="" temporary="" line="" found_name=0 found_sdk=0
  [[ -x "$sdk/default/openharmony/toolchains/hdc" ]] || return 0
  directory="$(hs_json instancePath "$1" "$HS_NAME")" || return 1
  [[ "$directory" == /* && "${directory:t}" == "$HS_NAME" && -d "$directory" && ! -L "$directory" ]] || {
    hs_error '新实例路径无效，未写入 SDK 配置。'; return 1
  }
  config="$directory/config.ini"
  [[ -f "$config" && ! -L "$config" ]] || { hs_error '新实例 config.ini 不存在或是符号链接，未写入 SDK 配置。'; return 1; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" != name=* ]] || { [[ "$line" == "name=$HS_NAME" ]] || return 1; (( found_name += 1 )); }
    if [[ "$line" == sdkPath=?* || "$line" == harmonyos.sdk.path=?* ]]; then found_sdk=1; fi
  done < "$config"
  (( found_name == 1 )) || { hs_error '新实例配置中的名称不一致，未写入 SDK 配置。'; return 1; }
  (( ! found_sdk )) || return 0
  temporary="$(/usr/bin/mktemp "$directory/.jobs-sdk.XXXXXX")" || return 1
  if /bin/cp -p "$config" "$temporary" && /usr/bin/awk '!/^sdkPath=\r?$/ && !/^harmonyos.sdk.path=\r?$/' "$config" > "$temporary" &&
      print -r -- "sdkPath=${sdk:A}" >> "$temporary" && /bin/mv -f "$temporary" "$config"; then
    hs_log "✔ 已为新实例配置 CLT SDK：${sdk:A}"
  else
    /bin/rm -f "$temporary"
    hs_error '写入新实例 SDK 路径失败；保留实例，未启动。'; return 1
  fi
}

hs_create_and_verify() {
  local answer="" result=0 current="" parsed=""
  hs_log "来源：Huawei DevEco Emulator；工具：$HS_BIN"
  hs_log "目标：DevEco 当前默认实例目录；名称：$HS_NAME；设备：$HS_TYPE；镜像：$HS_VERSION"
  IFS= read -r 'answer?回车确认新建；输入任意字符取消：' || return 130
  [[ -z "$answer" ]] || { hs_log '已取消，未创建模拟器。'; return 0; }
  # 确认期间可能有其它进程创建设备，写入前再检查一次命名冲突。
  current="$(hs_query_output -list -details)" || return $?
  parsed="$(hs_json names "$current")" || return 1
  local -a latest_names=("${(@f)parsed}")
  if hs_name_exists "$HS_NAME" "${latest_names[@]}"; then
    hs_error "名称已被其它操作使用：$HS_NAME；停止，不覆盖。"
    return 1
  fi
  hs_run_command -create "$HS_NAME" -deviceType "$HS_TYPE" -osVersion "$HS_VERSION" || return $?
  current="$(hs_query_output -list -details)" || result=$?
  (( result == 0 )) || { hs_error "创建命令已返回，但实例复检失败（退出码 $result），请在 Device Manager 核对。"; return "$result"; }
  hs_json verify "$current" "$HS_NAME" "$HS_TYPE" "$HS_VERSION" >/dev/null || {
    hs_error '创建命令已返回，但未验证到名称、设备类型和系统版本一致的唯一实例；不启动、不删除。'
    return 1
  }
  hs_bind_created_sdk "$current" || return $?
  hs_log "✔ 已验证新建实例：$HS_NAME"
  if (( HS_START )); then
    hs_review_licenses || return $?
    hs_log 'ℹ 即将交给官方启动流程；如官方额外要求账号授权，请按官方提示完成。'
    hs_run_command -start "$HS_NAME" || return $?
    hs_log '✔ 官方启动命令已返回；最终启动状态请查看模拟器窗口与官方输出。'
  fi
}

hs_dispatch() {
  setopt NO_NOMATCH PIPE_FAIL
  hs_parse "$@" || return $?
  if (( HS_HELP )); then hs_help; return 0; fi
  if (( ! HS_CHECK )); then
    [[ -t 0 ]] || { hs_error '请在可交互终端运行；无交互时只能使用 --check / --help。'; return 1; }
    local answer=""
    IFS= read -r 'answer?已了解用途与影响，按回车继续；非空输入 / Ctrl+C 取消：' || return 130
    [[ -z "$answer" ]] || { hs_log '已取消，未安装工具或创建模拟器。'; return 0; }
  fi
  hs_check_host || return $?
  (( HS_CHECK )) || hs_initialize_log || return $?
  local result=0
  hs_prepare_environment || result=$?
  if (( result == 130 )); then
    hs_log '已取消环境准备；未创建模拟器。'
    return 0
  fi
  (( result == 0 )) || return "$result"
  if (( HS_CHECK )); then
    hs_log '✔ 只读检查完成；未创建、启动或下载。'
    return 0
  fi
  if (( HS_PREPARE )); then
    hs_log '✔ 官方工具与已下载 Release 镜像已就绪；--prepare 已完成，未创建或启动模拟器。'
    return 0
  fi
  hs_select_image || return $?
  hs_create_and_verify
}

main() {
  hs_show_intro # 先说明用途、影响、平台要求和取消方式。
  hs_dispatch "$@" # 只读检查或交互选择本地镜像，创建并核验唯一实例。
}

main "$@"
