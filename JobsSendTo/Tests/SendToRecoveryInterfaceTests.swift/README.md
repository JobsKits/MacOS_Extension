# SendTo 恢复界面原生控件验证

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行](#jobs-toc-heading-2)
- [二、覆盖与边界](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

使用真实 [**AppKit**](https://developer.apple.com/documentation/appkit) 表格、按钮、selector 和事件循环验证恢复界面。仅在独立测试编译单元替换复制／任务存储边界，不读写真实任务账本、不挂载设备、不向用户文件或外盘写入。该测试不替代[真实进程崩溃恢复验证](../SendToResumeCrashTests.swift/README.md)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

从 JobsSendTo 根目录运行以下构建夹具。生产恢复控制器与测试 extension 组成同一个临时编译单元，生产文件不被改写。语言偏好的 suite 只在临时源码副本改成独占测试域；正常结束清理该域，不修改用户实际偏好。

```ruby
require 'fileutils'
require 'tmpdir'
require 'securerandom'
root = Dir.pwd
temporary = Dir.mktmpdir('JobsSendToRecoveryUI-')
domain = 'com.jobs.sendto.ui-fixture.' + SecureRandom.uuid
files = %w[
  JobsSendTo/AppDelegate.swift
  JobsSendTo/SendToAppMenu.swift
  JobsSendTo/SendToCancellation.swift
  JobsSendTo/SendToWindowController/SendToWindowController.swift
  JobsSendTo/SendToWindowController/SendToWindowFactories.swift
  JobsSendTo/SendToRecovery/SendToRecoveryWindowController.swift
  Tests/SendToRecoveryInterfaceTests.swift/SendToRecoveryInterfaceTests.swift
]
unit = File.join(temporary, 'Interface.swift')
File.write(unit, files.map { |file| File.read(File.join(root, file)) }.join("\n"))
localization = File.read(File.join(root, 'Shared/SendToLocalization/SendToLocalization.swift'))
localization.sub!('com.jobs.finderextensions.managementpanel.preferences', domain)
localization_file = File.join(temporary, 'Localization.swift')
File.write(localization_file, localization)
models = %w[SendToIdentity SendToVolume SendToSource SendToTaskSummary SendToResult SendToFailure SendToProgress SendToPersistentModels SendToFilesystem SendToPersistentIO SendToCoreError]
  .map { |name| File.join(root, 'Shared/SendToCore', name + '.swift') }
shared = %w[Shared/SendToFactories/SendToFactories.swift Shared/SendToRequest/SendToRequest.swift]
  .map { |file| File.join(root, file) }
shared += Dir[File.join(root, 'JobsSendTo/SendToReconnect/*.swift')]
binary = File.join(temporary, 'RecoveryUITests')
raise 'compile failed' unless system('xcrun', 'swiftc', '-parse-as-library',
  unit, localization_file, *models, *shared, '-o', binary)
raise 'native controls failed' unless system(binary, domain)
puts temporary
```

依赖系统 Swift 编译器和当前 MacOS SDK。临时编译目录保留供核对；App 使用 prohibited 激活策略，不作为真实界面截图或最终产品启动证明。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、覆盖与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 冷启动从任务 API 读取记录，默认空选、不自动恢复或新建复制；无选择、运行中任务均不能直接触发继续或放弃。
- 按稳定 UUID 选择任务；语言切换保留所选任务及按钮状态；阻塞任务保留诊断，读取失败不伪装成空任务，重读成功可清除之前的读取错误。
- 继续原任务以及暂停后的再次继续均调用原 taskID 的 resume，不转调新 copy；进度窗口关闭先请求暂停，后台完成后才关闭。
- 放弃对话框首个／默认按钮为取消，第二个按钮明确为危险动作；取消不调用 discard，确认仅发送所选任务 ID，移除任务后不自动选择下一项。
- 点设备先显示目标窗口，不自动向卷根复制；原生文件夹选择器只选目录，完整路径可滚动与复制，十语言和三主题切换保留选择，实际 copy 接收子目录。
- 未挂载设备时也按完整源集合提示原任务及完整目的地，默认取消、多条需显式选择；源变化禁继续，从头必须先解析当前原目标并安全 discard，失败不创建新复制。
- 后台重连就绪只恢复原任务 ID；离线选择从头则保留该意图，重连后严格按“解析目标 → 安全 discard → 新 copy”执行，取消／权限失败不清理旧数据，也不误走旧任务 resume。手动连接的异步 proof 迟到时，已取消操作不打开系统窗口。

测试中的存储／复制函数是内存替身，证明界面绑定和异步生命周期；实际块持久性、文件归属、跨进程锁和故障恢复由 Core 与独立进程测试验证。App 的完整布局、真实退出和目标系统绘制仍需独立验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
