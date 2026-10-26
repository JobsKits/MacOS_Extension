#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】卸载显示隐藏文件Finder扩展.command
# - 核心用途：卸载 hidden-files-toggle 单项菜单，保持独立入口与固定桌面顺序。
# - 影响范围：转交相邻 JobsDesktopTools 管理器，只调整该叶功能；不运行模拟器或切换隐藏文件偏好。
# - 运行提示：复用管理器的内置说明与唯一一次确认，支持 --non-interactive 和 --skip-finder-restart。
# shell: zsh

# 固定转发操作和叶 ID，调用方参数不能更换业务目标。
forward_to_desktop_tools() {
  local manager="${${(%):-%x}:A:h:h}/JobsDesktopTools/Scripts/ManageDesktopTools.zsh"
  [[ -f "$manager" ]] || { print -u2 '✖ 请取得包含 JobsDesktopTools 的完整 MacOS@Extension 源码，再运行此兼容入口。'; return 1; }
  exec /bin/zsh "$manager" uninstall hidden-files-toggle "$@"
}
# 兼容入口复用内层自述，避免出现两次确认。
main() {
  forward_to_desktop_tools "$@" # 将当前独立功能交给统一菜单管理器。
}

main "$@"
