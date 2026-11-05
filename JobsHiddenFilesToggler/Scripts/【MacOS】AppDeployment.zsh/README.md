# Finder 扩展 App 部署函数库

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、模式与能力](#capabilities)
- [二、管理器接口](#interfaces)
- [三、隔离验证](#validation)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

> [【MacOS】AppDeployment.zsh](./【MacOS】AppDeployment.zsh)供已完成操作确认的管理器加载。它使用 [**macOS**](https://www.apple.com/macos/) 自带工具，把完整宿主 App、内嵌 Finder 扩展和资源部署到“Jobs自定义右键菜单”联合 App，并提供失败回滚、精确卸载与可选构建清理；加载文件本身不安装、不登记、不弹窗。

## 一、<span id="capabilities">模式与能力</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 设置 | 默认值 | 行为 |
| --- | --- | --- |
| `JOBS_FINDER_INSTALL_LOCATION` | `build` | `build` 保留管理器的构建目录安装流程；`applications` 部署到 `Jobs自定义右键菜单.app/Contents/Applications/<原宿主名>.app`，再由管理器登记内嵌宿主及扩展。其它值报错。 |
| `JOBS_FINDER_APPLICATIONS_DIR` | `/Applications` | 应用程序目标根。必须已存在、无链接父级且可写；隔离测试可显式传入临时目录。函数库不自动提权。 |

- 复制前核对宿主与扩展 Bundle ID、执行程序及深度签名；复制后再次核验。资源随整个 App 复制，不依赖源码目录运行。
- 更新已有同名 App 时，只有宿主及预期内嵌扩展身份均相符才允许替换；未知 App、链接目标、外部链接资源或危险目标根均拒绝。
- 同盘临时目录保存完整待发布 App 与旧版备份。所有登记及配置保存成功后提交；失败恢复旧文件，并重新登记事务开始前已启用的副本，包含构建目录副本。
- 应用程序根只创建一个 `Jobs自定义右键菜单.app`，显示名为“Jobs自定义右键菜单”，固定身份为 `com.jobs.finderextensions.manager`。内部宿主保留各自 Bundle ID、签名与完整资源；仅最后一个宿主卸载后删除外容器，未知内部项保留。所选功能更新成功时，可核验的旧顶层同名宿主收拢进联合 App；其它功能和未知顶层 App 不动。
- 容器管理资源由相邻 `【MacOS】联合App管理.zsh/【MacOS】联合App管理.zsh` 的 `jobs_prepare_combined_manager_resources` 函数补齐。全容器互斥锁覆盖资源准备、宿主变化与签名；安装先签外层再登记子扩展，提交仅验证既有签名；卸载集合变化后重新签外层。递归验证但不深度重签子宿主，避免改掉子扩展权限。事务备份在应用程序根的隐藏目录，不进入外层签名内容。
- `jobs_deployment_retire_other_copies` 只注销其它位置的启用登记并保留其文件，使切换失败可恢复原位置。卸载只注销精确 App / appex 路径，不使用同 Bundle ID 的全局禁用。
- 并发改动导致目标或事务目录身份发生变化时，停止清理并保留备份；日志指出实际路径。进程异常终止可能留下互斥锁，应先核对事务与备份再处理。

## 二、<span id="interfaces">管理器接口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 函数 | 参数与结果 |
| --- | --- |
| `jobs_deployment_app_path` | `builtApp`：标准输出仅返回所选宿主路径；不要求构建产物存在，适用于源码已删除后的卸载。 |
| `jobs_deployment_container_path` | 标准输出返回固定联合 App 路径；已有同名未知对象报错。 |
| `jobs_deployment_prepare_container` | 创建、验证联合容器并准备同包管理资源；由安装事务在容器互斥锁内调用。 |
| `jobs_deployment_matches_path` | `candidate builtApp`：仅匹配所选宿主或其直接内嵌 appex，不匹配另一安装位置、同前缀副本或更深路径。 |
| `jobs_deployment_selected_exists` | `appPath`：只读判断所选 App 是目录且自身不是链接。完整身份由安装 / 卸载接口校验。 |
| `jobs_deployment_has_other_enabled` | `appPath extID`：`0` 有其它位置启用，`1` 没有，`2` 查询失败；调用者须把查询失败作为错误处理。 |
| `jobs_deployment_install` | `builtApp appID extName extID`：应用程序模式创建部署事务；构建模式仅记录原启用位置，继续现有构建与登记流程，不复制或改动构建文件。 |
| `jobs_deployment_prepare_registration` | 应用程序模式在登记前准备外层签名；同一事务已准备时只验证，不重复写入；构建模式不操作。`install` 和 `retire_other_copies` 均内置此步骤以兼容原单包管理器。 |
| `jobs_deployment_retire_other_copies` | `selectedApp appID extName extID`：注销其它启用副本，保存登记恢复信息；两种模式均可调用。 |
| `jobs_deployment_commit` | 所有登记、启用和配置保存成功后调用，清理备份及锁。 |
| `jobs_deployment_rollback` | 任一步失败或 worker 异常退出时调用，恢复旧文件和原启用位置；恢复失败保留备份并返回非零。 |
| `jobs_deployment_uninstall` | `appPath appID extName extID`：应用程序模式核验、精确注销并删除所选自有 App；构建模式不操作，由原管理器继续卸载。 |
| `jobs_deployment_cleanup_build_products` | `builtApp derivedRoot appID extName extID`：成功提交后，额外核验精确启用位置、完整部署签名、构建来源无残留登记或运行进程，才清除此轮明确的 DerivedData。默认不调用。 |
| `jobs_deployment_cleanup_existing_build_products` | 参数同上：独立清理已安装联合 App 对应的历史构建根，不要求本轮安装凭据；仍强校验 nested 宿主及外层签名、准确启用登记、来源无登记或进程和路径边界；源目录不存在或为空时不操作。 |

`appID` 与 `extID` 必须为调用管理器维护的固定 `com.jobs.*` 身份，`extName` 必须是单个 `.appex` 文件名，不能由任意用户输入推导。诊断与来源 / 目标日志写标准错误，进入管理器已有会话日志；函数库不单独创建日志文件。管理器负责命令行 `--install-location build|applications` 的解析、GUI 勾选、默认空选和按钮确认。

安装编排应在构建后执行 `install → retire_other_copies → prepare_registration → 所选位置登记与启用 → 保存配置 → commit`；任一步失败执行 `rollback`。签名在新扩展登记前完成，`commit` 不再创建签名封套。每个 App 必须先提交或回滚，才能处理下一个 App；事务函数不能放进命令替换或其它子 Shell，否则内存恢复状态不会回到调用者。

精确扩展注销保持幂等：`pluginkit -r` 失败后，只有成功复核该 Bundle ID 已无相同路径记录才视为已移除；查询失败或精确记录仍在时继续报错。签名写入若出现 `Operation not permitted` / `EPERM`，返回专属退出码 `77` 并输出 `JOBS_MANAGER_BLOCKED` / `app-management` 标记，说明应检查当前负责应用的“App 管理”授权；其它签名错误保留原码，不混报权限。负责应用优先从 `JOBS_FINDER_RESPONSIBLE_APP` 取得，否则只读检查父进程链。该分支不自动授权、不弹管理员密码、不以 root 运行整个安装器、不修改系统目录权限或隐私数据库。

总管理器可预建私有 `JobsFinderControl.*` 目录内的 `app-management.blocked`，通过 `JOBS_FINDER_BLOCKED_FILE` 传入。阻断时仅向当前用户所有、目录权限 `700`、普通单链接文件权限 `600` 的既有空文件写 `app-management`；不创建文件、不跟随链接、不接受其它文件名或目录名，打开后复核句柄身份。控制文件无效或未传入时仍保留原退出码及日志标记；管理器可在每个单元结束后检查旗标，避免子脚本丢失退出码后继续安装。

仅用户额外选择构建清理时，在 `commit` 后调用清理接口。它只接受 `work/<原宿主名>DerivedData` 或单包 `work/DerivedData`，且 `builtApp` 必须正好在该根的 `Build/Products/Debug` 或 `Release` 下。全 `work`、源码根、应用程序目录、链接父级和未经本次提交验证的来源一律拒绝。清理先同盘搬移锁定旧目录、再复查登记和进程，避免删除期间新建的同名构建目录；状态变化时保留或恢复来源。清理失败返回非零，应提示“已安装，构建清理失败”并保留安装结果，不回滚联合 App，不宣称清理成功；没有这次额外选择时保留构建产物。

独立清理入口使用 `jobs_deployment_cleanup_existing_build_products`：先验证已装联合 App 和来源状态，再临时复用相同安全删除内核，最后还原调用者原有凭据。它不构建、不安装、不登记、不结束进程、不改已安装 App，也不扩大到兄弟单元；自动安装清理接口仍保留“必须本次成功提交”的限制。

## 三、<span id="validation">隔离验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录执行语法验证：

```shell
zsh -n './【MacOS】AppDeployment.zsh'
```

在 macOS 总仓根目录执行 `ruby './Tests/AppDeploymentTests.rb/AppDeploymentTests.rb'` 运行临时夹具；单功能包只携带运行模块，不要求存在这份仓库级测试。

测试依赖 [**Ruby**](https://www.ruby-lang.org/) 与 macOS 原生 `PlistBuddy`、`ditto`；系统登记全部使用函数替身。签名流程通常隔离替换，专门的签名测试只在临时 Bundle 中实际签名，核对外层签名后内嵌扩展权限保留。清理测试实际删除临时 DerivedData 后执行联合 App 内宿主读取包内资源，兄弟目录保留；不构建工程、不写真实应用程序目录、不结束进程或重启 Finder。临时夹具通过不能代替真实 Finder 菜单或另一台机器验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
