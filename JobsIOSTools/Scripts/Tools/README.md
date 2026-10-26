# iOS 随包工具与来源

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [一、分发与适用目录](#jobs-toc-heading-1)
- [二、路径适配](#jobs-toc-heading-2)
- [三、载体和依赖](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

这里保存 JobsCommand@iOS 中用户明确指定的业务脚本副本、完整构建产物清理核心及 `DispatchIOSTools.zsh`。`SourceManifest.json` 逐项列出脚本功能 ID、规范源相对路径、原始 SHA-256 与副本 SHA-256；原脚本未被迁移或删除。具体功能与副作用见[功能总览](../../README.md#前言)与[菜单范围](../../README.md#project-scope)。

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">一、分发与适用目录</span><!-- jobs-toc:heading-end -->

`DispatchIOSTools.zsh` 只接受一个固定动作和一个绝对路径目录，重新检查同层 iOS 工程标记；本地 Pod 编译检查额外要求同层 `*.podspec`，产物清理另要求识别为 iOS/Xcode 工程。`--plan` 只显示动作、目标与脚本映射，不运行业务，不写项目或用户配置。实际运行必须拥有交互终端，直接调用原业务副本，不用管道自动输入确认。

旧 `ios-clean-cache` 请求归一为 `ios-clean-build-artifacts`，使用同一份白名单清理核心与 `CLEAN` 确认，不再随包携带删除 Pods、锁文件及全局 DerivedData 的缓存脚本。

`Pod Install` 不经过此分发器。Swift launcher 在项目门禁通过后，直接向 Terminal 的交互 Shell 发送 `cd -- <安全引用的项目路径> && pod install`；没有中间载体或输出管道，保留 Podfile 原生 TTY 提示与输入。该项不对应一份随包双击脚本。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">二、路径适配</span><!-- jobs-toc:heading-end -->

副本的 Finder 适配范围：

- 禁用沙盒、Pod Update、本地仓库更新以 `JOBS_IOS_PROJECT_DIR` 取代脚本所在目录作为目标。
- Pod 相关文件提取、依赖报告直接采用 Finder 的目标目录，保留后续自述、环境检查和输出交互。
- 本地 Pod 检查直接采用当前目录的 podspec；多个时选择一个，用父目录扫描兄弟依赖。Finder 入口跳过其它仓库 `x.command` 等待文案修补。
- 安装 CocoaPods、切换 Specs 源保留原全局环境流程；目标工作目录由分发器设置。
- JobsCodeSnippets 使用 `--finder <项目路径>`，项目只决定菜单资格；实际安装 / 升级固定处理当前用户 Xcode `UserData/CodeSnippets`。完整脚本与规范源逐字节同步，失败保留原片段目录，不在所选工程提交或拉取。
- `CleanBuildArtifacts.zsh` 与 Terminal 工程的核心逐字节一致，以 Finder 项目路径为唯一清理根，保留类型复检、归属检查、白名单预览与 `CLEAN` 门禁；Flutter 根由统一 Flutter 子菜单处理。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">三、载体和依赖</span><!-- jobs-toc:heading-end -->

宿主把本目录复制到权限为 `700` 的临时目录，以权限为 `600` 的载体打开 Terminal；目录和动作均为安全引用的数据参数。载体只清理自己的临时资源，业务退出码保留。运行不读取原工作树，分发器也不跳过原脚本的防误触或危险确认。

双击脚本来源为同一 JobsGenesis 根下的 `JobsCommand@iOS`，产物清理核心来源为本仓 `JobsTerminalOpener/Scripts/CleanBuildArtifacts.zsh`；此目录没有独立第三方脚本。业务依赖仍由原流程自检，安装本 Finder 扩展不代表已完成 CocoaPods / Ruby / Graphviz 环境安装。
