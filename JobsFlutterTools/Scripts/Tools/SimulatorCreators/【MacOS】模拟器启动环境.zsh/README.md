# <span id="前言">已有模拟器启动环境</span>

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="intro">前言</span>

运行器的“启动虚拟设备”提供 **iOS / Android / 鸿蒙** 三个平台。选平台后，先检查宿主启动环境、获取缺失组件、更新可核验的兼容正式启动工具并复检，再列出、启动已有实例。该层不新建设备，不生成工程 `ohos/`、切换工程 Flutter SDK 或处理第三方插件；设备就绪后才进入原工程运行门禁。

例如：运行器 → 启动虚拟设备 → Android → 自动准备 / 正式更新检查 → 选择原有 AVD → 等待精确 serial → 原工程运行门禁 → `flutter run`。不存在 AVD 时提示空清单并返回，不隐式新建。

## 一、<span id="platforms">平台能力与边界</span>

| 平台 | 本层处理 | 保留与阻塞 |
| --- | --- | --- |
| iOS | 本轮 `DEVELOPER_DIR` 或已装完整 Xcode；多个候选用键盘选择。缺完整安装只打开一次 [Apple 官方入口](https://developer.apple.com/xcode/)，可取消地等待本人账号 / 安装器 / 管理员流程，安装完成自动续行。执行 `-runFirstLaunch -checkForNewerComponents`；缺可用 iOS Runtime 时由 `-downloadPlatform iOS` 补齐并复检。 | 不全局 `xcode-select`，不替换完整 Xcode，不删除现有 Runtime / UUID。许可与权限不满足时明确未就绪，不以已打开安装器当作完成。组件行为见 [Apple 文档](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)。 |
| Android | 复用 Jobs 创建器的 Java、SDK、传统 CLI 兼容基线准备；官方 `sdkmanager --list --channel=0` 查询，只安装 `emulator` / `platform-tools` 正式更新，更新后重查及执行健康探测。 | 不使用全量 `--update`，不跟随可能成为联网启动器的 `cmdline-tools;latest`，不修改项目 API、NDK、构建工具或既有镜像。官方许可由本人阅读选择。 |
| 鸿蒙 | 从 [Huawei 官方说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-command-line/)的 `-list -details` 枚举已有实例，`-start` 启动原实例；更新来源与授权核验见随包官方更新模块。工具缺失 / 更新只侧装，不删除原目录。 | 官方更新目录、认证、下载授权、摘要或版本无法验证时停止本层，不以固定旧版本冒充更新完成，不绕过账号 / 协议。实例系统版本、数据与镜像不自动替换。 |

环境准备本身沿既有 SDK 获取的持续重试策略处理网络失败；确定的认证、许可、参数、权限错误或用户取消正常停止。Android 更新检查必须收到完整的已安装、可用组件表，以及存在更新时对应的更新记录；仅表标题、缺列、缺所需正式版本或获取警告都不能视为“无更新”。结构无法核验时以67停止，不进入网络重试；只有获取本身的网络失败沿原策略重试。查询、配置摘要与实例等待均有界。启动 / 构建不会因为网络重试被整体重复执行。

## 二、<span id="identity">选择与精确身份</span>

- 交互终端使用验证过的 `fzf`，`↑/↓` 移动，回车确认，子层 `←` 返回真正上一层；搜索不是必需。取消、无匹配、选择器错误不会成为设备 ID。
- `JOBS_FLUTTER_RUNNER_FZF=0` 或非 TTY 的显式文本路径使用编号；子层输入 `b` 返回，空输入取消。交互终端缺失 / 损坏的 `fzf` 明确停止，不静默改成编号菜单。
- 环境准备完成后返回会保留本轮已准备工具，不回滚；同一子流程重新进入平台列表复用已通过的准备，不重复获取工具。
- iOS 等待所选 UDID；Android 除 AVD 名，还检查 `.ini` 的实际路径、配置文件身份及稳定字段摘要，启动 / 等待期间替换同名实例即停止。目录按 `ANDROID_AVD_HOME` → `ANDROID_EMULATOR_HOME/avd` → `ANDROID_USER_HOME/avd` → `HOME/.android/avd` 解析；Flutter 识别完成后再次确认原实例身份、原 ADB serial 与交接 ID，变更即清空 ID 并停止。
- 鸿蒙键包含官方名称、实例路径、类型、系统版本、可用 UUID、配置文件身份和摘要；启动前完整摘要复核，启动后允许端口等动态字段更新，只接受原实例、同实例 SDK 的 HDC 与官方端口。项目准备后再次复核，不能换成另一部手机或同名重建的实例。

## 三、<span id="resources">资源与验证</span>

[主模块](./【MacOS】模拟器启动环境.zsh)由运行器 `source`，不会自行执行业务。`Resources` 内是从 Jobs Android / Harmony 创建器受控提取的函数库，移除其终端接管与 `main` 执行；在子 Shell 中调用准备函数，避免覆盖父运行器路径、日志或 `trap`。该目录随 `SimulatorCreators` 整包运输，可复制、改名，并从工程外工作目录调用。

`MacOS@Extension/JobsFlutterRunner/Tests/SimulatorStartEnvironmentTests.rb` 同名目录中的隔离测试使用临时 SDK、假安装 / 更新 / 启动命令与真实 JXA 配置解析，覆盖成功、更新失败、许可取消、iOS 安装等待续行和实例替换。真实 `fzf` / PTY 测试覆盖方向键、逐层返回、无匹配返回和取消。测试不安装 SDK、不启动真实模拟器、不修改业务工程；真实系统运行与业务构建另行验收。

<a id="🔚" href="#前言">返回顶部</a>
