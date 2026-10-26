#!/bin/zsh
# 脚本自述：
# - 脚本名称：RepairAndroidSimulator.zsh
# - 核心用途：只对 Android Emulator 执行存储诊断与逐项确认的修复。
# - 影响范围：选定模拟器的安装位置、编译缓存、明确包名或备份后的 AVD 配置。
# - 运行提示：--check 只查询；交互修复先阅读自述，危险动作输入 YES；不安装工具、不 Wipe Data。

SCRIPT_DIR=""
LOG_FILE=""
MODE="repair"
REQUESTED_SERIAL=""
ADB_BIN=""
EMULATOR_BIN=""
DEVICE_ID=""
AVD_NAME=""
AVD_HOME=""
AVD_PATH=""
AVD_DESCRIPTOR=""
CONFIG_PATH=""
BACKUP_PATH=""
THRESHOLD_MB=800
DEVICE_SERIALS=()
# 给交互终端突出自述标题，日志与非交互输出保持纯文本。
intro_line() {
  local role="$1"
  local message="$2"
  if [[ -t 1 && -n "${TERM:-}" && "${TERM}" != dumb && -z "${NO_COLOR+x}" ]]; then
    if [[ "$role" == title ]]; then
      /usr/bin/printf '\033[1;31m%s\033[0m\n' "$message"
    else
      /usr/bin/printf '\033[0;34m%s\033[0m\n' "$message"
    fi
  else
    print -r -- "$message"
  fi
}
# 第一屏声明作用范围；只读与帮助参数允许无交互执行。
show_script_intro_and_wait() {
  intro_line title '━━━━━━━━━━ Android 模拟器检测与修复 ━━━━━━━━━━'
  intro_line body '1、用途：诊断 /data 空间与安装位置；仅接受 Android Emulator，排除物理真机。'
  intro_line body '2、影响：每项修复单独确认；卸载删除所选包数据，容量配置须先停机并完整备份 AVD。'
  intro_line body '3、边界：不自动安装 SDK，不批量删内置应用，不 Wipe Data；配置增大不保证已有 userdata 扩容。'
  intro_line body '4、策略：--check 只查询且不写本工具日志；修复日志位于系统临时目录的 JobsAndroidSimulatorRepairer-*.log。'
  intro_line body '5、取消：直接回车跳过可选操作，危险操作只接受 YES；Ctrl+C 随时停止。'
  if (( ${@[(Ie)--check]} || ${@[(Ie)--help]} || ${@[(Ie)-h]} )); then
    return 0
  fi
  [[ -t 0 ]] || { print -u2 -r -- '错误：修复需要可交互终端；诊断可使用 --check。'; exit 1; }
  read -r '?已了解用途，按回车进入；Ctrl+C 取消：' _ || exit 0
}
# 严格解析固定入口，不提供绕过确认的自动同意参数。
parse_arguments() {
  while (( $# > 0 )); do
    case "$1" in
      --check) MODE="check"; shift ;;
      --repair) shift ;;
      --serial)
        (( $# >= 2 )) || { print -u2 -r -- '错误：--serial 缺少值。'; exit 2; }
        REQUESTED_SERIAL="$2"
        shift 2
        ;;
      --help|-h)
        print -r -- '用法：/bin/zsh RepairAndroidSimulator.zsh [--check|--repair] [--serial emulator-5554]'
        print -r -- '可用环境：ANDROID_ADB_BIN、ANDROID_EMULATOR_BIN、ANDROID_SDK_ROOT、ANDROID_HOME、ANDROID_AVD_HOME、ANDROID_USER_HOME。'
        exit 0
        ;;
      *) print -u2 -r -- "错误：未知参数 $1"; exit 2 ;;
    esac
  done
  if [[ -n "$REQUESTED_SERIAL" && ! "$REQUESTED_SERIAL" =~ '^emulator-[0-9]+$' ]]; then
    print -u2 -r -- '错误：仅允许 emulator-数字 形式的 Android Emulator 序列号。'
    exit 2
  fi
}
# 用户确认后才准备日志；只读模式不创建文件。
initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  umask 077
  SCRIPT_DIR="${ZSH_ARGZERO:A:h}"
  if [[ "$MODE" == repair ]]; then
    LOG_FILE="$(/usr/bin/mktemp "${TMPDIR:-/tmp/}JobsAndroidSimulatorRepairer-XXXXXX.log")" || exit 1
  fi
}
# 清除终端控制序列，避免设备输出污染终端或持久日志。
safe_text() {
  /usr/bin/awk 'BEGIN { esc=sprintf("%c",27) } { gsub(esc "\\[[0-?]*[ -/]*[@-~]", ""); gsub(/[\001-\010\013-\037\177]/, ""); print }'
}
# 同步输出纯文本；只读模式只显示到标准输出。
log() {
  if [[ -n "$LOG_FILE" ]]; then
    print -r -- "$*" | safe_text | /usr/bin/tee -a "$LOG_FILE"
  else
    print -r -- "$*" | safe_text
  fi
}
# 普通修复直接回车跳过；非空输入才执行。
ask_run() {
  local answer=""
  read -r "answer?$1（直接回车跳过，输入任意字符后回车执行）：" || return 1
  [[ -n "$answer" ]]
}
# 删除、缓存重置及容量修改必须精确输入 YES。
confirm_yes() {
  local answer=""
  log "⚠ $1"
  read -r 'answer?输入 YES 执行，其它输入取消：' || return 1
  [[ "$answer" == YES ]]
}
# 按显式覆盖、当前 PATH 和标准 SDK 目录发现已有工具，不安装未知软件。
discover_tools() {
  local candidate=""
  local root=""
  local roots=("${ANDROID_SDK_ROOT:-}" "${ANDROID_HOME:-}" "${HOME}/Library/Android/sdk")
  if [[ -n "${ANDROID_ADB_BIN:-}" ]]; then
    [[ -x "$ANDROID_ADB_BIN" && -f "$ANDROID_ADB_BIN" ]] || { log '错误：ANDROID_ADB_BIN 不可执行。'; exit 1; }
    ADB_BIN="$ANDROID_ADB_BIN"
  else
    candidate="$(command -v adb 2>/dev/null)"
    [[ -n "$candidate" && -f "$candidate" && -x "$candidate" ]] && ADB_BIN="$candidate"
    for root in "${roots[@]}"; do
      [[ -z "$ADB_BIN" && -n "$root" && -x "$root/platform-tools/adb" ]] && ADB_BIN="$root/platform-tools/adb"
    done
  fi
  [[ -n "$ADB_BIN" ]] || { log '错误：未找到 adb；请先在 Android Studio 的 SDK Manager 准备 Android SDK Platform-Tools。'; exit 1; }
  "$ADB_BIN" version >/dev/null 2>&1 || { log "错误：adb 健康检查失败：$ADB_BIN"; exit 1; }
  if [[ -n "${ANDROID_EMULATOR_BIN:-}" ]]; then
    [[ -x "$ANDROID_EMULATOR_BIN" && -f "$ANDROID_EMULATOR_BIN" ]] || { log '错误：ANDROID_EMULATOR_BIN 不可执行。'; exit 1; }
    EMULATOR_BIN="$ANDROID_EMULATOR_BIN"
  else
    candidate="$(command -v emulator 2>/dev/null)"
    [[ -n "$candidate" && -f "$candidate" && -x "$candidate" ]] && EMULATOR_BIN="$candidate"
    roots+=("${ADB_BIN:A:h:h}")
    for root in "${roots[@]}"; do
      [[ -z "$EMULATOR_BIN" && -n "$root" && -x "$root/emulator/emulator" ]] && EMULATOR_BIN="$root/emulator/emulator"
    done
  fi
  if [[ -n "$EMULATOR_BIN" ]] && ! "$EMULATOR_BIN" -version >/dev/null 2>&1; then
    log "警告：emulator 不健康，禁止自动冷启动：$EMULATOR_BIN"
    EMULATOR_BIN=""
  fi
  log "ADB：$ADB_BIN"
  log "Emulator：${EMULATOR_BIN:-未找到；容量流程不会自动冷启动}"
}
# 只收集已在线的 emulator-数字 设备；未经授权与物理设备不进入选择。
collect_devices() {
  local output=""
  output="$("$ADB_BIN" devices 2>&1)" || { log "错误：adb devices 失败：$output"; exit 1; }
  DEVICE_SERIALS=("${(@f)$(print -r -- "$output" | /usr/bin/awk '$1 ~ /^emulator-[0-9]+$/ && $2 == "device" {print $1}')}")
  DEVICE_SERIALS=("${(@)DEVICE_SERIALS:#}")
  (( ${#DEVICE_SERIALS[@]} > 0 )) || { log '错误：未发现在线 Android Emulator；请先启动 AVD。物理真机不会列入。'; exit 1; }
}
# 从 emulator console 取得真实 AVD 名称，并复验 qemu 属性。
device_avd_name() {
  local serial="$1"
  local result=""
  local name=""
  [[ "$serial" =~ '^emulator-[0-9]+$' ]] || return 1
  result="$("$ADB_BIN" -s "$serial" emu avd name 2>/dev/null)" || return 1
  name="$(print -r -- "$result" | /usr/bin/tr -d '\r' | /usr/bin/awk 'NF && $0 != "OK" { print; exit }')"
  [[ "$name" =~ '^[A-Za-z0-9_.-]+$' && "$name" != . && "$name" != .. ]] || return 1
  result="$("$ADB_BIN" -s "$serial" shell getprop ro.kernel.qemu 2>/dev/null)" || return 1
  [[ "${result//$'\r'/}" == 1 ]] || return 1
  print -r -- "$name"
}
# 每次写操作前复验 serial 与 AVD，防止选择期间设备被替换。
ensure_selected_device() {
  local current=""
  current="$(device_avd_name "$DEVICE_ID")" || { log '错误：设备已离线或无法确认 Android Emulator 身份。'; return 1; }
  [[ "$current" == "$AVD_NAME" ]] || { log '错误：同一序列号现已指向其它 AVD，已停止。'; return 1; }
}
# 单设备直接选定，多设备使用编号；不把提示混入返回值。
select_device() {
  local index=0
  local answer=""
  if [[ -n "$REQUESTED_SERIAL" ]]; then
    (( ${DEVICE_SERIALS[(Ie)$REQUESTED_SERIAL]} )) || { log '错误：指定模拟器不在线。'; exit 1; }
    DEVICE_ID="$REQUESTED_SERIAL"
  elif (( ${#DEVICE_SERIALS[@]} == 1 )); then
    DEVICE_ID="${DEVICE_SERIALS[1]}"
  else
    for (( index=1; index <= ${#DEVICE_SERIALS[@]}; index++ )); do
      log "$index、${DEVICE_SERIALS[$index]}"
    done
    read -r 'answer?选择模拟器序号（直接回车取消）：' || exit 0
    [[ "$answer" =~ '^[0-9]+$' && ${#answer} -le 3 ]] || exit 0
    index=$((10#$answer))
    (( index >= 1 && index <= ${#DEVICE_SERIALS[@]} )) || { log '错误：序号不在列表中。'; exit 1; }
    DEVICE_ID="${DEVICE_SERIALS[$index]}"
  fi
  AVD_NAME="$(device_avd_name "$DEVICE_ID")" || { log '错误：无法确认所选 Android Emulator 的 AVD 身份。'; exit 1; }
  log "选择：$DEVICE_ID；AVD：$AVD_NAME"
}
# 解析 df 的 Available 列；无法识别时返回失败，不伪造 0 或空间充足。
space_report() {
  local output=""
  local available=""
  output="$("$ADB_BIN" -s "$DEVICE_ID" shell df -k /data 2>&1)" || { log "错误：空间查询失败：$output"; return 1; }
  available="$(print -r -- "$output" | /usr/bin/tr -d '\r' | /usr/bin/awk 'NR==1 { for(i=1;i<=NF;i++) if($i=="Available" || $i=="Avail") col=i; next } col && NF>=col {v=$col} END {if(v ~ /^[0-9]+$/) print v}')"
  [[ "$available" =~ '^[0-9]+$' && ${#available} -le 14 ]] || { log "错误：无法解析 /data 可用空间：$output"; return 1; }
  log "/data 可用：$(( available / 1024 )) MB；提示阈值：$THRESHOLD_MB MB。"
  if (( available / 1024 < THRESHOLD_MB )); then
    log '警告：空间偏低；按需选择修复动作。'
    return 1
  fi
  return 0
}
# 取得 /data 当前文件系统总量；未知格式时拒绝容量修改。
data_total_mb() {
  local output=""
  local total=""
  output="$("$ADB_BIN" -s "$DEVICE_ID" shell df -k /data 2>/dev/null)" || return 1
  total="$(print -r -- "$output" | /usr/bin/tr -d '\r' | /usr/bin/awk 'NR==1 {for(i=1;i<=NF;i++) if($i=="1K-blocks" || $i=="1024-blocks") col=i; next} col && NF>=col {v=$col} END {if(v ~ /^[0-9]+$/) print v}')"
  [[ "$total" =~ '^[0-9]+$' && ${#total} -le 14 ]] || return 1
  print -r -- "$(( (total + 1023) / 1024 ))"
}
# 显示安装位置和空间；诊断错误保留非零退出码。
diagnose_device() {
  local location=""
  local failed=0
  ensure_selected_device || return 1
  location="$("$ADB_BIN" -s "$DEVICE_ID" shell pm get-install-location 2>&1)" || { log "错误：安装位置查询失败：$location"; return 1; }
  log "设备：$DEVICE_ID；AVD：$AVD_NAME；安装位置：$location"
  location="${location//$'\r'/}"
  [[ "$location" =~ '^0([[:space:]]*\[[^]]*\])?[[:space:]]*$' ]] || { log '警告：默认安装位置不是 0（自动）或响应无法识别。'; failed=1; }
  space_report || failed=1
  return "$failed"
}
# 只读模式支持指定设备或依次报告全部模拟器，不初始化日志和 AVD 配置。
run_checks_if_requested() {
  [[ "$MODE" == check ]] || return 0
  local serial=""
  local failed=0
  for serial in "${DEVICE_SERIALS[@]}"; do
    [[ -z "$REQUESTED_SERIAL" || "$REQUESTED_SERIAL" == "$serial" ]] || continue
    DEVICE_ID="$serial"
    AVD_NAME="$(device_avd_name "$serial")" || { log "错误：无法确认 $serial 的 AVD 身份。"; failed=1; continue; }
    diagnose_device || failed=1
  done
  if [[ -n "$REQUESTED_SERIAL" ]] && (( ! ${DEVICE_SERIALS[(Ie)$REQUESTED_SERIAL]} )); then
    log '错误：指定模拟器不在线。'
    failed=1
  fi
  exit "$failed"
}
# 确认后恢复安装位置，并查询实际结果，失败不报告修复成功。
fix_install_location() {
  ask_run '恢复当前模拟器的默认安装位置 0（自动）' || return 0
  ensure_selected_device || return 1
  local output=""
  output="$("$ADB_BIN" -s "$DEVICE_ID" shell pm set-install-location 0 2>&1)" || { log "错误：安装位置修改失败：$output"; return 1; }
  if print -r -- "$output" | /usr/bin/grep -Eiq 'error|failure|exception|unknown|not found'; then
    log "错误：设备拒绝安装位置修改：$output"
    return 1
  fi
  output="$("$ADB_BIN" -s "$DEVICE_ID" shell pm get-install-location 2>&1)" || { log "错误：安装位置复检失败：$output"; return 1; }
  output="${output//$'\r'/}"
  [[ "$output" =~ '^0([[:space:]]*\[[^]]*\])?[[:space:]]*$' ]] || { log "错误：安装位置未确认恢复为自动：$output"; return 1; }
  log '✔ 已回读确认安装位置为 0（自动）。'
  space_report
}
# 缓存重置可触发之后重新编译，只在明确 YES 后执行。
reset_compile_cache() {
  confirm_yes '重置所选模拟器全部包的编译状态；之后启动应用可能重新编译，空间收益需复检。' || return 0
  ensure_selected_device || return 1
  local output=""
  output="$("$ADB_BIN" -s "$DEVICE_ID" shell cmd package compile --reset -a 2>&1)" || { log "错误：编译状态重置失败或设备不支持：$output"; return 1; }
  if print -r -- "$output" | /usr/bin/grep -Eiq 'failure|error|exception|unknown|not found'; then
    log "错误：设备拒绝编译状态重置：$output"
    return 1
  fi
  log '编译状态重置命令已完成；以下空间查询决定实际结果。'
  space_report
}
# 仅卸载用户明确指定且精确存在的第三方包，禁止内置包清单或模糊匹配。
uninstall_exact_package() {
  local package=""
  local packages=""
  local output=""
  read -r 'package?输入完整第三方包名（直接回车取消）：' || return 0
  [[ -n "$package" ]] || return 0
  [[ "$package" =~ '^[A-Za-z][A-Za-z0-9_]*([.][A-Za-z][A-Za-z0-9_]*)+$' && ${#package} -le 255 ]] || { log '错误：包名格式非法。'; return 1; }
  ensure_selected_device || return 1
  packages="$("$ADB_BIN" -s "$DEVICE_ID" shell pm list packages -3 2>&1)" || { log "错误：第三方包清单查询失败：$packages"; return 1; }
  print -r -- "$packages" | /usr/bin/tr -d '\r' | /usr/bin/grep -Fxq -- "package:$package" || { log '错误：该精确包名不在第三方应用清单；未卸载。'; return 1; }
  confirm_yes "卸载 $package，删除该包在 $DEVICE_ID 上的应用与数据。" || return 0
  ensure_selected_device || return 1
  output="$("$ADB_BIN" -s "$DEVICE_ID" uninstall "$package" 2>&1)" || { log "错误：卸载失败：$output"; return 1; }
  [[ "${output//$'\r'/}" == Success ]] || { log "错误：设备未确认卸载成功：$output"; return 1; }
  log "✔ 设备报告已卸载：$package"
  space_report
}
# 配置与描述符只接受真实目录，拒绝符号链接和 AVD 根之外的写入。
resolve_avd_paths() {
  local descriptor_path=""
  local relative_path=""
  AVD_HOME="${ANDROID_AVD_HOME:-${ANDROID_USER_HOME:-${HOME}/.android}/avd}"
  [[ "$AVD_HOME" == /* && -d "$AVD_HOME" && ! -L "$AVD_HOME" ]] || { log '错误：AVD 根目录不是普通绝对目录。'; return 1; }
  AVD_HOME="${AVD_HOME:A}"
  AVD_DESCRIPTOR="$AVD_HOME/$AVD_NAME.ini"
  [[ -f "$AVD_DESCRIPTOR" && ! -L "$AVD_DESCRIPTOR" ]] || { log '错误：找不到普通 AVD .ini 描述符。'; return 1; }
  if ! /usr/bin/awk -F= '$1=="path" {paths++} $1=="path.rel" {relative++} END {exit (paths>1 || relative>1)}' "$AVD_DESCRIPTOR"; then
    log '错误：AVD 描述符含重复 path 或 path.rel，无法确认解释一致。'
    return 1
  fi
  descriptor_path="$(/usr/bin/awk -F= '$1=="path" {sub(/^[^=]*=/, ""); print; exit}' "$AVD_DESCRIPTOR")"
  relative_path="$(/usr/bin/awk -F= '$1=="path.rel" {sub(/^[^=]*=/, ""); print; exit}' "$AVD_DESCRIPTOR")"
  if [[ -n "$descriptor_path" ]]; then
    AVD_PATH="$descriptor_path"
  elif [[ -n "$relative_path" ]]; then
    AVD_PATH="${AVD_HOME:h}/$relative_path"
  else
    AVD_PATH="$AVD_HOME/$AVD_NAME.avd"
  fi
  [[ "$AVD_PATH" == /* && -d "$AVD_PATH" && ! -L "$AVD_PATH" ]] || { log '错误：AVD 描述符指向非普通绝对目录。'; return 1; }
  AVD_PATH="${AVD_PATH:A}"
  [[ "$AVD_PATH" == "$AVD_HOME/"* && "$AVD_PATH" != "$AVD_HOME" ]] || { log '错误：AVD 位于所选 AVD 根之外；请在 Device Manager 人工处理。'; return 1; }
  CONFIG_PATH="$AVD_PATH/config.ini"
  [[ -f "$CONFIG_PATH" && ! -L "$CONFIG_PATH" ]] || { log '错误：config.ini 缺失或为符号链接。'; return 1; }
  [[ -z "$(/usr/bin/find "$AVD_PATH" -type l -print)" ]] || { log '错误：AVD 内存在符号链接；已拒绝自动写入和备份。'; return 1; }
  [[ "$(/usr/bin/awk -F= '$1=="AvdId" {n++} END {print n+0}' "$CONFIG_PATH")" == 1 ]] || { log '错误：config.ini 的 AvdId 缺失或重复。'; return 1; }
  [[ "$(/usr/bin/awk -F= '$1=="AvdId" {print $2; exit}' "$CONFIG_PATH")" == "$AVD_NAME" ]] || { log '错误：config.ini 的 AvdId 与在线模拟器不匹配。'; return 1; }
}
# 自定义 userdata、只读实例或无法确认运行参数时禁止自动容量调整。
validate_default_userdata() {
  local processes=""
  local matching=""
  local image=""
  if /usr/bin/awk -F= '($1=="disk.dataPartition.path" || $1=="disk.dataPartition.initPath") && length($2)>0 {found=1} END {exit !found}' "$CONFIG_PATH"; then
    log '错误：存在显式 disk.dataPartition.path 或 disk.dataPartition.initPath；不会只备份默认目录后修改自定义数据。'
    return 1
  fi
  processes="$(/bin/ps -axo command=)" || return 1
  matching="$(print -r -- "$processes" | /usr/bin/awk -v name="$AVD_NAME" -v directory="$AVD_PATH" '
    /qemu-system|\/emulator/ && (index($0," -avd " name " ") || index($0," -avd " name)==length($0)-length(" -avd " name)+1 || index($0," @" name " ") || index($0,directory)) {print}
  ')"
  [[ -n "$matching" ]] || { log '错误：无法确认当前 AVD 的进程参数；容量配置请在 Device Manager 人工处理。'; return 1; }
  if print -r -- "$matching" | /usr/bin/grep -Eq -- '(^|[[:space:]])-(data|datadir|read-only)([[:space:]=]|$)'; then
    log '错误：当前实例使用 -data、-datadir 或 -read-only；自动容量调整已拒绝。'
    return 1
  fi
  for image in "$AVD_PATH/userdata-qemu.img" "$AVD_PATH/userdata.img"; do
    [[ ! -e "$image" || ( -f "$image" && ! -L "$image" ) ]] || { log '错误：userdata 不是普通文件。'; return 1; }
  done
}
# 把官方配置中的字节或 K/M/G 大小转成 MB；未知单位拒绝推断。
size_in_mb() {
  local value="$1"
  local number=""
  local multiplier=1
  [[ "$value" =~ '^[1-9][0-9]{0,11}([KkMmGg])?$' ]] || return 1
  number="${value%[KkMmGg]}"
  case "$value" in
    *[Gg]) multiplier=1024 ;;
    *[Mm]) multiplier=1 ;;
    *[Kk]) print -r -- "$(( (number + 1023) / 1024 ))"; return 0 ;;
    *) print -r -- "$(( (number + 1048575) / 1048576 ))"; return 0 ;;
  esac
  print -r -- "$(( number * multiplier ))"
}
# 停机必须同时满足 ADB 消失、锁释放、匹配进程退出，任一不确定都停止。
avd_is_stopped() {
  local devices=""
  local locks=("$AVD_PATH"/*.lock(N) "$AVD_PATH"/**/*.lock(N))
  local processes=""
  devices="$("$ADB_BIN" devices 2>/dev/null)" || return 1
  print -r -- "$devices" | /usr/bin/awk -v serial="$DEVICE_ID" '$1==serial {found=1} END {exit !found}' && return 1
  (( ${#locks[@]} == 0 )) || return 1
  processes="$(/bin/ps -axo command=)" || return 1
  print -r -- "$processes" | /usr/bin/awk -v name="$AVD_NAME" -v directory="$AVD_PATH" '
    /qemu-system|\/emulator/ && (index($0," -avd " name " ") || index($0," -avd " name)==length($0)-length(" -avd " name)+1 || index($0," @" name " ") || index($0,directory)) {found=1}
    END {exit !found}
  ' && return 1
  return 0
}
# 发出指定 emulator 的停机命令并有界等待，超时保留原配置。
stop_selected_avd() {
  ensure_selected_device || return 1
  local output=""
  local attempt=0
  output="$("$ADB_BIN" -s "$DEVICE_ID" emu kill 2>&1)" || { log "错误：模拟器未接受停机：$output"; return 1; }
  for attempt in {1..30}; do
    if avd_is_stopped; then
      log '✔ 设备已离线、锁已释放，未发现匹配运行进程。'
      return 0
    fi
    /bin/sleep 1
  done
  log '错误：30 秒内无法确认完全停机；未备份或修改配置，不删除残留锁。'
  return 1
}
# 按逻辑体积估算备份空间，完整保存 AVD 后才允许改配置。
backup_stopped_avd() {
  local target_mb="$1"
  local required_kb=""
  local available_kb=""
  required_kb="$(/usr/bin/du -A -sk "$AVD_PATH" | /usr/bin/awk '{print $1}')" || return 1
  available_kb="$(/bin/df -k "$AVD_HOME" | /usr/bin/awk 'END {print $4}')" || return 1
  [[ "$required_kb" =~ '^[0-9]+$' && "$available_kb" =~ '^[0-9]+$' ]] || { log '错误：无法确认备份磁盘空间。'; return 1; }
  (( available_kb > required_kb + target_mb * 1024 + 1048576 )) || { log '错误：可用空间不足以备份完整 AVD、预留目标容量并保留 1 GB 余量。'; return 1; }
  BACKUP_PATH="$(/usr/bin/mktemp -d "$AVD_HOME/.$AVD_NAME.repair-backup.XXXXXX")" || return 1
  log "来源：$AVD_PATH 与 $AVD_DESCRIPTOR"
  log "完整备份目标：$BACKUP_PATH；备份失败时保留现场，配置不会修改。"
  /usr/bin/ditto --norsrc --noextattr "$AVD_PATH" "$BACKUP_PATH/avd" || { log '错误：完整 AVD 备份失败；未修改配置。'; return 1; }
  /bin/cp -p "$AVD_DESCRIPTOR" "$BACKUP_PATH/$AVD_NAME.ini" || { log '错误：AVD 描述符备份失败；未修改配置。'; return 1; }
  /usr/bin/diff -qr "$AVD_PATH" "$BACKUP_PATH/avd" >/dev/null || { log '错误：完整 AVD 备份字节校验失败；未修改配置。'; return 1; }
}
# 仅增大配置，停机与备份再次验证后原子替换；不自行操作 userdata 或 qcow2。
write_larger_config() {
  local target_mb="$1"
  local stage=""
  avd_is_stopped || { log '错误：备份期间模拟器重新运行；未修改配置。'; return 1; }
  /usr/bin/cmp -s "$CONFIG_PATH" "$BACKUP_PATH/avd/config.ini" || { log '错误：备份后配置发生变化；未修改。'; return 1; }
  stage="$(/usr/bin/mktemp "$AVD_PATH/.jobs-config.XXXXXX")" || return 1
  if ! /usr/bin/awk -v size="${target_mb}M" 'BEGIN {seen=0} /^disk[.]dataPartition[.]size=/ {if(!seen) print "disk.dataPartition.size=" size; seen=1; next} {print} END {if(!seen) print "disk.dataPartition.size=" size}' "$CONFIG_PATH" > "$stage"; then
    /bin/rm -f -- "$stage"
    log '错误：配置草稿写入失败；原配置保留。'
    return 1
  fi
  /bin/chmod "$(/usr/bin/stat -f '%Lp' "$CONFIG_PATH")" "$stage" || return 1
  avd_is_stopped || { /bin/rm -f -- "$stage"; log '错误：模拟器重新启动；取消配置写入。'; return 1; }
  /bin/mv -f -- "$stage" "$CONFIG_PATH" || { log '错误：配置替换失败；请保留备份。'; return 1; }
  log "✔ 配置已写为 ${target_mb}M；完整备份：$BACKUP_PATH"
  log '这只确认配置值，不代表已有 userdata 文件系统已扩容；冷启动可能改写现有数据镜像。'
}
# 经单独确认以禁用快照加载的方式启动，并等待真实设备启动后查询空间。
cold_boot_and_recheck() {
  local before_total_mb="$1"
  local after_total_mb=""
  [[ -n "$EMULATOR_BIN" ]] || { log '待验证：未找到健康 emulator；请在 Device Manager 使用 Cold Boot，启动后重新执行 --check。'; return 2; }
  ask_run '使用 -no-snapshot-load 冷启动此 AVD（不使用 -wipe-data）；可能由 Emulator 调整已有 userdata' || { log '待验证：已跳过冷启动，仅配置已改变，容量尚未确认。'; return 2; }
  avd_is_stopped || { log '错误：AVD 已有运行实例，未重复启动。'; return 1; }
  log "启动：$EMULATOR_BIN -avd $AVD_NAME -no-snapshot-load"
  /usr/bin/nohup "$EMULATOR_BIN" -avd "$AVD_NAME" -no-snapshot-load < /dev/null 2>&1 | safe_text >> "$LOG_FILE" &!
  local attempt=0
  local serial=""
  local name=""
  local booted=""
  for attempt in {1..60}; do
    for serial in "${(@f)$("$ADB_BIN" devices 2>/dev/null | /usr/bin/awk '$1 ~ /^emulator-[0-9]+$/ && $2=="device" {print $1}')}"; do
      name="$(device_avd_name "$serial")" || continue
      [[ "$name" == "$AVD_NAME" ]] || continue
      booted="$("$ADB_BIN" -s "$serial" shell getprop sys.boot_completed 2>/dev/null)" || continue
      [[ "${booted//$'\r'/}" == 1 ]] || continue
      DEVICE_ID="$serial"
      log '冷启动后的实际空间复检：'
      diagnose_device || return 1
      after_total_mb="$(data_total_mb)" || { log '错误：启动后无法读取 /data 总量，容量未确认。'; return 1; }
      if (( after_total_mb <= before_total_mb )); then
        log "待验证：/data 总量没有增加（之前 $before_total_mb MB，现在 $after_total_mb MB）；配置不等于扩容生效。"
        return 2
      fi
      log "✔ 已复核 /data 总量增加（$before_total_mb → $after_total_mb MB），且可用空间达到阈值。"
      return 0
    done
    /bin/sleep 2
  done
  log '警告：120 秒内未确认启动完成；不认定容量生效。稍后重新执行 --check。'
  return 1
}
# 容量修复只接受更大的已知配置，先停机、完整备份，再改配置与可选冷启动。
increase_avd_capacity() {
  ensure_selected_device || return 1
  resolve_avd_paths || return 1
  local current=""
  local current_mb=""
  local target=""
  local target_mb=""
  local count=""
  local total_mb=""
  local image=""
  local image_bytes=""
  local initial_checksum=""
  count="$(/usr/bin/awk '/^disk[.]dataPartition[.]size=/ {n++} END {print n+0}' "$CONFIG_PATH")"
  [[ "$count" == 1 ]] || { log '错误：容量配置缺失或重复；无法确认不缩容，停止自动修改。'; return 1; }
  current="$(/usr/bin/awk -F= '$1=="disk.dataPartition.size" {print $2}' "$CONFIG_PATH")"
  current_mb="$(size_in_mb "$current")" || { log "错误：无法识别现有容量 $current；停止自动修改。"; return 1; }
  validate_default_userdata || return 1
  total_mb="$(data_total_mb)" || { log '错误：无法读取 /data 总量；不推断安全扩容值。'; return 1; }
  initial_checksum="$(/usr/bin/cksum "$CONFIG_PATH")" || return 1
  log "AVD：$AVD_PATH；当前配置：$current（约 $current_mb MB）。"
  read -r 'target?目标容量（如 8G、12G，直接回车取消）：' || return 0
  [[ -n "$target" ]] || return 0
  target_mb="$(size_in_mb "$target")" || { log '错误：容量须为正整数与可选 K/M/G 单位。'; return 1; }
  (( target_mb > current_mb && target_mb <= 1048576 )) || { log '错误：目标必须严格大于当前容量，且不超过 1 TB；不会缩容。'; return 1; }
  (( target_mb > total_mb )) || { log '错误：目标没有超过现有 /data 文件系统总量，已拒绝。'; return 1; }
  for image in "$AVD_PATH/userdata-qemu.img" "$AVD_PATH/userdata.img"; do
    [[ -f "$image" ]] || continue
    image_bytes="$(/usr/bin/stat -f '%z' "$image")" || return 1
    [[ "$image_bytes" =~ '^[0-9]+$' ]] || return 1
    (( target_mb * 1048576 > image_bytes )) || { log '错误：目标没有超过现有 userdata 镜像逻辑大小，已拒绝。'; return 1; }
  done
  confirm_yes "停止 $AVD_NAME、完整备份后把配置增大到 $target。备份可能很大；已有 userdata 不保证扩容，冷启动可能改写数据镜像。" || return 0
  stop_selected_avd || return 1
  resolve_avd_paths || return 1
  [[ "$(/usr/bin/cksum "$CONFIG_PATH")" == "$initial_checksum" ]] || { log '错误：等待期间 config.ini 发生变化；未备份或修改。'; return 1; }
  backup_stopped_avd "$target_mb" || return 1
  write_larger_config "$target_mb" || return 1
  cold_boot_and_recheck "$total_mb"
}
# 交互菜单始终从诊断开始，各动作失败保留现场并回到菜单。
run_repair_menu() {
  local answer=""
  local failed=0
  diagnose_device || log '警告：初始诊断不完整；请先检查 adb 与模拟器。'
  while true; do
    log '1、重新诊断  2、恢复默认安装位置  3、重置编译状态  4、卸载精确第三方包  5、增加 AVD 容量配置  0、退出'
    read -r 'answer?选择动作（直接回车退出）：' || break
    case "$answer" in
      1) diagnose_device || { log '本项诊断未通过。'; failed=1; } ;;
      2) fix_install_location || { log '本项修复未完成。'; failed=1; } ;;
      3) reset_compile_cache || { log '本项修复未完成。'; failed=1; } ;;
      4) uninstall_exact_package || { log '本项修复未完成。'; failed=1; } ;;
      5) increase_avd_capacity || { log '本项容量流程未完成；配置与备份状态以以上日志为准。'; failed=1; } ;;
      0|'') break ;;
      *) log '请输入列表内序号。' ;;
    esac
  done
  diagnose_device || { log '最终诊断未通过或设备处于停机待验证状态。'; failed=1; }
  log "流程结束；操作和复检结果见日志：$LOG_FILE"
  return "$failed"
}
# 编排自述、只读诊断或经过确认的交互修复。
main() {
  show_script_intro_and_wait "$@" # 先说明影响、风险、取消方式和只读入口。
  parse_arguments "$@" # 严格解析动作与模拟器序列号。
  initialize_runtime # 确认后初始化选项，修复模式才创建私有日志。
  discover_tools # 发现并复检已有 SDK 工具，不安装软件。
  collect_devices # 排除物理真机，只收集在线 Emulator。
  run_checks_if_requested # 只读模式查询后退出，不进入任何修复。
  select_device # 在终端内确定唯一 AVD 与序列号。
  run_repair_menu # 每项修复独立确认并复查实际空间。
}

main "$@"
