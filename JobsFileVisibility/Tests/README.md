# JobsFileVisibility 隔离验证

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行](#run)
- [二、验收边界](#boundary)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

只在独占系统临时目录中建立测试文件与文件夹，不注册菜单、不访问用户业务文件、不重启 Finder。测试结束删除本轮夹具；源码、管理映射和实际菜单交互分开验证。

## 一、<span id="run">运行</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本功能根目录执行：

```shell
xcrun swiftc \
  ./Shared/FileVisibilityContext/FileVisibilityContext.swift \
  ./Shared/FileVisibilityRequest/FileVisibilityRequest.swift \
  ./JobsFileVisibility/FileVisibilityService/FileVisibilityService.swift \
  ./Tests/FileVisibilityBehaviorTests.swift/FileVisibilityBehaviorTests.swift \
  -o "${TMPDIR%/}/JobsFileVisibilityBehaviorTests"
"${TMPDIR%/}/JobsFileVisibilityBehaviorTests"
```

测试输出 `FileVisibility: … assertions passed`，断言数以实际执行结果为准。覆盖真实 flags 增减、普通文件／文件夹、其它 flags 和正文／权限保全、只读0400成功、000安全失败、不递归、幂等、点文件不改名、符号链接／FIFO／根目录拒绝、128项与32 KiB请求边界、特殊路径往返、重复路径、未知字段／fragment拒绝、目标替换及消失。

## 二、<span id="boundary">验收边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

Swift 编译器、属性操作与工程构建均使用当前 MacOS SDK。隔离通过不代表 Finder 实际菜单、系统授权或其它文件系统已验收；APFS之外文件系统须服从其属性支持与权限结果。源码和构建产物说明见[功能 README](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
