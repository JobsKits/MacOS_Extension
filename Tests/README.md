# 回归测试入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、脚本导航](#jobs-toc-heading-2)
- [二、联合 App 背景菜单顺序验证](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

每项测试保存在完整同名脚本包内；进入对应说明检查依赖和实际影响后运行。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、脚本导航 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- [ManagementGUIBackendTests.rb](./ManagementGUIBackendTests.rb/README.md)
- [PortableLauncherTests.rb](./PortableLauncherTests.rb/README.md)
- [HiddenFilesInstallerIntegrationTests.rb](./HiddenFilesInstallerIntegrationTests.rb/README.md)
- [RunRevocationInstallerIntegrationTests.rb](./RunRevocationInstallerIntegrationTests.rb/README.md)
- [IOSToolsInstallerIntegrationTests.rb](./IOSToolsInstallerIntegrationTests.rb/README.md)
- [DesktopFinderMenuTests.rb](./DesktopFinderMenuTests.rb/README.md)
- [FileCreatorInstallerIntegrationTests.rb](./FileCreatorInstallerIntegrationTests.rb/README.md)
- [IOSToolsCodeSnippetsTests.rb](./IOSToolsCodeSnippetsTests.rb/README.md)
- [AndroidSimulatorRepairInstallerIntegrationTests.rb](./AndroidSimulatorRepairInstallerIntegrationTests.rb/README.md)
- [FlutterMaintenanceResourceParityTests.rb](./FlutterMaintenanceResourceParityTests.rb/README.md)
- [FinderManagerPanelTests.rb](./FinderManagerPanelTests.rb/README.md)
- [FinderManagerPreflightTests.rb](./FinderManagerPreflightTests.rb/README.md)
- [AndroidSimulatorInstallerIntegrationTests.rb](./AndroidSimulatorInstallerIntegrationTests.rb/README.md)
- [SidebarBasicMenuTests.rb](./SidebarBasicMenuTests.rb/README.md)
- [TerminalFeaturePanelTests.rb](./TerminalFeaturePanelTests.rb/README.md)
- [HarmonySimulatorInstallerIntegrationTests.rb](./HarmonySimulatorInstallerIntegrationTests.rb/README.md)
- [HarmonySimulatorRepairInstallerIntegrationTests.rb](./HarmonySimulatorRepairInstallerIntegrationTests.rb/README.md)
- [IPAResignInstallerIntegrationTests.rb](./IPAResignInstallerIntegrationTests.rb/README.md)
- [FinderFeatureSelectionTests.rb](./FinderFeatureSelectionTests.rb/README.md)
- [FlutterInstallerIntegrationTests.rb](./FlutterInstallerIntegrationTests.rb/README.md)


## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、联合 App 背景菜单顺序验证</span><!-- jobs-toc:heading-end -->

[OrderedDesktopMenuTests.swift](./OrderedDesktopMenuTests.swift) 编译真实 AppKit 菜单协调器与原请求解析器，覆盖全部十五种安装子集、唯一展示者、过滤、叶开关、复制菜单 tag、精确宿主、失效请求、符号链接及损坏清单。菜单复制后清除 `target`／`representedObject`，由 `NSApplication.sendAction` 将 selector 交给测试 principal，再进入协调器；不直接调用协调器模拟点击。仅使用临时目录和业务运输替身，不注册扩展、不打开宿主、不操作模拟器或真实文件。

在 `MacOS@Extension` 目录运行：

```shell
xcrun swiftc -parse-as-library \
  Tests/OrderedDesktopMenuTests.swift \
  JobsDesktopTools/Shared/OrderedDesktopMenu/*.swift \
  JobsDesktopTools/Shared/DesktopMenuAction/DesktopMenuAction.swift \
  JobsDesktopTools/Shared/DesktopMenuRequest/DesktopMenuRequest.swift \
  JobsFileCreator/Shared/FileCreationContext/FileCreationContext.swift \
  JobsFileCreator/Shared/FileCreationRequest/FileCreationRequest.swift \
  JobsDiskSpaceInfo/Shared/DiskCleanupRequest.swift \
  JobsEnvironmentUpdater/Shared/EnvironmentUpdateRequest.swift \
  -o "${TMPDIR%/}/JobsOrderedMenuTests"
"${TMPDIR%/}/JobsOrderedMenuTests"
```

共享协调器与只读磁盘标题实现随各独立功能包提供；四份协调器及四份磁盘显示源码必须逐字节一致。原各功能菜单测试保留无共享清单的独立路径，不能以其单独通过代替本套联合菜单验证。

[四包真实 principal 回归](./OrderedDesktopPrincipalTests.rb/README.md) 分别编译 JobsFileCreator、JobsDesktopTools、JobsEnvironmentUpdater、JobsDiskSpaceInfo 的完整生产 `FinderSync.swift`，调用真实 `menu(for:)`。同文件测试 extension 只注入临时协调器与宿主运输替身，验证每项菜单的 target 为当前 principal、principal 响应复制项 action，并通过 AppKit selector 分发到精确宿主。磁盘清理 UUID 协议及重复票据一并核验；测试不发送 AppleEvents、不启动 Terminal 或执行清理。

```shell
ruby Tests/OrderedDesktopPrincipalTests.rb/OrderedDesktopPrincipalTests.rb
```

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
