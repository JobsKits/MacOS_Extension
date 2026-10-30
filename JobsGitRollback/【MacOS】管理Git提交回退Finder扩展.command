#!/bin/zsh
# shell: zsh
# 公开启动入口：仅唤起同名 GUI；安装与卸载均在面板确认后后台执行。
# 不保留终端任务，也不关闭用户其它终端会话。
launch_management_panel() {
  local entry="${ZSH_ARGZERO:A}" application="" terminal_tty=""
  local arguments=("$@")
  application="${entry:r}.app"
  if [[ ! -d "$application" ]]; then
    /usr/bin/osascript -e 'display alert "管理面板缺失" message "请保留启动脚本旁的同名 App 和 Scripts 目录。" as critical'
    return 1
  fi
  if [[ "${TERM_PROGRAM:-}" == Apple_Terminal && -t 0 && -t 1 ]]; then
    terminal_tty="$(/usr/bin/tty 2>/dev/null)"
    [[ "$terminal_tty" == /dev/tty* ]] && arguments=(--launcher-tty "$terminal_tty" "${arguments[@]}")
  fi
  /usr/bin/open -n "$application" --args --package-root "${entry:h}" "${arguments[@]}"
}
# 业务只由面板启动；本进程唤起 App 后立即结束。
main() {
  launch_management_panel "$@" # 打开独立 GUI 并交给 App 清理本次已结束的终端页。
}
main "$@"
