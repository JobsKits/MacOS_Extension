#!/bin/zsh
# 安装统一的 IDE / Git 一级菜单；按功能合并现有配置，停用对应的旧扩展。
print '安装项目工具：IDE 操作相邻，Git 操作相邻；安装后重启 Finder。'
print 'iOS/Xcode 项目只显示 Xcode；其他项目显示 Android Studio、VSCode。'
[[ -t 0 ]] || { print -u2 '请在交互终端运行。'; exit 1; }
answer=""
IFS= read -r 'answer?直接回车安装，输入任意字符跳过：' || exit 0
[[ -z "$answer" ]] || exit 0
(( $# > 0 )) || set -- android_studio_opener vscode_opener xcode_opener git-pull git_remote git_remote_copier
exec /bin/zsh "${0:A:h}/Scripts/ManageProjectTools.zsh" install "$@"
