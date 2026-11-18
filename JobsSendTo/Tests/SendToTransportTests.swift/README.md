# SendTo 请求与 Finder principal 运输验证

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行](#jobs-toc-heading-2)
- [二、覆盖与边界](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

验证 [**MacOS**](https://www.apple.com/macos/) [**Finder Sync**](https://developer.apple.com/documentation/findersync) 发送到菜单的请求白名单、复制菜单项 selector 派发和十语言目录。只使用临时源文件与宿主运输替身，不发送真实 AppleEvents、不启动业务宿主、不复制到外部磁盘。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在 `JobsSendTo` 根目录使用 zsh 运行。为在测试 extension 中注入 principal 的私有请求缓存，将完整生产 `FinderSync.swift` 与测试合为同一临时编译单元；生产文件不会被改写。

```shell
sendto_test_dir="$(mktemp -d "${TMPDIR%/}/JobsSendToTransportBuild.XXXXXX")"
cat ./JobsSendToFinderSync/FinderSync.swift \
  ./Tests/SendToTransportTests.swift/SendToTransportTests.swift \
  > "$sendto_test_dir/Transport.swift"
xcrun swiftc -parse-as-library "$sendto_test_dir/Transport.swift" \
  ./Shared/**/*.swift ./JobsSendTo/SendToCancellation.swift \
  -o "$sendto_test_dir/SendToTransportTests"
"$sendto_test_dir/SendToTransportTests" "$PWD"
```

需要 [**Xcode**](https://developer.apple.com/xcode/) 命令行工具、[**Swift**](https://www.swift.org/) 和本机 AppKit／FinderSync SDK。测试源文件运行结束后自动回收；临时编译目录保留用于查看构建结果。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、覆盖与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 请求支持 1～128 项，URL 不超过 64 KiB；验证特殊路径、重复路径、空选择、非本地路径、额外／重复字段、错误 UUID、畸形 Base64 和超限输入。
- 编译真实 Finder principal；菜单项复制后清除 `target` 和 `representedObject`，检查 `responds(to:)`，经 `NSApplication.sendAction` 分发 `sendToVolume:` 与 `reloadDestinations:`。
- 验证复制与重载共用的 tag 唯一且执行后消费，请求目的地、精确宿主路径和重载后的临时源快照保持一致。
- 检查十种语言的目录及全部字面量界面 key 完整，不写入用户语言／主题偏好。
- Finder principal 初始化会只读扫描当前挂载卷；测试宿主运输全部记录在内存。文件系统复制、冲突改名、取消清理及卷身份另由 [Core 测试](../README.md) 验证；实际 Finder 跨进程菜单和真实外部磁盘交互另行验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
