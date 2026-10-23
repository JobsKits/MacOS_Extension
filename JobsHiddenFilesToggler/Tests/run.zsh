#!/bin/zsh
# 脚本自述：
# - 脚本名称：JobsHiddenFilesToggler 隔离回归。
# - 核心用途：验证背景菜单范围、固定请求、单次派发、偏好读写与独立安装边界。
# - 影响范围：只使用临时夹具和命令替身，不切换真实偏好、不注册扩展、不刷新 Finder。
# - 运行提示：开发者明确运行此测试即表示授权隔离验证，Ctrl+C 取消。
# shell: zsh

TEST_ROOT=''
PROJECT_ROOT=''
TEMP_ROOT=''
# 先说明只运行隔离夹具，不修改实际 Finder 状态。
show_test_intro() {
    print -r -- 'Jobs 显示 / 隐藏文件隔离回归：不写真实偏好、不注册扩展、不刷新 Finder。'
}
# 按脚本位置建立本次独立的测试产物目录。
initialize_test_context() {
    setopt NO_NOMATCH PIPE_FAIL
    TEST_ROOT="${${(%):-%x}:A:h}"
    PROJECT_ROOT="${TEST_ROOT:h}"
    TEMP_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/JobsHiddenFilesTests.XXXXXXXX")" || exit 1
}
# 只清理本次测试程序，不递归处理其它目录。
cleanup_test_context() {
    [[ -n "$TEMP_ROOT" ]] || return 0
    /bin/rm -f "$TEMP_ROOT/behavior" "$TEMP_ROOT/delegate"
    /bin/rmdir "$TEMP_ROOT" 2>/dev/null
}
# 退出时撤回本次临时产物，不影响用户配置。
TRAPEXIT() {
    cleanup_test_context
}
# 通过可注入边界验证规范值、偏好同步、失败和纯菜单上下文。
run_behavior_tests() {
    /usr/bin/xcrun swiftc \
        "$PROJECT_ROOT/JobsHiddenFilesShared/HiddenFilesRequest/HiddenFilesRequest.swift" \
        "$PROJECT_ROOT/JobsHiddenFilesShared/HiddenFilesMenuContext/HiddenFilesMenuContext.swift" \
        "$PROJECT_ROOT/JobsHiddenFilesToggler/HiddenFilesToggleService/HiddenFilesToggleService.swift" \
        "$PROJECT_ROOT/JobsHiddenFilesToggler/FinderHiddenFilesPreferences/FinderHiddenFilesPreferences.swift" \
        "$TEST_ROOT/HiddenFilesBehaviorTests.swift" \
        -o "$TEMP_ROOT/behavior" || exit 1
    "$TEMP_ROOT/behavior" || exit 1
}
# 假 Model 承接真实 AppDelegate，验证重复 URL 不会反转两次。
run_delegate_tests() {
    /usr/bin/xcrun swiftc \
        "$PROJECT_ROOT/JobsHiddenFilesShared/HiddenFilesRequest/HiddenFilesRequest.swift" \
        "$PROJECT_ROOT/JobsHiddenFilesToggler/AppDelegate.swift" \
        "$TEST_ROOT/HiddenFilesAppDelegateTests.swift" \
        -o "$TEMP_ROOT/delegate" || exit 1
    "$TEMP_ROOT/delegate" || exit 1
}
# 由系统命令替身覆盖登记、签名检查入口与精确卸载边界。
run_installer_tests() {
    /usr/bin/ruby "$TEST_ROOT/InstallerRegistrationTests.rb" || exit 1
}
# 编排完整隔离验证，任何失败均停止。
main() {
    show_test_intro # 先展示测试范围与取消方式。
    initialize_test_context # 为本次编译准备临时目录。
    run_behavior_tests # 验证背景范围、固定请求和偏好切换失败路径。
    run_delegate_tests # 验证宿主两类 URL 回调只处理一次动作。
    run_installer_tests # 验证本功能独立安装与卸载。
}

main "$@"
