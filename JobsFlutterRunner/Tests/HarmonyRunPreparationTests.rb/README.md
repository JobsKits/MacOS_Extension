# 鸿蒙运行环境准备隔离测试

![Jobs出品，必属精品](https://picsum.photos/1500/400)

```shell
ruby ./HarmonyRunPreparationTests.rb
```

使用临时工程、假 SDK／CLT 获取器和假工具执行准备闭环。覆盖 SDK 切换、暂存生成与原子发布、已有文件保护、跨目录运行、工具取消、Pub 失败、插件缺项及函数加载作用域；不下载真实 SDK、不切换用户工程、不安装或运行 App。真实设备授权、官方许可和业务插件兼容需要在目标环境验收。
