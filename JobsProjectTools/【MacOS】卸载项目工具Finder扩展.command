#!/bin/zsh
# 只关闭传入的功能；全部关闭后停用统一扩展，不删除其他功能与源码。
print '卸载选中的 IDE / Git 菜单功能；其他已安装功能保持启用，随后重启 Finder。'
[[ -t 0 ]] || { print -u2 '请在交互终端运行。'; exit 1; }
answer=""
IFS= read -r 'answer?直接回车卸载，输入任意字符跳过：' || exit 0
[[ -z "$answer" ]] || exit 0
(( $# > 0 )) || set -- android_studio_opener vscode_opener xcode_opener git-pull git_remote git_remote_copier
exec /bin/zsh "${0:A:h}/Scripts/ManageProjectTools.zsh" uninstall "$@"
