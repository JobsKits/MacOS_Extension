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
FEATURES=(android_studio_opener vscode_opener xcode_opener git-pull git_remote git_remote_copier)
LEGACY_APPS=(JobsAndroidStudioOpener JobsVSCodeOpener JobsXcodeOpener JobsGitPuller JobsGitRemoteOpener JobsGitRemoteCopier)
LEGACY_EXTENSIONS=(JobsAndroidStudioFinderSync JobsVSCodeFinderSync JobsXcodeFinderSync JobsGitPullFinderSync JobsGitRemoteFinderSync JobsGitRemoteCopyFinderSync)
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
  /usr/bin/pluginkit -m -i "com.jobs.$1.FinderSyncExtension" -A 2>/dev/null |
    /usr/bin/awk '$1 == "+" { found=1 } END { exit !found }'
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
  for index in {1..6}; do retire_legacy "$index"; done
  print -r -- "已启用统一项目菜单：$(<"$CONFIG_PATH")"
}

uninstall_features() {
  local feature="" index=""
  for feature in "$@"; do
    unset "ENABLED[$feature]"
    index=${FEATURES[(Ie)$feature]}
    retire_legacy "$index"
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
  /usr/bin/killall Finder 2>/dev/null || true
}

main "$@"
