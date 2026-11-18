# ProjectJavaManagerTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./ProjectJavaManagerTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./ProjectJavaManagerTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_source_has_no_execution_or_environment_changes`
- `test_check_is_read_only_and_resolves_numeric_and_full_jenv_alias`
- `test_cancel_before_final_confirmation_does_not_mutate`
- `test_existing_jdk_switch_uses_only_selected_project_and_does_not_install`
- `test_missing_jenv_and_jdk_are_installed_once_from_brew`
- `test_brew_failure_keeps_exit_code_and_original_config`
- `test_missing_jenv_reuses_healthy_jdk_without_reinstalling_it`
- `test_installed_jdk_is_rechecked_and_wrong_version_stops_before_local_write`
- `test_concurrent_change_before_write_is_preserved`
- `test_local_failure_restores_original_and_removes_lock`
- `test_local_failure_restores_absence_and_preserves_concurrent_changes`
- `test_interruption_restores_original_config`
- `test_invalid_config_and_symlink_are_rejected_without_execution`
- `test_binder_no_declaration_preserves_environment_and_jre_is_rejected`
- `test_gradle_criteria_conflict_is_not_reported_as_bound`
- `test_gradle_opts_keep_literal_special_path_and_packager_does_not_replace_declared_java`
- `test_binder_rejects_jdk_paths_that_gradle_wrappers_interpret_inconsistently`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
