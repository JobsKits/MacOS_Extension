#!/bin/zsh
# 脚本自述：
# - 脚本名称：SetupCreateAndroidSimulator.zsh。
# - 核心用途：启动已有AVD或按完整设备/系统映像清单创建Android模拟器。
# - 影响范围和取消方式由随包原内核的自述、许可及逐层确认完整说明。

# 内核只定义函数，入口显式先展示其自述，再执行完整模拟器流程。
# JOBS_SOURCE_LAYOUT_V1：源码同名包装与发布旧平铺目录分别解析，不改变运行时资源名。
# 保留实际文件路径；只有源码同名包装才向上还原原资源目录。
jobs_layout_directory() {
  local file="${1:A}" directory="${1:A:h}" levels="${2:-0}"
  [[ "${directory:t}" != "${file:t}" ]] || directory="${directory:h}"
  while (( levels > 0 )); do
    directory="${directory:h}"
    (( levels -= 1 ))
  done
  print -r -- "$directory"
}
# 优先兼容已发布的平铺文件，再尝试源码中的同名包装；不跟随链接文件。
jobs_layout_file() {
  local file="$1" directory="${1:h}" name="${1:t}" candidate="" prefixed=""
  if [[ -f "$file" && ! -L "$file" ]]; then
    print -r -- "$file"
    return 0
  fi
  case "$name" in
    EnableFinderExtension.zsh) prefixed="【MacOS@Xcode】$name" ;;
    *.zsh|*.command|*.sh) [[ "$name" == '【MacOS'* ]] && prefixed="$name" || prefixed="【MacOS】$name" ;;
    *.jxa) prefixed="$name" ;;
    *) print -r -- "$file"; return 0 ;;
  esac
  [[ "${directory:t}" != "$name" ]] || directory="${directory:h}"
  candidate="$directory/$prefixed/$prefixed"
  if [[ ! -L "$directory/$prefixed" && -f "$candidate" && ! -L "$candidate" ]]; then
    print -r -- "$candidate"
  else
    print -r -- "$file"
  fi
}

setup_android_simulator_intro() {
    source "$(jobs_layout_file "$(jobs_layout_directory "${(%):-%x}")/AndroidSdkSupport.zsh")" || return $?
    show_script_intro_and_wait "$@"
}
# 独立入口保持原内核全部交互，不以仅source假装创建成功。
main() {
    setup_android_simulator_intro "$@" # 加载随包完整内核并首先展示自述与确认。
    android_run_requested_action # 通过真实内核准备工具链，选择/创建或启动AVD。
}

if [[ "$ZSH_EVAL_CONTEXT" == toplevel ]]; then
    main "$@"
fi
