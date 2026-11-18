# Flutter 运行器随包模拟器创建资源

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、创建入口](#creators)
- [二、验证边界](#validation)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

> [**Flutter**](https://flutter.dev/) 运行器复用桌面右键创建内核，资源随独立 App 打包并复制到本次终端请求，不依赖外部扩展或源码仓库的位置。

## 一、<span id="creators">创建入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 平台 | 随包入口 | 桌面同源实现 |
| --- | --- | --- |
| [**iOS**](https://developer.apple.com/ios/) | [创建说明](./【MacOS】CreateIOSSimulator.zsh/README.md) | [桌面创建脚本](../../../JobsIOSSimulatorCreator/Scripts/【MacOS】CreateIOSSimulator.zsh/【MacOS】CreateIOSSimulator.zsh) |
| [**Android**](https://developer.android.com/) | [创建说明](./【MacOS】CreateAndroidSimulator.zsh/README.md) | [桌面创建脚本](../../../JobsAndroidSimulatorCreator/Scripts/【MacOS】CreateAndroidSimulator.zsh/【MacOS】CreateAndroidSimulator.zsh) |
| [**HarmonyOS**](https://developer.huawei.com/consumer/cn/) | [创建说明](./【MacOS】CreateHarmonySimulator.zsh/README.md) | [桌面创建脚本](../../../JobsHarmonySimulatorCreator/Scripts/【MacOS】CreateHarmonySimulator.zsh/【MacOS】CreateHarmonySimulator.zsh) |

- [已有模拟器启动环境](./【MacOS】模拟器启动环境.zsh/README.md)在独立启动分组中准备工具、核验更新并复检，随后只启动精确已有实例；不调用三份创建入口。
- 每份脚本保留桌面入口的自述、确认、取消、工具准备和许可证要求，在当前终端完成选择与创建。
- 创建调用结束后由运行器刷新设备列表。取消不会被当成创建成功；仍在开机的设备可等待片刻再重新加载。
- `SimulatorCreators` 是工程的资源文件夹引用；启动器校验三份脚本后整目录复制，终端退出或派发失败时只清理本次请求内的副本。

## 二、<span id="validation">验证边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

资源维护时将随包脚本与对应桌面脚本逐字节比较，执行 `zsh -n`，并验证独立启动器的复制与退出清理。隔离验证不安装工具、不创建真实模拟器，不等同于真实设备和业务 App 运行验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
