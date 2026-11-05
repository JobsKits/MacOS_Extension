# SDK 下载上下文隔离回归

运行 `ruby ./SdkDownloadContextTests.rb`。使用临时 SDK、项目声明和元数据验证：下载前版本及来源、SDK 根路径、宿主架构、目标平台与 Engine、Dart 缺失时明确未知、过期缓存与 `.old` 不冒充目标、匹配 Engine 后才采信 Dart 缓存，以及显式 Engine 覆盖与 Git 身份优先级。

Flutter 入口设置为会留下标记的假工具，测试确认其从未执行；不启动 Flutter / Dart、不下载 SDK、不修改正在运行的终端会话。两份运行器和数据助手分别覆盖。
