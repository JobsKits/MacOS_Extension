#!/bin/zsh
# Created by Jobs on 2026年11月15日，星期日.
# 供运行器 source：所选平台前台修复，其它平台经选择后隔离准备，不改当前工程绑定。
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

typeset -gA JOBS_RUN_OPTIONAL_ASKED
typeset -g JOBS_RUN_DEPENDENCIES_REPAIRED=0
# 公共依赖先与本轮SDK对齐，索引问题不应触发无关平台工具和许可安装。
jobs_run_prepare_project_dependencies() {
  local helper="" sdk="${FLUTTER_BIN:A:h:h}" result=0 output="$LOG_FILE.prepare-packages"
  JOBS_RUN_DEPENDENCIES_REPAIRED=0
  helper="$(jobs_layout_file "$SCRIPT_DIR/【MacOS】Flutter运行前体检.zsh/Flutter运行前体检.jxa")"
  [[ -f "$helper" && ! -L "$helper" ]] || { log "✖ 缺少依赖索引校验模块：$helper"; return 1; }
  run_bounded 20 "$output" /usr/bin/osascript -l JavaScript "$helper" packages "$PROJECT_PATH" "$sdk" || result=$?
  case "$result" in
    0) return 0 ;;
    124) return "$result" ;;
  esac
  (( result < 128 )) || return "$result"
  log '▶ 当前工程依赖索引未就绪，先使用本轮选定的 Flutter SDK 拉取依赖，再检查各平台。'
  (
    cd -- "$PROJECT_PATH" || return 1
    RUN_BOUNDED_STREAM=1 run_bounded 900 "$LOG_FILE.prepare-pub" "$FLUTTER_BIN" pub get
  ) || return $?
  result=0
  run_bounded 20 "$output" /usr/bin/osascript -l JavaScript "$helper" packages "$PROJECT_PATH" "$sdk" || result=$?
  if (( result != 0 )); then
    log "✖ 当前SDK依赖索引复检失败，未进入平台工具安装；详情：$output"
    return "$result"
  fi
  JOBS_RUN_DEPENDENCIES_REPAIRED=1
  log '✓ 当前工程依赖已与本轮 Flutter SDK 对齐。'
}
typeset -g JOBS_RUN_PREPARE_PACKAGE="${${(%):-%x}:A:h}"
# 选中平台后才复用该平台的隔离缓存，工程绑定仍由原准备器校验和应用。
jobs_run_use_optional() {
  local platform="$1" digest="" task="" root="${STATE_ROOT:-$HOME/Library/Application Support/JobsFlutterRunner/sessions}"
  [[ "$platform" != harmony ]] || platform=ohos
  digest="$(printf '%s\0%s' "$PROJECT_PATH" "$platform" | /usr/bin/shasum -a 256)"
  task="$root/environment-${digest%% *}"
  [[ -d "$task" && ! -L "$task" && -f "$task/status" && ! -L "$task/status" && "$(< "$task/status")" == prepared ]] || return 0
  case "$platform" in
    android)
      [[ -d "$task/cache/android" && ! -L "$task/cache/android" ]] || return 1
      export ANDROID_HOME="$task/cache/android" ANDROID_SDK_ROOT="$task/cache/android"
      ;;
    ohos)
      export JOBS_HARMONY_FVM_CACHE="$task/cache/harmony-flutter" JOBS_HARMONY_TOOLS_HOME="$task/cache/harmony-tools"
      ;;
  esac
  log "ℹ 复用 $platform 后台准备缓存，仍须按当前工程约束与设备复检：$task"
}
# 仅发布缺失的平台；生成过程留在私有目录，不覆盖已有业务源码。
jobs_run_prepare_native_platform() {
  local platform="$1" stage="" name=""
  [[ ! -e "$PROJECT_PATH/$platform" && ! -L "$PROJECT_PATH/$platform" ]] || return 0
  stage="$(/usr/bin/mktemp -d "$LOG_FILE.platform.XXXXXX")" || return 1
  name="$(/usr/bin/awk '/^name:[[:space:]]*/ { sub(/^name:[[:space:]]*/, ""); sub(/[[:space:]]+#.*/, ""); print; exit }' "$PROJECT_PATH/pubspec.yaml")"
  name="${(Q)name}"
  [[ "$name" =~ '^[a-z][a-z0-9_]*$' ]] || return 1
  (
    cd -- "$stage" || return 1
    RUN_BOUNDED_STREAM=1 run_bounded 300 "$LOG_FILE.create-$platform" "$FLUTTER_BIN" create --platforms "$platform" --no-pub --project-name "$name" .
  ) || return $?
  [[ -d "$stage/$platform" && ! -L "$stage/$platform" ]] || return 1
  /usr/bin/osascript -l JavaScript - "$stage/$platform" "$PROJECT_PATH/$platform" <<'JXA'
ObjC.import('Foundation');
function run(a) {
    if (!$.NSFileManager.defaultManager.moveItemAtPathToPathError(a[0], a[1], null)) throw Error('平台目标已出现或发布失败，保留现场。');
}
JXA
}
# 真机仅检查Xcode首次组件；Runtime获取由明确选择虚拟设备的流程负责。
jobs_run_prepare_ios_host() {
  local kind="${1:-physical}" result=0
  load_simulator_start_environment || return $?
  if [[ "$kind" == virtual ]]; then
    jobs_flutter_prepare_simulator_environment ios
    return $?
  fi
  jobs_sim_wait_for_xcode || return $?
  export DEVELOPER_DIR="$REPLY"
  jobs_sim_query ios-version 20 /usr/bin/xcodebuild -version || return $?
  jobs_sim_query ios-first-launch 20 /usr/bin/xcodebuild -checkFirstLaunchStatus || result=$?
  case "$result" in 129|130|131|137|143) return "$result" ;; esac
  if (( result != 0 )); then
    log '▶ 当前iOS真机运行需要Xcode首次组件；许可和管理员要求由官方交互处理。'
    jobs_sim_xcodebuild -license || return $?
    jobs_sim_xcode_acquire -runFirstLaunch || return $?
  fi
}
# 仅修复当前iOS运行必需的CocoaPods；不运行全局升级或自动接受许可。
jobs_run_prepare_cocoapods() {
  local pod="" brew="" candidate="" result=0
  pod="$(whence -p pod 2>/dev/null)" || pod=""
  if [[ -n "$pod" && -x "$pod" ]]; then
    run_bounded 20 "$LOG_FILE.pod-version" "$pod" --version || result=$?
    case "$result" in 0) return 0 ;; 129|130|131|137|143) return "$result" ;; esac
  fi
  for candidate in "$(whence -p brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    result=0
    run_bounded 10 "$LOG_FILE.brew-version" "$candidate" --version || result=$?
    case "$result" in 0) brew="$candidate"; break ;; 129|130|131|137|143) return "$result" ;; esac
  done
  [[ -n "$brew" ]] || { log '✖ 缺少可用CocoaPods及既有Homebrew；保留工程，请先安装Homebrew后重试。'; return 1; }
  log "━━━━━━━━━━ iOS必需组件：CocoaPods ━━━━━━━━━━"
  log "➤ 使用既有Homebrew安装cocoapods：$brew；本进程禁止自动更新和全量升级。"
  RUN_BOUNDED_STREAM=1 jobs_sdk_retry '当前iOS运行必需CocoaPods' "$LOG_FILE.pod-install" run_bounded 1800 "$LOG_FILE.pod-install" /usr/bin/env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_UPGRADE=1 "$brew" install cocoapods || return $?
  rehash
  for candidate in "$(whence -p pod 2>/dev/null)" "${brew:h}/pod" /opt/homebrew/bin/pod /usr/local/bin/pod; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    result=0
    run_bounded 20 "$LOG_FILE.pod-version" "$candidate" --version || result=$?
    case "$result" in 129|130|131|137|143) return "$result" ;; esac
    if (( result == 0 )); then
      export PATH="${candidate:h}:$PATH"
      return 0
    fi
  done
  log '✖ CocoaPods安装后实际命令复检失败，未进入Flutter构建。'
  return 1
}
# 在子Shell内适配成熟Android工程组件内核，避免其初始化覆盖运行器状态。
jobs_run_prepare_android_project() {
  local package="$JOBS_RUN_PREPARE_PACKAGE/Resources/Android" work="" sdk="" java="" result=0
  [[ ! -L "$(jobs_layout_file "$package/SetupFlutterPlatform.zsh")" && -s "$(jobs_layout_file "$package/SetupFlutterPlatform.zsh/SetupFlutterPlatform.zsh")" && ! -L "$(jobs_layout_file "$package/SetupFlutterPlatform.zsh/SetupFlutterPlatform.zsh")" && ! -L "$(jobs_layout_file "$package/AndroidSdkSupport.zsh")" && -s "$(jobs_layout_file "$package/AndroidSdkSupport.zsh/AndroidSdkSupport.zsh")" && ! -L "$(jobs_layout_file "$package/AndroidSdkSupport.zsh/AndroidSdkSupport.zsh")" ]] || {
    log "✖ 随包Android工程组件内核缺失：$package；请更新完整工具包。"
    return 1
  }
  work="$(/usr/bin/mktemp -d "$LOG_FILE.android-project.XXXXXX")" || return 1
  log "━━━━━━━━━━ Android工程编译组件准备 ━━━━━━━━━━"
  log "➤ 按当前工程compileSdk、build-tools、NDK和CMake准备；日志与local.properties备份：$work"
  (
    local PE_TOOLS_DIR="$package" PE_RUN_DIR="$work" PE_LOG_FILE="$work/environment.log" PE_SELECTION="" selected_java=""
    source "$(jobs_layout_file "$PE_TOOLS_DIR/AndroidSdkSupport.zsh/AndroidSdkSupport.zsh")" || return $?
    # 本层只准备JDK和工程组件，不运行模拟器内核的emulator安装入口。
    android_prepare_context
    ANDROID_SIM_MODE=prepare
    LOG_FILE="$work/android-tools.log"
    : > "$LOG_FILE"
    android_configure_network || return $?
    android_detect_architecture || return $?
    android_ensure_java || return $?
    selected_java="$JAVA_HOME"
    source "$(jobs_layout_file "$PE_TOOLS_DIR/SetupFlutterPlatform.zsh/SetupFlutterPlatform.zsh")" || return $?
    # 终端回调保留内核原始许可、版本选择和并发文件保护语义。
    pe_log() { log "$*"; }
    pe_event() {
      local marker='▶'
      [[ "$4" != succeeded ]] || marker='✓'
      [[ "$4" != failed ]] || marker='✖'
      log "$marker $3：${5:-}${6:+（$6）}"
    }
    pe_select() {
      ROWS=("${(@f)2}")
      select_row "$1：" 1 || return $?
      [[ "$REPLY" != __back__ ]] || return 10
      PE_SELECTION="$REPLY"
    }
    pe_filter_log() {
      /usr/bin/perl -pe 's/\e\[[0-?]*[ -\/]*[@-~]//g; s{(https?://)[^/\s@]+@}{${1}[REDACTED]@}g; s{(https?://[^\s?]+)\?[^\s]*}{${1}?[REDACTED]}g'
    }
    pe_run_logged() { RUN_BOUNDED_STREAM=1 run_bounded 60 "$work/command.log" "$@"; }
    sf_file_stamp() {
      local item="$1"
      [[ ! -L "${item:h}" && ! -L "$item" ]] || return 1
      [[ -e "$item" ]] || { print absent; return 0; }
      [[ -f "$item" && "$(/usr/bin/stat -f %l "$item")" == 1 && "$(/usr/bin/stat -f %z "$item")" -le 65536 ]] || return 1
      /usr/bin/stat -f '%d:%i:%l:%m:%c:%z' "$item" || return 1
      /usr/bin/shasum -a 256 "$item"
    }
    ap_prepare_android "$PROJECT_PATH" "$FLUTTER_BIN" "$selected_java" || return $?
    print -r -- "$selected_java" > "$work/tool-java"
  ) || result=$?
  (( result == 0 )) || return "$result"
  [[ -f "$work/android-sdk-root" && ! -L "$work/android-sdk-root" ]] || return 1
  sdk="$(< "$work/android-sdk-root")"
  [[ "$sdk" == /* && -d "$sdk" && ! -L "$sdk" ]] || return 1
  export ANDROID_HOME="$sdk" ANDROID_SDK_ROOT="$sdk" PATH="$sdk/platform-tools:$PATH"
  if [[ -f "$work/tool-java" && ! -L "$work/tool-java" ]]; then
    java="$(< "$work/tool-java")"
    [[ "$java" == /* && -x "$java/bin/java" ]] || return 1
    export JAVA_HOME="$java" PATH="$java/bin:$PATH"
  fi
}
# 必需的iOS/Android编译链路直接准备；正常平台不动，复检不过时仍明确阻塞。
jobs_run_prepare_required() {
  local platform="$1" kind="${2:-physical}" result=0
  [[ "${JOBS_PREFLIGHT_STATE[$platform]:-failed}" != passed ]] || return 0
  jobs_run_use_optional "$platform" || return $?
  case "$platform" in ios|android) ;; *) return 0 ;; esac
  jobs_run_prepare_project_dependencies || return $?
  if (( JOBS_RUN_DEPENDENCIES_REPAIRED )); then
    jobs_flutter_preflight_overview || return $?
    [[ "${JOBS_PREFLIGHT_STATE[$platform]:-failed}" != passed ]] || return 0
  fi
  log "▶ 当前运行需要 $platform，直接补齐缺失环境；完成后复检。"
  if [[ "$platform" == ios ]]; then
    jobs_run_prepare_ios_host "$kind" || return $?
    jobs_run_prepare_cocoapods || return $?
  fi
  jobs_run_prepare_native_platform "$platform" || return $?
  if [[ "$platform" == android ]]; then jobs_run_prepare_android_project || return $?; fi
  (
    cd -- "$PROJECT_PATH" || return 1
    RUN_BOUNDED_STREAM=1 run_bounded 900 "$LOG_FILE.prepare-pub" "$FLUTTER_BIN" pub get
  ) || return $?
  jobs_flutter_preflight_overview || return $?
  [[ "${JOBS_PREFLIGHT_STATE[$platform]:-failed}" == passed ]] || { jobs_fpf_report "$platform"; return 1; }
}
# 取消时只回收本后台任务实际派生的进程树，不影响其它运行任务。
jobs_run_cancel_optional() {
  local task="$1" child="" worker=""
  zmodload zsh/system || return 1
  worker="$sysparams[pid]"
  for child in ${(f)"$(/usr/bin/pgrep -P "$worker" 2>/dev/null)"}; do
    [[ "$child" == <-> ]] || continue
    jfs_route_stop_tree "$child"
  done
  print -r -- cancelled > "$task/status"
}
# 后台只准备隔离SDK、宿主工具和平台草稿，原工程集成在真正选用时再应用。
jobs_run_prepare_optional_worker() {
  local platform="$1" task="$2" result=0 source_project="$PROJECT_PATH"
  trap '' HUP
  trap 'result=$?; [[ -f "$task/status" && "$(< "$task/status")" != running ]] || print -r -- "failed:$result" > "$task/status"' EXIT
  trap 'jobs_run_cancel_optional "$task"; exit 130' INT TERM
  export NO_COLOR=1 PLAIN_OUTPUT=1 PUB_CACHE="$task/cache/pub" GRADLE_USER_HOME="$task/cache/gradle"
  export ANDROID_HOME="$task/cache/android" ANDROID_SDK_ROOT="$task/cache/android" ANDROID_USER_HOME="$task/cache/android-user"
  export JOBS_HARMONY_TOOLS_HOME="$task/cache/harmony-tools" JOBS_HARMONY_FVM_CACHE="$task/cache/harmony-flutter"
  export JOBS_HARMONY_PREPARE_FORCE_PRIVATE=1
  unset DEVECO_STUDIO_HOME TOOL_HOME DEVECO_SDK_HOME OHOS_SDK_HOME HARMONY_EMULATOR_BIN
  PROJECT_PATH="$task/project"
  SCRIPT_DIR="$task/Resources"
  LOG_FILE="$task/operations.log"
  /bin/mkdir -p "$PROJECT_PATH" || return 1
  /bin/cp -p "$source_project/pubspec.yaml" "$PROJECT_PATH/pubspec.yaml" || return 1
  print -r -- running > "$task/status"
  log "▶ 后台准备 $platform；缓存与工程草稿：$task；不改当前运行工程、FVM、依赖索引或共享SDK。"
  if [[ "$platform" == ohos ]]; then
    source "$SCRIPT_DIR/【MacOS】Flutter运行前体检.zsh/【MacOS】鸿蒙运行环境准备.zsh/【MacOS】鸿蒙运行环境准备.zsh" || return $?
    jobs_hpr_backup_project && jobs_hpr_prepare_sdk && jobs_hpr_prepare_platform && jobs_hpr_prepare_tools || result=$?
  else
    load_simulator_start_environment && jobs_flutter_prepare_simulator_environment "$platform" || result=$?
  fi
  if (( result == 0 )); then
    print -r -- prepared > "$task/status"
    log '✓ 隔离宿主环境准备完成；工程FVM绑定、平台集成及插件支持待实际选用时复检并应用，未报告原工程已就绪。'
  else
    print -r -- "failed:$result" > "$task/status"
    log "✖ 后台准备未完成（$result）；许可、认证或不兼容条件需按日志处理，不影响当前运行。"
  fi
  return "$result"
}
# 每项目每平台保存独立任务，启动时复制资源，关闭当前终端不删除准备现场。
jobs_run_start_optional() {
  local platform="$1" task="" digest="" root="${STATE_ROOT:-$HOME/Library/Application Support/JobsFlutterRunner/sessions}" pid="" lock_fd="" birth="" current=""
  digest="$(printf '%s\0%s' "$PROJECT_PATH" "$platform" | /usr/bin/shasum -a 256)"
  digest="${digest%% *}"
  task="$root/environment-$digest"
  [[ ! -L "$root" && ! -L "$task" ]] || return 1
  /bin/mkdir -p "$root" || return 1
  [[ ! -L "$task.lock" ]] || return 1
  : >> "$task.lock" || return 1
  zmodload zsh/system || return 1
  zsystem flock -t 0 -f lock_fd "$task.lock" || { log "ℹ $platform 后台准备正在登记，当前运行继续。"; return 0; }
  {
    if [[ -d "$task" ]]; then
      if [[ -f "$task/status" && "$(< "$task/status")" == prepared ]]; then
        log "ℹ 已有 $platform 隔离准备结果：$task；实际选用时复检，不重复下载。"
        return 0
      fi
      [[ ! -f "$task/pid" ]] || pid="$(< "$task/pid")"
      [[ ! -f "$task/pid-start" ]] || birth="$(< "$task/pid-start")"
      if [[ "$pid" == <-> && -n "$birth" ]]; then current="$(/bin/ps -p "$pid" -o lstart= 2>/dev/null)"; fi
      if [[ -n "$birth" && "$current" == "$birth" ]] && kill -0 "$pid" 2>/dev/null; then
        log "ℹ $platform 后台准备仍在运行；日志：$task/prepare.log。"
        return 0
      fi
      /bin/mv "$task" "$task.previous.$(/bin/date +%Y%m%d-%H%M%S).$$" || return 1
    fi
    if ! /bin/mkdir "$task" 2>/dev/null; then
      log "ℹ 已有 $platform 后台准备记录：$task/status；日志：$task/prepare.log（不重复启动）。"
      return 0
    fi
    /usr/bin/ditto "$SCRIPT_DIR" "$task/Resources" || return 1
    jobs_run_prepare_optional_worker "$platform" "$task" </dev/null > "$task/prepare.log" 2>&1 &!
    pid=$!
    print -r -- "$pid" > "$task/pid"
    /bin/ps -p "$pid" -o lstart= > "$task/pid-start"
    log "▶ 已后台准备 $platform，当前运行继续；日志：$task/prepare.log；状态：$task/status。"
  } always {
    zsystem flock -u "$lock_fd"
  }
}
# 仅停止当前工程记录且出生时间仍匹配的后台任务，保留缓存与全部准备现场。
jobs_run_stop_optional() {
  local platform="" root="${STATE_ROOT:-$HOME/Library/Application Support/JobsFlutterRunner/sessions}" digest="" task="" pid="" birth="" current="" tick=0 failures=0
  [[ -d "$root" && ! -L "$root" ]] || return 0
  for platform in ios android ohos; do
    digest="$(printf '%s\0%s' "$PROJECT_PATH" "$platform" | /usr/bin/shasum -a 256)"
    task="$root/environment-${digest%% *}"
    [[ -d "$task" && ! -L "$task" ]] || continue
    [[ -f "$task/status" && ! -L "$task/status" ]] || { log "⚠ $platform 后台任务状态无法核对，保留现场，未发送停止信号。"; failures=1; continue; }
    [[ "$(< "$task/status")" == running ]] || continue
    if [[ ! -f "$task/pid" || -L "$task/pid" || ! -f "$task/pid-start" || -L "$task/pid-start" ]]; then
      log "⚠ $platform 后台任务进程记录不完整，保留现场，未发送停止信号。"
      failures=1
      continue
    fi
    pid="$(< "$task/pid")" birth="$(< "$task/pid-start")" current=""
    if [[ "$pid" == <-> && -n "$birth" ]]; then current="$(/bin/ps -p "$pid" -o lstart= 2>/dev/null)"; fi
    if [[ -z "$birth" || "$current" != "$birth" ]] || ! kill -0 "$pid" 2>/dev/null; then
      log "⚠ $platform 后台任务原进程身份已失效；保留缓存，未停止其它进程。"
      failures=1
      continue
    fi
    kill -TERM "$pid" 2>/dev/null || { failures=1; continue; }
    for tick in {1..100}; do
      if [[ -f "$task/status" && ! -L "$task/status" && "$(< "$task/status")" == cancelled ]] && ! kill -0 "$pid" 2>/dev/null; then break; fi
      /bin/sleep 0.1
    done
    if [[ -f "$task/status" && ! -L "$task/status" && "$(< "$task/status")" == cancelled ]] && ! kill -0 "$pid" 2>/dev/null; then
      log "✓ 已停止本工程 $platform 后台准备；缓存与日志保留：$task"
    else
      log "⚠ $platform 后台准备尚未完成停止；保留现场，请检查：$task/prepare.log"
      failures=1
    fi
  done
  return "$failures"
}
# 选定目标后才询问其它平台；EOF跳过，回车明确选择后台补齐。
jobs_run_offer_optional() {
  local selected="$1" platform="" answer=""
  for platform in ios android ohos; do
    [[ "$platform" != "$selected" && "${JOBS_PREFLIGHT_STATE[$platform]:-failed}" != passed && "${JOBS_RUN_OPTIONAL_ASKED[$platform]:-0}" != 1 ]] || continue
    JOBS_RUN_OPTIONAL_ASKED[$platform]=1
    log "ℹ $platform 不是本次 $selected 运行的必要条件，可独立后台准备SDK与宿主工具；工程改动留待选用时应用。"
    answer=""
    if IFS= read -r "answer?$(jobs_prompt_render "是否补齐 $platform 环境？回车后台补齐；任意字符+回车不补：")" && [[ -z "$answer" ]]; then
      jobs_run_start_optional "$platform" || log "✖ 无法启动 $platform 后台准备；当前运行继续。"
    else
      log "ℹ 本次跳过 $platform 环境准备。"
    fi
  done
}
