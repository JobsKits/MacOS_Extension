#!/bin/zsh
# 脚本自述：
# - 脚本名称：JobsGitProxyConfigurator 隔离回归。
# - 核心用途：验证固定请求、真实桌面判定、单次派发、私有载体与菜单安装边界。
# - 影响范围：只使用临时夹具和命令替身；不打开 Terminal、不注册扩展、不安装 Git 配置。
# - 运行提示：开发者明确运行此测试即表示授权隔离验证，Ctrl+C 取消。
# shell: zsh

TEST_ROOT=''
PROJECT_ROOT=''
TEMP_ROOT=''
# 先说明测试范围，避免误解为真实菜单安装。
show_test_intro() {
    print -r -- 'Jobs Git 动态代理桌面菜单隔离回归：不注册扩展、不启动真实配置，不刷新 Finder。'
}
# 定位源码和本次临时编译产物。
initialize_test_context() {
    setopt NO_NOMATCH PIPE_FAIL
    TEST_ROOT="${${(%):-%x}:A:h}"
    PROJECT_ROOT="${TEST_ROOT:h}"
    TEMP_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/JobsGitProxyTests.XXXXXXXX")" || exit 1
}
# 只清理本次两个测试程序，不递归删除目录。
cleanup_test_context() {
    [[ -n "$TEMP_ROOT" ]] || return 0
    /bin/rm -f "$TEMP_ROOT/transport" "$TEMP_ROOT/delegate"
    /bin/rmdir "$TEMP_ROOT" 2>/dev/null
}
# 退出清理不涉及实际 App 或用户配置。
TRAPEXIT() {
    cleanup_test_context
}
# 包内业务是完整副本；规范源存在时逐字节校验，独立拷走仍可运行测试。
verify_embedded_command() {
    local canonical="${PROJECT_ROOT}/../../../JobsCommand@Gits/【MacOS】🌐双击配置Git动态代理.command/【MacOS】🌐双击配置Git动态代理.command"
    /bin/zsh -n "$PROJECT_ROOT/Scripts/ConfigureGitDynamicProxy.command" || exit 1
    if [[ -f "$canonical" ]]; then
        /usr/bin/cmp "$canonical" "$PROJECT_ROOT/Scripts/ConfigureGitDynamicProxy.command" || exit 1
        print -r -- '✔ 包内完整 command 与规范源逐字节一致。'
    else
        print -r -- '规范源不在当前目录树，已校验自包含业务脚本语法。'
    fi
}
# 编译真实上下文和终端载体，仅运行临时假业务脚本。
run_transport_tests() {
    /usr/bin/xcrun swiftc \
        "$PROJECT_ROOT/JobsGitProxyShared/GitProxyRequest/GitProxyRequest.swift" \
        "$PROJECT_ROOT/JobsGitProxyShared/GitProxyMenuContext/GitProxyMenuContext.swift" \
        "$PROJECT_ROOT/JobsGitProxyConfigurator/GitProxyTerminalLauncher/GitProxyTerminalLauncher.swift" \
        "$PROJECT_ROOT/JobsGitProxyConfigurator/GitProxyModel/GitProxyModel.swift" \
        "$TEST_ROOT/GitProxyTransportTests.swift" \
        -o "$TEMP_ROOT/transport" || exit 1
    "$TEMP_ROOT/transport" || exit 1
}
# 用假 Model 运行真实 AppDelegate，校验两个 URL 接收回调不会重复派发。
run_delegate_tests() {
    /usr/bin/xcrun swiftc \
        "$PROJECT_ROOT/JobsGitProxyShared/GitProxyRequest/GitProxyRequest.swift" \
        "$PROJECT_ROOT/JobsGitProxyConfigurator/AppDelegate.swift" \
        "$TEST_ROOT/GitProxyAppDelegateTests.swift" \
        -o "$TEMP_ROOT/delegate" || exit 1
    "$TEMP_ROOT/delegate" || exit 1
}
# 系统注册命令全部由 Ruby 夹具替换，覆盖独立安装与卸载范围。
run_installer_tests() {
    /usr/bin/ruby "$TEST_ROOT/InstallerRegistrationTests.rb" || exit 1
}
# 编排隔离验证；任何失败均停止，不进入真实安装流程。
main() {
    show_test_intro # 首先说明不涉及真实菜单或用户配置。
    initialize_test_context # 创建本次临时测试目录。
    verify_embedded_command # 对账业务资源与独立完整脚本。
    run_transport_tests # 检查请求、桌面范围、转义和临时文件清理。
    run_delegate_tests # 检查同一宿主只派发一次业务动作。
    run_installer_tests # 验证菜单注册、卸载和跳过 Finder 刷新。
}

main "$@"
