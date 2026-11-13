# Android SDK修复清单重试回归

运行 `ruby AndroidRepairCatalogRetryTests.rb`。执行真实修复脚本的catalog调用行与共享重试/响应校验，仅用替身代替sdkmanager有界执行，不联网、不安装组件或修改项目。覆盖退出0但明确下载失败的重试、失败stdout隔离、130中断阻断后续业务。

<!-- jobs-language-terminal-style-v1 -->

**终端配色保护：** `AndroidRepairCatalogRetryTests.rb` 直接运行时，在可可靠保存与恢复配色的交互终端中临时使用黑底白字和统一强调色；正常退出、失败及可捕获中断后恢复进入前的配色，保留原业务清理和退出状态。导入本文件不接管终端；无法可靠保护、纯文本模式或无交互终端时按纯文本约定降级。运行中另行修改的颜色会保留并报告冲突，强制终止后可按运行提示使用独立恢复入口。 此实现保留原解释器选项和预载状态；无可用 fork、Windows 或预载多线程时不重启脚本，以纯文本继续。
