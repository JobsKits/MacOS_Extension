# <span id="前言">Xcode 六组清理隔离验证</span>

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 一、<span id="run">运行</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录执行：

```shell
ruby ./XcodeCleanupTests.rb
```

依赖系统 [**Ruby**](https://www.ruby-lang.org/)、[**zsh**](https://zsh.sourceforge.io/) 和 [**MacOS**](https://www.apple.com/macos/) 自带 JXA；存在健康 [**fzf**](https://github.com/junegunn/fzf) 时额外执行真实 PTY 按键验证。缺少 fzf 会明确跳过该项，其余隔离用例照常运行。

## 二、<span id="coverage">验证范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 两份脚本内联块一致，六组路径边界、fzf 默认 ALL 与用户环境隔离、真实 Space 无勾选确认当前项／全选／跳过、既有单选／多选不增选当前光标、取消最后一个勾选及 Esc 取消、分组跳过、父链链接、清单后与暂存后并发修改、归档恢复失败保留、精确模拟器 UUID 停机删除、孤儿登记过滤与实体恢复保留，以及跨平台设备 JSON 路径校验。
- 保留右键 `main`、终端 `main` 与 source 模式 `jobs_clean_main` 的真实阶段编排。Xcode 普通失败后常规确认、初始化和清理继续且各执行一次；最终仍返回失败，成功常规步骤不清屏抹掉前置错误。复用 source 入口时上一轮失败不污染下一轮。
- 两入口完整自述逐字一致，直接展示自述不创建业务日志。真实 PTY 运行入口后，完整功能、影响与安全说明先于常规执行；原终端与右键统一回车确认，任意非空输入取消，取消不初始化或清理。测试仅把确认后的动作替换为记录，不用假自述代替生产展示；终端 list 来源另验证 ← 返回、Esc／非空／EOF 取消和回车继续。
- 真实 Xcode 阶段及 `builtin read` 覆盖：最终直接回车执行；`skip`、`YES` 或空格加回车均跳过 Xcode 并进入常规阶段；最终 EOF 停止整个运行。另覆盖初始跳过不扫描、运行中 Xcode 的保护失败后继续常规、取消码 `129/130/143` 传播、常规确认或初始化失败即停止，以及常规失败和取消不被 Xcode 结果掩盖。

## 三、<span id="boundaries">隔离边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

测试在私有临时 HOME 中建立夹具。阶段编排用例替换进程查询、扫描候选及所有实际清理步骤，只记录调用顺序；路径与清单用例只处理本轮临时文件。不运行真实 simctl、Homebrew、安装、注册、用户缓存清理或 Finder 菜单。阶段确认用例用真实输入读取配合隔离终端能力替身；fzf 的真实 PTY 按键单独验证。通过不代表用户真实缓存、已安装菜单或完整 Finder→Terminal 流程已验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
