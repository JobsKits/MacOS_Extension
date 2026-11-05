# Flutter SDK网络选路隔离回归

执行：`ruby FlutterSdkNetworkRouteTests.rb`。所有curl/Git/SDK均由私有临时夹具替代，不访问真实网络，不安装SDK或修改代理。

覆盖显式空配置保护、真实小Range响应校验、官方离线CFUG回退、私有源与realm、channel身份、陈旧缓存拒绝、任务缓存、健康SDK免网络、真实下载失败换路、取消、上层双栈单轮回退、curl配置指纹及确定本地错误停止。
