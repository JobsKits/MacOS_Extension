#!/bin/zsh
# 脚本自述：
# - 核心用途：通过统一项目菜单启用 Git 提交回退单项，保留其余功能。
# - 影响范围：当前用户 Finder 扩展配置；不执行目标仓库回退。
# - 运行提示：转发到统一安装器，复用其内置自述、确认与日志。
# 转交统一包，完整目录缺失时停止。
forward_project_tools() {
  local source_path="${(%):-%x}"
  local entry="${source_path:A:h:h}/JobsProjectTools/【MacOS】安装项目工具Finder扩展.command"
  if [[ ! -f "$entry" ]]; then
    print -u2 -r -- '请保留包含 JobsProjectTools 的完整 MacOS@Extension 目录。'
    return 1
  fi
  exec /bin/zsh "$entry" git-rollback
}
# 兼容入口只转发单项，确认由统一包负责。
main() {
  forward_project_tools "$@" # 启用统一Git菜单中的提交回退单项。
}

main "$@"
