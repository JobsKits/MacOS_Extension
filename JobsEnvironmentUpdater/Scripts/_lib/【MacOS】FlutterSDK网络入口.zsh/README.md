# <span id="前言">Flutter SDK网络入口</span>

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

此私有库供Flutter命令、安装和升级入口source；加载时只定义函数。SDK实际调用才创建任务缓存，以子进程探测原始来源和候选路线，SDK获取失败持续重试，Ctrl+C或终止信号取消。健康缓存直接复用，run/pub/analyze/build只执行一次。

`jobs_flutter_sdk_command 原命令 参数...`保留参数、stdin与退出码；`jobs_flutter_sdk_versions`只读取明确配置的制品源发布清单。Brew Flutter cask从brew真实JSON元数据读取原URL，URL和SHA由Brew校验，不替换下载主机。不source用户配置，不写全局代理或Flutter源。菜单工程将本目录与同级 FlutterSDK命令适配、FlutterSDK网络选路、SDK获取重试模块一起打包到 App 的 `Resources/Scripts/_lib/`；宿主运行前复制完整私有快照，不依赖原终端环境仓。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
