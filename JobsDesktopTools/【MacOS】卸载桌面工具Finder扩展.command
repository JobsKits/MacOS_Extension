#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】卸载桌面工具Finder扩展.command
# - 核心用途：卸载全部六个桌面菜单叶子，固定新建、修复、文件显示的顺序。
# - 影响范围：只改当前用户菜单与专用配置，不创建模拟器、不切换隐藏文件偏好。
# - 运行提示：复用管理器内置说明及确认，逐项选择请用上级总安装器。
# shell: zsh

# 保留统一入口的完整范围，实际业务仍由管理器白名单校验。
forward_request() {
  exec /bin/zsh "${${(%):-%x}:A:h}/Scripts/ManageDesktopTools.zsh" uninstall ios-simulator-create android-simulator-create harmony-simulator-create android-simulator-repair harmony-simulator-repair hidden-files-toggle "$@"
}
# 转发入口直接复用管理器自述，不重复请求确认。
main() {
  forward_request "$@" # 显式交付六叶范围，管理器完成事务及登记。
}

main "$@"
