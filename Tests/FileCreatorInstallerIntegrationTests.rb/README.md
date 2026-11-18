# FileCreatorInstallerIntegrationTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./FileCreatorInstallerIntegrationTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./FileCreatorInstallerIntegrationTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_catalog_maps_one_file_creation_action_to_its_independent_unit`
- `test_scoped_install_and_uninstall_plan_contains_only_file_creation`
- `test_single_file_creation_scope_rejects_other_tools_before_work`
- `test_file_creation_and_terminal_choices_remain_separate`
- `test_install_dispatches_only_file_creator_build_and_registration`
- `test_uninstall_calls_only_the_file_creator_manager_without_restarting_finder`
- `test_registration_initializes_host_once_without_opening_a_creation_dialog`
- `test_invisible_first_registration_is_added_again_after_host_initialization`
- `test_failed_second_registration_stops_without_an_enabled_result`
- `test_cancel_and_empty_panel_output_never_form_an_install_plan`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
