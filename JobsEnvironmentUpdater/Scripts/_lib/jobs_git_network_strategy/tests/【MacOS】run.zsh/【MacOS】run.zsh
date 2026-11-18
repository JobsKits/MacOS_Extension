#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】run.zsh
# - 核心用途：运行隔离路由用例和真实系统 Git / loopback HTTP 集成用例。
# - 影响范围：仅各套件自己的临时 HOME、临时仓库和本地 HTTP 服务。
# - 运行提示：不访问公网或修改用户配置；Ctrl+C 取消；临时夹具退出时自动清理。
# shell: zsh

typeset -g TEST_ROOT='' ROUTES_RESULT=0 INTEGRATION_RESULT=0

# 先说明验证内容和可随时取消的离线边界。
show_test_intro() {
    print -r -- 'Jobs Git 网络策略统一验证：隔离路由 + 真实 Git / loopback HTTP；无公网访问或用户配置修改。'
    print -r -- '运行策略：无交互连续验证；Ctrl+C 取消；临时日志与仓库由套件退出钩子清理。'
}
# 所有测试路径从统一入口自身定位。
prepare_test_suite() {
    setopt NO_NOMATCH
    TEST_ROOT="${${(%):-%x}:A:h:h}"
}
# 第一套从生产 main 检查路由和输出边界，外部 Git / curl 使用隔离夹具。
run_route_tests() {
    /bin/zsh "${TEST_ROOT}/【MacOS】routes.zsh/【MacOS】routes.zsh"
    ROUTES_RESULT=$?
}
# 第二套保留真实系统 Git / curl，以临时仓库和 loopback HTTP 检查完整业务。
run_integration_tests() {
    /bin/zsh "${TEST_ROOT}/【MacOS】integration.zsh/【MacOS】integration.zsh"
    INTEGRATION_RESULT=$?
}
# 任一套失败都将失败传播给调用者。
finish_test_suite() {
    print -r -- "Jobs Git 统一验证退出码：路由=${ROUTES_RESULT}，本地集成=${INTEGRATION_RESULT}。"
    (( ROUTES_RESULT == 0 && INTEGRATION_RESULT == 0 ))
}
# 编排测试说明、路由和真实本地集成。
main() {
  show_test_intro # 先展示离线范围、取消方式和记录清理。
  prepare_test_suite # 确定两个测试套件的同包路径。
  run_route_tests # 验证动态选路、参数和单次业务执行。
  run_integration_tests # 验证真实 Git 元数据与本地 HTTP 传输。
  finish_test_suite # 汇总并传播两个套件的最终状态。
}

main "$@"
