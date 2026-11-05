#!/bin/zsh
# 脚本自述：
# - 脚本名称：FinderManagerGUI.zsh（管理面板启动支持库）。
# - 核心用途：缓存编译原生面板，以固定身份、标准签名的 App 启动，供用户识别授权宿主。
# - 影响范围：仅当前工程或明确缓存目录中的面板二进制与 App，不执行扩展安装、登记或删除。
# - 运行提示：由管理入口 source；隐私授权须用户在系统设置中操作，不自动更改授权。
# shell: zsh

# 启动失败时在桌面显示错误；详情保留在本次独立启动日志中。
jobs_manager_launch_error() {
  local message="$1" details="${2:-}"
  print -u2 -r -- "$message${details:+：$details}"
  /usr/bin/osascript - "$message" "$details" <<'APPLESCRIPT'
on run arguments
  display alert "Finder 扩展管理器无法启动" message ((item 1 of arguments) & return & (item 2 of arguments)) as critical buttons {"好"} default button "好"
end run
APPLESCRIPT
  return 1
}
# 固定身份和执行入口才属于本工具，避免覆盖缓存目录中的同名第三方 App。
jobs_manager_gui_app_is_owned() {
  local app="$1"
  [[ -d "$app" && ! -L "$app" && ! -L "$app/Contents" &&
     -f "$app/Contents/Info.plist" && ! -L "$app/Contents/Info.plist" &&
     -d "$app/Contents/MacOS" && ! -L "$app/Contents/MacOS" &&
     -x "$app/Contents/MacOS/JobsFinderManager" && ! -L "$app/Contents/MacOS/JobsFinderManager" &&
     "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null)" == com.jobs.finderextensions.managementpanel &&
     "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist" 2>/dev/null)" == JobsFinderManager ]]
}
# 使用系统标准 ad-hoc 签名；不自定义授权需求、不修改系统隐私数据库。
jobs_manager_sign_gui_app() {
  /usr/bin/codesign --force --sign - "$1"
}
# 包内执行文件和资源都须通过验证，不能复用残缺或已被修改的缓存 App。
jobs_manager_verify_gui_app() {
  /usr/bin/codesign --verify --deep --strict "$1"
}
# 在私有暂存目录内装配固定身份，签名成功前不触碰已有 App。
jobs_manager_stage_gui_app() {
  local binary="$1" app="$2" source_hash="$3"
  /bin/mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" || return 1
  /bin/cp -p "$binary" "$app/Contents/MacOS/JobsFinderManager" &&
  /bin/chmod 755 "$app/Contents/MacOS/JobsFinderManager" || return 1
  /bin/cat > "$app/Contents/Info.plist" <<'GUI_HOST_PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.jobs.finderextensions.managementpanel</string><key>CFBundleName</key><string>Jobs右键菜单管理面板</string><key>CFBundleDisplayName</key><string>Jobs右键菜单管理面板</string><key>CFBundleExecutable</key><string>JobsFinderManager</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleVersion</key><string>1</string><key>LSUIElement</key><true/><key>NSAppleEventsUsageDescription</key><string>用于按用户操作在终端查看扩展管理日志。</string></dict></plist>
GUI_HOST_PLIST
  print -r -- "$source_hash" > "$app/Contents/Resources/BinarySource.sha256" || return 1
  jobs_manager_sign_gui_app "$app" >&2 && jobs_manager_verify_gui_app "$app" >&2
}
# 内容未变时保留稳定 App；新版本完整签名后才原子发布，失败恢复旧 App。
jobs_manager_prepare_gui_app() {
  local binary="$1" cache_dir="${2:A}" app="" source_hash="" stage="" lock="" result=0
  [[ -f "$binary" && -x "$binary" && ! -L "$binary" && -d "$cache_dir" && ! -L "$cache_dir" ]] || return 1
  app="$cache_dir/Jobs右键菜单管理面板.app"
  if [[ -e "$app" || -L "$app" ]]; then
    jobs_manager_gui_app_is_owned "$app" || { print -u2 -r -- "拒绝覆盖非自有管理 App：$app"; return 1; }
  fi
  source_hash="$(/usr/bin/shasum -a 256 "$binary" | /usr/bin/awk '{print $1}')" || return 1
  [[ ${#source_hash} == 64 ]] || return 1
  if [[ -f "$app/Contents/Resources/BinarySource.sha256" && ! -L "$app/Contents/Resources/BinarySource.sha256" &&
        "$(<"$app/Contents/Resources/BinarySource.sha256")" == "$source_hash" ]] && jobs_manager_verify_gui_app "$app" 2>/dev/null; then
    print -r -- "$app"
    return 0
  fi
  lock="$cache_dir/.JobsFinderManagerHost.lock"
  /bin/mkdir "$lock" 2>/dev/null || { print -u2 -r -- "管理面板 App 正在准备，请稍后重试：$lock"; return 1; }
  stage="$(/usr/bin/mktemp -d "$cache_dir/.JobsFinderManagerHost.XXXXXXXX")" || { /bin/rmdir "$lock"; return 1; }
  print -u2 -r -- "来源：本地面板缓存 $binary"
  print -u2 -r -- "目标：可授权原生管理 App $app"
  jobs_manager_stage_gui_app "$binary" "$stage/Jobs右键菜单管理面板.app" "$source_hash" || result=$?
  if (( ! result )) && [[ -e "$app" || -L "$app" ]]; then
    jobs_manager_gui_app_is_owned "$app" && /bin/mv "$app" "$stage/previous.app" || result=1
  fi
  if (( ! result )); then
    /bin/mv "$stage/Jobs右键菜单管理面板.app" "$app" || result=1
    if (( result )) && [[ -d "$stage/previous.app" ]]; then
      if ! /bin/mv "$stage/previous.app" "$app"; then
        print -u2 -r -- "管理面板恢复失败，原 App 保留：$stage/previous.app"
        return 1
      fi
    fi
  fi
  /bin/rm -r -- "$stage" || result=1
  /bin/rmdir "$lock" || result=1
  (( ! result )) || return "$result"
  print -r -- "$app"
}
# 从同名 App 进入后台会话，首次编译失败也通过 GUI 告知用户。
jobs_launch_finder_manager_gui() {
  local entry="$1" scope="$2" action="${3:-install}" gui_session="${4:-0}"
  local entry_dir="${1:A:h:h}" source="" binary="" launch_log="" temporary="" compile_status=0
  local cache_dir="${JOBS_FINDER_MANAGER_CACHE_DIR:-$entry_dir/work}"
  [[ "$cache_dir" == /* ]] || { jobs_manager_launch_error '管理面板缓存目录必须是绝对路径。' "$cache_dir"; return 1; }
  if [[ -f "$entry_dir/Scripts/SelectFinderExtensionFeatures.swift" ]]; then
    source="$entry_dir/Scripts/SelectFinderExtensionFeatures.swift"
    binary="$cache_dir/SelectFinderExtensionFeatures"
  else
    source="$entry_dir/Scripts/ManagementPanel.swift"
    binary="$cache_dir/ManagementPanel"
  fi
  [[ -f "$source" ]] || { jobs_manager_launch_error '缺少随包的管理面板源码。' "$source"; return 1; }
  if [[ ! -x "$binary" || "$source" -nt "$binary" ]]; then
    launch_log="$(/usr/bin/mktemp "${TMPDIR:-/tmp/}JobsFinderManagerLaunch.XXXXXXXX")" || return 1
    /bin/mkdir -p "${binary:h}" || { jobs_manager_launch_error '无法建立管理面板缓存目录。' "${binary:h}"; return 1; }
    temporary="$(/usr/bin/mktemp "${binary}.XXXXXXXX")" || return 1
    /usr/bin/xcrun swiftc -O "$source" -o "$temporary" > "$launch_log" 2>&1
    compile_status=$?
    if (( compile_status != 0 )); then
      /bin/rm -f "$temporary"
      jobs_manager_launch_error '管理面板编译失败，请检查 Xcode 命令行工具。启动日志：' "$launch_log"
      return "$compile_status"
    fi
    /bin/mv -f "$temporary" "$binary" || { jobs_manager_launch_error '无法保存管理面板。' "$binary"; return 1; }
  fi
  local arguments=(--manager "$entry" --action "$action" --install-location "${JOBS_FINDER_INSTALL_LOCATION:-build}")
  [[ "${JOBS_FINDER_CLEANUP_BUILD_PRODUCTS:-0}" != 1 ]] || arguments+=(--cleanup-build-products)
  [[ -z "$scope" ]] || arguments+=(--scope "$scope")
  local host_app=""
  host_app="$(jobs_manager_prepare_gui_app "$binary" "$cache_dir")" || {
    jobs_manager_launch_error '无法准备可授权的管理面板 App，原缓存 App 已保留。' "$cache_dir"
    return 1
  }
  export JOBS_FINDER_RESPONSIBLE_APP="$host_app"
  exec "$host_app/Contents/MacOS/JobsFinderManager" "${arguments[@]}"
}
