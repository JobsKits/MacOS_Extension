# Jobs iOS 辅助工具脚本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [一、职责与入口](#jobs-toc-heading-1)
- [二、使用与日志](#jobs-toc-heading-2)

</details>
<!-- jobs-toc:end -->

---

本目录只服务本独立扩展，不依赖其它 Finder 功能包。

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">一、职责与入口</span><!-- jobs-toc:heading-end -->

| 入口 | 用途 | 执行时机与影响 |
| --- | --- | --- |
| `EnableFinderExtension.zsh` | 构建后启用固定 Finder 扩展 | Xcode 的宿主 Build Phase 调用，注册本 App 内扩展并请求刷新 Finder；安装器或隔离构建设置 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 跳过注册。缺少有效构建上下文停止。 |
| `Tools/DispatchIOSTools.zsh` | 目录校验及固定动作分发 | Terminal 私有载体调用；普通运行保留原业务交互，`--plan` 只读检查不执行实际业务。 |
| `Tools/SourceManifest.json` | 来源和打包校验清单 | 维护时核对原始脚本与路径适配副本 SHA-256；不在运行时读取原仓库。 |

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">二、使用与日志</span><!-- jobs-toc:heading-end -->

完整能力、安装 / 卸载参数、产物和风险见[上级 README](../README.md)。随包脚本及逐项适配见[Tools 说明](./Tools/README.md)。构建阶段日志位于系统临时目录的 `JobsIOSToolsBuildPhase.log`；业务日志继续使用原脚本约定。
