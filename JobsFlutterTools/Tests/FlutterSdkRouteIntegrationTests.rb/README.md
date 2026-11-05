# Flutter SDK选路调用回归

执行 `ruby FlutterSdkRouteIntegrationTests.rb`。加载独立与聚合脚本函数后以替身拦截SDK、网络和设备工具，不触发实际下载、构建或系统注册。

验证下载前上下文顺序、真实SDK根传参、取消130阻断选择器、平台资源独立获取及共享Dart双端桥接副本一致。
