# 随包新建 Android 模拟器

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行与影响](#usage)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

> [创建脚本](./【MacOS】CreateAndroidSimulator.zsh) 与[桌面创建内核](../../../../JobsAndroidSimulatorCreator/Scripts/【MacOS】CreateAndroidSimulator.zsh/【MacOS】CreateAndroidSimulator.zsh)保持逐字节一致，按本机架构准备 [**Android**](https://developer.android.com/) 工具和系统镜像。

## 一、<span id="usage">运行与影响</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
/bin/zsh ./CreateAndroidSimulator.zsh --create
/bin/zsh ./CreateAndroidSimulator.zsh --prepare
/bin/zsh ./CreateAndroidSimulator.zsh --check
```

- 首屏回车继续，非空输入取消；`--create` 进入机型、系统镜像和名称选择，最终确认后创建并启动；无参数入口同时提供已有 AVD 启动。保留原有名称冲突检查，不覆盖、删除或擦除现有 AVD。
- `--prepare` 只准备并复检必要工具链，不创建模拟器；`--check` / `--help` 只读。必需 SDK 获取显示真实进度，失败持续重试，可用 `Ctrl+C` 结束；许可证仍由本人阅读接受。
- 选择器优先复用 [**fzf**](https://github.com/junegunn/fzf)。日志和模拟器日志位于系统临时目录，终端显示实际位置；网络配置仅作用本次流程，不改系统代理或 Shell 配置。
- 后台模拟器进程保持运行只说明启动命令已发出，系统仍需开机。运行器重新查询设备，尚未出现时等待片刻再重新加载；取消不视为创建成功。

**终端配色保护：** 独立运行时，在支持完整保存与恢复配色的交互终端中临时使用黑底白字及统一强调色；正常结束、失败或可捕获中断后恢复进入前的配色，不修改终端全局偏好或 Shell 启动配置。不支持完整保护、无交互终端、`NO_COLOR`、既有纯文本模式和 Sourcetree 场景不切换配色，并沿用纯文本输出约定。强制终止（如 `kill -9`）无法由脚本自身保证恢复，请使用运行时显示的独立恢复入口。

最终写操作沿用一次确认：默认取消，方向键选择明确执行项后回车才创建 / 切换；← 返回上一个系统映像或版本选择，取消不执行最终写入。

键盘选择使用 ↑/↓ 或 Tab 导航、回车确认；默认停在取消行，Esc / Ctrl+C 取消。子层按 ← 返回真实上一层，仍有效的查询会保留；候选变化后清空失效查询。返回、取消和选择器失败均不启动所选业务。

健康 fzf 直接复用；仅调用方已经确认的交互流程在缺失或损坏时沿 Homebrew 依赖链准备并复检。临时网络失败持续重试，Ctrl+C 可结束；确定的本地、认证、许可或版本错误停止。选择器不向 Shell 启动文件写入配置。只读检查不修复；非终端不等待交互。供 source 的库仅注册能力，不在加载时安装或重复确认。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
