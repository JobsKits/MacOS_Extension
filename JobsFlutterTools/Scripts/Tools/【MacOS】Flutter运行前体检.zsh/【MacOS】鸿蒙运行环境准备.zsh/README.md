# 鸿蒙运行环境准备

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

供 [**Flutter**](https://flutter.dev/) 运行器在同一终端承接鸿蒙设备选择。`source` 同名脚本后调用 `jobs_flutter_prepare_harmony_for_run <设备诊断键>`；模块准备环境并返回原诊断键，不启动 App，不要求改到其它菜单。

## 一、<span id="workflow">准备流程</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 在系统临时目录 `JobsHarmonyRun.*` 备份当前工程配置；SDK 管理器对项目绑定另有影子工程与失败恢复，不切换全局 SDK。
- 当前 SDK 缺少 HAP 能力或不满足工程版本约束时，直接调用随包管理器的 `--prepare-for-run`，从可信版本清单选最新正式适配标签并固定提交。绑定前以候选 SDK 自身的 YAML／semver 库验证 `pubspec.yaml` 的 Dart 与 Flutter 约束；正式版不能满足时保留原绑定，不自动选择预览版。现有 HAP SDK 也会通过只读 `--verify-sdk` 核验：本地版本缓存须匹配 SDK Git 提交及实际 Dart VM，信息无法解析时明确停止，不猜测版本。核验不查询远程标签；独立 SDK 管理菜单仍保留其原确认流程。
- 完全没有 `ohos/` 时，在私有暂存工程执行 `flutter create --platforms ohos --no-pub`，仅原子发布全新的 `ohos/`。保留既有 `lib/`、Pub 配置、README、元数据和其它平台；已有残缺平台或并发出现目标目录时停止，不重新生成覆盖。新模板的包标识、签名和业务原生配置仍须符合真实项目要求。
- 复用现有 DevEco／CLT；缺少时使用随包创建器的 `--tools-only` 获取固定大小与 SHA-256 的 CLT。下载来源和目标会显示，网络失败由既有重试逻辑处理；官方许可原文必须本人阅读同意。只准备工具，不下载模拟器系统镜像、不创建或启动设备。
- 激活本轮工具环境，复用运行时与编译器均为 17 的 JDK；缺少时从当前 [**Homebrew**](https://brew.sh/) 获取 `openjdk@17` 并复检，只设置本轮 Java，不创建全局链接。在真实工程执行 `pub get`，复核原生插件的鸿蒙声明，再执行 OHPM 安装与项目 Hvigor 同步。公司／供应商插件缺少实现时停止并保留源码，不用空实现或禁用能力冒充可运行。
- 返回后由原运行器复检 SDK、工具链及设备 USB 授权，刷新设备列表并继续同一设备的运行。

## 二、<span id="integration">调用与边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 父运行器提供 `PROJECT_PATH`、`FLUTTER_BIN`、`LOG_FILE`、`log` 与 `run_bounded`。成功更新当前进程的 Flutter 路径、DevEco／SDK／Java 环境和 `PATH`，`REPLY` 返回原设备诊断键；这些进程环境随本轮运行退出结束，不写 Shell 启动文件。
- 非零返回表示本轮未准备完成，父流程必须停止运行；下载、依赖解析与许可取消保留原失败码。已经完成的工具安装、新平台或成功 SDK 切换会保留，原配置备份及日志用于核对，不自动删除共享 SDK／缓存。
- 原始输出写入运行日志旁的 `.harmony-prepare.*` 文件。SDK 获取器与工具获取器还会显示自己的私有日志目录；分享原始日志前检查凭据。
- [随包资源](./Resources/README.md) 保留同仓库管理器、检测器、CLT 获取器及插件核验器快照。整个体检目录复制到另一位置后仍可运行，不依赖开发源码目录。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
