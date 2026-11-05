# Android SDK修复清单重试回归

运行 `ruby AndroidRepairCatalogRetryTests.rb`。执行真实修复脚本的catalog调用行与共享重试/响应校验，仅用替身代替sdkmanager有界执行，不联网、不安装组件或修改项目。覆盖退出0但明确下载失败的重试、失败stdout隔离、130中断阻断后续业务。
