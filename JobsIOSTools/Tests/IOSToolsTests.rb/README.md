# IOSToolsTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./IOSToolsTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./IOSToolsTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_shell_syntax_and_source_provenance`
- `test_all_nine_read_only_routes_and_podspec_gate`
- `test_build_cleanup_reuses_canonical_script_and_checks_native_ios_only`
- `test_subset_install_is_union_and_partial_uninstall_keeps_other_actions`
- `test_bad_feature_stops_before_mutation`
- `test_existing_cache_selection_migrates_when_installing_or_removing_another_feature`
- `test_podspec_gate_matches_hidden_files_and_rejects_directories_or_uppercase`
- `test_pod_target_and_sibling_dependency_paths_without_compiling`
- `test_swift_validator_request_and_shell_transport`
- `test_real_app_delegate_deduplicates_both_system_callbacks`
- `test_sidebar_menu_dispatch_uses_the_targeted_project`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
