#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】联合App管理.zsh（管理资源装配函数库）。
# - 核心用途：将原生管理面板、后台管理器与独立功能卸载入口装入联合 App。
# - 影响范围：只更新已核验身份容器内的管理资源，不构建、登记或卸载任何扩展。
# - 运行提示：仅供已确认的部署流程 source；写入前暂存，失败保留原管理资源。
# shell: zsh

typeset -g JOBS_COMBINED_MANAGER_LIBRARY_SOURCE="${(%):-%x}"
# 拒绝链接资源，复制不会读取容器外文件或写入其它位置。
jobs_combined_manager_check_tree() {
  local directory="$1" linked=""
  [[ -d "$directory" && ! -L "$directory" && "${directory:A}" == "$directory" ]] || return 1
  linked="$(/usr/bin/find "$directory" -type l -print -quit)" || return 1
  [[ -z "$linked" ]]
}
# 仅复制管理入口和部署库，业务 Tools 与工程源码不进入联合管理器。
jobs_combined_manager_copy_package() {
  local package="$1" target="$2" script="" deployment="$1/Scripts/【MacOS】AppDeployment.zsh"
  [[ -f "$package/Scripts/ManageExtension.zsh" && ! -L "$package/Scripts/ManageExtension.zsh" ]] || return 1
  /bin/mkdir -p "$target/Scripts" || return 1
  for script in ManageExtension.zsh ManageProjectTools.zsh ManageDesktopTools.zsh; do
    [[ -e "$package/Scripts/$script" || -L "$package/Scripts/$script" ]] || continue
    [[ -f "$package/Scripts/$script" && ! -L "$package/Scripts/$script" ]] || return 1
    /bin/cp -p "$package/Scripts/$script" "$target/Scripts/$script" || return 1
  done
  jobs_combined_manager_check_tree "$deployment" || return 1
  [[ ! -e "$target/Scripts/【MacOS】AppDeployment.zsh" ]] || /bin/rm -r -- "$target/Scripts/【MacOS】AppDeployment.zsh" || return 1
  /bin/cp -R "$deployment" "$target/Scripts/【MacOS】AppDeployment.zsh"
}
# 身份匹配后将新资源准备在同卷暂存区，再替换 ManagerRoot；失败恢复原目录。
jobs_prepare_combined_manager_resources() {
  local container="$1" library_dir="${JOBS_COMBINED_MANAGER_LIBRARY_SOURCE:A:h}" source_root="" resources="" stage="" target="" package="" snapshot="" result=0
  local packages=(JobsProjectTools JobsPathCopier JobsFileCreator JobsRunAuthorizer JobsRunAuthorizationRevoker JobsIPAResigner JobsDesktopTools JobsFlutterTools JobsTerminalOpener JobsIOSTools)
  [[ "$container" == /* && -d "$container" && ! -L "$container" && "${container:A}" == "$container" &&
     "${container:t}" == Jobs自定义右键菜单.app && ! -L "$container/Contents" &&
     -f "$container/Contents/Info.plist" && ! -L "$container/Contents/Info.plist" &&
     "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$container/Contents/Info.plist" 2>/dev/null)" == com.jobs.finderextensions.manager ]] || {
    print -u2 '✖ 联合 App 管理资源：容器身份或路径不符合要求。'; return 1
  }
  resources="$container/Contents/Resources"
  [[ ! -L "$resources" ]] || return 1
  /bin/mkdir -p "$resources" || return 1
  jobs_combined_manager_check_tree "$resources" || return 1
  if [[ -e "$resources/ManageInstalledExtensions.zsh" ]]; then
    [[ -f "$resources/ManageInstalledExtensions.zsh" ]] || return 1
  fi
  target="$resources/ManagerRoot"
  if [[ -e "$target" ]]; then
    [[ -d "$target" && -f "$target/.jobs-combined-manager" && "$(<"$target/.jobs-combined-manager")" == com.jobs.finderextensions.manager ]] || return 1
  fi
  for snapshot in RootWorker PanelSource GuiBootstrap; do
    [[ -f "$library_dir/Resources/$snapshot.txt" && ! -L "$library_dir/Resources/$snapshot.txt" ]] || return 1
  done
  source_root="${library_dir:h:h}"
  stage="$(/usr/bin/mktemp -d "$resources/.JobsCombinedManager.XXXXXXXX")" || return 1
  /bin/mkdir -p "$stage/ManagerRoot/Scripts" || result=1
  if (( ! result )) && [[ -d "$target" ]]; then
    /bin/cp -R "$target/." "$stage/ManagerRoot/" || result=1
  fi
  if (( ! result )); then
    /bin/cp "$library_dir/Resources/RootWorker.txt" "$stage/ManagerRoot/Scripts/ManageFinderExtensions.zsh" &&
    /bin/cp "$library_dir/Resources/PanelSource.txt" "$stage/ManagerRoot/Scripts/SelectFinderExtensionFeatures.swift" &&
    /bin/cp "$library_dir/Resources/GuiBootstrap.txt" "$stage/ManagerRoot/Scripts/FinderManagerGUI.zsh" &&
    print -r -- com.jobs.finderextensions.manager > "$stage/ManagerRoot/.jobs-combined-manager" || result=1
  fi
  if (( ! result )); then
    if [[ -f "$source_root/Scripts/ManageFinderExtensions.zsh" ]]; then
      for package in "${packages[@]}"; do
        [[ -d "$source_root/$package" ]] || continue
        jobs_combined_manager_copy_package "$source_root/$package" "$stage/ManagerRoot/$package" || { result=1; break; }
      done
    else
      package="${source_root:t}"
      (( ${packages[(Ie)$package]} )) && jobs_combined_manager_copy_package "$source_root" "$stage/ManagerRoot/$package" || result=1
    fi
  fi
  if (( ! result )); then
    jobs_combined_manager_check_tree "$source_root/Scripts/【MacOS】AppDeployment.zsh" || result=1
    [[ ! -e "$stage/ManagerRoot/Scripts/【MacOS】AppDeployment.zsh" ]] || /bin/rm -r -- "$stage/ManagerRoot/Scripts/【MacOS】AppDeployment.zsh" || result=1
    (( result )) || /bin/cp -R "$source_root/Scripts/【MacOS】AppDeployment.zsh" "$stage/ManagerRoot/Scripts/【MacOS】AppDeployment.zsh" || result=1
  fi
  if (( ! result )); then
    /bin/cat > "$stage/ManageInstalledExtensions.zsh" <<'ENTRY'
#!/bin/zsh
# 联合 App 的管理入口：本次管理从私有快照运行，卸载自身后仍保留所有后端文件。
JOBS_COMBINED_SESSION_SOURCE="${(%):-%x}"
JOBS_COMBINED_SESSION_DIR=""
JOBS_COMBINED_SESSION_ROOT=""
JOBS_COMBINED_SESSION_IDENTITY=""
JOBS_COMBINED_SESSION_PID=""
# 只清理当前入口创建且身份未变化的快照；子进程尚在运行时保留其依赖。
jobs_combined_session_cleanup() {
  local exit_code="$1"
  if [[ -n "$JOBS_COMBINED_SESSION_PID" ]] && /bin/kill -0 "$JOBS_COMBINED_SESSION_PID" 2>/dev/null; then
    print -u2 -r -- "ℹ 管理进程仍在运行，保留会话快照：$JOBS_COMBINED_SESSION_DIR"
    return "$exit_code"
  fi
  if [[ -n "$JOBS_COMBINED_SESSION_DIR" && -d "$JOBS_COMBINED_SESSION_DIR" &&
        ! -L "$JOBS_COMBINED_SESSION_DIR" && "${JOBS_COMBINED_SESSION_DIR:h}" == "$JOBS_COMBINED_SESSION_ROOT" &&
        "${JOBS_COMBINED_SESSION_DIR:A}" == "$JOBS_COMBINED_SESSION_DIR" &&
        "${JOBS_COMBINED_SESSION_DIR:t}" == JobsFinderManagerSession.* &&
        "$(/usr/bin/stat -f '%d:%i' "$JOBS_COMBINED_SESSION_DIR")" == "$JOBS_COMBINED_SESSION_IDENTITY" ]]; then
    /bin/rm -r -- "$JOBS_COMBINED_SESSION_DIR" || print -u2 -r -- "⚠ 会话快照未能清理：$JOBS_COMBINED_SESSION_DIR"
  fi
  return "$exit_code"
}
# 顶层退出钩子覆盖整个会话，不能在准备函数返回时提前清理。
TRAPEXIT() {
  jobs_combined_session_cleanup "$?"
}
# 完整复制管理根；不跟随资源链接，也不把缓存写回签名后的 App。
jobs_combined_session_prepare() {
  setopt NO_NOMATCH
  local resources="${JOBS_COMBINED_SESSION_SOURCE:A:h}" manager_root="" linked=""
  manager_root="$resources/ManagerRoot"
  [[ -d "$manager_root" && ! -L "$manager_root" && "${manager_root:A}" == "$manager_root" ]] || return 1
  linked="$(/usr/bin/find "$manager_root" -type l -print -quit)" || return 1
  [[ -z "$linked" ]] || return 1
  JOBS_COMBINED_SESSION_ROOT="${TMPDIR:-/tmp/}"
  JOBS_COMBINED_SESSION_ROOT="${JOBS_COMBINED_SESSION_ROOT:A}"
  [[ -d "$JOBS_COMBINED_SESSION_ROOT" && -w "$JOBS_COMBINED_SESSION_ROOT" ]] || return 1
  JOBS_COMBINED_SESSION_DIR="$(/usr/bin/mktemp -d "$JOBS_COMBINED_SESSION_ROOT/JobsFinderManagerSession.XXXXXXXX")" || return 1
  JOBS_COMBINED_SESSION_IDENTITY="$(/usr/bin/stat -f '%d:%i' "$JOBS_COMBINED_SESSION_DIR")" || return 1
  /bin/cp -R "$manager_root" "$JOBS_COMBINED_SESSION_DIR/ManagerRoot" || return 1
  unset JOBS_FINDER_BUILT_APP_PATH JOBS_FINDER_SOURCE_ROOT JOBS_INSTALL_FEATURES JOBS_TOOLS_REQUEST
  export JOBS_FINDER_INSTALL_LOCATION=applications
  export JOBS_FINDER_CLEANUP_BUILD_PRODUCTS=0
  export JOBS_FINDER_MANAGER_CACHE_DIR="${HOME}/Library/Caches/JobsFinderExtensions/Management"
}
# 等待本次面板及其 worker 结束后，退出清理只作用于私有快照。
jobs_combined_session_run() {
  local exit_code=0
  /bin/zsh "$JOBS_COMBINED_SESSION_DIR/ManagerRoot/Scripts/ManageFinderExtensions.zsh" --action uninstall --install-location applications --gui-session "$@" &
  JOBS_COMBINED_SESSION_PID=$!
  wait "$JOBS_COMBINED_SESSION_PID" || exit_code=$?
  if ! /bin/kill -0 "$JOBS_COMBINED_SESSION_PID" 2>/dev/null; then
    JOBS_COMBINED_SESSION_PID=""
  fi
  return "$exit_code"
}
# 准备私有会话并在其生命周期内管理已装功能，关闭后释放本次副本。
main() {
  jobs_combined_session_prepare || return $? # 先复制完整管理资源，失败不执行业务。
  jobs_combined_session_run "$@" # 从快照打开面板并等待其所有管理操作结束。
}
main "$@"
ENTRY
    /bin/chmod 755 "$stage/ManageInstalledExtensions.zsh" || result=1
  fi
  if (( ! result )); then
    [[ ! -e "$target" ]] || /bin/mv "$target" "$stage/previous" || result=1
    if (( ! result )); then
      /bin/mv "$stage/ManagerRoot" "$target" || result=1
      if (( ! result )); then
        /bin/mv -f "$stage/ManageInstalledExtensions.zsh" "$resources/ManageInstalledExtensions.zsh" || result=1
      fi
      if (( result )); then
        [[ ! -e "$target" ]] || /bin/rm -r -- "$target"
        if [[ -d "$stage/previous" ]] && ! /bin/mv "$stage/previous" "$target"; then
          print -u2 -r -- "✖ 联合管理资源恢复失败，备份保留：$stage/previous"
          return 1
        fi
      fi
    fi
  fi
  /bin/rm -r -- "$stage" || result=1
  return "$result"
}
