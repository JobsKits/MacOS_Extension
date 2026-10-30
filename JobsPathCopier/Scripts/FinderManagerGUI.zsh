#!/bin/zsh
# shell: zsh
# GUI 启动支持库：由 App 后台编译并运行原生管理面板；后台管理器仅位于 Scripts。
# 本文件随可独立复制的功能包分发，不执行扩展安装、登记或删除。

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
# 从同名 App 进入后台会话，首次编译失败也通过 GUI 告知用户。
jobs_launch_finder_manager_gui() {
  local entry="$1" scope="$2" action="${3:-install}" gui_session="${4:-0}"
  local entry_dir="${1:A:h:h}" source="" binary="" launch_log="" temporary="" compile_status=0
  if [[ -f "$entry_dir/Scripts/SelectFinderExtensionFeatures.swift" ]]; then
    source="$entry_dir/Scripts/SelectFinderExtensionFeatures.swift"
    binary="$entry_dir/work/SelectFinderExtensionFeatures"
  else
    source="$entry_dir/Scripts/ManagementPanel.swift"
    binary="$entry_dir/work/ManagementPanel"
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
  local arguments=(--manager "$entry" --action "$action")
  [[ -z "$scope" ]] || arguments+=(--scope "$scope")
  exec "$binary" "${arguments[@]}"
}
