#!/bin/zsh
# 脚本自述：
# - 脚本名称：JobsDesktopTools 桌面菜单安装管理。
# - 核心用途：逐叶启停六项桌面菜单，由一个扩展保证固定顺序。
# - 影响范围：本地构建、当前用户菜单登记与专用功能配置；不运行模拟器业务或切换隐藏文件偏好。
# - 运行提示：先阅读自述，直接回车执行、任意输入跳过；调用方可显式传 --non-interactive，Ctrl+C 取消。
# shell: zsh

PROJECT_ROOT=""
CONFIG_DIR=""
CONFIG_PATH=""
MARKER_PATH=""
APP_PATH=""
EXTENSION_PATH=""
DERIVED_PATH=""
LOG_FILE=""
TRANSACTION_DIR=""
TEMPORARY_ROOT=""
LOCK_PATH=""
LOCK_HELD=0
OPERATION=""
NON_INTERACTIVE=0
SKIP_RESTART=0
HAD_CONFIG=0
HAD_APP=0
WAS_ENABLED=0
CONFIG_PUBLISHED=0
MARKER_PUBLISHED=0
BUILD_STARTED=0
REGISTRATION_CHANGED=0
TRANSACTION_COMMITTED=0
ROLLED_BACK=0
FEATURES=(ios-simulator-create android-simulator-create harmony-simulator-create android-simulator-repair harmony-simulator-repair hidden-files-toggle)
LEGACY_IDS=(com.jobs.iossimulatorcreator.findersync com.jobs.androidsimulatorcreator.findersync com.jobs.harmonysimulatorcreator.findersync com.jobs.androidsimulatorrepairer.findersync com.jobs.harmonysimulatorrepairer.findersync com.jobs.hiddenfilestoggler.findersync)
EXTENSION_ID="com.jobs.desktoptools.findersync"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
REQUESTED=()
LEGACY_ENABLED=()
typeset -A ENABLED
# 仅计算展示路径并验证参数，确认之前不产生文件或登记。
prepare_context() {
  PROJECT_ROOT="${${(%):-%x}:A:h:h}"
  CONFIG_DIR="${HOME}/Library/Application Support/JobsDesktopTools"
  CONFIG_PATH="${CONFIG_DIR}/EnabledFeatures.txt"
  MARKER_PATH="${CONFIG_DIR}/MigrationVersion.txt"
  DERIVED_PATH="${PROJECT_ROOT}/work/DerivedData"
  APP_PATH="${DERIVED_PATH}/Build/Products/Debug/JobsDesktopTools.app"
  EXTENSION_PATH="${APP_PATH}/Contents/PlugIns/JobsDesktopToolsFinderSync.appex"
  LOCK_PATH="${CONFIG_DIR}/.manager-lock"
  TEMPORARY_ROOT="${TMPDIR:-/tmp}"
  LOG_FILE="${TEMPORARY_ROOT%/}/JobsDesktopToolsInstall.log"
  OPERATION="${1:-}"
  [[ "$OPERATION" == install || "$OPERATION" == uninstall ]] || { print -u2 '用法：install|uninstall 功能ID... [--non-interactive] [--skip-finder-restart]'; return 2; }
  shift
  local value=""
  for value in "$@"; do
    case "$value" in
      --non-interactive|--install|--uninstall) NON_INTERACTIVE=1 ;;
      --skip-finder-restart) SKIP_RESTART=1 ;;
      *)
        (( ${FEATURES[(Ie)$value]} )) || { print -u2 "✖ 未知桌面功能：$value"; return 2; }
        (( ${REQUESTED[(Ie)$value]} )) || REQUESTED+=("$value")
        ;;
    esac
  done
  (( ${#REQUESTED} > 0 )) || { print -u2 '✖ 至少明确选择一项功能，不会隐式全选。'; return 2; }
}
# 首屏声明操作范围；兼容转发入口复用本层说明及唯一一次确认。
show_script_intro_and_wait() {
  prepare_context "$@" || exit $?
  local color=0 answer=""
  [[ -t 1 && -n "${TERM:-}" && "${TERM}" != dumb && -z "${NO_COLOR+x}" ]] && color=1
  if (( color )); then
    print -r -- $'\033[1;31m━━━━━━━━━━ Jobs 固定顺序桌面菜单 ━━━━━━━━━━\033[0m'
  else
    print -r -- '━━━━━━━━━━ Jobs 固定顺序桌面菜单 ━━━━━━━━━━'
  fi
  print -r -- "1、操作：${OPERATION}；功能：${(j:,:)REQUESTED}。"
  print -r -- "2、来源：${PROJECT_ROOT}；产物：${APP_PATH}。"
  print -r -- '3、安装只合并所选叶子并迁移已启用旧菜单；卸载只移除所选叶子。安装登记不运行任何业务。'
  print -r -- '4、影响：当前用户扩展及专用配置；完成后按需刷新 Finder，Ctrl+C 取消。'
  print -r -- "5、日志：${LOG_FILE}；失败备份在日志记录的事务目录。"
  (( NON_INTERACTIVE )) && return 0
  [[ -t 0 ]] || { print -u2 '✖ 请在交互终端运行，或由已确认的安装器显式传 --non-interactive。'; exit 1; }
  IFS= read -r 'answer?直接回车执行；输入任意字符后回车跳过：' || exit 0
  [[ -z "$answer" ]] || exit 0
}
# 确认后准备日志和互斥锁，防止两个入口同时覆盖配置。
initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  : > "$LOG_FILE" || exit 1
  [[ ! -L "$CONFIG_DIR" && ! -L "$CONFIG_PATH" && ! -L "$MARKER_PATH" ]] || { print -u2 '✖ 配置位置是符号链接，已停止。'; exit 1; }
  /bin/mkdir -p "$CONFIG_DIR" || exit 1
  /bin/mkdir "$LOCK_PATH" 2>/dev/null || { print -u2 "✖ 另一个菜单管理操作正在进行：$LOCK_PATH"; exit 1; }
  LOCK_HELD=1
  TRANSACTION_DIR="$(/usr/bin/mktemp -d "${TEMPORARY_ROOT%/}/JobsDesktopToolsTransaction.XXXXXXXX")" || exit 1
  log "事务备份：${TRANSACTION_DIR}"
}
# 日志保留完整来源和失败位置，终端与文件内容一致。
log() {
  print -r -- "$*" | /usr/bin/tee -a "$LOG_FILE"
}
# 只接受白名单、无空白和不重复的配置，损坏内容不会被猜测或默认全开。
read_configuration() {
  local value="" entry="" bytes=0
  ENABLED=()
  if [[ -e "$CONFIG_PATH" ]]; then
    [[ -f "$CONFIG_PATH" && ! -L "$CONFIG_PATH" ]] || return 1
    HAD_CONFIG=1
    /bin/cp -p "$CONFIG_PATH" "$TRANSACTION_DIR/original-features" || return 1
    value="$(<"$CONFIG_PATH")"
    bytes="$(/usr/bin/wc -c < "$CONFIG_PATH")"
    (( bytes <= 4096 && bytes == ${#value} )) || { log '✖ 现有功能配置含异常字节，已停止。'; return 1; }
    if [[ -n "$value" ]]; then
      for entry in ${(s:,:)value}; do
        (( ${FEATURES[(Ie)$entry]} )) && [[ "${ENABLED[$entry]:-0}" != 1 ]] || { log '✖ 现有功能配置损坏，已停止。'; return 1; }
        ENABLED[$entry]=1
      done
      [[ "$value" != ,* && "$value" != *, && "$value" != *,,* ]] || return 1
    fi
  fi
  [[ ! -f "$MARKER_PATH" ]] || /bin/cp -p "$MARKER_PATH" "$TRANSACTION_DIR/original-marker" || return 1
}
# PlugInKit 明确的 + 状态才视为旧功能启用，不根据磁盘上 App 存在猜测。
extension_is_enabled() {
  /usr/bin/pluginkit -m -i "$1" -A -D 2>/dev/null | /usr/bin/awk '$1 == "+" { found=1 } END { exit !found }'
}
# 首次迁移当前启用旧叶子；后续不重新打开用户已经关闭的功能。
plan_configuration() {
  local index=0 feature=""
  extension_is_enabled "$EXTENSION_ID" && WAS_ENABLED=1
  for index in {1..6}; do
    if extension_is_enabled "${LEGACY_IDS[$index]}"; then
      LEGACY_ENABLED+=("${LEGACY_IDS[$index]}")
      if [[ "$OPERATION" == install && "$HAD_CONFIG" == 0 && ! -e "$MARKER_PATH" ]]; then
        ENABLED[${FEATURES[$index]}]=1
      fi
    fi
  done
  for feature in "${REQUESTED[@]}"; do
    if [[ "$OPERATION" == install ]]; then
      ENABLED[$feature]=1
    else
      unset "ENABLED[$feature]"
    fi
  done
}
# 构建前保存现有完整 App；业务资源固定从本包获取。
build_and_verify() {
  [[ "$(/usr/bin/uname -s)" == Darwin ]] || return 1
  if [[ -d "$APP_PATH" ]]; then
    [[ ! -L "$APP_PATH" ]] || return 1
    HAD_APP=1
    /usr/bin/ditto "$APP_PATH" "$TRANSACTION_DIR/previous.app" || return 1
  fi
  BUILD_STARTED=1
  log "来源：本地源码 ${PROJECT_ROOT}；目标：${APP_PATH}"
  JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1 /usr/bin/xcodebuild \
    -project "$PROJECT_ROOT/JobsDesktopTools.xcodeproj" -scheme JobsDesktopTools \
    -configuration Debug -destination "platform=macOS,arch=$(/usr/bin/uname -m)" \
    -derivedDataPath "$DERIVED_PATH" build 2>&1 | /usr/bin/tee -a "$LOG_FILE"
  (( ${pipestatus[1]} == 0 )) || return 1
  [[ -d "$EXTENSION_PATH" ]] || return 1
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")" == com.jobs.desktoptools ]] || return 1
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$EXTENSION_PATH/Contents/Info.plist")" == "$EXTENSION_ID" ]] || return 1
  /usr/bin/codesign --verify --deep --strict "$APP_PATH" 2>&1 | /usr/bin/tee -a "$LOG_FILE"
}
# 精确路径启用成功后才允许发布功能选择和收回旧菜单。
register_and_verify() {
  REGISTRATION_CHANGED=1
  "$LSREGISTER" -f "$APP_PATH" || return 1
  /usr/bin/pluginkit -a "$EXTENSION_PATH" || return 1
  /usr/bin/pluginkit -e use -i "$EXTENSION_ID" || return 1
  local attempt=0 state=""
  for attempt in {1..40}; do
    state="$(/usr/bin/pluginkit -m -i "$EXTENSION_ID" -A -D -vv 2>/dev/null)"
    if print -r -- "$state" | /usr/bin/awk -v path="$EXTENSION_PATH" '
      /^[+!-]/ { enabled=($1 == "+") }
      /Path = / { entry=$0; sub(/^.*Path = /,"",entry); if (enabled && entry==path) found=1 }
      END { exit !found }'; then
      return 0
    fi
    /bin/sleep 0.25
  done
  log '✖ 当前聚合扩展路径尚未启用；旧菜单尚未停用。'
  return 1
}
# 原配置未被外部改动时，按固定顺序原子发布所选叶子。
publish_configuration() {
  local feature="" values=() temporary=""
  if (( HAD_CONFIG )); then
    /usr/bin/cmp -s "$CONFIG_PATH" "$TRANSACTION_DIR/original-features" || { log '✖ 功能配置在操作中被外部修改，已停止。'; return 1; }
  else
    [[ ! -e "$CONFIG_PATH" ]] || return 1
  fi
  for feature in "${FEATURES[@]}"; do
    [[ "${ENABLED[$feature]:-0}" != 1 ]] || values+=("$feature")
  done
  temporary="$(/usr/bin/mktemp "$CONFIG_DIR/.features.XXXXXXXX")" || return 1
  print -nr -- "${(j:,:)values}" > "$temporary" && /bin/chmod 600 "$temporary" &&
    /bin/cp "$temporary" "$TRANSACTION_DIR/published-features" || return 1
  CONFIG_PUBLISHED=1
  /bin/mv -f "$temporary" "$CONFIG_PATH"
}
# 成功迁移后只停用旧扩展，不删除原源码、App 或任何业务配置。
retire_legacy() {
  local index=0
  for index in {1..6}; do
    if [[ "$OPERATION" == install ]] || (( ${REQUESTED[(Ie)${FEATURES[$index]}]} )); then
      if extension_is_enabled "${LEGACY_IDS[$index]}"; then
        /usr/bin/pluginkit -e ignore -i "${LEGACY_IDS[$index]}" || return 1
      fi
    fi
  done
  return 0
}
# 标记只在整个迁移成功时落盘，避免失败重试丢失原选择。
publish_marker() {
  local temporary=""
  temporary="$(/usr/bin/mktemp "$CONFIG_DIR/.migration.XXXXXXXX")" || return 1
  print -nr -- 1 > "$temporary" && /bin/chmod 600 "$temporary" &&
    /bin/cp "$temporary" "$TRANSACTION_DIR/published-marker" || return 1
  MARKER_PUBLISHED=1
  /bin/mv -f "$temporary" "$MARKER_PATH"
}
# 安装登记不执行 URL 或打开宿主，因此不会创建模拟器或切换隐藏状态。
install_features() {
  build_and_verify || return 1
  register_and_verify || return 1
  publish_configuration || return 1
  retire_legacy || return 1
  publish_marker || return 1
}
# 删除一项只更新该叶；最后一项移除后才停用统一菜单。
disable_aggregate_extension() {
  REGISTRATION_CHANGED=1
  /usr/bin/pluginkit -e ignore -i "$EXTENSION_ID" || return 1
  [[ ! -d "$EXTENSION_PATH" ]] || /usr/bin/pluginkit -r "$EXTENSION_PATH"
}
# 保留其它功能配置和完整 App，避免卸载一叶破坏共享业务资源。
uninstall_features() {
  if (( HAD_CONFIG )); then
    publish_configuration || return 1
    if (( ${#ENABLED} == 0 )); then
      disable_aggregate_extension || return 1
    fi
  fi
  retire_legacy
}
# 失败恢复本事务发布的配置及原启用状态，保护外部并发修改。
rollback_transaction() {
  ROLLED_BACK=1
  local identifier=""
  if (( CONFIG_PUBLISHED )) && /usr/bin/cmp -s "$CONFIG_PATH" "$TRANSACTION_DIR/published-features"; then
    if (( HAD_CONFIG )); then
      /bin/cp -p "$TRANSACTION_DIR/original-features" "$CONFIG_PATH"
    else
      /bin/rm -f "$CONFIG_PATH"
    fi
  fi
  if (( MARKER_PUBLISHED )) && /usr/bin/cmp -s "$MARKER_PATH" "$TRANSACTION_DIR/published-marker"; then
    if [[ -f "$TRANSACTION_DIR/original-marker" ]]; then
      /bin/cp -p "$TRANSACTION_DIR/original-marker" "$MARKER_PATH"
    else
      /bin/rm -f "$MARKER_PATH"
    fi
  fi
  if [[ "$OPERATION" == install ]] && (( BUILD_STARTED || REGISTRATION_CHANGED )); then
    /usr/bin/pluginkit -e ignore -i "$EXTENSION_ID" 2>/dev/null || true
    if (( HAD_APP )); then
      [[ "$APP_PATH" == "$PROJECT_ROOT"/work/DerivedData/Build/Products/Debug/JobsDesktopTools.app && ! -L "$APP_PATH" ]] || return 1
      [[ ! -e "$APP_PATH" ]] || /bin/rm -r "$APP_PATH"
      /usr/bin/ditto "$TRANSACTION_DIR/previous.app" "$APP_PATH" || return 1
      "$LSREGISTER" -f "$APP_PATH" || true
      /usr/bin/pluginkit -a "$EXTENSION_PATH" || true
    else
      [[ ! -d "$EXTENSION_PATH" ]] || /usr/bin/pluginkit -r "$EXTENSION_PATH" || true
      [[ ! -d "$APP_PATH" ]] || "$LSREGISTER" -u "$APP_PATH" || true
    fi
  fi
  if (( WAS_ENABLED && REGISTRATION_CHANGED )); then
    [[ ! -d "$EXTENSION_PATH" ]] || /usr/bin/pluginkit -a "$EXTENSION_PATH" || true
    /usr/bin/pluginkit -e use -i "$EXTENSION_ID" || true
  fi
  for identifier in "${LEGACY_ENABLED[@]}"; do
    /usr/bin/pluginkit -e use -i "$identifier" || true
  done
  log "✖ 操作失败，已尝试恢复原配置及登记；保留完整事务备份：${TRANSACTION_DIR}"
}
# 保留非零结果；一次刷新统一菜单，不运行任何叶子业务。
execute_operation() {
  read_configuration && plan_configuration || { rollback_transaction; exit 1; }
  if [[ "$OPERATION" == install ]]; then
    install_features
  else
    uninstall_features
  fi
  local result=$?
  if (( result != 0 )); then
    rollback_transaction
    exit "$result"
  fi
  TRANSACTION_COMMITTED=1
  log "✔ ${OPERATION} 已完成；当前叶功能：${(j:,:)${(k)ENABLED}}"
  if [[ "$SKIP_RESTART" != 1 && "${JOBS_SKIP_FINDER_RESTART:-0}" != 1 ]]; then
    /usr/bin/killall -u "$(/usr/bin/id -un)" Finder 2>/dev/null || log 'ℹ Finder 当前未运行。'
  fi
}
# 锁仅属于本次操作；备份和日志保留供人工核对。
cleanup_lock() {
  (( ! LOCK_HELD )) || /bin/rmdir "$LOCK_PATH" 2>/dev/null
}
# 退出只释放锁，取消不隐式执行业务或改选其它功能。
TRAPEXIT() {
  local result=$?
  if (( LOCK_HELD && ! TRANSACTION_COMMITTED && ! ROLLED_BACK )); then
    rollback_transaction
  fi
  cleanup_lock
  return "$result"
}
# 编排说明、互斥初始化和逐叶安装事务。
main() {
  show_script_intro_and_wait "$@" # 先展示影响范围并取得本次明确执行意图。
  initialize_runtime # 确认后建立日志、事务备份及专用互斥锁。
  execute_operation # 逐叶更新菜单，失败恢复原配置与旧入口。
}

main "$@"
