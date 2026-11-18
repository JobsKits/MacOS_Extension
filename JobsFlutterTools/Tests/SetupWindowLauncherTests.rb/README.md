# SetupWindowLauncherTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./SetupWindowLauncherTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./SetupWindowLauncherTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_prebuilt_window_launches_without_swift_source_or_compiler`
- `test_build_phase_runs_after_resource_copy_before_extension_registration_and_does_not_change_skip_gate`
- `test_real_build_helper_generates_executable_only_inside_fake_xcode_products`

构建入口用例从真实 `project.pbxproj` 提取 `Build Setup Window` 阶段和输入路径，在中文、空格、单引号的搬移目录及无关工作目录中执行实际阶段命令，覆盖源码同名包装、发布平铺和 `LC_ALL=C`。临时夹具只生成并验证 `arm64`／`x86_64` 可执行文件，不运行安装、扩展登记或 Finder 重启。

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
