# 模拟器启动环境隔离测试

从 MacOS@Extension 目录运行：

```shell
ruby JobsFlutterRunner/Tests/SimulatorStartEnvironmentTests.rb/SimulatorStartEnvironmentTests.rb
ruby JobsFlutterRunner/Tests/FlutterRunnerAndroidTests.rb
ruby JobsFlutterRunner/Tests/FlutterRunnerShellTests.rb
```

使用 Ruby、已有系统 osascript / AppKit Foundation 和 shasum。临时目录包含假 SDK、组件清单与实例配置；所有安装、更新、下载、Xcode 初始化、官方页面打开、HDC 与启动命令都被夹具替代。`run_bounded` 的宿主命令防护仅允许实际 JXA 解析临时文件，其它意外宿主命令返回99。

覆盖完整与畸形官方清单、正式启动组件筛选、更新失败不放行、无更新幂等、Xcode 组件更新、官方安装页只开一次 / 等待后续行 / 取消、AVD 和鸿蒙同名替换、端口动态变化及精确目标等待。Android 清单夹具使用实际 Installed / Available / Updates 的列格式，拒绝仅标题、缺列、缺目标正式版本及缺更新行；父准备组合使用真实重试函数，验证网络获取可重试、确定的格式错误只查一次并以67结束，且不安装、不发布就绪环境。身份目录验证 `ANDROID_AVD_HOME` → `ANDROID_EMULATOR_HOME/avd` → `ANDROID_USER_HOME/avd` → `HOME/.android/avd`；Flutter 长等待结束后再核原 AVD、原 serial 和返回 ID，替换、断连、错误 ID 与返回 / 取消均清空交接 ID。Shell suite 的真实 fzf / PTY 回归验证上下键、逐层左返回、搜索无匹配后返回、取消和错误传播；非 TTY 文本路径验证 `b` 返回。

不执行真实 SDK 安装、模拟器启动、业务工程修改或 Flutter 构建。资源包说明见[已有模拟器启动环境](../../Scripts/SimulatorCreators/【MacOS】模拟器启动环境.zsh/README.md)。
