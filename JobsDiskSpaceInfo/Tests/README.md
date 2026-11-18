# 磁盘空间统计回归

`DiskSpaceSummaryTests.swift` 与 `../Shared/DiskSpaceSummary.swift` 一同编译运行，覆盖 APFS 共享容器、挂载别名、多卷汇总、网络／只读／内部隐藏卷过滤、配额卷、满盘、数值溢出、两位小数、十语言和单行可点击清理菜单。另覆盖可写文件镜像／RAM排除、物理控制器保留、Data完整样本优先、反复枚举与实时余量变化、读取失败不沿用旧值、挂载身份变化和逐次菜单采样；系统可用空间测试要求同次总量／余量成对采用，包含可清除部分，缺值与负数不退回原始空闲量，零值有效，超过总量时限制到总量；最后执行本机只读查询。测试不安装扩展或改动真实磁盘内容。

在当前 `Tests` 目录执行，编译产物放系统临时目录：

```sh
test_binary_dir=$(mktemp -d /tmp/jobs-disk-space-tests.XXXXXX)
xcrun swiftc ../Shared/DiskSpaceSummary.swift ./DiskSpaceSummaryTests.swift -o "$test_binary_dir/DiskSpaceSummaryTests"
"$test_binary_dir/DiskSpaceSummaryTests"
```

构建成功和菜单对象断言不能替代 Finder 的真实安装、沙盒及右键显示验收。

`DiskCleanupTransportTests.swift` 与 `../Shared/DiskCleanup*.swift`、宿主 `AppDelegate.swift`、`DiskCleanupTerminalLauncher.swift` 一同编译，验证严格 UUID 请求／重复事件去重、特殊字符引用、私有脚本快照、原 App 资源移走后仍独立执行、子进程退出码及载体回收；Terminal 请求核对单次创建、先提交命令再激活、不占用已有窗口及特殊路径的 AppleScript 编译。只执行测试生成的 `fixture-only; exit 7` 脚本，不打开真实 Terminal 或运行清理资源。

旧六类清理的隔离验证见 [DiskCleanupTests](./DiskCleanupTests.rb)，只处理临时 HOME 与命令替身。Xcode 先行阶段另按对应阶段回归验证；不把原六类通过等同六组选择已实机验收。
