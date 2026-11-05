# App 部署隔离测试

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、覆盖与运行](#coverage)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

> [AppDeploymentTests.rb](./AppDeploymentTests.rb)验证[部署函数库](../../Scripts/【MacOS】AppDeployment.zsh/README.md)，只操作临时 App 夹具。使用 [**Ruby**](https://www.ruby-lang.org/) 自带 `Minitest`，不安装依赖。

## 一、<span id="coverage">覆盖与运行</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

覆盖默认构建模式、完整复制与提交、`Jobs自定义右键菜单.app` 联合容器、所选旧顶层宿主收拢及失败恢复、末项卸载、删除来源后实际执行部署宿主、旧 App 及原启用登记恢复、复制 / 签名 / 发布失败、未知同名 App 与符号链接拒绝、精确位置筛选、其它位置启用判定、单活切换，以及并发替换时保留备份。签名必须先于登记，提交不重签；模拟 App 管理策略拒绝核对退出码 `77`、机器标记和负责应用，普通签名错误仍保留原码；注销已无记录可幂等返回，查询失败或精确登记仍在不可假成功。可选清理实际删除临时 DerivedData，再执行部署宿主读取包内资源；独立清理覆盖无安装凭据的新 worker、空目录不操作和无效签名 / 登记拒绝。默认保留来源，旧登记、进程、父链接、错误根或未提交的自动清理均拒绝，兄弟目录保留。每例创建独立临时目录，结束自动移除。

在本目录执行：

```shell
ruby './AppDeploymentTests.rb'
```

依赖 [**macOS**](https://www.apple.com/macos/) 自带 `zsh`、`PlistBuddy` 和 `ditto`；测试替换所有系统登记函数。签名验证通常使用替身，专门一例只在临时容器、宿主及扩展中实际签名，验证外层签名不改变子扩展权限；不调用真实登记、不写 `/Applications`、不构建、不结束进程或重启 Finder。通过结果仅证明隔离部署逻辑，真实安装另行验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
