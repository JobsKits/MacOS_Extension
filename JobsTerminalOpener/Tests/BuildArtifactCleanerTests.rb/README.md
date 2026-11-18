# BuildArtifactCleanerTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./BuildArtifactCleanerTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./BuildArtifactCleanerTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_harmony_native_multimodule_preserves_dependencies_signing_and_nested_projects`
- `test_flutter_cleans_recognized_ohos_and_native_entry_does_not_touch_flutter_parent`
- `test_harmony_module_can_be_selected_and_invalid_or_linked_ohos_is_preserved`
- `test_harmony_incomplete_markers_and_module_output_links_are_safe`
- `test_flutter_has_priority_and_cleans_only_recognized_platforms`
- `test_android_kotlin_multimodule_and_nested_project_boundary`
- `test_flutter_android_openharmony_scope_preserves_ios_desktop_and_shared_artifacts`
- `test_flutter_android_openharmony_scope_is_empty_without_recognized_platforms`
- `test_android_openharmony_scope_rejects_native_ios_and_unknown_flags_before_deleting`
- `test_android_version_catalog_project_uses_manifest_evidence`
- `test_ios_preserves_pods_locks_and_global_cache`
- `test_only_owned_xcode_derived_data_build_is_deleted`
- `test_unknown_java_gradle_and_macos_are_rejected_without_deleting`
- `test_no_ancestor_or_child_project_search`
- `test_preview_cancel_eof_and_idempotence`
- `test_link_target_rejected_before_any_deletion_and_internal_link_never_followed`
- `test_file_named_build_is_never_deleted`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
