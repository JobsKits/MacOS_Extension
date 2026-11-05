#!/bin/zsh
# 由安装 / 卸载入口调用。共用一份配置和一个扩展，保留逐项启停能力。
setopt ERR_EXIT NO_UNSET PIPE_FAIL
PROJECT_ROOT="${0:A:h:h}"
CONFIG_DIR="${HOME}/Library/Application Support/JobsProjectTools"
CONFIG_PATH="${CONFIG_DIR}/EnabledFeatures.txt"
BUILT_APP_PATH="${PROJECT_ROOT}/work/DerivedData/Build/Products/Debug/JobsProjectTools.app"
APP_PATH="$BUILT_APP_PATH"
EXTENSION_PATH="${APP_PATH}/Contents/PlugIns/JobsProjectToolsFinderSync.appex"
EXTENSION_ID="com.jobs.JobsProjectTools.FinderSyncExtension"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
FEATURES=(android_studio_opener vscode_opener xcode_opener git-pull git_remote git_remote_copier git-proxy-configure git_empty_commit_push git-rollback git-sourcetree)
LEGACY_APPS=(JobsAndroidStudioOpener JobsVSCodeOpener JobsXcodeOpener JobsGitPuller JobsGitRemoteOpener JobsGitRemoteCopier)
LEGACY_EXTENSIONS=(JobsAndroidStudioFinderSync JobsVSCodeFinderSync JobsXcodeFinderSync JobsGitPullFinderSync JobsGitRemoteFinderSync JobsGitRemoteCopyFinderSync)
GIT_MIGRATION_PATH="${CONFIG_DIR}/GitMenuMigrationVersion.txt"
ROLLBACK_MIGRATION_PATH="${CONFIG_DIR}/GitRollbackMigrationVersion.txt"
TERMINAL_CONFIG_PATH="${HOME}/Library/Application Support/JobsTerminalOpener/EnabledFinderMenuFeatures.txt"
typeset -A ENABLED
PROJECT_CONFIG_TRANSACTION=""
STOP_REQUEST_FILE="${JOBS_FINDER_STOP_REQUEST_FILE:-}"
PROJECT_CONFIG_COMMITTED=0

read_configuration() {
  local feature=""
  if [[ -f "$CONFIG_PATH" ]]; then
    for feature in ${(s:,:)$(<"$CONFIG_PATH")}; do
      (( ${FEATURES[(Ie)$feature]} )) && ENABLED[$feature]=1
    done
  fi
  return 0
}

save_configuration() {
  local feature="" values=() temporary=""
  for feature in "${FEATURES[@]}"; do
    [[ "${ENABLED[$feature]:-0}" == 1 ]] && values+=("$feature")
  done
  project_validate_configuration_unchanged "$CONFIG_PATH" || return $?
  /bin/mkdir -p "$CONFIG_DIR"
  temporary="$(/usr/bin/mktemp "$CONFIG_DIR/.features.XXXXXX")"
  print -nr -- "${(j:,:)values}" > "$temporary"
  /bin/mv -f "$temporary" "$CONFIG_PATH"
  project_record_published_configuration "$CONFIG_PATH"
}

legacy_is_enabled() {
  identifier_is_enabled "com.jobs.$1.FinderSyncExtension"
}
# 只迁移系统明确标为启用的旧入口，不触发任何业务脚本。
identifier_is_enabled() {
  /usr/bin/pluginkit -m -i "$1" -A 2>/dev/null |
    /usr/bin/awk '$1 == "+" { found=1 } END { exit !found }'
}
# 新 Git 分组只迁移一次，避免后续安装重新启用已被用户关闭的功能。
migrate_legacy_git_features() {
  [[ ! -f "$GIT_MIGRATION_PATH" ]] || return 0
  if identifier_is_enabled com.jobs.gitproxyconfigurator.findersync; then
    ENABLED[git-proxy-configure]=1
  fi
  if identifier_is_enabled com.jobs.JobsTerminalOpener.FinderSyncExtension && [[ -f "$TERMINAL_CONFIG_PATH" ]]; then
    local entry=""
    for entry in ${(s:,:)$(<"$TERMINAL_CONFIG_PATH")}; do
      [[ "$entry" != git-empty-commit-push ]] || ENABLED[git_empty_commit_push]=1
    done
  fi
  return 0
}
# 仅迁移已启用的独立回退菜单，不重复打开用户已经关闭的选择。
migrate_legacy_rollback_feature() {
  [[ ! -f "$ROLLBACK_MIGRATION_PATH" ]] || return 0
  if identifier_is_enabled com.jobs.JobsGitRollback.FinderSyncExtension; then
    ENABLED[git-rollback]=1
  fi
  return 0
}
# 独立回退实现仍可保留源码，统一菜单启用后精确停用其登记。
retire_legacy_rollback() {
  /usr/bin/pkill -x JobsGitRollback 2>/dev/null || true
  /usr/bin/pkill -f 'JobsGitRollbackFinderSync.appex/Contents/MacOS/JobsGitRollbackFinderSync' 2>/dev/null || true
  if identifier_is_enabled com.jobs.JobsGitRollback.FinderSyncExtension; then
    /usr/bin/pluginkit -e ignore -i com.jobs.JobsGitRollback.FinderSyncExtension
  fi
  return 0
}
# 只有统一安装完成迁移才写标记，后续卸载不会被旧选择重新启用。
save_git_migration_marker() {
  project_validate_configuration_unchanged "$GIT_MIGRATION_PATH" || return $?
  print -r -- 1 > "$GIT_MIGRATION_PATH"
  project_record_published_configuration "$GIT_MIGRATION_PATH"
}
# 统一菜单落盘成功后，仅收回旧 Terminal 外层入口，保留其它功能和未知项。
retire_terminal_git_menu() {
  [[ -f "$TERMINAL_CONFIG_PATH" && ! -L "$TERMINAL_CONFIG_PATH" ]] || return 0
  local original="$(<"$TERMINAL_CONFIG_PATH")" entry="" values=() temporary=""
  for entry in ${(s:,:)original}; do
    [[ "$entry" == git-empty-commit-push ]] || values+=("$entry")
  done
  [[ "${(j:,:)values}" != "$original" ]] || return 0
  temporary="$(/usr/bin/mktemp "${TERMINAL_CONFIG_PATH:h}/.features.XXXXXX")" || return 1
  print -nr -- "${(j:,:)values}" > "$temporary" || return 1
  [[ "$(<"$TERMINAL_CONFIG_PATH")" == "$original" ]] || { /bin/rm -f -- "$temporary"; return 1; }
  /bin/mv -f "$temporary" "$TERMINAL_CONFIG_PATH"
  project_record_published_configuration "$TERMINAL_CONFIG_PATH"
}
# 停用旧桌面代理菜单，不删除业务脚本和用户已经配置的 Git 网络策略。
retire_legacy_proxy() {
  /usr/bin/pkill -x JobsGitProxyConfigurator 2>/dev/null || true
  /usr/bin/pkill -f 'JobsGitProxyFinderSync.appex/Contents/MacOS/JobsGitProxyFinderSync' 2>/dev/null || true
  if identifier_is_enabled com.jobs.gitproxyconfigurator.findersync; then
    /usr/bin/pluginkit -e ignore -i com.jobs.gitproxyconfigurator.findersync
  fi
  return 0
}

retire_legacy() {
  local index="$1" identifier="com.jobs.${LEGACY_APPS[$1]}.FinderSyncExtension"
  /usr/bin/pkill -x "${LEGACY_APPS[$index]}" 2>/dev/null || true
  /usr/bin/pkill -f "${LEGACY_EXTENSIONS[$index]}.appex/Contents/MacOS/${LEGACY_EXTENSIONS[$index]}" 2>/dev/null || true
  if legacy_is_enabled "${LEGACY_APPS[$index]}"; then
    /usr/bin/pluginkit -e ignore -i "$identifier"
  fi
  return 0
}

wait_until_enabled() {
  local attempt="" registration=""
  for attempt in {1..40}; do
    registration="$(/usr/bin/pluginkit -m -i "$EXTENSION_ID" -A -v 2>/dev/null || true)"
    if print -r -- "$registration" | /usr/bin/awk -v path="$EXTENSION_PATH" \
      '$1 == "+" && substr($0, length($0)-length(path)+1) == path { found=1 } END { exit !found }'; then
      return 0
    fi
    /bin/sleep 0.5
  done
  print -u2 '统一扩展尚未启用，请在系统设置的 Finder 扩展中启用 JobsProjectTools；旧菜单未停用。'
  return 1
}

# 成功提交 App 和功能配置后才清理本轮构建；清理失败不回滚已安装 App。
cleanup_committed_build_products() {
  [[ "${JOBS_FINDER_CLEANUP_BUILD_PRODUCTS:-0}" == 1 ]] || return 0
  if ! jobs_deployment_cleanup_build_products "$BUILT_APP_PATH" "$PROJECT_ROOT/work/DerivedData" com.jobs.JobsProjectTools JobsProjectToolsFinderSync.appex "$EXTENSION_ID"; then
    print -u2 -r -- '⚠ App 已安装成功，但清除此轮构建产物失败；已保留应用程序目录中的 App，请查看日志。'
  fi
  return 0
}
install_features() {
  local feature="" index="" had_config=0
  [[ ! -f "$CONFIG_PATH" ]] || had_config=1
  # 首次迁移将已启用的旧菜单一起带入，避免装一项时丢失其余项。
  if (( ! had_config )); then
    for index in {1..6}; do
      if legacy_is_enabled "${LEGACY_APPS[$index]}"; then ENABLED[${FEATURES[$index]}]=1; fi
    done
  fi
  migrate_legacy_git_features
  migrate_legacy_rollback_feature
  for feature in "$@"; do ENABLED[$feature]=1; done
  JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1 /usr/bin/xcodebuild \
    -project "$PROJECT_ROOT/JobsProjectTools.xcodeproj" -scheme JobsProjectTools \
    -configuration Debug -destination "platform=macOS,arch=$(/usr/bin/uname -m)" \
    -derivedDataPath "$PROJECT_ROOT/work/DerivedData" build
  jobs_deployment_install "$BUILT_APP_PATH" com.jobs.JobsProjectTools JobsProjectToolsFinderSync.appex "$EXTENSION_ID"
  jobs_deployment_retire_other_copies "$APP_PATH" com.jobs.JobsProjectTools JobsProjectToolsFinderSync.appex "$EXTENSION_ID"
  [[ -d "$EXTENSION_PATH" ]]
  /usr/bin/pkill -x JobsProjectTools 2>/dev/null || true
  /usr/bin/pkill -f 'JobsProjectToolsFinderSync.appex/Contents/MacOS/JobsProjectToolsFinderSync' 2>/dev/null || true
  "$LSREGISTER" -f "$APP_PATH"
  /usr/bin/pluginkit -a "$EXTENSION_PATH"
  /usr/bin/pluginkit -e use -i "$EXTENSION_ID"
  wait_until_enabled
  save_configuration
  save_git_migration_marker
  project_validate_configuration_unchanged "$ROLLBACK_MIGRATION_PATH" || return $?
  print -r -- 1 > "$ROLLBACK_MIGRATION_PATH"
  project_record_published_configuration "$ROLLBACK_MIGRATION_PATH"
  retire_terminal_git_menu
  for index in {1..6}; do retire_legacy "$index"; done
  retire_legacy_proxy
  retire_legacy_rollback
  jobs_deployment_commit || return $?
  cleanup_committed_build_products
  print -r -- "已启用统一项目菜单：$(<"$CONFIG_PATH")"
}

uninstall_features() {
  local feature="" index=""
  for feature in "$@"; do
    unset "ENABLED[$feature]"
    index=${FEATURES[(Ie)$feature]}
    if (( index <= 6 )); then
      retire_legacy "$index"
    elif [[ "$feature" == git-proxy-configure ]]; then
      retire_legacy_proxy
    elif [[ "$feature" == git-rollback ]]; then
      retire_legacy_rollback
    elif [[ "$feature" == git_empty_commit_push ]]; then
      retire_terminal_git_menu
    fi
  done
  # 尚未迁移的旧安装没有配置，不创建空文件去影响其他旧功能。
  if [[ -f "$CONFIG_PATH" ]]; then
    save_configuration
    if (( ${#ENABLED} == 0 )); then
      remove_selected_application
    fi
  fi
  [[ -f "$CONFIG_PATH" ]] || remove_selected_application
  print -r -- "已关闭项目菜单：$*"
}

# 快照仅包含本次可能改写的四份配置，保留原字节和权限。
project_capture_configuration() {
  local index=0 item="" temporary_root="${TMPDIR:-/tmp}"
  PROJECT_CONFIG_TRANSACTION="$(/usr/bin/mktemp -d "${temporary_root%/}/JobsProjectToolsConfiguration.XXXXXXXX")" || return 1
  for item in "$CONFIG_PATH" "$GIT_MIGRATION_PATH" "$ROLLBACK_MIGRATION_PATH" "$TERMINAL_CONFIG_PATH"; do
    (( index += 1 ))
    [[ ! -L "$item" && ! -L "${item:h}" ]] || return 1
    print -r -- "$item" > "$PROJECT_CONFIG_TRANSACTION/$index.path" || return 1
    if [[ -e "$item" ]]; then
      [[ -f "$item" ]] || return 1
      /bin/cp -p "$item" "$PROJECT_CONFIG_TRANSACTION/$index.original" || return 1
    fi
  done
}
# 每次发布前确认未被其它进程编辑，不能覆盖并发配置。
project_validate_configuration_unchanged() {
  [[ -n "$PROJECT_CONFIG_TRANSACTION" ]] || return 0
  local index=0 item="" reference=""
  for index in {1..4}; do
    item="$(<"$PROJECT_CONFIG_TRANSACTION/$index.path")"
    [[ "$item" == "$1" ]] || continue
    reference="$PROJECT_CONFIG_TRANSACTION/$index.original"
    [[ ! -e "$PROJECT_CONFIG_TRANSACTION/$index.published" ]] || reference="$PROJECT_CONFIG_TRANSACTION/$index.published"
    if [[ -f "$reference" ]]; then
      /usr/bin/cmp -s "$item" "$reference" || { print -u2 "✖ 配置已被外部修改，保留并停止：$item"; return 1; }
    else
      [[ ! -e "$item" && ! -L "$item" ]] || return 1
    fi
    return 0
  done
  return 1
}
# 记录本次成功发布的字节，失败恢复时只撤回自己的写入。
project_record_published_configuration() {
  [[ -n "$PROJECT_CONFIG_TRANSACTION" ]] || return 0
  local index=0
  for index in {1..4}; do
    [[ "$(<"$PROJECT_CONFIG_TRANSACTION/$index.path")" == "$1" ]] || continue
    /bin/cp -p "$1" "$PROJECT_CONFIG_TRANSACTION/$index.published"
    return $?
  done
  return 1
}
# 恢复失败前的配置；外部新编辑保留并明确报告。
project_rollback_configuration() {
  [[ -n "$PROJECT_CONFIG_TRANSACTION" ]] || return 0
  local index=0 item="" temporary="" result=0
  for index in {1..4}; do
    [[ -f "$PROJECT_CONFIG_TRANSACTION/$index.published" ]] || continue
    item="$(<"$PROJECT_CONFIG_TRANSACTION/$index.path")"
    if ! /usr/bin/cmp -s "$item" "$PROJECT_CONFIG_TRANSACTION/$index.published"; then
      print -u2 "⚠ 配置已被外部修改，未覆盖：$item"
      result=1
      continue
    fi
    if [[ -f "$PROJECT_CONFIG_TRANSACTION/$index.original" ]]; then
      temporary="$(/usr/bin/mktemp "${item}.restore.XXXXXXXX")" || return 1
      /bin/cp -p "$PROJECT_CONFIG_TRANSACTION/$index.original" "$temporary" && /bin/mv -f "$temporary" "$item" || return 1
    else
      /bin/rm -f -- "$item" || result=1
    fi
  done
  return "$result"
}
# 退出失败同时撤回 App 与本次配置；成功释放私有快照。
project_finish_transaction() {
  local original_result="${1:-$?}" restore_result=0
  if (( ! PROJECT_CONFIG_COMMITTED )); then
    project_rollback_configuration || restore_result=1
    jobs_deployment_rollback || restore_result=1
  fi
  if (( restore_result )); then
    print -u2 "⚠ 恢复未全部完成，保留配置快照：$PROJECT_CONFIG_TRANSACTION"
  elif [[ -n "$PROJECT_CONFIG_TRANSACTION" && -d "$PROJECT_CONFIG_TRANSACTION" && ! -L "$PROJECT_CONFIG_TRANSACTION" ]]; then
    /bin/rm -r -- "$PROJECT_CONFIG_TRANSACTION"
    PROJECT_CONFIG_TRANSACTION=""
  fi
  return "$original_result"
}
# 只移除本次选择的 App；不会全局停用同 ID 的另一份副本。
remove_selected_application() {
  if [[ "$JOBS_FINDER_INSTALL_LOCATION" == applications ]]; then
    jobs_deployment_uninstall "$APP_PATH" com.jobs.JobsProjectTools JobsProjectToolsFinderSync.appex "$EXTENSION_ID"
  else
    jobs_deployment_validate_app "$APP_PATH" com.jobs.JobsProjectTools JobsProjectToolsFinderSync.appex "$EXTENSION_ID" || return $?
    jobs_deployment_unregister_app "$APP_PATH" JobsProjectToolsFinderSync.appex || return $?
    /bin/rm -r -- "$APP_PATH"
  fi
}
# 参数解析只选择路径；功能与位置校验通过后才读取配置或执行业务。
parse_operation() {
  OPERATION="${1:-}"
  [[ "$OPERATION" == install || "$OPERATION" == uninstall || "$OPERATION" == cleanup ]] || { print -u2 '用法：ManageProjectTools.zsh install|uninstall|cleanup 功能ID... [--install-location build|applications] [--cleanup-build-products] [--stop-request-file PATH]'; return 2; }
  shift
  local value="" install_location="${JOBS_FINDER_INSTALL_LOCATION:-build}" cleanup_build_products="${JOBS_FINDER_CLEANUP_BUILD_PRODUCTS:-0}"
  REQUESTED=()
  while (( $# )); do
    case "$1" in
      --install-location) (( $# >= 2 )) || return 2; install_location="$2"; shift ;;
      --install-location=*) install_location="${1#--install-location=}" ;;
      --cleanup-build-products) cleanup_build_products=1 ;;
      --stop-request-file) (( $# >= 2 )) && [[ "$2" == /* ]] || return 2; STOP_REQUEST_FILE="$2"; shift ;;
      --stop-request-file=*) STOP_REQUEST_FILE="${1#--stop-request-file=}"; [[ "$STOP_REQUEST_FILE" == /* ]] || return 2 ;;
      *)
        value="$1"
        (( ${FEATURES[(Ie)$value]} )) || { print -u2 "未知功能：$value"; return 2; }
        [[ "$OPERATION" != install || "$value" != git-sourcetree ]] || { print -u2 '“用 Sourcetree 打开”已移除；旧配置仅支持卸载。'; return 2; }
        (( ${REQUESTED[(Ie)$value]} )) || REQUESTED+=("$value")
        ;;
    esac
    shift
  done
  [[ "$install_location" == build || "$install_location" == applications ]] || return 2
  (( ${#REQUESTED} > 0 )) || return 2
  [[ "$cleanup_build_products" == 0 || "$cleanup_build_products" == 1 ]] || return 2
  if [[ "$cleanup_build_products" == 1 && ( "$install_location" != applications || "$OPERATION" != install ) ]]; then
    print -u2 '✖ 仅安装到应用程序目录时允许清除此轮构建产物。'
    return 2
  fi
  [[ "$OPERATION" != cleanup || "$install_location" == applications ]] || { print -u2 '✖ 独立清理仅允许应用程序目录模式。'; return 2; }
  [[ -z "$STOP_REQUEST_FILE" || "$STOP_REQUEST_FILE" == /* ]] || return 2
  export JOBS_FINDER_STOP_REQUEST_FILE="$STOP_REQUEST_FILE"
  export JOBS_FINDER_CLEANUP_BUILD_PRODUCTS="$cleanup_build_products"
  export JOBS_FINDER_INSTALL_LOCATION="$install_location"
  source "$PROJECT_ROOT/Scripts/【MacOS】AppDeployment.zsh/【MacOS】AppDeployment.zsh" || return $?
  APP_PATH="$(jobs_deployment_app_path "$BUILT_APP_PATH")" || return $?
  EXTENSION_PATH="$APP_PATH/Contents/PlugIns/JobsProjectToolsFinderSync.appex"
}
# 缺失副本不触碰共同配置；另一位置启用时只清理当前非活动副本。
execute_selected_operation() {
  if [[ "$OPERATION" == cleanup ]]; then
    jobs_deployment_cleanup_existing_build_products "$BUILT_APP_PATH" "$PROJECT_ROOT/work/DerivedData" com.jobs.JobsProjectTools JobsProjectToolsFinderSync.appex "$EXTENSION_ID"
    return $?
  fi
  if [[ "$OPERATION" == uninstall ]]; then
    if [[ ! -e "$APP_PATH" && ! -L "$APP_PATH" ]]; then
      print -r -- "ℹ 所选位置未安装，无需卸载：$APP_PATH"
      return 0
    fi
    jobs_deployment_validate_app "$APP_PATH" com.jobs.JobsProjectTools JobsProjectToolsFinderSync.appex "$EXTENSION_ID" || return $?
    local other_enabled=0
    jobs_deployment_has_other_enabled "$APP_PATH" "$EXTENSION_ID" || other_enabled=$?
    (( other_enabled <= 1 )) || return "$other_enabled"
    if (( other_enabled == 0 )); then
      remove_selected_application
      return $?
    fi
  fi
  project_capture_configuration || return $?
  read_configuration
  if [[ "$OPERATION" == install ]]; then
    install_features "${REQUESTED[@]}"
  else
    uninstall_features "${REQUESTED[@]}"
  fi
  PROJECT_CONFIG_COMMITTED=1
  if [[ "${JOBS_SKIP_FINDER_RESTART:-0}" != 1 ]]; then
    /usr/bin/killall Finder 2>/dev/null || true
  fi
}
# zsh 的 ERR_EXIT 在函数失败时不保证触发 EXIT，错误陷阱也必须撤回本次事务。
TRAPZERR() {
  local original_result=$?
  if [[ -n "$PROJECT_CONFIG_TRANSACTION" ]]; then
    project_finish_transaction "$original_result" || true
  fi
  return "$original_result"
}
# 只恢复已经开始的事务；位置参数错误或空选不触碰配置和系统登记。
TRAPEXIT() {
  local original_result=$?
  if [[ -n "$PROJECT_CONFIG_TRANSACTION" ]]; then
    project_finish_transaction "$original_result"
  fi
  return "$original_result"
}
# 当前调用方已经通过面板确认，本入口集中编排参数与所选位置操作。
main() {
  parse_operation "$@" # 校验明确操作、功能清单与安装位置。
  execute_selected_operation # 只管理该位置并保留未选功能与其它副本。
}

main "$@"
