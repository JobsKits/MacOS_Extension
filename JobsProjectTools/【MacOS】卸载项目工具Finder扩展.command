#!/bin/zsh
# 脚本自述：按选择启停 IDE 一级菜单和 Git操作子菜单，保留其它已安装功能。
# 影响范围：仅构建 / 注册菜单、保存功能选择并刷新 Finder，不执行 Git 业务。
FEATURES=()
CLI_AUTHORIZED=0
SKIP_RESTART=0
# 先说明功能范围，再按双击或明确 CLI 参数决定是否等待确认。
show_script_intro_and_wait() {
  print '卸载项目工具：IDE 保留一级入口，七项 Git 功能集中到 Git操作子菜单。'
  print 'Git操作只在有效 Git 普通文件夹 / 工作树内显示；不会自动拉取、提交或修改代理。'
  print '用 Sourcetree 打开：仅检测到已安装且可运行的 Sourcetree 时显示。'
  print '其它已安装功能保留；Ctrl+C 取消。'
  local argument="" answer=""
  for argument in "$@"; do
    case "$argument" in
      --uninstall) CLI_AUTHORIZED=1 ;;
      --skip-finder-restart) SKIP_RESTART=1 ;;
      --*) print -u2 -- "未知参数：$argument"; exit 2 ;;
      *) FEATURES+=("$argument") ;;
    esac
  done
  if (( CLI_AUTHORIZED )); then
    return 0
  fi
  [[ -t 0 ]] || { print -u2 '请在可交互终端运行。'; exit 1; }
  IFS= read -r 'answer?直接回车卸载，输入任意字符跳过：' || exit 0
  [[ -z "$answer" ]] || exit 0
}
# 未指定功能时沿用全选；刷新策略只传递给本次管理子进程。
manage_selected_features() {
  setopt NO_NOMATCH
  if (( ${#FEATURES} == 0 )); then
    FEATURES=(android_studio_opener vscode_opener xcode_opener git-pull git-rollback git-sourcetree git_remote git_remote_copier git-proxy-configure git_empty_commit_push)
  fi
  JOBS_SKIP_FINDER_RESTART="$SKIP_RESTART" /bin/zsh "${ZSH_ARGZERO:A:h}/Scripts/ManageProjectTools.zsh" uninstall "${FEATURES[@]}"
}
# 编排自述、确认与按项卸载。
main() {
  show_script_intro_and_wait "$@" # 展示范围并等待用户确认，或复用明确 CLI 授权。
  manage_selected_features # 将选择交给统一管理器，保留其他菜单。
}
main "$@"
