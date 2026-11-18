# AndroidSetupPlatformTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./AndroidSetupPlatformTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./AndroidSetupPlatformTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_explicit_components_are_read_without_running_project`
- `test_flutter_extension_kotlin_typed_defaults`
- `test_unresolved_flutter_ndk_stops_instead_of_installing_guess`
- `test_comments_do_not_override_active_versions`
- `test_dynamic_native_versions_remain_pending_selection`
- `test_component_version_metadata_is_read_as_data`
- `test_sdk_property_merge_preserves_other_keys_and_backups`
- `test_symbolic_local_config_is_preserved`
- `test_health_checks_skip_already_installed_components`
- `test_module_source_has_no_install_or_project_write`
- `test_license_exit_zero_without_acceptance_is_still_attention`
- `test_license_acceptance_uses_official_result`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
