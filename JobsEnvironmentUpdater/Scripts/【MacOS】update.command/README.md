# 桌面菜单 update 独立副本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

本目录携带原 `【MacOS】update.command` 的完整业务源码；由[桌面菜单宿主](../../README.md)在私有快照中启动。运行不转调原仓库。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

从本目录查看原脚本完整自述和参数：

```zsh
/bin/zsh ./【MacOS】update.command --help
```

菜单无参数运行，与终端直接输入 `update` 一样默认低打扰：显示自述后自动按顺序维护，不等待开场回车、逐项确认或收尾重试选择。启动时复用已有管理员授权，必要时调用一次 `sudo -v` 请求系统密码，本轮每 45 秒保活，后续使用 `sudo -n`；不保存密码、不修改 `sudoers`。后台缺少授权时不询问密码，受限项明确计入未完成。

普通子命令使用输入结束，已知确认点定点自动回答；需要额外认证或未知输入时报告未完成并继续，不等待填写，不自动打开下载页面。收尾保留日志与未完成项并返回实际状态，需要再试时重新执行 `update`；`Ctrl+C` 可中止本轮，已完成更新不自动回滚。参数只保留 `-h`／`--help`，`-t`、`--trust`、`--unattended` 不再接受。

低打扰约定覆盖脚本自身交互；普通命令的输入结束与非交互环境不能保证任意第三方安装器绝不弹出独立系统授权或自行读取终端，实际要求以该安装器行为为准，不绕过权限。

## 二、依赖与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

需要同时保留相邻 `../_lib/` 的五组模块。更新包括系统及开发工具维护，直接运行即自动执行维护；帮助和参数错误不启动升级、不初始化日志。日志保留在 `$TMPDIR/update.log`；失败、缺失和权限受限按实际结果汇总，不把跳过项显示为成功。

原始维护源位于 `JobsConfigOS/🌍JobsMacEnvVarConfigs/scripts/【MacOS】update.command/【MacOS】update.command`；菜单副本与终端入口同步采用默认低打扰行为。同步时逐项核对其它业务与依赖，保留各自已有业务差异，不将两份主脚本声称为逐字节相同。测试和原源完整说明不放进运行包，不把原仓库相对路径当作随包资源。

## 三、验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

默认入口、帮助／参数错误、管理员授权及无额外输入的隔离验收状态见[资产盘点](../../../../项目相关报告/update桌面菜单资产盘点.md)；快照及引号验证见[测试说明](../../Tests/README.md)。未执行真实更新或联网下载。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
