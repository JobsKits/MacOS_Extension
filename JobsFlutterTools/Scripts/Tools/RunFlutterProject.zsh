#!/bin/zsh
# 脚本自述：
# - 脚本名称：从终端运行 Flutter 项目。
# - 核心用途：终端选择设备，独立后台运行 Flutter，并查看日志及控制热重载。
# - 影响范围：Flutter 构建可更新项目依赖和构建目录；按需创建、启动所选 iOS 模拟器。
# - 运行提示：先回车确认；关闭终端只离开日志，输入 s 才停止后台任务。
# - 选择方式：终端内优先用 fzf 上下键 + 输入筛选选择；fzf 不可用或非终端时自动回退编号输入。

SCRIPT_DIR=""
SCRIPT_PATH=""
SCRIPT_SOURCE="${(%):-%x}"
LOG_FILE=""
PROJECT_PATH=""
FLUTTER_BIN=""
HELPER=""
STATE_ROOT=""
SESSION_DIR=""
JOB_LABEL=""
DEVICE_ID=""
TAIL_PID=""
START_LOCK=""
LOCK_FD=""
QUERY_PID=""
REPLY=""
FZF_BIN=""
typeset -a ROWS=()

intro_line() {
  local role="$1" message="$2" code="0;34"
  [[ "$role" == title ]] && code="1;31"
  if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" ]]; then
    printf '\033[%sm%s\033[0m\n' "$code" "$message"
  else
    print -r -- "$message"
  fi
}

show_script_intro_and_wait() {
  intro_line title '从终端运行 Flutter 项目'
  intro_line body '1、选择设备后构建、运行当前 Flutter 项目；沿用项目 FVM SDK 或终端 Flutter。'
  intro_line body '2、Flutter 由当前登录会话的 launchd 托管，关闭 Terminal 不影响运行。'
  intro_line body '3、iOS 可选择已有模拟器；没有时内置选择型号、系统版本、创建及启动流程。'
  intro_line body '4、可能下载项目依赖、生成构建文件；项目声明的 FVM SDK 缺失时会确认后下载，不安装或升级全局 Flutter / Xcode。'
  intro_line body '5、日志与会话保存在用户资源库 Application Support/JobsFlutterRunner/sessions。'
  intro_line body '6、回车继续，非空或 Ctrl+C 取消；运行后 d 离开日志，s 停止后台任务。'
  intro_line body '7、设备、模拟器型号与系统版本用上下键选择，可直接输入关键字筛选；未装 fzf 时回退编号输入。'
  local answer=""
  IFS= read -r 'answer?已了解用途与范围，按回车继续；非空取消：' || exit 0
  [[ -z "$answer" ]] || exit 0
}

initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  umask 077
  SCRIPT_PATH="${SCRIPT_SOURCE:A}"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  HELPER="$SCRIPT_DIR/FlutterRunner.jxa"
  STATE_ROOT="$HOME/Library/Application Support/JobsFlutterRunner/sessions"
  LOG_FILE="$(/usr/bin/mktemp "${TMPDIR:-/tmp/}JobsFlutterRunner.XXXXXX")" || exit 1
  [[ -f "$HELPER" ]] || die '缺少 FlutterRunner.jxa，请保留完整脚本包。'
  log "操作日志：$LOG_FILE"
}

log() {
  print -r -- "$*" | /usr/bin/tee -a "$LOG_FILE"
}

die() {
  log "✖ $*"
  exit 1
}

json_helper() {
  /usr/bin/osascript -l JavaScript "$HELPER" "$@"
}

leave_terminal() {
  if [[ -n "$QUERY_PID" ]]; then
    kill -TERM "$QUERY_PID" 2>/dev/null
    QUERY_PID=""
  fi
  if [[ -n "$TAIL_PID" ]]; then
    kill "$TAIL_PID" 2>/dev/null
    wait "$TAIL_PID" 2>/dev/null
    TAIL_PID=""
  fi
  if [[ -n "$LOCK_FD" ]]; then
    zsystem flock -u "$LOCK_FD" 2>/dev/null
    LOCK_FD=""
  fi
}

# 有界等待仅用于发现和启动设备，不给持续运行的 Flutter 设置超时。
run_bounded() {
  local seconds="$1" output="$2" task_pid="" elapsed=0 result=0
  shift 2
  "$@" > "$output" 2>&1 &
  task_pid=$!
  QUERY_PID="$task_pid"
  while kill -0 "$task_pid" 2>/dev/null; do
    if (( elapsed >= seconds )); then
      kill -TERM "$task_pid" 2>/dev/null
      /bin/sleep 1
      kill -KILL "$task_pid" 2>/dev/null
      wait "$task_pid" 2>/dev/null
      QUERY_PID=""
      log "⚠ 命令超时（${seconds} 秒）：${1:t}；详情：$output"
      return 124
    fi
    /bin/sleep 1
    (( elapsed++ ))
  done
  wait "$task_pid" || result=$?
  QUERY_PID=""
  return "$result"
}

normalize_path_input() {
  local raw="${1%$'\r'}"
  local -a words=()
  if [[ -d "$raw" ]]; then
    REPLY="$raw"
    return
  fi
  words=("${(@z)raw}")
  (( ${#words} == 1 )) || die '请只输入或拖入一个项目目录。'
  REPLY="${(Q)words[1]}"
  [[ "$REPLY" == '~/'* ]] && REPLY="$HOME/${REPLY#\~/}"
}

read_project() {
  local input="" valid=""
  if (( $# == 2 )) && [[ "$1" == --project ]]; then
    PROJECT_PATH="$2"
  elif (( $# == 0 )); then
    IFS= read -r 'input?输入或拖入 Flutter 项目根目录：' || exit 0
    normalize_path_input "$input"
    PROJECT_PATH="$REPLY"
  else
    die '用法：RunFlutterProject.zsh --project <Flutter 项目根目录>'
  fi
  [[ -d "$PROJECT_PATH" && ! -L "$PROJECT_PATH" ]] || die '项目必须是存在的普通目录。'
  valid="$(json_helper validate "$PROJECT_PATH")" || die '无法解析 pubspec.yaml。'
  [[ "$valid" == true ]] || die '所选目录同层没有真实的 dependencies.flutter.sdk: flutter。'
  PROJECT_PATH="${PROJECT_PATH:A}"
  cd "$PROJECT_PATH" || die '不能进入项目目录。'
  log "项目：$PROJECT_PATH"
}

project_fvm_config() {
  if [[ -f "$PROJECT_PATH/.fvmrc" ]]; then
    REPLY="$PROJECT_PATH/.fvmrc"
    return 0
  fi
  if [[ -f "$PROJECT_PATH/.fvm/fvm_config.json" ]]; then
    REPLY="$PROJECT_PATH/.fvm/fvm_config.json"
    return 0
  fi
  return 1
}

resolve_fvm_cli() {
  local candidate=""
  for candidate in "${JOBS_FVM_BIN:-}" "${commands[fvm]:-}" /opt/homebrew/bin/fvm /usr/local/bin/fvm \
    "$HOME/.pub-cache/bin/fvm" "$HOME/.local/bin/fvm"; do
    if [[ -n "$candidate" && -x "$candidate" && ! -d "$candidate" ]]; then
      REPLY="${candidate:A}"
      return 0
    fi
  done
  return 1
}

# 项目 FVM SDK 就绪就直接返回；断链或缺失时补齐：本机缓存已有只重建链接，没有才下载。
prepare_project_fvm_sdk() {
  local link="$PROJECT_PATH/.fvm/flutter_sdk" config="" version="" fvm_bin="" answer="" cached=""
  if [[ -x "$link/bin/flutter" ]]; then
    REPLY="${link:A}/bin/flutter"
    return 0
  fi
  project_fvm_config || { log '⚠ 项目声明了 FVM，但既没有可用的 .fvm/flutter_sdk，也读不到版本声明。'; return 1; }
  config="$REPLY"
  version="$(json_helper fvm-version "$config")" || { log "⚠ 无法解析 FVM 版本声明：$config"; return 1; }
  resolve_fvm_cli || { log '⚠ 未找到 fvm；请先安装（brew install fvm）或设置 JOBS_FVM_BIN，再重新运行。'; return 1; }
  fvm_bin="$REPLY"
  log "ℹ 项目声明 Flutter $version，但 .fvm/flutter_sdk 未就绪。"
  cached="$HOME/fvm/versions/$version/bin/flutter"
  if [[ -x "$cached" ]]; then
    log '➤ 本机 FVM 缓存已有该版本，将重建项目链接；不下载。'
  else
    log "➤ 本机 FVM 缓存没有该版本，将下载并初始化 Flutter $version（需要联网，可能几分钟）。"
  fi
  IFS= read -r 'answer?回车补齐并继续；非空取消：' || return 1
  [[ -z "$answer" ]] || { log '➤ 已取消，未改动项目 FVM 配置。'; return 1; }
  if [[ ! -x "$cached" ]]; then
    run_bounded 1800 "$LOG_FILE.fvminstall" "$fvm_bin" install "$version" || {
      log "✖ fvm install $version 失败，详情：$LOG_FILE.fvminstall"
      return 1
    }
  fi
  run_bounded 300 "$LOG_FILE.fvmuse" "$fvm_bin" use "$version" --skip-pub-get --skip-setup \
    || log "⚠ fvm use $version 未成功确认，详情：$LOG_FILE.fvmuse"
  # fvm 在声明版本已一致时可能只写配置、不重建链接，这里按本机缓存兜底。
  if [[ ! -x "$link/bin/flutter" && -x "$cached" ]]; then
    # 只清理失效的符号链接本身，不动真实 SDK 目录。
    if [[ -L "$link" ]] && ! /bin/rm -f -- "$link"; then
      log '⚠ 无法清理失效的 .fvm/flutter_sdk 链接。'
      return 1
    fi
    /bin/ln -s "${cached:h:h}" "$link" || { log '⚠ 无法重建 .fvm/flutter_sdk 链接。'; return 1; }
    log '➤ 已按本机 FVM 缓存重建 .fvm/flutter_sdk 链接。'
  fi
  [[ -x "$link/bin/flutter" ]] || { log "✖ fvm 执行后 .fvm/flutter_sdk 仍不可用：$link"; return 1; }
  REPLY="${link:A}/bin/flutter"
  log "✔ FVM SDK 已就绪：Flutter $version → $REPLY"
}

find_flutter() {
  local candidate="" output="$LOG_FILE.version"
  if [[ -e "$PROJECT_PATH/.fvmrc" || -e "$PROJECT_PATH/.fvm/fvm_config.json" || -L "$PROJECT_PATH/.fvm/flutter_sdk" ]]; then
    prepare_project_fvm_sdk || die '项目 FVM SDK 未就绪且未自动补齐，详见日志；可手动运行 fvm use 后重试。'
    candidate="$REPLY"
  else
    die '项目未绑定 FVM；不会回退全局 Flutter。'
  fi
  [[ -n "$candidate" && -x "$candidate" ]] || die '未找到 Flutter；先配置终端 PATH 或项目 FVM SDK。'
  FLUTTER_BIN="${candidate:A}"
  run_bounded 45 "$output" "$FLUTTER_BIN" --version --machine || die "Flutter 体检失败：$output"
  log "Flutter：$FLUTTER_BIN"
}

# fzf 只用于终端交互；找不到就保持编号输入，不阻断运行。
resolve_fzf() {
  local candidate=""
  for candidate in "${commands[fzf]:-}" /opt/homebrew/bin/fzf /usr/local/bin/fzf "$HOME/.fzf/bin/fzf"; do
    if [[ -n "$candidate" && -x "$candidate" && ! -d "$candidate" ]]; then
      FZF_BIN="${candidate:A}"
      return 0
    fi
  done
  FZF_BIN=""
  return 1
}

# JOBS_FLUTTER_RUNNER_FZF：0 关闭；always 忽略终端检测（供测试注入）。
fzf_ready() {
  local mode="${JOBS_FLUTTER_RUNNER_FZF:-auto}"
  [[ "$mode" != 0 ]] || return 1
  if [[ "$mode" != always ]]; then
    [[ -t 0 && -t 1 ]] || return 1
  fi
  if [[ -z "$FZF_BIN" ]]; then
    resolve_fzf || return 1
  fi
  [[ -n "$FZF_BIN" ]] || return 1
}

# 每行是 "id\tdisplay"：只展示 display，输出整行以便回取原始 id。
fzf_pick_row() {
  local heading="$1" row="" answer="" pick_status=0
  local -a lines=()
  for row in "${ROWS[@]}"; do
    if [[ "$row" == *$'\t'* ]]; then
      lines+=("$row")
    else
      lines+=("$row"$'\t'"$row")
    fi
  done
  # 用户自己的 FZF 默认配置可能改变排序或多选，先清空保证输出恒为一行。
  answer="$(printf '%s\n' "${lines[@]}" | /usr/bin/env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_OPTS_FILE \
    "$FZF_BIN" --no-multi --cycle --layout=reverse \
    --height=40% --min-height=12 --border \
    --delimiter=$'\t' --with-nth=2.. \
    --prompt="${heading}› " \
    --header='↑/↓ 选择；输入即筛选；Esc 取消' 2>> "$LOG_FILE")"
  pick_status=$?
  # 退出码 2 是参数不兼容等运行错误，去掉装饰类参数再试一次；130 是用户取消，不再重试。
  if (( pick_status == 2 )); then
    answer="$(printf '%s\n' "${lines[@]}" | /usr/bin/env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_OPTS_FILE \
      "$FZF_BIN" --no-multi --layout=reverse --height=40% \
      --delimiter=$'\t' --with-nth=2.. --prompt="${heading}› " 2>> "$LOG_FILE")"
    pick_status=$?
  fi
  (( pick_status == 0 )) || return 1
  [[ -n "$answer" ]] || return 1
  REPLY="${answer%%$'\t'*}"
  return 0
}

select_row() {
  local heading="$1" answer="" row="" index=1
  (( ${#ROWS} > 0 )) || return 1
  if fzf_ready; then
    log "$heading"
    fzf_pick_row "$heading" || return 1
    return 0
  fi
  log "$heading"
  for row in "${ROWS[@]}"; do
    log "  ${index}、${row#*$'\t'}"
    (( index++ ))
  done
  while true; do
    IFS= read -r 'answer?输入编号，直接回车取消：' || return 1
    [[ -n "$answer" ]] || return 1
    if [[ "$answer" == <-> ]] && (( answer >= 1 && answer <= ${#ROWS} )); then
      REPLY="${ROWS[$answer]%%$'\t'*}"
      return 0
    fi
    log '⚠ 编号无效，请重新输入。'
  done
}

# 可选第一个参数为超时秒数；新 FVM 版本首次冷启动 flutter_tools 远超 30 秒，默认留给普通刷新。
refresh_devices() {
  local seconds="${1:-30}" output="$LOG_FILE.devices.json" table=""
  log 'ℹ 正在读取 Flutter 设备列表…'
  if run_bounded "$seconds" "$output" "$FLUTTER_BIN" devices --machine --device-timeout 10; then
    table="$(json_helper devices "$output" "$PROJECT_PATH")" || { log "⚠ 无法解析设备响应：$output"; ROWS=(); return 1; }
    ROWS=("${(@f)table}")
    [[ -n "$table" ]] || ROWS=()
  else
    ROWS=()
    log "⚠ 设备查询失败，可重新加载或选择 iOS 模拟器；详情：$output"
    if [[ -s "$output" ]]; then
      log '➤ 最近输出：'
      /usr/bin/tail -n 5 "$output" | while IFS= read -r line; do log "  $line"; done
    fi
    return 1
  fi
}

read_simulator_inventory() {
  /usr/bin/xcode-select -p >/dev/null 2>&1 || die '未选择 Xcode 开发目录，请先完成 Xcode 安装与配置。'
  run_bounded 30 "$LOG_FILE.simulators.json" /usr/bin/xcrun simctl list --json || die 'simctl 不可用，请确认当前开发目录是完整 Xcode，且已接受许可。'
}

# 只在明确不兼容且用户精确输入 r 后才重选，一路回车不会再反复弹出型号 / 系统列表。
confirm_simulator_reselection() {
  local answer=""
  if IFS= read -r 'answer?输入 r 重新选择型号和系统；直接回车或其它输入停止：' && [[ "$answer" == [rR] ]]; then
    return 0
  fi
  log '➤ 已停止，未重复选择或再次创建模拟器。'
  return 1
}

# 与独立初始化脚本同款命名：型号名@时间-进程号；创建前刷新已有设备，撞名追加“ (2)”。
simulator_name_for() {
  local type_name="$1" base="" name="" output="$LOG_FILE.devices.json"
  [[ -n "$type_name" ]] || return 1
  base="${type_name}@$(/bin/date '+%Y.%m.%d %H:%M:%S')-$$"
  run_bounded 30 "$output" /usr/bin/xcrun simctl list devices --json || return 1
  name="$(json_helper unique-name "$output" "$base")" || return 1
  [[ -n "$name" ]] || return 1
  REPLY="$name"
}

# 型号与系统分别列出：先按“有无可搭配系统”推荐型号，再只列匹配该型号的系统。
create_simulator() {
  local table="" type_id="" runtime_id="" type_name="" runtime_name="" simulator_name=""
  local simulator_id="" answer="" row="" output="$LOG_FILE.create" create_status=0
  while true; do
    table="$(json_helper preferred-types "$LOG_FILE.simulators.json" "$(/usr/bin/uname -m)")" || die '无法解析模拟器型号。'
    ROWS=("${(@f)table}")
    [[ -n "$table" ]] || die 'Xcode 没有可用 iPhone 型号。'
    select_row '选择模拟器设备型号：' || return 1
    type_id="$REPLY"
    type_name=""
    for row in "${ROWS[@]}"; do
      if [[ "${row%%$'\t'*}" == "$type_id" ]]; then
        # 展示列的“（本机无可搭配系统）”标注只用于选择，不进入设备名。
        type_name="${row#*$'\t'}"
        type_name="${type_name%%'（本机无可搭配系统）'}"
        break
      fi
    done
    [[ -n "$type_name" ]] || type_name="$type_id"
    table="$(json_helper runtimes "$LOG_FILE.simulators.json")" || die '无法解析 iOS Runtime。'
    [[ -n "$table" ]] || die '没有可用的 iOS Runtime，请在 Xcode → Settings → Components（旧版 Platforms）安装 iOS，再重新运行。'
    table="$(json_helper compatible-runtimes "$LOG_FILE.simulators.json" "$(/usr/bin/uname -m)" "$type_id")" || die '无法匹配所选型号的 iOS 系统。'
    ROWS=("${(@f)table}")
    if [[ -z "$table" ]]; then
      log '✖ 所选型号没有可搭配的已安装 iOS 系统；请在 Xcode 安装对应 Runtime，或重新选择型号。'
      confirm_simulator_reselection || return 1
      continue
    fi
    select_row '选择 iOS 系统版本（已按所选型号匹配排序）：' || return 1
    runtime_id="$REPLY"
    runtime_name=""
    for row in "${ROWS[@]}"; do
      if [[ "${row%%$'\t'*}" == "$runtime_id" ]]; then
        runtime_name="${row#*$'\t'}"
        break
      fi
    done
    simulator_name_for "$type_name" || die '无法确认唯一的模拟器名称。'
    simulator_name="$REPLY"
    log "将创建模拟器：$type_name / $runtime_name"
    log "➤ 新名称：$simulator_name"
    IFS= read -r 'answer?回车创建并启动；非空取消：' || return 1
    [[ -z "$answer" ]] || return 1
    create_status=0
    run_bounded 45 "$output" /usr/bin/xcrun simctl create "$simulator_name" "$type_id" "$runtime_id" || create_status=$?
    simulator_id="$(/bin/cat "$output" 2>/dev/null)"
    if (( create_status == 0 )); then
      if [[ ! "$simulator_id" =~ '^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$' ]]; then
        log "✖ simctl 没有返回有效 UDID：$output"
        log '➤ 已停止，未自动重试；请检查 Simulator 设备列表。'
        return 1
      fi
      REPLY="$simulator_id"
      return 0
    fi
    # 只有 Xcode 明确写出 Incompatible device 才算组合不受支持；
    # 泛化的 Unable to create a device for device type 可能来自权限或状态问题，不自动重选。
    if (( create_status != 124 )) && [[ "$simulator_id" == *'Incompatible device'* ]]; then
      log "⚠ 当前型号 / 系统组合不受支持：$simulator_id"
      log '➤ 未删除任何既有模拟器，设备列表保持不变。'
      confirm_simulator_reselection || return 1
      continue
    fi
    log "✖ 创建失败（退出码 ${create_status}），未自动重试，未删除任何既有模拟器：$output"
    return 1
  done
}

# Xcode 27 起模拟器界面改名为 DeviceHub.app 并移到 Xcode.app/Contents/Applications；
# 旧版为 Xcode.app/Contents/Developer/Applications/Simulator.app，两种布局都要认。
simulator_interface_path() {
  local developer="$1" candidate=""
  for candidate in "$developer/Applications/Simulator.app" "${developer:h}/Applications/Simulator.app" \
    "${developer:h}/Applications/DeviceHub.app"; do
    [[ -d "$candidate" ]] || continue
    REPLY="$candidate"
    return 0
  done
  return 1
}

simulator_interface_app() {
  local simctl_path=""
  simctl_path="$(/usr/bin/xcrun --find simctl 2>/dev/null)" || return 1
  [[ "$simctl_path" == */usr/bin/simctl ]] || return 1
  simulator_interface_path "${simctl_path%/usr/bin/simctl}"
}

# 设备已启动，界面打不开只提示，不终止本次运行。
reveal_simulator_interface() {
  local simulator_id="$1" app=""
  if ! simulator_interface_app; then
    log '⚠ 当前 Xcode 没有 Simulator / Device Hub，跳过打开界面；设备已启动，可在 Xcode → Devices and Simulators 查看。'
    return 1
  fi
  app="$REPLY"
  if [[ "${app:t}" == 'Simulator.app' ]]; then
    /usr/bin/open -a "$app" --args -CurrentDeviceUDID "$simulator_id" || {
      log "⚠ 无法打开模拟器界面：$app"
      return 1
    }
    log "➤ 已打开模拟器界面：$app"
    return 0
  fi
  /usr/bin/open -a "$app" || {
    log "⚠ 无法打开模拟器界面：$app"
    return 1
  }
  log "➤ 已打开 Device Hub：$app"
  log "➤ 请在 Device Hub 按设备名选中该模拟器（$simulator_id）。"
}

select_ios_simulator() {
  local table="" simulator_id="" row="" attempt=0
  read_simulator_inventory
  table="$(json_helper simulators "$LOG_FILE.simulators.json")" || die '无法解析模拟器列表。'
  ROWS=("${(@f)table}")
  [[ -n "$table" ]] || ROWS=()
  if (( ${#ROWS} > 0 )); then
    ROWS+=($'create\t创建新的 iOS 模拟器')
    select_row '选择 iOS 模拟器：' || return 1
    simulator_id="$REPLY"
  else
    log 'ℹ 尚无可用 iOS 模拟器，进入内置初始化流程。'
    simulator_id=create
  fi
  if [[ "$simulator_id" == create ]]; then
    create_simulator || return 1
    simulator_id="$REPLY"
  fi
  /usr/bin/xcrun simctl boot "$simulator_id" > "$LOG_FILE.boot" 2>&1 || {
    /usr/bin/xcrun simctl list devices booted | /usr/bin/grep -Fq "$simulator_id" || die "模拟器启动失败：$LOG_FILE.boot"
  }
  log "ℹ 等待所选模拟器就绪：$simulator_id"
  run_bounded 180 "$LOG_FILE.bootstatus" /usr/bin/xcrun simctl bootstatus "$simulator_id" -b || die "模拟器未在 180 秒内启动完成：$LOG_FILE.bootstatus"
  reveal_simulator_interface "$simulator_id" || log 'ℹ 界面未打开不影响运行；Flutter 仍会使用已启动的模拟器。'
  # 新建模拟器后 Flutter 首次冷启动可能重建 flutter_tools，前两次给足时间；仍失败再按普通超时重试。
  wait_for_simulator_recognition "$simulator_id"
}

# 新建模拟器后等设备出现在 Flutter 列表：首次 120 秒、第二次 60 秒、之后 30 秒，共 4 次。
wait_for_simulator_recognition() {
  local simulator_id="$1" attempt=0 timeout=30
  for attempt in 1 2 3 4; do
    if (( attempt == 1 )); then
      timeout=120
    elif (( attempt == 2 )); then
      timeout=60
    else
      timeout=30
    fi
    refresh_devices "$timeout" || { log "ℹ 第 ${attempt} 次读取设备列表失败，将继续重试。"; /bin/sleep 2; continue; }
    for row in "${ROWS[@]}"; do
      if [[ "${(L)${row%%$'\t'*}}" == "${(L)simulator_id}" ]]; then
        DEVICE_ID="${row%%$'\t'*}"
        return 0
      fi
    done
    log 'ℹ Flutter 尚未发现所选模拟器，正在重新加载…'
    /bin/sleep 3
  done
  die '模拟器已启动，但 Flutter 尚未识别；保留模拟器，请检查 flutter doctor 后重试。'
}

# Android SDK 原生命令列出 AVD；单独 launchd 作业防止模拟器跟随终端断连。
start_android_emulator() {
  local emulator="" candidate="" output="$LOG_FILE.avds" avd="" digest="" avd_session="" avd_label=""
  local -a candidates=("${ANDROID_HOME:-}/emulator/emulator" "${ANDROID_SDK_ROOT:-}/emulator/emulator"
    "$HOME/Library/Android/sdk/emulator/emulator" "${commands[emulator]:-}")
  for candidate in "${candidates[@]}"; do
    if [[ -n "$candidate" && -x "$candidate" && ! -d "$candidate" ]]; then
      emulator="${candidate:A}"
      break
    fi
  done
  [[ -n "$emulator" ]] || { log '⚠ 未找到 Android SDK emulator；设置 ANDROID_HOME / ANDROID_SDK_ROOT，或先从 Android Studio 启动模拟器。'; return 1; }
  run_bounded 30 "$output" "$emulator" -list-avds || { log "⚠ 无法读取 Android AVD：$output"; return 1; }
  ROWS=()
  while IFS= read -r avd; do
    avd="${avd%$'\r'}"
    [[ "$avd" =~ '^[A-Za-z0-9_.-]+$' ]] && ROWS+=("${avd}"$'\t'"${avd}")
  done < "$output"
  (( ${#ROWS} > 0 )) || { log 'ℹ 尚无 Android AVD，请先在 Android Studio Device Manager 创建，然后重新加载。'; return 1; }
  select_row '选择已配置的 Android AVD：' || return 1
  avd="$REPLY"
  digest="$(printf '%s\0%s' "$emulator" "$avd" | /usr/bin/shasum -a 256)"
  digest="${digest%% *}"
  avd_label="com.jobs.flutterrunner.avd.$digest"
  avd_session="$STATE_ROOT/android-$digest"
  [[ ! -L "$STATE_ROOT" && ! -L "$avd_session" ]] || die '模拟器会话目录不能是符号链接。'
  /bin/mkdir -p "$avd_session" || die '无法创建模拟器会话目录。'
  if /bin/launchctl print "gui/$UID/$avd_label" 2>/dev/null | /usr/bin/grep -Fq 'state = running'; then
    log 'ℹ 该 AVD 已由后台启动，请在设备列表选择对应设备。'
    return
  fi
  /bin/launchctl bootout "gui/$UID/$avd_label" >/dev/null 2>&1
  json_helper emulator-plist "$avd_session" "$avd_label" "$emulator" "$avd" >/dev/null || die '无法生成 Android 模拟器后台配置。'
  /bin/launchctl bootstrap "gui/$UID" "$avd_session/job.plist" >> "$LOG_FILE" 2>&1 || { log "⚠ AVD 启动失败，详情：$LOG_FILE"; return 1; }
  log "✔ 已请求后台启动 AVD：$avd；就绪后在设备列表选择，尚未出现可重新加载。"
  log "模拟器日志：$avd_session/emulator.log"
}

choose_device() {
  while true; do
    refresh_devices
    (( ${#ROWS} > 0 )) || log 'ℹ 暂无当前项目可运行的设备；连接手机、启动模拟器后可重新加载。'
    [[ ! -d "$PROJECT_PATH/ios" ]] || ROWS+=($'ios\tiOS 模拟器（启动已有 / 缺失时初始化）')
    [[ ! -d "$PROJECT_PATH/android" ]] || ROWS+=($'android-avd\t启动已有 Android 模拟器')
    ROWS+=($'refresh\t重新加载设备列表')
    select_row '选择 Flutter 运行设备：' || exit 0
    case "$REPLY" in
      refresh) continue ;;
      ios) select_ios_simulator && return ;;
      android-avd) start_android_emulator ;;
      *) DEVICE_ID="$REPLY"; return ;;
    esac
  done
}

session_live() {
  [[ ! -f "$SESSION_DIR/exitcode" ]] || return 1
  /bin/launchctl print "gui/$UID/$JOB_LABEL" 2>/dev/null | /usr/bin/grep -Eq '^[[:space:]]*pid = [1-9][0-9]*'
}

prepare_session() {
  local digest="" tick=0
  digest="$(printf '%s\0%s' "$PROJECT_PATH" "$DEVICE_ID" | /usr/bin/shasum -a 256)"
  digest="${digest%% *}"
  JOB_LABEL="com.jobs.flutterrunner.$digest"
  SESSION_DIR="$STATE_ROOT/$digest"
  [[ ! -L "$STATE_ROOT" && ! -L "$SESSION_DIR" ]] || die '后台会话目录不能是符号链接。'
  /bin/mkdir -p "$SESSION_DIR" || die '无法创建后台会话目录。'
  if session_live; then
    log 'ℹ 当前项目 / 设备已经在运行，连接已有日志。'
    return
  fi
  START_LOCK="$SESSION_DIR/start.lock"
  [[ ! -L "$START_LOCK" ]] || die '任务锁不能是符号链接。'
  : >> "$START_LOCK"
  zmodload zsh/system || die '系统 zsh 缺少文件锁模块。'
  zsystem flock -t 0 -f LOCK_FD "$START_LOCK" || die '另一个终端正在启动该任务；稍后重新右键。'
  if session_live; then
    zsystem flock -u "$LOCK_FD"
    LOCK_FD=""
    return
  fi
  /bin/launchctl bootout "gui/$UID/$JOB_LABEL" >/dev/null 2>&1
  # 上一次运行保留为独立日志，重启不会擦掉失败现场。
  if [[ -e "$SESSION_DIR/run.log" ]]; then
    /bin/mv "$SESSION_DIR/run.log" "$SESSION_DIR/run.$(/bin/date '+%Y%m%d-%H%M%S').$$.log" || die '无法归档已有日志。'
  fi
  /bin/rm -f "$SESSION_DIR/exitcode" "$SESSION_DIR/control.fifo"
  /bin/cp "$SCRIPT_PATH" "$SESSION_DIR/RunFlutterProject.zsh" || die '无法保存独立后台脚本。'
  /bin/cp "$HELPER" "$SESSION_DIR/FlutterRunner.jxa" || die '无法保存后台解析脚本。'
  /usr/bin/mkfifo "$SESSION_DIR/control.fifo" || die '无法创建后台控制通道。'
  : > "$SESSION_DIR/run.log"
  json_helper plist "$SESSION_DIR" "$JOB_LABEL" "$SESSION_DIR/RunFlutterProject.zsh" "$PROJECT_PATH" "$FLUTTER_BIN" "$DEVICE_ID" >/dev/null || die '无法生成 launchd 会话配置。'
  /usr/bin/plutil -lint "$SESSION_DIR/job.plist" >> "$LOG_FILE" 2>&1 || die '后台任务配置无效。'
  /bin/launchctl bootstrap "gui/$UID" "$SESSION_DIR/job.plist" >> "$LOG_FILE" 2>&1 || die 'launchd 无法托管任务，请在当前桌面登录会话重新运行，详见操作日志。'
  for tick in 1 2 3 4 5 6 7 8 9 10; do
    session_live && break
    [[ ! -f "$SESSION_DIR/exitcode" ]] || break
    /bin/sleep 0.2
  done
  zsystem flock -u "$LOCK_FD"
  LOCK_FD=""
  if ! session_live && [[ ! -f "$SESSION_DIR/exitcode" ]]; then
    die "后台任务未成功启动，请检查会话日志：$SESSION_DIR/run.log"
  fi
  log '✔ 后台任务已提交；构建或启动结果请查看下方日志。'
}

send_control() {
  local mode="$1" message=""
  session_live || { log '⚠ 后台任务已结束。'; return 1; }
  message="$(json_helper command "$SESSION_DIR/run.log" "$mode" 2>> "$LOG_FILE")" || { log '⚠ Flutter 尚未提供 appId，稍后重试；构建期间可用 s 停止。'; return 1; }
  # 读写模式打开 FIFO 不会因任务恰好退出而永久等待读端。
  [[ -p "$SESSION_DIR/control.fifo" ]] || return 1
  ( exec 8<>"$SESSION_DIR/control.fifo"; print -r -- "$message" >&8 )
}

stop_session() {
  local tick=0
  send_control stop
  for tick in 1 2 3 4 5; do
    session_live || break
    /bin/sleep 1
  done
  if /bin/launchctl print "gui/$UID/$JOB_LABEL" >/dev/null 2>&1; then
    /bin/launchctl bootout "gui/$UID/$JOB_LABEL" >> "$LOG_FILE" 2>&1 || { log '✖ 无法停止 launchd 任务，请检查操作日志。'; return 1; }
  fi
  log '✔ 已停止该项目 / 设备的后台运行。'
}

watch_session() {
  local answer=""
  log ''
  log '━━━━━━━━━━ Flutter 构建与运行 ━━━━━━━━━━'
  log "完整原始日志：$SESSION_DIR/run.log"
  log '控制：输入 r 热重载 / R 热重启 / s 停止 / d 离开，再按回车。'
  log '关闭终端或 Ctrl+C 只离开；[警告] 不等于失败，以 [成功] / [错误] 为准。'
  log '──────────────────────────────────────'
  /usr/bin/osascript -l JavaScript "$HELPER" watch-log "$SESSION_DIR/run.log" "$SESSION_DIR/exitcode" &
  TAIL_PID=$!
  while true; do
    # 不输出悬挂的输入提示符，避免异步日志接在“运行控制 >”后面。
    IFS= read -r answer || return 0
    case "$answer" in
      r) send_control reload ;;
      R) send_control restart ;;
      s) stop_session && return ;;
      d) log '后台任务继续运行；再次右键并选择同一设备可重看日志及停止。'; return ;;
      *)
        if session_live; then
          log 'ℹ 后台任务仍在运行。'
        else
          log "ℹ 后台任务已结束，退出码：$(/bin/cat "$SESSION_DIR/exitcode" 2>/dev/null || print unknown)"
          return
        fi
        ;;
    esac
  done
}

# 由 launchd 启动的独立入口；stdin 留在 FIFO，不继承终端的 EOF / HUP。
run_worker() {
  local session="$1" project="$2" flutter="$3" device="$4" result=0 child_pid=""
  setopt NO_NOMATCH PIPE_FAIL
  umask 077
  [[ -d "$session" && ! -L "$session" ]] || return 64
  [[ -p "$session/control.fifo" && -x "$flutter" ]] || { print 64 > "$session/exitcode"; return 64; }
  SCRIPT_DIR="${session:A}"
  HELPER="$SCRIPT_DIR/FlutterRunner.jxa"
  [[ "$(json_helper validate "$project")" == true ]] || { print '项目身份已变化，停止运行。'; print 65 > "$session/exitcode"; return 65; }
  cd "$project" || { print 66 > "$session/exitcode"; return 66; }
  exec 9<>"$session/control.fifo"
  trap '[[ -z "$child_pid" ]] || kill -TERM "$child_pid" 2>/dev/null; print 143 > "$session/exitcode"; exit 143' TERM INT
  print -r -- "Flutter 后台运行：$project / $device"
  # fd 9 只负责保持 FIFO 打开；Dart 的异步 stdin 必须另用只读描述符。
  # macOS 下直接继承 O_RDWR FIFO 会让 stdin.listen 收不到热重载 / 停止请求。
  "$flutter" run --machine -d "$device" < "$session/control.fifo" &
  child_pid=$!
  wait "$child_pid" || result=$?
  print -r -- "Flutter 已退出：$result"
  print -r -- "$result" > "$session/exitcode"
  return "$result"
}

main() {
  if [[ "${1:-}" == --worker ]]; then
    (( $# == 5 )) || return 64
    run_worker "$2" "$3" "$4" "$5"
    return $?
  fi
  show_script_intro_and_wait
  initialize_runtime
  trap 'leave_terminal' EXIT
  trap 'exit 0' HUP INT TERM
  read_project "$@"
  find_flutter
  choose_device
  prepare_session
  watch_session
}

main "$@"
