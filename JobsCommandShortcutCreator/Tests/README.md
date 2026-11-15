# 脚本快捷入口测试

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、入口与目录](#entry)
- [二、覆盖与限制](#coverage)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录验证 `JobsCommandShortcutCreator` 的目录识别、文件创建、相对路径转发和输入流程。测试只运行自行生成的临时脚本，不注册扩展、不安装 App，不操作真实业务脚本，也不写入真实管理面板的语言或主题偏好。

## 一、<span id="entry">入口与目录</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 路径 | 职责 |
| --- | --- |
| [CommandShortcutBehaviorTests.rb](./CommandShortcutBehaviorTests.rb/CommandShortcutBehaviorTests.rb) | 编译真实业务源码、运行隔离夹具并对原生对话框作类型检查。 |
| [CommandShortcutBehaviorTests.swift](./CommandShortcutBehaviorTests.swift/CommandShortcutBehaviorTests.swift) | 文件系统、请求、控制器、多语言与主题的行为断言。 |

在本目录运行：

```shell
ruby ./CommandShortcutBehaviorTests.rb/CommandShortcutBehaviorTests.rb
```

依赖 [**MacOS**](https://www.apple.com/macos/)、[**Ruby**](https://www.ruby-lang.org/) 标准库，以及可通过 `xcrun swiftc` 使用的 [**Swift**](https://www.swift.org/) 编译器与系统 SDK。无须额外安装测试框架。

## 二、<span id="coverage">覆盖与限制</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 仅接收 `.command` 文件夹及其同名普通脚本，排除无效目录、链接、异名脚本与不受支持的请求。
- 同级生成真实可执行转发脚本，保留原脚本、权限和 README；同名文件、文件夹、活链接与悬空链接均不覆盖，并发创建仅一个成功。
- 中文、空格、引号、美元符号、反引号、反斜杠和多行参数按原值传递；保留业务退出码，完整目录搬移后仍能从工程外工作目录运行。
- 系统 `zsh`、`bash`、`sh` 及对应 `env` 形式的 shebang 均以无执行权限的临时源脚本验证；源文件被移除或替换成符号链接时拒绝运行。
- 取消不写入，冲突后保留输入和错误，可改名重试；十种语言逐项映射，白天、黑夜与跟随系统三主题通过隔离的 AppKit 状态验证。

编译及行为验证不代表真实 Finder 菜单、安装登记或对话框视觉布局已经验收。临时编译产物和夹具由运行器自动清理；日志直接写入标准输出和标准错误。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
