#!/bin/zsh
# 兼容原入口：Git 动态代理菜单归入统一 Git操作子菜单，业务配置保留。
# 转发入口复用统一安装器自述与确认，不重复确认或执行代理脚本。
# 保留逐项安装能力，仅影响 Git 动态代理菜单。
# 转交统一项目工具，继续透传显式 CLI 授权与刷新选项。
main() {
  /bin/zsh "${ZSH_ARGZERO:A:h:h}/JobsProjectTools/【MacOS】安装项目工具Finder扩展.command" git-proxy-configure "$@" # 复用统一入口自述与菜单管理。
}
main "$@"
