# WrapperDistributionCacheTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./WrapperDistributionCacheTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./WrapperDistributionCacheTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_unsigned_md5_base36_matches_gradle_path_assembler_vector`
- `test_standard_cache_stages_verified_zip_without_forging_ok_then_fake_wrapper_reuses_it`
- `test_project_bases_and_distinct_zip_path_match_real_android_working_directory`
- `test_unknown_or_escaping_layout_and_jvm_overrides_stop_without_creating_cache`
- `test_existing_mismatched_zip_partial_and_symlinks_are_preserved`
- `test_marker_alone_does_not_skip_verified_zip_needed_for_broken_distribution_recovery`
- `test_function_scoped_source_preserves_resolved_paths_for_its_caller`
- `test_missing_wrapper_or_changed_source_never_publishes_zip`
- `test_actual_java_file_lock_blocks_publication_and_preserves_in_flight_state`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
