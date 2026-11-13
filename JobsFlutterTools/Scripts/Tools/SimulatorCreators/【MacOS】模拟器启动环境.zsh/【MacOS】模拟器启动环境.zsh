#!/bin/zsh
# Created by Jobs on 2026年11月12日，星期四.
# 供运行器 source：只准备启动已有模拟器所需的宿主工具，不创建业务平台或修改项目依赖。
# 下载沿现有持续重试与官方许可；不会新建、删除、重置或升级既有系统镜像。
typeset -g JOBS_SIM_ENV_PACKAGE="${${(%):-%x}:A:h}"
typeset -g JOBS_SIM_HARMONY_BIN=""
typeset -g ANDROID_RUN_AVD_IDENTITY=""
# 名称之外核验AVD登记文件、实际路径与稳定配置，启动期端口等变化不改变原实例身份。
jobs_sim_android_avd_identity() {
  local root="${ANDROID_AVD_HOME:-${ANDROID_EMULATOR_HOME:-${ANDROID_USER_HOME:-$HOME/.android}}/avd}"
  [[ "$1" =~ '^[A-Za-z0-9_.-]+$' ]] || return 1
  jobs_sim_instance_json avd-identity "$root" "$1"
}
# 对父运行器提供同一套有界查询与日志，长下载沿工具库自己的可取消获取流程。
jobs_sim_query() {
  local stage="$1" seconds="$2"
  shift 2
  run_bounded "$seconds" "$LOG_FILE.simulator-$stage" "$@"
}
# 配置摘要与JSON解析也有总时限，畸形或超大实例清单不会无限阻塞列表。
jobs_sim_instance_json() {
  jobs_sim_query instance-json 30 /usr/bin/osascript -l JavaScript "$JOBS_SIM_ENV_PACKAGE/模拟器实例.jxa" "$@" || return $?
  /bin/cat "$LOG_FILE.simulator-instance-json"
}
# 官方组件安装保留本人许可与管理员交互，不使用 sudo 或自动接受参数。
jobs_sim_xcodebuild() {
  /usr/bin/xcodebuild "$@"
}
# 单次官方组件获取保留原始退出码与实时日志，确定的许可/权限错误不能被当作网络重试。
jobs_sim_xcode_acquire_once() {
  local result=0 offset=0 output=""
  [[ ! -f "$LOG_FILE.ios-acquire" ]] || offset="$(/usr/bin/wc -c < "$LOG_FILE.ios-acquire")"
  jobs_sim_xcodebuild "$@" 2>&1 | /usr/bin/tee -a "$LOG_FILE.ios-acquire"
  result=${pipestatus[1]}
  if (( result != 0 )); then
    output="$(/usr/bin/tail -c +$((offset + 1)) "$LOG_FILE.ios-acquire")"
    if print -r -- "$output" | /usr/bin/grep -Eqi 'not agreed.*license|license.*not agreed|license.*declined'; then
      print -r -- 'license not accepted：Xcode许可尚未满足。' >> "$LOG_FILE.ios-acquire"
    elif print -r -- "$output" | /usr/bin/grep -Eqi 'must be run as root|requires.*(root|superuser|administrator)'; then
      print -r -- 'Permission denied：Xcode组件获取需要管理员授权。' >> "$LOG_FILE.ios-acquire"
    fi
  fi
  return "$result"
}
# 只重试可重入的组件获取，不重跑模拟器创建、启动或工程构建。
jobs_sim_xcode_acquire() {
  jobs_sdk_retry 'Xcode本轮兼容组件获取' "$LOG_FILE.ios-acquire" jobs_sim_xcode_acquire_once "$@"
}
# 这里只重试原生清单获取；结构解析由父层完成，畸形清单不会被当作网络失败无限重试。
jobs_sim_android_updates_once() {
  local result=0
  android_timed 60 "$ANDROID_SIM_SDKMANAGER" --sdk_root="$ANDROID_SIM_SDK" --list --channel=0 "${ANDROID_SIM_SDK_PROXY[@]}" > "$1" 2>&1 || result=$?
  if (( result != 0 )); then /bin/cat "$1" >> "$LOG_FILE"; return "$result"; fi
  if /usr/bin/grep -Eqi 'HTTP[^[:cntrl:]]*(401|403)|Authentication failed|Proxy Authentication' "$1"; then
    android_log '✖ Authentication failed：Android正式更新目录授权未满足，未报告环境就绪。'
    return 67
  fi
  if /usr/bin/grep -Eqi 'UnknownHostException|Read timed out|SocketTimeoutException|ConnectException|SocketException|SSLHandshakeException|Connection (reset|refused|timed out)|Could not resolve|[Nn]etwork is unreachable|HTTP[^[:cntrl:]]*(408|425|429|5[0-9]{2})|Failed to (download|fetch)[^[:cntrl:]]*(source|repository|https?://)' "$1"; then
    /bin/cat "$1" >> "$LOG_FILE"
    return 1
  fi
}
# 子 Shell 复用工具库，避免覆盖父运行器的日志、路径、trap 或业务 main。
jobs_sim_prepare_android() (
  local parent_log="$LOG_FILE" directory=""
  source "$JOBS_SIM_ENV_PACKAGE/Resources/【MacOS】Android工具库.zsh/【MacOS】Android工具库.zsh" || return 1
  android_prepare_context
  directory="$(umask 077; /usr/bin/mktemp -d "$parent_log.simulator-android.XXXXXX")" || return 1
  LOG_FILE="$directory/prepare.log"
  ANDROID_SIM_MODE=prepare
  android_initialize_runtime || return $?
  android_log "➤ Android启动准备日志：$LOG_FILE"
  android_prepare_toolchain || return $?
  # 只更新启动组件；传统 CLI 沿已验证的21.0基线，不追随可能成为首次联网启动器的latest。
  local report="$LOG_FILE.updates" updates="" package=""
  local -a packages=()
  android_log '来源：Google Android SDK Repository（https://dl.google.com/android/repository/）；只检查正式启动工具组件。'
  jobs_sdk_retry 'Android 启动组件正式更新清单' "$LOG_FILE" jobs_sim_android_updates_once "$report" || return $?
  updates="$(/usr/bin/osascript -l JavaScript "$JOBS_SIM_ENV_PACKAGE/模拟器实例.jxa" android-updates "$report" 2>> "$LOG_FILE")" || {
    android_log "✖ Android 正式清单缺失、截断或格式无效，未报告就绪；详情：$report"
    return 67
  }
  [[ -z "$updates" ]] || packages=("${(@f)updates}")
  [[ -x "$ANDROID_SIM_SDK/platform-tools/adb" ]] || packages+=(platform-tools)
  for package in "${(@u)packages}"; do
    [[ -n "$package" ]] || continue
    android_log "▶ 自动准备正式启动组件：$package（保留已有 AVD 与镜像）"
    android_install_package "$package" || return $?
  done
  if (( ${#packages} )); then
    jobs_sdk_retry 'Android 启动组件更新后复检' "$LOG_FILE" jobs_sim_android_updates_once "$report" || return $?
    updates="$(/usr/bin/osascript -l JavaScript "$JOBS_SIM_ENV_PACKAGE/模拟器实例.jxa" android-updates "$report" 2>> "$LOG_FILE")" || { android_log "✖ Android 更新后清单无法核验；详情：$report"; return 67; }
    [[ -z "$updates" ]] || { android_log "✖ 正式组件更新后仍未就绪：$updates"; return 1; }
  fi
  android_ensure_emulator || return $?
  [[ -x "$ANDROID_SIM_SDK/platform-tools/adb" ]] || return 1
  android_timed 15 "$ANDROID_SIM_SDK/platform-tools/adb" version || return $?
  print -r -- "$ANDROID_SIM_SDK"$'\t'"${JAVA_HOME:-}" > "$1"
)
# 无显式路径时用键盘选择健康候选，不能让多个安装退回手输环境变量。
jobs_sim_harmony_find() {
  if [[ -n "${HARMONY_EMULATOR_BIN:-}${DEVECO_STUDIO_HOME:-}${TOOL_HOME:-}" ]]; then hs_find_emulator; return $?; fi
  local candidate="" directory=""
  local -a candidates=(/Applications/DevEco*.app/Contents/tools/emulator/Emulator(N) "$HOME"/Applications/DevEco*.app/Contents/tools/emulator/Emulator(N) "$HS_TOOLS_HOME"/clt-*/emulator/Emulator(N)) compatible=()
  for directory in "${path[@]}"; do [[ -z "$directory" || ! -x "$directory/Emulator" ]] || candidates+=("$directory/Emulator"); done
  candidates=("${(@u)candidates}")
  for candidate in "${candidates[@]}"; do
    [[ -f "$candidate" && -x "$candidate" ]] || continue
    HS_BIN="${candidate:A}"
    hs_check_capabilities >> "$HS_LOG" 2>&1 && compatible+=("$HS_BIN")
  done
  HS_BIN=""
  (( ${#compatible} )) || return 3
  if (( ${#compatible} == 1 )); then HS_BIN="${compatible[1]}"; return 0; fi
  ROWS=()
  for candidate in "${compatible[@]}"; do ROWS+=("$candidate"$'\t'"$candidate"); done
  ROWS+=($'__back__\t返回启动虚拟设备')
  select_row '选择本轮鸿蒙模拟器工具：' 1 || return $?
  [[ "$REPLY" != __back__ ]] || return 10
  (( ${compatible[(Ie)$REPLY]} )) || return 2
  HS_BIN="$REPLY"
}
# 仅脱敏显示副本；真实下载URL保留官方授权参数，不能回写成脱敏地址。
jobs_sim_harmony_redact() {
  local message="$*" safe="${HS_CLT_URL%%\?*}" prefix="" rest="" authority=""
  prefix="${safe%%://*}://"; rest="${safe#*://}"; authority="${rest%%/*}"
  safe="$prefix${authority##*@}/${rest#*/}"
  message="${message//"$HS_CLT_URL"/"$safe"}"
  if [[ "$message" == *'该摘要固定 SDL 镜像内容'* ]]; then
    message='ℹ SHA-256来自本轮Huawei官方更新目录；下载与解压仍逐项校验。'
  fi
  message="${message//SDL 第三方免登录镜像/Huawei 官方授权下载}"
  message="${message//快照 SHA-256/官方 SHA-256}"
  message="${message//SDL/华为官方}"
  REPLY="$message"
}
# 官方下载沿同源日志器落盘，保证签名URL不会写入可复制操作日志。
jobs_sim_harmony_source_log() {
  jobs_sim_harmony_redact "$*"
  jobs_sim_harmony_original_log "$REPLY"
}
# 错误说明同样脱敏，原退出状态保持失败。
jobs_sim_harmony_source_error() {
  jobs_sim_harmony_redact "$*"
  jobs_sim_harmony_original_error "$REPLY"
}
# 归档摘要和结构通过后仍要核验实际版本，再发布新目录，绝不覆盖旧工具。
jobs_sim_harmony_publish_checked() {
  local file="$1/version.txt" actual=""
  [[ -f "$file" && ! -L "$file" ]] || return 1
  actual="$(< "$file")"
  [[ "$actual" == "$HS_CLT_VERSION" ]] || { hs_error '官方归档实际CLT版本与本轮更新元数据不一致，未发布。'; return 1; }
  jobs_sim_harmony_original_publish "$@"
}
# 官方更新核验先于任何缺失工具下载；认证/许可阻塞保持未就绪，不退回固定旧基线。
jobs_sim_prepare_harmony() (
  source "$JOBS_SIM_ENV_PACKAGE/Resources/【MacOS】Harmony工具库.zsh/【MacOS】Harmony工具库.zsh" || return 1
  source "$JOBS_SIM_ENV_PACKAGE/Resources/【MacOS】鸿蒙官方更新.zsh/【MacOS】鸿蒙官方更新.zsh" || return 1
  setopt NO_NOMATCH PIPE_FAIL
  hs_check_host || return $?
  hs_initialize_log || return $?
  local current="" version_file="" result=0 state="" update_receipt="$HS_LOG.official-update" selected="" repair=0
  jobs_sim_harmony_find || result=$?
  case "$result" in 0|3) ;; *) return "$result" ;; esac
  if [[ -n "$HS_BIN" ]]; then
    version_file="${HS_BIN:h:h}/version.txt"
    if [[ -f "$version_file" && ! -L "$version_file" ]]; then current="$(< "$version_file")"; fi
    [[ "$current" == <->.<->.<->.<-> ]] || { current=""; version_file=""; }
    if [[ -n "$current" ]]; then
      selected="${HS_BIN:h:h}"
      [[ -d "$selected/sdk/default/openharmony/ets" && -d "$selected/sdk/default/openharmony/native" && -x "$selected/sdk/default/openharmony/toolchains/hdc" ]] || repair=1
    fi
  fi
  (umask 077; : > "$update_receipt") || return 1
  if (( repair )); then
    hs_log '▶ 当前CLT配套SDK缺失，将通过官方元数据获取完整同分支正式工具；不覆盖原目录。'
    jobs_sim_harmony_official_update "" "$update_receipt" "" || return $?
  else
    jobs_sim_harmony_official_update "$current" "$update_receipt" "$version_file" || return $?
  fi
  [[ -z "$HS_BIN" || -n "$current" ]] || { hs_error '当前工具实际CLT版本未知，未以Emulator或IDE版本冒充，未替换所选工具。'; return 67; }
  state="$(jobs_sim_harmony_official_data field "$update_receipt" state)" || return 1
  case "$state" in
    ready)
      [[ -n "$HS_BIN" && -n "$current" ]] || { hs_error '实际CLT版本未验证，未报告启动就绪。'; return 67; }
      ;;
    update)
      HS_CLT_VERSION="$(jobs_sim_harmony_official_data field "$update_receipt" version)" || return 1
      HS_CLT_SIZE="$(jobs_sim_harmony_official_data field "$update_receipt" size)" || return 1
      HS_CLT_SHA256="$(jobs_sim_harmony_official_data field "$update_receipt" sha256)" || return 1
      HS_CLT_URL="$(jobs_sim_harmony_official_data field "$update_receipt" url)" || return 1
      functions[jobs_sim_harmony_original_log]="${functions[hs_log]}"
      functions[jobs_sim_harmony_original_error]="${functions[hs_error]}"
      functions[jobs_sim_harmony_original_publish]="${functions[hs_publish_clt]}"
      functions[hs_log]="${functions[jobs_sim_harmony_source_log]}"
      functions[hs_error]="${functions[jobs_sim_harmony_source_error]}"
      functions[hs_publish_clt]="${functions[jobs_sim_harmony_publish_checked]}"
      HS_TOOLS_ONLY=1
      hs_install_clt || return $?
      [[ -f "${HS_BIN:h:h}/version.txt" && "$(< "${HS_BIN:h:h}/version.txt")" == "$HS_CLT_VERSION" ]] || { hs_error '侧装后的实际CLT版本复检失败。'; return 1; }
      ;;
    *) hs_error '官方更新核验状态无效，未启动。'; return 67 ;;
  esac
  hs_check_capabilities || return $?
  selected="${HS_BIN:h:h}"
  [[ "${selected:t}" != tools ]] || selected="${selected:h}"
  DEVECO_STUDIO_HOME="$selected"
  TOOL_HOME=""
  HS_TOOLS_ONLY=1
  hs_prepare_tools_only || return $?
  hs_review_licenses || return $?
  hs_query_output -list -details > "$1.inventory" || return $?
  jobs_sim_instance_json rows "$1.inventory" >/dev/null || return 1
  print -r -- "$HS_BIN" > "$1"
)
# 只发现完整Xcode；显式目录不能被其它安装静默替换。
jobs_sim_find_xcode() {
  local developer="${DEVELOPER_DIR:-}" candidate=""
  if [[ -n "$developer" ]]; then
    [[ -x "$developer/usr/bin/simctl" && -x "$developer/usr/bin/xcodebuild" ]] || return 3
    REPLY="$developer"; return 0
  fi
  developer="$(/usr/bin/xcode-select -p 2>/dev/null)" || developer=""
  if [[ -x "$developer/usr/bin/simctl" && -x "$developer/usr/bin/xcodebuild" ]]; then REPLY="$developer"; return 0; fi
  local -a choices=(/Applications/Xcode*.app/Contents/Developer(N/) "$HOME"/Applications/Xcode*.app/Contents/Developer(N/))
  local -a complete=()
  for candidate in "${choices[@]}"; do
    [[ ! -x "$candidate/usr/bin/simctl" || ! -x "$candidate/usr/bin/xcodebuild" ]] || complete+=("$candidate")
  done
  (( ${#complete} )) || return 3
  if (( ${#complete} == 1 )); then REPLY="${complete[1]}"; return 0; fi
  ROWS=()
  for candidate in "${complete[@]}"; do ROWS+=("$candidate"$'\t'"${candidate:h:h:t}"); done
  ROWS+=($'__back__\t返回启动虚拟设备')
  select_row '选择本轮 Xcode（不改系统默认）：' 1 || return $?
  [[ "$REPLY" != __back__ ]] || return 10
}
# 仅打开一次Apple官方入口，保留本人账号、安装器与管理员授权。
jobs_sim_open_xcode_install_page() {
  /usr/bin/open 'https://developer.apple.com/xcode/'
}
# 原生安装器进行下载时保留当前流程，可取消地等待，不重复弹出页面。
jobs_sim_install_wait_tick() {
  /bin/sleep 3
}
# 安装完即自动续行；返回与取消不会继续组件安装或设备启动。
jobs_sim_wait_for_xcode() {
  local opened=0 result=0
  while true; do
    result=0
    jobs_sim_find_xcode || result=$?
    case "$result" in 0) return 0 ;; 3) ;; *) return "$result" ;; esac
    if (( ! opened )); then
      log 'ℹ iOS启动环境未就绪：缺少完整Xcode。即将打开Apple官方安装入口；账号、下载、许可和管理员授权由本人在官方流程完成。'
      jobs_sim_open_xcode_install_page || return $?
      opened=1
      log 'ℹ 当前流程等待安装就绪并自动复检；Ctrl+C取消。下载进度由Apple原生安装器显示，未报告环境已就绪。'
    fi
    jobs_sim_install_wait_tick || return $?
  done
}
# 当前Xcode优先；官方准备组件与Runtime，工程业务门禁在设备就绪后另行执行。
jobs_sim_prepare_ios() {
  local developer="" ready="" result=0
  jobs_sim_wait_for_xcode || return $?
  developer="$REPLY"
  export DEVELOPER_DIR="$developer"
  jobs_sim_query ios-version 20 /usr/bin/xcodebuild -version || return $?
  jobs_sim_query ios-first-launch 20 /usr/bin/xcodebuild -checkFirstLaunchStatus || result=$?
  case "$result" in 129|130|131|137|143) return "$result" ;; esac
  if (( result != 0 )); then
    log '▶ 当前 Xcode 首次组件尚未配置，调用官方初始化；许可与管理员要求由官方交互处理。'
    jobs_sim_xcodebuild -license || return $?
    jobs_sim_xcode_acquire -runFirstLaunch || return $?
  fi
  log '▶ 官方检查并安装当前 Xcode 的兼容组件更新；不替换完整 Xcode 或已有 Runtime。'
  jobs_sim_xcode_acquire -runFirstLaunch -checkForNewerComponents || return $?
  jobs_sim_query ios-runtimes 30 /usr/bin/xcrun simctl list runtimes available -j || return $?
  ready="$(/usr/bin/osascript -l JavaScript "$JOBS_SIM_ENV_PACKAGE/模拟器实例.jxa" ios-ready "$LOG_FILE.simulator-ios-runtimes")" || return 1
  if [[ "$ready" != true ]]; then
    log '▶ 当前 Xcode 无可用 iOS Runtime，自动下载此 Xcode 支持的正式 iOS 平台；保留已有镜像与设备。'
    jobs_sim_xcode_acquire -downloadPlatform iOS || return $?
    jobs_sim_query ios-runtimes 30 /usr/bin/xcrun simctl list runtimes available -j || return $?
    ready="$(/usr/bin/osascript -l JavaScript "$JOBS_SIM_ENV_PACKAGE/模拟器实例.jxa" ios-ready "$LOG_FILE.simulator-ios-runtimes")" || return 1
    [[ "$ready" == true ]] || { log '✖ 官方下载后仍无当前 Xcode 可用的 iOS Runtime，未启动。'; return 1; }
  fi
  jobs_sim_query ios-simctl 30 /usr/bin/xcrun simctl list devices available -j || return $?
}
# 三个平台使用启动环境门禁；成功后把实际工具路径交回父进程，不触碰项目平台与第三方插件。
jobs_flutter_prepare_simulator_environment() {
  local platform="$1" receipt="" value="" result=0
  log "▶ $platform 模拟器启动前环境体检、自动准备与复检；保留已有实例和系统镜像。"
  case "$platform" in
    ios) jobs_sim_prepare_ios; return $? ;;
    android|harmony) ;;
    *) return 2 ;;
  esac
  receipt="$(/usr/bin/mktemp "$LOG_FILE.simulator-environment.XXXXXX")" || return 1
  if [[ "$platform" == android ]]; then jobs_sim_prepare_android "$receipt" || result=$?
  else jobs_sim_prepare_harmony "$receipt" || result=$?; fi
  if (( result == 0 )) && [[ -s "$receipt" && ! -L "$receipt" ]]; then
    value="$(< "$receipt")"
    if [[ "$platform" == android ]]; then
      export ANDROID_HOME="${value%%$'\t'*}" ANDROID_SDK_ROOT="${value%%$'\t'*}"
      [[ -z "${value#*$'\t'}" ]] || export JAVA_HOME="${value#*$'\t'}"
    else JOBS_SIM_HARMONY_BIN="$value"; fi
  else
    (( result != 0 )) || result=1
    log "✖ $platform 模拟器启动环境未就绪，未列出或启动其它设备。"
  fi
  /bin/rm -f -- "$receipt" "$receipt.inventory"
  return "$result"
}
# 已选实例按完整原身份复检；只接受其当前官方端口和自身 SDK 的授权 HDC 连接。
jobs_flutter_start_harmony_instance() (
  local key="$1" output="$2" inventory="$LOG_FILE.harmony-instances" record="" identity="" remainder="" sdk="" directory="" hdc="" targets="" connection="" started=$SECONDS limit="${JOBS_SIM_HARMONY_WAIT_SECONDS:-240}"
  [[ "$limit" == <-> ]] && (( limit >= 0 && limit <= 3600 )) || return 2
  source "$JOBS_SIM_ENV_PACKAGE/Resources/【MacOS】Harmony工具库.zsh/【MacOS】Harmony工具库.zsh" || return 1
  setopt NO_NOMATCH PIPE_FAIL
  HS_BIN="$JOBS_SIM_HARMONY_BIN"
  HS_LOG="$LOG_FILE.harmony-start"
  hs_query_output -list -details > "$inventory" || return $?
  record="$(jobs_sim_instance_json record "$inventory" "$key")" || return 1
  HS_NAME="${record%%$'\t'*}"
  # 默认路径由同一次完整列表绑定；再次查询完整key可发现同名替换，不改全局配置。
  hs_run_command -start "$HS_NAME" || return $?
  while true; do
    hs_query_output -list -details > "$inventory" || return $?
    jobs_sim_instance_json verify-record "$inventory" "$key" >/dev/null || return 1
    connection="$(hs_json connection "$(< "$inventory")" "$HS_NAME")" || return 1
    if [[ "$connection" != waiting ]]; then
      identity="${connection%%$'\t'*}"; remainder="${connection#*$'\t'}"
      sdk="${remainder%%$'\t'*}"; directory="${remainder#*$'\t'}"
      hdc="$(hs_created_instance_hdc "$sdk" "$directory")" || { hs_error '所选实例 SDK 的 HDC 不完整或存在冲突；未选择其它设备。'; return 1; }
      targets="$(hs_created_hdc_targets "$hdc")" || return $?
      if print -r -- "$targets" | /usr/bin/tr -d '\r' | /usr/bin/grep -Fxq -- "$identity"; then
        print -r -- "$identity" > "$output"
        return 0
      fi
    fi
    (( SECONDS - started < limit )) || break
    /bin/sleep 3
  done
  hs_error '所选鸿蒙实例未在时限内授权就绪；保留实例，未运行或替换设备。'
)
# 工程准备后再次核对原实例与 HDC 端口，防止长时间 SDK 获取期间目标被替换。
jobs_flutter_verify_harmony_instance() (
  local key="$1" identity="$2" inventory="$LOG_FILE.harmony-final-instance" connection="" record=""
  source "$JOBS_SIM_ENV_PACKAGE/Resources/【MacOS】Harmony工具库.zsh/【MacOS】Harmony工具库.zsh" || return 1
  HS_BIN="$JOBS_SIM_HARMONY_BIN"
  hs_query_output -list -details > "$inventory" || return $?
  record="$(jobs_sim_instance_json verify-record "$inventory" "$key")" || return 1
  connection="$(hs_json connection "$(< "$inventory")" "${record%%$'\t'*}")" || return 1
  [[ "${connection%%$'\t'*}" == "$identity" ]] || { hs_error '原模拟器连接身份已变化，停止运行。'; return 1; }
)
