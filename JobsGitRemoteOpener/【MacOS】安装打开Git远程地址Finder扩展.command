#!/bin/zsh
# 兼容原入口：此功能由统一项目菜单扩展提供，保留其余功能的选择。
entry="${0:A:h:h}/JobsProjectTools/【MacOS】安装项目工具Finder扩展.command"
[[ -f "$entry" ]] || { print -u2 '请保留包含 JobsProjectTools 的完整 MacOS@Extension 目录。'; exit 1; }
exec /bin/zsh "$entry" git_remote
