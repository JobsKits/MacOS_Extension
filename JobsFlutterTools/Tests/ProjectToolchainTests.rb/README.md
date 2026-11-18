# ProjectToolchainTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./ProjectToolchainTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./ProjectToolchainTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_native_node_engine_and_version_file_are_checked_without_install`
- `test_locked_package_manager_must_match_lock_type_before_install`
- `test_missing_exact_package_manager_is_installed_only_in_user_version_directory_and_verified`
- `test_install_failure_and_failed_post_install_health_stop_the_chain`
- `test_cancel_missing_tool_does_not_install_or_start_business`
- `test_ohos_discovers_selected_studio_and_activates_complete_toolchain_in_same_process`
- `test_ohos_missing_sdk_component_never_executes_package_tools`
- `test_ohos_unhealthy_tool_requires_repair_and_does_not_run_business`
- `test_failed_ohos_selection_restores_environment_before_next_root`
- `test_exact_node_archive_is_checksum_verified_reused_and_does_not_use_brew`
- `test_spm_merge_rejects_target_ancestor_link_before_copying_any_file`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
