#!/bin/zsh
# 由安装 / 卸载入口调用。共用一份配置和一个扩展，保留逐项启停能力。
setopt ERR_EXIT NO_UNSET PIPE_FAIL
PROJECT_ROOT="${0:A:h:h}"
CONFIG_DIR="${HOME}/Library/Application Support/JobsProjectTools"
CONFIG_PATH="${CONFIG_DIR}/EnabledFeatures.txt"
APP_PATH="${PROJECT_ROOT}/work/DerivedData/Build/Products/Debug/JobsProjectTools.app"
EXTENSION_PATH="${APP_PATH}/Contents/PlugIns/JobsProjectToolsFinderSync.appex"
EXTENSION_ID="com.jobs.JobsProjectTools.FinderSyncExtension"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
FEATURES=(android_studio_opener vscode_opener xcode_opener git-pull git_remote git_remote_copier git-proxy-configure git_empty_commit_push)
LEGACY_APPS=(JobsAndroidStudioOpener JobsVSCodeOpener JobsXcodeOpener JobsGitPuller JobsGitRemoteOpener JobsGitRemoteCopier)
LEGACY_EXTENSIONS=(JobsAndroidStudioFinderSync JobsVSCodeFinderSync JobsXcodeFinderSync JobsGitPullFinderSync JobsGitRemoteFinderSync JobsGitRemoteCopyFinderSync)
GIT_MIGRATION_PATH="${CONFIG_DIR}/GitMenuMigrationVersion.txt"
TERMINAL_CONFIG_PATH="${HOME}/Library/Application Support/JobsTerminalOpener/EnabledFinderMenuFeatures.txt"
typeset -A ENABLED

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
  /bin/mkdir -p "$CONFIG_DIR"
  temporary="$(/usr/bin/mktemp "$CONFIG_DIR/.features.XXXXXX")"
  print -nr -- "${(j:,:)values}" > "$temporary"
  /bin/mv -f "$temporary" "$CONFIG_PATH"
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
# 只有统一安装完成迁移才写标记，后续卸载不会被旧选择重新启用。
save_git_migration_marker() {
  print -r -- 1 > "$GIT_MIGRATION_PATH"
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
  for feature in "$@"; do ENABLED[$feature]=1; done
  JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1 /usr/bin/xcodebuild \
    -project "$PROJECT_ROOT/JobsProjectTools.xcodeproj" -scheme JobsProjectTools \
    -configuration Debug -destination "platform=macOS,arch=$(/usr/bin/uname -m)" \
    -derivedDataPath "$PROJECT_ROOT/work/DerivedData" build
  [[ -d "$EXTENSION_PATH" ]]
  /usr/bin/pkill -x JobsProjectTools 2>/dev/null || true
  /usr/bin/pkill -f 'JobsProjectToolsFinderSync.appex/Contents/MacOS/JobsProjectToolsFinderSync' 2>/dev/null || true
  "$LSREGISTER" -f "$APP_PATH"
  /usr/bin/pluginkit -a "$EXTENSION_PATH"
  /usr/bin/pluginkit -e use -i "$EXTENSION_ID"
  wait_until_enabled
  save_configuration
  save_git_migration_marker
  retire_terminal_git_menu
  for index in {1..6}; do retire_legacy "$index"; done
  retire_legacy_proxy
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
    elif [[ "$feature" == git_empty_commit_push ]]; then
      retire_terminal_git_menu
    fi
  done
  # 尚未迁移的旧安装没有配置，不创建空文件去影响其他旧功能。
  if [[ -f "$CONFIG_PATH" ]]; then
    save_configuration
    if (( ${#ENABLED} == 0 )); then
      /usr/bin/pluginkit -e ignore -i "$EXTENSION_ID"
      [[ ! -d "$EXTENSION_PATH" ]] || /usr/bin/pluginkit -r "$EXTENSION_PATH"
      /usr/bin/pkill -x JobsProjectTools 2>/dev/null || true
    fi
  fi
  print -r -- "已关闭项目菜单：$*"
}

main() {
  local operation="${1:-}" feature=""
  [[ "$operation" == install || "$operation" == uninstall ]] || { print -u2 '用法：ManageProjectTools.zsh install|uninstall 功能ID...'; return 1; }
  shift
  (( $# > 0 )) || return 1
  for feature in "$@"; do
    (( ${FEATURES[(Ie)$feature]} )) || { print -u2 "未知功能：$feature"; return 1; }
  done
  read_configuration
  if [[ "$operation" == install ]]; then install_features "$@"; else uninstall_features "$@"; fi
  if [[ "${JOBS_SKIP_FINDER_RESTART:-0}" != 1 ]]; then
    /usr/bin/killall Finder 2>/dev/null || true
  fi
}

main "$@"
