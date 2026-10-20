# JobsFlutterRunner 脚本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行与风险](#runtime)
- [二、验证与故障](#verify)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录负责[独立 Flutter 运行扩展](../README.md)的终端交互、设备选择、后台会话和构建后注册。业务与 JSON 脚本必须放在一起；App Bundle 只打包这两份业务资源。

| 文件 | 入口与职责 |
| --- | --- |
| `RunFlutterProject.zsh` | `/bin/zsh -l` 运行；`--project <根目录>` 验证 Flutter、选择设备、启动或连接 launchd 会话、追踪日志和热重载。无参数时可输入或拖入根目录。 |
| `FlutterRunner.jxa` | macOS `osascript -l JavaScript` 调用；严格项目声明识别、设备 / 模拟器 JSON、launchd plist 和 Flutter machine 控制数据；不执行用户字符串中的 Shell 命令。 |
| `EnableFinderExtension.zsh` | Xcode Build Phase 的扩展注册与 Finder 刷新；`JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 跳过，用于隔离构建及外层安装器接管。 |

## 一、<span id="runtime">运行与风险</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录运行：

```shell
/bin/zsh -l ./RunFlutterProject.zsh \
  --project '/实际 Flutter 项目根目录'
```

先显示用途、影响与日志位置，回车继续、非空输入取消。复用项目 FVM SDK 或 PATH Flutter；未找到时给出提示，不自动安装。终端设备编号按项目平台目录过滤，并允许重新加载。有 `ios/` 才提供 iOS 模拟器入口；没有可用 iOS 模拟器时，使用内置 `xcrun simctl` 逻辑列出设备型号和已安装 iOS runtime，选择后创建并启动；缺 runtime 时提示前往 Xcode Settings → Components（旧版 Platforms）安装，不自动安装 Homebrew、Xcode 或 runtime。

有 `android/` 才提供 Android 模拟器入口，使用 SDK `emulator -list-avds` 列出已配置 AVD，选择后通过独立 launchd job 启动，再返回 Flutter 设备列表。该流程不创建 AVD；空列表时先在 Android Studio Device Manager 配置。模拟器本身的 job 与 Flutter 项目 / 设备会话分开，不因终端关闭而退出。

后台会话以项目 / 设备为独立身份，通过 `launchctl bootstrap gui/<UID>` 管理 `/bin/zsh` 同脚本的私有 `--worker` 入口。启动前将脚本与 helper 保存至会话目录，Worker 的输入连接 FIFO，不继承终端 stdin、EOF 或 HUP。`--worker` 只用于已准备的会话，无独立用户确认。

日志实时显示在终端，也保存到用户资源库 `Application Support/JobsFlutterRunner/sessions/` 的 `run.log`；本次操作日志在系统临时目录，终端打印精确文件位置。`r` 热重载、`R` 热重启、`s` 停止、`d` 离开；关闭 Terminal、Ctrl+C 或 EOF 都只离开查看。重复右键并选择相同设备可重连。注销 / 关机仍会终止当前用户会话，不提供自动重启。

Flutter 可能下载项目依赖、生成构建目录；创建模拟器会增加一个本机设备。停止只处理所选会话，不向无关 Flutter、模拟器或终端进程发信号。日志保留项目路径与目标输出，分享前检查。卸载菜单不清理或停止已有后台会话。

## 二、<span id="verify">验证与故障</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

隔离测试与构建命令见[工程验证说明](../README.md#verify)。脚本语法检查不会启动项目：

```shell
/bin/zsh -n ./RunFlutterProject.zsh
/bin/zsh -n ./EnableFinderExtension.zsh
ruby ../Tests/FlutterRunnerShellTests.rb
ruby ../Tests/FlutterRunnerJSONTests.rb
```

设备发现、模拟器就绪使用有界超时，超时后显示诊断并允许重试；持续运行的 Flutter 不设整体超时。`launchctl` 失败时确认从当前登录桌面的 Terminal 启动。构建日志报签名、依赖或平台工具错误时修复目标环境，不把提交 launchd 成功当作 Flutter 运行成功。真实 launchd 配合假 Flutter 的 HUP 存活、日志增长、重连与停止已通过；Finder 安装、真实设备运行和关闭终端后的真实 Flutter App 生命周期仍需单独验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
