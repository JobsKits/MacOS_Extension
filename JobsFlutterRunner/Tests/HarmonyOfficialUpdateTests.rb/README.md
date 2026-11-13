# 鸿蒙官方更新隔离测试

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

使用临时响应与假 HTTP，调用真实系统 JXA 验证官方更新核验；不下载 SDK、读取 Cookie、安装工具或启动设备。

## 一、<span id="run">运行与覆盖</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
ruby ./HarmonyOfficialUpdateTests.rb
```

- 覆盖公开 Release 与同段 Command Line 行关联、排除 Emulator 和 Beta 数字、本机真实版本来源、已达兼容正式版本免下载授权、严格目录与归档正向收据、错误架构／版本／大小／摘要／URL、认证外层失败、HTML／HTTP 失败及取消传播。
- `JOBS_HARMONY_OFFICIAL_TEST_HELPER` 可指定聚合包的同名模块，复用同组测试。测试中的成功服务响应是按官网前端字段构造的夹具，不冒充已取得真实授权目录；真实匿名认证限制单独记录。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
