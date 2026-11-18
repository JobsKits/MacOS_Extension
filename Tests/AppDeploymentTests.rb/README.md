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

覆盖默认构建模式、完整复制与提交、`Jobs自定义右键菜单.app` 联合容器、所选旧顶层宿主收拢及失败恢复、末项卸载、删除来源后实际执行部署宿主、旧 App 及原启用登记恢复、复制 / 签名 / 发布失败、未知同名 App 与符号链接拒绝、精确位置筛选、其它位置启用判定、单活切换，以及并发替换时保留备份。签名必须先于登记，提交不重签；模拟 App 管理策略拒绝核对退出码 `77`、机器标记和负责应用，普通签名错误仍保留原码；注销已无记录可幂等返回，查询失败或精确登记仍在不可假成功。可选清理实际删除临时 DerivedData，再执行部署宿主读取包内资源；独立清理覆盖无安装凭据的新 worker、空目录不操作、已安装模块的无效签名 / 登记拒绝，以及已卸载模块的残留清理与来源使用保护。默认保留来源，旧登记、进程、父链接、错误根或未提交的自动清理均拒绝，兄弟目录保留。每例创建独立临时目录，结束自动移除。

资源定位还覆盖 `LC_ALL=C`、`NO_UNSET`、移到含中文、空格及 `%` 的新路径后加载部署库，以及真实联合管理资源的准备；核对源路径不被转义、图标按准确源位置复制，并保持调用者的语言环境。

宿主注销还覆盖系统 `-10814` 且精确登记已缺失、另一位置与同前缀记录保留、重复卸载、查询失败／空响应／截断格式、仍登记、权限与其它错误不得忽略、中文空格及字面十六进制后缀路径，以及删除失败／删除命令假成功的结果复核。所有注销和登记查询由夹具承接，不使用真实用户登记。

实际删除的精确路径权限拒绝验证 `77` 阻断事件、负责面板及保留文件；其它路径权限信息与普通错误保留原退出码，不误报 App 管理阻断。

安装后登记核验使用替身时钟和独立临时 App，覆盖早期 `+` 后登记丢失、定向恢复后重新累计稳定时间、多个安装单元共享同一观察窗口、单个 ID 恢复次数及整轮总时限。恢复后的五秒发现等待期只观察，不立即消耗下一次恢复机会；长观察每十秒给出进度。查询失败不当成缺失后改写登记；恢复失败、查询／恢复／等待中的取消码 `129/130/143`、同 ID 的另一启用位置及目标 inode 并发替换均停止后续动作。恢复前每次系统写入都复核原节点，测试中的四个登记动作只写临时调用记录，不调用系统服务。事务旧 `previous.app` 必须在删除前按准确路径撤销登记；失败或取消保留旧副本与锁，允许原文件回滚，不能注销当前目标或其它 ID。

慢恢复跨过绝对时限后，不再执行剩余登记步骤或后续 ID 的写入；长暂停越过总时限也不能以仍显示启用为由成功。旧事务撤销使用真实生产注销函数，额外验证扩展移除及失败复核中的 `130` 原码传递，取消后不查询或注销后续宿主，也不删除 `previous.app`。

在本目录执行：

```shell
ruby './AppDeploymentTests.rb'
```

只核对登记稳定与事务旧节点，或用相同夹具核对磁盘独立包的部署副本：

```shell
ruby './AppDeploymentTests.rb' --name '/registration_postcheck|registration_repair|previous_transaction|exact_previous_transaction/'
JOBS_APP_DEPLOYMENT_TEST_LIBRARY='../../JobsDiskSpaceInfo/Scripts/【MacOS】AppDeployment.zsh/【MacOS】AppDeployment.zsh' \
  ruby './AppDeploymentTests.rb' --name '/registration_postcheck|registration_repair|previous_transaction|exact_previous_transaction/'
```

依赖 [**macOS**](https://www.apple.com/macos/) 自带 `zsh`、`PlistBuddy` 和 `ditto`；测试替换所有系统登记函数。签名验证通常使用替身，专门一例只在临时容器、宿主及扩展中实际签名，验证外层签名不改变子扩展权限；不调用真实登记、不写 `/Applications`、不构建、不结束进程或重启 Finder。通过结果仅证明隔离部署逻辑，真实安装另行验收。

<!-- jobs-language-terminal-style-v1 -->

**终端配色保护：** `AppDeploymentTests.rb` 直接运行时，在可可靠保存与恢复配色的交互终端中临时使用黑底白字和统一强调色；正常退出、失败及可捕获中断后恢复进入前的配色，保留原业务清理和退出状态。导入本文件不接管终端；无法可靠保护、纯文本模式或无交互终端时按纯文本约定降级。运行中另行修改的颜色会保留并报告冲突，强制终止后可按运行提示使用独立恢复入口。 此实现保留原解释器选项和预载状态；无可用 fork、Windows 或预载多线程时不重启脚本，以纯文本继续。


新增联合App菜单清单用例：四模块按固定优先级选择输出者，卸载后重选、旧协议排除及清单移除；错误宿主身份和符号链接保持原文件。签名替身核对清单先于签名；不写系统登记或用户真实应用目录。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
