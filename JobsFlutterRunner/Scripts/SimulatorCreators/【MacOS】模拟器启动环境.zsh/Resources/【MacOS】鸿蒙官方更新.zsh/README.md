# 鸿蒙官方 CLT 更新核验

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

内部模块供模拟器启动环境加载，在下载旧版工具之前核验 [**HarmonyOS**](https://developer.huawei.com/consumer/cn/) 官方兼容正式版本。只查询版本和归档元数据，不下载 SDK 归档、不安装工具、不读取浏览器 Cookie，不修改工程或全局配置。

## 一、<span id="api">调用与结果</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
jobs_sim_harmony_official_update "$current_clt_version" "$empty_receipt" "$actual_clt_version_file"
```

- 调用方提供 `LOG_FILE`、`log` 和 `run_bounded`。收据须为本轮预建的绝对路径空普通文件；当前版本仅取真实 CLT 根目录的 `version.txt`，文件内容必须与所报版本一致。不能用 Emulator、DevEco Studio 或 SDK 版本代替；无法核验时传空当前版本，不谎报最新。
- 先读取[官方公开兼容版本说明](https://developer.huawei.com/consumer/en/doc/doccenter-release-notes/deveco-studio-new-features-611/)，通过官网实际使用的 `getCenterDocument` 公开正文接口，逐段核对 Release 标题及同段唯一 `Command Line` 版本行。只针对已声明兼容的 6.1 正式分支，不从 Emulator、Beta 或其它表格取最大数字，不硬编码当前最新构建号。
- 本机已达该公开兼容 Release 或更新时，输出 `state: ready` 的 JSON 收据，继续由调用方检查工具实际能力；不会为了查询下载链接而阻止已就绪工具。
- 缺失或落后时请求[官方 CLT 下载目录](https://developer.huawei.com/consumer/cn/download/command-line-tools-for-hmos)的真实 `getToolVersionList` 服务，核对本机 macOS 架构、正式版本、唯一包名、大小及 SHA-256，再请求 `getToolVersionDownloadUrl`。下载目录不得落后于公开说明；不降级到固定旧版本。
- 可获取更新时收据为 `schemaVersion: 1`、`state: update`，附 `version`、`packageName`、`size`、`sha256`、`url` 及服务标识。只允许可核验华为 HTTPS 来源和匹配文件名。调用方侧装后仍须重新核对归档大小、SHA-256、实际 `version.txt` 和工具能力；收据不表示已安装成功。
- 返回 `67` 表示认证、HTTP、JSON、来源或版本完整性未就绪，收据保持空，停止工具下载及后续运行。`130`、`143` 原样传播。所有解析仅处理数据，不使用 Shell `eval`。

## 二、<span id="authentication">认证与日志</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 公开正文可匿名读取；下载目录或归档可能要求华为账号、实名及本人协议确认。当前匿名调用返回 `90910011` 时，明确报告缺少官方认证，不把它当作无更新、网络瞬断或可无限自动重试的下载错误。
- 仅在浏览器登录不会给本模块匿名请求添加 CSRF，原样重试不保证成功；模块不读取用户浏览器凭据、不自动签署协议。需要获取新归档但未取得完整官方元数据时，本轮保持未就绪。
- 每次 HTTP 最多 30 秒，外层等待最多 40 秒；解析最多 20 秒。DNS／连接失败、断流、超时、HTTP 408／425／429／5xx 仅重试元数据请求，以 1 秒起、最多 30 秒的可取消退避持续获取；不重放归档安装、创建或启动。401／403、证书与其它配置错误、普通 HTML 登录页、缺字段、认证返回及半成品元数据立即停止。
- 原始正文、目录、下载响应、请求及 HTTP 状态保存在 `$LOG_FILE.harmony-official.*`，不清空失败证据。隔离测试位于 `MacOS@Extension/JobsFlutterRunner/Tests/HarmonyOfficialUpdateTests.rb/`；从该测试目录执行 `ruby ./HarmonyOfficialUpdateTests.rb`。测试使用假 HTTP 和实际系统 JXA，覆盖健康现有版本、更新正向路径、网络恢复与取消、授权阻塞、版本与架构错误、来源及摘要检查；不下载或安装真实 SDK。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
