#!/bin/zsh
# 脚本自述：
# - 脚本名称：SetupCreateAndroidSimulator.zsh。
# - 核心用途：启动已有AVD或按完整设备/系统映像清单创建Android模拟器。
# - 影响范围和取消方式由随包原内核的自述、许可及逐层确认完整说明。

# 内核只定义函数，入口显式先展示其自述，再执行完整模拟器流程。
setup_android_simulator_intro() {
    source "${${(%):-%x}:A:h}/AndroidSdkSupport.zsh" || return $?
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
