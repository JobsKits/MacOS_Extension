# Git 远程打开隔离验证

![Jobs出品，必属精品](https://picsum.photos/1500/400)

---

## 🔥 <span id="前言">前言</span>

> 使用临时 [**Git**](https://git-scm.com/) 仓库和真实 [**fzf**](https://formulae.brew.sh/formula/fzf) 验证远程打开流程。浏览器、Terminal 和系统打开命令均由替身拦截。

## 一、执行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 在 [**MacOS**](https://www.apple.com/macos/) 中准备系统 [**Ruby**](https://www.ruby-lang.org/)、Xcode 命令行工具和 `/opt/homebrew/bin/fzf` 或 `/usr/local/bin/fzf` 后执行；测试不安装依赖。

  ```shell
  ruby ./GitRemoteBrowserOpenerTests.rb
  ```

- 测试编译真实 Swift 源码并替换浏览器与 Terminal 派发，使用原生 Git 读取临时仓库；不拉取远端、不修改用户 Git 配置、不注册扩展或重启 Finder。
- 覆盖零／单／多个远程、branch／origin 不越过多选、原始 URL 与 `insteadOf`、多 URL 首项、include、仓库子目录、linked worktree、中文及特殊字符路径和私有载体清理。
- 真实 PTY 发送方向键、回车、Esc 和左键，覆盖第二远程、返回第一远程和取消；错误码、空输出、非法输出、缺失／损坏 fzf、不支持的地址和浏览器失败均有替身验证。Windows 原生控制台与 Finder 菜单实机操作另行验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
