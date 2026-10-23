#!/bin/zsh
# Legacy entry: Flutter menus are now owned by JobsFlutterTools to keep a fixed order.
entry="${0:A:h:h}/JobsFlutterTools/【MacOS】安装Flutter开发辅助工具Finder扩展.command"
[[ -f "$entry" ]] || { print -u2 '请下载包含 JobsFlutterTools 的完整 MacOS@Extension，再安装统一 Flutter 菜单。'; exit 1; }
exec /bin/zsh "$entry" "$@"
