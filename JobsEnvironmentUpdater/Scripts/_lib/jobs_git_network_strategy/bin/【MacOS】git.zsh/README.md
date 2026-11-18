# `【MacOS】git.zsh`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

Jobs Git 网络策略的唯一完整实现。HTTP(S) 网络操作先尊重显式代理及空值，再按配置短探测直连或当前系统代理；原始 Git 命令只执行一次，不改 Git 或系统代理配置。普通本地、SSH、帮助和不明确形式沿用原生透传协议。

## 一、入口与依赖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

公开 PATH 入口仍是上级 `bin/git`，它只按相对路径转交本文件；保留整个策略目录。依赖系统 zsh、系统 Git 与原有原生探测工具，不新增运行时。Git 参数、stdin、stdout、stderr 与取消退出状态不经额外包装；不为命令协议增加确认，也不对机器输出着色。

## 二、日志与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

原审计位于当前用户 `Library/Logs/JobsGitNetworkStrategy/push.log`，仍保留脱敏与链接保护。纯语法检查：

```shell
/bin/zsh -n './【MacOS】git.zsh'
```

[完整策略与配置](../../README.md)列明优先级、超时、环境作用域和恢复；迁移后须同时验证455项隔离路由与49项真实Git加本机loopback集成，不把本机夹具冒充公网或用户实际仓库验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
